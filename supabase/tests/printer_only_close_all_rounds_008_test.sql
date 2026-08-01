-- ============================================================================
-- PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008 - pgTAP.
-- ============================================================================
-- THE DEFECT, proven from the server outwards.
--
--   * `app.add_order_items` opens each amendment as a NEW service round at
--     status 'submitted' (20260722090000).
--   * `app.update_round_status` admits a KDS DEVICE ONLY for
--     submitted->accepted->preparing->ready; a POS may only do ready->served
--     (the 20260722090000 device matrix). On a one-device / printer-only site
--     NO KDS device exists, so NOTHING can ever walk that round forward.
--   * `app.order_rounds_all_served` is therefore permanently FALSE for any
--     order that received Add-items.
--   * 20260804090000 fixed the ORDER by SKIPPING the rounds gate on a
--     printer_only branch - deliberately "WITHOUT writing any round status".
--     The order completes and the ROUND ROW STAYS LIVE FOR EVER.
--
-- That dangling round is what this ticket closes: a live non-served row on a
-- TERMINAL order, which makes `app.order_rounds_all_served` false for a
-- COMPLETED order and leaves the fragment every round-aware read model sees.
--
-- TABLE OCCUPANCY is measured through the REAL read path (`app.pos_tables`).
-- It is DERIVED from live dine-in orders in (submitted..served) - there is no
-- stored occupancy flag and no table write anywhere. Completing the order IS
-- the release; these tests pin that so a later change cannot silently break it.
--
-- Fixtures/helpers are EXTRACTED VERBATIM from
-- supabase/tests/deferred_order_amendments_001_test.sql (itself extracted from
-- psc_001c_service_rounds_test.sql) so this suite exercises the identical
-- harness. Only the extra tables, orders and assertions below are new.
--
--   csubmit -> one line, item f9, qty 2 @ 500 => subtotal/grand 1000
--   cadd    -> one line, item f9, qty 1 @ 500 => delta 500
--   PIN sessions: ...ad001 manager, ...ad002 cashier, ...ad003 kitchen
--   Devices:      ...00d1 POS, ...00d2 KDS      Branch: ...000c03
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(34);


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

-- submit a dine-in (table T1) or takeaway one-line order: item f9 qty 2 @500.

create or replace function pg_temp.csubmit(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_type text) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.submit', 'target_entity', 'order',

    'payload', jsonb_build_object(

      'order_id', p_order, 'order_type', p_type,

      'table_id', case when p_type = 'dine_in' then 'c0000000-0000-0000-0000-00000000ba01' end,

      'currency_code', 'USD',

      'subtotal_minor', 1000, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 1000,

      'order_items', jsonb_build_array(jsonb_build_object(

        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 2,

        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));

$$;

create or replace function pg_temp.cstatus(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_to text) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.status', 'target_entity', 'order',

    'payload', jsonb_build_object('order_id', p_order, 'new_status', p_to))));

$$;

-- advance an ORDER submitted -> served with four kitchen ops.

create or replace function pg_temp.cserve(p_prefix text, p_order uuid) returns void language plpgsql as $$

begin

  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-a', p_order, 'accepted');

  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-b', p_order, 'preparing');

  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-c', p_order, 'ready');

  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-d', p_order, 'served');

end;

$$;

create or replace function pg_temp.cpay(p_op text, p_order uuid) returns jsonb language sql as $$

  select public.sync_push('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',

    jsonb_build_array(jsonb_build_object(

      'local_operation_id', p_op, 'operation_type', 'payment.create', 'target_entity', 'payment',

      'payload', jsonb_build_object('order_id', p_order, 'tender_type', 'card', 'amount_tendered_minor', 0))));

$$;

create or replace function pg_temp.cvoid(p_op text, p_order uuid) returns jsonb language sql as $$

  select public.sync_push('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1',

    jsonb_build_array(jsonb_build_object(

      'local_operation_id', p_op, 'operation_type', 'order.void', 'target_entity', 'order',

      'payload', jsonb_build_object('order_id', p_order, 'reason', 'customer left'))));

$$;

-- canonical items_add: one line, item f9 qty 1 @500 (delta 500).

create or replace function pg_temp.cadd(p_pin uuid, p_dev uuid, p_op text, p_order uuid) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',

    'target_id', p_order,

    'payload', jsonb_build_object(

      'order_id', p_order,

      'order_items', jsonb_build_array(jsonb_build_object(

        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,

        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));

$$;

-- adversarial items_add: independent payload order + (possibly malformed) target.

create or replace function pg_temp.cadd2(p_pin uuid, p_dev uuid, p_op text, p_payload_order uuid, p_target text) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',

    'target_id', p_target,

    'payload', jsonb_build_object(

      'order_id', p_payload_order,

      'order_items', jsonb_build_array(jsonb_build_object(

        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,

        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));

$$;

-- items_add with a CUSTOM item list.

create or replace function pg_temp.caddx(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_items jsonb) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',

    'target_id', p_order,

    'payload', jsonb_build_object('order_id', p_order, 'order_items', p_items))));

