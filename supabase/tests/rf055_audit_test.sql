-- ============================================================================
-- RF-055 — pgTAP: append-only audit (D-013)
-- ============================================================================
-- A full open/close/reconcile cycle writes the six success audit rows
-- (shift.opened, cash_drawer.opened, shift.closed, cash_drawer.closed,
-- shift.reconciled, cash_drawer.reconciled) carrying the relevant amounts; denied
-- attempts write shift.open_denied / shift.close_denied; replays write no
-- duplicate audit rows. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055a-a', 'USD');
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
  ('00000000-0000-0000-0000-00000000ee01', 'rf055a-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf055a-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf055a-accountant@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf055a-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager'),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', null, null, 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-00000000ab03'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c521', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c531', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c541', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- open (float 5000), denied attempts, close (variance 0), reconcile -----------
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o1',5000);
select app.open_shift('00000000-0000-0000-0000-00000000c541','00000000-0000-0000-0000-00000000a5f8','00000000-0000-0000-0000-00000000acd8','00000000-0000-0000-0000-00000000da11','o-ks',0);   -- kitchen denied
select app.close_shift('00000000-0000-0000-0000-00000000c531','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c-ac',0,null);                                       -- accountant denied
select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c1',5000,null);
select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','r1',null);

-- the six success audit actions --------------------------------------------- 1-6
select is((select count(*) from audit_events where action='shift.opened')::int,           1, 'shift.opened written');
select is((select count(*) from audit_events where action='cash_drawer.opened')::int,     1, 'cash_drawer.opened written');
select is((select count(*) from audit_events where action='shift.closed')::int,           1, 'shift.closed written');
select is((select count(*) from audit_events where action='cash_drawer.closed')::int,     1, 'cash_drawer.closed written');
select is((select count(*) from audit_events where action='shift.reconciled')::int,       1, 'shift.reconciled written');
select is((select count(*) from audit_events where action='cash_drawer.reconciled')::int, 1, 'cash_drawer.reconciled written');

-- audit content -------------------------------------------------------------- 7-8
select is((select new_values->>'opening_float_minor' from audit_events where action='cash_drawer.opened'), '5000', 'cash_drawer.opened records the opening float');
select is((select new_values->>'variance_minor' from audit_events where action='shift.closed'), '0', 'shift.closed records the variance');

-- denied attempts audited ---------------------------------------------------- 9-10
select is((select count(*) from audit_events where action='shift.open_denied')::int,  1, 'shift.open_denied written (kitchen)');
select is((select count(*) from audit_events where action='shift.close_denied')::int, 1, 'shift.close_denied written (accountant)');

-- replays write NO duplicate audit ------------------------------------------- 11-12
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o1',5000);
select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','r1',null);
select is((select count(*) from audit_events where action='shift.opened')::int,     1, 'replayed open wrote no second shift.opened');
select is((select count(*) from audit_events where action='shift.reconciled')::int, 1, 'replayed reconcile wrote no second shift.reconciled');

select * from finish();
rollback;
