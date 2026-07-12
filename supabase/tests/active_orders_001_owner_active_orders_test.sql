-- ============================================================================
-- ACTIVE-ORDERS-001 — pgTAP: app.owner_active_orders (READ-ONLY ops board).
--
-- Fixture: Org A (Rest A1 tz=UTC; Branch A1a tz=Asia/Jerusalem, Branch A1b tz=
-- NULL -> falls back to the restaurant's UTC) + Org B (isolation).
--
-- Branch A1a orders (codes are the last 6 hex of the id, uppercased):
--   #02A001  3 DAYS AGO 09:00  preparing  unpaid   dine_in   Layla, table T1
--   #02A002  today     10:00   submitted  unpaid   takeaway  (null customer)
--   #02A003  today     11:00   ready      PAID cash 1000  dine_in
--   #02A004  today     12:00   served     UNPAID   takeaway   <- served-but-unpaid
--   #02A005  today     12:00   accepted   PAID cash 700   dine_in  <- SAME instant as #02A004 (tie-break)
--   #02A006  today     13:00   completed  paid     TERMINAL -> excluded
--   #02A007  today     13:30   voided     unpaid   TERMINAL -> excluded
--   #02A008  today     14:00   cancelled  unpaid   TERMINAL -> excluded
--   #02A009  today     15:00   draft               local-only pre-state -> excluded
--   #02A00A  today     16:00   preparing  SOFT-DELETED (deleted_at) -> excluded
-- Branch A1b: #02B001 today 10:30 preparing unpaid (branch filter / sibling denial)
-- Org B:      #02C001 today 10:00 preparing (cross-tenant isolation)
--
-- Asserts: envelope; the CANONICAL active set only (terminal + draft + deleted
-- excluded); NO date window (a 3-day-old open order still appears); FIFO order
-- with an id tie-break on equal timestamps; a PAID order stays active; a SERVED
-- order can be UNPAID; scope-wide summary (total/unpaid/by_status); enum-VALIDATED
-- status/order_type/payment filters (a terminal or unknown token -> 22023);
-- search by code/customer/table; branch filter; permitted all-branch scope;
-- sibling-branch denial; cross-tenant 42501 + no leak; kitchen_staff denied;
-- unauthenticated denied; page-size CAP + honest truncated/matching; integer-minor
-- money; created_at_utc + branch-local created_at + resolved timezone; NO private
-- field and NO fabricated due/late key in the payload; the function is STABLE (it
-- structurally cannot write) and no order row changes; the supporting index; and
-- the DEFINER/INVOKER + search_path + no-anon/PUBLIC ACL on both functions.
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(40);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'ao-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'ao-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1b', null),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', 'pos'),
  ('00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', 'active'),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-00000000c002'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'ao-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'ao-manager-a1a@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'ao-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'ao-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Bianca O.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('00000000-0000-0000-0000-0000000fa001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'T1');

