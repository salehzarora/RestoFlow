-- RF-112 Stage 1 -- settings RPCs over the EXISTING columns only (D-033 / §4.25 / T-015).
-- org_owner/restaurant_owner edit settings within scope; manager/cashier/kitchen_staff/accountant
-- are denied; cross-org/cross-restaurant and out-of-scope raise 42501; invalid currency/status/
-- timezone/name raise 42501; the slice excludes tax/locale/hours/template. GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112set-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112set-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112set-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf112set-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112set-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112set-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf112set-acct@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant');

set local role authenticated;

-- ===== authorized edits =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select is(
  (app.update_organization_settings('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','cad','CA','active') ->> 'ok'),
  'true', 'org_owner updates organization settings');
select is(
  (app.update_branch_settings('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','Main Branch','1 King St','Asia/Jerusalem','A1-','active') ->> 'ok'),
  'true', 'org_owner updates branch settings');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select is(
  (app.update_restaurant_settings('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','Rest A1 Renamed',null,'Asia/Jerusalem','active') ->> 'ok'),
  'true', 'restaurant_owner updates its restaurant settings');
select is(
  (app.update_branch_settings('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,null,null,'A1B-',null) ->> 'ok'),
  'true', 'restaurant_owner updates a branch of its restaurant');

-- ===== role-denied (permission_denied): manager / cashier / accountant cannot edit settings =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager (rank 2 < restaurant_owner)
select is(
  (app.update_branch_settings('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','X',null,null,null,null) ->> 'error'),
  'permission_denied', 'manager cannot edit branch settings (rank < restaurant_owner; permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is(
  (app.update_branch_settings('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','X',null,null,null,null) ->> 'error'),
  'permission_denied', 'cashier cannot edit branch settings (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';  -- accountant (org-wide, read-only)
select is(
  (app.update_organization_settings('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000000000a0',null,null,'suspended') ->> 'error'),
  'permission_denied', 'accountant cannot edit organization settings (read-only; permission_denied)');

-- ===== out-of-scope / cross-tenant: 42501 =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select throws_ok(
  $$ select app.update_organization_settings('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000000000a0',null,null,'suspended') $$,
  '42501', NULL, 'restaurant_owner cannot reach org-wide settings (downward-only; 42501)');
select throws_ok(
  $$ select app.update_restaurant_settings('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2','Hijack',null,null,null) $$,
  '42501', NULL, 'restaurant_owner(A1) cannot edit sibling restaurant A2 settings (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner @ Org A
select throws_ok(
  $$ select app.update_organization_settings('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000000000b0',null,null,'suspended') $$,
  '42501', NULL, 'org_owner of Org A cannot edit Org B settings (cross-org; 42501)');

-- ===== validation: bad currency / status / timezone / blank name -> 42501 =====
select throws_ok(
  $$ select app.update_organization_settings('00000000-0000-0000-0000-00000000c00b','00000000-0000-0000-0000-0000000000a0','us',null,null) $$,
  '42501', NULL, 'invalid currency code is rejected (42501)');
select throws_ok(
  $$ select app.update_organization_settings('00000000-0000-0000-0000-00000000c00c','00000000-0000-0000-0000-0000000000a0',null,null,'paused') $$,
  '42501', NULL, 'invalid status value is rejected (42501)');
select throws_ok(
  $$ select app.update_restaurant_settings('00000000-0000-0000-0000-00000000c00d','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,null,'Mars/Phobos',null) $$,
  '42501', NULL, 'invalid IANA timezone is rejected (42501)');
select throws_ok(
  $$ select app.update_restaurant_settings('00000000-0000-0000-0000-00000000c00e','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','   ',null,null,null) $$,
  '42501', NULL, 'a blank restaurant name is rejected (42501)');

-- ===== public wrapper =====
select is(
  (public.update_branch_settings('00000000-0000-0000-0000-00000000c00f','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,null,null,null,'suspended') ->> 'ok'),
  'true', 'public.update_branch_settings wrapper works (org_owner)');

-- ===== DB-state + audit + slice (as the BYPASSRLS owner) =====
reset role;
select is(
  (select default_currency from organizations where id = '00000000-0000-0000-0000-0000000000a0'),
  'CAD', 'the org settings update actually changed default_currency (cad -> CAD)');
select is(
  (select count(*) from audit_events where action = 'settings.organization.updated'
     and organization_id = '00000000-0000-0000-0000-0000000000a0')::int,
  1, 'a settings.organization.updated audit row was written');
select is(
  (select count(*) from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'update_branch_settings'
     and coalesce(array_to_string(p.proargnames, ','), '') ~* '(tax|locale|hours|template|logo|header|footer)')::int,
  0, 'branch settings RPC exposes NO tax/locale/hours/template parameters (slice only)');

select * from finish();
rollback;