$$;

-- canonical round_status.

create or replace function pg_temp.crst(p_pin uuid, p_dev uuid, p_op text, p_round uuid, p_to text) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.round_status', 'target_entity', 'order_service_round',

    'target_id', p_round,

    'payload', jsonb_build_object('round_id', p_round, 'new_status', p_to))));

$$;

-- adversarial round_status.

create or replace function pg_temp.crst2(p_pin uuid, p_dev uuid, p_op text, p_payload_round uuid, p_target text, p_to text) returns jsonb language sql as $$

  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(

    'local_operation_id', p_op, 'operation_type', 'order.round_status', 'target_entity', 'order_service_round',

    'target_id', p_target,

    'payload', jsonb_build_object('round_id', p_payload_round, 'new_status', p_to))));

$$;





-- ===== base flow fixtures ====================================================

-- Open ONE shift + drawer on POS-1 (cashier) so payments are possible.

select public.sync_push('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',

  jsonb_build_array(jsonb_build_object(

    'local_operation_id', 'sh-1', 'operation_type', 'shift.open', 'target_entity', 'shift',

    'payload', jsonb_build_object(

      'shift_id', 'c0000000-0000-0000-0000-00000000fa01',

      'cash_drawer_session_id', 'c0000000-0000-0000-0000-00000000fb01',

      'opening_float_minor', 0))));


-- ===== 008 additions to the extracted harness ================================
-- One table per dine-in scenario, so a release assertion is unambiguous (the
-- platform deliberately allows several active orders on one table).
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('c0000000-0000-0000-0000-00000000ba02', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'T2'),
  ('c0000000-0000-0000-0000-00000000ba03', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'T3'),
  ('c0000000-0000-0000-0000-00000000ba04', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'T4'),
  ('c0000000-0000-0000-0000-00000000ba05', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'T5');

-- An ORG OWNER (rank 4) for the setter. The extracted harness only carries
-- manager, cashier and kitchen memberships.
insert into app_users (id, email) values
  ('c0000000-0000-0000-0000-0000000ae004', 'rc-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('c0000000-0000-0000-0000-0000000ab004', 'c0000000-0000-0000-0000-0000000ae004', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'org_owner', '{}'::jsonb);

-- A dine-in submit onto a CHOSEN table (the extracted csubmit always uses T1).
create or replace function pg_temp.csubmit_at(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_table uuid) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', p_order, 'order_type', 'dine_in', 'table_id', p_table,
      'currency_code', 'USD',
      'subtotal_minor', 1000, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 1000,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 2,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));
$$;

-- active_order_count for ONE table, read through the REAL POS RPC (not a
-- hand-rolled predicate that could drift from what the app actually sees).
create or replace function pg_temp.coccupancy(p_table uuid) returns integer language sql as $$
  select coalesce((
    select (t ->> 'active_order_count')::int
      from jsonb_array_elements(
        app.pos_tables('c0000000-0000-0000-0000-0000000ad002',
                       'c0000000-0000-0000-0000-0000000000d1') -> 'tables') as t
     where (t ->> 'id')::uuid = p_table), -1);
$$;

-- live rounds of an order that are NOT terminal for app.order_rounds_all_served.
create or replace function pg_temp.clive(p_order uuid) returns integer language sql as $$
  select count(*)::int from public.order_service_rounds
   where order_id = p_order and deleted_at is null and status <> 'served';
$$;

-- ===== 008 orders ============================================================
select pg_temp.csubmit_at('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p1-s', 'c0000000-0000-0000-0000-0000000c8001', 'c0000000-0000-0000-0000-00000000ba02');
select pg_temp.csubmit_at('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p2-s', 'c0000000-0000-0000-0000-0000000c8002', 'c0000000-0000-0000-0000-00000000ba03');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p3-s', 'c0000000-0000-0000-0000-0000000c8003', 'takeaway');
select pg_temp.csubmit_at('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p4-s', 'c0000000-0000-0000-0000-0000000c8004', 'c0000000-0000-0000-0000-00000000ba04');
select pg_temp.csubmit_at('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p5-s', 'c0000000-0000-0000-0000-0000000c8005', 'c0000000-0000-0000-0000-00000000ba05');

