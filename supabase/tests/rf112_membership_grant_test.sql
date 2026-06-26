-- RF-112 Stage 1 -- grant_membership role matrix + tenant isolation (D-033 / §4.26 / T-015).
-- org_owner/restaurant_owner/manager grant LOWER roles within scope; cashier/kitchen_staff/
-- accountant are role-denied (permission_denied + committed denial audit); non-member / cross-org /
-- cross-restaurant / sibling-branch / bad-scope raise 42501. GUC-FREE: only app.current_app_user_id
-- is ever set (app.current_organization_id is NEVER set), proving the RPC does not need the org GUC.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112mg-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112mg-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
-- actors
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112mg-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf112mg-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112mg-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112mg-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf112mg-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf112mg-acct@example.test');
-- grant targets (existing app_users with no membership yet)
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'rf112mg-t1@example.test'),
  ('00000000-0000-0000-0000-0000000000d2', 'rf112mg-t2@example.test'),
  ('00000000-0000-0000-0000-0000000000d3', 'rf112mg-t3@example.test'),
  ('00000000-0000-0000-0000-0000000000d4', 'rf112mg-t4@example.test'),
  ('00000000-0000-0000-0000-0000000000d5', 'rf112mg-t5@example.test'),
  ('00000000-0000-0000-0000-0000000000d6', 'rf112mg-t6@example.test');
-- an INACTIVE app_user (a valid grant target must be active)
insert into app_users (id, email, is_active) values
  ('00000000-0000-0000-0000-0000000000df', 'rf112mg-inactive@example.test', false);
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant');

set local role authenticated;

-- ===== successes (no org GUC is EVER set below — GUC-free) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','cashier') ->> 'ok'),
  'true', 'org_owner grants a cashier in a branch (GUC-free)');
-- a SECOND grant of the same (target, exact scope) with a NEW request id is rejected (no duplicate)
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c0d0','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','cashier') $$,
  '42501', NULL, 'a second active membership at the same (target, scope) is rejected (42501; use update_role)');
-- granting a membership to an INACTIVE app_user is rejected
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c0d1','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000df','cashier') $$,
  '42501', NULL, 'granting a membership to an inactive app_user is rejected (42501)');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-0000000000d2','restaurant_owner') ->> 'ok'),
  'true', 'org_owner grants a restaurant_owner in a restaurant');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-0000000000d3','manager') ->> 'ok'),
  'true', 'restaurant_owner grants a manager in its restaurant');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d4','cashier') ->> 'ok'),
  'true', 'restaurant_owner grants a cashier in a branch of its restaurant');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d5','kitchen_staff') ->> 'ok'),
  'true', 'manager grants a kitchen_staff in its own branch');

-- ===== role-denied (permission_denied + denial audit) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d6','cashier') ->> 'error'),
  'permission_denied', 'cashier cannot manage memberships (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e5';  -- kitchen_staff
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d6','cashier') ->> 'error'),
  'permission_denied', 'kitchen_staff cannot manage memberships (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';  -- accountant (read-only, D-028)
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000000000a0',null,null,'00000000-0000-0000-0000-0000000000d6','cashier') ->> 'error'),
  'permission_denied', 'accountant cannot manage memberships (permission_denied; D-028)');

-- ===== structural 42501: cross-org / cross-restaurant / sibling-branch / bad scope / bad target / bad role =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner @ Org A
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000b1a00','00000000-0000-0000-0000-0000000000d6','cashier') $$,
  '42501', NULL, 'org_owner of Org A cannot grant into Org B (cross-org IDOR; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2',null,'00000000-0000-0000-0000-0000000000d6','cashier') $$,
  '42501', NULL, 'restaurant_owner(A1) cannot grant into sibling restaurant A2 (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c00b','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1b00','00000000-0000-0000-0000-0000000000d6','cashier') $$,
  '42501', NULL, 'manager(A1a) cannot grant into sibling branch A1b (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c00c','00000000-0000-0000-0000-0000000000a0',null,'00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d6','cashier') $$,
  '42501', NULL, 'branch requires restaurant (42501)');
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c00d','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000dead','cashier') $$,
  '42501', NULL, 'target app_user must already exist (no invite/pending; 42501)');
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c00e','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d6','platform_admin') $$,
  '42501', NULL, 'platform_admin is not an assignable tenant role (42501; D-026)');

-- ===== public wrapper exercises the Data-API surface =====
select is(
  (public.grant_membership('00000000-0000-0000-0000-00000000c00f','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d6','cashier') ->> 'ok'),
  'true', 'public.grant_membership wrapper works (org_owner grants cashier)');

-- ===== DB-state + audit verification (as the BYPASSRLS owner) =====
reset role;
select is(
  (select role from memberships where app_user_id = '00000000-0000-0000-0000-0000000000d1'
     and organization_id = '00000000-0000-0000-0000-0000000000a0' and deleted_at is null),
  'cashier', 'the granted membership row was actually created (t1 = cashier)');
select is(
  (select count(*) from audit_events where action = 'membership.granted'
     and (new_values ->> 'app_user_id') = '00000000-0000-0000-0000-0000000000d1')::int,
  1, 'a membership.granted audit row was written for the successful grant');
select is(
  (select count(*) from audit_events where action = 'membership.grant_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-0000000000e4')::int,
  1, 'the cashier role-denial wrote one membership.grant_denied audit row');

select * from finish();
rollback;
