-- ============================================================================
-- DASHBOARD-VISUAL-RANGE-REFRESH-S0 — pgTAP for the server slice:
--   * app/public.owner_top_items                (new)
--   * app/public.owner_report_range             (last60 / last90 / custom)
--   * app/public.owner_order_history            (last60 / last90 / custom)
--   * app/public.owner_sales_series             (last60 / last90 first-class)
--   * the ACL + security posture of all four
--
-- FIXTURE (Org A, Rest A1 tz='UTC' -> branch A1a; Rest A3 tz='Etc/GMT-3' ->
-- branch A3a; Org B for isolation). Branch A1a carries billed orders on:
--
--   today  T1 1000 / T2 500 / T7 100 / T8 600            net 2200
--   t-4    333        (the custom-comparison window)
--   t-6    999        (inside last7, outside the 3-day comparison window)
--   t-45   4500       (inside last60, outside last30)
--   t-59   59         (the LAST day inside last60)
--   t-60   60         (the FIRST day outside last60 — inside last90)
--   t-75   7500       (inside last90, outside last60)
--   t-89   89         (the LAST day inside last90)
--   t-90   90         (the FIRST day outside last90)
--   t-100  10000      (outside everything)
--
-- so every window boundary is proven by a row on BOTH sides of it, not by a
-- comfortable midpoint. Expected billed net per window:
--   today 2200 | last7 3532 | last30 3532 | last60 8091 | last90 15740
--
-- Today also carries every EXCLUSION as a real row that would otherwise change
-- the numbers: a voided order (T3), a cancelled one (T4), a draft (T5), a
-- soft-deleted one (T6), and — inside a live order — a VOIDED LINE (T7).
--
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(156);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'vrr-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'vrr-b', 'EUR');
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
  ('00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-00000000c005');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'vrr-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'vrr-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'vrr-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'vrr-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000e005', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour');

