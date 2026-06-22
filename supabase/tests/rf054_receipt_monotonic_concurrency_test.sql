-- ============================================================================
-- RF-054 — pgTAP: per-branch monotonic / gapless / unique receipt numbers (AC#1)
-- ============================================================================
-- Sequential record_payment calls in one branch produce distinct, gapless,
-- monotonic receipt numbers (1,2,3); a second branch's sequence is INDEPENDENT
-- (restarts at 1). The per-branch UNIQUE index makes a duplicate receipt number
-- within a branch impossible, while the SAME number may exist in different
-- branches. The number is allocated server-side under a row lock on
-- branch_receipt_counters (the concurrency-safety mechanism). Fixtures inserted
-- as the BYPASSRLS connection role; the RPC is SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(10);

-- ---- one org / one restaurant / TWO branches, each with its own device+session
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf054m-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A2');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-00000000fa22');
-- an org-wide cashier (covers both branches), one employee, one PIN session per branch
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee02', 'rf054m-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c5b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
-- three orders in branch 1, two in branch 2 (each grand_total 1000)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'b1-o1'),
  ('00000000-0000-0000-0000-00000000b102', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'b1-o2'),
  ('00000000-0000-0000-0000-00000000b103', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'b1-o3'),
  ('00000000-0000-0000-0000-00000000b201', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b2','00000000-0000-0000-0000-00000000da22','00000000-0000-0000-0000-00000000c5b2','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'b2-o1'),
  ('00000000-0000-0000-0000-00000000b202', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b2','00000000-0000-0000-0000-00000000da22','00000000-0000-0000-0000-00000000c5b2','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'b2-o2');

-- RF-055: record_payment now requires an open shift + active cash drawer (A2).
-- One shift per (branch, device): branch 1 / da11 and branch 2 / da22 (org-wide cashier).
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a5f1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','fx-shift-b1'),
  ('00000000-0000-0000-0000-00000000b5f2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b2','00000000-0000-0000-0000-00000000da22','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','fx-shift-b2');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000acd1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-0000000ef002',0,'fx-drawer-b1'),
  ('00000000-0000-0000-0000-00000000bcd2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b2','00000000-0000-0000-0000-00000000da22','00000000-0000-0000-0000-00000000b5f2','00000000-0000-0000-0000-0000000ef002',0,'fx-drawer-b2');

-- ---- branch 1: three payments -> receipt numbers 1, 2, 3 (gapless monotonic) -- 1-3
select is(app.record_payment('00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-00000000b101','00000000-0000-0000-0000-00000000da11','b1-p1','cash',1000,null) ->> 'receipt_number', '1', 'branch 1 first receipt number is 1');
select is(app.record_payment('00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-00000000b102','00000000-0000-0000-0000-00000000da11','b1-p2','cash',1000,null) ->> 'receipt_number', '2', 'branch 1 second receipt number is 2 (monotonic)');
select is(app.record_payment('00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-00000000b103','00000000-0000-0000-0000-00000000da11','b1-p3','cash',1000,null) ->> 'receipt_number', '3', 'branch 1 third receipt number is 3 (gapless)');

-- branch 1 issued exactly three distinct numbers ----------------------------- 4
select is((select count(distinct receipt_number) from orders where branch_id='00000000-0000-0000-0000-00000000a1b1' and receipt_number is not null)::int, 3, 'branch 1 issued three distinct receipt numbers');

-- ---- branch 2: independent sequence -> restarts at 1, 2 -------------------- 5-6
select is(app.record_payment('00000000-0000-0000-0000-00000000c5b2','00000000-0000-0000-0000-00000000b201','00000000-0000-0000-0000-00000000da22','b2-p1','cash',1000,null) ->> 'receipt_number', '1', 'branch 2 first receipt number restarts at 1 (independent sequence)');
select is(app.record_payment('00000000-0000-0000-0000-00000000c5b2','00000000-0000-0000-0000-00000000b202','00000000-0000-0000-0000-00000000da22','b2-p2','cash',1000,null) ->> 'receipt_number', '2', 'branch 2 second receipt number is 2');

-- ---- counters reflect last issued per branch ------------------------------- 7-8
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 3::bigint, 'branch 1 counter last_issued_value = 3');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b2')::bigint, 2::bigint, 'branch 2 counter last_issued_value = 2');

-- ---- a duplicate receipt number WITHIN a branch is impossible -------------- 9
-- (connection-role direct insert of a new order reusing branch 1's receipt '1')
select throws_ok($$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, receipt_number, local_operation_id)
  values ('00000000-0000-0000-0000-00000000b1dd', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c5b1','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'1','b1-dup')
$$, '23505', NULL, 'a duplicate receipt number within the same branch violates the unique index');

-- ---- the SAME receipt number ''1'' legitimately exists in BOTH branches ----- 10
select is((select count(*) from orders where receipt_number='1')::int, 2, 'receipt number 1 exists in both branches (per-branch sequences are independent)');

select * from finish();
rollback;
