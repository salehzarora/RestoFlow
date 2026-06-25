-- RF-109 Stage 1 -- menu RLS / tenant isolation (DECISION D-031; SECURITY T-013/T-003; D-026).
-- Proves: non-member sees zero; cross-org read blocked (+IDOR); branch-scoped member cannot
-- see sibling-branch rows; the five price-capable roles CAN read; kitchen_staff CANNOT read
-- any menu row on the direct-table path (T-003); direct INSERT/UPDATE/DELETE are denied (42501);
-- a platform-admin-only principal cannot bypass tenant RLS (D-026); deleted_at tombstones stay
-- visible to permitted readers (D-020, sync needs them later).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(27);

-- ===== fixtures (seeded as the BYPASSRLS connection) =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109rls-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf109rls-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf109-owner-a@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf109-mgr-a1a@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf109-cashier-a@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf109-kitchen-a@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf109-acct-a@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf109-cashier-b@example.test'),
  ('00000000-0000-0000-0000-0000000000e7', 'rf109-platadmin@example.test'),
  ('00000000-0000-0000-0000-0000000000e8', 'rf109-nobody@example.test');

insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'cashier');

-- platform-admin-only principal (NO tenant membership) -- D-026
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e7');

-- menu rows. Org A: branch A1a (full hierarchy), branch A1b (item), restaurant-scoped (item),
-- a soft-deleted item (branch A1a). Org B: a category + item.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'Cat A1a'),
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'Cat B1a');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, deleted_at) values
  ('00000000-0000-0000-0000-00000000da01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000ca01', 'Item A1a', 1500, 'USD', null),
  ('00000000-0000-0000-0000-00000000db01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000ca01', 'Item A1b', 1600, 'USD', null),
  ('00000000-0000-0000-0000-00000000dab1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   '00000000-0000-0000-0000-00000000ca01', 'Item Rest', 1700, 'USD', null),
  ('00000000-0000-0000-0000-00000000dde1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000ca01', 'Item Deleted', 1800, 'USD', now()),
  ('00000000-0000-0000-0000-00000000d0b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000cb01', 'Item B1a', 2000, 'EUR', null);
insert into item_sizes (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000000005a01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000da01', 'Large', 300);
insert into item_variants (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000000006a01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000da01', 'Spicy', 0);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-000000007a01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000da01', 'Toppings');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000000008a01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-000000007a01', 'Cheese', 250);

set local role authenticated;

-- ===== no-membership principal: deny-by-default (2) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e8';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_categories)::int, 0, 'no-membership principal sees zero menu_categories');
select is((select count(*) from menu_items)::int,      0, 'no-membership principal sees zero menu_items');

-- ===== Org B cashier: own-org visible, Org A invisible, IDOR blocked (3) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e6';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select ok((select count(*) from menu_items) >= 1, 'Org B cashier CAN read own-org menu_items (control)');
select is((select count(*) from menu_items where organization_id = '00000000-0000-0000-0000-0000000000a0')::int, 0, 'Org B cashier sees ZERO Org A menu_items (cross-org)');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01')::int, 0, 'Org B cashier cannot read an Org A item by id (IDOR blocked)');

-- ===== Org A cashier (branch A1a): own-branch + restaurant-scoped + tombstone visible; cross-org blocked (4) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01')::int, 1, 'Org A cashier CAN read own-branch item (control)');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000dab1')::int, 1, 'Org A cashier CAN read a restaurant-scoped (branch_id null) item');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000d0b1')::int, 0, 'Org A cashier sees ZERO Org B items (cross-org)');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000dde1')::int, 1, 'soft-deleted (tombstoned) menu_item stays VISIBLE to a permitted reader (D-020)');

-- ===== branch-scoped manager (A1a): sibling-branch isolation (3) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01')::int, 1, 'branch A1a manager CAN read own-branch item');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000db01')::int, 0, 'branch A1a manager CANNOT read a sibling-branch (A1b) item');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000dab1')::int, 1, 'branch A1a manager CAN read a restaurant-scoped (branch_id null) item');

-- ===== org_owner (org-wide) sees all branches (2) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01')::int, 1, 'org_owner CAN read branch A1a item');
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000db01')::int, 1, 'org_owner CAN read branch A1b item (org-wide scope)');

-- ===== accountant is a price-capable reader (1) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e5';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01')::int, 1, 'accountant CAN read menu (price-capable role)');

-- ===== kitchen_staff: ZERO menu rows on every menu table (T-003) (6) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_categories)::int,  0, 'kitchen_staff: ZERO menu_categories (T-003)');
select is((select count(*) from menu_items)::int,       0, 'kitchen_staff: ZERO menu_items (T-003)');
select is((select count(*) from item_sizes)::int,       0, 'kitchen_staff: ZERO item_sizes (T-003)');
select is((select count(*) from item_variants)::int,    0, 'kitchen_staff: ZERO item_variants (T-003)');
select is((select count(*) from modifiers)::int,        0, 'kitchen_staff: ZERO modifiers (T-003)');
select is((select count(*) from modifier_options)::int, 0, 'kitchen_staff: ZERO modifier_options (T-003)');

-- ===== platform-admin-only principal cannot bypass tenant RLS (D-026) (2) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from menu_items)::int,      0, 'platform-admin-only principal sees ZERO menu_items (not a tenant RLS bypass, D-026)');
select is((select count(*) from menu_categories)::int, 0, 'platform-admin-only principal sees ZERO menu_categories (D-026)');

-- ===== direct INSERT/UPDATE/DELETE denied (revoked) (4) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- cashier A
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000ca01','Rogue',100,'USD') $$,
  '42501', NULL, 'cashier direct INSERT on menu_items is denied (privilege revoked)');
select throws_ok(
  $$ update menu_items set name = 'hacked' where id = '00000000-0000-0000-0000-00000000da01' $$,
  '42501', NULL, 'cashier direct UPDATE on menu_items is denied (privilege revoked)');
select throws_ok(
  $$ delete from menu_items where id = '00000000-0000-0000-0000-00000000da01' $$,
  '42501', NULL, 'cashier direct DELETE on menu_items is denied (privilege revoked)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner (highest tenant role)
select throws_ok(
  $$ insert into menu_categories (organization_id, restaurant_id, branch_id, name)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','Rogue Cat') $$,
  '42501', NULL, 'even org_owner cannot direct-INSERT menu rows (writes go through RPC, later stage)');

reset role;
select * from finish();
rollback;
