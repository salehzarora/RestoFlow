-- ============================================================================
-- RF-062 — pgTAP: an order with a completed payment cannot be voided
-- ============================================================================
-- Proves the RF-062 guard + that all pre-existing void_order behavior is preserved.
-- A real paid order is built via the RPC chain (open_shift -> submit_order ->
-- record_payment, leaving the order at 'submitted' with a `completed` payment — D-025
-- does not advance status), plus an unpaid order and a 'completed'-STATUS order.
--   * manager/owner cannot void the paid order (permission_denied + detail) — no mutation;
--   * a default cashier (no void deny) is likewise blocked by the payment;
--   * an UNPAID eligible order still voids (happy path, items cascade, audit + ledger);
--   * an EXPLICITLY-DENIED cashier (permissions.void_order='false',
--     STAFF-CASHIER-PERMISSIONS-001) still hits the AUTHORIZATION denial first
--     (the payment guard runs AFTER authorization — no payment-state leak);
--   * a 'completed'-STATUS order is still rejected by state legality (42501);
--   * idempotency: a prior successful void replays; a paid-order denial writes no ledger.
-- Fixtures inserted as the BYPASSRLS connection role; RPCs derive actor/role from the
-- PIN session (callable as the connection role, matching the RF-052..057 test pattern).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf062a-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf062a-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf062a-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf062a-cashier-perm@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{"void_order":"false"}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-00000000ab03');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- RESTAURANT-OPERATIONS-V1-001: dine_in submits now REQUIRE a live active table
-- in the session's org/restaurant/branch — add one fixture table for both orders.
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF062 T1', true);

-- build a PAID order (O1) + an UNPAID order (O2) via the real RPC chain (cashier c502)
select app.open_shift('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);
select app.submit_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-s1','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-p1','cash',1000,null);
select app.submit_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-s2','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
-- a 'completed'-STATUS order (O5), inserted directly as the owner (terminal status)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d5', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','completed','USD',1000,1000,'o5-fixt');

-- ===== T1: manager CANNOT void the PAID order ================================ 1-6
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v1','correction',null) ->> 'error'), 'permission_denied',
  'manager void of a PAID order returns permission_denied');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v1b','correction',null) ->> 'detail'), 'order_has_completed_payment',
  'the denial carries detail=order_has_completed_payment');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d1')::text, 'submitted', 'paid order status is UNCHANGED after the denied void');
select is((select status from payments where order_id='00000000-0000-0000-0000-00000000a0d1')::text, 'completed', 'the completed payment is UNCHANGED');
select ok(exists(select 1 from audit_events where action='order.void_denied'
                   and (new_values->>'denied_reason')='order_has_completed_payment'
                   and (new_values->>'order_id')='00000000-0000-0000-0000-00000000a0d1'),
  'an order.void_denied audit row with denied_reason=order_has_completed_payment was written');
select is((select count(*) from order_operations where action='void_order' and order_id='00000000-0000-0000-0000-00000000a0d1')::int, 0,
  'NO order_operations void ledger row was written for the denied paid order');

-- ===== T2: a DEFAULT cashier (no void deny) is ALSO blocked ================== 7-8
select is((app.void_order('00000000-0000-0000-0000-00000000c503','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v2','perm void',null) ->> 'detail'), 'order_has_completed_payment',
  'a default cashier (no void deny) is blocked by the completed payment');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d1')::text, 'submitted', 'paid order still unchanged after the authorized-cashier denial');

-- ===== T3: UNPAID eligible order still voids (happy path preserved) =========== 9-13
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-v3','void unpaid',null) ->> 'ok')::boolean, true,
  'manager void of an UNPAID eligible order SUCCEEDS');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d2')::text, 'voided', 'the unpaid order is voided');
select ok(exists(select 1 from order_items where order_id='00000000-0000-0000-0000-00000000a0d2' and status='voided'),
  'the order_items cascade to voided');
select ok(exists(select 1 from audit_events where action='order.voided' and (new_values->>'status')='voided'),
  'an order.voided audit row was written');
select is((select count(*) from order_operations where action='void_order' and order_id='00000000-0000-0000-0000-00000000a0d2')::int, 1,
  'a void_order ledger row was written for the successful void');

-- ===== T4: explicit-deny cashier still hits AUTH denial first ================ 14-16
select is((app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v4','noperm',null) ->> 'error'), 'permission_denied',
  'a cashier with an explicit void_order=false deny is denied (authorization runs first)');
select ok((app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v4b','noperm',null) ->> 'detail') is null,
  'the plain-cashier denial is the AUTHORIZATION denial (no payment detail) — guard runs after authorization');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d1')::text, 'submitted', 'paid order still unchanged after the cashier authorization denial');

-- ===== T5: 'completed'-STATUS order still rejected by state legality ========== 17
-- MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): still rejected (D-024 terminal — the
-- eligibility set is unchanged), but with the stable, typed domain code instead of an
-- untyped 42501 raise. The POINT of this test survives intact and is now sharper: the
-- STATE-LEGALITY code (invalid_transition / order_not_voidable) is returned, and it is
-- NOT converted into the completed-payment guard (permission_denied /
-- order_has_completed_payment) — the two refusals stay distinguishable.
select ok(
  (select r ->> 'ok' = 'false'
      and r ->> 'error'  = 'invalid_transition'
      and r ->> 'detail' = 'order_not_voidable'
      and r ->> 'detail' <> 'order_has_completed_payment'
      and r ->> 'order_status' = 'completed'
   from app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d5','00000000-0000-0000-0000-00000000da11','op-v5','void completed',null) as r),
  'a completed-STATUS order is rejected by STATE LEGALITY (invalid_transition / order_not_voidable), NOT converted into the payment guard');

-- ===== T7: idempotency =====================================================  18-20
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-v3','void unpaid',null) ->> 'idempotency_replay')::boolean, true,
  'replay of the prior SUCCESSFUL void (same key/order) returns the stored success (idempotent)');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d1')::text, 'submitted',
  'after multiple denied void attempts the paid order is STILL submitted (no mutation)');
select is((select count(*) from order_operations where action='void_order' and order_id='00000000-0000-0000-0000-00000000a0d1')::int, 0,
  'still NO void ledger row for the paid order after repeated denials (denials never write the ledger)');

select * from finish();
rollback;
