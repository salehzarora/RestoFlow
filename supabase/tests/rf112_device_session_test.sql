-- RF-112 Stage 3 -- start_device_session: active-only, server token returned once, hash-only storage,
-- audit/idempotency no-leak, no duplicate on replay (D-034 / §4.29 / T-015). GUC-FREE (identity GUC only).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf112ses-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf112ses-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-0000dddd0001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'pos', 'Dev A1a');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at) values
  ('00000000-0000-0000-0000-0000aaaa0001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa0002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'active', now()),
  ('00000000-0000-0000-0000-0000aaaa0003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000dddd0001', 'paired', now());

-- capture table for the one-time session token (owner-created; granted to authenticated)
create temp table _s (token text, session uuid, ok text);
grant select, insert on _s to authenticated;

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';  -- org_owner

-- ===== start a session on an ACTIVE pairing =====
insert into _s
  select (r ->> 'session_token'), (r ->> 'device_session_id')::uuid, (r ->> 'ok')
  from (select app.start_device_session('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0001') as r) s;
select is((select ok from _s), 'true', 'start_device_session on an active pairing succeeds');
select isnt((select token from _s), null, 'a plaintext session token is returned (once)');
select isnt((select session from _s), null, 'a device_session_id is returned');

-- ===== must be ACTIVE: a paired pairing cannot start a session =====
select throws_ok(
  $$ select app.start_device_session('00000000-0000-0000-0000-00000000c002','00000000-0000-0000-0000-0000aaaa0003') $$,
  '42501', NULL, 'start_device_session on a PAIRED (non-active) pairing is rejected (42501)');

-- ===== idempotency: replay returns the same result WITHOUT re-leaking the token; conflict raises =====
select is(
  (app.start_device_session('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0001') ->> 'idempotent_replay'),
  'true', 'session replay (same client_request_id) -> idempotent_replay true');
select is(
  (app.start_device_session('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0001') ? 'session_token'),
  false, 'session replay does NOT re-return the one-time token (no leak)');
select throws_ok(
  $$ select app.start_device_session('00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000aaaa0002') $$,
  '42501', NULL, 'reusing a client_request_id for a different pairing raises (conflict; 42501)');

-- ===== secret storage + audit + no-duplicate (as the BYPASSRLS owner) =====
reset role;
select isnt(
  (select session_token_ref from device_sessions where id = (select session from _s)),
  (select token from _s), 'device_sessions stores a HASH, never the plaintext session token');
select is(
  (select session_token_ref from device_sessions where id = (select session from _s)),
  app.hash_provisioning_secret((select token from _s)), 'the stored session_token_ref equals sha256(token)');
select is(
  (select count(*) from audit_events where action = 'device.session_started'
     and (new_values ->> 'device_session_id') = (select session from _s)::text)::int,
  1, 'a device.session_started audit row was written');
select is(
  (select count(*) from audit_events where action = 'device.session_started'
     and new_values::text like '%' || (select token from _s) || '%')::int,
  0, 'NO audit row contains the plaintext session token');
select is(
  (select count(*) from device_sessions where device_pairing_id = '00000000-0000-0000-0000-0000aaaa0001')::int,
  1, 'the replayed start created exactly ONE device_sessions row (no duplicate)');

select * from finish();
rollback;
