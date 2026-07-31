-- ============================================================================
-- MONEY-PRICING-FORMULA-002A - pgTAP: configured-unit line totals across
--                              submit_order, add_order_items and apply_discount.
-- ============================================================================
-- The authoritative money contract (docs/MONEY_AND_TAX_SPEC.md Â§9:157, worked
-- example Â§9.1:179) prices a line as
--
--     quantity * (unit_price_minor + SUM(delta * modifier_qty)) - line_discount
--
-- i.e. a line is N identical FULLY CONFIGURED items and the modifier surcharge
-- rides inside the per-unit amount. The shipped functions computed
-- `quantity * unit + SUM(...)`, charging the surcharge once per LINE. The two
-- agree at quantity 1 and diverge by `SUM(...) * (quantity - 1)` above it.
--
-- THREE behaviours are pinned here:
--   * submit_order and add_order_items must use the configured-unit rule;
--   * apply_discount must be PRICING-EPOCH AGNOSTIC - it recovers a line's
--     pre-discount base from the stored authoritative row
--     (line_total_minor + line_discount_minor) instead of recomputing it from
--     components, so it neither destroys a new line's surcharge nor reprices a
--     historical line;
--   * historical stored money is never rewritten.
--
-- Fixtures/helpers are EXTRACTED VERBATIM from
-- supabase/tests/deferred_order_amendments_001_test.sql so this suite exercises
-- the identical harness; only the assertions are new. Fixtures are inserted as
-- the BYPASSRLS connection role (RF-056/RF-057 convention). Every operation is
-- driven through the REAL public.sync_push, never by calling app.* directly.
--
-- Money reference used throughout: item f9 has base 500. A "paid modifier" is
-- 300 per unit unless stated. So a qty-2 configured line is
--   corrected: 2 * (500 + 300) = 1600      old (wrong): 2 * 500 + 300 = 1300
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(45);
insert into organizations (id, name, slug, default_currency) values

  ('c0000000-0000-0000-0000-000000000c01', 'Org RC', 'rc-a', 'USD'),

  ('f0000000-0000-0000-0000-000000000c01', 'Org RB', 'rc-b', 'USD');

insert into restaurants (id, organization_id, name) values

  ('c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c01', 'Rest RC'),

  ('f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c01', 'Rest RB');

