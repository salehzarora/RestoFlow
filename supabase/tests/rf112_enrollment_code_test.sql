-- RF-112 Stage 2 -- enrollment code: secret handling (return-once, hash-only, no plaintext in DB or
-- audit), expiry, consume-once, wrong-code, and idempotency-no-leak (D-033 / §4.27 / T-015).
-- GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(16);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112ec-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112ec-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf112ec-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Dev 1'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Dev 2');
-- a pre-seeded EXPIRED code_issued pairing on d1 (hash of 'rf112expiredcode'; expired 1 minute ago)
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, enrollment_code_hash, code_expires_at, status) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00',
   '00000000-0000-0000-0000-0000000000d1', app.hash_provisioning_secret('rf112expiredcode'), now() - interval '1 minute', 'code_issued');

create temp table _iss (code text, pairing uuid, status text, expires timestamptz);
grant select, insert on _iss to authenticated;

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner

insert into _iss
  select (r ->> 'enrollment_code'), (r ->> 'device_pairing_id')::uuid, (r ->> 'status'), (r ->> 'code_expires_at')::timestamptz
  from (select app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000d1') as r) s;
select is((select status from _iss), 'code_issued', 'issue -> code_issued');
select isnt((select code from _iss), null, 'issue returns the plaintext enrollment code (once)');

-- ===== secret storage: hash only, never plaintext (read as owner) =====
reset role;
select isnt(
  (select enrollment_code_hash from device_pairings where id = (select pairing from _iss)),
  (select code from _iss), 'device_pairings stores a HASH, never the plaintext code');
select is(
  (select enrollment_code_hash from device_pairings where id = (select pairing from _iss)),
  app.hash_provisioning_secret((select code from _iss)), 'the stored hash equals sha256(code)');
select is(
  (select count(*) from audit_events where action = 'device.enrollment_code_issued'
     and (new_values ->> 'device_pairing_id') = (select pairing from _iss)::text)::int,
  1, 'an enrollment_code_issued audit row was written');
select is(
  (select count(*) from audit_events where action = 'device.enrollment_code_issued'
     and new_values::text like '%' || (select code from _iss) || '%')::int,
  0, 'NO audit row contains the plaintext enrollment code');
select ok(
  (select code_expires_at from device_pairings where id = (select pairing from _iss)) > now(),
  'code_expires_at is set in the future (conservative TTL)');

-- ===== idempotency: replay returns the same result WITHOUT re-leaking the one-time code =====
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
select is(
  (app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000d1') ->> 'idempotent_replay'),
  'true', 'issue replay (same client_request_id) -> idempotent_replay = true');
select is(
  (app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000d1') ? 'enrollment_code'),
  false, 'issue replay does NOT re-return the one-time enrollment code (no leak)');
select throws_ok(
  $$ select app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000d2') $$,
  '42501', NULL, 'reusing a client_request_id for a different device raises (conflict; 42501)');

-- ===== redeem: valid -> pending; consume-once; wrong code; expired code =====
select is(
  (app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000000000d1', (select code from _iss)) ->> 'status'),
  'pending', 'redeem the issued code -> pending');
select throws_ok(
  format($$ select app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c003','00000000-0000-0000-0000-0000000000d1', %L) $$, (select code from _iss)),
  '42501', NULL, 'consume-once: re-redeeming the same code is rejected (42501)');
select throws_ok(
  $$ select app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c004','00000000-0000-0000-0000-0000000000d1', 'totally-wrong-code') $$,
  '42501', NULL, 'a wrong enrollment code is rejected (42501)');
select throws_ok(
  $$ select app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c005','00000000-0000-0000-0000-0000000000d1', 'rf112expiredcode') $$,
  '42501', NULL, 'an expired enrollment code is rejected (42501)');

-- ===== role denial: cashier cannot issue or redeem =====
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e4';  -- cashier
select is(
  (app.issue_device_enrollment_code('00000000-0000-0000-0000-00000000c006','00000000-0000-0000-0000-0000000000d1') ->> 'error'),
  'permission_denied', 'cashier cannot issue an enrollment code (permission_denied)');
select is(
  (app.redeem_device_enrollment_code('00000000-0000-0000-0000-00000000c007','00000000-0000-0000-0000-0000000000d1','x') ->> 'error'),
  'permission_denied', 'cashier cannot redeem an enrollment code (permission_denied)');

select * from finish();
rollback;
