-- ============================================================================
-- RF-124 — pgTAP: public.get_my_context() is an authenticated-only, read-only,
--          STRICTLY self-scoped context resolver (API_CONTRACT §4.22,
--          DECISION D-029, T-012). >= 3 active orgs and >= 2 distinct,
--          separately-linked auth principals (T-012).
-- ============================================================================
-- Auth simulation = the repo's REAL JWT-sub mechanism (rf050 test:52-60):
--   set local role authenticated; set local app.current_app_user_id = '' (no GUC
--   crutch); set local request.jwt.claim.sub / request.jwt.claims. The resolver
--   derives identity from auth.uid() via app.current_app_user_id().
-- Each auth principal links to AT MOST ONE app_user (partial-unique
-- app_users_auth_user_id_key, rf050:60-62) — no duplicate auth_user_id.
-- Fixtures inserted as the BYPASSRLS connection role; assertions run as
-- `authenticated`; whole test in begin; ... rollback;.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(36);

-- ---- Auth principals (one per app_user) ------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0001', 'rf124-multi@example.test'),    -- user A: multi-membership (Org A + Org B)
  ('00000000-0000-0000-0000-0000000a0002', 'rf124-admin@example.test'),    -- platform admin, NO memberships
  ('00000000-0000-0000-0000-0000000a0003', 'rf124-kitchen@example.test'),  -- kitchen_staff, Org A; null display_name
  ('00000000-0000-0000-0000-0000000a0004', 'rf124-inactive@example.test'), -- inactive app_user
  ('00000000-0000-0000-0000-0000000a000b', 'rf124-userb@example.test'),    -- user B (Org D) — distinct second user
  ('00000000-0000-0000-0000-0000000a0009', 'rf124-unlinked@example.test'); -- real principal, NO app_user link

-- ---- Orgs: A, B, D, E active (>= 3); C soft-deleted --------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf124-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf124-b', 'EUR'),
  ('00000000-0000-0000-0000-0000000000d0', 'Org D', 'rf124-d', 'USD'),
  ('00000000-0000-0000-0000-0000000000e0', 'Org E', 'rf124-e', 'USD'),      -- ACTIVE org; holds soft-deleted restaurant/branch parents
  ('00000000-0000-0000-0000-0000000000c0', 'Org C deleted', 'rf124-c', 'USD');
update organizations set deleted_at = now() where id = '00000000-0000-0000-0000-0000000000c0';

-- Org A: live restaurant + live branch (the happy-path scoped membership)
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a0b01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'Branch A1');

-- Org E (RF124-B1): a SOFT-DELETED restaurant, and a LIVE restaurant with a
-- SOFT-DELETED branch. Active memberships scoped to these dead parents MUST be
-- excluded (without the fix they would surface with the original id + null name).
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000000e0d1', '00000000-0000-0000-0000-0000000000e0', 'Rest E-deleted'),
  ('00000000-0000-0000-0000-00000000e0a2', '00000000-0000-0000-0000-0000000000e0', 'Rest E-live');
update restaurants set deleted_at = now() where id = '00000000-0000-0000-0000-00000000e0d1';
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000e0bd1', '00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-00000000e0a2', 'Branch E-deleted');
update branches set deleted_at = now() where id = '00000000-0000-0000-0000-0000000e0bd1';

-- ---- app_users (one auth principal each; ee03 has a NULL display_name) --------
insert into app_users (id, email, display_name, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf124-multi@example.test',    'Multi U', '00000000-0000-0000-0000-0000000a0001'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf124-admin@example.test',    'Admin U', '00000000-0000-0000-0000-0000000a0002'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf124-kitchen@example.test',  null,      '00000000-0000-0000-0000-0000000a0003'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf124-inactive@example.test', 'Inact U', '00000000-0000-0000-0000-0000000a0004'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf124-userb@example.test',    'User B',  '00000000-0000-0000-0000-0000000a000b');
update app_users set is_active = false where id = '00000000-0000-0000-0000-00000000ee04';

-- ---- memberships -------------------------------------------------------------
-- user A: org_owner in Org A (branch-scoped, LIVE parents) + manager in Org B (org-wide) => 2 VISIBLE
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ba01', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001',
   '00000000-0000-0000-0000-0000000a0b01', 'org_owner');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ba02', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000b0', 'manager');
