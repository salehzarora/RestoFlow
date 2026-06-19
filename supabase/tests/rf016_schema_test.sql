-- ============================================================================
-- RF-016 — pgTAP schema test
-- ============================================================================
-- Proves the four device/session tables exist and are distinct (D-005 #4/#5/#6
-- + pairing), are tenant+BRANCH scoped (org/restaurant/branch NOT NULL), RLS is
-- enabled+forced, a DEVICE is not a human (no app_user_id/role), there are NO
-- plaintext code/token/PIN columns (only *_ref/_hash), pin_sessions carries a
-- NOT NULL resolved_membership_id (A7), and the two integrity guard functions +
-- triggers exist.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(50);

-- Tables exist + distinct ---------------------------------------------------- 1-4
select has_table('public', 'devices',         'devices table exists');
select has_table('public', 'device_pairings', 'device_pairings table exists');
select has_table('public', 'device_sessions', 'device_sessions table exists');
select has_table('public', 'pin_sessions',    'pin_sessions table exists');

-- uuid PK named id ----------------------------------------------------------- 5-12
select col_is_pk('public', 'devices',         'id', 'devices.id is PK');
select col_is_pk('public', 'device_pairings', 'id', 'device_pairings.id is PK');
select col_is_pk('public', 'device_sessions', 'id', 'device_sessions.id is PK');
select col_is_pk('public', 'pin_sessions',    'id', 'pin_sessions.id is PK');
select col_type_is('public', 'devices',         'id', 'uuid', 'devices.id uuid');
select col_type_is('public', 'device_pairings', 'id', 'uuid', 'device_pairings.id uuid');
select col_type_is('public', 'device_sessions', 'id', 'uuid', 'device_sessions.id uuid');
select col_type_is('public', 'pin_sessions',    'id', 'uuid', 'pin_sessions.id uuid');

-- tenant/branch scope columns NOT NULL on every table (D-001/D-002, A3) ------ 13-24
select col_not_null('public', 'devices',         'organization_id', 'devices.organization_id NOT NULL');
select col_not_null('public', 'devices',         'restaurant_id',   'devices.restaurant_id NOT NULL');
select col_not_null('public', 'devices',         'branch_id',       'devices.branch_id NOT NULL');
select col_not_null('public', 'device_pairings', 'organization_id', 'device_pairings.organization_id NOT NULL');
select col_not_null('public', 'device_pairings', 'restaurant_id',   'device_pairings.restaurant_id NOT NULL');
select col_not_null('public', 'device_pairings', 'branch_id',       'device_pairings.branch_id NOT NULL');
select col_not_null('public', 'device_sessions', 'organization_id', 'device_sessions.organization_id NOT NULL');
select col_not_null('public', 'device_sessions', 'restaurant_id',   'device_sessions.restaurant_id NOT NULL');
select col_not_null('public', 'device_sessions', 'branch_id',       'device_sessions.branch_id NOT NULL');
select col_not_null('public', 'pin_sessions',    'organization_id', 'pin_sessions.organization_id NOT NULL');
select col_not_null('public', 'pin_sessions',    'restaurant_id',   'pin_sessions.restaurant_id NOT NULL');
select col_not_null('public', 'pin_sessions',    'branch_id',       'pin_sessions.branch_id NOT NULL');

-- RLS enabled + forced on every table ---------------------------------------- 25-32
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='devices'),         'devices: RLS enabled');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='device_pairings'), 'device_pairings: RLS enabled');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='device_sessions'), 'device_sessions: RLS enabled');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='pin_sessions'),    'pin_sessions: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='devices'),         'devices: RLS forced');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='device_pairings'), 'device_pairings: RLS forced');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='device_sessions'), 'device_sessions: RLS forced');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='pin_sessions'),    'pin_sessions: RLS forced');

-- devices is a NON-human identity: no app_user_id / role / membership / PIN --- 33-37
select hasnt_column('public', 'devices', 'app_user_id',   'devices has NO app_user_id (device is not a human)');
select hasnt_column('public', 'devices', 'role',          'devices has NO human role column');
select hasnt_column('public', 'devices', 'membership_id', 'devices has NO membership column');
select hasnt_column('public', 'devices', 'pin',           'devices has NO pin column');
select has_column('public', 'devices', 'device_credential_ref', 'devices.device_credential_ref (reference/hash only) exists');

-- no plaintext code/token columns — only *_hash / *_ref ---------------------- 38-45
select has_column('public', 'device_pairings', 'enrollment_code_hash', 'device_pairings.enrollment_code_hash exists (hash/ref)');
select hasnt_column('public', 'device_pairings', 'enrollment_code',     'device_pairings has NO plaintext enrollment_code column');
select has_column('public', 'device_pairings', 'status',                'device_pairings.status exists');
select has_column('public', 'device_sessions', 'session_token_ref',     'device_sessions.session_token_ref exists (hash/ref)');
select hasnt_column('public', 'device_sessions', 'session_token',       'device_sessions has NO plaintext session_token column');
select hasnt_column('public', 'pin_sessions', 'pin',                    'pin_sessions has NO pin column');
select hasnt_column('public', 'pin_sessions', 'pin_hash',               'pin_sessions has NO pin_hash column');
select hasnt_column('public', 'pin_sessions', 'pin_credential_ref',     'pin_sessions stores NO PIN material (lives on employee_profiles)');

-- pin_sessions.resolved_membership_id NOT NULL (A7) -------------------------- 46
select col_not_null('public', 'pin_sessions', 'resolved_membership_id', 'pin_sessions.resolved_membership_id is NOT NULL (A7)');

-- integrity guard functions + triggers exist -------------------------------- 47-50
select has_function('app', 'enforce_pairing_code_expiry', 'app.enforce_pairing_code_expiry() exists');
select has_function('app', 'enforce_pin_session_backing', 'app.enforce_pin_session_backing() exists');
select has_trigger('public', 'device_pairings', 'device_pairings_enforce_code_expiry', 'expiry guard trigger attached to device_pairings');
select has_trigger('public', 'pin_sessions',    'pin_sessions_enforce_backing',        'backing guard trigger attached to pin_sessions');

select * from finish();
rollback;
