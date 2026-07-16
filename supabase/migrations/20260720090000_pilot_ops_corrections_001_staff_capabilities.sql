-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 (1/4) -- two DEFAULT-ON operational staff
-- capabilities: manage_menu_availability + manage_table_operations
-- ============================================================================
-- The pilot needs a cashier to (A) flip a menu item Sold out / Paused from the
-- POS and (B) run floor table operations (manual status, link/unlink), without
-- widening any money right. Both are DAY-TO-DAY operational rights, so they use
-- the EXISTING deny-only / default-ON model (app.cashier_capability_allowed) --
-- the same polarity as apply_discount/void_order/close_shift: a cashier holds
-- them by default, and an owner/manager may DENY them per employee from the
-- Dashboard (permissions ->> key = 'false'). Managers/owners hold them BY ROLE.
-- kitchen_staff/accountant never hold them (the resolver returns false for every
-- non-cashier role, so this widens nothing). No backfill: every existing cashier
-- (permissions '{}') gets them by construction, which is exactly the product
-- decision (default ON). The grant-only apply_full_comp resolver is UNTOUCHED.
--
-- This migration is the capability PLUMBING only. The POS write paths that ENFORCE
-- these capabilities (menu.availability_set, table.status_set/link/unlink through
-- app.sync_push) land in migrations 2-3 of this phase.
--
-- Faithful re-creation (byte-identical bodies + ONLY the capability delta):
--   * app.cashier_capability_allowed  -- +2 keys in the named allowlist (default ON)
--   * app.pin_session_capabilities    -- +2 effective booleans (POS advisory context)
--   * app.set_staff_capabilities      -- 6-arg -> 8-arg (DROP+recreate; deny-only store)
--   * app.list_staff                  -- +2 effective booleans per row
--   * app.create_staff_member         -- validator accepts the 2 deny-only keys
--   * app.audit_safe_detail           -- +2 keys in the nested capabilities allowlist
-- audit_action_has_detail is UNCHANGED (staff.capabilities%/staff.created already
-- carry detail; the two keys ride the existing capabilities object).
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.cashier_capability_allowed -- +manage_menu_availability +manage_table_operations
--    in the named default-ON allowlist. Every other predicate is verbatim.
-- ---------------------------------------------------------------------------
create or replace function app.cashier_capability_allowed(
  p_role        text,
  p_permissions jsonb,
  p_capability  text
)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  -- FAIL-CLOSED effective resolver. A named cashier capability is ALLOWED (role
  -- default ON) ONLY when the deny key is ABSENT from a well-formed JSON object.
  -- Deny-only storage writes exactly {"key":"false"} to deny and REMOVES the key
  -- to allow, so a PRESENT key always means a deny was intended; any present value
  -- (the canonical string "false", or a malformed "true"/boolean/null/number/
  -- array/object) therefore DENIES. Non-object / JSON-null / SQL-NULL permissions,
  -- every non-cashier role, and any capability outside the three named ones all
  -- DENY. Never a universal missing-value allow: absence allows ONLY a named cap.
  select p_role = 'cashier'
         and p_capability in ('apply_discount', 'void_order', 'close_shift', 'manage_menu_availability', 'manage_table_operations')
         and p_permissions is not null
         and jsonb_typeof(p_permissions) = 'object'
         and not (p_permissions ? p_capability);
$$;

comment on function app.cashier_capability_allowed(text, jsonb, text) is
  'STAFF-CASHIER-PERMISSIONS-001 + PILOT-OPERATIONS-CORRECTIONS-001: FAIL-CLOSED effective per-cashier capability resolver (pure, immutable) for the DEFAULT-ON / deny-only capabilities. TRUE iff role=cashier AND the capability is one of the named default-ON keys (apply_discount, void_order, close_shift, manage_menu_availability, manage_table_operations) AND permissions is a well-formed JSON object AND the deny key is ABSENT (role default ON). Deny-only storage removes the key to allow and writes {"key":"false"} to deny, so a PRESENT key ALWAYS denies. Non-object / JSON-null / SQL-NULL permissions, every non-cashier role, and any capability outside the named set all DENY. Callers OR it with owner/manager role grants, so it never widens another role.';

