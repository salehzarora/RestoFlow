-- RF-161 -- device-auth bridge: DEVICE-ORIGINATED redeem/restore/revoke security matrix.
-- The device principal is an ANONYMOUS authenticated user (role authenticated, NO app_user =
-- app.current_app_user_id() NULL); authorization is the one-time code / session token, never
-- membership. Covers: wrong device type, expiry, consume-once, hash-only storage (no plaintext
-- token), restore (right/wrong token/device), revoke invalidates restore, and cross-org scope
-- derivation (RISK R-003). Mirrors the rf112 GUC-free harness.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(21);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000000161a00', 'Org A', 'rf161-a', 'USD'),
  ('00000000-0000-0000-0000-000000161b00', 'Org B', 'rf161-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000000161a11', '00000000-0000-0000-0000-000000161a00', 'Rest A1'),
  ('00000000-0000-0000-0000-000000161b11', '00000000-0000-0000-0000-000000161b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000161a1a', '00000000-0000-0000-0000-000000161a00', '00000000-0000-0000-0000-000000161a11', 'Branch A1a'),
  ('00000000-0000-0000-0000-000000161b1a', '00000000-0000-0000-0000-000000161b00', '00000000-0000-0000-0000-000000161b11', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000000161ae1', 'rf161-mgra@example.test'),
  ('00000000-0000-0000-0000-000000161be2', 'rf161-mgrb@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000000161af1', '00000000-0000-0000-0000-000000161ae1', '00000000-0000-0000-0000-000000161a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000000161bf2', '00000000-0000-0000-0000-000000161be2', '00000000-0000-0000-0000-000000161b00', null, null, 'org_owner');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-000000161d01', '00000000-0000-0000-0000-000000161a00', '00000000-0000-0000-0000-000000161a11', '00000000-0000-0000-0000-000000161a1a', 'pos', 'A POS'),
  ('00000000-0000-0000-0000-000000161d02', '00000000-0000-0000-0000-000000161a00', '00000000-0000-0000-0000-000000161a11', '00000000-0000-0000-0000-000000161a1a', 'kds', 'A KDS'),
  ('00000000-0000-0000-0000-000000161d03', '00000000-0000-0000-0000-000000161a00', '00000000-0000-0000-0000-000000161a11', '00000000-0000-0000-0000-000000161a1a', 'pos', 'A POS 2'),
  ('00000000-0000-0000-0000-000000161d0b', '00000000-0000-0000-0000-000000161b00', '00000000-0000-0000-0000-000000161b11', '00000000-0000-0000-0000-000000161b1a', 'pos', 'B POS');

create temp table _codes (dev text, code text);
grant select, insert on _codes to authenticated;
create temp table _sess (dev text, sid uuid, token text, org text, dtype text);
grant select, insert on _sess to authenticated;

set local role authenticated;

-- issue enrollment codes as the org owners (management-driven; RF-112).
set local app.current_app_user_id = '00000000-0000-0000-0000-000000161ae1';
insert into _codes select 'pos',  (app.issue_device_enrollment_code('00000000-0000-0000-0000-000000161c01', '00000000-0000-0000-0000-000000161d01') ->> 'enrollment_code');
insert into _codes select 'kds',  (app.issue_device_enrollment_code('00000000-0000-0000-0000-000000161c02', '00000000-0000-0000-0000-000000161d02') ->> 'enrollment_code');
insert into _codes select 'pos2', (app.issue_device_enrollment_code('00000000-0000-0000-0000-000000161c03', '00000000-0000-0000-0000-000000161d03') ->> 'enrollment_code');
set local app.current_app_user_id = '00000000-0000-0000-0000-000000161be2';
insert into _codes select 'b',    (app.issue_device_enrollment_code('00000000-0000-0000-0000-000000161c0b', '00000000-0000-0000-0000-000000161d0b') ->> 'enrollment_code');

-- expire pos2's code (owner writes device_pairings directly).
reset role;
update device_pairings set code_expires_at = now() - interval '1 minute' where device_id = '00000000-0000-0000-0000-000000161d03';

-- ===== redeem as an ANONYMOUS device (role authenticated, NO app_user) =====
set local role authenticated;
set local app.current_app_user_id = '';

-- (1) wrong device type is denied WITHOUT consuming the code.
select is(
  (app.redeem_device_pairing((select code from _codes where dev = 'pos'), 'kds') ->> 'error'),
  'wrong_type', 'a POS code redeemed as kds is denied (wrong_type)');

-- (2) the correct type succeeds and returns a one-time session token.
insert into _sess
  select 'pos', (r ->> 'device_session_id')::uuid, (r ->> 'session_token'), (r ->> 'organization_id'), (r ->> 'device_type')
  from (select app.redeem_device_pairing((select code from _codes where dev = 'pos'), 'pos') as r) s;
select isnt((select token from _sess where dev = 'pos'), null, 'redeem returns a one-time session token');
-- (3) scope is server-derived from the code (Org A, never injected).
select is((select org from _sess where dev = 'pos'), '00000000-0000-0000-0000-000000161a00', 'redeem returns the code''s org (scope derived, RISK R-003)');
-- (4) device_type echoed.
select is((select dtype from _sess where dev = 'pos'), 'pos', 'redeem returns the device type');

-- (5) the code is consumed exactly once.
select is(
  (app.redeem_device_pairing((select code from _codes where dev = 'pos'), 'pos') ->> 'error'),
  'invalid_code', 're-redeeming a consumed code is denied (invalid_code)');
-- (6) a bogus code is denied.
select is(
  (app.redeem_device_pairing('not-a-real-code', 'pos') ->> 'error'),
  'invalid_code', 'a bogus code is denied (invalid_code)');
-- (7) an expired code is denied.
select is(
  (app.redeem_device_pairing((select code from _codes where dev = 'pos2'), 'pos') ->> 'error'),
  'expired', 'an expired code is denied (expired)');

-- (8) KDS code redeems to a kds session.
insert into _sess
  select 'kds', (r ->> 'device_session_id')::uuid, (r ->> 'session_token'), (r ->> 'organization_id'), (r ->> 'device_type')
  from (select app.redeem_device_pairing((select code from _codes where dev = 'kds'), 'kds') as r) s;
select is((select dtype from _sess where dev = 'kds'), 'kds', 'a KDS code redeems to a kds device session');

-- (19) cross-org: Org B's code redeems ONLY to Org B (never Org A).
insert into _sess
  select 'b', (r ->> 'device_session_id')::uuid, (r ->> 'session_token'), (r ->> 'organization_id'), (r ->> 'device_type')
  from (select app.redeem_device_pairing((select code from _codes where dev = 'b'), 'pos') as r) s;
select is((select org from _sess where dev = 'b'), '00000000-0000-0000-0000-000000161b00', 'Org B code redeems to Org B scope only (no cross-org)');

-- ===== hash-only storage (as the BYPASSRLS owner) =====
reset role;
-- (9) session_token_ref is the SHA-256 hash of the returned token.
select is(
  (select session_token_ref from device_sessions where id = (select sid from _sess where dev = 'pos')),
  encode(digest((select token from _sess where dev = 'pos'), 'sha256'), 'hex'),
  'device_sessions.session_token_ref is the sha256 hash of the returned token');
-- (10) the raw token is NEVER stored in plaintext.
select isnt(
  (select session_token_ref from device_sessions where id = (select sid from _sess where dev = 'pos')),
  (select token from _sess where dev = 'pos'),
  'the raw session token is never stored in plaintext');
-- (11) the pairing was activated (code_issued -> active).
select is(
  (select status || ':' || (paired_at is not null)::text from device_pairings
     where device_id = '00000000-0000-0000-0000-000000161d01' and status = 'active'),
  'active:true', 'redeem activated the pairing (status=active, paired_at set)');

-- ===== restore / revoke as the device =====
set local role authenticated;
set local app.current_app_user_id = '';

-- (12) restore with the correct token returns the SAME session id.
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d01', (select token from _sess where dev = 'pos')) ->> 'device_session_id'),
  (select sid from _sess where dev = 'pos')::text, 'restore with the correct token returns the live device_session_id');
