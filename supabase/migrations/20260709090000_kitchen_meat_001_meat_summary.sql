-- ============================================================================
-- KITCHEN-MEAT-001 -- total meat summary for the KDS, configured on modifier
-- options (e.g. a Size group's Single/Double options, or an "extra patty" add).
--
-- Additive + FORWARD-ONLY (never edits a prior migration). Changes:
--   1. public.modifier_options gains a NULLABLE `kitchen_meat jsonb` column: the
--      owner-configured meat contribution of ONE selection of that option --
--      a JSON OBJECT {quantity, unit} (NON-money: quantity is a COUNT, unit is
--      text; a money key is CHECK-rejected). NULL = the option contributes no
--      meat. Existing options are NULL and keep working. Nothing is inferred
--      from the option NAME or PRICE -- only what the owner configured.
--   2. public.order_item_modifiers gains a NULLABLE `meat_snapshot jsonb`: the
--      ORDER-TIME (D-008) snapshot of the selected option's kitchen_meat, so the
--      KDS can compute the whole-order meat total = sum over the order's items of
--      (meat.quantity x order_item_modifier.quantity x order_item.quantity),
--      grouped by unit. NON-money; existing rows are NULL.
--   3. menu_upsert_modifier_option (app + public wrapper) gains a 10th appended
--      p_kitchen_meat jsonb param (DROP+recreate at 10 args -- NEVER a defaulted
--      create-or-replace, which would create a 2nd overload; PostgREST-ambiguous).
--      Full-state: null / '{}' clears it. Shape re-validated (42501).
--   4. app.list_menu + app.pos_menu (same signatures => CREATE OR REPLACE keeps
--      ACLs) serve kitchen_meat on modifier_option rows: to the dashboard editor
--      (list_menu) and to the POS for the order-time snapshot (pos_menu, both the
--      redacted + full branches -- kitchen_meat is NON-money, like allow_quantity).
--   5. app.submit_order (same signature => CREATE OR REPLACE) also stores each
--      selected modifier's `meat_snapshot` verbatim into order_item_modifiers;
--      the money recompute/validation/idempotency/audit is byte-unchanged.
--
-- The READ path (sync_pull) needs NO change: it serializes rows via to_jsonb(t)
-- (all columns), so meat_snapshot auto-flows to the KDS pull, and app.redact_money
-- is a DENYLIST keyed on (^|_)minor($|_) + receipt fields, so a non-money meat
-- field is PRESERVED for kitchen_staff (KDS money-free, T-003).
--
-- Money/tax/payment logic is untouched (no *_minor column, cast, or arithmetic
-- change). KITCHEN-PREP-001's order_items.prep_snapshot schema is UNCHANGED.
--
-- LOCAL-ONLY: validate with `supabase db reset` + pgTAP + the app test suites.
-- Do NOT apply to hosted Supabase in this ticket (RISK R-003 sign-off gate).
--
-- Manual DOWN (teardown), if ever needed:
--   -- restore app.submit_order (20260708090000), app.list_menu + app.pos_menu
--   --   (20260704110000), menu_upsert_modifier_option app+public (20260625100000);
--   -- alter table public.order_item_modifiers drop column meat_snapshot;
--   -- alter table public.modifier_options drop column kitchen_meat;
--   -- drop function app.jsonb_is_meat_object(jsonb);
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. app.jsonb_is_meat_object -- a pure IMMUTABLE predicate backing both meat
--    CHECKs. TRUE when the value is NULL or a JSON OBJECT carrying NO money key
--    (nothing matching (^|_)minor($|_)) -- the D-007 belt-and-suspenders so a
--    meat object can never smuggle a money amount to the kitchen. Fully
--    schema-qualified; PUBLIC execute kept (a table CHECK must be evaluable by
--    every insert path incl. BYPASSRLS fixtures).
-- ---------------------------------------------------------------------------
create function app.jsonb_is_meat_object(p_value jsonb)
  returns boolean
  language sql
  immutable
as $$
  select p_value is null
      or (pg_catalog.jsonb_typeof(p_value) = 'object'
          and not exists (
                select 1
                from pg_catalog.jsonb_object_keys(p_value) as k(key)
                where k.key ~ '(^|_)minor($|_)'));
$$;

comment on function app.jsonb_is_meat_object(jsonb) is
  'KITCHEN-MEAT-001: TRUE when the value is NULL or a JSON object carrying NO money key ((^|_)minor($|_)). Pure IMMUTABLE predicate backing the modifier_options.kitchen_meat + order_item_modifiers.meat_snapshot CHECKs. Reads no data; fully schema-qualified. PUBLIC execute kept on purpose. A meat object is {quantity,unit} -- a count + text, never money (D-007).';

-- ---------------------------------------------------------------------------
-- 1. modifier_options.kitchen_meat -- the owner-configured per-selection meat
--    (nullable; no data rewrite -- existing rows stay NULL).
-- ---------------------------------------------------------------------------
alter table public.modifier_options
  add column kitchen_meat jsonb
    constraint modifier_options_kitchen_meat_shape
      check (app.jsonb_is_meat_object(kitchen_meat));

comment on column public.modifier_options.kitchen_meat is
  'KITCHEN-MEAT-001: OPTIONAL owner-configured meat contribution of ONE selection of this option -- a JSON object {quantity, unit} (e.g. {"quantity":2,"unit":"قطع"} for a Double). NON-money (D-007): quantity is a count, unit is text; a money key is CHECK-rejected. Nullable; NULL = no meat contribution. Never inferred from name/price. Served to the dashboard (list_menu) + POS (pos_menu, non-money so kitchen too).';

-- ---------------------------------------------------------------------------
-- 2. order_item_modifiers.meat_snapshot -- the order-time meat snapshot
--    (nullable; existing rows stay NULL).
-- ---------------------------------------------------------------------------
alter table public.order_item_modifiers
  add column meat_snapshot jsonb
    constraint order_item_modifiers_meat_snapshot_shape
      check (app.jsonb_is_meat_object(meat_snapshot));

comment on column public.order_item_modifiers.meat_snapshot is
  'KITCHEN-MEAT-001: ORDER-TIME (D-008) snapshot of the selected option''s kitchen_meat {quantity, unit}. NON-money (D-007). Nullable; existing rows are NULL. Passes through app.redact_money (no *_minor token) so kitchen_staff pulls carry it; the KDS computes the whole-order meat total = sum(meat.quantity x order_item_modifier.quantity x order_item.quantity) grouped by unit.';

-- ---------------------------------------------------------------------------
-- 3. menu_upsert_modifier_option -- DROP the exact CURRENT 9-arg signatures
--    (app + public wrapper, from 20260625100000) then recreate at 10 args with
--    an appended p_kitchen_meat jsonb (LAST, defaulted). Full-state: null/'{}'
--    clears it. Shape re-validated (42501). Grants re-issued for the new sigs.
-- ---------------------------------------------------------------------------
drop function if exists public.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean);
drop function if exists app.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean);

