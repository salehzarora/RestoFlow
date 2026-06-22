-- ============================================================================
-- RF-055 — pgTAP: idempotency (D-022; shift-bound)
-- ============================================================================
-- open/close/reconcile replays (same org+device+local_operation_id+action) return
-- the stored result and never duplicate state or audit. The same key/action reused
-- for a DIFFERENT shift is a conflict (40001), not a replay. Fixtures inserted as
-- the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055i-a', 'USD');
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
  ('00000000-0000-0000-0000-00000000ee01', 'rf055i-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf055i-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c521', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- open + replay -------------------------------------------------------------- 1-3
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-1',0) ->> 'status'), 'open', 'open succeeds');
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-1',0) ->> 'idempotency_replay')::boolean, true, 'replaying the same open returns idempotency_replay');
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-1',0) ->> 'shift_id'), '00000000-0000-0000-0000-00000000a5f1', 'replay returns the same shift_id');

-- open: same key/action for a DIFFERENT shift is a conflict ------------------ 4-5
select throws_ok($$ select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f9','00000000-0000-0000-0000-00000000acd9','00000000-0000-0000-0000-00000000da11','op-1',0) $$, '40001', NULL, 'reusing the open key for a different shift raises a conflict (40001)');
select is((select count(*) from shifts where device_id='00000000-0000-0000-0000-00000000da11')::int, 1, 'replay + conflict created no second shift');

-- close + replay ------------------------------------------------------------- 6-7
select is((app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','cl-1',0,null) ->> 'status'), 'closed', 'close succeeds (variance 0)');
select is((app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','cl-1',0,null) ->> 'idempotency_replay')::boolean, true, 'replaying the same close returns idempotency_replay');

-- close: same key/action for a DIFFERENT shift is a conflict ----------------- 8-9
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000acd3','00000000-0000-0000-0000-00000000da11','op-3',0);
select throws_ok($$ select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000da11','cl-1',0,null) $$, '40001', NULL, 'reusing the close key for a different shift raises a conflict (40001)');
select is((select count(*) from audit_events where action='shift.closed')::int, 1, 'replay/conflict wrote no duplicate shift.closed audit');

-- reconcile + replay --------------------------------------------------------- 10-12
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','rc-1',null) ->> 'status'), 'reconciled', 'reconcile succeeds');
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','rc-1',null) ->> 'idempotency_replay')::boolean, true, 'replaying the same reconcile returns idempotency_replay');
select is((select count(*) from audit_events where action='shift.reconciled')::int, 1, 'replay wrote no duplicate shift.reconciled audit');

select * from finish();
rollback;
