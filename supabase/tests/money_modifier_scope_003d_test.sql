-- ============================================================================
-- MONEY-SERVER-MODIFIER-SCOPE-003D — pgTAP: modifier option identity + ownership
-- ============================================================================
-- `public.order_item_modifiers.modifier_option_id` is a deliberately NON-FK
-- column (RF-052 A1). Before 20260806090000 both app.submit_order and
-- app.add_order_items validated the arithmetic and the snapshot shape but never
-- checked that the named option EXISTS, belongs to this ORGANIZATION, or belongs
-- to the ITEM it was submitted under. A modified authenticated client could
-- submit a structurally perfect, arithmetically consistent modifier snapshot for
-- an option belonging to another item or another tenant — declaring its own
-- price for it.
--
-- WHAT THIS SUITE PINS
--   * nonexistent / foreign-organization / wrong-item options are REFUSED under
--     ONE uniform code, `modifier_option_not_in_scope`, so the refusal is not an
--     existence oracle for another tenant's ids (R-003);
--   * the refusal is ATOMIC — no order, no order_items, no order_item_modifiers,
--     no service round, and no change to an existing order's totals;
--   * a valid same-item option is ACCEPTED and its SUBMITTED snapshot price is
--     stored verbatim (D-008) — never the live catalogue price;
--   * a SOFT-DELETED or INACTIVE same-item option is still ACCEPTED, because a
--     cart captured offline can legitimately name one (app.menu_soft_delete
--     tombstones exactly one row and app.pos_menu ships only live options);
--   * a legitimate integer ZERO delta stays legitimate;
--   * idempotent replay of a refusal stays refused, and replay of a valid
--     Add-items returns the SAME round.
--
-- Fixtures are inserted as the BYPASSRLS connection role, like every sibling
-- suite. Money is integer minor units throughout (D-007).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(34);

-- ---------------------------------------------------------------- org A scope
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00000003d0a0', 'Org 003D A', 'm003d-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d0a0', 'Rest A');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000003d1b1', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', 'Branch A');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000003dd11', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000003df11', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d1b1', '00000000-0000-0000-0000-00000003dd11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000003d5a1', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d1b1', '00000000-0000-0000-0000-00000003dd11', '00000000-0000-0000-0000-00000003df11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000003de0a', 'm003d@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000003db01', '00000000-0000-0000-0000-00000003de0a', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-00000003df01', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d1b1', '00000000-0000-0000-0000-00000003de0a', '00000000-0000-0000-0000-00000003db01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000003dc01', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', '00000000-0000-0000-0000-00000003d1b1', '00000000-0000-0000-0000-00000003d5a1', '00000000-0000-0000-0000-00000003df01', '00000000-0000-0000-0000-00000003db01', now() + interval '1 hour');

