-- ORDER-EDIT-001A — app.edit_order through app.sync_push (op order.edit):
-- the worked example (MONEY_AND_TAX_SPEC §9.2), the landing matrix on the KDS
-- channel (API_CONTRACT §4.45.4), unit closure, idempotent replay, and the
-- NORMATIVE rule that every refusal is decided before the first write (§4.45.1).
begin;
set local search_path to extensions, public, pg_catalog;

select plan(64);

-- ===== fixture ==============================================================
-- Org E: one KDS-mode branch with order editing ON; one POS + one KDS device;
-- cashier / manager / kitchen / void-denied cashier PIN sessions.
insert into organizations (id, name, slug, default_currency) values
  ('e0ed0000-0000-0000-0000-0000000000a0', 'Org Edit', 'org-edit-001a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000a0', 'Rest Edit');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled) values
  ('e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'Branch Edit', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e0ed0000-0000-0000-0000-0000000000d1', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'pos'),
  ('e0ed0000-0000-0000-0000-0000000000d2', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e0ed0000-0000-0000-0000-0000000000f1', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-0000000000d1', 'active'),
  ('e0ed0000-0000-0000-0000-0000000000f2', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-0000000000d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e0ed0000-0000-0000-0000-00000000005a', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-0000000000d1', 'e0ed0000-0000-0000-0000-0000000000f1'),
  ('e0ed0000-0000-0000-0000-00000000005b', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-0000000000d2', 'e0ed0000-0000-0000-0000-0000000000f2');
insert into app_users (id, email) values
  ('e0ed0000-0000-0000-0000-00000000006a', 'edit-cashier@example.test'),
  ('e0ed0000-0000-0000-0000-00000000006b', 'edit-manager@example.test'),
  ('e0ed0000-0000-0000-0000-00000000006c', 'edit-kitchen@example.test'),
  ('e0ed0000-0000-0000-0000-00000000006d', 'edit-novoid@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e0ed0000-0000-0000-0000-00000000007a', 'e0ed0000-0000-0000-0000-00000000006a', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('e0ed0000-0000-0000-0000-00000000007b', 'e0ed0000-0000-0000-0000-00000000006b', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('e0ed0000-0000-0000-0000-00000000007c', 'e0ed0000-0000-0000-0000-00000000006c', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb),
  ('e0ed0000-0000-0000-0000-00000000007d', 'e0ed0000-0000-0000-0000-00000000006d', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'cashier', '{"void_order":"false"}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e0ed0000-0000-0000-0000-00000000008a', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000006a', 'e0ed0000-0000-0000-0000-00000000007a', 'Dana Cashier'),
  ('e0ed0000-0000-0000-0000-00000000008b', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000006b', 'e0ed0000-0000-0000-0000-00000000007b', 'Mona Manager'),
  ('e0ed0000-0000-0000-0000-00000000008c', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000006c', 'e0ed0000-0000-0000-0000-00000000007c', 'Kim Kitchen'),
  ('e0ed0000-0000-0000-0000-00000000008d', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000006d', 'e0ed0000-0000-0000-0000-00000000007d', 'Noa Novoid');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e0ed0000-0000-0000-0000-00000000009a', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000005a', 'e0ed0000-0000-0000-0000-00000000008a', 'e0ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('e0ed0000-0000-0000-0000-00000000009b', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000005a', 'e0ed0000-0000-0000-0000-00000000008b', 'e0ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('e0ed0000-0000-0000-0000-00000000009c', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000005b', 'e0ed0000-0000-0000-0000-00000000008c', 'e0ed0000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  ('e0ed0000-0000-0000-0000-00000000009d', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000005a', 'e0ed0000-0000-0000-0000-00000000008d', 'e0ed0000-0000-0000-0000-00000000007d', now() + interval '1 hour'),
  ('e0ed0000-0000-0000-0000-00000000009e', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', 'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-00000000005b', 'e0ed0000-0000-0000-0000-00000000008a', 'e0ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- Menu: Burger 4000 (Extras: tomato 0, cucumber 0, cheese 300), Fries 1500,
-- Cola 800, Lemonade 900, Water 0.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e0ed0000-0000-0000-0000-0000000000c1', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e0ed0000-0000-0000-0000-000000001001', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('e0ed0000-0000-0000-0000-000000001002', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2),
  ('e0ed0000-0000-0000-0000-000000001003', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 3),
  ('e0ed0000-0000-0000-0000-000000001004', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-0000000000c1', 'Lemonade', 900, 'ILS', 4),
  ('e0ed0000-0000-0000-0000-000000001005', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-0000000000c1', 'Water', 0, 'ILS', 5);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('e0ed0000-0000-0000-0000-00000000d101', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('e0ed0000-0000-0000-0000-00000000e001', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-00000000d101', 'tomato',   0,   1, true),
  ('e0ed0000-0000-0000-0000-00000000e002', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-00000000d101', 'cucumber', 0,   2, true),
  ('e0ed0000-0000-0000-0000-00000000e003', 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1', null, 'e0ed0000-0000-0000-0000-00000000d101', 'cheese',   300, 3, true);

-- Order / line / modifier builders (direct inserts as the fixture role; the
-- line-position and display-order insert triggers still fire).
create function pg_temp.mk_order(p_id uuid, p_status text, p_type text default 'dine_in') returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at)
  values (p_id, 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1',
    'e0ed0000-0000-0000-0000-0000000000ab', 'e0ed0000-0000-0000-0000-0000000000d1',
    'e0ed0000-0000-0000-0000-00000000009a', 'e0ed0000-0000-0000-0000-00000000008a',
    'e0ed0000-0000-0000-0000-00000000007a', p_type, 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_round uuid default null, p_disc bigint default 0) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor, service_round_id)
  values (p_id, 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1',
    'e0ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, p_disc, p_total, p_round);
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_name text, p_price bigint, p_qty int default 1) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
  values ('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1',
    'e0ed0000-0000-0000-0000-0000000000ab', p_item, p_opt, 'Extras', p_name, p_price, p_qty);
$$;
create function pg_temp.mk_round(p_id uuid, p_order uuid, p_no int, p_status text) returns void
language sql as $$
  insert into order_service_rounds (id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, ready_at)
  values (p_id, 'e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000000a1',
    'e0ed0000-0000-0000-0000-0000000000ab', p_order, p_no, p_status,
    'e0ed0000-0000-0000-0000-0000000000d1', 'e0ed0000-0000-0000-0000-00000000008a',
    case when p_status in ('ready', 'served') then now() - interval '1 minute' end);
$$;
-- re-roll an order's stored totals from its live lines (tax off, no discount)
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push; returns the op's result
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'e0ed0000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;

-- ===== A. the worked example (MONEY §9.2): KDS, unit Waiting ==================
-- Burger 4000 (+tomato, +cucumber), Fries 1500, Cola 800 -> 6300. Edit: burger
-- without tomato, fries removed, one lemonade added -> 5700.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000a001', 'submitted');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000a1001', 'e0ed0000-0000-0000-0000-00000000a001', 'e0ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.mk_mod('e0ed0000-0000-0000-0000-0000000a1001', 'e0ed0000-0000-0000-0000-00000000e001', 'tomato', 0);
select pg_temp.mk_mod('e0ed0000-0000-0000-0000-0000000a1001', 'e0ed0000-0000-0000-0000-00000000e002', 'cucumber', 0);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000a1002', 'e0ed0000-0000-0000-0000-00000000a001', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000a1003', 'e0ed0000-0000-0000-0000-00000000a001', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000a001');

create temp table t_a as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'edit-a1',
  'e0ed0000-0000-0000-0000-00000000a001', '{
    "reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 5700, "tax_total_minor": 0, "grand_total_minor": 5700},
    "changes": [
      {"op": "modify", "order_item_id": "e0ed0000-0000-0000-0000-0000000a1001",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e0ed0000-0000-0000-0000-00000000e002"}]}]},
      {"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a1002"},
      {"op": "add", "item": {"menu_item_id": "e0ed0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;

select is((select r ->> 'status' from t_a), 'applied', '01 the worked-example edit is applied');
select ok((select (r ->> 'edit_number')::int = 1 and r ->> 'kitchen_channel' = 'kds'
                  and (r ->> 'kitchen_ack_required')::boolean and r -> 'new_round_id' = 'null'::jsonb
                  and not (r ->> 'unit1_closed')::boolean from t_a),
  '02 edit 1, KDS channel, confirmation required (it wrote to a Waiting unit), no new round');
select ok((select subtotal_minor = 5700 and tax_total_minor = 0 and grand_total_minor = 5700
                  and discount_total_minor = 0 and revision = 2 and edit_count = 1 and status = 'submitted'
             from orders where id = 'e0ed0000-0000-0000-0000-00000000a001'),
  '03 order: subtotal re-rolled to 5700, revision + 1, edit_count 1, status unchanged');
select ok((select (r -> 'before' ->> 'grand_total_minor')::bigint = 6300
                  and (r -> 'totals' ->> 'grand_total_minor')::bigint = 5700 from t_a),
  '04 envelope before/totals carry integer minor units 6300 -> 5700');
select ok((select status = 'cancelled' and removed_kitchen_stage = 'submitted'
                  and void_reason = 'order_edit:customer_changed_mind'
                  and removed_by_edit_id = ((select r ->> 'order_edit_id' from t_a))::uuid
                  and line_total_minor = 4000
             from order_items where id = 'e0ed0000-0000-0000-0000-0000000a1001'),
  '05 the modified burger is RETIRED (cancelled: its unit was Waiting), amounts kept');
select ok((select status = 'cancelled' and removed_by_edit_id is not null
             from order_items where id = 'e0ed0000-0000-0000-0000-0000000a1002'),
  '06 the removed fries line is cancelled with provenance');
select ok((select count(*) = 1 and bool_and(n.line_total_minor = 4000 and n.quantity = 1
                  and n.service_round_id is null and n.unit_price_minor_snapshot = 4000
                  and n.line_position = o.line_position and n.status = 'pending')
             from order_items n
             join order_items o on o.id = n.replaces_order_item_id
            where n.order_id = 'e0ed0000-0000-0000-0000-00000000a001'
              and n.replaces_order_item_id = 'e0ed0000-0000-0000-0000-0000000a1001'),
  '07 one replacement burger, in place, base price copied, old line_position kept');
select is((select string_agg(m.option_name_snapshot, ',' order by m.option_name_snapshot)
             from order_items n join order_item_modifiers m on m.order_item_id = n.id
            where n.replaces_order_item_id = 'e0ed0000-0000-0000-0000-0000000a1001'),
  'cucumber', '08 the replacement keeps cucumber only (tomato removed)');
select ok((select count(*) = 1 and bool_and(service_round_id is null and replaces_order_item_id is null
                  and edit_id is not null and line_total_minor = 900)
             from order_items where order_id = 'e0ed0000-0000-0000-0000-00000000a001'
              and menu_item_name_snapshot = 'Lemonade'),
  '09 the added lemonade lands in the ORIGINAL ticket (Waiting), no replaces');
select is((select sum(line_total_minor) from order_items
            where order_id = 'e0ed0000-0000-0000-0000-00000000a001' and status not in ('voided', 'cancelled')),
  5700::numeric, '10 money identity: subtotal = sum of live line totals');
select ok((select edit_number = 1 and reason_code = 'customer_changed_mind' and kitchen_channel = 'kds'
                  and kitchen_ack_required and kitchen_ack_at is null
                  and device_id = 'e0ed0000-0000-0000-0000-0000000000d1'
                  and employee_profile_id = 'e0ed0000-0000-0000-0000-00000000008a'
             from order_edits where order_id = 'e0ed0000-0000-0000-0000-00000000a001'),
  '11 one money-free order_edits row with the actor, reason and channel');
select is((select string_agg(c ->> 'landing', ',' order by o) from t_a,
                  jsonb_array_elements(r -> 'changes') with ordinality as x(c, o)),
  'in_place,removed,original_ticket', '12 per-change landing summary: modify in place, remove, add to the original');
select ok((select count(*) = 1 from audit_events
            where action = 'order.edited' and new_values ->> 'order_code' is not null
              and (new_values ->> 'edit_number')::int = 1
              and jsonb_array_length(new_values -> 'changes') = 3
              and (old_values ->> 'grand_total_minor')::bigint = 6300
              and (new_values ->> 'grand_total_minor')::bigint = 5700
              and actor_employee_profile_id = 'e0ed0000-0000-0000-0000-00000000008a'),
  '13 order.edited audit: actor, edit number, per-line changes, totals before/after');

-- A2. exact replay: the stored envelope, nothing written twice.
create temp table t_a2 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'edit-a1',
  'e0ed0000-0000-0000-0000-00000000a001', '{
    "reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 5700, "tax_total_minor": 0, "grand_total_minor": 5700},
    "changes": [
      {"op": "modify", "order_item_id": "e0ed0000-0000-0000-0000-0000000a1001",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e0ed0000-0000-0000-0000-00000000e002"}]}]},
      {"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a1002"},
      {"op": "add", "item": {"menu_item_id": "e0ed0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;
select ok((select (b.r ->> 'idempotency_replay')::boolean and b.r ->> 'order_edit_id' = a.r ->> 'order_edit_id'
             from t_a a, t_a2 b),
  '14 an exact replay returns the SAME edit (idempotency_replay)');
select ok((select count(*) = 1 from order_edits where order_id = 'e0ed0000-0000-0000-0000-00000000a001')
          and (select edit_count = 1 and revision = 2 from orders where id = 'e0ed0000-0000-0000-0000-00000000a001'),
  '15 the replay wrote nothing (one edit row, revision unchanged)');

-- A3. the business replay backstop: the same op id on ANOTHER order RAISES 40001.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000a002', 'submitted');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000a2001', 'e0ed0000-0000-0000-0000-00000000a002', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 2, 800, 1600);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000a002');
select throws_ok($$select app.edit_order('e0ed0000-0000-0000-0000-00000000009a', 'e0ed0000-0000-0000-0000-00000000a002',
    'e0ed0000-0000-0000-0000-0000000000d1', 'edit-a1',
    '{"expected": {"subtotal_minor": 2400, "tax_total_minor": 0, "grand_total_minor": 2400},
      "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 3}]}'::jsonb)$$,
  '40001', null, '16 the operation id reused on another order RAISES 40001');

-- ===== B. refusals are decided BEFORE the first write ========================
-- Snapshot of every table an edit could touch, compared after each refusal.
create function pg_temp.fp(p_order uuid) returns text language sql as $$
  select concat_ws('|',
    (select revision || ':' || edit_count || ':' || status || ':' || grand_total_minor from orders where id = p_order),
    (select count(*) from order_items where order_id = p_order),
    (select string_agg(status, ',' order by id) from order_items where order_id = p_order),
    (select count(*) from order_edits where order_id = p_order),
    (select count(*) from order_service_rounds where order_id = p_order),
    (select count(*) from order_operations where order_id = p_order),
    (select count(*) from kitchen_print_dispatches where order_id = p_order));
$$;
create temp table t_fp as select pg_temp.fp('e0ed0000-0000-0000-0000-00000000a002') as fp;
create function pg_temp.denied(p_res jsonb, p_error text, p_detail text default null) returns boolean
language sql as $$
  select p_res ->> 'status' = 'rejected' and p_res ->> 'error' = p_error
         and (p_detail is null or p_res ->> 'detail' = p_detail)
         and (select fp from t_fp) = pg_temp.fp('e0ed0000-0000-0000-0000-00000000a002');
$$;
-- the canonical valid payload for order a002 (Cola x2 -> x3 = 2400)
create function pg_temp.ok_payload() returns jsonb language sql as $$
  select '{"expected": {"subtotal_minor": 2400, "tax_total_minor": 0, "grand_total_minor": 2400},
           "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 3}]}'::jsonb;
$$;

select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-1', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() - 'expected'), 'expected_totals_required'),
  '17 expected totals are mandatory (expected_totals_required), nothing written');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-2', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": []}'), 'no_changes'), '18 no_changes');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-3', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || jsonb_build_object('changes', (select jsonb_agg('{"op":"add","item":{}}'::jsonb) from generate_series(1, 101)))),
  'too_many_changes'), '19 too_many_changes (> 100)');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-4', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001"},
                                         {"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 1}]}'),
  'duplicate_line_reference'), '20 duplicate_line_reference');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-5', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": [{"op": "replace", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001"}]}'),
  'invalid_payload'), '21 an unknown op is invalid_payload');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-6', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 1000}]}'),
  'invalid_payload'), '22 a quantity outside 1..999 is invalid_payload');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-shape-7', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 2}]}'),
  'invalid_payload'), '23 a no-op quantity (equal to the current one) is invalid_payload');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-line-1', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a1002"}]}'),
  'line_changed'), '24 a line of ANOTHER order (and retired at that) is line_changed');
select ok((select r -> 'stale_ids' = '["e0ed0000-0000-0000-0000-0000000a1002"]'::jsonb
             from (select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-line-2', 'e0ed0000-0000-0000-0000-00000000a002',
               pg_temp.ok_payload() || '{"changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a1002"}]}') as r) x),
  '25 line_changed echoes the stale ids');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-money-1', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"expected": {"subtotal_minor": 2400, "tax_total_minor": 0, "grand_total_minor": 2401}}'),
  'totals_mismatch'), '26 any expected total that differs is totals_mismatch');
