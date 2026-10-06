-- ============================================================================
-- POS-CASH-DRAWER-MANUAL-OPEN-001 -- an audited, permissioned MANUAL ("no-sale")
-- cash-drawer open from the POS.
-- ============================================================================
-- Owner decisions (2026-10-06):
--   * a POS button opens the cash drawer outside a sale;
--   * EVERY manual open is recorded (actor, device, branch, time) and shows in the
--     owner's Activity Log (PRINTERS_AND_HARDWARE_SPEC.md section 11, D-013);
--   * a NEW per-employee permission "open_cash_drawer": DEFAULT OFF for cashiers
--     (grant-only, the apply_full_comp polarity), held BY ROLE by manager /
--     restaurant_owner / org_owner, never by kitchen_staff / accountant;
--   * the POS button starts LOCKED for every PIN session; the FIRST open needs the
--     signed-in employee's OWN PIN, verified SERVER-SIDE (the PIN / a PIN hash never
--     lives on the device, D-006); after that a single tap opens the drawer until the
--     employee locks it again (long press) or the session ends;
--   * no free-text reason (the owner chose a one-tap open); the audit records the
--     actor, device, role and the bound drawer/shift instead;
--   * offline: an UNLOCKED button keeps working and the open is recorded through the
--     normal sync_push ledger when the connection returns (D-010 / D-022).
--
-- WHAT THIS MIGRATION ADDS / CHANGES (byte-faithful re-emits + ONLY the delta):
--   1. app.cashier_capability_granted -- 'open_cash_drawer' joins the grant-only set.
--   2. app.pin_session_capabilities   -- + effective 'open_cash_drawer' (POS advisory).
--   3. app.set_staff_capabilities     -- 8-arg -> 9-arg: p_open_cash_drawer DEFAULT
--      NULL = LEAVE UNCHANGED, so an older Dashboard that never sends it can never
--      silently revoke a grant. DROP + re-create (arity change) of app + public.
--   4. app.create_staff_member        -- validator accepts {"open_cash_drawer":"true"}.
--   5. app.list_staff                 -- + effective 'open_cash_drawer' per row.
--   6. app.audit_safe_detail          -- nested capabilities allowlist + the new key.
--   7. sync_operations CHECK          -- + 'cash_drawer.no_sale_open'.
--   8. app.pos_record_drawer_no_sale  -- NEW business function (reached ONLY via
--      sync_push): permission gate + audit cash_drawer.no_sale_opened / _denied.
--   9. app.sync_push                  -- re-emitted from its LIVE body with the new
--      op in BOTH allowlists (valid + revoked-device paths) and ONE dispatch arm.
--  10. app/public.pos_verify_drawer_pin -- NEW authenticated-only PIN check for the
--      unlock (reuses app.verify_pin_credential + the pin_attempt_states lockout of
--      start_pin_session; failures audited as cash_drawer.unlock_failed).
-- Global surface invariants are re-asserted at the foot (either #288 apply order).
-- Forward-only. NOT applied to hosted by this migration.
-- ============================================================================

-- 1. app.cashier_capability_granted -- + open_cash_drawer (grant-only, default OFF).
create or replace function app.cashier_capability_granted(
  p_role        text,
  p_permissions jsonb,
  p_capability  text
)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  -- FAIL-CLOSED. A default-OFF capability is GRANTED only by the EXPLICIT presence
  -- of the canonical JSON string "true". Absence DENIES (the role default). A JSON
  -- boolean true, the number 1, "TRUE"/"yes", null, an array, an object, a non-object
  -- permissions blob, a SQL NULL, every non-cashier role, and any capability outside
  -- the named grant-only set ALL DENY. There is no coercion anywhere: a malformed
  -- permissions payload can never manufacture the right to give food away.
  --
  -- THE coalesce IS LOAD-BEARING, NOT DEFENSIVE NOISE. `jsonb -> key` on a MISSING
  -- key returns SQL NULL, and `NULL = '"true"'::jsonb` is NULL -- which would poison
  -- the whole AND chain and make this function return NULL (not false) for the single
  -- most common input in the system: a cashier with no override. NULL is NOT false:
  -- the caller's guard reads `if ... and not v_may_comp then`, and `not NULL` is NULL,
  -- so the branch would NEVER FIRE and an UNGRANTED CASHIER COULD COMP THE ORDER --
  -- a fail-OPEN on the one permission that gives food away. coalesce(..., false)
  -- collapses NULL to a hard false. (The deny-only resolver is safe without this only
  -- because the `?` operator returns a strict boolean and never NULL.)
  select coalesce(
           p_role = 'cashier'
           and p_capability in ('apply_full_comp', 'open_cash_drawer')
           and p_permissions is not null
           and jsonb_typeof(p_permissions) = 'object'
           and p_permissions -> p_capability = '"true"'::jsonb,
         false);
$$;
comment on function app.cashier_capability_granted(text, jsonb, text) is
  'FULL-COMP-PERMISSION-001 + POS-CASH-DRAWER-MANUAL-OPEN-001: FAIL-CLOSED GRANT-ONLY (default-OFF) per-cashier capability resolver -- the polarity MIRROR of app.cashier_capability_allowed (deny-only/default-ON, unchanged). TRUE iff role=cashier AND the capability is one of the named grant-only keys (apply_full_comp, open_cash_drawer) AND permissions is a well-formed JSON object AND the key is PRESENT carrying exactly the canonical JSON string "true". ABSENCE DENIES (no backfill). Every malformed present value DENIES. Non-object / JSON-null / SQL-NULL permissions, every non-cashier role, and any capability outside the grant-only set all DENY. Callers OR it with their owner/manager role grants, so it never widens another role.';
revoke all on function app.cashier_capability_granted(text, jsonb, text) from public;
revoke all on function app.cashier_capability_granted(text, jsonb, text) from anon;
revoke all on function app.cashier_capability_granted(text, jsonb, text) from authenticated;

-- 2. app.pin_session_capabilities -- + open_cash_drawer (same signature; ACLs re-issued).
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
        or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_table_operations'),
      -- POS-CASH-DRAWER-MANUAL-OPEN-001: manual drawer open. manager+ BY ROLE, or a
      -- cashier the owner explicitly GRANTED (grant-only => absence denies).
      'open_cash_drawer',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_granted(v_role, v_m_perms, 'open_cash_drawer')));
end;
$$;
comment on function app.pin_session_capabilities(uuid, uuid) is
  'PILOT-OPERATIONS-CORRECTIONS-001 + POS-CASH-DRAWER-MANUAL-OPEN-001: READ-ONLY effective-capability projection for an ACTIVE PIN session on a PAIRED device (canonical hotfix preamble). Returns FIVE effective booleans: apply_discount, apply_full_comp, manage_menu_availability, manage_table_operations, open_cash_drawer (manager+ by role OR the cashier capability in its own polarity). ADVISORY ONLY -- the server re-decides on every mutation. Every invalid/expired/revoked/device- or scope-mismatched/inactive-membership session collapses to ONE indistinguishable invalid_session envelope (no probe oracle, R-003). No money, no PIN material, no identifier beyond the role.';
revoke all on function app.pin_session_capabilities(uuid, uuid) from public;
revoke all on function app.pin_session_capabilities(uuid, uuid) from anon;
grant execute on function app.pin_session_capabilities(uuid, uuid) to authenticated;

