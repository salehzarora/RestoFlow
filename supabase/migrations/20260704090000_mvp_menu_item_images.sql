-- ============================================================================
-- MVP (menu/media sprint) — real product images: menu_items.image_path pointer,
-- menu_upsert_item(p_image_path), list_menu/pos_menu exposure, and a narrowly
-- scoped DEVICE read path on the RF-110 'menu-images' bucket.
-- DECISIONS D-001/D-007/D-011/D-032; SECURITY T-003/T-014; RISK R-003.
-- ============================================================================
-- WHAT THIS DOES (all ADDITIVE and non-destructive; forward-only):
--   1. menu_items.image_path text NULL — the durable "current image of an item"
--      pointer that D-032/RF-110 explicitly deferred. It stores the RF-110
--      object key ({org}/{rest}/{branch|'global'}/menu_item/{item}/{image}.{ext})
--      of the item's current image in the private 'menu-images' bucket. Simple
--      sanity CHECK only (null or non-blank): the cross-tenant pointer risk is
--      neutralized at STORAGE RLS — signing a URL for a foreign path fails the
--      caller's own SELECT policy, so a bogus pointer can never leak bytes.
--   2. app.menu_upsert_item + the public wrapper gain `p_image_path text
--      default null` (appended LAST). Both old 12-arg functions are DROPPED and
--      recreated at 13 args — NEVER create-or-replace with an added defaulted
--      parameter (that creates a SECOND Postgres overload and PostgREST rpc
--      calls become ambiguous). The exact revoke/grant lines are re-issued for
--      the new signatures. `p_image_path` null (or blank) = CLEAR/unset — the
--      editor always sends the item's full state.
--   3. app.list_menu / app.pos_menu item JSON gain "image_path". In pos_menu the
--      key is OMITTED (not nulled) for kitchen_staff sessions — the same
--      omit-the-key pattern as the T-003 money redaction, because T-014 excludes
--      kitchen from menu images entirely (the KDS stays image-free by design).
--      NOTE: sync_pull serializes menu rows with to_jsonb, so price-capable
--      device pulls automatically carry image_path too; kitchen_staff cannot
--      pull menu entities at all (RF-109 sync raises 42501) — no new exposure.
--   4. DEVICE image reads (the RF-161 gap): device_sessions.auth_user_id uuid
--      NULL records the ANONYMOUS auth principal at redeem time, and a new
--      SECURITY DEFINER helper app.device_can_read_menu_image(name) +
--      storage.objects SELECT policy `menu_images_device_select` let an ACTIVE,
--      unrevoked, token-minted POS device session read ONLY its own org/
--      restaurant (branch-scoped) menu images. KDS devices are EXCLUDED
--      (T-014). This ADDS a narrowly-scoped read path; the four RF-110
--      membership policies are untouched.
--
-- SECURITY (RISK R-003 — PENDING the standing human RLS/security sign-off):
--   * No service-role / anon-ROLE path: the policy targets `authenticated` only
--     (anonymous device sign-ins ARE role authenticated — RF-161).
--   * The device path is READ-ONLY (SELECT). Devices can never write/delete.
--   * auth_user_id has NO FK to auth.users on purpose: the binding is a lookup
--     hint for the storage policy, and Supabase may prune anonymous auth users;
--     a pruned principal simply never matches (fail closed). It is NEVER a
--     secret and never replaces the token proof used by the RPC surface.
--   * Money stays integer minor everywhere (D-007); no money column is touched.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. menu_items.image_path — nullable pointer to the current RF-110 object key.
-- ---------------------------------------------------------------------------
alter table public.menu_items
  add column image_path text
  constraint menu_items_image_path_not_blank
    check (image_path is null or length(btrim(image_path)) > 0);

comment on column public.menu_items.image_path is
  'MVP (menu/media sprint): the RF-110 ''menu-images'' object key of the item''s current image ({org}/{rest}/{branch|global}/menu_item/{item}/{image}.{ext}), or NULL for no image. Closes the D-032 deferred "current image of an item" pointer. Sanity CHECK only (null or non-blank); byte access is always gated by the storage.objects RLS policies, so a bogus/foreign pointer can never leak image bytes.';

