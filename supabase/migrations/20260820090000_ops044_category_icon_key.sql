-- OPS-044 Phase 2 - EXPLICIT CATEGORY ICON: PERSISTENCE + WIRE CONTRACT.
--
-- WHAT THIS ENABLES. A POS category's icon is currently decided by its
-- POSITION in the fetched list (`kPosCategoryPalette[index % 6]`), so
-- drag-reordering categories silently reassigns every icon and a Drinks
-- category can end up wearing the burger glyph. OPS-044 lets the owner choose
-- one explicitly. This migration adds ONLY the storage and the wire contract:
-- no Dashboard picker, no POS rendering change. Every existing row stays NULL
-- and every surface keeps behaving exactly as it does today.
--
-- WHAT IS PERSISTED. An abstract application key ('burger', 'coffee', ...),
-- never a Material codepoint, an IconData, a widget name or a glyph id. The
-- 49-entry registry lives in `packages/design_system` (Phase 1). Because only
-- the key is stored, a future custom icon family replaces today's Material
-- approximations with no migration and no re-picking by the owner.
--
-- WHY THE DB VALIDATES SHAPE AND NOT MEMBERSHIP. `icon_key` is checked against
-- `^[a-z][a-z0-9_]{0,39}$` and nothing else. A CHECK naming the current 49 keys
-- would force a migration for every added icon AND break both directions of
-- compatibility: a newer Dashboard could not save a new key, and an older POS
-- must already tolerate one. The client resolves an unknown key to null and
-- falls back to its positional palette, so an unknown key degrades, never
-- crashes.
--
-- NULL IS "NOT CHOSEN", NEVER "CLEARED". `menu_upsert_category` is a
-- FULL-STATE upsert, so a caller that predates this column would wipe the
-- owner's choice on an unrelated name edit. The parameter is therefore
-- three-way: NULL preserves, '' resets, a valid key sets. This is the same
-- hazard OPS-043 Phase 3 hit on the item editor.
--
-- WHY THE FUNCTION IS DROPPED AND RECREATED, NOT REPLACED. `CREATE OR REPLACE`
-- cannot change a function's arity: it would leave the 7-argument version in
-- place beside the new 8-argument one, and PostgREST then refuses named-argument
-- calls it cannot disambiguate (PGRST203). The exact old signature is dropped
-- and its grants are re-issued verbatim against the new one. Positional 7-arg
-- callers - 29 of them across five pgTAP files - keep resolving because the new
-- parameter is LAST and defaulted.
--
-- ADDITIVE AND NON-DESTRUCTIVE. One nullable column, one CHECK, one function
-- arity change, two read functions each gaining one JSON key. No backfill, no
-- UPDATE, no DELETE, no table rebuild, no inference of an icon from a
-- category's name or position, no ordering change, and no change to item,
-- currency, availability or modifier semantics.
--
-- Tests: supabase/tests/ops044_category_icon_key_test.sql

-- ---------------------------------------------------------------------------
-- 1. Storage. Nullable: NULL means "no explicit icon chosen yet", which is the
--    state every existing row keeps.
-- ---------------------------------------------------------------------------
alter table public.menu_categories
  add column if not exists icon_key text;

alter table public.menu_categories
  drop constraint if exists menu_categories_icon_key_format;

alter table public.menu_categories
  add constraint menu_categories_icon_key_format
  check (icon_key is null or icon_key ~ '^[a-z][a-z0-9_]{0,39}$');

comment on column public.menu_categories.icon_key is
  'OPS-044: the owner-chosen category icon, as an abstract application key from the design-system registry (never a codepoint or widget name). NULL = not chosen; the client then falls back to its legacy positional palette. Shape-checked only - membership is owned by the app so new icons need no migration.';

-- ---------------------------------------------------------------------------
-- 2. Write. Drop the exact 7-argument signature (both schemas, wrapper first
--    so the app function has no dependent), then recreate at 8 arguments.
-- ---------------------------------------------------------------------------
drop function if exists public.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean);
drop function if exists app.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean);

