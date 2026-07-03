-- ============================================================================
-- RF-051 — pgTAP: idempotency replay safety (RF051-B1)
-- ============================================================================
-- app.start_pin_session performs its idempotency replay ONLY after full
-- validation (device session, pairing, employee, membership, lockout) AND a
-- successful verifier, scoped to (org, device session, employee, resolved
-- membership, local_operation_id). Proves a replay can never:
--   1. be skipped when the same validated op repeats (returns the same session);
--   2. be returned to a wrong verifier (returns NULL, no existing session);
--   3. be returned while the (employee, device) is locked (42501);
--   4. be returned after device/session/pairing revocation (42501);
--   5. return ANOTHER user's session (different employee + same op).
-- Fixtures inserted as the BYPASSRLS connection role; the RPC is SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r51i-org-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
-- device sessions: active (ok), inactive, revoked — all on the same active pairing/device
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', true,  null),   -- OK
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', false, null),   -- inactive
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', true,  now());  -- revoked
-- two employees (A and B), each with an authoritative membership + verifier
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'r51i-a@example.test'),
  ('00000000-0000-0000-0000-0000000000bb', 'r51i-b@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-0000000ab0a1', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a0', 'cashier'),
  ('00000000-0000-0000-0000-0000000ab0b1', '00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000a0', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef0a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000ab0a1', extensions.crypt('ref:A', extensions.gen_salt('bf'))),
  ('00000000-0000-0000-0000-0000000ef0b0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000ab0b1', extensions.crypt('ref:B', extensions.gen_salt('bf')));

-- ===== 1. same op + same validated inputs returns the SAME session ===========
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','opX');
select is(
  (select id from pin_sessions where local_operation_id = 'opX'),
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','opX'),
  'same op + same validated inputs replays the SAME pin_session id');                                                       -- 1
select is((select count(*) from pin_sessions where local_operation_id = 'opX')::int, 1,
  'no duplicate pin_session is created for the same operation');                                                            -- 2

-- ===== 2. same op + WRONG verifier does NOT return the existing session ======
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','opY');  -- create opY (resets A's counter)
select ok(
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:WRONG','opY') is null,
  'same op + WRONG verifier returns NULL (does NOT replay the existing session)');                                          -- 3
select is(
  (select failed_attempt_count from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef0a0' and device_id='00000000-0000-0000-0000-00000000da11')::int, 1,
  'the wrong-verifier replay attempt still increments the failed-attempt counter');                                         -- 4
select is((select count(*) from pin_sessions where local_operation_id = 'opY')::int, 1,
  'no new pin_session is created by the wrong-verifier replay attempt');                                                    -- 5

-- ===== 3. same op while LOCKED is rejected (no replay) =======================
update pin_attempt_states set locked_until = now() + interval '10 minutes'
  where employee_profile_id='00000000-0000-0000-0000-0000000ef0a0' and device_id='00000000-0000-0000-0000-00000000da11';
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','opX') $$, '42501', NULL,
  'same op while LOCKED is rejected (42501) even with the correct verifier — no replay');                                   -- 6
update pin_attempt_states set locked_until = null
  where employee_profile_id='00000000-0000-0000-0000-0000000ef0a0' and device_id='00000000-0000-0000-0000-00000000da11';

-- ===== 4. same op after device/session/pairing revocation is rejected =======
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a2','00000000-0000-0000-0000-0000000ef0a0','ref:A','opX') $$, '42501', NULL,
  'same op on an INACTIVE device session is rejected (42501) — no replay');                                                 -- 7
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a3','00000000-0000-0000-0000-0000000ef0a0','ref:A','opX') $$, '42501', NULL,
  'same op on a REVOKED device session is rejected (42501) — no replay');                                                   -- 8
select is((select count(*) from pin_sessions where local_operation_id = 'opX')::int, 1,
  'the rejected revocation replays created no extra session (A''s original opX remains the only one)');                     -- 9

-- ===== 5. same op + DIFFERENT employee cannot return another user's session ==
-- employee B is valid + correct verifier, but the replay is scoped by employee, so
-- it finds no B-session for opX; the insert then collides on the device-session
-- idempotency index (23505) => safe rejection, NOT A's session.
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0b0','ref:B','opX') $$, '23505', NULL,
  'same op + different employee is safely rejected (never returns another user''s session)');                              -- 10
select is(
  (select employee_profile_id from pin_sessions where local_operation_id = 'opX'),
  '00000000-0000-0000-0000-0000000ef0a0'::uuid,
  'the opX session still belongs to employee A (B could not hijack or be returned it)');                                    -- 11

select * from finish();
rollback;
