-- ORDER-EDIT-001F — the capture probe behind apps/pos/test/fixtures/order_edit_slip/*.json.
--
-- Runs REAL paper edits (app.edit_order through public.sync_push) on a local
-- PostgreSQL build of supabase/migrations and prints one JSON object
-- {case: {payload, envelope, before, after, dispatch, staff_display_name}}:
-- before/after are app.pos_order_detail, envelope is the sync_push answer and
-- dispatch is the STORED kitchen_print_dispatches.money_free_payload. Every
-- write is rolled back. Usage (as a superuser, on a disposable database):
--
--   psql -X -q -v ON_ERROR_STOP=1 -t -A -d <db> -f capture_probe.sql
--
-- then split the object into one <case>.json file per key. Fictional people.
begin;
set local search_path to extensions, public, pg_catalog;

insert into organizations (id, name, slug, default_currency) values
  ('fed00000-0000-0000-0000-0000000000a0', 'Org Slip Parity', 'org-slip-parity-001f', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000a0', 'Rest Slip Parity');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, order_edit_enabled) values
  ('fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'Branch Slip Parity', 'printer_only', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('fed00000-0000-0000-0000-0000000000d1', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('fed00000-0000-0000-0000-0000000000f1', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('fed00000-0000-0000-0000-00000000005a', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-0000000000d1', 'fed00000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('fed00000-0000-0000-0000-00000000006a', 'slip-cashier@example.test'),
  ('fed00000-0000-0000-0000-00000000006b', 'slip-manager@example.test'),
  ('fed00000-0000-0000-0000-00000000006c', 'slip-arabic@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('fed00000-0000-0000-0000-00000000007a', 'fed00000-0000-0000-0000-00000000006a', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('fed00000-0000-0000-0000-00000000007b', 'fed00000-0000-0000-0000-00000000006b', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('fed00000-0000-0000-0000-00000000007c', 'fed00000-0000-0000-0000-00000000006c', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb);
-- Staff display names: a plain two-word name, a first token LONGER than 40
-- characters, and an Arabic name.
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('fed00000-0000-0000-0000-00000000008a', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-00000000006a', 'fed00000-0000-0000-0000-00000000007a', 'Dana Cashier'),
  ('fed00000-0000-0000-0000-00000000008b', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-00000000006b', 'fed00000-0000-0000-0000-00000000007b', 'Bartholomew-Alexander-Maximilian-Fitzgerald Jones'),
  ('fed00000-0000-0000-0000-00000000008c', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-00000000006c', 'fed00000-0000-0000-0000-00000000007c', 'سارة أحمد');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('fed00000-0000-0000-0000-00000000009a', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-00000000005a', 'fed00000-0000-0000-0000-00000000008a', 'fed00000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('fed00000-0000-0000-0000-00000000009b', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-00000000005a', 'fed00000-0000-0000-0000-00000000008b', 'fed00000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('fed00000-0000-0000-0000-00000000009c', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-00000000005a', 'fed00000-0000-0000-0000-00000000008c', 'fed00000-0000-0000-0000-00000000007c', now() + interval '1 hour');
insert into tables (id, organization_id, restaurant_id, branch_id, label, status) values
  ('fed00000-0000-0000-0000-0000000000b1', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab', 'T4', 'available');

-- Menu: two categories (Drinks rank 2 before Mains rank 5 is deliberately
-- NOT alphabetical). Burger 4000 (Extras: tomato 0, cucumber 0, cheese 300),
-- Fries 1500, Cola 800, Lemonade 900, Water 0.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('fed00000-0000-0000-0000-0000000000c1', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'Mains', 5),
  ('fed00000-0000-0000-0000-0000000000c2', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'Drinks', 2);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('fed00000-0000-0000-0000-000000001001', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('fed00000-0000-0000-0000-000000001002', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2),
  ('fed00000-0000-0000-0000-000000001003', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-0000000000c2', 'Cola', 800, 'ILS', 2),
  ('fed00000-0000-0000-0000-000000001004', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-0000000000c2', 'Lemonade', 900, 'ILS', 1),
  ('fed00000-0000-0000-0000-000000001005', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-0000000000c2', 'Water', 0, 'ILS', 3);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('fed00000-0000-0000-0000-00000000d101', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('fed00000-0000-0000-0000-00000000e001', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-00000000d101', 'tomato',   0,   1, true),
  ('fed00000-0000-0000-0000-00000000e002', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-00000000d101', 'cucumber', 0,   2, true),
  ('fed00000-0000-0000-0000-00000000e003', 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', null, 'fed00000-0000-0000-0000-00000000d101', 'cheese',   300, 3, true);

create function pg_temp.mk_order(p_id uuid, p_type text, p_table uuid, p_customer text, p_notes text) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, table_id, customer_name, notes,
    currency_code, subtotal_minor, grand_total_minor, local_operation_id, status)
  values (p_id, 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1',
    'fed00000-0000-0000-0000-0000000000ab', 'fed00000-0000-0000-0000-0000000000d1',
    'fed00000-0000-0000-0000-00000000009a', 'fed00000-0000-0000-0000-00000000008a',
    'fed00000-0000-0000-0000-00000000007a', p_type, p_table, p_customer, p_notes,
    'ILS', 0, 0, 'submit-' || p_id::text, 'submitted');
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_notes text default null, p_prep jsonb default null) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor, notes, prep_snapshot)
  values (p_id, 'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1',
    'fed00000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, p_qty * p_unit,
    p_notes, p_prep);
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_name text, p_price bigint,
  p_qty int default 1, p_meat jsonb default null) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
  values ('fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1',
    'fed00000-0000-0000-0000-0000000000ab', p_item, p_opt, 'Extras', p_name, p_price, p_qty, p_meat);
  update order_items oi set line_total_minor = oi.quantity * (oi.unit_price_minor_snapshot
      + (select coalesce(sum(m.price_minor_snapshot * m.quantity), 0) from order_item_modifiers m where m.order_item_id = oi.id))
   where oi.id = p_item;
$$;
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
create function pg_temp.mk_initial_dispatch(p_order uuid) returns void
language sql as $$
  select app.create_kitchen_dispatch(
    'fed00000-0000-0000-0000-0000000000a0', 'fed00000-0000-0000-0000-0000000000a1', 'fed00000-0000-0000-0000-0000000000ab',
    p_order, null, 'initial_order',
    app.kitchen_dispatch_payload_initial('fed00000-0000-0000-0000-0000000000a0', p_order),
    'fed00000-0000-0000-0000-00000000008a', 'fed00000-0000-0000-0000-00000000007a', 'fed00000-0000-0000-0000-0000000000d1');
$$;
create function pg_temp.detail(p_pin uuid, p_order uuid) returns jsonb language sql as $$
  select app.pos_order_detail(p_pin, 'fed00000-0000-0000-0000-0000000000d1', p_order);
$$;
create temp table cap (k text primary key, j jsonb);
-- One captured paper edit: the detail before, the payload, the sync_push
-- result row (the envelope), the detail after and the STORED dispatch payload.
create function pg_temp.capture(p_case text, p_pin uuid, p_staff text, p_op text, p_order uuid, p_payload jsonb) returns void
language plpgsql as $$
declare
  v_before jsonb := pg_temp.detail(p_pin, p_order);
  v_payload jsonb := p_payload || jsonb_build_object('order_id', p_order);
  v_env jsonb;
  v_disp jsonb;
begin
  v_env := public.sync_push(p_pin, 'fed00000-0000-0000-0000-0000000000d1', jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', v_payload)));
  if (v_env -> 'results' -> 0 ->> 'status') is distinct from 'applied' then
    raise exception 'capture %: edit not applied: %', p_case, v_env;
  end if;
  select money_free_payload into v_disp from kitchen_print_dispatches
   where id = (v_env -> 'results' -> 0 -> 'kitchen_dispatch' ->> 'id')::uuid;
  insert into cap values (p_case, jsonb_build_object(
    'staff_display_name', p_staff,
    'local_operation_id', p_op,
    'payload', v_payload,
    'envelope', v_env,
    'before', v_before,
    'after', pg_temp.detail(p_pin, p_order),
    'dispatch', v_disp));
end;
$$;

-- ===== case A: dine-in at T4, a customer, every op kind =====================
--   A1 Burger x1 (+tomato x2, +cucumber), note '  no salt  ', prep -> modify ALL
--   A2 Fries x1                                              -> remove
--   A3 Cola x3                                               -> reduce to 1
--   A4 Lemonade x1                                           -> increase to 3
--   A5 Burger x2 (+cucumber with meat), prep                 -> modify just-1 split
--   + Water x1 note 'no ice'                                 -> add
select pg_temp.mk_order('fed00000-0000-0000-0000-00000000a001', 'dine_in', 'fed00000-0000-0000-0000-0000000000b1', '  Noa Levi  ', null);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000a1001', 'fed00000-0000-0000-0000-00000000a001', 'fed00000-0000-0000-0000-000000001001', 'Burger', 1, 4000,
  '  no salt  ', '[{"name": "Bun", "quantity": 1, "unit": "pc"}, {"name": " Patty ", "quantity": 1.5, "unit": "pc"}]'::jsonb);
select pg_temp.mk_mod('fed00000-0000-0000-0000-0000000a1001', 'fed00000-0000-0000-0000-00000000e001', 'tomato', 0, 2);
select pg_temp.mk_mod('fed00000-0000-0000-0000-0000000a1001', 'fed00000-0000-0000-0000-00000000e002', 'cucumber', 0);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000a1002', 'fed00000-0000-0000-0000-00000000a001', 'fed00000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000a1003', 'fed00000-0000-0000-0000-00000000a001', 'fed00000-0000-0000-0000-000000001003', 'Cola', 3, 800);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000a1004', 'fed00000-0000-0000-0000-00000000a001', 'fed00000-0000-0000-0000-000000001004', 'Lemonade', 1, 900);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000a1005', 'fed00000-0000-0000-0000-00000000a001', 'fed00000-0000-0000-0000-000000001001', 'Burger', 2, 4000,
  null, '[{"name": "Bun", "quantity": 1, "unit": "pc"}]'::jsonb);
select pg_temp.mk_mod('fed00000-0000-0000-0000-0000000a1005', 'fed00000-0000-0000-0000-00000000e002', 'cucumber', 0, 1,
  '{"quantity": 1, "unit": "pc"}'::jsonb);
select pg_temp.settle_totals('fed00000-0000-0000-0000-00000000a001');
select pg_temp.mk_initial_dispatch('fed00000-0000-0000-0000-00000000a001');
-- Before: 4000 + 1500 + 2400 + 900 + 8000 = 16800.
-- After: 4000 (modify all) + 800 + 2700 + (4000 + 4300) + 0 = 15800.
select pg_temp.capture('a_every_op', 'fed00000-0000-0000-0000-00000000009a', 'Dana Cashier', 'slip-a-1',
  'fed00000-0000-0000-0000-00000000a001', '{
    "reason_code": "other", "reason_text": "guest asked twice",
    "expected": {"subtotal_minor": 15800, "tax_total_minor": 0, "grand_total_minor": 15800},
    "changes": [
      {"op": "modify", "order_item_id": "fed00000-0000-0000-0000-0000000a1001",
       "replacements": [{"quantity": 1, "notes": "  well done ",
                         "modifiers": [{"modifier_option_id": "fed00000-0000-0000-0000-00000000e002"}]}]},
      {"op": "remove", "order_item_id": "fed00000-0000-0000-0000-0000000a1002"},
      {"op": "set_quantity", "order_item_id": "fed00000-0000-0000-0000-0000000a1003", "quantity": 1},
      {"op": "set_quantity", "order_item_id": "fed00000-0000-0000-0000-0000000a1004", "quantity": 3},
      {"op": "modify", "order_item_id": "fed00000-0000-0000-0000-0000000a1005",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "fed00000-0000-0000-0000-00000000e002"}]},
                        {"quantity": 1, "modifiers": [{"modifier_option_id": "fed00000-0000-0000-0000-00000000e002"},
                                                      {"modifier_option_id": "fed00000-0000-0000-0000-00000000e003",
                                                       "option_name_snapshot": "cheese", "price_minor_snapshot": 300}]}]},
      {"op": "add", "item": {"menu_item_id": "fed00000-0000-0000-0000-000000001005", "quantity": 1,
        "unit_price_minor_snapshot": 0, "menu_item_name_snapshot": "Water", "notes": "no ice", "modifiers": []}}]}'::jsonb);

-- ===== case A2: a SECOND edit of the same order (Change 2), another worker ===
-- Removes the added Water and raises the Cola remainder 1 -> 2; reason code
-- entry_mistake; the staff first token is longer than 40 characters.
select pg_temp.capture('a_second_edit', 'fed00000-0000-0000-0000-00000000009b',
  'Bartholomew-Alexander-Maximilian-Fitzgerald Jones', 'slip-a-2',
  'fed00000-0000-0000-0000-00000000a001',
  jsonb_build_object(
    'reason_code', 'entry_mistake',
    'expected', jsonb_build_object('subtotal_minor', 16600, 'tax_total_minor', 0, 'grand_total_minor', 16600),
    'changes', jsonb_build_array(
      jsonb_build_object('op', 'remove', 'order_item_id',
        (select id from order_items where order_id = 'fed00000-0000-0000-0000-00000000a001'
            and menu_item_name_snapshot = 'Water' and status not in ('voided', 'cancelled'))),
      jsonb_build_object('op', 'set_quantity', 'quantity', 2, 'order_item_id',
        (select id from order_items where order_id = 'fed00000-0000-0000-0000-00000000a001'
            and replaces_order_item_id = 'fed00000-0000-0000-0000-0000000a1003')))));

-- ===== case B: takeaway, legacy rank-0 lines, Arabic staff, add only =======
-- B1 Fries x2 and B2 Cola x1 carry rank-0 display-order snapshots (the
-- pre-MENU-ORDER legacy value; the columns are NOT NULL); B3 Burger x1 keeps
-- its ranks. The edit removes B2 and adds 2 x Lemonade, so ORDER NOW mixes
-- legacy and ranked lines.
select pg_temp.mk_order('fed00000-0000-0000-0000-00000000b001', 'takeaway', null, null, null);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000b1001', 'fed00000-0000-0000-0000-00000000b001', 'fed00000-0000-0000-0000-000000001002', 'Fries', 2, 1500);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000b1002', 'fed00000-0000-0000-0000-00000000b001', 'fed00000-0000-0000-0000-000000001003', 'Cola', 1, 800);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000b1003', 'fed00000-0000-0000-0000-00000000b001', 'fed00000-0000-0000-0000-000000001001', 'Burger', 1, 4000);
update order_items set category_display_order_snapshot = 0, item_display_order_snapshot = 0
 where id in ('fed00000-0000-0000-0000-0000000b1001', 'fed00000-0000-0000-0000-0000000b1002');
select pg_temp.settle_totals('fed00000-0000-0000-0000-00000000b001');
select pg_temp.mk_initial_dispatch('fed00000-0000-0000-0000-00000000b001');
-- Before 3000 + 800 + 4000 = 7800; after 3000 + 4000 + 1800 = 8800.
select pg_temp.capture('b_legacy_ranks_add', 'fed00000-0000-0000-0000-00000000009c', 'سارة أحمد', 'slip-b-1',
  'fed00000-0000-0000-0000-00000000b001', '{
    "reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 8800, "tax_total_minor": 0, "grand_total_minor": 8800},
    "changes": [
      {"op": "remove", "order_item_id": "fed00000-0000-0000-0000-0000000b1002"},
      {"op": "add", "item": {"menu_item_id": "fed00000-0000-0000-0000-000000001004", "quantity": 2,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);

-- ===== case C: an ORDER NOTE (gap G1 — the read surface omits it) ==========
select pg_temp.mk_order('fed00000-0000-0000-0000-00000000c001', 'takeaway', null, null, '  allergy: nuts  ');
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000c1001', 'fed00000-0000-0000-0000-00000000c001', 'fed00000-0000-0000-0000-000000001002', 'Fries', 1, 1500);
select pg_temp.mk_item('fed00000-0000-0000-0000-0000000c1002', 'fed00000-0000-0000-0000-00000000c001', 'fed00000-0000-0000-0000-000000001003', 'Cola', 2, 800);
select pg_temp.settle_totals('fed00000-0000-0000-0000-00000000c001');
select pg_temp.mk_initial_dispatch('fed00000-0000-0000-0000-00000000c001');
-- Before 1500 + 1600 = 3100; after 1500 + 800 = 2300.
select pg_temp.capture('c_order_note', 'fed00000-0000-0000-0000-00000000009a', 'Dana Cashier', 'slip-c-1',
  'fed00000-0000-0000-0000-00000000c001', '{
    "reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 2300, "tax_total_minor": 0, "grand_total_minor": 2300},
    "changes": [
      {"op": "set_quantity", "order_item_id": "fed00000-0000-0000-0000-0000000c1002", "quantity": 1}]}'::jsonb);

select jsonb_pretty(jsonb_object_agg(k, j order by k)) from cap;
rollback;
