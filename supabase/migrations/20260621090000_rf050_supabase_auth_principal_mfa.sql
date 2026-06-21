-- ============================================================================
-- RF-050 — Supabase Auth principal binding + interim MFA-assurance guards
-- ============================================================================
-- Binds the Supabase Auth principal (auth.uid()/JWT) to the existing identity
-- plane and adds an INTERIM, role-driven MFA-assurance enforcement mechanism.
-- Builds on RF-015 (app_users / memberships / employee_profiles + the interim
-- GUC resolvers). Additive and FORWARD-ONLY: it NEVER edits a prior migration.
--
-- WHAT THIS DOES
--   1. Links app_users to auth.users via a NEW nullable, UNIQUE auth_user_id
--      (one Supabase principal -> at most one app_user). app_users.id stays the
--      app-domain user id (NOT repurposed to auth.uid()); email is preserved.
--   2. Supersedes the USER SOURCE of app.current_app_user_id(): resolve the JWT
--      principal first (auth.uid() -> app_users.auth_user_id -> app_users.id),
--      then FALL BACK to the interim GUC. The GUC fallback is a TEST-ONLY /
--      interim seam kept so the RF-014/015/016/017/019 GUC suites stay green; it
--      is tightened to JWT-only at RF-059.
--   3. Adds interim MFA-assurance helpers + a guard that DENIES a privileged
--      membership operation (SQLSTATE 42501) when the session has not reached
--      assurance level aal2.
--
-- DECISIONS / OPEN QUESTIONS
--   * D-004  per-person identity, no shared accounts (auth_user_id is UNIQUE).
--   * D-005  the six identity concepts stay distinct (app_user vs auth principal).
--   * D-006  MFA is MANDATORY for privileged roles — the REQUIREMENT is frozen;
--            only the method + the exact role-to-MFA mapping are pending Q-008.
--   * D-011  no service-role assumptions; helpers run for `authenticated` only.
--   * D-027  Q-008 is Accepted Open: ship a SAFE INTERIM (generic aal2 + a
--            configurable, ASSUMPTION-marked privileged-role set) with NO
--            irreversible schema/contract assumption. The final MFA provider/
--            method and the exact role-to-MFA mapping are NOT frozen here.
--   * Q-008  ASSUMPTION (INTERIM, changeable without a migration rewrite):
--            org_owner / restaurant_owner / manager require aal2.
--   * RISK R-003 (CRITICAL): this changes a tenant-isolation resolver body; the
--            coalesce(auth.uid(), GUC) shape keeps every existing RLS suite green
--            while adding the JWT path (human RLS sign-off still applies).
--
-- OUT OF SCOPE (other tickets): PIN sessions / lockout (RF-051); business or
--   privileged RPC bodies (RF-052/053/054/055); sync (RF-056/057); the full
--   per-command role matrix + JWT-only tightening (RF-059); platform-admin
--   enforcement (RF-060); any UI / client Supabase wiring. No business tables.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Link app_users -> auth.users (identity binding).
--    nullable: PIN-only / local staff may have no email/password principal yet.
--    unique  : one Supabase auth principal maps to AT MOST one app_user (D-004).
--    app_users.id is NOT repurposed; email is preserved (RF-015). on delete
--    restrict matches the project-wide FK convention (no silent identity unlink).
-- ----------------------------------------------------------------------------
alter table public.app_users
  add column auth_user_id uuid references auth.users (id) on delete restrict;

comment on column public.app_users.auth_user_id is
  'RF-050: the Supabase Auth principal (auth.users.id) for this app_user, or NULL for PIN-only/local staff with no email-password account yet. UNIQUE (one principal -> one app_user; D-004 no shared accounts). app_users.id remains the app-domain id; it is NOT auth.uid().';

-- Partial-UNIQUE: multiple NULLs are allowed so PIN-only staff are not blocked.
create unique index app_users_auth_user_id_key
  on public.app_users (auth_user_id)
  where auth_user_id is not null;

