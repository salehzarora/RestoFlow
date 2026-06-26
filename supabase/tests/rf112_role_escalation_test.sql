-- RF-112 Stage 1 -- role-rank escalation guard (D-033 / T-015): the load-bearing security control.
-- An actor can NEVER grant/assign a role at or above its own rank, touch an equal/higher existing
-- membership, self-grant, or self-escalate; platform_admin is unassignable; a cross-org membership id
-- is rejected. GUC-FREE: only app.current_app_user_id is set.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112esc-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf112esc-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
-- actors + membership holders
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112esc-owner@example.test'),       -- org_owner @ A
  ('00000000-0000-0000-0000-0000000000e2', 'rf112esc-restowner@example.test'),   -- restaurant_owner @ A1
  ('00000000-0000-0000-0000-0000000000e3', 'rf112esc-bmanager@example.test'),    -- manager @ A1a (branch)
  ('00000000-0000-0000-0000-0000000000e7', 'rf112esc-omanager@example.test'),    -- manager @ A (org-wide)
  ('00000000-0000-0000-0000-0000000000d1', 'rf112esc-target@example.test'),      -- grant target (no membership)
  ('00000000-0000-0000-0000-0000000000dc', 'rf112esc-cashier@example.test'),     -- holds fc cashier @ A1a
  ('00000000-0000-0000-0000-0000000000da', 'rf112esc-manager2@example.test'),    -- holds fa manager  @ A1a
  ('00000000-0000-0000-0000-0000000000de', 'rf112esc-restowner2@example.test'),  -- holds fe restaurant_owner @ A1
  ('00000000-0000-0000-0000-0000000000db', 'rf112esc-bcashier@example.test');    -- holds fb cashier @ B1 (org B)
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000e7', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager'),
  ('00000000-0000-0000-0000-0000000000fc', '00000000-0000-0000-0000-0000000000dc', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000fa', '00000000-0000-0000-0000-0000000000da', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000fe', '00000000-0000-0000-0000-0000000000de', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000000fb', '00000000-0000-0000-0000-0000000000db', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', null, 'cashier');

set local role authenticated;

-- ===== grant escalation: an actor cannot assign a role >= its own rank (target scope it DOES cover) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a (rank 2)
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','manager') ->> 'error'),
  'permission_denied', 'manager cannot assign manager (equal rank; permission_denied)');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','restaurant_owner') ->> 'error'),
  'permission_denied', 'manager cannot assign restaurant_owner (permission_denied)');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','org_owner') ->> 'error'),
  'permission_denied', 'manager cannot assign org_owner (permission_denied)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner @ A1 (rank 3)
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-0000000000d1','org_owner') ->> 'error'),
  'permission_denied', 'restaurant_owner cannot assign org_owner (permission_denied)');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-0000000000d1','restaurant_owner') ->> 'error'),
  'permission_denied', 'restaurant_owner cannot assign restaurant_owner (strict equal; permission_denied)');

-- ===== no self-grant =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000000000a0',null,null,'00000000-0000-0000-0000-0000000000e1','cashier') ->> 'error'),
  'permission_denied', 'no self-grant: org_owner cannot grant a membership to itself (permission_denied)');

-- ===== update_role escalation: cannot assign/touch an equal-or-higher role =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager @ A1a
select is(
  (app.update_role('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000000000fc','manager') ->> 'error'),
  'permission_denied', 'manager cannot promote a cashier to manager (assign equal rank; permission_denied)');
select is(
  (app.update_role('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000000000fa','cashier') ->> 'error'),
  'permission_denied', 'manager cannot modify an equal-rank (manager) membership (permission_denied)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e7';  -- org-wide manager (covers A1, rank 2)
select is(
  (app.update_role('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000000000fe','cashier') ->> 'error'),
  'permission_denied', 'manager cannot demote a higher-rank (restaurant_owner) membership it covers (permission_denied)');

-- ===== no self-escalation =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e2';  -- restaurant_owner, owns f2
select is(
  (app.update_role('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000000000f2','org_owner') ->> 'error'),
  'permission_denied', 'no self-escalation: restaurant_owner cannot promote its own membership (permission_denied)');

-- ===== platform_admin unassignable (42501) + cross-org membership id rejected (42501) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select throws_ok(
  $$ select app.update_role('00000000-0000-0000-0000-00000000c00b','00000000-0000-0000-0000-0000000000fc','platform_admin') $$,
  '42501', NULL, 'platform_admin is not an assignable role via update_role (42501; D-026)');
select throws_ok(
  $$ select app.update_role('00000000-0000-0000-0000-00000000c00c','00000000-0000-0000-0000-0000000000fb','manager') $$,
  '42501', NULL, 'Org A owner cannot update an Org B membership by id (cross-org; 42501)');

-- ===== control: an authorized update DOES succeed (proves the guard is not over-broad) =====
select is(
  (app.update_role('00000000-0000-0000-0000-00000000c0d1','00000000-0000-0000-0000-0000000000fc','manager') ->> 'ok'),
  'true', 'org_owner CAN promote a cashier to manager (strictly outranks both; control success)');

select * from finish();
rollback;
