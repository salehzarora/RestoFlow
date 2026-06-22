-- ============================================================================
-- RF-055 — pgTAP: close_shift cash reconciliation (MONEY §14)
-- ============================================================================
-- expected_total_minor = opening_float_minor + completed cash payments for the
-- drawer; counted_total_minor = p_counted_amount_minor; variance_minor = counted -
-- expected (signed: + overage, - shortage). A non-empty reason is REQUIRED when the
-- variance is non-zero. The shift moves open->closed and its drawer active->closed,
-- with amounts persisted on both. Three registers (devices) in one branch exercise
-- overage / shortage / zero. Opens + payments use the real RPCs. Fixtures inserted
-- as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055c-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da33', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da22', 'active'),
  ('00000000-0000-0000-0000-00000000fa33', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da33', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-00000000fa22'),
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da33', '00000000-0000-0000-0000-00000000fa33');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf055c-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c512', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c513', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'cl-o1'),
  ('00000000-0000-0000-0000-00000000c0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',2000,2000,'cl-o2'),
  ('00000000-0000-0000-0000-00000000c0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da22','00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'cl-o3');

-- setup: open three shifts (da11 float 5000, da22 float 1000, da33 float 500)
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o-sh1',5000);
select app.open_shift('00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000acd2','00000000-0000-0000-0000-00000000da22','o-sh2',1000);
select app.open_shift('00000000-0000-0000-0000-00000000c513','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000acd3','00000000-0000-0000-0000-00000000da33','o-sh3',500);
-- setup: cash sales — da11 gets 1000 + 2000 (=3000); da22 gets 1000; da33 none
select app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000c0d1','00000000-0000-0000-0000-00000000da11','cl-p1','cash',1000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000c0d2','00000000-0000-0000-0000-00000000da11','cl-p2','cash',2000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-00000000c0d3','00000000-0000-0000-0000-00000000da22','cl-p3','cash',1000,null);

-- da11: expected 5000+3000=8000; counted 8100 -> variance +100 (overage; reason) -- 1-8
select is((app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','cl-c1',8100,'till over') ->> 'ok')::boolean, true, 'close da11 succeeds');
select is((select expected_total_minor from shifts where id='00000000-0000-0000-0000-00000000a5f1')::bigint, 8000::bigint, 'expected_total = opening float (5000) + cash sales (3000) = 8000');
select is((select counted_total_minor from shifts where id='00000000-0000-0000-0000-00000000a5f1')::bigint, 8100::bigint, 'counted_total stored (8100)');
select is((select variance_minor from shifts where id='00000000-0000-0000-0000-00000000a5f1')::bigint, 100::bigint, 'variance = counted - expected = +100 (overage)');
select is((select status from shifts where id='00000000-0000-0000-0000-00000000a5f1')::text, 'closed', 'shift moved to closed');
select is((select status from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1')::text, 'closed', 'drawer moved to closed');
select is((select variance_minor from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1')::bigint, 100::bigint, 'variance is also persisted on the drawer');
select is((select new_values->>'cash_sales_minor' from audit_events where action='shift.closed' and (new_values->>'shift_id')='00000000-0000-0000-0000-00000000a5f1'), '3000', 'shift.closed audit records cash_sales_minor = 3000');

-- da22: expected 1000+1000=2000; a non-zero variance close WITHOUT reason fails - 9-12
select throws_ok($$ select app.close_shift('00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000da22','cl-c2a',1700,null) $$, '42501', NULL, 'a non-zero-variance close without a reason is rejected (A7)');
select is((app.close_shift('00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000da22','cl-c2b',1700,'till short') ->> 'ok')::boolean, true, 'close da22 succeeds with a reason');
select is((select expected_total_minor from shifts where id='00000000-0000-0000-0000-00000000a5f2')::bigint, 2000::bigint, 'expected_total = 1000 + 1000 = 2000');
select is((select variance_minor from shifts where id='00000000-0000-0000-0000-00000000a5f2')::bigint, (-300)::bigint, 'variance = 1700 - 2000 = -300 (shortage; negative)');

-- da33: no sales, expected 500; counted 500 -> variance 0, no reason needed ---- 13-15
select is((app.close_shift('00000000-0000-0000-0000-00000000c513','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000da33','cl-c3',500,null) ->> 'ok')::boolean, true, 'close da33 (variance 0) succeeds without a reason');
select is((select variance_minor from shifts where id='00000000-0000-0000-0000-00000000a5f3')::bigint, 0::bigint, 'variance is 0 (counted 500 == expected 500)');
select is((select status from shifts where id='00000000-0000-0000-0000-00000000a5f3')::text, 'closed', 'da33 shift is closed');

select * from finish();
rollback;
