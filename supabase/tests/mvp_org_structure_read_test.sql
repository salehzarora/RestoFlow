-- ============================================================================
-- MVP — pgTAP: app.list_org_structure (GUC-free org -> restaurants -> branches
-- READ). Owner reads the tree (org name + default_currency, nested branches,
-- created_at-then-name ordering = deterministic first-pick, currency_override
-- surfaced); a branch-scoped manager of the SAME org CAN read (the documented
-- deliberately-not-scope-covering decision); cashier -> permission_denied;
-- other-org actor / membershipless -> 42501; tombstoned restaurants/branches
-- (deleted_at, D-020) excluded; wrapper introspection. GUC-FREE: only the
-- identity GUC is ever set (production-JWT shape), never the org GUC.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(22);

-- ===== fixture: Org S (2 live + 1 dead restaurant; branch ordering probes) =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000011800a00', 'Org Struct A', 'mvporgstruct-a', 'USD'),
  ('00000000-0000-0000-0000-000011800b00', 'Org Struct B', 'mvporgstruct-b', 'EUR');
-- created_at is set EXPLICITLY so ordering is deterministic in-txn:
-- 'Zeta Rest' is alphabetically LAST but created FIRST => must sort first
-- (created_at takes precedence over name).
insert into restaurants (id, organization_id, name, currency_override, timezone, created_at, deleted_at) values
  ('00000000-0000-0000-0000-000011800a10', '00000000-0000-0000-0000-000011800a00', 'Alpha Rest', 'ILS', 'Asia/Jerusalem', '2021-01-01T00:00:00Z', null),
  ('00000000-0000-0000-0000-000011800a20', '00000000-0000-0000-0000-000011800a00', 'Zeta Rest',  null,  null,             '2020-01-01T00:00:00Z', null),
  ('00000000-0000-0000-0000-000011800a30', '00000000-0000-0000-0000-000011800a00', 'Dead Rest',  null,  null,             '2019-01-01T00:00:00Z', now()),
  ('00000000-0000-0000-0000-000011800b10', '00000000-0000-0000-0000-000011800b00', 'Org B Rest', null,  null,             '2020-01-01T00:00:00Z', null);
-- Alpha Rest branches: 'Zed Branch' created first (must sort first), 'Alpha
-- Branch' second, plus a tombstoned one that must never resurface.
insert into branches (id, organization_id, restaurant_id, name, timezone, created_at, deleted_at) values
  ('00000000-0000-0000-0000-000011800a1a', '00000000-0000-0000-0000-000011800a00', '00000000-0000-0000-0000-000011800a10', 'Zed Branch',   'Asia/Jerusalem', '2021-01-02T00:00:00Z', null),
  ('00000000-0000-0000-0000-000011800a1b', '00000000-0000-0000-0000-000011800a00', '00000000-0000-0000-0000-000011800a10', 'Alpha Branch', null,             '2021-01-03T00:00:00Z', null),
  ('00000000-0000-0000-0000-000011800a1e', '00000000-0000-0000-0000-000011800a00', '00000000-0000-0000-0000-000011800a10', 'Dead Branch',  null,             '2021-01-04T00:00:00Z', now()),
  ('00000000-0000-0000-0000-000011800a2a', '00000000-0000-0000-0000-000011800a00', '00000000-0000-0000-0000-000011800a20', 'Zeta Main',    null,             '2020-01-02T00:00:00Z', null),
  ('00000000-0000-0000-0000-000011800b1a', '00000000-0000-0000-0000-000011800b00', '00000000-0000-0000-0000-000011800b10', 'Org B Main',   null,             '2020-01-02T00:00:00Z', null);
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000011800e01', 'mvporgstruct-owner@example.test'),
  ('00000000-0000-0000-0000-000011800e02', 'mvporgstruct-branchmgr@example.test'),
  ('00000000-0000-0000-0000-000011800e03', 'mvporgstruct-cashier@example.test'),
  ('00000000-0000-0000-0000-000011800e04', 'mvporgstruct-otherorg@example.test'),
  ('00000000-0000-0000-0000-000011800e05', 'mvporgstruct-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000011800f01', '00000000-0000-0000-0000-000011800e01', '00000000-0000-0000-0000-000011800a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000011800f02', '00000000-0000-0000-0000-000011800e02', '00000000-0000-0000-0000-000011800a00', '00000000-0000-0000-0000-000011800a10', '00000000-0000-0000-0000-000011800a1a', 'manager'),
  ('00000000-0000-0000-0000-000011800f03', '00000000-0000-0000-0000-000011800e03', '00000000-0000-0000-0000-000011800a00', '00000000-0000-0000-0000-000011800a10', '00000000-0000-0000-0000-000011800a1a', 'cashier'),
  ('00000000-0000-0000-0000-000011800f04', '00000000-0000-0000-0000-000011800e04', '00000000-0000-0000-0000-000011800b00', null, null, 'org_owner');