-- Every 008 order takes one addition round; p2 takes TWO.
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p1-r2', 'c0000000-0000-0000-0000-0000000c8001');
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p2-r2', 'c0000000-0000-0000-0000-0000000c8002');
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p2-r3', 'c0000000-0000-0000-0000-0000000c8002');
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p3-r2', 'c0000000-0000-0000-0000-0000000c8003');
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p4-r2', 'c0000000-0000-0000-0000-0000000c8004');
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'p5-r2', 'c0000000-0000-0000-0000-0000000c8005');

-- Pay + serve everything except p5 (deliberately unpaid).
select pg_temp.cpay('p1-pay', 'c0000000-0000-0000-0000-0000000c8001');
select pg_temp.cpay('p2-pay', 'c0000000-0000-0000-0000-0000000c8002');
select pg_temp.cpay('p3-pay', 'c0000000-0000-0000-0000-0000000c8003');
select pg_temp.cpay('p4-pay', 'c0000000-0000-0000-0000-0000000c8004');
select pg_temp.cserve('p1-sv', 'c0000000-0000-0000-0000-0000000c8001');
select pg_temp.cserve('p2-sv', 'c0000000-0000-0000-0000-0000000c8002');
select pg_temp.cserve('p3-sv', 'c0000000-0000-0000-0000-0000000c8003');
select pg_temp.cserve('p4-sv', 'c0000000-0000-0000-0000-0000000c8004');
select pg_temp.cserve('p5-sv', 'c0000000-0000-0000-0000-0000000c8005');

-- ===========================================================================
-- (1-3) THE FIXTURE IS THE DEFECT: paid, served, table occupied, round LIVE.
-- ===========================================================================
update branches set kitchen_workflow_mode = 'printer_only'
  where id = 'c0000000-0000-0000-0000-000000000c03';

select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8001'), 1,
  '1. fixture: the dine-in order carries exactly ONE live (non-served) round');
select is((select status from orders where id = 'c0000000-0000-0000-0000-0000000c8001'), 'served',
  '2. fixture: the order is served and fully paid');
select is(pg_temp.coccupancy('c0000000-0000-0000-0000-00000000ba02'), 1,
  '3. fixture: T2 reads as OCCUPIED through the real POS table RPC');

-- ===========================================================================
-- (4-9) DINE-IN, ONE ADDITION ROUND - the reported case.
-- ===========================================================================
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'p1-done', 'c0000000-0000-0000-0000-0000000c8001', 'completed') -> 'results' -> 0 ->> 'error'),
  null, '4. printer_only: the manual completion succeeds');
select is((select status from orders where id = 'c0000000-0000-0000-0000-0000000c8001'), 'completed',
  '5. the order is authoritatively terminal');
select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8001'), 0,
  '6. EVERY round reached the terminal status the completion predicate expects');
select ok(app.order_rounds_all_served('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-0000000c8001'),
  '7. app.order_rounds_all_served is now TRUE for the completed order');
select ok(
  (select bool_and(ready_at is not null) from order_service_rounds
    where order_id = 'c0000000-0000-0000-0000-0000000c8001' and deleted_at is null),
  '8. the served rounds carry the ready_at the table CHECK constraint requires');
select is(pg_temp.coccupancy('c0000000-0000-0000-0000-00000000ba02'), 0,
  '9. T2 is RELEASED - occupancy is derived from the order, so completing it frees the table');

-- ===========================================================================
-- (10-12) HISTORY, MONEY AND ITEMS SURVIVE.
-- ===========================================================================
select is((select count(*)::int from order_items where order_id = 'c0000000-0000-0000-0000-0000000c8001' and deleted_at is null),
  2, '10. both the original line and the ADDED line remain in history');
select is((select count(*)::int from order_service_rounds where order_id = 'c0000000-0000-0000-0000-0000000c8001' and deleted_at is null),
  1, '11. the round row is CLOSED, never deleted - service-round history is intact');
select is((select count(*)::int from payments where order_id = 'c0000000-0000-0000-0000-0000000c8001' and status = 'completed' and deleted_at is null),
  1, '12. the payment is untouched');

-- ===========================================================================
-- (13-16) TWO ADDITION ROUNDS close in ONE completion.
-- ===========================================================================
select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8002'), 2,
  '13. fixture: TWO live rounds (round 2 and round 3)');
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'p2-done', 'c0000000-0000-0000-0000-0000000c8002', 'completed') -> 'results' -> 0 ->> 'error'),
  null, '14. the completion succeeds with two rounds outstanding');
select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8002'), 0,
  '15. BOTH rounds are terminal - not just the first');
select is(pg_temp.coccupancy('c0000000-0000-0000-0000-00000000ba03'), 0,
  '16. T3 is released');

