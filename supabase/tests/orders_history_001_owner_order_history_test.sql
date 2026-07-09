-- ============================================================================
-- ORDERS-HISTORY-001 — pgTAP: app.owner_order_history (LIST) + app.owner_order_
-- detail (DETAIL). Org A (Rest A1 tz=UTC: Branch A1a) + Org B, to prove tenant
-- isolation. Branch A1a: O1 today 10:00 (Layla, table T1, dine_in, COMPLETED,
-- 1 item Burger x2 + Double modifier meat_snapshot + prep_snapshot, cash-paid
-- 1000); O2 today 11:00 (NULL customer, takeaway, SUBMITTED, 1 item, UNPAID,
-- 500); O3 yesterday (Sami, completed, paid 800); O4 D-10 (completed 2000). Org
-- B: O_B today (isolation). Asserts: envelope; today list (order/paid/customer/
-- table/item_count/order_code); range windows (yesterday/last7/last30); status /
-- order_type / payment filters; search by code/customer/table; keyset pagination
-- (limit + cursor + has_more); NULL customer_name; integer-minor shape; DETAIL
-- header+items+modifiers(meat)+prep+payments; NULL-customer detail; out-of-scope
-- -> not_found; kitchen_staff denied (list+detail); cross-org 42501 (list+detail);
-- unknown range 22023; invalid cursor 22023; both wrappers INVOKER/locked/no-anon.
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(36);

-- ===== fixture: Org A (Rest A1 tz=UTC, Branch A1a) and Org B ==================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'oh-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'oh-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a', null),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'oh-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'oh-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'oh-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Bianca O.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('00000000-0000-0000-0000-0000000fa001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'T1');

-- ---- Orders on A1a. O1 code #01D001; O2 #01D002; O3 #01D003; O4 #01D010.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, table_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, receipt_number, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000fa001', 'dine_in', 'completed', 'ILS', 1000, 0, 0, 1000, 'Layla', 'R-100', 'oh-o1', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'takeaway', 'submitted', 'ILS', 500, 0, 0, 500, null, null, 'oh-o2', (current_date + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in', 'completed', 'ILS', 800, 0, 0, 800, 'Sami', 'R-099', 'oh-o3', (current_date - 1 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d010', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in', 'completed', 'ILS', 2000, 0, 0, 2000, 'Old', 'R-090', 'oh-o4', (current_date - 10 + interval '12 hours') at time zone 'UTC');
-- Org B order today (isolation).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001db01', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'completed', 'EUR', 7777, 0, 0, 7777, 'oh-ob', (current_date + interval '10 hours') at time zone 'UTC');

-- ---- Items: O1 Burger x2 (+ Double modifier meat_snapshot + prep_snapshot); O2 Fries x1; O3 Salad x1.
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor, prep_snapshot) values
  ('00000000-0000-0000-0000-00000011d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000e1001', 2, 'Burger', 500, 1000, '[{"name":"Bun","quantity":1,"unit":"pcs"}]'::jsonb),
  ('00000000-0000-0000-0000-00000011d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000e1002', 1, 'Fries', 500, 500, null),
  ('00000000-0000-0000-0000-00000011d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000e1003', 1, 'Salad', 800, 800, null);
insert into order_item_modifiers (id, organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot) values
  ('00000000-0000-0000-0000-0000001ad001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000011d001', '00000000-0000-0000-0000-0000000e9001', 'Patty', 'Double', 0, 1, '{"quantity":2,"unit":"patties"}'::jsonb);

-- ---- Cash payments: O1 (1000, today) and O3 (800, yesterday) completed. O2 unpaid.
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, receipt_number, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000003b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'R-100', 'oh-p1', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003b003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 800, 800, 0, 'ILS', 'R-099', 'oh-p3', (current_date - 1 + interval '12 hours') at time zone 'UTC');

-- ===== calls (org_owner, scoped to Branch A1a) ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_today  as select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today')     as res;
create temp table t_yest   as select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'yesterday') as res;
create temp table t_w7     as select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'last7')     as res;
create temp table t_w30    as select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'last30')    as res;
create temp table t_detail as select app.owner_order_detail('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001') as res;
create temp table t_det2   as select app.owner_order_detail('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002') as res;
reset role;

-- ===== (1) envelope ==========================================================
select ok(
  (select (res->>'ok')::boolean = true and res->>'entity' = 'owner_order_history'
      and res->>'range' = 'today' and res->>'currency_code' = 'ILS'
      and (res->>'limit')::int = 25 from t_today),
  'today: ok/entity/range/currency/limit envelope');

