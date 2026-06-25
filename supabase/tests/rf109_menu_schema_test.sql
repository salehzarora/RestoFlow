-- RF-109 Stage 1 -- menu schema + constraints (DECISION D-031; DOMAIN_MODEL section 4).
-- Asserts: six tables + columns; tenant columns; timestamps + tombstone; display_order/
-- is_active; integer-minor money types; negative price_delta accepted; negative base_price
-- and bad currency rejected; NO float/numeric/decimal/money type on any menu column;
-- NO FK from order snapshot tables to the live menu (D-008).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(82);

-- ---- existence + shared columns (11 asserts x 6 tables = 66) ----
select has_table('public', 'menu_categories',  'menu_categories table exists');
select has_table('public', 'menu_items',       'menu_items table exists');
select has_table('public', 'item_sizes',       'item_sizes table exists');
select has_table('public', 'item_variants',    'item_variants table exists');
select has_table('public', 'modifiers',        'modifiers table exists');
select has_table('public', 'modifier_options', 'modifier_options table exists');

select col_is_pk('public', 'menu_categories',  'id', 'menu_categories.id is pk');
select col_is_pk('public', 'menu_items',       'id', 'menu_items.id is pk');
select col_is_pk('public', 'item_sizes',       'id', 'item_sizes.id is pk');
select col_is_pk('public', 'item_variants',    'id', 'item_variants.id is pk');
select col_is_pk('public', 'modifiers',        'id', 'modifiers.id is pk');
select col_is_pk('public', 'modifier_options', 'id', 'modifier_options.id is pk');

select col_type_is('public', 'menu_categories',  'id', 'uuid', 'menu_categories.id is uuid');
select col_type_is('public', 'menu_items',       'id', 'uuid', 'menu_items.id is uuid');
select col_type_is('public', 'item_sizes',       'id', 'uuid', 'item_sizes.id is uuid');
select col_type_is('public', 'item_variants',    'id', 'uuid', 'item_variants.id is uuid');
select col_type_is('public', 'modifiers',        'id', 'uuid', 'modifiers.id is uuid');
select col_type_is('public', 'modifier_options', 'id', 'uuid', 'modifier_options.id is uuid');

select col_not_null('public', 'menu_categories',  'organization_id', 'menu_categories.organization_id NOT NULL');
select col_not_null('public', 'menu_items',       'organization_id', 'menu_items.organization_id NOT NULL');
select col_not_null('public', 'item_sizes',       'organization_id', 'item_sizes.organization_id NOT NULL');
select col_not_null('public', 'item_variants',    'organization_id', 'item_variants.organization_id NOT NULL');
select col_not_null('public', 'modifiers',        'organization_id', 'modifiers.organization_id NOT NULL');
select col_not_null('public', 'modifier_options', 'organization_id', 'modifier_options.organization_id NOT NULL');

select col_not_null('public', 'menu_categories',  'restaurant_id', 'menu_categories.restaurant_id NOT NULL');
select col_not_null('public', 'menu_items',       'restaurant_id', 'menu_items.restaurant_id NOT NULL');
select col_not_null('public', 'item_sizes',       'restaurant_id', 'item_sizes.restaurant_id NOT NULL');
select col_not_null('public', 'item_variants',    'restaurant_id', 'item_variants.restaurant_id NOT NULL');
select col_not_null('public', 'modifiers',        'restaurant_id', 'modifiers.restaurant_id NOT NULL');
select col_not_null('public', 'modifier_options', 'restaurant_id', 'modifier_options.restaurant_id NOT NULL');

select col_is_null('public', 'menu_categories',  'branch_id', 'menu_categories.branch_id is nullable');
select col_is_null('public', 'menu_items',       'branch_id', 'menu_items.branch_id is nullable');
select col_is_null('public', 'item_sizes',       'branch_id', 'item_sizes.branch_id is nullable');
select col_is_null('public', 'item_variants',    'branch_id', 'item_variants.branch_id is nullable');
select col_is_null('public', 'modifiers',        'branch_id', 'modifiers.branch_id is nullable');
select col_is_null('public', 'modifier_options', 'branch_id', 'modifier_options.branch_id is nullable');

select col_not_null('public', 'menu_categories',  'display_order', 'menu_categories.display_order NOT NULL');
select col_not_null('public', 'menu_items',       'display_order', 'menu_items.display_order NOT NULL');
select col_not_null('public', 'item_sizes',       'display_order', 'item_sizes.display_order NOT NULL');
select col_not_null('public', 'item_variants',    'display_order', 'item_variants.display_order NOT NULL');
select col_not_null('public', 'modifiers',        'display_order', 'modifiers.display_order NOT NULL');
select col_not_null('public', 'modifier_options', 'display_order', 'modifier_options.display_order NOT NULL');

select col_not_null('public', 'menu_categories',  'is_active', 'menu_categories.is_active NOT NULL');
select col_not_null('public', 'menu_items',       'is_active', 'menu_items.is_active NOT NULL');
select col_not_null('public', 'item_sizes',       'is_active', 'item_sizes.is_active NOT NULL');
select col_not_null('public', 'item_variants',    'is_active', 'item_variants.is_active NOT NULL');
select col_not_null('public', 'modifiers',        'is_active', 'modifiers.is_active NOT NULL');
select col_not_null('public', 'modifier_options', 'is_active', 'modifier_options.is_active NOT NULL');

