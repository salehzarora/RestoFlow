-- RF-110 -- Menu image storage: private bucket + path-derived RLS on storage.objects.
--
-- Ratified by DECISION D-032 (per-ticket M6 backend-surface ADR). Contract owned by
-- API_CONTRACT section 4.24; isolation control T-014 (SECURITY_AND_THREAT_MODEL
-- section 14). Builds on the RF-109 menu schema (public.menu_items) and the
-- RF-014/015/050 identity + membership helpers.
--
-- WHY PATH-DERIVED HELPERS (the load-bearing decision, D-032):
--   Supabase Storage API requests carry the JWT principal (auth.uid()) but DO NOT
--   set the app organization GUC (app.current_organization_id). The existing tenant
--   helpers app.has_scope / app.has_role_in_scope all PIN to app.current_org_id(),
--   which therefore returns NULL in the storage context and makes those helpers fail
--   closed for EVERY caller. So storage.objects policies MUST NOT use them. Instead:
--     * the caller is identified via auth.uid() -> app.current_app_user_id();
--     * the target tenant scope is PARSED FROM THE OBJECT KEY;
--     * scope is then verified against public.memberships and public.menu_items.
--   The parsed-from-path org is the tenant boundary (NOT a client-asserted GUC).
--
-- Object key contract (menu-item images only):
--   {organization_id}/{restaurant_id}/{branch_id|'global'}/menu_item/{menu_item_id}/{image_id}.{ext}
--     - organization_id, restaurant_id, menu_item_id, image_id : uuid
--     - branch segment: a uuid OR the literal 'global'  ('global' => branch_id IS NULL)
--     - literal 4th segment 'menu_item' is required
--     - ext in (png, jpg, jpeg, webp), case-insensitive
--   A malformed key parses to NO ROW => deny (it must never raise).
--
-- Invariants honored:
--   D-001/D-012  organization_id isolation -- the parsed-org is the tenant boundary.
--   D-004/D-028  membership-scoped roles; accountant is read-only (no write path).
--   D-007        no money columns introduced; no float anywhere.
--   D-011        no service-role / no anon path; only `authenticated` policies.
--   D-026        platform_admin is NEVER referenced -- never a tenant storage bypass.
--   T-003/T-013/T-014  menu rows carry money; kitchen_staff is EXCLUDED from images.
--   D-032        no audit_events for blob mutations (accepted MVP gap); NO menu_items
--                image column / NO menu_item_images table (RF-111 wires metadata).

-- ---------------------------------------------------------------------------
-- 1. Private bucket (created by SQL; config.toml bucket config is NOT used).
--    storage.buckets.type defaults to 'STANDARD'. Upsert so re-runs are safe.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'menu-images',
  'menu-images',
  false,                                                   -- private: no public/anon read
  5242880,                                                 -- ~5 MiB (5 * 1024 * 1024)
  array['image/png', 'image/jpeg', 'image/webp']           -- D-032 allowed MIME types
)
on conflict (id) do update
  set name               = excluded.name,
      public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- 2. app.menu_image_scope(name) -- strict path parser.
--    Returns ONE row of (organization_id, restaurant_id, branch_id, menu_item_id)
--    for a well-formed key, or NO ROW for anything malformed. Pure string parsing
--    (no table access); casts happen ONLY after regex validation so a malformed
--    key can never raise a cast error -- it fails closed by returning no row.
-- ---------------------------------------------------------------------------
create or replace function app.menu_image_scope(p_name text)
  returns table (organization_id uuid, restaurant_id uuid, branch_id uuid, menu_item_id uuid)
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  f        text[];
  v_ext    text;
  v_image  text;
  c_uuid   constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if p_name is null then
    return;                                                -- no row => deny
  end if;

  -- storage.foldername() returns the folder segments WITHOUT the filename, so a
  -- well-formed menu-image key yields exactly five folders:
  --   [1]=org  [2]=restaurant  [3]=branch|'global'  [4]='menu_item'  [5]=menu_item_id
  f := storage.foldername(p_name);
  if f is null or array_length(f, 1) is distinct from 5 then
    return;
  end if;

  if f[4] <> 'menu_item' then
    return;                                                -- required literal segment
  end if;

  if f[1] !~ c_uuid or f[2] !~ c_uuid or f[5] !~ c_uuid then
    return;                                                -- org / restaurant / item must be uuid
  end if;

  if f[3] <> 'global' and f[3] !~ c_uuid then
    return;                                                -- branch must be uuid or the literal 'global'
  end if;

  v_ext := lower(storage.extension(p_name));
  if v_ext is null or v_ext not in ('png', 'jpg', 'jpeg', 'webp') then
    return;                                                -- allowed image extensions only
  end if;

  -- image_id is the filename with its extension stripped; it must be a uuid.
  v_image := regexp_replace(storage.filename(p_name), '\.[^.]*$', '');
  if v_image !~ c_uuid then
    return;
  end if;

  return query select
    f[1]::uuid,
    f[2]::uuid,
    case when f[3] = 'global' then null::uuid else f[3]::uuid end,
    f[5]::uuid;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. app.can_read_menu_image(org, restaurant, branch) -- read gate.
