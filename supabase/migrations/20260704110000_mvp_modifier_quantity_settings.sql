-- ============================================================================
-- MVP (menu/media sprint) — modifier per-option QUANTITY settings on the
-- modifier GROUP (public.modifiers). DECISIONS D-007/D-011/D-031;
-- SECURITY T-003; RISK R-003; defence in depth D-012 (layer 4 table CHECKs).
-- ============================================================================
-- WHAT THIS DOES (all ADDITIVE and non-destructive; forward-only; no data
-- rewrites — every existing row keeps working under the new defaults):
--   1. public.modifiers gains two columns:
--        * allow_quantity boolean NOT NULL DEFAULT false — lets the POS show a
--          per-OPTION quantity stepper on a 'multiple' group (e.g. "Extra
--          Cheese x3"). QUANTITY IS A COUNT, NOT MONEY (D-007 untouched —
--          option prices stay integer minor on modifier_options).
--        * max_quantity integer NULL — caps the units of ONE option (null = no
--          cap). CHECK (null or > 0).
--      Table CHECK guard (D-012 layer 4): NOT (selection_type = 'single' AND
--      allow_quantity) — a single-select group (e.g. doneness) can NEVER take
--      per-option quantities. Existing rows all default allow_quantity=false,
--      so adding the constraint is safe.
--      SEMANTICS: min_select / max_select keep counting DISTINCT options
--      (unchanged); max_quantity caps the UNITS of one chosen option. Selection
--      rules remain STORED-NOT-ENFORCED at submit time — consistent with
--      min_select/max_select since RF-109: app.submit_order validates money
--      from SUBMITTED SNAPSHOTS only (D-008) and already multiplies
--      modifiers[].quantity into line totals with anti-tamper rejection.
--      submit_order and sync_pull are NOT touched here.
--   2. app.menu_upsert_modifier + the public wrapper gain two appended params
--      (p_allow_quantity boolean default false, p_max_quantity integer default
--      null). Both CURRENT 12-arg functions are DROPPED and recreated at
--      14 args — NEVER create-or-replace with an added defaulted parameter
--      (that creates a SECOND Postgres overload and PostgREST rpc calls become
--      ambiguous). Exact-signature revoke/grant lines are re-issued.
--      FULL-STATE semantics (the house pattern pinned for menu_upsert_item):
--      the editor always sends the group's full state, so a legacy shorter
--      call RESETS allow_quantity/max_quantity to false/null. The function
--      re-validates (max_quantity null or > 0; allow_quantity=true on a
--      'single' group raises 42501 — the RF-109 validation style) with the
--      table CHECKs as the final safety boundary.
--   3. app.pos_menu modifiers[] rows gain allow_quantity + max_quantity for
--      EVERY role (same-signature CREATE OR REPLACE; ACLs preserved). These
--      are NON-MONEY selection rules — the kitchen already receives
--      selection_type/min_select/max_select, so serving the two new keys to
--      kitchen sessions is harmless and consistent. The T-003 money-key
--      omissions and the T-014 image_path omission are UNCHANGED.
--   4. app.list_menu modifiers[] rows gain the same two keys (same-signature
--      CREATE OR REPLACE; manager+ only surface, no redaction needed).
--
-- SECURITY: no RLS change; grants re-issued verbatim for the new signatures
-- (authenticated only — never anon/public/service_role). Money stays integer
-- minor everywhere (D-007); no money column is touched.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. public.modifiers — the two quantity-settings columns (additive; existing
--    rows all get allow_quantity=false / max_quantity=null, so both CHECKs are
--    trivially satisfied on add).
-- ---------------------------------------------------------------------------
alter table public.modifiers
  add column allow_quantity boolean not null default false,
  add column max_quantity integer
    constraint modifiers_max_quantity_positive
      check (max_quantity is null or max_quantity > 0),
  add constraint modifiers_single_never_quantity
    check (not (selection_type = 'single' and allow_quantity));

comment on column public.modifiers.allow_quantity is
  'MVP (menu/media sprint): TRUE lets the POS show a per-OPTION quantity stepper on a ''multiple'' group. A COUNT, never money (D-007). Table CHECK modifiers_single_never_quantity forbids it on selection_type=''single'' groups (a doneness picker never takes quantities; D-012 layer 4). Stored-not-enforced at submit time, consistent with min_select/max_select — app.submit_order validates from submitted snapshots (D-008) and already multiplies modifiers[].quantity into line totals.';