-- ---- Branch A1a orders (see the header table). ------------------------------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, table_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, receipt_number, notes, local_operation_id, created_at, deleted_at) values
  ('00000000-0000-0000-0000-00000002a001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000fa001', 'dine_in',  'preparing', 'ILS', 1000, 0, 0, 1000, 'Layla', null,    'PRIVATE-NOTE', 'ao-a1',  (current_date - 3 + interval '9 hours')  at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'takeaway', 'submitted', 'ILS',  500, 0, 0,  500, null,    null,    null, 'ao-a2',  (current_date + interval '10 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'ready',     'ILS', 1000, 0, 0, 1000, null,    'R-201', null, 'ao-a3',  (current_date + interval '11 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'takeaway', 'served',    'ILS',  900, 0, 0,  900, null,    null,    null, 'ao-a4',  (current_date + interval '12 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'accepted',  'ILS',  700, 0, 0,  700, null,    'R-202', null, 'ao-a5',  (current_date + interval '12 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'completed', 'ILS',  600, 0, 0,  600, null,    'R-203', null, 'ao-a6',  (current_date + interval '13 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'voided',    'ILS',  400, 0, 0,  400, null,    null,    null, 'ao-a7',  (current_date + interval '13 hours 30 minutes') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'cancelled', 'ILS',  300, 0, 0,  300, null,    null,    null, 'ao-a8',  (current_date + interval '14 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a009', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'draft',     'ILS',  200, 0, 0,  200, null,    null,    null, 'ao-a9',  (current_date + interval '15 hours')     at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000002a00a', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null, 'dine_in',  'preparing', 'ILS',  100, 0, 0,  100, null,    null,    null, 'ao-a10', (current_date + interval '16 hours')     at time zone 'UTC', now());
-- Branch A1b (sibling branch, tz-less -> restaurant 'UTC').
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000002b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'preparing', 'ILS', 2500, 0, 0, 2500, 'ao-b1', (current_date + interval '10 hours 30 minutes') at time zone 'UTC');
-- Org B (cross-tenant isolation).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000002c001', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'preparing', 'EUR', 7777, 0, 0, 7777, 'ao-c1', (current_date + interval '10 hours') at time zone 'UTC');

-- ---- Items (item_count = SUM(quantity)). ------------------------------------
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('00000000-0000-0000-0000-00000012a001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a001', '00000000-0000-0000-0000-0000000e1001', 2, 'Burger', 500, 1000),
  ('00000000-0000-0000-0000-00000012a002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a002', '00000000-0000-0000-0000-0000000e1002', 1, 'Fries',  500,  500);

-- ---- Completed cash payments: #02A003 (1000) and #02A005 (700). --------------
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, receipt_number, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000004a003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a003', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'R-201', 'ao-p3', (current_date + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000004a005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a005', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed',  700,  700, 0, 'ILS', 'R-202', 'ao-p5', (current_date + interval '12 hours') at time zone 'UTC');

-- ===== calls (org_owner) =====================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_a1a as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00') as res;
create temp table t_org as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000') as res;
create temp table t_cap as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, 2) as res;
reset role;

-- ===== (1) envelope ==========================================================
select ok(
  (select (res->>'ok')::boolean = true
      and res->>'entity' = 'owner_active_orders'
      and res->>'currency_code' = 'ILS'
      and (res->>'limit')::int = 100 from t_a1a),
  'envelope: ok / entity / currency_code / default limit 100');

-- ===== (2-4) THE ACTIVE SET: 5 active; terminal + draft + deleted excluded ====
select is((select jsonb_array_length(res->'orders') from t_a1a), 5,
  'Branch A1a: exactly the 5 CANONICAL active orders (submitted/accepted/preparing/ready/served)');
select ok(
  (select not exists (
     select 1 from jsonb_array_elements(res->'orders') o
     where o->>'status' in ('completed', 'cancelled', 'voided', 'draft')) from t_a1a),
  'TERMINAL (completed/cancelled/voided) and local-only draft never appear');
select ok(
  (select not exists (
     select 1 from jsonb_array_elements(res->'orders') o
     where o->>'order_code' = '#02A00A') from t_a1a),
  'a SOFT-DELETED (deleted_at) active order is excluded (D-020)');

-- ===== (5-8) FIFO ordering + NO date window + equal-timestamp tie-break =======
select is((select res->'orders'->0->>'order_code' from t_a1a), '#02A001',
  'FIFO: the 3-DAY-OLD still-preparing order is FIRST — there is NO date window (it would have vanished from an order-history "today" call)');
select is((select res->'orders'->1->>'order_code' from t_a1a), '#02A002', 'FIFO: then today 10:00 (submitted)');
select is((select res->'orders'->2->>'order_code' from t_a1a), '#02A003', 'FIFO: then today 11:00 (ready)');
select ok(
  (select res->'orders'->3->>'order_code' = '#02A004'
      and res->'orders'->4->>'order_code' = '#02A005' from t_a1a),
  'two orders with the SAME created_at order stably by id (#02A004 before #02A005)');

-- ===== (9-10) payment is a SEPARATE axis (D-025) =============================
select ok(
  (select o->>'status' = 'ready' and o->>'payment_status' = 'paid'
       and o->>'payment_method' = 'cash' and (o->>'paid_amount_minor')::bigint = 1000
   from t_a1a, lateral jsonb_array_elements(res->'orders') o
   where o->>'order_code' = '#02A003'),
  'a PAID order is STILL ACTIVE (paid never means done — D-025)');
select ok(
  (select o->>'status' = 'served' and o->>'payment_status' = 'unpaid'
       and o->>'payment_method' is null
   from t_a1a, lateral jsonb_array_elements(res->'orders') o
   where o->>'order_code' = '#02A004'),
  'a SERVED order can be UNPAID (the board surfaces it rather than hiding it)');

-- ===== (11-13) scope summary (deliberately ignores the list filters) =========
select is((select (res->'summary'->>'total')::int from t_a1a), 5, 'summary.total = 5 active in scope');
select is((select (res->'summary'->>'unpaid')::int from t_a1a), 3, 'summary.unpaid = 3 (#02A001, #02A002, #02A004)');
select ok(
  (select (res->'summary'->'by_status'->>'submitted')::int = 1
      and (res->'summary'->'by_status'->>'accepted')::int  = 1
      and (res->'summary'->'by_status'->>'preparing')::int = 1
      and (res->'summary'->'by_status'->>'ready')::int     = 1
      and (res->'summary'->'by_status'->>'served')::int    = 1 from t_a1a),
  'summary.by_status carries ALL FIVE active stages (never a partial map)');

-- ===== (14-19) enum-VALIDATED filters ========================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','ready')->'orders'->0->>'order_code'),
  '#02A003', 'status filter (ready) -> #02A003');
