-- ============================================================================
-- RF-059 — pgTAP: accountant is strictly read-only (T-011, D-028)
-- ============================================================================
-- The accountant role may READ permitted financial data within scope (it is a
-- financial-visibility role, NOT kitchen) but performs NO mutation: direct writes
-- are denied, and a mutating RPC (reconcile_shift / close_shift) returns
-- permission_denied. Fixtures (order, completed payment, a closed shift+drawer)
-- inserted as the BYPASSRLS connection role; assertions run as the accountant.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059acc-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf059acc-accountant@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'accountant');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef0ac', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000ac');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000005ac', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0ac', '00000000-0000-0000-0000-0000000000ac', now() + interval '1 hour');
-- an order + a completed payment + a CLOSED shift/drawer (for the reconcile-denial check)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000005ac','00000000-0000-0000-0000-0000000ef0ac','00000000-0000-0000-0000-0000000000ac','dine_in','submitted','USD',1000,1000,'oa1');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0000000a0fa1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef0ac','00000000-0000-0000-0000-0000000000ac','cash','completed',1000,1000,0,'USD','pa1');
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, status, expected_total_minor, counted_total_minor, variance_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a5f1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef0ac','00000000-0000-0000-0000-0000000000ac','closed',1000,1000,0,'sfx');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, status, expected_total_minor, counted_total_minor, variance_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000acd1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-0000000ef0ac',0,'closed',1000,1000,0,'dfx');

-- ===== accountant: READS permitted financial data ========================== 1-3
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0a';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from payments)::int, 1, 'accountant CAN SELECT payments (financial-visibility role)');
select is((select count(*) from shifts)::int,   1, 'accountant CAN SELECT shifts');
select is((select count(*) from orders)::int,   1, 'accountant CAN SELECT orders');

-- ===== accountant: NO direct mutation ======================================= 4-5
select throws_ok(
  $$ insert into payments (organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef0ac','00000000-0000-0000-0000-0000000000ac','cash','completed',1,1,0,'USD','acc-direct') $$,
  '42501', NULL, 'accountant CANNOT directly INSERT a payment (writes revoked)');
select throws_ok(
  $$ update shifts set status='reconciled' where id='00000000-0000-0000-0000-00000000a5f1' $$,
  '42501', NULL, 'accountant CANNOT directly UPDATE a shift (writes revoked)');
reset role;

-- ===== accountant: mutating RPCs are denied (T-011, D-028) ================== 6-8
select is((app.reconcile_shift('00000000-0000-0000-0000-0000000005ac','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','acc-rec',null) ->> 'ok')::boolean, false,
  'accountant reconcile_shift is denied (ok=false)');
select is((app.reconcile_shift('00000000-0000-0000-0000-0000000005ac','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','acc-rec2',null) ->> 'error'), 'permission_denied',
  'accountant reconcile_shift returns permission_denied (separation of duties, D-028)');
select is((app.close_shift('00000000-0000-0000-0000-0000000005ac','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','acc-cls',1000,null) ->> 'error'), 'permission_denied',
  'accountant close_shift returns permission_denied (strictly read-only)');

select * from finish();
rollback;
