-- ============================================================================
-- ADMIN-126 (2/2) — SECURE PLATFORM SUPPORT ACCESS.
--
-- STATUS: COMPLETE AND TESTED, DELIBERATELY NOT YET APPLIED TO HOSTED.
--
-- The session machinery below is finished and proven (see
-- supabase/tests/platform_support_sessions_126_test.sql, 57 assertions). What
-- is NOT finished is the half that makes it useful: the tenant Dashboard reads
-- all of its data through SECURITY DEFINER RPCs, not through the RLS SELECT
-- policies this migration extends, and those RPCs gate on
-- app.actor_rank_in_scope — the SAME helper that gates writes. Granting it
-- would grant writes with it.
--
-- Making "Open Dashboard" actually show data therefore needs the tenant READ
-- gate split from the WRITE gate across 22 read-only RPCs (list_menu,
-- owner_report_range, list_staff, list_devices, list_tables, ...), leaving the
-- 39 writing RPCs on the existing gate. That is a change to tenant
-- authorization across the whole read surface and deserves its own reviewed
-- phase — shipping this half alone would produce a support session that shows
-- an empty Dashboard, which is the "UI-only fake read-only mode" the ticket
-- explicitly forbids.
--
-- Applying this file early is HARMLESS (every addition is inert without a live
-- support session, and no client starts one), but it buys nothing until that
-- split lands.
--
-- "Open Dashboard" without asking a restaurant owner for their password.
--
-- WHAT THIS IS NOT
--   * NOT a login bypass. No owner credential is read, reset, or minted.
--   * NOT impersonation. app.current_app_user_id() keeps resolving to the
--     PLATFORM ADMIN for the whole session, so every audit row, every
--     created_by and every actor stamp names the operator, never the owner.
--   * NOT a membership. No row is written to public.memberships, ever —
--     not permanently and not temporarily.
--
-- WHAT MAKES IT READ-ONLY, AND WHY THAT IS A PROPERTY RATHER THAN A PROMISE
-- -------------------------------------------------------------------------
-- Tenant authorization in this system splits cleanly in two, and this migration
-- only ever touches the read half:
--
--   READS   RLS SELECT policies gate on app.current_org_id() / app.has_scope().
--           38 policies use them; ALL 38 are FOR SELECT. No policy for INSERT,
--           UPDATE or DELETE references either, and no function that writes a
--           public table calls either. (Both facts are asserted by the pgTAP
--           companion to this file, so they cannot silently stop being true.)
--
--   WRITES  gate on app.actor_rank_in_scope() (51 of 62 mutating RPCs, plus
--           menu_guard/printer_guard), on a device session token, or on a PIN
--           session. All three are derived from a MEMBERSHIP or a paired
--           device. A support operator has no membership and no device, so
--           every one of them already returns 0 / no-session and refuses.
--
-- So this migration extends ONLY app.current_org_id() and app.has_scope(), and
-- leaves app.actor_rank_in_scope() and app.has_role_in_scope() untouched. The
-- support operator can therefore SEE the tenant and can change nothing — not
-- because buttons are hidden, but because the server has nothing to authorize
-- the write with. The single exception is app.create_organization, which
-- authorizes on a bare auth.uid() (a new user has no tenant yet); it is given
-- an explicit refusal below.
--
-- BOTH extensions are strictly ADDITIVE: with no active support session the two
-- functions evaluate exactly as before, which the companion tests assert
-- directly against a tenant principal.
--
-- THE HANDOFF
--   start    -> a 32-byte random token; only its SHA-256 hash is stored, the
--               plaintext is returned ONCE and never persisted.
--   exchange -> one-time, ~60s window, marks the token consumed. A replay,
--               an expired window, or an ended session all fail closed.
--   session  -> server-side TTL (15 minutes). Expiry is evaluated on every
--               read, so a client that keeps its tab open gains nothing.
--   end      -> explicit, and audited like the rest.
--
-- No credential, access token, refresh token or TOTP material is stored here.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The session record
-- ----------------------------------------------------------------------------
create table if not exists public.platform_support_sessions (
  id                          uuid primary key default extensions.gen_random_uuid(),
  platform_admin_app_user_id  uuid        not null references public.app_users(id) on delete restrict,
  target_organization_id      uuid        not null references public.organizations(id) on delete restrict,
  target_restaurant_id        uuid        null     references public.restaurants(id)   on delete restrict,
  reason                      text        not null,
  status                      text        not null default 'pending',
  expires_at                  timestamptz not null,
  created_at                  timestamptz not null default now(),
  ended_at                    timestamptz null,
  -- ONLY the hash. The plaintext handoff token is returned to the operator once
  -- and is never written down, so a database disclosure cannot be replayed into
  -- a tenant session.
  token_hash                  text        not null,
  token_consumed_at           timestamptz null,
  constraint platform_support_sessions_reason_present check (btrim(reason) <> ''),
  constraint platform_support_sessions_status_valid  check (status in ('pending', 'active', 'ended')),
  constraint platform_support_sessions_token_hash_unique unique (token_hash)
);

