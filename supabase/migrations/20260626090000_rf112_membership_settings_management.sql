-- RF-112 Stage 1 -- GUC-free membership management + settings RPCs (DECISION D-033; API_CONTRACT §4.25/§4.26).
--
-- The tenant-administration backend for the owner/manager dashboard: membership grant/role
-- management and settings edits over the EXISTING org/restaurant/branch columns. Device
-- provisioning (§4.27) is Stage 2 -- NOT in this migration.
--
-- WHY GUC-FREE (the load-bearing decision, D-033):
--   The org-GUC helpers app.current_org_id() / app.has_scope() / app.has_role_in_scope() all
--   PIN to the GUC app.current_organization_id, which NO production caller sets (only pgTAP
--   sets it) -- so they fail closed for a real JWT (the RF-111 D1/D3 trap). RF-112 therefore
--   MUST NOT use them. Instead it mirrors the RF-110 path-derived pattern:
--     * the caller is identified via auth.uid() -> app.current_app_user_id();
--     * tenant scope is the PASSED p_organization_id/p_restaurant_id/p_branch_id;
--     * authority is verified by a DIRECT public.memberships lookup (no org GUC).
--   app.is_platform_admin() is NEVER referenced (D-026). No anon / service-role path (D-011).
--
-- ROLE-RANK GUARD (the missing control, D-033): a total rank
--   org_owner(4) > restaurant_owner(3) > manager(2) > cashier/kitchen_staff/accountant(1).
--   grant_membership / update_role require the actor to STRICTLY outrank the assigned/new role
--   AND (on update) the existing role; managing requires rank >= manager; settings require
--   rank >= restaurant_owner (managers are DENIED for settings -- the conservative reading;
--   the §4.25 "manager may edit branch settings" line is parenthetical/ambiguous and the Stage 1
--   brief says keep managers denied unless the contract clearly allows it). Downward-scope only;
--   no self-grant / no self-escalation; cross-org/restaurant/branch targets are IDOR-denied;
--   platform_admin is never an assignable role.
--
-- AUTHORIZATION OUTCOMES (RF-109 convention):
--   * structural failure (no auth, bad input/role, target/scope not found, caller has NO covering
--     membership = non-member/cross-org/out-of-scope) -> RAISE 42501 (rolled back, no audit).
--   * role/rank denial (caller IS a covering member but lacks the rank, or attempts escalation /
--     self-grant) -> committed `*_denied` audit row + RETURN {ok:false, error:'permission_denied'}.
--   * success -> mutation + committed `*` audit row + RETURN {ok:true, ...}.
--
-- IDEMPOTENCY (client_request_id, D-033/§4.26): management RPCs are online and device-less, so the
--   device outbox key (device_id+local_operation_id, D-022) does not apply and the RF-090 per-entity
--   provenance column only fits CREATE (it cannot make the 4 update-style RPCs replayable). A small
--   shared ledger public.management_request_results keyed on (actor_app_user_id, client_request_id)
--   stores the success result; it is claimed (inserted) BEFORE the mutation so a concurrent duplicate
--   is blocked at the unique key, never as a duplicate row. Conflicting reuse (same key, different
--   input) raises 42501. The key is per-actor, so idempotency never crosses actor; the org is in the
--   fingerprint, so it never crosses org. Locked down like sync_operations (RLS forced, deny-all, no grant).
--
-- Invariants honored: D-001 org isolation; D-004/D-005 membership-scoped roles; D-011 no service-role/
--   no anon (authenticated-only); D-012 RPC writes (direct DML stays RLS-denied, RF-059); D-013 audit;
--   D-026 platform separation (no is_platform_admin reference; platform_admin not assignable);
--   D-028 accountant read-only (rank 1, cannot manage). No money columns / no float (D-007).
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.

