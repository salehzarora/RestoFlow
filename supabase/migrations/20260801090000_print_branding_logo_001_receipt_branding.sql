-- ============================================================================
-- PRINT-BRANDING-LOGO-001 — restaurant receipt branding: a restaurant-level
-- customer-receipt logo (pointer + enabled flag + monotonic version), a
-- dedicated private storage bucket with path-derived RLS, a versioned
-- compare-and-set (CAS) write RPC, and additive delivery of the branding
-- pointer to token-proven POS devices via get_device_printer_assignments.
--
-- DECISIONS D-001/D-003 (organization is the tenant boundary; branding is
-- restaurant-level), D-004/D-028 (membership-scoped named roles), D-007 (no
-- money columns; a logo is not money), D-011 (authenticated only; never anon /
-- service_role), D-012 (defence in depth: RLS + role/scope + RPC + constraints),
-- D-013 (append-only audit), D-020 (forward-only; Supabase replays on reset),
-- D-032 (private bucket + path-derived helpers; NEVER a persisted signed URL).
-- Builds on RF-014 (restaurants/memberships), RF-110 (menu-images storage
-- pattern), the MVP device-read gate (20260704090000), RF-112 (actor_rank_in_scope
-- + management idempotency/audit helpers), RF-117 (set_branch_tax settings-write
-- template) and the MVP + KITCHEN-MODE-001B device-assignments read
-- (20260704130000 / 20260724090000).
--
-- WHY RESTAURANT-LEVEL (not order-time snapshot): branding is a CURRENT setting.
-- Old-order reprints intentionally use the CURRENT restaurant logo; no logo bytes
-- or URL are ever snapshotted onto orders (nothing added to orders/order_items).
--
-- WHY A NEW DEDICATED BUCKET (not menu-images): restaurant-logos is a different
-- object shape ({org}/{restaurant}/logo/...) with its own independent policies,
-- so the RF-110 menu-image policies stay byte-for-byte untouched (zero blast
-- radius on the shipped, tested menu-image surface).
--
-- Object key contract (restaurant logos only):
--   {organization_id}/{restaurant_id}/logo/{image_id}.{ext}
--     - organization_id, restaurant_id, image_id : uuid
--     - literal 3rd segment 'logo' is required
--     - ext in (png, jpg, jpeg, webp), case-insensitive
--   A malformed key parses to NO ROW => deny (it must never raise). Objects are
--   immutable/versioned (a fresh random image_id per upload) — a fixed key is
--   never overwritten, so cross-restaurant collisions cannot occur.
--
-- AUTHORIZATION (final decision, §2): manage = org_owner / restaurant_owner /
-- manager (verified as NAMED ROLES in pgTAP, not an opaque numeric threshold).
-- This intentionally DIFFERS from set_branch_tax (which excludes manager): a
-- restaurant-scoped manager may manage receipt branding. Ordinary cashier /
-- kitchen_staff / accountant, cross-tenant, anonymous and unpaired/inactive
-- devices are all denied.
--
-- FORWARD-ONLY. Manual DOWN at the foot. PENDING RISK R-003 human RLS/security
-- sign-off before this serves real tenant data (CLAUDE.md / AGENTS.md).
-- ============================================================================

-- ############################################################################
-- A. RESTAURANT-LEVEL BRANDING COLUMNS (additive, backward compatible)
-- ############################################################################
-- Existing rows keep path NULL, enabled false, version 0 (defaults). No
-- row-by-row backfill. The version is a monotonic integer bumped by the CAS RPC
-- on every accepted state change (upload / replace / removal / toggle); POS
-- caches key on it so a change invalidates the client-side raster cache.
alter table public.restaurants
  add column receipt_logo_path    text    null,
  add column receipt_logo_enabled boolean not null default false,
  add column receipt_logo_version integer not null default 0;

alter table public.restaurants
  add constraint restaurants_receipt_logo_version_nonneg
    check (receipt_logo_version >= 0),
  add constraint restaurants_receipt_logo_enabled_requires_path
    check (not receipt_logo_enabled or receipt_logo_path is not null);

