-- ORDER-EDIT-001A — the PAPER channel of app.edit_order (printer_only branch)
-- and its order_edit kitchen dispatch: the landing matrix's Paper column
-- (API_CONTRACT §4.45.4), the success envelope's kitchen_dispatch (§4.45.5),
-- the dispatch itself, its money-free change-slip payload and the amended
-- supersession guard (§4.45.9; DOMAIN_MODEL §6.4; ORDER_EDIT_DESIGN §7.3, §8).
begin;
set local search_path to extensions, public, pg_catalog;

select plan(62);

-- ===== fixture ==============================================================
-- Org E1: one PRINTER-ONLY branch with order editing ON; two POS devices
-- (d1 = till 1, d3 = till 2); a cashier PIN session on till 1 and a manager
-- PIN session on till 2. Till 1 also holds a device-session token so it can
-- report a dispatch through app.acknowledge_kitchen_print_dispatch.
insert into organizations (id, name, slug, default_currency) values
  ('e1ed0000-0000-0000-0000-0000000000a0', 'Org Edit Paper', 'org-edit-paper-001a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000a0', 'Rest Edit Paper');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, order_edit_enabled) values
  ('e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'Branch Edit Paper', 'printer_only', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e1ed0000-0000-0000-0000-0000000000d1', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'pos'),
  ('e1ed0000-0000-0000-0000-0000000000d3', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e1ed0000-0000-0000-0000-0000000000f1', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-0000000000d1', 'active'),
  ('e1ed0000-0000-0000-0000-0000000000f3', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-0000000000d3', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref) values
  ('e1ed0000-0000-0000-0000-00000000005a', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-0000000000d1', 'e1ed0000-0000-0000-0000-0000000000f1', app.hash_provisioning_secret('tok-e1-pos1')),
  ('e1ed0000-0000-0000-0000-00000000005c', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-0000000000d3', 'e1ed0000-0000-0000-0000-0000000000f3', app.hash_provisioning_secret('tok-e1-pos3'));
insert into app_users (id, email) values
  ('e1ed0000-0000-0000-0000-00000000006a', 'paper-cashier@example.test'),
  ('e1ed0000-0000-0000-0000-00000000006b', 'paper-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e1ed0000-0000-0000-0000-00000000007a', 'e1ed0000-0000-0000-0000-00000000006a', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('e1ed0000-0000-0000-0000-00000000007b', 'e1ed0000-0000-0000-0000-00000000006b', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e1ed0000-0000-0000-0000-00000000008a', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000006a', 'e1ed0000-0000-0000-0000-00000000007a', 'Dana Cashier'),
  ('e1ed0000-0000-0000-0000-00000000008b', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000006b', 'e1ed0000-0000-0000-0000-00000000007b', 'Mona Manager');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e1ed0000-0000-0000-0000-00000000009a', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000005a', 'e1ed0000-0000-0000-0000-00000000008a', 'e1ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('e1ed0000-0000-0000-0000-00000000009b', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000005c', 'e1ed0000-0000-0000-0000-00000000008b', 'e1ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour');

-- Menu: Burger 4000 (Extras: tomato 0, cucumber 0, cheese 300), Fries 1500,
-- Cola 800, Lemonade 900, Water 0.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e1ed0000-0000-0000-0000-0000000000c1', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e1ed0000-0000-0000-0000-000000001001', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('e1ed0000-0000-0000-0000-000000001002', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2),
  ('e1ed0000-0000-0000-0000-000000001003', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 3),
  ('e1ed0000-0000-0000-0000-000000001004', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-0000000000c1', 'Lemonade', 900, 'ILS', 4),
  ('e1ed0000-0000-0000-0000-000000001005', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-0000000000c1', 'Water', 0, 'ILS', 5);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('e1ed0000-0000-0000-0000-00000000d101', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('e1ed0000-0000-0000-0000-00000000e001', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-00000000d101', 'tomato',   0,   1, true),
  ('e1ed0000-0000-0000-0000-00000000e002', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-00000000d101', 'cucumber', 0,   2, true),
  ('e1ed0000-0000-0000-0000-00000000e003', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', null, 'e1ed0000-0000-0000-0000-00000000d101', 'cheese',   300, 3, true);

-- builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire)
create function pg_temp.mk_order(p_id uuid, p_status text default 'submitted') returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at)
  values (p_id, 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
    'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-0000000000d1',
    'e1ed0000-0000-0000-0000-00000000009a', 'e1ed0000-0000-0000-0000-00000000008a',
    'e1ed0000-0000-0000-0000-00000000007a', 'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end);
$$;
create function pg_temp.mk_round(p_id uuid, p_order uuid, p_no int) returns void
language sql as $$
  insert into order_service_rounds (id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id)
  values (p_id, 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
    'e1ed0000-0000-0000-0000-0000000000ab', p_order, p_no, 'submitted',
    'e1ed0000-0000-0000-0000-0000000000d1', 'e1ed0000-0000-0000-0000-00000000008a');
$$;
-- a kitchen dispatch exactly as submit_order (initial) / add-items (round) creates it
create function pg_temp.mk_dispatch(p_order uuid, p_round uuid default null) returns void
language sql as $$
  select app.create_kitchen_dispatch(
    'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab',
    p_order, p_round, case when p_round is null then 'initial_order' else 'service_round' end,
    case when p_round is null
         then app.kitchen_dispatch_payload_initial('e1ed0000-0000-0000-0000-0000000000a0', p_order)
         else app.kitchen_dispatch_payload_round('e1ed0000-0000-0000-0000-0000000000a0', p_order, p_round) end,
    'e1ed0000-0000-0000-0000-00000000008a', 'e1ed0000-0000-0000-0000-00000000007a', 'e1ed0000-0000-0000-0000-0000000000d1');
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_round uuid default null) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor, service_round_id)
  values (p_id, 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
    'e1ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, p_total, p_round);
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_name text, p_price bigint) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
  values ('e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
    'e1ed0000-0000-0000-0000-0000000000ab', p_item, p_opt, 'Extras', p_name, p_price, 1);
$$;
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- the dispatch id behind an idempotency key
create function pg_temp.kd(p_key text) returns uuid language sql as $$
  select id from kitchen_print_dispatches
   where organization_id = 'e1ed0000-0000-0000-0000-0000000000a0' and idempotency_key = p_key;
$$;
-- the money-free kitchen projection of one line
create function pg_temp.proj(p_item uuid) returns jsonb language sql as $$
  select app.kitchen_dispatch_item_projection('e1ed0000-0000-0000-0000-0000000000a0', p_item);
$$;
-- one order.edit through public.sync_push; returns the op's result
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'e1ed0000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- the order_edit dispatches of an order
create function pg_temp.edit_dispatch_count(p_order uuid) returns bigint language sql as $$
  select count(*) from kitchen_print_dispatches
   where organization_id = 'e1ed0000-0000-0000-0000-0000000000a0'
     and order_id = p_order and dispatch_type = 'order_edit';
$$;
-- the kitchen.dispatch_created order_edit audit rows of an order
create function pg_temp.edit_dispatch_audits(p_order uuid) returns bigint language sql as $$
  select count(*) from audit_events
   where organization_id = 'e1ed0000-0000-0000-0000-0000000000a0'
     and action = 'kitchen.dispatch_created'
     and new_values ->> 'dispatch_type' = 'order_edit'
     and new_values ->> 'order_code' = '#' || upper(right(replace(p_order::text, '-', ''), 6));
$$;

-- Order P1 (#00A001), printer-only, submitted. Original ticket:
--   L1 Burger x1 (+tomato, +cucumber) 4000   -> modify (drop tomato): CHANGE
--   L2 Fries x1 1500                         -> remove
--   L3 Cola x3 2400                          -> reduce to 1
--   L4 Lemonade x1 900                       -> increase to 3
--   L5 Burger x2 (+cucumber) 8000            -> modify: 1 unchanged + 1 (+cheese)
-- Round 2 (an earlier add-items round): L6 Cola x1 800 (untouched).
-- Subtotal 17600; after the edit (+ one Water 0) 16600.
select pg_temp.mk_order('e1ed0000-0000-0000-0000-00000000a001');
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a1001', 'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.mk_mod('e1ed0000-0000-0000-0000-0000000a1001', 'e1ed0000-0000-0000-0000-00000000e001', 'tomato', 0);
select pg_temp.mk_mod('e1ed0000-0000-0000-0000-0000000a1001', 'e1ed0000-0000-0000-0000-00000000e002', 'cucumber', 0);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a1002', 'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a1003', 'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-000000001003', 'Cola', 3, 800, 2400);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a1004', 'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a1005', 'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8000);
select pg_temp.mk_mod('e1ed0000-0000-0000-0000-0000000a1005', 'e1ed0000-0000-0000-0000-00000000e002', 'cucumber', 0);
select pg_temp.mk_round('e1ed0000-0000-0000-0000-00000000a0e2', 'e1ed0000-0000-0000-0000-00000000a001', 2);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a1006', 'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800, 'e1ed0000-0000-0000-0000-00000000a0e2');
select pg_temp.settle_totals('e1ed0000-0000-0000-0000-00000000a001');

-- The order's kitchen dispatches, created exactly as submit_order / add-items
-- create them: the INITIAL dispatch (left unresolved, unclaimed) and the
-- round-2 dispatch (then COMPLETED by till 1: printed, transport accepted).
select pg_temp.mk_dispatch('e1ed0000-0000-0000-0000-00000000a001');
select pg_temp.mk_dispatch('e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-00000000a0e2');
update kitchen_print_dispatches
   set claimed_at = now() - interval '5 minutes',
       claimed_by_device_id = 'e1ed0000-0000-0000-0000-0000000000d1',
       claim_expires_at = now() + interval '5 minutes',
       completed_at = now() - interval '4 minutes',
       last_client_status = 'transport_accepted'
 where id = pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e2');

select ok((select dispatch_type = 'initial_order' and superseded_by_dispatch_id is null
                  and completed_at is null and claimed_by_device_id is null
             from kitchen_print_dispatches where id = pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001'))
      and (select completed_at is not null and superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e2')),
  '01 fixture: an unresolved initial dispatch and a COMPLETED round-2 dispatch, neither superseded');

-- ===== A. edit 1 on the paper channel (cashier, till 1) ======================
create function pg_temp.e1_payload() returns jsonb language sql as $$
  select '{
    "reason_code": "entry_mistake",
    "expected": {"subtotal_minor": 16600, "tax_total_minor": 0, "grand_total_minor": 16600},
    "changes": [
      {"op": "modify", "order_item_id": "e1ed0000-0000-0000-0000-0000000a1001",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e1ed0000-0000-0000-0000-00000000e002"}]}]},
      {"op": "remove", "order_item_id": "e1ed0000-0000-0000-0000-0000000a1002"},
      {"op": "set_quantity", "order_item_id": "e1ed0000-0000-0000-0000-0000000a1003", "quantity": 1},
      {"op": "set_quantity", "order_item_id": "e1ed0000-0000-0000-0000-0000000a1004", "quantity": 3},
      {"op": "modify", "order_item_id": "e1ed0000-0000-0000-0000-0000000a1005",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e1ed0000-0000-0000-0000-00000000e002"}]},
                        {"quantity": 1, "modifiers": [{"modifier_option_id": "e1ed0000-0000-0000-0000-00000000e002"},
                                                      {"modifier_option_id": "e1ed0000-0000-0000-0000-00000000e003",
                                                       "option_name_snapshot": "cheese", "price_minor_snapshot": 300}]}]},
      {"op": "add", "item": {"menu_item_id": "e1ed0000-0000-0000-0000-000000001005", "quantity": 1,
        "unit_price_minor_snapshot": 0, "menu_item_name_snapshot": "Water", "modifiers": []}}]}'::jsonb;
$$;

create temp table t_e1 as select pg_temp.edit('e1ed0000-0000-0000-0000-00000000009a', 'p1-edit-1',
  'e1ed0000-0000-0000-0000-00000000a001', pg_temp.e1_payload()) as r;
-- the edit's identifiers, captured once
create temp table t_e1i as
  select (r ->> 'order_edit_id')::uuid as edit_id,
         (r ->> 'new_round_id')::uuid as round_id,
         (r -> 'kitchen_dispatch' ->> 'id')::uuid as kd_id,
         r -> 'changes' as ch
    from t_e1;
create temp table t_e1p as
  select money_free_payload as p from kitchen_print_dispatches where id = (select kd_id from t_e1i);

select ok((select r ->> 'status' = 'applied' and (r ->> 'edit_number')::int = 1
                  and r ->> 'kitchen_channel' = 'paper'
                  and not (r ->> 'kitchen_ack_required')::boolean from t_e1),
  '02 edit 1 applied on the PAPER channel, kitchen_ack_required FALSE (no confirmation step on paper)');
select ok((select kitchen_channel = 'paper' and not kitchen_ack_required and kitchen_ack_at is null
                  and edit_number = 1 and reason_code = 'entry_mistake'
                  and device_id = 'e1ed0000-0000-0000-0000-0000000000d1'
             from order_edits where id = (select edit_id from t_e1i)),
  '03 the order_edits row: channel paper, kitchen_ack_required FALSE, no acknowledgement');
select ok((select (r ->> 'new_round_number')::int = 3 from t_e1)
      and (select status = 'submitted' and round_number = 3 and edit_id = (select edit_id from t_e1i)
             from order_service_rounds where id = (select round_id from t_e1i)),
  '04 the edit opened ONE round, numbered after the existing round 2 (new_round_number 3)');
select ok((select subtotal_minor = 16600 and grand_total_minor = 16600 and revision = 2
                  and edit_count = 1 and status = 'submitted'
             from orders where id = 'e1ed0000-0000-0000-0000-00000000a001')
      and (select (r -> 'before' ->> 'grand_total_minor')::bigint = 17600
                  and (r -> 'totals' ->> 'grand_total_minor')::bigint = 16600 from t_e1)
      and (select sum(line_total_minor) = 16600 from order_items
            where order_id = 'e1ed0000-0000-0000-0000-00000000a001' and status not in ('voided', 'cancelled')),
  '05 money: 17600 -> 16600, subtotal = sum of live lines, revision + 1, edit_count 1');
select ok((select status = 'voided' and removed_kitchen_stage = 'printed'
                  and removed_by_edit_id = (select edit_id from t_e1i)
                  and void_reason = 'order_edit:entry_mistake' and line_total_minor = 1500
             from order_items where id = 'e1ed0000-0000-0000-0000-0000000a1002'),
  '06 paper remove: the line is VOIDED with removed_kitchen_stage printed (amount kept)');
select ok((select count(*) = 4 and bool_and(status = 'voided' and removed_kitchen_stage = 'printed'
                                            and removed_by_edit_id = (select edit_id from t_e1i))
             from order_items where order_id = 'e1ed0000-0000-0000-0000-00000000a001' and removed_by_edit_id is not null)
      and not exists (select 1 from order_items where order_id = 'e1ed0000-0000-0000-0000-00000000a001' and status = 'cancelled'),
  '07 every retired line (modify x2, remove, reduce) is voided / printed; nothing is cancelled on paper');
select ok((select count(*) = 1 and bool_and(n.quantity = 1 and n.line_total_minor = 800
                  and n.service_round_id is null and n.line_position = o.line_position
                  and n.edit_id = (select edit_id from t_e1i))
             from order_items n join order_items o on o.id = n.replaces_order_item_id
            where n.replaces_order_item_id = 'e1ed0000-0000-0000-0000-0000000a1003'),
  '08 paper reduce: the remainder (1) is written IN PLACE (original ticket, old line_position)');
select ok((select status = 'pending' and removed_by_edit_id is null and quantity = 1
             from order_items where id = 'e1ed0000-0000-0000-0000-0000000a1004')
      and (select count(*) = 1 and bool_and(quantity = 2 and line_total_minor = 1800
                  and service_round_id = (select round_id from t_e1i) and replaces_order_item_id is null)
             from order_items where order_id = 'e1ed0000-0000-0000-0000-00000000a001'
              and menu_item_name_snapshot = 'Lemonade' and edit_id is not null),
  '09 paper increase: the old line is KEPT and a +2 row lands in the edit''s round (no replaces)');
select ok((select count(*) = 1 and bool_and(n.service_round_id = (select round_id from t_e1i)
                  and n.quantity = 1 and n.line_total_minor = 4000
                  and (select string_agg(m.option_name_snapshot, ',' order by m.option_name_snapshot)
                         from order_item_modifiers m where m.order_item_id = n.id) = 'cucumber')
             from order_items n where n.replaces_order_item_id = 'e1ed0000-0000-0000-0000-0000000a1001'),
  '10 paper modify (changed): the replacement lands in the edit''s round as a CHANGE');
select ok((select count(*) = 1 and bool_and(n.service_round_id is null and n.line_position = o.line_position
                  and n.quantity = 1 and n.line_total_minor = 4000)
             from order_items n join order_items o on o.id = n.replaces_order_item_id
            where n.replaces_order_item_id = 'e1ed0000-0000-0000-0000-0000000a1005'
              and not exists (select 1 from order_item_modifiers m where m.order_item_id = n.id and m.option_name_snapshot = 'cheese'))
      and (select count(*) = 1 and bool_and(n.service_round_id = (select round_id from t_e1i)
                  and n.quantity = 1 and n.line_total_minor = 4300)
             from order_items n
            where n.replaces_order_item_id = 'e1ed0000-0000-0000-0000-0000000a1005'
              and exists (select 1 from order_item_modifiers m where m.order_item_id = n.id and m.option_name_snapshot = 'cheese')),
  '11 paper modify split: the UNCHANGED replacement continues in place, the changed one (+cheese) goes to the edit''s round');
select ok((select count(*) = 1 and bool_and(service_round_id = (select round_id from t_e1i)
                  and replaces_order_item_id is null and edit_id = (select edit_id from t_e1i))
             from order_items where order_id = 'e1ed0000-0000-0000-0000-00000000a001'
              and menu_item_name_snapshot = 'Water'),
  '12 paper add: the new line lands in the edit''s round');
select is((select string_agg(c ->> 'landing', ',' order by o) from t_e1,
                  jsonb_array_elements(r -> 'changes') with ordinality as x(c, o)),
  'edit_round,removed,in_place,edit_round,mixed,edit_round',
  '13 envelope landing summary in request order (modify, remove, reduce, increase, split modify, add)');
select ok((select bool_and(c ->> 'unit_stage' = 'printed' and not (c ->> 'remake')::boolean)
                  and string_agg(c ->> 'outcome_status', ',' order by o) = 'voided,voided,voided,kept,voided,added'
             from t_e1, jsonb_array_elements(r -> 'changes') with ordinality as x(c, o)),
  '14 every change has unit_stage printed and remake FALSE (paper lands a modify as CHANGE)');
select ok((select status = 'pending' and removed_by_edit_id is null
             from order_items where id = 'e1ed0000-0000-0000-0000-0000000a1006')
      and not exists (select 1 from kitchen_print_dispatches
                       where service_round_id = (select round_id from t_e1i)),
  '15 the earlier round is untouched; the edit''s round gets NO dispatch of its own (the change slip covers it)');

-- ===== B. the order_edit dispatch ============================================
select ok((select count(*) = 1 and bool_and(d.id = (select kd_id from t_e1i)
                  and d.order_edit_id = (select edit_id from t_e1i)
                  and d.idempotency_key = 'edit:' || (select edit_id from t_e1i)::text
                  and d.service_round_id is null and d.branch_id = 'e1ed0000-0000-0000-0000-0000000000ab')
             from kitchen_print_dispatches d
            where d.order_id = 'e1ed0000-0000-0000-0000-00000000a001' and d.dispatch_type = 'order_edit'),
  '16 exactly one order_edit dispatch: order_edit_id = the edit, key edit:<order_edit_id>, no round');
select ok((select claimed_by_device_id = 'e1ed0000-0000-0000-0000-0000000000d1'
                  and claimed_at = now() and claim_expires_at = now() + interval '10 minutes'
                  and completed_at is null and last_client_status is null and superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = (select kd_id from t_e1i)),
  '17 born CLAIMED by the acting POS: claimed_at now(), lease now() + 10 minutes, unresolved');
select ok((select (r -> 'kitchen_dispatch' ->> 'id')::uuid = d.id
                  and (r -> 'kitchen_dispatch' ->> 'claim_expires_at')::timestamptz = d.claim_expires_at
                  and (select array_agg(k order by k) from jsonb_object_keys(r -> 'kitchen_dispatch') k)
                      = array['claim_expires_at', 'id']
             from t_e1, kitchen_print_dispatches d where d.id = (select kd_id from t_e1i)),
  '18 envelope kitchen_dispatch {id, claim_expires_at} matches the row');
select is((select superseded_by_dispatch_id from kitchen_print_dispatches
            where id = pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001')),
  (select kd_id from t_e1i),
  '19 the order''s unresolved INITIAL dispatch is now superseded by the order_edit dispatch');
select ok((select superseded_by_dispatch_id is null and completed_at is not null
                  and last_client_status = 'transport_accepted'
             from kitchen_print_dispatches where id = pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e2')),
  '20 a COMPLETED earlier dispatch is NOT superseded (completed history stays unlinked)');
select ok(pg_temp.edit_dispatch_audits('e1ed0000-0000-0000-0000-00000000a001') = 1
      and (select actor_employee_profile_id = 'e1ed0000-0000-0000-0000-00000000008a'
                  and device_id = 'e1ed0000-0000-0000-0000-0000000000d1'
                  and new_values ->> 'order_code' = '#00A001'
             from audit_events
            where organization_id = 'e1ed0000-0000-0000-0000-0000000000a0'
              and action = 'kitchen.dispatch_created' and new_values ->> 'dispatch_type' = 'order_edit'),
  '21 one kitchen.dispatch_created audit {dispatch_type: order_edit, order_code} by the acting cashier and POS');
select is((select app.audit_safe_detail(action, new_values) from audit_events
            where organization_id = 'e1ed0000-0000-0000-0000-0000000000a0'
              and action = 'kitchen.dispatch_created' and new_values ->> 'dispatch_type' = 'order_edit'),
  '{"dispatch_type": "order_edit", "order_code": "#00A001"}'::jsonb,
  '22 app.audit_safe_detail of that row keeps ONLY dispatch_type and order_code');

-- ===== C. the money-free change-slip payload =================================
select ok((select p ->> 'kind' = 'order_edit' and (p ->> 'v')::int = 1
                  and (p ->> 'edit_number')::int = 1 and p ->> 'reason_code' = 'entry_mistake'
                  and p ->> 'order_code' = '#00A001' and p ->> 'order_type' = 'dine_in'
                  and p ->> 'staff_name' = 'Dana'
                  and (p ->> 'created_at')::timestamptz = (select created_at from order_edits where id = (select edit_id from t_e1i))
             from t_e1p),
  '23 payload header: kind order_edit, edit_number 1, reason_code, order_code, staff first name, the edit''s time');
select is((select jsonb_path_query_array(p, '$.edit_lines[*].op') from t_e1p),
  '["modify", "remove", "set_quantity", "set_quantity", "modify", "add"]'::jsonb,
  '24 edit_lines follow the REQUEST order, op = the change kind');
select is((select p -> 'edit_lines' from t_e1p),
  (select jsonb_build_array(
     jsonb_build_object('op', 'modify', 'was', pg_temp.proj('e1ed0000-0000-0000-0000-0000000a1001'),
                        'now', jsonb_build_array(pg_temp.proj((ch -> 0 -> 'new_order_item_ids' ->> 0)::uuid))),
     jsonb_build_object('op', 'remove', 'was', pg_temp.proj('e1ed0000-0000-0000-0000-0000000a1002')),
     jsonb_build_object('op', 'set_quantity', 'was', pg_temp.proj('e1ed0000-0000-0000-0000-0000000a1003'), 'now_qty', 1),
     jsonb_build_object('op', 'set_quantity', 'was', pg_temp.proj('e1ed0000-0000-0000-0000-0000000a1004'), 'now_qty', 3),
     jsonb_build_object('op', 'modify', 'was', pg_temp.proj('e1ed0000-0000-0000-0000-0000000a1005'),
                        'now', jsonb_build_array(pg_temp.proj((ch -> 4 -> 'new_order_item_ids' ->> 0)::uuid),
                                                 pg_temp.proj((ch -> 4 -> 'new_order_item_ids' ->> 1)::uuid))),
     jsonb_build_object('op', 'add',
                        'now', jsonb_build_array(pg_temp.proj((ch -> 5 -> 'new_order_item_ids' ->> 0)::uuid))))
     from t_e1i),
  '25 edit_lines: {op, was, now_qty | now} built from the retired lines and the new rows');
select ok((select jsonb_path_query_array(p, '$.edit_lines[0].was.modifiers[*].name') = '["tomato", "cucumber"]'::jsonb
                  and jsonb_path_query_array(p, '$.edit_lines[0].now[*].modifiers[*].name') = '["cucumber"]'::jsonb
                  and jsonb_path_query_array(p, '$.edit_lines[2].was.qty') = '[3]'::jsonb
                  and not (p -> 'edit_lines' -> 1 ? 'now') and not (p -> 'edit_lines' -> 1 ? 'now_qty')
                  and not (p -> 'edit_lines' -> 2 ? 'now') and not (p -> 'edit_lines' -> 3 ? 'now')
                  and jsonb_path_query_array(p, '$.edit_lines[4].now[*].qty') = '[1, 1]'::jsonb
                  and jsonb_path_query_array(p, '$.edit_lines[4].now[1].modifiers[*].name') = '["cucumber", "cheese"]'::jsonb
                  and not (p -> 'edit_lines' -> 5 ? 'was')
                  and jsonb_path_query_array(p, '$.edit_lines[5].now[*].name') = '["Water"]'::jsonb
             from t_e1p),
  '26 the slip reads was -> now: Burger tomato+cucumber -> cucumber; Cola 3 -> 1; Burger x2 -> 1 + 1 (+cheese); + Water');
select is((select p -> 'order_now' from t_e1p),
  (select jsonb_agg(pg_temp.proj(oi.id)
            order by coalesce(oi.category_display_order_snapshot, 0), coalesce(oi.item_display_order_snapshot, 0),
                     coalesce(oi.line_position, 0), oi.created_at, oi.id)
     from order_items oi
    where oi.order_id = 'e1ed0000-0000-0000-0000-00000000a001'
      and oi.deleted_at is null and oi.status not in ('voided', 'cancelled')),
  '27 order_now = EVERY live line of the order (round lines included), canonical menu order');
select ok((select string_agg((e ->> 'name') || 'x' || (e ->> 'qty'), ',' order by e ->> 'name', (e ->> 'qty')::int)
                  = 'Burgerx1,Burgerx1,Burgerx1,Colax1,Colax1,Lemonadex1,Lemonadex2,Waterx1'
             from t_e1p, jsonb_array_elements(p -> 'order_now') e)
      and not exists (select 1 from t_e1p, jsonb_path_query(p, '$.order_now[*].modifiers[*].name') n
                       where n = '"tomato"'::jsonb),
  '28 order_now holds no voided / cancelled line (no Fries, no tomato burger, no Cola x3)');
select ok((select app.kitchen_payload_offending_key(p) is null from t_e1p),
  '29 app.kitchen_payload_offending_key(payload) IS NULL (money-free under the ledger guard)');
select ok((select count(*) = 0
             from t_e1p, jsonb_path_query(p, '$.**') v,
                  jsonb_object_keys(case when jsonb_typeof(v) = 'object' then v else '{}'::jsonb end) k
            where k ~* '(minor|price|total|amount|discount|tax|payment)'),
  '30 no key at any nesting level is a money key (*_minor / price / total / amount / discount / tax)');

-- ===== D. replay: the same edit, the same dispatch ===========================
create temp table t_e1r as select pg_temp.edit('e1ed0000-0000-0000-0000-00000000009a', 'p1-edit-1',
  'e1ed0000-0000-0000-0000-00000000a001', pg_temp.e1_payload()) as r;
select ok((select (b.r ->> 'idempotency_replay')::boolean
                  and b.r ->> 'order_edit_id' = a.r ->> 'order_edit_id'
                  and b.r -> 'kitchen_dispatch' ->> 'id' = a.r -> 'kitchen_dispatch' ->> 'id'
                  and b.r -> 'kitchen_dispatch' ->> 'claim_expires_at' = a.r -> 'kitchen_dispatch' ->> 'claim_expires_at'
             from t_e1 a, t_e1r b),
  '31 an exact replay through sync_push returns the SAME order_edit_id and kitchen_dispatch');
select ok(pg_temp.edit_dispatch_count('e1ed0000-0000-0000-0000-00000000a001') = 1
      and pg_temp.edit_dispatch_audits('e1ed0000-0000-0000-0000-00000000a001') = 1
      and (select count(*) = 1 from order_edits where order_id = 'e1ed0000-0000-0000-0000-00000000a001')
      and (select revision = 2 and edit_count = 1 from orders where id = 'e1ed0000-0000-0000-0000-00000000a001'),
  '32 the replay created no second dispatch, no second audit, no second edit');
create temp table t_e1b as select app.edit_order('e1ed0000-0000-0000-0000-00000000009a',
  'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-0000000000d1', 'p1-edit-1',
  pg_temp.e1_payload() || '{"order_id": "e1ed0000-0000-0000-0000-00000000a001"}'::jsonb) as r;
select ok((select (b.r ->> 'idempotency_replay')::boolean
                  and b.r -> 'kitchen_dispatch' = a.r -> 'kitchen_dispatch'
                  and (b.r ->> 'edit_number')::int = 1
             from t_e1 a, t_e1b b)
      and pg_temp.edit_dispatch_count('e1ed0000-0000-0000-0000-00000000a001') = 1,
  '33 the business replay (order_edits key) returns the stored envelope with the same kitchen_dispatch');
create temp table t_e1c as select app.create_order_edit_dispatch(
  'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab',
  'e1ed0000-0000-0000-0000-00000000a001', (select edit_id from t_e1i), (select p from t_e1p),
  'e1ed0000-0000-0000-0000-00000000008b', 'e1ed0000-0000-0000-0000-00000000007b', 'e1ed0000-0000-0000-0000-0000000000d3') as r;
select ok((select (r ->> 'id')::uuid = (select kd_id from t_e1i) from t_e1c)
      and (select claimed_by_device_id = 'e1ed0000-0000-0000-0000-0000000000d1'
             from kitchen_print_dispatches where id = (select kd_id from t_e1i))
      and pg_temp.edit_dispatch_count('e1ed0000-0000-0000-0000-00000000a001') = 1
      and pg_temp.edit_dispatch_audits('e1ed0000-0000-0000-0000-00000000a001') = 1,
  '34 the creator is idempotent on edit:<id>: a retry (even from another till) returns the row, never re-claims or re-audits');

-- ===== E. a SECOND edit (manager, till 2) supersedes the first edit's dispatch
create temp table t_e2 as select pg_temp.edit('e1ed0000-0000-0000-0000-00000000009b', 'p1-edit-2',
  'e1ed0000-0000-0000-0000-00000000a001', '{
    "expected": {"subtotal_minor": 17400, "tax_total_minor": 0, "grand_total_minor": 17400},
    "changes": [{"op": "add", "item": {"menu_item_id": "e1ed0000-0000-0000-0000-000000001003", "quantity": 1,
      "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola"}}]}'::jsonb,
  'e1ed0000-0000-0000-0000-0000000000d3') as r;
create temp table t_e2i as
  select (r ->> 'order_edit_id')::uuid as edit_id, (r -> 'kitchen_dispatch' ->> 'id')::uuid as kd_id from t_e2;

select ok((select r ->> 'status' = 'applied' and (r ->> 'edit_number')::int = 2 and r ->> 'kitchen_channel' = 'paper'
                  and (r -> 'kitchen_dispatch' ->> 'id')::uuid <> (select kd_id from t_e1i) from t_e2)
      and pg_temp.edit_dispatch_count('e1ed0000-0000-0000-0000-00000000a001') = 2,
  '35 edit 2 applied on paper with its OWN order_edit dispatch');
select ok((select order_edit_id = (select edit_id from t_e2i)
                  and idempotency_key = 'edit:' || (select edit_id from t_e2i)::text
                  and claimed_by_device_id = 'e1ed0000-0000-0000-0000-0000000000d3'
                  and claimed_at = now() and claim_expires_at = now() + interval '10 minutes'
                  and superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = (select kd_id from t_e2i)),
  '36 edit 2''s dispatch is claimed by ITS acting POS (till 2) and unsuperseded');
select is((select superseded_by_dispatch_id from kitchen_print_dispatches where id = (select kd_id from t_e1i)),
  (select kd_id from t_e2i),
  '37 edit 1''s still-unresolved dispatch is superseded by edit 2''s');
select ok((select superseded_by_dispatch_id = (select kd_id from t_e1i)
             from kitchen_print_dispatches where id = pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001'))
      and (select superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e2')),
  '38 the chain initial -> edit1 -> edit2: the initial row is NOT re-pointed; the completed round row stays unlinked');
select ok((select (p ->> 'edit_number')::int = 2 and p ->> 'staff_name' = 'Mona'
                  and p -> 'edit_lines' = jsonb_build_array(jsonb_build_object('op', 'add',
                        'now', jsonb_build_array(pg_temp.proj((r -> 'changes' -> 0 -> 'new_order_item_ids' ->> 0)::uuid))))
                  and jsonb_array_length(p -> 'order_now') = 9
                  and not (p ? 'reason_code')
             from t_e2, (select money_free_payload as p from kitchen_print_dispatches where id = (select kd_id from t_e2i)) x),
  '39 edit 2''s slip: edit_number 2, staff Mona, one ADD line, ORDER NOW = all 9 live lines, no reason');
select ok(pg_temp.edit_dispatch_audits('e1ed0000-0000-0000-0000-00000000a001') = 2
      and (select count(*) = 1 from audit_events
            where organization_id = 'e1ed0000-0000-0000-0000-0000000000a0'
              and action = 'kitchen.dispatch_created' and new_values ->> 'dispatch_type' = 'order_edit'
              and device_id = 'e1ed0000-0000-0000-0000-0000000000d3'
              and actor_employee_profile_id = 'e1ed0000-0000-0000-0000-00000000008b'),
  '40 edit 2''s dispatch is audited once, by the manager on till 2');

-- ===== F. the amended guard: write-once pointer, target shape ===============
-- (each probe is isolated so that exactly one guard rule can fire)
select throws_ok(format($$update kitchen_print_dispatches set superseded_by_dispatch_id = %L where id = %L$$,
                        (select kd_id from t_e2i), pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001')),
  '23514', null, '41 re-pointing an already-set pointer (initial -> edit2, a valid target) RAISES 23514 (write-once)');
select throws_ok(format($$update kitchen_print_dispatches set superseded_by_dispatch_id = null where id = %L$$,
                        pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001')),
  '23514', null, '42 clearing an already-set pointer RAISES 23514 (write-once)');
select throws_ok(format($$update kitchen_print_dispatches set superseded_by_dispatch_id = %L where id = %L$$,
                        (select kd_id from t_e1i), pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e2')),
  '23514', null, '43 pointing an unsuperseded row at an order_edit target that is ITSELF superseded RAISES 23514');

-- ===== G. a void after the edits supersedes the unresolved edit dispatch =====
create temp table t_v as select app.void_order('e1ed0000-0000-0000-0000-00000000009b',
  'e1ed0000-0000-0000-0000-00000000a001', 'e1ed0000-0000-0000-0000-0000000000d3', 'p1-void-1', 'customer left') as r;
select ok((select (r ->> 'ok')::boolean from t_v)
      and (select count(*) = 1 from kitchen_print_dispatches
            where order_id = 'e1ed0000-0000-0000-0000-00000000a001' and dispatch_type = 'void'
              and idempotency_key = 'void:e1ed0000-0000-0000-0000-00000000a001' and superseded_by_dispatch_id is null),
  '44 void_order on the printer-only order creates ONE unsuperseded VOID dispatch');
select is((select superseded_by_dispatch_id from kitchen_print_dispatches where id = (select kd_id from t_e2i)),
  pg_temp.kd('void:e1ed0000-0000-0000-0000-00000000a001'),
  '45 the void supersedes the unresolved edit-2 dispatch');
select ok((select superseded_by_dispatch_id = (select kd_id from t_e1i)
             from kitchen_print_dispatches where id = pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001'))
      and (select superseded_by_dispatch_id = (select kd_id from t_e2i)
             from kitchen_print_dispatches where id = (select kd_id from t_e1i))
      and (select superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e2'))
      and (select count(*) = 1 from kitchen_print_dispatches
            where superseded_by_dispatch_id = pg_temp.kd('void:e1ed0000-0000-0000-0000-00000000a001')),
  '46 chain initial -> edit1 -> edit2 -> void: no earlier pointer re-pointed, only edit 2 points at the void');
select lives_ok(format($$update kitchen_print_dispatches
                            set last_client_status = 'transport_accepted', completed_at = now(), updated_at = now()
                          where id = %L$$, pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001')),
  '47 a later status/report UPDATE of the superseded initial row (target since superseded twice) does NOT raise');
select ok((select superseded_by_dispatch_id = (select kd_id from t_e1i) and completed_at = now()
                  and last_client_status = 'transport_accepted'
             from kitchen_print_dispatches where id = pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a001')),
  '48 that update kept the pointer and recorded the report');
create temp table t_ack as select app.acknowledge_kitchen_print_dispatch(
  'e1ed0000-0000-0000-0000-0000000000d1', 'tok-e1-pos1', (select kd_id from t_e1i), 'transport_accepted') as r;
select ok((select (r ->> 'ok')::boolean and (r ->> 'completed')::boolean from t_ack)
      and (select completed_at is not null and last_client_status = 'transport_accepted'
                  and superseded_by_dispatch_id = (select kd_id from t_e2i)
             from kitchen_print_dispatches where id = (select kd_id from t_e1i)),
  '49 the acting POS still acknowledges edit 1''s superseded dispatch (report RPC; target since superseded)');
select throws_ok(format($$update kitchen_print_dispatches set superseded_by_dispatch_id = %L where id = %L$$,
                        pg_temp.kd('void:e1ed0000-0000-0000-0000-00000000a001'), (select kd_id from t_e1i)),
  '23514', null, '50 after the report, edit 1''s pointer is still write-once (re-point to the unsuperseded void RAISES 23514)');
create temp table t_ack2 as select app.acknowledge_kitchen_print_dispatch(
  'e1ed0000-0000-0000-0000-0000000000d1', 'tok-e1-pos1', (select kd_id from t_e2i), 'transport_accepted') as r;
select ok((select r ->> 'error' = 'not_claim_owner' from t_ack2)
      and (select completed_at is null and last_client_status is null
                  and claimed_by_device_id = 'e1ed0000-0000-0000-0000-0000000000d3'
             from kitchen_print_dispatches where id = (select kd_id from t_e2i)),
  '51 another till cannot report edit 2''s dispatch: only its claim holder (till 2) may (not_claim_owner)');

-- ===== H. order P2: served food on paper, an unresolved round dispatch =====
-- P2 (#00A002), printer-only, SERVED: Cola x2 + Fries x1 on the original
-- ticket, Lemonade x1 in round 2. Both its initial and its round-2 dispatch
-- are unresolved. With "Only managers may remove food that is Ready or
-- Served" ON, a CASHIER removes the served Fries: on paper the switch has no
-- effect (§4.45.2 step 7). E = the edit's dispatch, left unsuperseded.
select pg_temp.mk_order('e1ed0000-0000-0000-0000-00000000a002', 'served');
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a2001', 'e1ed0000-0000-0000-0000-00000000a002', 'e1ed0000-0000-0000-0000-000000001003', 'Cola', 2, 800, 1600);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a2002', 'e1ed0000-0000-0000-0000-00000000a002', 'e1ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_round('e1ed0000-0000-0000-0000-00000000a0e3', 'e1ed0000-0000-0000-0000-00000000a002', 2);
select pg_temp.mk_item('e1ed0000-0000-0000-0000-0000000a2003', 'e1ed0000-0000-0000-0000-00000000a002', 'e1ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900, 'e1ed0000-0000-0000-0000-00000000a0e3');
select pg_temp.settle_totals('e1ed0000-0000-0000-0000-00000000a002');
select pg_temp.mk_dispatch('e1ed0000-0000-0000-0000-00000000a002');
select pg_temp.mk_dispatch('e1ed0000-0000-0000-0000-00000000a002', 'e1ed0000-0000-0000-0000-00000000a0e3');
update branches set order_edit_finished_food_manager_only = true where id = 'e1ed0000-0000-0000-0000-0000000000ab';
create temp table t_p2 as select pg_temp.edit('e1ed0000-0000-0000-0000-00000000009a', 'p2-edit-1',
  'e1ed0000-0000-0000-0000-00000000a002', '{
    "reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 2500, "tax_total_minor": 0, "grand_total_minor": 2500},
    "changes": [{"op": "remove", "order_item_id": "e1ed0000-0000-0000-0000-0000000a2002"}]}'::jsonb) as r;
update branches set order_edit_finished_food_manager_only = false where id = 'e1ed0000-0000-0000-0000-0000000000ab';
create temp table t_p2i as
  select (r ->> 'order_edit_id')::uuid as edit_id, (r -> 'kitchen_dispatch' ->> 'id')::uuid as kd_id from t_p2;
-- probe rows (inserted AFTER the edit so the edit does not supersede them):
--   b0001 initial_order, unsuperseded (an initial TARGET candidate)
--   b0002 initial_order, unsuperseded (a SOURCE for the UPDATE path)
--   b0003 void, unsuperseded
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id,
  dispatch_type, money_free_payload, idempotency_key) values
  ('e1ed0000-0000-0000-0000-0000000b0001', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
   'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002', 'initial_order', '{"v": 1}', 'probe:b0001'),
  ('e1ed0000-0000-0000-0000-0000000b0002', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
   'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002', 'initial_order', '{"v": 1}', 'probe:b0002'),
  ('e1ed0000-0000-0000-0000-0000000b0003', 'e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
   'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002', 'void', '{"v": 1}', 'probe:b0003');

select ok((select r ->> 'status' = 'applied' and r ->> 'kitchen_channel' = 'paper'
                  and not (r ->> 'kitchen_ack_required')::boolean from t_p2)
      and (select status = 'voided' and removed_kitchen_stage = 'printed'
             from order_items where id = 'e1ed0000-0000-0000-0000-0000000a2002'),
  '52 P2: on paper the finished-food switch has no effect: a cashier removes served food (voided, printed)');
select ok((select superseded_by_dispatch_id = (select kd_id from t_p2i)
             from kitchen_print_dispatches where id = pg_temp.kd('initial:e1ed0000-0000-0000-0000-00000000a002'))
      and (select superseded_by_dispatch_id = (select kd_id from t_p2i)
             from kitchen_print_dispatches where id = pg_temp.kd('round:e1ed0000-0000-0000-0000-00000000a0e3'))
      and (select claimed_by_device_id = 'e1ed0000-0000-0000-0000-0000000000d1' and superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = (select kd_id from t_p2i)),
  '53 P2: the order_edit dispatch supersedes BOTH the unresolved initial and the unresolved service_round dispatch');
select lives_ok(format($$update kitchen_print_dispatches set superseded_by_dispatch_id = %L
                          where id = 'e1ed0000-0000-0000-0000-0000000b0002'$$, (select kd_id from t_p2i)),
  '54 an initial row may be superseded by an unsuperseded order_edit target (UPDATE, NULL -> value)');
select lives_ok(format($$insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id,
                            dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
                          values ('e1ed0000-0000-0000-0000-0000000b0004', 'e1ed0000-0000-0000-0000-0000000000a0',
                            'e1ed0000-0000-0000-0000-0000000000a1', 'e1ed0000-0000-0000-0000-0000000000ab',
                            'e1ed0000-0000-0000-0000-00000000a002', 'initial_order', '{"v": 1}', 'probe:b0004', %L)$$,
                        (select kd_id from t_p2i)),
  '55 an initial row may be inserted already superseded by an order_edit target (INSERT path)');
select throws_ok(format($$update kitchen_print_dispatches set superseded_by_dispatch_id = %L
                           where id = 'e1ed0000-0000-0000-0000-0000000b0003'$$, (select kd_id from t_p2i)),
  '23514', null, '56 a VOID row can never be superseded, even by a valid order_edit target (23514)');
select throws_ok($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id,
                     dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
                   values ('e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
                     'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002',
                     'initial_order', '{"v": 1}', 'probe:b0005', 'e1ed0000-0000-0000-0000-0000000b0001')$$,
  '23514', null, '57 a target of type initial_order (unsuperseded) is still rejected (23514)');
select ok((select superseded_by_dispatch_id = (select kd_id from t_p2i)
             from kitchen_print_dispatches where id = 'e1ed0000-0000-0000-0000-0000000b0002')
      and (select superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = 'e1ed0000-0000-0000-0000-0000000b0003')
      and (select superseded_by_dispatch_id is null
             from kitchen_print_dispatches where id = (select kd_id from t_p2i)),
  '58 the lab rows: the UPDATE probe points at E, the void and E stay unsuperseded');

-- ===== I. CHECK kitchen_print_dispatches_order_edit_type + composite FK =======
select throws_ok($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id,
                     dispatch_type, money_free_payload, idempotency_key)
                   values ('e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
                     'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002',
                     'order_edit', '{"v": 1}', 'probe:c0001')$$,
  '23514', 'new row for relation "kitchen_print_dispatches" violates check constraint "kitchen_print_dispatches_order_edit_type"',
  '59 an order_edit dispatch WITHOUT order_edit_id RAISES 23514 (kitchen_print_dispatches_order_edit_type)');
select throws_ok(format($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id,
                            dispatch_type, order_edit_id, money_free_payload, idempotency_key)
                          values ('e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
                            'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002',
                            'initial_order', %L, '{"v": 1}', 'probe:c0002')$$, (select edit_id from t_p2i)),
  '23514', 'new row for relation "kitchen_print_dispatches" violates check constraint "kitchen_print_dispatches_order_edit_type"',
  '60 an initial_order dispatch WITH an order_edit_id (of its own order) RAISES 23514');
select throws_ok(format($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id,
                            dispatch_type, order_edit_id, money_free_payload, idempotency_key)
                          values ('e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
                            'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002',
                            'order_edit', %L, '{"v": 1}', 'probe:c0003')$$, (select edit_id from t_e1i)),
  '23503', 'insert or update on table "kitchen_print_dispatches" violates foreign key constraint "kitchen_print_dispatches_order_edit_fkey"',
  '61 an order_edit dispatch pointing at an edit of ANOTHER order RAISES 23503 (composite FK)');
select lives_ok(format($$insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id,
                           dispatch_type, order_edit_id, money_free_payload, idempotency_key)
                         values ('e1ed0000-0000-0000-0000-0000000000a0', 'e1ed0000-0000-0000-0000-0000000000a1',
                           'e1ed0000-0000-0000-0000-0000000000ab', 'e1ed0000-0000-0000-0000-00000000a002',
                           'order_edit', %L, '{"v": 1}', 'probe:c0004')$$, (select edit_id from t_p2i)),
  '62 control: an order_edit dispatch with an edit of ITS OWN order is accepted');

select * from finish();
rollback;
