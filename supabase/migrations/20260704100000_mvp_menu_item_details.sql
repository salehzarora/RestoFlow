-- ============================================================================
-- MVP (menu/media sprint) — rich product attributes: restaurant-realistic item
-- definitions that stay GENERIC across burger/pizza/shawarma/cafe menus.
-- DECISIONS D-001/D-007/D-011; SECURITY T-003/T-014; RISK R-003.
-- ============================================================================
-- WHAT THIS DOES (all ADDITIVE and non-destructive; forward-only; no data
-- rewrites — every new column is nullable and starts NULL on existing rows):
--   1. menu_items gains six nullable columns:
--        * item_type    text    — coarse kind: food/drink/side/combo/other
--                                 (NULL = unspecified; CHECK-pinned).
--        * tags         jsonb   — a JSON ARRAY OF STRINGS (CHECK via
--                                 app.jsonb_is_string_array). The VALUES are a
--                                 fixed client-side vocabulary ('spicy',
--                                 'vegetarian', 'popular', 'new') — stored as
--                                 stable wire strings, NEVER localized in data.
--        * prep_minutes integer — expected preparation time (CHECK null/>= 0).
--                                 TIME, not money.
--        * sku          text    — internal stock/product code (CHECK null or
--                                 non-blank). Back-office only: exposed to the
--                                 dashboard via list_menu, NEVER to devices
--                                 (pos_menu omits it).
--        * kitchen_note text    — a standing preparation note for the kitchen.
--        * attributes   jsonb   — a JSON OBJECT (CHECK) — the generic bag for
--                                 per-item, NON-MONEY attributes the schema
--                                 does not model as columns: portion_label,
--                                 patty_count, patty_weight_grams, and future
--                                 keys. A pizza/cafe item simply omits the
--                                 burger-ish keys.
--      HARD RULE (D-007): NO money values may EVER be stored in tags or
--      attributes. Money lives ONLY in integer *_minor columns with a
--      currency. patty_weight_grams is a WEIGHT (grams), not money.
--   2. app.menu_upsert_item + the public wrapper gain six appended params
--      (p_item_type, p_tags, p_prep_minutes, p_sku, p_kitchen_note,
--      p_attributes — all default null). Both CURRENT 13-arg functions are
--      DROPPED and recreated at 19 args — NEVER create-or-replace with an
--      added defaulted parameter (that creates a SECOND Postgres overload and
--      PostgREST rpc calls become ambiguous). The exact revoke/grant lines are
--      re-issued for the new signatures. Full-state semantics (same as
--      p_image_path): null = clear/unset — the editor always sends the item's
--      full state. The function re-validates shapes (garbage item_type /
--      non-string-array tags / non-object attributes / negative prep_minutes
--      RAISE 42501, the RF-109 validation style).
--   3. app.list_menu item JSON gains all six keys (ALWAYS present, JSON null
--      when unset — the Dart parser reads them uniformly). Management surface,
--      manager+ only — no redaction needed.
--   4. app.pos_menu item JSON gains item_type, tags, prep_minutes,
--      kitchen_note, attributes — NOT sku (an internal back-office code;
--      devices never need it). These five are NON-MONEY and PASS THROUGH to
--      kitchen sessions too (the kitchen needs prep info — prep_minutes,
--      kitchen_note, tags, attributes are exactly what a KDS wants). The
--      T-003/T-014 kitchen omissions are UNCHANGED: base_price_minor,
--      price_delta_minor, and image_path keys stay omitted for kitchen_staff.
--      NOTE: sync_pull serializes menu rows with to_jsonb, so price-capable
--      device pulls automatically carry the new columns too; kitchen_staff
--      cannot pull menu entities at all (RF-109 sync raises 42501).
--
-- SECURITY: no RLS change in this migration; grants are re-issued verbatim for
-- the new signatures (authenticated only — never anon/public/service_role).
-- Money stays integer minor everywhere (D-007); no money column is touched.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. app.jsonb_is_string_array — a pure IMMUTABLE predicate for the tags
--    CHECK below ("null or a JSON array whose every element is a string").
--    CHECK expressions cannot contain subqueries, so the element scan lives
--    here. It reads NO data; every reference is schema-qualified (safe under
--    any search_path). The default PUBLIC execute grant is deliberately kept:
--    a table CHECK must be evaluable by every insert path (definer RPCs,
--    RLS'd direct writes, BYPASSRLS test fixtures).
-- ---------------------------------------------------------------------------
create function app.jsonb_is_string_array(p_value jsonb)
  returns boolean
  language sql
  immutable
as $$
  select p_value is null
      or (pg_catalog.jsonb_typeof(p_value) = 'array'
          and not exists (
                select 1
                from pg_catalog.jsonb_array_elements(p_value) as e(elem)
                where pg_catalog.jsonb_typeof(e.elem) <> 'string'));
$$;

comment on function app.jsonb_is_string_array(jsonb) is
  'MVP (menu/media sprint): TRUE when the value is NULL or a JSON array whose every element is a string. Pure IMMUTABLE predicate backing the menu_items.tags CHECK (CHECK expressions cannot hold subqueries). Reads no data; fully schema-qualified. PUBLIC execute kept on purpose — table CHECKs must be evaluable by every insert path.';

-- ---------------------------------------------------------------------------
-- 1. menu_items — the six rich-attribute columns (nullable; no data rewrite).
-- ---------------------------------------------------------------------------
alter table public.menu_items
  add column item_type text
    constraint menu_items_item_type_valid
      check (item_type is null
             or item_type in ('food', 'drink', 'side', 'combo', 'other')),
  add column tags jsonb
    constraint menu_items_tags_is_string_array
      check (app.jsonb_is_string_array(tags)),
  add column prep_minutes integer
    constraint menu_items_prep_minutes_non_negative
      check (prep_minutes is null or prep_minutes >= 0),
  add column sku text
    constraint menu_items_sku_not_blank
      check (sku is null or length(btrim(sku)) > 0),
  add column kitchen_note text,
  add column attributes jsonb
    constraint menu_items_attributes_is_object
      check (attributes is null or jsonb_typeof(attributes) = 'object');

comment on column public.menu_items.item_type is
  'MVP (menu/media sprint): coarse item kind — food/drink/side/combo/other, or NULL for unspecified. Presentation/filtering metadata only; never authorization, never money.';
comment on column public.menu_items.tags is
  'MVP (menu/media sprint): JSON array of STRING tags from the fixed client vocabulary (spicy/vegetarian/popular/new). Stored as stable wire strings — NEVER localized in data, NEVER money (D-007). NULL = no tags.';
comment on column public.menu_items.prep_minutes is
  'MVP (menu/media sprint): expected preparation time in MINUTES (integer >= 0, or NULL = unspecified). Time, not money (D-007). Passed through to kitchen sessions (pos_menu) — a KDS needs prep info.';
comment on column public.menu_items.sku is
  'MVP (menu/media sprint): internal stock/product code (NULL or non-blank). Back-office only: list_menu exposes it to the dashboard; pos_menu NEVER serves it to devices.';
comment on column public.menu_items.kitchen_note is
  'MVP (menu/media sprint): standing preparation note for the kitchen (free text, or NULL). Non-money; passes through to kitchen sessions (pos_menu).';
comment on column public.menu_items.attributes is
  'MVP (menu/media sprint): JSON OBJECT of generic NON-MONEY item attributes (portion_label, patty_count, patty_weight_grams, ...). HARD RULE (D-007): money NEVER lives here — money is integer *_minor columns only. patty_weight_grams is WEIGHT in grams. NULL = none.';

-- ---------------------------------------------------------------------------
-- 2. menu_upsert_item gains the six params (appended, default null).
--    DROP the exact CURRENT 13-arg signatures first (app + public wrapper,
--    from 20260704090000) so exactly ONE function of each name remains —
--    PostgREST stays unambiguous.
-- ---------------------------------------------------------------------------
drop function if exists public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text);
drop function if exists app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text);