comment on column public.restaurants.receipt_logo_path is
  'PRINT-BRANDING-LOGO-001: object KEY (never a URL/token/bytes) of the current customer-receipt logo in the private restaurant-logos bucket, or NULL for none. Written only by app.set_restaurant_receipt_logo (D-011/D-032).';
comment on column public.restaurants.receipt_logo_enabled is
  'PRINT-BRANDING-LOGO-001: whether the logo prints on customer receipts. Default false. Constrained: enabled requires a non-null path. Disabling preserves the path but stops printing.';
comment on column public.restaurants.receipt_logo_version is
  'PRINT-BRANDING-LOGO-001: monotonic (>=0) branding version, bumped once per accepted change by the CAS RPC. Drives POS raster-cache invalidation and optimistic-concurrency (compare-and-set).';

-- ############################################################################
-- B. DEDICATED PRIVATE STORAGE BUCKET
-- ############################################################################
-- 2 MiB, png/jpeg/webp, private (no public/anon read). Upsert so re-runs are safe.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'restaurant-logos',
  'restaurant-logos',
  false,                                                   -- private: no public/anon read
  2097152,                                                 -- 2 MiB (2 * 1024 * 1024)
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
  set name               = excluded.name,
      public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ############################################################################
-- C. PATH-DERIVED SECURITY HELPERS (independent; menu-image helpers untouched)
-- ############################################################################

-- ---------------------------------------------------------------------------
-- C1. app.restaurant_logo_scope(name) — strict path parser. ONE row of
--     (organization_id, restaurant_id) for a well-formed key, or NO ROW for
--     anything malformed. Pure string parsing (no table access); casts happen
--     ONLY after regex validation so a malformed key can never raise — it fails
--     closed by returning no row.
-- ---------------------------------------------------------------------------
create or replace function app.restaurant_logo_scope(p_name text)
  returns table (organization_id uuid, restaurant_id uuid)
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
  -- well-formed restaurant-logo key yields exactly three folders:
  --   [1]=org  [2]=restaurant  [3]='logo'
  f := storage.foldername(p_name);
  if f is null or array_length(f, 1) is distinct from 3 then
    return;
  end if;

  if f[3] <> 'logo' then
    return;                                                -- required literal segment
  end if;

  if f[1] !~ c_uuid or f[2] !~ c_uuid then
    return;                                                -- org / restaurant must be uuid
  end if;

  v_ext := lower(storage.extension(p_name));
  if v_ext is null or v_ext not in ('png', 'jpg', 'jpeg', 'webp') then
    return;                                                -- allowed image extensions only
  end if;

  -- image_id is the filename with its extension stripped; it must be a uuid
  -- (cryptographically random, immutable, non-guessable — never a fixed key).
  v_image := regexp_replace(storage.filename(p_name), '\.[^.]*$', '');
  if v_image !~ c_uuid then
    return;
  end if;

  return query select f[1]::uuid, f[2]::uuid;
end;
$$;

comment on function app.restaurant_logo_scope(text) is
  'PRINT-BRANDING-LOGO-001 (D-032): strict parser for a restaurant-logo object key {org}/{restaurant}/logo/{image_id}.{ext}. Returns ONE (organization_id, restaurant_id) row for a well-formed key or NO ROW for anything malformed (fails closed; never raises). Pure string parsing — casts happen only after regex validation.';

-- ---------------------------------------------------------------------------
-- C2. app.can_read_restaurant_logo(org, restaurant) — Dashboard read gate.
--     Any ACTIVE membership covering the restaurant (branch members included —
--     the logo is what they print). Kitchen_staff EXCLUDED to mirror the
--     established menu-images Dashboard read roles. Path-parsed org is the
--     tenant boundary (no org GUC in the storage context).
-- ---------------------------------------------------------------------------
create or replace function app.can_read_restaurant_logo(p_org uuid, p_restaurant uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select p_org is not null and p_restaurant is not null and exists (
    select 1
    from public.memberships m
    where m.app_user_id     = app.current_app_user_id()
      and m.organization_id = p_org
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role = any (array['org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'])
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant)
  );
$$;

