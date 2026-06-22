-- ============================================================================
-- RF-055 — pgTAP: concurrency-locking regression (RF055-B1 / RF055-B2)
-- ============================================================================
-- DETERMINISTIC regression coverage for the FOR UPDATE row-lock fixes. pgTAP runs
-- each file in a single transaction, so true concurrent sessions cannot be staged
-- here; the FOR UPDATE locks on the shift (then drawer) rows in app.open_shift /
-- app.close_shift / app.reconcile_shift / app.record_payment are the ACTUAL
-- concurrency control. These tests prove the status-qualified guards that the locks
-- protect: a second distinct-key close/reconcile is rejected (no double-apply, no
-- duplicate audit/ledger), a payment after close is rejected, and a replay after
-- close still returns the stored payment. Fixtures inserted as the BYPASSRLS role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055l-a', 'USD');
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
  ('00000000-0000-0000-0000-00000000ee01', 'rf055l-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf055l-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c521', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o3a'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o3b'),
  ('00000000-0000-0000-0000-0000000000d4', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o4');

-- ===== (1) close_shift cannot be double-applied with a different op id ======= 1-5
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o-sh1',0);
select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','cl-1',0,null);   -- first close OK (variance 0)
select throws_ok($$ select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','cl-2',9999,'second') $$, '42501', NULL, 'a second close with a DIFFERENT op id is rejected (status-qualified, lock-protected)');
select is((select count(*) from audit_events where action='shift.closed')::int, 1, 'exactly one shift.closed audit (no double-close)');
select is((select count(*) from audit_events where action='cash_drawer.closed')::int, 1, 'exactly one cash_drawer.closed audit');
select is((select count(*) from shift_operations where action='close_shift' and shift_id='00000000-0000-0000-0000-00000000a5f1')::int, 1, 'exactly one close_shift ledger row');
select is((select counted_total_minor from shifts where id='00000000-0000-0000-0000-00000000a5f1')::bigint, 0::bigint, 'counted_total_minor not overwritten by the rejected second close (still 0, not 9999)');

-- ===== (2) reconcile_shift cannot be double-applied with a different op id === 6-9
select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','rc-1',null);  -- first reconcile OK
select throws_ok($$ select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','rc-2',null) $$, '42501', NULL, 'a second reconcile with a DIFFERENT op id is rejected');
select is((select count(*) from audit_events where action='shift.reconciled')::int, 1, 'exactly one shift.reconciled audit (no double-reconcile)');
select is((select count(*) from audit_events where action='cash_drawer.reconciled')::int, 1, 'exactly one cash_drawer.reconciled audit');
select is((select count(*) from shift_operations where action='reconcile_shift' and shift_id='00000000-0000-0000-0000-00000000a5f1')::int, 1, 'exactly one reconcile_shift ledger row');

-- ===== (3) record_payment after close is rejected; expected cash not stale === 10-13
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000acd3','00000000-0000-0000-0000-00000000da11','o-sh3',0);
select app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-00000000da11','p3a','cash',1000,null);  -- cash sale 1000 on the drawer
select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000da11','cl-3',1000,null);            -- expected = 0 + 1000 = 1000
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-00000000da11','p3b','cash',1000,null) $$, '42501', NULL, 'a new payment after the shift/drawer closed is rejected (precondition_failed)');
select is((select count(*) from payments)::int, 1, 'the rejected post-close payment created no payment row (only the one cash sale exists)');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 1::bigint, 'the rejected payment did NOT advance the receipt counter');
select is((select expected_total_minor from shifts where id='00000000-0000-0000-0000-00000000a5f3')::bigint, 1000::bigint, 'close expected_total_minor (1000) is correct and could not be made stale by a post-close payment');

-- ===== (4) record_payment replay after close still returns the stored result  14-18
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f4','00000000-0000-0000-0000-00000000acd4','00000000-0000-0000-0000-00000000da11','o-sh4',0);
select app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000000d4','00000000-0000-0000-0000-00000000da11','p4','cash',1000,null);    -- receipt 2
select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f4','00000000-0000-0000-0000-00000000da11','cl-4',1000,null);
select is((app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000000d4','00000000-0000-0000-0000-00000000da11','p4','cash',1000,null) ->> 'idempotency_replay')::boolean, true, 'replaying the original payment AFTER close returns idempotency_replay (precondition not reached on replay)');
select is(
  app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000000d4','00000000-0000-0000-0000-00000000da11','p4','cash',1000,null) ->> 'payment_id',
  (select id::text from payments where order_id='00000000-0000-0000-0000-0000000000d4'),
  'replay returns the original payment_id');
select is((select count(*) from payments where order_id='00000000-0000-0000-0000-0000000000d4')::int, 1, 'replay created no new payment');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 2::bigint, 'replay did NOT advance the receipt counter (still 2)');
select is((select count(*) from audit_events where action='payment.recorded' and (new_values->>'order_id')='00000000-0000-0000-0000-0000000000d4')::int, 1, 'replay wrote no new payment.recorded audit');

select * from finish();
rollback;
