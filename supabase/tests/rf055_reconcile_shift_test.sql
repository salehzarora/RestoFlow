-- ============================================================================
-- RF-055 — pgTAP: reconcile_shift (managerial sign-off; D-028)
-- ============================================================================
-- A manager reconciles a CLOSED shift+drawer to reconciled (terminal). A non-empty
-- note is REQUIRED when the variance is non-zero. A reconciled shift is terminal
-- (cannot be closed or reconciled again); an open shift cannot be reconciled. The
-- cashier opens+closes; the manager reconciles (separation of duties). Fixtures
-- inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055r-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf055r-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf055r-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c512', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c521', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c522', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- ---- da11: open (float 0) -> close (counted 0, variance 0) -> reconcile ----- 1-5
select app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','o-sh1',0);
select is((app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c-sh1',0,null) ->> 'variance_minor'), '0', 'cashier closes da11 with variance 0');
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','rc-sh1',null) ->> 'status'), 'reconciled', 'manager reconciles the variance-0 shift without a note');
select is((select status from shifts where id='00000000-0000-0000-0000-00000000a5f1')::text, 'reconciled', 'shift is reconciled (terminal)');
select is((select status from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1')::text, 'reconciled', 'the bound drawer is reconciled');
select is((select reconciled_by_employee_profile_id from shifts where id='00000000-0000-0000-0000-00000000a5f1'), '00000000-0000-0000-0000-0000000ef002'::uuid, 'reconciled_by records the manager');

-- ---- da22: close with variance +500 -> reconcile needs a note --------------- 6-8
select app.open_shift('00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000acd2','00000000-0000-0000-0000-00000000da22','o-sh2',0);
select app.close_shift('00000000-0000-0000-0000-00000000c512','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000da22','c-sh2',500,'till over');
select throws_ok($$ select app.reconcile_shift('00000000-0000-0000-0000-00000000c522','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000da22','rc-sh2a',null) $$, '42501', NULL, 'reconciling a non-zero-variance shift without a note is rejected (A7)');
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c522','00000000-0000-0000-0000-00000000a5f2','00000000-0000-0000-0000-00000000da22','rc-sh2b','approved over') ->> 'status'), 'reconciled', 'manager reconciles with a note when variance is non-zero');
select is((select status from shifts where id='00000000-0000-0000-0000-00000000a5f2')::text, 'reconciled', 'da22 shift is reconciled');

-- ---- terminal behavior + wrong-source-state rejections ---------------------- 9-12
select throws_ok($$ select app.close_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','c-sh1-again',0,null) $$, '42501', NULL, 'a reconciled shift cannot be closed again (terminal)');
select throws_ok($$ select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','rc-sh1-again',null) $$, '42501', NULL, 'a reconciled shift cannot be reconciled again (must be closed)');
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000acd3','00000000-0000-0000-0000-00000000da11','o-sh3',0) ->> 'status'), 'open', 'a new shift can open on da11 now the prior one is terminal');
select throws_ok($$ select app.reconcile_shift('00000000-0000-0000-0000-00000000c521','00000000-0000-0000-0000-00000000a5f3','00000000-0000-0000-0000-00000000da11','rc-sh3',null) $$, '42501', NULL, 'an OPEN shift cannot be reconciled (must be closed first)');

select * from finish();
rollback;
