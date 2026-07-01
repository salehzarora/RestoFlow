-- RF-160 Phase B -- app.list_devices: role/rank matrix, downward-scope coverage, cross-tenant
-- isolation (RISK R-003), status reflection, and no-secret-leak. GUC-FREE (identity GUC only),
-- mirroring rf112_device_provisioning_test.sql.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(17);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00000016000a', 'Org A', 'rf160ld-a', 'USD'),
  ('00000000-0000-0000-0000-00000016000b', 'Org B', 'rf160ld-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-00000016000a', 'Rest A1'),
  ('00000000-0000-0000-0000-0000001600a2', '00000000-0000-0000-0000-00000016000a', 'Rest A2'),
  ('00000000-0000-0000-0000-0000001600b1', '00000000-0000-0000-0000-00000016000b', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000160a1a', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-000000160a1b', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-000000160a2a', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-000000160b1a', '00000000-0000-0000-0000-00000016000b', '00000000-0000-0000-0000-0000001600b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000001600e1', 'rf160ld-owner@example.test'),
  ('00000000-0000-0000-0000-0000001600e2', 'rf160ld-restowner@example.test'),
  ('00000000-0000-0000-0000-0000001600e3', 'rf160ld-manager@example.test'),
  ('00000000-0000-0000-0000-0000001600e4', 'rf160ld-cashier@example.test'),
  ('00000000-0000-0000-0000-0000001600e5', 'rf160ld-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000001600e6', 'rf160ld-acct@example.test'),
  ('00000000-0000-0000-0000-0000001600e8', 'rf160ld-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000001600f1', '00000000-0000-0000-0000-0000001600e1', '00000000-0000-0000-0000-00000016000a', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000001600f2', '00000000-0000-0000-0000-0000001600e2', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000001600f3', '00000000-0000-0000-0000-0000001600e3', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a', 'manager'),
  ('00000000-0000-0000-0000-0000001600f4', '00000000-0000-0000-0000-0000001600e4', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a', 'cashier'),
  ('00000000-0000-0000-0000-0000001600f5', '00000000-0000-0000-0000-0000001600e5', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000001600f6', '00000000-0000-0000-0000-0000001600e6', '00000000-0000-0000-0000-00000016000a', null, null, 'accountant');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000016d0001', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a', 'pos', 'Front POS'),
  ('00000000-0000-0000-0000-0000016d0002', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a', 'kds', 'Kitchen KDS'),
  ('00000000-0000-0000-0000-0000016d0003', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1b', 'pos', 'Sibling POS'),
  ('00000000-0000-0000-0000-0000016d0004', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a2', '00000000-0000-0000-0000-000000160a2a', 'pos', 'RestA2 POS'),
  ('00000000-0000-0000-0000-0000016d0005', '00000000-0000-0000-0000-00000016000b', '00000000-0000-0000-0000-0000001600b1', '00000000-0000-0000-0000-000000160b1a', 'pos', 'OrgB POS');
-- dv1 carries a live 'paired' pairing; dv2..dv5 have none (status 'none').
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at) values
  ('00000000-0000-0000-0000-000001690001', '00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a', '00000000-0000-0000-0000-0000016d0001', 'paired', now());

set local role authenticated;

-- ===== success + scope coverage (no org GUC is ever set -> GUC-free) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e1';  -- org_owner (org-wide)
select is(
  (app.list_devices('00000000-0000-0000-0000-00000016000a', null, null) ->> 'ok'),
  'true', 'org_owner lists devices org-wide (ok:true)');
select is(
  jsonb_array_length(app.list_devices('00000000-0000-0000-0000-00000016000a', null, null) -> 'devices'),
  4, 'org_owner sees all 4 Org A devices (Org B excluded)');
select is(
  jsonb_array_length(app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a2', null) -> 'devices'),
  1, 'org_owner scoped to Rest A2 sees only that restaurant''s 1 device (scope filter)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e2';  -- restaurant_owner @ A1
select is(
  jsonb_array_length(app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', null) -> 'devices'),
  3, 'restaurant_owner(A1) sees its 3 devices (A1a x2 + A1b), not Rest A2');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e3';  -- manager @ A1a
select is(
  jsonb_array_length(app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a') -> 'devices'),
  2, 'manager(A1a) sees exactly the 2 devices in its own branch');

-- status reflection (latest live pairing) --
select is(
  (select e ->> 'status' from jsonb_array_elements(
     app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a') -> 'devices') e
   where e ->> 'device_id' = '00000000-0000-0000-0000-0000016d0001'),
  'paired', 'a device with a live paired pairing reports status=paired');
select is(
  (select e ->> 'status' from jsonb_array_elements(
     app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a') -> 'devices') e
   where e ->> 'device_id' = '00000000-0000-0000-0000-0000016d0002'),
  'none', 'a device with no pairing reports status=none');
select is(
  (select e ->> 'branch_label' from jsonb_array_elements(
     app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a') -> 'devices') e
   where e ->> 'device_id' = '00000000-0000-0000-0000-0000016d0001'),
  'Branch A1a', 'each device carries its human branch_label');

-- ===== rank denial (in-scope member, rank < manager -> permission_denied) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e4';  -- cashier @ A1a
select is(
  (app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a') ->> 'error'),
  'permission_denied', 'cashier cannot list devices (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e5';  -- kitchen_staff @ A1a
select is(
  (app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1a') ->> 'error'),
  'permission_denied', 'kitchen_staff cannot list devices (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e6';  -- accountant (org-wide, rank 1)
select is(
  (app.list_devices('00000000-0000-0000-0000-00000016000a', null, null) ->> 'error'),
  'permission_denied', 'accountant (read-only) cannot list devices (permission_denied)');

-- ===== structural / isolation denials (no covering membership -> 42501) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e8';  -- nobody
select throws_ok(
  $$ select app.list_devices('00000000-0000-0000-0000-00000016000a', null, null) $$,
  '42501', NULL, 'non-member cannot list devices (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e1';  -- org_owner @ Org A
select throws_ok(
  $$ select app.list_devices('00000000-0000-0000-0000-00000016000b', null, null) $$,
  '42501', NULL, 'org_owner(A) cannot list Org B devices (cross-org; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e3';  -- manager @ A1a
select throws_ok(
  $$ select app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', null) $$,
  '42501', NULL, 'branch manager cannot widen to restaurant-level listing (42501)');
select throws_ok(
  $$ select app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a1', '00000000-0000-0000-0000-000000160a1b') $$,
  '42501', NULL, 'manager(A1a) cannot list a sibling branch A1b (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e2';  -- restaurant_owner @ A1
select throws_ok(
  $$ select app.list_devices('00000000-0000-0000-0000-00000016000a', '00000000-0000-0000-0000-0000001600a2', null) $$,
  '42501', NULL, 'restaurant_owner(A1) cannot list sibling restaurant A2 (42501)');

-- ===== no-secret-leak: the result NEVER carries a hash/token ref =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000001600e1';
select ok(
  (app.list_devices('00000000-0000-0000-0000-00000016000a', null, null))::text not like '%hash%'
  and (app.list_devices('00000000-0000-0000-0000-00000016000a', null, null))::text not like '%token%',
  'list_devices never returns an enrollment/session secret ref');

select * from finish();
rollback;