revoke all on function app.cashier_capability_allowed(text, jsonb, text) from public;

-- ---------------------------------------------------------------------------
-- 2. app.pin_session_capabilities -- POS advisory capability context now also
--    projects the two new effective rights (role OR the default-ON cashier
--    capability). CREATE OR REPLACE (same signature) keeps ACLs; hotfix preamble.
-- ---------------------------------------------------------------------------
create or replace function app.pin_session_capabilities(
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
  v_membership uuid;
  v_ds_org     uuid;
  v_ds_rest    uuid;
  v_ds_branch  uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_m_perms    jsonb;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE — the one app.apply_discount actually
  --     uses, not an approximation of it. EVERY failure below (unknown session,
  --     inactive, expired, dead device session, revoked device, inactive pairing,
  --     device mismatch, scope mismatch, dead membership) returns ONE
  --     INDISTINGUISHABLE envelope. A caller must never learn WHICH check failed —
  --     that would turn a capability probe into an existence/scope oracle across
  --     tenants (RISK R-003).
  select ps.organization_id, ps.restaurant_id, ps.branch_id,
         ps.device_session_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  -- app.is_pin_session_valid is the SHARED validity rule (active + not expired +
  -- not ended). Use the helper; do not re-implement its predicate here.
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  select ds.organization_id, ds.restaurant_id, ds.branch_id,
         ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_org, v_ds_rest, v_ds_branch,
         v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id
     -- The PIN session and its backing device session MUST agree on scope. They are
     -- FK-linked at creation so this cannot diverge today; a capability oracle is
     -- precisely the wrong place to take that on trust.
     or v_ds_org    is distinct from v_org
     or v_ds_rest   is distinct from v_rest
     or v_ds_branch is distinct from v_branch then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  -- The membership is resolved through the session's OWN resolved_membership_id --
  -- the authoritative pointer -- not by re-deriving it from employee_profiles.
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  -- (b) EFFECTIVE rights -- byte-for-byte the predicates app.apply_discount enforces,
  --     so the client can never disagree with the server about what it may do. The
  --     capability MODEL is unchanged by this hotfix:
  --       apply_discount  = manager+ OR the DEFAULT-ON cashier capability (deny-only)
  --       apply_full_comp = manager+ OR the DEFAULT-OFF cashier grant (grant-only)
  --     Both resolvers are total and return BOOLEAN, never null: a missing override
  --     key resolves to false for apply_full_comp (grant-only => absence denies), and
  --     malformed permissions JSON fails closed in both.
  --     NOTHING here leaks: no permissions JSON, no membership/employee/session UUID,
  --     no PIN material, no money, no order data -- only the role and two booleans.
  return jsonb_build_object(
    'ok', true, 'entity', 'pin_session', 'role', v_role,
    'capabilities', jsonb_build_object(
      'apply_discount',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'apply_discount'),
      'apply_full_comp',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp'),
      'manage_menu_availability',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_menu_availability'),
      'manage_table_operations',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_table_operations')));
end;
$$;

comment on function app.pin_session_capabilities(uuid, uuid) is
  'PILOT-OPERATIONS-CORRECTIONS-001: READ-ONLY effective-capability projection for an ACTIVE PIN session on a PAIRED device (canonical hotfix preamble). Now returns FOUR effective booleans: apply_discount, apply_full_comp, and the two new DEFAULT-ON operational rights manage_menu_availability + manage_table_operations (manager+ by role OR the default-ON cashier capability). ADVISORY ONLY -- the server re-decides on every mutation. Every invalid/expired/revoked/device- or scope-mismatched/inactive-membership session collapses to ONE indistinguishable invalid_session envelope (no probe oracle, R-003). No money, no PIN material, no identifier beyond the role.';

revoke all on function app.pin_session_capabilities(uuid, uuid) from public;
revoke all on function app.pin_session_capabilities(uuid, uuid) from anon;
grant execute on function app.pin_session_capabilities(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. app.set_staff_capabilities -- 6-arg -> 8-arg. A CHANGED SIGNATURE cannot use
--    CREATE OR REPLACE (Postgres would leave the 6-arg as a second overload and
--    PostgREST would resolve ambiguously), so DROP + re-create both the public
--    wrapper and the app function; ACLs re-applied below. The two new toggles are
--    DEFAULT-ON / deny-only: ON removes the key, OFF stores the string "false".
-- ---------------------------------------------------------------------------
drop function if exists public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean);
drop function if exists app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean);

create function app.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean,
  p_apply_full_comp     boolean default false,  -- FULL-COMP-PERMISSION-001 (default OFF)
  p_manage_menu_availability boolean default true,  -- PILOT-OPERATIONS-CORRECTIONS-001 (default ON)
  p_manage_table_operations  boolean default true   -- PILOT-OPERATIONS-CORRECTIONS-001 (default ON)
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_membership uuid;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_perms      jsonb;
  v_new_perms  jsonb;
  v_rank       integer;
  v_fp         text;
  v_replay     jsonb;
  v_result     jsonb;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'set_staff_capabilities: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_staff_capabilities: client_request_id is required' using errcode = '42501';
  end if;
  if p_employee_profile_id is null then
    raise exception 'set_staff_capabilities: employee_profile_id is required' using errcode = '42501';
  end if;

  -- (b) idempotent replay FIRST -- BEFORE any target lookup, so the idempotency
  --     ledger cannot become an existence/scope oracle. The fingerprint is derived
  --     ONLY from caller-supplied canonical input; management_idem_check is
  --     actor-scoped (keyed on actor_app_user_id + client_request_id), so a stored
  --     replay result is never exposed to a different actor/membership/org/session.
  -- FULL-COMP-PERMISSION-001: the 4th toggle is PART OF THE FINGERPRINT. Without it,
  -- flipping ONLY full-comp on an otherwise-identical payload would hash to the prior
  -- request and REPLAY its stored result -- silently skipping the write.
  v_fp := md5(jsonb_build_object('emp', p_employee_profile_id,
              'apply_discount', p_apply_discount, 'void_order', p_void_order,
              'close_shift', p_close_shift, 'apply_full_comp', p_apply_full_comp,
              'manage_menu_availability', p_manage_menu_availability,
              'manage_table_operations', p_manage_table_operations)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_staff_capabilities', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (c) resolve the target: the employee_profile AND its authoritative membership
  --     in ONE coherent lookup, proving they are the SAME person (ep.membership_id
  --     = m.id, same organization, same app_user_id). Authorization AND the UPDATE
  --     both derive from the MEMBERSHIP's OWN scope (the row that will be mutated),
  --     NEVER the profile's -- a profile in branch A pointing at a branch-B
  --     membership can no longer authorize a branch-B mutation. A missing / deleted
  --     / inactive / mismatched (profile<->membership) target, a target outside the
  --     caller's covering scope, and a cross-tenant target ALL collapse to ONE
  --     fail-closed 42501 with an IDENTICAL message (no existence/scope oracle).
  select m.organization_id, m.restaurant_id, m.branch_id, m.id, m.role, m.status, m.deleted_at, m.permissions
    into v_org, v_rest, v_branch, v_membership, v_role, v_m_status, v_m_deleted, v_perms
    from public.employee_profiles ep
    join public.memberships m
      on m.id              = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.app_user_id     = ep.app_user_id
    where ep.id = p_employee_profile_id and ep.deleted_at is null;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'set_staff_capabilities: employee not found or not in caller scope' using errcode = '42501';
  end if;
  -- authority is measured against the MEMBERSHIP scope (downward-only coverage:
  -- an org/restaurant owner legitimately covers a branch; a branch manager does
  -- not cover a sibling branch). 0 => outside coverage => SAME 42501 as not-found.
  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_staff_capabilities: employee not found or not in caller scope' using errcode = '42501';
  end if;
  -- (d) rank >= manager AND strictly outrank the target. An IN-SCOPE but
  --     insufficient-rank actor gets a DURABLE staff.capabilities_denied audit +
  --     permission_denied (RETURNED, so the audit persists -- see the report note
  --     on why the not-found/cross-tenant RAISE paths cannot be durably audited).
  if v_rank < 2 or v_rank <= app.role_rank(v_role) then
    perform app.management_audit(v_org, v_rest, v_branch,
      'staff.capabilities_denied', null,
      jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership, 'target_role', v_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;
  -- these three toggles exist only for the cashier role.
  if v_role <> 'cashier' then
    raise exception 'set_staff_capabilities: capabilities apply only to the cashier role' using errcode = '42501';
  end if;

  -- (e) build the new permissions -- deny-only storage: canonical JSON string
  --     "false" to deny, drop the key to allow (role default ON). Only the three
  --     keys are ever touched; UNRELATED permission keys are preserved verbatim.
  v_new_perms := coalesce(v_perms, '{}'::jsonb);
  v_new_perms := case when p_apply_discount then v_new_perms - 'apply_discount'
                      else jsonb_set(v_new_perms, '{apply_discount}', '"false"'::jsonb) end;
  v_new_perms := case when p_void_order then v_new_perms - 'void_order'
                      else jsonb_set(v_new_perms, '{void_order}', '"false"'::jsonb) end;
  v_new_perms := case when p_close_shift then v_new_perms - 'close_shift'
                      else jsonb_set(v_new_perms, '{close_shift}', '"false"'::jsonb) end;
  -- FULL-COMP-PERMISSION-001 -- INVERTED STORAGE. The three above are DENY-ONLY
  -- (default ON: absence allows, the string "false" denies). Full-comp is the
  -- opposite: DEFAULT OFF, so a GRANT writes the canonical string "true" and a
  -- REVOKE removes the key. Absence therefore DENIES, so every existing cashier
  -- (permissions '{}') stays denied by construction -- no backfill, no migration
  -- of data, and no cashier silently gains the right to give food away.
  v_new_perms := case when p_apply_full_comp
                      then jsonb_set(v_new_perms, '{apply_full_comp}', '"true"'::jsonb)
                      else v_new_perms - 'apply_full_comp' end;
  -- PILOT-OPERATIONS-CORRECTIONS-001: two DEFAULT-ON (deny-only) capabilities, same
  -- polarity as the original three -- ON removes the key (role default), OFF stores "false".
  v_new_perms := case when p_manage_menu_availability then v_new_perms - 'manage_menu_availability'
                      else jsonb_set(v_new_perms, '{manage_menu_availability}', '"false"'::jsonb) end;
  v_new_perms := case when p_manage_table_operations then v_new_perms - 'manage_table_operations'
                      else jsonb_set(v_new_perms, '{manage_table_operations}', '"false"'::jsonb) end;

  -- (f) claim idempotency BEFORE mutating (race-safe), then a SCOPE-PREDICATED
  --     update (the predicates re-assert the membership's own scope; the UPDATE
  --     does not rely only on the prior SELECT) + audit with OLD and NEW raw
  --     permissions and effective values.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false,
                'entity', 'employee_profile', 'employee_profile_id', p_employee_profile_id,
                'membership_id', v_membership,
                'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
                  'void_order', p_void_order, 'close_shift', p_close_shift,
                  'apply_full_comp', p_apply_full_comp,
                  'manage_menu_availability', p_manage_menu_availability,
                  'manage_table_operations', p_manage_table_operations));
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_staff_capabilities', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  update public.memberships
     set permissions = v_new_perms, updated_at = now()
   where id = v_membership and organization_id = v_org
     and restaurant_id is not distinct from v_rest
     and branch_id     is not distinct from v_branch;

  perform app.management_audit(v_org, v_rest, v_branch, 'staff.capabilities_updated',
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership,
      'permissions', v_perms,
      'capabilities', jsonb_build_object(
        'apply_discount',  app.cashier_capability_allowed('cashier', v_perms, 'apply_discount'),
        'void_order',      app.cashier_capability_allowed('cashier', v_perms, 'void_order'),
        'close_shift',     app.cashier_capability_allowed('cashier', v_perms, 'close_shift'),
        'apply_full_comp', app.cashier_capability_granted('cashier', v_perms, 'apply_full_comp'),
        'manage_menu_availability', app.cashier_capability_allowed('cashier', v_perms, 'manage_menu_availability'),
        'manage_table_operations', app.cashier_capability_allowed('cashier', v_perms, 'manage_table_operations'))),
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership,
      'permissions', v_new_perms,
      'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
        'void_order', p_void_order, 'close_shift', p_close_shift,
        'apply_full_comp', p_apply_full_comp,
        'manage_menu_availability', p_manage_menu_availability,
        'manage_table_operations', p_manage_table_operations)));

  return v_result;