comment on function app.can_read_restaurant_logo(uuid, uuid) is
  'PRINT-BRANDING-LOGO-001 (D-032): Dashboard read gate for the restaurant-logos bucket. Any ACTIVE membership (org_owner/restaurant_owner/manager/cashier/accountant; kitchen excluded, mirroring menu-images) covering the restaurant. Path-parsed org is the tenant boundary; no org GUC.';

-- ---------------------------------------------------------------------------
-- C3. app.can_write_restaurant_logo(org, restaurant) — Dashboard write gate.
--     Write roles = org_owner / restaurant_owner / manager (§2 final). Coverage
--     is restaurant-level-or-above (m.branch_id IS NULL): a branch-scoped member
--     cannot write restaurant-level branding — EXACTLY the coverage the CAS RPC
--     enforces via actor_rank_in_scope(org, restaurant, NULL), so the storage
--     policy and the RPC gate can never disagree.
-- ---------------------------------------------------------------------------
create or replace function app.can_write_restaurant_logo(p_org uuid, p_restaurant uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select p_org is not null and p_restaurant is not null and exists (
    select 1
    from public.memberships m
    where m.app_user_id     = app.current_app_user_id()
      and m.organization_id = p_org
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role = any (array['org_owner', 'restaurant_owner', 'manager'])
      and m.branch_id is null
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant)
  );
$$;

comment on function app.can_write_restaurant_logo(uuid, uuid) is
  'PRINT-BRANDING-LOGO-001 (§2 final): Dashboard write gate for the restaurant-logos bucket. org_owner/restaurant_owner/manager only, restaurant-level-or-above coverage (branch members excluded) — identical to actor_rank_in_scope(org, restaurant, NULL) for those roles, so the storage policy and the CAS RPC agree. cashier/kitchen_staff/accountant denied.';

-- ---------------------------------------------------------------------------
-- C4. app.device_can_read_restaurant_logo(name) — POS device read gate.
--     Mirrors app.device_can_read_menu_image: an ACTIVE unrevoked device_session
--     bound to auth.uid() on an ACTIVE pairing, device is_active AND
--     device_type = 'pos' (KDS EXCLUDED — the KDS never prints customer
--     receipts), whose org + restaurant match the path scope. The logo is
--     restaurant-level (no branch segment), so there is no branch predicate.
-- ---------------------------------------------------------------------------
create or replace function app.device_can_read_restaurant_logo(p_object_name text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from app.restaurant_logo_scope(p_object_name) s
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
      and d.device_type = 'pos'                      -- KDS EXCLUDED (no receipts)
      and ds.organization_id = s.organization_id     -- tenant boundary (D-001)
      and ds.restaurant_id   = s.restaurant_id
  );
$$;

comment on function app.device_can_read_restaurant_logo(text) is
  'PRINT-BRANDING-LOGO-001 — DEVICE read gate for the restaurant-logos bucket. Path-derived (malformed => no row => deny); allows ONLY an ACTIVE unrevoked device_sessions row bound to auth.uid() on an ACTIVE pairing, device is_active AND device_type=pos (KDS EXCLUDED — never prints receipts), org+restaurant equal to the path scope. Read-only; never referenced by a write policy. No org GUC, no membership, no platform_admin (D-026).';

-- Grants: revoke from public, grant execute to authenticated only (D-011).
revoke all on function app.restaurant_logo_scope(text)                    from public;
revoke all on function app.can_read_restaurant_logo(uuid, uuid)           from public;
revoke all on function app.can_write_restaurant_logo(uuid, uuid)          from public;
revoke all on function app.device_can_read_restaurant_logo(text)          from public;
grant execute on function app.restaurant_logo_scope(text)                    to authenticated;
grant execute on function app.can_read_restaurant_logo(uuid, uuid)           to authenticated;
grant execute on function app.can_write_restaurant_logo(uuid, uuid)          to authenticated;
grant execute on function app.device_can_read_restaurant_logo(text)          to authenticated;

-- ############################################################################
-- D. storage.objects RLS — five explicit policies, all pinned to
--    bucket_id = 'restaurant-logos' and targeted at `authenticated` ONLY. No
--    anon policy, no public read, no platform_admin bypass, no service-role
--    path. RLS is already ENABLED with deny-by-default; these ADD the only
--    access for this bucket. Other buckets (incl. menu-images) are unaffected.
-- ############################################################################

