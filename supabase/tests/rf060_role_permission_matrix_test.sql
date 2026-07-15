-- ============================================================================
-- RF-060 — CANONICAL gate: role permission matrix (T-003, T-006 full, T-011)
-- ============================================================================
-- T-003 kitchen_staff cannot read financials (direct rows + no money keys via sync_pull);
-- T-006 (FULL, RF-062 + STAFF-CASHIER-PERMISSIONS-001): a cashier with an explicit
--   void deny (permissions.void_order='false') is denied — a plain default cashier is
--   now ALLOWED to void an unpaid order (staff_cashier_permissions_001_test.sql);
--   and a manager OR a default cashier CANNOT void an order with a live completed
--   payment (permission_denied + detail=order_has_completed_payment + order.void_denied
--   audit + no mutation + no success ledger), while an unpaid eligible order still voids;
-- T-011 accountant is strictly read-only (every mutating RPC denied).
-- A real paid order is built via open_shift -> submit_order -> record_payment (D-025:
-- status stays 'submitted'). Fixtures as the BYPASSRLS connection role; RPCs invoked as
-- the connection role (role derived from the PIN session); direct financial reads under
-- `set local role authenticated` + the GUC principal.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(23);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf060rpm-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf060rpm-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf060rpm-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf060rpm-cashier-perm@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf060rpm-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000ee05', 'rf060rpm-accountant@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{"void_order":"false"}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab05', '00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'accountant', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-00000000ab03'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04'),
  ('00000000-0000-0000-0000-0000000ef005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-00000000ab05');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c505', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef005', '00000000-0000-0000-0000-00000000ab05', now() + interval '1 hour');

-- Live active dining table in the SAME org/restaurant/branch as the PIN sessions
-- (RESTAURANT-OPERATIONS-V1-001: dine_in submits now REQUIRE a valid table).
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF060 T1', true);

-- Sellable menu fixture (RESTAURANT-OPERATIONS-V1-001 A1: submit_order now requires
-- every payload menu_item_id to be a proven-sellable menu item in the submitting org).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item', 1000, 'USD', 1);

-- PAID order O1 + UNPAID order O2 via the RPC chain (cashier c501); completed-status O5 direct
select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-s1','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-p1','cash',1000,null);
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-s2','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d5', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','completed','USD',1000,1000,'o5-fixt');

