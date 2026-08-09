-- ============================================================================
-- DASHBOARD-OWNER-ANALYTICS-B — pgTAP for the two SERVER-B changes:
--   (A) app.owner_report_range.comparison gains completed_count + discount_minor
--   (B) app.owner_order_history.p_payment accepts card / bit / external and
--       now VALIDATES the token (22023) instead of silently matching nothing.
--
-- Fixture: Org A (Rest A1 tz=UTC -> Branch A1a) plus Org B for isolation.
--
--   TODAY (the CURRENT window for p_range='today'):
--     T1 cash 1000 · T2 card 800 · T3 bit 300 · T4 external 200 — one COMPLETED
--     tender each, because payments_one_completed_per_order_uidx allows exactly
--     one completed payment per order. T5 is served and untendered. T6 is served
--     and carries a PENDING card payment, so it proves that a method filter
--     follows COMPLETED tender and never a merely-attempted one.
--
--   YESTERDAY (the PRIOR window for p_range='today'):
--     Y1 completed, order discount 100, one item with line_discount 50
--         => gross 950, discount 150, net 800, and a COMPLETED cash 400;
--     Y2 served (billed, not completed) net 300;
--     Y3 voided and Y4 draft, which must not reach the sales aggregate.
--   So the prior window is order_count 2 / completed_count 1 / discount 150 —
--   three numbers that are all DIFFERENT, so a test cannot pass by accident if
--   one key silently reads another key's column.
--
-- Session pinned to UTC; hex-only UUIDs; identity GUC only.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(46);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'ocb-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'ocb-b', 'EUR');
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
  ('00000000-0000-0000-0000-00000000f001', 'ocb-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'ocb-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Boaz R.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');

-- --- TODAY: one order per tender kind, plus untendered and pending-tender ----
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000002d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS', 1000, 0, 0, 1000, 'ocb-t1', (current_date + interval '9 hours')  at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'completed', 'ILS',  800, 0, 0,  800, 'ocb-t2', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway', 'completed', 'ILS',  300, 0, 0,  300, 'ocb-t3', (current_date + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002d004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway', 'completed', 'ILS',  200, 0, 0,  200, 'ocb-t4', (current_date + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'served',    'ILS',  500, 0, 0,  500, 'ocb-t5', (current_date + interval '13 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002d006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in',  'served',    'ILS',  700, 0, 0,  700, 'ocb-t6', (current_date + interval '14 hours') at time zone 'UTC');

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000000022001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002d001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash',     'completed', 1000, 1000, 0, 'ILS', 'ocb-p1', (current_date + interval '9 hours 5 minutes')  at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000022002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002d002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'card',     'completed',  800,  800, 0, 'ILS', 'ocb-p2', (current_date + interval '10 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000022003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002d003', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'bit',      'completed',  300,  300, 0, 'ILS', 'ocb-p3', (current_date + interval '11 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-000000022004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002d004', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'external', 'completed',  200,  200, 0, 'ILS', 'ocb-p4', (current_date + interval '12 hours 5 minutes') at time zone 'UTC'),
  -- T6: a card tender that was ATTEMPTED and never completed.
  ('00000000-0000-0000-0000-000000022006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002d006', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'card',     'pending',    700,  700, 0, 'ILS', 'ocb-p6', (current_date + interval '14 hours 5 minutes') at time zone 'UTC');

-- --- YESTERDAY: the PRIOR window for p_range='today' ------------------------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000002e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 900, 100, 0, 800, 'ocb-y1', (current_date - 1 + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002e002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 300,   0, 0, 300, 'ocb-y2', (current_date - 1 + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002e003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'voided',    'ILS', 400,   0, 0, 400, 'ocb-y3', (current_date - 1 + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000002e004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'draft',     'ILS', 250,   0, 0, 250, 'ocb-y4', (current_date - 1 + interval '13 hours') at time zone 'UTC');

insert into menu_categories (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000020c01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Mains');
insert into menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-000000020b01', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-000000020c01', 'Falafel', 900, 'ILS');
-- gross = line_total + line_discount = 900 + 50; item discount 50 + order discount 100 = 150.
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, menu_item_name_snapshot, quantity, unit_price_minor_snapshot, line_total_minor, line_discount_minor) values
  ('00000000-0000-0000-0000-000000021001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002e001', '00000000-0000-0000-0000-000000020b01', 'Falafel', 1, 900, 900, 50);

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000000022101', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002e001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 400, 400, 0, 'ILS', 'ocb-py1', (current_date - 1 + interval '10 hours 5 minutes') at time zone 'UTC');

-- --- Org B: a card-tendered order that must never cross the tenant boundary --
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000002b001', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'completed', 'EUR', 600, 0, 0, 600, 'ocb-b1', (current_date + interval '9 hours') at time zone 'UTC');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-000000022b01', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000002b001', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'card', 'completed', 600, 600, 0, 'EUR', 'ocb-pb1', (current_date + interval '9 hours 5 minutes') at time zone 'UTC');

-- ============================================================================
-- (A) owner_report_range.comparison
-- ============================================================================
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';

create temporary table t_rr on commit drop as
  select app.owner_report_range(
           '00000000-0000-0000-0000-0000000a0000',
           '00000000-0000-0000-0000-0000000a1000',
           '00000000-0000-0000-0000-0000000a1a00', 'today') as today,
         app.owner_report_range(
           '00000000-0000-0000-0000-0000000a0000',
           '00000000-0000-0000-0000-0000000a1000',
           '00000000-0000-0000-0000-0000000a1a00', 'yesterday') as yday;

-- (1-3) the new keys exist
select is((select (today->>'ok')::boolean from t_rr), true, 'owner_report_range still answers ok');
select ok((select today->'comparison' ? 'completed_count' from t_rr), 'comparison carries completed_count');
select ok((select today->'comparison' ? 'discount_minor'  from t_rr), 'comparison carries discount_minor');

-- (4-5) and they carry the PRIOR window's facts, not the current window's
select is((select (today->'comparison'->>'completed_count')::bigint from t_rr), 1::bigint,
          'comparison completed_count = yesterday completed orders (served Y2 excluded)');
select is((select (today->'comparison'->>'discount_minor')::bigint from t_rr), 150::bigint,
          'comparison discount_minor = item discount 50 + order discount 100');

-- (6-10) every pre-existing comparison key is untouched
select is((select (today->'comparison'->>'order_count')::bigint     from t_rr), 2::bigint,   'comparison order_count unchanged (voided + draft excluded)');
select is((select (today->'comparison'->>'gross_minor')::bigint     from t_rr), 950::bigint, 'comparison gross_minor unchanged');
select is((select (today->'comparison'->>'net_minor')::bigint       from t_rr), 1100::bigint,'comparison net_minor unchanged (800 + 300)');
select is((select (today->'comparison'->>'cash_minor')::bigint      from t_rr), 400::bigint, 'comparison cash_minor unchanged');
select is((select (today->'comparison'->>'collected_minor')::bigint from t_rr), 400::bigint, 'comparison collected_minor unchanged');

-- (11-12) nothing else moved, and unpaid_count was NOT fabricated
select is((select count(*)::int from t_rr, jsonb_object_keys(today->'comparison')), 7,
          'comparison has exactly the five original keys plus the two new ones');
select ok((select not (today->'comparison' ? 'unpaid_count') from t_rr),
          'comparison does NOT claim a historical unpaid_count (unpaid is a CURRENT settlement snapshot)');

-- (13) the strongest statement available: the prior window read as `comparison`
-- is the SAME window read as `current` when the caller asks for yesterday.
select is(
  (select today->'comparison' from t_rr),
  (select jsonb_build_object(
            'order_count',     yday->'current'->'order_count',
            'gross_minor',     yday->'current'->'gross_minor',
            'net_minor',       yday->'current'->'net_minor',
            'cash_minor',      yday->'current'->'cash_minor',
            'collected_minor', yday->'current'->'collected_minor',
            'completed_count', yday->'current'->'completed_count',
            'discount_minor',  yday->'current'->'discount_minor')
   from t_rr),
  'comparison == the same window read as current — one definition of "previous"');

-- (14) completed_count is a distinct fact, not an alias of order_count
select isnt((select today->'comparison'->'completed_count' from t_rr),
            (select today->'comparison'->'order_count' from t_rr),
            'completed_count is not a second copy of order_count');

-- (15-17) the CURRENT object is untouched by this change
select is((select (today->'current'->>'completed_count')::bigint from t_rr), 4::bigint, 'current completed_count still 4');
select is((select (today->'current'->>'discount_minor')::bigint  from t_rr), 0::bigint, 'current discount_minor still computed from the current window');
select is((select (today->'current'->>'unpaid_count')::bigint    from t_rr), 2::bigint, 'current unpaid_count still 2 (T5 untendered + T6 pending)');

-- (18-20) NO prior data => the keys are present and zero, never absent or null,
-- so a client can tell "prior window was empty" from "server sent nothing".
select ok((select yday->'comparison' ? 'completed_count' from t_rr), 'empty prior window still emits completed_count');
select is((select (yday->'comparison'->>'completed_count')::bigint from t_rr), 0::bigint, 'empty prior window completed_count = 0');
select is((select (yday->'comparison'->>'discount_minor')::bigint  from t_rr), 0::bigint, 'empty prior window discount_minor = 0');

-- (21) recreating the function did not drop its input validation.
-- DASHBOARD-VISUAL-RANGE-REFRESH-S0 made 'last90' a REAL token, so the probe
-- moved to one that is still unknown. The rule under test is unchanged.
select throws_ok(
  $$select app.owner_report_range('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$,
  '22023', null, 'owner_report_range still rejects an unknown range');

-- (22) the public wrapper carries the new keys through unchanged
select is((select (public.owner_report_range(
             '00000000-0000-0000-0000-0000000a0000',
             '00000000-0000-0000-0000-0000000a1000',
             '00000000-0000-0000-0000-0000000a1a00', 'today')->'comparison'->>'discount_minor')::bigint),
          150::bigint, 'public wrapper returns the new comparison keys');

-- (23-24) the ACL survives. S0 later DROPPED and recreated this function to
-- append p_start/p_end, which takes the grants with it — so these now assert
-- that the recreate restated them, against the 6-argument signature.
select ok(not has_function_privilege('anon', 'public.owner_report_range(uuid,uuid,uuid,text,date,date)', 'execute'),
          'anon still cannot execute public.owner_report_range');
select ok(has_function_privilege('authenticated', 'public.owner_report_range(uuid,uuid,uuid,text,date,date)', 'execute'),
          'authenticated still can execute public.owner_report_range');

-- ============================================================================
-- (B) owner_order_history.p_payment
-- ============================================================================
create temporary table t_oh on commit drop as
  select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, null,       50, null) as all_orders,
         app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, 'cash',     50, null) as f_cash,
         app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, 'card',     50, null) as f_card,
         app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, 'bit',      50, null) as f_bit,
         app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, 'external', 50, null) as f_external,
         app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, 'paid',     50, null) as f_paid,
         app.owner_order_history('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'today', null, null, null, 'unpaid',   50, null) as f_unpaid;

-- (25) the unfiltered baseline the filters are measured against
select is((select (all_orders->>'count')::int from t_oh), 6, 'unfiltered today = 6 orders');

-- (26-31) the three NEW tokens each select exactly their own order
select is((select (f_card->>'count')::int from t_oh), 1, 'card filter returns one order');
select is((select f_card->'orders'->0->>'order_id' from t_oh), '00000000-0000-0000-0000-00000002d002', 'card filter returns the card-tendered order');
select is((select (f_bit->>'count')::int from t_oh), 1, 'bit filter returns one order');
select is((select f_bit->'orders'->0->>'order_id' from t_oh), '00000000-0000-0000-0000-00000002d003', 'bit filter returns the bit-tendered order');
select is((select (f_external->>'count')::int from t_oh), 1, 'external filter returns one order');
select is((select f_external->'orders'->0->>'order_id' from t_oh), '00000000-0000-0000-0000-00000002d004', 'external filter returns the external-tendered order');

-- (32-33) cash — the token that already existed — still behaves identically
select is((select (f_cash->>'count')::int from t_oh), 1, 'cash filter still returns one order');
select is((select f_cash->'orders'->0->>'order_id' from t_oh), '00000000-0000-0000-0000-00000002d001', 'cash filter still returns the cash-tendered order');

-- (34-35) settlement tokens are untouched by the method widening
select is((select (f_paid->>'count')::int   from t_oh), 4, 'paid filter unchanged: the four settled orders');
select is((select (f_unpaid->>'count')::int from t_oh), 2, 'unpaid filter unchanged: untendered + pending-tender');

-- (36-38) a PENDING tender is not a method match, and never renders as one
select is((select count(*)::int from t_oh, jsonb_array_elements(f_card->'orders') o
           where o->>'order_id' = '00000000-0000-0000-0000-00000002d006'), 0,
          'the pending-card order is NOT selected by the card filter');
select is((select o->>'payment_method' from t_oh, jsonb_array_elements(all_orders->'orders') o
           where o->>'order_id' = '00000000-0000-0000-0000-00000002d006'), null::text,
          'the pending-card order reports no payment_method at all');
select is((select o->>'payment_status' from t_oh, jsonb_array_elements(f_card->'orders') o
           where o->>'order_id' = '00000000-0000-0000-0000-00000002d002'), 'paid',
          'a card-filtered order still reports its settlement status');

-- (39-41) an unknown token now FAILS LOUDLY instead of returning an empty list
-- that reads exactly like "no such orders exist".
select throws_ok(
  $$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, null, 'crypto', 25, null)$$,
  '22023', null, 'unknown payment token => 22023');