-- SELECT (Dashboard readers): scope-gated read roles.
create policy restaurant_logos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'restaurant-logos'
    and exists (
      select 1 from app.restaurant_logo_scope(name) s
      where app.can_read_restaurant_logo(s.organization_id, s.restaurant_id)
    )
  );

-- INSERT: write roles only, scope-gated.
create policy restaurant_logos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'restaurant-logos'
    and exists (
      select 1 from app.restaurant_logo_scope(name) s
      where app.can_write_restaurant_logo(s.organization_id, s.restaurant_id)
    )
  );

-- UPDATE: write permission on BOTH the existing path (USING) and the new path
-- (WITH CHECK) — prevents moving an object out of the caller's authorized scope
-- and keeps it in this bucket.
create policy restaurant_logos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'restaurant-logos'
    and exists (
      select 1 from app.restaurant_logo_scope(name) s
      where app.can_write_restaurant_logo(s.organization_id, s.restaurant_id)
    )
  )
  with check (
    bucket_id = 'restaurant-logos'
    and exists (
      select 1 from app.restaurant_logo_scope(name) s
      where app.can_write_restaurant_logo(s.organization_id, s.restaurant_id)
    )
  );

-- DELETE: write permission on the object's path.
create policy restaurant_logos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'restaurant-logos'
    and exists (
      select 1 from app.restaurant_logo_scope(name) s
      where app.can_write_restaurant_logo(s.organization_id, s.restaurant_id)
    )
  );

-- SELECT (POS device): additive read path (policies OR); the four Dashboard
-- policies are untouched. KDS is excluded inside the helper.
create policy restaurant_logos_device_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'restaurant-logos'
    and app.device_can_read_restaurant_logo(name)
  );

-- ############################################################################
-- E. VERSIONED CAS WRITE RPC + READ RPC
-- ############################################################################

