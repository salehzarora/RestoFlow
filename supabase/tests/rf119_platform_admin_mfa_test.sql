-- ============================================================================
-- RF-119 -- pgTAP: platform-admin MFA. Two server changes:
--   (a) get_my_context.is_mfa_aal2 -- the caller's OWN session assurance == aal2
--       (a UX signal for the admin gate's honest "MFA required" state); factor-
--       agnostic (Q-008); aal1 / no-aal => false (fail-closed).
--   (b) app.platform_admin_list_organizations now requires MFA aal2 (via
--       app.platform_admin_guard) -- closes the RF-091-documented Q-008 gap on
--       this RF-059 cross-tenant read.
-- Uses the JWT identity path (auth.users + app_users.auth_user_id linked), like
-- rf091_mfa_test. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000119a0', 'rf119-admin@example.test'),
  ('00000000-0000-0000-0000-0000000119b0', 'rf119-user@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-000000119ee1', 'rf119-admin@example.test', '00000000-0000-0000-0000-0000000119a0'),
  ('00000000-0000-0000-0000-000000119ee2', 'rf119-user@example.test',  '00000000-0000-0000-0000-0000000119b0');
-- an ACTIVE platform grant for the admin (D-026: NOT a tenant membership).
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000001190f1', '00000000-0000-0000-0000-000000119ee1', 'active', '00000000-0000-0000-0000-000000119ee1');
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000001190a0', 'RF119 Org', 'rf119-org', 'USD');

set local role authenticated;

-- ===== get_my_context.is_mfa_aal2 (session assurance UX signal) =============
-- (1-2) a PLAIN user (no grant) at aal2: mfa true, platform admin false.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000119b0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119b0","aal":"aal2"}';
select is((public.get_my_context()->>'is_mfa_aal2')::boolean, true,
  'aal2 session: is_mfa_aal2 = true');
select is((public.get_my_context()->>'is_platform_admin')::boolean, false,
  'plain user: is_platform_admin = false (a tenant/plain user is never platform admin)');

-- (3) aal1 => is_mfa_aal2 false.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119b0","aal":"aal1"}';
select is((public.get_my_context()->>'is_mfa_aal2')::boolean, false,
  'aal1 session: is_mfa_aal2 = false');

-- (4) no aal claim => is_mfa_aal2 false (fail-closed).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119b0"}';
select is((public.get_my_context()->>'is_mfa_aal2')::boolean, false,
  'no aal claim: is_mfa_aal2 = false (fail-closed)');

-- (5-6) a PLATFORM ADMIN without aal2 = the exact "MFA required" client state:
-- is_platform_admin true, is_mfa_aal2 false.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000119a0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119a0","aal":"aal1"}';
select is((public.get_my_context()->>'is_platform_admin')::boolean, true,
  'platform admin: is_platform_admin = true even at aal1 (grant is aal-independent)');
select is((public.get_my_context()->>'is_mfa_aal2')::boolean, false,
  'platform admin at aal1: is_mfa_aal2 = false -> the gate shows MFA required');

-- ===== platform_admin_list_organizations now requires aal2 (RF-119) =========
-- (7) aal1 => denied even with an active grant + a reason.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119a0","aal":"aal1"}';
select throws_ok(
  $$ select app.platform_admin_list_organizations('rf119 audit') $$, '42501', null,
  'list_organizations at aal1: DENIED (MFA aal2 required, RF-119)');

-- (8) no aal claim => denied (fail-closed).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119a0"}';
select throws_ok(
  $$ select app.platform_admin_list_organizations('rf119 audit') $$, '42501', null,
  'list_organizations no aal: DENIED (fail-closed)');

-- (9) aal2 => allowed.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000119a0","aal":"aal2"}';
select is((app.platform_admin_list_organizations('rf119 audit') ->> 'ok')::boolean, true,
  'list_organizations at aal2: allowed');

select * from finish();
rollback;
