-- RF-112 Stage 1 -- RF112-S1-B1 regression: reject authority on SOFT-DELETED parent scopes (D-020/D-006).
-- grant_membership must not create, and update_role must not mutate, a membership scoped to a
-- soft-deleted restaurant or branch (or a live branch whose PARENT restaurant is soft-deleted).
-- Plus a small privilege-posture check on the idempotency ledger. GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112sd-a', 'USD');
-- rA1 stays live; rDel is soft-deleted below
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1 (live)'),
  ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-0000000000a0', 'Rest Del (to be soft-deleted)');
-- bA1a live under rA1; bDel soft-deleted under rA1; bUDR live but its parent restaurant rDel is soft-deleted
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a (live)'),
  ('00000000-0000-0000-0000-0000000a1d00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch Del (to be soft-deleted)'),
  ('00000000-0000-0000-0000-0000000add00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000ad', 'Branch under soft-deleted Rest');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112sd-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000d1', 'rf112sd-t1@example.test'),
  ('00000000-0000-0000-0000-0000000000d2', 'rf112sd-t2@example.test'),
  ('00000000-0000-0000-0000-0000000000d3', 'rf112sd-t3@example.test'),
  ('00000000-0000-0000-0000-0000000000d4', 'rf112sd-t4@example.test'),
  ('00000000-0000-0000-0000-0000000000d5', 'rf112sd-t5@example.test'),
  ('00000000-0000-0000-0000-0000000000c1', 'rf112sd-u1@example.test'),
  ('00000000-0000-0000-0000-0000000000c2', 'rf112sd-u2@example.test'),
  ('00000000-0000-0000-0000-0000000000c3', 'rf112sd-u3@example.test'),
  ('00000000-0000-0000-0000-0000000000c4', 'rf112sd-u4@example.test');
-- f1 = org_owner actor; f5..f8 = existing ACTIVE memberships scoped to (soon-to-be) dead / live scopes.
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000ad', null, 'cashier'),
  ('00000000-0000-0000-0000-0000000000f6', '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1d00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f7', '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-0000000add00', 'cashier'),
  ('00000000-0000-0000-0000-0000000000f8', '00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier');
-- NOW tombstone the dead scopes (rows still exist; FKs satisfied; deleted_at set).
update restaurants set deleted_at = now() where id = '00000000-0000-0000-0000-0000000000ad';
update branches    set deleted_at = now() where id = '00000000-0000-0000-0000-0000000a1d00';

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner (fully authorized)

-- ===== grant_membership: soft-deleted parent scopes are rejected (42501, not permission_denied) =====
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000ad',null,'00000000-0000-0000-0000-0000000000d1','cashier') $$,
  '42501', NULL, 'grant to a soft-deleted RESTAURANT scope is denied (42501)');
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c012','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1d00','00000000-0000-0000-0000-0000000000d2','cashier') $$,
  '42501', NULL, 'grant to a soft-deleted BRANCH scope is denied (42501)');
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c013','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000ad','00000000-0000-0000-0000-0000000add00','00000000-0000-0000-0000-0000000000d3','cashier') $$,
  '42501', NULL, 'grant to a live branch whose PARENT restaurant is soft-deleted is denied (42501)');

-- ===== grant_membership: live scopes still work (the guard is not over-broad) =====
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c014','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-0000000000d4','cashier') ->> 'ok'),
  'true', 'grant to a LIVE restaurant scope still succeeds');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c015','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d5','cashier') ->> 'ok'),
  'true', 'grant to a LIVE branch scope still succeeds');

-- ===== update_role: dead-parent-scoped memberships cannot be mutated (42501) =====
select throws_ok(
  $$ select app.update_role('00000000-0000-0000-0000-00000000c021','00000000-0000-0000-0000-0000000000f5','manager') $$,
  '42501', NULL, 'update_role on a membership scoped to a soft-deleted RESTAURANT is denied (42501)');
select throws_ok(
  $$ select app.update_role('00000000-0000-0000-0000-00000000c022','00000000-0000-0000-0000-0000000000f6','manager') $$,
  '42501', NULL, 'update_role on a membership scoped to a soft-deleted BRANCH is denied (42501)');
select throws_ok(
  $$ select app.update_role('00000000-0000-0000-0000-00000000c023','00000000-0000-0000-0000-0000000000f7','manager') $$,
  '42501', NULL, 'update_role on a branch membership whose PARENT restaurant is soft-deleted is denied (42501)');

-- ===== update_role: a live-scope membership still updates =====
select is(
  (app.update_role('00000000-0000-0000-0000-00000000c024','00000000-0000-0000-0000-0000000000f8','manager') ->> 'ok'),
  'true', 'update_role on a LIVE-scope membership still succeeds');

-- ===== privilege posture: the idempotency ledger is locked; app/public RPCs are not anon-callable =====
reset role;
select is(
  has_table_privilege('authenticated', 'public.management_request_results', 'SELECT'),
  false, 'authenticated has NO direct grant on the management idempotency ledger');
select is(
  (select relforcerowsecurity from pg_catalog.pg_class where oid = 'public.management_request_results'::regclass),
  true, 'management_request_results has RLS FORCED');
select is(
  has_function_privilege('anon', 'public.grant_membership(uuid,uuid,uuid,uuid,uuid,text)', 'EXECUTE'),
  false, 'anon cannot execute public.grant_membership');

select * from finish();
rollback;
