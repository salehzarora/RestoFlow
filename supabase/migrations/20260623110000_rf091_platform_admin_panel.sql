-- ============================================================================
-- RF-091 — Platform admin panel (isolated, audited): read-only overview RPCs
-- ============================================================================
-- Extends the RF-059 platform plane (app.is_platform_admin / platform_admin_grants
-- / platform_admin_audit_events) with a small, READ-ONLY platform overview surface
-- for a platform admin. Every RPC: requires an authenticated principal, an ACTIVE
-- platform_admin grant (NOT a tenant membership — D-026), MFA/aal2 (RF-050), and a
-- non-empty reason; writes a reason-tagged platform_admin_audit_events row; and
-- returns only narrow summary fields. NO tenant mutation, NO impersonation, NO
-- generic cross-tenant `select *`, NO grant/revoke, NO new tables (D-011/12/13).
--
-- MFA NOTE (Q-008): the pre-existing app.platform_admin_list_organizations (RF-059)
-- is intentionally NOT retrofitted with the MFA gate here — its RF-059 test calls it
-- without an aal2 claim, so retrofitting would be broad unrelated churn. The NEW
-- RF-091 RPCs are aal2-gated; closing that inconsistency on the older RPC is a
-- Q-008/hardening follow-up (see API_CONTRACT §4.16).
-- ----------------------------------------------------------------------------

-- 1. Internal gate: authenticated + active platform grant + MFA(aal2) + reason.
--    Returns the platform-admin actor's app_user id. Internal only (not granted
--    to authenticated); called from within the SECURITY DEFINER RPCs below.
create or replace function app.platform_admin_guard(p_reason text)
  returns uuid
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
begin
  v_actor := app.current_app_user_id();
  if v_actor is null then
    raise exception 'platform admin: no authenticated principal' using errcode = '42501';
  end if;
  -- platform gate: a tenant membership (even org_owner) can NEVER satisfy this
  -- (is_platform_admin reads ONLY platform_admin_grants — D-026, T-008).
  if not app.is_platform_admin() then
    raise exception 'platform admin: caller is not an active platform admin' using errcode = '42501';
  end if;
  -- privileged platform access requires MFA/aal2 (RF-050; Q-008). We check the
  -- VERIFIED assurance level directly: app.require_mfa_for_privileged() is
  -- MEMBERSHIP-scoped (it only demands aal2 when the caller holds a privileged
  -- tenant membership) and a platform admin holds NO membership, so it would not
  -- gate the platform plane. app.current_auth_assurance_level() reads the aal
  -- ONLY from the verified JWT (NULL => no JWT => fail-closed), so requiring
  -- exactly 'aal2' here always enforces MFA for platform access.
  if app.current_auth_assurance_level() is distinct from 'aal2' then
    raise exception 'platform admin: multi-factor authentication (assurance level aal2) is required'
      using errcode = '42501';  -- insufficient_privilege
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'platform admin: a non-empty reason is required (access is reason-tagged)' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

comment on function app.platform_admin_guard(text) is
  'RF-091 internal gate: requires an authenticated principal + ACTIVE platform_admin grant (D-026) + MFA aal2 (RF-050) + a non-empty reason; returns the platform-admin actor app_user id. SECURITY DEFINER; not granted to authenticated (called only from the RF-091 platform RPCs).';

revoke all on function app.platform_admin_guard(text) from public;

-- ============================================================================
-- 2. platform_admin_organization_overview — platform-wide org summary + counts.
-- ============================================================================
create or replace function app.platform_admin_organization_overview(p_reason text)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_rows  jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  insert into public.platform_admin_audit_events (actor_app_user_id, target_organization_id, action, reason, details)
    values (v_actor, null, 'platform.organizations.overview', btrim(p_reason),
            jsonb_build_object('scope', 'all_organizations'));

  -- narrow per-org summary (NOT a generic select *); counts via scalar subqueries.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', o.id,
             'name', o.name,
             'status', o.status,
             'created_by_app_user_id', o.created_by_app_user_id,
             'creation_request_id', o.creation_request_id,
             'restaurants_count', (select count(*) from public.restaurants r where r.organization_id = o.id and r.deleted_at is null),
             'branches_count',    (select count(*) from public.branches    b where b.organization_id = o.id and b.deleted_at is null),
             'active_memberships_count', (select count(*) from public.memberships m where m.organization_id = o.id and m.status = 'active')
           ) order by o.created_at, o.id), '[]'::jsonb)
    into v_rows
    from public.organizations o
    where o.deleted_at is null;

  return jsonb_build_object('ok', true, 'organizations', v_rows, 'server_ts', now());
