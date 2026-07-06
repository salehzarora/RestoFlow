-- ============================================================================
-- RF-REPORT-003 — pgTAP: app.owner_daily_report TODAY shift / cash reconciliation.
-- Extends RF-REPORT-001/002. Org A (Rest A1 tz=UTC: branches A1a + A1b; Rest A2
-- tz=NULL: branch A2a tz-less) and Org B. Shifts closed TODAY on A1a/A1b with
-- stored RF-055 expected/counted/variance; plus an OPEN shift, a YESTERDAY close,
-- a TZ-LESS close, a DELETED close, and an Org B close (all excluded from Org A's
-- today figures). Asserts: shift_cash counts + aggregates (signed variance),
-- last_closed_shift (latest) + recent ordering, branch/restaurant scope, tz-less/
-- deleted/yesterday exclusion, cross-org isolation, kitchen_staff denied, empty
-- scope -> honest empty, integer-minor shape, public wrapper INVOKER/no-anon.
-- The report READS the stored close columns (expected-cash-only computation is an
-- RF-055 close_shift invariant, tested there). Session pinned to UTC. Hex UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(19);

-- ===== fixture: Org A (Rest A1 tz=UTC + Rest A2 tz=NULL) and Org B ============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'ods-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'ods-b', 'EUR');
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
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'ods-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'ods-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'ods-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
-- employee_profiles WITH display_name (closed_by_name source).
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Bianca O.');

