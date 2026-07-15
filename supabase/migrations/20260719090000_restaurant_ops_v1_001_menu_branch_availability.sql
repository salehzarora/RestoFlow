-- ============================================================================
-- RESTAURANT-OPERATIONS-V1-001 — branch-scoped menu item availability
-- ============================================================================
-- A manager must be able to mark a menu item Sold out / Paused in ONE branch
-- without deleting it, deactivating it everywhere, or touching historical
-- orders. `menu_items.is_active` is whole-scope (a restaurant-global row turned
-- off disappears from EVERY branch), so this adds the smallest per-branch
-- override:
--
--   * `menu_item_branch_availability` — at most ONE override row per
--     (branch, item). Row ABSENT or availability='available' ⇒ sellable.
--     availability='unavailable' carries a REQUIRED structured reason
--     ('sold_out' | 'paused') — never a free-form string (the operator note is
--     the audit `reason` column, not state).
--   * `app.menu_set_item_availability` — manager+ (menu_guard, GUC-free JWT
--     path like every other menu mutation), audited
--     `menu.menu_item.availability_changed` / `.availability_denied`.
--   * `app.pos_menu` — items now carry `availability` + `availability_reason`
--     for the SESSION branch. Unavailable items stay IN the payload (the POS
--     shows them greyed with the reason instead of silently hiding them).
--   * `app.list_menu` — when `p_branch_id` is passed, items carry the same two
--     keys for that branch (management view of the override).
--
-- The override is NOT part of the D-008 order snapshot model: submitted orders
-- are untouched by availability flips. Enforcement of "cannot SELL an
-- unavailable item" lands in app.submit_order in the NEXT migration of this
-- phase (20260719100000), which owns the submit-time validation rules.
--
-- Activity Log classification (audit_action_has_detail / audit_safe_detail)
-- for the new action is centralized in 20260719110000 together with the
-- table-move action — ONE stacked re-create instead of two.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Table. Branch REQUIRED (this is a per-branch override, never global);
--    composite same-org FKs to branches AND menu_items (D-012 layer 4, D-001).
--    No deleted_at: this is operational state, not a synced entity (it is not
--    in the sync_pull allowlist; POS reads it through pos_menu). Re-enabling
--    keeps the row as availability='available' so updated_at/audit history
--    stays inspectable.
-- ---------------------------------------------------------------------------
create table menu_item_branch_availability (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id),
  restaurant_id   uuid not null,
  branch_id       uuid not null,
  menu_item_id    uuid not null,
  availability    text not null default 'available'
                    check (availability in ('available', 'unavailable')),
  -- structured reason: REQUIRED exactly when unavailable ('sold_out'|'paused'),
  -- NULL exactly when available. Never free-form.
  reason          text
                    check (reason in ('sold_out', 'paused')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint menu_item_branch_availability_reason_shape check (
    (availability = 'unavailable' and reason is not null)
    or (availability = 'available' and reason is null)
  ),
  unique (organization_id, id),
  -- one override row per (branch, item)
  unique (organization_id, branch_id, menu_item_id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id),
  foreign key (organization_id, menu_item_id)
    references menu_items (organization_id, id)
);

comment on table menu_item_branch_availability is
  'RESTAURANT-OPERATIONS-V1-001: per-branch menu item availability override. Row absent OR availability=available => sellable in that branch. unavailable carries a REQUIRED structured reason (sold_out|paused; never free-form). Distinct from menu_items.is_active (whole-scope config switch) and deleted_at (tombstone): availability is a day-to-day OPERATIONAL state a manager flips without touching the item definition. Historical orders are never affected (D-008 snapshots). Writes only via app.menu_set_item_availability (manager+, D-011); direct DML is RLS-denied + unGRANTed. Not a synced entity (no tombstone; not in sync_pull) — the POS receives it through app.pos_menu.';

