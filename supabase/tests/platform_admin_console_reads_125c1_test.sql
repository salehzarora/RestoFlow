-- ============================================================================
-- PLATFORM-ADMIN-125C.1 — pgTAP: the Platform Console read contract
-- (D-011/D-012/D-013/D-026; RISK R-003; REPORT-123; POS-124 anon lesson)
-- ============================================================================
-- Five cross-tenant, platform-admin-only READ endpoints the 125C.2 console will
-- consume: console overview, subscribers list, subscriber detail, restaurants
-- list, audit search. Every one of them reads EVERY tenant's data, so the gate
-- is the whole feature: an active platform_admin_grant AND a verified aal2 JWT
-- AND a non-empty reason, enforced by app.platform_admin_guard as the FIRST
-- statement — a tenant membership, even org_owner, can never satisfy it (D-026).
--
-- Two lessons are binding here and are why the anon assertions look the way
-- they do:
--   * REPORT-123 — a public SECURITY INVOKER wrapper granted to authenticated
--     while its app.* twin is not produces a 42501 that no local test notices.
--     Both layers are pinned, and the wrappers are exercised AS the real
--     authenticated role.
--   * POS-124 — Supabase's hosted ALTER DEFAULT PRIVILEGES grants anon EXECUTE
--     on everything created in `public`, so "anon holds no grant" passes
--     locally and is FALSE in production. We assert the boundary that actually
--     holds instead: anon has no USAGE on schema `app`, so every wrapper is a
--     dead end for it whatever its own grant says.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(111);

-- ===== fixtures ==============================================================
-- Five LIVE organizations plus one TOMBSTONED one, so every count, filter and
-- sort is proven against a set where the wrong answer is visible.
--   Alpha   active,    USD, 2 restaurants, 3 branches, 3 active members, basic/active
--           (ee01 + ee02 below, PLUS the org_owner principal ee0e added with the
--            auth fixtures — it is a real active membership and must be counted)
--   Bravo   suspended, EUR, 1 restaurant,  1 branch,   1 active member,  NO subscription
--   Charlie active,    ILS, 0 restaurants, 0 branches, 0 members,        free/trialing
--   Delta   active,    GBP, 1 restaurant,  0 branches, 0 members,        basic/past_due
--   Golf    active,    USD, 0 restaurants, 0 branches, 0 members,        basic/canceled
--   Echo    DELETED — carries a restaurant, a branch AND a subscription, all of
--           which must be invisible to every endpoint.
insert into organizations (id, name, slug, default_currency, status, created_at) values
  ('c1000000-0000-0000-0000-0000000000a0', 'Alpha Group', 'pac-alpha',   'USD', 'active',    '2026-01-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000b0', 'Bravo Ltd',   'pac-bravo',   'EUR', 'suspended', '2026-02-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000c0', 'Charlie Co',  'pac-charlie', 'ILS', 'active',    '2026-03-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000d0', 'Delta Inc',   'pac-delta',   'GBP', 'active',    '2026-04-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000f0', 'Golf LLC',    'pac-golf',    'USD', 'active',    '2026-05-01T00:00:00Z');
insert into organizations (id, name, slug, default_currency, status, created_at, deleted_at) values
  ('c1000000-0000-0000-0000-0000000000e0', 'Echo Gone',   'pac-echo',    'USD', 'active',    '2026-06-01T00:00:00Z', now());

insert into restaurants (id, organization_id, name, status, created_at) values
  ('c1000000-0000-0000-0000-000000000a01', 'c1000000-0000-0000-0000-0000000000a0', 'Alpha One',   'active',   '2026-01-02T00:00:00Z'),
  ('c1000000-0000-0000-0000-000000000a02', 'c1000000-0000-0000-0000-0000000000a0', 'Alpha Two',   'suspended', '2026-01-03T00:00:00Z'),
  ('c1000000-0000-0000-0000-000000000b01', 'c1000000-0000-0000-0000-0000000000b0', 'Bravo One',   'active',   '2026-02-02T00:00:00Z'),
  ('c1000000-0000-0000-0000-000000000d01', 'c1000000-0000-0000-0000-0000000000d0', 'Delta One',   'active',   '2026-04-02T00:00:00Z'),
  ('c1000000-0000-0000-0000-000000000e01', 'c1000000-0000-0000-0000-0000000000e0', 'Echo One',    'active',   '2026-06-02T00:00:00Z');
-- a tombstoned restaurant inside a LIVE org — must not be counted or listed
insert into restaurants (id, organization_id, name, status, created_at, deleted_at) values
  ('c1000000-0000-0000-0000-000000000a03', 'c1000000-0000-0000-0000-0000000000a0', 'Alpha Ghost', 'active', '2026-01-04T00:00:00Z', now());

