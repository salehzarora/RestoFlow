-- RF-109 Stage 2 -- menu management RPCs + thin public wrappers (DECISION D-031; API_CONTRACT §4.23).
--
-- app.menu_upsert_* / app.menu_soft_delete: SECURITY DEFINER (run as table owner, so they
-- perform the write the Stage-1 RLS deny-policies forbid for `authenticated`), locked
-- search_path='', granted to authenticated only. Thin public.menu_* SECURITY INVOKER wrappers
-- (RF-064 / RF-122 pattern) make them Data-API-reachable without exposing the `app` schema.
--
-- Authorization (authenticated-user / membership-based, like RF-090):
--   - structural failures (unauthenticated/unlinked, no active membership in the target org,
--     caller scope does not cover the target, cross-org id, bad input/money/currency, unknown
--     entity) RAISE 42501 -> rolled back, no audit (RF-053 convention).
--   - role denial (caller IS an active member covering the target scope but lacks a WRITE role)
--     writes a committed `menu.<entity>.<action>_denied` audit row and RETURNS
--     {ok:false, error:'permission_denied'} (RF-053 return-not-raise pattern so the audit persists).
--   Write roles: org_owner / restaurant_owner / manager only (D-031/§4.23/D-028).
--   platform_admin is NEVER a tenant write path (D-026): no app.is_platform_admin() reference.
-- Money: integer minor only (D-007) -- typed bigint params; base_price_minor >= 0; signed child
--   price_delta_minor; currency_code ^[A-Z]{3}$. No float/numeric/decimal/money.
-- Snapshots (D-008): these RPCs touch the live menu only; order snapshots are never read or rewritten.
-- Soft delete (D-020): sets deleted_at=now() (set_updated_at trigger bumps updated_at); never physical.

-- ---------------------------------------------------------------------------
-- 0. Internal helpers (revoked from public; called only inside the SECURITY DEFINER RPCs).
-- ---------------------------------------------------------------------------

-- Structural gate + write-role check. Raises 42501 for non-member / wrong-org / scope-miss;
-- returns TRUE when the caller has a write role (org_owner/restaurant_owner/manager) in scope,
-- FALSE when the caller covers the scope but lacks a write role (role-denied path).
create or replace function app.menu_guard(p_org uuid, p_restaurant uuid, p_branch uuid)
  returns boolean
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if app.current_app_user_id() is null then
    raise exception 'menu: authentication required' using errcode = '42501';
  end if;
  if app.current_org_id() is null or app.current_org_id() <> p_org then
    raise exception 'menu: no active membership in the target organization' using errcode = '42501';
  end if;
  if not app.has_scope(p_org, p_restaurant, p_branch) then
    raise exception 'menu: caller scope does not cover the target' using errcode = '42501';
  end if;
  return app.has_role_in_scope(p_org, p_restaurant, p_branch,
           'org_owner', 'restaurant_owner', 'manager');
end;
$$;

-- Append-only audit writer for menu mutations (actor = the GUC-resolved app_user; no device).
create or replace function app.menu_audit(
  p_org uuid, p_restaurant uuid, p_branch uuid, p_action text, p_old jsonb, p_new jsonb)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
  values
    (p_org, p_restaurant, p_branch, app.current_app_user_id(), null, p_action, null, p_old, p_new);
end;
$$;

revoke all on function app.menu_guard(uuid, uuid, uuid) from public;
revoke all on function app.menu_audit(uuid, uuid, uuid, text, jsonb, jsonb) from public;