-- ------------------------------------------------------------ org A catalogue
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000003dca1', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, 'Food', 1);
-- ITEM X (the one every submit below is for) and ITEM Y (a sibling in the SAME org)
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-00000003d1f1', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003dca1', 'Burger X', 4500, 'USD', 1),
  ('00000000-0000-0000-0000-00000003d1f2', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003dca1', 'Pizza Y',  4500, 'USD', 2);

-- Group + options under ITEM X. The LIVE delta is deliberately 999 while every
-- submit below declares 1500: proof that nothing is repriced from the catalogue.
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-00000003d201', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003d1f1', 'Meat');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, is_active, deleted_at) values
  -- valid + live
  ('00000000-0000-0000-0000-00000003d301', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003d201', '240g', 999, true, null),
  -- valid but SOFT-DELETED and INACTIVE (an offline cart may still name it)
  ('00000000-0000-0000-0000-00000003d302', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003d201', 'Retired', 999, false, now()),
  -- valid, configured at exactly zero
  ('00000000-0000-0000-0000-00000003d303', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003d201', 'No onion', 0, true, null);

-- Group + option under ITEM Y (same org, WRONG item for our submits)
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-00000003d202', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003d1f2', 'Crust');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-00000003d304', '00000000-0000-0000-0000-00000003d0a0', '00000000-0000-0000-0000-00000003d0a1', null, '00000000-0000-0000-0000-00000003d202', 'Thin', 1500);

-- --------------------------------------------------------- FOREIGN org B
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00000003d0b0', 'Org 003D B', 'm003d-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000003d0b1', '00000000-0000-0000-0000-00000003d0b0', 'Rest B');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000003dcb1', '00000000-0000-0000-0000-00000003d0b0', '00000000-0000-0000-0000-00000003d0b1', null, 'Food B', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-00000003d1fb', '00000000-0000-0000-0000-00000003d0b0', '00000000-0000-0000-0000-00000003d0b1', null, '00000000-0000-0000-0000-00000003dcb1', 'Item B', 4500, 'USD', 1);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name) values
  ('00000000-0000-0000-0000-00000003d203', '00000000-0000-0000-0000-00000003d0b0', '00000000-0000-0000-0000-00000003d0b1', null, '00000000-0000-0000-0000-00000003d1fb', 'Meat B');
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor) values
  ('00000000-0000-0000-0000-00000003d305', '00000000-0000-0000-0000-00000003d0b0', '00000000-0000-0000-0000-00000003d0b1', null, '00000000-0000-0000-0000-00000003d203', 'Foreign', 1500);

-- ---------------------------------------------------------------- helpers
-- One line of ITEM X, quantity 2, unit 4500, ONE modifier at a declared 1500.
-- MONEY-PRICING-FORMULA-002A formula B: 2 x (4500 + 1500 x 1) = 12000.
create or replace function pg_temp.body(p_option uuid, p_delta bigint default 1500)
  returns jsonb language sql immutable as $fn$
  select jsonb_build_array(jsonb_build_object(
    'menu_item_id', '00000000-0000-0000-0000-00000003d1f1',
    'quantity', 2,
    'unit_price_minor_snapshot', 4500,
    'menu_item_name_snapshot', 'Burger X',
    'modifiers', jsonb_build_array(jsonb_build_object(
      'modifier_option_id', p_option,
      'price_minor_snapshot', p_delta,
      'quantity', 1,
      'modifier_name_snapshot', 'Meat',
      'option_name_snapshot', 'Declared'))));
$fn$;

create or replace function pg_temp.submit(p_order uuid, p_op text, p_option uuid, p_delta bigint default 1500, p_total bigint default 12000)
  returns jsonb language sql as $fn$
  select app.submit_order(
    '00000000-0000-0000-0000-00000003dc01', p_order,
    '00000000-0000-0000-0000-00000003dd11', p_op, 'takeaway', null, null, 'USD', null,
    pg_temp.body(p_option, p_delta), p_total, 0, 0, p_total, null);
$fn$;

-- ============================================================================
-- A — submit_order: NONEXISTENT option
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-00000003d901','op-A','00000000-0000-0000-0000-0000deadbeef') ->> 'error',
  'modifier_option_not_in_scope',
  'A1 submit_order REFUSES a syntactically valid but nonexistent option id');
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000003d901','op-A2','00000000-0000-0000-0000-0000deadbeef') ->> 'ok')::boolean,
  false, 'A2 the refusal is not ok:true');
select is((select count(*)::int from orders where id = '00000000-0000-0000-0000-00000003d901'), 0,
  'A3 ATOMIC: no order row persists for the refused submit');
select is((select count(*)::int from order_items where order_id = '00000000-0000-0000-0000-00000003d901'), 0,
  'A4 ATOMIC: no order_items persist');
select is((select count(*)::int from order_item_modifiers oim
             join order_items oi on oi.id = oim.order_item_id
            where oi.order_id = '00000000-0000-0000-0000-00000003d901'), 0,
  'A5 ATOMIC: no order_item_modifiers persist');

