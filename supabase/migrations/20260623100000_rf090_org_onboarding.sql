-- ============================================================================
-- RF-090 — Self-serve organization signup + onboarding (M4, Platform/SaaS)
-- ============================================================================
-- A new authenticated Supabase principal provisions its OWN tenant: organization
-- + first restaurant + branch (+ optional default station) + the first
-- `org_owner` membership, fully isolated by organization_id (D-001/D-002/D-004).
--
-- WHY AN RPC: every tenant table denies direct INSERT to `authenticated`
-- (RF-059 `*_ins_deny ... with check(false)`), and a brand-new principal has no
-- `app_users` row yet, so `app.current_app_user_id()` is NULL and no membership
-- exists. Onboarding therefore runs as a SECURITY DEFINER RPC that derives the
-- caller from `auth.uid()` (never from input), bootstraps the app_user, and
-- creates the tenant atomically. The org owner is a MEMBERSHIP role, never a
-- global/platform role; `platform_admin` is structurally impossible here
-- (memberships.role CHECK excludes it; platform_admin_grants is untouched, D-026).
--
-- IDEMPOTENCY (Option A, approved): two nullable provenance columns on
-- `organizations` — `created_by_app_user_id` + `creation_request_id` — with a
-- partial unique index. Same caller + same `client_request_id` returns the
-- existing org (no duplicates); a retry with CONFLICTING org-level input fails
-- clearly. No separate idempotency table; no slug-only dedup.
-- ----------------------------------------------------------------------------

-- 1. Provenance / idempotency columns on organizations (nullable; existing rows
--    and non-self-serve orgs keep NULL and are unaffected).
alter table public.organizations
  add column created_by_app_user_id uuid references public.app_users (id) on delete restrict,
  add column creation_request_id    uuid;

comment on column public.organizations.created_by_app_user_id is
  'RF-090: the app_user who self-served this organization via app.create_organization (NULL for orgs not created through self-serve onboarding).';
comment on column public.organizations.creation_request_id is
  'RF-090: the client-supplied idempotency key for self-serve onboarding (NULL otherwise). Unique per (created_by_app_user_id, creation_request_id) so a retried signup returns the same org instead of creating a duplicate (D-022 spirit).';

-- partial unique index: one org per (creator, client_request_id) for self-serve rows
create unique index organizations_onboarding_idem_key
  on public.organizations (created_by_app_user_id, creation_request_id)
  where creation_request_id is not null;

-- ============================================================================
-- 2. app.create_organization_replay — the SINGLE idempotent-replay path
--    (RF090-B1). Used by BOTH the pre-check replay and the concurrent
--    unique_violation race replay so they cannot diverge: it conflict-checks
--    the reused client_request_id against the STORED org (name/slug/currency)
--    and returns the stored-slug payload. Internal only (not granted to
--    authenticated); called from within the SECURITY DEFINER RPC below.
-- ============================================================================
create or replace function app.create_organization_replay(
  p_org      public.organizations,
  p_org_name text,
  p_slug     text,
  p_currency text,
  p_app_user uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_rest       uuid;
  v_branch     uuid;
  v_membership uuid;
begin
  -- conflicting input on a reused key must fail clearly (never return the wrong
  -- tenant) — identical comparison for the pre-check AND the race path.
  if p_org.name <> btrim(p_org_name)
     or p_org.slug <> p_slug
     or p_org.default_currency <> p_currency then
    raise exception 'create_organization: client_request_id reused with different input' using errcode = '42501';
  end if;
  select r.id into v_rest   from public.restaurants r where r.organization_id = p_org.id order by r.created_at, r.id limit 1;
  select b.id into v_branch from public.branches    b where b.organization_id = p_org.id order by b.created_at, b.id limit 1;
  select m.id into v_membership from public.memberships m
    where m.organization_id = p_org.id and m.app_user_id = p_app_user and m.role = 'org_owner' limit 1;
  return jsonb_build_object(
    'ok', true, 'idempotent_replay', true,
    'organization_id', p_org.id, 'restaurant_id', v_rest, 'branch_id', v_branch,
    'membership_id', v_membership, 'app_user_id', p_app_user,
    'slug', p_org.slug);  -- the STORED slug, never the caller-provided one
end;
$$;

comment on function app.create_organization_replay(public.organizations, text, text, text, uuid) is
  'RF-090 internal helper (RF090-B1): the single idempotent-replay path for app.create_organization. Conflict-checks a reused client_request_id against the STORED organization (name/slug/currency) and returns the stored-slug replay payload. Shared by the pre-check and the concurrent unique_violation race so they cannot diverge. SECURITY DEFINER; not granted to authenticated (internal).';

revoke all on function app.create_organization_replay(public.organizations, text, text, text, uuid) from public;

-- ============================================================================
-- 3. app.create_organization — the self-serve onboarding RPC.
-- ============================================================================
create or replace function app.create_organization(
  p_client_request_id   uuid,
  p_organization_name   text,
  p_organization_slug   text,
  p_restaurant_name     text,
  p_branch_name         text,
  p_currency_code       text,
  p_timezone            text,
  p_default_station_name text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
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
$$;

comment on function app.create_organization(uuid, text, text, text, text, text, text, text) is
  'RF-090 (API_CONTRACT §4): self-serve organization onboarding. SECURITY DEFINER, search_path locked. Caller derived from auth.uid() ONLY (never input); bootstraps the app_user, then atomically creates organization + first restaurant + branch (+ optional default station) + first org_owner MEMBERSHIP + an organization.created audit event. Idempotent per (caller, client_request_id) via organizations.creation_request_id; conflicting reuse fails. Never accepts role/app_user_id/organization_id/platform input; never grants platform_admin (D-026); no shared accounts (D-004).';

-- least privilege: authenticated only; never anon; never relies on service_role.
revoke all on function app.create_organization(uuid, text, text, text, text, text, text, text) from public;
grant execute on function app.create_organization(uuid, text, text, text, text, text, text, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists app.create_organization(uuid, text, text, text, text, text, text, text);
--   drop function if exists app.create_organization_replay(public.organizations, text, text, text, uuid);
--   drop index if exists public.organizations_onboarding_idem_key;
--   alter table public.organizations drop column if exists creation_request_id;
--   alter table public.organizations drop column if exists created_by_app_user_id;
-- ============================================================================
