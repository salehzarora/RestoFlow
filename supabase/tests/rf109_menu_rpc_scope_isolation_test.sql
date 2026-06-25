-- RF-109 Stage 2 -- menu RPC scope isolation (Codex blockers RF109-S2-B1 + RF109-S2-B2).
--
-- B1: org/restaurant/branch are IMMUTABLE on update -- a branch-A1a manager cannot update or
--     hijack a sibling-branch (A1b) row (neither by passing their own branch_id to "move" it,
--     nor by editing it in place), and cannot soft-delete it.
-- B2: parent references must be scope-compatible -- a branch-A1a child may reference a same-branch
--     parent OR a restaurant-scoped (branch_id null) parent, but NEVER a sibling-branch (A1b)
--     parent; a restaurant-scoped child (branch_id null) may reference only restaurant-scoped parents.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109scope-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e0', 'rf109scope-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e1', 'rf109scope-mgr-a1a@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f0', '00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'manager');

-- Branch A1b rows (the sibling branch the A1a manager must not touch / must not parent-reference)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', 'Cat B'),
  -- Branch A1a category + restaurant-scoped category for the "allowed" cases
  ('00000000-0000-0000-0000-00000000ca0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'Cat A1a'),
  ('00000000-0000-0000-0000-00000000cf01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   'Cat Rest');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-00000000db01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-00000000cb01', 'Item B', 1000, 'USD'),
  ('00000000-0000-0000-0000-00000000da0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000ca0a', 'Item A1a', 1100, 'USD');
insert into item_sizes (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000000005b01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-00000000db01', 'Size B', 0);
insert into item_variants (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000000006b01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-00000000db01', 'Var B', 0);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-000000007b01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-00000000db01', 'Mod B'),
  ('00000000-0000-0000-0000-000000007a0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000da0a', 'Mod A1a');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-000000007b01', 'Opt B', 0);
insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-000000005b1b', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', 'Station B');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- manager @ Branch A1a
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

-- ===== B1: branch-A1a manager cannot update/move/hijack sibling-branch (A1b) rows =====
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000cb01','Hijack',0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot MOVE a sibling-branch category to A1a (immutable scope)');
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b0','00000000-0000-0000-0000-00000000cb01','Hijack',0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot edit a sibling-branch category in place (no scope on A1b)');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000db01','00000000-0000-0000-0000-00000000ca0a','Hijack',null,100,'USD',null,0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot move/hijack a sibling-branch item');
select throws_ok(
  $$ select app.menu_upsert_size('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-000000005b01','00000000-0000-0000-0000-00000000da0a','Hijack',0,0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot move/hijack a sibling-branch size');
select throws_ok(
  $$ select app.menu_upsert_variant('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-000000006b01','00000000-0000-0000-0000-00000000da0a','Hijack',0,0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot move/hijack a sibling-branch variant');
select throws_ok(
  $$ select app.menu_upsert_modifier('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-000000007b01','00000000-0000-0000-0000-00000000da0a','Hijack','single',0,null,false,0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot move/hijack a sibling-branch modifier');
select throws_ok(
  $$ select app.menu_upsert_modifier_option('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-000000008b01','00000000-0000-0000-0000-000000007a0a','Hijack',0,0,true) $$,
  '42501', NULL, 'B1: A1a manager cannot move/hijack a sibling-branch modifier_option');
select throws_ok(
  $$ select app.menu_soft_delete('00000000-0000-0000-0000-0000000000a0','menu_item','00000000-0000-0000-0000-00000000db01') $$,
  '42501', NULL, 'B1: A1a manager cannot soft-delete a sibling-branch row (authorizes the existing row scope)');

-- ===== B2: branch-A1a child cannot reference sibling-branch (A1b) parents =====
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000cb01','X',null,100,'USD',null,0,true) $$,
  '42501', NULL, 'B2: A1a item cannot reference a sibling-branch (A1b) category');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000ca0a','X',null,100,'USD','00000000-0000-0000-0000-000000005b1b',0,true) $$,
  '42501', NULL, 'B2: A1a item cannot use a sibling-branch (A1b) default_station');
select throws_ok(
  $$ select app.menu_upsert_size('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000db01','X',0,0,true) $$,
  '42501', NULL, 'B2: A1a size cannot reference a sibling-branch (A1b) item');
select throws_ok(
  $$ select app.menu_upsert_variant('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000db01','X',0,0,true) $$,
  '42501', NULL, 'B2: A1a variant cannot reference a sibling-branch (A1b) item');
select throws_ok(
  $$ select app.menu_upsert_modifier('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000db01','X','single',0,null,false,0,true) $$,
  '42501', NULL, 'B2: A1a modifier cannot reference a sibling-branch (A1b) item');
select throws_ok(
  $$ select app.menu_upsert_modifier_option('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-000000007b01','X',0,0,true) $$,
  '42501', NULL, 'B2: A1a modifier_option cannot reference a sibling-branch (A1b) modifier');

-- ===== B2: allowed references (same branch, and restaurant-scoped parent reuse) =====
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000ca0a','OK Same',null,100,'USD',null,0,true) ->> 'ok')::boolean,
  true, 'B2: A1a item CAN reference a same-branch (A1a) category');
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000cf01','OK Rest',null,100,'USD',null,0,true) ->> 'ok')::boolean,
  true, 'B2: A1a item CAN reference a restaurant-scoped (branch null) category (intended reuse)');
select is(
  (app.menu_upsert_size('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0',null,'00000000-0000-0000-0000-00000000da0a','OK Size',0,0,true) ->> 'ok')::boolean,
  true, 'B2: A1a size CAN reference a same-branch (A1a) item');

-- ===== B2: restaurant-scoped child (branch null) -- org_owner; only restaurant-scoped parents =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e0';  -- org_owner
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,null,'00000000-0000-0000-0000-00000000cf01','RS OK',null,100,'USD',null,0,true) ->> 'ok')::boolean,
  true, 'B2: a restaurant-scoped item (branch null) CAN reference a restaurant-scoped category');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,null,'00000000-0000-0000-0000-00000000ca0a','RS Bad',null,100,'USD',null,0,true) $$,
  '42501', NULL, 'B2: a restaurant-scoped item (branch null) cannot reference a branch-scoped (A1a) category');

-- ===== B1: the sibling-branch row was never mutated by the denied attempts =====
reset role;
select is(
  (select name from menu_categories where id = '00000000-0000-0000-0000-00000000cb01'),
  'Cat B', 'B1: the sibling-branch (A1b) category is unchanged after the denied attempts');

select * from finish();
rollback;
