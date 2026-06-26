-- RF-112 Stage 3 -- start_device_session security: every NON-active pairing fails closed; role + scope
-- denials; revoked/soft-deleted; anon cannot call the RPCs (D-034 / §4.29 / T-004 / T-015 / RISK R-007).
-- GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(17);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112ss-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112ss-b', 'EUR');
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
  ('00000000-0000-0000-0000-0000000000e1', 'rf112ss-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf112ss-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112ss-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112ss-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf112ss-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf112ss-acct@example.test'),
  ('00000000-0000-0000-0000-0000000000e7', 'rf112ss-platadmin@example.test'),
  ('00000000-0000-0000-0000-0000000000e8', 'rf112ss-nobody@example.test');
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
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at) values
  ('00000000-0000-0000-0000-0000aaaa0001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa0002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'code_issued', null),
  ('00000000-0000-0000-0000-0000aaaa0003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'pending', null),
  ('00000000-0000-0000-0000-0000aaaa0004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'suspended', now()),
  ('00000000-0000-0000-0000-0000aaaa0005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'revoked', null),
  ('00000000-0000-0000-0000-0000aaaa0006', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'code_expired', null),
  ('00000000-0000-0000-0000-0000aaaa0007', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'paired', now()),
  ('00000000-0000-0000-0000-0000aaaa0008', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-0000dddd0002', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa0009', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000dddd0003', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa000a', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000dddd0004', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa000b', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1d00', '00000000-0000-0000-0000-0000dddd0005', 'active', now());
-- tombstone the soft-deleted branch (its active pairing 000b is now on a dead scope)
update branches set deleted_at = now() where id = '00000000-0000-0000-0000-0000000a1d00';

set local role authenticated;

-- ===== every NON-active pairing fails closed (org_owner; only the active-state guard fires) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0002') $$,
  '42501', NULL, 'no session on a code_issued pairing (42501)');
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000aaaa0003') $$,
  '42501', NULL, 'no session on a pending pairing (42501)');
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000aaaa0004') $$,
  '42501', NULL, 'no session on a suspended pairing (42501)');
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000aaaa0005') $$,
  '42501', NULL, 'no session on a revoked pairing — revoked device cannot start a session (42501; T-004)');
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000aaaa0006') $$,
  '42501', NULL, 'no session on a code_expired pairing (42501)');
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000aaaa0007') $$,
  '42501', NULL, 'no session on a paired (not-yet-active) pairing (42501)');

-- ===== role denials (on the active pairing 0001) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is((app.start_device_session('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000aaaa0001') ->> 'error'),
  'permission_denied', 'cashier cannot start a device session (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e5';  -- kitchen_staff
select is((app.start_device_session('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000aaaa0001') ->> 'error'),
  'permission_denied', 'kitchen_staff cannot start a device session (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';  -- accountant
select is((app.start_device_session('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000aaaa0001') ->> 'error'),
  'permission_denied', 'accountant cannot start a device session (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';  -- platform-admin-only
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000aaaa0001') $$,
  '42501', NULL, 'platform-admin-only cannot start a device session (no tenant membership; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e8';  -- nobody
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c00b','00000000-0000-0000-0000-0000aaaa0001') $$,
  '42501', NULL, 'non-member cannot start a device session (42501)');

-- ===== scope denials: cross-org / cross-restaurant / sibling-branch / soft-deleted (active pairings) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org A owner
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c00c','00000000-0000-0000-0000-0000aaaa000a') $$,
  '42501', NULL, 'org_owner of Org A cannot start a session on an Org B pairing (cross-org; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c00d','00000000-0000-0000-0000-0000aaaa0008') $$,
  '42501', NULL, 'restaurant_owner(A1) cannot start a session on a sibling-restaurant A2 pairing (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c00e','00000000-0000-0000-0000-0000aaaa0009') $$,
  '42501', NULL, 'manager(A1a) cannot start a session on a sibling-branch A1b pairing (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select throws_ok($$ select app.start_device_session('00000000-0000-0000-0000-00000000c00f','00000000-0000-0000-0000-0000aaaa000b') $$,
  '42501', NULL, 'no session on a pairing whose branch is soft-deleted (42501)');

-- ===== posture: anon cannot execute the activation/session RPCs =====
reset role;
select is(has_function_privilege('anon', 'public.start_device_session(uuid,uuid)', 'EXECUTE'),
  false, 'anon cannot execute public.start_device_session');
select is(has_function_privilege('anon', 'public.activate_device(uuid,uuid)', 'EXECUTE'),
  false, 'anon cannot execute public.activate_device');

select * from finish();
rollback;