-- ===== (2-4) today list: order, count, newest-first =========================
select is((select jsonb_array_length(res->'orders') from t_today), 2, 'today has 2 orders (O1, O2)');
select is((select res->'orders'->0->>'order_code' from t_today), '#01D002', 'newest-first: O2 (11:00) is first');
select is((select res->'orders'->1->>'order_code' from t_today), '#01D001', 'then O1 (10:00)');

-- ===== (5-8) row content: customer / table / item_count / paid ===============
select is((select res->'orders'->1->>'customer_name' from t_today), 'Layla', 'O1 customer_name = Layla');
select is((select res->'orders'->1->>'table_label' from t_today), 'T1', 'O1 table_label = T1');
select is((select (res->'orders'->1->>'item_count')::int from t_today), 2, 'O1 item_count = 2 (Burger x2)');
select ok(
  (select res->'orders'->1->>'payment_status' = 'paid'
      and res->'orders'->1->>'payment_method' = 'cash'
      and (res->'orders'->1->>'paid_amount_minor')::bigint = 1000
      and res->'orders'->1->>'staff_name' = 'Amira K.' from t_today),
  'O1 paid cash 1000 by Amira K.');

-- ===== (9) O2 NULL customer + unpaid =========================================
select ok(
  (select res->'orders'->0->>'customer_name' is null
      and res->'orders'->0->>'payment_status' = 'unpaid'
      and res->'orders'->0->>'payment_method' is null from t_today),
  'O2 has NULL customer_name and is unpaid (payment_method null)');

-- ===== (10-11) has_more/cursor (full page) ===================================
select is((select (res->>'has_more')::boolean from t_today), false, 'today has_more = false (both fit)');
select is((select res->>'next_cursor' from t_today), null, 'today next_cursor = null (no more)');

-- ===== (12-13) range windows =================================================
select is((select jsonb_array_length(res->'orders') from t_yest), 1, 'yesterday: 1 order (O3)');
select is((select jsonb_array_length(res->'orders') from t_w7), 3, 'last7: 3 orders (O1,O2,O3)');
-- last30 counted separately below to keep numbering:
select is((select jsonb_array_length(res->'orders') from t_w30), 4, 'last30: 4 orders (O1,O2,O3,O4)');  -- (14)

-- ===== (15-18) filters (today scope) =========================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select jsonb_array_length(app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today',null,'submitted')->'orders')),
  1, 'status=submitted filter -> 1 (O2)');
