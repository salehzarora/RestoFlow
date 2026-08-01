-- ============================================================================
-- MENU-ORDER-001 — pgTAP (Codex 3rd correction: EXECUTED on PostgreSQL 17):
--   * order_items.category_display_order_snapshot + item_display_order_snapshot
--     capture the item's category + within-category menu ranks at submit
--     (assign_order_item_display_order_snapshot trigger), server-derived from
--     the authoritative menu — NOT client values.
--   * order_item_modifiers.modifier_group_display_order_snapshot +
--     modifier_option_display_order_snapshot + line_position capture the
--     modifier's group + option menu ranks + a SERVER-derived insertion ordinal
--     (a client-supplied line_position is IGNORED).
--   * Those snapshots are IMMUTABLE: a later menu reorder does NOT change an
--     existing order's snapshots (D-008; no live-menu lookup at print time).
--   * app.menu_reorder atomically rewrites display_order for a complete sibling
--     set — authorized via the REAL production contract (app.menu_guard over the
--     CALLER-PASSED org/restaurant/branch scope, BEFORE any id is inspected),
--     PG17-safe (no min(uuid)), advisory-locked per sibling scope, and with NO
--     existence oracle (every invalid id set -> one generic 42501).
--
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
-- Submit runs via the real public.sync_push -> app.submit_order path; the menu
-- reorder runs via public.menu_reorder authorized by app.current_app_user_id()
-- (GUC in tests, auth.uid() in prod) + memberships (GUC-free, rf112 pattern).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(55);

-- ===== fixtures: Org M ======================================================
insert into organizations (id, name, slug, default_currency) values
  ('e0000000-0000-0000-0000-000000000001', 'Org M', 'org-m', 'USD');
insert into restaurants (id, organization_id, name) values
  ('e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000001', 'Rest M');
insert into branches (id, organization_id, restaurant_id, name) values
  ('e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'Branch M');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e0000000-0000-0000-0000-0000000000d1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-0000000000d1', 'e0000000-0000-0000-0000-0000000000a1');