-- ---------------------------------------------------------------------------
-- E1. app.set_restaurant_receipt_logo — the ONLY writer of the branding columns.
--     Auth + named-role gate (org_owner/restaurant_owner/manager), path-ownership
--     validation, enabled/path coupling, optimistic compare-and-set on
--     receipt_logo_version, idempotent replay, and full before/after audit.
--
--     ORDERING (concurrency-correct): the restaurant row is locked FOR UPDATE
--     BEFORE the idempotency read so two presses of the SAME client_request_id
--     serialize — the second sees the first's committed ledger row and replays
--     rather than reporting a false version conflict. The CAS check runs under
--     that lock; a stale expected_version returns a typed conflict WITHOUT
--     claiming the ledger (so the real change is never shadowed).
-- ---------------------------------------------------------------------------
create or replace function app.set_restaurant_receipt_logo(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_logo_path         text,
  p_enabled           boolean,
  p_expected_version  integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor       uuid := app.current_app_user_id();
  v_rank        integer;
  v_scope_org   uuid;
  v_scope_rest  uuid;
  v_enabled     boolean;
  v_fp          text;
  v_replay      jsonb;
  v_result      jsonb;
  v_old         jsonb;
  v_new         jsonb;
  v_cur_version integer;
  v_cur_path    text;
  v_cur_enabled boolean;
  v_new_version integer;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'set_restaurant_receipt_logo: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_restaurant_receipt_logo: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'set_restaurant_receipt_logo: organization_id and restaurant_id are required' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'set_restaurant_receipt_logo: enabled is required' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    raise exception 'set_restaurant_receipt_logo: expected_version must be a non-negative integer' using errcode = '42501';
  end if;

  -- (b) enabled/path coupling. Enabling with no path is INVALID (typed, not a
  --     raw error). Removal (path NULL) forces the disabled state.
  if p_logo_path is null then
    if p_enabled then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'enabled_requires_path', 'entity', 'restaurant');
    end if;
    v_enabled := false;                                   -- remove => disabled
  else
    v_enabled := p_enabled;
  end if;

  -- (c) path ownership: a non-null path MUST parse and belong to THIS org+restaurant
  --     (defends against pointing branding at another tenant's object).
  if p_logo_path is not null then
    select s.organization_id, s.restaurant_id into v_scope_org, v_scope_rest
      from app.restaurant_logo_scope(p_logo_path) s;
    if v_scope_org is null then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'malformed_path', 'entity', 'restaurant');
    end if;
    if v_scope_org <> p_organization_id or v_scope_rest <> p_restaurant_id then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'path_scope_mismatch', 'entity', 'restaurant');
    end if;
  end if;

  -- (d) authority: named-role gate (org_owner/restaurant_owner/manager). A denied
  --     caller learns NOTHING about the current path/version (§6.11 no leak).
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'set_restaurant_receipt_logo: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then                                      -- below manager: cashier/kitchen/accountant
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.restaurant.logo_update_denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'setting', 'receipt_logo'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'restaurant');
  end if;

  -- (e) lock the restaurant row FIRST (serialize concurrent writers of THIS
  --     restaurant), also proving existence + live scope in-org.
  select r.receipt_logo_version, r.receipt_logo_path, r.receipt_logo_enabled, to_jsonb(r)
    into v_cur_version, v_cur_path, v_cur_enabled, v_old
    from public.restaurants r
    where r.id = p_restaurant_id
      and r.organization_id = p_organization_id
      and r.deleted_at is null
    for update;
  if v_cur_version is null then
    raise exception 'set_restaurant_receipt_logo: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;

  -- (f) idempotent replay (under the lock: a serialized duplicate of the same
  --     client_request_id sees the first press's committed result).
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'path', p_logo_path, 'enabled', v_enabled, 'expected_version', p_expected_version)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_restaurant_receipt_logo', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (g) compare-and-set: reject a stale write WITHOUT claiming the ledger, and
  --     return the CURRENT authoritative state so the caller can refresh.
  if v_cur_version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'entity', 'restaurant',
      'restaurant_id', p_restaurant_id,
      'receipt_logo_path', v_cur_path, 'receipt_logo_enabled', v_cur_enabled,
      'receipt_logo_version', v_cur_version);
  end if;

  -- (h) accepted: bump version exactly once, claim the ledger, mutate, audit.
  v_new_version := v_cur_version + 1;
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'restaurant',
                'restaurant_id', p_restaurant_id,
                'receipt_logo_path', p_logo_path, 'receipt_logo_enabled', v_enabled,
                'receipt_logo_version', v_new_version);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_restaurant_receipt_logo', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  update public.restaurants
     set receipt_logo_path = p_logo_path,
         receipt_logo_enabled = v_enabled,
         receipt_logo_version = v_new_version
   where id = p_restaurant_id;
  select to_jsonb(r) into v_new from public.restaurants r where r.id = p_restaurant_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.restaurant.logo_updated', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer) is
  'PRINT-BRANDING-LOGO-001 (D-011/D-012/D-013): the ONLY writer of restaurants.receipt_logo_*. Named-role gate org_owner/restaurant_owner/manager (rank>=manager over the restaurant; branch members excluded); cashier/kitchen/accountant/cross-tenant/anonymous denied with NO state leak. Validates path ownership (parses to this org+restaurant), couples enabled<->path (enable-with-null => invalid; path null => disabled), and does optimistic compare-and-set on receipt_logo_version (stale => typed version_conflict carrying current state, no ledger claim). Idempotent (management_request_results) with the restaurant row locked BEFORE the idem read so duplicate presses replay instead of false-conflicting. Full before/after audit settings.restaurant.logo_updated. No money (D-007).';