-- A catalog exists, but ONLY so it can be renamed and deleted underneath the
-- history. Nothing in owner_top_items joins it.
insert into menu_categories (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000010c01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Mains');
insert into menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-000000010b01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-000000010c01', 'Falafel', 300, 'ILS'),
  ('00000000-0000-0000-0000-000000010b02', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-000000010c01', 'Hummus',  400, 'ILS'),
  ('00000000-0000-0000-0000-000000010b03', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-000000010c01', 'Salad',   200, 'ILS');

-- ---- TODAY on branch A1a. Distinct hours so newest-first is unambiguous. ----
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at, deleted_at) values
  ('00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS', 1000, 0, 0, 1000, 'vrr-o-1',  (current_date + interval '10 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway', 'completed', 'ILS',  500, 0, 0,  500, 'vrr-o-2',  (current_date + interval '11 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'voided',    'ILS',  700, 0, 0,  700, 'vrr-o-3',  (current_date + interval '12 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'cancelled', 'ILS',  900, 0, 0,  900, 'vrr-o-4',  (current_date + interval '13 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'draft',     'ILS',  300, 0, 0,  300, 'vrr-o-5',  (current_date + interval '14 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS',  400, 0, 0,  400, 'vrr-o-6',  (current_date + interval '15 hours') at time zone 'UTC', now()),
  ('00000000-0000-0000-0000-00000001d007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS',  100, 0, 0,  100, 'vrr-o-7',  (current_date + interval '16 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS',  600, 0, 0,  600, 'vrr-o-8',  (current_date + interval '17 hours') at time zone 'UTC', null);

-- ---- The window-boundary orders, one on each side of every edge. -----------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d040', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',   333, 0, 0,   333, 'vrr-o-p4',  ((current_date -   4) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d060', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',   999, 0, 0,   999, 'vrr-o-p6',  ((current_date -   6) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d450', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',  4500, 0, 0,  4500, 'vrr-o-45',  ((current_date -  45) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d590', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',    59, 0, 0,    59, 'vrr-o-59',  ((current_date -  59) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d600', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',    60, 0, 0,    60, 'vrr-o-60',  ((current_date -  60) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d750', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',  7500, 0, 0,  7500, 'vrr-o-75',  ((current_date -  75) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d890', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',    89, 0, 0,    89, 'vrr-o-89',  ((current_date -  89) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d900', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',    90, 0, 0,    90, 'vrr-o-90',  ((current_date -  90) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001da00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 10000, 0, 0, 10000, 'vrr-o-100', ((current_date - 100) + interval '10 hours') at time zone 'UTC');

-- ---- Lines. created_at is SET EXPLICITLY: now() is transaction-stable, so a
-- ---- default would make every line the same age and the "newest snapshot"
-- ---- rule untestable.
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, menu_item_name_snapshot, quantity, unit_price_minor_snapshot, line_total_minor, line_discount_minor, status, created_at) values
  -- T1: Falafel 600 + Hummus 400 = 1000
  ('00000000-0000-0000-0000-000000011001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-000000010b01', 'Falafel',       2, 300,  600, 0, 'served', (current_date + interval '10 hours') at time zone 'UTC'),
  -- The OLDER Hummus snapshot deliberately carries the HIGHER id, so a display
  -- name resolved by id alone would pick this one and the test would fail.
  ('00000000-0000-0000-0000-0000000110ff', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-000000010b02', 'Hummus',        1, 400,  400, 0, 'served', (current_date + interval '10 hours') at time zone 'UTC'),
  -- T2: Falafel 300 + Salad 200 = 500
  ('00000000-0000-0000-0000-000000011002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-000000010b01', 'Falafel',       1, 300,  300, 0, 'served', (current_date + interval '11 hours') at time zone 'UTC'),
  -- A LIVE line carrying a REAL line discount (base 240, less 40, total 200).
  -- Without it, "dead-line discounts are excluded" could be satisfied by a
  -- rollup that simply reported zero discount for everything.
  ('00000000-0000-0000-0000-000000011003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-000000010b03', 'Salad',         1, 240,  200, 40, 'served', (current_date + interval '11 hours') at time zone 'UTC'),
  -- T3 is a VOIDED ORDER; its line is cascade-voided. Item b06 exists ONLY here.
  ('00000000-0000-0000-0000-000000011004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-000000010b06', 'Void Only',     1, 700,  700, 0, 'voided', (current_date + interval '12 hours') at time zone 'UTC'),
  -- T4 CANCELLED / T5 DRAFT / T6 DELETED keep LIVE lines on purpose: only the
  -- ORDER-level filter can exclude them, so it must be doing the work.
  ('00000000-0000-0000-0000-000000011005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d004', '00000000-0000-0000-0000-000000010b02', 'Hummus',        5, 180,  900, 0, 'served', (current_date + interval '13 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-000000010b03', 'Salad',         3, 100,  300, 0, 'pending', (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-000000010b01', 'Falafel',       2, 200,  400, 0, 'served', (current_date + interval '15 hours') at time zone 'UTC'),
  -- T7: ONE live Hummus line (the NEWEST valid snapshot) + a VOIDED line whose
  -- snapshot is newer still. If the void filter were missing, the displayed
  -- name would be 'Hummus VOIDED' and the revenue would be 400 too high.
  ('00000000-0000-0000-0000-000000011007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d007', '00000000-0000-0000-0000-000000010b02', 'Hummus Bowl',   1, 100,  100, 0, 'served', (current_date + interval '16 hours') at time zone 'UTC'),
  -- S0.1: the dead lines now carry REAL money (a total AND a discount), so
  -- including them is observable in gross and discount, not just in quantity.
  ('00000000-0000-0000-0000-000000011009', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d007', '00000000-0000-0000-0000-000000010b02', 'Hummus VOIDED', 4, 100,  370, 30, 'voided', (current_date + interval '17 hours 30 minutes') at time zone 'UTC'),
  -- A CANCELLED line inside the same live, billed order T1. Its line_total is
  -- NOT part of T1.subtotal_minor (1000 = 600 + 400), exactly as the order
  -- writers compute it — so counting it in gross invents revenue.
  ('00000000-0000-0000-0000-00000001100c', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-000000010b01', 'Falafel CANCELLED', 1, 275, 250, 25, 'cancelled', (current_date + interval '10 hours 30 minutes') at time zone 'UTC'),
  -- T8: a genuine REVENUE + QUANTITY tie, broken by name ascending.
  ('00000000-0000-0000-0000-00000001100a', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-000000010b04', 'Zeta',          1, 300,  300, 0, 'served', (current_date + interval '17 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001100b', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-000000010b05', 'Alpha',         1, 300,  300, 0, 'served', (current_date + interval '17 hours') at time zone 'UTC'),
  -- Boundary orders, each with its OWN product so window membership is crisp.
  ('00000000-0000-0000-0000-000000011f04', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d040', '00000000-0000-0000-0000-000000010bf4', 'Prev Window',   1,   333,   333, 0, 'served', ((current_date -   4) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011f06', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d060', '00000000-0000-0000-0000-000000010bf6', 'Older Prev',    1,   999,   999, 0, 'served', ((current_date -   6) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011045', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d450', '00000000-0000-0000-0000-000000010b07', 'Old Item',      1,  4500,  4500, 0, 'served', ((current_date -  45) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011059', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d590', '00000000-0000-0000-0000-000000010b59', 'Boundary 59',   1,    59,    59, 0, 'served', ((current_date -  59) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011060', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d600', '00000000-0000-0000-0000-000000010b60', 'Boundary 60',   1,    60,    60, 0, 'served', ((current_date -  60) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011075', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d750', '00000000-0000-0000-0000-000000010b08', 'Older Item',    1,  7500,  7500, 0, 'served', ((current_date -  75) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011089', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d890', '00000000-0000-0000-0000-000000010b89', 'Boundary 89',   1,    89,    89, 0, 'served', ((current_date -  89) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011090', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d900', '00000000-0000-0000-0000-000000010b90', 'Boundary 90',   1,    90,    90, 0, 'served', ((current_date -  90) + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000011100', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001da00', '00000000-0000-0000-0000-000000010b09', 'Ancient',       1, 10000, 10000, 0, 'served', ((current_date - 100) + interval '10 hours') at time zone 'UTC');

-- Completed payments TODAY, for the payment-filter regression inside a window.
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000000012001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'vrr-p-1', (current_date + interval '10 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000012002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'card', 'completed',  500,  500, 0, 'ILS', 'vrr-p-2', (current_date + interval '11 hours 5 minutes') at time zone 'UTC');

-- THE CATALOG NOW MOVES UNDERNEATH THE HISTORY: Hummus is DELETED outright and
-- Salad is RENAMED. Neither must change what the completed orders report.
delete from menu_items where id = '00000000-0000-0000-0000-000000010b02';
update menu_items set name = 'Salad RENAMED IN CATALOG'
  where id = '00000000-0000-0000-0000-000000010b03';

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';

-- ============================================================================
-- A. owner_top_items
-- ============================================================================
create temporary table t_top on commit drop as
  select app.owner_top_items(
    '00000000-0000-0000-0000-0000000a0000',
    '00000000-0000-0000-0000-0000000a1000',
    '00000000-0000-0000-0000-0000000a1a00', 'today') as res;

select is((select (res->>'ok')::boolean from t_top), true, 'A1 owner_top_items ok envelope');
select is((select res->>'entity' from t_top), 'owner_top_items', 'A2 entity name');
select is((select res->>'currency_code' from t_top), 'ILS', 'A3 currency from the org');
select is((select res->>'range' from t_top), 'today', 'A4 range echoes the preset token');
select is((select (res->>'limit')::int from t_top), 10, 'A5 default limit is 10');

-- Expected today: Falafel 900 (qty 3, 2 orders) | Hummus Bowl 500 (qty 2, 2)
--                 | Alpha 300 | Zeta 300 | Salad 200.
select is((select jsonb_array_length(res->'items') from t_top), 5, 'A6 five distinct products sold today');
select is((select res->'items'->0->>'name' from t_top), 'Falafel', 'A7 highest revenue first');
select is((select (res->'items'->0->>'revenue_minor')::bigint from t_top), 900::bigint, 'A8 revenue = SUM(line_total_minor) across orders');
select is((select (res->'items'->0->>'quantity')::bigint from t_top), 3::bigint, 'A9 quantity sums across orders');
select is((select (res->'items'->0->>'order_count')::bigint from t_top), 2::bigint, 'A10 order_count is DISTINCT orders containing the item');
select is((select res->'items'->0->>'menu_item_id' from t_top), '00000000-0000-0000-0000-000000010b01', 'A11 the stable menu_item_id is reported');

-- Identity is the id: a RENAMED product stays ONE row, and reports the name it
-- was SOLD under, not the newest one and not the catalog's.
select is((select res->'items'->1->>'name' from t_top), 'Hummus Bowl', 'A12 renamed product: the NEWEST captured snapshot wins (not the newest id)');
select is((select (res->'items'->1->>'revenue_minor')::bigint from t_top), 500::bigint, 'A13 renamed product is ONE row (400 + 100), never split by name');
select is((select (res->'items'->1->>'quantity')::bigint from t_top), 2::bigint, 'A14 the VOIDED line (qty 4) is excluded from quantity');

-- A deleted catalog row cannot erase history; a renamed one cannot rewrite it.
select ok((select not exists (select 1 from menu_items where id = '00000000-0000-0000-0000-000000010b02')), 'A15 the Hummus catalog row really is gone');
select is((select res->'items'->1->>'name' from t_top), 'Hummus Bowl', 'A16 a DELETED menu item still reports its sold name (no catalog join)');
select is((select i->>'name' from t_top, jsonb_array_elements(res->'items') i where i->>'menu_item_id' = '00000000-0000-0000-0000-000000010b03'), 'Salad', 'A17 a RENAMED menu item reports the ORDER-TIME snapshot, not the catalog name');

-- Deterministic tie-break: equal revenue AND equal quantity -> name ascending.
select is((select res->'items'->2->>'name' from t_top), 'Alpha', 'A18 tie broken by name ascending (Alpha before Zeta)');
select is((select res->'items'->3->>'name' from t_top), 'Zeta',  'A19 the loser of the tie is next, deterministically');
select is((select res->'items'->4->>'name' from t_top), 'Salad', 'A20 lowest revenue last');

-- Exclusions, each proven by a row that would otherwise appear.
select ok((select not exists (select 1 from t_top, jsonb_array_elements(res->'items') i where i->>'name' = 'Void Only')), 'A21 a VOIDED order contributes nothing');
select ok((select not exists (select 1 from t_top, jsonb_array_elements(res->'items') i where i->>'name' = 'Hummus VOIDED')), 'A22 a VOIDED LINE inside a live order contributes nothing');
select is((select coalesce(sum((i->>'revenue_minor')::bigint), 0)::bigint from t_top, jsonb_array_elements(res->'items') i), 2200::bigint, 'A23 revenue reconciles EXACTLY to billed subtotal (cancelled/draft/deleted all excluded)');

-- Money stays integral.
select ok((select bool_and(jsonb_typeof(i->'revenue_minor') = 'number' and (i->>'revenue_minor') !~ '[.eE]') from t_top, jsonb_array_elements(res->'items') i), 'A24 revenue_minor is an integer JSON number, never a float');
select ok((select bool_and(jsonb_typeof(i->'quantity') = 'number' and (i->>'quantity') !~ '[.eE]') from t_top, jsonb_array_elements(res->'items') i), 'A25 quantity is an integer JSON number');

-- Scope.
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000'))->'items')), 5, 'A26 org-wide scope sees the same 5 today');
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000'))->'items')), 5, 'A27 restaurant scope sees them too');
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a3000','00000000-0000-0000-0000-0000000a3a00'))->'items')), 0, 'A28 a SIBLING branch with no orders returns an honest empty list');

-- Ranges.
select ok((select not exists (select 1 from jsonb_array_elements((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'last30'))->'items') i where i->>'name' = 'Old Item')), 'A29 last30 excludes the t-45 product');
select ok((select exists (select 1 from jsonb_array_elements((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->'items') i where i->>'name' = 'Old Item')), 'A30 last60 includes the t-45 product');
select ok((select exists (select 1 from jsonb_array_elements((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'last60', null, null, 50))->'items') i where i->>'name' = 'Boundary 59')), 'A31 last60 includes t-59, its LAST day');
select ok((select not exists (select 1 from jsonb_array_elements((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'last60', null, null, 50))->'items') i where i->>'name' = 'Boundary 60')), 'A32 last60 EXCLUDES t-60, the first day outside it');
select ok((select exists (select 1 from jsonb_array_elements((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'last90', null, null, 50))->'items') i where i->>'name' = 'Boundary 89')), 'A33 last90 includes t-89, its LAST day');
select ok((select not exists (select 1 from jsonb_array_elements((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'last90', null, null, 50))->'items') i where i->>'name' = 'Boundary 90')), 'A34 last90 EXCLUDES t-90');
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'yesterday'))->'items')), 0, 'A35 yesterday has no facts => empty items, not null');

-- Custom window.
select is((select (app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 46, current_date - 44))->>'range'), 'custom', 'A36 a custom pair reports range=custom');
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 46, current_date - 44))->'items')), 1, 'A37 a custom window selects exactly the days asked for');
select is((select (app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 46, current_date - 44))->'items'->0->>'name'), 'Old Item', 'A38 and returns that day''s product');
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, current_date))->'items')), 5, 'A39 a single-day custom window (start = end) is INCLUSIVE');

