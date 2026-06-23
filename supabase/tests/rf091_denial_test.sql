-- ============================================================================
-- RF-091 — pgTAP: authorization denial (AC2) + reason + grant!=membership + not-found
-- ============================================================================
-- A non-platform user and a tenant org_owner (no grant) are denied on ALL three
-- RPCs. A platform grant is NOT a membership (zero tenant rows). Reason is
-- required. A missing org fails clearly.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf091d-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000adf0', 'rf091d-admin@example.test'),
  ('00000000-0000-0000-0000-00000000ad01', 'rf091d-owner@example.test'),
  ('00000000-0000-0000-0000-00000000ad09', 'rf091d-nobody@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf091d-admin@example.test', '00000000-0000-0000-0000-00000000adf0'),
  ('00000000-0000-0000-0000-00000000ee01', 'rf091d-owner@example.test', '00000000-0000-0000-0000-00000000ad01'),
  ('00000000-0000-0000-0000-00000000ee09', 'rf091d-nobody@example.test', '00000000-0000-0000-0000-00000000ad09');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'active', '00000000-0000-0000-0000-00000000ee0f');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', 'org_owner');

set local role authenticated;

-- ===== a regular user with NO grant is denied on all three (aal2 set) ========= 1-3
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad09';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad09","aal":"aal2"}';
select throws_ok($$ select app.platform_admin_organization_overview('x') $$, '42501', null, 'non-platform user denied: overview');
select throws_ok($$ select app.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','x') $$, '42501', null, 'non-platform user denied: detail');
select throws_ok($$ select app.platform_admin_recent_audit('x', 10) $$, '42501', null, 'non-platform user denied: recent-audit');

-- ===== tenant org_owner (no grant) is denied; grant != membership ============= 4-7
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad01';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad01","aal":"aal2"}';
select is(app.is_platform_admin(), false, 'org_owner: is_platform_admin() is false');
select throws_ok($$ select app.platform_admin_organization_overview('try') $$, '42501', null, 'T-008: org_owner cannot call the platform overview');
select throws_ok($$ select app.platform_admin_get_organization('00000000-0000-0000-0000-0000000000a0','try') $$, '42501', null, 'T-008: org_owner cannot call platform detail');

-- the platform admin grant alone yields ZERO tenant rows (grant != membership, T-009)
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from restaurants)::int, 0, 'T-009: platform-admin grant alone yields ZERO tenant rows');

-- ===== reason required (blank/null) ========================================== 8-9
select throws_ok($$ select app.platform_admin_organization_overview('') $$, '42501', null, 'overview: blank reason denied');
select throws_ok($$ select app.platform_admin_organization_overview(null) $$, '42501', null, 'overview: null reason denied');

-- ===== org-detail not-found fails clearly ===================================== 10
select throws_ok($$ select app.platform_admin_get_organization('00000000-0000-0000-0000-0000000dead0','reason') $$, '42501', null, 'detail: non-existent org fails clearly');

-- ===== platform admin (correct gates) succeeds — positive control ============= 11
select is((app.platform_admin_organization_overview('positive control') ->> 'ok')::boolean, true, 'platform admin (grant + aal2 + reason) succeeds');

select * from finish();
rollback;