create function app.menu_upsert_item(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid     default null,
  p_id                uuid     default null,
  p_menu_category_id  uuid     default null,
  p_name              text     default null,
  p_description       text     default null,
  p_base_price_minor  bigint   default null,
  p_currency_code     text     default null,
  p_default_station_id uuid    default null,
  p_display_order     integer  default 0,
  p_is_active         boolean  default true,
  p_image_path        text     default null,
  p_item_type         text     default null,
  p_tags              jsonb    default null,
  p_prep_minutes      integer  default null,
  p_sku               text     default null,
  p_kitchen_note      text     default null,
  p_attributes        jsonb    default null
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
  -- blank normalizes to NULL: null/blank = clear/unset (the editor always
  -- sends the item's full state). Same rule for every optional text field.
  v_image        text := nullif(btrim(p_image_path), '');
  v_sku          text := nullif(btrim(p_sku), '');
  v_note         text := nullif(btrim(p_kitchen_note), '');
  -- an empty array/object normalizes to NULL (one canonical "unset" shape).
  v_tags         jsonb := case when p_tags = '[]'::jsonb then null else p_tags end;
  v_attrs        jsonb := case when p_attributes = '{}'::jsonb then null else p_attributes end;
begin
  if not app.menu_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'menu.menu_item.upsert_denied', null, jsonb_build_object('entity', 'menu_item', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'menu_item');
  end if;
  -- validation
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_item: name is required' using errcode = '42501';
  end if;
  if p_base_price_minor is null or p_base_price_minor < 0 then
    raise exception 'menu_upsert_item: base_price_minor must be a non-negative integer (minor units)' using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'menu_upsert_item: invalid currency_code (expected uppercase ISO 4217 ^[A-Z]{3}$)' using errcode = '42501';
  end if;
  -- rich-attribute shapes (menu/media sprint). Same 42501 style as above; the
  -- table CHECKs remain the final safety boundary (D-012 layer 4).
  if p_item_type is not null
     and p_item_type not in ('food', 'drink', 'side', 'combo', 'other') then
    raise exception 'menu_upsert_item: invalid item_type (expected food, drink, side, combo, other, or null)' using errcode = '42501';
  end if;
  if not app.jsonb_is_string_array(p_tags) then
    raise exception 'menu_upsert_item: tags must be a JSON array of strings (fixed client vocabulary; never money — D-007)' using errcode = '42501';
  end if;
  if p_prep_minutes is not null and p_prep_minutes < 0 then
    raise exception 'menu_upsert_item: prep_minutes must be null or a non-negative integer (minutes)' using errcode = '42501';
  end if;
  if p_attributes is not null and jsonb_typeof(p_attributes) <> 'object' then
    raise exception 'menu_upsert_item: attributes must be a JSON object of non-money attributes (D-007)' using errcode = '42501';
  end if;
  -- parent scope: category must be in the same org + restaurant
  if not exists (select 1 from public.menu_categories c
                 where c.id = p_menu_category_id
                   and c.organization_id = p_organization_id
                   and c.restaurant_id = p_restaurant_id
                   -- B2: scope-compatible parent -- restaurant-scoped (branch null) OR same branch;
                   -- never a sibling-branch parent. A restaurant-scoped item (p_branch_id null)
                   -- may therefore reference only a restaurant-scoped category.
                   and (c.branch_id is null or c.branch_id = p_branch_id)) then
    raise exception 'menu_upsert_item: menu_category_id not found or not scope-compatible (same org/restaurant; restaurant-scoped or same branch)' using errcode = '42501';
  end if;
  -- optional station: must be in the same org + restaurant
  if p_default_station_id is not null and not exists (
       select 1 from public.stations s
       where s.id = p_default_station_id
         and s.organization_id = p_organization_id
         and s.restaurant_id = p_restaurant_id
         -- B2: stations are always branch-scoped, so this requires the station's branch to match
         -- the item's branch; a restaurant-scoped item (p_branch_id null) cannot pin a branch station.
         and (s.branch_id is null or s.branch_id = p_branch_id)) then
    raise exception 'menu_upsert_item: default_station_id not found or not scope-compatible (same org/restaurant and branch)' using errcode = '42501';
  end if;
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.menu_items where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'menu_upsert_item: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'menu_upsert_item: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.menu_items
      (id, organization_id, restaurant_id, branch_id, menu_category_id, default_station_id,
       name, description, base_price_minor, currency_code, display_order, is_active, image_path,
       item_type, tags, prep_minutes, sku, kitchen_note, attributes)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_category_id, p_default_station_id,
       btrim(p_name), p_description, p_base_price_minor, p_currency_code,
       coalesce(p_display_order, 0), coalesce(p_is_active, true), v_image,
       p_item_type, v_tags, p_prep_minutes, v_sku, v_note, v_attrs);
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.menu_items t where t.id = p_id;
    update public.menu_items set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_category_id = p_menu_category_id,
      default_station_id = p_default_station_id, name = btrim(p_name), description = p_description,
      base_price_minor = p_base_price_minor, currency_code = p_currency_code,
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true),
      image_path = v_image,
      item_type = p_item_type, tags = v_tags, prep_minutes = p_prep_minutes,
      sku = v_sku, kitchen_note = v_note, attributes = v_attrs
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.menu_items t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.menu_item.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'menu_item', 'id', v_id, 'action', v_action);
end;
$$;

