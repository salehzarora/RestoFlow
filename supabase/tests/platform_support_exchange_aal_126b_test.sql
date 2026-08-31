-- ============================================================================
-- ADMIN-126B2 — pgTAP: the support-handoff AAL MODEL threat matrix.
--
-- aal2 is proven at START (admin origin); the one-time token carries that
-- proof across origins; EXCHANGE binds to the same operator with a live grant
-- and works at aal1 (the Dashboard origin has no MFA). Everything an attacker
-- could try with a stolen or replayed token stays fail-closed 42501.
--
-- Fixture (UTC; hex-only UUIDs prefix c7): Org A; operator with an active
-- platform grant; a second operator with their OWN active grant (the
-- different-operator probe must not fail for the wrong reason); a tenant
-- org_owner (never an operator).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(14);

insert into organizations (id, name, slug, default_currency) values
  ('c7000000-0000-0000-0000-0000000000a0', 'Aal A', 'aal126b-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('c7000000-0000-0000-0000-0000000000a1', 'c7000000-0000-0000-0000-0000000000a0', 'Rest A', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('c7000000-0000-0000-0000-00000000a1b1', 'c7000000-0000-0000-0000-0000000000a0', 'c7000000-0000-0000-0000-0000000000a1', 'B1', 'UTC');
insert into auth.users (id, email) values
  ('c7000000-0000-0000-0000-00000000adf0', 'aal-op@example.test'),
  ('c7000000-0000-0000-0000-00000000adf2', 'aal-op2@example.test'),
  ('c7000000-0000-0000-0000-00000000adf1', 'aal-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('c7000000-0000-0000-0000-00000000ee0f', 'aal-op@example.test',    'c7000000-0000-0000-0000-00000000adf0'),
  ('c7000000-0000-0000-0000-00000000ee02', 'aal-op2@example.test',   'c7000000-0000-0000-0000-00000000adf2'),
  ('c7000000-0000-0000-0000-00000000ee0e', 'aal-owner@example.test', 'c7000000-0000-0000-0000-00000000adf1');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('c7000000-0000-0000-0000-0000000000e1', 'c7000000-0000-0000-0000-00000000ee0f', 'active',
   'c7000000-0000-0000-0000-00000000ee0f'),
  ('c7000000-0000-0000-0000-0000000000e4', 'c7000000-0000-0000-0000-00000000ee02', 'active',
   'c7000000-0000-0000-0000-00000000ee0f');
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('c7000000-0000-0000-0000-0000000000e2', 'c7000000-0000-0000-0000-00000000ee0e',
   'c7000000-0000-0000-0000-0000000000a0', 'org_owner', 'active');

-- ===========================================================================
-- S. START still demands aal2 (unchanged anchor)
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c7000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok(
  $$ select public.platform_admin_start_support_session('c7000000-0000-0000-0000-0000000000a0', null, 'aal1 start probe') $$,
  '42501', null,
  'S1. START without aal2 is refused - the anchor is unchanged');

-- start properly at aal2 (admin origin)
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table t1 as select public.platform_admin_start_support_session(
  'c7000000-0000-0000-0000-0000000000a0', null, 'cross-origin handoff') as res;
grant select on t1 to public;  -- the anon probe below must read the token

-- ===========================================================================
-- T. EXCHANGE at the DASHBOARD origin (aal1) - the fix and its boundaries
-- ===========================================================================
-- unauthenticated exchange
reset role;
set local role anon;
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$, (select res ->> 'handoff_token' from t1)),
  '42501', null,
  'T1. an UNAUTHENTICATED dashboard cannot exchange (anon has no execute anyway)');
reset role;

-- a DIFFERENT operator, even at aal2, holding the stolen token
set local role authenticated;
set local request.jwt.claim.sub = 'c7000000-0000-0000-0000-00000000adf2';
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf2","aal":"aal2"}';
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$, (select res ->> 'handoff_token' from t1)),
  '42501', null,
  'T2. a STOLEN token is useless to another operator - identity binding holds');

-- the tenant owner holding the stolen token
set local request.jwt.claim.sub = 'c7000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf1","aal":"aal2"}';
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$, (select res ->> 'handoff_token' from t1)),
  '42501', null,
  'T3. ...and to a tenant member with no platform grant');

-- the SAME operator at the dashboard origin: aal1 (no Dashboard MFA exists)
set local request.jwt.claim.sub = 'c7000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
create temp table x1 as select public.platform_support_exchange(
  (select res ->> 'handoff_token' from t1)) as res;
select is((select res ->> 'ok' from x1), 'true',
  'T4. THE FIX: the same operator exchanges at aal1 - aal2 was proven at start');
select is((select res ->> 'read_only' from x1), 'true',
  'T5. the exchanged session is read-only');

-- replay
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$, (select res ->> 'handoff_token' from t1)),
  '42501', null,
  'T6. REPLAY of a spent token is refused');

-- reads + end work under the aal1 dashboard session
select is(public.list_org_structure('c7000000-0000-0000-0000-0000000000a0') ->> 'ok', 'true',
  'T7. approved reads work for the aal1 dashboard session');
select is(public.platform_support_current() ->> 'active', 'true',
  'T8. the status poll sees the live session');
select is(public.platform_support_end(null) ->> 'ended', 'true',
  'T9. End Support Access works at aal1');

-- ===========================================================================
-- W. EXCHANGE WINDOW + GRANT REVOCATION (still fail-closed)
-- ===========================================================================
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table t2 as select public.platform_admin_start_support_session(
  'c7000000-0000-0000-0000-0000000000a0', null, 'window probe') as res;
reset role;
update platform_support_sessions
   set created_at = now() - interval '2 minutes'
 where status = 'pending';
set local role authenticated;
set local request.jwt.claim.sub = 'c7000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$, (select res ->> 'handoff_token' from t2)),
  '42501', null,
  'W1. a token past its 60-second exchange window is dead');

set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table t3 as select public.platform_admin_start_support_session(
  'c7000000-0000-0000-0000-0000000000a0', null, 'revocation probe') as res;
reset role;
update platform_admin_grants set status = 'revoked'
 where id = 'c7000000-0000-0000-0000-0000000000e1';
set local role authenticated;
set local request.jwt.claim.sub = 'c7000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c7000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$, (select res ->> 'handoff_token' from t3)),
  '42501', null,
  'W2. a grant revoked between start and exchange closes the door');
reset role;
update platform_admin_grants set status = 'active'
 where id = 'c7000000-0000-0000-0000-0000000000e1';

-- ===========================================================================
-- X. STRUCTURE: the deployed predicate matches the model
-- ===========================================================================
select ok(
  (select prosrc not like '%aal2%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'platform_support_exchange'),
  'X1. exchange no longer references aal - the anchor lives at start');
select ok(
  (select prosrc like '%aal2%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'platform_admin_guard'),
  'X2. the start-path guard still demands aal2');

select * from finish();
rollback;
