-- ============================================================================
-- MONEY-VOID-001 — pgTAP: order.void reachable via public.sync_push
-- ============================================================================
-- Proves the NEW dispatch path end-to-end: public.sync_push -> app.sync_push ->
-- app.void_order. app.void_order itself (role gate, reason, state legality,
-- completed-payment block, tenant scope, idempotency, audit) is exhaustively
-- covered by rf053_* / rf062_* — this file proves those guarantees SURFACE
-- through the sync_push order.void op that MONEY-VOID-001 adds, plus the
-- sync_operations.operation_type CHECK extension. Money-free: a void writes no
-- payment and recomputes no total. Fixtures inserted as the BYPASSRLS connection
-- role (RF-056/RF-057 convention).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(17);

-- ===== fixtures: Org A (POS device, 4 operators) + Org B (a cross-tenant mgr) =
insert into organizations (id, name, slug, default_currency) values
  ('a0000000-0000-0000-0000-000000000a01', 'Org VA', 'va-a', 'USD'),
  ('b0000000-0000-0000-0000-000000000b01', 'Org VB', 'vb-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a01', 'Rest VA'),
  ('b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b01', 'Rest VB');
insert into branches (id, organization_id, restaurant_id, name) values
  ('a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'Branch VA'),
  ('b0000000-0000-0000-0000-000000000b03', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'Branch VB');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('a0000000-0000-0000-0000-0000000000d1', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'pos'),
  ('b0000000-0000-0000-0000-0000000000d1', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b03', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('a0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000000d1', 'active'),
  ('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b03', 'b0000000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000000d1', 'a0000000-0000-0000-0000-0000000000f1'),
  ('b0000000-0000-0000-0000-0000000000e1', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b03', 'b0000000-0000-0000-0000-0000000000d1', 'b0000000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('a0000000-0000-0000-0000-0000000ae001', 'va-mgr@example.test'),
  ('a0000000-0000-0000-0000-0000000ae002', 'va-cash@example.test'),
  ('a0000000-0000-0000-0000-0000000ae003', 'va-cashperm@example.test'),
  ('a0000000-0000-0000-0000-0000000ae004', 'va-kitchen@example.test'),
  ('b0000000-0000-0000-0000-0000000be001', 'vb-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('a0000000-0000-0000-0000-0000000ab001', 'a0000000-0000-0000-0000-0000000ae001', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'manager', '{}'::jsonb),
  ('a0000000-0000-0000-0000-0000000ab002', 'a0000000-0000-0000-0000-0000000ae002', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'cashier', '{}'::jsonb),
  ('a0000000-0000-0000-0000-0000000ab003', 'a0000000-0000-0000-0000-0000000ae003', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'cashier', '{"void_order": "true"}'::jsonb),
  ('a0000000-0000-0000-0000-0000000ab004', 'a0000000-0000-0000-0000-0000000ae004', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'kitchen_staff', '{}'::jsonb),
  ('b0000000-0000-0000-0000-0000000bb001', 'b0000000-0000-0000-0000-0000000be001', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b03', 'manager', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('a0000000-0000-0000-0000-0000000ac001', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000ae001', 'a0000000-0000-0000-0000-0000000ab001'),
  ('a0000000-0000-0000-0000-0000000ac002', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000ae002', 'a0000000-0000-0000-0000-0000000ab002'),
  ('a0000000-0000-0000-0000-0000000ac003', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000ae003', 'a0000000-0000-0000-0000-0000000ab003'),
  ('a0000000-0000-0000-0000-0000000ac004', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000ae004', 'a0000000-0000-0000-0000-0000000ab004'),
  ('b0000000-0000-0000-0000-0000000bc001', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b03', 'b0000000-0000-0000-0000-0000000be001', 'b0000000-0000-0000-0000-0000000bb001');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('a0000000-0000-0000-0000-0000000ad001', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-0000000ac001', 'a0000000-0000-0000-0000-0000000ab001', now() + interval '1 hour'),
  ('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-0000000ac002', 'a0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('a0000000-0000-0000-0000-0000000ad003', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-0000000ac003', 'a0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('a0000000-0000-0000-0000-0000000ad004', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-0000000ac004', 'a0000000-0000-0000-0000-0000000ab004', now() + interval '1 hour'),
  ('b0000000-0000-0000-0000-0000000bd001', 'b0000000-0000-0000-0000-000000000b01', 'b0000000-0000-0000-0000-000000000b02', 'b0000000-0000-0000-0000-000000000b03', 'b0000000-0000-0000-0000-0000000000e1', 'b0000000-0000-0000-0000-0000000bc001', 'b0000000-0000-0000-0000-0000000bb001', now() + interval '1 hour');

-- ---- helpers: submit an order.submit op, and push an order.void op ----------
create or replace function pg_temp.vsubmit(p_pin uuid, p_dev uuid, p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', p_order, 'order_type', 'takeaway', 'currency_code', 'USD',
      'subtotal_minor', 1000, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 1000,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'a0000000-0000-0000-0000-0000000000f9', 'quantity', 1,
        'unit_price_minor_snapshot', 1000, 'menu_item_name_snapshot', 'Item'))))));
$$;
create or replace function pg_temp.vvoid(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_reason text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.void', 'target_entity', 'order',
    'payload', jsonb_build_object('order_id', p_order, 'reason', p_reason))));
$$;