-- ---------------------------------------------------------------------------
-- 2. menu_upsert_item gains p_image_path (appended, default null).
--    DROP the exact OLD 12-arg signatures first (app + public wrapper) so
--    exactly ONE function of each name remains — PostgREST stays unambiguous.
-- ---------------------------------------------------------------------------
drop function if exists public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean);
drop function if exists app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean);

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
  p_image_path        text     default null
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
  -- blank normalizes to NULL: p_image_path null/blank = clear/unset (the
  -- editor always sends the item's full state).
  v_image        text := nullif(btrim(p_image_path), '');
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
       name, description, base_price_minor, currency_code, display_order, is_active, image_path)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_menu_category_id, p_default_station_id,
       btrim(p_name), p_description, p_base_price_minor, p_currency_code,
       coalesce(p_display_order, 0), coalesce(p_is_active, true), v_image);
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.menu_items t where t.id = p_id;
    update public.menu_items set
      restaurant_id = p_restaurant_id, branch_id = p_branch_id, menu_category_id = p_menu_category_id,
      default_station_id = p_default_station_id, name = btrim(p_name), description = p_description,
      base_price_minor = p_base_price_minor, currency_code = p_currency_code,
      display_order = coalesce(p_display_order, 0), is_active = coalesce(p_is_active, true),
      image_path = v_image
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.menu_items t where t.id = v_id;
  perform app.menu_audit(p_organization_id, p_restaurant_id, p_branch_id, 'menu.menu_item.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'menu_item', 'id', v_id, 'action', v_action);
end;
$$;

comment on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text) is
  'RF-109 menu item upsert + MVP p_image_path (the RF-110 object key of the item''s current image; null/blank = clear). DROP+recreated at 13 args so exactly ONE overload exists (PostgREST-unambiguous). Same guard/validation/audit behavior as RF-109 with the GUC-free app.menu_guard (D-033). Money integer minor (D-007).';

create function public.menu_upsert_item(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null,
  p_id uuid default null, p_menu_category_id uuid default null, p_name text default null,
  p_description text default null, p_base_price_minor bigint default null, p_currency_code text default null,
  p_default_station_id uuid default null, p_display_order integer default 0, p_is_active boolean default true,
  p_image_path text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.menu_upsert_item(p_organization_id, p_restaurant_id, p_branch_id, p_id, p_menu_category_id, p_name, p_description, p_base_price_minor, p_currency_code, p_default_station_id, p_display_order, p_is_active, p_image_path); $$;

-- Grants for the NEW exact signatures (RF-109 posture: authenticated only;
-- never anon / public / service_role).
revoke all on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text) from public;
grant execute on function app.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text) to authenticated;
revoke all on function public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text) from public;
grant execute on function public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3a. app.list_menu — item rows gain "image_path" (management read, manager+
--     only; no redaction needed). Same signature => CREATE OR REPLACE keeps the
--     existing ACLs. Body identical to 20260703100000 except the one added key.
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
  -- NO redaction (manager+ only surface). MVP: + image_path (nullable — the
  -- key is always present so the Dart parser reads it uniformly).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'organization_id', i.organization_id, 'restaurant_id', i.restaurant_id,
           'branch_id', i.branch_id, 'menu_category_id', i.menu_category_id, 'name', i.name,
           'description', i.description, 'base_price_minor', i.base_price_minor,
           'currency_code', i.currency_code, 'default_station_id', i.default_station_id,
           'display_order', i.display_order, 'is_active', i.is_active,
           'image_path', i.image_path)
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
  'MVP (D-033; API_CONTRACT §4.23): GUC-free menu MANAGEMENT read for the owner/manager dashboard. Menu/media sprint: item rows additionally carry image_path (the RF-110 object key of the item''s current image, or null). Manager+ only (no redaction needed); every row carries the tenant keys (D-001); money integer minor bigint (D-007). Read-only; scope-safe (R-003).';

-- ---------------------------------------------------------------------------
-- 3b. app.pos_menu — item rows gain "image_path" for price-capable sessions;
--     for kitchen_staff the KEY IS OMITTED (T-014 excludes kitchen from menu
--     images — same omit-the-key pattern as the T-003 money redaction). Same
--     signature => CREATE OR REPLACE keeps ACLs; body identical to
--     20260703130000 except the items branch.
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
  --     KEYS are omitted (not nulled) below. MVP: the SAME kitchen principal
  --     also never receives image_path (T-014 — kitchen is excluded from menu
  --     images; the key is omitted, not nulled).
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
  --     OMITTED for kitchen_staff (T-014 — the KDS stays image-free).
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id)
           else
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
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
  'MVP POS menu read RPC (D-011, RF-109 schema) with sizes/variants/modifiers/modifier_options. Menu/media sprint: item rows additionally carry image_path (the RF-110 object key, or null) for price-capable sessions; for kitchen_staff the image_path KEY is OMITTED (not nulled) exactly like the T-003 money keys — T-014 excludes kitchen from menu images, so the KDS stays image-free. All prior behavior (session/device validation A8, live filtering, branch visibility, kitchen money redaction, ordering, lean rows) is unchanged. Money integer minor bigint (D-007); org+restaurant+branch filter is the isolation boundary (R-003).';

