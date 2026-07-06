-- ============================================================================
-- RF-REPORT-004 — pgTAP: app.owner_report_range (ranges + comparison + branch-
-- local today + single-day hourly + deeper shift_cash). Additive; owner_daily_
-- report untouched. Org A (Rest A1 tz=UTC: A1a; Rest A3 tz='Etc/GMT-3' (UTC+3):
-- A3a) + Org B. Branch A1a carries billed orders across days D0/D-1/D-2/D-3/D-10/
-- D-40/D-70 (net only; subtotal=net, no order_items needed) plus a CLOSED shift
-- ST1 (opening float 5000, expected 6500/counted 6450/var -50) with two cash
-- payments stamped to it, and an OPEN shift SO1. A3a carries a LOCAL-today 00:30
-- order (UTC-yesterday) and a LOCAL-yesterday order to prove branch-local windows.
-- Asserts: today/yesterday/last7/last30 current + prior-period comparison; hourly
-- present only for single-day ranges (empty for multi-day); shift_cash v2 (float,
-- opened_by, duration, FK-stamped per-shift order/collected/cash from
-- payments.shift_id); branch-local windowing; integer-minor shape; invalid range
-- 22023; kitchen_staff denied; cross-org 42501; wrapper INVOKER/no-anon/locked.
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(31);

-- ===== fixture: Org A (Rest A1 tz=UTC + Rest A3 tz=Etc/GMT-3) and Org B ========
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'orr-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'orr-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a0000', 'Rest A3', 'Etc/GMT-3'),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a', null),
  ('00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', 'Branch A3a', null),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', 'active'),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-00000000c005'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'orr-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'orr-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'orr-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Bianca O.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000e005', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour');

-- ---- Branch A1a (tz=UTC) billed orders across days; net = subtotal (no items).
-- D0: O_today1 net1000 @10:00, O_today2 net500 @10:30 (both cash, shift ST1).
-- D-1: O_yest 800 @12:00. D-2: 600. D-3: 400. D-10: 2000. D-40: 3000. D-70: 9999.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 1000, 0, 0, 1000, 'orr-o-t1', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway', 'completed', 'ILS', 500, 0, 0, 500, 'orr-o-t2', (current_date + interval '10 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 800, 0, 0, 800, 'orr-o-y', (current_date - 1 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 600, 0, 0, 600, 'orr-o-d2', (current_date - 2 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 400, 0, 0, 400, 'orr-o-d3', (current_date - 3 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d010', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 2000, 0, 0, 2000, 'orr-o-d10', (current_date - 10 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d040', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 3000, 0, 0, 3000, 'orr-o-d40', (current_date - 40 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d070', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 9999, 0, 0, 9999, 'orr-o-d70', (current_date - 70 + interval '12 hours') at time zone 'UTC');

-- ---- Branch A3a (tz=Etc/GMT-3 = UTC+3): LOCAL-today 00:30 (UTC-yesterday) and a
-- LOCAL-yesterday order, both built from the BRANCH zone so they are deterministic.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001da01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 1111, 0, 0, 1111, 'orr-a3-t', ((now() at time zone 'Etc/GMT-3')::date + interval '30 minutes') at time zone 'Etc/GMT-3'),
  ('00000000-0000-0000-0000-00000001da02', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 2222, 0, 0, 2222, 'orr-a3-y', ((now() at time zone 'Etc/GMT-3')::date - 1 + interval '12 hours') at time zone 'Etc/GMT-3');

-- ---- Shift ST1 on A1a CLOSED today (opened 09:00, closed 18:00 -> 540 min).
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, expected_total_minor, counted_total_minor, variance_minor, opened_at, closed_at, local_operation_id) values
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'closed', 6500, 6450, -50, (current_date + interval '9 hours') at time zone 'UTC', (current_date + interval '18 hours') at time zone 'UTC', 'orr-st1'),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'open', null, null, null, (current_date + interval '19 hours') at time zone 'UTC', null, 'orr-so1');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('00000000-0000-0000-0000-0000000cd501', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000e0f01', 5000, 'orr-cds1');

-- ---- Cash payments for today's two orders, STAMPED to shift ST1 (RF-117 path).
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000003b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000cd501', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'orr-p1', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003b002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000cd501', 'cash', 'completed', 500, 500, 0, 'ILS', 'orr-p2', (current_date + interval '10 hours 30 minutes') at time zone 'UTC');

