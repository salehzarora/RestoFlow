-- ============================================================================
-- RF-REPORT-001 — pgTAP: app.owner_daily_report (GUC-free real owner daily report).
-- Org A (Rest A1 tz=UTC: branches A1a + A1b; Rest A2 tz=NULL: branch A2a tz-less)
-- and Org B. Today: billed orders (completed / open / unpaid / voided / cancelled)
-- with order_items, cash + card completed payments, a tz-less order (excluded).
-- Yesterday: one completed order+cash payment (prior_day block). Asserts:
--   * billed sales split from collected payments (gross != collected);
--   * gross/discount/net, void count+total, collected/cash/last-cash, tenders;
--   * prior-day block; empty-branch zero/empty; integer minor shape;
--   * ROLE GATE: org_owner + accountant + cashier READ; kitchen_staff denied;
--   * tenant isolation (cross-org 42501) + branch scope narrowing;
--   * tz-less branch excluded; public wrapper is INVOKER + locked search_path +
--     authenticated-only grants (no anon/PUBLIC).
-- GUC-FREE (identity GUC only), mirroring mvp_sales_summary_test.sql. All UUIDs
-- are hex-only.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(30);

-- ===== fixture: Org A (Rest A1 tz=UTC + Rest A2 tz=NULL) and Org B ============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'odr-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'odr-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a0000', 'Rest A2', null),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a', null),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1b', null),
  ('00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', 'Branch A2a', null),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', 'pos'),
  ('00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', 'active'),
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', 'active'),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-00000000c002'),
  ('00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000c003'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'odr-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'odr-accountant@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'odr-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f004', 'odr-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'odr-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0000', null, null, 'accountant'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0004', '00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');