end;
$$;

comment on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) is
  'STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001 + PILOT-OPERATIONS-CORRECTIONS-001: owner/manager sets a target CASHIER''s capabilities. Deny-only / default-ON toggles (apply_discount, void_order, close_shift, manage_menu_availability, manage_table_operations): OFF stores the JSON string "false", ON removes the key. Grant-only / default-OFF (apply_full_comp): ON stores "true", OFF removes the key. Unrelated permission keys preserved verbatim. Tenant + branch + role-rank scoped (caller must COVER the target scope AND rank >= manager AND STRICTLY OUTRANK the target; cross-tenant/not-found collapse to ONE 42501, no R-003 oracle). Cashier-role-only. Idempotent -- all six toggles are part of the fingerprint. Audited staff.capabilities_updated with OLD/NEW raw permissions AND effective capabilities; an in-scope insufficient-rank actor gets a durable staff.capabilities_denied + permission_denied.';

create or replace function public.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean,
  p_apply_full_comp     boolean default false,
  p_manage_menu_availability boolean default true,
  p_manage_table_operations  boolean default true
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$
  select app.set_staff_capabilities(p_client_request_id, p_employee_profile_id,
                                    p_apply_discount, p_void_order, p_close_shift,
                                    p_apply_full_comp,
                                    p_manage_menu_availability, p_manage_table_operations);
