-- RF-112 Stage 3 -- activate_device: the explicit paired -> active edge (D-034 / §4.28 / STATE_MACHINES §9).
-- paired -> active only; pending -> active impossible; approve_device still stops at paired; role/scope
-- matrix; fail-closed on every non-paired state; audit + idempotency. GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(24);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112act-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112act-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000a1d00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1 Del'),
  ('00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112act-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf112act-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112act-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112act-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf112act-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf112act-acct@example.test'),
  ('00000000-0000-0000-0000-0000000000e7', 'rf112act-platadmin@example.test'),
  ('00000000-0000-0000-0000-0000000000e8', 'rf112act-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant');
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e7');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000dddd0001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Dev A1a'),
  ('00000000-0000-0000-0000-0000dddd0002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000a2a00', 'pos', 'Dev A2a'),
  ('00000000-0000-0000-0000-0000dddd0003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1b00', 'pos', 'Dev A1b'),
  ('00000000-0000-0000-0000-0000dddd0004', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'pos', 'Dev B1a'),
  ('00000000-0000-0000-0000-0000dddd0005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1d00', 'pos', 'Dev A1d');
-- pairings: paired (success/denial targets), the various non-paired states, and cross-scope paired ones.
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at) values
  ('00000000-0000-0000-0000-0000aaaa0001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa0002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa0003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa0004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa0005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'code_issued', null),
  ('00000000-0000-0000-0000-0000aaaa0006', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'pending', null),
  ('00000000-0000-0000-0000-0000aaaa0007', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa0008', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'suspended', now()),
  ('00000000-0000-0000-0000-0000aaaa0009', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'revoked', null),
  ('00000000-0000-0000-0000-0000aaaa000a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'code_expired', null),
  ('00000000-0000-0000-0000-0000aaaa000b', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-0000dddd0002', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa000c', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000dddd0003', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa000d', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000dddd0004', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa000e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1d00', '00000000-0000-0000-0000-0000dddd0005', 'paired', now());
-- tombstone the soft-deleted branch (its paired pairing 000e is now on a dead scope)
update branches set deleted_at = now() where id = '00000000-0000-0000-0000-0000000a1d00';

set local role authenticated;

-- ===== success: org_owner / restaurant_owner / manager activate (paired -> active) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select is(
  (app.activate_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0001') ->> 'status'),
  'active', 'org_owner activates a paired pairing -> active');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select is(
  (app.activate_device('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000aaaa0002') ->> 'status'),
  'active', 'restaurant_owner activates a paired pairing in its restaurant');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select is(
  (app.activate_device('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000aaaa0003') ->> 'status'),
  'active', 'manager activates a paired pairing in its branch');

-- ===== fail-closed: every NON-paired state is rejected (42501). pending -> active is impossible. =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner (authorized; only the state guard fires)
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000aaaa0005') $$,
  '42501', NULL, 'activate rejects a code_issued pairing (42501)');
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000aaaa0006') $$,
  '42501', NULL, 'activate rejects a PENDING pairing (pending -> active is impossible; 42501)');
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000aaaa0007') $$,
  '42501', NULL, 'activate rejects an already-active pairing (42501)');
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000aaaa0008') $$,
  '42501', NULL, 'activate rejects a suspended pairing (42501)');
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000aaaa0009') $$,
  '42501', NULL, 'activate rejects a revoked pairing (42501)');
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000aaaa000a') $$,
  '42501', NULL, 'activate rejects a code_expired pairing (42501)');

-- ===== role denials (on a paired pairing 0004) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is((app.activate_device('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000aaaa0004') ->> 'error'),
  'permission_denied', 'cashier cannot activate (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e5';  -- kitchen_staff
select is((app.activate_device('00000000-0000-0000-0000-00000000c00b','00000000-0000-0000-0000-0000aaaa0004') ->> 'error'),
  'permission_denied', 'kitchen_staff cannot activate (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';  -- accountant
select is((app.activate_device('00000000-0000-0000-0000-00000000c00c','00000000-0000-0000-0000-0000aaaa0004') ->> 'error'),
  'permission_denied', 'accountant cannot activate (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';  -- platform-admin-only
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c00d','00000000-0000-0000-0000-0000aaaa0004') $$,
  '42501', NULL, 'platform-admin-only cannot activate (no tenant membership; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e8';  -- nobody
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c00e','00000000-0000-0000-0000-0000aaaa0004') $$,
  '42501', NULL, 'non-member cannot activate (42501)');

-- ===== scope denials: cross-org / cross-restaurant / sibling-branch / soft-deleted =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org A owner
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c00f','00000000-0000-0000-0000-0000aaaa000d') $$,
  '42501', NULL, 'org_owner of Org A cannot activate an Org B pairing (cross-org; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c010','00000000-0000-0000-0000-0000aaaa000b') $$,
  '42501', NULL, 'restaurant_owner(A1) cannot activate a sibling-restaurant A2 pairing (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000aaaa000c') $$,
  '42501', NULL, 'manager(A1a) cannot activate a sibling-branch A1b pairing (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c012','00000000-0000-0000-0000-0000aaaa000e') $$,
  '42501', NULL, 'cannot activate a pairing on a soft-deleted branch (42501)');

-- ===== lifecycle proof: approve_device stops at paired, then activate_device goes active (separately) =====
select is((app.approve_device('00000000-0000-0000-0000-00000000c013','00000000-0000-0000-0000-0000aaaa0006') ->> 'status'),
  'paired', 'approve_device on the pending pairing -> paired (NOT active)');
select is((app.activate_device('00000000-0000-0000-0000-00000000c014','00000000-0000-0000-0000-0000aaaa0006') ->> 'status'),
  'active', 'activate_device then takes the now-paired pairing -> active (full chain, separate edges)');

-- ===== idempotency: replay + conflict =====
select is((app.activate_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0001') ->> 'idempotent_replay'),
  'true', 'activate replay (same client_request_id) -> idempotent_replay true');
select throws_ok($$ select app.activate_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0004') $$,
  '42501', NULL, 'activate same client_request_id with a different pairing -> conflict (42501)');

-- ===== audit (as the BYPASSRLS owner) =====
reset role;
select is((select count(*) from audit_events where action = 'device.activated'
     and (new_values ->> 'device_pairing_id') = '00000000-0000-0000-0000-0000aaaa0001')::int,
  1, 'a device.activated audit row was written for the successful activation');
select is((select count(*) from audit_events where action = 'device.activate_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-0000000000e4')::int,
  1, 'the cashier activate-denial wrote one device.activate_denied audit row');

select * from finish();
rollback;
