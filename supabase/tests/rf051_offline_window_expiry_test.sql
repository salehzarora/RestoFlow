-- ============================================================================
-- RF-051 — pgTAP: offline validity window MECHANISM (AC#3)
-- ============================================================================
-- Q-009 is Accepted Open: the offline window DURATION is an INTERIM ASSUMPTION
-- (8 h, centralized in app.pin_session_offline_window()). This test proves the
-- MECHANISM, not the frozen duration:
--   * a future expires_at => the session is valid;
--   * a past expires_at   => the session is invalid (forces re-auth);
--   * the window is centralized (ASSUMPTION/Q-009);
--   * app.start_pin_session sets expires_at from the centralized window.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(5);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r51o-org-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'r51o-user@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01', 'ref:test-correct');

-- a pin_session with a FUTURE expires_at is valid; with a PAST one it is not --- 1-2
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c5f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5f2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() - interval '1 hour');
select ok(app.is_pin_session_valid('00000000-0000-0000-0000-00000000c5f1'),     'future expires_at => session is VALID');
select ok(not app.is_pin_session_valid('00000000-0000-0000-0000-00000000c5f2'), 'past expires_at => session is INVALID (forces re-auth)');

-- the window is centralized (ASSUMPTION / Q-009) ------------------------------ 3
select is(app.pin_session_offline_window(), interval '8 hours', 'offline window is centralized (ASSUMPTION / Q-009)');

-- app.start_pin_session sets expires_at from the centralized window ----------- 4-5
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:test-correct','op-off');
select ok((select expires_at from pin_sessions where local_operation_id='op-off') > now() + interval '7 hours',
  'start_pin_session sets expires_at beyond ~7h (uses the centralized window)');
select ok((select expires_at from pin_sessions where local_operation_id='op-off') < now() + interval '9 hours',
  'start_pin_session sets expires_at under ~9h (uses the centralized window, not unbounded)');

select * from finish();
rollback;
