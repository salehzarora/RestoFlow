-- ============================================================================
-- KIOSK-PRINT-114B.6B — the kitchen dispatch payload emits each item's
-- modifiers in the AUTHORITATIVE dashboard order.
--
-- BLOCKER CLOSED. app.kitchen_dispatch_payload_initial / _round aggregated
-- modifiers `order by om.created_at, om.id`; every modifier row of one submit
-- shares created_at (transaction time), so the tie-break fell to the random
-- UUID id and the kiosk initial ticket / POS drain ticket printed the sub-lines
-- shuffled. pos_order_detail already orders by the MENU-ORDER-001 trigger-stamped
-- snapshots (group rank, option rank, line_position, created_at, id) — the
-- dispatch builders now mirror that exact expression.
--
-- Fixture: dashboard order 240g, cheese, lettuce, tomato, onion; rows inserted
-- in the REVERSE (touch) order with UUIDs ascending in that reverse order, so
-- the pre-fix `created_at, id` order is DETERMINISTICALLY wrong (RED), never
-- accidentally right.
-- ============================================================================
begin;

set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(22);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('b6b00000-0000-0000-0000-0000000000a0', 'Org 6B', 'org-6b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000a0', 'Rest 6B');
insert into branches (id, organization_id, restaurant_id, name) values
  ('b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'Branch 6B');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b6b00000-0000-0000-0000-0000000000d1', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b6b00000-0000-0000-0000-0000000000f1', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b6b00000-0000-0000-0000-00000000005a', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000000d1', 'b6b00000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('b6b00000-0000-0000-0000-00000000006a', 'dispatch-order-6b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('b6b00000-0000-0000-0000-00000000007a', 'b6b00000-0000-0000-0000-00000000006a', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('b6b00000-0000-0000-0000-00000000008a', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-00000000006a', 'b6b00000-0000-0000-0000-00000000007a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('b6b00000-0000-0000-0000-00000000009a', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-00000000005a', 'b6b00000-0000-0000-0000-00000000008a', 'b6b00000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- The dashboard menu: Size (group rank 1) = 240g; Extras (group rank 2) =
-- cheese, lettuce, tomato, onion (option ranks 1..4).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('b6b00000-0000-0000-0000-0000000000c1', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'Burgers', 1),
  ('b6b00000-0000-0000-0000-0000000000c2', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'Sides', 2);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('b6b00000-0000-0000-0000-000000001001', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-0000000000c1', 'Classic Burger', 4500, 'ILS', 1),
  ('b6b00000-0000-0000-0000-000000001002', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-0000000000c2', 'Fries', 1000, 'ILS', 1);
-- (display_order is set ON INSERT: app.preserve_menu_display_order reverts any
--  direct UPDATE outside app.menu_reorder — it is INSERT-neutral.)
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('b6b00000-0000-0000-0000-00000000d101', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-000000001001', 'Size',   'single',   1, 1,    true,  true, 1),
  ('b6b00000-0000-0000-0000-00000000d102', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 2);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat) values
  ('b6b00000-0000-0000-0000-00000000e240', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-00000000d101', '240g',    0, 1, true, '{"quantity":2,"unit":"meat"}'::jsonb),
  ('b6b00000-0000-0000-0000-00000000e0c1', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-00000000d102', 'cheese',  0, 1, true, null),
  ('b6b00000-0000-0000-0000-00000000e0c2', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-00000000d102', 'lettuce', 0, 2, true, null),
  ('b6b00000-0000-0000-0000-00000000e0c3', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-00000000d102', 'tomato',  0, 3, true, null),
  ('b6b00000-0000-0000-0000-00000000e0c4', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', null, 'b6b00000-0000-0000-0000-00000000d102', 'onion',   0, 4, true, null);

-- The order: 2 × Classic Burger 240g (+ Fries in the Sides category, inserted
-- FIRST so item ordering by category snapshot is exercised) + a service round.
insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values (
  'b6b00000-0000-0000-0000-00000000010a', 'b6b00000-0000-0000-0000-0000000000a0',
  'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab',
  'b6b00000-0000-0000-0000-0000000000d1', 'b6b00000-0000-0000-0000-00000000009a',
  'b6b00000-0000-0000-0000-00000000008a', 'b6b00000-0000-0000-0000-00000000007a',
  'takeaway', 'ILS', 10000, 10000, 'op-6b-initial', 'submitted');
insert into order_service_rounds (
  id, organization_id, restaurant_id, branch_id, order_id, round_number,
  device_id, opened_by_employee_profile_id, status)
values (
  'b6b00000-0000-0000-0000-00000000012a', 'b6b00000-0000-0000-0000-0000000000a0',
  'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab',
  'b6b00000-0000-0000-0000-00000000010a', 2,
  'b6b00000-0000-0000-0000-0000000000d1', 'b6b00000-0000-0000-0000-00000000008a',
  'submitted');

insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor,
  prep_snapshot, service_round_id)
values
  -- Fries first (Sides, category rank 2) — must still print AFTER the burger.
  ('b6b00000-0000-0000-0000-0000000100a0', 'b6b00000-0000-0000-0000-0000000000a0',
   'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab',
   'b6b00000-0000-0000-0000-00000000010a', 'b6b00000-0000-0000-0000-000000001002',
   1, 'Fries', 1000, 1000, null, null),
  ('b6b00000-0000-0000-0000-0000000100a1', 'b6b00000-0000-0000-0000-0000000000a0',
   'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab',
   'b6b00000-0000-0000-0000-00000000010a', 'b6b00000-0000-0000-0000-000000001001',
   2, 'Classic Burger', 4500, 9000, '[{"name":"Bun","quantity":1,"unit":"pcs"}]'::jsonb, null),
  -- The round's own burger.
  ('b6b00000-0000-0000-0000-0000000100a2', 'b6b00000-0000-0000-0000-0000000000a0',
   'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab',
   'b6b00000-0000-0000-0000-00000000010a', 'b6b00000-0000-0000-0000-000000001001',
   1, 'Classic Burger', 4500, 4500, '[{"name":"Bun","quantity":1,"unit":"pcs"}]'::jsonb,
   'b6b00000-0000-0000-0000-00000000012a'),
  -- A HISTORICAL-style line: its modifiers point at options the menu no longer
  -- has, so the trigger stamps rank 0 and only line_position orders them.
  ('b6b00000-0000-0000-0000-0000000100a3', 'b6b00000-0000-0000-0000-0000000000a0',
   'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab',
   'b6b00000-0000-0000-0000-00000000010a', 'b6b00000-0000-0000-0000-000000001001',
   1, 'Legacy Burger', 4500, 4500, null, null);

-- Modifiers inserted in REVERSE dashboard (touch) order; ids ascend in that
-- same reverse order, so `created_at, id` is deterministically WRONG.
insert into order_item_modifiers (
  id, organization_id, restaurant_id, branch_id, order_item_id,
  modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
values
  ('b6b00000-0000-0000-0000-000000010101', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a1', 'b6b00000-0000-0000-0000-00000000e0c4', 'onion',   0, 1, null),
  ('b6b00000-0000-0000-0000-000000010102', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a1', 'b6b00000-0000-0000-0000-00000000e0c3', 'tomato',  0, 1, null),
  ('b6b00000-0000-0000-0000-000000010103', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a1', 'b6b00000-0000-0000-0000-00000000e0c2', 'lettuce', 0, 1, null),
  ('b6b00000-0000-0000-0000-000000010104', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a1', 'b6b00000-0000-0000-0000-00000000e0c1', 'cheese',  0, 1, null),
  ('b6b00000-0000-0000-0000-000000010105', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a1', 'b6b00000-0000-0000-0000-00000000e240', '240g',    0, 1, '{"quantity":2,"unit":"meat"}'::jsonb),
  -- the round's burger, same reverse touch order
  ('b6b00000-0000-0000-0000-000000010201', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a2', 'b6b00000-0000-0000-0000-00000000e0c4', 'onion',   0, 1, null),
  ('b6b00000-0000-0000-0000-000000010202', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a2', 'b6b00000-0000-0000-0000-00000000e0c3', 'tomato',  0, 1, null),
  ('b6b00000-0000-0000-0000-000000010203', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a2', 'b6b00000-0000-0000-0000-00000000e0c2', 'lettuce', 0, 1, null),
  ('b6b00000-0000-0000-0000-000000010204', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a2', 'b6b00000-0000-0000-0000-00000000e0c1', 'cheese',  0, 1, null),
  ('b6b00000-0000-0000-0000-000000010205', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a2', 'b6b00000-0000-0000-0000-00000000e240', '240g',    0, 1, '{"quantity":2,"unit":"meat"}'::jsonb),
  -- the historical line: unknown options -> rank 0 -> insertion order wins;
  -- ids DESCEND here so `id` order would reverse them (RED-safe either way).
  ('b6b00000-0000-0000-0000-000000010303', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a3', 'b6b00000-0000-0000-0000-0000000fffff', 'first',  0, 1, null),
  ('b6b00000-0000-0000-0000-000000010302', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a3', 'b6b00000-0000-0000-0000-0000000ffffe', 'second', 0, 1, null),
  ('b6b00000-0000-0000-0000-000000010301', 'b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-0000000000a1', 'b6b00000-0000-0000-0000-0000000000ab', 'b6b00000-0000-0000-0000-0000000100a3', 'b6b00000-0000-0000-0000-0000000ffffd', 'third',  0, 1, null);

-- Sanity: the MENU-ORDER-001 trigger stamped the dashboard ranks.
select is(
  (select array_agg(option_name_snapshot order by modifier_group_display_order_snapshot, modifier_option_display_order_snapshot, line_position)
     from order_item_modifiers where order_item_id = 'b6b00000-0000-0000-0000-0000000100a1'),
  array['240g','cheese','lettuce','tomato','onion'],
  '01 fixture: the trigger stamped dashboard ranks (authoritative order proven on the rows)');
select is(
  (select array_agg(option_name_snapshot order by created_at, id)
     from order_item_modifiers where order_item_id = 'b6b00000-0000-0000-0000-0000000100a1'),
  array['onion','tomato','lettuce','cheese','240g'],
  '02 fixture: created_at+id order is the reverse (the pre-fix shuffle is deterministic here)');

create temp table _p as
  select app.kitchen_dispatch_payload_initial('b6b00000-0000-0000-0000-0000000000a0',
                                              'b6b00000-0000-0000-0000-00000000010a') as res;
create temp table _r as
  select app.kitchen_dispatch_payload_round('b6b00000-0000-0000-0000-0000000000a0',
                                            'b6b00000-0000-0000-0000-00000000010a',
                                            'b6b00000-0000-0000-0000-00000000012a') as res;

-- helper: the modifier names of item #i in a payload, in emitted order
create or replace function pg_temp.mod_names(p jsonb, i int) returns text[] language sql as $$
  select coalesce(array_agg(m ->> 'name' order by ord), array[]::text[])
  from jsonb_array_elements(p -> 'items' -> i -> 'modifiers') with ordinality as t(m, ord);
$$;
-- helper: the detail's modifier names for ONE order item (the detail lists the
-- round item too, so items are addressed by id, never by index)
create or replace function pg_temp.detail_mod_names(p jsonb, item uuid) returns text[] language sql as $$
  select coalesce(array_agg(m ->> 'option_name_snapshot' order by ord), array[]::text[])
  from jsonb_array_elements(p -> 'items') it,
       jsonb_array_elements(it -> 'modifiers') with ordinality as t(m, ord)
  where (it ->> 'order_item_id')::uuid = item;
$$;

-- ===== G. item ordering unchanged (category rank first) ===================
select is((select array_agg(it ->> 'name' order by ord) from _p, jsonb_array_elements(res -> 'items') with ordinality as t(it, ord)),
  array['Classic Burger','Legacy Burger','Fries'],
  '03 G. initial items keep the canonical menu order (burgers before sides)');

-- ===== A. initial payload modifier order ===================================
select is((select pg_temp.mod_names(res, 0) from _p),
  array['240g','cheese','lettuce','tomato','onion'],
  '04 A. INITIAL payload modifiers are in dashboard order');

-- ===== B. round payload modifier order =====================================
select is((select array_agg(it ->> 'name' order by ord) from _r, jsonb_array_elements(res -> 'items') with ordinality as t(it, ord)),
  array['Classic Burger'],
  '05 B. the round payload scopes to the round''s own item');
select is((select pg_temp.mod_names(res, 0) from _r),
  array['240g','cheese','lettuce','tomato','onion'],
  '06 B. ROUND payload modifiers are in dashboard order');

-- ===== C. deterministic on repeated invocation =============================
select is(
  (select app.kitchen_dispatch_payload_initial('b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-00000000010a')),
  (select res from _p),
  '07 C. a second initial invocation is byte-identical');
select is(
  (select app.kitchen_dispatch_payload_round('b6b00000-0000-0000-0000-0000000000a0', 'b6b00000-0000-0000-0000-00000000010a', 'b6b00000-0000-0000-0000-00000000012a')),
  (select res from _r),
  '08 C. a second round invocation is byte-identical');

-- ===== D. dispatch order == pos_order_detail order =========================
create temp table _d as
  select app.pos_order_detail('b6b00000-0000-0000-0000-00000000009a',
                              'b6b00000-0000-0000-0000-0000000000d1',
                              'b6b00000-0000-0000-0000-00000000010a') as res;
select is((select res ->> 'ok' from _d), 'true', '09 D. the detail read succeeds');
select is(
  (select pg_temp.detail_mod_names(res, 'b6b00000-0000-0000-0000-0000000100a1') from _d),
  (select pg_temp.mod_names(res, 0) from _p),
  '10 D. pos_order_detail and the initial dispatch payload agree on the modifier order');
select is(
  (select pg_temp.detail_mod_names(res, 'b6b00000-0000-0000-0000-0000000100a1') from _d),
  array['240g','cheese','lettuce','tomato','onion'],
  '11 D. (and that order is the dashboard order)');

-- ===== E. no ordering keys leak into the payload ===========================
select is(
  (select array_agg(k order by k) from _p, jsonb_object_keys(res -> 'items' -> 0 -> 'modifiers' -> 0) k),
  array['name','prep','qty'],
  '12 E. a modifier WITH a contribution carries exactly {qty, name, prep}');
select is(
  (select array_agg(k order by k) from _p, jsonb_object_keys(res -> 'items' -> 0 -> 'modifiers' -> 1) k),
  array['name','qty'],
  '13 E. a modifier WITHOUT a contribution carries exactly {qty, name}');
select ok((select not (res::text ~ 'display_order|line_position|modifier_option_id') from _p),
  '14 E. no ordering/identity key is exposed');

-- ===== F. prep / meat projection unchanged ================================
select is((select res #> '{items,0,modifiers,0,prep}' from _p), '{"quantity":2,"unit":"meat"}'::jsonb,
  '15 F. the 240g meat contribution projects unchanged (per modifier unit)');
select is((select res #> '{items,0,prep}' from _p), '[{"name":"Bun","quantity":1,"unit":"pcs"}]'::jsonb,
  '16 F. the item prep projects unchanged (per unit)');
select is((select res #>> '{items,0,qty}' from _p), '2', '17 F. the line quantity is carried (2)');

-- ===== H. money-free ========================================================
select ok((select not (res::text ~* 'price|minor|amount|total|subtotal|tax') from _p),
  '18 H. the initial payload carries no money vocabulary');
select ok((select not (res::text ~* 'price|minor|amount|total|subtotal|tax') from _r),
  '19 H. the round payload carries no money vocabulary');

-- ===== I. historical rows (rank 0) fall back to insertion order ===========
select is(
  (select array_agg(modifier_group_display_order_snapshot || ':' || modifier_option_display_order_snapshot order by line_position)
     from order_item_modifiers where order_item_id = 'b6b00000-0000-0000-0000-0000000100a3'),
  array['0:0','0:0','0:0'],
  '20 I. unknown options were stamped rank 0 (historical shape)');
select is((select pg_temp.mod_names(res, 1) from _p),
  array['first','second','third'],
  '21 I. rank-0 modifiers print in INSERTION order (line_position), never by uuid');
select is(
  (select pg_temp.detail_mod_names(res, 'b6b00000-0000-0000-0000-0000000100a3') from _d),
  array['first','second','third'],
  '22 I. pos_order_detail agrees on the historical fallback order');

select * from finish();
rollback;