-- ----------------------------------------------------------------------------
-- 2. Supersede the USER SOURCE of app.current_app_user_id() (RF-015 anticipated
--    this at RF-050). BRANCH on auth.uid(): when a JWT principal EXISTS, resolve
--    ONLY via app_users.auth_user_id — an authenticated-but-UNLINKED principal
--    returns NULL (FAIL CLOSED), and NEVER falls back to the GUC (RF050-B1). The
--    interim GUC fallback applies ONLY when there is NO JWT principal (the
--    test/interim path). It reads public.app_users => SECURITY DEFINER + locked,
--    empty search_path so the lookup bypasses app_users' FORCE RLS (no recursion
--    through the app_users_self policy) and the path cannot be hijacked. STABLE,
--    read-only, takes no caller identity as an argument.
--    ASSUMPTION (same as the RF-015 resolvers app.current_org_id()/has_scope()):
--    the function owner is the migration runner, a superuser/BYPASSRLS role, so
--    the app_users read bypasses FORCE RLS. If these functions were ever owned by
--    a non-privileged role the read would recurse — this is the established
--    RF-015 pattern, not a new dependency.
-- ----------------------------------------------------------------------------
create or replace function app.current_app_user_id()
  returns uuid
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- RF050-B1: branch on the presence of a JWT principal. If auth.uid() exists,
  -- resolve ONLY via app_users.auth_user_id. A JWT principal with no linked
  -- app_user => NULL (deny-by-default): an authenticated-but-unlinked principal
  -- feeds tenant RLS and MUST fail closed, NOT fall back to the GUC. The GUC
  -- fallback is used ONLY when there is NO JWT principal (test/interim path).
  -- RF-059 will tighten this further (remove the GUC fallback entirely).
  select case
    when auth.uid() is not null then (
      select au.id
      from public.app_users au
      where au.auth_user_id = auth.uid()
      limit 1
    )
    else nullif(current_setting('app.current_app_user_id', true), '')::uuid
  end
$$;

comment on function app.current_app_user_id() is
  'RF-050: current app_user id. BRANCHES on auth.uid(): a JWT principal resolves ONLY via app_users.auth_user_id (present-but-UNLINKED => NULL, fail closed — RF050-B1, NEVER falls back to the GUC); the INTERIM GUC app.current_app_user_id is used ONLY when no JWT principal exists (test/interim path; keeps the RF-014/015/016/017/019 GUC suites green). Tightened to JWT-only at RF-059. SECURITY DEFINER (reads app_users; bypasses FORCE RLS, no recursion). Superseded-from RF-015.';

revoke all on function app.current_app_user_id() from public;
grant execute on function app.current_app_user_id() to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Interim MFA-assurance helpers (Q-008 Accepted Open; D-006 requirement
--    frozen, method pending). Enforcement keys on Supabase's GENERIC assurance
--    level (aal2), independent of which factor (TOTP/SMS/...) produced it, so the
--    final method stays unfrozen (D-027).
-- ----------------------------------------------------------------------------

-- 3a. The session's assurance level from the request JWT claims, or NULL when no
--     JWT/claim is present (e.g. the interim GUC test path). Malformed claims =>
--     NULL (guarded). GUC-only; no table read => no SECURITY DEFINER needed.
create or replace function app.current_auth_assurance_level()
  returns text
  language plpgsql
  stable
  set search_path = ''
as $$
declare
  raw_claims text := nullif(current_setting('request.jwt.claims', true), '');
  aal_value  text;
begin
  -- Read the assurance level ONLY from the VERIFIED request JWT claims. There is
  -- deliberately NO individual-claim GUC fallback: the interim GUC identity path
  -- carries no verified assurance, so it returns NULL => privileged principals on
  -- the GUC path FAIL CLOSED (they cannot reach aal2 without a real Supabase Auth
  -- JWT). This avoids trusting a client/session-settable, unverified GUC.
  if raw_claims is null then
    return null;
  end if;
  begin
    aal_value := (raw_claims::jsonb) ->> 'aal';
  exception when others then
    aal_value := null;  -- malformed claims JSON => treat as no assurance
  end;
  return nullif(aal_value, '');
end;
$$;

comment on function app.current_auth_assurance_level() is
  'RF-050: the Supabase Auth assurance level (aal1/aal2) read ONLY from the verified request.jwt.claims; NULL if absent/malformed (fail-closed; the interim GUC identity path has no verified assurance). Generic per Q-008 (factor-agnostic).';

