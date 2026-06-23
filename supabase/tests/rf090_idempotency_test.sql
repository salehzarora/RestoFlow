-- ============================================================================
-- RF-090 — pgTAP: client_request_id idempotency (Option A)
-- ============================================================================
-- Same caller + same client_request_id returns the SAME org (no duplicates).
-- A different client_request_id creates another org (multi-org ownership ok).
-- Reusing a client_request_id with CONFLICTING org input fails clearly.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0002', 'owner2@example.test');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0002';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0002","email":"owner2@example.test","aal":"aal2"}';

-- first call + idempotent replay (same key, same input)
create temp table r1 as select app.create_organization(
  '22222222-2222-2222-2222-222222222222'::uuid,'Org Two','org-two','R1','B1','USD','UTC',null) as res;
create temp table r2 as select app.create_organization(
  '22222222-2222-2222-2222-222222222222'::uuid,'Org Two','org-two','R1','B1','USD','UTC',null) as res;
-- different request id -> a second org (multi-org ownership allowed)
create temp table r3 as select app.create_organization(
  '33333333-3333-3333-3333-333333333333'::uuid,'Org Three','org-three','R1','B1','USD','UTC',null) as res;

-- reused key with DIFFERENT input must fail (clear error, no wrong tenant returned)
select throws_ok(
  $$ select app.create_organization('22222222-2222-2222-2222-222222222222'::uuid,'Different Name','org-two','R1','B1','USD','UTC',null) $$,
  '42501', null, 'reused client_request_id with conflicting input fails clearly');

reset role;

select is((select (res->>'idempotent_replay')::boolean from r1), false, 'first call is not a replay');
select is((select (res->>'idempotent_replay')::boolean from r2), true,  'second call (same key) is an idempotent replay');
select is((select (res->>'organization_id') from r2), (select (res->>'organization_id') from r1), 'replay returns the SAME organization id');
select is((select (res->>'organization_id') from r3) <> (select (res->>'organization_id') from r1), true, 'different request_id creates a different org');

-- exactly two orgs created by this caller (the duplicate key did NOT create a third)
select is((select count(*) from organizations
           where created_by_app_user_id = (select (res->>'app_user_id')::uuid from r1))::int,
          2, 'no duplicate org: same key created one org, a new key created one more (total 2)');
-- and exactly one membership per org for the caller
select is((select count(*) from memberships
           where app_user_id = (select (res->>'app_user_id')::uuid from r1) and role = 'org_owner')::int,
          2, 'one org_owner membership per created org (no duplicate membership)');

select * from finish();
rollback;
