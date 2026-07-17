-- ============================================================================
-- PSC-001D — pgTAP: void provenance + kitchen cancellation acknowledgement
-- ============================================================================
-- Proves the whole contract end-to-end through public.sync_push:
--   * app.void_order stamps voided_at / voided_from_status and computes
--     kitchen_ack_required per source state (submitted|accepted|preparing|
--     ready => TRUE; served => FALSE) while item snapshots stay intact;
--   * app.kitchen_ack_void (op #13 'order.void_ack') is KDS-DEVICE-ONLY with
--     the kitchen role set, flat typed audited denials, anti-oracle scope
--     behaviour, idempotent already-acknowledged replay (ONE success audit),
--     two-device convergence, and a revision/updated_at bump for pull
--     redelivery;
--   * the 13-op allowlist + every prior dispatch arm survive the sync_push
--     recreation; the target_id/payload mismatch is rejected; the new
--     columns' CHECKs enforce the valid combinations; anon cannot execute.
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(53);

-- ===== fixtures: Org A (1 POS + 2 KDS devices, 5 operators) + Org B (KDS mgr) =
insert into organizations (id, name, slug, default_currency) values
  ('e0000000-0000-0000-0000-000000000e01', 'Org KA', 'ka-a', 'USD'),
  ('f0000000-0000-0000-0000-000000000f01', 'Org KB', 'kb-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e01', 'Rest KA'),
  ('f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f01', 'Rest KB');
insert into branches (id, organization_id, restaurant_id, name) values
  ('e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'Branch KA'),
  ('f0000000-0000-0000-0000-000000000f03', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'Branch KB');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e0000000-0000-0000-0000-0000000000d1', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'pos'),
  ('e0000000-0000-0000-0000-0000000000d2', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'kds'),
  ('e0000000-0000-0000-0000-0000000000d3', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'kds'),
  ('f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000d1', 'active'),
  ('e0000000-0000-0000-0000-0000000000a2', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000d2', 'active'),
  ('e0000000-0000-0000-0000-0000000000a3', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000d3', 'active'),
  ('f0000000-0000-0000-0000-0000000000a1', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'f0000000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000d1', 'e0000000-0000-0000-0000-0000000000a1'),
  ('e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000d2', 'e0000000-0000-0000-0000-0000000000a2'),
  ('e0000000-0000-0000-0000-0000000000e3', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000d3', 'e0000000-0000-0000-0000-0000000000a3'),
  ('f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-0000000000a1');
insert into app_users (id, email) values
  ('e0000000-0000-0000-0000-0000000ae001', 'ka-mgr@example.test'),
  ('e0000000-0000-0000-0000-0000000ae002', 'ka-cash@example.test'),
  ('e0000000-0000-0000-0000-0000000ae003', 'ka-kitchen@example.test'),
  ('e0000000-0000-0000-0000-0000000ae004', 'ka-owner@example.test'),
  ('f0000000-0000-0000-0000-0000000be001', 'kb-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e0000000-0000-0000-0000-0000000ab001', 'e0000000-0000-0000-0000-0000000ae001', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'manager', '{}'::jsonb),
  ('e0000000-0000-0000-0000-0000000ab002', 'e0000000-0000-0000-0000-0000000ae002', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'cashier', '{}'::jsonb),
  ('e0000000-0000-0000-0000-0000000ab003', 'e0000000-0000-0000-0000-0000000ae003', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'kitchen_staff', '{}'::jsonb),
  ('e0000000-0000-0000-0000-0000000ab004', 'e0000000-0000-0000-0000-0000000ae004', 'e0000000-0000-0000-0000-000000000e01', null, null, 'org_owner', '{}'::jsonb),
  ('f0000000-0000-0000-0000-0000000bb001', 'f0000000-0000-0000-0000-0000000be001', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'manager', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('e0000000-0000-0000-0000-0000000ac001', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000ae001', 'e0000000-0000-0000-0000-0000000ab001'),
  ('e0000000-0000-0000-0000-0000000ac002', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000ae002', 'e0000000-0000-0000-0000-0000000ab002'),
  ('e0000000-0000-0000-0000-0000000ac003', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000ae003', 'e0000000-0000-0000-0000-0000000ab003'),
  ('e0000000-0000-0000-0000-0000000ac004', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000ae004', 'e0000000-0000-0000-0000-0000000ab004'),
  ('f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'f0000000-0000-0000-0000-0000000be001', 'f0000000-0000-0000-0000-0000000bb001');
-- PIN sessions: managers/cashier on the POS device; kitchen/manager/cashier/
-- owner on KDS-1; kitchen on KDS-2; Org B manager on B's KDS.
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-0000000ac001', 'e0000000-0000-0000-0000-0000000ab001', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-0000000ac002', 'e0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-0000000ac003', 'e0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-0000000ad004', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-0000000ac001', 'e0000000-0000-0000-0000-0000000ab001', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-0000000ad005', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-0000000ac002', 'e0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-0000000ad006', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-0000000ac004', 'e0000000-0000-0000-0000-0000000ab004', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-0000000ad007', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', 'e0000000-0000-0000-0000-000000000e03', 'e0000000-0000-0000-0000-0000000000e3', 'e0000000-0000-0000-0000-0000000ac003', 'e0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-0000000bb001', now() + interval '1 hour');

-- Sellable menu fixture for org A.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e0000000-0000-0000-0000-0000000000c9', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e0000000-0000-0000-0000-0000000000f9', 'e0000000-0000-0000-0000-000000000e01', 'e0000000-0000-0000-0000-000000000e02', null, 'e0000000-0000-0000-0000-0000000000c9', 'Item', 1000, 'USD', 1);

-- ---- helpers ---------------------------------------------------------------
create or replace function pg_temp.ksubmit(p_pin uuid, p_dev uuid, p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', p_order, 'order_type', 'takeaway', 'currency_code', 'USD',
      'subtotal_minor', 1000, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 1000,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'e0000000-0000-0000-0000-0000000000f9', 'quantity', 2,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));
$$;
create or replace function pg_temp.kstatus(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_to text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.status', 'target_entity', 'order',
    'payload', jsonb_build_object('order_id', p_order, 'new_status', p_to))));
$$;
create or replace function pg_temp.kvoid(p_pin uuid, p_dev uuid, p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.void', 'target_entity', 'order',
    'payload', jsonb_build_object('order_id', p_order, 'reason', 'customer left'))));
$$;
create or replace function pg_temp.kack(p_pin uuid, p_dev uuid, p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.void_ack', 'target_entity', 'order',
    'target_id', p_order,
    'payload', jsonb_build_object('order_id', p_order))));
$$;
-- Adversarial variant: independent payload order and (possibly malformed) target.
create or replace function pg_temp.kack2(p_pin uuid, p_dev uuid, p_op text, p_payload_order uuid, p_target text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.void_ack', 'target_entity', 'order',
    'target_id', p_target,
    'payload', jsonb_build_object('order_id', p_payload_order))));
