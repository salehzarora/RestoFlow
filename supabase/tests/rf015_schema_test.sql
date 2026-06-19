-- ============================================================================
-- RF-015 — pgTAP schema test
-- ============================================================================
-- Proves the identity tables exist and the six identity concepts are kept
-- distinct (DECISION D-005): app_users (global principal), memberships (scoped
-- relationship), employee_profiles (employment record) are SEPARATE tables, and
-- platform_admin_grants is a SEPARATE platform-plane table with NO tenant
-- columns (DECISION D-026). Also asserts app_users has NO global role column
-- (DECISION D-004) and RLS is enabled+forced on all four (DECISION D-012 L1).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(37);

-- The four identity tables exist and are distinct (D-005) ------------------ 1-4
select has_table('public', 'app_users',             'app_users table exists');
select has_table('public', 'memberships',           'memberships table exists');
select has_table('public', 'employee_profiles',     'employee_profiles table exists');
select has_table('public', 'platform_admin_grants', 'platform_admin_grants table exists');

-- uuid primary key named id on each (D-017) -------------------------------- 5-8
select col_is_pk('public', 'app_users',             'id', 'app_users.id is the primary key');
select col_is_pk('public', 'memberships',           'id', 'memberships.id is the primary key');
select col_is_pk('public', 'employee_profiles',     'id', 'employee_profiles.id is the primary key');
select col_is_pk('public', 'platform_admin_grants', 'id', 'platform_admin_grants.id is the primary key');

-- app_users: global principal — NOT tenant-scoped, NO global role (D-004) -- 9-12
select hasnt_column('public', 'app_users', 'organization_id', 'app_users has NO organization_id (global, not tenant-scoped)');
select hasnt_column('public', 'app_users', 'role',            'app_users has NO global role column (roles are membership-scoped — D-004)');
select has_column('public', 'app_users', 'email',     'app_users.email exists');
select has_column('public', 'app_users', 'is_active', 'app_users.is_active exists');

-- memberships: scoped relationship with role + optional restaurant/branch -- 13-19
select has_column('public', 'memberships', 'app_user_id',     'memberships.app_user_id exists');
select has_column('public', 'memberships', 'organization_id', 'memberships.organization_id exists');
select has_column('public', 'memberships', 'restaurant_id',   'memberships.restaurant_id exists (optional scope)');
select has_column('public', 'memberships', 'branch_id',       'memberships.branch_id exists (optional scope)');
select has_column('public', 'memberships', 'role',            'memberships.role exists');
select col_not_null('public', 'memberships', 'organization_id', 'memberships.organization_id is NOT NULL (D-001)');
select col_not_null('public', 'memberships', 'app_user_id',     'memberships.app_user_id is NOT NULL');

-- employee_profiles: distinct, links to app_user + membership ------------- 20-23
select has_column('public', 'employee_profiles', 'organization_id', 'employee_profiles.organization_id exists');
select has_column('public', 'employee_profiles', 'app_user_id',     'employee_profiles.app_user_id exists (optional link)');
select has_column('public', 'employee_profiles', 'membership_id',   'employee_profiles.membership_id exists (authoritative role+scope link)');
select col_not_null('public', 'employee_profiles', 'organization_id', 'employee_profiles.organization_id is NOT NULL (D-001)');

-- platform_admin_grants: separate platform plane, NO tenant columns (D-026) 24-27
select hasnt_column('public', 'platform_admin_grants', 'organization_id', 'platform_admin_grants has NO organization_id (D-026)');
select hasnt_column('public', 'platform_admin_grants', 'restaurant_id',   'platform_admin_grants has NO restaurant_id (D-026)');
select hasnt_column('public', 'platform_admin_grants', 'branch_id',       'platform_admin_grants has NO branch_id (D-026)');
select has_column('public', 'platform_admin_grants', 'app_user_id',       'platform_admin_grants.app_user_id exists');

-- RLS enabled AND forced on every identity table (D-012 L1) --------------- 28-35
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'app_users'),             'app_users: RLS enabled');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'memberships'),           'memberships: RLS enabled');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'employee_profiles'),     'employee_profiles: RLS enabled');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_admin_grants'), 'platform_admin_grants: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'app_users'),             'app_users: RLS forced');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'memberships'),           'memberships: RLS forced');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'employee_profiles'),     'employee_profiles: RLS forced');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'platform_admin_grants'), 'platform_admin_grants: RLS forced');

-- Interim membership-context helpers exist (RF-015) ----------------------- 36-37
select has_function('app', 'current_app_user_id', 'app.current_app_user_id() exists');
select has_function('app', 'has_scope',           'app.has_scope() exists');

select * from finish();
rollback;