comment on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb) is
  'RF-109 menu item upsert + MVP p_image_path + rich attributes (p_item_type/p_tags/p_prep_minutes/p_sku/p_kitchen_note/p_attributes; null = clear — full-state upsert). DROP+recreated at 19 args so exactly ONE overload exists (PostgREST-unambiguous). Shape validation raises 42501 (RF-109 style); guard/audit unchanged. Money integer minor ONLY (D-007) — tags/attributes never carry money.';

create function public.menu_upsert_item(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_category_id uuid default null, p_name text default null,
  p_description text default null, p_base_price_minor bigint default null, p_currency_code text default null,
  p_default_station_id uuid default null, p_display_order integer default 0, p_is_active boolean default true,
  p_image_path text default null,
  p_item_type text default null, p_tags jsonb default null, p_prep_minutes integer default null,
  p_sku text default null, p_kitchen_note text default null, p_attributes jsonb default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_item(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_category_id, p_name, p_description, p_base_price_minor, p_currency_code, p_default_station_id, p_display_order, p_is_active, p_image_path, p_item_type, p_tags, p_prep_minutes, p_sku, p_kitchen_note, p_attributes); $$;

-- Grants for the NEW exact signatures (RF-109 posture: authenticated only;
-- never anon / public / service_role).
revoke all on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb) from public;
grant execute on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb) to authenticated;
revoke all on function public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb) from public;
grant execute on function public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 3a. app.list_menu — item rows gain the six keys (management read, manager+
--     only; no redaction needed). Same signature => CREATE OR REPLACE keeps the
--     existing ACLs. Body identical to 20260704090000 except the added keys.
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

  -- modifiers: children of the RETURNED item set.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'organization_id', m.organization_id, 'restaurant_id', m.restaurant_id,
           'branch_id', m.branch_id, 'menu_item_id', m.menu_item_id, 'name', m.name,
           'selection_type', m.selection_type, 'min_select', m.min_select,
           'max_select', m.max_select, 'is_required', m.is_required,
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
  'MVP (D-033; API_CONTRACT §4.23): GUC-free menu MANAGEMENT read for the owner/manager dashboard. Menu/media sprint: item rows carry image_path plus the six rich-attribute keys (item_type/tags/prep_minutes/sku/kitchen_note/attributes — always present, null when unset). Manager+ only (no redaction needed); every row carries the tenant keys (D-001); money integer minor bigint (D-007). Read-only; scope-safe (R-003).';

