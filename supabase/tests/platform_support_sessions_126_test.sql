-- ============================================================================
-- ADMIN-126 — pgTAP: secure, audited, READ-ONLY platform support access.
--
-- Two groups carry the security argument and everything else supports them:
--
--   R  — READ-ONLY IS STRUCTURAL. Representative mutations from every family
--        the Dashboard exposes (menu, staff/membership, org settings, device,
--        printer, orders via sync_push, onboarding) are attempted BY A LIVE
--        SUPPORT OPERATOR and every one is refused by the SERVER. Nothing here
--        depends on a hidden button.
--
--   N  — NOTHING CHANGES WITHOUT A SESSION. The two extended read helpers are
--        re-checked against an ordinary tenant with no support session, so the
--        additive branch cannot quietly alter tenant authorization (RISK R-003).
--
-- Plus the structural invariants the design rests on: every RLS policy that
-- consults those helpers is FOR SELECT, and no function that writes a public
-- table consults them. If either stops being true, this file fails — which is
-- the only way "support mode is read-only" can keep meaning something.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(57);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency, status) values
  ('c3000000-0000-0000-0000-0000000000a0', 'Alpha Group', 'sup126-a', 'ILS', 'active'),
  ('c3000000-0000-0000-0000-0000000000b0', 'Bravo Ltd',   'sup126-b', 'EUR', 'active');
