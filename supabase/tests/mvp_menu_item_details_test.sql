-- ============================================================================
-- MVP (menu/media sprint) — pgTAP: rich product attributes end to end.
-- Covers: the six menu_items columns (item_type/tags/prep_minutes/sku/
-- kitchen_note/attributes) + their CHECKs; menu_upsert_item DROP+recreated at
-- 19 args with a SINGLE overload (PostgREST-unambiguous) + exact grants; a
-- full roundtrip of every field incl. the attributes object; function-level
-- shape validation (42501); list_menu exposing all six keys (always present,
-- null when unset); pos_menu exposing the five device keys (NEVER sku) with
-- kitchen PASS-THROUGH of the non-money prep info while the T-003 money keys
-- and the T-014 image_path key stay OMITTED for kitchen; legacy 13-arg
-- positional binding (full-state clear) and blank/empty normalization.
-- HARD RULE under test: money NEVER rides tags/attributes (D-007) — the
-- kitchen %minor% sweep stays green with the new keys present.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(49);

-- ===== fixtures (BYPASSRLS connection role) =================================
insert into organizations (id, name, slug, default_currency) values
  ('78000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpdet-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('78000000-0000-0000-0000-00000000ee01', 'mvpdet-owner@example.test'),
  ('78000000-0000-0000-0000-00000000ee02', 'mvpdet-cashier@example.test'),
  ('78000000-0000-0000-0000-00000000ee03', 'mvpdet-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('78000000-0000-0000-0000-00000000ab01', '78000000-0000-0000-0000-00000000ee01', '78000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('78000000-0000-0000-0000-00000000ab02', '78000000-0000-0000-0000-00000000ee02', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'cashier'),
  ('78000000-0000-0000-0000-00000000ab03', '78000000-0000-0000-0000-00000000ee03', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('78000000-0000-0000-0000-0000000ef002', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000ee02', '78000000-0000-0000-0000-00000000ab02'),
  ('78000000-0000-0000-0000-0000000ef003', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000ee03', '78000000-0000-0000-0000-00000000ab03');

-- devices + sessions: a POS (cashier PIN session) and a KDS (kitchen PIN session).
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('78000000-0000-0000-0000-00000000d001', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'pos'),
  ('78000000-0000-0000-0000-00000000d002', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('78000000-0000-0000-0000-00000000fa01', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d001', 'active'),
  ('78000000-0000-0000-0000-00000000fa02', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active) values
  ('78000000-0000-0000-0000-000000005a01', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d001', '78000000-0000-0000-0000-00000000fa01', true),
  ('78000000-0000-0000-0000-000000005a02', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d002', '78000000-0000-0000-0000-00000000fa02', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('78000000-0000-0000-0000-00000000c501', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-000000005a01', '78000000-0000-0000-0000-0000000ef002', '78000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('78000000-0000-0000-0000-00000000c503', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-000000005a02', '78000000-0000-0000-0000-0000000ef003', '78000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- menu: a restaurant-wide category; a PLAIN item seeded without any of the new
-- fields (the rich item e001 is created through the RPC below).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('78000000-0000-0000-0000-00000000ca01', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', null, 'Cat A');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('78000000-0000-0000-0000-00000000e002', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', null, '78000000-0000-0000-0000-00000000ca01', 'Plain Tea', 900, 'USD');

-- ===== (1-7) schema: the six columns exist, all nullable =====================
select has_column('public', 'menu_items', 'item_type',    'menu_items.item_type exists');
select has_column('public', 'menu_items', 'tags',         'menu_items.tags exists');
select has_column('public', 'menu_items', 'prep_minutes', 'menu_items.prep_minutes exists');
select has_column('public', 'menu_items', 'sku',          'menu_items.sku exists');
select has_column('public', 'menu_items', 'kitchen_note', 'menu_items.kitchen_note exists');
select has_column('public', 'menu_items', 'attributes',   'menu_items.attributes exists');
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'menu_items'
      and column_name in ('item_type', 'tags', 'prep_minutes', 'sku', 'kitchen_note', 'attributes')
      and is_nullable = 'YES'),
  6, 'all six rich-attribute columns are nullable (unset = null; no data rewrite)');

-- ===== (8-13) schema: column types ===========================================
select col_type_is('public', 'menu_items', 'item_type',    'text',    'item_type is text');
select col_type_is('public', 'menu_items', 'tags',         'jsonb',   'tags is jsonb');
select col_type_is('public', 'menu_items', 'prep_minutes', 'integer', 'prep_minutes is integer (minutes — time, never money)');
select col_type_is('public', 'menu_items', 'sku',          'text',    'sku is text');
select col_type_is('public', 'menu_items', 'kitchen_note', 'text',    'kitchen_note is text');
select col_type_is('public', 'menu_items', 'attributes',   'jsonb',   'attributes is jsonb');

-- ===== (14-19) schema: CHECK constraints (the D-012 layer-4 boundary) ========
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, item_type)
     values ('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000ca01','Bad Type', 100, 'USD', 'dessert') $$,
  '23514', NULL, 'menu_items.item_type rejects a value outside food/drink/side/combo/other (check_violation)');
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, tags)
     values ('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000ca01','Bad Tags', 100, 'USD', '{"spicy": true}'::jsonb) $$,
  '23514', NULL, 'menu_items.tags rejects a non-array jsonb value (check_violation)');
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, tags)
     values ('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000ca01','Bad Tag El', 100, 'USD', '["spicy", 3]'::jsonb) $$,
  '23514', NULL, 'menu_items.tags rejects an array containing a non-string element (check_violation)');
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, prep_minutes)
     values ('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000ca01','Bad Prep', 100, 'USD', -5) $$,
  '23514', NULL, 'menu_items.prep_minutes rejects a negative value (check_violation)');
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, sku)
     values ('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000ca01','Bad Sku', 100, 'USD', '   ') $$,
  '23514', NULL, 'menu_items.sku rejects a blank (whitespace-only) value (check_violation)');
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, attributes)
     values ('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000ca01','Bad Attrs', 100, 'USD', '["portion_label"]'::jsonb) $$,
  '23514', NULL, 'menu_items.attributes rejects a non-object jsonb value (check_violation)');