create function app.menu_upsert_modifier_option(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid     default null,
  p_id                uuid     default null,
  p_modifier_id       uuid     default null,
  p_name              text     default null,
  p_price_delta_minor bigint   default 0,
  p_display_order     integer  default 0,
  p_is_active         boolean  default true,
  p_kitchen_meat      jsonb    default null
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
  -- an empty object normalizes to NULL (one canonical "no meat" shape).
  v_meat         jsonb := case when p_kitchen_meat = '{}'::jsonb then null else p_kitchen_meat end;
begin
  if not app.menu_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'menu.modifier_option.upsert_denied', null, jsonb_build_object('entity', 'modifier_option', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'modifier_option');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_modifier_option: name is required' using errcode = '42501';
  end if;
  -- KITCHEN-MEAT-001: kitchen_meat is null or a money-free JSON object (D-007).
  if not app.jsonb_is_meat_object(p_kitchen_meat) then
    raise exception 'menu_upsert_modifier_option: kitchen_meat must be null or a JSON object with no money key (D-007)' using errcode = '42501';
  end if;
  if not exists (select 1 from public.modifiers m
                 where m.id = p_modifier_id
                   and m.organization_id = p_organization_id
                   and m.restaurant_id = p_restaurant_id
                   -- B2: scope-compatible parent (restaurant-scoped or same branch; never sibling branch)
                   and (m.branch_id is null or m.branch_id = p_branch_id)) then
    raise exception 'menu_upsert_modifier_option: modifier_id not found or not scope-compatible (same org/restaurant; restaurant-scoped or same branch)' using errcode = '42501';
  end if;
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.modifier_options where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'menu_upsert_modifier_option: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'menu_upsert_modifier_option: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.modifier_options
      (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_modifier_id, btrim(p_name),
       coalesce(p_price_delta_minor, 0), coalesce(p_display_order, 0), coalesce(p_is_active, true), v_meat);
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.modifier_options t where t.id = p_id;
    update public.modifier_options set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, modifier_id = p_modifier_id,
      name = btrim(p_name), price_delta_minor = coalesce(p_price_delta_minor, 0),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true),
      kitchen_meat = v_meat
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.modifier_options t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.modifier_option.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'modifier_option', 'id', v_id, 'action', v_action);
end;
$$;

