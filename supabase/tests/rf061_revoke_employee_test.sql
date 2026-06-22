-- ============================================================================
-- RF-061 — pgTAP: app.revoke_employee
-- ============================================================================
-- A manager revokes a same-org employee: employment_status -> terminated and the org
-- memberships -> revoked, with an employee.revoked audit. A cashier is denied
-- (employee.revoke_denied + permission_denied). A cross-org target is rejected.
-- Re-revoke is idempotent. Existing COMPLETED orders/payments are NOT touched.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf061re-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf061re-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf061re-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf061re-target@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf061re-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf061re-orgb@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-00000000ab03'),
  ('00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-00000000ab0b');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');
-- a pre-existing COMPLETED order + payment for the target employee (must remain untouched)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','completed','USD',1000,1000,'oa1-hist');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0000000a0fa1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','cash','completed',1000,1000,0,'USD','pa1-hist');

-- ===== manager revokes the target employee ================================= 1-4
select is((app.revoke_employee('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','op-re','left the company') ->> 'ok')::boolean, true,
  'manager can revoke a same-org employee');
select is((select employment_status from employee_profiles where id='00000000-0000-0000-0000-0000000ef002')::text, 'terminated', 'the target employee profile is terminated');
select is((select status from memberships where id='00000000-0000-0000-0000-00000000ab02')::text, 'revoked', 'the target org membership is revoked');
select ok(exists(select 1 from audit_events where action='employee.revoked' and (new_values->>'target_employee_profile_id')='00000000-0000-0000-0000-0000000ef002'),
  'an employee.revoked audit row was written');

-- ===== a cashier cannot revoke (audited denial) ============================= 5-6
select is((app.revoke_employee('00000000-0000-0000-0000-00000000c503','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','op-re2','try') ->> 'error'), 'permission_denied',
  'a cashier cannot revoke an employee (permission_denied)');
select ok(exists(select 1 from audit_events where action='employee.revoke_denied' and (new_values->>'role')='cashier'),
  'the denied employee revoke is audited (employee.revoke_denied)');

-- ===== cross-org target rejected; idempotent re-revoke ====================== 7-8
select throws_ok(
  $$ select app.revoke_employee('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef00b','op-re3','x') $$,
  '42501', NULL, 'a cross-org target employee cannot be revoked');
select is((app.revoke_employee('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','op-re4','again') ->> 'idempotency_replay')::boolean, true,
  're-revoking an already-revoked employee is an idempotent clean replay');

-- ===== existing completed records are untouched ============================= 9
select ok(
  (select status from orders where id='00000000-0000-0000-0000-00000000a0d1')='completed'
  and (select status from payments where id='00000000-0000-0000-0000-0000000a0fa1')='completed',
  'the target employee''s existing COMPLETED order + payment are untouched by revocation (no historical rewrite)');

select * from finish();
rollback;