select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, null)$$, '22023', null, 'A40 half-supplied custom window rejected');
select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, null, current_date)$$, '22023', null, 'A41 the other half is rejected too');
select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, current_date - 1)$$, '22023', null, 'A42 reversed range rejected');
select lives_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 91, current_date)$$, 'A43 exactly 92 inclusive days accepted');
select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 92, current_date)$$, '22023', null, 'A44 93 days rejected');
select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$, '22023', null, 'A45 unknown preset token => 22023, never a silent fallback to today');

-- p_limit clamps rather than raising: a page size is a display choice.
select is((select jsonb_array_length((app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, 2))->'items')), 2, 'A46 p_limit truncates to the top N');
select is((select (app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, 2))->'items'->0->>'name'), 'Falafel', 'A47 and keeps the ranking while doing so');
select is((select (app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, 0))->>'limit')::int, 1, 'A48 p_limit 0 clamps UP to 1');
select is((select (app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, 5000))->>'limit')::int, 50, 'A49 p_limit 5000 clamps DOWN to 50');
select is((select (app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, null))->>'limit')::int, 10, 'A50 a null p_limit falls back to the default');

-- Authorization.
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
select is((select ((app.owner_top_items('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today'))->>'ok')::boolean), true, 'A51 cashier is a financial-read role, as everywhere else in this family');
select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a3000','00000000-0000-0000-0000-0000000a3a00','today')$$, '42501', null, 'A52 a branch-scoped cashier cannot reach a sibling branch');

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is((select ((app.owner_top_items('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today'))->>'error')), 'permission_denied', 'A53 kitchen_staff is DENIED owner financial analytics');

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f005';
select throws_ok($$select app.owner_top_items('00000000-0000-0000-0000-0000000a0000', null, null, 'today')$$, '42501', null, 'A54 a cross-org caller cannot read Org A');

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';