-- 3. app.set_staff_capabilities -- 8-arg -> 9-arg. A CHANGED SIGNATURE cannot use
--    CREATE OR REPLACE (PostgREST would see two overloads), so DROP + re-create the
--    public wrapper and the app function; ACLs re-applied below.
drop function if exists public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean);
drop function if exists app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean);
create function app.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean,
  p_apply_full_comp     boolean default false,  -- FULL-COMP-PERMISSION-001 (default OFF)
  p_manage_menu_availability boolean default true,  -- PILOT-OPERATIONS-CORRECTIONS-001 (default ON)
  p_manage_table_operations  boolean default true,  -- PILOT-OPERATIONS-CORRECTIONS-001 (default ON)
  p_open_cash_drawer         boolean default null   -- POS-CASH-DRAWER-MANUAL-OPEN-001 (grant-only; NULL = leave unchanged)
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
              'manage_table_operations', p_manage_table_operations,
              'open_cash_drawer', p_open_cash_drawer)::text);
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
  -- POS-CASH-DRAWER-MANUAL-OPEN-001: GRANT-ONLY (default OFF, the apply_full_comp
  -- polarity): ON stores the canonical string "true", OFF removes the key. NULL --
  -- an older client that predates the toggle -- LEAVES the stored state untouched,
  -- so saving any other toggle can never silently revoke a drawer grant.
  if p_open_cash_drawer is not null then
    v_new_perms := case when p_open_cash_drawer
                        then jsonb_set(v_new_perms, '{open_cash_drawer}', '"true"'::jsonb)
                        else v_new_perms - 'open_cash_drawer' end;
  end if;

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
                  'manage_table_operations', p_manage_table_operations,
                  'open_cash_drawer', app.cashier_capability_granted('cashier', v_new_perms, 'open_cash_drawer')));
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
        'manage_table_operations', app.cashier_capability_allowed('cashier', v_perms, 'manage_table_operations'),
        'open_cash_drawer', app.cashier_capability_granted('cashier', v_perms, 'open_cash_drawer'))),
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership,
      'permissions', v_new_perms,
      'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
        'void_order', p_void_order, 'close_shift', p_close_shift,
        'apply_full_comp', p_apply_full_comp,
        'manage_menu_availability', p_manage_menu_availability,
        'manage_table_operations', p_manage_table_operations,
        'open_cash_drawer', app.cashier_capability_granted('cashier', v_new_perms, 'open_cash_drawer'))));

  return v_result;
end;
$$;
comment on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) is
  'STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001 + PILOT-OPERATIONS-CORRECTIONS-001 + POS-CASH-DRAWER-MANUAL-OPEN-001: owner/manager sets a target CASHIER''s capabilities. Deny-only / default-ON toggles (apply_discount, void_order, close_shift, manage_menu_availability, manage_table_operations): OFF stores the JSON string "false", ON removes the key. Grant-only / default-OFF (apply_full_comp, open_cash_drawer): ON stores "true", OFF removes the key; p_open_cash_drawer NULL leaves the stored state UNCHANGED (older clients). Unrelated permission keys preserved verbatim. Tenant + branch + role-rank scoped (caller must COVER the target scope AND rank >= manager AND STRICTLY OUTRANK the target; cross-tenant/not-found collapse to ONE 42501, no R-003 oracle). Cashier-role-only. Idempotent -- all toggles are part of the fingerprint. Audited staff.capabilities_updated with OLD/NEW raw permissions AND effective capabilities; an in-scope insufficient-rank actor gets a durable staff.capabilities_denied + permission_denied.';

create or replace function public.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean,
  p_apply_full_comp     boolean default false,
  p_manage_menu_availability boolean default true,
  p_manage_table_operations  boolean default true,
  p_open_cash_drawer         boolean default null
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
                                    p_manage_menu_availability, p_manage_table_operations,
                                    p_open_cash_drawer);
$$;

comment on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) is
  'POS-CASH-DRAWER-MANUAL-OPEN-001: PUBLIC (PostgREST-reachable) INVOKER wrapper over the 9-arg app.set_staff_capabilities. Re-created after the arity change. Carries no authority of its own.';

revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from public;
revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from anon;
grant execute on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;
revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from public;
revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) from anon;
grant execute on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;

-- 4. app.create_staff_member -- accepts the grant-only open_cash_drawer key (same 7-arg signature).
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
            or e.key not in ('apply_discount', 'void_order', 'close_shift', 'apply_full_comp', 'manage_menu_availability', 'manage_table_operations', 'open_cash_drawer')
            or (e.key in ('apply_discount', 'void_order', 'close_shift', 'manage_menu_availability', 'manage_table_operations')
                and e.value <> '"false"'::jsonb)
            or (e.key in ('apply_full_comp', 'open_cash_drawer') and e.value <> '"true"'::jsonb)) then
      raise exception 'create_staff_member: capabilities may only DENY (JSON string "false") apply_discount/void_order/close_shift or GRANT (JSON string "true") apply_full_comp/open_cash_drawer' using errcode = '42501';
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
          'manage_table_operations', app.cashier_capability_allowed('cashier', v_perms, 'manage_table_operations'),
          'open_cash_drawer', app.cashier_capability_granted('cashier', v_perms, 'open_cash_drawer'))
        else null end));
  return v_result;
end;
$$;

-- 5. app.list_staff -- + effective open_cash_drawer per row (same signature).
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
        'manage_table_operations', app.cashier_capability_allowed(m.role, m.permissions, 'manage_table_operations'),
        -- POS-CASH-DRAWER-MANUAL-OPEN-001: grant-only (default OFF) like apply_full_comp.
        'open_cash_drawer', app.cashier_capability_granted(m.role, m.permissions, 'open_cash_drawer'))
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