comment on table public.platform_support_sessions is
  'ADMIN-126 short-lived, audited, READ-ONLY platform support sessions. Stores a '
  'SHA-256 token hash only — never the plaintext token and never any credential. '
  'Grants no membership: the operator remains the actor throughout.';

create index if not exists platform_support_sessions_admin_active_idx
  on public.platform_support_sessions (platform_admin_app_user_id, status, expires_at desc);
create index if not exists platform_support_sessions_target_idx
  on public.platform_support_sessions (target_organization_id, created_at desc);

-- Platform plane, exactly like platform_admin_grants: RLS on and FORCED with NO
-- policy at all, so the tenant path is denied by default-deny rather than by a
-- predicate someone could widen later. No grants are issued to anon or
-- authenticated; the only way in is through the SECURITY DEFINER functions below.
alter table public.platform_support_sessions enable row level security;
alter table public.platform_support_sessions force row level security;
revoke all on table public.platform_support_sessions from public;
revoke all on table public.platform_support_sessions from anon;
revoke all on table public.platform_support_sessions from authenticated;

-- ----------------------------------------------------------------------------
-- 2. Resolver — the caller's live support session, if any
-- ----------------------------------------------------------------------------
create or replace function app.current_support_session()
  returns uuid
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- ACTIVE means: exchanged (token consumed), not ended, and not past its TTL.
  -- Expiry is evaluated here on EVERY call rather than by a sweeper, so a stale
  -- row can never behave as if it were live.
  select s.id
    from public.platform_support_sessions s
   where s.platform_admin_app_user_id = app.current_app_user_id()
     and s.status            = 'active'
     and s.token_consumed_at is not null
     and s.expires_at        > now()
   order by s.expires_at desc
   limit 1
$$;

comment on function app.current_support_session() is
  'ADMIN-126: the calling platform admin''s live support session, or NULL. '
  'Consulted only by the tenant READ helpers (app.current_org_id / app.has_scope) '
  'and by app.create_organization''s read-only refusal.';

-- ----------------------------------------------------------------------------
-- 3. The two READ helpers, extended additively
-- ----------------------------------------------------------------------------
create or replace function app.current_org_id()
  returns uuid
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- A MEMBERSHIP still wins, and is evaluated first and unchanged: with no
  -- support session this function returns exactly what it returned before.
  select coalesce(
    (
      select m.organization_id
      from public.memberships m
      where m.app_user_id = app.current_app_user_id()
        and m.organization_id = nullif(current_setting('app.current_organization_id', true), '')::uuid
        and m.status = 'active'
        and m.deleted_at is null
      limit 1
    ),
    -- ADMIN-126: a live support session resolves the SAME requested org, and
    -- only that org. It cannot widen a tenant's own scope — a caller with a
    -- membership never reaches this branch, and a caller without one is a
    -- platform operator who has been handed a session for this tenant.
    (
      select s.target_organization_id
      from public.platform_support_sessions s
      where s.id = app.current_support_session()
        and s.target_organization_id = nullif(current_setting('app.current_organization_id', true), '')::uuid
      limit 1
    )
  )
$$;