-- ============================================================================
-- B. owner_report_range — last60 / last90 / custom
-- ============================================================================
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'today'))->'current'->>'net_minor')::bigint), 2200::bigint, 'B1 today unchanged');
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last7'))->'current'->>'net_minor')::bigint), 3532::bigint, 'B2 last7 unchanged');
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last30'))->'current'->>'net_minor')::bigint), 3532::bigint, 'B3 last30 unchanged');
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'yesterday'))->'current'->>'net_minor')::bigint), 0::bigint, 'B4 yesterday unchanged');
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->'current'->>'net_minor')::bigint), 8091::bigint, 'B5 last60 = last30 + t-45 + t-59');
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->'current'->>'net_minor')::bigint), 15740::bigint, 'B6 last90 = last60 + t-60 + t-75 + t-89');
select is((select (app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->>'range_start'), to_char(current_date - 59, 'YYYY-MM-DD'), 'B7 last60 starts 59 days back — 60 branch-local days INCLUDING today');
select is((select (app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->>'range_end'), to_char(current_date, 'YYYY-MM-DD'), 'B8 last60 ends today');
select is((select (app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->>'range_start'), to_char(current_date - 89, 'YYYY-MM-DD'), 'B9 last90 starts 89 days back');
select is((select (app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->>'range'), 'last90', 'B10 the preset token is echoed back');

-- Preset comparisons still describe the immediately preceding equal-length
-- window: last7 covers [t-6,t] so its prior window [t-13,t-7] is empty here.
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last7'))->'comparison'->>'net_minor')::bigint), 0::bigint, 'B11 preset comparison window is unchanged');
-- last60 covers [t-59,t], so its prior window is the 60 days [t-119,t-60] —
-- which is where t-60, t-75, t-89, t-90 and t-100 all live.
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->'comparison'->>'net_minor')::bigint), 17739::bigint, 'B12 last60 compares against the 60 days immediately before it');

-- CUSTOM: [t-2, t] is 3 days, so the comparison window is exactly [t-5, t-3].
create temporary table t_custom on commit drop as
  select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null,
                                current_date - 2, current_date) as res;