comment on column public.modifiers.max_quantity is
  'MVP (menu/media sprint): cap on the UNITS of ONE chosen option when allow_quantity is on (null = no cap; CHECK null or > 0). A COUNT, never money (D-007). min_select/max_select keep counting DISTINCT options; this caps repeats of a single option. Stored-not-enforced at submit time (see allow_quantity).';

-- ---------------------------------------------------------------------------
-- 2. menu_upsert_modifier gains the two params (appended, defaulted).
--    DROP the exact CURRENT 12-arg signatures first (app + public wrapper,
--    from 20260625100000) so exactly ONE function of each name remains —
--    PostgREST stays unambiguous.
-- ---------------------------------------------------------------------------
drop function if exists public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean);
drop function if exists app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean);

create function app.menu_upsert_modifier(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid     default null,
  p_id              uuid     default null,
  p_menu_item_id    uuid     default null,
  p_name            text     default null,
  p_selection_type  text     default 'single',
  p_min_select      integer  default 0,
  p_max_select      integer  default null,
  p_is_required     boolean  default false,
  p_display_order   integer  default 0,
  p_is_active       boolean  default true,
  p_allow_quantity  boolean  default false,
  p_max_quantity    integer  default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_found_org    uuid;
  v_found_rest   uuid;
  v_found_branch uuid;
  v_id           uuid;
  v_action       text;
  v_old          jsonb;
  v_new          jsonb;
begin
  if not app.menu_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'menu.modifier.upsert_denied', null, jsonb_build_object('entity', 'modifier', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'modifier');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_modifier: name is required' using errcode = '42501';
  end if;
  if coalesce(p_selection_type, 'single') not in ('single', 'multiple') then
    raise exception 'menu_upsert_modifier: selection_type must be single or multiple' using errcode = '42501';
  end if;
  if coalesce(p_min_select, 0) < 0 or (p_max_select is not null and p_max_select < 0) then
    raise exception 'menu_upsert_modifier: min_select/max_select must be non-negative' using errcode = '42501';
  end if;
  -- MVP quantity settings (same 42501 style; the table CHECKs remain the final
  -- safety boundary — D-012 layer 4).
  if p_max_quantity is not null and p_max_quantity <= 0 then
    raise exception 'menu_upsert_modifier: max_quantity must be null or a positive integer (units of one option; a count, not money)' using errcode = '42501';
  end if;
  if coalesce(p_allow_quantity, false) and coalesce(p_selection_type, 'single') = 'single' then
    raise exception 'menu_upsert_modifier: allow_quantity requires selection_type = multiple (a single-select group never takes per-option quantities)' using errcode = '42501';
  end if;
  if not exists (select 1 from public.menu_items mi
                 where mi.id = p_menu_item_id
                   and mi.organization_id = p_organization_id
                   and mi.restaurant_id = p_restaurant_id
                   -- B2: scope-compatible parent (restaurant-scoped or same branch; never sibling branch)
                   and (mi.branch_id is null or mi.branch_id = p_branch_id)) then
    raise exception 'menu_upsert_modifier: menu_item_id not found in the target organization/restaurant' using errcode = '42501';
  end if;
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.modifiers where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'menu_upsert_modifier: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'menu_upsert_modifier: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.modifiers
      (id, organization_id, restaurant_id, branch_id, menu_item_id, name,
       selection_type, min_select, max_select, is_required, display_order, is_active,
       allow_quantity, max_quantity)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_item_id, btrim(p_name),
       coalesce(p_selection_type, 'single'), coalesce(p_min_select, 0), p_max_select,
       coalesce(p_is_required, false), coalesce(p_display_order, 0), coalesce(p_is_active, true),
       coalesce(p_allow_quantity, false), p_max_quantity);
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.modifiers t where t.id = p_id;
    update public.modifiers set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_item_id = p_menu_item_id,
      name = btrim(p_name), selection_type = coalesce(p_selection_type, 'single'),
      min_select = coalesce(p_min_select, 0), max_select = p_max_select,
      is_required = coalesce(p_is_required, false),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true),
      -- FULL-STATE semantics (menu_upsert_item house pattern): a legacy shorter
      -- call resets the quantity settings to false/null.
      allow_quantity = coalesce(p_allow_quantity, false), max_quantity = p_max_quantity
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.modifiers t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.modifier.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'modifier', 'id', v_id, 'action', v_action);
end;
$$;

