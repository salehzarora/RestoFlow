-- ============================================================================
-- RF-017 — pgTAP schema test
-- ============================================================================
-- Proves the audit_events shape: uuid PK; the exact DOMAIN_MODEL §10.2 columns;
-- required NOT NULLs; jsonb old/new_values; NO updated_at / deleted_at /
-- device_session_id / pin_session_id / membership_id; RLS enabled+forced; the
-- append-only trigger + its function exist; and least-privilege grants
-- (authenticated SELECT only — no INSERT/UPDATE/DELETE).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(39);

-- table + uuid PK ------------------------------------------------------------ 1-3
select has_table('public', 'audit_events', 'audit_events table exists');
select col_is_pk('public', 'audit_events', 'id', 'audit_events.id is PK');
select col_type_is('public', 'audit_events', 'id', 'uuid', 'audit_events.id is uuid');

-- expected columns exist (DOMAIN_MODEL §10.2) -------------------------------- 4-15
select has_column('public', 'audit_events', 'organization_id',           'organization_id exists');
select has_column('public', 'audit_events', 'restaurant_id',             'restaurant_id exists');
select has_column('public', 'audit_events', 'branch_id',                 'branch_id exists');
select has_column('public', 'audit_events', 'actor_app_user_id',         'actor_app_user_id exists');
select has_column('public', 'audit_events', 'actor_employee_profile_id', 'actor_employee_profile_id exists');
select has_column('public', 'audit_events', 'device_id',                 'device_id exists');
select has_column('public', 'audit_events', 'action',                    'action exists');
select has_column('public', 'audit_events', 'reason',                    'reason exists');
select has_column('public', 'audit_events', 'old_values',                'old_values exists');
select has_column('public', 'audit_events', 'new_values',                'new_values exists');
select has_column('public', 'audit_events', 'occurred_at',               'occurred_at exists');
select has_column('public', 'audit_events', 'created_at',                'created_at exists');

-- required NOT NULL fields --------------------------------------------------- 16-19
select col_not_null('public', 'audit_events', 'organization_id', 'organization_id NOT NULL');
select col_not_null('public', 'audit_events', 'action',          'action NOT NULL');
select col_not_null('public', 'audit_events', 'occurred_at',     'occurred_at NOT NULL');
select col_not_null('public', 'audit_events', 'created_at',      'created_at NOT NULL');

-- old/new values are jsonb --------------------------------------------------- 20-21
select col_type_is('public', 'audit_events', 'old_values', 'jsonb', 'old_values is jsonb');
select col_type_is('public', 'audit_events', 'new_values', 'jsonb', 'new_values is jsonb');

-- forbidden columns absent --------------------------------------------------- 22-26
select hasnt_column('public', 'audit_events', 'updated_at',        'NO updated_at (audit is never updated)');
select hasnt_column('public', 'audit_events', 'deleted_at',        'NO deleted_at (audit is permanent, never soft-deleted)');
select hasnt_column('public', 'audit_events', 'device_session_id', 'NO device_session_id (not in DOMAIN_MODEL §10.2)');
select hasnt_column('public', 'audit_events', 'pin_session_id',    'NO pin_session_id (not in DOMAIN_MODEL §10.2)');
select hasnt_column('public', 'audit_events', 'membership_id',     'NO membership_id (not in DOMAIN_MODEL §10.2)');

-- RLS enabled + forced ------------------------------------------------------- 27-28
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='audit_events'), 'audit_events: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname='public' and c.relname='audit_events'), 'audit_events: RLS forced');

-- append-only trigger + function exist --------------------------------------- 29-30
select has_trigger('public', 'audit_events', 'audit_events_append_only', 'append-only trigger attached to audit_events');
select has_function('app', 'enforce_audit_append_only', 'app.enforce_audit_append_only() exists');

-- least-privilege grants: authenticated SELECT only -------------------------- 31-34
select ok(has_table_privilege('authenticated', 'public.audit_events', 'SELECT'),      'authenticated HAS SELECT on audit_events');
select ok(not has_table_privilege('authenticated', 'public.audit_events', 'INSERT'),  'authenticated has NO INSERT on audit_events');
select ok(not has_table_privilege('authenticated', 'public.audit_events', 'UPDATE'),  'authenticated has NO UPDATE on audit_events');
select ok(not has_table_privilege('authenticated', 'public.audit_events', 'DELETE'),  'authenticated has NO DELETE on audit_events');

-- anon has NO access at all (mirrors the RF-014 grant-level guard; FORCE RLS would
-- otherwise mask a mistaken grant by returning zero rows instead of erroring) ---- 35
select ok(not has_table_privilege('anon', 'public.audit_events', 'SELECT'), 'anon has NO SELECT on audit_events');

-- the SELECT-only RLS policy exists and is exactly that (catches widening to FOR ALL) 36-37
select policies_are('public', 'audit_events', array['audit_events_select'], 'audit_events has exactly the one (SELECT-only) policy');
select policy_cmd_is('public', 'audit_events', 'audit_events_select', 'SELECT', 'audit_events_select is a SELECT-only policy');

-- the append-only trigger function is a NORMAL INVOKER (Codex-required), search_path-locked 38-39
select ok((select not p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'enforce_audit_append_only'),
          'enforce_audit_append_only is NOT security definer (normal invoker)');
select ok((select exists (
             select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
             cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
             where n.nspname = 'app' and p.proname = 'enforce_audit_append_only'
               and cfg like 'search_path=%')),
          'enforce_audit_append_only has a locked search_path');

select * from finish();
rollback;