$$;

-- Orders o1..o8 (POS cashier submits; kitchen advances where needed).
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o1', 'e0000000-0000-0000-0000-00000000a0d1');
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o2', 'e0000000-0000-0000-0000-00000000a0d2');
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o3', 'e0000000-0000-0000-0000-00000000a0d3');
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o4', 'e0000000-0000-0000-0000-00000000a0d4');
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o5', 'e0000000-0000-0000-0000-00000000a0d5');
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o6', 'e0000000-0000-0000-0000-00000000a0d6');
select pg_temp.ksubmit('e0000000-0000-0000-0000-0000000ad002', 'e0000000-0000-0000-0000-0000000000d1', 'sub-o7', 'e0000000-0000-0000-0000-00000000a0d7');
-- advance o2 -> accepted; o3 -> preparing; o4 -> ready; o5 -> served (kitchen on KDS-1)
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o2a', 'e0000000-0000-0000-0000-00000000a0d2', 'accepted');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o3a', 'e0000000-0000-0000-0000-00000000a0d3', 'accepted');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o3b', 'e0000000-0000-0000-0000-00000000a0d3', 'preparing');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o4a', 'e0000000-0000-0000-0000-00000000a0d4', 'accepted');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o4b', 'e0000000-0000-0000-0000-00000000a0d4', 'preparing');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o4c', 'e0000000-0000-0000-0000-00000000a0d4', 'ready');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o5a', 'e0000000-0000-0000-0000-00000000a0d5', 'accepted');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o5b', 'e0000000-0000-0000-0000-00000000a0d5', 'preparing');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o5c', 'e0000000-0000-0000-0000-00000000a0d5', 'ready');
select pg_temp.kstatus('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'st-o5d', 'e0000000-0000-0000-0000-00000000a0d5', 'served');

-- ===== (1-4) structural: 13-op CHECK, all dispatch arms, ACLs =================
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'sync_operations_operation_type_check') like '%order.void_ack%',
  '1. sync_operations.operation_type CHECK accepts order.void_ack (13 ops)');