-- Create the orders (org A cashier) that the tests void.
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o1', 'a0000000-0000-0000-0000-00000000a0d1');
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o2', 'a0000000-0000-0000-0000-00000000a0d2');
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o3', 'a0000000-0000-0000-0000-00000000a0d3');
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o4', 'a0000000-0000-0000-0000-00000000a0d4');
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o5', 'a0000000-0000-0000-0000-00000000a0d5');
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o6', 'a0000000-0000-0000-0000-00000000a0d6');
select pg_temp.vsubmit('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'sub-o7', 'a0000000-0000-0000-0000-00000000a0d7');

-- A live COMPLETED payment on o5 (direct insert; the paid-void guard checks this).
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, method, status,
    amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('a0000000-0000-0000-0000-00000000a005', 'a0000000-0000-0000-0000-000000000a01', 'a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-00000000a0d5', 'a0000000-0000-0000-0000-0000000000d1',
   'a0000000-0000-0000-0000-0000000ac002', 'a0000000-0000-0000-0000-0000000ab002', 'cash', 'completed',
   1000, 1000, 0, 'USD', 'pay-o5');

-- ===== (1-5) MANAGER voids an unpaid order via sync_push -> applied ===========
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad001', 'a0000000-0000-0000-0000-0000000000d1', 'void-o1', 'a0000000-0000-0000-0000-00000000a0d1', 'wrong item') -> 'results' -> 0 ->> 'status'),
  'applied', 'MANAGER: order.void dispatches through sync_push and is applied');
select is(
  (select status from orders where id = 'a0000000-0000-0000-0000-00000000a0d1'),
  'voided', 'the order is now voided (status set by app.void_order, money-free)');
select ok(
  (select bool_and(status = 'voided') from order_items where order_id = 'a0000000-0000-0000-0000-00000000a0d1'),
  'the order items cascade to voided');
select ok(
  exists (select 1 from audit_events where action = 'order.voided'
          and (new_values ->> 'status') = 'voided'
          and organization_id = 'a0000000-0000-0000-0000-000000000a01'),
  'an order.voided audit event is written (auditable, D-013)');
select ok(
  exists (select 1 from sync_operations where operation_type = 'order.void'
          and local_operation_id = 'void-o1' and status = 'applied'),
  'a sync_operations ledger row is recorded with operation_type=order.void, status=applied');

-- ===== (6-7) kitchen_staff is DENIED, no mutation =============================
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad004', 'a0000000-0000-0000-0000-0000000000d1', 'void-o2', 'a0000000-0000-0000-0000-00000000a0d2', 'x') -> 'results' -> 0 ->> 'error'),
  'permission_denied', 'kitchen_staff void is denied (permission_denied)');
select is(
  (select status from orders where id = 'a0000000-0000-0000-0000-00000000a0d2'),
  'submitted', 'a denied void makes NO state change (order stays submitted)');

-- ===== (8) plain cashier (no permission) is DENIED ===========================
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad002', 'a0000000-0000-0000-0000-0000000000d1', 'void-o3', 'a0000000-0000-0000-0000-00000000a0d3', 'x') -> 'results' -> 0 ->> 'error'),
  'permission_denied', 'a cashier WITHOUT the void_order permission is denied');

-- ===== (9) cashier WITH permissions.void_order=true is ALLOWED ================
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad003', 'a0000000-0000-0000-0000-0000000000d1', 'void-o4', 'a0000000-0000-0000-0000-00000000a0d4', 'wrong table') -> 'results' -> 0 ->> 'status'),
  'applied', 'a cashier WITH the void_order permission may void');

-- ===== (10-11) a PAID order is rejected (unpaid-only MVP) =====================
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad001', 'a0000000-0000-0000-0000-0000000000d1', 'void-o5', 'a0000000-0000-0000-0000-00000000a0d5', 'x') -> 'results' -> 0 ->> 'detail'),
  'order_has_completed_payment', 'a paid order cannot be voided (completed-payment block, RF-062)');
select is(
  (select status from orders where id = 'a0000000-0000-0000-0000-00000000a0d5'),
  'submitted', 'the paid order is unchanged (no void, no money touched)');

-- ===== (12) a blank reason is rejected =======================================
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad001', 'a0000000-0000-0000-0000-0000000000d1', 'void-noreason', 'a0000000-0000-0000-0000-00000000a0d6', '   ') -> 'results' -> 0 ->> 'status'),
  'rejected', 'a void with a blank reason is rejected');

-- ===== (13) an unknown order is rejected =====================================
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad001', 'a0000000-0000-0000-0000-0000000000d1', 'void-unknown', 'a0000000-0000-0000-0000-0000000fffff', 'x') -> 'results' -> 0 ->> 'status'),
  'rejected', 'voiding an unknown order id is rejected');

-- ===== (14) cross-tenant: Org B manager cannot void Org A's order ============
select is(
  (pg_temp.vvoid('b0000000-0000-0000-0000-0000000bd001', 'b0000000-0000-0000-0000-0000000000d1', 'void-xtenant', 'a0000000-0000-0000-0000-00000000a0d7', 'x') -> 'results' -> 0 ->> 'status'),
  'rejected', 'a cross-tenant void (Org B actor, Org A order) is rejected (R-003)');
select is(
  (select status from orders where id = 'a0000000-0000-0000-0000-00000000a0d7'),
  'submitted', 'the cross-tenant target order is unchanged');

-- ===== (16) idempotent replay: the SAME void op returns the stored result ====
select is(
  (pg_temp.vvoid('a0000000-0000-0000-0000-0000000ad001', 'a0000000-0000-0000-0000-0000000000d1', 'void-o1', 'a0000000-0000-0000-0000-00000000a0d1', 'wrong item') -> 'results' -> 0 ->> 'idempotency_replay')::boolean,
  true, 'replaying the same order.void op returns the stored result (idempotent, D-022)');

-- ===== (17) the operation_type CHECK now permits order.void ==================
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'sync_operations_operation_type_check') like '%order.void%',
  'sync_operations.operation_type CHECK now accepts order.void');

select * from finish();
rollback;
