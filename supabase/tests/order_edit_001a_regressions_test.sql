-- ORDER-EDIT-001A — regressions for the independent review findings:
-- canonical id spelling (an upper-case id can never skip a gate or re-price a
-- kept option), no reservation side effect, the no-op modify refusal, the
-- continuation-first allotment, +N deltas and the REMAKE flag, the literal
-- void acknowledgement widening, the Dashboard order detail and the sensitive-only
-- Activity Log filter, bill_presented_at parsing, the setter's uniform
-- not-found message, and the INSERT path of the supersession guard.
begin;
set local search_path to extensions, public, pg_catalog;

select plan(33);

-- ===== fixture (the order_edit_001a_edit_order_test shape, prefix e5ed) =====
-- Org E: one KDS-mode branch with order editing ON; one POS + one KDS device;
-- cashier / manager / kitchen / void-denied cashier PIN sessions.
insert into organizations (id, name, slug, default_currency) values
  ('e5ed0000-0000-0000-0000-0000000000a0', 'Org Edit', 'org-edit-001a-regr', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000a0', 'Rest Edit');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled) values
  ('e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'Branch Edit', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e5ed0000-0000-0000-0000-0000000000d1', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'pos'),
  ('e5ed0000-0000-0000-0000-0000000000d2', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e5ed0000-0000-0000-0000-0000000000f1', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-0000000000d1', 'active'),
  ('e5ed0000-0000-0000-0000-0000000000f2', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-0000000000d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e5ed0000-0000-0000-0000-00000000005a', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-0000000000d1', 'e5ed0000-0000-0000-0000-0000000000f1'),
  ('e5ed0000-0000-0000-0000-00000000005b', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-0000000000d2', 'e5ed0000-0000-0000-0000-0000000000f2');
insert into app_users (id, email) values
  ('e5ed0000-0000-0000-0000-00000000006a', 'r-edit-cashier@example.test'),
  ('e5ed0000-0000-0000-0000-00000000006b', 'r-edit-manager@example.test'),
  ('e5ed0000-0000-0000-0000-00000000006c', 'r-edit-kitchen@example.test'),
  ('e5ed0000-0000-0000-0000-00000000006d', 'r-edit-novoid@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e5ed0000-0000-0000-0000-00000000007a', 'e5ed0000-0000-0000-0000-00000000006a', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('e5ed0000-0000-0000-0000-00000000007b', 'e5ed0000-0000-0000-0000-00000000006b', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('e5ed0000-0000-0000-0000-00000000007c', 'e5ed0000-0000-0000-0000-00000000006c', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb),
  ('e5ed0000-0000-0000-0000-00000000007d', 'e5ed0000-0000-0000-0000-00000000006d', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'cashier', '{"void_order":"false"}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e5ed0000-0000-0000-0000-00000000008a', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000006a', 'e5ed0000-0000-0000-0000-00000000007a', 'Dana Cashier'),
  ('e5ed0000-0000-0000-0000-00000000008b', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000006b', 'e5ed0000-0000-0000-0000-00000000007b', 'Mona Manager'),
  ('e5ed0000-0000-0000-0000-00000000008c', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000006c', 'e5ed0000-0000-0000-0000-00000000007c', 'Kim Kitchen'),
  ('e5ed0000-0000-0000-0000-00000000008d', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000006d', 'e5ed0000-0000-0000-0000-00000000007d', 'Noa Novoid');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e5ed0000-0000-0000-0000-00000000009a', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000005a', 'e5ed0000-0000-0000-0000-00000000008a', 'e5ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('e5ed0000-0000-0000-0000-00000000009b', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000005a', 'e5ed0000-0000-0000-0000-00000000008b', 'e5ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('e5ed0000-0000-0000-0000-00000000009c', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000005b', 'e5ed0000-0000-0000-0000-00000000008c', 'e5ed0000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  ('e5ed0000-0000-0000-0000-00000000009d', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000005a', 'e5ed0000-0000-0000-0000-00000000008d', 'e5ed0000-0000-0000-0000-00000000007d', now() + interval '1 hour'),
  ('e5ed0000-0000-0000-0000-00000000009e', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000005b', 'e5ed0000-0000-0000-0000-00000000008a', 'e5ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- Menu: Burger 4000 (Extras: tomato 0, cucumber 0, cheese 300), Fries 1500,
-- Cola 800, Lemonade 900, Water 0.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e5ed0000-0000-0000-0000-0000000000c1', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e5ed0000-0000-0000-0000-000000001001', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('e5ed0000-0000-0000-0000-000000001002', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2),
  ('e5ed0000-0000-0000-0000-000000001003', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 3),
  ('e5ed0000-0000-0000-0000-000000001004', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-0000000000c1', 'Lemonade', 900, 'ILS', 4),
  ('e5ed0000-0000-0000-0000-000000001005', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-0000000000c1', 'Water', 0, 'ILS', 5);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('e5ed0000-0000-0000-0000-00000000d101', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('e5ed0000-0000-0000-0000-00000000e001', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-00000000d101', 'tomato',   0,   1, true),
  ('e5ed0000-0000-0000-0000-00000000e002', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-00000000d101', 'cucumber', 0,   2, true),
  ('e5ed0000-0000-0000-0000-00000000e003', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', null, 'e5ed0000-0000-0000-0000-00000000d101', 'cheese',   300, 3, true);

-- Order / line / modifier builders (direct inserts as the fixture role; the
-- line-position and display-order insert triggers still fire).
create function pg_temp.mk_order(p_id uuid, p_status text, p_type text default 'dine_in') returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at)
  values (p_id, 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1',
    'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-0000000000d1',
    'e5ed0000-0000-0000-0000-00000000009a', 'e5ed0000-0000-0000-0000-00000000008a',
    'e5ed0000-0000-0000-0000-00000000007a', p_type, 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_round uuid default null, p_disc bigint default 0) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor, service_round_id)
  values (p_id, 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1',
    'e5ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, p_disc, p_total, p_round);
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_name text, p_price bigint, p_qty int default 1) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
  values ('e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1',
    'e5ed0000-0000-0000-0000-0000000000ab', p_item, p_opt, 'Extras', p_name, p_price, p_qty);
$$;
create function pg_temp.mk_round(p_id uuid, p_order uuid, p_no int, p_status text) returns void
language sql as $$
  insert into order_service_rounds (id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, ready_at)
  values (p_id, 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1',
    'e5ed0000-0000-0000-0000-0000000000ab', p_order, p_no, p_status,
    'e5ed0000-0000-0000-0000-0000000000d1', 'e5ed0000-0000-0000-0000-00000000008a',
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
  p_dev uuid default 'e5ed0000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;


-- extra fixture: an org owner (Dashboard reads), a reservable table, and a
-- printer-only branch of the same org.
insert into app_users (id, email) values
  ('e5ed0000-0000-0000-0000-00000000006f', 'r-edit-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e5ed0000-0000-0000-0000-00000000007f', 'e5ed0000-0000-0000-0000-00000000006f', 'e5ed0000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb);
insert into tables (id, organization_id, restaurant_id, branch_id, label, status) values
  ('e5ed0000-0000-0000-0000-0000000000b1', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', 'T1', 'available');

-- ===== R1. canonical spelling: an UPPER-CASE line id cannot skip a gate =====
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a101', 'preparing');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a1101', 'e5ed0000-0000-0000-0000-00000000a101', 'e5ed0000-0000-0000-0000-000000001002', 'Fries', 3, 1500, 4500);
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a1102', 'e5ed0000-0000-0000-0000-00000000a101', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a101');
select ok((select r ->> 'error' = 'permission_denied' and r ->> 'detail' = 'removal_not_permitted'
             from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009d', 'r1-novoid', 'e5ed0000-0000-0000-0000-00000000a101',
               '{"expected": {"subtotal_minor": 1, "tax_total_minor": 0, "grand_total_minor": 1},
                 "changes": [{"op": "set_quantity", "order_item_id": "E5ED0000-0000-0000-0000-0000000A1101", "quantity": 1}]}'::jsonb) as r) x),
  '01 an UPPER-CASE line id still hits the authorization gate (removal_not_permitted, not a 23502)');
select ok((select r ->> 'error' = 'totals_mismatch'
             from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009b', 'r1-totals', 'e5ed0000-0000-0000-0000-00000000a101',
               '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 1, "tax_total_minor": 0, "grand_total_minor": 1},
                 "changes": [{"op": "remove", "order_item_id": "E5ED0000-0000-0000-0000-0000000A1102"}]}'::jsonb) as r) x),
  '02 ...and the money gate (totals_mismatch, not a 23502)');
-- (two statements: a write made inside a call is visible only to a LATER statement)
create temp table t_r1 as select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009b', 'r1-ok', 'e5ed0000-0000-0000-0000-00000000a101',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 4500, "tax_total_minor": 0, "grand_total_minor": 4500},
    "changes": [{"op": "remove", "order_item_id": "E5ED0000-0000-0000-0000-0000000A1102"}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_r1)
      and (select status = 'voided' and removed_by_edit_id is not null from order_items where id = 'e5ed0000-0000-0000-0000-0000000a1102'),
  '03 a valid UPPER-CASE reference is applied to the right line');

-- R2. an UPPER-CASE kept option is still the KEPT option (frozen price kept)
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a201', 'ready');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a2101', 'e5ed0000-0000-0000-0000-00000000a201', 'e5ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4300);
select pg_temp.mk_mod('e5ed0000-0000-0000-0000-0000000a2101', 'e5ed0000-0000-0000-0000-00000000e003', 'cheese', 300);
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a2102', 'e5ed0000-0000-0000-0000-00000000a201', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a201');
create temp table t_r2 as select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r2', 'e5ed0000-0000-0000-0000-00000000a201',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 9100, "tax_total_minor": 0, "grand_total_minor": 9100},
    "changes": [{"op": "modify", "order_item_id": "e5ed0000-0000-0000-0000-0000000a2101",
                 "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "E5ED0000-0000-0000-0000-00000000E003",
                                                                 "option_name_snapshot": "cheese", "price_minor_snapshot": 0}]},
                                  {"quantity": 1, "modifiers": []}]}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and not (r -> 'changes' -> 0 ->> 'remake')::boolean from t_r2)
      and (select count(*) = 1 and bool_and(n.service_round_id is null and m.price_minor_snapshot = 300 and n.line_total_minor = 4300)
             from order_items n join order_item_modifiers m on m.order_item_id = n.id
            where n.replaces_order_item_id = 'e5ed0000-0000-0000-0000-0000000a2101'),
  '04 an UPPER-CASE kept option is the KEPT option: the continuation keeps its frozen 300 in place, no REMAKE');

-- ===== R3. an ordinary edit never clears a table reservation ==================
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a301', 'preparing');
update orders set table_id = 'e5ed0000-0000-0000-0000-0000000000b1' where id = 'e5ed0000-0000-0000-0000-00000000a301';
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a3101', 'e5ed0000-0000-0000-0000-00000000a301', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a301');
update tables set status = 'reserved' where id = 'e5ed0000-0000-0000-0000-0000000000b1';
select is((pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r3', 'e5ed0000-0000-0000-0000-00000000a301',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 0, "grand_total_minor": 1600},
    "changes": [{"op": "set_quantity", "order_item_id": "e5ed0000-0000-0000-0000-0000000a3101", "quantity": 2}]}'::jsonb)) ->> 'status',
  'applied', '05 the edit is applied');
select is((select status from tables where id = 'e5ed0000-0000-0000-0000-0000000000b1'), 'reserved',
  '06 ...and the table reservation is untouched (status is not rewritten by an ordinary edit)');

-- ===== R4. a modify that changes nothing is refused like a no-op quantity =====
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a401', 'preparing');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a4101', 'e5ed0000-0000-0000-0000-00000000a401', 'e5ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8000);
select pg_temp.mk_mod('e5ed0000-0000-0000-0000-0000000a4101', 'e5ed0000-0000-0000-0000-00000000e001', 'tomato', 0);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a401');
select ok((select r ->> 'error' = 'invalid_payload' from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r4', 'e5ed0000-0000-0000-0000-00000000a401',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 8000, "tax_total_minor": 0, "grand_total_minor": 8000},
    "changes": [{"op": "modify", "order_item_id": "e5ed0000-0000-0000-0000-0000000a4101",
                 "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e5ed0000-0000-0000-0000-00000000e001"}]},
                                  {"quantity": 1, "modifiers": [{"modifier_option_id": "e5ed0000-0000-0000-0000-00000000e001"}]}]}]}'::jsonb) as r) x)
      and (select count(*) = 0 from order_edits where order_id = 'e5ed0000-0000-0000-0000-00000000a401'),
  '07 a modify whose replacements are all unchanged and keep the quantity is invalid_payload, nothing written');

-- ===== R5. Ready unit, more dishes than before: the UNCHANGED dishes keep the
--           finished food in place; the changed dish beyond the old quantity
--           is a NEW dish in the edit's round (no REMAKE, nothing wasted) ====
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a501', 'ready');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a5101', 'e5ed0000-0000-0000-0000-00000000a501', 'e5ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8000);
select pg_temp.mk_mod('e5ed0000-0000-0000-0000-0000000a5101', 'e5ed0000-0000-0000-0000-00000000e001', 'tomato', 0);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a501');
create temp table t_r5 as select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r5', 'e5ed0000-0000-0000-0000-00000000a501',
  '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 12300, "tax_total_minor": 0, "grand_total_minor": 12300},
    "changes": [{"op": "modify", "order_item_id": "e5ed0000-0000-0000-0000-0000000a5101",
                 "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e5ed0000-0000-0000-0000-00000000e003", "option_name_snapshot": "cheese", "price_minor_snapshot": 300}]},
                                  {"quantity": 2, "modifiers": [{"modifier_option_id": "e5ed0000-0000-0000-0000-00000000e001"}]}]}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and not (r -> 'changes' -> 0 ->> 'remake')::boolean
                  and r -> 'changes' -> 0 ->> 'landing' = 'mixed' from t_r5),
  '08 R5 applied, mixed landing, and NOT a remake (no finished dish is taken back)');