select throws_ok(
  $$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, null, '', 25, null)$$,
  '22023', null, 'empty payment token => 22023, not "everything" and not "nothing"');
select throws_ok(
  $$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, null, 'CARD', 25, null)$$,
  '22023', null, 'payment tokens are case-sensitive, like every other filter here');

-- (42) recreating the function did not drop its other validation.
-- 'last90' is a real token since S0; the probe moved, the rule did not.
select throws_ok(
  $$select app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'quarter')$$,
  '22023', null, 'owner_order_history still rejects an unknown range');

-- (43-44) the widened filter did not widen the tenant boundary
select is((select count(*)::int from jsonb_array_elements(
             (app.owner_order_history('00000000-0000-0000-0000-0000000a0000', null, null, 'today', null, null, null, 'card', 50, null))->'orders') o
           where o->>'order_id' = '00000000-0000-0000-0000-00000002b001'), 0,
          'Org A card filter cannot see Org B''s card order');
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f005';
select is((select (app.owner_order_history('00000000-0000-0000-0000-0000000b0000', null, null, 'today', null, null, null, 'card', 50, null))->'orders'->0->>'order_id'),
          '00000000-0000-0000-0000-00000002b001', 'Org B owner sees only Org B''s card order');

-- (45-46) ACL preserved across the S0 DROP + recreate (p_start/p_end appended)
select ok(not has_function_privilege('anon', 'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text,date,date)', 'execute'),
          'anon still cannot execute public.owner_order_history');
select ok(has_function_privilege('authenticated', 'public.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,int,text,date,date)', 'execute'),
          'authenticated still can execute public.owner_order_history');

select * from finish();
rollback;
