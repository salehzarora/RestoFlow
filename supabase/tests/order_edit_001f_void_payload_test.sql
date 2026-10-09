-- ORDER-EDIT-001F — the VOID slip's line count after an order edit
-- (API_CONTRACT §4.45.10; ORDER_EDIT_DESIGN §7.3). app.kitchen_dispatch_payload_void
-- excludes the lines an order edit retired (removed_by_edit_id IS NOT NULL), so
-- after a paper edit each live line counts ONCE; an order that was never edited
-- keeps a byte-identical payload (voided and cancelled lines included, exactly
-- as before — kitchen_dispatch_harden_001_test still expects 7).
begin;
set local search_path to extensions, public, pg_catalog;

select plan(14);

-- ===== fixture ==============================================================
-- Org F1: one PRINTER-ONLY branch with order editing ON, one POS till, a
-- cashier PIN session (edits) and a manager PIN session (voids), one table.
insert into organizations (id, name, slug, default_currency) values
  ('f1ed0000-0000-0000-0000-0000000000a0', 'Org Void Count', 'org-void-count-001f', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000a0', 'Rest Void Count');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, order_edit_enabled) values
  ('f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'Branch Void Count', 'printer_only', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('f1ed0000-0000-0000-0000-0000000000d1', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('f1ed0000-0000-0000-0000-0000000000f1', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('f1ed0000-0000-0000-0000-00000000005a', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-0000000000d1', 'f1ed0000-0000-0000-0000-0000000000f1');
insert into app_users (id, email) values
  ('f1ed0000-0000-0000-0000-00000000006a', 'void-count-cashier@example.test'),
  ('f1ed0000-0000-0000-0000-00000000006b', 'void-count-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('f1ed0000-0000-0000-0000-00000000007a', 'f1ed0000-0000-0000-0000-00000000006a', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('f1ed0000-0000-0000-0000-00000000007b', 'f1ed0000-0000-0000-0000-00000000006b', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('f1ed0000-0000-0000-0000-00000000008a', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-00000000006a', 'f1ed0000-0000-0000-0000-00000000007a', 'Vera Cashier'),
  ('f1ed0000-0000-0000-0000-00000000008b', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-00000000006b', 'f1ed0000-0000-0000-0000-00000000007b', 'Max Manager');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('f1ed0000-0000-0000-0000-00000000009a', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-00000000005a', 'f1ed0000-0000-0000-0000-00000000008a', 'f1ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('f1ed0000-0000-0000-0000-00000000009b', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-00000000005a', 'f1ed0000-0000-0000-0000-00000000008b', 'f1ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour');
insert into tables (id, organization_id, restaurant_id, branch_id, label, status) values
  ('f1ed0000-0000-0000-0000-0000000000b1', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab', 'T7', 'available');

-- Menu: Burger 4000 (Extras: cucumber 0, cheese 300), Fries 1500, Cola 800,
-- Lemonade 900, Water 0.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('f1ed0000-0000-0000-0000-0000000000c1', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('f1ed0000-0000-0000-0000-000000001001', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('f1ed0000-0000-0000-0000-000000001002', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2),
  ('f1ed0000-0000-0000-0000-000000001003', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 3),
  ('f1ed0000-0000-0000-0000-000000001004', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-0000000000c1', 'Lemonade', 900, 'ILS', 4),
  ('f1ed0000-0000-0000-0000-000000001005', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-0000000000c1', 'Water', 0, 'ILS', 5);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('f1ed0000-0000-0000-0000-00000000d101', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-000000001001', 'Extras', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('f1ed0000-0000-0000-0000-00000000e002', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-00000000d101', 'cucumber', 0,   1, true),
  ('f1ed0000-0000-0000-0000-00000000e003', 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', null, 'f1ed0000-0000-0000-0000-00000000d101', 'cheese',   300, 2, true);

-- builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire)
create function pg_temp.mk_order(p_id uuid, p_table uuid default null) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, table_id, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status)
  values (p_id, 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1',
    'f1ed0000-0000-0000-0000-0000000000ab', 'f1ed0000-0000-0000-0000-0000000000d1',
    'f1ed0000-0000-0000-0000-00000000009a', 'f1ed0000-0000-0000-0000-00000000008a',
    'f1ed0000-0000-0000-0000-00000000007a', case when p_table is null then 'takeaway' else 'dine_in' end,
    p_table, 'ILS', 0, 0, 'submit-' || p_id::text, 'submitted');
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor)
  values (p_id, 'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1',
    'f1ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, p_total);
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_name text, p_price bigint) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
  values ('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1',
    'f1ed0000-0000-0000-0000-0000000000ab', p_item, p_opt, 'Extras', p_name, p_price, 1);
$$;
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- the order's initial kitchen dispatch, exactly as submit_order creates it
create function pg_temp.mk_initial_dispatch(p_order uuid) returns void
language sql as $$
  select app.create_kitchen_dispatch(
    'f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-0000000000a1', 'f1ed0000-0000-0000-0000-0000000000ab',
    p_order, null, 'initial_order',
    app.kitchen_dispatch_payload_initial('f1ed0000-0000-0000-0000-0000000000a0', p_order),
    'f1ed0000-0000-0000-0000-00000000008a', 'f1ed0000-0000-0000-0000-00000000007a', 'f1ed0000-0000-0000-0000-0000000000d1');
$$;
-- one order.edit through public.sync_push; returns the op's result
create function pg_temp.edit(p_op text, p_order uuid, p_payload jsonb) returns jsonb
language sql as $$
  select public.sync_push('f1ed0000-0000-0000-0000-00000000009a', 'f1ed0000-0000-0000-0000-0000000000d1',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
      'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- the stored money_free_payload of an order's VOID dispatch
create function pg_temp.void_slip(p_order uuid) returns jsonb language sql as $$
  select money_free_payload from kitchen_print_dispatches
   where organization_id = 'f1ed0000-0000-0000-0000-0000000000a0'
     and order_id = p_order and dispatch_type = 'void';
$$;
-- The PRE-001F builder, copied verbatim from its live definition
-- (20260725090000_kitchen_mode_001c1_dispatch_ledger.sql): the oracle that an
-- order never edited keeps a byte-identical VOID payload.
create function pg_temp.payload_void_pre_001f(
  p_organization_id uuid,
  p_order_id        uuid,
  p_reason          text
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'void',
    'void', true,
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'reason', nullif(left(btrim(coalesce(p_reason, '')), 200), ''),
    'voided_at', now(),
    'affected_item_count', (
      select count(*)::int from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id and oi.deleted_at is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

-- ===== A. the definition: one predicate, posture unchanged ==================
select is(
  (select count(*)::int
     from regexp_matches(pg_get_functiondef('app.kitchen_dispatch_payload_void(uuid, uuid, text)'::regprocedure),
                         'and oi\.removed_by_edit_id is null', 'g')),
  1,
  '01 the VOID builder carries the edit-retired predicate exactly once');
select ok(
  (select not p.prosecdef and p.provolatile = 's' and p.prolang = (select oid from pg_language where lanname = 'sql')
          and p.proconfig = array['search_path=""']
          and pg_get_function_result(p.oid) = 'jsonb'
     from pg_proc p where p.oid = 'app.kitchen_dispatch_payload_void(uuid, uuid, text)'::regprocedure),
  '02 posture unchanged: LANGUAGE sql, STABLE, SECURITY INVOKER, search_path='''', returns jsonb');
select ok(
  not has_function_privilege('anon', 'app.kitchen_dispatch_payload_void(uuid, uuid, text)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_void(uuid, uuid, text)', 'execute')
  and not has_function_privilege('public', 'app.kitchen_dispatch_payload_void(uuid, uuid, text)', 'execute'),
  '03 still INTERNAL-ONLY: no anon / authenticated / public execute');
select ok(
  (select d like 'KITCHEN-MODE-001C1 INTERNAL: the money-free VOID slip snapshot (marker + safe reason + counts; no items priced, no payment data).%'
          and d like '% ORDER-EDIT-001F: affected_item_count excludes the lines an order edit retired%'
     from obj_description('app.kitchen_dispatch_payload_void(uuid, uuid, text)'::regprocedure, 'pg_proc') d),
  '04 the COMMENT keeps its KITCHEN-MODE-001C1 text and gains the 001F provenance sentence');

-- ===== B. an order NEVER edited: byte-identical, voided/cancelled included ==
-- Order U1 (dine-in, table T7): two live lines, one line voided and one line
-- cancelled by something other than an edit.
select pg_temp.mk_order('f1ed0000-0000-0000-0000-00000000b001', 'f1ed0000-0000-0000-0000-0000000000b1');
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000b1001', 'f1ed0000-0000-0000-0000-00000000b001', 'f1ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000b1002', 'f1ed0000-0000-0000-0000-00000000b001', 'f1ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 3000);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000b1003', 'f1ed0000-0000-0000-0000-00000000b001', 'f1ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000b1004', 'f1ed0000-0000-0000-0000-00000000b001', 'f1ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900);
update order_items set status = 'voided' where id = 'f1ed0000-0000-0000-0000-0000000b1003';
update order_items set status = 'cancelled' where id = 'f1ed0000-0000-0000-0000-0000000b1004';
select pg_temp.settle_totals('f1ed0000-0000-0000-0000-00000000b001');

select is(
  app.kitchen_dispatch_payload_void('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000b001', '  wrong table  '),
  pg_temp.payload_void_pre_001f('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000b001', '  wrong table  '),
  '05 never edited: the payload is byte-identical to the pre-001F builder (table, trimmed reason, counts)');
select is(
  (app.kitchen_dispatch_payload_void('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000b001', null)
   ->> 'affected_item_count')::int,
  4,
  '06 never edited: every line still counts, the voided and the cancelled one included');

select pg_temp.mk_initial_dispatch('f1ed0000-0000-0000-0000-00000000b001');
create temp table t_vu as select app.void_order('f1ed0000-0000-0000-0000-00000000009b', 'f1ed0000-0000-0000-0000-00000000b001',
  'f1ed0000-0000-0000-0000-0000000000d1', 'f1-void-u1', 'wrong table') as r;
select ok(
  (select (r ->> 'ok')::boolean from t_vu)
  and pg_temp.void_slip('f1ed0000-0000-0000-0000-00000000b001')
      = pg_temp.payload_void_pre_001f('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000b001', 'wrong table'),
  '07 never edited: app.void_order stores the byte-identical VOID slip (affected_item_count 4)');

-- ===== C. a PAPER edit, then a whole-order void =============================
-- Order P1 (#00C001, takeaway). Original ticket:
--   L1 Burger x1 4000                       -> remove
--   L2 Cola x2 1600                         -> reduce to 1 (remainder in place)
--   L3 Burger x2 (+cucumber) 8000           -> modify "just 1": 1 unchanged + 1 (+cheese)
--   L4 Lemonade x1 900                      -> increase to 3 (old row kept + a +2 row)
--   L5 Fries x1 1500                        -> untouched
--   + Water x1 0                            -> add
-- Subtotal 16000 -> 13300.
select pg_temp.mk_order('f1ed0000-0000-0000-0000-00000000c001');
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000c1001', 'f1ed0000-0000-0000-0000-00000000c001', 'f1ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000c1002', 'f1ed0000-0000-0000-0000-00000000c001', 'f1ed0000-0000-0000-0000-000000001003', 'Cola', 2, 800, 1600);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000c1003', 'f1ed0000-0000-0000-0000-00000000c001', 'f1ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8000);
select pg_temp.mk_mod('f1ed0000-0000-0000-0000-0000000c1003', 'f1ed0000-0000-0000-0000-00000000e002', 'cucumber', 0);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000c1004', 'f1ed0000-0000-0000-0000-00000000c001', 'f1ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900);
select pg_temp.mk_item('f1ed0000-0000-0000-0000-0000000c1005', 'f1ed0000-0000-0000-0000-00000000c001', 'f1ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.settle_totals('f1ed0000-0000-0000-0000-00000000c001');
select pg_temp.mk_initial_dispatch('f1ed0000-0000-0000-0000-00000000c001');

create temp table t_pe as select pg_temp.edit('f1-edit-p1', 'f1ed0000-0000-0000-0000-00000000c001', '{
    "reason_code": "entry_mistake",
    "expected": {"subtotal_minor": 13300, "tax_total_minor": 0, "grand_total_minor": 13300},
    "changes": [
      {"op": "remove", "order_item_id": "f1ed0000-0000-0000-0000-0000000c1001"},
      {"op": "set_quantity", "order_item_id": "f1ed0000-0000-0000-0000-0000000c1002", "quantity": 1},
      {"op": "modify", "order_item_id": "f1ed0000-0000-0000-0000-0000000c1003",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "f1ed0000-0000-0000-0000-00000000e002"}]},
                        {"quantity": 1, "modifiers": [{"modifier_option_id": "f1ed0000-0000-0000-0000-00000000e002"},
                                                      {"modifier_option_id": "f1ed0000-0000-0000-0000-00000000e003",
                                                       "option_name_snapshot": "cheese", "price_minor_snapshot": 300}]}]},
      {"op": "set_quantity", "order_item_id": "f1ed0000-0000-0000-0000-0000000c1004", "quantity": 3},
      {"op": "add", "item": {"menu_item_id": "f1ed0000-0000-0000-0000-000000001005", "quantity": 1,
        "unit_price_minor_snapshot": 0, "menu_item_name_snapshot": "Water", "modifiers": []}}]}'::jsonb) as r;

select ok(
  (select r ->> 'status' = 'applied' and r ->> 'kitchen_channel' = 'paper' and (r ->> 'edit_number')::int = 1 from t_pe)
  and (select count(*) = 10 from order_items where order_id = 'f1ed0000-0000-0000-0000-00000000c001' and deleted_at is null)
  and (select count(*) = 3 from order_items where order_id = 'f1ed0000-0000-0000-0000-00000000c001'
          and removed_by_edit_id = (select (r ->> 'order_edit_id')::uuid from t_pe))
  and (select count(*) = 7 from order_items where order_id = 'f1ed0000-0000-0000-0000-00000000c001'
          and status not in ('voided', 'cancelled')),
  '08 fixture: the paper edit applied; 10 rows = 3 retired (remove, reduce, modify) + 7 live');
select is(
  (pg_temp.payload_void_pre_001f('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000c001', 'x')
   ->> 'affected_item_count')::int,
  10,
  '09 the defect: the pre-001F builder counts each retired row next to its replacement (10)');
select is(
  (app.kitchen_dispatch_payload_void('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000c001', 'x')
   ->> 'affected_item_count')::int,
  7,
  '10 after the edit the VOID builder counts the 7 live lines (remainder, both replacements, the +2 row and the add once each)');

create temp table t_vp as select app.void_order('f1ed0000-0000-0000-0000-00000000009b', 'f1ed0000-0000-0000-0000-00000000c001',
  'f1ed0000-0000-0000-0000-0000000000d1', 'f1-void-p1', 'guest left') as r;
select ok(
  (select (r ->> 'ok')::boolean from t_vp)
  and (select count(*) = 10 and bool_and(status in ('voided', 'cancelled'))
         from order_items where order_id = 'f1ed0000-0000-0000-0000-00000000c001' and deleted_at is null),
  '11 the whole-order void voided every line (a status filter could not tell retired rows apart)');
select is(
  (pg_temp.void_slip('f1ed0000-0000-0000-0000-00000000c001') ->> 'affected_item_count')::int,
  7,
  '12 the stored VOID slip of the edited order reports 7 lines, not 10');
select is(
  pg_temp.void_slip('f1ed0000-0000-0000-0000-00000000c001') - 'affected_item_count',
  pg_temp.payload_void_pre_001f('f1ed0000-0000-0000-0000-0000000000a0', 'f1ed0000-0000-0000-0000-00000000c001', 'guest left') - 'affected_item_count',
  '13 every other key of the VOID slip is unchanged (marker, code, type, reason, voided_at)');
select ok(
  (select bool_and(not (k ~ '_minor$'))
     from jsonb_object_keys(pg_temp.void_slip('f1ed0000-0000-0000-0000-00000000c001')) k),
  '14 the VOID slip stays money-free (no _minor key)');

select * from finish();
rollback;
