-- ============================================================================
-- RF-015 — pgTAP membership-scoped RLS isolation test  (RISK R-003, CRITICAL)
-- ============================================================================
-- Proves, under the non-privileged `authenticated` role with the interim GUCs
-- app.current_app_user_id + app.current_organization_id:
--   * multi-org: a user with memberships in 2 orgs accesses ONLY the selected,
--     validated org; unselected/non-member/empty org => zero rows (never an
--     arbitrary org);
--   * org isolation: Org A context cannot read Org B rows;
--   * RESTAURANT-LEVEL isolation (Codex RF-015 required adjustment / A2), proven
--     for ALL four scoped surfaces (restaurants, branches, stations,
--     employee_profiles): a cashier scoped to Restaurant A1 cannot READ or WRITE
--     Restaurant A2 rows even inside the SAME org, while an org-level role sees all;
--   * BRANCH-LEVEL narrowing: a branch-scoped membership sees only its branch,
--     not a sibling branch in the same restaurant (minimal proof; full matrix RF-059);
--   * memberships RLS: a user sees its OWN membership (bootstrap) and in-scope
--     memberships; cross-restaurant membership writes are denied (WITH CHECK);
--   * app_users self-only: a user reads only its own row (cross-tenant PII isolation);
--   * platform plane: a platform_admin_grant WITHOUT a membership yields NO tenant
--     rows, and platform_admin_grants is unreachable on the tenant path.
-- Fixtures are inserted as the BYPASSRLS connection role; every assertion runs
-- under `set local role authenticated`. An RLS WITH CHECK violation = 42501.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(32);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
-- Org A: two restaurants (A1, A2) same org; RA1 has TWO branches (BA1, BA1b) for
-- branch-narrowing; RA2 has BA2. Each restaurant gets a station + employee_profile.
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rls-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rls-org-b', 'EUR');

insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A2'),
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B1');

insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a0011', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'Branch A1'),
  ('00000000-0000-0000-0000-0000000a0012', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000a0021', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a002', 'Branch A2'),
  ('00000000-0000-0000-0000-0000000b0011', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-00000000b001', 'Branch B1');

insert into stations (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000a01a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000a0011', 'Station A1'),
  ('00000000-0000-0000-0000-00000000a02a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-0000000a0021', 'Station A2');

insert into employee_profiles (id, organization_id, restaurant_id, display_name) values
  ('00000000-0000-0000-0000-00000000a01e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'Employee A1'),
  ('00000000-0000-0000-0000-00000000a02e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a002', 'Employee A2');

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'multi@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'cashier-a1@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'platadmin@example.test'),
  ('00000000-0000-0000-0000-00000000ee05', 'cashier-branch-a1@example.test');

-- M: org-wide in A AND B; OW: org-wide in A; CR: cashier scoped to RA1;
-- CB: cashier scoped to RA1 + Branch A1 (branch-narrowed).
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000b0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', null,                                   'cashier'),
  ('00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000a0011', 'cashier');

-- PA holds an ACTIVE platform-admin grant but NO membership anywhere.
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ee04');

set local role authenticated;

-- ===== Scenario A — multi-org user selects ONE valid org at a time ==========
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';

set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from restaurants)::int, 2, 'M @ Org A: sees both Org A restaurants');                                                   -- 1
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-00000000b001')::int, 0, 'M @ Org A: cannot read Org B restaurant'); -- 2

set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from restaurants)::int, 1, 'M @ Org B: sees only the Org B restaurant');                                                -- 3
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-00000000a001')::int, 0, 'M @ Org B: cannot read Org A restaurant'); -- 4

set local app.current_organization_id = '00000000-0000-0000-0000-0000000000c0';   -- an org M is NOT a member of
select is((select count(*) from restaurants)::int, 0, 'M @ non-member org: zero rows (selected org not validated => never an arbitrary org)');      -- 5

set local app.current_organization_id = '';
select is((select count(*) from restaurants)::int, 0, 'M @ empty org context: zero rows (deny-by-default)');                                        -- 6

-- ===== Scenario B — org-level role sees ALL in its org + in-scope memberships =
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee02';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from restaurants)::int, 2, 'org_owner @ Org A: sees ALL restaurants in the org');                                        -- 7
select is((select count(*) from memberships)::int, 4, 'org_owner @ Org A: in-scope read sees all 4 Org A memberships (not Org B)');                 -- 8