-- ============================================================================
-- B — submit_order: FOREIGN-ORGANIZATION option
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-00000003d902','op-B','00000000-0000-0000-0000-00000003d305') ->> 'error',
  'modifier_option_not_in_scope',
  'B1 submit_order REFUSES an option owned by another organization');
select is((select count(*)::int from orders where id = '00000000-0000-0000-0000-00000003d902'), 0,
  'B2 ATOMIC: no order row persists');
-- UNIFORM CODE: a real foreign option and a nonexistent uuid are indistinguishable,
-- so the refusal cannot be used to probe another tenant's catalogue (R-003).
select is(
  pg_temp.submit('00000000-0000-0000-0000-00000003d903','op-B3','00000000-0000-0000-0000-00000003d305') ->> 'error',
  pg_temp.submit('00000000-0000-0000-0000-00000003d904','op-B4','00000000-0000-0000-0000-0000deadbeef') ->> 'error',
  'B3 foreign-org and nonexistent produce the SAME code (no existence oracle)');

-- ============================================================================
-- C — submit_order: SAME ORG, WRONG ITEM
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-00000003d905','op-C','00000000-0000-0000-0000-00000003d304') ->> 'error',
  'modifier_option_not_in_scope',
  'C1 submit_order REFUSES a same-org option belonging to a DIFFERENT item');
select is((select count(*)::int from orders where id = '00000000-0000-0000-0000-00000003d905'), 0,
  'C2 ATOMIC: no order row persists');

-- ============================================================================
-- D — submit_order: VALID same-item option
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000003d906','op-D','00000000-0000-0000-0000-00000003d301') ->> 'ok')::boolean,
  true, 'D1 submit_order ACCEPTS a live option belonging to the submitted item');
select is((select count(*)::int from orders where id = '00000000-0000-0000-0000-00000003d906'), 1,
  'D2 the order persists');
-- D-008: the SUBMITTED snapshot is stored, NOT the live 999 catalogue delta.
select is((select oim.price_minor_snapshot from order_item_modifiers oim
             join order_items oi on oi.id = oim.order_item_id
            where oi.order_id = '00000000-0000-0000-0000-00000003d906'), 1500::bigint,
  'D3 the SUBMITTED 1500 snapshot is stored, never the live 999 catalogue price');
select is((select line_total_minor from order_items where order_id = '00000000-0000-0000-0000-00000003d906'), 12000::bigint,
  'D4 formula B holds: 2 x (4500 + 1500 x 1) = 12000');
select is((select quantity from order_items where order_id = '00000000-0000-0000-0000-00000003d906'), 2,
  'D5 item quantity stays 2');
select is((select oim.quantity from order_item_modifiers oim
             join order_items oi on oi.id = oim.order_item_id
            where oi.order_id = '00000000-0000-0000-0000-00000003d906'), 1,
  'D6 modifier quantity stays 1 — separate from item quantity');

-- ============================================================================
-- E — submit_order: VALID but SOFT-DELETED + INACTIVE same-item option
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000003d907','op-E','00000000-0000-0000-0000-00000003d302') ->> 'ok')::boolean,
  true, 'E1 a SOFT-DELETED, INACTIVE same-item option is still ACCEPTED (offline snapshot)');
select is((select oim.price_minor_snapshot from order_item_modifiers oim
             join order_items oi on oi.id = oim.order_item_id
            where oi.order_id = '00000000-0000-0000-0000-00000003d907'), 1500::bigint,
  'E2 it is not repriced by current sellability either');

-- ============================================================================
-- F — submit_order: LEGITIMATE ZERO delta
-- ============================================================================
select is(
  (pg_temp.submit('00000000-0000-0000-0000-00000003d908','op-F','00000000-0000-0000-0000-00000003d303', 0, 9000) ->> 'ok')::boolean,
  true, 'F1 an integer ZERO delta on a valid option is ACCEPTED');