-- ===== range report calls (org_owner, scoped to Branch A1a to isolate A3a) =====
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_today as select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today')     as res;
create temp table t_yest  as select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'yesterday') as res;
create temp table t_w7    as select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'last7')     as res;
create temp table t_w30   as select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'last30')    as res;
create temp table t_a3t   as select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', 'today')     as res;
create temp table t_a3y   as select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', 'yesterday') as res;
reset role;

-- ===== (1) envelope ==========================================================
select ok(
  (select (res->>'ok')::boolean = true and res->>'entity' = 'owner_report_range'
      and res->>'range' = 'today' and res->>'currency_code' = 'ILS' from t_today),
  'today: ok/entity/range/currency envelope');

-- ===== (2-6) TODAY current + comparison ======================================
select is((select (res->'current'->>'net_minor')::bigint from t_today), 1500::bigint, 'today net_minor = 1500 (1000+500)');
select is((select (res->'current'->>'order_count')::int from t_today), 2, 'today order_count = 2');
select is((select (res->'current'->>'cash_minor')::bigint from t_today), 1500::bigint, 'today cash_minor = 1500 (both cash)');
select is((select (res->'comparison'->>'net_minor')::bigint from t_today), 800::bigint, 'today comparison net = 800 (yesterday D-1)');
select is((select (res->'comparison'->>'order_count')::int from t_today), 1, 'today comparison order_count = 1');

-- ===== (7-9) TODAY hourly (single-day => present) =============================
select is((select jsonb_array_length(res->'hourly') from t_today), 24, 'today hourly has 24 buckets');
select is((select (res->'hourly'->10->>'net_minor')::bigint from t_today), 1500::bigint, 'today hour 10 = 1500 (both orders)');
select is(
  (select sum((h->>'net_minor')::bigint)::bigint from t_today, jsonb_array_elements(res->'hourly') h),
  1500::bigint, 'today hourly total reconciles with current net (1500)');

-- ===== (10-12) YESTERDAY current + comparison + hourly ========================
select is((select (res->'current'->>'net_minor')::bigint from t_yest), 800::bigint, 'yesterday net = 800');
select is((select (res->'comparison'->>'net_minor')::bigint from t_yest), 600::bigint, 'yesterday comparison net = 600 (D-2)');
select ok(
  (select jsonb_array_length(res->'hourly') = 24
      and (res->'hourly'->12->>'net_minor')::bigint = 800 from t_yest),
  'yesterday hourly present (single-day), hour 12 = 800');

-- ===== (13-16) LAST7 current + comparison + hourly EMPTY (multi-day) ==========
select is((select (res->'current'->>'net_minor')::bigint from t_w7), 3300::bigint,
          'last7 net = 3300 (D0 1500 + D-1 800 + D-2 600 + D-3 400)');
select is((select (res->'current'->>'order_count')::int from t_w7), 5, 'last7 order_count = 5');
select is((select (res->'comparison'->>'net_minor')::bigint from t_w7), 2000::bigint,
          'last7 comparison net = 2000 (prev 7 days: D-10)');
select is((select jsonb_array_length(res->'hourly') from t_w7), 0, 'last7 hourly EMPTY (multi-day, chart hides)');

-- ===== (17-19) LAST30 current + comparison + hourly EMPTY =====================
select is((select (res->'current'->>'net_minor')::bigint from t_w30), 5300::bigint,
          'last30 net = 5300 (3300 + D-10 2000; D-70 9999 excluded)');
select is((select (res->'comparison'->>'net_minor')::bigint from t_w30), 3000::bigint,
          'last30 comparison net = 3000 (prev 30 days: D-40)');
select is((select jsonb_array_length(res->'hourly') from t_w30), 0, 'last30 hourly EMPTY (multi-day)');

-- ===== (20) shift_cash v2: today closed aggregates ===========================
select ok(
  (select (res->'shift_cash'->>'closed_shift_count')::int = 1
      and (res->'shift_cash'->>'expected_cash_minor')::bigint = 6500
      and (res->'shift_cash'->>'counted_cash_minor')::bigint = 6450
      and (res->'shift_cash'->>'cash_variance_minor')::bigint = -50 from t_today),
  'today shift_cash: 1 closed, expected 6500, counted 6450, variance -50 (stored RF-055)');