create or replace function app.menu_upsert_category(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid     default null,
  p_id              uuid     default null,
  p_name            text     default null,
  p_display_order   integer  default 0,
  p_is_active       boolean  default true,
  -- OPS-044: NULL = the caller did not send the field (PRESERVE the
  -- stored key); '' = an explicit reset to "no chosen icon"; anything
  -- else must be a well-formed key. NULL must NEVER mean "clear", or a
  -- caller that predates this column silently wipes the owner's choice.
  p_icon_key        text     default null
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
  v_icon_key     text;
  v_action       text;
  v_old          jsonb;
  v_new          jsonb;
begin
  if not app.menu_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'menu.menu_category.upsert_denied', null, jsonb_build_object('entity', 'menu_category', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'menu_category');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_category: name is required' using errcode = '42501';
  end if;
  -- OPS-044: the DB validates the key SHAPE, not the 49-entry app
  -- registry. Pinning the allow-list in SQL would force a migration for
  -- every new icon and would break forward compatibility both ways.
  if p_icon_key is not null then
    v_icon_key := btrim(p_icon_key);
    if v_icon_key <> '' and v_icon_key !~ '^[a-z][a-z0-9_]{0,39}$' then
      raise exception 'menu_upsert_category: icon_key must match ^[a-z][a-z0-9_]{0,39}$' using errcode = '42501';
    end if;
  end if;
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.menu_categories where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'menu_upsert_category: id belongs to another organization' using errcode = '42501';
      end if;
      -- B1: org/restaurant/branch are IMMUTABLE on update; reject moving or hijacking a row
      -- into a scope different from the one it currently occupies (e.g. a branch manager
      -- updating a sibling-branch row by passing their own branch_id).
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'menu_upsert_category: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.menu_categories
      (id, organization_id, restaurant_id, branch_id, name, display_order, is_active, icon_key)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, btrim(p_name),
       coalesce(p_display_order, 0), coalesce(p_is_active, true),
       nullif(v_icon_key, ''));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.menu_categories t where t.id = p_id;
    update public.menu_categories set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, name = btrim(p_name),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true),
      -- OPS-044 three-way: omitted -> keep, '' -> clear, key -> set.
      icon_key = case when p_icon_key is null then icon_key
                      else nullif(v_icon_key, '') end
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.menu_categories t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.menu_category.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'menu_category', 'id', v_id, 'action', v_action);
end;
$$;

create or replace function public.menu_upsert_category(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_name text default null, p_display_order integer default 0,
  p_is_active boolean default true, p_icon_key text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_category(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_name, p_display_order, p_is_active, p_icon_key); $$;

comment on function app.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean, text) is
  'RF-109 category upsert. OPS-044 added p_icon_key with three-way semantics: NULL preserves the stored key, '''' resets it to NULL, a valid key sets it. Shape is validated here and by the menu_categories CHECK; membership in the app icon registry is deliberately NOT validated server-side.';

-- ---------------------------------------------------------------------------
-- 3. Grants: restore the RF-109 posture verbatim against the new signature -
--    authenticated only, on both the app function and the public wrapper;
--    never anon / public / service_role.
-- ---------------------------------------------------------------------------
revoke all on function app.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean, text) from public;
grant execute on function app.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean, text) to authenticated;
revoke all on function public.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean, text) from public;
grant execute on function public.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Reads. Both bodies are the 20260719090000 definitions VERBATIM with a
--    single added JSON key; the generator asserted the round-trip. Signatures,
--    volatility, SECURITY DEFINER, search_path, ordering, tenant filters and
--    every other response field are untouched, so the existing grants stand
--    and no consumer sees a changed shape - only one additional key.
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
           jsonb_build_object('id', c.id, 'name', c.name, 'display_order', c.display_order,
                              'icon_key', c.icon_key)
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
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
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
      on i.organization_id = s.organization_id
     and i.restaurant_id   = v_rest
     and i.id = s.menu_item_id
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
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
      on i.organization_id = v.organization_id
     and i.restaurant_id   = v_rest
     and i.id = v.menu_item_id
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
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
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_rest
     and i.id = m.menu_item_id
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
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
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_rest
     and i.id = m.menu_item_id
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
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
           'is_active', c.is_active, 'icon_key', c.icon_key)
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