select is(
  (select jsonb_array_length(app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,null,'unpaid')->'orders')),
  3, 'payment filter (unpaid) -> 3');
select is(
  (select jsonb_array_length(app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,null,'cash')->'orders')),
  2, 'payment filter (cash) -> 2');
select is(
  (select jsonb_array_length(app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,'dine_in')->'orders')),
  3, 'order_type filter (dine_in) -> 3 (#02A001, #02A003, #02A005)');
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','completed') $$,
  '22023', NULL, 'a TERMINAL status is NOT an active-board filter -> 22023 (never a silently-empty board)');
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,null,'bogus') $$,
  '22023', NULL, 'an unknown payment token -> 22023');

-- ===== (20-22) search (safe reference fields only) ===========================
select is(
  (select jsonb_array_length(app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,null,null,'#02A003')->'orders')),
  1, 'search by order code -> 1');
select is(
  (select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,null,null,'layla')->'orders'->0->>'order_code'),
  '#02A001', 'search by customer (case-insensitive) -> #02A001');
select is(
  (select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,null,null,'T1')->'orders'->0->>'order_code'),
  '#02A001', 'search by table label -> #02A001');

-- ===== (23) unknown order_type -> 22023 ======================================
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00',null,'delivery') $$,
  '22023', NULL, 'an unmodelled order_type -> 22023');
reset role;

-- ===== (24-25) branch filter + permitted ALL-BRANCH scope ====================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select ok(
  (select jsonb_array_length(res->'orders') = 1
      and res->'orders'->0->>'order_code' = '#02B001'
      and res->'orders'->0->>'branch_name' = 'Branch A1b'
   from (select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1b00') as res) x),
  'branch filter is enforced SERVER-side (Branch A1b -> only #02B001)');
select ok(
  (select jsonb_array_length(res->'orders') = 6
      and (res->'summary'->>'total')::int = 6 from t_org),
  'the org_owner ALL-BRANCH scope returns both branches (5 + 1) and the summary agrees');
reset role;

-- ===== (26-27) sibling-branch denial + the manager''s own branch ==============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';  -- manager of A1a only
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1b00') $$,
  '42501', NULL, 'a Branch A1a manager cannot read SIBLING Branch A1b (42501)');
select is(
  (select jsonb_array_length(app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00')->'orders')),
  5, 'the same manager reads their OWN branch (5 active)');
reset role;

-- ===== (28-29) cross-tenant: rejected, and never leaked into an org-wide call =
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000b0000') $$,
  '42501', NULL, 'Org A owner cannot read Org B active orders (cross-org 42501)');
reset role;
select ok(
  (select not exists (
     select 1 from jsonb_array_elements(res->'orders') o
     where o->>'order_code' = '#02C001') from t_org),
  'Org B''s active order never appears in Org A''s org-wide board (D-001)');

-- ===== (30) kitchen_staff DENIED (the board carries money) ===================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is(
  (select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00')->>'error'),
  'permission_denied', 'kitchen_staff is DENIED (permission_denied) — the board carries order totals');
reset role;

-- ===== (31) UNAUTHENTICATED denied ==========================================
set local role authenticated;
set local app.current_app_user_id = '';
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000') $$,
  '42501', NULL, 'an unauthenticated caller is denied (42501)');
reset role;

-- ===== (32-34) page-size CAP + honest truncation =============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select (app.owner_active_orders('00000000-0000-0000-0000-0000000a0000',null,null,null,null,null,null,999)->>'limit')::int),
  200, 'p_limit is CAPPED at 200 (999 -> 200)');
select is(
  (select (app.owner_active_orders('00000000-0000-0000-0000-0000000a0000',null,null,null,null,null,null,0)->>'limit')::int),
  1, 'p_limit floor is 1 (0 -> 1)');
