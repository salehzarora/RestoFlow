-- ============================================================================
-- RF-090 — pgTAP: no privilege escalation (D-004/D-026)
-- ============================================================================
-- Onboarding makes the caller an org_owner via MEMBERSHIP only — never a global
-- or platform role. The RPC accepts no role/platform input and never writes
-- platform_admin_grants (the platform plane stays untouched).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(5);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0003', 'owner3@example.test');

-- baseline: platform plane is empty
select is((select count(*) from platform_admin_grants)::int, 0, 'baseline: no platform_admin grants');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0003';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","email":"owner3@example.test","aal":"aal2"}';
create temp table rp as select app.create_organization(
  '44444444-4444-4444-4444-444444444444'::uuid,'Org P','org-p','R','B','USD','UTC',null) as res;

reset role;

-- the ONLY membership for the caller is a tenant org_owner (a membership-scoped role)
select is((select role from memberships where app_user_id = (select (res->>'app_user_id')::uuid from rp)),
          'org_owner', 'caller is org_owner via membership (not a global role)');
select ok((select role in ('org_owner','restaurant_owner','manager','cashier','kitchen_staff','accountant')
           from memberships where app_user_id = (select (res->>'app_user_id')::uuid from rp)),
          'membership role is within the tenant role set (platform_admin not a member role, D-026)');

-- platform plane untouched: no grant created for this user, none at all
select is((select count(*) from platform_admin_grants
           where app_user_id = (select (res->>'app_user_id')::uuid from rp))::int, 0,
          'no platform_admin grant created for the new owner');
select is((select count(*) from platform_admin_grants)::int, 0, 'platform_admin_grants remains empty after onboarding');

select * from finish();
rollback;