select ok((select count(*) = 1 and bool_and(service_round_id is null and quantity = 2 and line_total_minor = 8000)
             from order_items where order_id = 'e5ed0000-0000-0000-0000-00000000a501'
              and replaces_order_item_id = 'e5ed0000-0000-0000-0000-0000000a5101'),
  '09 R5 the continuation keeps BOTH finished dishes in place (replaces the old line)');
select ok((select count(*) = 1 and bool_and(replaces_order_item_id is null and quantity = 1 and line_total_minor = 4300
                  and service_round_id = (select (r ->> 'new_round_id')::uuid from t_r5))
             from order_items where order_id = 'e5ed0000-0000-0000-0000-00000000a501'
              and edit_id is not null and service_round_id is not null),
  '10 R5 the changed (+cheese) dish beyond the old quantity is a NEW dish in the edit''s round (reported as added)');
select ok((select (r ->> 'kitchen_ack_required')::boolean from t_r5),
  '11 R5 the kitchen still confirms (the edit retired a line of a Ready unit)');

-- R6. a modify whose replacements are ALL unchanged is a quantity change in
--     disguise: refused (it must be a set_quantity), even with another total
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a601', 'ready');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a6101', 'e5ed0000-0000-0000-0000-00000000a601', 'e5ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8000);
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a6102', 'e5ed0000-0000-0000-0000-00000000a601', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a601');
select ok((select r ->> 'error' = 'invalid_payload'
             from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r6', 'e5ed0000-0000-0000-0000-00000000a601',
               '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 12800, "tax_total_minor": 0, "grand_total_minor": 12800},
                 "changes": [{"op": "modify", "order_item_id": "e5ed0000-0000-0000-0000-0000000a6101",
                              "replacements": [{"quantity": 3, "modifiers": []}]}]}'::jsonb) as r) x)
      and (select count(*) = 0 from order_edits where order_id = 'e5ed0000-0000-0000-0000-00000000a601'),
  '12 R6 an all-unchanged modify that RAISES the quantity is invalid_payload (send a set_quantity), nothing written');