reset role;
select ok(
  (select jsonb_array_length(res->'orders') = 2
      and (res->>'count')::int = 2
      and (res->>'matching')::int = 5
      and (res->>'truncated')::boolean = true from t_cap),
  'a truncated page reports HONESTLY (count 2, matching 5, truncated true) — never a silent cut');

-- ===== (35-36) time: absolute UTC instant + resolved branch-local zone ========
select ok(
  (select o->>'timezone' = 'Asia/Jerusalem'
      and o->>'created_at_utc' like '%T%Z'
      and right(o->>'created_at_utc', 1) = 'Z'
      -- the branch-local display string is NOT the UTC clock time (Asia/Jerusalem
      -- is never UTC+0), proving the branch zone is actually applied.
      and right(o->>'created_at', 5) <> substring(o->>'created_at_utc' from 12 for 5)
   from t_a1a, lateral jsonb_array_elements(res->'orders') o
   where o->>'order_code' = '#02A002'),
  'Branch A1a (Asia/Jerusalem): created_at is BRANCH-LOCAL, created_at_utc is the absolute instant, timezone is resolved');
select ok(
  (select o->>'timezone' = 'UTC'
      and right(o->>'created_at', 5) = substring(o->>'created_at_utc' from 12 for 5)
   from t_org, lateral jsonb_array_elements(res->'orders') o
   where o->>'order_code' = '#02B001'),
  'a tz-less branch falls back to the RESTAURANT zone (UTC) — the order is never dropped');

-- ===== (37) money stays integer minor; NO float ==============================
select ok(
  (select jsonb_typeof(o->'grand_total_minor') = 'number'
      and jsonb_typeof(o->'paid_amount_minor') = 'number'
      and (o->>'grand_total_minor')::bigint = 1000
      and (o->>'item_count')::int is not null
   from t_a1a, lateral jsonb_array_elements(res->'orders') o
   where o->>'order_code' = '#02A003'),
  'money is an integer-shaped JSON number read from the stored snapshot (no float)');

-- ===== (38) the payload carries NO private field and NO fabricated due/late ===
select ok(
  (select not exists (
     select 1
     from jsonb_array_elements(res->'orders') o,
          lateral jsonb_object_keys(o) k
     where k in ('device_id', 'pin_session_id', 'organization_id', 'restaurant_id',
                 'branch_id', 'resolved_membership_id', 'opened_by_employee_profile_id',
                 'table_id', 'notes', 'metadata', 'attributes', 'local_operation_id',
                 'due_at', 'promised_at', 'late', 'overdue', 'sla'))
   from t_a1a),
  'NO private identifier, NO raw notes/metadata, and NO fabricated due/late key is ever projected');

-- ===== (39) READ-ONLY: the function is STABLE and no order row changed =======
select ok(
  (select provolatile = 's' from pg_proc
    where proname = 'owner_active_orders' and pronamespace = 'app'::regnamespace)
  and (select count(*) from orders where organization_id = '00000000-0000-0000-0000-0000000a0000' and status = 'preparing') = 3
  and (select count(*) from orders where organization_id = '00000000-0000-0000-0000-0000000a0000' and status = 'completed') = 1,
  'app.owner_active_orders is STABLE (it structurally cannot write) and the order rows are unchanged after every call');

-- ===== (40) ACL: DEFINER/INVOKER + search_path + authenticated-only ==========
select ok(
  (select prosecdef = true  from pg_proc where proname='owner_active_orders' and pronamespace='app'::regnamespace)
  and (select prosecdef = false from pg_proc where proname='owner_active_orders' and pronamespace='public'::regnamespace)
  and exists (select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
              where p.proname='owner_active_orders' and p.pronamespace='app'::regnamespace and cfg like 'search_path=%')
  and exists (select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
              where p.proname='owner_active_orders' and p.pronamespace='public'::regnamespace and cfg like 'search_path=%')
  and not has_function_privilege('anon',   'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int)', 'execute')
  and not has_function_privilege('public', 'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int)', 'execute')
  and not has_function_privilege('anon',   'app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int)', 'execute')
  and not has_function_privilege('public', 'app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int)', 'execute')
  and has_function_privilege('authenticated', 'app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int)', 'execute')
  and exists (select 1 from pg_indexes where schemaname='public' and indexname='orders_active_ops_idx'),
  'app fn is DEFINER + public wrapper is INVOKER, both search_path-locked, authenticated-only (anon + PUBLIC revoked), and the supporting index exists');

select * from finish();
rollback;
