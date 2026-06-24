-- ============================================================================
-- RF-123 — pgTAP: public.start_pin_session is a SAFE, narrow wrapper over
--          app.start_pin_session (API_CONTRACT §4.21, DECISION D-029, T-012).
-- ============================================================================
-- public.start_pin_session exists, returns a bare uuid, is SECURITY INVOKER,
-- search_path-locked, callable by `authenticated` but NOT by public/anon.
-- Behaviourally it delegates VERBATIM to app.start_pin_session (the source of
-- truth, RF-051): a matching verifier returns a uuid; a keyed replay returns the
-- same uuid; the wrapper equals the inner call for the same keyed op; a wrong PIN
-- returns NULL (and persists the failed-attempt increment); and structural /
-- precondition / lockout failures raise 42501 — all unchanged through the
-- wrapper. Finally, NO broad `app` exposure regression (only the authorized
-- wrappers live in `public`).
--
-- Fixtures inserted as the BYPASSRLS connection role (RF-051/RF-064 pattern);
-- the start_pin_session calls run as the connection role (the owner has EXECUTE
-- on app.start_pin_session). T-012 requires >= 2 orgs and >= 2 users: Org A (a
-- full valid chain) and Org B (a distinct org + user/employee for cross-org).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(17);

-- ---- Org A: full valid chain --------------------------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf123-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
-- the valid, active backing device session
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
-- a SECOND, REVOKED/inactive device session in Org A (for the revoked-session 42501 case)
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', false, now());
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'rf123-a@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-0000000ab0a1', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a0', 'cashier');  -- org-wide (covers any scope)
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef0a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000ab0a1', 'ref:A');

-- ---- Org B: a distinct org + user/employee (for the cross-org 42501 case) ------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf123-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000b1c1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000bb', 'rf123-b@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-0000000ab0b1', '00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000b0', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef0b0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1c1', '00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000ab0b1', 'ref:B');

-- ============================================================================
-- (A) STRUCTURE / SIGNATURE  (1-4)
-- ============================================================================
select has_function('public', 'start_pin_session',
  array['uuid','uuid','text','text'],
  'public.start_pin_session(uuid, uuid, text, text) exists with the exact 4-arg signature');

select is(
  (select format_type(prorettype, null) from pg_proc
     where proname = 'start_pin_session' and pronamespace = 'public'::regnamespace and pronargs = 4),
  'uuid',
  'public.start_pin_session returns a bare uuid (no richer/composite return)');

select is(
  (select prosecdef from pg_proc
     where proname = 'start_pin_session' and pronamespace = 'public'::regnamespace and pronargs = 4),
  false,
  'public.start_pin_session is SECURITY INVOKER (prosecdef = false)');

select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname = 'start_pin_session' and p.pronamespace = 'public'::regnamespace and p.pronargs = 4
       and cfg like 'search_path=%')),
  'public.start_pin_session has a locked search_path');

-- ============================================================================
-- (B) GRANT POSTURE (T-012): authenticated only; never anon/public  (5-8)
-- ============================================================================
select ok(
  has_function_privilege('authenticated', 'public.start_pin_session(uuid, uuid, text, text)', 'execute'),
  'authenticated MAY execute public.start_pin_session');
select ok(
  not has_function_privilege('anon', 'public.start_pin_session(uuid, uuid, text, text)', 'execute'),
  'anon may NOT execute public.start_pin_session');
select ok(
  not has_function_privilege('public', 'public.start_pin_session(uuid, uuid, text, text)', 'execute'),
  'PUBLIC may NOT execute public.start_pin_session (revoked)');
-- the `app` schema stays UNEXPOSED: no broad app exposure leaked into public
select hasnt_function('public', 'sync_push',
  'no broad app exposure regression: app.* stays unexposed (no public.sync_push sibling)');

-- ============================================================================
-- (C) FAITHFUL PASS-THROUGH SEMANTICS  (9-14)
-- ============================================================================
-- 9. happy path: matching verifier 'ref:A' => non-null uuid (resets attempt state)
select ok(
  public.start_pin_session(
    '00000000-0000-0000-0000-0000000005a1',
    '00000000-0000-0000-0000-0000000ef0a0',
    'ref:A', 'op-happy') is not null,
  'happy path: wrapper returns a non-null uuid for a matching verifier');

-- 10. idempotent replay: same validated op via the wrapper returns the SAME uuid
select is(
  public.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-idem'),
  public.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-idem'),
  'idempotent replay through the wrapper returns the same session uuid');

-- 11. wrapper-vs-inner equivalence: same keyed op => same row (wrapper creates, inner replays)
select is(
  public.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-equiv'),
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-equiv'),
  'wrapper delegates verbatim: same uuid as app.start_pin_session for the same keyed op');

-- 12. wrong PIN => NULL (no row, no error); persists the failed-attempt increment
select ok(
  public.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:WRONG','op-wrong') is null,
  'wrong PIN through the wrapper returns NULL (no row, no error)');

-- 13. wrong PIN incremented the durable attempt counter
select ok(
  (select failed_attempt_count from pin_attempt_states
     where organization_id     = '00000000-0000-0000-0000-0000000000a0'
       and employee_profile_id = '00000000-0000-0000-0000-0000000ef0a0'
       and device_id           = '00000000-0000-0000-0000-00000000da11') >= 1,
  'wrong PIN through the wrapper persists a failed-attempt increment (existing behavior preserved)');

-- 14. cross-org: an Org B employee on an Org A device session => 42501 (extends T-001)
select throws_ok(
  $$ select public.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0b0','ref:B','op-xorg') $$,
  '42501', NULL, 'cross-org employee on an Org A device session raises 42501 through the wrapper');

-- ============================================================================
-- (D) STRUCTURAL / PRECONDITION / LOCKOUT => 42501  (15-17)
-- ============================================================================
-- 15. revoked / inactive backing device session
select throws_ok(
  $$ select public.start_pin_session('00000000-0000-0000-0000-0000000005a2','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-revsess') $$,
  '42501', NULL, 'revoked/inactive device session raises 42501 through the wrapper');

-- 16. unknown device session
select throws_ok(
  $$ select public.start_pin_session('00000000-0000-0000-0000-00000000dead','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-nosess') $$,
  '42501', NULL, 'unknown device session raises 42501 through the wrapper');

-- 17. LOCKOUT (deterministic): seed an ACTIVE lock directly as the BYPASSRLS
--     connection role (on conflict, a row already exists from the op-wrong
--     increment), then assert the next call raises 42501. This avoids any
--     dependency on the attempt-cap value or on assertion ordering.
--     pin_attempt_states unique key = (organization_id, employee_profile_id, device_id);
--     id defaults via gen_random_uuid(); locked_until is the lock gate (rf051:402-409).
insert into pin_attempt_states
    (organization_id, restaurant_id, branch_id, employee_profile_id, device_id, failed_attempt_count, locked_until)
  values ('00000000-0000-0000-0000-0000000000a0',
          '00000000-0000-0000-0000-0000000000a1',
          '00000000-0000-0000-0000-00000000a1b1',
          '00000000-0000-0000-0000-0000000ef0a0',
          '00000000-0000-0000-0000-00000000da11',
          app.pin_max_failed_attempts(),
          now() + interval '1 hour')
  on conflict (organization_id, employee_profile_id, device_id) do update
    set failed_attempt_count = excluded.failed_attempt_count,
        locked_until         = excluded.locked_until;
select throws_ok(
  $$ select public.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','op-postlock') $$,
  '42501', NULL, 'a call made while the PIN is locked on this device raises 42501 through the wrapper');

select * from finish();
rollback;