insert into branches (id, organization_id, restaurant_id, name) values

  ('c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'Branch RC'),

  ('f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'Branch RB');

insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values

  ('c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'pos'),

  ('c0000000-0000-0000-0000-0000000000d2', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kds'),

  ('c0000000-0000-0000-0000-0000000000d3', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kds'),

  ('c0000000-0000-0000-0000-0000000000d4', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'pos'),

  ('f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'pos');

insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values

  ('c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d1', 'active'),

  ('c0000000-0000-0000-0000-0000000000a2', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d2', 'active'),

  ('c0000000-0000-0000-0000-0000000000a3', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d3', 'active'),

  ('c0000000-0000-0000-0000-0000000000a4', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d4', 'active'),

  ('f0000000-0000-0000-0000-0000000000a1', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000000d1', 'active');

insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values

  ('c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000000a1'),

  ('c0000000-0000-0000-0000-0000000000e2', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d2', 'c0000000-0000-0000-0000-0000000000a2'),

  ('c0000000-0000-0000-0000-0000000000e3', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d3', 'c0000000-0000-0000-0000-0000000000a3'),

  ('c0000000-0000-0000-0000-0000000000e4', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d4', 'c0000000-0000-0000-0000-0000000000a4'),

  ('f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-0000000000a1');

insert into app_users (id, email) values

  ('c0000000-0000-0000-0000-0000000ae001', 'rc-mgr@example.test'),

  ('c0000000-0000-0000-0000-0000000ae002', 'rc-cash@example.test'),

  ('c0000000-0000-0000-0000-0000000ae003', 'rc-kitchen@example.test'),

  ('f0000000-0000-0000-0000-0000000be001', 'rb-mgr@example.test');

insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values

  ('c0000000-0000-0000-0000-0000000ab001', 'c0000000-0000-0000-0000-0000000ae001', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'manager', '{}'::jsonb),

  ('c0000000-0000-0000-0000-0000000ab002', 'c0000000-0000-0000-0000-0000000ae002', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'cashier', '{}'::jsonb),

  ('c0000000-0000-0000-0000-0000000ab003', 'c0000000-0000-0000-0000-0000000ae003', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kitchen_staff', '{}'::jsonb),

  ('f0000000-0000-0000-0000-0000000bb001', 'f0000000-0000-0000-0000-0000000be001', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'manager', '{}'::jsonb);

insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values

  ('c0000000-0000-0000-0000-0000000ac001', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000ae001', 'c0000000-0000-0000-0000-0000000ab001'),

  ('c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000ae002', 'c0000000-0000-0000-0000-0000000ab002'),

  ('c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000ae003', 'c0000000-0000-0000-0000-0000000ab003'),

  ('f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000be001', 'f0000000-0000-0000-0000-0000000bb001');

-- PIN sessions: mgr/cashier/kitchen on POS-1; kitchen/mgr/cashier on KDS-1;

-- kitchen on KDS-2; cashier on POS-2; Org B mgr on B's POS.

insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values

  ('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000ac001', 'c0000000-0000-0000-0000-0000000ab001', now() + interval '1 hour'),

  ('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),

  ('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e2', 'c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),

  ('c0000000-0000-0000-0000-0000000ad004', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e2', 'c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),

  ('c0000000-0000-0000-0000-0000000ad005', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),

  ('c0000000-0000-0000-0000-0000000ad007', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e3', 'c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),

  ('c0000000-0000-0000-0000-0000000ad009', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e4', 'c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),

  ('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-0000000bb001', now() + interval '1 hour');



-- Menu + floor fixtures for org A.

insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values

  ('c0000000-0000-0000-0000-0000000000c9', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', null, 'Fixture Food', 1);

insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values

  ('c0000000-0000-0000-0000-0000000000f9', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', null, 'c0000000-0000-0000-0000-0000000000c9', 'Item', 500, 'USD', 1),

  ('c0000000-0000-0000-0000-0000000000f8', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', null, 'c0000000-0000-0000-0000-0000000000c9', 'SoldOut', 400, 'USD', 2);

insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values

  ('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000f8', 'unavailable', 'sold_out');

insert into tables (id, organization_id, restaurant_id, branch_id, label) values

  ('c0000000-0000-0000-0000-00000000ba01', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'T1');
-- ---- helpers ---------------------------------------------------------------
-- Submit an order with an EXPLICIT item array and client subtotal, so each test
-- states its own money. The server recomputes and REFUSES a mismatch, which is
-- itself one of the contracts under test.
create or replace function pg_temp.msub(p_op text, p_order uuid, p_items jsonb, p_subtotal bigint)
  returns jsonb language sql as $$
  select public.sync_push(
    'c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'order.submit', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', p_order, 'order_type', 'takeaway', 'currency_code', 'USD',
        'subtotal_minor', p_subtotal, 'discount_total_minor', 0,
        'tax_total_minor', 0, 'grand_total_minor', p_subtotal,
        'order_items', p_items))));
$$;

-- ONE configured line: base 500 x p_qty, one modifier at p_delta x p_mqty.
create or replace function pg_temp.mline(p_qty int, p_delta bigint, p_mqty int)
  returns jsonb language sql immutable as $$
  select jsonb_build_array(jsonb_build_object(
    'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9',
    'quantity', p_qty,
    'unit_price_minor_snapshot', 500,
    'menu_item_name_snapshot', 'Item',
    'modifiers', jsonb_build_array(jsonb_build_object(
      'modifier_option_id', 'c0000000-0000-0000-0000-00000000e001',
      'option_name_snapshot', 'Upgrade',
      'price_minor_snapshot', p_delta,
      'quantity', p_mqty))));
$$;

-- Add a configured round to an existing order.
create or replace function pg_temp.madd(p_op text, p_order uuid, p_items jsonb)
  returns jsonb language sql as $$
  select public.sync_push(
    'c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',
      'target_id', p_order,
      'payload', jsonb_build_object('order_id', p_order, 'order_items', p_items))));
$$;

-- Item-scope discount, driven by the MANAGER pin session.
create or replace function pg_temp.mdisc(p_op text, p_order uuid, p_item uuid, p_type text, p_value bigint)
  returns jsonb language sql as $$
  select public.sync_push(
    'c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'order.discount', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', p_order, 'scope', 'order_item', 'order_item_id', p_item,
        'discount_type', p_type, 'value', p_value, 'reason', 'test'))));
$$;

-- The single stored line of an order.
create or replace function pg_temp.mline_total(p_order uuid) returns bigint language sql as $$
  select line_total_minor from public.order_items where order_id = p_order order by created_at, id limit 1;
$$;
create or replace function pg_temp.mline_id(p_order uuid) returns uuid language sql as $$
  select id from public.order_items where order_id = p_order order by created_at, id limit 1;
$$;
create or replace function pg_temp.msub_of(p_order uuid) returns bigint language sql as $$
  select subtotal_minor from public.orders where id = p_order;
$$;

-- ---- A. submit_order uses the CONFIGURED-UNIT rule -------------------------

select is((pg_temp.msub('mf-a1', 'c0000000-0000-0000-0000-00000000f001', pg_temp.mline(1, 300, 1), 800)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A1 qty 1 paid modifier: 1*(500+300)=800 accepted');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f001'), 800::bigint,
          'A1b stored line total is 800');

select is((pg_temp.msub('mf-a2', 'c0000000-0000-0000-0000-00000000f002', pg_temp.mline(2, 300, 1), 1600)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A2 qty 2 paid modifier: 2*(500+300)=1600 accepted');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f002'), 1600::bigint,
          'A2b stored line total is 1600, NOT the old 1300');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f002'), 1600::bigint,
          'A2c order subtotal is 1600');

select is((pg_temp.msub('mf-a3', 'c0000000-0000-0000-0000-00000000f003', pg_temp.mline(3, 300, 1), 2400)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A3 qty 3 paid modifier: 3*(500+300)=2400 accepted');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f003'), 2400::bigint,
          'A3b stored line total is 2400');

select is((pg_temp.msub('mf-a4', 'c0000000-0000-0000-0000-00000000f004', pg_temp.mline(3, 100, 2), 2100)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A4 modifier quantity 2 at item qty 3: 3*(500+100*2)=2100 accepted');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f004'), 2100::bigint,
          'A4b modifier quantity is per ITEM UNIT');

select is((pg_temp.msub('mf-a5', 'c0000000-0000-0000-0000-00000000f005', pg_temp.mline(2, 0, 1), 1000)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A5 a FREE modifier at qty 2 is unchanged: 1000');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f005'), 1000::bigint,
          'A5b free modifier stores 1000');

-- A plain line with NO modifiers is identical under both rules.
select is((pg_temp.msub('mf-a6', 'c0000000-0000-0000-0000-00000000f006',
             jsonb_build_array(jsonb_build_object(
               'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 2,
               'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item')), 1000)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A6 an unmodified line is unaffected by the correction');

-- Two configured lines aggregate.
select is((pg_temp.msub('mf-a7', 'c0000000-0000-0000-0000-00000000f007',
             pg_temp.mline(2, 300, 1) || pg_temp.mline(1, 700, 1), 2800)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'A7 two configured lines: 1600 + 1200 = 2800 accepted');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f007'), 2800::bigint,
          'A7b subtotal aggregates both configured lines');

-- ---- B. the OLD subtotal is now REFUSED ------------------------------------
select is((pg_temp.msub('mf-b1', 'c0000000-0000-0000-0000-00000000f011', pg_temp.mline(2, 300, 1), 1300)
           -> 'results' -> 0 ->> 'status'), 'rejected',
          'B1 the OLD per-line subtotal (1300) is refused after the correction');
select is((select count(*) from public.orders where id = 'c0000000-0000-0000-0000-00000000f011'), 0::bigint,
          'B1b nothing was written for the refused submit');

-- ---- C. add_order_items uses the SAME rule ---------------------------------
select is((pg_temp.msub('mf-c0', 'c0000000-0000-0000-0000-00000000f021', pg_temp.mline(1, 300, 1), 800)
           -> 'results' -> 0 ->> 'status'), 'applied', 'C0 seed order at 800');
select is((pg_temp.madd('mf-c1', 'c0000000-0000-0000-0000-00000000f021', pg_temp.mline(2, 300, 1))
           -> 'results' -> 0 ->> 'status'), 'applied',
          'C1 a configured round of qty 2 is added');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f021'), 2400::bigint,
          'C1b order subtotal 800 + 1600 = 2400 (the round uses the configured-unit rule)');
select is((select line_total_minor from public.order_items
            where order_id = 'c0000000-0000-0000-0000-00000000f021' and service_round_id is not null),
          1600::bigint, 'C1c the added line stores 1600');

-- an exact replay adds nothing
select is((pg_temp.madd('mf-c1', 'c0000000-0000-0000-0000-00000000f021', pg_temp.mline(2, 300, 1))
           -> 'results' -> 0 ->> 'idempotency_replay'), 'true',
          'C2 an exact replay is flagged idempotency_replay');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f021'), 2400::bigint,
          'C2b the replay did not double the surcharge');

-- ---- D. apply_discount on a CORRECTED (formula-B) line ---------------------
select is((pg_temp.msub('mf-d0', 'c0000000-0000-0000-0000-00000000f031', pg_temp.mline(2, 300, 1), 1600)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D0 seed a corrected 1600 line');
select is((pg_temp.mdisc('mf-d1', 'c0000000-0000-0000-0000-00000000f031',
             pg_temp.mline_id('c0000000-0000-0000-0000-00000000f031'), 'fixed', 100)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D1 a 100 item discount applies');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f031'), 1500::bigint,
          'D1b 1600 - 100 = 1500: the discount base was the STORED 1600, not a recomputed 1300');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f031'), 1500::bigint,
          'D1c the order subtotal follows');

-- percentage discount off the corrected base
select is((pg_temp.msub('mf-d2', 'c0000000-0000-0000-0000-00000000f032', pg_temp.mline(2, 300, 1), 1600)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D2 seed another corrected 1600 line');
select is((pg_temp.mdisc('mf-d3', 'c0000000-0000-0000-0000-00000000f032',
             pg_temp.mline_id('c0000000-0000-0000-0000-00000000f032'), 'percentage', 1000)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D3 a 10% item discount applies');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f032'), 1440::bigint,
          'D3b 10% of the CORRECTED 1600 is 160 -> 1440 (10% of 1300 would be 1170)');

-- re-discount must recover the ORIGINAL pre-discount base
select is((pg_temp.mdisc('mf-d4', 'c0000000-0000-0000-0000-00000000f032',
             pg_temp.mline_id('c0000000-0000-0000-0000-00000000f032'), 'fixed', 200)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D4 the discount is replaced');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f032'), 1400::bigint,
          'D4b the replacement recovered the ORIGINAL 1600 base (1600-200), not 1440-200');

-- full comp zeroes the line from the corrected base
select is((pg_temp.msub('mf-d5', 'c0000000-0000-0000-0000-00000000f033', pg_temp.mline(2, 300, 1), 1600)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D5 seed a corrected line for comp');
select is((pg_temp.mdisc('mf-d6', 'c0000000-0000-0000-0000-00000000f033',
             pg_temp.mline_id('c0000000-0000-0000-0000-00000000f033'), 'percentage', 10000)
           -> 'results' -> 0 ->> 'status'), 'applied', 'D6 a manager full comp applies');
select is(pg_temp.mline_total('c0000000-0000-0000-0000-00000000f033'), 0::bigint,
          'D6b the comp zeroes the line');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f033'), 0::bigint,
          'D6c and the order subtotal');

-- ---- E. apply_discount on a HISTORICAL (formula-A) line --------------------
-- A line stored BEFORE the correction: base 500 x qty 2 with a 300 modifier was
-- stored as 1300 under the old rule. Applying a discount must use 1300 - the
-- line must NOT be repriced upward to the corrected 1600.
insert into public.orders (id, organization_id, restaurant_id, branch_id, device_id, order_type,
                           status, currency_code, subtotal_minor, discount_total_minor,
                           tax_total_minor, grand_total_minor, local_operation_id,
                           pin_session_id, opened_by_employee_profile_id, resolved_membership_id)
  values ('c0000000-0000-0000-0000-00000000f041', 'c0000000-0000-0000-0000-000000000c01',
          'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03',
          'c0000000-0000-0000-0000-0000000000d1', 'takeaway', 'submitted', 'USD',
          1300, 0, 0, 1300, 'hist-seed-1',
          'c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000ac002',
          'c0000000-0000-0000-0000-0000000ab002');
insert into public.order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
                                status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
                                line_discount_minor, line_total_minor)
  values ('c0000000-0000-0000-0000-00000000f042', 'c0000000-0000-0000-0000-000000000c01',
          'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03',
          'c0000000-0000-0000-0000-00000000f041', 'c0000000-0000-0000-0000-0000000000f9',
          'pending', 2, 'Item', 500, 0, 1300);
insert into public.order_item_modifiers (id, organization_id, restaurant_id, branch_id, order_item_id,
                                         modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity)
  values ('c0000000-0000-0000-0000-00000000f043', 'c0000000-0000-0000-0000-000000000c01',
          'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03',
          'c0000000-0000-0000-0000-00000000f042', 'c0000000-0000-0000-0000-00000000e001',
          'Upgrade', 300, 1);

select is((pg_temp.mdisc('mf-e1', 'c0000000-0000-0000-0000-00000000f041',
             'c0000000-0000-0000-0000-00000000f042', 'fixed', 100)
           -> 'results' -> 0 ->> 'status'), 'applied', 'E1 a discount applies to a HISTORICAL line');
select is((select line_total_minor from public.order_items where id = 'c0000000-0000-0000-0000-00000000f042'),
          1200::bigint,
          'E1b the historical base stayed 1300 (1300-100); it was NOT repriced upward to 1600');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f041'), 1200::bigint,
          'E1c historical money is preserved through the discount');

-- ---- F. MIXED historical + corrected order ---------------------------------
-- Adding a round to the historical order prices ONLY the new round under the
-- corrected rule; the historical line keeps its stored amount.
select is((pg_temp.madd('mf-f1', 'c0000000-0000-0000-0000-00000000f041', pg_temp.mline(2, 300, 1))
           -> 'results' -> 0 ->> 'status'), 'applied',
          'F1 a new round is added to a historical order');
select is(pg_temp.msub_of('c0000000-0000-0000-0000-00000000f041'), 2800::bigint,
          'F1b 1200 (historical, discounted) + 1600 (corrected round) = 2800');
select is((select line_total_minor from public.order_items where id = 'c0000000-0000-0000-0000-00000000f042'),
          1200::bigint, 'F1c the historical line is STILL untouched');

-- ---- G. snapshot trust + security posture ----------------------------------
-- A price snapshot that exists in no catalogue is still trusted (D-008).
select is((pg_temp.msub('mf-g1', 'c0000000-0000-0000-0000-00000000f051', pg_temp.mline(2, 1234, 1), 3468)
           -> 'results' -> 0 ->> 'status'), 'applied',
          'G1 a non-catalogue modifier snapshot is trusted: 2*(500+1234)=3468');

select is((select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname = 'apply_discount'), true,
          'G2 apply_discount is still SECURITY DEFINER');
select is((select p.proconfig::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname = 'apply_discount'), '{"search_path=\"\""}',
          'G3 apply_discount still pins an empty search_path');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname in ('submit_order','add_order_items','apply_discount')),
          3::bigint, 'G4 exactly one definition of each re-emitted function remains');

select finish();
rollback;