-- ===== (1-12) org_owner reads the structure (NO org GUC ever set) ==============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011800e01';
create temp table t_struct as select app.list_org_structure('00000000-0000-0000-0000-000011800a00') as res;
reset role;
select is((select (res->>'ok')::boolean from t_struct), true, 'org_owner reads the org structure (ok:true)');
select is((select res->>'entity' from t_struct), 'org_structure', 'list_org_structure returns entity:org_structure');
select is((select res->'organization'->>'name' from t_struct), 'Org Struct A', 'the organization object carries its name');
select is((select res->'organization'->>'default_currency' from t_struct), 'USD',
          'the organization object carries default_currency (the real tenant currency source)');
select is((select jsonb_array_length(res->'restaurants') from t_struct), 2,
          'restaurants = 2 live (the tombstoned restaurant is excluded)');
select is((select res->'restaurants'->0->>'name' from t_struct), 'Zeta Rest',
          'restaurants are ordered by created_at then name (deterministic first-pick)');
select is((select res->'restaurants'->0->>'status' from t_struct), 'active',
          'each restaurant carries its status (suspension filtering is the client''s decision)');
select is((select e->>'currency_override' from t_struct, jsonb_array_elements(res->'restaurants') e
            where e->>'name'='Alpha Rest'), 'ILS',
          'a restaurant''s currency_override is surfaced');
select is((select jsonb_array_length(e->'branches') from t_struct, jsonb_array_elements(res->'restaurants') e
            where e->>'name'='Alpha Rest'), 2,
          'nested branches = 2 live (the tombstoned branch is excluded)');
select is((select e->'branches'->0->>'name' from t_struct, jsonb_array_elements(res->'restaurants') e
            where e->>'name'='Alpha Rest'), 'Zed Branch',
          'branches are ordered by created_at then name (deterministic first-pick)');
select is((select count(*) from t_struct, jsonb_array_elements(res->'restaurants') e
            where e->>'id'='00000000-0000-0000-0000-000011800a30')::int, 0,
          'a soft-deleted restaurant is NOT returned (D-020)');
select is((select count(*) from t_struct, jsonb_array_elements(res->'restaurants') e,
                 jsonb_array_elements(e->'branches') b
            where b->>'id'='00000000-0000-0000-0000-000011800a1e')::int, 0,
          'a soft-deleted branch is NOT returned (D-020)');

-- ===== (13) branch-scoped manager of the SAME org CAN read ====================
-- documented decision: the rank gate is membership rank ANYWHERE in the org,
-- deliberately NOT scope-covering (structure names/currency only; the caller
-- already sees these names via get_my_context).
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011800e02';
create temp table t_mgr as select app.list_org_structure('00000000-0000-0000-0000-000011800a00') as res;
reset role;
select is((select (res->>'ok')::boolean from t_mgr), true,
          'a branch-scoped manager CAN read their own org''s structure (deliberately not scope-covering)');

-- ===== (14) cashier -> permission_denied ======================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011800e03';
create temp table t_cashier as select app.list_org_structure('00000000-0000-0000-0000-000011800a00') as res;
reset role;
select is((select res->>'error' from t_cashier), 'permission_denied',
          'a cashier cannot read the org structure (permission_denied)');

-- ===== (15-16) other-org actor / membershipless -> 42501 (fail closed) ========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011800e04';  -- org_owner of Org B only
select throws_ok(
  $$ select app.list_org_structure('00000000-0000-0000-0000-000011800a00') $$,
  '42501', NULL, 'an Org B owner cannot read Org A structure (cross-org 42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-000011800e05';  -- no memberships at all
select throws_ok(
  $$ select app.list_org_structure('00000000-0000-0000-0000-000011800a00') $$,
  '42501', NULL, 'a membershipless principal cannot read any org structure (42501)');
reset role;

-- ===== (17) public.* wrapper delegates verbatim ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011800e01';
select is(
  public.list_org_structure('00000000-0000-0000-0000-000011800a00'),
  app.list_org_structure('00000000-0000-0000-0000-000011800a00'),
  'public.list_org_structure delegates verbatim to app.list_org_structure');
reset role;

-- ===== (18-22) wrapper introspection: invoker / search_path / grants ===========
select is(
  (select prosecdef from pg_proc where proname='list_org_structure' and pronamespace='public'::regnamespace and pronargs=1),
  false, 'public.list_org_structure is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='list_org_structure' and p.pronamespace='public'::regnamespace and p.pronargs=1
       and cfg like 'search_path=%')),
  'public.list_org_structure has a locked search_path');
select ok(
  not has_function_privilege('public', 'public.list_org_structure(uuid)', 'execute'),
  'PUBLIC may NOT execute public.list_org_structure (revoked)');
select ok(
  not has_function_privilege('anon', 'public.list_org_structure(uuid)', 'execute'),
  'anon may NOT execute public.list_org_structure');
select ok(
  has_function_privilege('authenticated', 'public.list_org_structure(uuid)', 'execute'),
  'authenticated MAY execute public.list_org_structure');

select * from finish();
rollback;