select is((select res->>'range' from t_custom), 'custom', 'B13 a custom pair reports range=custom');
select is((select res->>'range_start' from t_custom), to_char(current_date - 2, 'YYYY-MM-DD'), 'B14 custom range_start is the FIXED date given');
select is((select res->>'range_end' from t_custom), to_char(current_date, 'YYYY-MM-DD'), 'B15 custom range_end is the FIXED date given');
select is((select (res->'current'->>'net_minor')::bigint from t_custom), 2200::bigint, 'B16 custom current window holds only today''s orders');
select is((select (res->'comparison'->>'net_minor')::bigint from t_custom), 333::bigint, 'B17 custom comparison is the IMMEDIATELY PRECEDING equal-length window: t-4 is in');
select is((select (res->'comparison'->>'order_count')::bigint from t_custom), 1::bigint, 'B18 and t-6 is OUT — the prior window is 3 days, not "everything before"');
select is((select (res->'comparison'->>'completed_count')::bigint from t_custom), 1::bigint, 'B19 the SERVER-B comparison keys are populated for custom too');

-- Hourly is a property of the WINDOW LENGTH, not of the token used to ask.
select is((select jsonb_array_length((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, current_date))->'hourly')), 24, 'B20 a ONE-DAY custom window fills 24 hourly buckets');
select is((select jsonb_array_length(res->'hourly') from t_custom), 0, 'B21 a multi-day custom window has no hourly series');
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, current_date))->'hourly'->10->>'net_minor')::bigint), 1000::bigint, 'B22 and the 10:00 bucket holds the 10:00 order');

select throws_ok($$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, null)$$, '22023', null, 'B23 half-supplied custom window rejected');
select throws_ok($$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, current_date - 1)$$, '22023', null, 'B24 reversed custom range rejected');
select throws_ok($$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 92, current_date)$$, '22023', null, 'B25 93-day custom window rejected');
select lives_ok($$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 91, current_date)$$, 'B26 92-day custom window accepted');
select throws_ok($$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$, '22023', null, 'B27 unknown range still raises 22023');

-- Branch-local windows still resolve PER BRANCH after the rewrite.
select is((select (app.owner_report_range('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a3000','00000000-0000-0000-0000-0000000a3a00','last60'))->>'range_start'), to_char(((now() at time zone 'Etc/GMT-3')::date - 59), 'YYYY-MM-DD'), 'B28 a UTC+3 branch computes last60 from ITS OWN local today');

-- Authorization is untouched by the widening.
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is((select ((app.owner_report_range('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','last90'))->>'error')), 'permission_denied', 'B29 kitchen_staff still denied, including on the NEW ranges');
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f005';
select throws_ok($$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 2, current_date)$$, '42501', null, 'B30 a cross-org caller cannot reach a custom window either');
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';

-- ============================================================================
-- C. owner_order_history — last60 / last90 / custom
-- ============================================================================
create temporary table t_hist on commit drop as
  select app.owner_order_history(
    '00000000-0000-0000-0000-0000000a0000',
    '00000000-0000-0000-0000-0000000a1000',
    '00000000-0000-0000-0000-0000000a1a00', 'today') as res;

