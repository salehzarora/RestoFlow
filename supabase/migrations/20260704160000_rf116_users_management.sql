-- ============================================================================
-- RF-116 — Users management: the missing member-LIST read + a JWT/GUC-free
-- membership REVOKE. DECISIONS D-004/D-005 (per-person identity; membership-
-- scoped roles), D-011 (RPC-only sensitive mutation), D-012 (rank + same-tenant),
-- D-013 (append-only audit), D-026 (platform_admin never a tenant role), D-033
-- (GUC-free). RISK R-003.
-- ============================================================================
-- The RF-112 membership WRITE RPCs (grant_membership, update_role) are correct
-- and JWT-callable but UNDRIVABLE from a real dashboard: update_role needs a
-- membership_id and there is NO read that lists other members (get_my_context is
-- self-only; list_staff is employee_profile-shaped with no membership_id/email;
-- a direct memberships SELECT is RLS-dead for a real JWT — the memberships_scoped
-- policy pins to the unset app.current_organization_id GUC). And revoke was only
-- app.revoke_employee (PIN-session/device-scoped, no public wrapper) — not
-- callable by a dashboard JWT owner. This additive, forward-only migration adds:
--
--   1. app.list_members(p_organization_id) — GUC-free SECURITY DEFINER member
--      directory, gated exactly like app.list_org_structure (rank >= manager
--      ANYWHERE in the org; cashier/kitchen_staff/accountant -> permission_denied;
--      non-member/cross-org -> 42501). Joins memberships -> app_users (+ the
--      optional employee_profile) and returns membership_id, app_user_id, email,
--      display_name, role, scope ids + names, status, is_self, has_pin. LIVE
--      memberships (deleted_at IS NULL); status (active/revoked) returned, not
--      filtered. This single read unblocks update_role + the new revoke.
--
--   2. app.revoke_membership(p_client_request_id, p_membership_id, p_reason) —
--      GUC-free membership deactivation, auth MIRRORING update_role: authority
--      over the membership's OWN scope (actor_rank_in_scope), rank >= manager,
--      NO self-revoke, must STRICTLY outrank the target role (cannot revoke an
--      equal/higher member). Sets status='revoked' + deleted_at, cascades any
--      linked employee_profile to employment_status='terminated' (a revoked
--      member must not keep a working PIN), writes a membership.revoked audit,
--      idempotent via the management_request_results ledger. It NEVER touches
--      platform_admin_grants (D-026) and cannot escalate.
--
-- NOT in scope (honest): inviting/creating BRAND-NEW users (needs an auth-admin
-- / email path we will not add from a client) — grant_membership still requires
-- a pre-existing app_users.id, so the dashboard drives list + role-change +
-- revoke, and grant/invite of new accounts stays out (documented).
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual DOWN at the foot. RISK
-- R-003 human RLS/security sign-off still gates real tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.list_members — the org member directory (rank >= manager, GUC-free).
-- ---------------------------------------------------------------------------
create or replace function app.list_members(
  p_organization_id uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_rank    integer;
  v_members jsonb;
begin
  if v_actor is null then
    raise exception 'list_members: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_members: organization_id is required' using errcode = '42501';
  end if;

  -- the caller's highest ACTIVE membership rank ANYWHERE in this org (like
  -- list_org_structure; deliberately not scope-covering). 0 => not a member.
  select coalesce(max(app.role_rank(m.role)), 0)
    into v_rank
    from public.memberships m
    where m.app_user_id = v_actor
      and m.organization_id = p_organization_id
      and m.status = 'active'
      and m.deleted_at is null;
  if v_rank = 0 then
    raise exception 'list_members: caller has no active membership in the target organization' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant excluded
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'members');
  end if;

  -- LIVE memberships of the org, joined to the identity + optional employee
  -- profile. Highest rank first, then email, for a deterministic directory.
  select coalesce(jsonb_agg(item order by (item ->> 'role_rank')::int desc, (item ->> 'email')), '[]'::jsonb)
    into v_members
  from (
    select jsonb_build_object(
      'membership_id',    m.id,
      'app_user_id',      m.app_user_id,
      'email',            u.email,
      'display_name',     coalesce(ep.display_name, u.display_name),
      'role',             m.role,
      'role_rank',        app.role_rank(m.role),
      'organization_id',  m.organization_id,
      'restaurant_id',    m.restaurant_id,
      'restaurant_name',  r.name,
      'branch_id',        m.branch_id,
      'branch_name',      b.name,
      'status',           m.status,
      'is_self',          (m.app_user_id = v_actor),
      'has_pin',          (ep.pin_credential_ref is not null)
    ) as item
    from public.memberships m
    join public.app_users u on u.id = m.app_user_id
    left join public.restaurants r on r.id = m.restaurant_id and r.organization_id = m.organization_id
    left join public.branches b on b.id = m.branch_id and b.organization_id = m.organization_id
    left join public.employee_profiles ep on ep.membership_id = m.id and ep.organization_id = m.organization_id
    where m.organization_id = p_organization_id
      and m.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'members', 'members', v_members, 'server_ts', now());
end;
$$;

