-- ============================================================================
-- MVP — pgTAP: app.pos_menu / public.pos_menu (D-007, D-011, T-003, R-003)
-- ============================================================================
-- app.pos_menu returns the session restaurant's LIVE menu (is_active, not
-- soft-deleted, category live, branch_id null OR = session branch) with the
-- organization default_currency; money is integer minor (base_price_minor,
-- D-007). T-003: kitchen_staff receives items WITHOUT the base_price_minor key
-- (omitted, not nulled) — asserted absent. An other-branch item, a soft-deleted
-- item, and an inactive item are excluded. Invalid session / device mismatch
-- fail closed (42501); menu never crosses organizations (R-003). The one
-- public.pos_menu wrapper is SECURITY INVOKER, STABLE, search_path-locked,
-- authenticated-only (RF-064/RF-126 pattern). Fixtures inserted as the
-- BYPASSRLS connection role (pin_sessions inserted directly — the RF-056/RF-057
-- convention); app.pos_menu is SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(31);

-- ===== fixtures: org A, two branches; POS+cashier and KDS+kitchen on branch A1
insert into organizations (id, name, slug, default_currency) values
  ('30000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpm-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('30000000-0000-0000-0000-00000000a1b2', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', 'Branch A2');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('30000000-0000-0000-0000-00000000da11', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('30000000-0000-0000-0000-00000000da22', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('30000000-0000-0000-0000-00000000fa11', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-00000000da11', 'active'),
  ('30000000-0000-0000-0000-00000000fa22', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('30000000-0000-0000-0000-0000000005a1', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-00000000da11', '30000000-0000-0000-0000-00000000fa11'),
  ('30000000-0000-0000-0000-0000000005a2', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-00000000da22', '30000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('30000000-0000-0000-0000-00000000ee01', 'mvpm-cashier@example.test'),
  ('30000000-0000-0000-0000-00000000ee04', 'mvpm-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('30000000-0000-0000-0000-00000000ab01', '30000000-0000-0000-0000-00000000ee01', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('30000000-0000-0000-0000-00000000ab04', '30000000-0000-0000-0000-00000000ee04', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('30000000-0000-0000-0000-0000000ef001', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-00000000ee01', '30000000-0000-0000-0000-00000000ab01'),
  ('30000000-0000-0000-0000-0000000ef004', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-00000000ee04', '30000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-0000000005a1', '30000000-0000-0000-0000-0000000ef001', '30000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('30000000-0000-0000-0000-00000000c504', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b1', '30000000-0000-0000-0000-0000000005a2', '30000000-0000-0000-0000-0000000ef004', '30000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ===== fixtures: org B (own device/session + own menu) — isolation control ===
insert into organizations (id, name, slug, default_currency) values
  ('40000000-0000-0000-0000-0000000000b0', 'Org B', 'mvpm-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('40000000-0000-0000-0000-00000000b1b1', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('40000000-0000-0000-0000-00000000db11', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-00000000b1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('40000000-0000-0000-0000-00000000fb11', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-00000000b1b1', '40000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('40000000-0000-0000-0000-0000000005b1', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-00000000b1b1', '40000000-0000-0000-0000-00000000db11', '40000000-0000-0000-0000-00000000fb11');
insert into app_users (id, email) values
  ('40000000-0000-0000-0000-00000000ee02', 'mvpm-b-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('40000000-0000-0000-0000-00000000ab02', '40000000-0000-0000-0000-00000000ee02', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-00000000b1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('40000000-0000-0000-0000-0000000ef002', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-00000000b1b1', '40000000-0000-0000-0000-00000000ee02', '40000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('40000000-0000-0000-0000-00000000c502', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', '40000000-0000-0000-0000-00000000b1b1', '40000000-0000-0000-0000-0000000005b1', '40000000-0000-0000-0000-0000000ef002', '40000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- ===== fixtures: menu (RF-109 tables). 2 categories; 4 items: one live, one ==
-- ===== branch-scoped to ANOTHER branch, one soft-deleted, one inactive =======
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('30000000-0000-0000-0000-00000000ca01', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', null, 'Food', 1),
  ('30000000-0000-0000-0000-00000000ca02', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', null, 'Drinks', 2);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, description, base_price_minor, currency_code, display_order, is_active, deleted_at) values
  ('30000000-0000-0000-0000-0000000000f1', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', null,
   '30000000-0000-0000-0000-00000000ca01', 'Burger', 'House burger', 5000, 'USD', 1, true, null),
  ('30000000-0000-0000-0000-0000000000f2', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', '30000000-0000-0000-0000-00000000a1b2',
   '30000000-0000-0000-0000-00000000ca01', 'A2 Special', 'Only at branch A2', 7000, 'USD', 2, true, null),
  ('30000000-0000-0000-0000-0000000000f3', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', null,
   '30000000-0000-0000-0000-00000000ca01', 'Old Burger', 'Retired', 4000, 'USD', 3, true, now()),
  ('30000000-0000-0000-0000-0000000000f4', '30000000-0000-0000-0000-0000000000a0', '30000000-0000-0000-0000-0000000000a1', null,
   '30000000-0000-0000-0000-00000000ca02', 'Flat Cola', 'Deactivated', 1500, 'USD', 1, false, null);
-- org B menu
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('40000000-0000-0000-0000-00000000cb01', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', null, 'B Cat', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('40000000-0000-0000-0000-0000000000fb', '40000000-0000-0000-0000-0000000000b0', '40000000-0000-0000-0000-0000000000b1', null,
   '40000000-0000-0000-0000-00000000cb01', 'B Tea', 900, 'EUR', 1);

-- ===== (1-5) cashier session: envelope + org currency + ordered categories ===
select is(
  (app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') ->> 'ok')::boolean,
  true, 'cashier pos_menu returns ok:true');
select is(
  (app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') ->> 'entity'),
  'menu', 'pos_menu returns entity=menu');
select is(
  (app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') ->> 'currency_code'),
  'USD', 'currency_code is the organization default_currency (USD)');
select is(
  jsonb_array_length(app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'categories'),
  2, 'cashier receives both live categories');
select is(
  (app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'categories' -> 0 ->> 'name'),
  'Food', 'categories are ordered by display_order (Food first)');

-- ===== (6-8) cashier items: only the live branch-visible item, WITH price ====
select is(
  jsonb_array_length(app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items'),
  1, 'cashier receives exactly the one live, branch-visible item');
select is(
  (app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items' -> 0 ->> 'name'),
  'Burger', 'the visible item is Burger');
select ok(
  (select (it ? 'base_price_minor') and (it ->> 'base_price_minor')::bigint = 5000
   from (select app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items' -> 0 as it) s),
  'the cashier item carries base_price_minor = 5000 (integer minor, D-007)');

-- ===== (9-12) kitchen session: money key OMITTED (T-003), menu still usable ==
select ok(
  not ((app.pos_menu('30000000-0000-0000-0000-00000000c504', '30000000-0000-0000-0000-00000000da22') -> 'items' -> 0) ? 'base_price_minor'),
  'the kitchen item has NO base_price_minor key (omitted, not nulled — T-003)');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(app.pos_menu('30000000-0000-0000-0000-00000000c504', '30000000-0000-0000-0000-00000000da22') -> 'items') as it
    cross join lateral jsonb_object_keys(it) as k
    where k like '%minor%'),
  'NO kitchen item carries any money (*minor*) key at all (T-003 defence sweep)');
select is(
  (app.pos_menu('30000000-0000-0000-0000-00000000c504', '30000000-0000-0000-0000-00000000da22') -> 'items' -> 0 ->> 'name'),
  'Burger', 'the kitchen session still receives the item name (menu usable without money)');
select is(
  jsonb_array_length(app.pos_menu('30000000-0000-0000-0000-00000000c504', '30000000-0000-0000-0000-00000000da22') -> 'categories'),
  2, 'the kitchen session receives the categories (no money on categories)');

-- ===== (13-15) exclusions: other-branch / soft-deleted / inactive ============
select ok(
  not exists (
    select 1 from jsonb_array_elements(app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items') as it
    where it ->> 'name' = 'A2 Special'),
  'an item branch-scoped to ANOTHER branch is excluded');
select ok(
  not exists (
    select 1 from jsonb_array_elements(app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items') as it
    where it ->> 'name' = 'Old Burger'),
  'a soft-deleted item is excluded (live menu, not the sync feed)');
select ok(
  not exists (
    select 1 from jsonb_array_elements(app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items') as it
    where it ->> 'name' = 'Flat Cola'),
  'an inactive item is excluded');

-- ===== (16-17) fail-closed: invalid session / device mismatch ================
select throws_ok(
  $$ select app.pos_menu('30000000-0000-0000-0000-0000000000ff', '30000000-0000-0000-0000-00000000da11') $$,
  '42501', NULL, 'a non-existent PIN session is rejected fail-closed (42501)');
select throws_ok(
  $$ select app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da22') $$,
  '42501', NULL, 'a device_id not matching the PIN session device is rejected (42501)');

-- ===== (18-20) cross-org isolation (R-003) ===================================
select ok(
  not exists (
    select 1 from jsonb_array_elements(app.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') -> 'items') as it
    where it ->> 'name' = 'B Tea'),
  'the org A session never sees the org B menu item');
select ok(
  (select m ->> 'currency_code' = 'EUR'
      and jsonb_array_length(m -> 'items') = 1
      and m -> 'items' -> 0 ->> 'name' = 'B Tea'
   from (select app.pos_menu('40000000-0000-0000-0000-00000000c502', '40000000-0000-0000-0000-00000000db11') as m) s),
  'the org B session gets ONLY the org B menu with the org B currency (EUR)');
select ok(
  not exists (
    select 1 from jsonb_array_elements(app.pos_menu('40000000-0000-0000-0000-00000000c502', '40000000-0000-0000-0000-00000000db11') -> 'categories') as c
    where c ->> 'name' = 'Food'),
  'the org B session never sees an org A category');

-- ===== (21-28) wrapper introspection: existence / type / INVOKER / search_path
-- ===== / STABLE / grants (RF-064/RF-126 pattern) ==============================
select has_function('public', 'pos_menu', array['uuid', 'uuid'], 'public.pos_menu(uuid, uuid) exists');
select is(
  (select format_type(prorettype, null) from pg_proc where proname = 'pos_menu' and pronamespace = 'public'::regnamespace),
  'jsonb', 'public.pos_menu returns jsonb');
select is(
  (select prosecdef from pg_proc where proname = 'pos_menu' and pronamespace = 'public'::regnamespace),
  false, 'public.pos_menu is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname = 'pos_menu' and p.pronamespace = 'public'::regnamespace
       and cfg like 'search_path=%')),
  'public.pos_menu has a locked search_path');
select is(
  (select provolatile from pg_proc where proname = 'pos_menu' and pronamespace = 'public'::regnamespace),
  's', 'public.pos_menu is STABLE (pure read)');
select ok(
  not has_function_privilege('public', 'public.pos_menu(uuid, uuid)', 'execute'),
  'PUBLIC may NOT execute public.pos_menu (revoked)');
select ok(
  not has_function_privilege('anon', 'public.pos_menu(uuid, uuid)', 'execute'),
  'anon may NOT execute public.pos_menu (authenticated-only)');
select ok(
  has_function_privilege('authenticated', 'public.pos_menu(uuid, uuid)', 'execute'),
  'authenticated MAY execute public.pos_menu');

-- ===== (29-30) delegate posture: app.pos_menu DEFINER + authenticated-only ===
select is(
  (select prosecdef from pg_proc where proname = 'pos_menu' and pronamespace = 'app'::regnamespace),
  true, 'app.pos_menu is SECURITY DEFINER (D-011)');
select ok(
  has_function_privilege('authenticated', 'app.pos_menu(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'app.pos_menu(uuid, uuid)', 'execute'),
  'authenticated (and NOT anon) may execute app.pos_menu');

-- ===== (31) the wrapper delegates verbatim ===================================
select is(
  (public.pos_menu('30000000-0000-0000-0000-00000000c501', '30000000-0000-0000-0000-00000000da11') ->> 'ok')::boolean,
  true, 'public.pos_menu delegates to app.pos_menu (ok:true through the wrapper)');

select * from finish();
rollback;
