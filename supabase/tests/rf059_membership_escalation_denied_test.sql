-- ============================================================================
-- RF-059 — pgTAP: sensitive-management direct writes denied (A2, T-002/T-008)
-- ============================================================================
-- The headline RF-059 hardening: closing the membership/device self-escalation hole.
-- Under the non-privileged `authenticated` role, a cashier cannot directly INSERT a
-- membership (e.g. self-grant org_owner), UPDATE its own membership's role, or write
-- any sensitive-management table; a kitchen_staff principal cannot create devices /
-- pairings / sessions. All such direct writes are REVOKED (42501). Fixtures inserted
-- as the BYPASSRLS connection role; assertions run as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059esc-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf059esc-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf059esc-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');

-- ===== cashier: every sensitive-management direct write is DENIED ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

-- the self-escalation attempt: insert a fresh org_owner membership for myself ----- 1
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-00000000ee01','00000000-0000-0000-0000-0000000000a0','org_owner') $$,
  '42501', NULL, 'cashier CANNOT INSERT a membership (self-grant org_owner is denied)');
-- the in-place escalation attempt: promote my own cashier membership to org_owner -- 2
select throws_ok(
  $$ update memberships set role='org_owner' where id='00000000-0000-0000-0000-00000000ab01' $$,
  '42501', NULL, 'cashier CANNOT UPDATE its own membership role to org_owner');
-- deleting a membership is denied --------------------------------------------------- 3
select throws_ok(
  $$ delete from memberships where id='00000000-0000-0000-0000-00000000ab01' $$,
  '42501', NULL, 'cashier CANNOT DELETE a membership');
-- other sensitive-management tables -------------------------------------------- 4-7
select throws_ok(
  $$ insert into employee_profiles (organization_id, restaurant_id, branch_id, display_name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','rogue') $$,
  '42501', NULL, 'cashier CANNOT INSERT an employee_profile (writes are RPC-only)');
select throws_ok(
  $$ insert into restaurants (organization_id, name) values ('00000000-0000-0000-0000-0000000000a0','rogue') $$,
  '42501', NULL, 'cashier CANNOT INSERT a restaurant');
select throws_ok(
  $$ insert into branches (organization_id, restaurant_id, name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','rogue') $$,
  '42501', NULL, 'cashier CANNOT INSERT a branch');
select throws_ok(
  $$ insert into stations (organization_id, restaurant_id, branch_id, name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','rogue') $$,
  '42501', NULL, 'cashier CANNOT INSERT a station');

-- ===== kitchen_staff: device/pairing/session creation is DENIED ============== 8-10
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee04';
select throws_ok(
  $$ insert into devices (organization_id, restaurant_id, branch_id, device_type) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','kds') $$,
  '42501', NULL, 'kitchen_staff CANNOT create a device');
select throws_ok(
  $$ insert into device_pairings (organization_id, restaurant_id, branch_id, device_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11') $$,
  '42501', NULL, 'kitchen_staff CANNOT create a device_pairing');
select throws_ok(
  $$ update devices set label='hijack' where id='00000000-0000-0000-0000-00000000da11' $$,
  '42501', NULL, 'kitchen_staff CANNOT UPDATE a device');

-- ===== positive control: SELECT in-scope is still permitted ================== 11-12
select is((select count(*) from memberships where app_user_id='00000000-0000-0000-0000-00000000ee04')::int, 1,
  'kitchen_staff CAN still SELECT its own membership (reads are not revoked)');
select is((select count(*) from devices)::int, 1,
  'kitchen_staff CAN still SELECT in-scope devices (only writes are locked down)');

select * from finish();
rollback;