-- 3b. Does the current principal hold a privileged membership in the current org
--     that requires MFA? The ASSUMPTION/Q-008 role set is centralized here so it
--     changes in ONE place without a migration rewrite. Reads memberships =>
--     SECURITY DEFINER + locked search_path (same rationale as app.current_org_id()).
create or replace function app.current_membership_requires_mfa()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- ASSUMPTION / Q-008 (INTERIM, NOT frozen): org_owner, restaurant_owner and
  -- manager require MFA. The final role-to-MFA mapping is pending Q-008 (D-006).
  -- FAIL-CLOSED on a missing org context: when no org is selected
  -- (app.current_org_id() IS NULL) we cannot confirm the principal is
  -- non-privileged for a specific org, so ANY active privileged membership counts
  -- and the guard then demands aal2. When an org IS selected (the normal case)
  -- the check is org-scoped EXACTLY as specified ("privileged in the current org").
  select exists (
    select 1
    from public.memberships m
    where m.app_user_id = app.current_app_user_id()
      and m.status = 'active'
      and m.deleted_at is null
      and m.role in ('org_owner', 'restaurant_owner', 'manager')  -- ASSUMPTION / Q-008
      and (app.current_org_id() is null or m.organization_id = app.current_org_id())
  )
$$;

comment on function app.current_membership_requires_mfa() is
  'RF-050 (ASSUMPTION/Q-008, INTERIM): true iff the current principal holds an active org_owner/restaurant_owner/manager membership in the current org; FAIL-CLOSED when no org is selected (any active privileged membership counts). The role set is centralized here, changeable without a migration rewrite; the final mapping is pending Q-008 (D-006). SECURITY DEFINER (membership lookup only).';

-- 3c. Is the session's assurance sufficient? Non-privileged => always true;
--     privileged => requires aal2. Invoker (orchestrates the helpers above).
create or replace function app.has_required_assurance()
  returns boolean
  language sql
  stable
  set search_path = ''
as $$
  select case
           when not app.current_membership_requires_mfa() then true
           when app.current_auth_assurance_level() = 'aal2' then true
           else false
         end
$$;

comment on function app.has_required_assurance() is
  'RF-050: true unless the current principal holds a privileged (ASSUMPTION/Q-008) membership in the current org without reaching assurance level aal2. The unit of MFA enforcement reused by future privileged RPCs (RF-052/053/055).';

-- 3d. The GUARD future privileged RPCs call FIRST. Raises 42501
--     (insufficient_privilege, matching RLS WITH CHECK denials) when a privileged
--     membership lacks aal2; returns true otherwise. No business RPC ships in
--     RF-050 — the guard is testable standalone. Invoker (orchestration only).
create or replace function app.require_mfa_for_privileged()
  returns boolean
  language plpgsql
  stable
  set search_path = ''
as $$
begin
  if not app.has_required_assurance() then
    raise exception
      'privileged operation requires multi-factor authentication (assurance level aal2)'
      using errcode = '42501';  -- insufficient_privilege
  end if;
  return true;
end;
$$;

comment on function app.require_mfa_for_privileged() is
  'RF-050 guard: raises SQLSTATE 42501 when the current principal holds a privileged (ASSUMPTION/Q-008) membership in the current org and the session has not reached assurance aal2; else returns true. RF-052/053/055 privileged RPCs will call this before mutating. Q-008 Accepted Open / D-006 / D-027.';

-- ----------------------------------------------------------------------------
-- 4. Helper grants: least privilege, authenticated only (never anon/service_role).
-- ----------------------------------------------------------------------------
revoke all on function app.current_auth_assurance_level()    from public;
revoke all on function app.current_membership_requires_mfa() from public;
revoke all on function app.has_required_assurance()          from public;
revoke all on function app.require_mfa_for_privileged()      from public;
grant execute on function app.current_auth_assurance_level()    to authenticated;
grant execute on function app.current_membership_requires_mfa() to authenticated;
grant execute on function app.has_required_assurance()          to authenticated;
grant execute on function app.require_mfa_for_privileged()      to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. To fully undo by hand, in reverse-dependency order:
-- ----------------------------------------------------------------------------
-- drop function if exists app.require_mfa_for_privileged();
-- drop function if exists app.has_required_assurance();
-- drop function if exists app.current_membership_requires_mfa();
-- drop function if exists app.current_auth_assurance_level();
-- -- restore the RF-015 GUC-only user resolver (no SECURITY DEFINER):
-- create or replace function app.current_app_user_id() returns uuid language sql stable
--   set search_path = '' as $$ select nullif(current_setting('app.current_app_user_id', true), '')::uuid $$;
-- drop index if exists public.app_users_auth_user_id_key;
-- alter table public.app_users drop column if exists auth_user_id;
-- ============================================================================