-- ---- shifts (report reads stored expected/counted/variance directly) --------
-- S1 A1a CLOSED today @10:00 exp 1500 cnt 1440 var -60; S2 A1a CLOSED today @18:00
-- exp 2000 cnt 2050 var +50 (LATEST -> last_closed); S3 A1b CLOSED today @14:00
-- exp 800 cnt 780 var -20. S4 A1a OPEN now. S5 A1a CLOSED YESTERDAY (excluded).
-- S6 A2a (tz-less) CLOSED today (excluded). S7 A1a CLOSED today but DELETED
-- (excluded). SB1 Org B CLOSED today (isolation).
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, expected_total_minor, counted_total_minor, variance_minor, opened_at, closed_at, local_operation_id) values
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'closed',     1500, 1440, -60, (current_date + interval '8 hours')  at time zone 'UTC', (current_date + interval '10 hours') at time zone 'UTC', 'ods-s1'),
  ('00000000-0000-0000-0000-000000005002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'reconciled', 2000, 2050,  50, (current_date + interval '15 hours') at time zone 'UTC', (current_date + interval '18 hours') at time zone 'UTC', 'ods-s2'),
  ('00000000-0000-0000-0000-000000005003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'closed',      800,  780, -20, (current_date + interval '12 hours') at time zone 'UTC', (current_date + interval '14 hours') at time zone 'UTC', 'ods-s3'),
  ('00000000-0000-0000-0000-000000005004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', null,                       'open',       null, null, null, (current_date + interval '19 hours') at time zone 'UTC', null, 'ods-s4'),
  ('00000000-0000-0000-0000-000000005005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'closed',     9999, 9999,   0, (current_date - 1 + interval '8 hours') at time zone 'UTC', (current_date - 1 + interval '10 hours') at time zone 'UTC', 'ods-s5'),
  ('00000000-0000-0000-0000-000000005006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'closed',     7777, 7777,   0, (current_date + interval '9 hours')  at time zone 'UTC', (current_date + interval '11 hours') at time zone 'UTC', 'ods-s6');
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, expected_total_minor, counted_total_minor, variance_minor, opened_at, closed_at, local_operation_id, deleted_at) values
  ('00000000-0000-0000-0000-000000005007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-0000000e0f01', 'closed',     5555, 5555,   0, (current_date + interval '7 hours') at time zone 'UTC', (current_date + interval '9 hours') at time zone 'UTC', 'ods-s7', now());
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, expected_total_minor, counted_total_minor, variance_minor, opened_at, closed_at, local_operation_id) values
  ('00000000-0000-0000-0000-0000000050b1', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-0000000e0f05', 'closed', 3000, 3000, 0, (current_date + interval '8 hours') at time zone 'UTC', (current_date + interval '12 hours') at time zone 'UTC', 'ods-sb1');

-- ===== (1-8) org_owner org-wide (Org A): shift_cash aggregates ================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_all as select app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', null, null) as res;
reset role;

select is((select (res->>'ok')::boolean from t_all), true, 'org_owner owner_daily_report ok=true');
select is((select (res->'shift_cash'->>'closed_shift_count')::int from t_all), 3,
          'closed_shift_count = 3 today (yesterday/tz-less/deleted/OrgB excluded)');
select is((select (res->'shift_cash'->>'open_shift_count')::int from t_all), 1, 'open_shift_count = 1 (S4)');
select is((select (res->'shift_cash'->>'expected_cash_minor')::bigint from t_all), 4300::bigint,
          'expected_cash_minor = 4300 (1500+2000+800)');
select is((select (res->'shift_cash'->>'counted_cash_minor')::bigint from t_all), 4270::bigint,
          'counted_cash_minor = 4270 (1440+2050+780)');
select is((select (res->'shift_cash'->>'cash_variance_minor')::bigint from t_all), (-30)::bigint,
          'cash_variance_minor = -30 SIGNED (-60+50-20) = counted - expected');
select is(
  (select (res->'shift_cash'->>'cash_variance_minor')::bigint from t_all),
  (select (res->'shift_cash'->>'counted_cash_minor')::bigint
        - (res->'shift_cash'->>'expected_cash_minor')::bigint from t_all),
  'variance = counted - expected (identity)');
select ok((select (res->'shift_cash'->>'expected_cash_minor')::bigint <> (res->'today'->>'gross_minor')::bigint from t_all),
          'shift expected cash is NOT sales gross (distinct reconciliation data)');

-- ===== (9-11) last_closed_shift = latest (S2), with names + amounts ===========
select is((select res->'shift_cash'->'last_closed_shift'->>'shift_id' from t_all),
          '00000000-0000-0000-0000-000000005002', 'last_closed_shift = S2 (latest closed_at today)');
select is((select (res->'shift_cash'->'last_closed_shift'->>'counted_cash_minor')::bigint from t_all), 2050::bigint,
          'last_closed_shift counted_cash_minor = 2050');
select is((select res->'shift_cash'->'last_closed_shift'->>'closed_by_name' from t_all), 'Amira K.',
          'last_closed_shift closed_by_name from employee_profiles.display_name');
select ok(
  (select (res->'shift_cash'->'last_closed_shift'->>'closed_at')
            ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$' from t_all),
  'last_closed_shift closed_at is a branch-local YYYY-MM-DD HH24:MI string (not raw ISO)');

-- ===== (12-13) recent_closed_shifts scoped + ordered newest-first =============
select is((select jsonb_array_length(res->'shift_cash'->'recent_closed_shifts') from t_all), 3,
          'recent_closed_shifts has 3 (today only)');
select is((select res->'shift_cash'->'recent_closed_shifts'->0->>'shift_id' from t_all),
          '00000000-0000-0000-0000-000000005002', 'recent_closed_shifts[0] = S2 (18:00, newest first)');

-- ===== (14) branch A1a scope narrows shift_cash (S3 on A1b excluded) ==========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_branch as select app.owner_daily_report(
  '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00') as res;
reset role;
select ok((select (res->'shift_cash'->>'closed_shift_count')::int = 2
             and (res->'shift_cash'->>'expected_cash_minor')::bigint = 3500
             and (res->'shift_cash'->>'cash_variance_minor')::bigint = -10 from t_branch),
          'branch A1a: closed 2, expected 3500, variance -10 (A1b S3 excluded)');

-- ===== (15) tz-less branch A2a -> honest EMPTY shift_cash =====================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_empty as select app.owner_daily_report(
  '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00') as res;
reset role;
select ok((select (res->'shift_cash'->>'closed_shift_count')::int = 0
             and (res->'shift_cash'->'last_closed_shift') = 'null'::jsonb
             and jsonb_array_length(res->'shift_cash'->'recent_closed_shifts') = 0
             and (res->>'ok')::boolean = true from t_empty),
          'tz-less branch: 0 closed shifts, last_closed_shift null, recent [] (honest empty)');

-- ===== (16) integer-minor shape ==============================================
select ok(
  (select jsonb_typeof(res->'shift_cash'->'expected_cash_minor') = 'number'
      and jsonb_typeof(res->'shift_cash'->'cash_variance_minor') = 'number'
      and jsonb_typeof(res->'shift_cash'->'closed_shift_count') = 'number'
      and jsonb_typeof(res->'shift_cash'->'last_closed_shift'->'counted_cash_minor') = 'number' from t_all),
  'shift_cash money + counts are integer-shaped JSON numbers (no float text)');

-- ===== (17) kitchen_staff is DENIED (no shift_cash) ==========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is(
  (select app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00')->>'error'),
  'permission_denied', 'kitchen_staff cannot read shift_cash (permission_denied)');
reset role;

-- ===== (18) cross-org caller is structurally rejected (42501) =================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_daily_report('00000000-0000-0000-0000-0000000b0000', null, null) $$,
  '42501', NULL, 'an Org A owner cannot read the Org B shift_cash (cross-org 42501)');
reset role;

select * from finish();
rollback;