select ok((select (r -> 'totals' ->> 'grand_total_minor')::bigint = 2400
                  and (r -> 'totals' ->> 'subtotal_minor')::bigint = 2400
             from (select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-money-2', 'e0ed0000-0000-0000-0000-00000000a002',
               pg_temp.ok_payload() || '{"expected": {"subtotal_minor": 1, "tax_total_minor": 0, "grand_total_minor": 1}}') as r) x),
  '27 totals_mismatch carries the server''s own figures');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-auth-1', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 1}]}'),
  'reason_required'), '28 a reduction needs a reason (reason_required)');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-auth-2', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"reason_code": "other", "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 1}]}'),
  'reason_required'), '29 reason "other" needs a text (reason_required)');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009d', 'b-auth-3', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload() || '{"reason_code": "entry_mistake", "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001", "quantity": 1}]}'),
  'permission_denied', 'removal_not_permitted'), '30 a void-denied cashier cannot REDUCE (removal_not_permitted)');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009e', 'b-dev-1', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload(), 'e0ed0000-0000-0000-0000-0000000000d2'), 'invalid_device_type'),
  '31 only a POS edits orders (a KDS device is invalid_device_type)');
select ok(pg_temp.denied(pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-empty-1', 'e0ed0000-0000-0000-0000-00000000a002',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 0, "tax_total_minor": 0, "grand_total_minor": 0},
    "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a2001"}]}'::jsonb),
  'edit_would_empty_order'), '32 removing every live line is edit_would_empty_order');