insert into branches (id, organization_id, restaurant_id, name) values
  ('c1000000-0000-0000-0000-00000000ab01', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-000000000a01', 'Alpha B1'),
  ('c1000000-0000-0000-0000-00000000ab02', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-000000000a01', 'Alpha B2'),
  ('c1000000-0000-0000-0000-00000000ab03', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-000000000a02', 'Alpha B3'),
  ('c1000000-0000-0000-0000-00000000bb01', 'c1000000-0000-0000-0000-0000000000b0', 'c1000000-0000-0000-0000-000000000b01', 'Bravo B1'),
  ('c1000000-0000-0000-0000-00000000eb01', 'c1000000-0000-0000-0000-0000000000e0', 'c1000000-0000-0000-0000-000000000e01', 'Echo B1');

insert into app_users (id, email) values
  ('c1000000-0000-0000-0000-00000000ee01', 'pac-a1@example.test'),
  ('c1000000-0000-0000-0000-00000000ee02', 'pac-a2@example.test'),
  ('c1000000-0000-0000-0000-00000000ee03', 'pac-b1@example.test'),
  ('c1000000-0000-0000-0000-00000000ee04', 'pac-a3-revoked@example.test');
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('c1000000-0000-0000-0000-00000000ab11', 'c1000000-0000-0000-0000-00000000ee01', 'c1000000-0000-0000-0000-0000000000a0', 'org_owner', 'active'),
  ('c1000000-0000-0000-0000-00000000ab12', 'c1000000-0000-0000-0000-00000000ee02', 'c1000000-0000-0000-0000-0000000000a0', 'manager',   'active'),
  ('c1000000-0000-0000-0000-00000000bb11', 'c1000000-0000-0000-0000-00000000ee03', 'c1000000-0000-0000-0000-0000000000b0', 'org_owner', 'active');
-- a revoked membership must not inflate the active count
insert into memberships (id, app_user_id, organization_id, role, status, deleted_at) values
  ('c1000000-0000-0000-0000-00000000ab13', 'c1000000-0000-0000-0000-00000000ee04', 'c1000000-0000-0000-0000-0000000000a0', 'cashier', 'revoked', now());

-- `plans` is SEEDED by RF-093 (free, basic) — referenced, never re-inserted.
insert into organization_subscriptions (organization_id, plan_code, status, current_period_start, current_period_end) values
  ('c1000000-0000-0000-0000-0000000000a0', 'basic', 'active',   '2026-06-01T00:00:00Z', '2026-07-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000c0', 'free',  'trialing', '2026-07-01T00:00:00Z', '2026-08-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000d0', 'basic', 'past_due', '2026-04-01T00:00:00Z', '2026-05-01T00:00:00Z'),
  ('c1000000-0000-0000-0000-0000000000f0', 'basic', 'canceled', '2026-08-01T00:00:00Z', '2026-09-01T00:00:00Z'),
  -- on the TOMBSTONED org: must never reach a count or a row
  ('c1000000-0000-0000-0000-0000000000e0', 'basic', 'active',   '2026-06-01T00:00:00Z', '2026-07-01T00:00:00Z');

-- principals: a platform operator, and an ordinary org_owner who must never pass
insert into auth.users (id, email) values
  ('c1000000-0000-0000-0000-00000000adf0', 'pac-operator@example.test'),
  ('c1000000-0000-0000-0000-00000000adf1', 'pac-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('c1000000-0000-0000-0000-00000000ee0f', 'pac-operator@example.test', 'c1000000-0000-0000-0000-00000000adf0'),
  ('c1000000-0000-0000-0000-00000000ee0e', 'pac-owner@example.test',    'c1000000-0000-0000-0000-00000000adf1');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('c1000000-0000-0000-0000-0000000000f1', 'c1000000-0000-0000-0000-00000000ee0f', 'active', 'c1000000-0000-0000-0000-00000000ee0f');
-- the org_owner principal holds a REAL tenant membership and NO platform grant
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('c1000000-0000-0000-0000-00000000ab14', 'c1000000-0000-0000-0000-00000000ee0e', 'c1000000-0000-0000-0000-0000000000a0', 'org_owner', 'active');

-- audit fixtures for group E (deterministic timestamps, newest last)
insert into platform_admin_audit_events (id, actor_app_user_id, target_organization_id, action, reason, details, occurred_at) values
  ('c1000000-0000-0000-0000-00000000e001', 'c1000000-0000-0000-0000-00000000ee0f', null,                                     'platform.organizations.overview', 'seed 1', jsonb_build_object('secret','must-not-leak'), '2026-05-01T10:00:00Z'),
  ('c1000000-0000-0000-0000-00000000e002', 'c1000000-0000-0000-0000-00000000ee0f', 'c1000000-0000-0000-0000-0000000000a0',   'platform.subscriber.detail',      'seed 2', jsonb_build_object('secret','must-not-leak'), '2026-05-02T10:00:00Z'),
  ('c1000000-0000-0000-0000-00000000e003', 'c1000000-0000-0000-0000-00000000ee0f', 'c1000000-0000-0000-0000-0000000000b0',   'platform.subscriber.detail',      'seed 3', jsonb_build_object('secret','must-not-leak'), '2026-05-03T10:00:00Z'),
  ('c1000000-0000-0000-0000-00000000e004', 'c1000000-0000-0000-0000-00000000ee0f', null,                                     'platform.audit.read',             'seed 4', jsonb_build_object('secret','must-not-leak'), '2026-05-04T10:00:00Z');

-- ===========================================================================
-- 0. EXISTENCE (11)
-- ===========================================================================
select has_function('app', 'platform_admin_console_overview', array['text'],
  '0.1 app.platform_admin_console_overview exists');
select has_function('public', 'platform_admin_console_overview', array['text'],
  '0.2 its wrapper exists');
select has_function('app', 'platform_admin_list_subscribers',
  array['text', 'integer', 'integer', 'text', 'text', 'text', 'text', 'text'],
  '0.3 app.platform_admin_list_subscribers exists');
select has_function('public', 'platform_admin_list_subscribers',
  array['text', 'integer', 'integer', 'text', 'text', 'text', 'text', 'text'],
  '0.4 its wrapper exists');
select has_function('app', 'platform_admin_get_subscriber', array['uuid', 'text'],
  '0.5 app.platform_admin_get_subscriber exists');
select has_function('public', 'platform_admin_get_subscriber', array['uuid', 'text'],
  '0.6 its wrapper exists');
select has_function('app', 'platform_admin_list_restaurants',
  array['text', 'integer', 'integer', 'text', 'text', 'text'],
  '0.7 app.platform_admin_list_restaurants exists');
select has_function('public', 'platform_admin_list_restaurants',
  array['text', 'integer', 'integer', 'text', 'text', 'text'],
  '0.8 its wrapper exists');
select has_function('app', 'platform_admin_audit_search',
  array['text', 'integer', 'timestamptz', 'uuid', 'text', 'uuid', 'timestamptz', 'timestamptz'],
  '0.9 app.platform_admin_audit_search exists');
select has_function('public', 'platform_admin_audit_search',
  array['text', 'integer', 'timestamptz', 'uuid', 'text', 'uuid', 'timestamptz', 'timestamptz'],
  '0.10 its wrapper exists');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('platform_admin_console_overview', 'platform_admin_list_subscribers',
                        'platform_admin_get_subscriber', 'platform_admin_list_restaurants',
                        'platform_admin_audit_search')
      and p.prosecdef
      and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
  5, '0.11 all five implementations are SECURITY DEFINER with a pinned search_path');

-- ===========================================================================
-- A. CONSOLE OVERVIEW (17)
-- ===========================================================================
-- Denials first, as the real authenticated ROLE (REPORT-123).
set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf1","aal":"aal2"}';
select throws_ok(
  $$ select public.platform_admin_console_overview('RestoFlow admin: platform overview (read-only)') $$,
  '42501', NULL, 'A1. an org_owner with NO platform grant is denied (D-026/T-008)');

set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok(
  $$ select public.platform_admin_console_overview('RestoFlow admin: platform overview (read-only)') $$,
  '42501', NULL, 'A2. a platform admin at aal1 is denied (MFA required)');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0"}';
select throws_ok(
  $$ select public.platform_admin_console_overview('RestoFlow admin: platform overview (read-only)') $$,
  '42501', NULL, 'A3. no aal claim at all is denied (fail-closed)');

set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select throws_ok(
  $$ select public.platform_admin_console_overview('   ') $$,
  '42501', NULL, 'A4. a blank reason is denied (platform access is reason-tagged)');
select throws_ok(
  $$ select public.platform_admin_console_overview(null) $$,
  '42501', NULL, 'A5. a null reason is denied');

create temp table a_ov as
  select public.platform_admin_console_overview('RestoFlow admin: platform overview (read-only)') as res;
reset role;

select is((select (res->>'ok')::boolean from a_ov), true, 'A6. a platform admin at aal2 is allowed');
select is(
  (select array(select jsonb_object_keys(res) order by 1) from a_ov),
  array['active_memberships_total', 'branches_total', 'ok', 'organizations_active',
        'organizations_suspended', 'organizations_total', 'restaurants_total', 'server_ts',
        'subscriptions_active', 'subscriptions_canceled', 'subscriptions_past_due',
        'subscriptions_trialing'],
  'A7. exact key set — counts only, no money, no devices, no orders, no alerts');
select is((select (res->>'organizations_total')::int from a_ov), 5,
  'A8. organizations_total excludes the tombstoned org');
select is((select (res->>'organizations_active')::int from a_ov), 4, 'A9. organizations_active');
select is((select (res->>'organizations_suspended')::int from a_ov), 1, 'A10. organizations_suspended');
select is((select (res->>'restaurants_total')::int from a_ov), 4,
  'A11. restaurants_total excludes tombstoned restaurants AND the tombstoned org''s');
select is((select (res->>'branches_total')::int from a_ov), 4, 'A12. branches_total, same exclusions');
select is((select (res->>'active_memberships_total')::int from a_ov), 4,
  'A13. active_memberships_total counts Alpha''s 3 + Bravo''s 1, ignoring the revoked one');
select is((select (res->>'subscriptions_active')::int from a_ov), 1,
  'A14. subscriptions_active — the tombstoned org''s active subscription is NOT counted');
select is((select (res->>'subscriptions_trialing')::int from a_ov), 1, 'A15. subscriptions_trialing');
select is((select (res->>'subscriptions_past_due')::int from a_ov), 1, 'A16. subscriptions_past_due');
select is((select (res->>'subscriptions_canceled')::int from a_ov), 1, 'A17. subscriptions_canceled');

-- ===========================================================================
-- B. SUBSCRIBERS LIST (26)
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal2"}';

create temp table b_all as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)') as res;
create temp table b_search as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 50, 0, 'alp') as res;
create temp table b_status as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 50, 0, null, 'suspended') as res;
create temp table b_plan as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 50, 0, null, null, 'free') as res;
create temp table b_substatus as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 50, 0, null, null, null, 'past_due') as res;
create temp table b_page as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 2, 1) as res;
create temp table b_clamp_hi as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 9999) as res;
create temp table b_clamp_lo as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 0, -5) as res;
create temp table b_created as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 50, 0, null, null, null, null, 'created_desc') as res;
create temp table b_period as select public.platform_admin_list_subscribers(
  'RestoFlow admin: subscriber list (read-only)', 50, 0, null, null, null, null, 'period_end_asc') as res;