-- ===== (20-23) menu_upsert_item: ONE overload + grants =======================
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_item'), 1,
  'exactly ONE app.menu_upsert_item exists (no overload — PostgREST-unambiguous)');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_item'), 1,
  'exactly ONE public.menu_upsert_item wrapper exists');
select ok(
  has_function_privilege('authenticated', 'public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb)', 'execute'),
  'authenticated MAY execute the 19-arg public.menu_upsert_item');
select ok(
  not has_function_privilege('anon', 'public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text, text, jsonb, integer, text, text, jsonb)', 'execute'),
  'anon may NOT execute the 19-arg public.menu_upsert_item');

-- ===== (24-30) full roundtrip of every field through the RPC =================
set local role authenticated;
set local app.current_app_user_id = '78000000-0000-0000-0000-00000000ee01';  -- org_owner
select is(
  (app.menu_upsert_item(
     '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', null,
     '78000000-0000-0000-0000-00000000e001', '78000000-0000-0000-0000-00000000ca01',
     'Rich Burger', 'Flame-grilled.', 4200, 'USD', null, 0, true, null,
     'food', '["spicy","popular"]'::jsonb, 12, 'BRG-01', 'No onions on the grill.',
     '{"portion_label":"Single","patty_count":1,"patty_weight_grams":160}'::jsonb) ->> 'action'),
  'created', 'creating an item with all six rich attributes succeeds');