create or replace function public.set_restaurant_receipt_logo(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_logo_path text, p_enabled boolean, p_expected_version integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_restaurant_receipt_logo(p_client_request_id, p_organization_id, p_restaurant_id, p_logo_path, p_enabled, p_expected_version); $$;

revoke all on function app.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer)    from public;
grant execute on function app.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer) to authenticated;
revoke all on function public.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer)    from public;
grant execute on function public.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- E2. app.get_restaurant_receipt_logo — Dashboard READ of restaurant branding.
--     READ is any active membership covering the restaurant (branch members
--     INCLUDED — they print it), mirroring can_read_restaurant_logo, so the same
--     rule holds for the Storage read, the read RPC and the reprint resolver.
--     The result also carries `can_manage` — the BACKEND capability signal the
--     Dashboard keys editability on (never the literal role name): true only for
--     a restaurant-level manager+ (org_owner/restaurant_owner/restaurant-scoped
--     manager); a branch-only manager, cashier and accountant read but cannot
--     manage. No covering membership / cross-tenant => not_found (no leak).
-- ---------------------------------------------------------------------------
create or replace function app.get_restaurant_receipt_logo(
  p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_can_read   boolean;
  v_can_manage boolean;
  v_r          record;
begin
  if v_actor is null then
    raise exception 'get_restaurant_receipt_logo: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'restaurant');
  end if;
  -- READ coverage: identical to can_read_restaurant_logo (branch members read;
  -- kitchen_staff excluded from the money-bearing surface).
  select exists (
    select 1 from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role = any (array['org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'])
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
  ) into v_can_read;
  if not v_can_read then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'restaurant');
  end if;
  -- MANAGE capability: restaurant-level rank >= manager (identical to the CAS
  -- write gate + can_write_restaurant_logo). Branch-only members => false.
  v_can_manage := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null) >= 2;
  select r.receipt_logo_path, r.receipt_logo_enabled, r.receipt_logo_version into v_r
    from public.restaurants r
    where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'restaurant');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'restaurant', 'restaurant_id', p_restaurant_id,
    'receipt_logo_path', v_r.receipt_logo_path, 'receipt_logo_enabled', v_r.receipt_logo_enabled,
    'receipt_logo_version', v_r.receipt_logo_version, 'can_manage', v_can_manage);
end;
$$;

comment on function app.get_restaurant_receipt_logo(uuid, uuid) is
  'PRINT-BRANDING-LOGO-001: Dashboard READ of restaurant receipt branding. READ = any active covering membership (branch members included; kitchen excluded), same as can_read_restaurant_logo. Returns receipt_logo_path/enabled/version PLUS can_manage (actor_rank_in_scope >= manager at restaurant level — the backend editability signal the Dashboard keys on; branch-only manager/cashier/accountant => false). No covering membership / cross-tenant => not_found (no leak).';

