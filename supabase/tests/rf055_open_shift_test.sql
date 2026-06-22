-- ============================================================================
-- RF-055 — pgTAP: open_shift
-- ============================================================================
-- A cashier opens a shift + its bound active cash drawer (one call); the opening
-- float is recorded; shift.opened + cash_drawer.opened are audited. Denied roles
-- (kitchen_staff/accountant) get permission_denied + a shift.open_denied audit and
-- create nothing. opening_float < 0 is rejected. One active shift per (org,branch,
-- device) is enforced. A replay is safe (no duplicate shift). Fixtures inserted as
-- the BYPASSRLS connection role; the RPC is SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055o-a', 'USD');
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
  ('00000000-0000-0000-0000-00000000ee01', 'rf055o-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf055o-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf055o-accountant@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf055o-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'accountant'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-00000000ab03'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- cashier opens a shift + bound active drawer (opening float 5000) ----------- 1-5
select is((app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000) ->> 'status'), 'open', 'cashier opens a shift (status open)');
select is((select status from shifts where id='00000000-0000-0000-0000-00000000a5f1')::text, 'open', 'the shift row is open');
select is((select status from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1')::text, 'active', 'the bound cash drawer is active');
select is((select opening_float_minor from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1')::bigint, 5000::bigint, 'opening float is recorded (5000)');
select is((select shift_id from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1'), '00000000-0000-0000-0000-00000000a5f1'::uuid, 'the drawer is bound to the shift');

-- audits ---------------------------------------------------------------------- 6-7
select is((select count(*) from audit_events where action='shift.opened')::int,        1, 'one shift.opened audit row');
select is((select count(*) from audit_events where action='cash_drawer.opened')::int,  1, 'one cash_drawer.opened audit row');

-- denied roles: kitchen_staff + accountant ----------------------------------- 8-11
select is(app.open_shift('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000a5f8','00000000-0000-0000-0000-00000000acd8','00000000-0000-0000-0000-00000000da11','op-ks',0) ->> 'error', 'permission_denied', 'kitchen_staff is denied open_shift');
select is(app.open_shift('00000000-0000-0000-0000-00000000c503','00000000-0000-0000-0000-00000000a5f9','00000000-0000-0000-0000-00000000acd9','00000000-0000-0000-0000-00000000da11','op-ac',0) ->> 'error', 'permission_denied', 'accountant is denied open_shift');
select is((select count(*) from audit_events where action='shift.open_denied')::int, 2, 'both denials wrote a shift.open_denied audit row');
select is((select count(*) from shifts where id in ('00000000-0000-0000-0000-00000000a5f8','00000000-0000-0000-0000-00000000a5f9'))::int, 0, 'denied opens created NO shift');

-- opening float negative is rejected ----------------------------------------- 12
select throws_ok($$ select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000acd3','00000000-0000-0000-0000-00000000da11','op-neg',-100) $$, '42501', NULL, 'a negative opening float is rejected');

-- one active shift per (org, branch, device) --------------------------------- 13
select throws_ok($$ select app.open_shift('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000acd2','00000000-0000-0000-0000-00000000da11','op-2nd',0) $$, '42501', NULL, 'a second active shift on the same branch/device is rejected (A1)');

-- replay is safe ------------------------------------------------------------- 14-15
select is((app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000) ->> 'idempotency_replay')::boolean, true, 'replaying the same open is flagged idempotency_replay');
select is((select count(*) from shifts where device_id='00000000-0000-0000-0000-00000000da11')::int, 1, 'replay created no second shift (exactly one shift on the device)');

select * from finish();
rollback;
