-- ============================================================================
-- PIN-SESSION-CAPABILITIES-HOTFIX-001 — repair production PIN capability resolution
-- ============================================================================
-- PRODUCTION DEFECT (live since 20260717090000 was applied to hosted).
--
-- app.pin_session_capabilities raises
--     SQLSTATE 42703: column ps.status does not exist
-- on EVERY call, and has never once returned a value.
--
-- ROOT CAUSE. FULL-COMP-PERMISSION-001 HAND-WROTE the session preamble instead of
-- reusing the proven one. Its comment claims "The SAME session validation
-- app.apply_discount performs" — that was simply not true. It contains THREE
-- divergences from the canonical flow, two of them fatal:
--
--   1. `ps.status = 'active'`  -> public.pin_sessions HAS NO `status` COLUMN.
--                                 It uses `is_active` (20260619190131). FATAL.
--   2. `ds.status = 'active'`  -> public.device_sessions HAS NO `status` COLUMN
--                                 either. Also `is_active`. FATAL.
--   3. membership resolved by joining employee_profiles -> memberships, rather than
--      following pin_sessions.resolved_membership_id (the authoritative pointer the
--      rest of the tree uses). Not fatal, but a second, divergent authorization path.
--
--   It also never calls app.is_pin_session_valid(), the shared validity helper.
--
-- WHY IT SHIPPED GREEN. plpgsql plans lazily: a body is only parsed against the
-- catalog on FIRST EXECUTION. The migration therefore applied cleanly, and every
-- test passed — because the FULL-COMP-PERMISSION-001 pgTAP suite (48 tests) never
-- actually CALLED this function. A suite must EXERCISE what it ships; asserting on a
-- function's source text or merely creating it proves nothing. That gap is closed
-- here: the accompanying suite invokes the REAL function on every path.
--
-- IMPACT — FAIL-SAFE, BUT THE FEATURE NEVER WORKED.
--   * The POS treats an errored capability probe as "unknown", declines to
--     pre-block, and defers to the server. app.apply_discount re-decides
--     authorization on every mutation and still refuses correctly, so NO cashier
--     ever gained a permission and NO unauthorized comp was possible.
--   * But the capability-aware UX never functioned: instead of being told up front,
--     the cashier types a comp, waits for the round trip, and is refused at the end.
--
-- THE FIX is NOT to rename two columns. It is to STOP maintaining a parallel,
-- hand-written preamble and adopt the CANONICAL one used by every other PIN-scoped
-- RPC (app.apply_discount 20260715090000:137-163, app.record_payment, app.void_order):
--     app.is_pin_session_valid(pin_session)        -- validity/expiry, one helper
--     device_sessions.is_active + revoked_at is null
--     device_pairings.status = 'active'
--     device_id matches the session's device
--     membership via pin_sessions.resolved_membership_id, active + not deleted
-- plus an EXPLICIT check that the PIN session and its device session agree on
-- organization / restaurant / branch (hardening: the two are FK-linked at creation,
-- so a mismatch is impossible today — and a capability oracle is exactly the wrong
-- place to trust that quietly).
--
-- UNCHANGED: the signature, the response envelope, the capability MODEL, the public
-- wrapper, and the ACLs. This is a body repair only — the POS client needs no change
-- and no APK rebuild.
--
-- Forward-only. CREATE OR REPLACE (same signature, so ACLs are preserved).
-- ============================================================================

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
        or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp')));
end;
$$;

comment on function app.pin_session_capabilities(uuid, uuid) is
  'FULL-COMP-PERMISSION-001 + PIN-SESSION-CAPABILITIES-HOTFIX-001 (D-006/D-011): READ-ONLY projection of the EFFECTIVE capabilities of the human behind an ACTIVE PIN session on a PAIRED, ACTIVE device. HOTFIX: the FULL-COMP-PERMISSION-001 body hand-wrote its session preamble and selected `ps.status` AND `ds.status` -- NEITHER COLUMN EXISTS (pin_sessions and device_sessions both use `is_active`) -- so it raised SQLSTATE 42703 on EVERY call and never once returned a value. plpgsql plans lazily, so it applied cleanly and the 48-test FULL-COMP suite passed WITHOUT EVER CALLING IT. It failed SAFE (the client treats an error as "unknown" and defers to the server, which still refuses correctly, so no cashier ever gained a permission) but the capability-aware UX never worked. It now uses the CANONICAL preamble every other PIN-scoped RPC uses: app.is_pin_session_valid + device_sessions.is_active + revoked_at + device_pairings.status + the device match + an EXPLICIT org/restaurant/branch agreement check + the membership via resolved_membership_id. Returns EFFECTIVE rights -- role OR explicit grant -- computed with byte-for-byte the predicates app.apply_discount enforces: apply_discount (manager+ OR the DEFAULT-ON cashier capability) and apply_full_comp (manager+ OR the EXPLICIT DEFAULT-OFF cashier grant); a missing override resolves to FALSE, never null. The capability MODEL, the signature, the envelope and the ACLs are UNCHANGED -- no client change and no APK rebuild. ADVISORY ONLY: the server remains the sole authority and re-decides on every mutation. Every invalid / expired / revoked / device-mismatched / scope-mismatched / inactive-membership session collapses to ONE indistinguishable invalid_session envelope (no probe oracle, RISK R-003). Carries no money, no permissions JSON, no PIN material, and no identifier beyond the role.';


-- ---------------------------------------------------------------------------
-- ACLs. CREATE OR REPLACE with an unchanged signature PRESERVES the existing ACL,
-- so these are a re-assertion, not a change: PUBLIC and anon revoked, authenticated
-- only (the POS reaches it through the public.pin_session_capabilities INVOKER
-- wrapper with the anon key + its PIN/device session, exactly like public.sync_push).
-- No service-role grant. No table DML. The public wrapper is UNTOUCHED.
-- ---------------------------------------------------------------------------
revoke all on function app.pin_session_capabilities(uuid, uuid) from public;
revoke all on function app.pin_session_capabilities(uuid, uuid) from anon;
grant execute on function app.pin_session_capabilities(uuid, uuid) to authenticated;
