-- ============================================================================
-- OPS-043 Phase 2 — pgTAP: per-row currency on the order LIST reads, the
-- effective (override-aware) envelope currency, and the per-currency report
-- breakdown.
--
-- FIXTURE. One organization whose default currency is ILS, with TWO restaurants:
--   * Rest A1 carries currency_override = 'USD' — the Phase-1 Operating currency
--     an owner can now set;
--   * Rest A2 carries NO override, so it inherits ILS.
-- Rest A1 holds an OLD order stored in ILS (taken before the switch) and a NEW
-- order stored in USD, both completed and paid. That single fixture is what
-- makes the historical-relabelling question answerable at all: if the server
-- emitted only one currency per payload, those two orders would be
-- indistinguishable to any client.
--
-- ASSERTS. history rows carry their OWN currency_code; the active board does
-- too; the envelope now coalesces the restaurant override (and still falls back
-- to the org default org-wide); the breakdown groups money by currency and never
-- merges two currencies into one figure; date validation; kitchen_staff denied;
-- cross-org 42501; the public wrapper is INVOKER, locked to authenticated, and
-- unreachable by anon.
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(24);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000043a0000', 'Org C43', 'c43-a', 'ILS'),
  ('00000000-0000-0000-0000-0000043b0000', 'Org D43', 'c43-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone, currency_override) values
  ('00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a0000', 'Rest A1', 'UTC', 'USD'),
  ('00000000-0000-0000-0000-0000043a2000', '00000000-0000-0000-0000-0000043a0000', 'Rest A2', 'UTC', null),
  ('00000000-0000-0000-0000-0000043b1000', '00000000-0000-0000-0000-0000043b0000', 'Rest B1', 'UTC', null);
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', 'Branch A1a', null),
  ('00000000-0000-0000-0000-0000043a2a00', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a2000', 'Branch A2a', null),
  ('00000000-0000-0000-0000-0000043b1a00', '00000000-0000-0000-0000-0000043b0000', '00000000-0000-0000-0000-0000043b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', 'pos'),
  ('00000000-0000-0000-0000-000004300d02', '00000000-0000-0000-0000-0000043b0000', '00000000-0000-0000-0000-0000043b1000', '00000000-0000-0000-0000-0000043b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000004300c01', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-000004300d01', 'active'),
  ('00000000-0000-0000-0000-000004300c02', '00000000-0000-0000-0000-0000043b0000', '00000000-0000-0000-0000-0000043b1000', '00000000-0000-0000-0000-0000043b1a00', '00000000-0000-0000-0000-000004300d02', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-000004300e01', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-000004300c01'),
  ('00000000-0000-0000-0000-000004300e02', '00000000-0000-0000-0000-0000043b0000', '00000000-0000-0000-0000-0000043b1000', '00000000-0000-0000-0000-0000043b1a00', '00000000-0000-0000-0000-000004300d02', '00000000-0000-0000-0000-000004300c02');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000004300f01', 'c43-owner@example.test'),
  ('00000000-0000-0000-0000-000004300f03', 'c43-kitchen@example.test'),
  ('00000000-0000-0000-0000-000004300f05', 'c43-orgd-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000043a0001', '00000000-0000-0000-0000-000004300f01', '00000000-0000-0000-0000-0000043a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000043a0003', '00000000-0000-0000-0000-000004300f03', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000043a0005', '00000000-0000-0000-0000-000004300f05', '00000000-0000-0000-0000-0000043b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0000', null, null, '00000000-0000-0000-0000-000004300f01', '00000000-0000-0000-0000-0000043a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000043e0f05', '00000000-0000-0000-0000-0000043b0000', null, null, '00000000-0000-0000-0000-000004300f05', '00000000-0000-0000-0000-0000043a0005', 'Bianca O.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000043b0001', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-000004300e01', '00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000043b0005', '00000000-0000-0000-0000-0000043b0000', '00000000-0000-0000-0000-0000043b1000', '00000000-0000-0000-0000-0000043b1a00', '00000000-0000-0000-0000-000004300e02', '00000000-0000-0000-0000-0000043e0f05', '00000000-0000-0000-0000-0000043a0005', now() + interval '1 hour');

-- THE HISTORICAL PAIR on ONE restaurant: an OLD order stored in ILS and a NEW
-- order stored in USD after the operating currency was switched. Both today, so
-- both land in every default window.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000431d001', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-0000043b0001', '00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0001', 'dine_in',  'completed', 'ILS', 1000, 0, 0, 1000, 'Old ILS', 'c43-o1', (current_date + interval '9 hours')  at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000431d002', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-0000043b0001', '00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0001', 'takeaway', 'completed', 'USD',  700, 0, 0,  700, 'New USD', 'c43-o2', (current_date + interval '10 hours') at time zone 'UTC'),
  -- still OPEN, so it appears on the active board (and in the safety gate).
  ('00000000-0000-0000-0000-00000431d003', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-0000043b0001', '00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0001', 'dine_in',  'submitted', 'ILS',  400, 0, 0,  400, 'Open ILS', 'c43-o3', (current_date + interval '11 hours') at time zone 'UTC');

insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('00000000-0000-0000-0000-00000431e001', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-00000431d001', '00000000-0000-0000-0000-0000043e1001', 1, 'Burger', 1000, 1000),
  ('00000000-0000-0000-0000-00000431e002', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-00000431d002', '00000000-0000-0000-0000-0000043e1002', 1, 'Wrap',    700,  700),
  ('00000000-0000-0000-0000-00000431e003', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-00000431d003', '00000000-0000-0000-0000-0000043e1003', 1, 'Salad',   400,  400);

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000431f001', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-00000431d001', '00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0001', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'c43-p1', (current_date + interval '9 hours')  at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000431f002', '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', '00000000-0000-0000-0000-0000043a1a00', '00000000-0000-0000-0000-00000431d002', '00000000-0000-0000-0000-000004300d01', '00000000-0000-0000-0000-0000043e0f01', '00000000-0000-0000-0000-0000043a0001', 'card', 'completed',  700, 700, 0, 'USD', 'c43-p2', (current_date + interval '10 hours') at time zone 'UTC');

set local app.current_app_user_id = '00000000-0000-0000-0000-000004300f01';

-- ===== 1. ORDER HISTORY: rows carry their OWN currency =======================
select is(
  (select (r->>'ok')::boolean from public.owner_order_history(
     '00000000-0000-0000-0000-0000043a0000', '00000000-0000-0000-0000-0000043a1000', null, 'today') r),
  true, 'history: ok');

select is(
  (select o->>'currency_code'
   from public.owner_order_history('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r,
        jsonb_array_elements(r->'orders') o
   where o->>'customer_name' = 'Old ILS'),
  'ILS', 'history: the OLD order keeps ILS even though the restaurant now operates in USD');

select is(
  (select o->>'currency_code'
   from public.owner_order_history('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r,
        jsonb_array_elements(r->'orders') o
   where o->>'customer_name' = 'New USD'),
  'USD', 'history: the NEW order reports USD');

select is(
  (select count(distinct o->>'currency_code')::int
   from public.owner_order_history('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r,
        jsonb_array_elements(r->'orders') o),
  2, 'history: two currencies are DISTINGUISHABLE in one payload');

select is(
  (select count(*)::int
   from public.owner_order_history('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r,
        jsonb_array_elements(r->'orders') o
   where o->'currency_code' is null),
  0, 'history: every row carries a currency_code');

select is(
  (select r->>'currency_code' from public.owner_order_history(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r),
  'USD', 'history: the envelope uses the RESTAURANT override, not the org default');

select is(
  (select r->>'currency_code' from public.owner_order_history(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a2000',null,'today') r),
  'ILS', 'history: a restaurant with no override inherits the org default');

select is(
  (select r->>'currency_code' from public.owner_order_history(
     '00000000-0000-0000-0000-0000043a0000', null, null, 'today') r),
  'ILS', 'history: an ORG-WIDE call keeps the org default (no single override applies)');

-- Existing envelope keys still present and unchanged in meaning.
select ok(
  (select r ? 'orders' and r ? 'has_more' and r ? 'next_cursor' and r ? 'count'
          and r ? 'range' and r ? 'limit' and r ? 'entity'
   from public.owner_order_history('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r),
  'history: every pre-existing envelope key survives (backward compatible)');

select is(
  (select (o->>'grand_total_minor')::bigint
   from public.owner_order_history('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null,'today') r,
        jsonb_array_elements(r->'orders') o
   where o->>'customer_name' = 'Old ILS'),
  1000::bigint, 'history: NO conversion — the stored minor amount is untouched');

-- ===== 2. ACTIVE BOARD: rows carry their OWN currency ========================
select is(
  (select o->>'currency_code'
   from public.owner_active_orders('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null) r,
        jsonb_array_elements(r->'orders') o
   where o->>'customer_name' = 'Open ILS'),
  'ILS', 'active board: the open ILS order reports ILS under a USD restaurant');

select is(
  (select r->>'currency_code' from public.owner_active_orders(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null) r),
  'USD', 'active board: the envelope uses the restaurant override');

select ok(
  (select r ? 'orders' and r ? 'summary' and r ? 'queue' and r ? 'sort'
          and r ? 'matching' and r ? 'has_more' and r ? 'next_cursor'
   from public.owner_active_orders('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null) r),
  'active board: pre-existing envelope keys survive');

-- ===== 3. THE PER-CURRENCY BREAKDOWN ========================================
-- REPORT-123: from here the suite executes AS THE AUTHENTICATED ROLE, not as
-- superuser. The public wrapper is SECURITY INVOKER, so only a real-role call
-- exercises the EXECUTE grant on the inner app.* implementation -- the grant
-- whose absence produced 42501 in production while this suite stayed green.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000004300f01';

select is(
  (select (r->>'ok')::boolean from public.owner_report_currency_breakdown(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) r),
  true, 'breakdown: ok');

select is(
  (select jsonb_array_length(r->'by_currency') from public.owner_report_currency_breakdown(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) r),
  2, 'breakdown: one entry per currency present in the window');

select is(
  (select (c->>'net_minor')::bigint
   from public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) r,
        jsonb_array_elements(r->'by_currency') c
   where c->>'currency_code' = 'ILS'),
  1400::bigint, 'breakdown: ILS net is the ILS orders only (1000 + 400), never mixed with USD');

select is(
  (select (c->>'net_minor')::bigint
   from public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) r,
        jsonb_array_elements(r->'by_currency') c
   where c->>'currency_code' = 'USD'),
  700::bigint, 'breakdown: USD net is the USD order only');

select is(
  (select (c->>'collected_minor')::bigint
   from public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) r,
        jsonb_array_elements(r->'by_currency') c
   where c->>'currency_code' = 'ILS'),
  1000::bigint, 'breakdown: collected follows the PAYMENT row currency');

select is(
  (select (c->>'cash_minor')::bigint
   from public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) r,
        jsonb_array_elements(r->'by_currency') c
   where c->>'currency_code' = 'USD'),
  0::bigint, 'breakdown: the USD payment was card, so USD cash is zero');

select is(
  (select jsonb_array_length(r->'by_currency') from public.owner_report_currency_breakdown(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a2000',null, current_date, current_date) r),
  0, 'breakdown: a restaurant with no orders in the window returns an empty array, not a fabricated zero row');

-- ===== 4. GUARDS ============================================================
select throws_ok(
  $$ select public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, null, null) $$,
  '42501', null, 'breakdown: a missing date window is refused');

select throws_ok(
  $$ select public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date - 1) $$,
  '42501', null, 'breakdown: an inverted window is refused');

-- kitchen_staff is pinned to (Rest A1, Branch A1a), so the call must name that
-- exact scope to get PAST the coverage check and reach the financial-read
-- allowlist — which is the gate under test. A wider scope would be refused a
-- step earlier, for a different reason, and would prove nothing about roles.
set local app.current_app_user_id = '00000000-0000-0000-0000-000004300f03';
select is(
  (select r->>'error' from public.owner_report_currency_breakdown(
     '00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',
     '00000000-0000-0000-0000-0000043a1a00', current_date, current_date) r),
  'permission_denied', 'breakdown: kitchen_staff is denied by the financial-read allowlist');

set local app.current_app_user_id = '00000000-0000-0000-0000-000004300f05';
select throws_ok(
  $$ select public.owner_report_currency_breakdown('00000000-0000-0000-0000-0000043a0000','00000000-0000-0000-0000-0000043a1000',null, current_date, current_date) $$,
  '42501', null, 'breakdown: a cross-org caller is refused (RISK R-003)');

reset role;
select finish();
rollback;
