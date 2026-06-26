-- RF-112 Stage 1 -- audit + client_request_id idempotency (D-033 / §4.26 / T-015 / D-013).
-- Replay of the same (actor, client_request_id) returns the same result (no duplicate mutation);
-- conflicting reuse raises 42501; the key is per-actor (never shared); success and denial both audit;
-- audit_events stays append-only. GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112ai-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112ai-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112ai-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000d1', 'rf112ai-t1@example.test'),
  ('00000000-0000-0000-0000-0000000000d2', 'rf112ai-t2@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager');

set local role authenticated;

-- ===== idempotency: first call vs replay vs conflict vs per-actor independence =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','cashier') ->> 'idempotent_replay'),
  'false', 'first grant: idempotent_replay = false');
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','cashier') ->> 'idempotent_replay'),
  'true', 'same (actor, client_request_id, input): idempotent_replay = true');
select throws_ok(
  $$ select app.grant_membership('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','manager') $$,
  '42501', NULL, 'same client_request_id with DIFFERENT input raises (conflicting reuse; 42501)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager: SAME request id, different actor
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d2','cashier') ->> 'idempotent_replay'),
  'false', 'idempotency is per-actor: a different actor reusing the same request_id is a fresh request');

-- ===== settings idempotency (update-style RPC) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
select is(
  (app.update_organization_settings('00000000-0000-0000-0000-00000000c022','00000000-0000-0000-0000-0000000000a0',null,null,'suspended') ->> 'idempotent_replay'),
  'false', 'first settings update: idempotent_replay = false');
select is(
  (app.update_organization_settings('00000000-0000-0000-0000-00000000c022','00000000-0000-0000-0000-0000000000a0',null,null,'suspended') ->> 'idempotent_replay'),
  'true', 'settings replay returns the same result (idempotent_replay = true)');

-- ===== a denial (for the denial-audit assertion) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager grants org_owner -> denied
select is(
  (app.grant_membership('00000000-0000-0000-0000-00000000c033','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-0000000000d1','org_owner') ->> 'error'),
  'permission_denied', 'manager grant of org_owner is denied (sets up the denial audit)');

-- ===== state + audit verification (as the BYPASSRLS owner) =====
reset role;
select is(
  (select count(*) from memberships
     where app_user_id = '00000000-0000-0000-0000-0000000000d1'
       and organization_id = '00000000-0000-0000-0000-0000000000a0'
       and branch_id = '00000000-0000-0000-0000-0000000a1a00' and role = 'cashier' and deleted_at is null)::int,
  1, 'the replayed grant created exactly ONE membership (no duplicate)');
select is(
  (select count(*) from audit_events where action = 'membership.granted'
     and (new_values ->> 'app_user_id') = '00000000-0000-0000-0000-0000000000d1')::int,
  1, 'the success audit was written exactly once (replay did not double-audit)');
select is(
  (select count(*) from audit_events where action = 'settings.organization.updated'
     and organization_id = '00000000-0000-0000-0000-0000000000a0')::int,
  1, 'the settings success audit was written exactly once (replay did not double-audit)');
select is(
  (select count(*) from audit_events where action = 'membership.grant_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-0000000000e3')::int,
  1, 'the role denial wrote exactly one membership.grant_denied audit row');

-- ===== audit_events remains append-only =====
select throws_ok(
  $$ update audit_events set action = 'tampered' where action = 'membership.granted' $$,
  '42501', NULL, 'audit_events cannot be UPDATEd (append-only; 42501)');
select throws_ok(
  $$ delete from audit_events where action = 'membership.granted' $$,
  '42501', NULL, 'audit_events cannot be DELETEd (append-only; 42501)');

select * from finish();
rollback;