comment on function app.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean, jsonb) is
  'RF-109 modifier-option upsert + KITCHEN-MEAT-001 p_kitchen_meat (null = clear; empty object -> null; full-state). DROP+recreated at 10 args so exactly ONE overload exists (PostgREST-unambiguous). kitchen_meat is a money-free JSON object {quantity,unit} validated by app.jsonb_is_meat_object (42501 on a money key, D-007). price_delta_minor stays integer minor (D-007); guard/audit unchanged.';

create function public.menu_upsert_modifier_option(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_modifier_id uuid default null, p_name text default null,
  p_price_delta_minor bigint default 0, p_display_order integer default 0, p_is_active boolean default true,
  p_kitchen_meat jsonb default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_modifier_option(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_modifier_id, p_name, p_price_delta_minor, p_display_order, p_is_active, p_kitchen_meat); $$;

-- Grants for the NEW exact signatures (authenticated only; never anon/service_role).
revoke all on function app.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean, jsonb) from public;
grant execute on function app.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean, jsonb) to authenticated;
revoke all on function public.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean, jsonb) from public;
grant execute on function public.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. app.list_menu -- CREATE OR REPLACE (keeps ACLs); modifier_option rows gain
--    the kitchen_meat key. Body extracted verbatim from 20260704110000.
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
  'RF-109/D-033 GUC-free menu MANAGEMENT read (manager+). KITCHEN-MEAT-001: modifier_option rows additionally carry kitchen_meat (a money-free {quantity,unit} object or null) so the dashboard editor can load/edit it. Every row carries the tenant keys (D-001); money integer minor bigint (D-007); read-only, scope-safe (R-003).';

-- ---------------------------------------------------------------------------
-- 5. app.pos_menu -- CREATE OR REPLACE (keeps ACLs); modifier_option rows gain
--    the kitchen_meat key in BOTH branches (non-money -> served to every role
--    incl. kitchen, like allow_quantity). Body extracted verbatim from
--    20260704110000. The T-003 money-key omission + T-014 image_path omission
--    for kitchen_staff are UNCHANGED.
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
  'MVP POS menu read RPC (D-011). KITCHEN-MEAT-001: modifier_option rows additionally carry kitchen_meat (a money-free {quantity,unit} object or null) in BOTH branches so the POS can snapshot the selected option''s meat at order time; served to every role incl. kitchen (non-money, like allow_quantity). The T-003 money-key omission + T-014 image_path omission for kitchen_staff are UNCHANGED; money integer minor bigint (D-007).';