-- R7. In-kitchen unit: the unchanged dish continues in place; the changed dish
--     beyond the old quantity is a NEW dish IN PLACE (no replaces), exactly
--     like an increase.
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a701', 'preparing');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a7101', 'e5ed0000-0000-0000-0000-00000000a701', 'e5ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a701');
create temp table t_r7 as select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r7', 'e5ed0000-0000-0000-0000-00000000a701',
  '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 8300, "tax_total_minor": 0, "grand_total_minor": 8300},
    "changes": [{"op": "modify", "order_item_id": "e5ed0000-0000-0000-0000-0000000a7101",
                 "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e5ed0000-0000-0000-0000-00000000e003", "option_name_snapshot": "cheese", "price_minor_snapshot": 300}]},
                                  {"quantity": 1, "modifiers": []}]}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and r -> 'changes' -> 0 ->> 'landing' = 'in_place'
                  and not (r -> 'changes' -> 0 ->> 'remake')::boolean and r -> 'new_round_id' = 'null'::jsonb from t_r7)
      and (select count(*) = 1 from order_items where order_id = 'e5ed0000-0000-0000-0000-00000000a701'
              and edit_id is not null and replaces_order_item_id is null and line_total_minor = 4300 and service_round_id is null)
      and (select count(*) = 1 from order_items where order_id = 'e5ed0000-0000-0000-0000-00000000a701'
              and replaces_order_item_id = 'e5ed0000-0000-0000-0000-0000000a7101' and line_total_minor = 4000),
  '13 R7 In kitchen: the plain dish continues in place (replaces), the +cheese dish is a new dish in place (no replaces)');