-- 6. app.audit_safe_detail -- the nested capabilities allowlist gains open_cash_drawer.
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
    'dispatch_mode',   -- KITCHEN-PRINT-DUAL-001C: closed dispatch enum (kds|direct_print); money-free state (T-003)
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
    'table_label','from_table_label','to_table_label',
    -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status transition
    -- (closed enum available|reserved|occupied|out_of_service) + the combined
    -- group label (floor names). Never money, never identifiers (T-003 holds).
    'from_status','to_status','group_label',
    -- PSC-001D: void provenance + kitchen acknowledgement. voided_from_status
    -- is the closed order-status enum; device_type is the closed pos|kds enum;
    -- kitchen_ack_required is a boolean. Never money, never identifiers
    -- (T-003 holds).
    'voided_from_status','device_type','kitchen_ack_required',
    -- PSC-001C: service rounds. round_number and added_item_count are small
    -- integers (a position in the order and a line count) — never money,
    -- never identifiers (T-003 holds).
    'round_number','added_item_count',
    -- KITCHEN-MODE-001B: printer configuration scalars. display_name is tenant
    -- display text (the item_name/table_label class); the rest are closed
    -- enums/booleans. connection_config (host/port/addresses) is a NESTED
    -- OBJECT and is therefore structurally dropped by the scalar-only rule —
    -- endpoints never reach the Activity Log timeline.
    'display_name','paper_width','is_enabled','connection_type',
    -- KITCHEN-MODE-001C1: kitchen dispatch safe scalars (closed enum + the
    -- existing safe order_code class). The money_free_payload itself is
    -- NEVER projected into audit detail.
    'dispatch_type',
    -- KITCHEN-MODE-001C3A: the kitchen-mode family scalars. kitchen_workflow_mode
    -- is the closed kds|printer_only enum; kitchen_workflow_mode_revision is a
    -- small positive integer (never money, never an identifier — T-003 holds);
    -- resolution / reason_code are CLOSED safe state tokens written only by the
    -- future 001C3B owner setter + hold resolution (human-actor paths). NOTE:
    -- settings.branch.updated projects full branch-row snapshots, so the mode
    -- and revision now also surface there — both are safe display state, the
    -- timezone/name class.
    'kitchen_workflow_mode','kitchen_workflow_mode_revision','resolution','reason_code'
  ] loop
    -- PSC-001C correction (Finding 6): the four service-round actions are
    -- MONEY-FREE by approved contract — any *_minor key (hostile, manual, or
    -- accidental) is dropped for EXACTLY these actions, action-specifically:
    -- the approved money-carrying actions (payments / discounts / shifts /
    -- order.submitted / completion) keep their allowlisted money keys.
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        -- KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        -- the same hostile-key hardening applies to the whole printer family.
        or p_action like 'printer.%'
        -- KITCHEN-MODE-001C1: kitchen dispatch events are MONEY-FREE too.
        or p_action like 'kitchen.%')
       and v_key like '%\_minor' escape '\' then
      continue;
    end if;
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
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations','open_cash_drawer']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;

-- 7. sync_operations.operation_type CHECK -- + 'cash_drawer.no_sale_open' (the
--    latest list from 20260821090000_kiosk_001 plus the new value).
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'kiosk.order.submit', 'cash_drawer.no_sale_open'));

-- 8. app.pos_record_drawer_no_sale -- the business function behind the
--    'cash_drawer.no_sale_open' sync op. Reached ONLY via app.sync_push, which owns
--    transport idempotency (D-022: device_id + local_operation_id), the revoked-
--    device path and the per-op rejection ledger. The physical pulse happens on the
--    device; this records WHO opened WHICH till's drawer, and refuses (audited) when
--    the actor lacks the right. A no-sale open is an AUDIT-ONLY event: it changes no
--    shift / drawer-session state (STATE_MACHINES section 7, D-018) and moves no money.
create function app.pos_record_drawer_no_sale(
  p_pin_session_id      uuid,
  p_device_id           uuid,
  p_client_occurred_at  timestamptz default null
)
  returns jsonb
  language plpgsql
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
  v_m_perms    jsonb;
  v_dtype      text;
  v_shift_id   uuid;
  v_drawer_id  uuid;
