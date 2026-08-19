-- ============================================================================
-- OPS-043 Phase 5A — pgTAP: the four Overview report RPCs advertise the
-- EFFECTIVE restaurant currency, not the organization default.
--
-- WHY THIS EXISTS. Phase 1 made `restaurants.currency_override` writable and
-- Phase 2 moved `owner_order_history` / `owner_active_orders` onto
-- `coalesce(override, default)`. These four were left behind, so a restaurant
-- operating in an overridden currency had its Overview labelled with the
-- organization's. Phase 5 reproduced the consequence: with default ILS and
-- override JOD, 47400 minor units rendered `JOD 47.400` in one card and a
-- 2-decimal figure in another ON THE SAME SCREEN, because the formatter takes
-- its exponent from the label.
--
-- FIXTURE. One organization defaulting to ILS with two restaurants:
--   * Rest P1 carries currency_override = 'JOD' (a 3-decimal currency, chosen
--     deliberately: an exponent difference turns a wrong label into a wrong
--     NUMBER, which is the failure this pins);
--   * Rest P2 carries NO override, so it must still inherit ILS.
-- Plus a second organization (EUR) that no call may ever reach.
--
-- ASSERTS. All four RPCs return JOD for P1 and ILS for P2; an ORG-WIDE call
-- keeps the org default; no sibling restaurant's money crosses over; the
-- signatures, overload count, wrapper behaviour and ACL posture are unchanged.
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(31);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000053a0000', 'Org P5A', 'p5a-a', 'ILS'),
  ('00000000-0000-0000-0000-0000053b0000', 'Org P5B', 'p5a-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone, currency_override) values
  ('00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a0000', 'Rest P1', 'UTC', 'JOD'),
  ('00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a0000', 'Rest P2', 'UTC', null),
  ('00000000-0000-0000-0000-0000053b1000', '00000000-0000-0000-0000-0000053b0000', 'Rest P3', 'UTC', null);
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', 'Branch P1a', null),
  ('00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', 'Branch P2a', null),
  ('00000000-0000-0000-0000-0000053b1a00', '00000000-0000-0000-0000-0000053b0000', '00000000-0000-0000-0000-0000053b1000', 'Branch P3a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-000005300d01', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', 'pos'),
  ('00000000-0000-0000-0000-000005300d02', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000005300c01', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-000005300d01', 'active'),
  ('00000000-0000-0000-0000-000005300c02', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-000005300d02', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-000005300e01', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-000005300d01', '00000000-0000-0000-0000-000005300c01'),
  ('00000000-0000-0000-0000-000005300e02', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-000005300d02', '00000000-0000-0000-0000-000005300c02');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000005300f01', 'p5a-owner@example.test'),
  ('00000000-0000-0000-0000-000005300f03', 'p5a-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000053a0001', '00000000-0000-0000-0000-000005300f01', '00000000-0000-0000-0000-0000053a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000053a0003', '00000000-0000-0000-0000-000005300f03', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0000', null, null, '00000000-0000-0000-0000-000005300f01', '00000000-0000-0000-0000-0000053a0001', 'Owner P5A');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000053b0001', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-000005300e01', '00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000053b0002', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-000005300e02', '00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0001', now() + interval '1 hour');

-- 47400 minor units is the Phase-5 repro amount: JOD 47.400 vs a 2-decimal
-- reading of the same integer.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000531d001', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-000005300d01', '00000000-0000-0000-0000-0000053b0001', '00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0001', 'dine_in', 'completed', 'JOD', 47400, 0, 0, 47400, 'P1 today', 'p5a-o1', (current_date + interval '9 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000531d002', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-000005300d02', '00000000-0000-0000-0000-0000053b0002', '00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0001', 'takeaway', 'completed', 'ILS', 1500, 0, 0, 1500, 'P2 today', 'p5a-o2', (current_date + interval '9 hours') at time zone 'UTC');

insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('00000000-0000-0000-0000-00000531e001', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-00000531d001', '00000000-0000-0000-0000-0000053e1001', 1, 'Shawarma', 47400, 47400),
  ('00000000-0000-0000-0000-00000531e002', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-00000531d002', '00000000-0000-0000-0000-0000053e1002', 1, 'Falafel', 1500, 1500);

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000531f001', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a1000', '00000000-0000-0000-0000-0000053a1a00', '00000000-0000-0000-0000-00000531d001', '00000000-0000-0000-0000-000005300d01', '00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0001', 'cash', 'completed', 47400, 47400, 0, 'JOD', 'p5a-p1', (current_date + interval '9 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000531f002', '00000000-0000-0000-0000-0000053a0000', '00000000-0000-0000-0000-0000053a2000', '00000000-0000-0000-0000-0000053a2a00', '00000000-0000-0000-0000-00000531d002', '00000000-0000-0000-0000-000005300d02', '00000000-0000-0000-0000-0000053e0f01', '00000000-0000-0000-0000-0000053a0001', 'cash', 'completed', 1500, 1500, 0, 'ILS', 'p5a-p2', (current_date + interval '9 hours') at time zone 'UTC');

set local app.current_app_user_id = '00000000-0000-0000-0000-000005300f01';

-- ===== 1. THE FIX: all four advertise the restaurant's operating currency ====
select is(
  (select app.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today')->>'currency_code'),
  'JOD', 'owner_report_range: the RESTAURANT override, not the org default');

select is(
  (select app.owner_top_items('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today')->>'currency_code'),
  'JOD', 'owner_top_items: the RESTAURANT override, not the org default');

select is(
  (select app.owner_sales_series('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'last7')->>'currency_code'),
  'JOD', 'owner_sales_series: the RESTAURANT override, not the org default');

select is(
  (select app.owner_daily_report('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null)->>'currency_code'),
  'JOD', 'owner_daily_report: the RESTAURANT override, not the org default');

-- ===== 2. A sibling with NO override still inherits the org default ==========
select is(
  (select app.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a2000',null,'today')->>'currency_code'),
  'ILS', 'owner_report_range: no override inherits the org default');

select is(
  (select app.owner_top_items('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a2000',null,'today')->>'currency_code'),
  'ILS', 'owner_top_items: no override inherits the org default');

select is(
  (select app.owner_sales_series('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a2000',null,'last7')->>'currency_code'),
  'ILS', 'owner_sales_series: no override inherits the org default');

select is(
  (select app.owner_daily_report('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a2000',null)->>'currency_code'),
  'ILS', 'owner_daily_report: no override inherits the org default');

-- ===== 3. ORG-WIDE keeps the org default (no single override applies) ========
select is(
  (select app.owner_report_range('00000000-0000-0000-0000-0000053a0000',null,null,'today')->>'currency_code'),
  'ILS', 'owner_report_range: an ORG-WIDE call keeps the org default');

select is(
  (select app.owner_top_items('00000000-0000-0000-0000-0000053a0000',null,null,'today')->>'currency_code'),
  'ILS', 'owner_top_items: an ORG-WIDE call keeps the org default');

select is(
  (select app.owner_sales_series('00000000-0000-0000-0000-0000053a0000',null,null,'last7')->>'currency_code'),
  'ILS', 'owner_sales_series: an ORG-WIDE call keeps the org default');

select is(
  (select app.owner_daily_report('00000000-0000-0000-0000-0000053a0000',null,null)->>'currency_code'),
  'ILS', 'owner_daily_report: an ORG-WIDE call keeps the org default');

-- ===== 4. No cross-restaurant leakage =======================================
-- P1 sold 47400 and P2 sold 1500. Each scope must see only its own, or the
-- label would be right and the money still wrong.
select is(
  (select (app.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today')->'current'->>'gross_minor')::bigint),
  47400::bigint, 'scope P1: only P1 money');

select is(
  (select (app.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a2000',null,'today')->'current'->>'gross_minor')::bigint),
  1500::bigint, 'scope P2: only P2 money — the sibling override never leaks its rows either');

select is(
  (select count(*)::int
   from jsonb_array_elements(app.owner_top_items('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today')->'items') i
   where i->>'name' = 'Falafel'),
  0, 'owner_top_items: a sibling restaurant''s item never appears');

-- A different ORGANIZATION is unreachable for this caller.
select throws_ok(
  $$ select app.owner_report_range('00000000-0000-0000-0000-0000053b0000','00000000-0000-0000-0000-0000053b1000',null,'today') $$,
  '42501', null, 'cross-org report is refused');

-- ===== 5. The envelope is still a complete, unchanged payload ================
select ok(
  (select r ? 'ok' and r ? 'currency_code' and r ? 'current' and r ? 'comparison'
          and r ? 'hourly' and r ? 'shift_cash' and r ? 'range'
          and r ? 'range_start' and r ? 'range_end' and r ? 'entity'
          and (r->'current') ? 'gross_minor' and (r->'current') ? 'net_minor'
          and (r->'current') ? 'order_count' and (r->'current') ? 'collected_minor'
   from (select app.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today') r) s),
  'owner_report_range: every pre-existing envelope key survives');

select is(
  (select (app.owner_daily_report('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null)->>'ok')::boolean),
  true, 'owner_daily_report: still ok');

select is(
  (select (app.owner_sales_series('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'last7')->>'ok')::boolean),
  true, 'owner_sales_series: still ok');

select is(
  (select (app.owner_top_items('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today')->>'ok')::boolean),
  true, 'owner_top_items: still ok');

-- ===== 6. Signatures, overloads, wrappers and ACLs are unchanged =============
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'owner_report_range'),
  1, 'owner_report_range: exactly ONE app overload');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'owner_top_items'),
  1, 'owner_top_items: exactly ONE app overload');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'owner_sales_series'),
  1, 'owner_sales_series: exactly ONE app overload');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'owner_daily_report'),
  1, 'owner_daily_report: exactly ONE app overload');

select is(
  (select pg_get_function_identity_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'owner_report_range'),
  'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_range text, p_start date, p_end date',
  'owner_report_range: the signature is unchanged');

select is(
  (select pg_get_function_identity_arguments(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname = 'owner_daily_report'),
  'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid',
  'owner_daily_report: the signature is unchanged');

-- The public wrappers still resolve, and still carry the corrected label.
select is(
  (select public.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null,'today')->>'currency_code'),
  'JOD', 'public.owner_report_range: the wrapper carries the effective currency');

select is(
  (select public.owner_daily_report('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000',null)->>'currency_code'),
  'JOD', 'public.owner_daily_report: the wrapper carries the effective currency');

-- ACL posture is NOT widened: anon can reach none of them, authenticated can.
select ok(
  (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app','public')
     and p.proname in ('owner_report_range','owner_top_items','owner_sales_series','owner_daily_report')),
  'anon can execute NONE of the four report RPCs, in either schema');

select ok(
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('app','public')
     and p.proname in ('owner_report_range','owner_top_items','owner_sales_series','owner_daily_report')),
  'authenticated keeps EXECUTE on all four, in both schemas');

-- ===== 7. Role gate still holds =============================================
set local app.current_app_user_id = '00000000-0000-0000-0000-000005300f03';
select is(
  (select app.owner_report_range('00000000-0000-0000-0000-0000053a0000','00000000-0000-0000-0000-0000053a1000','00000000-0000-0000-0000-0000053a1a00','today')->>'error'),
  'permission_denied', 'kitchen_staff is still refused the financial read');

select finish();
rollback;
