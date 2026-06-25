-- RF-109 Stage 2 -- menu RPC role matrix (D-031 §4.23 / D-026 / D-028 / T-013).
-- Write roles org_owner/restaurant_owner/manager can create/update/soft-delete in scope;
-- cashier/kitchen_staff/accountant are role-denied (permission_denied + committed denial audit);
-- platform-admin-only and non-member raise 42501; cross-org IDOR (by id) raises 42501.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109rpc-rm-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf109rpc-rm-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf109rm-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf109rm-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf109rm-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf109rm-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf109rm-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf109rm-acct@example.test'),
  ('00000000-0000-0000-0000-0000000000e7', 'rf109rm-platadmin@example.test'),
  ('00000000-0000-0000-0000-0000000000e8', 'rf109rm-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant');
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e7');
-- seed: a category + item (Org A) and a category (Org B, IDOR target)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'Cat A'),
  ('00000000-0000-0000-0000-00000000c0b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'Cat B');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-00000000d0a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000c0a1', 'Item A', 1500, 'USD');

set local role authenticated;

-- ===== org_owner: create / update / soft-delete =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000c011','Specials',0,true) ->> 'action'),
  'created', 'org_owner can create a category');
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000c0a1','Cat A renamed',0,true) ->> 'action'),
  'updated', 'org_owner can update a category (upsert by id)');
select is(
  (app.menu_soft_delete('00000000-0000-0000-0000-0000000000a0','menu_category','00000000-0000-0000-0000-00000000c011') ->> 'action'),
  'soft_deleted', 'org_owner can soft-delete a category');

-- ===== restaurant_owner: create + soft-delete in scope =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000d011','00000000-0000-0000-0000-00000000c0a1','Tea',null,800,'USD',null,0,true) ->> 'action'),
  'created', 'restaurant_owner can create an item in scope');
select is(
  (app.menu_soft_delete('00000000-0000-0000-0000-0000000000a0','menu_item','00000000-0000-0000-0000-00000000d011') ->> 'action'),
  'soft_deleted', 'restaurant_owner can soft-delete an item in scope');

-- ===== manager: create + soft-delete in scope =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';
select is(
  (app.menu_upsert_size('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-000000005031','00000000-0000-0000-0000-00000000d0a1','Large',300,0,true) ->> 'action'),
  'created', 'manager can create a size in scope');
select is(
  (app.menu_soft_delete('00000000-0000-0000-0000-0000000000a0','item_size','00000000-0000-0000-0000-000000005031') ->> 'action'),
  'soft_deleted', 'manager can soft-delete a size in scope');

-- ===== cashier / kitchen_staff / accountant: role-denied (permission_denied) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'Cashier Cat',0,true) ->> 'error'),
  'permission_denied', 'cashier is role-denied (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e5';
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'Kitchen Cat',0,true) ->> 'error'),
  'permission_denied', 'kitchen_staff is role-denied (permission_denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,null,'Acct Cat',0,true) ->> 'error'),
  'permission_denied', 'accountant is role-denied (permission_denied)');

-- ===== platform-admin-only and non-member: structural 42501 =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'PA Cat',0,true) $$,
  '42501', NULL, 'platform-admin-only principal cannot write menu (no tenant membership; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e8';
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'Nobody Cat',0,true) $$,
  '42501', NULL, 'non-member principal cannot write menu (42501)');

-- ===== cross-org IDOR: Org A org_owner cannot touch an Org B row by id =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000c0b1','Hijack',0,true) $$,
  '42501', NULL, 'cross-org IDOR: cannot upsert an Org B category id under Org A (42501)');

-- ===== same-org scope isolation: cannot write outside the caller's restaurant/branch =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ Rest A1
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2',null,null,'CrossRest',0,true) $$,
  '42501', NULL, 'restaurant_owner(A1) cannot write to a sibling restaurant A2 (same org; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ Branch A1a
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1b00',null,'CrossBranch',0,true) $$,
  '42501', NULL, 'manager(branch A1a) cannot write to a sibling branch A1b (same org; 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is(
  (app.menu_soft_delete('00000000-0000-0000-0000-0000000000a0','menu_item','00000000-0000-0000-0000-00000000d0a1') ->> 'error'),
  'permission_denied', 'cashier soft-delete is role-denied (delete_denied path returns permission_denied)');

-- ===== denial audit (read as BYPASSRLS connection) =====
reset role;
select is(
  (select count(*) from audit_events where action = 'menu.menu_category.upsert_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-0000000000e4')::int,
  1, 'the cashier role-denial wrote one menu.menu_category.upsert_denied audit row (actor = cashier)');
select is(
  (select organization_id from audit_events where action = 'menu.menu_category.upsert_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-0000000000e4'),
  '00000000-0000-0000-0000-0000000000a0'::uuid, 'the denial audit is tenant-scoped to the caller org (no cross-tenant leak)');

select * from finish();
rollback;