insert into restaurants (id, organization_id, name, timezone) values
  ('c3000000-0000-0000-0000-0000000000a1', 'c3000000-0000-0000-0000-0000000000a0', 'Alpha One', 'UTC'),
  ('c3000000-0000-0000-0000-0000000000b1', 'c3000000-0000-0000-0000-0000000000b0', 'Bravo One', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('c3000000-0000-0000-0000-0000000000c1', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1', 'A1 Main', null),
  ('c3000000-0000-0000-0000-0000000000c2', 'c3000000-0000-0000-0000-0000000000b0', 'c3000000-0000-0000-0000-0000000000b1', 'B1 Main', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c3000000-0000-0000-0000-0000000000d1', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1', 'c3000000-0000-0000-0000-0000000000c1', 'pos');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('c3000000-0000-0000-0000-0000000000f1', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1', 'c3000000-0000-0000-0000-0000000000c1', 'Mains', 1);

insert into auth.users (id, email) values
  ('c3000000-0000-0000-0000-00000000adf0', 'sup-operator@example.test'),
  ('c3000000-0000-0000-0000-00000000adf1', 'sup-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('c3000000-0000-0000-0000-00000000ee0f', 'sup-operator@example.test', 'c3000000-0000-0000-0000-00000000adf0'),
  ('c3000000-0000-0000-0000-00000000ee0e', 'sup-owner@example.test',    'c3000000-0000-0000-0000-00000000adf1');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('c3000000-0000-0000-0000-0000000000e1', 'c3000000-0000-0000-0000-00000000ee0f', 'active',
   'c3000000-0000-0000-0000-00000000ee0f');
-- An ordinary org_owner of Alpha, with NO platform grant. Used for group N.
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('c3000000-0000-0000-0000-0000000000e2', 'c3000000-0000-0000-0000-00000000ee0e',
   'c3000000-0000-0000-0000-0000000000a0', 'org_owner', 'active');

-- ===========================================================================
-- S. START + EXCHANGE
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c3000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-00000000adf0","aal":"aal2"}';

create temp table started as select public.platform_admin_start_support_session(
  'c3000000-0000-0000-0000-0000000000a0', null,
  'Owner reports missing sales for today') as res;

select ok((select res ->> 'handoff_token' from started) ~ '^[0-9a-f]{64}$',
  'S1. start returns a 32-byte random handoff token, hex-encoded');
select ok((select (res ->> 'expires_at')::timestamptz from started) > now() + interval '10 minutes',
  'S2. the session TTL is server-set and generous enough to be useful');
select ok((select (res ->> 'expires_at')::timestamptz from started) <= now() + interval '15 minutes',
  'S3. ...and short enough to be safe (<= 15 minutes)');
select ok((select (res ->> 'exchange_expires_at')::timestamptz from started) <= now() + interval '61 seconds',
  'S4. the EXCHANGE window is far shorter than the session (~60s)');

-- The plaintext must exist nowhere on the server.
reset role;
select is(
  (select count(*)::int from platform_support_sessions s, started
    where s.token_hash = (started.res ->> 'handoff_token')),
  0, 'S5. the PLAINTEXT token is not stored — a database dump cannot be replayed');
select is(
  (select count(*)::int from platform_support_sessions s, started
    where s.token_hash = encode(digest(started.res ->> 'handoff_token', 'sha256'), 'hex')),
  1, 'S6. only its SHA-256 hash is stored');
select is((select status from platform_support_sessions), 'pending',
  'S7. a started session is PENDING until the token is exchanged');
select ok((select token_consumed_at is null from platform_support_sessions),
  'S8. and unconsumed');
-- The operator gains nothing until the exchange happens.
select is((select count(*)::int from memberships
            where app_user_id = 'c3000000-0000-0000-0000-00000000ee0f'),
  0, 'S9. NO membership row is created — not permanently and not temporarily');

set local role authenticated;
set local request.jwt.claim.sub = 'c3000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table exchanged as select public.platform_support_exchange(
  (select res ->> 'handoff_token' from started)) as res;
select is((select res ->> 'ok' from exchanged), 'true', 'S10. the token exchanges once');
select is((select res -> 'organization' ->> 'name' from exchanged), 'Alpha Group',
  'S11. and names the tenant being supported');
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$,
         (select res ->> 'handoff_token' from started)),
  '42501', NULL, 'S12. REPLAY of the same token is refused');
select throws_ok(
  $$ select public.platform_support_exchange('deadbeef') $$,
  '42501', NULL, 'S13. an unknown token is refused with the SAME error as a replay');
select throws_ok(
  $$ select public.platform_support_exchange('   ') $$,
  '42501', NULL, 'S14. a blank token is refused');

-- ===========================================================================
-- V. THE SUPPORT OPERATOR CAN SEE THE TENANT
-- ===========================================================================
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000a0', true) is not null as _;
select is(app.current_org_id(), 'c3000000-0000-0000-0000-0000000000a0'::uuid,
  'V1. the support session resolves the TARGET organization');
select ok(app.has_scope('c3000000-0000-0000-0000-0000000000a0', null, null),
  'V2. and grants READ scope over it');
select is((select count(*)::int from restaurants), 1,
  'V3. tenant rows are actually readable through RLS (one Alpha restaurant)');
select is((select name from restaurants), 'Alpha One', 'V4. and they are the right tenant''s');
select ok((select active from (select (public.platform_support_current() ->> 'active')::boolean as active) q),
  'V5. the Dashboard can ask whether it is in support mode');
select is(public.platform_support_current() ->> 'read_only', 'true',
  'V6. and is told, by the SERVER, that the session is read-only');

-- Cross-tenant: the session is for Alpha and grants nothing anywhere else.
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000b0', true) is not null as _;
select is(app.current_org_id(), null,
  'V7. a session for Alpha resolves NOTHING for Bravo');
select ok(not app.has_scope('c3000000-0000-0000-0000-0000000000b0', null, null),
  'V8. and grants no scope over Bravo');
select is((select count(*)::int from restaurants), 0,
  'V9. so Bravo''s rows stay invisible');
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000a0', true) is not null as _;

-- ===========================================================================
-- R. READ-ONLY IS STRUCTURAL — every write family is refused SERVER-SIDE
-- ===========================================================================
-- app.actor_rank_in_scope is an INTERNAL helper with no `authenticated` grant
-- (which is itself part of the defence), so these two are evaluated outside the
-- role. The JWT claims GUC is still in force, so the identity under test is the
-- same support operator.
reset role;
select ok(app.actor_rank_in_scope('c3000000-0000-0000-0000-0000000000a0', null, null) = 0,
  'R1. the write gate ranks a support operator at ZERO — this is why writes fail');
select ok(not app.has_role_in_scope('c3000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  'R2. and no role is granted in the target scope');
set local role authenticated;

select throws_ok(
  $$ select public.menu_upsert_category('c3000000-0000-0000-0000-0000000000a0','c3000000-0000-0000-0000-0000000000a1','c3000000-0000-0000-0000-0000000000c1',null,'Injected',9,true,null) $$,
  '42501', NULL, 'R3. MENU write refused');
select throws_ok(
  $$ select public.menu_set_item_availability('c3000000-0000-0000-0000-0000000000a0','c3000000-0000-0000-0000-0000000000a1','c3000000-0000-0000-0000-0000000000c1','c3000000-0000-0000-0000-0000000000f1','out_of_stock','x') $$,
  '42501', NULL, 'R4. MENU AVAILABILITY write refused');
select throws_ok(
  $$ select public.grant_membership('c3000000-0000-0000-0000-00000000aa01','c3000000-0000-0000-0000-0000000000a0',null,null,'c3000000-0000-0000-0000-00000000ee0f','org_owner') $$,
  '42501', NULL, 'R5. MEMBERSHIP write refused — a support operator cannot make itself an owner');
select throws_ok(
  $$ select public.create_staff_member('c3000000-0000-0000-0000-00000000aa02','c3000000-0000-0000-0000-0000000000a0','c3000000-0000-0000-0000-0000000000a1','c3000000-0000-0000-0000-0000000000c1','Mallory','cashier',null) $$,
  '42501', NULL, 'R6. STAFF write refused');
select throws_ok(
  $$ select public.set_branch_tax('c3000000-0000-0000-0000-00000000aa03','c3000000-0000-0000-0000-0000000000a0','c3000000-0000-0000-0000-0000000000a1','c3000000-0000-0000-0000-0000000000c1',true,1700) $$,
  '42501', NULL, 'R7. ORG/BRANCH SETTINGS write refused');
select throws_ok(
  $$ select public.set_printer_route('c3000000-0000-0000-0000-0000000000a0','c3000000-0000-0000-0000-0000000000a1','c3000000-0000-0000-0000-0000000000c1',null,null,true) $$,
  '42501', NULL, 'R8. PRINTER/DEVICE CONFIG write refused');
select throws_ok(
  $$ select public.sync_push('c3000000-0000-0000-0000-00000000aa04','c3000000-0000-0000-0000-0000000000d1','[]'::jsonb) $$,
  '42501', NULL, 'R9. ORDER/MONEY writes refused — sync_push needs a PIN session a support operator has not got');
select throws_ok(
  $$ select public.create_organization('c3000000-0000-0000-0000-00000000aa05','New Co','new-co','R','B','ILS','UTC',null) $$,
  '42501', NULL, 'R10. ONBOARDING refused — the one write path not gated on a membership says no explicitly');

-- Direct table DML, in case a future policy ever widens.
select throws_ok(
  $$ update public.restaurants set name = 'Renamed' $$,
  '42501', NULL, 'R11. a DIRECT table UPDATE is refused');
select throws_ok(
  $$ insert into public.branches (organization_id, restaurant_id, name) values ('c3000000-0000-0000-0000-0000000000a0','c3000000-0000-0000-0000-0000000000a1','Injected') $$,
  '42501', NULL, 'R12. a DIRECT table INSERT is refused');

-- ===========================================================================
-- E. EXPIRY AND END FAIL CLOSED
-- ===========================================================================
reset role;
update platform_support_sessions set expires_at = now() - interval '1 second';
set local role authenticated;
set local request.jwt.claim.sub = 'c3000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000a0', true) is not null as _;
select is((select count(*)::int from restaurants), 0,
  'E1. an EXPIRED session takes the tenant rows away immediately');
select is(app.current_org_id(), null, 'E2. and grants no organization');
reset role;
select is(app.current_support_session(), null, 'E3. the session itself resolves to nothing');
set local role authenticated;

reset role;
update platform_support_sessions set expires_at = now() + interval '10 minutes';
set local role authenticated;
set local request.jwt.claim.sub = 'c3000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000a0', true) is not null as _;
select is((select count(*)::int from restaurants), 1, 'E4. restoring the TTL restores read access');
select is(public.platform_support_end(null) ->> 'ended', 'true', 'E5. End Support Access ends it');
select is((select count(*)::int from restaurants), 0, 'E6. and the tenant goes dark again');
reset role;
select is(app.current_support_session(), null, 'E7. an ENDED session resolves to nothing');
set local role authenticated;
select is(public.platform_support_end(null) ->> 'ended', 'false',
  'E8. ending twice is a no-op, not an error');

-- ===========================================================================
-- N. NOTHING CHANGES FOR A TENANT WITHOUT A SESSION  (RISK R-003)
-- ===========================================================================
reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'c3000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-00000000adf1","aal":"aal1"}';
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000a0', true) is not null as _;
select is(app.current_org_id(), 'c3000000-0000-0000-0000-0000000000a0'::uuid,
  'N1. an ordinary org_owner still resolves their own organization');
select ok(app.has_scope('c3000000-0000-0000-0000-0000000000a0', null, null),
  'N2. and still has scope over it');
reset role;
select ok(app.has_role_in_scope('c3000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  'N3. and still holds their role');
select ok(app.actor_rank_in_scope('c3000000-0000-0000-0000-0000000000a0', null, null) > 0,
  'N4. and can still be authorized to WRITE — the tenant path is untouched');
set local role authenticated;
select set_config('app.current_organization_id', 'c3000000-0000-0000-0000-0000000000b0', true) is not null as _;
select is(app.current_org_id(), null,
  'N5. and still cannot reach a tenant they do not belong to');
reset role;

-- ===========================================================================
-- X. THE STRUCTURAL INVARIANTS THE DESIGN RESTS ON
-- ===========================================================================
select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and cmd <> 'SELECT'
      and (coalesce(qual,'') || coalesce(with_check,'')) ~ 'has_scope|current_org_id'),
  0,
  'X1. EVERY policy consulting the extended read helpers is FOR SELECT — '
  'extending them cannot authorize a write');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ 'app\.(has_scope|current_org_id)\s*\('
      and pg_get_functiondef(p.oid) ~* '(insert into|update |delete from)\s*public\.'),
  0,
  'X2. and no function that WRITES a public table consults them');