select ok((select count(*) >= 15 from audit_events
            where action = 'order.edit_denied' and new_values ->> 'attempted_action' = 'edit_order'
              and new_values ->> 'order_code' = '#' || upper(right(replace('e0ed0000-0000-0000-0000-00000000a002', '-', ''), 6))),
  '33 every refusal is audited order.edit_denied (same order code)');
select ok((select new_values ->> 'denied_reason' = 'removal_not_permitted' from audit_events
            where action = 'order.edit_denied' and actor_employee_profile_id = 'e0ed0000-0000-0000-0000-00000000008d'),
  '34 the audit records the detail token as denied_reason');
-- the void-denied cashier may still INCREASE without a reason (adding change)
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009d', 'b-auth-4', 'e0ed0000-0000-0000-0000-00000000a002',
  pg_temp.ok_payload())) ->> 'status', 'applied',
  '35 a void-denied cashier may INCREASE a sent line, no reason needed');
-- feature switch OFF
update branches set order_edit_enabled = false where id = 'e0ed0000-0000-0000-0000-0000000000ab';
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-off-1', 'e0ed0000-0000-0000-0000-00000000a002',
  '{"expected": {"subtotal_minor": 3200, "tax_total_minor": 0, "grand_total_minor": 3200},
    "changes": [{"op": "add", "item": {"menu_item_id": "e0ed0000-0000-0000-0000-000000001003", "quantity": 1,
      "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola"}}]}'::jsonb)) ->> 'error',
  'feature_disabled', '36 the branch switch OFF refuses every edit (feature_disabled)');