create index menu_item_branch_availability_item_idx
  on menu_item_branch_availability (organization_id, branch_id, menu_item_id);

create trigger menu_item_branch_availability_set_updated_at
  before update on menu_item_branch_availability
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. RLS (menu-table mirror, RF-109 shape): SELECT for the five non-kitchen
--    roles; INSERT/UPDATE/DELETE denied-by-policy AND revoked — all writes go
--    through the SECURITY DEFINER RPC (D-011/D-012).
-- ---------------------------------------------------------------------------
alter table menu_item_branch_availability enable row level security;
alter table menu_item_branch_availability force  row level security;
create policy menu_item_branch_availability_sel
  on menu_item_branch_availability for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy menu_item_branch_availability_ins_deny
  on menu_item_branch_availability for insert to authenticated with check (false);
create policy menu_item_branch_availability_upd_deny
  on menu_item_branch_availability for update to authenticated using (false) with check (false);
create policy menu_item_branch_availability_del_deny
  on menu_item_branch_availability for delete to authenticated using (false);

grant select, insert, update, delete on menu_item_branch_availability to authenticated;
revoke insert, update, delete on menu_item_branch_availability from authenticated;

-- ---------------------------------------------------------------------------
-- 3. app.menu_set_item_availability — the ONLY write path.
--    Dashboard JWT path: menu_guard (42501 for non-member/cross-scope; FALSE =
--    covering member below manager -> committed denial audit + permission_denied,
--    exactly like every menu_upsert_*). The target item must be live and
--    VISIBLE in the target branch (item.branch_id null or = branch) — an item
--    pinned to a sibling branch is `not_found`, not a cross-branch write.
-- ---------------------------------------------------------------------------
create function app.menu_set_item_availability(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_menu_item_id    uuid,
  p_availability    text,
  p_reason          text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_item_rest   uuid;
  v_item_branch uuid;
  v_item_name   text;
  v_reason      text;
  v_old_avail   text;
  v_old_reason  text;
  v_row_id      uuid;
begin
  if not app.menu_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'menu.menu_item.availability_denied', null,
      jsonb_build_object('entity', 'menu_item', 'id', p_menu_item_id,
                         'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'entity', 'menu_item_availability');
  end if;

  -- structural validation (shape errors raise: the dashboard UI can never
  -- produce them, so they are not part of the typed product contract).
  if p_branch_id is null then
    raise exception 'menu_set_item_availability: branch_id is required (the override is per-branch)'
      using errcode = '42501';
  end if;
  if p_availability is null or p_availability not in ('available', 'unavailable') then
    raise exception 'menu_set_item_availability: availability must be available|unavailable'
      using errcode = '42501';
  end if;
  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if p_availability = 'unavailable' then
    if v_reason is null or v_reason not in ('sold_out', 'paused') then
      raise exception 'menu_set_item_availability: unavailable requires a structured reason (sold_out|paused)'
        using errcode = '42501';
    end if;
  else
    v_reason := null; -- available never carries a reason
  end if;
  -- the branch must belong to the passed restaurant (IDOR fail-closed; the
  -- guard already proved authority over the passed scope).
  if not exists (
       select 1 from public.branches b
       where b.id = p_branch_id
         and b.organization_id = p_organization_id
         and b.restaurant_id   = p_restaurant_id) then
    raise exception 'menu_set_item_availability: branch not found in the target restaurant'
      using errcode = '42501';
  end if;

  -- the item must be live and visible in the target branch. A tombstoned item,
  -- a foreign-restaurant item, or an item pinned to a DIFFERENT branch is the
  -- same typed refusal — the caller learns nothing about siblings (R-003).
  --
  -- REVIEW CORRECTION (A2): FOR UPDATE — this is the availability
  -- serialization point, shared with app.submit_order (which locks the same
  -- canonical menu_items rows before validating sellability). Locking the
  -- OVERRIDE row would not serialize anything: it may not exist yet. Under
  -- this lock the old-state read below is the TRUE serialized BEFORE state,
  -- so concurrent setters can never record stale audit before/after values —
  -- and a submit that locked first commits its accepted order before this
  -- setter's change applies to later orders.
  select i.restaurant_id, i.branch_id, i.name
    into v_item_rest, v_item_branch, v_item_name
    from public.menu_items i
    where i.id = p_menu_item_id
      and i.organization_id = p_organization_id
      and i.deleted_at is null
    for update;
  if not found
     or v_item_rest <> p_restaurant_id
     or (v_item_branch is not null and v_item_branch <> p_branch_id) then
    return jsonb_build_object('ok', false, 'error', 'not_found',
                              'entity', 'menu_item_availability');
  end if;

  -- current effective override (absence = available).
  select a.id, a.availability, a.reason
    into v_row_id, v_old_avail, v_old_reason
    from public.menu_item_branch_availability a
    where a.organization_id = p_organization_id
      and a.branch_id       = p_branch_id
      and a.menu_item_id    = p_menu_item_id;
  if not found then
    v_old_avail  := 'available';
    v_old_reason := null;
  end if;

  -- no-change writes succeed without a row/audit (idempotent from the UI).
  if v_old_avail = p_availability and v_old_reason is not distinct from v_reason then
    return jsonb_build_object('ok', true, 'entity', 'menu_item_availability',
                              'menu_item_id', p_menu_item_id,
                              'availability', p_availability,
                              'reason', v_reason,
                              'no_change', true);
  end if;

  insert into public.menu_item_branch_availability
    (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, p_menu_item_id, p_availability, v_reason)
  on conflict (organization_id, branch_id, menu_item_id)
  do update set availability = excluded.availability, reason = excluded.reason;

  -- WHAT/WHO/WHEN/SCOPE/BEFORE/AFTER/REASON. STABILIZATION: the reason COLUMN
  -- stays NULL — it is free-text for operators and the Activity Log renders it
  -- verbatim; the STRUCTURED token lives in old/new values, where the client
  -- localizes it (sold_out -> "Sold out" in ar/he/en, never a raw token).
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id,
     action, reason, old_values, new_values)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, app.current_app_user_id(), null,
     'menu.menu_item.availability_changed', null,
     jsonb_build_object('availability', v_old_avail, 'availability_reason', v_old_reason),
     jsonb_build_object('availability', p_availability, 'availability_reason', v_reason,
                        'item_name', v_item_name, 'menu_item_id', p_menu_item_id));

  return jsonb_build_object('ok', true, 'entity', 'menu_item_availability',
                            'menu_item_id', p_menu_item_id,
                            'availability', p_availability,
                            'reason', v_reason);