select is((select line_total_minor from order_items where order_id = '00000000-0000-0000-0000-00000003d908'), 9000::bigint,
  'F2 zero delta prices exactly: 2 x (4500 + 0) = 9000');

-- ============================================================================
-- Replay / conflict on a REFUSED submit
-- ============================================================================
select is(
  pg_temp.submit('00000000-0000-0000-0000-00000003d901','op-A','00000000-0000-0000-0000-0000deadbeef') ->> 'error',
  'modifier_option_not_in_scope',
  'R1 an identical replay of a refused submit is STABLY refused');
select is((select count(*)::int from orders where id = '00000000-0000-0000-0000-00000003d901'), 0,
  'R2 the replay still applies nothing');

-- ============================================================================
-- G-L — add_order_items
-- ============================================================================
-- A clean parent order built from a VALID option, to amend below.
select pg_temp.submit('00000000-0000-0000-0000-00000003da01','op-parent','00000000-0000-0000-0000-00000003d301');

create or replace function pg_temp.amend(p_op text, p_option uuid, p_delta bigint default 1500)
  returns jsonb language sql as $fn$
  select app.add_order_items(
    '00000000-0000-0000-0000-00000003dc01', '00000000-0000-0000-0000-00000003da01',
    '00000000-0000-0000-0000-00000003dd11', p_op, pg_temp.body(p_option, p_delta), null);
$fn$;

select is(pg_temp.amend('op-G','00000000-0000-0000-0000-0000deadbeef') ->> 'error',
  'modifier_option_not_in_scope', 'G1 add_order_items REFUSES a nonexistent option');
select is(pg_temp.amend('op-H','00000000-0000-0000-0000-00000003d305') ->> 'error',
  'modifier_option_not_in_scope', 'H1 add_order_items REFUSES a foreign-organization option');
select is(pg_temp.amend('op-I','00000000-0000-0000-0000-00000003d304') ->> 'error',
  'modifier_option_not_in_scope', 'I1 add_order_items REFUSES a same-org wrong-item option');

-- L — the refusals above left the parent order completely untouched.
select is((select count(*)::int from order_items where order_id = '00000000-0000-0000-0000-00000003da01'), 1,
  'L1 ATOMIC: the refused amendments added no order item');
select is((select count(*)::int from order_service_rounds where order_id = '00000000-0000-0000-0000-00000003da01'), 0,
  'L2 ATOMIC: no service round was created by a refused amendment');
select is((select subtotal_minor from orders where id = '00000000-0000-0000-0000-00000003da01'), 12000::bigint,
  'L3 the existing subtotal is unchanged');
select is((select grand_total_minor from orders where id = '00000000-0000-0000-0000-00000003da01'), 12000::bigint,
  'L4 the existing grand total is unchanged');

-- J — a VALID same-item amendment applies exactly once.
select is((pg_temp.amend('op-J','00000000-0000-0000-0000-00000003d301') ->> 'ok')::boolean, true,
  'J1 add_order_items ACCEPTS a valid same-item option');
select is((select count(*)::int from order_service_rounds where order_id = '00000000-0000-0000-0000-00000003da01'), 1,
  'J2 exactly ONE service round exists');
-- Idempotent replay returns the SAME round (unchanged by the new validation).
select is(pg_temp.amend('op-J','00000000-0000-0000-0000-00000003d301') ->> 'round_id',
          (select id::text from order_service_rounds where order_id = '00000000-0000-0000-0000-00000003da01'),
  'J3 an identical replay returns the SAME round id');
select is((select count(*)::int from order_service_rounds where order_id = '00000000-0000-0000-0000-00000003da01'), 1,
  'J4 the replay created NO second round');

-- K — a soft-deleted/inactive valid option is accepted through the amendment path too.
select is((pg_temp.amend('op-K','00000000-0000-0000-0000-00000003d302') ->> 'ok')::boolean, true,
  'K1 a SOFT-DELETED, INACTIVE same-item option is ACCEPTED by add_order_items');

select * from finish();
rollback;
