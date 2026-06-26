-- RF-112 Stage 1 -- app.role_rank + app.actor_rank_in_scope (the GUC-FREE authority resolver).
-- Proves the rank ladder, downward-only scope coverage, and that the resolver does NOT depend
-- on the org GUC app.current_organization_id (the RF-111 D1/D3 trap): a wrong/unset org GUC
-- never changes the result. The internal helpers are not granted to authenticated, so these
-- unit tests run as the migration owner with only the identity GUC (app.current_app_user_id) set.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(22);

-- ---- fixtures (two orgs; org A has two restaurants, restaurant A1 has two branches) --------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112ah-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112ah-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112ah-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf112ah-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112ah-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e7', 'rf112ah-platadmin@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager');
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000e7');

-- ===== app.role_rank: the total ladder =====
select is(app.role_rank('org_owner'),        4, 'role_rank org_owner = 4');
select is(app.role_rank('restaurant_owner'), 3, 'role_rank restaurant_owner = 3');
select is(app.role_rank('manager'),          2, 'role_rank manager = 2');
select is(app.role_rank('cashier'),          1, 'role_rank cashier = 1');
select is(app.role_rank('kitchen_staff'),    1, 'role_rank kitchen_staff = 1');
select is(app.role_rank('accountant'),       1, 'role_rank accountant = 1');
select is(app.role_rank('platform_admin'),   0, 'role_rank platform_admin = 0 (not a tenant role)');
select is(app.role_rank('nonsense'),         0, 'role_rank unknown = 0');

-- ===== app.actor_rank_in_scope: org_owner covers everything in its org =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  4, 'org_owner covers a branch target (rank 4)');
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0', null, null),
  4, 'org_owner covers the org-wide target (rank 4)');

-- ===== restaurant_owner(A1): covers its restaurant + branches; NOT org-wide, NOT sibling restaurant =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1', null),
  3, 'restaurant_owner covers its restaurant (rank 3)');
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  3, 'restaurant_owner covers a branch under its restaurant (rank 3)');
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0', null, null),
  0, 'restaurant_owner does NOT cover the org-wide target (downward-only -> 0)');
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2', null),
  0, 'restaurant_owner does NOT cover a sibling restaurant (0)');

-- ===== manager(A1a): covers only its branch =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  2, 'manager covers its own branch (rank 2)');
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1b00'),
  0, 'manager does NOT cover a sibling branch (0)');
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1', null),
  0, 'branch manager does NOT cover a restaurant-level target (0)');

-- ===== cross-org: an Org A owner has zero authority in Org B =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1', null),
  0, 'org_owner of Org A has rank 0 in Org B (cross-org)');

-- ===== GUC-FREE PROOF: a wrong/unset org GUC does not change the result =====
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';  -- deliberately the WRONG org
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  4, 'GUC-free: a WRONG app.current_organization_id does not change the rank (still 4 for Org A)');
set local app.current_organization_id = '';  -- unset
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  4, 'GUC-free: with NO org GUC set, the rank still resolves (4)');

-- ===== fail-closed: no actor, and a platform-admin-only principal =====
set local app.current_app_user_id = '';
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  0, 'no authenticated principal -> rank 0 (fail-closed)');
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';
select is(app.actor_rank_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'),
  0, 'platform-admin-only principal has NO tenant rank (0; D-026)');

select * from finish();
rollback;