reset role;
select is((select item_type from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  'food', 'the created row stores item_type');
select is((select tags from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  '["spicy","popular"]'::jsonb, 'the created row stores tags (wire strings, never localized)');
select is((select prep_minutes from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  12, 'the created row stores prep_minutes');
select is((select sku from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  'BRG-01', 'the created row stores sku');
select is((select kitchen_note from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  'No onions on the grill.', 'the created row stores kitchen_note');
select is((select attributes from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  '{"portion_label":"Single","patty_count":1,"patty_weight_grams":160}'::jsonb,
  'the created row stores the attributes object (non-money bag: portion/count/weight-in-grams)');

-- ===== (31-34) list_menu exposes all six keys =================================
set local role authenticated;
set local app.current_app_user_id = '78000000-0000-0000-0000-00000000ee01';
create temp table t_list as select app.list_menu(
  '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', null) as res;
reset role;
select ok(
  (select bool_and((e ? 'item_type') and (e ? 'tags') and (e ? 'prep_minutes')
              and (e ? 'sku') and (e ? 'kitchen_note') and (e ? 'attributes'))
     from t_list, jsonb_array_elements(res->'items') e),
  'every list_menu item row carries all six rich-attribute keys (uniform parse)');
select ok(
  (select e->>'item_type' = 'food' and (e->>'prep_minutes')::int = 12
      and e->>'sku' = 'BRG-01' and e->>'kitchen_note' = 'No onions on the grill.'
     from t_list, jsonb_array_elements(res->'items') e
    where e->>'id' = '78000000-0000-0000-0000-00000000e001'),
  'the rich item roundtrips item_type/prep_minutes/sku/kitchen_note through list_menu');
select ok(
  (select e->'tags' = '["spicy","popular"]'::jsonb
      and e->'attributes' = '{"portion_label":"Single","patty_count":1,"patty_weight_grams":160}'::jsonb
     from t_list, jsonb_array_elements(res->'items') e
    where e->>'id' = '78000000-0000-0000-0000-00000000e001'),
  'the rich item roundtrips tags + attributes as jsonb through list_menu');
select ok(
  (select (e->>'item_type') is null and jsonb_typeof(e->'tags') = 'null'
      and (e->>'prep_minutes') is null and (e->>'sku') is null
      and (e->>'kitchen_note') is null and jsonb_typeof(e->'attributes') = 'null'
     from t_list, jsonb_array_elements(res->'items') e
    where e->>'id' = '78000000-0000-0000-0000-00000000e002'),
  'an item WITHOUT rich attributes carries the keys with null values');

-- ===== (35-36) pos_menu cashier: five device keys, NEVER sku =================
select ok(
  (select it->>'item_type' = 'food' and (it->>'prep_minutes')::int = 12
      and it->>'kitchen_note' = 'No onions on the grill.'
      and it->'tags' = '["spicy","popular"]'::jsonb
      and it->'attributes' = '{"portion_label":"Single","patty_count":1,"patty_weight_grams":160}'::jsonb
     from jsonb_array_elements(app.pos_menu('78000000-0000-0000-0000-00000000c501', '78000000-0000-0000-0000-00000000d001') -> 'items') it
    where it->>'name' = 'Rich Burger'),
  'the cashier pos_menu item carries item_type/tags/prep_minutes/kitchen_note/attributes');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(app.pos_menu('78000000-0000-0000-0000-00000000c501', '78000000-0000-0000-0000-00000000d001') -> 'items') it
    where it ? 'sku'),
  'NO cashier pos_menu item carries the sku key (internal back-office code — devices never need it)');

-- ===== (37-40) pos_menu kitchen: non-money prep info PASSES THROUGH ==========
select ok(
  (select it->>'item_type' = 'food' and (it->>'prep_minutes')::int = 12
      and it->>'kitchen_note' = 'No onions on the grill.'
      and it->'tags' = '["spicy","popular"]'::jsonb
      and it->'attributes' = '{"portion_label":"Single","patty_count":1,"patty_weight_grams":160}'::jsonb
     from jsonb_array_elements(app.pos_menu('78000000-0000-0000-0000-00000000c503', '78000000-0000-0000-0000-00000000d002') -> 'items') it
    where it->>'name' = 'Rich Burger'),
  'the KITCHEN pos_menu item still carries the non-money prep info (kitchen_note/prep_minutes/tags/attributes/item_type pass through — a KDS needs prep info)');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(app.pos_menu('78000000-0000-0000-0000-00000000c503', '78000000-0000-0000-0000-00000000d002') -> 'items') it
    where it ? 'sku'),
  'NO kitchen pos_menu item carries the sku key either');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(app.pos_menu('78000000-0000-0000-0000-00000000c503', '78000000-0000-0000-0000-00000000d002') -> 'items') it
    where (it ? 'base_price_minor') or (it ? 'image_path')),
  'kitchen items still OMIT base_price_minor (T-003) and image_path (T-014) — regression');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(app.pos_menu('78000000-0000-0000-0000-00000000c503', '78000000-0000-0000-0000-00000000d002') -> 'items') it
    cross join lateral jsonb_object_keys(it) k
    where k like '%minor%'),
  'NO kitchen item carries any money (*minor*) key with the new attributes present (T-003 defence sweep — money never rides tags/attributes, D-007)');