-- ---------------------------------------------------------------------------
-- 1. app.menu_upsert_category
-- ---------------------------------------------------------------------------
create or replace function app.menu_upsert_category(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid     default null,
  p_id              uuid     default null,
  p_name            text     default null,
  p_display_order   integer  default 0,
  p_is_active       boolean  default true
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
      'menu.menu_category.upsert_denied', null, jsonb_build_object('entity', 'menu_category', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'menu_category');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_category: name is required' using errcode = '42501';
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
      (id, organization_id, restaurant_id, branch_id, name, display_order, is_active)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, btrim(p_name),
       coalesce(p_display_order, 0), coalesce(p_is_active, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.menu_categories t where t.id = p_id;
    update public.menu_categories set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, name = btrim(p_name),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true)
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.menu_categories t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.menu_category.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'menu_category', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. app.menu_upsert_item
-- ---------------------------------------------------------------------------
create or replace function app.menu_upsert_item(
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
  p_is_active         boolean  default true
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
       name, description, base_price_minor, currency_code, display_order, is_active)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_category_id, p_default_station_id,
       btrim(p_name), p_description, p_base_price_minor, p_currency_code,
       coalesce(p_display_order, 0), coalesce(p_is_active, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.menu_items t where t.id = p_id;
    update public.menu_items set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_category_id = p_menu_category_id,
      default_station_id = p_default_station_id, name = btrim(p_name), description = p_description,
      base_price_minor = p_base_price_minor, currency_code = p_currency_code,
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true)
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.menu_items t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.menu_item.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'menu_item', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. app.menu_upsert_size  (child of menu_items; signed delta)
-- ---------------------------------------------------------------------------
create or replace function app.menu_upsert_size(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid     default null,
  p_id                uuid     default null,
  p_menu_item_id      uuid     default null,
  p_name              text     default null,
  p_price_delta_minor bigint   default 0,
  p_display_order     integer  default 0,
  p_is_active         boolean  default true
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
      'menu.item_size.upsert_denied', null, jsonb_build_object('entity', 'item_size', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'item_size');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_size: name is required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.menu_items mi
                 where mi.id = p_menu_item_id
                   and mi.organization_id = p_organization_id
                   and mi.restaurant_id = p_restaurant_id
                   -- B2: scope-compatible parent (restaurant-scoped or same branch; never sibling branch)
                   and (mi.branch_id is null or mi.branch_id = p_branch_id)) then
    raise exception 'menu_upsert_size: menu_item_id not found in the target organization/restaurant' using errcode = '42501';
  end if;
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.item_sizes where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'menu_upsert_size: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'menu_upsert_size: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.item_sizes
      (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor, display_order, is_active)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_item_id, btrim(p_name),
       coalesce(p_price_delta_minor, 0), coalesce(p_display_order, 0), coalesce(p_is_active, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.item_sizes t where t.id = p_id;
    update public.item_sizes set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_item_id = p_menu_item_id,
      name = btrim(p_name), price_delta_minor = coalesce(p_price_delta_minor, 0),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true)
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.item_sizes t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.item_size.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'item_size', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. app.menu_upsert_variant  (child of menu_items; signed delta)
-- ---------------------------------------------------------------------------
create or replace function app.menu_upsert_variant(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid     default null,
  p_id                uuid     default null,
  p_menu_item_id      uuid     default null,
  p_name              text     default null,
  p_price_delta_minor bigint   default 0,
  p_display_order     integer  default 0,
  p_is_active         boolean  default true
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
      'menu.item_variant.upsert_denied', null, jsonb_build_object('entity', 'item_variant', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'item_variant');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_variant: name is required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.menu_items mi
                 where mi.id = p_menu_item_id
                   and mi.organization_id = p_organization_id
                   and mi.restaurant_id = p_restaurant_id
                   -- B2: scope-compatible parent (restaurant-scoped or same branch; never sibling branch)
                   and (mi.branch_id is null or mi.branch_id = p_branch_id)) then
    raise exception 'menu_upsert_variant: menu_item_id not found in the target organization/restaurant' using errcode = '42501';
  end if;
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.item_variants where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'menu_upsert_variant: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'menu_upsert_variant: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.item_variants
      (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor, display_order, is_active)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_item_id, btrim(p_name),
       coalesce(p_price_delta_minor, 0), coalesce(p_display_order, 0), coalesce(p_is_active, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.item_variants t where t.id = p_id;
    update public.item_variants set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_item_id = p_menu_item_id,
      name = btrim(p_name), price_delta_minor = coalesce(p_price_delta_minor, 0),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true)
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.item_variants t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.item_variant.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'item_variant', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. app.menu_upsert_modifier  (child of menu_items; selection rules)
-- ---------------------------------------------------------------------------
create or replace function app.menu_upsert_modifier(
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
  p_is_active       boolean  default true
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
       selection_type, min_select, max_select, is_required, display_order, is_active)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_item_id, btrim(p_name),
       coalesce(p_selection_type, 'single'), coalesce(p_min_select, 0), p_max_select,
       coalesce(p_is_required, false), coalesce(p_display_order, 0), coalesce(p_is_active, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.modifiers t where t.id = p_id;
    update public.modifiers set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_item_id = p_menu_item_id,
      name = btrim(p_name), selection_type = coalesce(p_selection_type, 'single'),
      min_select = coalesce(p_min_select, 0), max_select = p_max_select,
      is_required = coalesce(p_is_required, false),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true)
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.modifiers t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.modifier.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'modifier', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. app.menu_upsert_modifier_option  (child of modifiers; signed delta)
-- ---------------------------------------------------------------------------
create or replace function app.menu_upsert_modifier_option(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid     default null,
  p_id                uuid     default null,
  p_modifier_id       uuid     default null,
  p_name              text     default null,
  p_price_delta_minor bigint   default 0,
  p_display_order     integer  default 0,
  p_is_active         boolean  default true
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
      'menu.modifier_option.upsert_denied', null, jsonb_build_object('entity', 'modifier_option', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'modifier_option');
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'menu_upsert_modifier_option: name is required' using errcode = '42501';
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
      (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_modifier_id, btrim(p_name),
       coalesce(p_price_delta_minor, 0), coalesce(p_display_order, 0), coalesce(p_is_active, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.modifier_options t where t.id = p_id;
    update public.modifier_options set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, modifier_id = p_modifier_id,
      name = btrim(p_name), price_delta_minor = coalesce(p_price_delta_minor, 0),
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true)
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.modifier_options t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.modifier_option.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'modifier_option', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. app.menu_soft_delete  (discriminated; tombstone only; D-020)
-- ---------------------------------------------------------------------------
create or replace function app.menu_soft_delete(
  p_organization_id uuid,
  p_entity          text,
  p_id              uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_table     text;
  v_found_org uuid;
  v_rest      uuid;
  v_branch    uuid;
  v_old       jsonb;
  v_new       jsonb;
begin
  v_table := case p_entity
    when 'menu_category'   then 'menu_categories'
    when 'menu_item'       then 'menu_items'
    when 'item_size'       then 'item_sizes'
    when 'item_variant'    then 'item_variants'
    when 'modifier'        then 'modifiers'
    when 'modifier_option' then 'modifier_options'
    else null
  end;
  if v_table is null then
    raise exception 'menu_soft_delete: unknown entity %', p_entity using errcode = '42501';
  end if;

  -- locate the row (as the SECURITY DEFINER owner, RLS-bypassing) to resolve its scope
  execute format('select organization_id, restaurant_id, branch_id, to_jsonb(t) from public.%I t where id = $1', v_table)
    into v_found_org, v_rest, v_branch, v_old using p_id;
  if v_found_org is null then
    raise exception 'menu_soft_delete: % not found' , p_entity using errcode = '42501';
  end if;
  if v_found_org <> p_organization_id then
    raise exception 'menu_soft_delete: id belongs to another organization' using errcode = '42501';
  end if;

  -- gate against the ROW's actual scope
  if not app.menu_guard(p_organization_id, v_rest, v_branch) then
    perform app.menu_audit(p_organization_id, v_rest, v_branch,
      'menu.' || p_entity || '.delete_denied', v_old, null);
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', p_entity);
  end if;

  execute format('update public.%I set deleted_at = now() where id = $1', v_table) using p_id;
  execute format('select to_jsonb(t) from public.%I t where id = $1', v_table) into v_new using p_id;
  perform app.menu_audit(p_organization_id, v_rest, v_branch, 'menu.' || p_entity || '.deleted', v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', p_entity, 'id', p_id, 'action', 'soft_deleted');
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Thin public SECURITY INVOKER wrappers (RF-064 / RF-122 pattern).
--    No logic; delegate verbatim to app.*; the caller's EXECUTE on app.* is reused.
-- ---------------------------------------------------------------------------
create or replace function public.menu_upsert_category(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_name text default null, p_display_order integer default 0,
  p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_category(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_name, p_display_order, p_is_active); $$;

create or replace function public.menu_upsert_item(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_category_id uuid default null, p_name text default null,
  p_description text default null, p_base_price_minor bigint default null, p_currency_code text default null,
  p_default_station_id uuid default null, p_display_order integer default 0, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_item(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_category_id, p_name, p_description, p_base_price_minor, p_currency_code, p_default_station_id, p_display_order, p_is_active); $$;

create or replace function public.menu_upsert_size(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_item_id uuid default null, p_name text default null,
  p_price_delta_minor bigint default 0, p_display_order integer default 0, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_size(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_item_id, p_name, p_price_delta_minor, p_display_order, p_is_active); $$;

create or replace function public.menu_upsert_variant(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_item_id uuid default null, p_name text default null,
  p_price_delta_minor bigint default 0, p_display_order integer default 0, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_variant(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_item_id, p_name, p_price_delta_minor, p_display_order, p_is_active); $$;

create or replace function public.menu_upsert_modifier(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_item_id uuid default null, p_name text default null,
  p_selection_type text default 'single', p_min_select integer default 0, p_max_select integer default null,
  p_is_required boolean default false, p_display_order integer default 0, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_modifier(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_item_id, p_name, p_selection_type, p_min_select, p_max_select, p_is_required, p_display_order, p_is_active); $$;

create or replace function public.menu_upsert_modifier_option(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_modifier_id uuid default null, p_name text default null,
  p_price_delta_minor bigint default 0, p_display_order integer default 0, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_modifier_option(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_modifier_id, p_name, p_price_delta_minor, p_display_order, p_is_active); $$;

create or replace function public.menu_soft_delete(p_organization_id uuid, p_entity text, p_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_soft_delete(p_organization_id, p_entity, p_id); $$;

-- ---------------------------------------------------------------------------
-- 9. Grants: authenticated only on both the app functions and the public wrappers;
--    never anon / public / service_role.
-- ---------------------------------------------------------------------------
revoke all on function app.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean) from public;
revoke all on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean) from public;
revoke all on function app.menu_upsert_size(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) from public;
revoke all on function app.menu_upsert_variant(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) from public;
revoke all on function app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean) from public;
revoke all on function app.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) from public;
revoke all on function app.menu_soft_delete(uuid, text, uuid) from public;

grant execute on function app.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean) to authenticated;
grant execute on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean) to authenticated;
grant execute on function app.menu_upsert_size(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) to authenticated;
grant execute on function app.menu_upsert_variant(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) to authenticated;
grant execute on function app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean) to authenticated;
grant execute on function app.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) to authenticated;
grant execute on function app.menu_soft_delete(uuid, text, uuid) to authenticated;

revoke all on function public.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean) from public;
revoke all on function public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean) from public;
revoke all on function public.menu_upsert_size(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) from public;
revoke all on function public.menu_upsert_variant(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) from public;
revoke all on function public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean) from public;
revoke all on function public.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) from public;
revoke all on function public.menu_soft_delete(uuid, text, uuid) from public;

grant execute on function public.menu_upsert_category(uuid, uuid, uuid, uuid, text, integer, boolean) to authenticated;
grant execute on function public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean) to authenticated;
grant execute on function public.menu_upsert_size(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) to authenticated;
grant execute on function public.menu_upsert_variant(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) to authenticated;
grant execute on function public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean) to authenticated;
grant execute on function public.menu_upsert_modifier_option(uuid, uuid, uuid, uuid, uuid, text, bigint, integer, boolean) to authenticated;
grant execute on function public.menu_soft_delete(uuid, text, uuid) to authenticated;
