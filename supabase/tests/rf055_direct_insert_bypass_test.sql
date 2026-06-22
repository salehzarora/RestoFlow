-- ============================================================================
-- RF-055 — pgTAP: direct-write bypass prevention
-- ============================================================================
-- An `authenticated` client must NOT write shifts / cash_drawer_sessions /
-- shift_operations directly (that would bypass the open/close/reconcile RPCs'
-- authorization, state machines, reconciliation math, and idempotency).
-- INSERT/UPDATE/DELETE are revoked; the SECURITY DEFINER RPCs are the only writers
-- (D-011). Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf055b-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf055b-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- ===== authenticated: direct writes to the new tables are DENIED ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select throws_ok($$ insert into shifts (organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','d1') $$, '42501', NULL, 'authenticated direct INSERT into shifts is DENIED');                                                          -- 1
select throws_ok($$ update shifts set status='closed' where id='00000000-0000-0000-0000-00000000a5f1' $$, '42501', NULL, 'authenticated direct UPDATE on shifts is DENIED');                                                              -- 2
select throws_ok($$ delete from shifts where id='00000000-0000-0000-0000-00000000a5f1' $$, '42501', NULL, 'authenticated direct DELETE on shifts is DENIED');                                                                            -- 3
select throws_ok($$ insert into cash_drawer_sessions (organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-0000000ef001',0,'d2') $$, '42501', NULL, 'authenticated direct INSERT into cash_drawer_sessions is DENIED'); -- 4
select throws_ok($$ update cash_drawer_sessions set status='closed' where id='00000000-0000-0000-0000-00000000acd1' $$, '42501', NULL, 'authenticated direct UPDATE on cash_drawer_sessions is DENIED');                                  -- 5
select throws_ok($$ delete from cash_drawer_sessions where id='00000000-0000-0000-0000-00000000acd1' $$, '42501', NULL, 'authenticated direct DELETE on cash_drawer_sessions is DENIED');                                                -- 6
select throws_ok($$ insert into shift_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, shift_id, result) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','x','open_shift','00000000-0000-0000-0000-00000000a5f1','{}'::jsonb) $$, '42501', NULL, 'authenticated cannot directly write the shift_operations ledger'); -- 7

reset role;

-- ===== the SECURITY DEFINER RPC path CAN open a shift ======================= 8-9
select is((app.open_shift('00000000-0000-0000-0000-00000000c511','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-rpc',0) ->> 'status'), 'open', 'the SECURITY DEFINER RPC path CAN open a shift');
select is((select count(*) from shifts where device_id='00000000-0000-0000-0000-00000000da11')::int, 1, 'the RPC created exactly one shift (the only write path)');

select * from finish();
rollback;