update branches set order_edit_enabled = true where id = 'e0ed0000-0000-0000-0000-0000000000ab';
-- anti-oracle: a nonexistent order RAISES 42501 (rolled back, flattened)
select ok((select r ->> 'status' = 'rejected' and r ->> 'sqlstate' = '42501'
             from (select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-oracle-1', 'e0ed0000-0000-0000-0000-00000000dead',
               pg_temp.ok_payload()) as r) x),
  '37 a nonexistent order RAISES 42501 (anti-oracle), never a typed refusal');

-- discounts / legacy lines can only be removed
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000a003', 'submitted');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000a3001', 'e0ed0000-0000-0000-0000-00000000a003', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 2800, null, 200);
-- legacy (pre-002A per-line price): 2 x (4000 + cheese 300) stored as 8300
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000a3002', 'e0ed0000-0000-0000-0000-00000000a003', 'e0ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8300);
select pg_temp.mk_mod('e0ed0000-0000-0000-0000-0000000a3002', 'e0ed0000-0000-0000-0000-00000000e003', 'cheese', 300);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000a003');
select ok(app.order_item_is_legacy_priced('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000a3002')
          and not app.order_item_is_legacy_priced('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000a3001')
          and not app.order_item_is_legacy_priced('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-0000000a1003'),
  '38 M1a legacy predicate: 2 x (4000+300) stored as 8300 is legacy; per-unit rows are not');
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-disc-1', 'e0ed0000-0000-0000-0000-00000000a003',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 9800, "tax_total_minor": 0, "grand_total_minor": 9800},
    "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a3001", "quantity": 1}]}'::jsonb)) ->> 'error',
  'line_has_discount', '39 a discounted line cannot be reduced (line_has_discount)');
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-leg-1', 'e0ed0000-0000-0000-0000-00000000a003',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 7100, "tax_total_minor": 0, "grand_total_minor": 7100},
    "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000a3002", "quantity": 1}]}'::jsonb)) ->> 'error',
  'legacy_line_not_editable', '40 a legacy line cannot be reduced (legacy_line_not_editable)');
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'b-leg-2', 'e0ed0000-0000-0000-0000-00000000a003',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 2800, "tax_total_minor": 0, "grand_total_minor": 2800},
    "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000a3002"}]}'::jsonb)) ->> 'status',
  'applied', '41 a legacy line CAN be removed');