-- user A: REVOKED membership in Org A (must be EXCLUDED)
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('00000000-0000-0000-0000-00000000ba03', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000a0', 'cashier', 'revoked');
-- user A: SOFT-DELETED membership in Org A (must be EXCLUDED)
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ba04', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000a0', 'accountant');
update memberships set deleted_at = now() where id = '00000000-0000-0000-0000-00000000ba04';
-- user A: ACTIVE membership whose PARENT ORG is soft-deleted (EXCLUDED by the org join)
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ba06', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000c0', 'manager');
-- RF124-B1 user A: ACTIVE membership scoped to a SOFT-DELETED RESTAURANT (must be EXCLUDED)
insert into memberships (id, app_user_id, organization_id, restaurant_id, role) values
  ('00000000-0000-0000-0000-00000000ba07', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-00000000e0d1', 'restaurant_owner');
-- RF124-B1 user A: ACTIVE membership scoped to a LIVE restaurant but a SOFT-DELETED BRANCH (must be EXCLUDED)
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ba08', '00000000-0000-0000-0000-00000000ee01',
   '00000000-0000-0000-0000-0000000000e0', '00000000-0000-0000-0000-00000000e0a2',
   '00000000-0000-0000-0000-0000000e0bd1', 'cashier');
-- kitchen user: kitchen_staff in Org A
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ba05', '00000000-0000-0000-0000-00000000ee03',
   '00000000-0000-0000-0000-0000000000a0', 'kitchen_staff');
-- user B: org_owner in Org D — must NEVER appear in A's context (cross-user)
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ba0b', '00000000-0000-0000-0000-00000000ee0b',
   '00000000-0000-0000-0000-0000000000d0', 'org_owner');