comment on function app.list_members(uuid) is
  'RF-116 (D-033): GUC-free member directory for the owner/manager dashboard. Auth like list_org_structure — unauthenticated -> 42501; rank = highest ACTIVE membership rank anywhere in the org; 0 -> 42501; < manager -> permission_denied. Returns LIVE memberships (deleted_at IS NULL; status active/revoked returned) joined to app_users (email, display_name) + optional employee_profile (display_name, has_pin), with membership_id/app_user_id/role/scope + is_self. Unblocks update_role/revoke_membership (both need a membership_id). Read-only, no secret, no platform_admin (D-026).';

create or replace function public.list_members(p_organization_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_members(p_organization_id); $$;

revoke all on function app.list_members(uuid)    from public;
grant execute on function app.list_members(uuid) to authenticated;
revoke all on function public.list_members(uuid)    from public;
grant execute on function public.list_members(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. app.revoke_membership — GUC-free deactivation (auth mirrors update_role).
-- ---------------------------------------------------------------------------
create or replace function app.revoke_membership(
  p_client_request_id uuid,
  p_membership_id     uuid,
  p_reason            text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_m      public.memberships%rowtype;
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
  v_new    jsonb;
  v_ep_cnt integer;
begin
  if v_actor is null then
    raise exception 'revoke_membership: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'revoke_membership: client_request_id is required' using errcode = '42501';
  end if;
  if p_membership_id is null then
    raise exception 'revoke_membership: membership_id is required' using errcode = '42501';
  end if;

  select * into v_m from public.memberships where id = p_membership_id;
  if not found then
    raise exception 'revoke_membership: membership not found' using errcode = '42501';
  end if;

  -- idempotency replay FIRST (before the active-state check): a retry of the SAME
  -- request must return the stored result even though the membership is now
  -- revoked (unlike update_role, revoke flips status, so the state check below
  -- would otherwise reject a legitimate replay).
  v_fp := md5(jsonb_build_object('membership', p_membership_id, 'action', 'revoke')::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'revoke_membership', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_m.status <> 'active' or v_m.deleted_at is not null then
    raise exception 'revoke_membership: membership is not active' using errcode = '42501';
  end if;

  -- authority over the membership's OWN scope. 0 => non-member / cross-org id => 42501.
  v_rank := app.actor_rank_in_scope(v_m.organization_id, v_m.restaurant_id, v_m.branch_id);
  if v_rank = 0 then
    raise exception 'revoke_membership: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  -- denials (audited permission_denied): no self-revoke; rank>=manager; must STRICTLY
  -- outrank the existing role (cannot revoke an equal/higher membership).
  if v_m.app_user_id = v_actor
     or v_rank < 2
     or v_rank <= app.role_rank(v_m.role) then
    perform app.management_audit(v_m.organization_id, v_m.restaurant_id, v_m.branch_id,
      'membership.revoke_denied', null,
      jsonb_build_object('membership_id', p_membership_id, 'role', v_m.role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'membership');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'membership',
                'membership_id', p_membership_id, 'status', 'revoked');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'revoke_membership', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.memberships t where t.id = p_membership_id;
  update public.memberships set status = 'revoked', deleted_at = now() where id = p_membership_id;
  -- cascade: a revoked member must not keep a working PIN (their employee profile,
  -- if any, is terminated so app.is_pin_session_valid / staff lists fail closed).
  update public.employee_profiles
    set employment_status = 'terminated'
    where membership_id = p_membership_id and organization_id = v_m.organization_id
      and employment_status <> 'terminated';
  get diagnostics v_ep_cnt = row_count;
  select to_jsonb(t) into v_new from public.memberships t where t.id = p_membership_id;
  perform app.management_audit(v_m.organization_id, v_m.restaurant_id, v_m.branch_id, 'membership.revoked',
    v_old, v_new || jsonb_build_object('reason', nullif(btrim(coalesce(p_reason, '')), ''), 'employee_profiles_terminated', v_ep_cnt));
  return v_result;
end;
$$;

comment on function app.revoke_membership(uuid, uuid, text) is
  'RF-116 (D-011/D-012/D-013): GUC-free membership deactivation. Auth mirrors update_role — authority over the membership''s own scope (actor_rank_in_scope), rank >= manager, NO self-revoke, must STRICTLY outrank the target role (equal/higher denied -> membership.revoke_denied audit + permission_denied). Sets status=revoked + deleted_at, cascades any linked employee_profile to terminated (revoked member keeps no working PIN), writes membership.revoked audit. Idempotent (management_request_results). Never touches platform_admin_grants (D-026).';

create or replace function public.revoke_membership(p_client_request_id uuid, p_membership_id uuid, p_reason text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.revoke_membership(p_client_request_id, p_membership_id, p_reason); $$;

revoke all on function app.revoke_membership(uuid, uuid, text)    from public;
grant execute on function app.revoke_membership(uuid, uuid, text) to authenticated;
revoke all on function public.revoke_membership(uuid, uuid, text)    from public;
grant execute on function public.revoke_membership(uuid, uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase forward-only — `supabase db reset` replays):
--   drop function if exists public.revoke_membership(uuid, uuid, text);
--   drop function if exists app.revoke_membership(uuid, uuid, text);
--   drop function if exists public.list_members(uuid);
--   drop function if exists app.list_members(uuid);
-- ============================================================================