-- History is a LIST: it shows voided/cancelled/draft too, and only the DELETED
-- order is absent. 7 rows today.
select is((select (res->>'count')::int from t_hist), 7, 'C1 today lists every live order, whatever its status');
select is((select res->'orders'->0->>'order_id' from t_hist), '00000000-0000-0000-0000-00000001d008', 'C2 newest first');
select is((select res->'orders'->6->>'order_id' from t_hist), '00000000-0000-0000-0000-00000001d001', 'C3 oldest last');

select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last30', null, null, null, null, 100))->>'count')::int), 9, 'C4 last30 adds t-4 and t-6');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last60', null, null, null, null, 100))->>'count')::int), 11, 'C5 last60 adds t-45 and t-59');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last90', null, null, null, null, 100))->>'count')::int), 14, 'C6 last90 adds t-60, t-75 and t-89 — and NOT t-90');
select is((select (app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->>'range'), 'last90', 'C7 the preset token is echoed back');
select is((select (app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->>'entity'), 'owner_order_history', 'C8 entity unchanged');

-- Custom window.
select is((select (app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, null, 100, null, current_date - 6, current_date - 4))->>'range'), 'custom', 'C9 a custom pair reports range=custom');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, null, 100, null, current_date - 6, current_date - 4))->>'count')::int), 2, 'C10 custom window selects exactly the fixed inclusive dates');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, null, 100, null, current_date - 6, current_date - 4))->'orders'->0->>'order_id')), '00000000-0000-0000-0000-00000001d040', 'C11 and is STILL newest-first inside a custom window');

-- Keyset pagination is unaffected: page 2 continues exactly where page 1 stopped.
create temporary table t_p1 on commit drop as
  select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today', null, null, null, null, 3) as res;
select is((select (res->>'count')::int from t_p1), 3, 'C12 page 1 honours p_limit');
select is((select (res->>'has_more')::boolean from t_p1), true, 'C13 page 1 knows there is more');
select isnt((select res->>'next_cursor' from t_p1), null, 'C14 page 1 hands back a cursor');
select is((select res->'orders'->2->>'order_id' from t_p1), '00000000-0000-0000-0000-00000001d005', 'C15 page 1 ends on the draft order (14:00)');

create temporary table t_p2 on commit drop as
  select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today', null, null, null, null, 3,
    (select res->>'next_cursor' from t_p1)) as res;
select is((select res->'orders'->0->>'order_id' from t_p2), '00000000-0000-0000-0000-00000001d004', 'C16 page 2 resumes at the NEXT row, with no overlap and no gap');
select is((select (res->>'count')::int from t_p2), 3, 'C17 page 2 is full');

-- Pagination inside a CUSTOM window behaves identically.
create temporary table t_cp1 on commit drop as
  select app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, null, 3, null, current_date, current_date) as res;
select is((select (res->>'count')::int from t_cp1), 3, 'C18 a custom window paginates like any other');
select is((select res->'orders'->0->>'order_id' from t_cp1), '00000000-0000-0000-0000-00000001d008', 'C19 newest-first is preserved under custom + limit');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, null, 3, (select res->>'next_cursor' from t_cp1), current_date, current_date))->'orders'->0->>'order_id')), '00000000-0000-0000-0000-00000001d004', 'C20 and the cursor still resumes correctly');

-- Filters still apply inside the new windows.
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, 'cash', 100, null, current_date, current_date))->>'count')::int), 1, 'C21 the payment filter still works inside a custom window');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, 'card', 100, null, current_date, current_date))->'orders'->0->>'order_id')), '00000000-0000-0000-0000-00000001d002', 'C22 and picks the right tender');
select is((select ((app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last90', null, 'voided', null, null, 100))->>'count')::int), 1, 'C23 the status filter still works across a 90-day window');
select throws_ok($$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last90', null, null, null, 'giftcard')$$, '22023', null, 'C24 an unknown payment token still raises');

select throws_ok($$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, null, 25, null, current_date, null)$$, '22023', null, 'C25 half-supplied custom window rejected');
select throws_ok($$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, null, 25, null, current_date, current_date - 1)$$, '22023', null, 'C26 reversed custom range rejected');
select throws_ok($$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, null, null, null, null, null, 25, null, current_date - 92, current_date)$$, '22023', null, 'C27 93-day custom window rejected');
select throws_ok($$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$, '22023', null, 'C28 unknown range still raises 22023');
select throws_ok($$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'last90', null, null, null, null, 25, 'not-a-cursor')$$, '22023', null, 'C29 an invalid cursor still raises 22023');

-- ============================================================================
-- D. owner_sales_series — last60 / last90 as first-class tokens
-- ============================================================================
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'today'))->'buckets')), 1, 'D1 today unchanged');
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last30'))->'buckets')), 3, 'D2 last30 unchanged');
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->'buckets')), 5, 'D3 last60 adds the t-45 and t-59 days');
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->'buckets')), 8, 'D4 last90 adds t-60, t-75 and t-89 — and stops before t-90');
select is((select (app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->>'range'), 'last90', 'D5 the token is echoed, not rewritten to custom');
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->'buckets'->0->>'day')), to_char(current_date - 59, 'YYYY-MM-DD'), 'D6 the earliest last60 bucket is exactly t-59');
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->'buckets'->0->>'day')), to_char(current_date - 89, 'YYYY-MM-DD'), 'D7 the earliest last90 bucket is exactly t-89');
select is((select sum((b->>'net_minor')::bigint)::bigint from jsonb_array_elements((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last90'))->'buckets') b), 15740::bigint, 'D8 the series sums to the SAME last90 net owner_report_range reports');
select is((select sum((b->>'net_minor')::bigint)::bigint from jsonb_array_elements((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'last60'))->'buckets') b), 8091::bigint, 'D9 and the same last60 net — one vocabulary, one answer');

-- The custom path is untouched by adding preset tokens.
select is((select (app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 46, current_date - 44))->>'range'), 'custom', 'D10 custom still reports range=custom');
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 46, current_date - 44))->'buckets')), 1, 'D11 custom still selects exactly the days asked for');
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 92, current_date)$$, '22023', null, 'D12 the 92-day cap still holds');
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$, '22023', null, 'D13 an unknown token still raises 22023');