$$;

comment on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) is
  'PILOT-OPERATIONS-CORRECTIONS-001: PUBLIC (PostgREST-reachable) INVOKER wrapper over the 8-arg app.set_staff_capabilities. Re-created after the arity change. Carries no authority of its own.';

revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) from public;
revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) from anon;
grant execute on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;
revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) from public;
revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) from anon;
grant execute on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. app.create_staff_member -- the initial-capabilities validator accepts the two
--    new DEFAULT-ON keys (deny-only: may only ever be DENIED with the string
--    "false"); the staff.created audit records their effective values. CREATE OR
--    REPLACE (same 7-arg signature keeps ACLs).
-- ---------------------------------------------------------------------------
create or replace function app.create_staff_member(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_display_name      text,
  p_role              text,
  p_capabilities      jsonb   default null   -- STAFF-CASHIER-PERMISSIONS-001: initial cashier deny overrides (atomic)
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_name       text;
  v_fp         text;
  v_replay     jsonb;
  v_app_user   uuid := gen_random_uuid();
  v_membership uuid := gen_random_uuid();
  v_employee   uuid := gen_random_uuid();
  v_email      text;
  v_result     jsonb;
  v_new        jsonb;
  v_perms      jsonb := '{}'::jsonb;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'create_staff_member: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_staff_member: client_request_id is required' using errcode = '42501';
  end if;
  -- staff operators are branch-scoped (they work a PIN pad at a branch)
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'create_staff_member: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;

  -- (b) structural validation
  v_name := btrim(coalesce(p_display_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_staff_member: display_name is required' using errcode = '42501';
  end if;
  -- only operator roles are creatable here (owners are onboarded/granted via
  -- create_organization / grant_membership, never as PIN-only staff).
  if p_role is null or p_role not in ('cashier', 'kitchen_staff', 'manager') then
    raise exception 'create_staff_member: role must be cashier, kitchen_staff or manager' using errcode = '42501';
  end if;
  -- STAFF-CASHIER-PERMISSIONS-001: OPTIONAL initial cashier capability DENY
  -- overrides, persisted ATOMICALLY with the membership in THIS transaction (no
  -- fail-open create-then-set). Fail-closed + deny-only: only role=cashier, only
  -- the three named keys, only the string 'false' (absence/'true' => role default
  -- ON, so those are never stored). Anything else raises => nothing is created.
  if p_capabilities is not null and p_capabilities <> '{}'::jsonb then
    if jsonb_typeof(p_capabilities) <> 'object' then
      raise exception 'create_staff_member: capabilities must be a JSON object' using errcode = '42501';
    end if;
    if p_role <> 'cashier' then
      raise exception 'create_staff_member: capabilities apply only to the cashier role' using errcode = '42501';
    end if;
    -- STRICT + fail-closed: iterate with jsonb_each (NO text coercion). Every key
    -- must be one of the three canonical keys AND every value must be the exact
    -- JSON STRING "false". Rejects JSON null / boolean false / boolean true /
    -- string "true" / numbers / arrays / nested objects / unknown keys / mixed
    -- payloads (a scalar/array/null ROOT is already rejected by the object check).
    -- FULL-COMP-PERMISSION-001: TWO storage polarities now coexist, and each key is
    -- validated against ITS OWN one. The three default-ON keys may only ever be
    -- DENIED (the JSON string "false"). apply_full_comp is DEFAULT-OFF and may only
    -- ever be GRANTED (the JSON string "true"). Anything else -- a "true" on a
    -- default-ON key, a "false" on full-comp (that is already the default, so
    -- storing it would be meaningless noise), a boolean, a number, null, an array,
    -- an object, or an unknown key -- RAISES, and nothing is created. Fail-closed;
    -- no silent coercion of a malformed grant into a real one.
    if exists (
         select 1 from jsonb_each(p_capabilities) e
         where jsonb_typeof(e.value) <> 'string'
            or e.key not in ('apply_discount', 'void_order', 'close_shift', 'apply_full_comp', 'manage_menu_availability', 'manage_table_operations')
            or (e.key in ('apply_discount', 'void_order', 'close_shift', 'manage_menu_availability', 'manage_table_operations')
                and e.value <> '"false"'::jsonb)
            or (e.key = 'apply_full_comp' and e.value <> '"true"'::jsonb)) then
      raise exception 'create_staff_member: capabilities may only DENY (JSON string "false") apply_discount/void_order/close_shift or GRANT (JSON string "true") apply_full_comp' using errcode = '42501';
    end if;
    v_perms := p_capabilities;
  end if;
  -- target branch + parent restaurant must exist in the org AND be LIVE (RF-112 rule:
  -- never create authority on a dead scope).
  if not exists (
       select 1 from public.branches b
       join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'create_staff_member: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  -- (c) committed idempotent replay (before authorization -> true idempotency;
  --     mirrors grant_membership). Fingerprint carries NO secret (there is none here).
  -- STAFF-CASHIER-PERMISSIONS-001 (idempotency legacy compat): with NO initial
  -- denies (p_capabilities NULL/{} -> v_perms {}) compute the EXACT pre-migration
  -- fingerprint (no capabilities component) so a request created before this
  -- migration replays after it. Only when real denies exist do we extend the
  -- fingerprint with a canonical representation -- v_perms is jsonb, so equivalent
  -- deny objects (any key order) share one canonical text (key order is irrelevant).
  if v_perms = '{}'::jsonb then
    v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
                'branch', p_branch_id, 'display_name', v_name, 'role', p_role)::text);
  else
    v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
                'branch', p_branch_id, 'display_name', v_name, 'role', p_role,
                'capabilities', v_perms)::text);
  end if;
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'create_staff_member', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (d) authorization (GUC-free + role-rank guard). 0 => no covering membership => 42501.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'create_staff_member: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  -- caller IS a covering member from here -> denials are audited permission_denied:
  -- rank >= manager required AND the caller must STRICTLY outrank the assigned role.
  if v_rank < 2 or v_rank <= app.role_rank(p_role) then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'staff.create_denied', null,
      jsonb_build_object('display_name', v_name, 'role', p_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  -- (e) claim idempotency BEFORE mutating (race-safe), then create the three rows + audit.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'employee_profile',
                'employee_profile_id', v_employee, 'membership_id', v_membership,
                'app_user_id', v_app_user, 'role', p_role);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'create_staff_member', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- synthetic, unique, lowercase identifier email (RFC-2606 .invalid TLD): PIN-only
  -- operators have NO login account; this is ONLY an identifier (D-004 preserved --
  -- each operator is their own person/identity, never a shared account).
  v_email := 'staff-' || replace(gen_random_uuid()::text, '-', '') || '@pin.restoflow.invalid';

  insert into public.app_users (id, email, display_name, is_active)
  values (v_app_user, v_email, v_name, true);

  insert into public.memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status, permissions)
  values (v_membership, v_app_user, p_organization_id, p_restaurant_id, p_branch_id, p_role, 'active', v_perms);

  insert into public.employee_profiles
    (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id,
     display_name, employment_status, pin_credential_ref)
  values
    (v_employee, p_organization_id, p_restaurant_id, p_branch_id, v_app_user, v_membership,
     v_name, 'active', null);  -- NO PIN yet: provisioned separately via set_employee_pin

  -- audit (D-013): the profile post-image WITHOUT the credential column (defensive --
  -- it is NULL here, but audit must structurally never carry PIN material).
  select to_jsonb(t) - 'pin_credential_ref' into v_new
    from public.employee_profiles t where t.id = v_employee;
  -- STAFF-CASHIER-PERMISSIONS-001: include the initial canonical deny overrides
  -- (v_perms: {} when none) and the effective capability values for a cashier, so
  -- staff.created records the exact provisioned capabilities. No PIN/secret data.
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'staff.created', null,
    v_new || jsonb_build_object('membership_id', v_membership, 'app_user_id', v_app_user, 'role', p_role,
      'permissions', v_perms,
      'capabilities', case when p_role = 'cashier' then jsonb_build_object(
          'apply_discount',  app.cashier_capability_allowed('cashier', v_perms, 'apply_discount'),
          'void_order',      app.cashier_capability_allowed('cashier', v_perms, 'void_order'),
          'close_shift',     app.cashier_capability_allowed('cashier', v_perms, 'close_shift'),
          'apply_full_comp', app.cashier_capability_granted('cashier', v_perms, 'apply_full_comp'),
          'manage_menu_availability', app.cashier_capability_allowed('cashier', v_perms, 'manage_menu_availability'),
          'manage_table_operations', app.cashier_capability_allowed('cashier', v_perms, 'manage_table_operations'))
        else null end));
  return v_result;