select col_not_null('public', 'menu_categories',  'created_at', 'menu_categories.created_at NOT NULL');
select col_not_null('public', 'menu_items',       'created_at', 'menu_items.created_at NOT NULL');
select col_not_null('public', 'item_sizes',       'created_at', 'item_sizes.created_at NOT NULL');
select col_not_null('public', 'item_variants',    'created_at', 'item_variants.created_at NOT NULL');
select col_not_null('public', 'modifiers',        'created_at', 'modifiers.created_at NOT NULL');
select col_not_null('public', 'modifier_options', 'created_at', 'modifier_options.created_at NOT NULL');

select col_not_null('public', 'menu_categories',  'updated_at', 'menu_categories.updated_at NOT NULL');
select col_not_null('public', 'menu_items',       'updated_at', 'menu_items.updated_at NOT NULL');
select col_not_null('public', 'item_sizes',       'updated_at', 'item_sizes.updated_at NOT NULL');
select col_not_null('public', 'item_variants',    'updated_at', 'item_variants.updated_at NOT NULL');
select col_not_null('public', 'modifiers',        'updated_at', 'modifiers.updated_at NOT NULL');
select col_not_null('public', 'modifier_options', 'updated_at', 'modifier_options.updated_at NOT NULL');

select col_is_null('public', 'menu_categories',  'deleted_at', 'menu_categories.deleted_at tombstone (nullable)');
select col_is_null('public', 'menu_items',       'deleted_at', 'menu_items.deleted_at tombstone (nullable)');
select col_is_null('public', 'item_sizes',       'deleted_at', 'item_sizes.deleted_at tombstone (nullable)');
select col_is_null('public', 'item_variants',    'deleted_at', 'item_variants.deleted_at tombstone (nullable)');
select col_is_null('public', 'modifiers',        'deleted_at', 'modifiers.deleted_at tombstone (nullable)');
select col_is_null('public', 'modifier_options', 'deleted_at', 'modifier_options.deleted_at tombstone (nullable)');

-- ---- money column types (D-007 integer minor) (10 asserts) ----
select col_type_is('public', 'menu_items', 'base_price_minor', 'bigint', 'menu_items.base_price_minor is bigint');
select col_not_null('public', 'menu_items', 'base_price_minor', 'menu_items.base_price_minor NOT NULL');
select col_type_is('public', 'menu_items', 'currency_code', 'character(3)', 'menu_items.currency_code is char(3)');
select col_not_null('public', 'menu_items', 'currency_code', 'menu_items.currency_code NOT NULL');
select col_type_is('public', 'item_sizes',       'price_delta_minor', 'bigint', 'item_sizes.price_delta_minor is bigint');
select col_not_null('public', 'item_sizes',      'price_delta_minor', 'item_sizes.price_delta_minor NOT NULL');
select col_type_is('public', 'item_variants',    'price_delta_minor', 'bigint', 'item_variants.price_delta_minor is bigint');
select col_not_null('public', 'item_variants',   'price_delta_minor', 'item_variants.price_delta_minor NOT NULL');
select col_type_is('public', 'modifier_options', 'price_delta_minor', 'bigint', 'modifier_options.price_delta_minor is bigint');
select col_not_null('public', 'modifier_options','price_delta_minor', 'modifier_options.price_delta_minor NOT NULL');

-- ---- no float/numeric/decimal/money on any menu column (1) ----
select is(
  (select count(*)::int from information_schema.columns
   where table_schema = 'public'
     and table_name in ('menu_categories','menu_items','item_sizes','item_variants','modifiers','modifier_options')
     and data_type in ('numeric','double precision','real','money')),
  0, 'no menu table column uses float/numeric/decimal/money (D-007)');

-- ---- no FK from order snapshot tables to live menu tables (D-008) (1) ----
select is(
  (select count(*)::int
   from pg_constraint c
   join pg_class child  on child.oid  = c.conrelid
   join pg_class parent on parent.oid = c.confrelid
   where c.contype = 'f'
     and child.relname  in ('order_items','order_item_modifiers')
     and parent.relname in ('menu_categories','menu_items','item_sizes','item_variants','modifiers','modifier_options')),
  0, 'no FK from order_items/order_item_modifiers to the live menu (D-008 snapshot independence)');

-- ---- constraint behavior (fixtures seeded as BYPASSRLS connection) (4) ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109schema-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'Cat A');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000c1', 'Item A', 1500, 'USD');

select lives_ok(
  $$ insert into item_sizes (organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-0000000000d1','Small', -500) $$,
  'item_sizes.price_delta_minor accepts a NEGATIVE signed delta');

select lives_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-0000000000c1','Free Item', 0, 'USD') $$,
  'menu_items.base_price_minor accepts 0 (>= 0)');

select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-0000000000c1','Bad', -1, 'USD') $$,
  '23514', NULL, 'menu_items.base_price_minor rejects a NEGATIVE value (check_violation)');

select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-0000000000c1','Bad Cur', 100, 'usd') $$,
  '23514', NULL, 'menu_items.currency_code rejects a non [A-Z]{3} value (check_violation)');

select * from finish();
rollback;