begin
  -- (a) canonical PIN-session preamble (the app.pos_set_table_status shape: a dead
  --     session/device/membership RAISES 42501, which app.sync_push records as a
  --     per-op rejection -- 'revoked_employee' for a dead membership).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then raise exception 'pos_record_drawer_no_sale: PIN session not found' using errcode='42501'; end if;
  if not app.is_pin_session_valid(p_pin_session_id) then raise exception 'pos_record_drawer_no_sale: PIN session is not valid' using errcode='42501'; end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_record_drawer_no_sale: backing device session/pairing is not active' using errcode='42501'; end if;
  if v_ds_device <> p_device_id then raise exception 'pos_record_drawer_no_sale: device_id does not match the PIN session device' using errcode='42501'; end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_record_drawer_no_sale: resolved membership is not active' using errcode='42501'; end if;

  -- (b) only a POS till has a cash drawer. A KDS/kiosk device is refused (typed).
  select d.device_type into v_dtype
    from public.devices d where d.id = p_device_id and d.organization_id = v_org;
  if v_dtype is distinct from 'pos' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'cash_drawer.no_sale_denied', null, null,
            jsonb_build_object('role', v_role, 'denied_reason', 'permission_denied', 'device_type', v_dtype,
                               'client_occurred_at', p_client_occurred_at, 'resolved_membership_id', v_membership));
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'cash_drawer');
  end if;

  -- (c) the permission: manager+ BY ROLE, or a cashier GRANTED open_cash_drawer.
  --     kitchen_staff / accountant never hold it (the resolver denies every
  --     non-cashier role). A refusal RETURNS (so the denial audit persists).
  if not ((v_role in ('manager', 'restaurant_owner', 'org_owner'))
          or app.cashier_capability_granted(v_role, v_m_perms, 'open_cash_drawer')) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'cash_drawer.no_sale_denied', null, null,
            jsonb_build_object('role', v_role, 'denied_reason', 'permission_denied',
                               'client_occurred_at', p_client_occurred_at, 'resolved_membership_id', v_membership));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'cash_drawer');
  end if;

  -- (d) bind the event to this till's current shift / drawer session when one is
  --     open (PRINTERS_AND_HARDWARE_SPEC section 11). Read-only, no lock: a no-sale
  --     changes no drawer state, so it never contends with payments or close.
  select s.id into v_shift_id
    from public.shifts s
    where s.organization_id = v_org and s.branch_id = v_branch and s.device_id = p_device_id
      and s.status = 'open'
    order by s.created_at desc
    limit 1;
  if v_shift_id is not null then
    select cds.id into v_drawer_id
      from public.cash_drawer_sessions cds
      where cds.organization_id = v_org and cds.shift_id = v_shift_id and cds.status = 'active'
      limit 1;
  end if;

  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'cash_drawer.no_sale_opened', null, null,
          jsonb_build_object('role', v_role, 'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
                             'client_occurred_at', p_client_occurred_at, 'resolved_membership_id', v_membership));

  return jsonb_build_object('ok', true, 'entity', 'cash_drawer', 'recorded', true,
                            'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id);
end;
$$;

comment on function app.pos_record_drawer_no_sale(uuid, uuid, timestamptz) is
  'POS-CASH-DRAWER-MANUAL-OPEN-001 (D-013, PRINTERS_AND_HARDWARE_SPEC section 11): records a MANUAL ("no-sale") cash-drawer open from a POS till. Canonical PIN-session preamble (dead session/device/membership RAISE 42501 -> sync_push per-op rejection). POS devices only (invalid_device_type). Permission: manager+ BY ROLE or a cashier GRANTED open_cash_drawer (grant-only, default OFF); kitchen_staff/accountant never. A refusal audits cash_drawer.no_sale_denied and RETURNS permission_denied. Success audits cash_drawer.no_sale_opened with actor, device, role and the bound open shift / active drawer session (null when none). AUDIT-ONLY: no shift/drawer state change, no money. Reached ONLY via app.sync_push (cash_drawer.no_sale_open), which owns D-022 idempotency.';

revoke all on function app.pos_record_drawer_no_sale(uuid, uuid, timestamptz) from public;
revoke all on function app.pos_record_drawer_no_sale(uuid, uuid, timestamptz) from anon;
grant execute on function app.pos_record_drawer_no_sale(uuid, uuid, timestamptz) to authenticated;

-- 9. app.sync_push -- re-emitted from its LIVE body
--    (20260905090001_sync_push_precondition_detail_002) with ONLY: the new op in
--    BOTH allowlists (valid path AND revoked-device path, so a revoked till's
--    no-sale is still ledgered + audited as sync.operation_rejected) and ONE
--    dispatch arm. Everything else is byte-identical.
CREATE OR REPLACE FUNCTION app.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_op           jsonb;
  v_local_op     text;
  v_op_type      text;
  v_payload      jsonb;
  v_depends      jsonb;
  v_target_ent   text;
  v_target_id    uuid;
  v_client_ts    timestamptz;
  v_fingerprint  text;
  v_dep          text;
  v_dep_ok       boolean;
  v_ex_status    text;
  v_ex_result    jsonb;
  v_ex_optype    text;
  v_ex_fp        text;
  -- PSC-001C correction (Finding 1): the existing row's id when the atomic
  -- ledger claim loses, and whether this request ADOPTED a stale non-terminal
  -- row (the only case that bumps retry_count â€” the pre-fix contract).
  v_ex_id        uuid;
  v_adopted      boolean;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
  v_customer_phone text;
  v_ack_order    uuid;
  v_ack_ok       boolean;
  -- KITCHEN-DISPATCH-ENFORCE-001: the REQUESTED order.submit dispatch mode
  -- (defaulted, so an absent key is the deployed 'kds' contract) and the
  -- AUTHORITATIVE branch kitchen workflow mode read under a FOR SHARE lock.
  v_requested_dispatch  text;
  v_branch_kitchen_mode text;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests â€” keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing. Scope is derived here. The PIN
  --     session must exist + be valid (offline-window bounded, Q-009); a missing session
  --     or expired PIN still raises (cannot key/record safely without a session/window).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_push: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_push: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found then
    raise exception 'sync_push: backing device session not found' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- RF061-A1: a REVOKED / inactive device session or pairing no longer fails the whole
  -- batch with a silent raise. Instead each pushed op is RECORDED as rejected
  -- (revoked_device) and surfaced, so the offline-queued operations are not lost (R-007;
  -- AC1). Authorization is INGEST-TIME (the device is revoked NOW); client timestamps are
  -- never trusted. A previously-APPLIED op still replays its stored result (idempotency).
  if not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    v_device_revoked := true;
    for v_op in select * from jsonb_array_elements(p_operations)
    loop
      v_local_op   := v_op ->> 'local_operation_id';
      v_op_type    := v_op ->> 'operation_type';
      v_payload    := v_op -> 'payload';
      v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
      v_target_ent := v_op ->> 'target_entity';
      -- PSC-001D correction (F3) + PSC-001C: for the three IDENTITY-HARDENED
      -- operations (order.void_ack, order.items_add, order.round_status) the
      -- target id is parsed inside a PROTECTED boundary â€” a malformed uuid
      -- must reject only ITS operation, never abort the whole batch. The 12
      -- prior operations keep their exact existing parse semantics.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        begin
          v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
        exception when others then
          v_target_id := null;
        end;
      else
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      end if;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'cash_drawer.no_sale_open') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      -- PSC-001D correction (final pass) + PSC-001C: the SAME canonical
      -- identity contract as the valid path for ALL THREE hardened operations,
      -- enforced BEFORE the fingerprint, the terminal-replay lookup, the
      -- idempotency-conflict comparison and the ledger write. A revoked device
      -- must not gain permission to submit ambiguous or contradictory
      -- operation identity: a missing, malformed or CONTRADICTORY
      -- target/payload-identity pair (payload.order_id for order.void_ack and
      -- order.items_add; payload.round_id for order.round_status) is a hostile
      -- or malformed envelope â€” rejected with NO ledger row (the malformed-
      -- envelope convention), the batch continues. Only that op is affected.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_ack_ok := v_target_id is not null;
        begin
          v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
        exception when others then
          v_ack_order := null;
        end;
        if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
            'ok', false, 'error', 'invalid_payload',
            'detail', v_op_type || ' requires matching uuid target_id and payload.'
                      || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
            'status', 'rejected', 'idempotency_replay', false);
          continue;
        end if;
      end if;

      -- PSC-001D correction (F2 + final pass) + PSC-001C: the SAME target-
      -- bound fingerprint SHAPE as the valid path for all three hardened
      -- operations â€” the target component is the PARSED uuid's text
      -- (guaranteed non-null and equal to the parsed payload identity by the
      -- check above), so a legitimately-applied op still replays its stored
      -- result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
      else
        -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): customer_phone is DATA
        -- ONLY on an order.submit â€” carried in the payload for persistence but
        -- EXCLUDED from the operation identity, so re-sending the same op with only
        -- a different phone is an idempotent replay, not a conflict. Removing an
        -- absent key is a no-op, so a phone-less op keeps its EXACT prior
        -- fingerprint (backward compatible); every other field and every other
        -- operation type is unchanged.
        v_fingerprint := md5(v_op_type || '|' || (case when v_op_type = 'order.submit' then v_payload - 'customer_phone' else v_payload end)::text);
      end if;

      -- dedup/replay (PSC-001C correction, Finding 1 â€” ATOMIC CLAIM): the
      -- rejected/revoked_device recording is now claimed with ONE
      -- INSERT .. ON CONFLICT DO NOTHING on the transport identity. When the
      -- claim loses, the existing row is LOCKED (waiting out any concurrent
      -- claimant's COMMIT) and decided from its COMMITTED state: a TERMINAL
      -- row replays its stored result (a legitimately-APPLIED op before
      -- revocation is NOT re-rejected â€” and can no longer be OVERWRITTEN by
      -- this path racing a valid-device apply); a different identity is a
      -- conflict; only a genuinely stale NON-terminal row is re-recorded as
      -- rejected (the pre-fix retry contract, bump included).
      v_so_id := null;
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do nothing
      returning so.id into v_so_id;
      if v_so_id is null then
        select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
          into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
          from public.sync_operations so
          where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
          for update;
        if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
          insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
          values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                  jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                     'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
            'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
          continue;
        end if;
        if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
          v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
            || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
          continue;
        end if;
        -- a stale NON-terminal row: re-record it as rejected (revoked_device)
        -- under the held lock â€” the pre-fix on-conflict contract, verbatim.
        update public.sync_operations as so
          set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
              rejection_reason = 'revoked_device',
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
              retry_count = so.retry_count + 1, updated_at = now()
          where so.id = v_ex_id;
      end if;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'revoked_device', null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'reason', 'revoked_device'));
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false);
    end loop;
    return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now(), 'device_revoked', true);
  end if;

  -- (b) per-operation loop (ordered) â€” VALID device path (unchanged from RF-056)
  for v_op in select * from jsonb_array_elements(p_operations)
  loop
    v_caught_state := null;
    v_caught_msg   := null;
    v_dispatch     := null;
    v_dispatch_ok  := null;
    v_so_id        := null;

    v_local_op   := v_op ->> 'local_operation_id';
    v_op_type    := v_op ->> 'operation_type';
    v_payload    := v_op -> 'payload';
    v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
    v_target_ent := v_op ->> 'target_entity';
    -- PSC-001D correction (F3) + PSC-001C: protected parse for the three
    -- identity-hardened operations â€” a malformed target uuid rejects only ITS
    -- operation (below), never the batch. The 12 prior operations keep their
    -- exact existing semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      begin
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      exception when others then
        v_target_id := null;
      end;
    else
      v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
    end if;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'cash_drawer.no_sale_open') then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
        'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if jsonb_typeof(v_depends) <> 'array' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_depends_on', 'detail', 'depends_on must be a JSON array', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;

    -- (b1+) PSC-001D correction (F2/F3) + PSC-001C: CANONICAL TARGET IDENTITY
    -- for the three hardened operations, enforced BEFORE the fingerprint, the
    -- terminal-replay lookup and the dispatch. The envelope MUST carry a
    -- parseable target_id AND a parseable payload identity (payload.order_id
    -- for order.void_ack and order.items_add; payload.round_id for
    -- order.round_status) and they MUST be the same uuid â€” a missing,
    -- malformed or CONTRADICTORY pair is a hostile/malformed envelope:
    -- rejected with NO ledger row (the malformed-envelope convention), so a
    -- replayed local_operation_id with a swapped target can never reach the
    -- stored terminal result, mutate anything, or learn anything about
    -- another order or round. Only that operation is affected.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_ack_ok := v_target_id is not null;
      begin
        v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
      exception when others then
        v_ack_order := null;
      end;
      if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload',
          'detail', v_op_type || ' requires matching uuid target_id and payload.'
                    || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
          'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
    end if;

    -- PSC-001D correction (F2) + PSC-001C: the fingerprint of every hardened
    -- operation BINDS the canonical target identity, so a terminal replay is
    -- valid only for the same local_operation_id + operation + payload +
    -- TARGET. The 12 prior operations keep their exact existing fingerprint
    -- semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): order.submit identity
      -- EXCLUDES customer_phone (data-only) â€” same canonical rule as the
      -- rejection path above, so both paths fingerprint an op identically. A
      -- phone-less op is byte-identical; all other fields/op-types unchanged.
      v_fingerprint := md5(v_op_type || '|' || (case when v_op_type = 'order.submit' then v_payload - 'customer_phone' else v_payload end)::text);
    end if;

    -- (b2) ATOMIC LEDGER CLAIM (PSC-001C correction, Finding 1). The pre-fix
    -- shape read the ledger and only LATER upserted it, so two concurrent
    -- requests with the SAME (org, device, local_operation_id) + fingerprint
    -- could both pass the read; the loser's upsert then dragged the winner's
    -- COMMITTED terminal row back to in_flight, re-dispatched (now an
    -- invalid_transition), and finalized the previously-successful row as
    -- rejected. The claim is now ONE INSERT .. ON CONFLICT DO NOTHING on the
    -- transport identity, computed AFTER envelope validation + identity
    -- canonicalization + the fingerprint:
    --   * claim WON  -> this transaction owns dispatch (fresh row, in_flight,
    --     retry_count 0) and finalizes it exactly once at (b6);
    --   * claim LOST -> the existing row is LOCKED (FOR UPDATE â€” waiting out a
    --     concurrent claimant's COMMIT) and decided from COMMITTED state: a
    --     fingerprint/op mismatch keeps the exact idempotency-conflict
    --     contract; a TERMINAL row replays its stored result (and can never be
    --     overwritten or reset to in_flight again); only a genuinely stale
    --     NON-terminal row (pending / crashed in_flight) is ADOPTED â€” the
    --     pre-fix retry contract, bump included. A losing concurrent caller
    --     therefore converges on the winner's stored terminal result.
    v_adopted := false;
    v_so_id   := null;
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do nothing
    returning so.id into v_so_id;

    if v_so_id is null then
      select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
        for update;
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
      v_so_id   := v_ex_id;
      v_adopted := true;
    end if;

    -- (b3) dependency guard (still BEFORE any dispatch; the claimed/adopted
    -- row is parked as pending exactly like the pre-fix contract â€” a fresh
    -- claim keeps retry_count 0, an adopted re-attempt bumps it).
    v_dep_ok := true;
    for v_dep in select jsonb_array_elements_text(v_depends)
    loop
      if not exists (
        select 1 from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id
          and so.local_operation_id = v_dep and so.status = 'applied'
      ) then
        v_dep_ok := false;
        exit;
      end if;
    end loop;

    if not v_dep_ok then
      update public.sync_operations as so
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + (case when v_adopted then 1 else 0 end),
            updated_at = now()
        where so.id = v_so_id;
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) an ADOPTED stale re-attempt returns to in_flight with the retry
    -- bump (the pre-fix on-conflict contract); a fresh claim is already
    -- in_flight and is never re-written here.
    if v_adopted then
      update public.sync_operations as so
        set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
        where so.id = v_so_id;
    end if;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction.
    begin
      case v_op_type
        when 'shift.open' then
          v_dispatch := app.open_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            (v_payload ->> 'cash_drawer_session_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'opening_float_minor')::bigint);
        when 'order.submit' then
          -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: validate the OPTIONAL customer
          -- phone UP FRONT. Empty/whitespace -> null (the order proceeds). A
          -- non-empty value that is not a valid phone (>32 chars / a disallowed
          -- character / fewer than 5 digits) REJECTS the whole op with a typed
          -- invalid_payload and creates NO order (the POS UI already blocks
          -- submit on an invalid phone; this is server-side defence in depth,
          -- and the DB CHECK is the final boundary). A valid/empty phone falls
          -- through to the UNCHANGED submit path; a valid phone is stamped after.
          v_customer_phone := btrim(coalesce(v_payload ->> 'customer_phone', ''));
          -- KITCHEN-DISPATCH-ENFORCE-001: resolve the REQUESTED dispatch mode
          -- (an absent key is the deployed 'kds' contract) and, ONLY for the
          -- privileged direct_print request, read the AUTHORITATIVE branch mode
          -- under a FOR SHARE row lock held to transaction end. The predicate is
          -- the same tenant-scoped one app.submit_order's dispatch gate uses and
          -- the scope comes from the SESSION (v_org/v_branch), never the payload.
          -- FOR SHARE conflicts with the FOR NO KEY UPDATE lock a
          -- kitchen_workflow_mode UPDATE takes, so a mode change cannot commit
          -- underneath an in-flight acceptance (and vice versa), while concurrent
          -- direct_print submits share the lock. The common absent/'kds' path
          -- reads nothing here and takes NO lock.
          v_requested_dispatch  := coalesce(v_payload ->> 'dispatch_mode', 'kds');
          v_branch_kitchen_mode := null;
          if v_requested_dispatch = 'direct_print' then
            select b.kitchen_workflow_mode
              into v_branch_kitchen_mode
              from public.branches b
              where b.id              = v_branch
                and b.organization_id = v_org
                and b.deleted_at is null
              for share;
          end if;
          -- Validation runs BEFORE app.submit_order, so every rejection below
          -- creates NO business rows at all (the shipped customer-phone guard
          -- precedent). Anything but an affirmative 'printer_only' â€” including a
          -- missing or tombstoned branch row â€” fails CLOSED.
          if v_customer_phone <> '' and not app.is_valid_customer_phone(v_customer_phone) then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'invalid_payload', 'detail', 'customer_phone');
          elsif v_requested_dispatch not in ('kds', 'direct_print') then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'invalid_payload', 'detail', 'dispatch_mode');
          elsif v_requested_dispatch = 'direct_print'
                and coalesce(v_branch_kitchen_mode, '') <> 'printer_only' then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'dispatch_mode_not_allowed',
              'detail', 'direct_print_requires_printer_only_branch');
          else
            v_dispatch := app.submit_order(
              p_pin_session_id,
              (v_payload ->> 'order_id')::uuid,
              p_device_id,
              v_local_op,
              v_payload ->> 'order_type',
              nullif(v_payload ->> 'table_id', '')::uuid,
              nullif(v_payload ->> 'shift_id', '')::uuid,
              v_payload ->> 'currency_code',
              v_payload ->> 'notes',
              v_payload -> 'order_items',
              (v_payload ->> 'subtotal_minor')::bigint,
              (v_payload ->> 'discount_total_minor')::bigint,
              (v_payload ->> 'tax_total_minor')::bigint,
              (v_payload ->> 'grand_total_minor')::bigint,
              v_client_ts);
            -- ORDER-CUSTOMER-001: stamp the OPTIONAL customer display name on the
            -- order app.submit_order just created. Kept OUT of submit_order so its
            -- validated INSERT stays byte-unchanged. Money-free display text: trim
            -- + empty->null + 80-char cap. Tenant-scoped by v_org; the
            -- `customer_name is null` guard makes it idempotent (a replay returns
            -- the same order_id, already stamped) and never overwrites.
            v_customer_name := left(btrim(coalesce(v_payload ->> 'customer_name', '')), 80);
            if v_customer_name <> '' then
              update public.orders
                set customer_name = v_customer_name
                where id = (v_dispatch ->> 'order_id')::uuid
                  and organization_id = v_org
                  and customer_name is null;
            end if;
            -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: stamp the validated OPTIONAL
            -- customer phone parallel to customer_name. Tenant-scoped; the
            -- `customer_phone is null` guard makes an offline replay idempotent
            -- (a replay returns the same order_id, already stamped) and never
            -- overwrites. The value was validated BEFORE submit_order below.
            if v_customer_phone <> '' then
              update public.orders
                set customer_phone = v_customer_phone
                where id = (v_dispatch ->> 'order_id')::uuid
                  and organization_id = v_org
                  and customer_phone is null;
            end if;
            -- KITCHEN-MODE-001C1-CORRECTION-001: the initial kitchen dispatch
            -- payload is built inside app.submit_order BEFORE this stamp, so on
            -- the REAL push path customer_display_name was missing. Rebuild the
            -- COMPLETE normalized payload through the trusted internal server
            -- builder IN THIS SAME TRANSACTION â€” never by patching client JSON
            -- in, never after a client could have seen it (claimed / completed
            -- / superseded rows are left untouched; inside this first-apply
            -- transaction the row is not yet visible to any puller), never
            -- duplicating the dispatch or its audit row (no INSERT, no audit
            -- here). The row only exists for printer_only branches, so kds
            -- branches are a structural no-op; the guard trigger re-proves the
            -- rebuilt payload money-free on UPDATE.
            if v_customer_name <> '' then
              update public.kitchen_print_dispatches kd
                set money_free_payload = app.kitchen_dispatch_payload_initial(v_org, (v_dispatch ->> 'order_id')::uuid),
                    updated_at = now()
                where kd.organization_id = v_org
                  and kd.order_id = (v_dispatch ->> 'order_id')::uuid
                  and kd.dispatch_type = 'initial_order'
                  and kd.claimed_at is null
                  and kd.completed_at is null
                  and kd.superseded_by_dispatch_id is null;
            end if;
            -- KITCHEN-PRINT-DUAL-001C: a direct_print order is dispatched to the
            -- kitchen via the POS printer (no KDS device), IN THIS SAME transaction
            -- â€” a concurrent sync_pull can never observe an intermediate active
            -- state (sync_push commits once). app.submit_order already ran above, so
            -- the outcome here is CONDITIONAL, not an unconditional promotion:
            --   * CHARGEABLE printer_only order, still `submitted` -> the helper
            --     routes it OUT of the KDS active workflow: served +
            --     dispatch_mode=direct_print, dispatched=true; completion still
            --     waits for settlement.
            --   * ZERO-TOTAL printer_only order -> app.submit_order ALREADY
            --     completed it (a zero balance is settled on arrival), so the helper
            --     declines with dispatched=false / reason=not_eligible and the order
            --     stays completed / dispatch_mode='kds' / revision 2.
            -- Settlement is NEVER bypassed and physical print success NEVER completes
            -- an order; the POS local kitchen print is a separate best-effort client
            -- path and is not represented in this result. A 'kds' (default) order is
            -- a structural no-op here.
            if v_requested_dispatch = 'direct_print' then
              -- Merge the ADDITIVE outcome (order_status/revision/auto_completed)
              -- into the envelope so the client sees the FINAL committed state,
              -- exactly like the zero-total submit tail. A no-op replay merges only
              -- {dispatched:false} (submit_order's replay already re-reads the
              -- current revision), so the envelope stays correct.
              v_dispatch := v_dispatch || app.apply_direct_print_dispatch(
                v_org, v_rest, v_branch, (v_dispatch ->> 'order_id')::uuid,
                v_emp, v_membership, p_device_id, v_local_op);
            end if;
          end if;
        when 'order.discount' then
          v_dispatch := app.apply_discount(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'scope',
            nullif(v_payload ->> 'order_item_id', '')::uuid,
            v_payload ->> 'discount_type',
            (v_payload ->> 'value')::bigint,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'payment.create' then
          v_dispatch := app.record_payment(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'tender_type',
            (v_payload ->> 'amount_tendered_minor')::bigint,
            nullif(v_payload ->> 'provisional_receipt_number', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'shift.close' then
          v_dispatch := app.close_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'counted_amount_minor')::bigint,
            nullif(v_payload ->> 'reason', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        -- MVP addition: KDS/POS order-status updates ride the SAME outbox/ledger
        -- (D-010/D-022). Scope/actor come from the pin session + device passed
        -- through (A8); the payload contributes ONLY {order_id, new_status}.
        when 'order.status' then
          v_dispatch := app.update_order_status(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'order_id')::uuid,
            v_payload ->> 'new_status',
            v_local_op);
        when 'order.void' then
          -- MONEY-VOID-001: role-gated void of a wrong UNPAID order. Mirrors the
          -- order.discount branch - actor/org/branch come from the PIN session
          -- (never the payload) and the op's local_operation_id threads
          -- app.void_order's own idempotency (D-022). app.void_order (RF-053,
          -- hardened by RF-062) enforces manager/restaurant_owner/org_owner (or a
          -- cashier with permissions.void_order='true'), a mandatory reason, legal
          -- source states (submitted/accepted/preparing/ready/served), and the
          -- completed-payment block (an order with a live completed payment
          -- returns permission_denied) - so paid orders are refused server-side.
          -- Money-free: it only sets orders.status='voided' + void_reason +
          -- revision and cascades items -> voided; no payment/total is touched.
          v_dispatch := app.void_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'order.table_move' then
          -- RESTAURANT-OPERATIONS-V1-001: atomic dine-in table move. Mirrors the
          -- order.void branch â€” actor/org/branch come from the PIN session
          -- (never the payload); the op's local_operation_id threads
          -- app.move_order_table's ORDER-BOUND idempotency (D-022); the payload
          -- contributes ONLY {order_id, table_id[, expected_revision]}. Typed
          -- refusals (table_not_allowed / invalid_transition+order_not_movable /
          -- table_not_available / permission_denied) RETURN through verbatim;
          -- a revision conflict raises 40001 -> the per-op 'conflict' status.
          -- Money-free: only orders.table_id + revision move.
          v_dispatch := app.move_order_table(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'menu.availability_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: a cashier (default-ON
          -- manage_menu_availability) or manager+ sets a menu item's per-branch
          -- availability from the POS. Actor/org/branch derive from the PIN
          -- session (NEVER the payload); the capability is enforced inside. The
          -- payload contributes ONLY {menu_item_id, availability, reason}. The
          -- setter is naturally idempotent (no-change re-applies the same state
          -- with no audit) and transport dedup (sync_operations) guards replay.
          -- Typed RETURN refusals (permission_denied / not_found) survive
          -- verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_item_availability(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'menu_item_id')::uuid,
            v_payload ->> 'availability',
            nullif(v_payload ->> 'reason', ''));
        when 'table.status_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: manual table floor-state from the
          -- POS (manage_table_operations). Scope/actor from the session; payload
          -- {table_id, status}. Typed refusals survive verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_table_status(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid,
            v_payload ->> 'status');
        when 'table.link' then
          -- Link two same-branch tables into an operational group (no order/bill
          -- merge). Payload {table_id_a, table_id_b}. Deterministic lock order.
          v_dispatch := app.pos_link_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id_a')::uuid,
            (v_payload ->> 'table_id_b')::uuid);
        when 'table.unlink' then
          -- Dissolve the group a table belongs to (orders untouched). Payload
          -- {table_id}.
          v_dispatch := app.pos_unlink_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid);
        when 'cash_drawer.no_sale_open' then
          -- POS-CASH-DRAWER-MANUAL-OPEN-001: a MANUAL ("no-sale") drawer open
          -- recorded from the POS. Actor/org/branch/device come from the PIN
          -- session (NEVER the payload); the payload contributes ONLY the
          -- client's own occurrence time (display only -- the audit's
          -- occurred_at stays server time). The permission is enforced inside;
          -- typed refusals (permission_denied / invalid_device_type) RETURN
          -- through verbatim. Transport dedup (sync_operations) makes a replay
          -- return the stored result -- one open, one audit row. MONEY-FREE.
          v_dispatch := app.pos_record_drawer_no_sale(
            p_pin_session_id, p_device_id,
            nullif(v_payload ->> 'client_occurred_at', '')::timestamptz);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch â€” actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay â€” by the time this arm runs, target_id and
          -- payload.order_id are guaranteed present, valid and equal. The
          -- check below is pure defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.void_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_void(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op);
        when 'order.items_add' then
          -- PSC-001C: add items to an existing eligible dine-in order as ONE
          -- new authoritative service round. Actor/org/branch come from the
          -- PIN session; the payload contributes {order_id, order_items}.
          -- app.add_order_items enforces the POS-class device, the cashier+
          -- role set, eligibility (dine_in, open status, no completed
          -- payment), submit_order-parity pricing/sellability, and round-level
          -- idempotency; its flat typed refusals (invalid_device_type /
          -- permission_denied / order_not_dine_in / order_not_eligible /
          -- order_already_settled / item_unavailable / invalid_item_payload)
          -- RETURN through verbatim. TARGET-ID CONSISTENCY is enforced at
          -- (b1+) BEFORE the fingerprint and the terminal replay â€” the check
          -- below is pure defence-in-depth and unreachable.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.items_add target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.add_order_items(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload -> 'order_items',
            v_client_ts);
        when 'order.round_status' then
          -- PSC-001C: the additional service round's own single-step
          -- lifecycle. Actor/org/branch come from the PIN session; the
          -- payload contributes {round_id, new_status}. app.update_round_status
          -- enforces the LOCKED device/role matrix (production steps KDS-only;
          -- ready->served KDS kitchen set or POS cashier set), the parent
          -- guards, single-step legality, the WRITE-ONCE ready_at stamp and
          -- the completion chain; its flat typed refusals RETURN through
          -- verbatim. TARGET-ID CONSISTENCY (against payload.round_id) is
          -- enforced at (b1+) â€” the check below is pure defence-in-depth and
          -- unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'round_id')::uuid then
            raise exception 'sync_push: order.round_status target_id does not match payload.round_id' using errcode = '42501';
          end if;
          v_dispatch := app.update_round_status(
            p_pin_session_id,
            (v_payload ->> 'round_id')::uuid,
            p_device_id,
            v_payload ->> 'new_status',
            v_local_op);
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      if v_caught_state = '40001' then
        update public.sync_operations
          set status = 'conflict', last_error_code = v_caught_state, last_error_class = 'conflict',
              conflict_info = jsonb_build_object('sqlstate', v_caught_state, 'message', v_caught_msg),
              result = jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'sqlstate', v_caught_state, 'status', 'conflict', 'idempotency_replay', false);
      elsif v_caught_state = 'RFDM0' then
        -- KITCHEN-DISPATCH-ENFORCE-001: the app.apply_direct_print_dispatch
        -- defensive belt fired. Normalize the DEDICATED internal SQLSTATE to the
        -- SAME terminal typed rejection the primary ingest guard returns â€” the
        -- ledger, the audit and the client envelope all carry
        -- `dispatch_mode_not_allowed` (class permanent) and NEVER a raw SQLSTATE
        -- or any internal branch-mode detail. The raise already rolled this
        -- operation's subtransaction back, so no business rows survive. The
        -- stored result is what a replay returns, so the rejection is idempotent.
        update public.sync_operations
          set status = 'rejected', last_error_code = 'dispatch_mode_not_allowed', last_error_class = 'permanent',
              rejection_reason = 'dispatch_mode_not_allowed',
              result = jsonb_build_object('ok', false, 'error', 'dispatch_mode_not_allowed',
                         'detail', 'direct_print_requires_printer_only_branch'), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'dispatch_mode_not_allowed', null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', 'dispatch_mode_not_allowed'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'dispatch_mode_not_allowed', 'detail', 'direct_print_requires_printer_only_branch',
          'status', 'rejected', 'idempotency_replay', false);
      else
        -- STALE-TABLE-ORDER-RECOVERY-001 (error contract): a dispatched RPC's
        -- PRECONDITION refusal - the message carries '(precondition_failed)', e.g.
        -- record_payment with no open shift / no active drawer on the paying device -
        -- is classified as the stable detail token 'precondition_failed' so the POS
        -- can say exactly that (open a shift) instead of a generic failure. Every
        -- other message still collapses to the generic 'rejected' (never raw text).
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else null end,
          'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      update public.sync_operations
        set status = 'rejected', last_error_code = coalesce(v_dispatch ->> 'error', 'rejected'), last_error_class = 'permanent',
            rejection_reason = coalesce(v_dispatch ->> 'error', 'rejected'), result = v_dispatch, updated_at = now()
        where id = v_so_id;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', coalesce(v_dispatch ->> 'error', 'rejected'), null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', coalesce(v_dispatch ->> 'error', 'rejected')));
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'rejected', 'idempotency_replay', false));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now());
end;
$function$;

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly, verbatim).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- 10. app.pos_verify_drawer_pin -- unlocks the POS drawer button for the CURRENT
--     PIN session by re-proving the signed-in employee's OWN PIN, server-side.
--     The PIN never lives on the device (D-006), so the unlock needs the server;
--     once unlocked, the POS may open the drawer offline until the session ends.
--     It reuses the sign-in verifier (app.verify_pin_credential) AND the sign-in
--     lockout ledger (public.pin_attempt_states, same (org, employee, device) key):
--     wrong drawer PINs count toward the SAME 5-attempt / 15-minute lockout, so the
--     unlock can never become a second, unthrottled PIN oracle. Every refusal
--     RETURNS a typed envelope (a RAISE would roll back the counter + the audit).
--     The PIN is NEVER recorded anywhere.
create function app.pos_verify_drawer_pin(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_pin            text
)
  returns jsonb
  language plpgsql
  volatile
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
  v_expires_at timestamptz;
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
  v_dtype      text;
  v_locked_until timestamptz;
  v_locked_set   timestamptz;
  v_count        integer;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (app.pin_session_capabilities): every
  --     failure collapses to ONE indistinguishable invalid_session envelope -- no
  --     existence/scope oracle (R-003).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id, ps.expires_at
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership, v_expires_at
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
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
     or v_ds_org    is distinct from v_org
     or v_ds_rest   is distinct from v_rest
     or v_ds_branch is distinct from v_branch then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  -- (b) POS tills only.
  select d.device_type into v_dtype
    from public.devices d where d.id = p_device_id and d.organization_id = v_org;
  if v_dtype is distinct from 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'cash_drawer');
  end if;

  -- (c) the permission BEFORE any PIN work: a cashier without the grant cannot use
  --     this to probe their PIN, and learns only permission_denied (audited).
  if not ((v_role in ('manager', 'restaurant_owner', 'org_owner'))
          or app.cashier_capability_granted(v_role, v_m_perms, 'open_cash_drawer')) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'cash_drawer.no_sale_denied', null, null,
            jsonb_build_object('role', v_role, 'denied_reason', 'permission_denied', 'stage', 'unlock',
                               'resolved_membership_id', v_membership));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'cash_drawer');
  end if;

  -- (d) the SAME lockout the sign-in uses, keyed (org, employee, device).
  select pas.locked_until into v_locked_until
    from public.pin_attempt_states pas
    where pas.organization_id = v_org
      and pas.employee_profile_id = v_emp
      and pas.device_id = p_device_id;
  if v_locked_until is not null and v_locked_until > now() then
    return jsonb_build_object('ok', false, 'error', 'pin_locked', 'entity', 'cash_drawer',
                              'locked_until', v_locked_until);
  end if;

  -- (e) verify the employee's OWN PIN (the PIN session's employee -- never an
  --     employee id supplied by the client).
  if not app.verify_pin_credential(v_emp, p_pin) then
    insert into public.pin_attempt_states as pas
        (organization_id, restaurant_id, branch_id, employee_profile_id, device_id,
         failed_attempt_count, last_failed_at, last_attempt_at)
      values (v_org, v_rest, v_branch, v_emp, p_device_id, 1, now(), now())
      on conflict (organization_id, employee_profile_id, device_id) do update
        set failed_attempt_count = pas.failed_attempt_count + 1,
            last_failed_at = now(),
            last_attempt_at = now()
      returning pas.failed_attempt_count into v_count;
    if v_count >= app.pin_max_failed_attempts() then
      update public.pin_attempt_states
        set locked_until = now() + app.pin_lockout_duration()
        where organization_id = v_org
          and employee_profile_id = v_emp
          and device_id = p_device_id
        returning locked_until into v_locked_set;
    end if;
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'cash_drawer.unlock_failed', null, null,
            jsonb_build_object('role', v_role, 'failed_attempt_count', v_count,
                               'locked', (v_locked_set is not null), 'locked_until', v_locked_set,
                               'resolved_membership_id', v_membership));
    return jsonb_build_object('ok', false,
                              'error', case when v_locked_set is not null then 'pin_locked' else 'invalid_pin' end,
                              'entity', 'cash_drawer', 'locked_until', v_locked_set);
  end if;

  -- (f) success: clear the shared attempt counter exactly like a successful sign-in.
  insert into public.pin_attempt_states as pas
      (organization_id, restaurant_id, branch_id, employee_profile_id, device_id,
       failed_attempt_count, locked_until, last_attempt_at)
    values (v_org, v_rest, v_branch, v_emp, p_device_id, 0, null, now())
    on conflict (organization_id, employee_profile_id, device_id) do update
      set failed_attempt_count = 0,
          locked_until = null,
          last_attempt_at = now();

  -- The server PIN-session expiry lets the POS bound OFFLINE opens to a window in
  -- which the queued audit can still be recorded under this same session.
  return jsonb_build_object('ok', true, 'entity', 'cash_drawer', 'unlocked', true,
                            'session_expires_at', v_expires_at, 'server_now', now());