-- ---------------------------------------------------------------------------
-- 3b. app.pos_menu — item rows gain item_type/tags/prep_minutes/kitchen_note/
--     attributes for EVERY session (non-money prep/presentation data the
--     kitchen needs too) — but NEVER sku (internal back-office code). The
--     T-003/T-014 kitchen omissions (money keys + image_path) are UNCHANGED.
--     Same signature => CREATE OR REPLACE keeps ACLs; body identical to
--     20260704090000 except the items branch.
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
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', m.id, 'menu_item_id', m.menu_item_id, 'name', m.name,
             'selection_type', m.selection_type, 'min_select', m.min_select,
             'max_select', m.max_select, 'is_required', m.is_required,
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
  'MVP POS menu read RPC (D-011, RF-109 schema) with sizes/variants/modifiers/modifier_options + image_path. Menu/media sprint: item rows additionally carry item_type, tags, prep_minutes, kitchen_note, attributes — non-money prep/presentation data served to EVERY session incl. kitchen (a KDS needs prep info); sku is an internal back-office code and is NEVER served to devices. The T-003 money-key omission and the T-014 image_path omission for kitchen_staff are UNCHANGED, as is all session/device validation (A8), live filtering, branch visibility, and ordering. Money integer minor bigint (D-007); org+restaurant+branch filter is the isolation boundary (R-003).';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   restore the 20260704090000 app.pos_menu and app.list_menu bodies (no
--     rich-attribute keys);
--   drop function public.menu_upsert_item(... 19 args ...) / app.menu_upsert_item(...)
--     and restore the 13-arg pair + grants (20260704090000);
--   alter table public.menu_items
--     drop constraint menu_items_item_type_valid,
--     drop constraint menu_items_tags_is_string_array,
--     drop constraint menu_items_prep_minutes_non_negative,
--     drop constraint menu_items_sku_not_blank,
--     drop constraint menu_items_attributes_is_object,
--     drop column item_type, drop column tags, drop column prep_minutes,
--     drop column sku, drop column kitchen_note, drop column attributes;
--   drop function app.jsonb_is_string_array(jsonb);
-- ============================================================================
