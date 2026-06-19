-- ============================================================================
-- RF-015 — pgTAP membership role-key constraint test
-- ============================================================================
-- Proves memberships.role accepts EXACTLY the six tenant role keys (DECISION
-- D-004/D-026), including the reserved `accountant` key (Q-017; read-only per
-- D-028, no behavior implemented here), and REJECTS `platform_admin` — which is
-- not a membership role (DECISION D-026) — and any other value, via CHECK
-- (SQLSTATE 23514). Runs as the connection role; CHECK constraints bind every
-- role, so no RLS role switch is needed.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

-- ---- Fixtures: one org + one user (org-wide memberships, restaurant_id NULL)
insert into organizations (id, name, slug, default_currency)
  values ('00000000-0000-0000-0000-000000000001', 'Role Org', 'role-org', 'USD');
insert into app_users (id, email)
  values ('00000000-0000-0000-0000-0000000000f1', 'role-user@example.test');

-- The six valid role keys are accepted (incl. reserved accountant) --------- 1-6
select lives_ok($$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','org_owner') $$,       'role org_owner accepted');
select lives_ok($$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','restaurant_owner') $$, 'role restaurant_owner accepted');
select lives_ok($$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','manager') $$,         'role manager accepted');
select lives_ok($$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','cashier') $$,         'role cashier accepted');
select lives_ok($$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','kitchen_staff') $$,   'role kitchen_staff accepted');
select lives_ok($$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','accountant') $$,      'role accountant accepted (reserved key, Q-017; no behavior)');

-- platform_admin is NOT a membership role (D-026) -------------------------- 7
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','platform_admin') $$,
  '23514', NULL,
  'role platform_admin is REJECTED by CHECK (D-026: not a membership role)');

-- any other value is rejected --------------------------------------------- 8
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, role) values ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000001','superadmin') $$,
  '23514', NULL,
  'an unknown role value is REJECTED by CHECK');

select * from finish();
rollback;