-- ===== C. landing matrix, KDS channel ========================================
-- C1. unit In kitchen (preparing): remove -> voided; reduce -> remainder in
--     place; increase -> +N delta in place; confirmation required.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c001', 'preparing');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c1001', 'e0ed0000-0000-0000-0000-00000000c001', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 3, 1500, 4500);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c1002', 'e0ed0000-0000-0000-0000-00000000c001', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c1003', 'e0ed0000-0000-0000-0000-00000000c001', 'e0ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c001');
create temp table t_c1 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c1', 'e0ed0000-0000-0000-0000-00000000c001',
  '{"reason_code": "kitchen_issue",
    "expected": {"subtotal_minor": 5400, "tax_total_minor": 0, "grand_total_minor": 5400},
    "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000c1001", "quantity": 2},
                {"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000c1002", "quantity": 3},
                {"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c1003"}]}'::jsonb) as r;
select is((select r ->> 'status' from t_c1), 'applied', '42 C1 applied (In kitchen)');
select ok((select status = 'voided' and removed_kitchen_stage = 'preparing' from order_items where id = 'e0ed0000-0000-0000-0000-0000000c1003')
      and (select status = 'voided' from order_items where id = 'e0ed0000-0000-0000-0000-0000000c1001'),
  '43 C1 removed / reduced lines are voided (stage preparing)');
