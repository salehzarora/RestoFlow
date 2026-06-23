-- ============================================================================
-- RF-090 — pgTAP: new-org tenant isolation (AC1, RISK R-003)
-- ============================================================================
-- Two principals each self-serve their own org. Each owner sees ONLY their own
-- org's data; neither can see the other's (Org-scoped RLS, D-001). Active org
-- context is set via set_config('app.current_organization_id', ..., true) which
-- app.current_org_id() validates against the caller's membership.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a000a', 'owner-a@example.test'),
  ('00000000-0000-0000-0000-0000000a000b', 'owner-b@example.test');

-- principal A onboards Org A
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a000a';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a000a","email":"owner-a@example.test","aal":"aal2"}';
create temp table ra as select app.create_organization(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,'Org A','iso-org-a','Rest A','Branch A','USD','UTC','Grill') as res;

-- principal B onboards Org B
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a000b';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a000b","email":"owner-b@example.test","aal":"aal2"}';
create temp table rb as select app.create_organization(
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,'Org B','iso-org-b','Rest B','Branch B','USD','UTC','Grill') as res;

reset role;
create temp table iso as select
  (select (res->>'organization_id')::uuid from ra) as org_a,
  (select (res->>'organization_id')::uuid from rb) as org_b;
-- the temp table is owned by the test-runner role; let the impersonated
-- `authenticated` role read the captured ids back.
grant select on iso to authenticated;

-- ===== as owner A (JWT A + active org A) =====
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a000a';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a000a","email":"owner-a@example.test","aal":"aal2"}';
select set_config('app.current_organization_id', (select org_a::text from iso), true);
select is((select count(*) from organizations where id = (select org_a from iso))::int, 1, 'owner A sees own org A');
select is((select count(*) from organizations where id = (select org_b from iso))::int, 0, 'owner A canNOT see org B');
select is((select count(*) from restaurants where organization_id = (select org_b from iso))::int, 0, 'owner A canNOT see org B restaurants');

-- ===== as owner B (JWT B + active org B) =====
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a000b';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a000b","email":"owner-b@example.test","aal":"aal2"}';
select set_config('app.current_organization_id', (select org_b::text from iso), true);
select is((select count(*) from organizations where id = (select org_b from iso))::int, 1, 'owner B sees own org B');
select is((select count(*) from organizations where id = (select org_a from iso))::int, 0, 'owner B canNOT see org A');
select is((select count(*) from restaurants where organization_id = (select org_a from iso))::int, 0, 'owner B canNOT see org A restaurants');

select * from finish();
rollback;