-- ===== (21) last_closed_shift: opening float + duration =======================
select ok(
  (select (res->'shift_cash'->'last_closed_shift'->>'opening_float_minor')::bigint = 5000
      and (res->'shift_cash'->'last_closed_shift'->>'duration_minutes')::int = 540 from t_today),
  'last_closed_shift: opening float 5000, duration 540 min (09:00->18:00)');

-- ===== (22) last_closed_shift: FK-stamped per-shift order/collected/cash =======
select ok(
  (select (res->'shift_cash'->'last_closed_shift'->>'order_count')::int = 2
      and (res->'shift_cash'->'last_closed_shift'->>'collected_minor')::bigint = 1500
      and (res->'shift_cash'->'last_closed_shift'->>'cash_sales_minor')::bigint = 1500 from t_today),
  'last_closed_shift: 2 orders, collected 1500, cash 1500 (from payments.shift_id)');

-- ===== (23) last_closed_shift: opened_by + closed_by names =====================
select ok(
  (select res->'shift_cash'->'last_closed_shift'->>'opened_by_name' = 'Amira K.'
      and res->'shift_cash'->'last_closed_shift'->>'closed_by_name' = 'Amira K.' from t_today),
  'last_closed_shift: opened_by + closed_by = Amira K. (employee_profiles.display_name)');

-- ===== (24) open_shift_count live (SO1) ======================================
select is((select (res->'shift_cash'->>'open_shift_count')::int from t_today), 1, 'open_shift_count = 1 (SO1 open now)');

-- ===== (25-26) branch-local windowing on A3a (tz=Etc/GMT-3) ===================
select is((select (res->'current'->>'net_minor')::bigint from t_a3t), 1111::bigint,
          'A3a today = 1111 (LOCAL-today 00:30 order counted branch-local, not UTC-yesterday)');
select is((select (res->'current'->>'net_minor')::bigint from t_a3y), 2222::bigint,
          'A3a yesterday = 2222 (branch-local yesterday window)');

-- ===== (27) integer-minor shape ==============================================
select ok(
  (select jsonb_typeof(res->'current'->'net_minor') = 'number'
      and jsonb_typeof(res->'comparison'->'net_minor') = 'number'
      and jsonb_typeof(res->'shift_cash'->'last_closed_shift'->'opening_float_minor') = 'number'
      and jsonb_typeof(res->'shift_cash'->'last_closed_shift'->'collected_minor') = 'number' from t_today),
  'money fields are integer-shaped JSON numbers (no float text)');

-- ===== (28) invalid range -> 22023 (bad request, not a denial) ===============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select throws_ok(
  $$ select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter') $$,
  '22023', NULL, 'unknown range raises 22023 (invalid parameter, not a silent default)');
reset role;

-- ===== (29) kitchen_staff DENIED =============================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is(
  (select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today')->>'error'),
  'permission_denied', 'kitchen_staff cannot read owner_report_range (permission_denied)');
reset role;

-- ===== (30) cross-org caller structurally rejected (42501) ===================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_report_range('00000000-0000-0000-0000-0000000b0000', null, null, 'today') $$,
  '42501', NULL, 'an Org A owner cannot read the Org B range report (cross-org 42501)');
reset role;

-- ===== (31) public wrapper: INVOKER + locked search_path + no anon/PUBLIC ======
select ok(
  (select prosecdef = false from pg_proc where proname='owner_report_range' and pronamespace='public'::regnamespace and pronargs=4)
  and (select exists(
     select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='owner_report_range' and p.pronamespace='public'::regnamespace and p.pronargs=4 and cfg like 'search_path=%'))
  and not has_function_privilege('anon', 'public.owner_report_range(uuid, uuid, uuid, text)', 'execute')
  and not has_function_privilege('public', 'public.owner_report_range(uuid, uuid, uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_report_range(uuid, uuid, uuid, text)', 'execute'),
  'public.owner_report_range is INVOKER, search_path-locked, authenticated-only (no anon/PUBLIC)');

select * from finish();
rollback;