-- ---------------------------------------------------------------------------
-- 4a. device_sessions.auth_user_id — records the (anonymous) auth principal
--     that redeemed the pairing code, so storage RLS can bind auth.uid() to a
--     live device session. Nullable: pre-existing sessions and the pgTAP GUC
--     harness have no JWT principal (they simply never match the new policy).
--     NO FK to auth.users on purpose (see the header). Never a secret.
-- ---------------------------------------------------------------------------
alter table public.device_sessions add column auth_user_id uuid;

comment on column public.device_sessions.auth_user_id is
  'MVP (menu/media sprint): the anonymous Supabase auth principal (auth.uid()) that redeemed the pairing code (RF-161), recorded at mint time. Used ONLY as the storage.objects policy binding for device menu-image reads (app.device_can_read_menu_image). Nullable (legacy/GUC sessions have none => they never match the device read policy — fail closed). Deliberately NO FK to auth.users: anonymous principals may be pruned; a pruned principal simply never matches. Not a credential — token proof (session_token_ref) remains the device authorization everywhere else.';

-- Partial index: the storage policy probes by auth_user_id on every object row.
create index device_sessions_auth_user_id_idx
  on public.device_sessions (auth_user_id)
  where auth_user_id is not null;

-- ---------------------------------------------------------------------------
-- 4b. app.redeem_device_pairing — DROP + recreate PRESERVING RF-161 behavior
--     exactly, adding only auth_user_id = auth.uid() to the minted session.
--     The public wrapper (same signature) is untouched and keeps delegating.
-- ---------------------------------------------------------------------------
drop function if exists app.redeem_device_pairing(text, text);

create function app.redeem_device_pairing(
  p_enrollment_code text,
  p_device_type     text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();  -- null for an anonymous device
  v_hash       text;
  v_pairing    uuid;
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_device     uuid;
  v_expires    timestamptz;
  v_dtype      text;
  v_dactive    boolean;
  v_ddeleted   timestamptz;
  v_session    uuid := gen_random_uuid();
  v_token      text;
  v_token_hash text;
  v_rows       integer;
begin
  if p_enrollment_code is null or btrim(p_enrollment_code) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if p_device_type is null or p_device_type not in ('pos', 'kds') then
    return jsonb_build_object('ok', false, 'error', 'invalid_type', 'entity', 'device_pairing');
  end if;

  v_hash := app.hash_provisioning_secret(btrim(p_enrollment_code));

  -- redeemable pairing by code hash: code_issued + live + unrevoked. Scope is DERIVED here.
  select dp.id, dp.organization_id, dp.restaurant_id, dp.branch_id, dp.device_id, dp.code_expires_at
    into v_pairing, v_org, v_rest, v_branch, v_device, v_expires
    from public.device_pairings dp
    where dp.enrollment_code_hash = v_hash
      and dp.status = 'code_issued'
      and dp.revoked_at is null
      and dp.deleted_at is null
    order by dp.created_at desc
    limit 1;
  if v_pairing is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_expires is not null and v_expires <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired', 'entity', 'device_pairing');
  end if;

  -- the device must be live on a LIVE branch/restaurant, and its declared type must match.
  select d.device_type, d.is_active, d.deleted_at
    into v_dtype, v_dactive, v_ddeleted
    from public.devices d
    join public.branches b on b.id = d.branch_id and b.organization_id = d.organization_id
      and b.restaurant_id = d.restaurant_id and b.deleted_at is null
    join public.restaurants r on r.id = d.restaurant_id and r.organization_id = d.organization_id
      and r.deleted_at is null
    where d.id = v_device and d.organization_id = v_org;
  if v_dtype is null or not v_dactive or v_ddeleted is not null then
    -- device or scope not live => invalid (fail closed; no scope leak).
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_dtype <> p_device_type then
    return jsonb_build_object('ok', false, 'error', 'wrong_type', 'entity', 'device_pairing');
  end if;

  -- consume the code + activate the pairing (guarded; race-safe one-time redemption).
  update public.device_pairings
     set status = 'active', paired_at = now()
     where id = v_pairing and status = 'code_issued';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;

  -- hygiene: one active session per device -> revoke any prior live sessions.
  update public.device_sessions
     set is_active = false, revoked_at = now()
     where device_id = v_device and revoked_at is null;

  -- mint the session: store ONLY the hash; return the raw token ONCE.
  -- MVP (menu/media sprint): additionally record the (anonymous) auth principal
  -- (auth.uid(), NULL in the GUC harness) so storage RLS can bind this session
  -- for the device menu-image read policy. Never a secret; never authorization
  -- by itself (the token hash remains the proof for every RPC).
  v_token      := replace(gen_random_uuid()::text, '-', '');
  v_token_hash := app.hash_provisioning_secret(v_token);
  insert into public.device_sessions
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, auth_user_id)
  values (v_session, v_org, v_rest, v_branch, v_device, v_pairing, v_token_hash, true, auth.uid());

  -- audit ONLY when a human actor exists (audit_events requires a human actor; a device has none).
  if v_actor is not null then
    insert into public.audit_events
      (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
    values
      (v_org, v_rest, v_branch, v_actor, v_device, 'device.redeemed_by_code', null,
       jsonb_build_object('device_pairing_id', v_pairing, 'from', 'code_issued'),
       jsonb_build_object('device_pairing_id', v_pairing, 'device_session_id', v_session, 'status', 'active'));
  end if;

  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_session, 'session_token', v_token,
    'organization_id', v_org, 'restaurant_id', v_rest, 'branch_id', v_branch,
    'device_id', v_device, 'device_type', v_dtype);