select throws_ok(
  $$ select public.platform_admin_list_subscribers('r', 50, 0, null, 'bogus') $$,
  '22023', NULL, 'B1. an unknown organization status is refused');
select throws_ok(
  $$ select public.platform_admin_list_subscribers('r', 50, 0, null, null, 'no-such-plan') $$,
  '22023', NULL, 'B2. a plan code that is not in plans is refused');
select throws_ok(
  $$ select public.platform_admin_list_subscribers('r', 50, 0, null, null, null, 'bogus') $$,
  '22023', NULL, 'B3. an unknown subscription status is refused');
select throws_ok(
  $$ select public.platform_admin_list_subscribers('r', 50, 0, null, null, null, null, 'bogus') $$,
  '22023', NULL, 'B4. an unknown sort key is refused (no dynamic SQL surface)');
reset role;

select is((select (res->>'ok')::boolean from b_all), true, 'B5. the list loads for a platform admin');
select is(
  (select array(select jsonb_object_keys(res) order by 1) from b_all),
  array['limit', 'offset', 'ok', 'rows', 'server_ts', 'total_count'],
  'B6. exact envelope keys');
select is(
  (select array(select jsonb_object_keys(res->'rows'->0) order by 1) from b_all),
  array['active_memberships_count', 'branches_count', 'created_at', 'current_period_end',
        'current_period_start', 'default_currency', 'organization_id', 'organization_name',
        'organization_status', 'plan_code', 'plan_display_name', 'restaurants_count',
        'subscription_status'],
  'B7. exact row projection — organization_id present, no created_by, no member PII, no price');
