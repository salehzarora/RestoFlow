-- RF-112 Stage 2 -- fail-closed regression: redeem/approve reject revoked / suspended / code_expired /
-- already-paired / not-yet-redeemed pairings; approve never does pending->active; anon cannot call the
-- provisioning RPCs (D-033 / §4.27 / STATE_MACHINES §9 / T-004 / RISK R-007). GUC-FREE.
-- (The RF-061 revoke RPCs are unchanged; this proves MY redeem/approve fail closed on dead states.)

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112rev-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112rev-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
-- one device per target pairing state
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Revoked dev'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Suspended dev'),
  ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Code-expired dev'),
  ('00000000-0000-0000-0000-0000000000d4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Already-paired dev'),
  ('00000000-0000-0000-0000-0000000000d5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Code-issued dev'),
  ('00000000-0000-0000-0000-0000000000d6', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Pending dev');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, enrollment_code_hash, code_expires_at, status, paired_at) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000d1', app.hash_provisioning_secret('rf112rev'), null, 'revoked', null),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000d2', app.hash_provisioning_secret('rf112sus'), null, 'suspended', null),
  ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000d3', app.hash_provisioning_secret('rf112exp'), now() - interval '1 minute', 'code_expired', null),
  ('00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000d4', null, null, 'paired', now()),
  ('00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000d5', app.hash_provisioning_secret('rf112ci'), now() + interval '10 minutes', 'code_issued', null),
  ('00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000d6', null, null, 'pending', null);

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner

-- ===== redeem fails closed on dead/non-code_issued pairings (even with the right code) =====
select throws_ok(
  $$ select app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000d1','rf112rev') $$,
  '42501', NULL, 'redeem on a REVOKED pairing is rejected (no code_issued match; 42501)');
select throws_ok(
  $$ select app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000000000d2','rf112sus') $$,
  '42501', NULL, 'redeem on a SUSPENDED pairing is rejected (42501)');
select throws_ok(
  $$ select app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000000000d3','rf112exp') $$,
  '42501', NULL, 'redeem on a CODE_EXPIRED pairing is rejected (42501)');

-- ===== approve only accepts pending; every other state fails closed (never pending->active) =====
select throws_ok(
  $$ select app.approve_device('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000000000b1') $$,
  '42501', NULL, 'approve a REVOKED pairing is rejected (not pending; 42501)');
select throws_ok(
  $$ select app.approve_device('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000000000b2') $$,
  '42501', NULL, 'approve a SUSPENDED pairing is rejected (42501)');
select throws_ok(
  $$ select app.approve_device('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000000000b3') $$,
  '42501', NULL, 'approve a CODE_EXPIRED pairing is rejected (42501)');
select throws_ok(
  $$ select app.approve_device('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000000000b4') $$,
  '42501', NULL, 'approve an already-PAIRED pairing is rejected (no re-approve / no pending->active; 42501)');
select throws_ok(
  $$ select app.approve_device('00000000-0000-0000-0000-00000000c008','00000000-0000-0000-0000-0000000000b5') $$,
  '42501', NULL, 'approve a not-yet-redeemed CODE_ISSUED pairing is rejected (must redeem first; 42501)');

-- ===== controls: the live edges still succeed (guards are not over-broad) =====
select is(
  (app.approve_device('00000000-0000-0000-0000-00000000c009','00000000-0000-0000-0000-0000000000b6') ->> 'status'),
  'paired', 'approve a PENDING pairing succeeds (pending -> paired; control)');
select is(
  (app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c00a','00000000-0000-0000-0000-0000000000d5','rf112ci') ->> 'status'),
  'pending', 'redeem a live CODE_ISSUED pairing succeeds (code_issued -> pending; control)');

-- ===== posture: anon cannot execute the provisioning RPCs =====
reset role;
select is(
  has_function_privilege('anon', 'public.create_device(uuid,uuid,uuid,uuid,text,text)', 'EXECUTE'),
  false, 'anon cannot execute public.create_device');
select is(
  has_function_privilege('anon', 'public.approve_device(uuid,uuid)', 'EXECUTE'),
  false, 'anon cannot execute public.approve_device');

select * from finish();
rollback;