-- ===== R8. the void acknowledgement widening (the literal contract rule) =====
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a801', 'served');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a8101', 'e5ed0000-0000-0000-0000-00000000a801', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('e5ed0000-0000-0000-0000-0000000a8e02', 'e5ed0000-0000-0000-0000-00000000a801', 2, 'submitted');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a8102', 'e5ed0000-0000-0000-0000-00000000a801', 'e5ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'e5ed0000-0000-0000-0000-0000000a8e02');
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a801');
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a802', 'served');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a8201', 'e5ed0000-0000-0000-0000-00000000a802', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('e5ed0000-0000-0000-0000-0000000a8e12', 'e5ed0000-0000-0000-0000-00000000a802', 2, 'submitted');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a8202', 'e5ed0000-0000-0000-0000-00000000a802', 'e5ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'e5ed0000-0000-0000-0000-0000000a8e12');
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a802');
update orders set dispatch_mode = 'direct_print' where id = 'e5ed0000-0000-0000-0000-00000000a802';
create temp table t_r8a as select app.void_order('e5ed0000-0000-0000-0000-00000000009b', 'e5ed0000-0000-0000-0000-00000000a801',
  'e5ed0000-0000-0000-0000-0000000000d1', 'r8-void-kds', 'wrong order') as r;
select ok((select (r ->> 'ok')::boolean from t_r8a)
      and (select kitchen_ack_required from orders where id = 'e5ed0000-0000-0000-0000-00000000a801'),
  '14 KDS channel: a served order with a live round needs the kitchen acknowledgement');