-- ===========================================================================
-- 0. Management idempotency ledger (device-less client_request_id replay). Locked
--    to the DEFINER RPCs only: RLS forced + deny-all + no authenticated grant.
-- ===========================================================================
create table public.management_request_results (
  id                  uuid        primary key default gen_random_uuid(),
  actor_app_user_id   uuid        not null references public.app_users (id) on delete restrict,
  client_request_id   uuid        not null,
  operation           text        not null check (length(btrim(operation)) > 0),
  request_fingerprint text        not null,
  result              jsonb       not null,
  created_at          timestamptz not null default now(),
  -- per-actor idempotency: a request_id is unique within one actor; replay/conflict are
  -- resolved against the stored operation+fingerprint (which embeds the org -> never crosses org).
  unique (actor_app_user_id, client_request_id)
);

comment on table public.management_request_results is
  'RF-112 (D-033): device-less client_request_id idempotency ledger for the management RPCs (grant_membership/update_role/update_*_settings). Keyed on (actor_app_user_id, client_request_id); stores the success result for deterministic replay; conflicting reuse (same key, different fingerprint) raises 42501. Written/read ONLY by the SECURITY DEFINER RPCs (BYPASSRLS owner); the tenant authenticated path has NO grant + deny-all policies. No organization_id column (per-actor key; org isolation is via the fingerprint + the RPC scope checks).';

create index management_request_results_actor_idx on public.management_request_results (actor_app_user_id);

alter table public.management_request_results enable row level security;
alter table public.management_request_results force  row level security;

-- deny-all per-command policies (>= 1 policy for the RF-019 detector); no authenticated grant.
create policy management_request_results_sel_deny on public.management_request_results for select to authenticated using (false);
create policy management_request_results_ins_deny on public.management_request_results for insert to authenticated with check (false);
create policy management_request_results_upd_deny on public.management_request_results for update to authenticated using (false) with check (false);
create policy management_request_results_del_deny on public.management_request_results for delete to authenticated using (false);
-- intentionally NO grant to authenticated (like platform_admin_grants / the sync_operations lockdown).

-- ===========================================================================
-- 1. app.role_rank(text) -- the total role rank (IMMUTABLE; no table access).
--    Invalid / unknown / platform_admin -> 0 (never outranked by a real role; callers
--    additionally reject non-six-key roles structurally before the rank checks run).
-- ===========================================================================
create or replace function app.role_rank(p_role text)
  returns integer
  language sql
  immutable
  set search_path = ''
as $$
  select case p_role
    when 'org_owner'        then 4
    when 'restaurant_owner' then 3
    when 'manager'          then 2
    when 'cashier'          then 1
    when 'kitchen_staff'    then 1
    when 'accountant'       then 1
    else 0
  end;
$$;

comment on function app.role_rank(text) is
  'RF-112 (D-033): total tenant role rank org_owner(4) > restaurant_owner(3) > manager(2) > cashier/kitchen_staff/accountant(1); unknown/platform_admin = 0. Drives the role-rank escalation guard.';

-- ===========================================================================
-- 2. app.actor_rank_in_scope(org, restaurant, branch) -- GUC-FREE authority resolver.
--    Returns the current caller's HIGHEST active membership rank whose scope COVERS the
--    target (downward-only): an org-wide member covers any restaurant/branch; a
--    restaurant member covers that restaurant + its branches; a branch member covers only
--    that branch. 0 when the caller has no covering membership (non-member / cross-org /
--    out-of-scope / unauthenticated) => fail-closed. NOTE the coverage predicate drops the
--    RF-110 read-helper's `target is null` escape on purpose: an org-wide target
--    (restaurant null) requires an org-wide actor, so a restaurant_owner cannot reach
--    org-level settings, and a branch member cannot reach restaurant-level settings.
--    Uses NO org GUC: identity = app.current_app_user_id(), org = the PASSED p_org.
-- ===========================================================================
create or replace function app.actor_rank_in_scope(p_org uuid, p_restaurant uuid, p_branch uuid)
  returns integer
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select coalesce(max(app.role_rank(m.role)), 0)
  from public.memberships m
  where m.app_user_id     = app.current_app_user_id()
    and m.organization_id = p_org
    and m.status          = 'active'
    and m.deleted_at is null
    and (m.restaurant_id is null or m.restaurant_id = p_restaurant)
    and (m.branch_id     is null or m.branch_id     = p_branch);
