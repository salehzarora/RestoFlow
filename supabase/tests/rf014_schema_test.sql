-- ============================================================================
-- RF-014 — pgTAP schema test
-- ============================================================================
-- Verifies the structural acceptance criteria of the first multi-tenant
-- migration: every tenant table has a uuid primary key named `id` (DECISION
-- D-017), every CHILD table has a NOT NULL uuid `organization_id` (the tenant
-- key, DECISION D-001), RLS is ENABLED *and* FORCED on every table (DECISION
-- D-012 layer 1), and the timestamp + soft-delete tombstone columns exist
-- (DECISION D-017 / D-020). Table names assert D-017 snake_case-plural naming.
--
-- Run via `supabase test db`. pgTAP is created inside the transaction and
-- rolled back, so it never enters a migration (kept out of production).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(51);

-- The four tenant tables exist (DECISION D-017: snake_case, plural) --------- 1-4
select has_table('public', 'organizations', 'organizations table exists');
select has_table('public', 'restaurants',   'restaurants table exists');
select has_table('public', 'branches',      'branches table exists');
select has_table('public', 'stations',      'stations table exists');

-- Primary key is a uuid column named `id` (DECISION D-017) ------------------ 5-12
select col_is_pk('public', 'organizations', 'id', 'organizations.id is the primary key');
select col_is_pk('public', 'restaurants',   'id', 'restaurants.id is the primary key');
select col_is_pk('public', 'branches',      'id', 'branches.id is the primary key');
select col_is_pk('public', 'stations',      'id', 'stations.id is the primary key');
select col_type_is('public', 'organizations', 'id', 'uuid', 'organizations.id is uuid');
select col_type_is('public', 'restaurants',   'id', 'uuid', 'restaurants.id is uuid');
select col_type_is('public', 'branches',      'id', 'uuid', 'branches.id is uuid');
select col_type_is('public', 'stations',      'id', 'uuid', 'stations.id is uuid');

-- Every CHILD table carries a NOT NULL uuid organization_id (DECISION D-001)  13-18
select col_not_null('public', 'restaurants', 'organization_id', 'restaurants.organization_id is NOT NULL');
select col_not_null('public', 'branches',    'organization_id', 'branches.organization_id is NOT NULL');
select col_not_null('public', 'stations',    'organization_id', 'stations.organization_id is NOT NULL');
select col_type_is('public', 'restaurants', 'organization_id', 'uuid', 'restaurants.organization_id is uuid');
select col_type_is('public', 'branches',    'organization_id', 'uuid', 'branches.organization_id is uuid');
select col_type_is('public', 'stations',    'organization_id', 'uuid', 'stations.organization_id is uuid');

-- RLS ENABLED *and* FORCED on every table (DECISION D-012 layer 1) ---------- 19-26
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'organizations'), 'organizations: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'organizations'), 'organizations: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'restaurants'),   'restaurants: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'restaurants'),   'restaurants: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'branches'),      'branches: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'branches'),      'branches: RLS forced');
select ok((select relrowsecurity      from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'stations'),      'stations: RLS enabled');
select ok((select relforcerowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = 'stations'),      'stations: RLS forced');

-- Timestamp columns present (DECISION D-017) ------------------------------- 27-34
select has_column('public', 'organizations', 'created_at', 'organizations.created_at exists');
select has_column('public', 'restaurants',   'created_at', 'restaurants.created_at exists');
select has_column('public', 'branches',      'created_at', 'branches.created_at exists');
select has_column('public', 'stations',      'created_at', 'stations.created_at exists');
select has_column('public', 'organizations', 'updated_at', 'organizations.updated_at exists');
select has_column('public', 'restaurants',   'updated_at', 'restaurants.updated_at exists');
select has_column('public', 'branches',      'updated_at', 'branches.updated_at exists');
select has_column('public', 'stations',      'updated_at', 'stations.updated_at exists');

-- Soft-delete tombstone present and nullable (DECISION D-020) -------------- 35-42
select has_column('public', 'organizations', 'deleted_at', 'organizations.deleted_at exists');
select has_column('public', 'restaurants',   'deleted_at', 'restaurants.deleted_at exists');
select has_column('public', 'branches',      'deleted_at', 'branches.deleted_at exists');
select has_column('public', 'stations',      'deleted_at', 'stations.deleted_at exists');
select col_is_null('public', 'organizations', 'deleted_at', 'organizations.deleted_at is nullable (tombstone)');
select col_is_null('public', 'restaurants',   'deleted_at', 'restaurants.deleted_at is nullable (tombstone)');
select col_is_null('public', 'branches',      'deleted_at', 'branches.deleted_at is nullable (tombstone)');
select col_is_null('public', 'stations',      'deleted_at', 'stations.deleted_at is nullable (tombstone)');

-- updated_at maintenance triggers attached on every table (DECISION D-017) - 43-46
select has_trigger('public', 'organizations', 'organizations_set_updated_at', 'organizations updated_at trigger attached');
select has_trigger('public', 'restaurants',   'restaurants_set_updated_at',   'restaurants updated_at trigger attached');
select has_trigger('public', 'branches',      'branches_set_updated_at',      'branches updated_at trigger attached');
select has_trigger('public', 'stations',      'stations_set_updated_at',      'stations updated_at trigger attached');

-- The trigger actually stamps updated_at = now() on UPDATE (behavioral) ----- 47
-- (runs as the BYPASSRLS connection role; the BEFORE UPDATE trigger fires only on UPDATE)
insert into organizations (id, name, slug, default_currency, updated_at)
  values ('00000000-0000-0000-0000-0000000000ee', 'Trig Org', 'trig-org', 'USD', '2000-01-01T00:00:00Z');
update organizations set name = 'Trig Org 2' where id = '00000000-0000-0000-0000-0000000000ee';
select cmp_ok(
  (select updated_at from organizations where id = '00000000-0000-0000-0000-0000000000ee'),
  '>', '2000-01-01T00:00:00Z'::timestamptz,
  'UPDATE bumps organizations.updated_at via app.set_updated_at() trigger');

-- Least privilege: anon has NO table access (grants target only authenticated) 48-51
-- Asserted on the GRANT directly (not a runtime deny) because FORCED RLS would
-- otherwise mask a mistaken grant by returning zero rows instead of an error.
select ok(not has_table_privilege('anon', 'public.organizations', 'SELECT'), 'anon has no SELECT on organizations');
select ok(not has_table_privilege('anon', 'public.restaurants',   'SELECT'), 'anon has no SELECT on restaurants');
select ok(not has_table_privilege('anon', 'public.branches',      'SELECT'), 'anon has no SELECT on branches');
select ok(not has_table_privilege('anon', 'public.stations',      'SELECT'), 'anon has no SELECT on stations');

select * from finish();
rollback;
