-- ============================================================================
-- RF-017 — pgTAP append-only / immutability / field-completeness test
-- ============================================================================
-- Proves D-013 append-only + the CHECKs. Mutation denial is shown two ways:
--   * app role (authenticated): INSERT/UPDATE/DELETE -> 42501 (no grant);
--   * elevated path (BYPASSRLS connection role): UPDATE/DELETE -> 42501 (the
--     BEFORE UPDATE/DELETE trigger fires and raises), proving the trigger itself.
-- Plus actor/action CHECKs and NOT NULL completeness. (audit_events has no FKs,
-- so no parent fixtures are needed; reference columns are soft uuids.)
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

-- ---- Fixture (connection role / BYPASSRLS): one valid row to mutate --------
insert into audit_events (id, organization_id, action, actor_app_user_id)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', 'seed.event', '00000000-0000-0000-0000-00000000ee01');

-- CHECK: an actor must be present (A3) -------------------------------------- 1
select throws_ok(
  $$ insert into audit_events (organization_id, action) values ('00000000-0000-0000-0000-0000000000a0', 'no.actor') $$,
  '23514', NULL, 'row with BOTH actor fields null is rejected (actor presence CHECK)');

-- CHECK: action must be non-blank ------------------------------------------- 2
select throws_ok(
  $$ insert into audit_events (organization_id, action, actor_app_user_id) values ('00000000-0000-0000-0000-0000000000a0', '   ', '00000000-0000-0000-0000-00000000ee01') $$,
  '23514', NULL, 'blank action is rejected (action length CHECK)');

-- a fully-populated valid row inserts cleanly (elevated path) ---------------- 3
select lives_ok(
  $$ insert into audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
     values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1',
             '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000ef0a1', '00000000-0000-0000-0000-00000000da11',
             'order.voided', 'manager override', '{"status":"submitted"}'::jsonb, '{"status":"voided"}'::jsonb) $$,
  'a fully-populated audit row inserts successfully');

-- field completeness: required NOT NULL columns ----------------------------- 4-7
select throws_ok($$ insert into audit_events (organization_id, action, actor_app_user_id) values (null, 'x', '00000000-0000-0000-0000-00000000ee01') $$, '23502', NULL, 'organization_id null rejected');
select throws_ok($$ insert into audit_events (organization_id, action, actor_app_user_id) values ('00000000-0000-0000-0000-0000000000a0', null, '00000000-0000-0000-0000-00000000ee01') $$, '23502', NULL, 'action null rejected');
select throws_ok($$ insert into audit_events (organization_id, action, actor_app_user_id, occurred_at) values ('00000000-0000-0000-0000-0000000000a0', 'x', '00000000-0000-0000-0000-00000000ee01', null) $$, '23502', NULL, 'occurred_at null rejected');
select throws_ok($$ insert into audit_events (organization_id, action, actor_app_user_id, created_at) values ('00000000-0000-0000-0000-0000000000a0', 'x', '00000000-0000-0000-0000-00000000ee01', null) $$, '23502', NULL, 'created_at null rejected');

-- elevated path: the trigger blocks UPDATE/DELETE (BYPASSRLS owner reaches the trigger) 8-9
select throws_ok($$ update audit_events set action = 'tampered' where id = '00000000-0000-0000-0000-0000000000e1' $$, '42501', NULL, 'append-only trigger blocks UPDATE (elevated path)');
select throws_ok($$ delete from audit_events where id = '00000000-0000-0000-0000-0000000000e1' $$, '42501', NULL, 'append-only trigger blocks DELETE (elevated path)');
select throws_ok($$ truncate audit_events $$, '42501', NULL, 'append-only trigger blocks TRUNCATE (elevated path)');

-- no soft-delete behaviour exists --------------------------------------------
select hasnt_column('public', 'audit_events', 'deleted_at', 'no soft-delete column on audit_events');

-- app role (authenticated) cannot mutate at all ----------------------------- 11-13
set local role authenticated;
select throws_ok($$ insert into audit_events (organization_id, action, actor_app_user_id) values ('00000000-0000-0000-0000-0000000000a0', 'x', '00000000-0000-0000-0000-00000000ee01') $$, '42501', NULL, 'authenticated cannot directly INSERT audit_events');
select throws_ok($$ update audit_events set action = 'x' where id = '00000000-0000-0000-0000-0000000000e1' $$, '42501', NULL, 'authenticated cannot UPDATE audit_events');
select throws_ok($$ delete from audit_events where id = '00000000-0000-0000-0000-0000000000e1' $$, '42501', NULL, 'authenticated cannot DELETE audit_events');
reset role;

-- defense in depth: prove the RLS *policy* layer blocks INSERT independently of the
-- grant layer. Temporarily grant INSERT to authenticated (rolled back with the test
-- transaction); the absent INSERT policy under FORCE RLS still denies it (42501).
grant insert on audit_events to authenticated;
set local role authenticated;
select throws_ok(
  $$ insert into audit_events (organization_id, action, actor_app_user_id) values ('00000000-0000-0000-0000-0000000000a0', 'x', '00000000-0000-0000-0000-00000000ee01') $$,
  '42501', NULL, 'even WITH an INSERT grant, FORCE RLS (no INSERT policy) blocks the insert');
reset role;

select * from finish();
rollback;
