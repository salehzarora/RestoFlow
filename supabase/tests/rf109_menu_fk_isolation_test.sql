-- RF-109 Stage 1 -- menu FK / same-org tenant shape (DECISION D-031; D-012 layer 4).
-- Proves composite same-org FKs reject cross-org and cross-restaurant/branch references,
-- and that menu_items.default_station_id is a same-org composite FK to stations
-- (RF-109-Q1; stations gained unique(organization_id, id) in this migration).
-- Fixtures seeded as the BYPASSRLS connection (FK/constraint checks apply to everyone).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109fk-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf109fk-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000a2a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-00000000b1a0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000a5a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'Station A1'),
  ('00000000-0000-0000-0000-00000000b5b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1a0', 'Station B1');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000c0a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'Cat A'),
  ('00000000-0000-0000-0000-00000000c0b0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1a0', 'Cat B');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-00000000d0a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000c0a0', 'Item A', 1500, 'USD'),
  ('00000000-0000-0000-0000-00000000d0b0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1a0', '00000000-0000-0000-0000-00000000c0b0', 'Item B', 2000, 'EUR');
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-00000000e0b0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1a0', '00000000-0000-0000-0000-00000000d0b0', 'Mod B');

-- (1) stations gained the same-org composite-FK target unique(organization_id, id)
select ok(
  exists(
    select 1 from pg_constraint c
    join pg_class ch on ch.oid = c.conrelid and ch.relname = 'stations'
    where c.contype = 'u'
      and (select array_agg(a.attname::text order by a.attname::text)
             from pg_attribute a where a.attrelid = ch.oid and a.attnum = any (c.conkey))
          = array['id','organization_id']),
  'stations has a UNIQUE (organization_id, id) constraint (composite-FK target for default_station_id)');

-- (2-4) valid same-org inserts succeed (incl. restaurant-scoped branch_id null)
select lives_ok(
  $$ insert into menu_categories (organization_id, restaurant_id, branch_id, name)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','Cat A2') $$,
  'same-org/branch menu_category inserts ok');
select lives_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000c0a0','Item A2',900,'USD') $$,
  'same-org menu_item (cat in same org) inserts ok');
select lives_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1', null,'00000000-0000-0000-0000-00000000c0a0','Item RestScoped',900,'USD') $$,
  'restaurant-scoped menu_item (branch_id null) inserts ok (branch FK skipped by MATCH SIMPLE)');

-- (5) cross-org parent FK: Org A item referencing an Org B category is rejected
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000c0b0','X',100,'USD') $$,
  '23503', NULL, 'menu_item cannot reference a menu_category from another organization (composite FK)');

-- (6) cross-org restaurant: Org A item with an Org B restaurant_id is rejected
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000b1', null,'00000000-0000-0000-0000-00000000c0a0','X',100,'USD') $$,
  '23503', NULL, 'menu_item cannot reference a restaurant from another organization (composite FK)');

-- (7) branch/restaurant mismatch: branch A2a does not belong to restaurant A1
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a2a0','00000000-0000-0000-0000-00000000c0a0','X',100,'USD') $$,
  '23503', NULL, 'menu_item branch_id must belong to its restaurant (composite branch FK)');

-- (8-9) default_station_id is a same-org FK to stations
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, default_station_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000c0a0','00000000-0000-0000-0000-00000000b5b1','X',100,'USD') $$,
  '23503', NULL, 'menu_item.default_station_id cannot reference a station from another organization');
select lives_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, default_station_id, name, base_price_minor, currency_code)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000c0a0','00000000-0000-0000-0000-00000000a5a1','OK Station',100,'USD') $$,
  'menu_item.default_station_id accepts a same-org station');

-- (10-11) child -> parent across orgs rejected; same-org accepted
select throws_ok(
  $$ insert into item_sizes (organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000d0b0','X',0) $$,
  '23503', NULL, 'item_sizes cannot reference a menu_item from another organization (composite FK)');
select lives_ok(
  $$ insert into item_sizes (organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000d0a0','Large',300) $$,
  'item_sizes accepts a same-org menu_item');

-- (12) modifier_options -> modifier across orgs rejected
select throws_ok(
  $$ insert into modifier_options (organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1a0','00000000-0000-0000-0000-00000000e0b0','X',0) $$,
  '23503', NULL, 'modifier_options cannot reference a modifier from another organization (composite FK)');

select * from finish();
rollback;