select is(
  (select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today',null,null,'dine_in')->'orders'->0->>'order_code'),
  '#01D001', 'order_type=dine_in filter -> O1');
select is(
  (select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today',null,null,null,'unpaid')->'orders'->0->>'order_code'),
  '#01D002', 'payment=unpaid filter -> O2');
select is(
  (select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today',null,null,null,'cash')->'orders'->0->>'order_code'),
  '#01D001', 'payment=cash filter -> O1');

-- ===== (19-21) search by code / customer / table =============================
select is(
  (select jsonb_array_length(app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today','#01D001')->'orders')),
  1, 'search "#01D001" -> 1 (O1 by code)');
select is(
  (select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today','layla')->'orders'->0->>'customer_name'),
  'Layla', 'search "layla" -> O1 (case-insensitive customer)');
select is(
  (select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today','T1')->'orders'->0->>'order_code'),
  '#01D001', 'search "T1" -> O1 (table label)');

-- ===== (22-24) keyset pagination: limit 1 then follow the cursor =============
create temp table t_p1 as select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today',null,null,null,null,1,null) as res;
select ok(
  (select (res->>'has_more')::boolean = true
      and jsonb_array_length(res->'orders') = 1
      and res->'orders'->0->>'order_code' = '#01D002'
      and res->>'next_cursor' is not null from t_p1),
  'page 1 (limit 1): O2, has_more true, cursor present');
create temp table t_p2 as select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today',null,null,null,null,1,(select res->>'next_cursor' from t_p1)) as res;
select is((select res->'orders'->0->>'order_code' from t_p2), '#01D001', 'page 2 (cursor): O1');
select is((select (res->>'has_more')::boolean from t_p2), false, 'page 2 has_more = false (end)');
reset role;

-- ===== (25) integer-minor shape ==============================================
select ok(
  (select jsonb_typeof(res->'orders'->1->'grand_total_minor') = 'number'
      and jsonb_typeof(res->'orders'->1->'paid_amount_minor') = 'number' from t_today),
  'list money fields are integer-shaped JSON numbers (no float text)');

-- ===== (26-29) DETAIL: header + items + modifier(meat) + prep + payments =====
select ok(
  (select (res->>'ok')::boolean = true and res->>'entity' = 'owner_order_detail'
      and res->'order'->>'order_code' = '#01D001'
      and res->'order'->>'customer_name' = 'Layla'
      and res->'order'->>'table_label' = 'T1'
      and res->'order'->>'staff_name' = 'Amira K.'
      and (res->'order'->>'grand_total_minor')::bigint = 1000 from t_detail),
  'detail O1: header (code/customer/table/staff/total)');
select ok(
  (select jsonb_array_length(res->'order'->'items') = 1
      and res->'order'->'items'->0->>'name' = 'Burger'
      and (res->'order'->'items'->0->>'quantity')::int = 2
      and res->'order'->'items'->0->'prep_snapshot'->0->>'name' = 'Bun' from t_detail),
  'detail O1: 1 item Burger x2 with prep_snapshot Bun');
select ok(
  (select jsonb_array_length(res->'order'->'items'->0->'modifiers') = 1
      and res->'order'->'items'->0->'modifiers'->0->>'option_name' = 'Double'
      and res->'order'->'items'->0->'modifiers'->0->'meat_snapshot'->>'unit' = 'patties'
      and (res->'order'->'items'->0->'modifiers'->0->'meat_snapshot'->>'quantity')::int = 2 from t_detail),
  'detail O1: Double modifier carries meat_snapshot 2 patties');
select ok(
  (select jsonb_array_length(res->'order'->'payments') = 1
      and res->'order'->'payments'->0->>'method' = 'cash'
      and (res->'order'->'payments'->0->>'amount_minor')::bigint = 1000 from t_detail),
  'detail O1: 1 cash payment 1000');

-- ===== (30) DETAIL NULL customer + empty payments ============================
select ok(
  (select res->'order'->>'customer_name' is null
      and jsonb_array_length(res->'order'->'payments') = 0
      and jsonb_array_length(res->'order'->'items') = 1 from t_det2),
  'detail O2: NULL customer, no payments, 1 item (no crash)');

-- ===== (31) DETAIL out-of-scope order -> not_found (no cross-tenant leak) =====
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select app.owner_order_detail('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000001db01')->>'error'),
  'not_found', 'Org A owner asking for an Org B order id -> not_found (scoped, no leak)');
reset role;

-- ===== (32) kitchen_staff DENIED (list + detail) =============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select ok(
  (select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today')->>'error' = 'permission_denied'
      and app.owner_order_detail('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000001d001')->>'error' = 'permission_denied'),
  'kitchen_staff cannot read history or detail (permission_denied)');
reset role;

-- ===== (33) cross-org caller structurally rejected (42501) ===================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_order_history('00000000-0000-0000-0000-0000000b0000', null, null, 'today') $$,
  '42501', NULL, 'Org A owner cannot read Org B history (cross-org 42501)');
reset role;

-- ===== (34) unknown range -> 22023 (bad request, not a denial) ===============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select throws_ok(
  $$ select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter') $$,
  '22023', NULL, 'unknown range raises 22023 (invalid parameter, not a silent default)');
reset role;

-- ===== (35) invalid cursor -> 22023 ==========================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select throws_ok(
  $$ select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, null, 25, 'not-a-cursor') $$,
  '22023', NULL, 'a malformed keyset cursor raises 22023');
reset role;

-- ===== (36) both wrappers INVOKER + locked search_path + no anon/PUBLIC =======
select ok(
  (select prosecdef = false from pg_proc where proname='owner_order_history' and pronamespace='public'::regnamespace and pronargs=10)
  and (select prosecdef = false from pg_proc where proname='owner_order_detail' and pronamespace='public'::regnamespace and pronargs=4)
  and exists (select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
              where p.proname='owner_order_history' and p.pronamespace='public'::regnamespace and p.pronargs=10 and cfg like 'search_path=%')
  and exists (select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
              where p.proname='owner_order_detail' and p.pronamespace='public'::regnamespace and p.pronargs=4 and cfg like 'search_path=%')
  and not has_function_privilege('anon',   'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text)', 'execute')
  and not has_function_privilege('public', 'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text)', 'execute')
  and not has_function_privilege('anon',   'public.owner_order_detail(uuid,uuid,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_order_detail(uuid,uuid,uuid,uuid)', 'execute'),
  'both public wrappers are INVOKER, search_path-locked, authenticated-only (no anon/PUBLIC)');

select * from finish();
rollback;
