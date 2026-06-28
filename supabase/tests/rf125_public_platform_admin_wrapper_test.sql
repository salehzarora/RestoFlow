-- ============================================================================
-- RF-125 — pgTAP: public.platform_admin_* are SAFE, narrow wrappers over the
-- RF-091 app platform-admin RPCs (PROPOSED DECISION D-035, T-007/T-008, R-003).
-- ============================================================================
-- For each of the three wrappers (organization_overview / get_organization /
-- recent_audit): it exists, returns jsonb, is SECURITY INVOKER, search_path-locked,
-- callable by `authenticated` but NOT by public/anon. Behaviourally it delegates
-- verbatim to the app.* source of truth: identical jsonb for a credentialed
-- platform admin, and the SAME 42501 deny through the wrapper for a non-admin, a
-- tenant org_owner (grant != membership, T-008/T-009), a blank/null reason, and a
-- missing aal2 MFA claim (the entire app.platform_admin_guard is preserved — the
-- wrapper adds no bypass). Finally, NO sibling platform-admin RPC was given an
-- unintended public wrapper.
--
-- Fixtures inserted as the BYPASSRLS connection role; the credentialed calls run
-- as `authenticated` with a request.jwt.claims (sub + aal) session, mirroring
-- rf091_denial_test / rf091_mfa_test.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(34);

-- ===== fixture: an org + restaurant; a platform admin (active grant), a tenant =
-- ===== org_owner (membership, NO grant), and a non-member nobody ===============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf125w-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000adf0', 'rf125w-admin@example.test'),
  ('00000000-0000-0000-0000-00000000ad01', 'rf125w-owner@example.test'),
  ('00000000-0000-0000-0000-00000000ad09', 'rf125w-nobody@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf125w-admin@example.test', '00000000-0000-0000-0000-00000000adf0'),
  ('00000000-0000-0000-0000-00000000ee01', 'rf125w-owner@example.test', '00000000-0000-0000-0000-00000000ad01'),
  ('00000000-0000-0000-0000-00000000ee09', 'rf125w-nobody@example.test', '00000000-0000-0000-0000-00000000ad09');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'active', '00000000-0000-0000-0000-00000000ee0f');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', 'org_owner');

-- ===== (1-12) introspection: existence / return type / INVOKER / search_path ===
select has_function('public', 'platform_admin_organization_overview', array['text'],         'public.platform_admin_organization_overview(text) exists');
select has_function('public', 'platform_admin_get_organization',      array['uuid','text'],   'public.platform_admin_get_organization(uuid, text) exists');
select has_function('public', 'platform_admin_recent_audit',          array['text','integer'],'public.platform_admin_recent_audit(text, integer) exists');

select is((select format_type(prorettype, null) from pg_proc where proname='platform_admin_organization_overview' and pronamespace='public'::regnamespace), 'jsonb', 'overview wrapper returns jsonb');
select is((select format_type(prorettype, null) from pg_proc where proname='platform_admin_get_organization'      and pronamespace='public'::regnamespace), 'jsonb', 'get_organization wrapper returns jsonb');
select is((select format_type(prorettype, null) from pg_proc where proname='platform_admin_recent_audit'          and pronamespace='public'::regnamespace), 'jsonb', 'recent_audit wrapper returns jsonb');

select is((select prosecdef from pg_proc where proname='platform_admin_organization_overview' and pronamespace='public'::regnamespace), false, 'overview wrapper is SECURITY INVOKER (not definer)');
select is((select prosecdef from pg_proc where proname='platform_admin_get_organization'      and pronamespace='public'::regnamespace), false, 'get_organization wrapper is SECURITY INVOKER (not definer)');
select is((select prosecdef from pg_proc where proname='platform_admin_recent_audit'          and pronamespace='public'::regnamespace), false, 'recent_audit wrapper is SECURITY INVOKER (not definer)');

select ok((select exists(select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg where p.proname='platform_admin_organization_overview' and p.pronamespace='public'::regnamespace and cfg like 'search_path=%')), 'overview wrapper has a locked search_path');
select ok((select exists(select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg where p.proname='platform_admin_get_organization'      and p.pronamespace='public'::regnamespace and cfg like 'search_path=%')), 'get_organization wrapper has a locked search_path');
select ok((select exists(select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg where p.proname='platform_admin_recent_audit'          and p.pronamespace='public'::regnamespace and cfg like 'search_path=%')), 'recent_audit wrapper has a locked search_path');