create or replace function app.has_scope(target_org uuid, target_restaurant uuid, target_branch uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.app_user_id = app.current_app_user_id()
      and m.organization_id = app.current_org_id()
      and m.organization_id = target_org
      and m.status = 'active'
      and m.deleted_at is null
      and (m.restaurant_id is null or target_restaurant is null or m.restaurant_id = target_restaurant)
      and (m.branch_id     is null or target_branch     is null or m.branch_id     = target_branch)
  )
  -- ADMIN-126: read scope for a live support session, bounded to its target and
  -- (when the session names one) to its target restaurant. This is the READ
  -- half only — app.has_role_in_scope and app.actor_rank_in_scope are
  -- deliberately NOT extended, which is what keeps the session read-only.
  or exists (
    select 1
    from public.platform_support_sessions s
    where s.id = app.current_support_session()
      and s.target_organization_id = target_org
      and s.target_organization_id = app.current_org_id()
      and (s.target_restaurant_id is null
           or target_restaurant is null
           or s.target_restaurant_id = target_restaurant)
  )
$$;

-- ----------------------------------------------------------------------------
-- 4. Start — mint a one-time handoff
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_start_support_session(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_reason          text default null
)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor    uuid;
  v_token    text;
  v_id       uuid;
  v_org      public.organizations%rowtype;
  v_rest     public.restaurants%rowtype;
  v_expires  timestamptz;
