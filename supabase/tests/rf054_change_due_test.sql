-- ============================================================================
-- RF-054 — pgTAP: change due = tendered - total, integer _minor (AC#3)
-- ============================================================================
-- change_due_minor = amount_tendered_minor - orders.grand_total_minor: zero when
-- exact, positive when over, and a tender BELOW the total is rejected (change is
-- never negative). A negative tender is rejected. All money is integer bigint
-- _minor (D-007) — the bigint signature/columns structurally exclude float/
-- fractional money. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf054c-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee02', 'rf054c-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
-- three orders, each grand_total 1000
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'c-o1'),
  ('00000000-0000-0000-0000-00000000c0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'c-o2'),
  ('00000000-0000-0000-0000-00000000c0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'c-o3');

-- tendered exactly equals total -> change 0 --------------------------------- 1-2
select is(app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000c0d1','00000000-0000-0000-0000-00000000da11','c-p1','cash',1000,null) ->> 'change_due_minor', '0', 'tendered == total => change_due_minor 0');
select is((select change_minor from payments where order_id='00000000-0000-0000-0000-00000000c0d1')::bigint, 0::bigint, 'stored payments.change_minor is 0');

-- tendered greater than total -> positive change ---------------------------- 3-4
select is(app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000c0d2','00000000-0000-0000-0000-00000000da11','c-p2','cash',1500,null) ->> 'change_due_minor', '500', 'tendered > total => change_due_minor 500');
select is((select change_minor from payments where order_id='00000000-0000-0000-0000-00000000c0d2')::bigint, 500::bigint, 'stored payments.change_minor is 500');

-- tendered less than total -> rejected (change never negative) -------------- 5
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000c0d3','00000000-0000-0000-0000-00000000da11','c-p3','cash',900,null) $$, '42501', NULL, 'tendered < total is rejected (no negative change)');

-- negative tender -> rejected ----------------------------------------------- 6
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000c0d3','00000000-0000-0000-0000-00000000da11','c-p4','cash',-100,null) $$, '42501', NULL, 'a negative tender is rejected');

-- money is integer bigint _minor (no float/fraction can persist; D-007) ----- 7
select is((select data_type from information_schema.columns where table_schema='public' and table_name='payments' and column_name='change_minor'), 'bigint', 'change_minor is integer bigint _minor (non-integer money structurally precluded)');

select * from finish();
rollback;