-- ============================================================================
-- F. S0.1 — VOIDED / CANCELLED LINES ARE NOT REVENUE (gross rollups)
-- ============================================================================
-- A line voided or cancelled OFF a live bill is not sold. The order writers
-- already say so: orders.subtotal_minor is recomputed as SUM(line_total_minor)
-- over lines whose status is NOT voided/cancelled. The gross rollup in
-- owner_report_range and owner_sales_series read every non-deleted line
-- instead, so a line struck off the bill still inflated gross — and the
-- discount captured on that dead line inflated discount_minor with it.
--
-- Net was never affected (it reads orders.subtotal_minor), which is exactly why
-- this could sit unnoticed: the headline number was right while the number
-- beside it was wrong.
--
-- Today's branch-A1a fixture, after S0.1:
--   live lines      600 + 400 + 300 + (200 total, 40 discount) + 100 + 300 + 300
--                   => SUM(line_total) = 2200, SUM(line_discount) = 40
--   dead lines      T1 cancelled (250 + 25) and T7 voided (370 + 30)
--
--   gross    = SUM(line_total + line_discount) over LIVE lines   = 2240
--   discount = SUM(live line_discount) + SUM(order discount)     =   40
--   net      = SUM(order subtotal - order discount)              = 2200
--
-- Before the fix those were 2915 and 95: the two dead lines contributed 675 of
-- invented gross.

-- The fixture guards come FIRST. Every assertion below is about rows being
-- EXCLUDED, so if the dead lines ever vanished from the fixture the whole
-- section would pass while proving nothing.
select is((select count(*)::int from order_items oi
           where oi.order_id in ('00000000-0000-0000-0000-00000001d001',
                                 '00000000-0000-0000-0000-00000001d007')
             and oi.deleted_at is null
             and oi.status in ('voided', 'cancelled')),
          2, 'F1 the fixture really holds dead lines INSIDE live billed orders');
select is((select sum(oi.line_total_minor + oi.line_discount_minor)::bigint from order_items oi
           where oi.order_id in ('00000000-0000-0000-0000-00000001d001',
                                 '00000000-0000-0000-0000-00000001d007')
             and oi.deleted_at is null
             and oi.status in ('voided', 'cancelled')),
          675::bigint, 'F2 and they carry real money, so excluding them is observable');

create temporary table t_gross on commit drop as
  select app.owner_report_range(
    '00000000-0000-0000-0000-0000000a0000',
    '00000000-0000-0000-0000-0000000a1000',
    '00000000-0000-0000-0000-0000000a1a00', 'today') as res;

select is((select (res->'current'->>'gross_minor')::bigint from t_gross), 2240::bigint,
          'F3 owner_report_range gross EXCLUDES voided and cancelled lines');
select is((select (res->'current'->>'discount_minor')::bigint from t_gross), 40::bigint,
          'F4 and so does the item-discount component — 40 is the LIVE line''s discount, not the dead lines'' 55');
select is((select (res->'current'->>'net_minor')::bigint from t_gross), 2200::bigint,
          'F5 net is UNCHANGED — it always read orders.subtotal_minor');
select is((select ((res->'current'->>'gross_minor')::bigint - (res->'current'->>'discount_minor')::bigint) from t_gross),
          (select (res->'current'->>'net_minor')::bigint from t_gross),
          'F6 gross - discount = net: the three now describe ONE set of lines');

create temporary table t_series_gross on commit drop as
  select app.owner_sales_series(
    '00000000-0000-0000-0000-0000000a0000',
    '00000000-0000-0000-0000-0000000a1000',
    '00000000-0000-0000-0000-0000000a1a00', 'today')->'buckets'->0 as b;

