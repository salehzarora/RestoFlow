-- ============================================================================
-- RF-055 — pgTAP schema test
-- ============================================================================
-- shifts / cash_drawer_sessions / shift_operations exist with the right states,
-- integer _minor money (no float), the one-active-shift partial unique index, the
-- shift_operations action CHECK, RLS enabled+forced, direct writes revoked, the
-- payments shift/drawer FKs, and the three RPCs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(29);

-- tables exist -------------------------------------------------------------- 1-3
select has_table('public', 'shifts',               'shifts table exists');
select has_table('public', 'cash_drawer_sessions', 'cash_drawer_sessions table exists');
select has_table('public', 'shift_operations',     'shift_operations table exists');

-- key columns --------------------------------------------------------------- 4-5
select has_column('public', 'shifts', 'device_id', 'shifts.device_id exists (A1)');
select col_not_null('public', 'cash_drawer_sessions', 'shift_id', 'cash_drawer_sessions.shift_id NOT NULL (bound 1:1)');

-- money columns are integer bigint _minor ----------------------------------- 6-12
select is((select data_type from information_schema.columns where table_schema='public' and table_name='shifts' and column_name='expected_total_minor'), 'bigint', 'shifts.expected_total_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='shifts' and column_name='counted_total_minor'),  'bigint', 'shifts.counted_total_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='shifts' and column_name='variance_minor'),       'bigint', 'shifts.variance_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='cash_drawer_sessions' and column_name='opening_float_minor'),  'bigint', 'cash_drawer_sessions.opening_float_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='cash_drawer_sessions' and column_name='expected_total_minor'), 'bigint', 'cash_drawer_sessions.expected_total_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='cash_drawer_sessions' and column_name='counted_total_minor'),  'bigint', 'cash_drawer_sessions.counted_total_minor is bigint');
select is((select data_type from information_schema.columns where table_schema='public' and table_name='cash_drawer_sessions' and column_name='variance_minor'),       'bigint', 'cash_drawer_sessions.variance_minor is bigint');

-- NO float/numeric/double/money columns on the new tables (D-007) ----------- 13
select is(
  (select count(*) from information_schema.columns
     where table_schema='public' and table_name in ('shifts','cash_drawer_sessions','shift_operations')
       and data_type in ('numeric','real','double precision','money'))::int, 0,
  'no numeric/real/double/money columns on shifts/cash_drawer_sessions/shift_operations');

-- status CHECKs carry the D-018 state sets ---------------------------------- 14-15
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname='shifts_status_check' and conrelid='public.shifts'::regclass)
    like all (array['%opening%','%open%','%closing%','%closed%','%reconciled%']),
  'shifts.status CHECK carries opening/open/closing/closed/reconciled');
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname='cash_drawer_sessions_status_check' and conrelid='public.cash_drawer_sessions'::regclass)
    like all (array['%opened%','%active%','%counting%','%closed%','%reconciled%']),
  'cash_drawer_sessions.status CHECK carries opened/active/counting/closed/reconciled');

-- shift_operations action CHECK --------------------------------------------- 16
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname='shift_operations_action_check' and conrelid='public.shift_operations'::regclass)
    like all (array['%open_shift%','%close_shift%','%reconcile_shift%']),
  'shift_operations.action CHECK carries open_shift/close_shift/reconcile_shift');

-- one-active-shift partial unique index ------------------------------------- 17
select ok(
  (select indexdef from pg_indexes where schemaname='public' and indexname='shifts_one_active_per_device_uidx') like '%UNIQUE%device_id%',
  'shifts has the one-active-shift-per-(org,branch,device) partial unique index (A1)');

-- RLS enabled + forced ------------------------------------------------------ 18-23
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='shifts'),               'shifts: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='shifts'),               'shifts: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='cash_drawer_sessions'), 'cash_drawer_sessions: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='cash_drawer_sessions'), 'cash_drawer_sessions: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='shift_operations'),     'shift_operations: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='shift_operations'),     'shift_operations: RLS forced');

-- payments shift/drawer FKs added (A3) -------------------------------------- 24-25
select ok(exists(select 1 from pg_constraint where conname='payments_shift_same_org' and conrelid='public.payments'::regclass and contype='f'),
  'payments has the composite same-org FK to shifts (A3)');
select ok(exists(select 1 from pg_constraint where conname='payments_cash_drawer_session_same_org' and conrelid='public.payments'::regclass and contype='f'),
  'payments has the composite same-org FK to cash_drawer_sessions (A3)');

-- the three RPCs exist ------------------------------------------------------ 26-28
select has_function('app', 'open_shift',      'app.open_shift() exists');
select has_function('app', 'close_shift',     'app.close_shift() exists');
select has_function('app', 'reconcile_shift', 'app.reconcile_shift() exists');

-- direct writes to the new tables are denied for authenticated (RPC-only) ---
set local role authenticated;
select throws_ok($$ insert into shifts (organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','x') $$, '42501', NULL, 'authenticated cannot directly INSERT into shifts');
reset role;

select * from finish();
rollback;