-- ---------------------------------------------------------------------------
-- 6. app.submit_order -- CREATE OR REPLACE (keeps ACLs). FAITHFUL re-creation of
--    the KITCHEN-PREP-001 body (20260708090000) with the ONLY change being
--    `meat_snapshot` added to the order_item_modifiers INSERT (extracted
--    verbatim; money recompute/validation/prep_snapshot unchanged).
-- ---------------------------------------------------------------------------
create or replace function app.submit_order(
  p_pin_session_id              uuid,
  p_order_id                    uuid,
  p_device_id                   uuid,
  p_local_operation_id          text,
  p_order_type                  text,
  p_table_id                    uuid,
  p_shift_id                    uuid,
  p_currency_code               text,
  p_notes                       text,
  p_order_items                 jsonb,
  p_client_subtotal_minor       bigint,
  p_client_discount_total_minor bigint,
  p_client_tax_total_minor      bigint,
  p_client_grand_total_minor    bigint,
  p_client_created_at           timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing_stat  text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_m_rest        uuid;
  v_m_branch      uuid;
  v_existing_id   uuid;
  v_existing_rev  integer;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_line_disc     bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_subtotal      bigint := 0;
  v_grand         bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
begin
  -- (1-5) PIN session: exists, valid (active/not-ended/not-expired), backing
  -- device session active + not revoked, pairing active. Scope + actor derived here.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found then
    raise exception 'submit_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'submit_order: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;

  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing_stat
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing_stat = 'active') then
    raise exception 'submit_order: backing device session/pairing is not active' using errcode = '42501';
  end if;

  -- (6) the caller's claimed device must be the device behind the PIN session
  if v_ds_device <> p_device_id then
    raise exception 'submit_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;

  -- (9-14) membership: active, role permitted, scope covers the derived branch
  select m.role, m.status, m.deleted_at, m.restaurant_id, m.branch_id
    into v_role, v_m_status, v_m_deleted, v_m_rest, v_m_branch
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'submit_order: resolved membership is not active' using errcode = '42501';
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    raise exception 'submit_order: role % may not submit orders', v_role using errcode = '42501';
  end if;
  if not (v_m_rest is null or v_m_rest = v_rest) or not (v_m_branch is null or v_m_branch = v_branch) then
    raise exception 'submit_order: membership scope does not cover the order branch' using errcode = '42501';
  end if;
  -- NOTE: org/restaurant/branch are taken from the PIN session (v_org/v_rest/v_branch),
  -- NEVER from client input, so a cross-tenant submit is structurally impossible.

  -- (payload) basic shape + currency + order_type
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'submit_order: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'submit_order: invalid order_type %', p_order_type using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'submit_order: currency_code must be a 3-letter ISO code' using errcode = '42501';
  end if;
  if p_client_discount_total_minor < 0 or p_client_tax_total_minor < 0
     or p_client_subtotal_minor < 0 or p_client_grand_total_minor < 0 then
    raise exception 'submit_order: order totals must be non-negative integers (minor units)' using errcode = '42501';
  end if;

  -- (money recompute) from the SUBMITTED SNAPSHOTS ONLY (never the live menu).
  -- Validate the per-line and order totals; reject any client/snapshot mismatch.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    -- bound to the integer column range so an absurd quantity yields a clean 42501
    -- rather than a raw 22003 on the ::int insert (and limits qty*price overflow risk).
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'submit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    if (v_item ->> 'menu_item_id') is null then
      raise exception 'submit_order: order_items[].menu_item_id is required' using errcode = '42501';
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      raise exception 'submit_order: order_items[].menu_item_name_snapshot is required' using errcode = '42501';
    end if;

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'submit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;
    if v_line_total < 0 then
      raise exception 'submit_order: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_client_subtotal_minor <> v_subtotal then
    raise exception 'submit_order: client subtotal_minor (%) does not match snapshot recompute (%)',
      p_client_subtotal_minor, v_subtotal using errcode = '42501';
  end if;
  v_grand := v_subtotal - p_client_discount_total_minor + p_client_tax_total_minor;
  if v_grand < 0 then
    raise exception 'submit_order: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  if p_client_grand_total_minor <> v_grand then
    raise exception 'submit_order: client grand_total_minor (%) does not match snapshot recompute (%)',
      p_client_grand_total_minor, v_grand using errcode = '42501';
  end if;

  -- (idempotency) ONLY AFTER full validation: replay scoped to the validated
  -- (org, device, local_operation_id). Returns the same order; never re-inserts;
  -- never bypasses validation; never crosses tenants (org is session-derived).
  select o.id, o.revision into v_existing_id, v_existing_rev
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    return jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (insert) order header at status 'submitted'
  insert into public.orders (
    id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, table_id, shift_id,
    order_type, status, currency_code,
    subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor,
    notes, local_operation_id, revision, client_created_at)
  values (
    p_order_id, v_org, v_rest, v_branch, p_device_id, p_pin_session_id,
    v_emp, v_membership, p_table_id, p_shift_id,
    p_order_type, 'submitted', p_currency_code,
    v_subtotal, p_client_discount_total_minor, p_client_tax_total_minor, v_grand,
    p_notes, p_local_operation_id, 1, p_client_created_at);

  -- (insert) items at status 'pending' + their modifiers, recomputing line_total
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes, prep_snapshot)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', v_line_disc, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot')
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          raise exception 'submit_order: modifiers[].modifier_option_id is required' using errcode = '42501';
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          raise exception 'submit_order: modifiers[].option_name_snapshot is required' using errcode = '42501';
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (audit) append-only order.submitted event (D-013, API_CONTRACT §4.1) in the
  -- SAME transaction. This SECURITY DEFINER RPC writes it as the audit_events
  -- table owner (RF-017 grants app roles NO insert; the append-only trigger
  -- blocks only UPDATE/DELETE/TRUNCATE). The idempotency-replay path returns
  -- earlier, so a replay NEVER writes a second audit row. actor =
  -- employee_profile (RF-017 requires app_user OR employee_profile present).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch,
    null, v_emp, p_device_id,
    'order.submitted', null, null,
    jsonb_build_object(
      'order_id',               p_order_id,
      'status',                 'submitted',
      'revision',               1,
      'currency_code',          p_currency_code,
      'subtotal_minor',         v_subtotal,
      'discount_total_minor',   p_client_discount_total_minor,
      'tax_total_minor',        p_client_tax_total_minor,
      'grand_total_minor',      v_grand,
      'device_id',              p_device_id,
      'local_operation_id',     p_local_operation_id,
      'order_type',             p_order_type,
      'table_id',               p_table_id,
      'shift_id',               p_shift_id,
      'resolved_membership_id', v_membership,
      'item_count',             v_item_count,
      'modifier_count',         v_mod_count));

  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id, 'revision', 1,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'RF-052 SECURITY DEFINER submit_order + KITCHEN-PREP-001 order_items.prep_snapshot + KITCHEN-MEAT-001 order_item_modifiers.meat_snapshot: each selected modifier''s NON-money meat_snapshot ({quantity,unit}) is stored verbatim from the payload element. Signature UNCHANGED (both snapshots ride inside p_order_items), so money recompute/validation/idempotency/audit are byte-unchanged (D-007/D-008).';

-- Grants re-issued for the UNCHANGED signature (parity; CREATE OR REPLACE keeps
-- ACLs). Authenticated only -- never anon / public / service_role.
revoke all on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) from public;
grant execute on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;