select ok(
  (select bool_and((select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'app' and p.proname = 'sync_push') like '%when ''' || op || '''%')
     from unnest(array['shift.open','order.submit','order.discount','payment.create','shift.close','order.status','order.void','order.table_move','menu.availability_set','table.status_set','table.link','table.unlink','order.void_ack']) as op),
  '2. app.sync_push carries ALL 13 dispatch arms (12 prior + order.void_ack)');
select ok(
  not has_function_privilege('anon', 'app.kitchen_ack_void(uuid,uuid,uuid,text)', 'execute'),
  '3. anon cannot execute app.kitchen_ack_void');
select ok(
  has_function_privilege('authenticated', 'app.kitchen_ack_void(uuid,uuid,uuid,text)', 'execute'),
  '4. authenticated may execute app.kitchen_ack_void (dispatcher path)');

-- ===== (5) defaults on a live order ==========================================
select ok(
  (select (kitchen_ack_required = false and voided_at is null and voided_from_status is null and kitchen_ack_at is null)
     from orders where id = 'e0000000-0000-0000-0000-00000000a0d1'),
  '5. a live order carries the safe defaults (no provenance, no ack demand)');

-- ===== (6-12) void provenance per source state ================================
select is(
  (pg_temp.kvoid('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'vd-o1', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'status'),
  'applied', '6. void from SUBMITTED applies');
select ok(
  (select (voided_at is not null and voided_from_status = 'submitted' and kitchen_ack_required)
     from orders where id = 'e0000000-0000-0000-0000-00000000a0d1'),
  '7. submitted-source void stamps provenance and REQUIRES acknowledgement');
select ok(
  (select bool_and(status = 'voided' and menu_item_name_snapshot = 'Item' and quantity = 2)
     from order_items where order_id = 'e0000000-0000-0000-0000-00000000a0d1'),
  '8. voided items keep their snapshots intact (name + quantity survive)');
select pg_temp.kvoid('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'vd-o2', 'e0000000-0000-0000-0000-00000000a0d2');
select ok(
  (select (voided_from_status = 'accepted' and kitchen_ack_required) from orders where id = 'e0000000-0000-0000-0000-00000000a0d2'),
  '9. accepted-source void requires acknowledgement');
select pg_temp.kvoid('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'vd-o3', 'e0000000-0000-0000-0000-00000000a0d3');
select ok(
  (select (voided_from_status = 'preparing' and kitchen_ack_required) from orders where id = 'e0000000-0000-0000-0000-00000000a0d3'),
  '10. preparing-source void requires acknowledgement');
select pg_temp.kvoid('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'vd-o4', 'e0000000-0000-0000-0000-00000000a0d4');
select ok(
  (select (voided_from_status = 'ready' and kitchen_ack_required) from orders where id = 'e0000000-0000-0000-0000-00000000a0d4'),
  '11. ready-source void requires acknowledgement');
select pg_temp.kvoid('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'vd-o5', 'e0000000-0000-0000-0000-00000000a0d5');
select ok(
  (select (voided_from_status = 'served' and not kitchen_ack_required) from orders where id = 'e0000000-0000-0000-0000-00000000a0d5'),
  '12. served-source void does NOT require acknowledgement (already off the board)');

-- ===== (13-18) typed audited denials ==========================================
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad005', 'e0000000-0000-0000-0000-0000000000d2', 'ack-cash', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'error'),
  'permission_denied', '13. a CASHIER on a KDS device is denied');
select ok(
  exists (select 1 from audit_events where action = 'order.void_ack_denied'
          and (new_values ->> 'denied_reason') = 'permission_denied'
          and (new_values ->> 'role') = 'cashier'),
  '14. the cashier denial is audited with its safe reason');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'ack-pos', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'error'),
  'invalid_device_type', '15. a MANAGER on a POS device is denied invalid_device_type (locked safeguard)');
select ok(
  exists (select 1 from audit_events where action = 'order.void_ack_denied'
          and (new_values ->> 'denied_reason') = 'invalid_device_type'
          and (new_values ->> 'device_type') = 'pos'),
  '16. the POS-device denial is audited with device_type=pos');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-live', 'e0000000-0000-0000-0000-00000000a0d6') -> 'results' -> 0 ->> 'error'),
  'order_not_voided', '17. acknowledging a LIVE order returns the flat order_not_voided');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-served', 'e0000000-0000-0000-0000-00000000a0d5') -> 'results' -> 0 ->> 'error'),
  'acknowledgement_not_required', '18. a served-source void returns acknowledgement_not_required');

-- ===== (19-25) first ack, write-once state, single audit, idempotent replay ===
create temp table pre_ack as
  select revision, updated_at from orders where id = 'e0000000-0000-0000-0000-00000000a0d1';
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o1', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'status'),
  'applied', '19. kitchen_staff on a KDS device acknowledges successfully');
select ok(
  (select (kitchen_ack_at is not null
           and kitchen_ack_by_employee_profile_id = 'e0000000-0000-0000-0000-0000000ac003'
           and kitchen_ack_device_id = 'e0000000-0000-0000-0000-0000000000d2')
     from orders where id = 'e0000000-0000-0000-0000-00000000a0d1'),
  '20. the acknowledgement triple is stamped (kitchen actor + the KDS device)');
select is(
  (select count(*)::int from audit_events where action = 'order.void_acknowledged'
    and (new_values ->> 'order_id') = 'e0000000-0000-0000-0000-00000000a0d1'),
  1, '21. exactly ONE order.void_acknowledged audit row is written');
-- NOTE: inside this single pgTAP transaction now() is FROZEN, so the trigger
-- re-stamps updated_at with the SAME transaction timestamp the void wrote —
-- equality here IS proof the trigger fired; across real (separate) client
-- transactions the stamp is strictly newer and the (updated_at, id) cursor
-- re-delivers the row.
select ok(
  (select (o.revision > p.revision
           and o.updated_at >= p.updated_at
           and o.updated_at = now())
     from orders o, pre_ack p where o.id = 'e0000000-0000-0000-0000-00000000a0d1'),
  '22. the ack bumps revision and re-stamps updated_at (the pull cursor re-delivers it)');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o1', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'idempotency_replay')::boolean,
  true, '23. replaying the SAME op returns the stored result (transport idempotency)');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o1b', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'already_acknowledged')::boolean,
  true, '24. a NEW op on an acknowledged order replays success (already_acknowledged)');
select is(
  (select count(*)::int from audit_events where action = 'order.void_acknowledged'
    and (new_values ->> 'order_id') = 'e0000000-0000-0000-0000-00000000a0d1'),
  1, '25. the duplicate acknowledgement writes NO second success audit');

-- ===== (26-28) roles + two-device convergence =================================
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad004', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o2', 'e0000000-0000-0000-0000-00000000a0d2') -> 'results' -> 0 ->> 'status'),
  'applied', '26. a MANAGER on a KDS device acknowledges successfully');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad006', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o3', 'e0000000-0000-0000-0000-00000000a0d3') -> 'results' -> 0 ->> 'status'),
  'applied', '27. an ORG_OWNER on a KDS device acknowledges successfully');
-- KDS-1 kitchen acks o4; KDS-2 kitchen tries next (two-device race, second wins nothing)
select pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o4', 'e0000000-0000-0000-0000-00000000a0d4');
select is(
  (pg_temp.kack('e0000000-0000-0000-0000-0000000ad007', 'e0000000-0000-0000-0000-0000000000d3', 'ack-o4-dev2', 'e0000000-0000-0000-0000-00000000a0d4') -> 'results' -> 0 ->> 'already_acknowledged')::boolean,
  true, '28. a SECOND KDS device converges: already_acknowledged success, no double write');

-- ===== (29-30) anti-oracle cross-tenant probe =================================
select pg_temp.kvoid('e0000000-0000-0000-0000-0000000ad001', 'e0000000-0000-0000-0000-0000000000d1', 'vd-o7', 'e0000000-0000-0000-0000-00000000a0d7');
select is(
  (pg_temp.kack('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1', 'ack-xt', 'e0000000-0000-0000-0000-00000000a0d7') -> 'results' -> 0 ->> 'status'),
  'rejected', '29. a cross-tenant acknowledgement is a structural rejection (anti-oracle, R-003)');
select ok(
  (select kitchen_ack_at is null from orders where id = 'e0000000-0000-0000-0000-00000000a0d7'),
  '30. the cross-tenant target order is unchanged (still pending)');

-- ===== (31-32) hostile envelopes ==============================================
select is(
  (select public.sync_push('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2',
     jsonb_build_array(jsonb_build_object(
       'local_operation_id', 'ack-mismatch', 'operation_type', 'order.void_ack', 'target_entity', 'order',
       'target_id', 'e0000000-0000-0000-0000-00000000a0d1',
       'payload', jsonb_build_object('order_id', 'e0000000-0000-0000-0000-00000000a0d7')))) -> 'results' -> 0 ->> 'status'),
  'rejected', '31. a target_id contradicting payload.order_id is rejected (hardened envelope)');
select is(
  (select public.sync_push('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2',
     jsonb_build_array(jsonb_build_object(
       'local_operation_id', 'ack-noid', 'operation_type', 'order.void_ack', 'target_entity', 'order',
       'payload', jsonb_build_object()))) -> 'results' -> 0 ->> 'status'),
  'rejected', '32. a payload without order_id follows the hardened exception path');

-- ===== (33-34) schema self-defence (D-012 layer 4) ============================
select throws_ok(
  $$ update orders set kitchen_ack_at = now(),
       kitchen_ack_by_employee_profile_id = 'e0000000-0000-0000-0000-0000000ac003',
       kitchen_ack_device_id = 'e0000000-0000-0000-0000-0000000000d2'
     where id = 'e0000000-0000-0000-0000-00000000a0d6' $$,
  '23514', null,
  '33. an ack on an order that never required one violates the CHECK (even for a privileged writer)');
select throws_ok(
  $$ update orders set kitchen_ack_at = now(),
       kitchen_ack_by_employee_profile_id = 'e0000000-0000-0000-0000-0000000ac003',
       kitchen_ack_device_id = 'f0000000-0000-0000-0000-0000000000d1'
     where id = 'e0000000-0000-0000-0000-00000000a0d7' $$,
  '23503', null,
  '34. a cross-branch acknowledging device violates the 4-part composite FK');

-- ===== (35-36) safe-detail projection ========================================
select is(
  app.audit_safe_detail('order.void_acknowledged', jsonb_build_object(
    'order_code', '#ABC123', 'voided_from_status', 'preparing',
    'device_type', 'kds', 'kitchen_ack_required', true, 'role', 'kitchen_staff',
    'order_id', 'e0000000-0000-0000-0000-00000000a0d1', 'resolved_membership_id', 'x')),
  jsonb_build_object('role', 'kitchen_staff', 'order_code', '#ABC123',
                     'voided_from_status', 'preparing', 'device_type', 'kds',
                     'kitchen_ack_required', true),
  '35. audit_safe_detail projects the new safe scalars and DROPS the identifiers');
select is(
  app.audit_category('order.void_acknowledged'),
  'voids',
  '36. order.void_acknowledged classifies under voids (never Other)');

-- ===== (37-40) CORRECTION F1: nonexistent vs foreign order are EXTERNALLY ====
-- ===== INDISTINGUISHABLE — immediate result, ledger, AND the canonical  ====
-- ===== operation_statuses read path                                      ====
-- A REAL order in Org B (direct fixture insert) that Org A's kitchen probes.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
                    opened_by_employee_profile_id, resolved_membership_id, order_type, status,
                    currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('f0000000-0000-0000-0000-00000000b0d1', 'f0000000-0000-0000-0000-000000000f01', 'f0000000-0000-0000-0000-000000000f02', 'f0000000-0000-0000-0000-000000000f03', 'f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-0000000bd001',
   'f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-0000000bb001', 'takeaway', 'submitted',
   'USD', 1000, 1000, 'sub-b1');
create temp table probe_results as
  select
    (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-ghost', '99999999-9999-4999-8999-999999999999') -> 'results' -> 0) - 'local_operation_id' as ghost,
    (pg_temp.kack('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-foreign', 'f0000000-0000-0000-0000-00000000b0d1') -> 'results' -> 0) - 'local_operation_id' as foreign_probe;
select ok(
  (select ghost = foreign_probe from probe_results),
  '37. F1: the IMMEDIATE results for a nonexistent vs a foreign order are identical');
select ok(
  (select g.status = f.status and g.rejection_reason = f.rejection_reason
     from sync_operations g, sync_operations f
     where g.local_operation_id = 'ack-ghost' and f.local_operation_id = 'ack-foreign'),
  '38. F1: the LEDGER status + rejection_reason are identical for both probes');
select ok(
  (select (g.result - 'local_operation_id') = (f.result - 'local_operation_id')
     from sync_operations g, sync_operations f
     where g.local_operation_id = 'ack-ghost' and f.local_operation_id = 'ack-foreign'),
  '39. F1: the LEDGER result envelopes are identical for both probes');
-- The canonical read path: this DEVICE's operation_statuses feed via sync_pull.
create temp table probe_feed as
  select value as row_j
    from jsonb_array_elements(
      public.sync_pull('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2',
                       array['operation_statuses']) -> 'operation_statuses' -> 'rows');
select ok(
  (select (a.row_j - array['local_operation_id','target_id','id','created_at','updated_at','applied_at','server_received_at','client_created_at'])
        = (b.row_j - array['local_operation_id','target_id','id','created_at','updated_at','applied_at','server_received_at','client_created_at'])
     from probe_feed a, probe_feed b
     where a.row_j ->> 'local_operation_id' = 'ack-ghost'
       and b.row_j ->> 'local_operation_id' = 'ack-foreign'),
  '40. F1: the operation_statuses feed rows are indistinguishable (identity fields aside)');

-- ===== (41-44) CORRECTION F2: a terminal replay is bound to the TARGET =======
-- 'ack-o1' is the APPLIED acknowledgement of o1 (test 19). Replaying the same
-- local_operation_id + same payload with a SWAPPED target must NOT return the
-- stored applied result — it is a hostile envelope.
select is(
  (pg_temp.kack2('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-o1',
                 'e0000000-0000-0000-0000-00000000a0d1', 'e0000000-0000-0000-0000-00000000a0d7') -> 'results' -> 0 ->> 'error'),
  'invalid_payload', '41. F2: a terminal replay with a swapped target_id is rejected, never replayed');
select ok(
  (select kitchen_ack_at is null from orders where id = 'e0000000-0000-0000-0000-00000000a0d7'),
  '42. F2: the swapped-target order is untouched by the hostile replay');
select is(
  (select count(*)::int from audit_events where action = 'order.void_acknowledged'
    and (new_values ->> 'order_id') = 'e0000000-0000-0000-0000-00000000a0d1'),
  1, '43. F2: no additional success audit was written by the hostile replay');
select is(
  (select status from sync_operations where local_operation_id = 'ack-o1'),
  'applied', '44. F2: the stored terminal ledger row is unchanged (still the original applied)');

-- ===== (45-46) CORRECTION F2: a fresh payload/target mismatch is hostile =====
select is(
  (pg_temp.kack2('e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2', 'ack-mm2',
                 'e0000000-0000-0000-0000-00000000a0d7', 'e0000000-0000-0000-0000-00000000a0d1') -> 'results' -> 0 ->> 'error'),
  'invalid_payload', '45. F2: target A + payload B on a NEW op is a malformed envelope');
select ok(
  not exists (select 1 from sync_operations where local_operation_id = 'ack-mm2'),
  '46. F2: a malformed envelope leaves NO ledger row (the malformed convention)');

-- ===== (47-53) CORRECTION F3: a malformed target rejects ONLY its own op ====
-- Mixed batch, VALID FIRST: a real order.status advance + a malformed void_ack.
create temp table mixed1 as select public.sync_push(
  'e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2',
  jsonb_build_array(
    jsonb_build_object('local_operation_id', 'st-mixed1', 'operation_type', 'order.status', 'target_entity', 'order',
      'payload', jsonb_build_object('order_id', 'e0000000-0000-0000-0000-00000000a0d6', 'new_status', 'accepted')),
    jsonb_build_object('local_operation_id', 'ack-bad1', 'operation_type', 'order.void_ack', 'target_entity', 'order',
      'target_id', 'not-a-uuid',
      'payload', jsonb_build_object('order_id', 'e0000000-0000-0000-0000-00000000a0d1')))) as r;
select is((select r -> 'results' -> 0 ->> 'status' from mixed1), 'applied',
  '47. F3: the valid sibling (a PRIOR dispatch arm, order.status) still applies');
select is((select r -> 'results' -> 1 ->> 'error' from mixed1), 'invalid_payload',
  '48. F3: the malformed target_id rejects ONLY its own operation');
select is((select status from orders where id = 'e0000000-0000-0000-0000-00000000a0d6'), 'accepted',
  '49. F3: the sibling mutation landed (o6 advanced) — the batch was not aborted');
-- Mixed batch, MALFORMED FIRST: ordering must not matter.
create temp table mixed2 as select public.sync_push(
  'e0000000-0000-0000-0000-0000000ad003', 'e0000000-0000-0000-0000-0000000000d2',
  jsonb_build_array(
    jsonb_build_object('local_operation_id', 'ack-bad2', 'operation_type', 'order.void_ack', 'target_entity', 'order',
      'target_id', 'also-not-a-uuid',
      'payload', jsonb_build_object('order_id', 'e0000000-0000-0000-0000-00000000a0d1')),
    jsonb_build_object('local_operation_id', 'st-mixed2', 'operation_type', 'order.status', 'target_entity', 'order',
      'payload', jsonb_build_object('order_id', 'e0000000-0000-0000-0000-00000000a0d6', 'new_status', 'preparing')))) as r;
select is((select r -> 'results' -> 0 ->> 'error' from mixed2), 'invalid_payload',
  '50. F3: malformed-first is rejected per-operation');
select is((select r -> 'results' -> 1 ->> 'status' from mixed2), 'applied',
  '51. F3: the valid sibling AFTER the malformed op still applies');
select is((select status from orders where id = 'e0000000-0000-0000-0000-00000000a0d6'), 'preparing',
  '52. F3: the second sibling mutation landed too');
select ok(
  not exists (select 1 from sync_operations where local_operation_id in ('ack-bad1', 'ack-bad2')),
  '53. F3: malformed void_ack envelopes leave NO ledger rows; no acknowledgement mutated');

select * from finish();
rollback;
