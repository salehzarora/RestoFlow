-- ============================================================================
-- DEFERRED-ORDER-AMENDMENTS-001 - pgTAP: takeaway amendments + mode-aware
--                                  manual completion.
-- ============================================================================
-- Proves the TWO approved changes in
-- 20260804090000_deferred_order_amendments_001_takeaway_and_mode_close.sql,
-- driven through the REAL public.sync_push operations (never by calling the
-- inner app.* functions directly):
--
--   * app.add_order_items now accepts order_type IN ('dine_in','takeaway').
--     A takeaway amendment succeeds, keeps the SAME parent order (id, code,
--     takeaway type, no table), creates exactly ONE round whose items are
--     DELTA-ONLY, moves totals and revision exactly once, audits once, and
--     replays idempotently under the same local_operation_id. dine_in is
--     unchanged; paid / settled / terminal / unsupported-type orders keep their
--     EXISTING typed refusals.
--
--   * app.apply_order_status_transition's manual-completion rounds gate now
--     consults the authoritative branches.kitchen_workflow_mode, FAIL-CLOSED to
--     'kds'. printer_only skips the KDS service-round gate WITHOUT writing any
--     round status; kds keeps `rounds_not_served`. The D-025 payment gate and
--     app.try_auto_complete_order are untouched.
--
-- The tenancy / device / PIN-session / menu / shift fixtures, the submitted
-- orders and the pg_temp helpers below are EXTRACTED VERBATIM from
-- supabase/tests/psc_001c_service_rounds_test.sql so this suite exercises the
-- identical harness. Only the assertions are new.
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
--
-- Helper reminder (from the extracted block):
--   csubmit -> one line, menu item f9, qty 2 @ 500 => subtotal/grand 1000, rev 1
--   cadd    -> one line, menu item f9, qty 1 @ 500 => delta 500
--   PIN sessions: ...ad001 manager, ...ad002 cashier, ...ad003 kitchen
--   Devices:      ...00d1 POS, ...00d2 KDS      Branch: ...000c03
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(32);


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

-- Orders (dine-in unless stated): o1 (main additions target), o2 (served-state

-- additions), o3 takeaway, o4 (voided-eligibility), o5 (completed-eligibility),

-- o6 (paid-open), o8 (zero-round completion regression), oR1/oR2/oR3 (races),

-- oV (void integration).

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o1', 'c0000000-0000-0000-0000-00000000a001', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o2', 'c0000000-0000-0000-0000-00000000a002', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o3', 'c0000000-0000-0000-0000-00000000a003', 'takeaway');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o4', 'c0000000-0000-0000-0000-00000000a004', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o5', 'c0000000-0000-0000-0000-00000000a005', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o6', 'c0000000-0000-0000-0000-00000000a006', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o8', 'c0000000-0000-0000-0000-00000000a008', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-r1', 'c0000000-0000-0000-0000-00000000a0b1', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-r2', 'c0000000-0000-0000-0000-00000000a0b2', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-r3', 'c0000000-0000-0000-0000-00000000a0b3', 'dine_in');

select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-ov', 'c0000000-0000-0000-0000-00000000a0c1', 'dine_in');


-- ===========================================================================
-- (1-10) TAKEAWAY additions: the widened order-type gate.
--        o3 (...a003) is the TAKEAWAY fixture order and has NO table.
-- ===========================================================================
create temp table tw1 as
  select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
                      'doa-tw1', 'c0000000-0000-0000-0000-00000000a003') as r;
select is(
  (select r -> 'results' -> 0 ->> 'error' from tw1),
  null, '1. a TAKEAWAY order ACCEPTS an addition (the order-type gate is widened)');
select is(
  (select r -> 'results' -> 0 ->> 'status' from tw1),
  'applied', '2. the takeaway addition is APPLIED (a real durable write, not a soft ok)');
select is(
  (select (r -> 'results' -> 0 ->> 'round_number')::int from tw1),
  2, '3. it allocates ROUND 2 (the original takeaway order IS work unit 1)');
select is(
  (select order_type from orders where id = 'c0000000-0000-0000-0000-00000000a003'),
  'takeaway', '4. the parent order_type is STILL takeaway (never rewritten to dine_in)');
