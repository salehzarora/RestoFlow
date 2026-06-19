-- ============================================================================
-- RF-014 — pgTAP RLS tenant-isolation test  (RISK R-003, CRITICAL)
-- ============================================================================
-- Proves the deny-by-default tenant-isolation contract of the RLS skeleton:
--   * No tenant context  => zero rows everywhere (deny-by-default).
--   * Context = Org A     => sees ONLY Org A rows; Org B rows are invisible,
--                            including a direct by-id lookup (IDOR blocked).
--   * Context = Org B     => symmetric.
--
-- Fixtures for BOTH orgs are inserted as the connection role (postgres, which
-- has BYPASSRLS), so the rows genuinely exist; every isolation assertion then
-- runs under `SET LOCAL ROLE authenticated` — a NON-privileged role without
-- BYPASSRLS — which is the only way RLS is actually exercised (TESTING_STRATEGY:
-- run as real principals, never owner/superuser/service_role).
--
-- Interim tenant context is the GUC app.current_organization_id read by
-- app.current_org_id() (RF-014; superseded by RF-015/RF-050/RF-059).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(24);

-- ---- Fixtures (inserted as postgres / BYPASSRLS): two fully-populated orgs --
insert into organizations (id, name, slug, default_currency, country_code) values
  ('00000000-0000-0000-0000-00000000000a', 'Org A', 'org-a', 'USD', 'US'),
  ('00000000-0000-0000-0000-00000000000b', 'Org B', 'org-b', 'EUR', 'DE');

insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', 'Restaurant A'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', 'Restaurant B');

insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'Branch A'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000b1', 'Branch B');

insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2', 'Station A'),
  ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b2', 'Station B');

-- ---- Exercise RLS as the non-privileged `authenticated` role ---------------
set local role authenticated;

-- Deny-by-default: GUC genuinely unset => current_org_id() is NULL => zero rows  1-4
select is((select count(*) from organizations)::int, 0, 'No tenant context => zero organizations (deny-by-default)');
select is((select count(*) from restaurants)::int,   0, 'No tenant context => zero restaurants (deny-by-default)');
select is((select count(*) from branches)::int,      0, 'No tenant context => zero branches (deny-by-default)');
select is((select count(*) from stations)::int,      0, 'No tenant context => zero stations (deny-by-default)');

-- Context = Org A: sees only Org A; Org B is invisible even by id (IDOR)  ---- 5-10
set local app.current_organization_id = '00000000-0000-0000-0000-00000000000a';
select is((select count(*) from organizations)::int, 1, 'Org A context: sees exactly its own organization');
select is((select count(*) from restaurants)::int,   1, 'Org A context: sees only its restaurants');
select is((select count(*) from branches)::int,      1, 'Org A context: sees only its branches');
select is((select count(*) from stations)::int,      1, 'Org A context: sees only its stations');
select is((select count(*) from restaurants  where id = '00000000-0000-0000-0000-0000000000b1')::int, 0, 'Org A cannot read Org B restaurant by id (IDOR blocked)');
select is((select count(*) from organizations where id = '00000000-0000-0000-0000-00000000000b')::int, 0, 'Org A cannot read Org B organization by id (IDOR blocked)');

-- Context = Org B: symmetric isolation  ------------------------------------- 11-15
set local app.current_organization_id = '00000000-0000-0000-0000-00000000000b';
select is((select count(*) from organizations)::int, 1, 'Org B context: sees exactly its own organization');
select is((select count(*) from restaurants)::int,   1, 'Org B context: sees only its restaurants');
select is((select count(*) from branches)::int,      1, 'Org B context: sees only its branches');
select is((select count(*) from stations)::int,      1, 'Org B context: sees only its stations');
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-0000000000a1')::int, 0, 'Org B cannot read Org A restaurant by id (IDOR blocked)');

-- Empty tenant context => NULL => deny-by-default  -------------------------- 16-17
set local app.current_organization_id = '';
select is((select count(*) from organizations)::int, 0, 'Empty tenant context => zero organizations (deny-by-default)');
select is((select count(*) from restaurants)::int,   0, 'Empty tenant context => zero restaurants (deny-by-default)');

-- ===========================================================================
-- WRITE isolation under RLS WITH CHECK (RISK R-003 write half; T-002) + the
-- intentional tombstone-visibility property. The read half above proves USING;
-- this half proves WITH CHECK, the clause that stops cross-tenant WRITES. An
-- RLS WITH CHECK violation raises SQLSTATE 42501 (insufficient_privilege),
-- NOT a 23xxx constraint code. Still role = authenticated; re-set Org A context.
-- ===========================================================================
set local app.current_organization_id = '00000000-0000-0000-0000-00000000000a';

-- 18: soft-deleted OWN-tenant row stays visible — policies intentionally omit a
-- `deleted_at IS NULL` filter so tombstones still propagate (DECISION D-020).
update restaurants set deleted_at = now() where id = '00000000-0000-0000-0000-0000000000a1';
select is((select count(*) from restaurants)::int, 1, 'Org A: soft-deleted own restaurant remains visible (RLS does not hide tombstones — D-020)');

-- 19: positive control — an in-tenant INSERT passes WITH CHECK (guards against an over-tight policy)
select lives_ok(
  $$ insert into restaurants (organization_id, name) values ('00000000-0000-0000-0000-00000000000a', 'In-tenant OK') $$,
  'Org A: in-tenant INSERT under authenticated succeeds (WITH CHECK passes)');

-- 20: cross-org INSERT on restaurants rejected by WITH CHECK (restaurants has only an existence FK, so WITH CHECK is the sole defence)
select throws_ok(
  $$ insert into restaurants (organization_id, name) values ('00000000-0000-0000-0000-00000000000b', 'X') $$,
  '42501', NULL,
  'Org A: INSERT tagged organization_id = Org B is rejected by RLS WITH CHECK');

-- 21: cross-org INSERT on organizations (no FK backstop at all) rejected by WITH CHECK — use a fresh id to avoid a PK clash
select throws_ok(
  $$ insert into organizations (id, name, slug, default_currency) values ('00000000-0000-0000-0000-00000000000c', 'Y', 'y-slug', 'USD') $$,
  '42501', NULL,
  'Org A: INSERT organization with a foreign id is rejected by RLS WITH CHECK');

-- 22: re-tenanting UPDATE rejected by WITH CHECK — USING passes (own row visible), the post-image fails the check
select throws_ok(
  $$ update restaurants set organization_id = '00000000-0000-0000-0000-00000000000b' where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501', NULL,
  'Org A: re-tenanting a row into Org B is rejected by RLS WITH CHECK');

-- cross-tenant UPDATEs under Org A are silent no-ops (USING hides Org B rows); verified after RESET ROLE below
update restaurants   set name   = 'hijack-attempt' where id = '00000000-0000-0000-0000-0000000000b1';
update organizations set status = 'suspended'      where id = '00000000-0000-0000-0000-00000000000b';

reset role;

-- 23-24: as the BYPASSRLS connection role, confirm Org B rows were untouched by the cross-tenant write attempts
select is((select name   from restaurants   where id = '00000000-0000-0000-0000-0000000000b1'), 'Restaurant B', 'cross-tenant UPDATE under Org A did NOT modify Org B restaurant (USING no-op)');
select is((select status from organizations where id = '00000000-0000-0000-0000-00000000000b'), 'active',       'cross-tenant UPDATE under Org A did NOT modify Org B organization (USING no-op)');

select * from finish();
rollback;
