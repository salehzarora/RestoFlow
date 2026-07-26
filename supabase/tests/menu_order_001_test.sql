-- ============================================================================
-- MENU-ORDER-001 — pgTAP:
--   * order_items.category_display_order_snapshot + item_display_order_snapshot
--     capture the item's category + within-category menu ranks at submit
--     (assign_order_item_display_order_snapshot trigger), server-derived from
--     the authoritative menu — NOT client values.
--   * order_item_modifiers.modifier_group_display_order_snapshot +
--     modifier_option_display_order_snapshot + line_position capture the
--     modifier's group + option menu ranks + insertion ordinal.
--   * Those snapshots are IMMUTABLE: a later menu reorder does NOT change an
--     existing order's snapshots (D-008; no live-menu lookup at print time).
--   * app.menu_reorder atomically rewrites display_order for a complete sibling
--     set, manager+ only, siblings-in-one-scope only.
--
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
-- Submit runs via the real public.sync_push -> app.submit_order path; the menu
-- reorder runs via public.menu_reorder under the GUC principal (rf109 pattern).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(27);

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
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('e0000000-0000-0000-0000-0000000000b1', 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000003', 'T1');

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

-- ===== menu_reorder is exposed to authenticated only ========================
select ok(
  has_function_privilege('authenticated', 'public.menu_reorder(uuid, text, uuid[])', 'execute'),
  'authenticated may execute public.menu_reorder');
select ok(
  not has_function_privilege('anon', 'public.menu_reorder(uuid, text, uuid[])', 'execute'),
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
  (select array_agg(oim.modifier_option_display_order_snapshot order by oim.line_position)
     from public.order_item_modifiers oim
     join public.order_items oi on oi.id = oim.order_item_id
    where oi.order_id = 'e0000000-0000-0000-0000-0000000000f9'),
  array[1, 2, 3],
  'each modifier carries its option''s menu rank (group rank = 4 for all here)');

-- ===== menu_reorder happy path + HISTORICAL IMMUTABILITY (org owner) =========
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';
set local app.current_organization_id = 'e0000000-0000-0000-0000-000000000001';

-- (i) reorder the Cat 1 ITEMS: Item A's live display_order changes 5 -> 2.
select is(
  (public.menu_reorder('e0000000-0000-0000-0000-000000000001', 'menu_item',
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
set local app.current_organization_id = 'e0000000-0000-0000-0000-000000000001';

-- (ii) reorder the CATEGORIES: Cat 1's live display_order changes 1 -> 2.
select is(
  (public.menu_reorder('e0000000-0000-0000-0000-000000000001', 'menu_category',
     array['e0000000-0000-0000-0000-0000000000c2',
           'e0000000-0000-0000-0000-0000000000c1']::uuid[]) ->> 'ok')::boolean,
  true, 'org owner reorders the restaurant category set');

reset role;
-- The submitted order's category snapshot is IMMUTABLE — still 1, NOT the new 2.
select is(
  (select category_display_order_snapshot from public.order_items
    where order_id = 'e0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  1, 'category_display_order_snapshot is IMMUTABLE after a later category reorder (D-008)');

-- The live menu DID change (proves the reorder was real, not a no-op).
select is(
  (select display_order from public.menu_items where id = 'e0000000-0000-0000-0000-0000000000f1'),
  2, 'the live menu_items.display_order WAS rewritten by the reorder');

-- ===== role denial: a covering-but-no-write-role cashier ====================
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae03';
set local app.current_organization_id = 'e0000000-0000-0000-0000-000000000001';

select is(
  (public.menu_reorder('e0000000-0000-0000-0000-000000000001', 'menu_item',
     array['e0000000-0000-0000-0000-0000000000f1',
           'e0000000-0000-0000-0000-0000000000f2',
           'e0000000-0000-0000-0000-0000000000f3']::uuid[]) ->> 'error'),
  'permission_denied', 'a restaurant cashier is role-denied (returns permission_denied)');

reset role;
select is(
  (select count(*)::int from public.audit_events
    where action = 'menu.menu_item.reorder_denied'
      and actor_app_user_id = 'e0000000-0000-0000-0000-00000000ae03'),
  1, 'the role denial wrote exactly one menu.menu_item.reorder_denied audit row');

-- ===== enforcement: incomplete set + mixed-parent are rejected (42501) ======
set local role authenticated;
set local app.current_app_user_id = 'e0000000-0000-0000-0000-00000000ae02';
set local app.current_organization_id = 'e0000000-0000-0000-0000-000000000001';

select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001', 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000f2']::uuid[]) $$,
  '42501', null,
  'an INCOMPLETE sibling set (2 of 3) is rejected');

select throws_ok(
  $$ select public.menu_reorder('e0000000-0000-0000-0000-000000000001', 'menu_item',
       array['e0000000-0000-0000-0000-0000000000f1',
             'e0000000-0000-0000-0000-0000000000e5']::uuid[]) $$,
  '42501', null,
  'a MIXED-parent set (items from two categories) is rejected');

reset role;
select * from finish();
rollback;