select ok(
  (select table_id is null from orders where id = 'c0000000-0000-0000-0000-00000000a003'),
  '5. the takeaway parent still has NO table (no table requirement was added)');
select is(
  (select count(*)::int from order_service_rounds
     where order_id = 'c0000000-0000-0000-0000-00000000a003' and deleted_at is null),
  1, '6. exactly ONE service round exists for the takeaway amendment');
select ok(
  (select count(*)::int from order_items oi
     join order_service_rounds r on r.id = oi.service_round_id
    where r.order_id = 'c0000000-0000-0000-0000-00000000a003') = 1
  and (select count(*)::int from order_items
        where order_id = 'c0000000-0000-0000-0000-00000000a003' and service_round_id is null) = 1,
  '7. the round carries DELTA-ONLY items and the original line is untouched');
select ok(
  (select (revision = 2 and subtotal_minor = 1500 and grand_total_minor = 1500
           and status = 'submitted')
     from orders where id = 'c0000000-0000-0000-0000-00000000a003'),
  '8. the parent gained the delta ONCE, bumped revision, and NEVER moved status');
select is(
  (select count(*)::int from orders where order_type = 'takeaway' and deleted_at is null),
  1, '9. NO second/replacement order was fabricated (the parent identity is kept)');
select is(
  (select count(*)::int from audit_events where action = 'order.items_added'
     and (new_values ->> 'order_id') = 'c0000000-0000-0000-0000-00000000a003'
     and (new_values ->> 'round_number')::int = 2),
  1, '10. exactly ONE order.items_added audit event for the takeaway round');

-- ===========================================================================
-- (11-12) IDEMPOTENT REPLAY of the SAME local_operation_id.
-- ===========================================================================
create temp table tw2 as
  select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
                      'doa-tw1', 'c0000000-0000-0000-0000-00000000a003') as r;
select ok(
  (select ((r -> 'results' -> 0 ->> 'idempotency_replay')::boolean
           and (r -> 'results' -> 0 ->> 'round_number')::int = 2) from tw2),
  '11. the SAME local_operation_id replays to the SAME round (idempotency_replay)');
select ok(
  (select count(*)::int from order_service_rounds
     where order_id = 'c0000000-0000-0000-0000-00000000a003' and deleted_at is null) = 1
  and (select (revision = 2 and grand_total_minor = 1500)
         from orders where id = 'c0000000-0000-0000-0000-00000000a003')
  and (select count(*)::int from order_items oi
         join order_service_rounds r on r.id = oi.service_round_id
        where r.order_id = 'c0000000-0000-0000-0000-00000000a003') = 1,
  '12. the replay duplicated NOTHING: no round, no item, no total, no revision');

-- ===========================================================================
-- (13-17) dine_in regression + the EXISTING typed refusals, all untouched.
-- ===========================================================================
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'doa-di', 'c0000000-0000-0000-0000-00000000a001') -> 'results' -> 0 ->> 'error'),
  null, '13. a DINE-IN addition still succeeds (no regression from widening the gate)');
select pg_temp.cpay('doa-p6', 'c0000000-0000-0000-0000-00000000a006');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'doa-paid', 'c0000000-0000-0000-0000-00000000a006') -> 'results' -> 0 ->> 'error'),
  'order_already_settled', '14. a PAID-but-open order still refuses additions (payment freeze)');
select pg_temp.cserve('doa-s5', 'c0000000-0000-0000-0000-00000000a005');
select pg_temp.cpay('doa-p5', 'c0000000-0000-0000-0000-00000000a005');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'doa-done', 'c0000000-0000-0000-0000-00000000a005') -> 'results' -> 0 ->> 'error'),
  'order_not_eligible', '15. a COMPLETED (terminal) order still refuses additions');
select pg_temp.cvoid('doa-vd', 'c0000000-0000-0000-0000-00000000a004');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'doa-void', 'c0000000-0000-0000-0000-00000000a004') -> 'results' -> 0 ->> 'error'),
  'order_not_eligible', '16. a VOIDED order still refuses additions');
