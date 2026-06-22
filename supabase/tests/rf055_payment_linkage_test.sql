-- ============================================================================
-- RF-055 — pgTAP: record_payment open-shift linkage (A2)
-- ============================================================================
-- After RF-055, record_payment REQUIRES an open shift + active bound cash drawer
-- for the (org, branch, device) and STAMPS payments.shift_id /
-- cash_drawer_session_id. RF-054 behavior is preserved (receipt number + change).
-- A replay still returns the same payment + receipt. Fixtures inserted as the
-- BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055p-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf055p-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'ord-1');

-- record_payment is rejected when there is NO open shift/drawer -------------- 1
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','lp-1','cash',1500,null) $$, '42501', NULL, 'record_payment is rejected when no open shift/drawer exists (precondition_failed)');

-- open a shift, then payment succeeds and is stamped with the linkage -------- 2-6
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o-sh1',0);
select is(app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','lp-2','cash',1500,null) ->> 'receipt_number', '1', 'record_payment succeeds with an open shift (RF-054 receipt numbering preserved)');
select is((select change_minor from payments where order_id='00000000-0000-0000-0000-00000000a0d1')::bigint, 500::bigint, 'change is computed (RF-054 behavior preserved): 1500 - 1000 = 500');
select is((select shift_id from payments where order_id='00000000-0000-0000-0000-00000000a0d1'), '00000000-0000-0000-0000-00000000a5f1'::uuid, 'the payment is stamped with the open shift_id');
select is((select cash_drawer_session_id from payments where order_id='00000000-0000-0000-0000-00000000a0d1'), '00000000-0000-0000-0000-00000000acd1'::uuid, 'the payment is stamped with the active cash_drawer_session_id');
select is((select count(*) from payments where order_id='00000000-0000-0000-0000-00000000a0d1')::int, 1, 'exactly one payment row');

-- replay preserves the same payment + receipt ------------------------------- 7-9
select is(
  app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','lp-2','cash',1500,null) ->> 'payment_id',
  (select id::text from payments where order_id='00000000-0000-0000-0000-00000000a0d1'),
  'replay returns the same payment_id');
select is((app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','lp-2','cash',1500,null) ->> 'idempotency_replay')::boolean, true, 'replay is flagged idempotency_replay');
select is((select count(*) from payments where order_id='00000000-0000-0000-0000-00000000a0d1')::int, 1, 'replay created no second payment');

select * from finish();
rollback;