select ok(
  (select count(*) from pg_policies
    where schemaname = 'public' and cmd = 'SELECT'
      and (coalesce(qual,'') || coalesce(with_check,'')) ~ 'has_scope|current_org_id') >= 30,
  'X3. non-vacuity: those helpers really do gate the tenant read plane');

-- ===========================================================================
-- G. GRANTS + AUDIT
-- ===========================================================================
select ok(not has_function_privilege('anon', 'public.platform_admin_start_support_session(uuid,uuid,text)', 'EXECUTE'),
  'G1. anon cannot start a support session');
select ok(not has_table_privilege('authenticated', 'public.platform_support_sessions', 'SELECT'),
  'G2. the tenant path cannot even read the support-session table');
select is(
  (select array_agg(distinct action order by action) from platform_admin_audit_events
    where action like 'platform.support.%'),
  array['platform.support.end', 'platform.support.exchange', 'platform.support.start'],
  'G3. start, exchange and end are ALL audited');
select is(
  (select count(distinct actor_app_user_id)::int from platform_admin_audit_events
    where action like 'platform.support.%'),
  1, 'G4. every support event names ONE actor...');
select is(
  (select distinct actor_app_user_id from platform_admin_audit_events
    where action like 'platform.support.%'),
  'c3000000-0000-0000-0000-00000000ee0f'::uuid,
  'G5. ...and it is the PLATFORM OPERATOR, never the restaurant owner');
select ok(
  (select bool_and(coalesce(btrim(reason), '') <> '') from platform_admin_audit_events
    where action like 'platform.support.%'),
  'G6. and every one carries the typed support reason');

select * from finish();
rollback;