create temp table t_r8b as select app.void_order('e5ed0000-0000-0000-0000-00000000009b', 'e5ed0000-0000-0000-0000-00000000a802',
  'e5ed0000-0000-0000-0000-0000000000d1', 'r8-void-dp', 'wrong order') as r;
select ok((select (r ->> 'ok')::boolean from t_r8b)
      and (select kitchen_ack_required from orders where id = 'e5ed0000-0000-0000-0000-00000000a802'),
  '15 a direct_print order with a live round carries the flag too (contract-literal; only the KDS reads it)');
update branches set kitchen_workflow_mode = 'printer_only' where id = 'e5ed0000-0000-0000-0000-0000000000ab';
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a803', 'served');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a8301', 'e5ed0000-0000-0000-0000-00000000a803', 'e5ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('e5ed0000-0000-0000-0000-0000000a8e22', 'e5ed0000-0000-0000-0000-00000000a803', 2, 'submitted');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a8302', 'e5ed0000-0000-0000-0000-00000000a803', 'e5ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'e5ed0000-0000-0000-0000-0000000a8e22');
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a803');
create temp table t_r8c as select app.void_order('e5ed0000-0000-0000-0000-00000000009b', 'e5ed0000-0000-0000-0000-00000000a803',
  'e5ed0000-0000-0000-0000-0000000000d1', 'r8-void-po', 'wrong order') as r;