$$;

comment on function app.actor_rank_in_scope(uuid, uuid, uuid) is
  'RF-112 (D-033): GUC-free authority resolver. The current caller''s (app.current_app_user_id()) highest ACTIVE membership rank whose scope COVERS (p_org, p_restaurant, p_branch), downward-only; 0 if none (fail-closed). Does NOT use app.current_org_id()/has_scope()/has_role_in_scope() -- the org boundary is the PASSED p_org validated directly against memberships.';

-- ===========================================================================
-- 3. Internal audit + idempotency helpers (DEFINER; revoked from public; called only
--    inside the RF-112 RPCs as their owner).
-- ===========================================================================

-- Append-only audit writer (actor = the resolved app_user; no device). Mirrors app.menu_audit.
create or replace function app.management_audit(
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

-- Returns the stored result (idempotent_replay=true) for a committed matching request, or
-- NULL if none exists; raises 42501 when the same key was used with different input.
create or replace function app.management_idem_check(
  p_actor uuid, p_client_request_id uuid, p_operation text, p_fingerprint text)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v public.management_request_results%rowtype;
begin
  select * into v from public.management_request_results
    where actor_app_user_id = p_actor and client_request_id = p_client_request_id;
  if not found then
    return null;
  end if;
  if v.operation <> p_operation or v.request_fingerprint <> p_fingerprint then
    raise exception 'management: client_request_id reused with different input' using errcode = '42501';
  end if;
  return jsonb_set(v.result, '{idempotent_replay}', 'true'::jsonb);
end;
$$;

-- Claims the request by inserting the ledger row BEFORE the caller mutates. Returns NULL when
-- THIS call claimed it (caller proceeds to mutate); returns the stored replay result when a
-- concurrent caller already claimed it (caller returns it WITHOUT mutating). Raises on conflict.
create or replace function app.management_claim_request(
  p_actor uuid, p_client_request_id uuid, p_operation text, p_fingerprint text, p_result jsonb)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  insert into public.management_request_results
    (actor_app_user_id, client_request_id, operation, request_fingerprint, result)
  values (p_actor, p_client_request_id, p_operation, p_fingerprint, p_result);
  return null;                                          -- claimed: caller mutates
exception when unique_violation then
  return app.management_idem_check(p_actor, p_client_request_id, p_operation, p_fingerprint);
end;
$$;

-- ===========================================================================
-- 4. app.grant_membership -- add a membership for an EXISTING app_user (no invite/pending).
-- ===========================================================================
create or replace function app.grant_membership(
  p_client_request_id   uuid,
  p_organization_id     uuid,
  p_restaurant_id       uuid,
  p_branch_id           uuid,
  p_target_app_user_id  uuid,
  p_role                text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_id     uuid := gen_random_uuid();
  v_result jsonb;
  v_new    jsonb;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'grant_membership: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'grant_membership: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'grant_membership: organization_id is required' using errcode = '42501';
  end if;
  if p_target_app_user_id is null then
    raise exception 'grant_membership: target_app_user_id is required' using errcode = '42501';
  end if;

  -- (b) structural validation: role must be one of the six tenant keys (platform_admin rejected).
  if p_role is null or p_role not in
       ('org_owner','restaurant_owner','manager','cashier','kitchen_staff','accountant') then
    raise exception 'grant_membership: invalid role % (platform_admin is not a tenant role)', p_role using errcode = '42501';
  end if;
  if p_branch_id is not null and p_restaurant_id is null then
    raise exception 'grant_membership: branch requires restaurant' using errcode = '42501';
  end if;
  -- existing, ACTIVE app_user only (no invite/pending flow; never grant to a disabled account)
  if not exists (select 1 from public.app_users au where au.id = p_target_app_user_id and au.is_active) then
    raise exception 'grant_membership: target app_user not found or inactive' using errcode = '42501';
  end if;
  -- target scope must exist in the SAME org AND be LIVE (not a soft-deleted tombstone) -- never create
  -- authority on a dead scope (RF112-S1-B1). Clean 42501 instead of a raw FK error. Because a branch
  -- target also carries a restaurant (branch_requires_restaurant above), the restaurant check below runs
  -- first and rejects a branch whose PARENT restaurant is soft-deleted.
  if p_restaurant_id is not null and not exists (
       select 1 from public.restaurants r
        where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'grant_membership: restaurant not found in organization or is soft-deleted' using errcode = '42501';
  end if;
  if p_branch_id is not null and not exists (
       select 1 from public.branches b
        where b.id = p_branch_id and b.organization_id = p_organization_id
          and b.restaurant_id = p_restaurant_id and b.deleted_at is null) then
    raise exception 'grant_membership: branch not found in organization/restaurant or is soft-deleted' using errcode = '42501';
  end if;

  -- (c) committed idempotent replay (before authorization -> true idempotency)
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'target', p_target_app_user_id, 'role', p_role)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'grant_membership', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (d) authorization (GUC-free + role-rank guard). 0 => caller covers nothing here => structural 42501.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'grant_membership: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  -- caller IS a covering member from here -> denials are audited permission_denied:
  --   no self-grant; cashier/kitchen_staff/accountant (rank 1) cannot manage; must STRICTLY outrank the assigned role.
  if p_target_app_user_id = v_actor
     or v_rank < 2
     or v_rank <= app.role_rank(p_role) then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'membership.grant_denied', null,
      jsonb_build_object('target_app_user_id', p_target_app_user_id, 'role', p_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'membership');
  end if;

  -- (e) data integrity: at most ONE active membership per (app_user, EXACT scope). A second active
  -- membership at the same org/restaurant/branch is rejected so revocation stays unambiguous and
  -- authority enumeration is not inflated; change a role via update_role, not a second grant. A
  -- revoked/tombstoned row at the same scope does NOT block a re-grant. (Checked after authorization
  -- so a non-covering caller cannot probe for existing memberships.)
  if exists (
       select 1 from public.memberships m
        where m.app_user_id     = p_target_app_user_id
          and m.organization_id = p_organization_id
          and m.restaurant_id is not distinct from p_restaurant_id
          and m.branch_id     is not distinct from p_branch_id
          and m.status = 'active'
          and m.deleted_at is null) then
    raise exception 'grant_membership: an active membership already exists for this app_user at this scope (use update_role to change the role)' using errcode = '42501';
  end if;

  -- (f) claim idempotency BEFORE mutating (race-safe -> no duplicate membership), then mutate + audit.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'membership',
                'membership_id', v_id, 'app_user_id', p_target_app_user_id, 'role', p_role);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'grant_membership', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  insert into public.memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status)
  values (v_id, p_target_app_user_id, p_organization_id, p_restaurant_id, p_branch_id, p_role, 'active');

  select to_jsonb(t) into v_new from public.memberships t where t.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'membership.granted', null, v_new);
  return v_result;
