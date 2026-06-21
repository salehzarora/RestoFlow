-- ============================================================================
-- RF-051 — pgTAP: direct-insert bypass prevention (security correction)
-- ============================================================================
-- After RF-051 an `authenticated` client must NOT be able to establish a PIN
-- session by directly inserting into pin_sessions (bypassing the verifier,
-- attempt limit, lockout, and membership resolution). INSERT on pin_sessions is
-- REVOKED from authenticated (D-011: PIN-session establishment only via the
-- SECURITY DEFINER RPC). Proves:
--   * a direct authenticated INSERT into pin_sessions is rejected (42501),
--     even for an otherwise in-scope, authorized org_owner;
--   * the RPC path CAN create a valid active session;
--   * the RF-016 backing guard still fires (23514) on a bad-backing insert.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(5);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r51b-org-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', true,  null),  -- active
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', false, null);  -- inactive
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'r51b-owner@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', 'org_owner');  -- authorized, org-wide
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01', 'ref:test-correct');

-- ===== authenticated path: direct INSERT is blocked, RPC works ==============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0a';        -- an authorized org_owner...
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';    -- ...in its own org/scope

-- a direct INSERT into pin_sessions (valid scope + valid backing) is REJECTED -- 1
select throws_ok($$
  insert into pin_sessions (organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01')
$$, '42501', NULL,
  'authenticated direct INSERT into pin_sessions is REJECTED (bypass closed; INSERT revoked)');

-- the RPC path CAN establish a session (verifier/lockout/resolution applied) -- 2
select ok(
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:test-correct','op-rpc') is not null,
  'the RPC path CAN create a PIN session for an authenticated caller');

reset role;

-- the RPC actually created an ACTIVE, valid session -------------------------- 3-4
select is((select count(*) from pin_sessions where local_operation_id='op-rpc' and is_active)::int, 1,
  'RPC created exactly one ACTIVE pin_session');
select ok(app.is_pin_session_valid((select id from pin_sessions where local_operation_id='op-rpc')),
  'the RPC-created session is valid (within its offline window)');

-- the RF-016 backing guard still fires on a bad-backing insert --------------- 5
select throws_ok($$
  insert into pin_sessions (organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a2','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01')
$$, '23514', NULL,
  'RF-016 backing guard still enforced: an active pin_session on an INACTIVE device session is rejected (23514)');

select * from finish();
rollback;
