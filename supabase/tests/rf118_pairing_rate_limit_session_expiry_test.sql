-- ============================================================================
-- RF-118 -- pgTAP: device-pairing brute-force lockout + device-session expiry.
-- ============================================================================
-- Pairing lockout (per CALLER PRINCIPAL = auth.uid()): an invalid redeem PERSISTS
-- a failed-attempt increment (redeem RETURNS, never raises, so the counter
-- commits); at the centralized cap (10) the principal is locked; a locked caller
-- gets a SAFE generic 'locked' error even with a VALID code, and the valid code is
-- NOT consumed (lockout runs BEFORE the code lookup); after the lockout lapses a
-- valid redeem succeeds and RESETS (deletes) the counter.
-- Device-session expiry: redeem mints device_sessions.expires_at = now() + the
-- max age; restore rejects an expired session (invalid_session); a NULL
-- expires_at (pre-RF-118 rows) still restores (backward compatible).
--
-- The device principal is simulated via request.jwt.claims (-> auth.uid()); the
-- enrollment code is issued FIRST as an authenticated manager (current_app_user_id
-- GUC, no JWT) exactly like RF-161. Runs as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000000118a00', 'Org A', 'rf118-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000000118a11', '00000000-0000-0000-0000-000000118a00', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000118a1a', '00000000-0000-0000-0000-000000118a00', '00000000-0000-0000-0000-000000118a11', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000000118ae1', 'rf118-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000000118af1', '00000000-0000-0000-0000-000000118ae1', '00000000-0000-0000-0000-000000118a00', null, null, 'org_owner');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-000000118d01', '00000000-0000-0000-0000-000000118a00', '00000000-0000-0000-0000-000000118a11', '00000000-0000-0000-0000-000000118a1a', 'pos', 'A POS');

create temp table _c (code text);
create temp table _s (sid uuid, token text);

-- ---- Issue the enrollment code as the manager (no JWT; GUC principal) -------
set local app.current_app_user_id = '00000000-0000-0000-0000-000000118ae1';
insert into _c
  select app.issue_device_enrollment_code(
    '00000000-0000-0000-0000-000000118c01', '00000000-0000-0000-0000-000000118d01') ->> 'enrollment_code';
set local app.current_app_user_id = '';

-- ---- Attacker principal: drive auth.uid() via the JWT claim GUCs -----------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a77ac';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a77ac","role":"authenticated"}';

-- (1) sanity: the JWT principal resolves through auth.uid() (the lockout key).
select is(
  (auth.uid())::text, '00000000-0000-0000-0000-0000000a77ac',
  'request.jwt.claims drives auth.uid() (the pairing-lockout key)');

-- (2) an invalid code is denied (invalid_code) ...
select is(
  (app.redeem_device_pairing('not-a-real-code', 'pos') ->> 'error'),
  'invalid_code', 'an invalid pairing code is denied (invalid_code)');
-- (3) ... and PERSISTS a failed-attempt increment for the principal.
select is(
  (select failed_attempt_count from device_pairing_attempt_states
     where auth_user_id = '00000000-0000-0000-0000-0000000a77ac'),
  1, 'an invalid attempt increments the principal failed_attempt_count (persisted)');

-- Drive 9 more invalid attempts -> reach the centralized cap (10).
do $$
begin
  for i in 1..9 loop
    perform app.redeem_device_pairing('not-a-real-code', 'pos');
  end loop;
end $$;

-- (4) the counter reached the cap.
select is(
  (select failed_attempt_count from device_pairing_attempt_states
     where auth_user_id = '00000000-0000-0000-0000-0000000a77ac'),
  10, 'after the cap the failed_attempt_count = app.pairing_max_failed_attempts() (10)');
-- (5) the principal is now locked.
select ok(
  (select locked_until > now() from device_pairing_attempt_states
     where auth_user_id = '00000000-0000-0000-0000-0000000a77ac'),
  'reaching the cap locks the principal (locked_until in the future)');

-- (6) a locked caller gets a SAFE generic 'locked' error EVEN WITH A VALID code.
select is(
  (app.redeem_device_pairing((select code from _c), 'pos') ->> 'error'),
  'locked', 'a locked caller is refused with a safe generic ''locked'' error (valid code included)');
-- (7) the VALID code was NOT consumed (lockout runs BEFORE the code lookup).
-- (the pairing id is server-generated; the device has exactly one pairing here.)
select is(
  (select status from device_pairings where device_id = '00000000-0000-0000-0000-000000118d01'),
  'code_issued', 'the valid code is NOT consumed while locked (lockout precedes the lookup)');

-- Lapse the lockout (server-side time; owner writes the state row).
update device_pairing_attempt_states set locked_until = now() - interval '1 minute'
  where auth_user_id = '00000000-0000-0000-0000-0000000a77ac';

-- (8) after the lockout lapses, a VALID redeem succeeds.
insert into _s
  select (r ->> 'device_session_id')::uuid, (r ->> 'session_token')
  from (select app.redeem_device_pairing((select code from _c), 'pos') as r) x;
select isnt((select token from _s), null,
  'after the lockout lapses a valid redeem succeeds (session token minted)');
-- (9) success RESETS (deletes) the principal's failure counter.
select is(
  (select count(*)::int from device_pairing_attempt_states
     where auth_user_id = '00000000-0000-0000-0000-0000000a77ac'),
  0, 'a successful redeem resets (deletes) the principal failure counter');

-- ===== Device-session expiry (RF-118) =====
-- (10) the minted session carries expires_at ~ now() + app.device_session_max_age() (7 days).
select ok(
  (select expires_at > now() + interval '6 days' and expires_at < now() + interval '8 days'
     from device_sessions where id = (select sid from _s)),
  'redeem mints device_sessions.expires_at ~ now() + the device-session max age (7d)');
-- (11) restore works while the session is unexpired.
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000118d01', (select token from _s)) ->> 'device_session_id'),
  (select sid from _s)::text, 'restore returns the live session while unexpired');
-- (12) an EXPIRED session is rejected (invalid_session).
update device_sessions set expires_at = now() - interval '1 minute' where id = (select sid from _s);
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000118d01', (select token from _s)) ->> 'error'),
  'invalid_session', 'an expired device session is rejected on restore (invalid_session)');
-- (13) a NULL expires_at (pre-RF-118 row) STILL restores (backward compatible).
-- Insert directly on the device's (now active) pairing with a known token + NULL expiry.
insert into device_sessions
  (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, expires_at)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000118a00', '00000000-0000-0000-0000-000000118a11',
   '00000000-0000-0000-0000-000000118a1a', '00000000-0000-0000-0000-000000118d01',
   (select id from device_pairings where device_id = '00000000-0000-0000-0000-000000118d01'),
   app.hash_provisioning_secret('bc-token'), true, null);
select is(
  (app.restore_device_session('00000000-0000-0000-0000-000000118d01', 'bc-token') ->> 'ok')::boolean,
  true, 'a NULL expires_at session (pre-RF-118) still restores (backward compatible)');

select * from finish();
rollback;