select ok((select quantity = 2 and line_total_minor = 3000 and service_round_id is null
                  and replaces_order_item_id = 'e0ed0000-0000-0000-0000-0000000c1001'
             from order_items where order_id = 'e0ed0000-0000-0000-0000-00000000c001'
              and replaces_order_item_id = 'e0ed0000-0000-0000-0000-0000000c1001'),
  '44 C1 the reduce remainder (2) is written in place and replaces the old line');
select ok((select status = 'pending' and removed_by_edit_id is null and quantity = 1
             from order_items where id = 'e0ed0000-0000-0000-0000-0000000c1002')
      and (select quantity = 2 and line_total_minor = 1600 and service_round_id is null and replaces_order_item_id is null
             from order_items where order_id = 'e0ed0000-0000-0000-0000-00000000c001'
              and menu_item_name_snapshot = 'Cola' and edit_id is not null),
  '45 C1 increase: the old line is KEPT and a +2 delta lands in place (no replaces)');
select ok((select (r ->> 'kitchen_ack_required')::boolean and r -> 'new_round_id' = 'null'::jsonb from t_c1),
  '46 C1 confirmation required, no round opened');

-- C2. unit Ready: increase -> +N in the edit's round; modify -> REMAKE in
--     the edit's round; the order stays ready (other live lines).
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c002', 'ready');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c2001', 'e0ed0000-0000-0000-0000-00000000c002', 'e0ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8000);
select pg_temp.mk_mod('e0ed0000-0000-0000-0000-0000000c2001', 'e0ed0000-0000-0000-0000-00000000e001', 'tomato', 0);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c2002', 'e0ed0000-0000-0000-0000-00000000c002', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c002');
create temp table t_c2 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c2', 'e0ed0000-0000-0000-0000-00000000c002',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 9900, "tax_total_minor": 0, "grand_total_minor": 9900},
    "changes": [{"op": "modify", "order_item_id": "e0ed0000-0000-0000-0000-0000000c2001",
                 "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e0ed0000-0000-0000-0000-00000000e001"},
                                                                 {"modifier_option_id": "e0ed0000-0000-0000-0000-00000000e003", "option_name_snapshot": "cheese", "price_minor_snapshot": 300}]},
                                  {"quantity": 1, "modifiers": [{"modifier_option_id": "e0ed0000-0000-0000-0000-00000000e001"}]}]},
                {"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000c2002", "quantity": 2}]}'::jsonb) as r;
select is((select r ->> 'status' from t_c2), 'applied', '47 C2 applied (Ready)');
select ok((select (r ->> 'new_round_number')::int = 2 and r ->> 'new_round_id' is not null from t_c2)
      and (select status = 'submitted' and edit_id is not null and local_operation_id is null
             from order_service_rounds where order_id = 'e0ed0000-0000-0000-0000-00000000c002'),
  '48 C2 the edit opened ONE round (round 2, submitted, edit_id set, no op id)');