-- ===== (13-21) grants: PUBLIC/anon may NOT execute; authenticated MAY ==========
select ok(not has_function_privilege('public', 'public.platform_admin_organization_overview(text)',        'execute'), 'PUBLIC may NOT execute overview wrapper (revoked)');
select ok(not has_function_privilege('anon',   'public.platform_admin_organization_overview(text)',        'execute'), 'anon may NOT execute overview wrapper');
select ok(    has_function_privilege('authenticated', 'public.platform_admin_organization_overview(text)', 'execute'), 'authenticated MAY execute overview wrapper');
select ok(not has_function_privilege('public', 'public.platform_admin_get_organization(uuid, text)',        'execute'), 'PUBLIC may NOT execute get_organization wrapper (revoked)');
select ok(not has_function_privilege('anon',   'public.platform_admin_get_organization(uuid, text)',        'execute'), 'anon may NOT execute get_organization wrapper');
select ok(    has_function_privilege('authenticated', 'public.platform_admin_get_organization(uuid, text)', 'execute'), 'authenticated MAY execute get_organization wrapper');
select ok(not has_function_privilege('public', 'public.platform_admin_recent_audit(text, integer)',         'execute'), 'PUBLIC may NOT execute recent_audit wrapper (revoked)');
select ok(not has_function_privilege('anon',   'public.platform_admin_recent_audit(text, integer)',         'execute'), 'anon may NOT execute recent_audit wrapper');
select ok(    has_function_privilege('authenticated', 'public.platform_admin_recent_audit(text, integer)',  'execute'), 'authenticated MAY execute recent_audit wrapper');

-- ===== (22) guard: no OTHER platform-admin RPC got an unintended public sibling =
select hasnt_function('public', 'platform_admin_list_organizations', 'no public.platform_admin_list_organizations wrapper exists (only the 3 RF-091 panel RPCs are wrapped)');

set local role authenticated;

-- ===== (23-28) credentialed platform admin (grant + aal2 + reason): the wrapper =
-- ===== delegates verbatim — ok:true and byte-identical jsonb to the app RPC =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select is((public.platform_admin_organization_overview('rf125 control') ->> 'ok')::boolean, true, 'platform admin via wrapper: overview ok');
select is((public.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','rf125 control') ->> 'ok')::boolean, true, 'platform admin via wrapper: get_organization ok');
select is((public.platform_admin_recent_audit('rf125 control', 10) ->> 'ok')::boolean, true, 'platform admin via wrapper: recent_audit ok');
select is(
  public.platform_admin_organization_overview('rf125 eq'),
  app.platform_admin_organization_overview('rf125 eq'),
  'overview: public wrapper delegates verbatim — identical jsonb to app.platform_admin_organization_overview');
select is(
  public.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','rf125 eq'),
  app.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','rf125 eq'),
  'get_organization: public wrapper delegates verbatim — identical jsonb to the app RPC');
select is(jsonb_typeof(public.platform_admin_recent_audit('rf125 eq', 5) -> 'events'), 'array', 'recent_audit via wrapper: events is a jsonb array');

-- ===== (29) non-platform user (no grant, aal2) denied through the wrapper ======
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad09';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad09","aal":"aal2"}';
select throws_ok($$ select public.platform_admin_organization_overview('x') $$, '42501', null, 'non-platform user denied through public.platform_admin_organization_overview (guard preserved)');

-- ===== (30-31) tenant org_owner (membership, NO grant, aal2) denied: T-008 =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad01';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad01","aal":"aal2"}';
select throws_ok($$ select public.platform_admin_organization_overview('try') $$, '42501', null, 'T-008: org_owner cannot reach the platform overview via the wrapper (grant != membership)');
select throws_ok($$ select public.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','try') $$, '42501', null, 'T-008: org_owner cannot reach platform detail via the wrapper');

-- ===== (32-33) reason required, enforced inside the unchanged app body =========
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select throws_ok($$ select public.platform_admin_organization_overview('') $$, '42501', null, 'blank reason denied through the wrapper');
select throws_ok($$ select public.platform_admin_organization_overview(null) $$, '42501', null, 'null reason denied through the wrapper');

-- ===== (34) MFA aal2 gate preserved: admin WITHOUT an aal2 claim is denied =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0"}';
select throws_ok($$ select public.platform_admin_organization_overview('no mfa') $$, '42501', null, 'platform admin WITHOUT aal2 denied through the wrapper (MFA gate preserved)');

select * from finish();
rollback;
