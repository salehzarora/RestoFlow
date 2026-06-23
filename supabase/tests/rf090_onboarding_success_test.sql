-- ============================================================================
-- RF-090 — pgTAP: successful self-serve onboarding (bootstrap + creation)
-- ============================================================================
-- A fresh authenticated principal (auth.users row, JWT, NO app_user yet) calls
-- app.create_organization once. It must bootstrap the app_user, create the org
-- + restaurant + branch + default station + org_owner membership + an
-- organization.created audit event, with provenance/idempotency columns set, and
-- return the ids. The identity is the caller's PERSONAL auth principal (no shared
-- account) and is bound to auth.uid() (cannot create for someone else).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0001', 'owner@example.test');

-- act as the JWT principal (fresh: no app_users row exists yet)
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","email":"owner@example.test","aal":"aal2"}';

create temp table rf090_res as
  select app.create_organization(
    '11111111-1111-1111-1111-111111111111'::uuid,
    'Pilot Org', 'pilot-org', 'Main Restaurant', 'Downtown Branch', 'USD', 'Asia/Jerusalem', 'Grill') as res;

reset role;

create temp table rf090_ids as
  select (res->>'ok')::boolean              as ok,
         (res->>'idempotent_replay')::boolean as replay,
         (res->>'organization_id')::uuid    as org,
         (res->>'restaurant_id')::uuid      as rest,
         (res->>'branch_id')::uuid          as branch,
         (res->>'station_id')::uuid         as station,
         (res->>'membership_id')::uuid      as mem,
         (res->>'app_user_id')::uuid        as usr
  from rf090_res;

select is((select ok from rf090_ids), true, 'RPC returns ok=true');
select is((select replay from rf090_ids), false, 'first call is not an idempotent replay');

-- organization created WITH provenance + idempotency key
select is((select count(*) from organizations o, rf090_ids i
           where o.id = i.org
             and o.created_by_app_user_id = i.usr
             and o.creation_request_id = '11111111-1111-1111-1111-111111111111')::int,
          1, 'organization created with created_by + creation_request_id');
select is((select default_currency from organizations o, rf090_ids i where o.id = i.org), 'USD', 'org currency stored');

-- restaurant + branch + default station, all under the new org
select is((select count(*) from restaurants r, rf090_ids i where r.id = i.rest and r.organization_id = i.org)::int, 1, 'first restaurant created under the org');
select is((select count(*) from branches b, rf090_ids i where b.id = i.branch and b.organization_id = i.org and b.restaurant_id = i.rest)::int, 1, 'first branch created under the restaurant');
select is((select count(*) from stations s, rf090_ids i where s.id = i.station and s.organization_id = i.org and s.branch_id = i.branch)::int, 1, 'default station created under the branch');

-- owner membership: org_owner, org-wide (membership role, NOT a global role)
select is((select role from memberships m, rf090_ids i where m.id = i.mem), 'org_owner', 'owner membership role is org_owner');
select ok((select m.restaurant_id is null and m.branch_id is null from memberships m, rf090_ids i where m.id = i.mem), 'owner membership is org-wide (no restaurant/branch narrowing)');
select is((select m.app_user_id from memberships m, rf090_ids i where m.id = i.mem), (select usr from rf090_ids), 'membership belongs to the caller''s app_user');

-- app_user bootstrapped + linked to the auth principal (personal, not shared)
select is((select au.auth_user_id from app_users au, rf090_ids i where au.id = i.usr),
          '00000000-0000-0000-0000-0000000a0001'::uuid, 'app_user linked to auth.uid() (bound to the caller, not input)');
select is((select au.email from app_users au, rf090_ids i where au.id = i.usr), 'owner@example.test', 'app_user email from the JWT claim (personal identity)');

-- append-only audit event written
select is((select count(*) from audit_events a, rf090_ids i
           where a.action = 'organization.created' and a.organization_id = i.org and a.actor_app_user_id = i.usr)::int,
          1, 'organization.created audit event written with the app_user as actor');

select * from finish();
rollback;
