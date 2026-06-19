-- ============================================================================
-- RF-014 — pgTAP constraints test  (DECISION D-012 layer 4: DB as last boundary)
-- ============================================================================
-- Proves the DB-level safety boundary independent of RLS (constraints bind even
-- the BYPASSRLS connection role, so these run as the connection role):
--   * organization_id cannot be NULL (DECISION D-001).
--   * organization_id must reference a real organization (FK).
--   * status / currency CHECK constraints reject bad values.
--   * CROSS-ORG parent references are STRUCTURALLY IMPOSSIBLE: the composite
--     same-org FKs reject a child whose parent lives in another organization
--     (SECURITY_AND_THREAT_MODEL structural cross-tenant prevention).
--   * A correctly same-org child chain inserts successfully.
--
-- SQLSTATEs asserted: 23502 not_null_violation, 23503 foreign_key_violation,
-- 23514 check_violation. (errmsg arg = NULL so only the SQLSTATE is asserted,
-- keeping tests resilient to message wording.)
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

-- ---- Fixtures: two orgs, each with a restaurant + branch -------------------
insert into organizations (id, name, slug, default_currency, country_code) values
  ('00000000-0000-0000-0000-00000000000a', 'Org A', 'org-a', 'USD', 'US'),
  ('00000000-0000-0000-0000-00000000000b', 'Org B', 'org-b', 'EUR', 'DE');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', 'Restaurant A'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000b', 'Restaurant B');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'Branch A'),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000b1', 'Branch B');

-- 1. NULL organization_id rejected (DECISION D-001) ------------------------- 1
select throws_ok(
  $$ insert into restaurants (organization_id, name) values (NULL, 'No Org') $$,
  '23502', NULL,
  'restaurants.organization_id NULL is rejected (not_null_violation)');

-- 2. organization_id must reference a real organization --------------------- 2
select throws_ok(
  $$ insert into restaurants (organization_id, name)
     values ('00000000-0000-0000-0000-0000000000ff', 'Ghost Org') $$,
  '23503', NULL,
  'restaurants.organization_id to a non-existent org is rejected (foreign_key_violation)');

-- 3. status CHECK rejects an unknown value ---------------------------------- 3
select throws_ok(
  $$ insert into organizations (name, slug, default_currency, status)
     values ('Bad Status', 'bad-status', 'USD', 'bogus') $$,
  '23514', NULL,
  'organizations.status outside the allowed set is rejected (check_violation)');

-- 4. currency CHECK rejects a non-ISO-shaped code --------------------------- 4
select throws_ok(
  $$ insert into organizations (name, slug, default_currency)
     values ('Bad Currency', 'bad-currency', 'usd') $$,
  '23514', NULL,
  'organizations.default_currency not matching ^[A-Z]{3}$ is rejected (check_violation)');

-- 5. CROSS-ORG branch: Org A branch pointing at Org B restaurant ------------ 5
select throws_ok(
  $$ insert into branches (organization_id, restaurant_id, name)
     values ('00000000-0000-0000-0000-00000000000a',
             '00000000-0000-0000-0000-0000000000b1', 'Cross-org Branch') $$,
  '23503', NULL,
  'branch referencing a restaurant in another org is structurally rejected (composite FK)');

-- 6. CROSS-ORG station: Org A station pointing at Org B branch -------------- 6
select throws_ok(
  $$ insert into stations (organization_id, restaurant_id, branch_id, name)
     values ('00000000-0000-0000-0000-00000000000a',
             '00000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000b2', 'Cross-org Station') $$,
  '23503', NULL,
  'station referencing a branch in another org is structurally rejected (composite FK)');

-- 7. A valid same-org branch inserts cleanly -------------------------------- 7
select lives_ok(
  $$ insert into branches (organization_id, restaurant_id, name)
     values ('00000000-0000-0000-0000-00000000000a',
             '00000000-0000-0000-0000-0000000000a1', 'Valid Branch A2') $$,
  'a same-org branch (Org A restaurant) inserts successfully');

-- 8. A valid same-org station inserts cleanly ------------------------------- 8
select lives_ok(
  $$ insert into stations (organization_id, restaurant_id, branch_id, name)
     values ('00000000-0000-0000-0000-00000000000a',
             '00000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', 'Valid Station A2') $$,
  'a same-org station (Org A branch) inserts successfully');

-- 9. slug of a SOFT-DELETED org is NOT reusable -------------------------------- 9
-- Pins the interim decision (migration: comment on organizations.slug): the
-- global UNIQUE is unconditional, so a D-020 tombstone keeps the slug reserved.
-- Flip this to lives_ok + a partial unique index if reuse-after-offboarding is
-- ever required (Q-005). 23505 = unique_violation.
update organizations set deleted_at = now() where id = '00000000-0000-0000-0000-00000000000a';
select throws_ok(
  $$ insert into organizations (name, slug, default_currency)
     values ('Reuse A', 'org-a', 'USD') $$,
  '23505', NULL,
  'slug of a soft-deleted organization cannot be reused (global unique persists through tombstone — interim decision)');

select * from finish();
rollback;
