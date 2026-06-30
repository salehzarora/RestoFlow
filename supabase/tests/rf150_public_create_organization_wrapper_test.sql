-- ============================================================================
-- RF-150 — pgTAP: public.create_organization is a SAFE, narrow self-serve
-- ONBOARDING wrapper over app.create_organization (RF-090, API_CONTRACT §4).
-- ============================================================================
-- public.create_organization exists with the 8-arg signature, returns jsonb, is
-- SECURITY INVOKER, search_path-locked, VOLATILE (so PostgREST POST-routes the
-- write), and is callable by `authenticated` but NOT by public/anon. The narrowness
-- guard proves RF-150 exposed ONLY create_organization: the internal replay helper
-- did NOT gain a public sibling, so the `app` schema stays unexposed. Behaviourally
-- it delegates VERBATIM: a fresh authenticated principal who calls
-- public.create_organization provisions a real organization + restaurant + branch +
-- org_owner membership + audit (RF-090 semantics), a retry with the SAME
-- client_request_id returns idempotent_replay without a duplicate, and an
-- unauthenticated caller is rejected with the SAME 42501 as app.create_organization.
--
-- The wrapper is SECURITY INVOKER (runs as `authenticated`); app.create_organization
-- is SECURITY DEFINER (owned by the BYPASSRLS migration role) so it performs the
-- creation the RF-059 deny-policies forbid for direct client INSERT — the RF-090/126
-- pattern.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(20);

-- a fresh Supabase Auth principal (auth.users row, JWT later, NO app_user yet).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000150a0001', 'rf150-owner@example.test');

-- ===== (1-8) introspection: existence / type / INVOKER / search_path / VOLATILE /
-- ===== grants ================================================================
select has_function(
  'public', 'create_organization',
  array['uuid','text','text','text','text','text','text','text'],
  'public.create_organization(uuid, text x7) exists');
select is(
  (select format_type(prorettype, null) from pg_proc where proname='create_organization' and pronamespace='public'::regnamespace),
  'jsonb', 'public.create_organization returns jsonb');
select is(
  (select prosecdef from pg_proc where proname='create_organization' and pronamespace='public'::regnamespace),
  false, 'public.create_organization is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='create_organization' and p.pronamespace='public'::regnamespace
       and cfg like 'search_path=%')),
  'public.create_organization has a locked search_path');
select is(
  (select provolatile from pg_proc where proname='create_organization' and pronamespace='public'::regnamespace),
  'v', 'public.create_organization is VOLATILE (PostgREST POST-routes the write)');
select ok(
  not has_function_privilege('public', 'public.create_organization(uuid, text, text, text, text, text, text, text)', 'execute'),
  'PUBLIC may NOT execute public.create_organization (revoked)');
select ok(
  not has_function_privilege('anon', 'public.create_organization(uuid, text, text, text, text, text, text, text)', 'execute'),
  'anon may NOT execute public.create_organization (no anon signup write)');
select ok(
  has_function_privilege('authenticated', 'public.create_organization(uuid, text, text, text, text, text, text, text)', 'execute'),
  'authenticated MAY execute public.create_organization');

-- ===== (9) narrowness: the internal replay helper did NOT gain a public sibling
select hasnt_function('public', 'create_organization_replay',
  'no public.create_organization_replay wrapper (internal helper stays app-only)');

-- ===== (10) the WHOLE gate is preserved through the wrapper: an unauthenticated
-- ===== caller (no auth.uid()) is rejected with the same 42501 as the delegate ===
set local role authenticated;  -- authenticated, but NO request.jwt claims set => auth.uid() is NULL
select throws_ok(
  $$ select public.create_organization(
       '22222222-2222-2222-2222-222222222222'::uuid,
       'Rogue', 'rogue-org', 'R', 'B', 'USD', 'Asia/Jerusalem', null) $$,
  '42501', NULL, 'an unauthenticated caller through public.create_organization raises 42501 (gate preserved)');
reset role;

-- ===== (11-18) a REAL self-serve signup THROUGH the wrapper provisions the tenant
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000150a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000150a0001","email":"rf150-owner@example.test","aal":"aal2"}';

create temp table rf150_res as
  select public.create_organization(
    '11111111-1111-1111-1111-1111150a0001'::uuid,
    'RF150 Pilot Org', 'rf150-pilot-org', 'Main Restaurant', 'Downtown Branch', 'USD', 'Asia/Jerusalem', 'Grill') as res;

reset role;

create temp table rf150_ids as
  select (res->>'ok')::boolean               as ok,
         (res->>'idempotent_replay')::boolean as replay,
         (res->>'organization_id')::uuid     as org,
         (res->>'restaurant_id')::uuid       as rest,
         (res->>'branch_id')::uuid           as branch,
         (res->>'membership_id')::uuid       as mem,
         (res->>'app_user_id')::uuid         as usr
  from rf150_res;

select is((select ok from rf150_ids), true, 'signup through the wrapper returns ok=true');
select is((select replay from rf150_ids), false, 'first signup through the wrapper is not an idempotent replay');
select is((select count(*) from organizations o, rf150_ids i
           where o.id = i.org
             and o.created_by_app_user_id = i.usr
             and o.creation_request_id = '11111111-1111-1111-1111-1111150a0001')::int,
          1, 'organization created with provenance (created_by + creation_request_id)');
select is((select count(*) from restaurants r, rf150_ids i where r.id = i.rest and r.organization_id = i.org)::int,
          1, 'first restaurant created under the new org');
select is((select count(*) from branches b, rf150_ids i where b.id = i.branch and b.organization_id = i.org and b.restaurant_id = i.rest)::int,
          1, 'first branch created under the restaurant');
select is((select role from memberships m, rf150_ids i where m.id = i.mem), 'org_owner',
          'first membership is org_owner (membership-scoped role, not a global role)');
select is((select au.auth_user_id from app_users au, rf150_ids i where au.id = i.usr),
          '00000000-0000-0000-0000-0000150a0001'::uuid, 'app_user is bound to auth.uid() (caller identity, not input)');
select is((select count(*) from audit_events a, rf150_ids i
           where a.action = 'organization.created' and a.organization_id = i.org and a.actor_app_user_id = i.usr)::int,
          1, 'organization.created audit event written (D-013)');

-- ===== (19-20) idempotency: replaying the SAME client_request_id through the =====
-- ===== wrapper returns idempotent_replay and creates NO second organization =====
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000150a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000150a0001","email":"rf150-owner@example.test","aal":"aal2"}';
select is(
  (public.create_organization(
     '11111111-1111-1111-1111-1111150a0001'::uuid,
     'RF150 Pilot Org', 'rf150-pilot-org', 'Main Restaurant', 'Downtown Branch', 'USD', 'Asia/Jerusalem', 'Grill')
   ->> 'idempotent_replay')::boolean, true,
  'replaying the same client_request_id through the wrapper is flagged idempotent_replay');
reset role;
select is((select count(*) from organizations where creation_request_id = '11111111-1111-1111-1111-1111150a0001')::int,
          1, 'the retry created NO second organization (idempotent self-serve signup)');

select * from finish();
rollback;