end;
$$;

-- ===========================================================================
-- 5. app.update_role -- change an existing membership's role (scope immutable: reassignment
--    is revoke + grant, mirroring the menu RPCs' "org/rest/branch immutable on update").
-- ===========================================================================
create or replace function app.update_role(
  p_client_request_id uuid,
  p_membership_id     uuid,
  p_new_role          text
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
begin
  if v_actor is null then
    raise exception 'update_role: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'update_role: client_request_id is required' using errcode = '42501';
  end if;
  if p_membership_id is null then
    raise exception 'update_role: membership_id is required' using errcode = '42501';
  end if;
  if p_new_role is null or p_new_role not in
       ('org_owner','restaurant_owner','manager','cashier','kitchen_staff','accountant') then
    raise exception 'update_role: invalid role % (platform_admin is not a tenant role)', p_new_role using errcode = '42501';
  end if;

  select * into v_m from public.memberships where id = p_membership_id;
  if not found then
    raise exception 'update_role: membership not found' using errcode = '42501';
  end if;
  if v_m.status <> 'active' or v_m.deleted_at is not null then
    raise exception 'update_role: membership is not active' using errcode = '42501';
  end if;
  -- RF112-S1-B1: the membership's parent restaurant/branch scope must still be LIVE -- never mutate
  -- authority on a soft-deleted scope. A branch membership also carries restaurant_id, so the
  -- restaurant check below covers "parent restaurant not soft-deleted" for branch memberships.
  if v_m.restaurant_id is not null and not exists (
       select 1 from public.restaurants r
        where r.id = v_m.restaurant_id and r.organization_id = v_m.organization_id and r.deleted_at is null) then
    raise exception 'update_role: membership restaurant scope is soft-deleted' using errcode = '42501';
  end if;
  if v_m.branch_id is not null and not exists (
       select 1 from public.branches b
        where b.id = v_m.branch_id and b.organization_id = v_m.organization_id
          and b.restaurant_id = v_m.restaurant_id and b.deleted_at is null) then
    raise exception 'update_role: membership branch scope is soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('membership', p_membership_id, 'new_role', p_new_role)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'update_role', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- authority over the membership's OWN scope. 0 => non-member / cross-org id / out-of-scope => 42501.
  v_rank := app.actor_rank_in_scope(v_m.organization_id, v_m.restaurant_id, v_m.branch_id);
  if v_rank = 0 then
    raise exception 'update_role: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  -- denials (audited permission_denied): no self-escalation; rank>=manager required; must STRICTLY
  -- outrank BOTH the existing role and the new role (cannot touch an equal/higher membership).
  if v_m.app_user_id = v_actor
     or v_rank < 2
     or v_rank <= app.role_rank(v_m.role)
     or v_rank <= app.role_rank(p_new_role) then
    perform app.management_audit(v_m.organization_id, v_m.restaurant_id, v_m.branch_id,
      'membership.role_update_denied', null,
      jsonb_build_object('membership_id', p_membership_id, 'from_role', v_m.role, 'to_role', p_new_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'membership');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'membership',
                'membership_id', p_membership_id, 'role', p_new_role);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'update_role', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.memberships t where t.id = p_membership_id;
  update public.memberships set role = p_new_role where id = p_membership_id;
  select to_jsonb(t) into v_new from public.memberships t where t.id = p_membership_id;
  perform app.management_audit(v_m.organization_id, v_m.restaurant_id, v_m.branch_id, 'membership.role_updated', v_old, v_new);
  return v_result;
end;
$$;

-- ===========================================================================
-- 6. Settings RPCs -- edits over the EXISTING columns only (no new tables/columns; no
--    tax/rounding/locale/business-hours/receipt-template). A null parameter leaves the
--    field UNCHANGED (clearing an optional field is deferred). Authorized to
--    restaurant_owner/org_owner covering the target scope (managers DENIED).
-- ===========================================================================

-- 6a. organization settings: default_currency, country_code, status. Org-wide scope => org_owner only.
create or replace function app.update_organization_settings(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_default_currency  text default null,
  p_country_code      text default null,
  p_status            text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_cur    text;
  v_cc     text;
  v_st     text;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'update_organization_settings: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'update_organization_settings: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'update_organization_settings: organization_id is required' using errcode = '42501';
  end if;

  if p_default_currency is not null then
    v_cur := upper(btrim(p_default_currency));
    if v_cur !~ '^[A-Z]{3}$' then
      raise exception 'update_organization_settings: default_currency must match ^[A-Z]{3}$' using errcode = '42501';
    end if;
  end if;
  if p_country_code is not null then
    v_cc := upper(btrim(p_country_code));
    if v_cc !~ '^[A-Z]{2}$' then
      raise exception 'update_organization_settings: country_code must match ^[A-Z]{2}$' using errcode = '42501';
    end if;
  end if;
  if p_status is not null then
    if p_status not in ('active','suspended') then
      raise exception 'update_organization_settings: status must be active or suspended' using errcode = '42501';
    end if;
    v_st := p_status;
  end if;

  if not exists (select 1 from public.organizations o where o.id = p_organization_id and o.deleted_at is null) then
    raise exception 'update_organization_settings: organization not found' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'currency', v_cur, 'country', v_cc, 'status', v_st)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'update_organization_settings', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, null, null);
  if v_rank = 0 then
    raise exception 'update_organization_settings: caller has no active membership covering the organization' using errcode = '42501';
  end if;
  if v_rank < 3 then
    perform app.management_audit(p_organization_id, null, null, 'settings.organization.update_denied', null,
      jsonb_build_object('organization_id', p_organization_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'organization');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'organization',
                'organization_id', p_organization_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'update_organization_settings', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.organizations t where t.id = p_organization_id;
  update public.organizations set
    default_currency = coalesce(v_cur, default_currency),
    country_code     = coalesce(v_cc,  country_code),
    status           = coalesce(v_st,  status)
  where id = p_organization_id;
  select to_jsonb(t) into v_new from public.organizations t where t.id = p_organization_id;
  perform app.management_audit(p_organization_id, null, null, 'settings.organization.updated', v_old, v_new);
  return v_result;
end;
$$;

-- 6b. restaurant settings: name, currency_override, timezone, status.
create or replace function app.update_restaurant_settings(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_name              text default null,
  p_currency_override text default null,
  p_timezone          text default null,
  p_status            text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_name   text;
  v_cur    text;
  v_tz     text;
  v_st     text;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'update_restaurant_settings: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'update_restaurant_settings: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'update_restaurant_settings: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  if p_name is not null then
    v_name := btrim(p_name);
    if length(v_name) = 0 then
      raise exception 'update_restaurant_settings: name cannot be blank' using errcode = '42501';
    end if;
  end if;
  if p_currency_override is not null then
    v_cur := upper(btrim(p_currency_override));
    if v_cur !~ '^[A-Z]{3}$' then
      raise exception 'update_restaurant_settings: currency_override must match ^[A-Z]{3}$' using errcode = '42501';
    end if;
  end if;
  if p_timezone is not null then
    v_tz := p_timezone;
    if not exists (select 1 from pg_catalog.pg_timezone_names where name = v_tz) then
      raise exception 'update_restaurant_settings: timezone % is not a valid IANA timezone', v_tz using errcode = '42501';
    end if;
  end if;
  if p_status is not null then
    if p_status not in ('active','suspended') then
      raise exception 'update_restaurant_settings: status must be active or suspended' using errcode = '42501';
    end if;
    v_st := p_status;
  end if;

  if not exists (select 1 from public.restaurants r
                 where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'update_restaurant_settings: restaurant not found in organization' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'name', v_name, 'currency', v_cur, 'timezone', v_tz, 'status', v_st)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'update_restaurant_settings', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'update_restaurant_settings: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 3 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null, 'settings.restaurant.update_denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'restaurant');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'restaurant',
                'restaurant_id', p_restaurant_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'update_restaurant_settings', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.restaurants t where t.id = p_restaurant_id;
  update public.restaurants set
    name              = coalesce(v_name, name),
    currency_override = coalesce(v_cur,  currency_override),
    timezone          = coalesce(v_tz,   timezone),
    status            = coalesce(v_st,   status)
  where id = p_restaurant_id;
  select to_jsonb(t) into v_new from public.restaurants t where t.id = p_restaurant_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, null, 'settings.restaurant.updated', v_old, v_new);
  return v_result;
