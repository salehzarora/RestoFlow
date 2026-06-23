-- ============================================================================
-- RF-090 — pgTAP: idempotent-replay conflict safety (RF090-B1 regression)
-- ============================================================================
-- The concurrent unique_violation race path now replays through the SAME helper
-- as the pre-check: app.create_organization_replay(...). This test exercises
-- that shared path directly (deterministic; a true race can't be forced
-- sequentially) and proves:
--   * conflicting payload (different name OR currency) on a reused request fails
--     clearly (42501) — never silent success;
--   * the failed conflicting replays create NO duplicate org/restaurant/membership;
--   * a matching replay returns the STORED slug + org (not caller-provided).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0005', 'owner5@example.test');

-- create the original org via the RPC (as the authenticated principal)
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0005';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0005","email":"owner5@example.test","aal":"aal2"}';
create temp table base as select app.create_organization(
  '77777777-7777-7777-7777-777777777777'::uuid,
  'Stored Org', 'stored-slug', 'Stored Rest', 'Stored Branch', 'USD', 'UTC', 'Grill') as res;

reset role;
create temp table ids as
  select (res->>'organization_id')::uuid as org,
         (res->>'app_user_id')::uuid     as usr,
         (res->>'slug')                  as slug
  from base;

-- ===== conflicting payload through the shared replay path must FAIL ===========
select throws_ok(
  $$ select app.create_organization_replay(
       (select o from public.organizations o where o.id = (select org from ids)),
       'DIFFERENT NAME', (select slug from ids), 'USD', (select usr from ids)) $$,
  '42501', null, 'race/replay path: conflicting name fails clearly (no silent success)');

select throws_ok(
  $$ select app.create_organization_replay(
       (select o from public.organizations o where o.id = (select org from ids)),
       'Stored Org', (select slug from ids), 'EUR', (select usr from ids)) $$,
  '42501', null, 'race/replay path: conflicting currency fails clearly');

-- ===== the failed conflicting replays created NO duplicates ===================
select is((select count(*) from organizations where created_by_app_user_id = (select usr from ids))::int, 1, 'no duplicate organization');
select is((select count(*) from restaurants where organization_id = (select org from ids))::int, 1, 'no duplicate restaurant');
select is((select count(*) from memberships where organization_id = (select org from ids) and role = 'org_owner')::int, 1, 'no duplicate org_owner membership');

-- ===== a matching replay returns the STORED values ============================
create temp table rep as select app.create_organization_replay(
  (select o from public.organizations o where o.id = (select org from ids)),
  'Stored Org', (select slug from ids), 'USD', (select usr from ids)) as res;
select is((select (res->>'idempotent_replay')::boolean from rep), true, 'matching replay returns idempotent_replay=true');
select is((select (res->>'slug') from rep), (select slug from ids), 'matching replay returns the STORED slug');
select is((select (res->>'organization_id') from rep), (select org::text from ids), 'matching replay returns the stored organization id');

select * from finish();
rollback;
