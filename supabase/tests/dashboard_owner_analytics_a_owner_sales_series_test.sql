-- ============================================================================
-- DASHBOARD-OWNER-ANALYTICS-A — pgTAP: app/public.owner_sales_series.
--
-- Fixture: Org A (Rest A1 tz=UTC -> branch A1a; Rest A3 tz='Etc/GMT-3' (UTC+3)
-- -> branch A3a) and Org B (isolation). Branch A1a carries, on LOCAL TODAY, a
-- dine_in order with items (gross 1200 / item discount 100 / order discount 100
-- => net 1000), a takeaway order (net 500), a VOIDED order (grand 700), a
-- CANCELLED order, a DRAFT order and a soft-DELETED order — so every exclusion
-- rule is proven by a row that would otherwise change the numbers. Payments on
-- local today: cash 600, card 300, bit 100, external 50 (all completed) plus a
-- PENDING cash 999 that must never be collected. Branch A3a carries a 00:30
-- local-today order (which is YESTERDAY in UTC) to prove per-branch windowing.
--
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(42);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'oss-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'oss-b', 'EUR');
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
  ('00000000-0000-0000-0000-00000000f001', 'oss-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'oss-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'oss-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'oss-orgb-owner@example.test');
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

-- Branch A1a (tz=UTC), LOCAL TODAY. Every exclusion rule gets a real row.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at, deleted_at) values
  ('00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS', 1100, 100, 0, 1000, 'oss-o-1', (current_date + interval '10 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway', 'completed', 'ILS',  500,   0, 0,  500, 'oss-o-2', (current_date + interval '11 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'voided',    'ILS',  700,   0, 0,  700, 'oss-o-v', (current_date + interval '12 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'cancelled', 'ILS',  900,   0, 0,  900, 'oss-o-c', (current_date + interval '13 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'draft',     'ILS',  300,   0, 0,  300, 'oss-o-d', (current_date + interval '14 hours') at time zone 'UTC', null),
  ('00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS',  400,   0, 0,  400, 'oss-o-x', (current_date + interval '15 hours') at time zone 'UTC', now());

-- Items ONLY on order 1: gross = line_total + line_discount = 1100 + 100 = 1200,
-- item discount = 100. Combined with the order-level discount 100 the expected
-- discount_minor is 200, exactly as owner_report_range computes it.
-- The schema enforces ONE completed payment per order (payments_one_completed_per_order_uidx),
-- so each tender kind needs its own order. That is a real domain rule, not a
-- test convenience: an order is settled once.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS', 200, 0, 0, 200, 'oss-o-7', (current_date + interval '16 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway', 'completed', 'ILS', 100, 0, 0, 100, 'oss-o-8', (current_date + interval '17 hours') at time zone 'UTC');

-- Minimal menu fixture so an order_item can exist (menu_item_id is NOT NULL).
insert into menu_categories (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000010c01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Mains');
insert into menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-000000010b01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-000000010c01', 'Falafel', 1100, 'ILS');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, menu_item_name_snapshot, quantity, unit_price_minor_snapshot, line_total_minor, line_discount_minor) values
  ('00000000-0000-0000-0000-000000011001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-000000010b01', 'Falafel', 1, 1100, 1100, 100);

-- Payments on LOCAL TODAY: four completed tenders + one PENDING that must never
-- appear in collected_minor or by_method.
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000000012001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 600, 600, 0, 'ILS', 'oss-p-1', (current_date + interval '10 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000012002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'card', 'completed', 300, 300, 0, 'ILS', 'oss-p-2', (current_date + interval '11 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000012003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d007', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'bit', 'completed', 100, 100, 0, 'ILS', 'oss-p-3', (current_date + interval '16 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000012004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d008', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'external', 'completed', 50, 50, 0, 'ILS', 'oss-p-4', (current_date + interval '17 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000012005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'pending', 999, 999, 0, 'ILS', 'oss-p-5', (current_date + interval '11 hours 7 minutes') at time zone 'UTC');

-- Branch A3a (tz=Etc/GMT-3 = UTC+3): 00:30 LOCAL TODAY, which is UTC-yesterday.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001da01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a3000', '00000000-0000-0000-0000-0000000a3a00', '00000000-0000-0000-0000-00000000d005', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 1111, 0, 0, 1111, 'oss-a3-t', ((now() at time zone 'Etc/GMT-3')::date + interval '30 minutes') at time zone 'Etc/GMT-3');

-- ===== owner, branch A1a, TODAY ============================================
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';

create temporary table t_today on commit drop as
  select app.owner_sales_series(
    '00000000-0000-0000-0000-0000000a0000',
    '00000000-0000-0000-0000-0000000a1000',
    '00000000-0000-0000-0000-0000000a1a00', 'today') as res;

-- (1-4) envelope + bucket shape
select is((select (res->>'ok')::boolean from t_today), true, 'ok envelope is true');
select is((select res->>'entity' from t_today), 'owner_sales_series', 'entity name');
select is((select res->>'currency_code' from t_today), 'ILS', 'currency from the org');
select is((select jsonb_array_length(res->'buckets') from t_today), 1, 'today = exactly one daily bucket');

-- (5-11) money semantics
select is((select (res->'buckets'->0->>'day') from t_today), to_char(current_date, 'YYYY-MM-DD'), 'bucket day is the branch-local date');
select is((select (res->'buckets'->0->>'order_count')::int from t_today), 4, 'order_count counts only billed rows (void/cancel/draft/deleted excluded)');
select is((select (res->'buckets'->0->>'gross_minor')::bigint from t_today), 1200::bigint, 'gross = line_total + line_discount');
select is((select (res->'buckets'->0->>'discount_minor')::bigint from t_today), 200::bigint, 'discount = item discount + order discount');
select is((select (res->'buckets'->0->>'net_minor')::bigint from t_today), 1800::bigint, 'net = sum(subtotal - order discount) = 1000+500+200+100');
select is((select (res->'buckets'->0->>'void_count')::int from t_today), 1, 'voids are counted in their OWN bucket');
select is((select (res->'buckets'->0->>'void_total_minor')::bigint from t_today), 700::bigint, 'void total uses grand_total and is not folded into billed');

-- (12-14) collected is NOT billed
select is((select (res->'buckets'->0->>'collected_minor')::bigint from t_today), 1050::bigint, 'collected = 600+300+100+50 COMPLETED only (pending 999 excluded)');
select is((select (res->'buckets'->0->>'cash_minor')::bigint from t_today), 600::bigint, 'cash_minor = completed cash only');
select isnt((select (res->'buckets'->0->>'collected_minor') from t_today), (select (res->'buckets'->0->>'net_minor') from t_today), 'billed and collected are different numbers');

-- (15-20) by_method
select is((select jsonb_array_length(res->'buckets'->0->'by_method') from t_today), 4, 'by_method has one row per completed tender kind');
select is((select (res->'buckets'->0->'by_method'->0->>'method') from t_today), 'bit', 'by_method ordered by method (bit first)');
select is((select (res->'buckets'->0->'by_method'->1->>'method') from t_today), 'card', 'by_method includes card');
select is((select (res->'buckets'->0->'by_method'->2->>'method') from t_today), 'cash', 'by_method includes cash');
select is((select (res->'buckets'->0->'by_method'->3->>'method') from t_today), 'external', 'by_method includes external');
select is((select (m->>'total_minor')::bigint from t_today, jsonb_array_elements(res->'buckets'->0->'by_method') m where m->>'method' = 'cash'), 600::bigint, 'cash by_method total matches cash_minor');

-- (21-22) by_method counts + pending exclusion
select is((select (m->>'count')::int from t_today, jsonb_array_elements(res->'buckets'->0->'by_method') m where m->>'method' = 'cash'), 1, 'cash count excludes the PENDING payment');
select is((select coalesce(sum((m->>'total_minor')::bigint), 0)::bigint from t_today, jsonb_array_elements(res->'buckets'->0->'by_method') m), 1050::bigint, 'by_method totals sum to collected_minor');

-- (23-26) by_order_type
select is((select jsonb_array_length(res->'buckets'->0->'by_order_type') from t_today), 2, 'by_order_type has dine_in + takeaway');
select is((select (res->'buckets'->0->'by_order_type'->0->>'order_type') from t_today), 'dine_in', 'persisted token dine_in');
select is((select (res->'buckets'->0->'by_order_type'->1->>'order_type') from t_today), 'takeaway', 'persisted token takeaway');
select is((select (t->>'net_minor')::bigint from t_today, jsonb_array_elements(res->'buckets'->0->'by_order_type') t where t->>'order_type' = 'takeaway'), 600::bigint, 'takeaway net = 500 + 100');

-- ===== ranges ===============================================================
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','yesterday'))->'buckets')), 0, 'yesterday has no facts => stable empty buckets array');
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','last7'))->'buckets'->0->>'net_minor')::bigint), 1800::bigint, 'last7 includes today');
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','last30'))->'buckets'->0->>'net_minor')::bigint), 1800::bigint, 'last30 includes today');

-- ===== custom window ========================================================
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, current_date, current_date))->>'range')), 'custom', 'custom window reports range=custom');
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, current_date - 1)$$, '22023', null, 'inverted custom range rejected');
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 92, current_date)$$, '22023', null, '>92 day window rejected');
select lives_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date - 91, current_date)$$, 'exactly 92 inclusive days accepted');
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, null, current_date, null)$$, '22023', null, 'half-supplied custom window rejected');
-- DASHBOARD-VISUAL-RANGE-REFRESH-S0 promoted 'last90' to a real preset token,
-- so the probe uses one that is still unknown. The rule is unchanged: an
-- unrecognised token is a bad request, never a silent fallback to today.
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$, '22023', null, 'unknown predefined range => 22023');

-- ===== branch-local timezone ===============================================
select is((select jsonb_array_length((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a3000','00000000-0000-0000-0000-0000000a3a00','today'))->'buckets')), 1, 'A3a 00:30 local order lands in LOCAL today, not UTC yesterday');

-- ===== authorization ========================================================
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today'))->>'ok')::boolean), true, 'cashier is a financial-read role (matches owner_report_range)');

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is((select ((app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00','today'))->>'error')), 'permission_denied', 'kitchen_staff denied owner financial analytics');

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f005';
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000', null, null, 'today')$$, '42501', null, 'cross-org caller cannot read Org A');

set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
select throws_ok($$select app.owner_sales_series('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a3000','00000000-0000-0000-0000-0000000a3a00','today')$$, '42501', null, 'branch-scoped cashier cannot reach a sibling restaurant/branch');

-- ===== grants ===============================================================
select ok(not has_function_privilege('anon', 'public.owner_sales_series(uuid,uuid,uuid,text,date,date)', 'execute'), 'anon cannot execute the public wrapper');
select ok(has_function_privilege('authenticated', 'public.owner_sales_series(uuid,uuid,uuid,text,date,date)', 'execute'), 'authenticated can execute the public wrapper');

select * from finish();
rollback;