select ok((select count(*) = 1 and bool_and(n.service_round_id = (select (r ->> 'new_round_id')::uuid from t_c2)
                  and n.line_total_minor = 4300)
             from order_items n where n.replaces_order_item_id = 'e0ed0000-0000-0000-0000-0000000c2001'
              and exists (select 1 from order_item_modifiers m where m.order_item_id = n.id and m.option_name_snapshot = 'cheese')),
  '49 C2 the CHANGED replacement (+cheese) lands in the edit''s round as REMAKE');
select ok((select count(*) = 1 and bool_and(n.service_round_id is null and n.line_total_minor = 4000)
             from order_items n where n.replaces_order_item_id = 'e0ed0000-0000-0000-0000-0000000c2001'
              and not exists (select 1 from order_item_modifiers m where m.order_item_id = n.id and m.option_name_snapshot = 'cheese')),
  '50 C2 the UNCHANGED replacement is a continuation, kept in place (nothing re-cooked)');
select ok((select count(*) = 1 from order_items n
            where n.order_id = 'e0ed0000-0000-0000-0000-00000000c002' and n.menu_item_name_snapshot = 'Cola'
              and n.edit_id is not null and n.quantity = 1
              and n.service_round_id = (select (r ->> 'new_round_id')::uuid from t_c2)),
  '51 C2 the +1 increase on a Ready unit lands in the edit''s round');
select ok((select (r -> 'changes' -> 0 ->> 'remake')::boolean and r -> 'changes' -> 0 ->> 'landing' = 'mixed'
                  and not (r -> 'changes' -> 1 ->> 'remake')::boolean from t_c2),
  '52 C2 envelope: the modify is a REMAKE with mixed landing');
select ok((select status = 'ready' and ready_at is not null from orders where id = 'e0ed0000-0000-0000-0000-00000000c002')
      and not app.order_rounds_all_served('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-00000000c002'),
  '53 C2 the order stays ready; the edit''s round now blocks completion');

-- C3. Served unit, adding only -> new ticket only: NO confirmation.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c003', 'served');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c3001', 'e0ed0000-0000-0000-0000-00000000c003', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c003');
create temp table t_c3 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c3', 'e0ed0000-0000-0000-0000-00000000c003',
  '{"expected": {"subtotal_minor": 2300, "tax_total_minor": 0, "grand_total_minor": 2300},
    "changes": [{"op": "add", "item": {"menu_item_id": "e0ed0000-0000-0000-0000-000000001002", "quantity": 1,
      "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and not (r ->> 'kitchen_ack_required')::boolean
                  and r -> 'changes' -> 0 ->> 'landing' = 'edit_round' from t_c3),
  '54 C3 an add to a served order opens a ticket and needs NO confirmation');

-- C4. Takeaway closure: emptying the In-kitchen original ticket while the
--     edit lands lines in its round -> served WITHOUT a ready_at stamp.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c004', 'preparing', 'takeaway');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c4001', 'e0ed0000-0000-0000-0000-00000000c004', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c004');
create temp table t_c4 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009b', 'c4', 'e0ed0000-0000-0000-0000-00000000c004',
  '{"reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
    "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c4001"},
                {"op": "add", "item": {"menu_item_id": "e0ed0000-0000-0000-0000-000000001003", "quantity": 1,
                  "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola"}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'unit1_closed')::boolean and r ->> 'order_status' = 'served' from t_c4)
      and (select status = 'served' and ready_at is null from orders where id = 'e0ed0000-0000-0000-0000-00000000c004'),
  '55 C4 the emptied original ticket moves the order to served, ready_at stays NULL');
select ok((select r.status = 'submitted' from order_service_rounds r where r.order_id = 'e0ed0000-0000-0000-0000-00000000c004')
      and not app.order_rounds_all_served('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-00000000c004')
      and (select status <> 'completed' from orders where id = 'e0ed0000-0000-0000-0000-00000000c004'),
  '56 C4 the edit''s round is still active, so completion cannot fire early');

-- C5. An emptied service round in submitted..ready is VOIDED by the edit and
--     no longer blocks completion.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c005', 'served');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c5001', 'e0ed0000-0000-0000-0000-00000000c005', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('e0ed0000-0000-0000-0000-0000000c5e02', 'e0ed0000-0000-0000-0000-00000000c005', 2, 'preparing');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c5002', 'e0ed0000-0000-0000-0000-00000000c005', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'e0ed0000-0000-0000-0000-0000000c5e02');
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c005');
select ok(not app.order_rounds_all_served('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-00000000c005'),
  '57 C5 before: the live round blocks completion');
create temp table t_c5 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c5', 'e0ed0000-0000-0000-0000-00000000c005',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
    "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c5002"}]}'::jsonb) as r;