select is((select (b->>'gross_minor')::bigint from t_series_gross), 2240::bigint,
          'F7 owner_sales_series gross excludes them in the daily bucket too');
select is((select (b->>'discount_minor')::bigint from t_series_gross), 40::bigint,
          'F8 and its discount matches owner_report_range exactly');
select is((select (b->>'net_minor')::bigint from t_series_gross), 2200::bigint,
          'F9 the series net is unchanged as well');
select is((select ((b->>'gross_minor')::bigint - (b->>'discount_minor')::bigint) from t_series_gross),
          (select (b->>'net_minor')::bigint from t_series_gross),
          'F10 and the same identity holds — the chart and the KPI card agree');

-- ============================================================================
-- E. ACL + security posture
-- ============================================================================
-- EXACTLY ONE definition of each widened name: the DROP really removed the old
-- signature instead of leaving an overload pair for PostgREST to choose between.
select is((select count(*)::int from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'owner_report_range'), 1, 'E1 exactly one app.owner_report_range survives');
select is((select count(*)::int from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'owner_report_range'), 1, 'E2 exactly one public.owner_report_range survives');
select is((select count(*)::int from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'owner_order_history'), 1, 'E3 exactly one app.owner_order_history survives');
select is((select count(*)::int from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'owner_order_history'), 1, 'E4 exactly one public.owner_order_history survives');

-- Security posture, read from the catalog rather than assumed.
select is((select p.prosecdef from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'owner_top_items'), true, 'E5 app.owner_top_items is SECURITY DEFINER');
select is((select p.prosecdef from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'owner_top_items'), false, 'E6 the public wrapper is SECURITY INVOKER');
-- `set search_path = ''` is STORED as the element search_path="" (quoted empty
-- string), not as a bare trailing '='. A NULL proconfig means nothing was
-- pinned at all, so it must fail the check rather than skip it.
select ok(not exists (
  select 1 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'app' and p.proname in ('owner_top_items','owner_report_range','owner_order_history','owner_sales_series')
    and not (coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""'])
), 'E7 every app implementation pins an EMPTY search_path');
select ok(not exists (
  select 1 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('owner_top_items','owner_report_range','owner_order_history','owner_sales_series')
    and not (coalesce(p.proconfig, '{}'::text[]) @> array['search_path=""'])
), 'E8 and so does every public wrapper');
select is((select p.prosecdef from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'owner_report_range'), true, 'E9 the recreated app.owner_report_range is still SECURITY DEFINER');
select is((select p.prosecdef from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and p.proname = 'owner_order_history'), true, 'E10 the recreated app.owner_order_history is still SECURITY DEFINER');

-- PUBLIC holds no EXECUTE. coalesce(proacl, acldefault(...)) is load-bearing: a
-- NULL proacl means DEFAULT privileges, under which PUBLIC *does* hold EXECUTE,
-- and an aclexplode over NULL would return no rows and pass vacuously.
select ok(not exists (
  select 1 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
  where n.nspname = 'public' and p.proname in ('owner_top_items','owner_report_range','owner_order_history','owner_sales_series')
    and a.grantee = 0 and a.privilege_type = 'EXECUTE'
), 'E11 PUBLIC holds EXECUTE on none of the four public wrappers');
select ok(not exists (
  select 1 from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
  where n.nspname = 'app' and p.proname in ('owner_top_items','owner_report_range','owner_order_history','owner_sales_series')
    and a.grantee = 0 and a.privilege_type = 'EXECUTE'
), 'E12 PUBLIC holds EXECUTE on none of the four app implementations');

select ok(not has_function_privilege('anon', 'public.owner_top_items(uuid,uuid,uuid,text,date,date,integer)', 'execute'), 'E13 anon cannot execute public.owner_top_items');
select ok(has_function_privilege('authenticated', 'public.owner_top_items(uuid,uuid,uuid,text,date,date,integer)', 'execute'), 'E14 authenticated can');
select ok(not has_function_privilege('anon', 'public.owner_report_range(uuid,uuid,uuid,text,date,date)', 'execute'), 'E15 anon cannot execute the widened owner_report_range');
select ok(has_function_privilege('authenticated', 'public.owner_report_range(uuid,uuid,uuid,text,date,date)', 'execute'), 'E16 authenticated can — the grant survived the DROP');
select ok(not has_function_privilege('anon', 'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text,date,date)', 'execute'), 'E17 anon cannot execute the widened owner_order_history');
select ok(has_function_privilege('authenticated', 'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text,date,date)', 'execute'), 'E18 authenticated can');
select ok(not has_function_privilege('anon', 'app.owner_top_items(uuid,uuid,uuid,text,date,date,integer)', 'execute'), 'E19 anon cannot execute the app implementation either');
select ok(not has_function_privilege('anon', 'public.owner_sales_series(uuid,uuid,uuid,text,date,date)', 'execute'), 'E20 anon still cannot execute owner_sales_series');

select * from finish();
rollback;