-- An UNSUPPORTED type keeps the EXISTING typed refusal `order_not_dine_in` -
-- part of the shipped wire contract and deliberately NOT renamed by this phase.
-- It is asserted STRUCTURALLY on purpose: public.orders CHECK-restricts
-- order_type to exactly dine_in|takeaway, so once the gate accepts BOTH there is
-- no reachable third value to drive it with (a `delivery` row cannot even be
-- forced in by privileged SQL - the CHECK rejects it). The refusal therefore
-- survives as D-012 layer-4 defence in depth for a future order type, and the
-- constraint below is what makes it unreachable today.
select ok(
  (select prosrc like '%not in (''dine_in'', ''takeaway'')%'
      and prosrc like '%order_not_dine_in%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'add_order_items')
  and (select pg_get_constraintdef(oid) = 'CHECK ((order_type = ANY (ARRAY[''dine_in''::text, ''takeaway''::text])))'
         from pg_constraint where conname = 'orders_order_type_check'),
  '17. any OTHER order type keeps the typed refusal (unreachable today: the orders CHECK allows only these two)');

-- ===========================================================================
-- (18-23) MODE-AWARE MANUAL COMPLETION. o2 (...a002) gets the same shape the
--         shipped suite uses for the manual gate: an addition, full payment,
--         then served -> so exactly ONE thing separates the two runs below,
--         the branch's authoritative kitchen_workflow_mode.
-- ===========================================================================
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'doa-r2', 'c0000000-0000-0000-0000-00000000a002');
select pg_temp.cpay('doa-p2', 'c0000000-0000-0000-0000-00000000a002');
select pg_temp.cserve('doa-s2', 'c0000000-0000-0000-0000-00000000a002');
select ok(
  (select status = 'served' from orders where id = 'c0000000-0000-0000-0000-00000000a002')
  and exists (select 1 from order_service_rounds
               where order_id = 'c0000000-0000-0000-0000-00000000a002'
                 and status <> 'served' and deleted_at is null),
  '18. fixture: the order is served + fully paid and carries an ACTIVE round');

-- KDS MODE (the shipped default): the rounds gate still refuses.
update branches set kitchen_workflow_mode = 'kds'
  where id = 'c0000000-0000-0000-0000-000000000c03';
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'doa-c-kds', 'c0000000-0000-0000-0000-00000000a002', 'completed') -> 'results' -> 0 ->> 'error'),
  'rounds_not_served', '19. kds mode: MANUAL completion is still refused with rounds_not_served');
select is(
  (select status from orders where id = 'c0000000-0000-0000-0000-00000000a002'),
  'served', '20. kds mode: the order really did NOT complete (the refusal is authoritative)');

-- PRINTER-ONLY: no KDS exists to walk the round to `served`, so holding manual
-- completion on it would strand the order forever. The gate is SKIPPED.
update branches set kitchen_workflow_mode = 'printer_only'
  where id = 'c0000000-0000-0000-0000-000000000c03';
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'doa-c-po', 'c0000000-0000-0000-0000-00000000a002', 'completed') -> 'results' -> 0 ->> 'error'),
  null, '21. printer_only: the SAME manual completion now SUCCEEDS');
select is(
  (select status from orders where id = 'c0000000-0000-0000-0000-00000000a002'),
  'completed', '22. printer_only: the order is authoritatively terminal (not merely hidden)');
-- SUPERSEDED BY PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008.
-- This migration skipped the gate WITHOUT writing any round status, which is
-- what the original assertion pinned. That left a live round hanging off a
-- TERMINAL order for ever (app.order_rounds_all_served false for a COMPLETED
-- order) - the defect 008 fixes. The round is now CLOSED by the completion, in
-- the same transaction, so the contract asserted here is inverted on purpose.
-- What 20260804090000 owns is unchanged and still asserted by 21/22: the GATE
-- is skipped and the order completes.
select ok(
  (select bool_and(status = 'served') from order_service_rounds
    where order_id = 'c0000000-0000-0000-0000-00000000a002' and deleted_at is null),
  '23. printer_only: 008 now CLOSES the round the gate skipped (no dangling round)');

-- ===========================================================================
-- (24-25) printer_only widened NOTHING else: the D-025 payment gate still
--         holds, and it is evaluated BEFORE the rounds gate. o8 (...a008) is
--         the zero-round order; serve it but never pay it.
-- ===========================================================================
select pg_temp.cserve('doa-s8', 'c0000000-0000-0000-0000-00000000a008');
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'doa-c-np', 'c0000000-0000-0000-0000-00000000a008', 'completed') -> 'results' -> 0 ->> 'error'),
  'order_not_paid', '24. printer_only: an UNPAID order is still refused (payment gate untouched)');