-- ===== T-003 kitchen_staff cannot read financials =========================== 1-5
select ok(
  (select bool_and(not (r ? 'grand_total_minor')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'T-003: kitchen sync_pull orders rows carry NO grand_total_minor (money redacted)');
-- RF060-B2: generically prove NO kitchen-visible orders-row key matches the money
-- token rule (^|_)minor($|_) (RF-059 redaction), not just the single grand_total_minor key.
select is(
  (select count(*)
     from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') as r
     cross join lateral jsonb_object_keys(r) as keys(key)
    where keys.key ~ '(^|_)minor($|_)')::int,
  0, 'T-003: NO kitchen orders-row key matches the money token (^|_)minor($|_) — full redaction (RF-059), not just grand_total_minor');
select ok(
  (select bool_and(r ? 'status') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'T-003: kitchen sync_pull orders rows keep the non-money status field');
select ok(
  (select bool_or(r ? 'grand_total_minor') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'T-003 control: cashier sync_pull orders rows KEEP grand_total_minor (financial role, no over-redaction)');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee04';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from payments)::int, 0, 'T-003: kitchen_staff direct SELECT on payments returns ZERO rows');
select is((select count(*) from shifts)::int,   0, 'T-003: kitchen_staff direct SELECT on shifts returns ZERO rows');
reset role;

-- ===== T-006 cashier-no-permission + paid-order void (RF-062 canonical) ====== 6-16
select ok((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v0','noperm',null) ->> 'detail') is null,
  'T-006: an explicit-deny cashier (void_order=false) hits the AUTHORIZATION denial (no payment detail)');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v0b','noperm',null) ->> 'error'), 'permission_denied',
  'T-006: the explicit-deny cashier void returns permission_denied');
select is((app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v1','manager paid void',null) ->> 'error'), 'permission_denied',
  'T-006: a MANAGER cannot void an order with a live completed payment (RF-062)');
select is((app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v1b','manager paid void',null) ->> 'detail'), 'order_has_completed_payment',
  'T-006: the paid-order void denial carries detail=order_has_completed_payment');
select is((app.void_order('00000000-0000-0000-0000-00000000c503','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v2','perm cashier paid void',null) ->> 'detail'), 'order_has_completed_payment',
  'T-006: a DEFAULT cashier (no void deny) is also blocked by the completed payment');
-- RF060-B1: the authorized-cashier paid-order denial also carries error=permission_denied (not just detail)
select is((app.void_order('00000000-0000-0000-0000-00000000c503','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-v2b','perm cashier paid void',null) ->> 'error'), 'permission_denied',
  'T-006: the authorized-cashier paid-order void returns error=permission_denied');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d1')::text, 'submitted',
  'T-006: the paid order is UNCHANGED after the denied voids');
select is((select status from payments where order_id='00000000-0000-0000-0000-00000000a0d1')::text, 'completed',
  'T-006: the completed payment is UNCHANGED');
-- RF060-B1: the paid-order denial also leaves order_items UNCHANGED (no cascade to voided)
select is((select count(*) from order_items where order_id='00000000-0000-0000-0000-00000000a0d1' and status <> 'pending')::int, 0,
  'T-006: the paid-order void denial did NOT mutate order_items (all still pending, no void cascade)');
select ok(exists(select 1 from audit_events where action='order.void_denied'
                   and (new_values->>'denied_reason')='order_has_completed_payment'
                   and (new_values->>'order_id')='00000000-0000-0000-0000-00000000a0d1'),
  'T-006: an order.void_denied audit row with denied_reason=order_has_completed_payment was written');
select is((select count(*) from order_operations where action='void_order' and order_id='00000000-0000-0000-0000-00000000a0d1')::int, 0,
  'T-006: NO success void ledger row for the paid order');
select is((app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-v3','void unpaid',null) ->> 'ok')::boolean, true,
  'T-006: an UNPAID eligible order is still voided by a manager');
-- MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): eligibility is UNCHANGED — a completed
-- order is still refused (D-024 terminal) — but the refusal is now the stable, typed
-- domain code instead of an untyped 42501 raise (which app.sync_push flattened into a
-- generic 'rejected'). The assertion is strengthened accordingly.
select ok(
  (select r ->> 'ok' = 'false' and r ->> 'error' = 'invalid_transition'
      and r ->> 'detail' = 'order_not_voidable' and r ->> 'order_status' = 'completed'
   from app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d5','00000000-0000-0000-0000-00000000da11','op-v5','void completed',null) as r),
  'T-006: a completed-STATUS order is rejected by state legality (invalid_transition / order_not_voidable)');

-- ===== T-011 accountant is strictly read-only ============================== 17-20
select throws_ok(
  $$ select app.submit_order('00000000-0000-0000-0000-00000000c505','00000000-0000-0000-0000-00000000a0da','00000000-0000-0000-0000-00000000da11','op-acc-s','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,'[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) $$,
  '42501', NULL, 'T-011: accountant cannot submit_order (role denied, 42501)');
select is((app.record_payment('00000000-0000-0000-0000-00000000c505','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-acc-p','cash',1000,null) ->> 'error'), 'permission_denied',
  'T-011: accountant record_payment is denied (permission_denied)');
select is((app.close_shift('00000000-0000-0000-0000-00000000c505','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','op-acc-c',5000,null,null) ->> 'error'), 'permission_denied',
  'T-011: accountant close_shift is denied (permission_denied)');
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c505','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','op-acc-r',null,null) ->> 'error'), 'permission_denied',
  'T-011: accountant reconcile_shift is denied (separation of duties, D-028)');

select * from finish();
rollback;