end;
$$;

comment on function app.redeem_device_pairing(text, text) is
  'RF-161: DEVICE-ORIGINATED code redemption. Authorized by the one-time enrollment code (hash), NOT membership; scope is server-derived from the pairing (no cross-org/branch injection). Consumes the code (code_issued -> active), revokes prior device sessions, mints a new session (hash stored; raw token returned ONCE). MVP (menu/media sprint): also records device_sessions.auth_user_id = auth.uid() so the storage device-read policy can bind the anonymous principal to this session. SECURITY DEFINER, search_path locked. authenticated only (anonymous devices qualify).';

-- Re-issue the exact RF-161 grants (DROP removed the old ACLs).
revoke all on function app.redeem_device_pairing(text, text)    from public;
grant execute on function app.redeem_device_pairing(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. app.device_can_read_menu_image(p_object_name) — the DEVICE read gate.
--    Path-derived (D-032 pattern: app.menu_image_scope; a malformed key parses
--    to no row => deny). Allows ONLY an ACTIVE, unrevoked device session bound
--    to auth.uid() on an ACTIVE pairing whose device is is_active AND
--    device_type = 'pos' (KDS EXCLUDED — T-014), whose org + restaurant match
--    the path scope, and whose branch matches (path 'global'/null OR equal to
--    the session branch). Mirrors app.restore_device_session's liveness gates.
-- ---------------------------------------------------------------------------
create function app.device_can_read_menu_image(p_object_name text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from app.menu_image_scope(p_object_name) s
    join public.device_sessions ds
      on ds.auth_user_id = auth.uid()
    join public.device_pairings dp
      on dp.id = ds.device_pairing_id
    join public.devices d
      on d.id = ds.device_id
    where ds.is_active
      and ds.revoked_at is null
      and dp.status = 'active'
      and dp.revoked_at is null
      and dp.deleted_at is null
      and d.is_active
      and d.deleted_at is null
      and d.device_type = 'pos'                      -- KDS EXCLUDED (T-014)
      and ds.organization_id = s.organization_id     -- tenant boundary (D-001)
      and ds.restaurant_id   = s.restaurant_id
      and (s.branch_id is null or s.branch_id = ds.branch_id)
  );
$$;

comment on function app.device_can_read_menu_image(text) is
  'MVP (menu/media sprint) — DEVICE read gate for the RF-110 menu-images bucket. PENDING the standing human RLS/security sign-off (RISK R-003). Path-derived via app.menu_image_scope (malformed => no row => deny); allows ONLY an ACTIVE unrevoked device_sessions row bound to auth.uid() (recorded at RF-161 redeem) on an ACTIVE pairing, device is_active AND device_type=pos (KDS EXCLUDED — T-014), org+restaurant equal to the path scope, branch: path global/null OR equal to the session branch. Read-only; never referenced by a write policy. No org GUC, no membership, no platform_admin (D-026).';

revoke all on function app.device_can_read_menu_image(text)    from public;
grant execute on function app.device_can_read_menu_image(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. storage.objects SELECT policy — the device read path. ADDS access only
--    (policies are OR'ed); the four RF-110 membership policies are untouched.
--    PENDING the standing human RLS/security sign-off (RISK R-003).
-- ---------------------------------------------------------------------------
create policy menu_images_device_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'menu-images'
    and app.device_can_read_menu_image(name)
  );

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop policy if exists menu_images_device_select on storage.objects;
--   drop function if exists app.device_can_read_menu_image(text);
--   restore the RF-161 app.redeem_device_pairing body (20260701110000);
--   drop index if exists device_sessions_auth_user_id_idx;
--   alter table public.device_sessions drop column auth_user_id;
--   restore the 20260703130000 app.pos_menu body and the 20260703100000
--     app.list_menu body (no image_path key);
--   drop function public.menu_upsert_item(... 13 args ...) / app.menu_upsert_item(...)
--     and restore the RF-109 12-arg pair + grants (20260625100000);
--   alter table public.menu_items drop constraint menu_items_image_path_not_blank,
--     drop column image_path;
-- ============================================================================