begin
  v_actor := app.platform_admin_guard(p_reason);

  select * into v_org from public.organizations
   where id = p_organization_id and deleted_at is null;
  if not found then
    -- Same code as a denial: the console must not become a way to discover
    -- which organization ids exist.
    raise exception 'platform support: no such organization, or access denied'
      using errcode = '42501';
  end if;

  if p_restaurant_id is not null then
    select * into v_rest from public.restaurants
     where id = p_restaurant_id
       and organization_id = p_organization_id
       and deleted_at is null;
    if not found then
      raise exception 'platform support: no such restaurant in that organization'
        using errcode = '42501';
    end if;
  end if;

  v_expires := now() + (app.platform_support_ttl_minutes() || ' minutes')::interval;
  -- 32 bytes of CSPRNG. Only the hash is stored; this plaintext is returned to
  -- the operator exactly once and then exists nowhere on the server.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.platform_support_sessions
    (platform_admin_app_user_id, target_organization_id, target_restaurant_id,
     reason, status, expires_at, token_hash)
  values
    (v_actor, p_organization_id, p_restaurant_id, btrim(p_reason), 'pending', v_expires,
     encode(extensions.digest(v_token, 'sha256'), 'hex'))
  returning id into v_id;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, p_organization_id, 'platform.support.start', btrim(p_reason),
     jsonb_build_object('support_session_id', v_id,
                        'target_restaurant_id', p_restaurant_id,
                        'expires_at', v_expires));

  return jsonb_build_object(
    'ok', true,
    'support_session_id', v_id,
    -- Returned ONCE. There is no read path that can produce it again.
    'handoff_token', v_token,
    'exchange_expires_at', now() + (app.platform_support_exchange_seconds() || ' seconds')::interval,
    'expires_at', v_expires,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Exchange — one time, then never again
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_exchange(p_token text)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_row   public.platform_support_sessions%rowtype;
  v_org   public.organizations%rowtype;
  v_rest  public.restaurants%rowtype;
begin
  if v_actor is null then
    raise exception 'platform support: authentication required' using errcode = '42501';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'platform support: a handoff token is required' using errcode = '42501';
  end if;

  -- The token is matched by HASH, and the row is locked so two concurrent
  -- exchanges of the same token cannot both win.
  select * into v_row
    from public.platform_support_sessions
   where token_hash = encode(extensions.digest(btrim(p_token), 'sha256'), 'hex')
   for update;

  -- Every failure below is the SAME error: an attacker must not be able to tell
  -- "wrong token" from "already used" from "expired".
  if not found
     or v_row.platform_admin_app_user_id <> v_actor
     or v_row.status <> 'pending'
     or v_row.token_consumed_at is not null
     or v_row.expires_at <= now()
     or v_row.created_at + (app.platform_support_exchange_seconds() || ' seconds')::interval < now()
  then
    raise exception 'platform support: this handoff is not valid' using errcode = '42501';
  end if;

  -- A support session additionally requires the operator to still be a platform
  -- admin at aal2 AT EXCHANGE TIME — a grant revoked between start and exchange
  -- must close the door.
  if not app.is_platform_admin() or app.current_auth_assurance_level() is distinct from 'aal2' then
    raise exception 'platform support: this handoff is not valid' using errcode = '42501';
  end if;

  update public.platform_support_sessions
     set status = 'active', token_consumed_at = now()
   where id = v_row.id;

  select * into v_org  from public.organizations where id = v_row.target_organization_id;
  if v_row.target_restaurant_id is not null then
    select * into v_rest from public.restaurants where id = v_row.target_restaurant_id;
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, v_row.target_organization_id, 'platform.support.exchange', v_row.reason,
     jsonb_build_object('support_session_id', v_row.id));

  return jsonb_build_object(
    'ok', true,
    'support_session_id', v_row.id,
    'reason', v_row.reason,
    'expires_at', v_row.expires_at,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Status + end
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_current()
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_row  public.platform_support_sessions%rowtype;
  v_org  public.organizations%rowtype;
  v_rest public.restaurants%rowtype;
begin
  select * into v_row from public.platform_support_sessions
   where id = app.current_support_session();
  if not found then
    -- Not an error: the ordinary tenant answer is "no support session".
    return jsonb_build_object('ok', true, 'active', false, 'server_ts', now());
  end if;
  select * into v_org from public.organizations where id = v_row.target_organization_id;
  if v_row.target_restaurant_id is not null then
    select * into v_rest from public.restaurants where id = v_row.target_restaurant_id;
  end if;
  return jsonb_build_object(
    'ok', true,
    'active', true,
    'support_session_id', v_row.id,
    'reason', v_row.reason,
    'expires_at', v_row.expires_at,
    'read_only', true,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

create or replace function app.platform_support_end(p_support_session_id uuid default null)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_id    uuid := coalesce(p_support_session_id, app.current_support_session());
  v_row   public.platform_support_sessions%rowtype;
begin
  if v_actor is null then
    raise exception 'platform support: authentication required' using errcode = '42501';
  end if;
  if v_id is null then
    return jsonb_build_object('ok', true, 'ended', false, 'server_ts', now());
  end if;

  -- Only the operator who started it may end it.
  update public.platform_support_sessions
     set status = 'ended', ended_at = now()
   where id = v_id
     and platform_admin_app_user_id = v_actor
     and status <> 'ended'
  returning * into v_row;

  if not found then
    return jsonb_build_object('ok', true, 'ended', false, 'server_ts', now());
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, v_row.target_organization_id, 'platform.support.end', v_row.reason,
     jsonb_build_object('support_session_id', v_row.id));

  return jsonb_build_object('ok', true, 'ended', true,
                            'support_session_id', v_row.id, 'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. Tunables, in one place
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_ttl_minutes()
  returns integer language sql immutable set search_path = '' as $$ select 15 $$;

create or replace function app.platform_support_exchange_seconds()
  returns integer language sql immutable set search_path = '' as $$ select 60 $$;

-- ----------------------------------------------------------------------------
-- 8. Onboarding refuses to run under a support session
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.create_organization(p_client_request_id uuid, p_organization_name text, p_organization_slug text, p_restaurant_name text, p_branch_name text, p_currency_code text, p_timezone text, p_default_station_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_auth        uuid := auth.uid();
  v_email       text;
  v_app_user    uuid;
  v_currency    text := upper(btrim(coalesce(p_currency_code, '')));
  v_slug        text := lower(btrim(coalesce(p_organization_slug, '')));
  v_station     text := nullif(btrim(coalesce(p_default_station_name, '')), '');
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_station_id  uuid;
  v_membership  uuid;
  v_existing    public.organizations%rowtype;
begin
  -- ADMIN-126 (a0): SUPPORT MODE IS READ-ONLY.
  -- Every other authenticated write path in the system is gated on a
  -- membership, a device token or a PIN session, and a support session grants
  -- none of those — so they refuse a support operator without any change. This
  -- one does not: onboarding deliberately authorizes on a bare auth.uid()
  -- because a brand-new user has no tenant yet. It is therefore the only place
  -- that has to say no explicitly.
  if app.current_support_session() is not null then
    raise exception 'create_organization: platform support mode is read-only'
      using errcode = '42501';
  end if;

  -- (a) authentication: the caller MUST be a Supabase Auth principal.
  if v_auth is null then
    raise exception 'create_organization: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_organization: client_request_id is required' using errcode = '42501';
  end if;

  -- (b) input validation (no money math; integer-free).
  if length(btrim(coalesce(p_organization_name, ''))) = 0 then
    raise exception 'create_organization: organization_name is required' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_restaurant_name, ''))) = 0 then
    raise exception 'create_organization: restaurant_name is required' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_branch_name, ''))) = 0 then
    raise exception 'create_organization: branch_name is required' using errcode = '42501';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'create_organization: currency_code must match ^[A-Z]{3}$ (got %)', p_currency_code using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'create_organization: organization_slug must match ^[a-z0-9]+(-[a-z0-9]+)*$ (got %)', p_organization_slug using errcode = '42501';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'create_organization: timezone % is not a valid IANA timezone', p_timezone using errcode = '42501';
  end if;

  -- (c) bootstrap the caller's app_user (derive ONLY from auth.uid(); never input).
  select au.id into v_app_user
  from public.app_users au
  where au.auth_user_id = v_auth;

  if v_app_user is null then
    v_email := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
    if length(v_email) = 0 then
      raise exception 'create_organization: an email claim is required to provision an account' using errcode = '42501';
    end if;
    begin
      insert into public.app_users (email, auth_user_id)
      values (v_email, v_auth)
      returning id into v_app_user;
    exception when unique_violation then
      -- race or pre-existing email: re-resolve by auth principal; if the email
      -- belongs to an unlinked/other account, fail clearly (no shared accounts).
      select au.id into v_app_user from public.app_users au where au.auth_user_id = v_auth;
      if v_app_user is null then
        raise exception 'create_organization: an account already exists for this email' using errcode = '42501';
      end if;
    end;
  end if;

  -- (d) idempotency replay: same caller + same client_request_id.
  select * into v_existing
  from public.organizations o
  where o.created_by_app_user_id = v_app_user
    and o.creation_request_id    = p_client_request_id;

  if found then
    return app.create_organization_replay(v_existing, p_organization_name, v_slug, v_currency, v_app_user);
  end if;

  -- (e) create the organization (provenance + idem key recorded).
  begin
    insert into public.organizations (name, slug, default_currency, created_by_app_user_id, creation_request_id)
    values (btrim(p_organization_name), v_slug, v_currency, v_app_user, p_client_request_id)
    returning id into v_org;
  exception when unique_violation then
    -- A concurrent call for the SAME (caller, request_id) won the idem index.
    -- RF090-B1: re-load the FULL existing org and replay through the SAME helper
    -- as the pre-check — it runs the identical conflict comparison (so a racing
    -- conflicting payload still fails) and returns the STORED slug.
    select * into v_existing
    from public.organizations o
    where o.created_by_app_user_id = v_app_user and o.creation_request_id = p_client_request_id;
    if found then
      return app.create_organization_replay(v_existing, p_organization_name, v_slug, v_currency, v_app_user);
    end if;
    -- otherwise it was a global slug collision with a DIFFERENT org.
    raise exception 'create_organization: organization slug "%" is already taken', v_slug using errcode = '42501';
  end;

  -- (f) first restaurant + branch (+ optional default station).
  insert into public.restaurants (organization_id, name, timezone)
  values (v_org, btrim(p_restaurant_name), p_timezone)
  returning id into v_rest;

  insert into public.branches (organization_id, restaurant_id, name, timezone)
  values (v_org, v_rest, btrim(p_branch_name), p_timezone)
  returning id into v_branch;

  if v_station is not null then
    insert into public.stations (organization_id, restaurant_id, branch_id, name)
    values (v_org, v_rest, v_branch, v_station)
    returning id into v_station_id;
  end if;

  -- (g) first membership: org_owner (membership-scoped role, NOT a global role).
  --     restaurant_id/branch_id NULL => org-wide. Role is hardcoded; no role,
  --     app_user_id, organization_id, or platform input is ever accepted.
  insert into public.memberships (app_user_id, organization_id, restaurant_id, branch_id, role, status)
  values (v_app_user, v_org, null, null, 'org_owner', 'active')
  returning id into v_membership;

  -- (h) append-only audit event (D-013). Actor is the app_user (no device/PIN yet).
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
  values
    (v_org, v_rest, v_branch, v_app_user, null, 'organization.created', null, null,
     jsonb_build_object(
       'client_request_id', p_client_request_id,
       'organization_name', btrim(p_organization_name),
       'slug', v_slug,
       'default_currency', v_currency,
       'restaurant_name', btrim(p_restaurant_name),
       'branch_name', btrim(p_branch_name),
       'default_station_name', v_station,
       'owner_membership_role', 'org_owner'));

  return jsonb_build_object(
    'ok', true, 'idempotent_replay', false,
    'organization_id', v_org, 'restaurant_id', v_rest, 'branch_id', v_branch,
    'station_id', v_station_id, 'membership_id', v_membership,
    'app_user_id', v_app_user, 'slug', v_slug);