--    Mirrors app.has_role_in_scope EXCEPT it drops the app.current_org_id() pin
--    (unset in the storage context) and instead uses the path-parsed org as the
--    tenant boundary. Read roles = the five price-capable roles; kitchen_staff is
--    EXCLUDED because menu images belong to a money-bearing surface (T-003/T-014).
--    Scope hierarchy (identical null-or-equal semantics to has_role_in_scope):
--      org-scoped member        -> any restaurant/branch in the org
--      restaurant-scoped member -> that restaurant, any branch + global
--      branch-scoped member     -> own branch + restaurant-scoped/global; NOT siblings
-- ---------------------------------------------------------------------------
create or replace function app.can_read_menu_image(p_org uuid, p_restaurant uuid, p_branch uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select p_org is not null and exists (
    select 1
    from public.memberships m
    where m.app_user_id    = app.current_app_user_id()
      and m.organization_id = p_org
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role = any (array['org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'])
      and (m.restaurant_id is null or p_restaurant is null or m.restaurant_id = p_restaurant)
      and (m.branch_id     is null or p_branch     is null or m.branch_id     = p_branch)
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. app.can_write_menu_image(org, restaurant, branch, menu_item_id) -- write gate.
--    Write roles = org_owner / restaurant_owner / manager (cashier, accountant and
--    kitchen_staff CANNOT write). In addition, the referenced menu_items row MUST
--    exist in the SAME parsed org/restaurant/branch scope -- read as SECURITY
--    DEFINER (NOT via menu RLS, which is unevaluable in the storage context). The
--    branch must correspond EXACTLY (`is not distinct from`): a restaurant-scoped
--    item (branch_id NULL) is addressed with 'global'; a branch item with its uuid.
--    Existence is a plain row check (tombstones are not filtered) per D-032.
-- ---------------------------------------------------------------------------
create or replace function app.can_write_menu_image(
  p_org uuid, p_restaurant uuid, p_branch uuid, p_menu_item_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select
    p_org is not null
    and p_restaurant is not null
    and p_menu_item_id is not null
    and exists (
      select 1
      from public.memberships m
      where m.app_user_id     = app.current_app_user_id()
        and m.organization_id = p_org
        and m.status          = 'active'
        and m.deleted_at is null
        and m.role = any (array['org_owner', 'restaurant_owner', 'manager'])
        and (m.restaurant_id is null or p_restaurant is null or m.restaurant_id = p_restaurant)
        and (m.branch_id     is null or p_branch     is null or m.branch_id     = p_branch)
    )
    and exists (
      select 1
      from public.menu_items mi
      where mi.organization_id = p_org
        and mi.restaurant_id   = p_restaurant
        and mi.id              = p_menu_item_id
        and mi.branch_id is not distinct from p_branch
    );
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants: revoke from public, grant execute to authenticated (RF-015 lineage).
--    authenticated already holds USAGE on schema app (RF-014). anon is never
--    granted: the storage policies target authenticated only.
-- ---------------------------------------------------------------------------
revoke all on function app.menu_image_scope(text)                        from public;
revoke all on function app.can_read_menu_image(uuid, uuid, uuid)         from public;
revoke all on function app.can_write_menu_image(uuid, uuid, uuid, uuid)  from public;
grant execute on function app.menu_image_scope(text)                       to authenticated;
grant execute on function app.can_read_menu_image(uuid, uuid, uuid)        to authenticated;
grant execute on function app.can_write_menu_image(uuid, uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. storage.objects policies -- four explicit per-command policies, all pinned to
--    bucket_id = 'menu-images' and targeted at `authenticated` ONLY. No anon
--    policy, no public read, no platform_admin bypass, no service-role path.
--    storage.objects already has RLS ENABLED with deny-by-default (no policies),
--    so these ADD the only access for this bucket; other buckets are unaffected.
--    A malformed key yields no scope row => the EXISTS is false => denied.
-- ---------------------------------------------------------------------------

-- SELECT: price-capable readers (kitchen excluded), scope-gated.
create policy menu_images_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'menu-images'
    and exists (
      select 1 from app.menu_image_scope(name) s
      where app.can_read_menu_image(s.organization_id, s.restaurant_id, s.branch_id)
    )
  );

-- INSERT: write roles only; the menu_item must exist in the parsed scope (the
-- existence requirement lives inside app.can_write_menu_image).
create policy menu_images_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'menu-images'
    and exists (
      select 1 from app.menu_image_scope(name) s
      where app.can_write_menu_image(s.organization_id, s.restaurant_id, s.branch_id, s.menu_item_id)
    )
  );

-- UPDATE: write permission required on BOTH the existing path (USING) and the new
-- path (WITH CHECK) -- this prevents moving an object to a path the caller cannot
-- write (sibling branch, other restaurant, other org) and keeps it in this bucket.
create policy menu_images_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'menu-images'
    and exists (
      select 1 from app.menu_image_scope(name) s
      where app.can_write_menu_image(s.organization_id, s.restaurant_id, s.branch_id, s.menu_item_id)
    )
  )
  with check (
    bucket_id = 'menu-images'
    and exists (
      select 1 from app.menu_image_scope(name) s
      where app.can_write_menu_image(s.organization_id, s.restaurant_id, s.branch_id, s.menu_item_id)
    )
  );

-- DELETE: write permission required on the object's path.
create policy menu_images_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'menu-images'
    and exists (
      select 1 from app.menu_image_scope(name) s
      where app.can_write_menu_image(s.organization_id, s.restaurant_id, s.branch_id, s.menu_item_id)
    )
  );