select ok((select status = 'voided' and voided_by_edit_id is not null and ready_at is null
             from order_service_rounds where id = 'e0ed0000-0000-0000-0000-0000000c5e02')
      and (select jsonb_array_length(r -> 'rounds_closed') = 1 and (r ->> 'kitchen_ack_required')::boolean from t_c5),
  '58 C5 the emptied round is voided BY THE EDIT (and the kitchen must confirm)');
select ok(app.order_rounds_all_served('e0ed0000-0000-0000-0000-0000000000a0', 'e0ed0000-0000-0000-0000-00000000c005'),
  '59 C5 order_rounds_all_served ignores ONLY the edit-emptied round');

-- C6. finished food: switch ON -> a cashier may not remove Ready food; a
--     manager may.
update branches set order_edit_finished_food_manager_only = true where id = 'e0ed0000-0000-0000-0000-0000000000ab';
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c006', 'ready');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c6001', 'e0ed0000-0000-0000-0000-00000000c006', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c6002', 'e0ed0000-0000-0000-0000-00000000c006', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c006');
select ok((select r ->> 'error' = 'permission_denied' and r ->> 'detail' = 'finished_food_needs_manager'
             from (select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c6-cashier', 'e0ed0000-0000-0000-0000-00000000c006',
               '{"reason_code": "kitchen_issue", "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
                 "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c6001"}]}'::jsonb) as r) x),
  '60 C6 finished-food switch: a cashier removing Ready food is refused');
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009b', 'c6-manager', 'e0ed0000-0000-0000-0000-00000000c006',
  '{"reason_code": "kitchen_issue", "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
    "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c6001"}]}'::jsonb)) ->> 'status',
  'applied', '61 C6 a manager may');
update branches set order_edit_finished_food_manager_only = false where id = 'e0ed0000-0000-0000-0000-0000000000ab';

-- C7. zero-out guard: a cashier leaving only a free line (total > 0 -> 0) is
--     refused; a manager may (and the order auto-completes when served).
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c007', 'served');
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c7001', 'e0ed0000-0000-0000-0000-00000000c007', 'e0ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c7002', 'e0ed0000-0000-0000-0000-00000000c007', 'e0ed0000-0000-0000-0000-000000001005', 'Water', 1, 0, 0);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c007');
select ok((select r ->> 'error' = 'permission_denied' and r ->> 'detail' = 'full_comp_permission_required'
             from (select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c7-cashier', 'e0ed0000-0000-0000-0000-00000000c007',
               '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 0, "tax_total_minor": 0, "grand_total_minor": 0},
                 "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c7001"}]}'::jsonb) as r) x),
  '62 C7 a cashier cannot zero a chargeable order (full_comp_permission_required)');
create temp table t_c7 as select pg_temp.edit('e0ed0000-0000-0000-0000-00000000009b', 'c7-manager', 'e0ed0000-0000-0000-0000-00000000c007',
  '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 0, "tax_total_minor": 0, "grand_total_minor": 0},
    "changes": [{"op": "remove", "order_item_id": "e0ed0000-0000-0000-0000-0000000c7001"}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'auto_completed')::boolean and r ->> 'order_status' = 'completed' from t_c7)
      and (select status = 'completed' from orders where id = 'e0ed0000-0000-0000-0000-00000000c007')
      and exists (select 1 from audit_events where action = 'order.status_updated'
                   and new_values ->> 'completion_trigger' = 'order_edited'
                   and new_values ->> 'order_code' = '#' || upper(right(replace('e0ed0000-0000-0000-0000-00000000c007', '-', ''), 6))),
  '63 C7 a manager may; the served, now-free order auto-completes (trigger order_edited)');

-- C8. direct_print order on a KDS branch has no resolvable channel.
select pg_temp.mk_order('e0ed0000-0000-0000-0000-00000000c008', 'served');
update orders set dispatch_mode = 'direct_print' where id = 'e0ed0000-0000-0000-0000-00000000c008';
select pg_temp.mk_item('e0ed0000-0000-0000-0000-0000000c8001', 'e0ed0000-0000-0000-0000-00000000c008', 'e0ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e0ed0000-0000-0000-0000-00000000c008');
select is((pg_temp.edit('e0ed0000-0000-0000-0000-00000000009a', 'c8', 'e0ed0000-0000-0000-0000-00000000c008',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 0, "grand_total_minor": 1600},
    "changes": [{"op": "set_quantity", "order_item_id": "e0ed0000-0000-0000-0000-0000000c8001", "quantity": 2}]}'::jsonb)) ->> 'error',
  'kitchen_mode_changed', '64 C8 a direct-print order on a KDS branch is kitchen_mode_changed');

select * from finish();
rollback;