create or replace function public.get_restaurant_receipt_logo(p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_restaurant_receipt_logo(p_organization_id, p_restaurant_id); $$;

revoke all on function app.get_restaurant_receipt_logo(uuid, uuid)    from public;
grant execute on function app.get_restaurant_receipt_logo(uuid, uuid) to authenticated;
revoke all on function public.get_restaurant_receipt_logo(uuid, uuid)    from public;
grant execute on function public.get_restaurant_receipt_logo(uuid, uuid) to authenticated;

-- ############################################################################
-- F. DEVICE ASSIGNMENT DELIVERY — get_device_printer_assignments +3 keys
-- ############################################################################
-- Faithful DROP+recreate of the CURRENT (KITCHEN-MODE-001B, 20260724090000)
-- body — signature, authorization, every existing JSON key and behavior
-- preserved verbatim — with ONE additive delta: the token-proven device block
-- also carries receipt_logo_path / receipt_logo_enabled / receipt_logo_version
-- for the device's OWN (already proven) restaurant. Keys are additive and
-- default-safe (path null / enabled false / version 0 for a legacy restaurant);
-- old POS/KDS clients ignore unknown keys. connection_config is still NEVER
-- exposed. The shipped 20260724090000 migration is NOT modified.
--
-- DROP first (both wrappers) then recreate + re-grant. Same (uuid, text)
-- signature and jsonb return type — no stacked overloads.
drop function if exists public.get_device_printer_assignments(uuid, text);
drop function if exists app.get_device_printer_assignments(uuid, text);

create function app.get_device_printer_assignments(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_hash      text;
  v_sid       uuid;
  v_org       uuid;
  v_rest      uuid;
  v_branch    uuid;
  v_dtype     text;
  v_label     text;
  v_bname     text;
  v_rname     text;
  v_logo_path text;     -- PRINT-BRANDING-LOGO-001 (additive)
  v_logo_on   boolean;  -- PRINT-BRANDING-LOGO-001 (additive)
  v_logo_ver  integer;  -- PRINT-BRANDING-LOGO-001 (additive)
  v_roles     text[];
  v_kitchen_mode text;
  v_printers  jsonb;
  v_routes    jsonb;
  v_stations  jsonb;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- token proof EXACTLY like app.list_device_staff / app.restore_device_session
  -- (RF-161). Also pull the display context AND (additive) the restaurant's
  -- current receipt-branding pointer for the device's OWN, already-proven
  -- restaurant (no extra scope check — it is the proven session's restaurant).
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id,
         d.device_type, d.label, b.name, r.name,
         r.receipt_logo_path, r.receipt_logo_enabled, r.receipt_logo_version
    into v_sid, v_org, v_rest, v_branch, v_dtype, v_label, v_bname, v_rname,
         v_logo_path, v_logo_on, v_logo_ver
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id and b.deleted_at is null
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;

  -- KITCHEN-MODE-001B role membership BY DEVICE TYPE + branch workflow mode
  -- (fail-closes to 'kds'). Unchanged.
  if v_dtype = 'pos' then
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_roles := array['receipt', 'kitchen', 'both'];
    else
      v_roles := array['receipt', 'both'];
    end if;
  elsif v_dtype = 'kds' then
    v_roles := array['kitchen', 'both'];
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;

  -- printers: LIVE rows of the device's OWN branch, visible role only, disabled
  -- rows included. NEVER connection_config. Unchanged.
  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'id')), '[]'::jsonb)
    into v_printers
  from (
    select jsonb_build_object(
      'id',              pd.id,
      'display_name',    pd.display_name,
      'role',            case when pd.role = 'both'
                              then case v_dtype when 'kds' then 'kitchen' else 'receipt' end
                              else pd.role end,
      'configured_role', pd.role,
      'supported_purposes',
        case pd.role
          when 'receipt' then '["customer_receipt"]'::jsonb
          when 'kitchen' then '["kitchen_ticket"]'::jsonb
          else case
            when v_dtype = 'kds' then '["kitchen_ticket"]'::jsonb
            when coalesce(v_kitchen_mode, 'kds') = 'printer_only'
              then '["customer_receipt", "kitchen_ticket"]'::jsonb
            else '["customer_receipt"]'::jsonb
          end
        end,
      'connection_type', pd.connection_type,
      'paper_width',     pd.paper_width,
      'is_enabled',      pd.is_enabled
    ) as item
    from public.printer_devices pd
    where pd.organization_id = v_org
      and pd.restaurant_id   = v_rest
      and pd.branch_id       = v_branch
      and pd.role            = any(v_roles)
      and pd.deleted_at is null
  ) t;

  -- routes: LIVE routes of that branch pointing at VISIBLE printers only. Unchanged.
  select coalesce(jsonb_agg(item order by (item ->> 'station_id'), (item ->> 'printer_device_id')), '[]'::jsonb)
    into v_routes
  from (
    select jsonb_build_object(
      'station_id',        pr.station_id,
      'printer_device_id', pr.printer_device_id,
      'is_enabled',        pr.is_enabled
    ) as item
    from public.printer_routes pr
    join public.printer_devices pd
      on pd.organization_id = pr.organization_id
     and pd.restaurant_id   = pr.restaurant_id
     and pd.branch_id       = pr.branch_id
     and pd.id              = pr.printer_device_id
     and pd.role            = any(v_roles)
     and pd.deleted_at is null
    where pr.organization_id = v_org
      and pr.restaurant_id   = v_rest
      and pr.branch_id       = v_branch
      and pr.deleted_at is null
  ) t;

  -- stations: LIVE + ACTIVE stations referenced by the RETURNED routes. Unchanged.
  select coalesce(jsonb_agg(item order by (item ->> 'name'), (item ->> 'id')), '[]'::jsonb)
    into v_stations
  from (
    select jsonb_build_object('id', s.id, 'name', s.name) as item
    from public.stations s
    where s.organization_id = v_org
      and s.restaurant_id   = v_rest
      and s.branch_id       = v_branch
      and s.is_active
      and s.deleted_at is null
      and exists (
        select 1
        from public.printer_routes pr
        join public.printer_devices pd
          on pd.organization_id = pr.organization_id
         and pd.restaurant_id   = pr.restaurant_id
         and pd.branch_id       = pr.branch_id
         and pd.id              = pr.printer_device_id
         and pd.role            = any(v_roles)
         and pd.deleted_at is null
        where pr.organization_id = v_org
          and pr.restaurant_id   = v_rest
          and pr.branch_id       = v_branch
          and pr.station_id      = s.id
          and pr.deleted_at is null
      )
  ) t;

  return jsonb_build_object(
    'ok', true, 'entity', 'device_printer_assignments',
    'device', jsonb_build_object(
      'device_id',       p_device_id,
      'device_type',     v_dtype,
      'label',           v_label,
      'branch_id',       v_branch,
      'branch_name',     v_bname,
      'restaurant_name', v_rname,
      -- PRINT-BRANDING-LOGO-001 additive keys (device's OWN proven scope +
      -- current branding pointer; all default-safe for a legacy restaurant).
      -- organization_id + restaurant_id give the POS a stable tenant identity
      -- for the offline raster-cache key (never a client-asserted value).
      'organization_id',      v_org,
      'restaurant_id',        v_rest,
      'receipt_logo_path',    v_logo_path,
      'receipt_logo_enabled', coalesce(v_logo_on, false),
      'receipt_logo_version', coalesce(v_logo_ver, 0)
    ),
    'printers',  v_printers,
    'routes',    v_routes,
    'stations',  v_stations,
    'server_ts', now()
  );