end;
$$;

comment on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb) is
  'MVP staff provisioning + STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001 + PILOT-OPERATIONS-CORRECTIONS-001: creates employee_profile + membership atomically with OPTIONAL initial cashier capabilities. The validator is fail-closed and polarity-aware: apply_discount/void_order/close_shift/manage_menu_availability/manage_table_operations may only ever be DENIED (JSON string "false"); apply_full_comp may only ever be GRANTED ("true"). Any unknown key, non-string value, a "true" on a deny-only key, or a "false" on the grant-only key RAISES 42501 and nothing is created. Cashier-role-only. Audited staff.created (projected) with the effective capabilities.';

-- ---------------------------------------------------------------------------
-- 5. app.list_staff -- each cashier row's effective capabilities gain the two new
--    booleans (deny-only resolver). CREATE OR REPLACE (same signature keeps ACLs).
-- ---------------------------------------------------------------------------
create or replace function app.list_staff(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
begin
  if v_actor is null then
    raise exception 'list_staff: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_staff: organization_id is required' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_staff: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot list staff
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'employee_profile_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'employee_profile_id', ep.id,
      'display_name',        ep.display_name,
      'employee_number',     ep.employee_number,
      'role',                m.role,
      'employment_status',   ep.employment_status,
      'has_pin',             (ep.pin_credential_ref is not null),  -- boolean ONLY; never the ref
      'restaurant_id',       ep.restaurant_id,
      'branch_id',           ep.branch_id,
      'created_at',          ep.created_at,
      'capabilities',        jsonb_build_object(
        'apply_discount',  app.cashier_capability_allowed(m.role, m.permissions, 'apply_discount'),
        'void_order',      app.cashier_capability_allowed(m.role, m.permissions, 'void_order'),
        'close_shift',     app.cashier_capability_allowed(m.role, m.permissions, 'close_shift'),
        -- FULL-COMP-PERMISSION-001: default-OFF, so it resolves through the GRANT
        -- resolver, not the deny-only one. A cashier with no override reports false.
        'apply_full_comp', app.cashier_capability_granted(m.role, m.permissions, 'apply_full_comp'),
        'manage_menu_availability', app.cashier_capability_allowed(m.role, m.permissions, 'manage_menu_availability'),
        'manage_table_operations', app.cashier_capability_allowed(m.role, m.permissions, 'manage_table_operations'))
    ) as item
    from public.employee_profiles ep
    join public.memberships m
      on m.id = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.status = 'active'
     and m.deleted_at is null
    where ep.organization_id = p_organization_id
      and (p_restaurant_id is null or ep.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or ep.branch_id     = p_branch_id)
      and ep.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'employee_profile', 'staff', v_items);