-- (13) restore returns the derived org.
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d01', (select token from _sess where dev = 'pos')) ->> 'organization_id'),
  '00000000-0000-0000-0000-000000161a00', 'restore returns the device''s org (scope derived)');
-- (14) restore with a wrong token fails closed.
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d01', 'wrong-token') ->> 'error'),
  'invalid_session', 'restore with a wrong token is denied (invalid_session)');
-- (15) restore with the RIGHT token but the WRONG device is denied (token pins the device).
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d02', (select token from _sess where dev = 'pos')) ->> 'error'),
  'invalid_session', 'a token cannot restore a different device''s session');

-- (16) the device self-revokes its session.
select is(
  (app.revoke_device_session('00000000-0000-0000-0000-000000161d01', (select token from _sess where dev = 'pos')) ->> 'revoked')::int,
  1, 'revoke_device_session revokes the live session (revoked=1)');
-- (17) restore after revoke fails closed.
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d01', (select token from _sess where dev = 'pos')) ->> 'error'),
  'invalid_session', 'restore after revoke is denied (invalid_session)');
-- (18) revoke is idempotent.
select is(
  (app.revoke_device_session('00000000-0000-0000-0000-000000161d01', (select token from _sess where dev = 'pos')) ->> 'revoked')::int,
  0, 're-revoking is idempotent (revoked=0, still ok)');

-- (20) owner-side pairing revocation invalidates restore (RISK R-007).
reset role;
update device_pairings set revoked_at = now() where device_id = '00000000-0000-0000-0000-000000161d02';
set local role authenticated;
set local app.current_app_user_id = '';
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d02', (select token from _sess where dev = 'kds')) ->> 'error'),
  'invalid_session', 'a revoked pairing invalidates device-session restore (owner revoke)');

-- (21) a soft-deleted BRANCH invalidates restore (MF-1: redeem/restore tombstone symmetry).
-- Org B's device (dB) has a live session (test 19); tombstone its branch and restore must fail.
reset role;
update branches set deleted_at = now() where id = '00000000-0000-0000-0000-000000161b1a';
set local role authenticated;
set local app.current_app_user_id = '';
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000161d0b', (select token from _sess where dev = 'b')) ->> 'error'),
  'invalid_session', 'a soft-deleted branch invalidates device-session restore (decommission)');

select * from finish();
rollback;
