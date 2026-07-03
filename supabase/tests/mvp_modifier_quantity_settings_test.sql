-- ============================================================================
-- MVP (menu/media sprint) — pgTAP: modifier quantity settings
-- (allow_quantity / max_quantity on public.modifiers) — D-007, D-011, D-012,
-- T-003, R-003.
-- ============================================================================
-- Covers: the two additive columns (defaults false/null; CHECK rejects
-- max_quantity <= 0; CHECK rejects single+allow_quantity — both via direct
-- insert and constraint presence); the DROP+recreated 14-arg
-- menu_upsert_modifier (create with allow=true/max=5 persists; a LEGACY
-- 12-arg call RESETS them to false/null — the full-state house pin; RPC-level
-- 42501 validation; exactly ONE overload per schema; grants intact);
-- pos_menu serving the two keys to cashier AND kitchen sessions (with the
-- kitchen %minor% sweep unchanged); list_menu serving the two keys; and two
-- NEW order-loop pins: submit_order accepts/persists the modifier-quantity
-- total math (unit*qty + delta*3) while rejecting a subtotal computed as if
-- quantity were 1, and order_items[].notes round-trips through a
-- kitchen-device sync_pull row (notes present, NO %minor% keys).
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057
-- convention); authorized RPC calls use the identity GUC ONLY (never the org
-- GUC — the production JWT shape, mvp_menu_real_access convention).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(33);