-- ---- TODAY orders on Branch A1a (Rest A1, tz=UTC) ----------------------------
-- O1 completed 1000; O2 served(open) net 1800 w/ 200 item discount; O5 submitted
-- (open, UNPAID) 1500; O3 voided 5000; O4 cancelled 9000 (excluded from sales).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 1000, 0, 0, 1000, 'odr-o1'),
  ('00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 1800, 0, 0, 1800, 'odr-o2'),
  ('00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway','submitted', 'ILS', 1500, 0, 0, 1500, 'odr-o5'),
  ('00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'voided',    'ILS', 5000, 0, 0, 5000, 'odr-o3'),
  ('00000000-0000-0000-0000-00000001d004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'cancelled', 'ILS', 9000, 0, 0, 9000, 'odr-o4');
-- O6 today on Branch A1b (Rest A1) — completed 400, tests org-wide vs branch scope.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway','completed', 'ILS', 400, 0, 0, 400, 'odr-o6');
-- O7 today on Branch A2a (Rest A2, tz-less) — MUST be excluded (no timezone).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000001d007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-0000000b0003', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 7777, 0, 0, 7777, 'odr-o7');
-- O8 YESTERDAY on Branch A1a — completed 1200 (prior_day block).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 1200, 0, 0, 1200, 'odr-o8', now() - interval '1 day');
-- OB1 today on Org B — isolation.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000001d0b1', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'completed', 'EUR', 9000, 0, 0, 9000, 'odr-ob1');

-- ---- order_items (billed gross/discount): O1=1000; O2 gross 2000, item disc 200,
-- net 1800; O5=1500; O6=400; O3(void)=5000; O8(yesterday)=1200 -----------------
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, menu_item_name_snapshot, quantity, unit_price_minor_snapshot, line_discount_minor, line_total_minor) values
  ('00000000-0000-0000-0000-00000002a001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 1000, 0,   1000),
  ('00000000-0000-0000-0000-00000002a002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 1000, 200, 800),
  ('00000000-0000-0000-0000-00000002a003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 1000, 0,   1000),
  ('00000000-0000-0000-0000-00000002a005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 1500, 0,   1500),
  ('00000000-0000-0000-0000-00000002a006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 400,  0,   400),
  ('00000000-0000-0000-0000-00000002a03c', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 5000, 0,   5000),
  ('00000000-0000-0000-0000-00000002a008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-0000000e1001', 'Item', 1, 1200, 0,   1200);

-- ---- payments (collected): today O1 cash 1000 + O2 card 1800 + O6 cash 400;
-- O5 UNPAID; yesterday O8 cash 1200; Org B OB1 cash 9000. -----------------------
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-00000003b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'odr-a1'),
  ('00000000-0000-0000-0000-00000003b002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'card', 'completed', 1800, 1800, 0, 'ILS', 'odr-a2'),
  ('00000000-0000-0000-0000-00000003b006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 400,  400,  0, 'ILS', 'odr-a6'),
  ('00000000-0000-0000-0000-00000003b0b1', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000001d0b1', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'cash', 'completed', 9000, 9000, 0, 'EUR', 'odr-ab1');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000003b008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 1200, 1200, 0, 'ILS', 'odr-a8', now() - interval '1 day');

-- ===== (1-15) org_owner org-wide (Org A): today totals ========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_all as select app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', null, null) as res;
reset role;
select is((select (res->>'ok')::boolean from t_all), true, 'org_owner owner_daily_report ok=true');
select is((select res->>'currency_code' from t_all), 'ILS', 'currency_code = organizations.default_currency');
select is((select (res->'today'->>'order_count')::int from t_all), 4, 'today order_count = 4 (void/cancelled/tz-less excluded)');
select is((select (res->'today'->>'completed_count')::int from t_all), 2, 'today completed_count = 2 (O1 + O6)');
select is((select (res->'today'->>'open_count')::int from t_all), 2, 'today open_count = 2 (O2 served + O5 submitted)');
select is((select (res->'today'->>'unpaid_count')::int from t_all), 1, 'today unpaid_count = 1 (O5 has no completed payment)');
select is((select (res->'today'->>'gross_minor')::bigint from t_all), 4900::bigint, 'today gross_minor = 4900 (1000+2000+1500+400)');
select is((select (res->'today'->>'discount_minor')::bigint from t_all), 200::bigint, 'today discount_minor = 200 (O2 item discount)');
select is((select (res->'today'->>'net_minor')::bigint from t_all), 4700::bigint, 'today net_minor = 4700 (gross 4900 - discount 200)');
select is((select (res->'today'->>'void_count')::int from t_all), 1, 'today void_count = 1 (O3)');
select is((select (res->'today'->>'void_total_minor')::bigint from t_all), 5000::bigint, 'today void_total_minor = 5000');
select is((select (res->'today'->>'collected_minor')::bigint from t_all), 3200::bigint, 'today collected_minor = 3200 (cash 1000+400 + card 1800)');
select is((select (res->'today'->>'cash_minor')::bigint from t_all), 1400::bigint, 'today cash_minor = 1400 (1000 + 400)');
select is((select (res->'today'->>'last_cash_payment_minor')::bigint from t_all), 400::bigint, 'today last_cash_payment_minor = 400 (most recent cash)');
select ok((select (res->'today'->>'gross_minor')::bigint <> (res->'today'->>'collected_minor')::bigint from t_all),
          'billed gross (4900) is SPLIT from collected (3200) — not conflated');

-- ===== (16-18) tender breakdown by method =====================================
select is((select jsonb_array_length(res->'today'->'tenders') from t_all), 2, 'today tenders has 2 methods (card + cash)');
select is((select res->'today'->'tenders'->0->>'method' from t_all), 'card', 'tenders ordered by method: card first');
select is((select (res->'today'->'tenders'->1->>'total_minor')::bigint from t_all), 1400::bigint, 'cash tender total_minor = 1400 (count 2)');

-- ===== (19-22) prior-day block (yesterday O8: 1200 completed + cash 1200) ======
select is((select (res->'prior_day'->>'order_count')::int from t_all), 1, 'prior_day order_count = 1 (O8)');
select is((select (res->'prior_day'->>'gross_minor')::bigint from t_all), 1200::bigint, 'prior_day gross_minor = 1200');
select is((select (res->'prior_day'->>'net_minor')::bigint from t_all), 1200::bigint, 'prior_day net_minor = 1200');
select is((select (res->'prior_day'->>'cash_minor')::bigint from t_all), 1200::bigint, 'prior_day cash_minor = 1200');

-- ===== (23-24) branch filter narrows to Branch A1a ============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_branch as select app.owner_daily_report(
  '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00') as res;
reset role;
select is((select (res->'today'->>'order_count')::int from t_branch), 3, 'branch A1a: order_count = 3 (A1b O6 excluded)');
select is((select (res->'today'->>'gross_minor')::bigint from t_branch), 4500::bigint, 'branch A1a: gross_minor = 4500 (excludes A1b 400)');

-- ===== (25) accountant (rank 1, org-wide) MAY read (can_read_financials) =======
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
select is(
  (select (app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', null, null)->>'ok')::boolean),
  true, 'accountant MAY read the owner daily report (can_read_financials allowlist)');
reset role;

-- ===== (26) cashier MAY read (can_read_financials includes cashier) ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f004';
select is(
  (select (app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00')->>'ok')::boolean),
  true, 'cashier MAY read the owner daily report (financial-read role)');
reset role;

-- ===== (27) kitchen_staff is DENIED (permission_denied) =======================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is(
  (select app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00')->>'error'),
  'permission_denied', 'kitchen_staff cannot read financial reports (permission_denied)');
reset role;

-- ===== (28) cross-org caller is structurally rejected (42501) =================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_daily_report('00000000-0000-0000-0000-0000000b0000', null, null) $$,
  '42501', NULL, 'an Org A owner cannot read the Org B report (cross-org 42501)');
reset role;

-- ===== (29) tz-less branch yields an honest empty today (excluded rows) ========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_empty as select app.owner_daily_report(
  '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00') as res;
reset role;
select ok((select (res->'today'->>'order_count')::int = 0
             and (res->'today'->>'gross_minor')::bigint = 0
             and (res->'today'->>'collected_minor')::bigint = 0
             and jsonb_array_length(res->'today'->'tenders') = 0
             and (res->>'ok')::boolean = true from t_empty),
          'tz-less branch yields an honest empty today (zeros + empty tenders), never fabricated');

-- ===== (30) public wrapper: INVOKER + locked search_path + grants =============
select ok(
  (select prosecdef = false from pg_proc where proname='owner_daily_report' and pronamespace='public'::regnamespace and pronargs=3)
  and (select exists(
     select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='owner_daily_report' and p.pronamespace='public'::regnamespace and p.pronargs=3 and cfg like 'search_path=%'))
  and not has_function_privilege('anon', 'public.owner_daily_report(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('public', 'public.owner_daily_report(uuid, uuid, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_daily_report(uuid, uuid, uuid)', 'execute'),
  'public.owner_daily_report is INVOKER, search_path-locked, authenticated-only (no anon/PUBLIC)');

select * from finish();
rollback;