-- ---- platform-admin grant (admin user; NO memberships) -----------------------
insert into platform_admin_grants (app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-00000000ee02', 'active', '00000000-0000-0000-0000-00000000ee02');

-- ============================================================================
-- (A) STRUCTURE / SIGNATURE / GRANTS  (1-8)
-- ============================================================================
select has_function('public', 'get_my_context', array[]::text[],
  '1: public.get_my_context() exists with NO arguments (identity is never an input)');
select is(
  (select format_type(prorettype, null) from pg_proc
     where proname = 'get_my_context' and pronamespace = 'public'::regnamespace),
  'jsonb', '2: public.get_my_context returns jsonb');
select is(
  (select prosecdef from pg_proc
     where proname = 'get_my_context' and pronamespace = 'public'::regnamespace),
  false, '3: public.get_my_context is SECURITY INVOKER (wrapper)');
select is(
  (select prosecdef from pg_proc
     where proname = 'get_my_context' and pronamespace = 'app'::regnamespace),
  true, '4: app.get_my_context is SECURITY DEFINER (source of truth)');
select ok(
  has_function_privilege('authenticated', 'public.get_my_context()', 'execute'),
  '5: authenticated MAY execute public.get_my_context');
select ok(
  not has_function_privilege('anon', 'public.get_my_context()', 'execute'),
  '6: anon may NOT execute public.get_my_context');
select ok(
  not has_function_privilege('public', 'public.get_my_context()', 'execute'),
  '7: PUBLIC may NOT execute public.get_my_context (revoked)');
select hasnt_function('public', 'is_platform_admin',
  '8: no broad app exposure regression: app.is_platform_admin not mirrored into public');

-- ============================================================================
-- (B) AUTHENTICATED MULTI-MEMBERSHIP SELF-READ as user A  (9-27)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '';   -- prove the JWT path, no GUC crutch
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';

select is((select (public.get_my_context()->>'ok')::boolean), true,
  '9: ok = true on the self-read path');
select is((select public.get_my_context()->'app_user'->>'id'),
  '00000000-0000-0000-0000-00000000ee01', '10: app_user.id is the caller''s own id');
select is((select public.get_my_context()->'app_user'->>'email'),
  'rf124-multi@example.test', '11: app_user.email is the caller''s own (non-null) email');
select is((select (public.get_my_context()->'app_user'->>'is_active')::boolean), true,
  '12: app_user.is_active is true for the active caller');
select is((select (public.get_my_context()->>'is_platform_admin')::boolean), false,
  '13: non-admin caller: is_platform_admin is a separate boolean = false');
select is((select jsonb_typeof(public.get_my_context()->'memberships')), 'array',
  '14: memberships is a JSON array (LIST), never a single global role');
select is((select jsonb_array_length(public.get_my_context()->'memberships'))::int, 2,
  '15: exactly the 2 visible memberships (revoked, soft-deleted, dead-org-parent, dead-restaurant, dead-branch all excluded)');
select ok((select not (public.get_my_context() ? 'role')),
  '16: no single global top-level role key (D-004 multi-membership)');
select is(
  (select (e->>'role') from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000a0'),
  'org_owner', '17: Org A membership role is org_owner (role is per-membership)');
select is(
  (select (e->>'organization_name') from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000a0'),
  'Org A', '18: Org A membership carries organization_name');
select is(
  (select (e->>'restaurant_name') from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000a0'),
  'Rest A1', '19: branch-scoped Org A membership carries restaurant_name');
select is(
  (select (e->>'branch_name') from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000a0'),
  'Branch A1', '20: branch-scoped Org A membership carries branch_name');
select ok(
  (select (e->'restaurant_id') = 'null'::jsonb and (e->'branch_id') = 'null'::jsonb
   from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000b0'),
  '21: org-wide Org B membership has null restaurant_id and branch_id');
select is(
  (select count(*) from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000c0')::int,
  0, '22: a membership whose parent ORG is soft-deleted never surfaces');
-- RF124-B1 positive coverage: scoped memberships pointing at dead parents are excluded.
select is(
  (select count(*) from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'restaurant_id') = '00000000-0000-0000-0000-00000000e0d1')::int,
  0, '23: RF124-B1 — active membership scoped to a SOFT-DELETED restaurant is excluded (no stale id/null name)');
select is(
  (select count(*) from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'branch_id') = '00000000-0000-0000-0000-0000000e0bd1')::int,
  0, '24: RF124-B1 — active membership scoped to a SOFT-DELETED branch is excluded (no stale id/null name)');
-- and Org E (which held ONLY the two dead-parent-scoped memberships) never surfaces at all
select is(
  (select count(*) from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000e0')::int,
  0, '25: Org E (only dead-parent-scoped memberships) does not surface at all');
select is(
  (select public.get_my_context()->'memberships'->0->>'organization_id'),
  '00000000-0000-0000-0000-0000000000a0',
  '26: deterministic ordering: first membership is Org A (ordered by organization_id)');
select is(
  (select count(*) from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
   where (e->>'organization_id') = '00000000-0000-0000-0000-0000000000d0')::int,
  0, '27: user A never sees user B''s Org D (no cross-user membership leak)');

-- ============================================================================
-- (C) CROSS-USER / CROSS-ORG ISOLATION (>= 3 orgs, 2 users, bidirectional)  (28-29)
-- ============================================================================
select results_eq(
  $$ select distinct (e->>'organization_id')
       from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
      order by 1 $$,
  $$ values ('00000000-0000-0000-0000-0000000000a0'),
            ('00000000-0000-0000-0000-0000000000b0') $$,
  '28: user A sees EXACTLY its own orgs {A,B} — no cross-org / cross-user leak');

-- act as user B: must see ONLY Org D, never A's orgs (bidirectional probe)
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a000b';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a000b","aal":"aal2"}';
select results_eq(
  $$ select distinct (e->>'organization_id')
       from lateral jsonb_array_elements(public.get_my_context()->'memberships') e
      order by 1 $$,
  $$ values ('00000000-0000-0000-0000-0000000000d0') $$,
  '29: user B sees ONLY its own Org D — A''s orgs never leak the other way');

-- ============================================================================
-- (D) PLATFORM ADMIN: separate boolean, no memberships  (30-31)
-- ============================================================================
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0002';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0002","aal":"aal2"}';
select is((select (public.get_my_context()->>'is_platform_admin')::boolean), true,
  '30: active grant holder: is_platform_admin = true');
select is((select jsonb_array_length(public.get_my_context()->'memberships'))::int, 0,
  '31: platform admin with no memberships: memberships = [] (separate boolean, not a membership)');

-- ============================================================================
-- (E) KITCHEN_STAFF: null display_name + no money field anywhere  (32-33)
-- ============================================================================
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0003';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select ok((select public.get_my_context()->'app_user'->'display_name' = 'null'::jsonb),
  '32: display_name may be null (returned as JSON null)');
select ok((select (public.get_my_context())::text not like '%_minor%'),
  '33: kitchen_staff context contains no *_minor / money field');

-- ============================================================================
-- (F) FAIL-CLOSED: inactive app user / unlinked principal / unauthenticated  (34-36)
-- ============================================================================
-- inactive app_user => 42501
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0004';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select throws_ok($$ select public.get_my_context() $$, '42501', NULL,
  '34: inactive app_user is rejected with 42501');

-- real JWT principal with NO app_user link => 42501 (fail closed)
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0009';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0009","aal":"aal2"}';
select throws_ok($$ select public.get_my_context() $$, '42501', NULL,
  '35: authenticated-but-unlinked principal fails closed with 42501');

-- unauthenticated: no JWT, no GUC => auth.uid() null => current_app_user_id() null
set local app.current_app_user_id = '';
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '';
select throws_ok($$ select public.get_my_context() $$, '42501', NULL,
  '36: unauthenticated (no JWT) fails closed with 42501');

reset role;
select * from finish();
rollback;