-- ===== fixtures: org/restaurant/branch + pos & kds device stacks =============
insert into organizations (id, name, slug, default_currency) values
  ('70000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpmq-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('70000000-0000-0000-0000-00000000da11', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('70000000-0000-0000-0000-00000000da22', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('70000000-0000-0000-0000-00000000fa11', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-00000000da11', 'active'),
  ('70000000-0000-0000-0000-00000000fa22', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('70000000-0000-0000-0000-0000000005a1', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-00000000da11', '70000000-0000-0000-0000-00000000fa11'),
  ('70000000-0000-0000-0000-0000000005a2', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-00000000da22', '70000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('70000000-0000-0000-0000-00000000ee01', 'mvpmq-cashier@example.test'),
  ('70000000-0000-0000-0000-00000000ee04', 'mvpmq-kitchen@example.test'),
  ('70000000-0000-0000-0000-00000000ee05', 'mvpmq-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('70000000-0000-0000-0000-00000000ab01', '70000000-0000-0000-0000-00000000ee01', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('70000000-0000-0000-0000-00000000ab04', '70000000-0000-0000-0000-00000000ee04', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', 'kitchen_staff'),
  ('70000000-0000-0000-0000-00000000ab05', '70000000-0000-0000-0000-00000000ee05', '70000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('70000000-0000-0000-0000-0000000ef001', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-00000000ee01', '70000000-0000-0000-0000-00000000ab01'),
  ('70000000-0000-0000-0000-0000000ef004', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-00000000ee04', '70000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('70000000-0000-0000-0000-00000000c501', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-0000000005a1', '70000000-0000-0000-0000-0000000ef001', '70000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('70000000-0000-0000-0000-00000000c504', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-00000000a1b1', '70000000-0000-0000-0000-0000000005a2', '70000000-0000-0000-0000-0000000ef004', '70000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ===== fixtures: menu — one live item; a quantity-capable group + a plain one =
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('70000000-0000-0000-0000-00000000ca01', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('70000000-0000-0000-0000-0000000000f1', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null,
   '70000000-0000-0000-0000-00000000ca01', 'Burger', 5000, 'ILS', 1, true);
-- 'Extras': a 'multiple' group WITH quantity settings; 'Plain': legacy-shaped
-- insert (NO new columns named) — pins the defaults false/null.
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, display_order, is_active, allow_quantity, max_quantity) values
  ('70000000-0000-0000-0000-000000000701', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, '70000000-0000-0000-0000-0000000000f1', 'Extras', 'multiple', 0, 3, false, 1, true, true, 5);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, display_order, is_active) values
  ('70000000-0000-0000-0000-000000000702', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, '70000000-0000-0000-0000-0000000000f1', 'Plain', 'single', 0, null, false, 2, true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order) values
  ('70000000-0000-0000-0000-000000000801', '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, '70000000-0000-0000-0000-000000000701', 'Cheese', 100, 1);

-- ===== (1-5) columns exist; nullability; defaults false/null ==================
select has_column('public', 'modifiers', 'allow_quantity', 'modifiers.allow_quantity column exists');
select has_column('public', 'modifiers', 'max_quantity',   'modifiers.max_quantity column exists');
select col_not_null('public', 'modifiers', 'allow_quantity', 'modifiers.allow_quantity is NOT NULL');
select col_is_null('public', 'modifiers', 'max_quantity',    'modifiers.max_quantity is nullable (null = no cap)');
select ok(
  (select m.allow_quantity = false and m.max_quantity is null
     from modifiers m where m.id = '70000000-0000-0000-0000-000000000702'),
  'a legacy-shaped insert (no new columns) defaults to allow_quantity=false / max_quantity=null');

-- ===== (6-9) table CHECKs (D-012 layer 4) =====================================
select throws_ok($$
  insert into modifiers (organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, allow_quantity, max_quantity)
  values ('70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, '70000000-0000-0000-0000-0000000000f1', 'Zero', 'multiple', true, 0) $$,
  '23514', NULL, 'direct insert with max_quantity = 0 violates modifiers_max_quantity_positive (23514)');
select throws_ok($$
  insert into modifiers (organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, allow_quantity, max_quantity)
  values ('70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, '70000000-0000-0000-0000-0000000000f1', 'Neg', 'multiple', true, -3) $$,
  '23514', NULL, 'direct insert with max_quantity = -3 violates modifiers_max_quantity_positive (23514)');
select throws_ok($$
  insert into modifiers (organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, allow_quantity)
  values ('70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null, '70000000-0000-0000-0000-0000000000f1', 'SingleQty', 'single', true) $$,
  '23514', NULL, 'direct insert with selection_type=single + allow_quantity=true violates modifiers_single_never_quantity (23514)');
select ok(
  exists (select 1 from pg_constraint where conname = 'modifiers_single_never_quantity' and conrelid = 'public.modifiers'::regclass)
  and exists (select 1 from pg_constraint where conname = 'modifiers_max_quantity_positive' and conrelid = 'public.modifiers'::regclass),
  'both quantity CHECK constraints are present on public.modifiers (defence in depth, D-012 layer 4)');

-- ===== (10-15) menu_upsert_modifier roundtrip — identity GUC only, no org GUC =
set local role authenticated;
set local app.current_app_user_id = '70000000-0000-0000-0000-00000000ee05';  -- org_owner
select is(
  (app.menu_upsert_modifier('70000000-0000-0000-0000-0000000000a0','70000000-0000-0000-0000-0000000000a1',null,
     '70000000-0000-0000-0000-000000000777','70000000-0000-0000-0000-0000000000f1','RPC Extras','multiple',0,3,false,9,true,
     true,5) ->> 'action'),
  'created', 'menu_upsert_modifier (14-arg) creates a multiple group with allow_quantity=true + max_quantity=5');
reset role;
select ok(
  (select m.allow_quantity = true and m.max_quantity = 5 and m.selection_type = 'multiple'
     from modifiers m where m.id = '70000000-0000-0000-0000-000000000777'),
  'the created row persists allow_quantity=true / max_quantity=5');
set local role authenticated;
set local app.current_app_user_id = '70000000-0000-0000-0000-00000000ee05';
select is(
  (app.menu_upsert_modifier('70000000-0000-0000-0000-0000000000a0','70000000-0000-0000-0000-0000000000a1',null,
     '70000000-0000-0000-0000-000000000777','70000000-0000-0000-0000-0000000000f1','RPC Extras','multiple',0,3,false,9,true) ->> 'action'),
  'updated', 'a LEGACY 12-arg call (no quantity args) still resolves (single overload) and updates');
reset role;
select ok(
  (select m.allow_quantity = false and m.max_quantity is null
     from modifiers m where m.id = '70000000-0000-0000-0000-000000000777'),
  'the legacy call RESET allow_quantity/max_quantity to false/null (FULL-STATE semantics pin)');
set local role authenticated;
set local app.current_app_user_id = '70000000-0000-0000-0000-00000000ee05';
select throws_ok($$
  select app.menu_upsert_modifier('70000000-0000-0000-0000-0000000000a0','70000000-0000-0000-0000-0000000000a1',null,
    null,'70000000-0000-0000-0000-0000000000f1','Bad Cap','multiple',0,3,false,9,true,true,0) $$,
  '42501', 'menu_upsert_modifier: max_quantity must be null or a positive integer (units of one option; a count, not money)',
  'the RPC rejects max_quantity = 0 before the table CHECK (42501, RF-109 validation style)');
select throws_ok($$
  select app.menu_upsert_modifier('70000000-0000-0000-0000-0000000000a0','70000000-0000-0000-0000-0000000000a1',null,
    null,'70000000-0000-0000-0000-0000000000f1','Bad Single','single',0,null,false,9,true,true,null) $$,
  '42501', 'menu_upsert_modifier: allow_quantity requires selection_type = multiple (a single-select group never takes per-option quantities)',
  'the RPC rejects allow_quantity=true on a single-select group (42501)');

-- ===== (16) public wrapper delegates with the two new params ==================
select is(
  (public.menu_upsert_modifier('70000000-0000-0000-0000-0000000000a0','70000000-0000-0000-0000-0000000000a1',null,
     '70000000-0000-0000-0000-000000000778','70000000-0000-0000-0000-0000000000f1','Wrap Extras','multiple',0,2,false,8,true,
     true,2) ->> 'action'),
  'created', 'public.menu_upsert_modifier (wrapper) delegates the two new params');
reset role;

-- ===== (17-21) exactly ONE overload per schema; grants intact =================
select is(
  (select count(*)::int from pg_proc where proname = 'menu_upsert_modifier' and pronamespace = 'app'::regnamespace),
  1, 'app.menu_upsert_modifier has exactly ONE overload (old 12-arg signature dropped; PostgREST-unambiguous)');
select is(
  (select count(*)::int from pg_proc where proname = 'menu_upsert_modifier' and pronamespace = 'public'::regnamespace),
  1, 'public.menu_upsert_modifier has exactly ONE overload');
select ok(
  has_function_privilege('authenticated', 'app.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer)', 'execute'),
  'authenticated MAY execute the 14-arg app.menu_upsert_modifier');
select ok(
  has_function_privilege('authenticated', 'public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer)', 'execute'),
  'authenticated MAY execute the 14-arg public.menu_upsert_modifier wrapper');
select ok(
  not has_function_privilege('anon', 'public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer)', 'execute')
  and not has_function_privilege('public', 'public.menu_upsert_modifier(uuid, uuid, uuid, uuid, uuid, text, text, integer, integer, boolean, integer, boolean, boolean, integer)', 'execute'),
  'anon and PUBLIC may NOT execute the new public.menu_upsert_modifier (grants re-issued exactly)');

-- ===== (22-25) pos_menu serves the two keys; kitchen sweep unchanged ==========
create temp table t_cash    as select app.pos_menu('70000000-0000-0000-0000-00000000c501', '70000000-0000-0000-0000-00000000da11') as m;
create temp table t_kitchen as select app.pos_menu('70000000-0000-0000-0000-00000000c504', '70000000-0000-0000-0000-00000000da22') as m;
select ok(
  (select (r->>'allow_quantity')::boolean = true and (r->>'max_quantity')::int = 5
     from t_cash, lateral jsonb_array_elements(m->'modifiers') r
     where r->>'id' = '70000000-0000-0000-0000-000000000701'),
  'cashier pos_menu: the Extras modifier row carries allow_quantity=true + max_quantity=5');
select ok(
  (select (r ? 'max_quantity') and r->'max_quantity' = 'null'::jsonb and (r->>'allow_quantity')::boolean = false
     from t_cash, lateral jsonb_array_elements(m->'modifiers') r
     where r->>'id' = '70000000-0000-0000-0000-000000000702'),
  'cashier pos_menu: the Plain row carries allow_quantity=false and an explicit JSON-null max_quantity (keys always present)');
select ok(
  (select (r->>'allow_quantity')::boolean = true and (r->>'max_quantity')::int = 5
     from t_kitchen, lateral jsonb_array_elements(m->'modifiers') r
     where r->>'id' = '70000000-0000-0000-0000-000000000701'),
  'kitchen pos_menu: the SAME two keys are served (non-money selection rules, consistent with min/max_select)');
select ok(
  (select not exists (
     select 1
     from t_kitchen,
          lateral jsonb_array_elements((m->'items') || (m->'sizes') || (m->'variants')
                                       || (m->'modifiers') || (m->'modifier_options')) as it,
          lateral jsonb_object_keys(it) as k
     where k like '%minor%')),
  'kitchen pos_menu: NO row in ANY of the five arrays carries any money (*minor*) key (T-003 sweep unchanged)');

-- ===== (26) list_menu serves the two keys =====================================
set local role authenticated;
set local app.current_app_user_id = '70000000-0000-0000-0000-00000000ee05';
create temp table t_menu as select app.list_menu(
  '70000000-0000-0000-0000-0000000000a0', '70000000-0000-0000-0000-0000000000a1', null) as res;
reset role;
select ok(
  (select (r->>'allow_quantity')::boolean = true and (r->>'max_quantity')::int = 5
     from t_menu, lateral jsonb_array_elements(res->'modifiers') r
     where r->>'id' = '70000000-0000-0000-0000-000000000701'),
  'list_menu (management read): the Extras modifier row carries allow_quantity=true + max_quantity=5');

-- ===== (27-31) NEW total-math pin: submit_order with modifier quantity 3 ======
-- 1 x Burger @5000 + Cheese @100 x3 -> line = 5000 + 300 = 5300; grand = 5300.
-- The item carries a kitchen note in order_items[].notes.
create temp table t_submit as select app.submit_order(
  '70000000-0000-0000-0000-00000000c501','70000000-0000-0000-0000-00000000a0d1',
  '70000000-0000-0000-0000-00000000da11','op-mq1','dine_in',null,null,'ILS',null,
  '[{"menu_item_id":"70000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":5000,"menu_item_name_snapshot":"Burger","notes":"no onions","modifiers":[{"modifier_option_id":"70000000-0000-0000-0000-000000000801","price_minor_snapshot":100,"quantity":3,"modifier_name_snapshot":"Extras","option_name_snapshot":"Cheese"}]}]'::jsonb,
  5300, 0, 0, 5300, null) as res;
select is((select (res->>'ok')::boolean from t_submit), true,
  'submit_order ACCEPTS the correct modifier-quantity subtotal (unit*qty + delta*3 = 5300)');
select is(
  (select subtotal_minor from orders where id = '70000000-0000-0000-0000-00000000a0d1')::bigint, 5300::bigint,
  'orders.subtotal_minor persists the quantity-multiplied recompute (5000 + 100*3)');
select is(
  (select oim.quantity from order_item_modifiers oim
     join order_items oi on oi.id = oim.order_item_id
     where oi.order_id = '70000000-0000-0000-0000-00000000a0d1'), 3,
  'the order_item_modifiers row stores quantity = 3');
select throws_ok($$ select app.submit_order(
  '70000000-0000-0000-0000-00000000c501','70000000-0000-0000-0000-00000000a0d2',
  '70000000-0000-0000-0000-00000000da11','op-mq2','dine_in',null,null,'ILS',null,
  '[{"menu_item_id":"70000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":5000,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"70000000-0000-0000-0000-000000000801","price_minor_snapshot":100,"quantity":3,"modifier_name_snapshot":"Extras","option_name_snapshot":"Cheese"}]}]'::jsonb,
  5100, 0, 0, 5100, null) $$, '42501', NULL,
  'a subtotal computed AS IF quantity were 1 (5100) is REJECTED (anti-tamper recompute multiplies the modifier quantity)');
select is(
  (select oi.notes from order_items oi where oi.order_id = '70000000-0000-0000-0000-00000000a0d1'), 'no onions',
  'order_items.notes persists the submitted per-line note');

-- ===== (32-33) NEW note pin: the note reaches a kitchen-device sync_pull row ==
create temp table t_kpull as select app.sync_pull(
  '70000000-0000-0000-0000-00000000c504','70000000-0000-0000-0000-00000000da22',
  array['order_items'],'{}'::jsonb,500) as res;
select ok(
  (select bool_or((r ? 'notes') and r->>'notes' = 'no onions')
     from t_kpull, lateral jsonb_array_elements(res->'changes'->'order_items'->'rows') r),
  'a kitchen-device sync_pull order_items row carries the submitted notes value');
select is(
  (select count(*) from t_kpull,
     lateral jsonb_array_elements(res->'changes'->'order_items'->'rows') r,
     lateral jsonb_object_keys(r) k
     where k like '%minor%')::int, 0,
  'the SAME kitchen order_items pull rows carry NO money (*minor*) key (T-003 redaction unchanged)');

select * from finish();
rollback;