end;
$$;

comment on function app.pos_verify_drawer_pin(uuid, uuid, text) is
  'POS-CASH-DRAWER-MANUAL-OPEN-001: unlocks the POS manual-drawer button for the CURRENT PIN session by re-verifying the signed-in employee''s OWN PIN server-side (app.verify_pin_credential; the PIN never lives on the device, D-006). Canonical PIN-session preamble (one indistinguishable invalid_session envelope, R-003). POS devices only. Permission (manager+ by role or the grant-only cashier capability open_cash_drawer) is checked BEFORE any PIN work; refusal audits cash_drawer.no_sale_denied (stage unlock). Shares the sign-in lockout ledger (pin_attempt_states, 5 attempts / 15 minutes): wrong PINs audit cash_drawer.unlock_failed (count + lock state, never the PIN) and RETURN invalid_pin / pin_locked. Success resets the counter and returns the PIN-session expiry so offline opens stay inside the server session. Writes no drawer/shift state.';

create function public.pos_verify_drawer_pin(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_pin            text
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$ select app.pos_verify_drawer_pin(p_pin_session_id, p_device_id, p_pin); $$;

comment on function public.pos_verify_drawer_pin(uuid, uuid, text) is
  'POS-CASH-DRAWER-MANUAL-OPEN-001: authenticated-only INVOKER wrapper over app.pos_verify_drawer_pin (the precedent of public.start_pin_session: a credential check, not a business write). Carries no authority of its own.';

revoke all on function app.pos_verify_drawer_pin(uuid, uuid, text) from public;
revoke all on function app.pos_verify_drawer_pin(uuid, uuid, text) from anon;
grant execute on function app.pos_verify_drawer_pin(uuid, uuid, text) to authenticated;
revoke all on function public.pos_verify_drawer_pin(uuid, uuid, text) from public;
revoke all on function public.pos_verify_drawer_pin(uuid, uuid, text) from anon;
grant execute on function public.pos_verify_drawer_pin(uuid, uuid, text) to authenticated;

-- New functions never broaden either global public surface. These assertions match
-- STOREFRONT-READ-001, BIZBOT-DEVICE-SESSION-FIX-001 and pending #288 in either
-- apply order.
do $$
declare
  v_anon_set text;
  v_defs text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_anon_set from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'POS-CASH-DRAWER-MANUAL-OPEN-001: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'POS-CASH-DRAWER-MANUAL-OPEN-001: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'POS-CASH-DRAWER-MANUAL-OPEN-001: anon has app schema usage';
  end if;
end;
$$;