comment on function app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer) is
  'RF-109 modifier-group upsert + MVP quantity settings (p_allow_quantity/p_max_quantity — full-state upsert: a legacy shorter call resets them to false/null, the menu_upsert_item house pattern). DROP+recreated at 14 args so exactly ONE overload exists (PostgREST-unambiguous). Validates max_quantity null or > 0 and rejects allow_quantity on selection_type=single (42501, RF-109 style); guard/audit unchanged. Quantities are COUNTS, never money (D-007).';

create function public.menu_upsert_modifier(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_item_id uuid default null, p_name text default null,
  p_selection_type text default 'single', p_min_select integer default 0, p_max_select integer default null,
  p_is_required boolean default false, p_display_order integer default 0, p_is_active boolean default true,
  p_allow_quantity boolean default false, p_max_quantity integer default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_modifier(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_item_id, p_name, p_selection_type, p_min_select, p_max_select, p_is_required, p_display_order, p_is_active, p_allow_quantity, p_max_quantity); $$;

-- Grants for the NEW exact signatures (RF-109 posture: authenticated only;
-- never anon / public / service_role).
revoke all on function app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer) from public;
grant execute on function app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer) to authenticated;
revoke all on function public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer) from public;
grant execute on function public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 3a. app.pos_menu — modifiers[] rows gain allow_quantity + max_quantity for
--     EVERY session (non-money selection rules; the kitchen already receives
--     selection_type/min/max). Same signature => CREATE OR REPLACE keeps ACLs.
--     Body identical to 20260704100000 except the modifiers branch (h).
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
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'item_type', i.item_type, 'tags', i.tags,
               'prep_minutes', i.prep_minutes, 'kitchen_note', i.kitchen_note,
               'attributes', i.attributes)
           else
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'item_type', i.item_type, 'tags', i.tags,
               'prep_minutes', i.prep_minutes, 'kitchen_note', i.kitchen_note,
               'attributes', i.attributes,
               'base_price_minor', i.base_price_minor,
               'image_path', i.image_path)
           end
           order by i.display_order, i.name), '[]'::jsonb)
    into v_items
    from public.menu_items i
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
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
               'display_order', mo.display_order)
           else
             jsonb_build_object(
               'id', mo.id, 'modifier_id', mo.modifier_id, 'name', mo.name,
               'display_order', mo.display_order,
               'price_delta_minor', mo.price_delta_minor)
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
  'MVP POS menu read RPC (D-011, RF-109 schema) with sizes/variants/modifiers/modifier_options + image_path + rich item attributes. Menu/media sprint: modifier rows additionally carry allow_quantity + max_quantity — non-money COUNT settings (per-option quantity stepper on multiple-select groups) served to EVERY session incl. kitchen, consistent with selection_type/min/max_select. The T-003 money-key omission and the T-014 image_path omission for kitchen_staff are UNCHANGED, as is all session/device validation (A8), live filtering, branch visibility, and ordering. Money integer minor bigint (D-007); org+restaurant+branch filter is the isolation boundary (R-003).';

-- ---------------------------------------------------------------------------
-- 3b. app.list_menu — modifiers[] rows gain the same two keys (management
--     read, manager+ only; no redaction needed). Same signature => CREATE OR
--     REPLACE keeps ACLs. Body identical to 20260704100000 except the
--     modifiers aggregate.
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
      and i.deleted_at is null
      and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id);

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
           'display_order', mo.display_order, 'is_active', mo.is_active)
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
  'MVP (D-033; API_CONTRACT §4.23): GUC-free menu MANAGEMENT read for the owner/manager dashboard. Menu/media sprint: item rows carry image_path plus the six rich-attribute keys; modifier rows additionally carry allow_quantity + max_quantity (COUNT settings for the per-option quantity stepper — never money, D-007). Manager+ only (no redaction needed); every row carries the tenant keys (D-001); money integer minor bigint (D-007). Read-only; scope-safe (R-003).';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   restore the 20260704100000 app.pos_menu and app.list_menu bodies (no
--     allow_quantity/max_quantity keys on modifiers rows);
--   drop function public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer);
--   drop function app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer);
--     and restore the 12-arg pair + grants (20260625100000);
--   alter table public.modifiers
--     drop constraint modifiers_single_never_quantity,
--     drop constraint modifiers_max_quantity_positive,
--     drop column allow_quantity, drop column max_quantity;
-- ============================================================================