end;
$$;

comment on function app.list_staff(uuid, uuid, uuid) is
  'MVP staff list + STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001 + PILOT-OPERATIONS-CORRECTIONS-001: per-row `capabilities` now carries SIX effective booleans -- apply_discount/void_order/close_shift/manage_menu_availability/manage_table_operations via the DENY-ONLY resolver, apply_full_comp via the GRANT-ONLY resolver. Non-cashier rows report false (toggles apply only to the cashier role; owners/managers hold these BY ROLE). Owner/manager-only, read-only, otherwise verbatim.';

-- ---------------------------------------------------------------------------
-- 6. app.audit_safe_detail -- the nested `capabilities` allowlist gains the two new
--    keys so the staff.capabilities_updated / staff.created Activity-Log projection
--    shows them. CREATE OR REPLACE (same signature keeps ACLs). audit_action_has_detail
--    is UNCHANGED (staff.capabilities%/staff.created already carry detail).
-- ---------------------------------------------------------------------------
create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state',
    -- RESTAURANT-OPERATIONS-V1-001: branch availability (closed enums
    -- available|unavailable / sold_out|paused) + the menu item's display name,
    -- and table-move floor labels (human table names). Names/labels are tenant
    -- display text already shown on receipts/tickets — never money, never ids.
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label'
  ] loop
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its four
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;

comment on function app.audit_safe_detail(text, jsonb) is
  'AUDIT-LOG-DASHBOARD-001 .. RESTAURANT-OPERATIONS-V1-001 + PILOT-OPERATIONS-CORRECTIONS-001: ALLOWLIST projection of one audit payload to canonical safe fields. Unchanged except the nested `capabilities` object now keeps SIX boolean keys (apply_discount/void_order/close_shift/apply_full_comp/manage_menu_availability/manage_table_operations). Every un-listed key and nested structure is DROPPED; malformed -> ''{}''; never throws. Server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   restore app.cashier_capability_allowed / app.list_staff / app.create_staff_member
--     / app.audit_safe_detail from their prior bodies (20260710110000 / 20260717090000
--     / 20260719110000);
--   restore app.pin_session_capabilities from 20260717120000;
--   drop function if exists public.set_staff_capabilities(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean);
--   drop function if exists app.set_staff_capabilities(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean);
--   restore app.set_staff_capabilities(...,6-arg) + wrapper from 20260717090000.
-- ============================================================================