select ok((select (r ->> 'ok')::boolean from t_r8c)
      and (select kitchen_ack_required and voided_from_status = 'served' from orders where id = 'e5ed0000-0000-0000-0000-00000000a803'),
  '16 ...as on a printer_only branch (where PSC-001D already set it for submitted voids)');
update branches set kitchen_workflow_mode = 'kds' where id = 'e5ed0000-0000-0000-0000-0000000000ab';

-- ===== R9. the Dashboard order detail lists live lines only ==================
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000a901', 'preparing');
select pg_temp.mk_item('e5ed0000-0000-0000-0000-0000000a9101', 'e5ed0000-0000-0000-0000-00000000a901', 'e5ed0000-0000-0000-0000-000000001002', 'Fries', 3, 1500, 4500);
select pg_temp.settle_totals('e5ed0000-0000-0000-0000-00000000a901');
select is((pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r9', 'e5ed0000-0000-0000-0000-00000000a901',
  '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 3000, "tax_total_minor": 0, "grand_total_minor": 3000},
    "changes": [{"op": "set_quantity", "order_item_id": "e5ed0000-0000-0000-0000-0000000a9101", "quantity": 2}]}'::jsonb)) ->> 'status',
  'applied', '17 R9 the 3 -> 2 edit is applied');
set local role authenticated;
set local app.current_app_user_id = 'e5ed0000-0000-0000-0000-00000000006f';
create temp table t_r9 as select app.owner_order_detail('e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1',
  'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000a901') as r;
create temp table t_r9b as select app.owner_order_detail('e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1',
  'e5ed0000-0000-0000-0000-0000000000ab', 'e5ed0000-0000-0000-0000-00000000a802') as r;
create temp table t_r10 as select app.owner_audit_events('e5ed0000-0000-0000-0000-0000000000a0', null, null, 'today',
  p_sensitive_only => true, p_action => 'order.edited', p_limit => 200) as r;
reset role;
select ok((select jsonb_array_length(r -> 'order' -> 'items') = 1
                  and (r -> 'order' -> 'items' -> 0 ->> 'quantity')::int = 2
                  and (r -> 'order' -> 'items' -> 0 ->> 'line_total_minor')::bigint = 3000 from t_r9),
  '18 R9 owner_order_detail lists the remainder only (the retired line is not a second line)');
select ok((select jsonb_array_length(r -> 'order' -> 'items') = 2 from t_r9b),
  '19 R9 a VOIDED, unedited order still lists every line (unchanged)');

-- ===== R10. order.edited is a sensitive Activity Log action ==================
select ok((select (r ->> 'count')::int >= 5
                  and (select bool_and(e ->> 'action' = 'order.edited') from jsonb_array_elements(r -> 'events') e) from t_r10),
  '20 R10 sensitive_only returns the applied order.edited rows (API §4.33 item 9)');