-- ===== (41-45) function-level shape validation (42501, RF-109 style) =========
set local role authenticated;
set local app.current_app_user_id = '78000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.menu_upsert_item('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000e001','78000000-0000-0000-0000-00000000ca01','Rich Burger',null,4200,'USD',null,0,true,null,'dessert',null,null,null,null,null) $$,
  '42501', NULL, 'menu_upsert_item raises 42501 on a garbage item_type');
select throws_ok(
  $$ select app.menu_upsert_item('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000e001','78000000-0000-0000-0000-00000000ca01','Rich Burger',null,4200,'USD',null,0,true,null,null,'{"spicy":true}'::jsonb,null,null,null,null) $$,
  '42501', NULL, 'menu_upsert_item raises 42501 when tags is not a JSON array');
select throws_ok(
  $$ select app.menu_upsert_item('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000e001','78000000-0000-0000-0000-00000000ca01','Rich Burger',null,4200,'USD',null,0,true,null,null,'["spicy",3]'::jsonb,null,null,null,null) $$,
  '42501', NULL, 'menu_upsert_item raises 42501 when a tags element is not a string');
select throws_ok(
  $$ select app.menu_upsert_item('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000e001','78000000-0000-0000-0000-00000000ca01','Rich Burger',null,4200,'USD',null,0,true,null,null,null,null,null,null,'["not","an","object"]'::jsonb) $$,
  '42501', NULL, 'menu_upsert_item raises 42501 when attributes is not a JSON object');
select throws_ok(
  $$ select app.menu_upsert_item('78000000-0000-0000-0000-0000000000a0','78000000-0000-0000-0000-0000000000a1',null,'78000000-0000-0000-0000-00000000e001','78000000-0000-0000-0000-00000000ca01','Rich Burger',null,4200,'USD',null,0,true,null,null,null,-1,null,null,null) $$,
  '42501', NULL, 'menu_upsert_item raises 42501 on a negative prep_minutes');

-- ===== (46-47) legacy 13-arg positional call binds; full-state clear =========
create temp table t_legacy as select app.menu_upsert_item(
  '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', null,
  '78000000-0000-0000-0000-00000000e001', '78000000-0000-0000-0000-00000000ca01',
  'Rich Burger', null, 4200, 'USD', null, 0, true, null) as r;
select is((select r->>'action' from t_legacy), 'updated',
  'the legacy 13-arg positional call still binds (the six new params default to null)');
reset role;
select ok(
  (select item_type is null and tags is null and prep_minutes is null
      and sku is null and kitchen_note is null and attributes is null
     from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  'omitting the rich params CLEARS all six stored values (full-state upsert, same rule as p_image_path)');

-- ===== (48-49) blank/empty inputs normalize to null (never a blank row) ======
set local role authenticated;
set local app.current_app_user_id = '78000000-0000-0000-0000-00000000ee01';
create temp table t_blank as select app.menu_upsert_item(
  '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', null,
  '78000000-0000-0000-0000-00000000e001', '78000000-0000-0000-0000-00000000ca01',
  'Rich Burger', null, 4200, 'USD', null, 0, true, null,
  null, '[]'::jsonb, null, '   ', '  ', '{}'::jsonb) as r;
select is((select (r->>'ok')::boolean from t_blank), true,
  'a blank sku/kitchen_note + empty tags/attributes upsert succeeds (normalized, never a crash)');
reset role;
select ok(
  (select sku is null and kitchen_note is null and tags is null and attributes is null
     from menu_items where id = '78000000-0000-0000-0000-00000000e001'),
  'blank text fields and empty array/object normalize to NULL (one canonical unset shape)');

select * from finish();
rollback;