end;
$$;

comment on function app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) is
  'RESTAURANT-OPERATIONS-V1-001: sets the per-branch availability override for a live menu item (manager+ via app.menu_guard, GUC-free JWT path). availability=available clears the reason; unavailable REQUIRES reason sold_out|paused. Target item must be live and visible in the target branch (branch-pinned siblings are not_found — no cross-branch leak, R-003). No-change calls return ok+no_change without an audit row. Success audits menu.menu_item.availability_changed with before/after {availability, reason} + item_name and the structured reason in the reason column; role denial audits menu.menu_item.availability_denied and returns permission_denied. Historical orders unaffected (D-008).';

-- ---------------------------------------------------------------------------
-- 4. app.pos_menu — CREATE OR REPLACE (same signature, keeps ACLs). FAITHFUL
--    re-creation of the KITCHEN-MEAT-001 body (20260709090000) with the ONLY
--    change in section (e): items LEFT JOIN their session-branch availability
--    override and carry `availability` ('available'|'unavailable') +
--    `availability_reason` ('sold_out'|'paused'|null). Unavailable items are
--    NOT filtered out — the POS must show them as not sellable WITH the reason.
--    T-003/T-014 kitchen redaction unchanged.
-- ---------------------------------------------------------------------------
create or replace function app.pos_menu(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_redact     boolean;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
  v_sizes      jsonb;
  v_variants   jsonb;
  v_modifiers  jsonb;
  v_options    jsonb;
begin
  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'pos_menu: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'pos_menu: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_menu: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'pos_menu: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_menu: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) T-003 money redaction: a kitchen principal never receives a money figure.
  --     base_price_minor (items) AND price_delta_minor (sizes/variants/options)
  --     KEYS are omitted (not nulled) below. The SAME kitchen principal also
  --     never receives image_path (T-014). Menu/media sprint: item_type/tags/
  --     prep_minutes/kitchen_note/attributes are NON-MONEY and pass through to
  --     kitchen too — that is exactly the prep info a KDS needs.
  v_redact := (v_role = 'kitchen_staff');

  -- (c) the REAL tenant currency: restaurants.currency_override, else the
  --     organization default (matches app.list_menu).
  select coalesce(r.currency_override, o.default_currency)
    into v_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = v_rest and r.organization_id = v_org;

  -- (d) live categories of the session restaurant, branch-visible
  --     (branch_id null = restaurant-scoped, or the session branch). Tombstoned
  --     (deleted_at) and inactive rows are excluded — this is the LIVE sell menu,
  --     not the sync feed (tombstone propagation stays with sync_pull, D-020).
  select coalesce(jsonb_agg(
           jsonb_build_object('id', c.id, 'name', c.name, 'display_order', c.display_order)
           order by c.display_order, c.name), '[]'::jsonb)
    into v_categories
    from public.menu_categories c
    where c.organization_id = v_org
      and c.restaurant_id = v_rest
      and c.is_active
      and c.deleted_at is null
      and (c.branch_id is null or c.branch_id = v_branch);

  -- (e) live items: item live + branch-visible AND parent category live +
  --     branch-visible. base_price_minor is integer minor (bigint; D-007) and is
  --     OMITTED entirely for kitchen_staff (T-003); image_path is likewise
  --     OMITTED for kitchen_staff (T-014). item_type/tags/prep_minutes/
  --     kitchen_note/attributes are non-money and serve BOTH branches; sku is
  --     an internal back-office code and is NEVER served to devices.
  --     RESTAURANT-OPERATIONS-V1-001: every item additionally carries its
  --     SESSION-BRANCH availability ('available' when no override row exists)
  --     + availability_reason — unavailable items stay in the payload so the
  --     POS can show WHY they cannot be sold (they are excluded from SALE by
  --     app.submit_order, not from sight).
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'item_type', i.item_type, 'tags', i.tags,
               'prep_minutes', i.prep_minutes, 'kitchen_note', i.kitchen_note,
               'attributes', i.attributes,
               'availability', coalesce(a.availability, 'available'),
               'availability_reason', a.reason)
           else
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'item_type', i.item_type, 'tags', i.tags,
               'prep_minutes', i.prep_minutes, 'kitchen_note', i.kitchen_note,
               'attributes', i.attributes,
               'base_price_minor', i.base_price_minor,
               'image_path', i.image_path,
               'availability', coalesce(a.availability, 'available'),
               'availability_reason', a.reason)
           end
           order by i.display_order, i.name), '[]'::jsonb)
    into v_items
    from public.menu_items i
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
    left join public.menu_item_branch_availability a
      on a.organization_id = i.organization_id
     and a.branch_id       = v_branch
     and a.menu_item_id    = i.id
    where i.organization_id = v_org
      and i.restaurant_id = v_rest
      and i.is_active
      and i.deleted_at is null
      and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active
      and c.deleted_at is null
      and (c.branch_id is null or c.branch_id = v_branch);

  -- (f) live sizes of LIVE items (parent chain: size live + branch-visible,
  --     item live + branch-visible, item's category live + branch-visible).
  --     price_delta_minor is SIGNED integer minor (D-007); OMITTED for kitchen.
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', s.id, 'menu_item_id', s.menu_item_id, 'name', s.name,
               'display_order', s.display_order)
           else
             jsonb_build_object(
               'id', s.id, 'menu_item_id', s.menu_item_id, 'name', s.name,
               'display_order', s.display_order,
               'price_delta_minor', s.price_delta_minor)
           end
           order by s.display_order, s.name), '[]'::jsonb)
    into v_sizes
    from public.item_sizes s
    join public.menu_items i
      on i.organization_id = s.organization_id and i.id = s.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
    where s.organization_id = v_org
      and s.restaurant_id = v_rest
      and s.is_active
      and s.deleted_at is null
      and (s.branch_id is null or s.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  -- (g) live variants of LIVE items — same filters/shape as sizes.
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', v.id, 'menu_item_id', v.menu_item_id, 'name', v.name,
               'display_order', v.display_order)
           else
             jsonb_build_object(
               'id', v.id, 'menu_item_id', v.menu_item_id, 'name', v.name,
               'display_order', v.display_order,
               'price_delta_minor', v.price_delta_minor)
           end
           order by v.display_order, v.name), '[]'::jsonb)
    into v_variants
    from public.item_variants v
    join public.menu_items i
      on i.organization_id = v.organization_id and i.id = v.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
    where v.organization_id = v_org
      and v.restaurant_id = v_rest
      and v.is_active
      and v.deleted_at is null
      and (v.branch_id is null or v.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  -- (h) live modifiers of LIVE items (money-free rows — selection rules only).
  --     MVP quantity settings: allow_quantity + max_quantity are COUNTS (never
  --     money, D-007) and serve EVERY role incl. kitchen — consistent with
  --     selection_type/min_select/max_select already served here.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', m.id, 'menu_item_id', m.menu_item_id, 'name', m.name,
             'selection_type', m.selection_type, 'min_select', m.min_select,
             'max_select', m.max_select, 'is_required', m.is_required,
             'allow_quantity', m.allow_quantity, 'max_quantity', m.max_quantity,
             'display_order', m.display_order)
           order by m.display_order, m.name), '[]'::jsonb)
    into v_modifiers
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
    where m.organization_id = v_org
      and m.restaurant_id = v_rest
      and m.is_active
      and m.deleted_at is null
      and (m.branch_id is null or m.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  -- (i) live options of LIVE modifiers (full parent chain: option live +
  --     branch-visible, modifier live + branch-visible, modifier's item live +
  --     branch-visible, item's category live + branch-visible). price_delta_minor
  --     OMITTED for kitchen (T-003).
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', mo.id, 'modifier_id', mo.modifier_id, 'name', mo.name,
               'display_order', mo.display_order, 'kitchen_meat', mo.kitchen_meat)
           else
             jsonb_build_object(
               'id', mo.id, 'modifier_id', mo.modifier_id, 'name', mo.name,
               'display_order', mo.display_order,
               'price_delta_minor', mo.price_delta_minor, 'kitchen_meat', mo.kitchen_meat)
           end
           order by mo.display_order, mo.name), '[]'::jsonb)
    into v_options
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
    where mo.organization_id = v_org
      and mo.restaurant_id = v_rest
      and mo.is_active
      and mo.deleted_at is null
      and (mo.branch_id is null or mo.branch_id = v_branch)
      and m.is_active and m.deleted_at is null and (m.branch_id is null or m.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  return jsonb_build_object(
    'ok', true,
    'entity', 'menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'sizes', v_sizes,
    'variants', v_variants,
    'modifiers', v_modifiers,
    'modifier_options', v_options,
    'server_ts', now());
end;
$$;

comment on function app.pos_menu(uuid, uuid) is
  'MVP POS menu read RPC (D-011). RESTAURANT-OPERATIONS-V1-001: item rows additionally carry availability (available|unavailable, coalesced available when no per-branch override row exists) + availability_reason (sold_out|paused|null) for the SESSION branch — unavailable items stay in the payload (the POS greys them out with the reason; the sale itself is refused by app.submit_order). KITCHEN-MEAT-001 kitchen_meat, T-003 money-key omission + T-014 image_path omission for kitchen_staff, and money integer minor bigint (D-007) are all UNCHANGED.';

-- ---------------------------------------------------------------------------
-- 5. app.list_menu — CREATE OR REPLACE (same signature, keeps ACLs). FAITHFUL
--    re-creation of the NEWEST (KITCHEN-MEAT-001, 20260709090000) body — incl.
--    image_path, the six rich attribute keys, allow_quantity/max_quantity and
--    kitchen_meat — with ONE change: when p_branch_id IS passed, item rows
--    carry `availability` + `availability_reason` for that branch (management
--    view of the override).
-- ---------------------------------------------------------------------------
create or replace function app.list_menu(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
  v_sizes      jsonb;
  v_variants   jsonb;
  v_modifiers  jsonb;
  v_options    jsonb;
begin
  if v_actor is null then
    raise exception 'list_menu: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_menu: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_menu: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    -- kitchen_staff/cashier/accountant are excluded from the management view
    -- (consistent with T-003: menu rows carry money and this surface is manager+
    -- only, so no per-row redaction is needed below).
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'menu');
  end if;

  -- structural validation: the restaurant must belong to the org, and the
  -- branch (when passed) must belong to that restaurant (IDOR fail-closed).
  if not exists (select 1 from public.restaurants r
                 where r.id = p_restaurant_id and r.organization_id = p_organization_id) then
    raise exception 'list_menu: restaurant not found in the target organization' using errcode = '42501';
  end if;
  if p_branch_id is not null and not exists (
       select 1 from public.branches b
       where b.id = p_branch_id
         and b.organization_id = p_organization_id
         and b.restaurant_id   = p_restaurant_id) then
    raise exception 'list_menu: branch not found in the target restaurant' using errcode = '42501';
  end if;

  -- the REAL tenant currency: restaurants.currency_override, else the
  -- organization default (so menu writes stop defaulting to USD client-side).
  select coalesce(r.currency_override, o.default_currency)
    into v_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = p_restaurant_id and r.organization_id = p_organization_id;

  -- Every returned row carries organization_id / restaurant_id / branch_id
  -- (the Dart fromJson factories require the tenant keys on every row; D-001).

  -- categories: tombstone-excluded, INACTIVE INCLUDED (management view);
  -- branch-visible (restaurant-wide branch-null rows + the requested branch).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'organization_id', c.organization_id, 'restaurant_id', c.restaurant_id,
           'branch_id', c.branch_id, 'name', c.name, 'display_order', c.display_order,
           'is_active', c.is_active)
           order by c.display_order, c.name), '[]'::jsonb)
    into v_categories
    from public.menu_categories c
    where c.organization_id = p_organization_id
      and c.restaurant_id   = p_restaurant_id
      and c.deleted_at is null
      and (p_branch_id is null or c.branch_id is null or c.branch_id = p_branch_id);

  -- items: same filters; base_price_minor is integer minor bigint (D-007);
  -- NO redaction (manager+ only surface). MVP: + image_path + the six rich
  -- attribute keys (each nullable — the keys are always present so the Dart
  -- parser reads them uniformly).
  -- RESTAURANT-OPERATIONS-V1-001: when a branch is requested, each item
  -- additionally carries its availability override for THAT branch (absent
  -- row = available). With no branch there is no single truthful answer, so
  -- the keys are simply ABSENT (wire-compatible).
  if p_branch_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', i.id, 'organization_id', i.organization_id, 'restaurant_id', i.restaurant_id,
             'branch_id', i.branch_id, 'menu_category_id', i.menu_category_id, 'name', i.name,
             'description', i.description, 'base_price_minor', i.base_price_minor,
             'currency_code', i.currency_code, 'default_station_id', i.default_station_id,
             'display_order', i.display_order, 'is_active', i.is_active,
             'image_path', i.image_path,
             'item_type', i.item_type, 'tags', i.tags, 'prep_minutes', i.prep_minutes,
             'sku', i.sku, 'kitchen_note', i.kitchen_note, 'attributes', i.attributes,
             'availability', coalesce(a.availability, 'available'),
             'availability_reason', a.reason)
             order by i.display_order, i.name), '[]'::jsonb)
      into v_items
      from public.menu_items i
      left join public.menu_item_branch_availability a
        on a.organization_id = i.organization_id
       and a.branch_id       = p_branch_id
       and a.menu_item_id    = i.id
      where i.organization_id = p_organization_id
        and i.restaurant_id   = p_restaurant_id
        and i.deleted_at is null
        and (i.branch_id is null or i.branch_id = p_branch_id);
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', i.id, 'organization_id', i.organization_id, 'restaurant_id', i.restaurant_id,
             'branch_id', i.branch_id, 'menu_category_id', i.menu_category_id, 'name', i.name,
             'description', i.description, 'base_price_minor', i.base_price_minor,
             'currency_code', i.currency_code, 'default_station_id', i.default_station_id,
             'display_order', i.display_order, 'is_active', i.is_active,
             'image_path', i.image_path,
             'item_type', i.item_type, 'tags', i.tags, 'prep_minutes', i.prep_minutes,
             'sku', i.sku, 'kitchen_note', i.kitchen_note, 'attributes', i.attributes)
             order by i.display_order, i.name), '[]'::jsonb)
      into v_items
      from public.menu_items i
      where i.organization_id = p_organization_id
        and i.restaurant_id   = p_restaurant_id
        and i.deleted_at is null;
  end if;

  -- sizes: children of the RETURNED item set (join, tombstone-filtered at
  -- each level, child branch-visible too).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'organization_id', s.organization_id, 'restaurant_id', s.restaurant_id,
           'branch_id', s.branch_id, 'menu_item_id', s.menu_item_id, 'name', s.name,
           'price_delta_minor', s.price_delta_minor,
           'display_order', s.display_order, 'is_active', s.is_active)
           order by s.display_order, s.name), '[]'::jsonb)
    into v_sizes
    from public.item_sizes s
    join public.menu_items i
      on i.organization_id = s.organization_id and i.id = s.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and s.deleted_at is null
      and (p_branch_id is null or s.branch_id is null or s.branch_id = p_branch_id);

  -- variants: same shape/filters as sizes.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'organization_id', v.organization_id, 'restaurant_id', v.restaurant_id,
           'branch_id', v.branch_id, 'menu_item_id', v.menu_item_id, 'name', v.name,
           'price_delta_minor', v.price_delta_minor,
           'display_order', v.display_order, 'is_active', v.is_active)
           order by v.display_order, v.name), '[]'::jsonb)
    into v_variants
    from public.item_variants v
    join public.menu_items i
      on i.organization_id = v.organization_id and i.id = v.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where v.organization_id = p_organization_id
      and v.restaurant_id   = p_restaurant_id
      and v.deleted_at is null
      and (p_branch_id is null or v.branch_id is null or v.branch_id = p_branch_id);

  -- modifiers: children of the RETURNED item set. MVP: + allow_quantity /
  -- max_quantity (COUNT settings, never money — D-007).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'organization_id', m.organization_id, 'restaurant_id', m.restaurant_id,
           'branch_id', m.branch_id, 'menu_item_id', m.menu_item_id, 'name', m.name,
           'selection_type', m.selection_type, 'min_select', m.min_select,
           'max_select', m.max_select, 'is_required', m.is_required,
           'allow_quantity', m.allow_quantity, 'max_quantity', m.max_quantity,
           'display_order', m.display_order, 'is_active', m.is_active)
           order by m.display_order, m.name), '[]'::jsonb)
    into v_modifiers
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where m.organization_id = p_organization_id
      and m.restaurant_id   = p_restaurant_id
      and m.deleted_at is null
      and (p_branch_id is null or m.branch_id is null or m.branch_id = p_branch_id);

  -- modifier options: children of the RETURNED modifier set (which itself
  -- requires the parent item in the set) — tombstone-filtered at each level.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', mo.id, 'organization_id', mo.organization_id, 'restaurant_id', mo.restaurant_id,
           'branch_id', mo.branch_id, 'modifier_id', mo.modifier_id, 'name', mo.name,
           'price_delta_minor', mo.price_delta_minor,
           'display_order', mo.display_order, 'is_active', mo.is_active, 'kitchen_meat', mo.kitchen_meat)
           order by mo.display_order, mo.name), '[]'::jsonb)
    into v_options
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
     and m.restaurant_id = p_restaurant_id
     and m.deleted_at is null
     and (p_branch_id is null or m.branch_id is null or m.branch_id = p_branch_id)
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where mo.organization_id = p_organization_id
      and mo.restaurant_id   = p_restaurant_id
      and mo.deleted_at is null
      and (p_branch_id is null or mo.branch_id is null or mo.branch_id = p_branch_id);

  return jsonb_build_object(
    'ok', true,
    'entity', 'menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'sizes', v_sizes,
    'variants', v_variants,
    'modifiers', v_modifiers,
    'modifier_options', v_options,
    'server_ts', now());
