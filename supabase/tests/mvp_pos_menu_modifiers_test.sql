-- ============================================================================
-- MVP — pgTAP: app.pos_menu sizes/variants/modifiers/modifier_options + the
-- tenant currency fix (D-007, D-011, T-003, R-003)
-- ============================================================================
-- The replaced app.pos_menu (20260703130000) returns FOUR new arrays alongside
-- categories/items. Live filtering matches items exactly: is_active +
-- deleted_at null + LIVE parent chain (option -> modifier -> item -> category)
-- + branch visibility (branch_id null OR = session branch). T-003: a kitchen
-- session receives NO price_delta_minor key anywhere (omitted, not nulled);
-- the cashier session DOES (signed integer minor, D-007). currency_code now
-- honors restaurants.currency_override -> organizations.default_currency (the
-- FALLBACK path stays covered by mvp_pos_menu_test.sql, whose restaurant has
-- no override and still asserts the org default). The public.pos_menu wrapper
-- is untouched and keeps delegating. Fixtures inserted as the BYPASSRLS
-- connection role (RF-056/RF-057 convention); app.pos_menu is SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(19);

-- ===== fixtures: org (USD default), restaurant WITH currency_override ILS ====
insert into organizations (id, name, slug, default_currency) values
  ('60000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpmm-a', 'USD');
insert into restaurants (id, organization_id, name, currency_override) values
  ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000a0', 'Rest A1', 'ILS');