end;
$$;

comment on function app.get_device_printer_assignments(uuid, text) is
  'MVP + KITCHEN-MODE-001B + PRINT-BRANDING-LOGO-001: TOKEN-PROVEN printer-assignment read for POS/KDS devices (auth + role-membership + old-client compatibility unchanged; still NEVER returns connection_config). PRINT-BRANDING-LOGO-001 adds three ADDITIVE device-block keys — receipt_logo_path / receipt_logo_enabled / receipt_logo_version — for the device''s OWN already-proven restaurant (default-safe: null/false/0 for a legacy restaurant); old clients ignore them. Faithful DROP+recreate of the 20260724090000 body otherwise.';

create function public.get_device_printer_assignments(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_printer_assignments(p_device_id, p_session_token); $$;

revoke all on function app.get_device_printer_assignments(uuid, text)    from public;
grant execute on function app.get_device_printer_assignments(uuid, text) to authenticated;
revoke all on function public.get_device_printer_assignments(uuid, text)    from public;
grant execute on function public.get_device_printer_assignments(uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.get_device_printer_assignments(uuid, text);
--   drop function if exists app.get_device_printer_assignments(uuid, text);
--   -- restore the 20260724090000 (KITCHEN-MODE-001B) body of both;
--   drop function if exists public.get_restaurant_receipt_logo(uuid, uuid);
--   drop function if exists app.get_restaurant_receipt_logo(uuid, uuid);
--   drop function if exists public.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer);
--   drop function if exists app.set_restaurant_receipt_logo(uuid, uuid, uuid, text, boolean, integer);
--   drop policy if exists restaurant_logos_device_select on storage.objects;
--   drop policy if exists restaurant_logos_delete on storage.objects;
--   drop policy if exists restaurant_logos_update on storage.objects;
--   drop policy if exists restaurant_logos_insert on storage.objects;
--   drop policy if exists restaurant_logos_select on storage.objects;
--   drop function if exists app.device_can_read_restaurant_logo(text);
--   drop function if exists app.can_write_restaurant_logo(uuid, uuid);
--   drop function if exists app.can_read_restaurant_logo(uuid, uuid);
--   drop function if exists app.restaurant_logo_scope(text);
--   delete from storage.buckets where id = 'restaurant-logos';  -- only if empty
--   alter table public.restaurants
--     drop constraint restaurants_receipt_logo_enabled_requires_path,
--     drop constraint restaurants_receipt_logo_version_nonneg,
--     drop column receipt_logo_version, drop column receipt_logo_enabled,
--     drop column receipt_logo_path;
-- ============================================================================
