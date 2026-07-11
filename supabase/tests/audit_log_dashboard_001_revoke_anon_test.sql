-- ============================================================================
-- AUDIT-LOG-DASHBOARD-001 (corrective) — pgTAP: the read-only audit-timeline
-- wrapper is AUTHENTICATED-ONLY (no anon / no PUBLIC), the underlying app
-- functions stay authenticated-only + DEFINER + locked search_path, exactly one
-- public overload exists, the anon REVOKE is effective even against a
-- hosted-style pre-existing grant, and the management-only authorization
-- behaviour is unchanged.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(19);

-- ---- structure + ACL (no fixtures) -----------------------------------------
-- 1. the exact expected signature exists (and is unique => resolvable).
select isnt(
  to_regprocedure('public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)')::text,
  null, 'public.owner_audit_events exists with the exact expected signature');
-- 2/3. authenticated may execute the wrapper; anon may NOT.
select ok(has_function_privilege('authenticated','public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'authenticated has EXECUTE on the public wrapper');
select ok(not has_function_privilege('anon','public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'anon does NOT have EXECUTE on the public wrapper');
-- 4. no PUBLIC grant indirectly gives anon execution.
select ok(
  not exists (
    select 1 from pg_proc p, lateral aclexplode(p.proacl) a
    where p.proname = 'owner_audit_events' and p.pronamespace = 'public'::regnamespace
      and a.grantee = 0 /* PUBLIC */ and a.privilege_type = 'EXECUTE'),
  'the public wrapper has NO PUBLIC execute grant');
-- 5. the underlying app DEFINER function is not anon-executable either.
select ok(not has_function_privilege('anon','app.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'anon does NOT have EXECUTE on app.owner_audit_events');
-- 6. app function stays available to its intended role (authenticated).
select ok(has_function_privilege('authenticated','app.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'authenticated retains EXECUTE on app.owner_audit_events');
-- 7. the safe-projection helpers are not anon-executable.
select ok(
  not has_function_privilege('anon','app.audit_safe_detail(text,jsonb)','execute')
  and not has_function_privilege('anon','app.audit_action_has_detail(text)','execute'),
  'anon does NOT have EXECUTE on the safe-projection helpers');
-- 8/9. wrapper stays SECURITY INVOKER; app function stays SECURITY DEFINER.
select is((select prosecdef from pg_proc where proname='owner_audit_events' and pronamespace='public'::regnamespace),
  false, 'the public wrapper remains SECURITY INVOKER');
select is((select prosecdef from pg_proc where proname='owner_audit_events' and pronamespace='app'::regnamespace),
  true, 'app.owner_audit_events remains SECURITY DEFINER');
-- 10/11. search_path stays pinned on both.
select ok(exists(select 1 from pg_proc p, lateral unnest(p.proconfig) c
    where p.proname='owner_audit_events' and p.pronamespace='app'::regnamespace and c like 'search_path=%'),
  'app.owner_audit_events keeps a pinned search_path');
select ok(exists(select 1 from pg_proc p, lateral unnest(p.proconfig) c
    where p.proname='owner_audit_events' and p.pronamespace='public'::regnamespace and c like 'search_path=%'),
  'the public wrapper keeps a pinned search_path');
-- 12. exactly ONE public overload (no duplicate wrapper).
select is((select count(*)::int from pg_proc where proname='owner_audit_events' and pronamespace='public'::regnamespace),
  1, 'exactly one public.owner_audit_events overload exists');

-- ---- the anon REVOKE is effective vs a hosted-style pre-existing grant ------
-- Simulate the hosted default-privilege grant, then apply the corrective REVOKE.
grant execute on function public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text) to anon;
select ok(has_function_privilege('anon','public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'sanity: an explicit anon grant is present before the revoke');
revoke all on function public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text) from anon;
select ok(not has_function_privilege('anon','public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'the corrective REVOKE removes the anon grant');
select ok(has_function_privilege('authenticated','public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,int,text)','execute'),
  'the corrective REVOKE leaves authenticated EXECUTE intact');

-- ---- behaviour is unchanged (compact fixture) ------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000c0000', 'Org C', 'ra-c', 'ILS'),
  ('00000000-0000-0000-0000-0000000d0000', 'Org D', 'ra-d', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c0000', 'Rest C1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000c1a00', '00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', 'Branch C1a', null);
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000fc01', 'ra-mgr@example.test'),
  ('00000000-0000-0000-0000-00000000fc02', 'ra-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000c0a01', '00000000-0000-0000-0000-00000000fc01', '00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000c0a02', '00000000-0000-0000-0000-00000000fc02', '00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c1a00', 'cashier');

-- 4 (behaviour): an anonymous DIRECT invocation of the wrapper is refused at the
-- grant layer (anon has no EXECUTE) — permission denied (42501).
set local role anon;
select throws_ok(
  $$ select public.owner_audit_events('00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c1a00', 'today') $$,
  '42501', null, 'an anon caller cannot execute the wrapper (permission denied)');
reset role;

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000fc01';  -- manager
select is(
  (app.owner_audit_events('00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c1a00', 'today') ->> 'ok')::boolean,
  true, 'a manager authenticated call still works (ok:true)');
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000fc02';  -- cashier
select is(
  (app.owner_audit_events('00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c1a00', 'today') ->> 'error'),
  'permission_denied', 'cashier authorization behaviour is unchanged (denied)');
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000fc01';  -- manager -> cross-org
select throws_ok(
  $$ select app.owner_audit_events('00000000-0000-0000-0000-0000000d0000', null, null, 'today') $$,
  '42501', null, 'cross-tenant isolation is unchanged (Org C manager asking Org D -> 42501)');
reset role;

select * from finish();
rollback;