insert into branches (id, organization_id, restaurant_id, name) values
  ('60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('60000000-0000-0000-0000-00000000a1b2', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', 'Branch A2');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('60000000-0000-0000-0000-00000000da11', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('60000000-0000-0000-0000-00000000da22', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('60000000-0000-0000-0000-00000000fa11', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000da11', 'active'),
  ('60000000-0000-0000-0000-00000000fa22', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('60000000-0000-0000-0000-0000000005a1', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000da11', '60000000-0000-0000-0000-00000000fa11'),
  ('60000000-0000-0000-0000-0000000005a2', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000da22', '60000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('60000000-0000-0000-0000-00000000ee01', 'mvpmm-cashier@example.test'),
  ('60000000-0000-0000-0000-00000000ee04', 'mvpmm-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('60000000-0000-0000-0000-00000000ab01', '60000000-0000-0000-0000-00000000ee01', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('60000000-0000-0000-0000-00000000ab04', '60000000-0000-0000-0000-00000000ee04', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('60000000-0000-0000-0000-0000000ef001', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000ee01', '60000000-0000-0000-0000-00000000ab01'),
  ('60000000-0000-0000-0000-0000000ef004', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000ee04', '60000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('60000000-0000-0000-0000-00000000c501', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-0000000005a1', '60000000-0000-0000-0000-0000000ef001', '60000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('60000000-0000-0000-0000-00000000c504', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-0000000005a2', '60000000-0000-0000-0000-0000000ef004', '60000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ===== fixtures: menu — one live item; children exercising every filter ======
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('60000000-0000-0000-0000-00000000ca01', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('60000000-0000-0000-0000-0000000000f1', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null,
   '60000000-0000-0000-0000-00000000ca01', 'Burger', 5000, 'ILS', 1, true),
  ('60000000-0000-0000-0000-0000000000f2', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null,
   '60000000-0000-0000-0000-00000000ca01', 'Retired', 4000, 'ILS', 2, false);
-- sizes: live / tombstoned / dead-parent / other-branch
insert into item_sizes (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor, display_order, deleted_at) values
  ('60000000-0000-0000-0000-000000000501', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-0000000000f1', 'Large',      500, 1, null),
  ('60000000-0000-0000-0000-000000000502', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-0000000000f1', 'DeadSize',   200, 2, now()),
  ('60000000-0000-0000-0000-000000000503', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-0000000000f2', 'OrphanSize', 100, 3, null),
  ('60000000-0000-0000-0000-000000000504', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b2', '60000000-0000-0000-0000-0000000000f1', 'A2Size', 300, 4, null);
-- variants: one live with a NEGATIVE (signed) delta
insert into item_variants (id, organization_id, restaurant_id, branch_id, menu_item_id, name, price_delta_minor, display_order) values
  ('60000000-0000-0000-0000-000000000601', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-0000000000f1', 'Mini', -200, 1);
-- modifiers: one live 'multiple' picker; one inactive (its live option must vanish)
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, display_order, is_active) values
  ('60000000-0000-0000-0000-000000000701', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-0000000000f1', 'Toppings', 'multiple', 0, 3, false, 1, true),
  ('60000000-0000-0000-0000-000000000702', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-0000000000f1', 'DeadMod',  'single',   0, null, false, 2, false);
-- options: live / inactive / tombstoned under the live modifier; live under the DEAD one
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, deleted_at) values
  ('60000000-0000-0000-0000-000000000801', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-000000000701', 'Cheese',   100, 1, true,  null),
  ('60000000-0000-0000-0000-000000000802', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-000000000701', 'FlatOpt',   50, 2, false, null),
  ('60000000-0000-0000-0000-000000000803', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-000000000701', 'GoneOpt',   75, 3, true,  now()),
  ('60000000-0000-0000-0000-000000000804', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', null, '60000000-0000-0000-0000-000000000702', 'GhostOpt',  25, 1, true,  null);

-- cache both payloads once (STABLE read; no role switch needed — session-authorized)
create temp table t_cash as select app.pos_menu('60000000-0000-0000-0000-00000000c501', '60000000-0000-0000-0000-00000000da11') as m;
create temp table t_kitchen as select app.pos_menu('60000000-0000-0000-0000-00000000c504', '60000000-0000-0000-0000-00000000da22') as m;

-- ===== (1-3) envelope + currency override + base regression ==================
select is((select (m->>'ok')::boolean from t_cash), true, 'cashier pos_menu returns ok:true');
select is((select m->>'currency_code' from t_cash), 'ILS',
          'currency_code honors restaurants.currency_override (ILS, not the USD org default)');
select ok((select jsonb_array_length(m->'categories') = 1 and jsonb_array_length(m->'items') = 1 from t_cash),
          'categories/items regression: the live category + the one live item are still returned');

-- ===== (4-7) sizes: live filtering identical to items ========================
select is((select jsonb_array_length(m->'sizes') from t_cash), 1,
          'exactly ONE size survives (tombstoned, dead-parent and other-branch sizes excluded)');
select ok(
  (select r->>'id' = '60000000-0000-0000-0000-000000000501'
      and r->>'menu_item_id' = '60000000-0000-0000-0000-0000000000f1'
      and (r->>'price_delta_minor')::bigint = 500
   from (select m->'sizes'->0 as r from t_cash) s),
  'the size row carries menu_item_id + price_delta_minor = 500 (integer minor, D-007)');
select ok(
  (select not exists (select 1 from t_cash, jsonb_array_elements(m->'sizes') e
                      where e->>'id' in ('60000000-0000-0000-0000-000000000502',
                                         '60000000-0000-0000-0000-000000000504'))),
  'the tombstoned size and the other-branch size are excluded');
select ok(
  (select not exists (select 1 from t_cash, jsonb_array_elements(m->'sizes') e
                      where e->>'id' = '60000000-0000-0000-0000-000000000503')),
  'a size under an INACTIVE item is excluded (live parent chain)');

-- ===== (8) variants: same treatment; SIGNED delta ============================
select ok(
  (select jsonb_array_length(m->'variants') = 1
      and (m->'variants'->0->>'price_delta_minor')::bigint = -200 from t_cash),
  'the one live variant is returned with its SIGNED price_delta_minor (-200)');

-- ===== (9-12) modifiers + options ============================================
select is((select jsonb_array_length(m->'modifiers') from t_cash), 1,
          'exactly ONE modifier survives (the inactive modifier is excluded)');
select ok(
  (select r->>'selection_type' = 'multiple' and (r->>'min_select')::int = 0
      and (r->>'max_select')::int = 3 and (r->>'is_required')::boolean = false
      and r->>'menu_item_id' = '60000000-0000-0000-0000-0000000000f1'
   from (select m->'modifiers'->0 as r from t_cash) s),
  'the modifier row carries the selection rules (selection_type/min/max/is_required)');
select ok(
  (select jsonb_array_length(m->'modifier_options') = 1
      and m->'modifier_options'->0->>'id' = '60000000-0000-0000-0000-000000000801'
      and m->'modifier_options'->0->>'modifier_id' = '60000000-0000-0000-0000-000000000701'
      and (m->'modifier_options'->0->>'price_delta_minor')::bigint = 100
   from t_cash),
  'exactly ONE option survives, with modifier_id + price_delta_minor = 100 (cashier sees money)');
select ok(
  (select not exists (select 1 from t_cash, jsonb_array_elements(m->'modifier_options') e
                      where e->>'id' = '60000000-0000-0000-0000-000000000804')),
  'a LIVE option under an INACTIVE modifier is excluded (live parent chain)');

-- ===== (13-17) kitchen session: T-003 money-key omission =====================
select is((select jsonb_array_length(m->'sizes') from t_kitchen), 1,
          'the kitchen session still receives the size row (menu usable without money)');
select ok(
  (select not ((m->'sizes'->0) ? 'price_delta_minor') from t_kitchen),
  'the kitchen size row has NO price_delta_minor key (omitted, not nulled — T-003)');
select ok(
  (select not ((m->'modifier_options'->0) ? 'price_delta_minor') from t_kitchen),
  'the kitchen option row has NO price_delta_minor key either');
select ok(
  (select not exists (
     select 1
     from t_kitchen,
          lateral jsonb_array_elements((m->'items') || (m->'sizes') || (m->'variants')
                                       || (m->'modifiers') || (m->'modifier_options')) as it,
          lateral jsonb_object_keys(it) as k
     where k like '%minor%')),
  'NO kitchen row in ANY of the five arrays carries any money (*minor*) key (T-003 defence sweep)');
select ok(
  (select m->'modifier_options'->0->>'name' = 'Cheese'
      and m->'modifiers'->0->>'name' = 'Toppings' from t_kitchen),
  'the kitchen session still receives modifier/option names (KDS-usable without money)');

-- ===== (18-19) wrapper regression: public.pos_menu untouched, delegates ======
select is(
  (public.pos_menu('60000000-0000-0000-0000-00000000c501', '60000000-0000-0000-0000-00000000da11') ->> 'currency_code'),
  'ILS', 'public.pos_menu (untouched wrapper) delegates to the replaced body (currency override visible)');
select is(
  jsonb_array_length(public.pos_menu('60000000-0000-0000-0000-00000000c501', '60000000-0000-0000-0000-00000000da11') -> 'sizes'),
  1, 'public.pos_menu exposes the new sizes array through the same wrapper');

select * from finish();
rollback;