-- ===== Scenario C — cashier scoped to Restaurant A1: RESTAURANT isolation ====
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee03';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from restaurants)::int, 1, 'cashier @ RA1: sees only its own restaurant (NOT RA2, same org)');                            -- 9
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-00000000a001')::int, 1, 'cashier @ RA1: can read RA1');              -- 10
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-00000000a002')::int, 0, 'cashier @ RA1: CANNOT read RA2 (Restaurant B, same org)'); -- 11
select is((select count(*) from branches)::int, 2, 'cashier @ RA1: sees only RA1 branches (BA1+BA1b, not the RA2 branch)');                          -- 12
select is((select count(*) from branches where id = '00000000-0000-0000-0000-0000000a0021')::int, 0, 'cashier @ RA1: cannot read the RA2 branch');   -- 13
select is((select count(*) from stations)::int, 1, 'cashier @ RA1: sees only the RA1 station');                                                     -- 14
select is((select count(*) from stations where id = '00000000-0000-0000-0000-00000000a02a')::int, 0, 'cashier @ RA1: CANNOT read the RA2 station (same org)'); -- 15
select is((select count(*) from employee_profiles)::int, 1, 'cashier @ RA1: sees only the RA1 employee_profile');                                    -- 16
select is((select count(*) from employee_profiles where id = '00000000-0000-0000-0000-00000000a02e')::int, 0, 'cashier @ RA1: CANNOT read the RA2 employee_profile (PII, same org)'); -- 17
select is((select count(*) from app_users)::int, 1, 'cashier @ RA1: app_users self-only — sees just its own row');                                  -- 18
select is((select count(*) from app_users where id = '00000000-0000-0000-0000-00000000ee02')::int, 0, 'cashier @ RA1: cannot read another user (app_users self-only)'); -- 19
select is((select count(*) from memberships where app_user_id = '00000000-0000-0000-0000-00000000ee03')::int, 1, 'cashier @ RA1: sees its OWN membership row'); -- 20
-- positive control: the cashier MAY modify its own restaurant
select lives_ok(
  $$ update restaurants set name = 'Restaurant A1 (edited)' where id = '00000000-0000-0000-0000-00000000a001' $$,
  'cashier @ RA1: MAY modify its own restaurant (RA1)');                                                                                            -- 21
-- write isolation (WITH CHECK via has_scope) on every scoped surface --> 42501
select throws_ok(
  $$ insert into branches (organization_id, restaurant_id, name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a002','rogue') $$,
  '42501', NULL, 'cashier @ RA1: CANNOT create a branch under RA2 (WITH CHECK)');                                                                   -- 22
select throws_ok(
  $$ insert into stations (organization_id, restaurant_id, branch_id, name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a002','00000000-0000-0000-0000-0000000a0021','rogue') $$,
  '42501', NULL, 'cashier @ RA1: CANNOT create a station under RA2 (WITH CHECK)');                                                                  -- 23
select throws_ok(
  $$ insert into employee_profiles (organization_id, restaurant_id, display_name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a002','rogue') $$,
  '42501', NULL, 'cashier @ RA1: CANNOT create an employee_profile under RA2 (WITH CHECK)');                                                        -- 24
select throws_ok(
  $$ insert into memberships (app_user_id, organization_id, restaurant_id, role) values ('00000000-0000-0000-0000-00000000ee01','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000a002','cashier') $$,
  '42501', NULL, 'cashier @ RA1: CANNOT create a membership scoped to RA2 (WITH CHECK confines membership writes)');                                -- 25
-- a cashier UPDATE targeting RA2 is a silent no-op (USING hides it); verified after RESET ROLE
update restaurants set name = 'hacked-by-cashier' where id = '00000000-0000-0000-0000-00000000a002';

-- ===== Scenario C2 — bootstrap: own membership visible with NO org selected ==
set local app.current_organization_id = '';
select is((select count(*) from memberships)::int, 1, 'cashier @ no-org: still sees ONLY its own membership (bootstrap self-visibility)');           -- 26

-- ===== Scenario D — branch-scoped cashier: BRANCH-LEVEL narrowing ===========
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee05';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from branches where id = '00000000-0000-0000-0000-0000000a0011')::int, 1, 'branch cashier @ BA1: sees its own branch BA1'); -- 27
select is((select count(*) from branches where id = '00000000-0000-0000-0000-0000000a0012')::int, 0, 'branch cashier @ BA1: does NOT see sibling branch BA1b (same restaurant)'); -- 28
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-00000000a001')::int, 1, 'branch cashier @ BA1: still sees its parent restaurant RA1'); -- 29

-- ===== Scenario E — a platform-admin grant does NOT satisfy tenant RLS ======
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee04';     -- active grant, NO membership
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from restaurants)::int, 0, 'platform-admin grant WITHOUT a membership yields NO tenant rows');                            -- 30
select throws_ok(
  $$ select count(*) from platform_admin_grants $$,
  '42501', NULL, 'authenticated (tenant path) has NO access to platform_admin_grants');                                                             -- 31

reset role;

-- as the BYPASSRLS connection role, confirm the cashier UPDATE of RA2 changed nothing
select is((select name from restaurants where id = '00000000-0000-0000-0000-00000000a002'), 'Restaurant A2', 'cashier @ RA1 UPDATE of RA2 modified nothing (USING no-op)'); -- 32

select * from finish();
rollback;
