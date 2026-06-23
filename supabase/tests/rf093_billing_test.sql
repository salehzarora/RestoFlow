-- ============================================================================
-- RF-093 — pgTAP: platform-admin plan assignment + tenant read + isolation
-- ============================================================================
-- Platform admin (active grant + aal2 + reason) assigns org plans; org_owner
-- reads its own entitlement; managers/kitchen and cross-tenant get nothing;
-- direct tenant mutation is denied; the limit primitive is per-org and leak-free.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(26);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf093-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf093-b', 'ILS');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000adf0', 'rf093-platadmin@example.test'),
  ('00000000-0000-0000-0000-00000000ad0a', 'rf093-ownera@example.test'),
  ('00000000-0000-0000-0000-00000000ad0b', 'rf093-managera@example.test'),
  ('00000000-0000-0000-0000-00000000ad0c', 'rf093-kitchena@example.test'),
  ('00000000-0000-0000-0000-00000000ad0d', 'rf093-ownerb@example.test'),
  ('00000000-0000-0000-0000-00000000ad0e', 'rf093-cashiera@example.test'),
  ('00000000-0000-0000-0000-00000000ad0f', 'rf093-accountanta@example.test');
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee0f', 'rf093-platadmin@example.test', '00000000-0000-0000-0000-00000000adf0'),
  ('00000000-0000-0000-0000-00000000ee0a', 'rf093-ownera@example.test', '00000000-0000-0000-0000-00000000ad0a'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf093-managera@example.test', '00000000-0000-0000-0000-00000000ad0b'),
  ('00000000-0000-0000-0000-00000000ee0c', 'rf093-kitchena@example.test', '00000000-0000-0000-0000-00000000ad0c'),
  ('00000000-0000-0000-0000-00000000ee0d', 'rf093-ownerb@example.test', '00000000-0000-0000-0000-00000000ad0d'),
  ('00000000-0000-0000-0000-00000000ee0e', 'rf093-cashiera@example.test', '00000000-0000-0000-0000-00000000ad0e'),
  ('00000000-0000-0000-0000-00000000ee10', 'rf093-accountanta@example.test', '00000000-0000-0000-0000-00000000ad0f');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000ee0f', 'active', '00000000-0000-0000-0000-00000000ee0f');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab0a', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000a0', null, null, 'manager'),
  ('00000000-0000-0000-0000-00000000ab0c', '00000000-0000-0000-0000-00000000ee0c', '00000000-0000-0000-0000-0000000000a0', null, null, 'kitchen_staff'),
  ('00000000-0000-0000-0000-00000000ab0d', '00000000-0000-0000-0000-00000000ee0d', '00000000-0000-0000-0000-0000000000b0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000000ab0e', '00000000-0000-0000-0000-00000000ee0e', '00000000-0000-0000-0000-0000000000a0', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00000000ab10', '00000000-0000-0000-0000-00000000ee10', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant');

set local role authenticated;

-- ===== platform admin (active grant + aal2 + reason) assigns plans ============
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select is((app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','free','active','onboarding A') ->> 'ok')::boolean, true, 'platform admin assigns Org A the free plan');
select is((app.set_organization_plan('00000000-0000-0000-0000-0000000000b0','basic','active','onboarding B') ->> 'ok')::boolean, true, 'platform admin assigns Org B the basic plan');

-- validation
select throws_ok($$ select app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','nope','active','r') $$, '42501', null, 'invalid plan_code rejected');
select throws_ok($$ select app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','free','bogus','r') $$, '42501', null, 'invalid status rejected');
select throws_ok($$ select app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','free','active','') $$, '42501', null, 'blank reason rejected');
select throws_ok($$ select app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','free','active','r', now(), now() - interval '1 day') $$, '42501', null, 'period end before start rejected');

-- aal1 platform admin denied (MFA gate)
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok($$ select app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','free','active','r') $$, '42501', null, 'aal1 platform admin denied (MFA required)');

-- ===== org_owner A: reads OWN entitlement; org_owner cannot mutate ===========
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad0a';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad0a","aal":"aal2"}';
select set_config('app.current_organization_id', '00000000-0000-0000-0000-0000000000a0', true);
select is((select plan_code from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000a0'), 'free', 'org_owner A reads own entitlement plan = free');
select is((select max_branches from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 1, 'org_owner A entitlement max_branches = 1');
select is((select price_minor from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000a0')::bigint, 0::bigint, 'org_owner A entitlement price_minor = 0 (integer)');
select is(app.org_plan_limit('00000000-0000-0000-0000-0000000000a0', 'max_branches')::int, 1, 'org_plan_limit(A, max_branches) = 1');
-- org_owner cannot mutate billing (not a platform admin) nor write the table directly
select throws_ok($$ select app.set_organization_plan('00000000-0000-0000-0000-0000000000a0','basic','active','r') $$, '42501', null, 'org_owner cannot call set_organization_plan (not platform admin)');
select throws_ok($$ update public.organization_subscriptions set plan_code='basic' where organization_id='00000000-0000-0000-0000-0000000000a0' $$, null, null, 'org_owner cannot directly UPDATE organization_subscriptions');

-- ===== manager / kitchen: NO billing read =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad0b';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad0b","aal":"aal2"}';
select set_config('app.current_organization_id', '00000000-0000-0000-0000-0000000000a0', true);
select is((select count(*) from public.organization_entitlements)::int, 0, 'manager: ZERO billing entitlement rows');
select ok(app.org_plan_limit('00000000-0000-0000-0000-0000000000a0', 'max_branches') is null, 'manager: org_plan_limit returns null (no leak)');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad0c';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad0c","aal":"aal2"}';
select set_config('app.current_organization_id', '00000000-0000-0000-0000-0000000000a0', true);
select is((select count(*) from public.organization_entitlements)::int, 0, 'kitchen_staff: ZERO billing entitlement rows');

-- ===== cashier: NO billing read, NO direct mutation (RF093-B1) =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad0e';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad0e","aal":"aal2"}';
select set_config('app.current_organization_id', '00000000-0000-0000-0000-0000000000a0', true);
select is((select count(*) from public.organization_entitlements)::int, 0, 'cashier: ZERO billing entitlement rows');
select ok(app.org_plan_limit('00000000-0000-0000-0000-0000000000a0', 'max_branches') is null, 'cashier: org_plan_limit returns null (no leak)');
select throws_ok($$ update public.organization_subscriptions set plan_code='basic' where organization_id='00000000-0000-0000-0000-0000000000a0' $$, null, null, 'cashier cannot directly UPDATE organization_subscriptions');

-- ===== accountant: ALLOWED billing read (positive control) =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad0f';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad0f","aal":"aal2"}';
select set_config('app.current_organization_id', '00000000-0000-0000-0000-0000000000a0', true);
select is((select plan_code from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000a0'), 'free', 'accountant: CAN read own org entitlement (policy allows org_owner + accountant)');

-- ===== cross-tenant: org_owner B sees only B; cannot read/leak A ==============
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000ad0d';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000ad0d","aal":"aal2"}';
select set_config('app.current_organization_id', '00000000-0000-0000-0000-0000000000b0', true);
select is((select plan_code from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000b0'), 'basic', 'org_owner B reads own entitlement plan = basic');
select ok((select max_branches is null from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000b0'), 'org_owner B basic max_branches null (unlimited)');
select is((select count(*) from public.organization_entitlements where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 0, 'cross-tenant: org_owner B sees ZERO of Org A');
select ok(app.org_plan_limit('00000000-0000-0000-0000-0000000000a0', 'max_branches') is null, 'cross-tenant: org_plan_limit(A) from B is null (no leak)');

-- ===== audit: each assignment wrote a platform audit row (reset to bypass) ====
reset role;
select cmp_ok((select count(*) from platform_admin_audit_events where action='platform.org.plan_set')::int, '>=', 2, 'each plan assignment wrote a platform_admin_audit_events row');
select is((select actor_app_user_id from platform_admin_audit_events where action='platform.org.plan_set' and target_organization_id='00000000-0000-0000-0000-0000000000a0' limit 1),
          '00000000-0000-0000-0000-00000000ee0f'::uuid, 'audit row records the platform-admin actor + target org');

select * from finish();
rollback;