end;
$$;

comment on function app.platform_admin_organization_overview(text) is
  'RF-091: read-only platform-wide organization overview (id/name/status + onboarding provenance + restaurant/branch/active-membership counts). Platform-admin + MFA + reason gated; audited (platform.organizations.overview). No tenant mutation/impersonation.';

revoke all on function app.platform_admin_organization_overview(text) from public;
grant execute on function app.platform_admin_organization_overview(text) to authenticated;

-- ============================================================================
-- 3. platform_admin_get_organization — one org's detail + restaurant/branch list.
-- ============================================================================
create or replace function app.platform_admin_get_organization(p_organization_id uuid, p_reason text)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_org   public.organizations%rowtype;
  v_rests jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  select * into v_org from public.organizations o where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'platform admin: organization % not found', p_organization_id using errcode = '42501';
  end if;

  insert into public.platform_admin_audit_events (actor_app_user_id, target_organization_id, action, reason, details)
    values (v_actor, p_organization_id, 'platform.organization.read', btrim(p_reason),
            jsonb_build_object('organization_id', p_organization_id));

  -- narrow restaurant summary + per-restaurant branch count (read-only).
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', r.id,
             'name', r.name,
             'status', r.status,
             'branches_count', (select count(*) from public.branches b where b.organization_id = r.organization_id and b.restaurant_id = r.id and b.deleted_at is null)
           ) order by r.created_at, r.id), '[]'::jsonb)
    into v_rests
    from public.restaurants r
    where r.organization_id = p_organization_id and r.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'organization', jsonb_build_object(
      'id', v_org.id, 'name', v_org.name, 'status', v_org.status,
      'default_currency', v_org.default_currency,
      'created_by_app_user_id', v_org.created_by_app_user_id,
      'creation_request_id', v_org.creation_request_id,
      'created_at', v_org.created_at),
    'restaurants', v_rests,
    'restaurants_count',         (select count(*) from public.restaurants r where r.organization_id = p_organization_id and r.deleted_at is null),
    'branches_count',            (select count(*) from public.branches    b where b.organization_id = p_organization_id and b.deleted_at is null),
    'active_memberships_count',  (select count(*) from public.memberships m where m.organization_id = p_organization_id and m.status = 'active'),
    'server_ts', now());
end;
$$;

comment on function app.platform_admin_get_organization(uuid, text) is
  'RF-091: read-only detail for ONE organization (+ restaurant/branch summary and counts). Platform-admin + MFA + reason gated; audited (platform.organization.read) with target_organization_id. Fails clearly if the org does not exist. No tenant mutation/impersonation.';

revoke all on function app.platform_admin_get_organization(uuid, text) from public;
grant execute on function app.platform_admin_get_organization(uuid, text) to authenticated;

-- ============================================================================
-- 4. platform_admin_recent_audit — recent platform-admin audit events (self-view).
-- ============================================================================
create or replace function app.platform_admin_recent_audit(p_reason text, p_limit integer default 50)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);  -- validated + capped [1,200]
  v_rows  jsonb;
begin
  v_actor := app.platform_admin_guard(p_reason);

  insert into public.platform_admin_audit_events (actor_app_user_id, target_organization_id, action, reason, details)
    values (v_actor, null, 'platform.audit.read', btrim(p_reason),
            jsonb_build_object('limit', v_limit));

  select coalesce(jsonb_agg(row_to_json(e)::jsonb order by e.occurred_at desc, e.id desc), '[]'::jsonb)
    into v_rows
    from (
      select a.id, a.actor_app_user_id, a.target_organization_id, a.action, a.reason, a.occurred_at
      from public.platform_admin_audit_events a
      order by a.occurred_at desc, a.id desc
      limit v_limit
    ) e;

  return jsonb_build_object('ok', true, 'events', v_rows, 'limit', v_limit, 'server_ts', now());
end;
$$;

comment on function app.platform_admin_recent_audit(text, integer) is
  'RF-091: read-only recent platform_admin_audit_events (id/actor/target_org/action/reason/occurred_at), newest first, limit capped [1,200]. Platform-admin + MFA + reason gated; the read itself is audited (platform.audit.read). No tenant mutation/impersonation.';

revoke all on function app.platform_admin_recent_audit(text, integer) from public;
grant execute on function app.platform_admin_recent_audit(text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists app.platform_admin_recent_audit(text, integer);
--   drop function if exists app.platform_admin_get_organization(uuid, text);
--   drop function if exists app.platform_admin_organization_overview(text);
--   drop function if exists app.platform_admin_guard(text);
-- ============================================================================