end;
$$;

comment on function app.list_menu(uuid, uuid, uuid) is
  'RF-109/D-033 GUC-free menu MANAGEMENT read (manager+) + KITCHEN-MEAT-001 kitchen_meat. RESTAURANT-OPERATIONS-V1-001: when p_branch_id is passed, item rows additionally carry availability (available|unavailable) + availability_reason (sold_out|paused|null) for THAT branch — with no branch requested the keys are absent (no single truthful restaurant-wide answer). Everything else is the NEWEST body verbatim: image_path + six rich attribute keys on items, allow_quantity/max_quantity on modifiers, kitchen_meat on options, tenant keys on every row (D-001), money integer minor bigint (D-007). Read-only; scope-safe (R-003).';

-- ---------------------------------------------------------------------------
-- 6. Thin public SECURITY INVOKER wrapper + grants (authenticated only; the
--    hosted-Supabase default-privilege anon grant is explicitly revoked).
-- ---------------------------------------------------------------------------
create function public.menu_set_item_availability(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_menu_item_id    uuid,
  p_availability    text,
  p_reason          text default null
)
  returns jsonb language sql volatile security invoker set search_path = ''
as $$
  select app.menu_set_item_availability(
    p_organization_id, p_restaurant_id, p_branch_id,
    p_menu_item_id, p_availability, p_reason);
$$;

revoke all on function app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) from public;
revoke all on function app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) from anon;
grant execute on function app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) to authenticated;
revoke all on function public.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) from public;
revoke all on function public.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) from anon;
grant execute on function public.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text) to authenticated;

-- pos_menu / list_menu were CREATE OR REPLACE (same signature) — ACLs kept; the
-- grants below re-assert the intended posture defensively.
revoke all on function app.pos_menu(uuid, uuid) from public;
grant execute on function app.pos_menu(uuid, uuid) to authenticated;
revoke all on function app.list_menu(uuid, uuid, uuid) from public;
grant execute on function app.list_menu(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text);
--   drop function if exists app.menu_set_item_availability(uuid, uuid, uuid, uuid, text, text);
--   restore app.pos_menu + app.list_menu from 20260709090000 / 20260703100000;
--   drop table if exists menu_item_branch_availability;
-- ============================================================================