end;
$function$;


-- ----------------------------------------------------------------------------
-- 9. Thin public SECURITY INVOKER wrappers
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_start_support_session(
  p_organization_id uuid, p_restaurant_id uuid default null, p_reason text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_start_support_session(p_organization_id, p_restaurant_id, p_reason); $$;

create or replace function public.platform_support_exchange(p_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_support_exchange(p_token); $$;

create or replace function public.platform_support_current()
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_support_current(); $$;

create or replace function public.platform_support_end(p_support_session_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_support_end(p_support_session_id); $$;

-- ----------------------------------------------------------------------------
-- 10. Grants — both layers to authenticated; PUBLIC *and* anon revoked
-- ----------------------------------------------------------------------------
revoke all on function app.platform_admin_start_support_session(uuid, uuid, text) from public;
revoke all on function app.platform_admin_start_support_session(uuid, uuid, text) from anon;
revoke all on function app.platform_support_exchange(text)                        from public;
revoke all on function app.platform_support_exchange(text)                        from anon;
revoke all on function app.platform_support_current()                             from public;
revoke all on function app.platform_support_current()                             from anon;
revoke all on function app.platform_support_end(uuid)                             from public;
revoke all on function app.platform_support_end(uuid)                             from anon;
revoke all on function app.current_support_session()                              from public;
revoke all on function app.current_support_session()                              from anon;
revoke all on function app.platform_support_ttl_minutes()                         from public;
revoke all on function app.platform_support_ttl_minutes()                         from anon;
revoke all on function app.platform_support_exchange_seconds()                    from public;
revoke all on function app.platform_support_exchange_seconds()                    from anon;

revoke all on function public.platform_admin_start_support_session(uuid, uuid, text) from public;
revoke all on function public.platform_admin_start_support_session(uuid, uuid, text) from anon;
revoke all on function public.platform_support_exchange(text)                        from public;
revoke all on function public.platform_support_exchange(text)                        from anon;
revoke all on function public.platform_support_current()                             from public;
revoke all on function public.platform_support_current()                             from anon;
revoke all on function public.platform_support_end(uuid)                             from public;
revoke all on function public.platform_support_end(uuid)                             from anon;

grant execute on function app.platform_admin_start_support_session(uuid, uuid, text) to authenticated;
grant execute on function app.platform_support_exchange(text)                        to authenticated;
grant execute on function app.platform_support_current()                             to authenticated;
grant execute on function app.platform_support_end(uuid)                             to authenticated;
grant execute on function public.platform_admin_start_support_session(uuid, uuid, text) to authenticated;
grant execute on function public.platform_support_exchange(text)                        to authenticated;
grant execute on function public.platform_support_current()                             to authenticated;
grant execute on function public.platform_support_end(uuid)                             to authenticated;

-- app.current_support_session is consulted by the read helpers, which are
-- SECURITY DEFINER, so `authenticated` never needs to call it itself.

comment on function app.platform_admin_start_support_session(uuid, uuid, text) is
  'ADMIN-126: mints a one-time handoff for a READ-ONLY support session. Returns '
  'the plaintext token ONCE; only its SHA-256 hash is stored. Requires an active '
  'platform grant + aal2 + a typed reason; audited as platform.support.start.';
comment on function app.platform_support_exchange(text) is
  'ADMIN-126: exchanges a handoff token exactly once, inside a 60s window, for an '
  'active read-only support session. Replay, expiry, a revoked grant and a lost '
  'aal2 all fail with the same 42501 so the failure mode leaks nothing.';
