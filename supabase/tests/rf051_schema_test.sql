-- ============================================================================
-- RF-051 — pgTAP schema test
-- ============================================================================
-- Proves the RF-051 surface exists: pin_attempt_states (tenant/branch scoped,
-- unique per employee+device, lockout columns, NO plaintext PIN), the helper /
-- guard / RPC functions, the lockout trigger, the pin_sessions idempotency
-- column, and the centralized ASSUMPTION/Q-009 interim constants.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(28);

-- table + scoped columns ----------------------------------------------------- 1-6
select has_table('public', 'pin_attempt_states', 'pin_attempt_states table exists');
select col_not_null('public', 'pin_attempt_states', 'organization_id', 'pin_attempt_states.organization_id NOT NULL');
select col_not_null('public', 'pin_attempt_states', 'restaurant_id',   'pin_attempt_states.restaurant_id NOT NULL');
select col_not_null('public', 'pin_attempt_states', 'branch_id',       'pin_attempt_states.branch_id NOT NULL');
select col_not_null('public', 'pin_attempt_states', 'employee_profile_id', 'pin_attempt_states.employee_profile_id NOT NULL');
select col_not_null('public', 'pin_attempt_states', 'device_id',       'pin_attempt_states.device_id NOT NULL');

-- lockout columns ------------------------------------------------------------ 7-10
select has_column('public', 'pin_attempt_states', 'failed_attempt_count', 'failed_attempt_count column exists');
select has_column('public', 'pin_attempt_states', 'locked_until',         'locked_until column exists');
select has_column('public', 'pin_attempt_states', 'last_failed_at',       'last_failed_at column exists');
select has_column('public', 'pin_attempt_states', 'last_attempt_at',      'last_attempt_at column exists');

-- unique per (org, employee, device) ----------------------------------------- 11
select ok(
  exists (
    select 1
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'pin_attempt_states' and con.contype = 'u'
      and con.conkey @> array[
        (select attnum from pg_attribute where attrelid = c.oid and attname = 'organization_id'),
        (select attnum from pg_attribute where attrelid = c.oid and attname = 'employee_profile_id'),
        (select attnum from pg_attribute where attrelid = c.oid and attname = 'device_id')
      ]::int2[]
  ),
  'pin_attempt_states has a UNIQUE constraint covering (organization_id, employee_profile_id, device_id)');

-- RLS enabled + forced ------------------------------------------------------- 12-13
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='pin_attempt_states'), 'pin_attempt_states: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='pin_attempt_states'), 'pin_attempt_states: RLS forced');

-- no plaintext PIN material -------------------------------------------------- 14-16
select hasnt_column('public', 'pin_attempt_states', 'pin',                'pin_attempt_states has NO pin column');
select hasnt_column('public', 'pin_attempt_states', 'pin_hash',           'pin_attempt_states has NO pin_hash column');
select hasnt_column('public', 'pin_attempt_states', 'pin_credential_ref', 'pin_attempt_states stores NO PIN material');

-- helper / guard / RPC functions exist --------------------------------------- 17-23
select has_function('app', 'start_pin_session',          'app.start_pin_session() exists');
select has_function('app', 'verify_pin_credential',      'app.verify_pin_credential() exists (interim seam)');
select has_function('app', 'enforce_pin_not_locked',     'app.enforce_pin_not_locked() exists (lockout guard)');
select has_function('app', 'is_pin_session_valid',       'app.is_pin_session_valid() exists (offline mechanism)');
select has_function('app', 'pin_max_failed_attempts',    'app.pin_max_failed_attempts() exists (centralized constant)');
select has_function('app', 'pin_lockout_duration',       'app.pin_lockout_duration() exists (centralized constant)');
select has_function('app', 'pin_session_offline_window', 'app.pin_session_offline_window() exists (centralized constant)');

-- lockout trigger + idempotency column --------------------------------------- 24-25
select has_trigger('public', 'pin_sessions', 'pin_sessions_enforce_not_locked', 'lockout guard trigger attached to pin_sessions');
select has_column('public', 'pin_sessions', 'local_operation_id', 'pin_sessions.local_operation_id exists (idempotency, D-022)');

-- centralized interim constants carry the approved ASSUMPTION/Q-009 values ---- 26-28
select is(app.pin_max_failed_attempts(),    5,                    'max failed attempts = 5 (ASSUMPTION / Q-009)');
select is(app.pin_lockout_duration(),       interval '15 minutes', 'lockout duration = 15 min (ASSUMPTION / Q-009)');
select is(app.pin_session_offline_window(), interval '8 hours',    'offline window = 8 h (ASSUMPTION / Q-009)');

select * from finish();
rollback;