-- ===========================================================================
-- (17-19) TAKEAWAY leaves no fragment.
-- ===========================================================================
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'p3-done', 'c0000000-0000-0000-0000-0000000c8003', 'completed') -> 'results' -> 0 ->> 'error'),
  null, '17. takeaway completes');
select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8003'), 0,
  '18. the takeaway addition round is terminal too');
select is((select count(*)::int from orders where id = 'c0000000-0000-0000-0000-0000000c8003' and deleted_at is null),
  1, '19. the takeaway order remains in history (never deleted)');

-- ===========================================================================
-- (20-22) IDEMPOTENCY - pressing finish again changes nothing.
-- ===========================================================================
create temp table p1_after as
  select id, status, revision, ready_at from order_service_rounds
   where order_id = 'c0000000-0000-0000-0000-0000000c8001';
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'p1-done-2', 'c0000000-0000-0000-0000-0000000c8001', 'completed') -> 'results' -> 0 ->> 'error'),
  'invalid_transition', '20. a repeat completion is refused - the order is already terminal');
select ok(
  not exists (select 1 from order_service_rounds r join p1_after a on a.id = r.id
               where r.status is distinct from a.status
                  or r.revision is distinct from a.revision
                  or r.ready_at is distinct from a.ready_at),
  '21. the repeat changed NO round row (status, revision and ready_at all identical)');
select is((select count(*)::int from payments where order_id = 'c0000000-0000-0000-0000-0000000c8001' and deleted_at is null),
  1, '22. and it created no second payment');

-- ===========================================================================
-- (23-25) UNPAID IS STILL REFUSED - the money gate is untouched, and a refused
--         completion must not close rounds either (no partial work).
-- ===========================================================================
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'p5-done', 'c0000000-0000-0000-0000-0000000c8005', 'completed') -> 'results' -> 0 ->> 'error'),
  'order_not_paid', '23. an UNPAID order with a live round is still refused');
select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8005'), 1,
  '24. ATOMICITY: the refusal closed NO round - all of it or none of it');
select is(pg_temp.coccupancy('c0000000-0000-0000-0000-00000000ba05'), 1,
  '25. and T5 stays occupied');

-- ===========================================================================
-- (26-28) DEDICATED KDS IS UNCHANGED. Same shape, mode flipped back.
-- ===========================================================================
update branches set kitchen_workflow_mode = 'kds'
  where id = 'c0000000-0000-0000-0000-000000000c03';
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'p4-done', 'c0000000-0000-0000-0000-0000000c8004', 'completed') -> 'results' -> 0 ->> 'error'),
  'rounds_not_served', '26. kds mode: completion is still refused with rounds_not_served');
select is(pg_temp.clive('c0000000-0000-0000-0000-0000000c8004'), 1,
  '27. kds mode: the round was NOT closed by the POS - the KDS still owns it');
select is(pg_temp.coccupancy('c0000000-0000-0000-0000-00000000ba04'), 1,
  '28. kds mode: T4 stays occupied');

-- ===========================================================================
-- (29-34) THE MODE SETTER. Without it printer_only is unreachable in
--         production: the column is `not null default 'kds'` and NOTHING in the
--         shipped migrations ever writes it (only pgTAP fixtures do), which is
--         why the whole printer-only path has been dormant.
-- ===========================================================================
select has_function('app', 'set_kitchen_workflow_mode', array['uuid','uuid','uuid','text'],
  '29. app.set_kitchen_workflow_mode exists');

set local app.current_app_user_id = 'c0000000-0000-0000-0000-0000000ae004';
select is(
  (app.set_kitchen_workflow_mode('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'printer_only') ->> 'ok'),
  'true', '30. an org owner may set printer_only');
select ok(
  (select kitchen_workflow_mode = 'printer_only' and kitchen_workflow_mode_revision > 1
     from branches where id = 'c0000000-0000-0000-0000-000000000c03'),
  '31. the mode changed AND the revision was bumped (stale client caches are rejectable)');
select is(
  (app.set_kitchen_workflow_mode('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'both') ->> 'error'),
  'invalid_mode', '32. an unknown mode is refused');
select is(
  (app.set_kitchen_workflow_mode('f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'printer_only') ->> 'error'),
  'not_found', '33. a CROSS-TENANT branch is invisible (no scope leak, no mutation)');

set local app.current_app_user_id = 'c0000000-0000-0000-0000-0000000ae002';
select is(
  (app.set_kitchen_workflow_mode('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kds') ->> 'error'),
  'permission_denied', '34. a CASHIER may not change the branch workflow mode');

select * from finish();
rollback;