select isnt(
  (select status from orders where id = 'c0000000-0000-0000-0000-00000000a008'),
  'completed', '25. printer_only: the unpaid order did NOT complete');

-- ===========================================================================
-- (26-27) The AUTOMATIC completion path is unchanged by this migration.
--         Back in kds mode, settling a served order that still has an ACTIVE
--         round must NOT auto-complete it.
-- ===========================================================================
update branches set kitchen_workflow_mode = 'kds'
  where id = 'c0000000-0000-0000-0000-000000000c03';
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'doa-rb1', 'c0000000-0000-0000-0000-00000000a0b1');
select pg_temp.cserve('doa-sb1', 'c0000000-0000-0000-0000-00000000a0b1');
create temp table payb1 as
  select pg_temp.cpay('doa-pb1', 'c0000000-0000-0000-0000-00000000a0b1') as r;
select ok(
  (select (r -> 'results' -> 0 ->> 'status') = 'applied' from payb1)
  and (select status = 'served' from orders where id = 'c0000000-0000-0000-0000-00000000a0b1'),
  '26. kds mode: payment applies but does NOT auto-complete while a round is active');
select ok(
  (select prosrc like '%kitchen_workflow_mode%' and prosrc like '%order_rounds_all_served%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'try_auto_complete_order'),
  '27. app.try_auto_complete_order still owns its OWN mode read + rounds gate (not re-emitted here)');

-- ===========================================================================
-- (28-29) FAIL-CLOSED BY CONSTRUCTION. kitchen_workflow_mode is NOT NULL with a
--         two-value CHECK, so an "unknown" value is unreachable at runtime and
--         cannot be asserted behaviourally. What IS assertable is the shape of
--         the gate: the read is tenant+branch scoped, ignores soft-deleted
--         branches, coalesces a missing row to 'kds', and skips ONLY on the
--         exact literal 'printer_only' - so anything that is not printer_only
--         keeps the historical KDS behaviour.
-- ===========================================================================
select ok(
  (select prosrc like '%coalesce(v_kitchen_mode, ''kds'')%'
      and prosrc like '%and b.deleted_at is null%'
      and prosrc like '%v_kitchen_mode <> ''printer_only''%'
      and prosrc like '%and not app.order_rounds_all_served(v_o_org, p_order_id) then%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'apply_order_status_transition'),
  '28. the completion gate is FAIL-CLOSED: scoped read, coalesce to kds, skip only on printer_only');
select ok(
  (select pg_get_constraintdef(oid) = 'CHECK ((kitchen_workflow_mode = ANY (ARRAY[''kds''::text, ''printer_only''::text])))'
     from pg_constraint where conname = 'branches_kitchen_workflow_mode_check'),
  '29. branches.kitchen_workflow_mode is still CHECK-restricted to exactly kds|printer_only');

-- ===========================================================================
-- (30-32) GRANT + SECURITY POSTURE: re-emitting the two functions broadened
--         nothing. add_order_items stays authenticated-only (it is the
--         order.items_add front); apply_order_status_transition stays INTERNAL.
-- ===========================================================================
select ok(
  not has_function_privilege('anon', 'app.add_order_items(uuid,uuid,uuid,text,jsonb,timestamptz)', 'execute')
  and has_function_privilege('authenticated', 'app.add_order_items(uuid,uuid,uuid,text,jsonb,timestamptz)', 'execute'),
  '30. app.add_order_items: anon denied, authenticated allowed (posture unchanged)');
select ok(
  not has_function_privilege('anon', 'app.apply_order_status_transition(uuid,text,uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,text,integer)', 'execute')
  and not has_function_privilege('authenticated', 'app.apply_order_status_transition(uuid,text,uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,text,integer)', 'execute'),
  '31. app.apply_order_status_transition stays INTERNAL (anon AND authenticated denied)');
select ok(
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'])
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app'
       and p.proname in ('add_order_items', 'apply_order_status_transition')),
  '32. both re-emitted functions are SECURITY DEFINER with a pinned EMPTY search_path');

select * from finish();
rollback;
