-- ============================================================================
-- RF-054 — pgTAP: offline provisional -> authoritative reconciliation (AC#2)
-- ============================================================================
-- A client-provided provisional receipt id is accepted and stored. Replaying the
-- SAME (device, local_operation_id, action, order) returns the SAME authoritative
-- receipt number and the SAME payment id — no duplicate payment row and no second
-- receipt-number allocation (reconciliation without duplication, D-021/D-022).
-- The same idempotency key on a DIFFERENT order is a conflict (40001), never a
-- replay. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf054o-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee02', 'rf054o-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'ord-1'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'ord-2');

-- RF-055: record_payment now requires an open shift + active cash drawer (A2)
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a5f1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','fx-shift');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000acd1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-0000000ef002',0,'fx-drawer');

-- first call with a client provisional id ----------------------------------- 1-2
select is(app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-recon','cash',1500,'PV-LOCAL-9') ->> 'receipt_number', '1', 'first payment allocates authoritative receipt number 1');
select is((select provisional_receipt_number from payments where order_id='00000000-0000-0000-0000-00000000a0d1'), 'PV-LOCAL-9', 'the client provisional receipt id is stored on the payment');

-- replay the SAME key/order returns the SAME payment id + receipt number ----- 3-5
select is(
  app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-recon','cash',1500,'PV-LOCAL-9') ->> 'payment_id',
  (select id::text from payments where order_id='00000000-0000-0000-0000-00000000a0d1'),
  'replay returns the SAME payment id');
select is(app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-recon','cash',1500,'PV-LOCAL-9') ->> 'receipt_number', '1', 'replay returns the SAME authoritative receipt number (no re-allocation)');
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-recon','cash',1500,'PV-LOCAL-9') ->> 'idempotency_replay')::boolean, true, 'replay is flagged idempotency_replay = true');

-- no duplicate payment row, no second receipt allocation --------------------- 6-7
select is((select count(*) from payments where order_id='00000000-0000-0000-0000-00000000a0d1')::int, 1, 'exactly one payment row exists for the order (no duplicate)');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 1::bigint, 'only one receipt number was allocated for the branch (replay did not advance the counter)');

-- the same key on a DIFFERENT order is a conflict, not a replay -------------- 8
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-recon','cash',1000,null) $$, '40001', NULL, 'the same idempotency key on a different order raises a conflict (40001)');

select * from finish();
rollback;