end;
$$;

-- 6c. branch settings: name, address, timezone, receipt_prefix, status.
create or replace function app.update_branch_settings(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_name              text default null,
  p_address           text default null,
  p_timezone          text default null,
  p_receipt_prefix    text default null,
  p_status            text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_name   text;
  v_addr   text;
  v_tz     text;
  v_rp     text;
  v_st     text;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'update_branch_settings: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'update_branch_settings: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'update_branch_settings: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;

  if p_name is not null then
    v_name := btrim(p_name);
    if length(v_name) = 0 then
      raise exception 'update_branch_settings: name cannot be blank' using errcode = '42501';
    end if;
  end if;
  if p_address is not null then
    v_addr := btrim(p_address);
  end if;
  if p_timezone is not null then
    v_tz := p_timezone;
    if not exists (select 1 from pg_catalog.pg_timezone_names where name = v_tz) then
      raise exception 'update_branch_settings: timezone % is not a valid IANA timezone', v_tz using errcode = '42501';
    end if;
  end if;
  if p_receipt_prefix is not null then
    v_rp := btrim(p_receipt_prefix);
  end if;
  if p_status is not null then
    if p_status not in ('active','suspended') then
      raise exception 'update_branch_settings: status must be active or suspended' using errcode = '42501';
    end if;
    v_st := p_status;
  end if;

  -- RF112-S1-B1 (wider scan): the branch AND its parent restaurant must be LIVE (not soft-deleted).
  if not exists (select 1 from public.branches b
                 join public.restaurants r
                   on r.id = b.restaurant_id and r.organization_id = b.organization_id
                 where b.id = p_branch_id and b.organization_id = p_organization_id
                   and b.restaurant_id = p_restaurant_id
                   and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'update_branch_settings: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'branch', p_branch_id,
              'name', v_name, 'address', v_addr, 'timezone', v_tz, 'receipt_prefix', v_rp, 'status', v_st)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'update_branch_settings', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'update_branch_settings: caller has no active membership covering the branch' using errcode = '42501';
  end if;
  if v_rank < 3 then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.update_denied', null,
      jsonb_build_object('branch_id', p_branch_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'branch');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'branch',
                'branch_id', p_branch_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'update_branch_settings', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.branches t where t.id = p_branch_id;
  update public.branches set
    name           = coalesce(v_name, name),
    address        = coalesce(v_addr, address),
    timezone       = coalesce(v_tz,   timezone),
    receipt_prefix = coalesce(v_rp,   receipt_prefix),
    status         = coalesce(v_st,   status)
  where id = p_branch_id;
  select to_jsonb(t) into v_new from public.branches t where t.id = p_branch_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.updated', v_old, v_new);
  return v_result;
end;
$$;

-- ===========================================================================
-- 7. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 pattern). No logic; delegate
--    verbatim to app.*; the caller's EXECUTE on app.* is reused. Make the RPCs Data-API
--    reachable without exposing the app schema.
-- ===========================================================================
create or replace function public.grant_membership(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_target_app_user_id uuid, p_role text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.grant_membership(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_target_app_user_id, p_role); $$;

create or replace function public.update_role(
  p_client_request_id uuid, p_membership_id uuid, p_new_role text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.update_role(p_client_request_id, p_membership_id, p_new_role); $$;

create or replace function public.update_organization_settings(
  p_client_request_id uuid, p_organization_id uuid,
  p_default_currency text default null, p_country_code text default null, p_status text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.update_organization_settings(p_client_request_id, p_organization_id, p_default_currency, p_country_code, p_status); $$;

create or replace function public.update_restaurant_settings(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_name text default null, p_currency_override text default null, p_timezone text default null, p_status text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.update_restaurant_settings(p_client_request_id, p_organization_id, p_restaurant_id, p_name, p_currency_override, p_timezone, p_status); $$;

create or replace function public.update_branch_settings(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_name text default null, p_address text default null, p_timezone text default null,
  p_receipt_prefix text default null, p_status text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.update_branch_settings(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_name, p_address, p_timezone, p_receipt_prefix, p_status); $$;

-- ===========================================================================
-- 8. Grants: authenticated only (never anon / service_role). The public wrappers + their
--    app.* targets are granted to authenticated; the internal helpers (role_rank,
--    actor_rank_in_scope, management_audit/idem/claim) are revoked from public and NOT
--    granted -- they run only inside the DEFINER RPCs as the owner.
-- ===========================================================================
revoke all on function app.role_rank(text)                                  from public;
revoke all on function app.actor_rank_in_scope(uuid, uuid, uuid)            from public;
revoke all on function app.management_audit(uuid, uuid, uuid, text, jsonb, jsonb) from public;
revoke all on function app.management_idem_check(uuid, uuid, text, text)    from public;
revoke all on function app.management_claim_request(uuid, uuid, text, text, jsonb) from public;

revoke all on function app.grant_membership(uuid, uuid, uuid, uuid, uuid, text)                    from public;
revoke all on function app.update_role(uuid, uuid, text)                                           from public;
revoke all on function app.update_organization_settings(uuid, uuid, text, text, text)              from public;
revoke all on function app.update_restaurant_settings(uuid, uuid, uuid, text, text, text, text)    from public;
revoke all on function app.update_branch_settings(uuid, uuid, uuid, uuid, text, text, text, text, text) from public;

grant execute on function app.grant_membership(uuid, uuid, uuid, uuid, uuid, text)                 to authenticated;
grant execute on function app.update_role(uuid, uuid, text)                                        to authenticated;
grant execute on function app.update_organization_settings(uuid, uuid, text, text, text)           to authenticated;
grant execute on function app.update_restaurant_settings(uuid, uuid, uuid, text, text, text, text) to authenticated;
grant execute on function app.update_branch_settings(uuid, uuid, uuid, uuid, text, text, text, text, text) to authenticated;

revoke all on function public.grant_membership(uuid, uuid, uuid, uuid, uuid, text)                 from public;
revoke all on function public.update_role(uuid, uuid, text)                                        from public;
revoke all on function public.update_organization_settings(uuid, uuid, text, text, text)           from public;
revoke all on function public.update_restaurant_settings(uuid, uuid, uuid, text, text, text, text) from public;
revoke all on function public.update_branch_settings(uuid, uuid, uuid, uuid, text, text, text, text, text) from public;

grant execute on function public.grant_membership(uuid, uuid, uuid, uuid, uuid, text)                 to authenticated;
grant execute on function public.update_role(uuid, uuid, text)                                        to authenticated;
grant execute on function public.update_organization_settings(uuid, uuid, text, text, text)           to authenticated;
grant execute on function public.update_restaurant_settings(uuid, uuid, uuid, text, text, text, text) to authenticated;
grant execute on function public.update_branch_settings(uuid, uuid, uuid, uuid, text, text, text, text, text) to authenticated;

-- ===========================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays from empty):
--   drop function if exists public.update_branch_settings(uuid, uuid, uuid, uuid, text, text, text, text, text);
--   drop function if exists public.update_restaurant_settings(uuid, uuid, uuid, text, text, text, text);
--   drop function if exists public.update_organization_settings(uuid, uuid, text, text, text);
--   drop function if exists public.update_role(uuid, uuid, text);
--   drop function if exists public.grant_membership(uuid, uuid, uuid, uuid, uuid, text);
--   drop function if exists app.update_branch_settings(uuid, uuid, uuid, uuid, text, text, text, text, text);
--   drop function if exists app.update_restaurant_settings(uuid, uuid, uuid, text, text, text, text);
--   drop function if exists app.update_organization_settings(uuid, uuid, text, text, text);
--   drop function if exists app.update_role(uuid, uuid, text);
--   drop function if exists app.grant_membership(uuid, uuid, uuid, uuid, uuid, text);
--   drop function if exists app.management_claim_request(uuid, uuid, text, text, jsonb);
--   drop function if exists app.management_idem_check(uuid, uuid, text, text);
--   drop function if exists app.management_audit(uuid, uuid, uuid, text, jsonb, jsonb);
--   drop function if exists app.actor_rank_in_scope(uuid, uuid, uuid);
--   drop function if exists app.role_rank(text);
--   drop table if exists public.management_request_results;
-- ===========================================================================
