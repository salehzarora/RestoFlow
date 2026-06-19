-- ============================================================================
-- RF-015 — pgTAP constraints test  (DECISION D-012 layer 4: DB as last boundary)
-- ============================================================================
-- Proves the structural same-org defenses the identity tables rely on actually
-- FIRE (mirroring rf014_constraints_test.sql). Run as the BYPASSRLS connection
-- role so FORCE RLS never masks a raw constraint error; constraints bind every
-- role. SQLSTATEs: 23503 foreign_key_violation, 23514 check_violation.
--   * memberships / employee_profiles cannot reference a restaurant, branch, or
--     membership in ANOTHER organization (composite same-org FKs).
--   * a branch scope cannot be set without its restaurant (branch_requires_restaurant).
--   * valid same-org rows insert cleanly (positive controls).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

-- ---- Fixtures: two orgs, each with a restaurant + branch; a user; one
--      membership per org (MA in A, MB in B) as composite-FK targets.
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'c-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'c-org-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A'),
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a0011', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'Branch A'),
  ('00000000-0000-0000-0000-0000000b0011', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-00000000b001', 'Branch B');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'constraints-user@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-0000000000a9', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000000a0', 'org_owner'),
  ('00000000-0000-0000-0000-0000000000b9', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000000b0', 'org_owner');

-- 1. membership cannot scope to a restaurant in ANOTHER org ----------------- 1
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, restaurant_id, role)
     values ('00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000b001','cashier') $$,
  '23503', NULL,
  'membership scoped to a foreign-org restaurant is structurally rejected (composite FK)');

-- 2. membership cannot scope to a branch in ANOTHER org/restaurant ---------- 2
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role)
     values ('00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-0000000b0011','cashier') $$,
  '23503', NULL,
  'membership scoped to a foreign branch is structurally rejected (composite FK)');

-- 3. membership branch scope requires a restaurant scope -------------------- 3
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, branch_id, role)
     values ('00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000a0011','cashier') $$,
  '23514', NULL,
  'membership with branch_id but NULL restaurant_id is rejected (branch_requires_restaurant)');

-- 4. employee_profile cannot link a membership in ANOTHER org --------------- 4
select throws_ok(
  $$ insert into employee_profiles (organization_id, membership_id, display_name)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000b9','x') $$,
  '23503', NULL,
  'employee_profile linking a foreign-org membership is structurally rejected (composite FK)');

-- 5. employee_profile cannot scope to a restaurant in ANOTHER org ----------- 5
select throws_ok(
  $$ insert into employee_profiles (organization_id, restaurant_id, display_name)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000b001','x') $$,
  '23503', NULL,
  'employee_profile scoped to a foreign-org restaurant is structurally rejected (composite FK)');

-- 6. employee_profile branch scope requires a restaurant scope -------------- 6
select throws_ok(
  $$ insert into employee_profiles (organization_id, branch_id, display_name)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000a0011','x') $$,
  '23514', NULL,
  'employee_profile with branch_id but NULL restaurant_id is rejected (branch_requires_restaurant)');

-- 7. a valid same-org membership inserts cleanly ---------------------------- 7
select lives_ok(
  $$ insert into memberships (app_user_id, organization_id, restaurant_id, role)
     values ('00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a001','cashier') $$,
  'a same-org restaurant-scoped membership inserts successfully');

-- 8. a valid same-org employee_profile (incl. same-org membership link) ----- 8
select lives_ok(
  $$ insert into employee_profiles (organization_id, restaurant_id, membership_id, display_name)
     values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-0000000000a9','ok') $$,
  'a same-org employee_profile with a same-org membership link inserts successfully');

select * from finish();
rollback;
