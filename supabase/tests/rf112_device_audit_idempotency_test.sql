-- RF-112 Stage 2 -- device provisioning audit + client_request_id idempotency (D-033 / §4.27 /
-- T-015 / D-013). Every mutation + denial audits; replay returns the same result (no duplicate);
-- conflicting reuse raises; the key is per-actor. GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(14);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112dai-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112dai-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf112dai-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112dai-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Lifecycle Dev');

create temp table _dev (r jsonb);
create temp table _iss (code text, pairing uuid);
grant select, insert on _dev, _iss to authenticated;

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner

-- ===== create_device idempotency (replay / conflict / per-actor) =====
insert into _dev select app.create_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','Audit Dev');
select is(((select r from _dev) ->> 'idempotent_replay'), 'false', 'create_device first call -> idempotent_replay false');
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','Audit Dev') ->> 'idempotent_replay'),
  'true', 'create_device replay (same client_request_id) -> idempotent_replay true');
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','Audit Dev') ->> 'device_id'),
  ((select r from _dev) ->> 'device_id'), 'create_device replay returns the SAME device_id (no duplicate)');
select throws_ok(
  $$ select app.create_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','kds','Audit Dev') $$,
  '42501', NULL, 'create_device same client_request_id with different input -> conflict (42501)');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e3';  -- manager: SAME request id, different actor
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','Mgr Dev') ->> 'idempotent_replay'),
  'false', 'idempotency is per-actor: a different actor reusing the request id is a fresh request');

set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier: denial (for the denied audit)
select is(
  (app.create_device('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','pos','x') ->> 'error'),
  'permission_denied', 'cashier create is denied (sets up the device.create_denied audit)');

-- ===== lifecycle (for the per-action audit rows) + approve idempotency =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
insert into _iss
  select (r ->> 'enrollment_code'), (r ->> 'device_pairing_id')::uuid
  from (select app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c010','00000000-0000-0000-0000-0000000000d1') as r) s;
select is(
  (app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c011','00000000-0000-0000-0000-0000000000d1', (select code from _iss)) ->> 'status'),
  'pending', 'redeem -> pending');
select is(
  (app.approve_device('00000000-0000-0000-0000-00000000c012', (select pairing from _iss)) ->> 'status'),
  'paired', 'approve -> paired');
select is(
  (app.approve_device('00000000-0000-0000-0000-00000000c012', (select pairing from _iss)) ->> 'idempotent_replay'),
  'true', 'approve_device replay (same client_request_id) -> idempotent_replay true');

-- ===== audit verification (as the BYPASSRLS owner) =====
reset role;
select is(
  (select count(*) from devices where id = ((select r from _dev) ->> 'device_id')::uuid)::int,
  1, 'the replayed create produced exactly ONE device row (no duplicate)');
select is(
  (select count(*) from audit_events where action = 'device.create_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-0000000000e4')::int,
  1, 'the cashier create-denial wrote one device.create_denied audit row');
select is(
  (select count(*) from audit_events where action = 'device.enrollment_code_issued'
     and (new_values ->> 'device_pairing_id') = (select pairing from _iss)::text)::int,
  1, 'a device.enrollment_code_issued audit row was written');
select is(
  (select count(*) from audit_events where action = 'device.enrollment_code_redeemed'
     and (new_values ->> 'device_pairing_id') = (select pairing from _iss)::text)::int,
  1, 'a device.enrollment_code_redeemed audit row was written');
select is(
  (select count(*) from audit_events where action = 'device.approved'
     and (new_values ->> 'device_pairing_id') = (select pairing from _iss)::text)::int,
  1, 'a device.approved audit row was written');

select * from finish();
rollback;
