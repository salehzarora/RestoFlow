-- RF-109 Stage 2 -- menu RPC validation, scope/FK, soft-delete, audit (D-031 §4.23 / D-007 / D-008 / D-020).
-- Money: integer-minor; base_price >= 0; signed child delta; bad currency rejected.
-- Scope/FK: cross-org parent/station rejected; branch-outside-restaurant rejected; branch null ok.
-- Soft delete: sets deleted_at, bumps updated_at, preserves row, no cascade to children,
--   tombstone visible to permitted readers. Audit: success + soft-delete rows, tenant-scoped.
-- All write/read ops run as an Org A org_owner (a write + read role).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(19);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109rpc-va-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf109rpc-va-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf109va-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'Station A1'),
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'Station B1');
-- Cat A is RESTAURANT-scoped (branch_id null) so branch-A1a items AND the restaurant-scoped
-- item below can both reference it under the B2 scope-compatibility rule.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Cat A'),
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'Cat B');
-- IA: seeded with an OLD updated_at so the soft-delete trigger bump is observable in-txn.
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, updated_at) values
  ('00000000-0000-0000-0000-00000000da01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000ca01', 'Item A', 1500, 'USD', '2020-01-01T00:00:00Z'),
  ('00000000-0000-0000-0000-00000000db01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000cb01', 'Item B', 2000, 'EUR', now());
insert into item_sizes (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-0000000005c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000da01', 'Small', -100);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-00000000eb01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000db01', 'Mod B');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

-- ===== money validation (4) =====
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000d101','00000000-0000-0000-0000-00000000ca01','Valid',null,900,'USD',null,0,true) ->> 'ok')::boolean,
  true, 'valid base_price_minor (>=0) accepted');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'00000000-0000-0000-0000-00000000ca01','Neg',null,-1,'USD',null,0,true) $$,
  '42501', NULL, 'negative base_price_minor rejected (42501)');
select is(
  (app.menu_upsert_size('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-000000005101','00000000-0000-0000-0000-00000000da01','Mini',-500,0,true) ->> 'ok')::boolean,
  true, 'signed NEGATIVE price_delta_minor accepted on a child');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'00000000-0000-0000-0000-00000000ca01','BadCur',null,100,'usd',null,0,true) $$,
  '42501', NULL, 'invalid currency_code rejected (42501)');

-- ===== scope / FK validation (6) =====
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'00000000-0000-0000-0000-00000000cb01','X',null,100,'USD',null,0,true) $$,
  '42501', NULL, 'item cannot attach to a category from another organization');
select throws_ok(
  $$ select app.menu_upsert_size('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'00000000-0000-0000-0000-00000000db01','X',0,0,true) $$,
  '42501', NULL, 'size cannot attach to an item from another organization');
select throws_ok(
  $$ select app.menu_upsert_modifier_option('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'00000000-0000-0000-0000-00000000eb01','X',0,0,true) $$,
  '42501', NULL, 'modifier_option cannot attach to a modifier from another organization');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00',null,'00000000-0000-0000-0000-00000000ca01','X',null,100,'USD','00000000-0000-0000-0000-0000000005b1',0,true) $$,
  '42501', NULL, 'default_station_id from another organization rejected');
select throws_ok(
  $$ select app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a2a00',null,'00000000-0000-0000-0000-00000000ca01','X',null,100,'USD',null,0,true) $$,
  '23503', NULL, 'branch outside the restaurant rejected by the composite branch FK');
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-00000000d201','00000000-0000-0000-0000-00000000ca01','RestScoped',null,100,'USD',null,0,true) ->> 'ok')::boolean,
  true, 'restaurant-scoped (branch_id null) item upsert works');

-- ===== soft delete behavior (6) =====
select is(
  (app.menu_soft_delete('00000000-0000-0000-0000-0000000000a0','menu_item','00000000-0000-0000-0000-00000000da01') ->> 'action'),
  'soft_deleted', 'menu_soft_delete returns soft_deleted');
select is(
  (select deleted_at is not null from menu_items where id = '00000000-0000-0000-0000-00000000da01'),
  true, 'soft delete sets deleted_at');
select ok(
  (select updated_at from menu_items where id = '00000000-0000-0000-0000-00000000da01') > '2021-01-01T00:00:00Z',
  'soft delete bumps updated_at (set_updated_at trigger)');
select is(
  (select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01')::int,
  1, 'soft delete preserves the row (not physically deleted)');
select is(
  (select deleted_at is null from item_sizes where id = '00000000-0000-0000-0000-0000000005c1'),
  true, 'soft delete does NOT cascade to child rows (order-snapshot independence; single-table tombstone)');
select is(
  (select count(*) from menu_items where id = '00000000-0000-0000-0000-00000000da01' and deleted_at is not null)::int,
  1, 'a permitted reader still SEES the tombstoned row (D-020; deleted_at not filtered)');

-- ===== audit (3) =====
select ok(
  (select count(*) from audit_events where action = 'menu.menu_item.created') >= 1,
  'a successful create writes a menu.menu_item.created audit row');
select is(
  (select count(*) from audit_events where action = 'menu.menu_item.deleted'
     and (new_values ->> 'id') = '00000000-0000-0000-0000-00000000da01')::int,
  1, 'the soft delete writes a menu.menu_item.deleted audit row');
select is(
  (select organization_id from audit_events where action = 'menu.menu_item.deleted'
     and (new_values ->> 'id') = '00000000-0000-0000-0000-00000000da01'),
  '00000000-0000-0000-0000-0000000000a0'::uuid, 'the soft-delete audit is tenant-scoped to Org A');

reset role;
select * from finish();
rollback;
