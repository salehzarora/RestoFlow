-- ============================================================================
-- RF-053 — pgTAP: idempotency-replay security (RF053-B1)
-- ============================================================================
-- Authorization runs BEFORE the idempotency replay, and the replay is ORDER-BOUND:
--   * an unauthorized actor on the same device CANNOT replay a prior SUCCESS — they
--     are denied (no leak, no duplicate state, no duplicate success audit);
--   * the same (org, device, local_operation_id, action) reused on a DIFFERENT order
--     is a conflict, not a replay (never returns the original order's result).
-- Proven for both void_order and apply_discount. Fixtures inserted as the BYPASSRLS
-- connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf053b1-a', 'USD');
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
-- manager (authorized) and a plain cashier (no void/discount permission), same device
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf053b1-mgr@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf053b1-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
-- four submitted orders: A/B for void, C/D for discount
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'seed-A'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'seed-B'),
  ('00000000-0000-0000-0000-00000000a0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'seed-C'),
  ('00000000-0000-0000-0000-00000000a0d4', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'seed-D');

-- ===== VOID: authorized manager voids order A with key 'k-v' =================
select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','k-v','manager void', null);

-- 1) an unauthorized cashier REPLAYING the same key is DENIED (no success leak) - 1
select is(
  (app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','k-v','retry', null) ->> 'error'),
  'permission_denied', 'unauthorized replay of a stored void SUCCESS is denied, not leaked');
-- 2) order A unchanged by the denied replay (still voided at the manager revision) - 2
select is((select status || ':' || revision from orders where id='00000000-0000-0000-0000-00000000a0d1'), 'voided:2', 'order A unchanged by the denied replay (no duplicate state mutation)');
-- 3) exactly one success audit (the manager's) ------------------------------- 3
select is((select count(*) from audit_events where action='order.voided')::int, 1, 'no duplicate order.voided success audit');
-- 4) the denied replay wrote exactly one void_denied audit ------------------- 4
select is((select count(*) from audit_events where action='order.void_denied')::int, 1, 'the unauthorized replay attempt is audited (order.void_denied)');
-- 5) same key on a DIFFERENT order is a conflict, not a replay --------------- 5
select throws_ok($$ select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','k-v','reuse key', null) $$, '40001', NULL,
  'reusing the same void key on a DIFFERENT order is a conflict (40001), not a replay');
-- 6) order B was not mutated by the conflicting attempt --------------------- 6
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d2')::text, 'submitted', 'order B unchanged by the same-key/different-order conflict');

-- ===== DISCOUNT: authorized manager discounts order C with key 'k-d' ========
select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','k-d','order',null,'fixed',100,'manager promo', null);

-- 7) unauthorized cashier replaying the discount key is DENIED --------------- 7
select is(
  (app.apply_discount('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','k-d','order',null,'fixed',100,'retry', null) ->> 'error'),
  'permission_denied', 'unauthorized replay of a stored discount SUCCESS is denied, not leaked');
-- 8) order C discount unchanged (no double-apply) --------------------------- 8
select is((select discount_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d3')::bigint, 100::bigint, 'order C discount unchanged by the denied replay');
-- 9) exactly one discount success audit ------------------------------------- 9
select is((select count(*) from audit_events where action='order.discount_applied')::int, 1, 'no duplicate order.discount_applied success audit');
-- 10) the denied replay wrote exactly one discount_denied audit ------------- 10
select is((select count(*) from audit_events where action='order.discount_denied')::int, 1, 'the unauthorized discount replay attempt is audited (order.discount_denied)');
-- 11) same key on a DIFFERENT order is a conflict --------------------------- 11
select throws_ok($$ select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d4','00000000-0000-0000-0000-00000000da11','k-d','order',null,'fixed',100,'reuse key', null) $$, '40001', NULL,
  'reusing the same discount key on a DIFFERENT order is a conflict (40001), not a replay');
-- 12) order D not discounted by the conflicting attempt -------------------- 12
select is((select discount_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d4')::bigint, 0::bigint, 'order D unchanged by the same-key/different-order conflict');

select * from finish();
rollback;
