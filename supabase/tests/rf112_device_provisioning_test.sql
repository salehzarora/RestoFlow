-- RF-112 Stage 2 -- device provisioning lifecycle + create_device role/scope matrix
-- (D-033 / §4.27 / STATE_MACHINES §9 / T-015). Lifecycle: create -> issue (code_issued)
-- -> redeem (code_issued->pending) -> approve (pending->paired). GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(19);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112dp-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112dp-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000a1d00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1 Del'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112dp-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf112dp-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112dp-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112dp-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf112dp-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf112dp-acct@example.test'),
  ('00000000-0000-0000-0000-0000000000e7', 'rf112dp-platadmin@example.test'),
  ('00000000-0000-0000-0000-0000000000e8', 'rf112dp-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant');
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e7');
-- a device directly seeded for the issue->redeem->approve lifecycle
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Lifecycle POS');
-- tombstone a branch (for the soft-deleted-scope denial)
update branches set deleted_at = now() where id = '00000000-0000-0000-0000-0000000a1d00';

-- capture table for the one-time enrollment code (created as owner; granted to authenticated so
-- the test does not depend on the authenticated role holding the TEMPORARY privilege).
create temp table _iss (code text, pairing uuid, status text);
grant select, insert on _iss to authenticated;

set local role authenticated;

-- ===== create_device role/scope matrix (no org GUC is ever set -> GUC-free) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','POS One') ->> 'ok'),
  'true', 'org_owner creates a device in scope');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','kds','KDS One') ->> 'ok'),
  'true', 'restaurant_owner creates a device in its restaurant');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','POS Two') ->> 'ok'),
  'true', 'manager creates a device in its own branch');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','x') ->> 'error'),
  'permission_denied', 'cashier cannot provision a device (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e5';  -- kitchen_staff
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','x') ->> 'error'),
  'permission_denied', 'kitchen_staff cannot provision a device (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';  -- accountant
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','x') ->> 'error'),
  'permission_denied', 'accountant cannot provision a device (permission_denied)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';  -- platform-admin-only
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','x') $$,
  '42501', NULL, 'platform-admin-only principal cannot provision a device (no tenant membership; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e8';  -- nobody
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','x') $$,
  '42501', NULL, 'non-member cannot provision a device (42501)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner @ Org A
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000b1a00','pos','x') $$,
  '42501', NULL, 'org_owner of Org A cannot create a device in Org B (cross-org; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2',null,'pos','x') $$,
  '42501', NULL, 'restaurant_owner(A1) cannot create a device in sibling restaurant A2 (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c00b','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1b00','pos','x') $$,
  '42501', NULL, 'manager(A1a) cannot create a device in sibling branch A1b (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c00c','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1d00','pos','x') $$,
  '42501', NULL, 'cannot create a device in a soft-deleted branch (42501)');
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c00d','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','tablet','x') $$,
  '42501', NULL, 'invalid device_type is rejected (42501)');

-- ===== lifecycle: issue -> redeem -> approve on the seeded device d1 (as org_owner) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
insert into _iss
  select (r ->> 'enrollment_code'), (r ->> 'device_pairing_id')::uuid, (r ->> 'status')
  from (select app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c010','00000000-0000-0000-0000-0000000000d1') as r) s;
select is((select status from _iss), 'code_issued', 'issue_device_enrollment_code -> a code_issued pairing');
select isnt((select code from _iss), null, 'issue returns a plaintext enrollment code (once)');
select is(
  (app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000d1', (select code from _iss)) ->> 'status'),
  'pending', 'redeem_device_enrollment_code: code_issued -> pending');
select is(
  (app.approve_device('00000000-0000-0000-0000-00000000c012', (select pairing from _iss)) ->> 'status'),
  'paired', 'approve_device: pending -> paired (NOT active)');

-- ===== DB-state verification (as the BYPASSRLS owner) =====
reset role;
select is(
  (select count(*) from devices where organization_id = '00000000-0000-0000-0000-0000000000a0'
     and label = 'POS One' and device_type = 'pos' and deleted_at is null)::int,
  1, 'the org_owner create_device persisted exactly one device row');
select is(
  (select count(*) from device_pairings where device_id = '00000000-0000-0000-0000-0000000000d1'
     and status = 'paired' and paired_at is not null)::int,
  1, 'the approved pairing is paired in the DB (paired_at set, never active)');

select * from finish();
rollback;