select is((select (res->>'total_count')::int from b_all), 5,
  'B8. total_count counts live organizations only');
select is(
  (select array_agg(r->>'organization_name' order by ord)
     from b_all, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['Alpha Group', 'Bravo Ltd', 'Charlie Co', 'Delta Inc', 'Golf LLC'],
  'B9. default sort is name_asc');
select is(
  (select r->>'organization_id' from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'),
  'c1000000-0000-0000-0000-0000000000a0',
  'B10. the organization id is returned — without it the console cannot open a detail page');

-- the joined subscription, and the honest null state
select is(
  (select r->>'plan_code' from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'), 'basic', 'B11. plan_code is joined');
select is(
  (select r->>'plan_display_name' from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'), 'Basic', 'B12. plan_display_name comes from plans');
select is(
  (select r->>'subscription_status' from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'), 'active', 'B13. subscription_status is joined');
select ok(
  (select (r->'current_period_end') is not null from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'), 'B14. the period is returned');
select ok(
  (select (r->'plan_code') = 'null'::jsonb
      and (r->'subscription_status') = 'null'::jsonb
      and (r->'current_period_start') = 'null'::jsonb
      and (r->'current_period_end') = 'null'::jsonb
     from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Bravo Ltd'),
  'B15. an organization with NO subscription returns NULL fields, never a fabricated plan');
select is(
  (select r->>'default_currency' from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Bravo Ltd'), 'EUR', 'B16. default_currency is returned');
select is(
  (select (r->>'created_at')::date from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Bravo Ltd'), '2026-02-01'::date,
  'B17. created_at is returned (the old overview only ORDER BYs it)');
select is(
  (select (r->>'restaurants_count')::int from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'), 2,
  'B18. restaurants_count excludes the tombstoned restaurant');
select is(
  (select (r->>'active_memberships_count')::int from b_all, jsonb_array_elements(res->'rows') r
    where r->>'organization_name' = 'Alpha Group'), 3,
  'B19. active_memberships_count ignores the revoked membership');

select is(
  (select array_agg(r->>'organization_name') from b_search, jsonb_array_elements(res->'rows') r),
  array['Alpha Group'], 'B20. search matches the organization name, case-insensitively');
select is((select (res->>'total_count')::int from b_search), 1,
  'B21. total_count reflects the FILTER, not the whole table');
select is(
  (select array_agg(r->>'organization_name') from b_status, jsonb_array_elements(res->'rows') r),
  array['Bravo Ltd'], 'B22. the organization-status filter works');
select is(
  (select array_agg(r->>'organization_name') from b_plan, jsonb_array_elements(res->'rows') r),
  array['Charlie Co'], 'B23. the plan filter works');
select is(
  (select array_agg(r->>'organization_name') from b_substatus, jsonb_array_elements(res->'rows') r),
  array['Delta Inc'], 'B24. the subscription-status filter works');
select is(
  (select array_agg(r->>'organization_name' order by ord)
     from b_created, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['Golf LLC', 'Delta Inc', 'Charlie Co', 'Bravo Ltd', 'Alpha Group'],
  'B25. created_desc sorts newest first');
select is(
  (select array_agg(r->>'organization_name' order by ord)
     from b_period, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['Delta Inc', 'Alpha Group', 'Charlie Co', 'Golf LLC', 'Bravo Ltd'],
  'B26. period_end_asc puts the unsubscribed organization LAST, deterministically');

-- ===========================================================================
-- B2. PAGINATION (5)
-- ===========================================================================
select is((select jsonb_array_length(res->'rows') from b_page), 2, 'B27. limit is honoured');
select is((select (res->>'offset')::int from b_page), 1, 'B28. offset is echoed');
select is(
  (select array_agg(r->>'organization_name' order by ord)
     from b_page, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['Bravo Ltd', 'Charlie Co'], 'B29. offset actually skips');
select is((select (res->>'total_count')::int from b_page), 5,
  'B30. total_count is independent of the page size');
select is(
  (select (res->>'limit')::int from b_clamp_hi) || '/' || (select (res->>'limit')::int from b_clamp_lo),
  '200/1', 'B31. limit is clamped to [1,200] server-side');

-- ===========================================================================
-- C. SUBSCRIBER DETAIL (13)
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf1","aal":"aal2"}';
select throws_ok(
  $$ select public.platform_admin_get_subscriber('c1000000-0000-0000-0000-0000000000a0',
       'RestoFlow admin: subscriber detail (read-only)') $$,
  '42501', NULL, 'C1. an org_owner is denied even for their OWN organization (platform plane)');
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal1"}';
select throws_ok(
  $$ select public.platform_admin_get_subscriber('c1000000-0000-0000-0000-0000000000a0', 'r') $$,
  '42501', NULL, 'C2. aal1 is denied');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select throws_ok(
  $$ select public.platform_admin_get_subscriber('c1000000-0000-0000-0000-0000000000a0', '') $$,
  '42501', NULL, 'C3. a blank reason is denied');
select throws_ok(
  $$ select public.platform_admin_get_subscriber('c1000000-0000-0000-0000-00000000ffff', 'r') $$,
  '42501', NULL, 'C4. an unknown organization raises 42501 — the same code as a denial, so a caller cannot probe existence');
select throws_ok(
  $$ select public.platform_admin_get_subscriber('c1000000-0000-0000-0000-0000000000e0', 'r') $$,
  '42501', NULL, 'C5. a TOMBSTONED organization is not retrievable');
create temp table c_alpha as select public.platform_admin_get_subscriber(
  'c1000000-0000-0000-0000-0000000000a0', 'RestoFlow admin: subscriber detail (read-only)') as res;
create temp table c_bravo as select public.platform_admin_get_subscriber(
  'c1000000-0000-0000-0000-0000000000b0', 'RestoFlow admin: subscriber detail (read-only)') as res;
reset role;

select is(
  (select array(select jsonb_object_keys(res) order by 1) from c_alpha),
  array['counts', 'ok', 'organization', 'restaurants', 'server_ts', 'subscription'],
  'C6. exact envelope keys');
select is(
  (select array(select jsonb_object_keys(res->'organization') order by 1) from c_alpha),
  array['created_at', 'default_currency', 'id', 'name', 'status'],
  'C7. the organization block withholds created_by_app_user_id and creation_request_id');
select is(
  (select array(select jsonb_object_keys(res->'counts') order by 1) from c_alpha),
  array['active_memberships_count', 'branches_count', 'restaurants_count'], 'C8. exact counts block');
select is(
  (select (res->'counts'->>'restaurants_count')::int || '/' ||
          (res->'counts'->>'branches_count')::int || '/' ||
          (res->'counts'->>'active_memberships_count')::int from c_alpha),
  '2/3/3', 'C9. counts match the fixtures and exclude tombstones/revoked');
select is(
  (select array(select jsonb_object_keys(res->'restaurants'->0) order by 1) from c_alpha),
  array['branches_count', 'id', 'name', 'status'], 'C10. the restaurants array is a safe projection');
select is(
  (select array_agg(r->>'name' order by ord)
     from c_alpha, jsonb_array_elements(res->'restaurants') with ordinality as t(r, ord)),
  array['Alpha One', 'Alpha Two'], 'C11. tombstoned restaurants are absent, order is deterministic');
select is(
  (select array(select jsonb_object_keys(res->'subscription') order by 1) from c_alpha),
  array['current_period_end', 'current_period_start', 'plan_code', 'plan_display_name', 'status'],
  'C12. the subscription block is exactly the five safe fields (no price)');
select ok((select (res->'subscription') = 'null'::jsonb from c_bravo),
  'C13. an organization with no subscription returns subscription: null');

-- ===========================================================================
-- D. RESTAURANTS LIST (12)
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf1","aal":"aal2"}';
select throws_ok(
  $$ select public.platform_admin_list_restaurants('RestoFlow admin: restaurant list (read-only)') $$,
  '42501', NULL, 'D1. an org_owner cannot read the platform-wide restaurant list');
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table d_all as select public.platform_admin_list_restaurants(
  'RestoFlow admin: restaurant list (read-only)') as res;
create temp table d_search as select public.platform_admin_list_restaurants(
  'RestoFlow admin: restaurant list (read-only)', 50, 0, 'bravo') as res;
create temp table d_status as select public.platform_admin_list_restaurants(
  'RestoFlow admin: restaurant list (read-only)', 50, 0, null, 'suspended') as res;
create temp table d_page as select public.platform_admin_list_restaurants(
  'RestoFlow admin: restaurant list (read-only)', 1, 0) as res;
select throws_ok(
  $$ select public.platform_admin_list_restaurants('r', 50, 0, null, null, 'bogus') $$,
  '22023', NULL, 'D2. an unknown sort key is refused');
reset role;

select is(
  (select array(select jsonb_object_keys(res->'rows'->0) order by 1) from d_all),
  array['branches_count', 'created_at', 'currency_override', 'effective_currency',
        'organization_id', 'organization_name', 'organization_status',
        'restaurant_id', 'restaurant_name', 'restaurant_status'],
  'D3. exact row projection — no financial, member or order keys');
select is((select (res->>'total_count')::int from d_all), 4,
  'D4. platform-wide: every live restaurant of every live organization');
select is(
  (select array_agg(r->>'restaurant_name' order by ord)
     from d_all, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['Alpha One', 'Alpha Two', 'Bravo One', 'Delta One'],
  'D5. default name_asc; the tombstoned restaurant and the tombstoned org''s are absent');
select is(
  (select r->>'organization_name' from d_all, jsonb_array_elements(res->'rows') r
    where r->>'restaurant_name' = 'Bravo One'), 'Bravo Ltd',
  'D6. each row carries its subscriber');
select is(
  (select r->>'organization_status' from d_all, jsonb_array_elements(res->'rows') r
    where r->>'restaurant_name' = 'Bravo One'), 'suspended',
  'D7. and the subscriber status, so a suspended tenant is visible in the list');
select is(
  (select (r->>'branches_count')::int from d_all, jsonb_array_elements(res->'rows') r
    where r->>'restaurant_name' = 'Alpha One'), 2, 'D8. branches_count is per restaurant');
select is(
  (select r->>'effective_currency' from d_all, jsonb_array_elements(res->'rows') r
    where r->>'restaurant_name' = 'Alpha One'), 'USD',
  'D9. effective_currency falls back to the organization default, matching app.list_menu');
select ok(
  (select (r->'currency_override') = 'null'::jsonb from d_all, jsonb_array_elements(res->'rows') r
    where r->>'restaurant_name' = 'Alpha One'),
  'D10. currency_override is reported honestly as null when unset');
select is(
  (select array_agg(r->>'restaurant_name') from d_search, jsonb_array_elements(res->'rows') r),
  array['Bravo One'], 'D11. search matches restaurant OR organization name');
select is(
  (select array_agg(r->>'restaurant_name') from d_status, jsonb_array_elements(res->'rows') r),
  array['Bravo One'], 'D12. the organization-status filter works');
select is((select jsonb_array_length(res->'rows') from d_page) || '/' ||
          (select (res->>'total_count')::int from d_page),
  '1/4', 'D13. pagination bounds the page but not the total');

-- ===========================================================================
-- E. AUDIT SEARCH (14)
-- ===========================================================================
-- Every read in groups A-D wrote its OWN audit row (that is the point of a
-- reason-tagged platform plane), and those rows carry today's timestamp — so
-- they are NEWER than the seeded fixtures. Each ordering assertion therefore
-- bounds the window to the seed range; that keeps the test deterministic no
-- matter how many reads ran before it, and it exercises the date filter at the
-- same time.
set local role authenticated;
set local request.jwt.claim.sub = 'c1000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table e_p1 as select public.platform_admin_audit_search(
  'RestoFlow admin: audit log (read-only)', 2, null, null, null, null,
  '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z') as res;
-- page 2 THROUGH THE CURSOR page 1 handed back: the keyset must continue
-- exactly where it stopped, with no repeat and no skip.
create temp table e_p2 as select public.platform_admin_audit_search(
  'RestoFlow admin: audit log (read-only)', 2,
  (select (res->'next_cursor'->>'occurred_at')::timestamptz from e_p1),
  (select (res->'next_cursor'->>'id')::uuid from e_p1),
  null, null, '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z') as res;
create temp table e_action as select public.platform_admin_audit_search(
  'RestoFlow admin: audit log (read-only)', 50, null, null, 'platform.subscriber.detail',
  null, '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z') as res;
create temp table e_org as select public.platform_admin_audit_search(
  'RestoFlow admin: audit log (read-only)', 50, null, null, null,
  'c1000000-0000-0000-0000-0000000000a0', '2026-05-01T00:00:00Z', '2026-05-31T23:59:59Z') as res;
create temp table e_range as select public.platform_admin_audit_search(
  'RestoFlow admin: audit log (read-only)', 50, null, null, null, null,
  '2026-05-02T00:00:00Z', '2026-05-03T23:59:59Z') as res;
create temp table e_clamp as select public.platform_admin_audit_search(
  'RestoFlow admin: audit log (read-only)', 9999) as res;
select throws_ok(
  $$ select public.platform_admin_audit_search('r', 50, '2026-05-01T00:00:00Z'::timestamptz, null) $$,
  '22023', NULL, 'E1. half a cursor is refused — both parts or neither');
reset role;

select is(
  (select array(select jsonb_object_keys(res) order by 1) from e_p1),
  array['has_more', 'limit', 'next_cursor', 'ok', 'rows', 'server_ts'],
  'E2. exact envelope with keyset cursor');
select is(
  (select array(select jsonb_object_keys(res->'rows'->0) order by 1) from e_p1),
  array['action', 'actor_app_user_id', 'id', 'occurred_at', 'reason', 'target_organization_id'],
  'E3. exact row projection — the details jsonb is NOT exposed');
select ok(
  (select not exists (select 1 from e_p1, jsonb_array_elements(res->'rows') r
                       where r::text like '%must-not-leak%')),
  'E4. and the secret seeded inside details never appears anywhere in the payload');
select ok(
  (select res::text not like '%@example.test%' from e_p1),
  'E5. no resolved actor email/name — the actor stays an opaque id in this phase');
select is((select jsonb_array_length(res->'rows') from e_p1), 2, 'E6. limit is honoured');
select is((select (res->>'has_more')::boolean from e_p1), true,
  'E7. has_more is true while a page remains');
select ok((select (res->'next_cursor') != 'null'::jsonb from e_p1), 'E8. a next cursor is returned');
select is(
  (select array_agg(r->>'reason' order by ord)
     from e_p1, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['seed 4', 'seed 3'], 'E9. newest-first ordering (occurred_at desc, id desc)');
select is(
  (select array_agg(r->>'reason' order by ord)
     from e_p2, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['seed 2', 'seed 1'],
  'E10. the cursor continues exactly where page 1 stopped — no duplicate, no gap');
select is((select (res->>'has_more')::boolean from e_p2), false,
  'E11. has_more is false on the last page');
select is(
  (select array_agg(r->>'reason' order by ord)
     from e_action, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['seed 3', 'seed 2'], 'E12. the action filter works');
select is(
  (select array_agg(r->>'reason') from e_org, jsonb_array_elements(res->'rows') r),
  array['seed 2'], 'E13. the target-organization filter works');
select is(
  (select array_agg(r->>'reason' order by ord)
     from e_range, jsonb_array_elements(res->'rows') with ordinality as t(r, ord)),
  array['seed 3', 'seed 2'], 'E14. the date range filters inclusively');
select is((select (res->>'limit')::int from e_clamp), 200, 'E15. the limit is clamped to 200');

-- ===========================================================================
-- F. ACL FAMILY GUARD + AUDIT WRITES (11)
-- ===========================================================================
-- REPORT-123, stated as a rule and enforced dynamically so a function added
-- later with the same mistake fails here without anyone extending a list.
select is(
  (select coalesce(string_agg(w.proname, ', ' order by w.proname), '')
     from pg_proc w
     join pg_namespace wn on wn.oid = w.pronamespace
     join pg_proc a on a.proname = w.proname
     join pg_namespace an on an.oid = a.pronamespace
    where wn.nspname = 'public' and an.nspname = 'app'
      and w.proname like 'platform\_admin\_%'
      and w.prosecdef = false
      and has_function_privilege('authenticated', w.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', a.oid, 'EXECUTE')),
  '', 'F1. no platform_admin_* wrapper is granted to authenticated while its app.* twin is not');
select cmp_ok(
  (select count(*)::int from pg_proc w join pg_namespace wn on wn.oid = w.pronamespace
    where wn.nspname = 'public' and w.proname like 'platform\_admin\_%'
      and w.prosecdef = false and has_function_privilege('authenticated', w.oid, 'EXECUTE')),
  '>=', 8, 'F2. the guard is NOT vacuous — it covers the 3 existing + 5 new wrappers');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('platform_admin_console_overview', 'platform_admin_list_subscribers',
                        'platform_admin_get_subscriber', 'platform_admin_list_restaurants',
                        'platform_admin_audit_search')
      and not p.prosecdef),
  5, 'F3. all five wrappers are SECURITY INVOKER');
select is(
  (select coalesce(string_agg(n.nspname || '.' || p.proname, ', ' order by p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public') and p.proname like 'platform\_admin\_%'
      and has_function_privilege('public', p.oid, 'EXECUTE')),
  '', 'F4. PUBLIC is revoked across the whole platform_admin family, both layers');
-- POS-124: hosted default privileges may grant anon EXECUTE on public functions,
-- so "anon holds no grant" is NOT the boundary. This is.
select ok(not has_schema_privilege('anon', 'app', 'USAGE'),
  'F5. anon holds no USAGE on schema app — every INVOKER wrapper is a dead end for it');
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname like 'platform\_admin\_%'
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  '', 'F6. anon may execute NO app.* platform implementation');

-- behavioural: anon actually fails, whatever the wrapper grant says
set local role anon;
select throws_ok(
  $$ select public.platform_admin_console_overview('r') $$,
  NULL, NULL, 'F7. an anon caller cannot complete the console overview');
select throws_ok(
  $$ select public.platform_admin_list_subscribers('r') $$,
  NULL, NULL, 'F8. an anon caller cannot complete the subscribers list');
reset role;

-- every read is reason-tagged and audited (D-013)
select is(
  (select count(*)::int from platform_admin_audit_events
    where action = 'platform.console.overview'
      and reason = 'RestoFlow admin: platform overview (read-only)'),
  1, 'F9. the console overview wrote ONE audit row carrying the page-specific reason');
select cmp_ok(
  (select count(*)::int from platform_admin_audit_events
    where action = 'platform.subscribers.list'
      and reason = 'RestoFlow admin: subscriber list (read-only)'),
  '>=', 1, 'F10. the subscribers list is audited with its own reason');
-- NOTE: every row written inside this test shares one occurred_at (now() is
-- TRANSACTION time), so "the latest row" is not a well-defined question here.
-- Assert the real property: each opened tenant produced its own tagged row.
select is(
  (select array_agg(distinct target_organization_id::text order by target_organization_id::text)
     from platform_admin_audit_events
    where action = 'platform.subscriber.detail'
      and reason = 'RestoFlow admin: subscriber detail (read-only)'),
  array['c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000b0'],
  'F11. subscriber detail records WHICH tenant was opened, for every tenant opened');

select * from finish();
rollback;
