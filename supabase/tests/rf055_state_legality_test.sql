-- ============================================================================
-- RF-055 — pgTAP: shift / cash-drawer state-transition legality (D-018)
-- ============================================================================
-- open: only when no active shift on the device. close: only from open. reconcile:
-- only from closed. reconciled is terminal. One non-terminal shift per device.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055s-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf055s-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf055s-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c521', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- open -> closed -> reconciled, with illegal transitions rejected ------------ 1-6
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o1',0) ->> 'status'), 'open', 'open -> open');
select is((app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c1',0,null) ->> 'status'), 'closed', 'open -> closed');
select throws_ok($$ select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c1b',0,null) $$, '42501', NULL, 'closing an already-closed shift is rejected');
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','r1',null) ->> 'status'), 'reconciled', 'closed -> reconciled');
select throws_ok($$ select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','r1b',null) $$, '42501', NULL, 'reconciling a reconciled shift is rejected (terminal)');
select throws_ok($$ select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c1c',0,null) $$, '42501', NULL, 'closing a reconciled shift is rejected (terminal)');

-- reconcile requires closed; one active shift per device --------------------- 7-9
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000acd2','00000000-0000-0000-0000-00000000da11','o2',0) ->> 'status'), 'open', 'a new shift opens on the device once the prior one is terminal');
select throws_ok($$ select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000da11','r2',null) $$, '42501', NULL, 'reconciling an OPEN shift is rejected (must be closed)');
select throws_ok($$ select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000acd3','00000000-0000-0000-0000-00000000da11','o3',0) $$, '42501', NULL, 'opening a second active shift on the same device is rejected');

select * from finish();
rollback;
