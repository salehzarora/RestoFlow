-- ============================================================================
-- MVP — pgTAP: menu real access. The GUC-free app.menu_guard swap + app.list_menu.
-- CRITICAL new coverage: the PRODUCTION-JWT-SHAPE path — every authorized call
-- here sets ONLY the identity GUC (app.current_app_user_id) and NEVER
-- app.current_organization_id (the whole point of the swap: real dashboard
-- JWTs never set the org GUC). Covers: manager+ writes with no org GUC,
-- rank denial + committed denial audit, non-member/cross-org 42501, the
-- documented tightening (branch-scoped actor can no longer write
-- restaurant-wide branch-null rows), list_menu shape (tombstones out,
-- inactive in, children of returned parents, currency preference, branch
-- visibility, T-003-consistent role exclusion), and wrapper introspection.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(35);

-- ===== fixture: Org A (Rest A1: branches A1a/A1b; Rest A2 w/ currency override) =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000011700a00', 'Org A', 'mvpmenu-a', 'USD'),
  ('00000000-0000-0000-0000-000011700b00', 'Org B', 'mvpmenu-b', 'EUR');
insert into restaurants (id, organization_id, name, currency_override) values
  ('00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a00', 'Rest A1', null),
  ('00000000-0000-0000-0000-000011700a20', '00000000-0000-0000-0000-000011700a00', 'Rest A2', 'ILS'),
  ('00000000-0000-0000-0000-000011700b10', '00000000-0000-0000-0000-000011700b00', 'Rest B1', null);
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000011700a1a', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-000011700a1b', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', 'Branch A1b'),
  ('00000000-0000-0000-0000-000011700a2a', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a20', 'Branch A2a'),
  ('00000000-0000-0000-0000-000011700b1a', '00000000-0000-0000-0000-000011700b00', '00000000-0000-0000-0000-000011700b10', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000011700e01', 'mvpmenu-owner@example.test'),
  ('00000000-0000-0000-0000-000011700e02', 'mvpmenu-manager@example.test'),
  ('00000000-0000-0000-0000-000011700e03', 'mvpmenu-cashier@example.test'),
  ('00000000-0000-0000-0000-000011700e04', 'mvpmenu-kitchen@example.test'),
  ('00000000-0000-0000-0000-000011700e05', 'mvpmenu-nobody@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000011700f01', '00000000-0000-0000-0000-000011700e01', '00000000-0000-0000-0000-000011700a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000011700f02', '00000000-0000-0000-0000-000011700e02', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a', 'manager'),
  ('00000000-0000-0000-0000-000011700f03', '00000000-0000-0000-0000-000011700e03', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a', 'cashier'),
  ('00000000-0000-0000-0000-000011700f04', '00000000-0000-0000-0000-000011700e04', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a', 'kitchen_staff');
-- menu (Rest A1): categories — restaurant-wide, A1a-scoped, A1b-scoped, tombstoned.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, deleted_at) values
  ('00000000-0000-0000-0000-000011701001', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null,                                     'Cat Rest', null),
  ('00000000-0000-0000-0000-000011701002', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a', 'Cat A1a',  null),
  ('00000000-0000-0000-0000-000011701003', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1b', 'Cat A1b',  null),
  ('00000000-0000-0000-0000-000011701004', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null,                                     'Cat Dead', now());
-- items: live, INACTIVE (management view must include it), tombstoned.
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, is_active, deleted_at) values
  ('00000000-0000-0000-0000-000011702001', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011701001', 'Item Live', 1000, 'USD', true,  null),
  ('00000000-0000-0000-0000-000011702002', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011701001', 'Item Off',  500,  'USD', false, null),
  ('00000000-0000-0000-0000-000011702003', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011701001', 'Item Dead', 700,  'USD', true,  now());
-- children: live size, tombstoned size, size under a TOMBSTONED parent (must not resurface).
insert into item_sizes (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor, deleted_at) values
  ('00000000-0000-0000-0000-000011703001', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011702001', 'Size L',      200, null),
  ('00000000-0000-0000-0000-000011703002', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011702001', 'Size Dead',   0,   now()),
  ('00000000-0000-0000-0000-000011703003', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011702003', 'Size Orphan', 0,   null);
insert into item_variants (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-000011704001', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011702001', 'Var A', 0);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-000011705001', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011702001', 'Mod A');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, deleted_at) values
  ('00000000-0000-0000-0000-000011706001', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011705001', 'Opt A',    100, null),
  ('00000000-0000-0000-0000-000011706002', '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null, '00000000-0000-0000-0000-000011705001', 'Opt Dead', 0,   now());

-- ===== (1-13) list_menu happy path — org_owner, NO org GUC ever set ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';
create temp table t_menu_all as select app.list_menu(
  '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null) as res;
reset role;
select is((select (res->>'ok')::boolean from t_menu_all), true, 'org_owner lists the menu with NO org GUC set (ok:true)');
select is((select res->>'entity' from t_menu_all), 'menu', 'list_menu returns entity:menu');
select is((select res->>'currency_code' from t_menu_all), 'USD',
          'currency_code falls back to organizations.default_currency when the restaurant has no override');
select is((select jsonb_array_length(res->'categories') from t_menu_all), 3,
          'restaurant-wide listing returns 3 live categories (tombstoned excluded; both branch scopes included)');
select is((select count(*) from t_menu_all, jsonb_array_elements(res->'categories') e
            where e->>'id'='00000000-0000-0000-0000-000011701004')::int, 0,
          'a soft-deleted category is NOT returned');
select is((select jsonb_array_length(res->'items') from t_menu_all), 2,
          'items = 2 (live + inactive; tombstoned excluded)');
select is((select count(*) from t_menu_all, jsonb_array_elements(res->'items') e
            where e->>'id'='00000000-0000-0000-0000-000011702002' and (e->>'is_active')::boolean = false)::int, 1,
          'an is_active=false item IS returned (management view shows disabled rows)');
select is((select count(*) from t_menu_all, jsonb_array_elements(res->'items') e
            where e->>'id'='00000000-0000-0000-0000-000011702003')::int, 0,
          'a soft-deleted item is NOT returned');
select is((select (e->>'base_price_minor')::bigint from t_menu_all, jsonb_array_elements(res->'items') e
            where e->>'id'='00000000-0000-0000-0000-000011702001'), 1000::bigint,
          'items carry integer-minor base_price_minor (manager+ surface; no redaction)');
select is((select jsonb_array_length(res->'sizes') from t_menu_all), 1,
          'sizes = 1 (tombstoned size AND the size under a tombstoned item excluded)');
select is((select jsonb_array_length(res->'variants') from t_menu_all), 1,
          'variants = 1 (the live item child is returned)');
select is((select res->'modifiers'->0->>'id' from t_menu_all), '00000000-0000-0000-0000-000011705001',
          'the live modifier of a returned item is included');
select is((select count(*) from t_menu_all, jsonb_array_elements(res->'modifier_options') e)::int, 1,
          'modifier_options = 1 (Opt A; the tombstoned option excluded)');
-- every row of ALL SIX arrays carries the tenant keys organization_id /
-- restaurant_id / branch_id (the Dart fromJson factories require them; D-001).
select ok(
  (select bool_and(e ? 'organization_id' and e ? 'restaurant_id' and e ? 'branch_id')
     from t_menu_all,
          jsonb_array_elements(
            (res->'categories') || (res->'items') || (res->'sizes')
            || (res->'variants') || (res->'modifiers') || (res->'modifier_options')) e),
  'every returned row (all six entity arrays) carries organization_id + restaurant_id + branch_id');

-- ===== (14-15) branch visibility (p_branch = A1a) ==============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';
create temp table t_menu_a1a as select app.list_menu(
  '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a') as res;
reset role;
select is((select count(*) from t_menu_a1a, jsonb_array_elements(res->'categories') e
            where e->>'id'='00000000-0000-0000-0000-000011701003')::int, 0,
          'a sibling-branch (A1b) category is excluded when p_branch = A1a');
select is((select jsonb_array_length(res->'categories') from t_menu_a1a), 2,
          'branch view = 2 categories (the branch-null restaurant-wide row IS included + the A1a row)');

-- ===== (16) currency preference: restaurants.currency_override wins ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';
create temp table t_menu_a2 as select app.list_menu(
  '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a20', null) as res;
reset role;
select is((select res->>'currency_code' from t_menu_a2), 'ILS',
          'currency_code prefers restaurants.currency_override over the org default');

-- ===== (17-20) list_menu role/structural denials ===============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e03';  -- cashier
create temp table t_menu_cashier as select app.list_menu(
  '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a') as res;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e04';  -- kitchen_staff
create temp table t_menu_kitchen as select app.list_menu(
  '00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', '00000000-0000-0000-0000-000011700a1a') as res;
reset role;
select is((select res->>'error' from t_menu_cashier), 'permission_denied', 'cashier cannot list the management menu (permission_denied)');
select is((select res->>'error' from t_menu_kitchen), 'permission_denied', 'kitchen_staff cannot list the management menu (permission_denied; T-003-consistent)');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e05';  -- non-member
select throws_ok(
  $$ select app.list_menu('00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null) $$,
  '42501', NULL, 'a non-member cannot list the menu (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';  -- Org A owner
select throws_ok(
  $$ select app.list_menu('00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700b10', null) $$,
  '42501', NULL, 'a restaurant outside the passed org is structurally rejected (42501)');
reset role;

-- ===== (21-28) menu WRITES through the swapped guard — NO org GUC ever set =====
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';  -- org_owner
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-000011700a00','00000000-0000-0000-0000-000011700a10','00000000-0000-0000-0000-000011700a1a','00000000-0000-0000-0000-000011707001','Owner Cat',0,true) ->> 'action'),
  'created', 'org_owner (org-wide membership) can upsert a category with NO org GUC');
select is(
  (app.menu_upsert_item('00000000-0000-0000-0000-000011700a00','00000000-0000-0000-0000-000011700a10',null,'00000000-0000-0000-0000-000011707002','00000000-0000-0000-0000-000011701001','Owner Item',null,1200,'USD',null,0,true) ->> 'action'),
  'created', 'org_owner can upsert a restaurant-wide item with NO org GUC');
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e02';  -- manager @ A1a
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-000011700a00','00000000-0000-0000-0000-000011700a10','00000000-0000-0000-0000-000011700a1a','00000000-0000-0000-0000-000011707003','Mgr Cat',0,true) ->> 'action'),
  'created', 'a branch-scoped manager can upsert in their own branch with NO org GUC');
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e03';  -- cashier @ A1a
select is(
  (app.menu_upsert_category('00000000-0000-0000-0000-000011700a00','00000000-0000-0000-0000-000011700a10','00000000-0000-0000-0000-000011700a1a',null,'Cashier Cat',0,true) ->> 'error'),
  'permission_denied', 'an in-scope cashier is role-denied (permission_denied envelope, not 42501)');
reset role;
select is(
  (select count(*) from audit_events where action = 'menu.menu_category.upsert_denied'
     and actor_app_user_id = '00000000-0000-0000-0000-000011700e03')::int,
  1, 'the cashier denial still writes the committed menu.menu_category.upsert_denied audit row');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e05';  -- non-member
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-000011700a00','00000000-0000-0000-0000-000011700a10','00000000-0000-0000-0000-000011700a1a',null,'Nobody Cat',0,true) $$,
  '42501', NULL, 'a non-member write raises 42501 (fail closed, no audit)');
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';  -- Org A owner
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-000011700b00','00000000-0000-0000-0000-000011700b10','00000000-0000-0000-0000-000011700b1a',null,'CrossOrg Cat',0,true) $$,
  '42501', NULL, 'a cross-org p_org write raises 42501 (no covering membership in Org B)');
-- the ONE documented tightening: a branch-scoped actor can no longer write a
-- RESTAURANT-wide (branch_id null) row — actor_rank_in_scope has no
-- `target is null` escape (the old app.has_scope allowed this).
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e02';  -- manager @ A1a
select throws_ok(
  $$ select app.menu_upsert_category('00000000-0000-0000-0000-000011700a00','00000000-0000-0000-0000-000011700a10',null,null,'RestWide Cat',0,true) $$,
  '42501', NULL, 'MVP tightening: a branch-scoped manager writing a branch-null (restaurant-wide) category now raises 42501');
reset role;

-- ===== (29) public.list_menu delegates verbatim ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000011700e01';
select is(
  public.list_menu('00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null),
  app.list_menu('00000000-0000-0000-0000-000011700a00', '00000000-0000-0000-0000-000011700a10', null),
  'public.list_menu delegates verbatim to app.list_menu');
reset role;

-- ===== (30-34) wrapper introspection: invoker / search_path / grants ===========
select is(
  (select prosecdef from pg_proc where proname='list_menu' and pronamespace='public'::regnamespace and pronargs=3),
  false, 'public.list_menu is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='list_menu' and p.pronamespace='public'::regnamespace and p.pronargs=3
       and cfg like 'search_path=%')),
  'public.list_menu has a locked search_path');
select ok(
  not has_function_privilege('public', 'public.list_menu(uuid, uuid, uuid)', 'execute'),
  'PUBLIC may NOT execute public.list_menu (revoked)');
select ok(
  not has_function_privilege('anon', 'public.list_menu(uuid, uuid, uuid)', 'execute'),
  'anon may NOT execute public.list_menu');
select ok(
  has_function_privilege('authenticated', 'public.list_menu(uuid, uuid, uuid)', 'execute'),
  'authenticated MAY execute public.list_menu');

select * from finish();
rollback;