-- ===== R11. bill_presented_at: ISO date-times only ===========================
select ok((select r ->> 'error' = 'invalid_payload' from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r11-inf', 'e5ed0000-0000-0000-0000-00000000a901',
  '{"bill_presented_at": "infinity", "expected": {"subtotal_minor": 4500, "tax_total_minor": 0, "grand_total_minor": 4500},
    "changes": [{"op": "add", "item": {"menu_item_id": "e5ed0000-0000-0000-0000-000000001002", "quantity": 1, "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb) as r) x),
  '21 R11 bill_presented_at "infinity" is invalid_payload');
select ok((select r ->> 'error' = 'invalid_payload' from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r11-now', 'e5ed0000-0000-0000-0000-00000000a901',
  '{"bill_presented_at": "now", "expected": {"subtotal_minor": 4500, "tax_total_minor": 0, "grand_total_minor": 4500},
    "changes": [{"op": "add", "item": {"menu_item_id": "e5ed0000-0000-0000-0000-000000001002", "quantity": 1, "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb) as r) x),
  '22 R11 bill_presented_at "now" is invalid_payload');
select ok((select r ->> 'error' = 'invalid_payload' from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r11-bc', 'e5ed0000-0000-0000-0000-00000000a901',
  '{"bill_presented_at": "2026-10-08 10:00 BC", "expected": {"subtotal_minor": 4500, "tax_total_minor": 0, "grand_total_minor": 4500},
    "changes": [{"op": "add", "item": {"menu_item_id": "e5ed0000-0000-0000-0000-000000001002", "quantity": 1, "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb) as r) x)
      and (select r ->> 'error' = 'invalid_payload' from (select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r11-nooffset', 'e5ed0000-0000-0000-0000-00000000a901',
  '{"bill_presented_at": "2026-10-08T12:30:00", "expected": {"subtotal_minor": 4500, "tax_total_minor": 0, "grand_total_minor": 4500},
    "changes": [{"op": "add", "item": {"menu_item_id": "e5ed0000-0000-0000-0000-000000001002", "quantity": 1, "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb) as r) x),
  '22b R11 a BC suffix or a missing offset is invalid_payload (one RFC 3339 wire format)');
create temp table t_r11 as select pg_temp.edit('e5ed0000-0000-0000-0000-00000000009a', 'r11-ok', 'e5ed0000-0000-0000-0000-00000000a901',
  '{"bill_presented_at": "2026-10-08T12:30:00Z", "expected": {"subtotal_minor": 4500, "tax_total_minor": 0, "grand_total_minor": 4500},
    "changes": [{"op": "add", "item": {"menu_item_id": "e5ed0000-0000-0000-0000-000000001002", "quantity": 1, "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_r11)
      and (select bill_presented_at = '2026-10-08T12:30:00Z'::timestamptz from order_edits
            where order_id = 'e5ed0000-0000-0000-0000-00000000a901' and edit_number = 2),
  '23 R11 an ISO bill_presented_at is accepted and stored');

-- ===== R12. the setter is no existence oracle ================================
insert into organizations (id, name, slug, default_currency) values
  ('e5ed0000-0000-0000-0000-0000000000b0', 'Org Other', 'org-edit-001a-other', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e5ed0000-0000-0000-0000-0000000000b9', 'e5ed0000-0000-0000-0000-0000000000b0', 'Rest Other');
insert into branches (id, organization_id, restaurant_id, name) values
  ('e5ed0000-0000-0000-0000-0000000000bb', 'e5ed0000-0000-0000-0000-0000000000b0', 'e5ed0000-0000-0000-0000-0000000000b9', 'Branch Other');
set local role authenticated;
set local app.current_app_user_id = 'e5ed0000-0000-0000-0000-00000000006f';
select throws_ok($$select public.set_branch_order_edit_settings('e5ed0000-0000-0000-0000-00000000cc01',
    'e5ed0000-0000-0000-0000-0000000000b0', 'e5ed0000-0000-0000-0000-0000000000b9', 'e5ed0000-0000-0000-0000-0000000000bb', true, false)$$,
  '42501', 'set_branch_order_edit_settings: branch not found or not accessible',
  '24 R12 another tenant''s REAL branch -> the uniform not-found message');
select throws_ok($$select public.set_branch_order_edit_settings('e5ed0000-0000-0000-0000-00000000cc02',
    'e5ed0000-0000-0000-0000-0000000000b0', 'e5ed0000-0000-0000-0000-0000000000b9', 'e5ed0000-0000-0000-0000-0000000000cc', true, false)$$,
  '42501', 'set_branch_order_edit_settings: branch not found or not accessible',
  '25 R12 a NONEXISTENT branch -> the same message');
select ok((public.set_branch_order_edit_settings('e5ed0000-0000-0000-0000-00000000cc03',
    'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab', true, true) ->> 'ok')::boolean,
  '26 R12 control: the owner of the branch succeeds');
-- re-using that request key against another tenant's REAL branch, or a
-- nonexistent one, still yields the one uniform message (the membership and
-- existence checks run before the idempotency lookup).
select throws_ok($$select public.set_branch_order_edit_settings('e5ed0000-0000-0000-0000-00000000cc03',
    'e5ed0000-0000-0000-0000-0000000000b0', 'e5ed0000-0000-0000-0000-0000000000b9', 'e5ed0000-0000-0000-0000-0000000000bb', true, true)$$,
  '42501', 'set_branch_order_edit_settings: branch not found or not accessible',
  '26b R12 a reused key on another tenant''s REAL branch -> the uniform message');
select throws_ok($$select public.set_branch_order_edit_settings('e5ed0000-0000-0000-0000-00000000cc03',
    'e5ed0000-0000-0000-0000-0000000000b0', 'e5ed0000-0000-0000-0000-0000000000b9', 'e5ed0000-0000-0000-0000-0000000000cc', true, true)$$,
  '42501', 'set_branch_order_edit_settings: branch not found or not accessible',
  '26c R12 the same reused key on a NONEXISTENT branch -> the same message');
reset role;

-- ===== R13. supersession guard, INSERT path ==================================
-- Two order_edit dispatches of one order: edit1 is superseded by edit2; an
-- initial row INSERTED pointing at the superseded edit1 is rejected.
select pg_temp.mk_order('e5ed0000-0000-0000-0000-00000000ad01', 'submitted');
insert into order_edits (id, organization_id, restaurant_id, branch_id, order_id, edit_number, device_id, local_operation_id,
  pin_session_id, employee_profile_id, membership_id, kitchen_channel) values
  ('e5ed0000-0000-0000-0000-0000000ed001', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab',
   'e5ed0000-0000-0000-0000-00000000ad01', 1, 'e5ed0000-0000-0000-0000-0000000000d1', 'r13-e1',
   'e5ed0000-0000-0000-0000-00000000009a', 'e5ed0000-0000-0000-0000-00000000008a', 'e5ed0000-0000-0000-0000-00000000007a', 'paper'),
  ('e5ed0000-0000-0000-0000-0000000ed002', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab',
   'e5ed0000-0000-0000-0000-00000000ad01', 2, 'e5ed0000-0000-0000-0000-0000000000d1', 'r13-e2',
   'e5ed0000-0000-0000-0000-00000000009a', 'e5ed0000-0000-0000-0000-00000000008a', 'e5ed0000-0000-0000-0000-00000000007a', 'paper');
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, order_edit_id, money_free_payload, idempotency_key) values
  ('e5ed0000-0000-0000-0000-0000000dd001', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab',
   'e5ed0000-0000-0000-0000-00000000ad01', 'order_edit', 'e5ed0000-0000-0000-0000-0000000ed001', '{"v":1,"kind":"order_edit"}'::jsonb, 'edit:r13-1'),
  ('e5ed0000-0000-0000-0000-0000000dd002', 'e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab',
   'e5ed0000-0000-0000-0000-00000000ad01', 'order_edit', 'e5ed0000-0000-0000-0000-0000000ed002', '{"v":1,"kind":"order_edit"}'::jsonb, 'edit:r13-2');
select lives_ok($$update kitchen_print_dispatches set superseded_by_dispatch_id = 'e5ed0000-0000-0000-0000-0000000dd002'
                   where id = 'e5ed0000-0000-0000-0000-0000000dd001'$$,
  '27 R13 an order_edit dispatch may be superseded by a newer order_edit dispatch');
select throws_ok($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
     values ('e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab',
             'e5ed0000-0000-0000-0000-00000000ad01', 'initial_order', '{"v":1}'::jsonb, 'r13-initial',
             'e5ed0000-0000-0000-0000-0000000dd001')$$,
  '23514', 'kitchen_print_dispatches: the supersession target is itself superseded',
  '28 R13 INSERT path: a row born pointing at an already-superseded target is rejected');
select lives_ok($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
     values ('e5ed0000-0000-0000-0000-0000000000a0', 'e5ed0000-0000-0000-0000-0000000000a1', 'e5ed0000-0000-0000-0000-0000000000ab',
             'e5ed0000-0000-0000-0000-00000000ad01', 'initial_order', '{"v":1}'::jsonb, 'r13-initial-ok',
             'e5ed0000-0000-0000-0000-0000000dd002')$$,
  '29 R13 control: the same INSERT pointing at the unsuperseded edit2 is accepted');
select throws_ok($$update kitchen_print_dispatches set superseded_by_dispatch_id = null
                    where id = 'e5ed0000-0000-0000-0000-0000000dd001'$$,
  '23514', 'kitchen_print_dispatches: superseded_by_dispatch_id is write-once',
  '30 R13 the pointer is write-once (clearing raises)');

select * from finish();
rollback;
