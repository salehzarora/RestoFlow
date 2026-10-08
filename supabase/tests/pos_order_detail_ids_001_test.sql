-- ============================================================================
-- POS-ORDER-DETAIL-IDS-001 — pos_order_detail exposes each modifier's option id
-- and order-time display-order ranks (ORDER-EDIT slice 2, API_CONTRACT §4.45.10).
--
-- Contract under test (ADDITIVE, non-money keys only):
--   items[].modifiers[].modifier_option_id                     = m.modifier_option_id
--   items[].modifiers[].modifier_group_display_order_snapshot  = m.modifier_group_display_order_snapshot
--   items[].modifiers[].modifier_option_display_order_snapshot = m.modifier_option_display_order_snapshot
-- The values are the STORED columns (MENU-ORDER-001 trigger-stamped at insert),
-- never re-derived from the live menu (D-008). Every existing key, value and
-- ordering, the auth/scoping envelopes (R-003) and the grants are unchanged.
-- ============================================================================
begin;

set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(19);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('d0d00000-0000-0000-0000-0000000000a0', 'Org ODI', 'org-odi', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('d0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000a0', 'Rest ODI');
insert into branches (id, organization_id, restaurant_id, name) values
  ('d0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'Branch ODI');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('d0d00000-0000-0000-0000-0000000000d1', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('d0d00000-0000-0000-0000-0000000000f1', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('d0d00000-0000-0000-0000-00000000005a', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000000d1', 'd0d00000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('d0d00000-0000-0000-0000-00000000006a', 'pos-detail-ids@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('d0d00000-0000-0000-0000-00000000007a', 'd0d00000-0000-0000-0000-00000000006a', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('d0d00000-0000-0000-0000-00000000008a', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-00000000006a', 'd0d00000-0000-0000-0000-00000000007a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('d0d00000-0000-0000-0000-00000000009a', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-00000000005a', 'd0d00000-0000-0000-0000-00000000008a', 'd0d00000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- Menu: Size (group rank 1) = 240g (option rank 1); Extras (group rank 2) =
-- cheese (option rank 1), onion (option rank 2), pickles (never reordered:
-- the column-default display_order 0). After the order is placed the LIVE menu
-- is reordered (Extras -> 9, cheese -> 8), so a live-menu lookup can no longer
-- pass for the STORED snapshot.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('d0d00000-0000-0000-0000-0000000000c1', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'Burgers', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('d0d00000-0000-0000-0000-000000001001', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('d0d00000-0000-0000-0000-00000000d101', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-000000001001', 'Size',   'single',   1, 1,    true,  true, 1),
  ('d0d00000-0000-0000-0000-00000000d102', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 2);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('d0d00000-0000-0000-0000-00000000e240', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-00000000d101', '240g',   0,   1, true),
  ('d0d00000-0000-0000-0000-00000000e0c1', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-00000000d102', 'cheese', 300, 1, true),
  ('d0d00000-0000-0000-0000-00000000e0c4', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-00000000d102', 'onion',  0,   2, true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, is_active) values
  ('d0d00000-0000-0000-0000-00000000e0d1', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', null, 'd0d00000-0000-0000-0000-00000000d102', 'pickles', 0, true);

insert into orders (
  id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type,
  currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
values
  ('d0d00000-0000-0000-0000-00000000010a', 'd0d00000-0000-0000-0000-0000000000a0',
   'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab',
   'd0d00000-0000-0000-0000-0000000000d1', 'd0d00000-0000-0000-0000-00000000009a',
   'd0d00000-0000-0000-0000-00000000008a', 'd0d00000-0000-0000-0000-00000000007a',
   'takeaway', 'ILS', 8600, 8600, 'op-odi-1', 'submitted');

insert into order_items (
  id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor, status)
values
  -- 2 × Burger 240g + cheese + onion = 2 × (4000 + 300) = 8600.
  ('d0d00000-0000-0000-0000-0000000100a1', 'd0d00000-0000-0000-0000-0000000000a0',
   'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab',
   'd0d00000-0000-0000-0000-00000000010a', 'd0d00000-0000-0000-0000-000000001001',
   2, 'Burger', 4000, 8600, 'pending'),
  -- A historical line whose option the menu no longer knows (rank 0).
  ('d0d00000-0000-0000-0000-0000000100a2', 'd0d00000-0000-0000-0000-0000000000a0',
   'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab',
   'd0d00000-0000-0000-0000-00000000010a', 'd0d00000-0000-0000-0000-000000001001',
   1, 'Old Burger', 0, 0, 'pending'),
  -- A voided line: still never returned by the detail (unchanged).
  ('d0d00000-0000-0000-0000-0000000100a3', 'd0d00000-0000-0000-0000-0000000000a0',
   'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab',
   'd0d00000-0000-0000-0000-00000000010a', 'd0d00000-0000-0000-0000-000000001001',
   1, 'Voided Burger', 4000, 4000, 'voided');

-- Modifiers inserted in REVERSE dashboard order (onion, cheese, 240g).
insert into order_item_modifiers (
  id, organization_id, restaurant_id, branch_id, order_item_id,
  modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity)
values
  ('d0d00000-0000-0000-0000-000000010103', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000100a1', 'd0d00000-0000-0000-0000-00000000e0c4', 'onion',  0,   1),
  ('d0d00000-0000-0000-0000-000000010102', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000100a1', 'd0d00000-0000-0000-0000-00000000e0c1', 'cheese', 300, 1),
  ('d0d00000-0000-0000-0000-000000010101', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000100a1', 'd0d00000-0000-0000-0000-00000000e240', '240g',   0,   1),
  ('d0d00000-0000-0000-0000-000000010201', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000100a2', 'd0d00000-0000-0000-0000-0000000fffff', 'gone',   0,   1),
  ('d0d00000-0000-0000-0000-000000010202', 'd0d00000-0000-0000-0000-0000000000a0', 'd0d00000-0000-0000-0000-0000000000a1', 'd0d00000-0000-0000-0000-0000000000ab', 'd0d00000-0000-0000-0000-0000000100a2', 'd0d00000-0000-0000-0000-00000000e0d1', 'pickles', 0,  1);

-- Reorder the LIVE menu AFTER submit (the sanctioned app.menu_reorder gate):
-- the stored ranks must not follow it (D-008).
select set_config('app.menu_reordering', 'on', true);
update modifiers        set display_order = 9 where id = 'd0d00000-0000-0000-0000-00000000d102';
update modifier_options set display_order = 8 where id = 'd0d00000-0000-0000-0000-00000000e0c1';
select set_config('app.menu_reordering', 'off', true);

create temp table _d as
  select app.pos_order_detail('d0d00000-0000-0000-0000-00000000009a',
                              'd0d00000-0000-0000-0000-0000000000d1',
                              'd0d00000-0000-0000-0000-00000000010a') as res;

-- ===== A. the three new keys, from the STORED columns =======================
select is((select res ->> 'ok' from _d), 'true', '01 the authorized detail read succeeds');

select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res #> '{items,0,modifiers,0}') k),
  array['meat_snapshot','modifier_group_display_order_snapshot','modifier_name_snapshot',
        'modifier_option_display_order_snapshot','modifier_option_id','option_name_snapshot',
        'price_minor_snapshot','quantity'],
  '02 modifiers[] = the shipped keys + exactly modifier_option_id and the two display-order snapshots');

select is(
  (select jsonb_path_query_array(res, '$.items[0].modifiers[*].option_name_snapshot') from _d),
  '["240g", "cheese", "onion"]'::jsonb,
  '03 modifier ORDER is unchanged (dashboard order, not insertion order)');

select is(
  (select jsonb_path_query_array(res, '$.items[0].modifiers[*].modifier_option_id') from _d),
  '["d0d00000-0000-0000-0000-00000000e240", "d0d00000-0000-0000-0000-00000000e0c1", "d0d00000-0000-0000-0000-00000000e0c4"]'::jsonb,
  '04 each modifier carries its own option id');

select is(
  (select jsonb_path_query_array(res, '$.items[0].modifiers[*].modifier_group_display_order_snapshot') from _d),
  '[1, 2, 2]'::jsonb,
  '05 each modifier carries its group rank as an integer');

select is(
  (select jsonb_path_query_array(res, '$.items[0].modifiers[*].modifier_option_display_order_snapshot') from _d),
  '[1, 1, 2]'::jsonb,
  '06 each modifier carries its option rank as an integer');

select is(
  (select count(*)::int
     from _d
     cross join lateral jsonb_array_elements(res -> 'items') it
     cross join lateral jsonb_array_elements(it -> 'modifiers') md
     join order_item_modifiers m
       on m.organization_id = 'd0d00000-0000-0000-0000-0000000000a0'
      and m.order_item_id = (it ->> 'order_item_id')::uuid
      and m.modifier_option_id = (md ->> 'modifier_option_id')::uuid
    where (md ->> 'modifier_group_display_order_snapshot')::int = m.modifier_group_display_order_snapshot
      and (md ->> 'modifier_option_display_order_snapshot')::int = m.modifier_option_display_order_snapshot),
  5,
  '07 every emitted modifier matches its STORED row exactly (5 of 5), not the reordered live menu');

select is(
  (select res #> '{items,1,modifiers,0}' from _d)
    - 'modifier_name_snapshot' - 'option_name_snapshot' - 'price_minor_snapshot'
    - 'quantity' - 'meat_snapshot',
  '{"modifier_option_id": "d0d00000-0000-0000-0000-0000000fffff",
    "modifier_group_display_order_snapshot": 0,
    "modifier_option_display_order_snapshot": 0}'::jsonb,
  '08 an option the menu no longer knows: its id is still carried, ranks are the stored 0 (never re-derived)');

-- ===== B. everything else is unchanged =====================================
select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res #> '{items,0}') k),
  array['category_display_order_snapshot','item_display_order_snapshot','item_size_snapshot',
        'item_variant_snapshot','line_discount_minor','line_position','line_total_minor',
        'menu_item_id','menu_item_name_snapshot','modifiers','notes','order_item_id',
        'prep_snapshot','quantity','round_number','service_round_id','status',
        'unit_price_minor_snapshot'],
  '09 items[] keys are byte-unchanged (order_item_id, menu_item_id and status already present)');

select is(
  (select (res #>> '{items,0,order_item_id}') || '|' || (res #>> '{items,0,menu_item_id}') || '|' || (res #>> '{items,0,status}') from _d),
  'd0d00000-0000-0000-0000-0000000100a1|d0d00000-0000-0000-0000-000000001001|pending',
  '10 the item ids and status the POS parser now keeps are the stored values');

select is(
  (select jsonb_path_query_array(res, '$.items[*].menu_item_name_snapshot') from _d),
  '["Burger", "Old Burger"]'::jsonb,
  '11 voided lines are still excluded (unchanged)');

select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res -> 'order') k),
  array['created_at','currency_code','customer_name','customer_phone','discount_total_minor',
        'grand_total_minor','order_code','order_id','order_type','receipt_number','revision',
        'status','subtotal_minor','table_label','tax_total_minor','updated_at'],
  '12 the order header keys are byte-unchanged');

select is(
  (select array_agg(k order by k) from _d, jsonb_object_keys(res) k),
  array['entity','items','ok','order','payment','rounds','server_ts'],
  '13 the envelope keys are byte-unchanged');

select is(
  (select count(*)::int from _d, jsonb_array_elements(res -> 'items') it,
          jsonb_array_elements(it -> 'modifiers') md, jsonb_object_keys(md) k
    where k like '%\_minor' escape '\' and k <> 'price_minor_snapshot'),
  0,
  '14 no new money key: price_minor_snapshot stays the only *_minor key on a modifier');

select is(
  (select app.pos_order_detail('d0d00000-0000-0000-0000-00000000009a',
                               'd0d00000-0000-0000-0000-0000000000d1',
                               'd0d00000-0000-0000-0000-00000000090a') ->> 'error'),
  'order_not_found',
  '15 an unknown order id still returns order_not_found (envelope unchanged; foreign-vs-nonexistent no-oracle: psc_001c_service_rounds_test assert "85.")');

-- ===== C. definition posture unchanged =====================================
select ok(
  (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_detail'),
  '16 app.pos_order_detail stays SECURITY DEFINER, STABLE, search_path=''''');

select ok(
  has_function_privilege('authenticated', 'app.pos_order_detail(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'app.pos_order_detail(uuid, uuid, uuid)', 'execute'),
  '17 grants unchanged: authenticated may execute, anon may not');

select ok(
  (select p.prosrc like '%''modifier_option_id'',                     m.modifier_option_id,%'
      and p.prosrc like '%''modifier_group_display_order_snapshot'',  m.modifier_group_display_order_snapshot,%'
      and p.prosrc like '%''modifier_option_display_order_snapshot'', m.modifier_option_display_order_snapshot%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_order_detail'),
  '18 the live body emits the three keys straight from the stored columns');

select is(
  (select (res #>> '{items,1,modifiers,1,option_name_snapshot}') || '|'
          || (res #>> '{items,1,modifiers,1,modifier_group_display_order_snapshot}') || '|'
          || (res #>> '{items,1,modifiers,1,modifier_option_display_order_snapshot}') from _d)
   || '|' || (select (is_active and deleted_at is null)::text from modifier_options
               where id = 'd0d00000-0000-0000-0000-00000000e0d1'),
  'pickles|2|0|true',
  '19 rank 0 is NOT a liveness signal: a live, never-reordered option also carries option rank 0');

select * from finish();
rollback;