-- A branch cashier (drives the PIN session that submits the order).
insert into app_users (id, email) values
  ('e0000000-0000-0000-0000-00000000ae01', 'm-cash@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e0000000-0000-0000-0000-00000000ab01', 'e0000000-0000-0000-0000-00000000ae01', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('e0000000-0000-0000-0000-00000000ac01', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-00000000ae01', 'e0000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e0000000-0000-0000-0000-00000000ad01', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-00000000ac01', 'e0000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
-- An org owner (write role) + a restaurant-scoped cashier (covers the menu
-- scope but lacks a write role -> the role-denied path).
insert into app_users (id, email) values
  ('e0000000-0000-0000-0000-00000000ae02', 'm-owner@example.test'),
  ('e0000000-0000-0000-0000-00000000ae03', 'm-restcash@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e0000000-0000-0000-0000-00000000ab02', 'e0000000-0000-0000-0000-00000000ae02', 'e0000000-0000-0000-0000-000000000001', null, null, 'org_owner', '{}'::jsonb),
  ('e0000000-0000-0000-0000-00000000ab03', 'e0000000-0000-0000-0000-00000000ae03', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'cashier', '{}'::jsonb);
-- Two restaurant-scoped categories (cat1 rank 1, cat2 rank 2); three items in
-- cat1 (ranks 5/6/7) + one in cat2; a modifier group on item A + three options.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e0000000-0000-0000-0000-0000000000c1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'Cat 1', 1),
  ('e0000000-0000-0000-0000-0000000000c2', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'Cat 2', 2);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e0000000-0000-0000-0000-0000000000f1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000c1', 'Item A', 500, 'USD', 5),
  ('e0000000-0000-0000-0000-0000000000f2', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000c1', 'Item B', 500, 'USD', 6),
  ('e0000000-0000-0000-0000-0000000000f3', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000c1', 'Item C', 500, 'USD', 7),
  ('e0000000-0000-0000-0000-0000000000e5', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000c2', 'Item D', 500, 'USD', 1);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, display_order) values
  ('e0000000-0000-0000-0000-0000000000d5', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000f1', 'Extras', 4);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order) values
  ('e0000000-0000-0000-0000-0000000000d6', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000d5', 'Opt 1', 0, 1),
  ('e0000000-0000-0000-0000-0000000000d7', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000d5', 'Opt 2', 0, 2),
  ('e0000000-0000-0000-0000-0000000000d8', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000d5', 'Opt 3', 0, 3);
-- MONEY-SERVER-MODIFIER-SCOPE-003D: the service-round add below submits these
-- same options under ITEM B, so Item B needs its OWN group owning options with
-- the ids the amendment names. Group d5 above belongs to Item A, and an option
-- may only price the item its group belongs to. Display orders are preserved so
-- the MENU-ORDER-001 rank-snapshot assertions keep their meaning.
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, display_order) values
  ('e0000000-0000-0000-0000-0000000000e5', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000f2', 'Extras', 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order) values
  ('e0000000-0000-0000-0000-0000000000e6', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000e5', 'Opt 1', 0, 1),
  ('e0000000-0000-0000-0000-0000000000e7', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000e5', 'Opt 2', 0, 2),
  ('e0000000-0000-0000-0000-0000000000e8', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', null, 'e0000000-0000-0000-0000-0000000000e5', 'Opt 3', 0, 3);
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('e0000000-0000-0000-0000-0000000000b1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'T1');
-- A SECOND org (Org N) with its own category — for cross-tenant reorder rejection.
insert into organizations (id, name, slug, default_currency) values
  ('f0000000-0000-0000-0000-000000000001', 'Org N', 'org-n', 'USD');
insert into restaurants (id, organization_id, name) values
  ('f0000000-0000-0000-0000-000000000002', 'f0000000-0000-0000-0000-000000000001', 'Rest N');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('f0000000-0000-0000-0000-0000000000c1', 'f0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000002', null, 'Cat N', 1);

-- ===== column shape =========================================================
select has_column('public', 'order_items', 'category_display_order_snapshot', 'order_items has category_display_order_snapshot');
select col_type_is('public', 'order_items', 'category_display_order_snapshot', 'integer', 'category_display_order_snapshot is integer');
select col_default_is('public', 'order_items', 'category_display_order_snapshot', '0', 'category snapshot defaults to 0');
select has_column('public', 'order_items', 'item_display_order_snapshot', 'order_items has item_display_order_snapshot');
select col_type_is('public', 'order_items', 'item_display_order_snapshot', 'integer', 'item_display_order_snapshot is integer');
select col_default_is('public', 'order_items', 'item_display_order_snapshot', '0', 'item snapshot defaults to 0');
select has_column('public', 'order_item_modifiers', 'line_position', 'order_item_modifiers has line_position');
select col_type_is('public', 'order_item_modifiers', 'line_position', 'integer', 'modifier line_position is integer');
select has_column('public', 'order_item_modifiers', 'modifier_group_display_order_snapshot', 'order_item_modifiers has modifier_group_display_order_snapshot');
select col_type_is('public', 'order_item_modifiers', 'modifier_group_display_order_snapshot', 'integer', 'modifier group snapshot is integer');
select has_column('public', 'order_item_modifiers', 'modifier_option_display_order_snapshot', 'order_item_modifiers has modifier_option_display_order_snapshot');
select col_type_is('public', 'order_item_modifiers', 'modifier_option_display_order_snapshot', 'integer', 'modifier option snapshot is integer');

-- ===== menu_reorder is exposed to authenticated only (5-arg contract) =======
select ok(
  has_function_privilege('authenticated', 'public.menu_reorder(uuid, uuid, uuid, text, uuid[])', 'execute'),
  'authenticated may execute public.menu_reorder(org, restaurant, branch, entity, ids)');
select ok(
  not has_function_privilege('anon', 'public.menu_reorder(uuid, uuid, uuid, text, uuid[])', 'execute'),
  'anon may NOT execute public.menu_reorder');

-- ===== submit a DINE-IN order: Item A (cat rank 1, item rank 5) + 3 modifiers.
select public.sync_push(
  'e0000000-0000-0000-0000-00000000ad01'::uuid,
  'e0000000-0000-0000-0000-0000000000d1'::uuid,
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'm-op-submit-1',
    'operation_type', 'order.submit',
    'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', 'e0000000-0000-0000-0000-0000000000f9',
      'order_type', 'dine_in',
      'table_id', 'e0000000-0000-0000-0000-0000000000b1',
      'currency_code', 'USD',
      'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
      'order_items', jsonb_build_array(
        jsonb_build_object(
          'menu_item_id', 'e0000000-0000-0000-0000-0000000000f1',
          'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item A',
          'modifiers', jsonb_build_array(
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000d6', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 1', 'price_minor_snapshot', 0, 'quantity', 1),
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000d7', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 2', 'price_minor_snapshot', 0, 'quantity', 1),
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000d8', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 3', 'price_minor_snapshot', 0, 'quantity', 1))))))));

-- The item's category + item menu ranks were snapshotted server-side.
select is(
  (select category_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  1, 'category_display_order_snapshot = the item''s category rank (menu_categories.display_order)');
select is(
  (select item_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  5, 'item_display_order_snapshot = the item''s rank within its category (menu_items.display_order)');

-- The modifiers carry the group + option ranks and sort into Dashboard order.
select is(
  (select array_agg(oim.option_name_snapshot
     order by oim.modifier_group_display_order_snapshot,
              oim.modifier_option_display_order_snapshot,
              oim.line_position)
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'),
  array['Opt 1', 'Opt 2', 'Opt 3'],
  'modifiers sorted by (group, option, line_position) reproduce the Dashboard order');
select is(
  (select array_agg(oim.line_position order by oim.line_position)
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'),
  array[1, 2, 3],
  'the submit path derives modifier line_position 1..N (server-side, not client)');

-- ===== menu_reorder happy path + HISTORICAL IMMUTABILITY (org owner) =========
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';

-- (i) reorder the Cat 1 ITEMS: Item A's live display_order changes 5 -> 2.
select is(
  (public.menu_reorder(
     'e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
     array['e0000000-0000-0000-0000-0000000000f3',
           'e0000000-0000-0000-0000-0000000000f1',
           'e0000000-0000-0000-0000-0000000000f2']::uuid[]) ->> 'ok')::boolean,
  true, 'org owner reorders the Cat 1 item set');

reset role;
-- The submitted order's item snapshot is IMMUTABLE — still 5, NOT the new 2.
select is(
  (select item_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  5, 'item_display_order_snapshot is IMMUTABLE after a later menu-item reorder (D-008)');

set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';

-- (ii) reorder the CATEGORIES: Cat 1's live display_order changes 1 -> 2.
select is(
  (public.menu_reorder(
     'e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002', null, 'menu_category',
     array['e0000000-0000-0000-0000-0000000000c2',
           'e0000000-0000-0000-0000-0000000000c1']::uuid[]) ->> 'ok')::boolean,
  true, 'org owner reorders the restaurant category set');

-- min(uuid)-FIX PROOF: menu_reorder EXECUTES without a UUID-aggregate error for
-- ALL FOUR entity types (items + categories above; options + groups here).
select is(
  (public.menu_reorder(
     'e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002', null, 'modifier_option',
     array['e0000000-0000-0000-0000-0000000000d8',
           'e0000000-0000-0000-0000-0000000000d7',
           'e0000000-0000-0000-0000-0000000000d6']::uuid[]) ->> 'ok')::boolean,
  true, 'org owner reorders the modifier OPTION set (PG17-safe, no UUID aggregate)');
select is(
  (public.menu_reorder(
     'e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002', null, 'modifier',
     array['e0000000-0000-0000-0000-0000000000d5']::uuid[]) ->> 'ok')::boolean,
  true, 'org owner reorders the modifier GROUP set (single-sibling complete set)');

reset role;
-- The modifier options' live display_order WAS rewritten to the requested order.
select is(
  (select array_agg(id order by display_order)
     from public.modifier_options
    where modifier_id = 'e0000000-0000-0000-0000-0000000000d5' and deleted_at is null),
  array['e0000000-0000-0000-0000-0000000000d8',
        'e0000000-0000-0000-0000-0000000000d7',
        'e0000000-0000-0000-0000-0000000000d6']::uuid[],
  'the modifier options were rewritten to display_order 1..N in the requested order');
-- The submitted order's category snapshot is IMMUTABLE — still 1, NOT the new 2.
select is(
  (select category_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  1, 'category_display_order_snapshot is IMMUTABLE after a later category reorder (D-008)');

-- The live menu DID change (proves the reorder was real, not a no-op).
select is(
  (select display_order from public.menu_items where id = 'e0000000-0000-0000-0000-0000000000f1'),
  2, 'the live menu_items.display_order WAS rewritten by the reorder');

-- ===== SERVICE ROUND (#10): a later add_order_items item snapshots the CURRENT
--       menu (Cat 1 rank now 2, Item B rank now 3) and appends its line_position
--       after the order's existing lines; the ORIGINAL item keeps its old snapshot.
select public.sync_push(
  'e0000000-0000-0000-0000-00000000ad01'::uuid,
  'e0000000-0000-0000-0000-0000000000d1'::uuid,
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'm-op-add-1',
    'operation_type', 'order.items_add',
    'target_entity', 'order',
    'target_id', 'e0000000-0000-0000-0000-0000000000f9',
    'payload', jsonb_build_object(
      'order_id', 'e0000000-0000-0000-0000-0000000000f9',
      'round_id', 'e0000000-0000-0000-0000-0000000000e9',
      'order_items', jsonb_build_array(
        jsonb_build_object('menu_item_id', 'e0000000-0000-0000-0000-0000000000f2', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item B',
          -- #10: modifiers through the REAL order.items_add (app.add_order_items)
          -- path, with a MALICIOUS client payload that DELIBERATELY supplies a
          -- line_position (999) AND forged group/option display-order snapshots
          -- (999). The RPC never reads those fields (it inserts only the option
          -- id + name/price/qty/meat snapshots), and the BEFORE INSERT trigger
          -- derives line_position 1..N and snapshots the CURRENT live-menu ranks —
          -- so the forged 999s are ignored end to end (asserted below).
          'modifiers', jsonb_build_array(
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000e7', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 2', 'price_minor_snapshot', 0, 'quantity', 1, 'line_position', 999, 'modifier_group_display_order_snapshot', 999, 'modifier_option_display_order_snapshot', 999),
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000e6', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 1', 'price_minor_snapshot', 0, 'quantity', 1, 'line_position', 999, 'modifier_group_display_order_snapshot', 999, 'modifier_option_display_order_snapshot', 999))))))));
select is(
  (select category_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item B'),
  2, 'a service-round item snapshots the CURRENT category rank (2) at add time');
select is(
  (select item_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item B'),
  3, 'a service-round item snapshots the CURRENT item rank (Item B is now 3) at add time');
select cmp_ok(
  (select line_position from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item B'),
  '>',
  (select line_position from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  'the service-round item''s line_position is appended AFTER the original items');

-- Idempotent replay (#10): re-pushing the SAME add op adds nothing / renumbers nothing.
select public.sync_push(
  'e0000000-0000-0000-0000-00000000ad01'::uuid,
  'e0000000-0000-0000-0000-0000000000d1'::uuid,
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'm-op-add-1',
    'operation_type', 'order.items_add',
    'target_entity', 'order',
    'target_id', 'e0000000-0000-0000-0000-0000000000f9',
    'payload', jsonb_build_object(
      'order_id', 'e0000000-0000-0000-0000-0000000000f9',
      'round_id', 'e0000000-0000-0000-0000-0000000000e9',
      'order_items', jsonb_build_array(
        jsonb_build_object('menu_item_id', 'e0000000-0000-0000-0000-0000000000f2', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item B',
          -- #10: the idempotent replay carries the SAME malicious 999 fields; the
          -- replay is a no-op (idempotency ledger), so nothing is re-derived either.
          'modifiers', jsonb_build_array(
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000e7', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 2', 'price_minor_snapshot', 0, 'quantity', 1, 'line_position', 999, 'modifier_group_display_order_snapshot', 999, 'modifier_option_display_order_snapshot', 999),
            jsonb_build_object('modifier_option_id', 'e0000000-0000-0000-0000-0000000000e6', 'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Opt 1', 'price_minor_snapshot', 0, 'quantity', 1, 'line_position', 999, 'modifier_group_display_order_snapshot', 999, 'modifier_option_display_order_snapshot', 999))))))));
select is(
  (select count(*)::int from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item B'),
  1, 'an idempotent replay of the service-round add inserts NO duplicate Item B');
select is(
  (select count(*)::int from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item B'),
  2, 'the idempotent replay did NOT duplicate the service-round modifiers');

-- ===== #10 SERVICE-ROUND MODIFIERS (via the REAL order.items_add path, with a
--       MALICIOUS client payload) ==================================================
-- Item B's modifiers were inserted through app.add_order_items (NOT a standalone
-- insert), and the client payload DELIBERATELY forged line_position=999 and
-- group/option display-order snapshots=999. The trigger derived their line_position
-- 1..N in payload order and snapshotted the CURRENT menu ranks (after the reorders
-- the group d5 -> 1 and the options -> d8=1, d7=2, d6=3). The forged 999s are ignored.
select is(
  (select array_agg(oim.line_position order by oim.line_position)
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item B'),
  array[1, 2],
  'service-round modifiers get SERVER-derived line_position 1..N (real add path)');
-- The forged 999s never reached ANY column of the stored rows.
select is(
  (select count(*)::int from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item B'
      and (oim.line_position = 999
        or oim.modifier_group_display_order_snapshot = 999
        or oim.modifier_option_display_order_snapshot = 999)),
  0, 'the malicious client line_position/snapshots (999) never reach the stored rows');
select is(
  (select oim.modifier_option_display_order_snapshot
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item B'
      and oim.option_name_snapshot = 'Opt 2'),
  2, 'a service-round modifier snapshots the CURRENT option rank (d7 is now 2)');
select is(
  (select oim.modifier_group_display_order_snapshot
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item B'
      and oim.option_name_snapshot = 'Opt 2'),
  1, 'a service-round modifier snapshots the CURRENT group rank (e5, Item B''s own group, is rank 1) — the SERVER overrides the client''s bogus 999');

-- ===== #9 HISTORICAL MODIFIER A/B: the OLD order A (submitted BEFORE the option
--       + group reorder) keeps its ORIGINAL modifier snapshots — IMMUTABLE.
select is(
  (select array_agg(oim.modifier_option_display_order_snapshot order by oim.line_position)
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item A'
      and oim.option_name_snapshot in ('Opt 1', 'Opt 2', 'Opt 3')),
  array[1, 2, 3],
  'order A''s modifier OPTION snapshots are immutable after the option reorder (D-008)');
select is(
  (select array_agg(distinct oim.modifier_group_display_order_snapshot)
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'
      and oi.menu_item_name_snapshot = 'Item A'
      and oim.option_name_snapshot in ('Opt 1', 'Opt 2', 'Opt 3')),
  array[4],
  'order A''s modifier GROUP snapshot is immutable (still 4) after the group reorder');

-- ===== CLIENT line_position IS IGNORED (#10): a direct insert with 999 is
--       overridden by the trigger to the server-derived max+1 (Item A had 3).
--       The probe row carries a unique option_name_snapshot so it is found back
--       unambiguously (a data-modifying WITH cannot nest in a scalar subquery).
insert into public.order_item_modifiers
  (organization_id, restaurant_id, branch_id, order_item_id,
   modifier_option_id, option_name_snapshot, price_minor_snapshot, line_position)
values ('e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
   'e0000000-0000-0000-0000-000000000003',
   (select id from public.order_items where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
   'e0000000-0000-0000-0000-0000000000d6', 'PROBE-999', 0, 999);
select is(
  (select line_position from public.order_item_modifiers where option_name_snapshot = 'PROBE-999'),
  4, 'a client-supplied line_position (999) is IGNORED; the trigger derives max+1 (=4)');

-- ===== NEW ORDER B (#11): an order submitted AFTER the reorder uses the NEW
--       ranks (Cat 1 -> 2, Item A -> 2), while the old order keeps A (1, 5).
select public.sync_push(
  'e0000000-0000-0000-0000-00000000ad01'::uuid,
  'e0000000-0000-0000-0000-0000000000d1'::uuid,
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'm-op-submit-2',
    'operation_type', 'order.submit',
    'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', 'e0000000-0000-0000-0000-0000000000f8',
      'order_type', 'takeaway',
      'currency_code', 'USD',
      'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
      'order_items', jsonb_build_array(
        jsonb_build_object('menu_item_id', 'e0000000-0000-0000-0000-0000000000f1', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item A'))))));
select is(
  (select category_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f8' and menu_item_name_snapshot = 'Item A'),
  2, 'a NEW order after the reorder uses the NEW category rank (2), not the old 1');
select is(
  (select item_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f8' and menu_item_name_snapshot = 'Item A'),
  2, 'a NEW order after the reorder uses the NEW item rank (2), not the old 5');

-- ===== role denial: a covering-but-no-write-role cashier (real auth contract) =
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae03';

select is(
  (public.menu_reorder(
     'e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
     array['e0000000-0000-0000-0000-0000000000f1',
           'e0000000-0000-0000-0000-0000000000f2',
           'e0000000-0000-0000-0000-0000000000f3']::uuid[]) ->> 'error'),
  'permission_denied', 'a restaurant cashier (covers scope, below manager) is role-denied');

reset role;
select is(
  (select count(*)::int from public.audit_events
    where action = 'menu.menu_item.reorder_denied'
      and actor_app_user_id = 'e0000000-0000-0000-0000-00000000ae03'),
  1, 'the role denial wrote exactly one menu.menu_item.reorder_denied audit row');

-- ===== enforcement: incomplete / mixed-parent / duplicate / mixed-tenant =====
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';

select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000f2']::uuid[]) $$,
  '42501', null,
  'an INCOMPLETE sibling set (2 of 3) is rejected (generic; count NOT disclosed)');

select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000e5']::uuid[]) $$,
  '42501', null,
  'a MIXED-parent set (items from two categories) is rejected');

select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000f2']::uuid[]) $$,
  '42501', null,
  'a DUPLICATE id set is rejected (generic invalid request)');

-- Mixed local + foreign: two local categories + one Org N category -> generic.
select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_category',
       array['e0000000-0000-0000-0000-0000000000c1',
             'e0000000-0000-0000-0000-0000000000c2',
             'f0000000-0000-0000-0000-0000000000c1']::uuid[]) $$,
  '42501', null,
  'a MIXED local+foreign id set is rejected (generic; no cross-tenant oracle)');

-- Cross-tenant only: an id from ANOTHER org does not resolve in the authorized
-- scope -> the SAME generic 42501 (no existence oracle).
select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_category',
       array['f0000000-0000-0000-0000-0000000000c1']::uuid[]) $$,
  '42501', null,
  'a CROSS-TENANT id (Org N category under Org M) is rejected (generic invalid request)');
-- A nonexistent id -> the SAME generic invalid request (missing == foreign).
select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
       array['e0000000-0000-0000-0000-0000000000ff']::uuid[]) $$,
  '42501', null,
  'a NONEXISTENT id is rejected as the SAME generic invalid request (no oracle)');

reset role;

-- Unauthenticated: no actor -> denied at step 1, BEFORE any id inspection.
set local role authenticated;
set local app.current_app_user_id = '';
select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000f2',
             'e0000000-0000-0000-0000-0000000000f3']::uuid[]) $$,
  '42501', null,
  'an UNAUTHENTICATED reorder is denied (no actor, no id oracle)');

-- A caller with NO membership in the target org -> menu_guard raises 42501
-- (authorization fails on the PASSED scope, before ids).
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';
select throws_ok(
  $$ select public.menu_reorder('f0000000-0000-0000-0000-000000000001',
       'f0000000-0000-0000-0000-000000000002', null, 'menu_category',
       array['f0000000-0000-0000-0000-0000000000c1']::uuid[]) $$,
  '42501', null,
  'a caller with no membership in the target org is denied on the PASSED scope (before ids)');

reset role;

-- ===== #6 ORDER-NEUTRAL EDITS: a normal menu_upsert edit cannot clobber the
--       drag-set display_order (PART 5 guard trigger). Cat 1 is rank 2 after the
--       category reorder; an edit passing a STALE display_order (99) leaves it at
--       2, while its OTHER fields (name) apply. menu_reorder stays the ONLY writer.
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';
select public.menu_upsert_category(
  'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002',
  null, 'e0000000-0000-0000-0000-0000000000c1', 'Cat 1 renamed', 99, true);
reset role;
select is(
  (select display_order from public.menu_categories where id = 'e0000000-0000-0000-0000-0000000000c1'),
  2, 'a normal edit with a STALE display_order (99) does NOT change the drag-set order (guard trigger)');
select is(
  (select name from public.menu_categories where id = 'e0000000-0000-0000-0000-0000000000c1'),
  'Cat 1 renamed', 'the edit''s OTHER fields (name) DID apply');

-- ===== #7 DELETED/INACTIVE SIBLING SAFETY: soft-delete Item C, then a reorder
--       INCLUDING the deleted id is rejected as the SAME generic 42501 (deleted ==
--       foreign; no leak); the surviving set reorders fine; a rejected request
--       leaves display_order UNCHANGED. (Runs LAST — it mutates the item set.)
update public.menu_items set deleted_at = now()
  where id = 'e0000000-0000-0000-0000-0000000000f3';
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';
select is(
  (public.menu_reorder('e0000000-0000-0000-0000-000000000001',
     'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
     array['e0000000-0000-0000-0000-0000000000f2',
           'e0000000-0000-0000-0000-0000000000f1']::uuid[]) ->> 'ok')::boolean,
  true, 'a soft-deleted sibling is EXCLUDED; reordering the survivors [f2,f1] succeeds');
select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001',
       'e0000000-0000-0000-0000-000000000002', null, 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000f2',
             'e0000000-0000-0000-0000-0000000000f3']::uuid[]) $$,
  '42501', null,
  'a reorder INCLUDING a soft-deleted id is rejected as the SAME generic 42501');
reset role;
select is(
  (select array_agg(id order by display_order)
     from public.menu_items
    where menu_category_id = 'e0000000-0000-0000-0000-0000000000c1' and deleted_at is null),
  array['e0000000-0000-0000-0000-0000000000f2',
        'e0000000-0000-0000-0000-0000000000f1']::uuid[],
  'the rejected (deleted-id) reorder left the survivors'' display_order unchanged');

select * from finish();
rollback;
