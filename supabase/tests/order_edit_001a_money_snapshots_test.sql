-- ORDER-EDIT-001A — MONEY (MONEY_AND_TAX_SPEC §9.2 M1-M13, §13) and SNAPSHOTS
-- (API_CONTRACT §4.45.2 step 8, §4.45.3 step 15; D-008) of app.edit_order,
-- driven end-to-end through public.sync_push (order.edit / order.edit_ack):
--   A. app.edit_tax_minor — the POS tax_math.dart vectors (M7)
--   B. app.edit_reanswer_prep — the frozen classifier re-answer (pure)
--   C. whole-order tax recompute from the branch's CURRENT settings, half away
--      from zero, correcting earlier untaxed lines (R-008); inclusive refused
--   D. the absolute order discount is KEPT, never clamped (M6), zero-out (M8)
--   E. order_already_settled (M10) / order_not_editable
--   F. snapshots copied server-side after the live menu moved (D-008): ranks,
--      prices, size / variant, notes, prep + meat classifier re-answer
--   G. new-option / sellability validation of a modify / add (nothing written)
--   H. the MONEY §9.2 worked example and the §13 Order edits classification
--   I. M11 (revision; the kitchen "Got it" never bumps it) and M12 / T-003
begin;
set local search_path to extensions, public, pg_catalog;

select plan(79);

-- ===== fixture ==============================================================
-- Org E4: one KDS branch, order editing ON, tax ON at 1700 bp EXCLUSIVE; one
-- POS + one KDS; cashier / manager PIN sessions on the POS, kitchen on the KDS.
insert into organizations (id, name, slug, default_currency) values
  ('e4ed0000-0000-0000-0000-0000000000a0', 'Org Edit Money', 'org-edit-money-001a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000a0', 'Rest Edit Money');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled, tax_enabled, tax_rate_bp, tax_mode) values
  ('e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
   'Branch Edit Money', true, true, 1700, 'exclusive');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e4ed0000-0000-0000-0000-0000000000d1', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'pos'),
  ('e4ed0000-0000-0000-0000-0000000000d2', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e4ed0000-0000-0000-0000-0000000000f1', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-0000000000d1', 'active'),
  ('e4ed0000-0000-0000-0000-0000000000f2', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-0000000000d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e4ed0000-0000-0000-0000-00000000005a', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-0000000000d1', 'e4ed0000-0000-0000-0000-0000000000f1'),
  ('e4ed0000-0000-0000-0000-00000000005b', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-0000000000d2', 'e4ed0000-0000-0000-0000-0000000000f2');
insert into app_users (id, email) values
  ('e4ed0000-0000-0000-0000-00000000006a', 'money-cashier@example.test'),
  ('e4ed0000-0000-0000-0000-00000000006b', 'money-manager@example.test'),
  ('e4ed0000-0000-0000-0000-00000000006c', 'money-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e4ed0000-0000-0000-0000-00000000007a', 'e4ed0000-0000-0000-0000-00000000006a', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('e4ed0000-0000-0000-0000-00000000007b', 'e4ed0000-0000-0000-0000-00000000006b', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('e4ed0000-0000-0000-0000-00000000007c', 'e4ed0000-0000-0000-0000-00000000006c', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e4ed0000-0000-0000-0000-00000000008a', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000006a', 'e4ed0000-0000-0000-0000-00000000007a', 'Cara Cashier'),
  ('e4ed0000-0000-0000-0000-00000000008b', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000006b', 'e4ed0000-0000-0000-0000-00000000007b', 'Max Manager'),
  ('e4ed0000-0000-0000-0000-00000000008c', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000006c', 'e4ed0000-0000-0000-0000-00000000007c', 'Kai Kitchen');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e4ed0000-0000-0000-0000-00000000009a', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000005a', 'e4ed0000-0000-0000-0000-00000000008a', 'e4ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('e4ed0000-0000-0000-0000-00000000009b', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000005a', 'e4ed0000-0000-0000-0000-00000000008b', 'e4ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('e4ed0000-0000-0000-0000-00000000009c', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000005b', 'e4ed0000-0000-0000-0000-00000000008c', 'e4ed0000-0000-0000-0000-00000000007c', now() + interval '1 hour');

-- Menu (ranks at ORDER time): Mains 1 {Burger 1, Fries 2, Salad 3}, Drinks 2
-- {Cola 1, Lemonade 2}. Burger: Extras 1 {tomato 1 +0, cucumber 2 +0,
-- cheese 3 +300 (kitchen_meat 20 g)}, Meat 2 {bacon 1 +400 (kitchen_meat 50 g,
-- classifier -> cheese)}; Fries: Sauce 1 {ketchup 1 +100}; Cola: Garnish 1
-- {lemon 1 +50}. Burger's live prep component Patty is classified by cheese.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e4ed0000-0000-0000-0000-0000000000c1', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1),
  ('e4ed0000-0000-0000-0000-0000000000c2', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'Drinks', 2);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, attributes) values
  ('e4ed0000-0000-0000-0000-000000001001', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1,
   '{"prep_components": [{"name": "Patty", "quantity": 180, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003"}, {"name": "Bun", "quantity": 1, "unit": "pc"}]}'),
  ('e4ed0000-0000-0000-0000-000000001002', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2, null),
  ('e4ed0000-0000-0000-0000-000000001003', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-0000000000c2', 'Cola', 800, 'ILS', 1, null),
  ('e4ed0000-0000-0000-0000-000000001004', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-0000000000c2', 'Lemonade', 900, 'ILS', 2, null),
  ('e4ed0000-0000-0000-0000-000000001005', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-0000000000c1', 'Salad', 2000, 'ILS', 3, null);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, display_order) values
  ('e4ed0000-0000-0000-0000-00000000d101', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-000000001001', 'Extras',  'multiple', 0, null, false, true, 1),
  ('e4ed0000-0000-0000-0000-00000000d102', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-000000001001', 'Meat',    'multiple', 0, null, false, true, 2),
  ('e4ed0000-0000-0000-0000-00000000d103', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-000000001002', 'Sauce',   'multiple', 0, null, false, true, 1),
  ('e4ed0000-0000-0000-0000-00000000d104', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-000000001003', 'Garnish', 'multiple', 0, null, false, true, 1);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat) values
  ('e4ed0000-0000-0000-0000-00000000e001', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-00000000d101', 'tomato',   0,   1, true, null),
  ('e4ed0000-0000-0000-0000-00000000e002', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-00000000d101', 'cucumber', 0,   2, true, null),
  ('e4ed0000-0000-0000-0000-00000000e003', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-00000000d101', 'cheese',   300, 3, true,
   '{"quantity": 20, "unit": "g"}'),
  ('e4ed0000-0000-0000-0000-00000000e004', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-00000000d102', 'bacon',    400, 1, true,
   '{"quantity": 50, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003"}'),
  ('e4ed0000-0000-0000-0000-00000000e005', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-00000000d103', 'ketchup',  100, 1, true, null),
  ('e4ed0000-0000-0000-0000-00000000e006', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', null, 'e4ed0000-0000-0000-0000-00000000d104', 'lemon',    50,  1, true, null);

-- Builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire).
create function pg_temp.mk_order(p_id uuid, p_status text) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at, voided_at, voided_from_status)
  values (p_id, 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
    'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-0000000000d1',
    'e4ed0000-0000-0000-0000-00000000009a', 'e4ed0000-0000-0000-0000-00000000008a',
    'e4ed0000-0000-0000-0000-00000000007a', 'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served', 'completed') then now() - interval '5 minutes' end,
    case when p_status = 'voided' then now() end,
    case when p_status = 'voided' then 'served' end);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_notes text default null, p_prep jsonb default null,
  p_size jsonb default null, p_variant jsonb default null) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor,
    notes, prep_snapshot, item_size_snapshot, item_variant_snapshot)
  values (p_id, 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
    'e4ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, 0, p_total,
    p_notes, p_prep, p_size, p_variant);
$$;
create function pg_temp.mk_mod(p_item uuid, p_opt uuid, p_group text, p_name text, p_price bigint,
  p_meat jsonb default null) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
  values ('e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
    'e4ed0000-0000-0000-0000-0000000000ab', p_item, p_opt, p_group, p_name, p_price, 1, p_meat);
$$;
-- stored totals: subtotal = live lines, the given discount and tax (a tax of 0
-- on a tax-enabled branch models earlier UNTAXED add-items lines, R-008).
create function pg_temp.settle(p_order uuid, p_disc bigint, p_tax bigint) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, discount_total_minor = p_disc, tax_total_minor = p_tax,
                      grand_total_minor = s.t - p_disc + p_tax
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push; returns the op's result
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'e4ed0000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- one order.edit_ack through public.sync_push (default: the KDS)
create function pg_temp.ack(p_pin uuid, p_op text, p_order uuid, p_n int,
  p_dev uuid default 'e4ed0000-0000-0000-0000-0000000000d2') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit_ack', 'target_entity', 'order',
    'target_id', p_order, 'payload', jsonb_build_object('order_id', p_order, 'up_to_edit_number', p_n)))) -> 'results' -> 0;
$$;
-- everything an edit could write for an order (refusals must leave it as is)
create function pg_temp.fp(p_order uuid) returns text language sql as $$
  select concat_ws('|',
    (select revision || ':' || edit_count || ':' || status || ':' || subtotal_minor || ':' || discount_total_minor
            || ':' || tax_total_minor || ':' || grand_total_minor from orders where id = p_order),
    (select count(*) || ':' || coalesce(string_agg(id::text || '=' || status || '=' || line_total_minor, ',' order by id), '')
       from order_items where order_id = p_order),
    (select count(*) from order_item_modifiers m join order_items i on i.id = m.order_item_id where i.order_id = p_order),
    (select count(*) from order_edits where order_id = p_order),
    (select count(*) || ':' || coalesce(string_agg(status, ',' order by id), '') from order_service_rounds where order_id = p_order),
    (select count(*) from order_operations where order_id = p_order),
    (select count(*) from kitchen_print_dispatches where order_id = p_order));
$$;
create temp table t_fp (order_id uuid primary key, fp text not null);
create function pg_temp.snap(p_order uuid) returns void language sql as $$
  insert into t_fp values (p_order, pg_temp.fp(p_order))
  on conflict (order_id) do update set fp = excluded.fp;
$$;
-- refusal results are stored first (own statement), then judged
create temp table t_res (k text primary key, r jsonb);
create function pg_temp.refused(p_k text, p_order uuid, p_error text, p_detail text default null) returns boolean
language sql as $$
  select coalesce((select r ->> 'status' = 'rejected' and r ->> 'error' = p_error
                          and (p_detail is null or r ->> 'detail' = p_detail)
                     from t_res where k = p_k), false)
         and (select fp from t_fp where order_id = p_order) = pg_temp.fp(p_order);
$$;
-- MONEY identity of an order after an edit (M3 / M5 / M7 / M8): 'ok' or the
-- list of violations. The tax is recomputed independently with the POS
-- integer rule (base * bp + 5000) / 10000 from the branch's current settings.
create function pg_temp.money_check(p_order uuid) returns text language sql as $$
  with o as (select * from orders where id = p_order),
  b as (select br.tax_enabled, br.tax_rate_bp, br.tax_mode from branches br, o where br.id = o.branch_id),
  live as (select coalesce(sum(line_total_minor), 0)::bigint as s from order_items
            where order_id = p_order and status not in ('voided', 'cancelled') and deleted_at is null),
  bad as (select count(*) as n from order_items n
           where n.order_id = p_order and n.edit_id is not null
             and (n.line_discount_minor <> 0
                  or n.line_total_minor <> n.quantity::bigint * (n.unit_price_minor_snapshot + coalesce((
                       select sum(m.price_minor_snapshot * m.quantity) from order_item_modifiers m
                        where m.order_item_id = n.id and m.deleted_at is null), 0))))
  select coalesce(nullif(concat_ws('; ',
    case when o.subtotal_minor <> live.s then 'subtotal ' || o.subtotal_minor || ' <> live sum ' || live.s end,
    case when o.grand_total_minor <> o.subtotal_minor - o.discount_total_minor + o.tax_total_minor
         then 'grand ' || o.grand_total_minor || ' <> subtotal - discount + tax' end,
    case when o.tax_total_minor <> case when b.tax_enabled and b.tax_rate_bp > 0
                                        then ((o.subtotal_minor - o.discount_total_minor) * b.tax_rate_bp + 5000) / 10000
                                        else 0 end
         then 'tax ' || o.tax_total_minor || ' is not the recomputed whole-order tax' end,
    case when bad.n > 0 then bad.n || ' edit-written rows mispriced or discounted' end), ''), 'ok')
  from o, b, live, bad;
$$;
-- MONEY §13 / ORDER_EDIT_DESIGN §9.1 M13 Order-edits figures of one order,
-- computed ONLY from removed_by_edit_id / replaces_order_item_id / edit_id.
create function pg_temp.m13(p_order uuid) returns jsonb language sql as $$
  with r as (select * from order_items where order_id = p_order and removed_by_edit_id is not null
                                        and status in ('voided', 'cancelled')),
  n as (select * from order_items where order_id = p_order and edit_id is not null
                                    and status not in ('voided', 'cancelled') and deleted_at is null),
  f as (select
    (select coalesce(sum(r.line_total_minor), 0) from r
      where not exists (select 1 from order_items x where x.replaces_order_item_id = r.id)) as removed,
    (select coalesce(sum(r.line_total_minor), 0) from r
      where exists (select 1 from order_items x where x.replaces_order_item_id = r.id)) as replaced_out,
    (select coalesce(sum(n.line_total_minor), 0) from n where n.replaces_order_item_id is not null) as replaced_in,
    (select coalesce(sum(n.line_total_minor), 0) from n where n.replaces_order_item_id is null) as added)
  select jsonb_build_object('removed_minor', removed, 'replaced_out_minor', replaced_out,
                            'replaced_in_minor', replaced_in, 'added_minor', added,
                            'net_change_minor', replaced_in + added - removed - replaced_out)
    from f;
$$;

-- ===== A. app.edit_tax_minor (M7) — the tax_math.dart vectors =================
select is(array[app.edit_tax_minor(9999, true, 1700, 'exclusive'),
                app.edit_tax_minor(100, true, 1725, 'exclusive'),
                app.edit_tax_minor(100, true, 1775, 'exclusive'),
                app.edit_tax_minor(1, true, 5000, 'exclusive'),
                app.edit_tax_minor(3, true, 5000, 'exclusive'),
                app.edit_tax_minor(5, true, 5000, 'exclusive'),
                app.edit_tax_minor(10000, true, 0, 'exclusive'),
                app.edit_tax_minor(0, true, 1700, 'exclusive')],
          array[1700, 17, 18, 1, 2, 3, 0, 0]::bigint[],
  '01 exclusive tax = round half AWAY from zero of base x bp / 10000 (tax_math.dart vectors)');
select is(app.edit_tax_minor(10000, false, 1700, 'exclusive'), 0::bigint,
  '02 tax disabled -> 0 (even with a rate)');
select is(app.edit_tax_minor(10000, true, 1700, 'inclusive'), null::bigint,
  '03 inclusive with tax enabled and a rate > 0 -> NULL (the caller refuses tax_mode_unsupported)');
select is(app.edit_tax_minor(10000, false, 1700, 'inclusive'), 0::bigint,
  '04 inclusive with tax disabled -> 0 (no effect while tax is OFF)');
select ok(app.edit_tax_minor(10000, true, 0, 'inclusive') = 0
          and app.edit_tax_minor(10000, null, 1700, 'exclusive') = 0
          and app.edit_tax_minor(999999999999, true, 10000, 'exclusive') = 999999999999,
  '05 a 0 bp rate -> 0 in any mode; NULL enabled -> 0; large bases stay exact (integer minor units)');

-- ===== B. app.edit_reanswer_prep — the frozen classifier link, re-answered ====
select is(app.edit_reanswer_prep(
  '{"quantity": 50, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": false}'::jsonb,
  '[{"modifier_option_id": "x-tomato"}, {"modifier_option_id": "x-cheese"}]'::jsonb),
  '{"quantity": 50, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": true}'::jsonb,
  '06 object: classifier present in the full set -> classifier_selected TRUE, every other key copied');
select is(app.edit_reanswer_prep(
  '{"quantity": 50, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": true}'::jsonb,
  '[{"modifier_option_id": "x-tomato"}]'::jsonb),
  '{"quantity": 50, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": false}'::jsonb,
  '07 object: classifier absent -> flips back to FALSE');
select is(app.edit_reanswer_prep(
  '[{"name": "Patty", "quantity": 180, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": false},
    {"name": "Bun", "quantity": 1, "unit": "pc"},
    {"name": "Sauce", "quantity": 2, "unit": "ml", "classifier_option_id": "x-mayo", "classifier_option_name": "mayo", "classifier_selected": true}]'::jsonb,
  '[{"modifier_option_id": "x-cheese"}]'::jsonb),
  '[{"name": "Patty", "quantity": 180, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": true},
    {"name": "Bun", "quantity": 1, "unit": "pc"},
    {"name": "Sauce", "quantity": 2, "unit": "ml", "classifier_option_id": "x-mayo", "classifier_option_name": "mayo", "classifier_selected": false}]'::jsonb,
  '08 array: each classifier element re-answered, the non-classifier element untouched, order kept');
select is(app.edit_reanswer_prep(
  '[{"name": "Patty", "quantity": 1, "unit": "pc", "classifier_option_id": "x-cheese"},
    {"name": "Patty", "quantity": 1, "unit": "pc", "classifier_option_id": 7, "classifier_selected": false},
    "loose"]'::jsonb,
  '[{"modifier_option_id": "x-cheese"}, {"modifier_option_id": "7"}]'::jsonb),
  '[{"name": "Patty", "quantity": 1, "unit": "pc", "classifier_option_id": "x-cheese"},
    {"name": "Patty", "quantity": 1, "unit": "pc", "classifier_option_id": 7, "classifier_selected": false},
    "loose"]'::jsonb,
  '09 elements without a classifier_selected key, with a non-string id, or not objects are copied unchanged');
select ok(app.edit_reanswer_prep('"text"'::jsonb, '[{"modifier_option_id": "x"}]'::jsonb) = '"text"'::jsonb
          and app.edit_reanswer_prep('42'::jsonb, '[]'::jsonb) = '42'::jsonb
          and app.edit_reanswer_prep('null'::jsonb, '[]'::jsonb) = 'null'::jsonb
          and app.edit_reanswer_prep(null, '[]'::jsonb) is null
          and app.edit_reanswer_prep('[]'::jsonb, '[]'::jsonb) = '[]'::jsonb,
  '10 a non-array / non-object input is returned unchanged (NULL stays NULL)');
select is(app.edit_reanswer_prep(
  '{"quantity": 50, "unit": "g", "classifier_option_id": "x-cheese", "classifier_option_name": "cheese", "classifier_selected": true}'::jsonb,
  '{"modifier_option_id": "x-cheese"}'::jsonb) ->> 'classifier_selected', 'false',
  '11 a non-array selection is an EMPTY set (fail closed: classifier not selected)');

-- ===== C. whole-order tax recompute (M7, R-008) ==============================
-- C1 In kitchen: Fries x2 3000 + Cola 800 = 3800, discount 450, stored tax 0
--    (untaxed earlier lines). Edit: + Lemonade 900 -> subtotal 4700, base
--    4250, tax 722.5 -> 723 (half away), grand 4700 - 450 + 723 = 4973.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000c001', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c1001', 'e4ed0000-0000-0000-0000-00000000c001', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 3000);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c1002', 'e4ed0000-0000-0000-0000-00000000c001', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000c001', 450, 0);
select pg_temp.snap('e4ed0000-0000-0000-0000-00000000c001');
insert into t_res select 'c1-bankers', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c1-x', 'e4ed0000-0000-0000-0000-00000000c001',
  '{"expected": {"subtotal_minor": 4700, "tax_total_minor": 722, "grand_total_minor": 4972},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
      "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);
select ok(pg_temp.refused('c1-bankers', 'e4ed0000-0000-0000-0000-00000000c001', 'totals_mismatch')
          and (select r -> 'totals' = '{"subtotal_minor": 4700, "discount_total_minor": 450, "tax_total_minor": 723, "grand_total_minor": 4973}'::jsonb
                 from t_res where k = 'c1-bankers'),
  '12 a half-to-even tax (722) is totals_mismatch carrying the server figures 4700 / 450 / 723 / 4973; nothing written');
create temp table t_c1 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c1', 'e4ed0000-0000-0000-0000-00000000c001',
  '{"expected": {"subtotal_minor": 4700, "tax_total_minor": 723, "grand_total_minor": 4973},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
      "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;
select is((select r ->> 'status' from t_c1), 'applied', '13 C1 the correctly-taxed edit is applied');
select ok((select subtotal_minor = 4700 and discount_total_minor = 450 and tax_total_minor = 723 and grand_total_minor = 4973
             from orders where id = 'e4ed0000-0000-0000-0000-00000000c001'),
  '14 C1 order: subtotal 4700, discount 450 KEPT, tax round((4700 - 450) x 1700 / 10000) = 723, grand 4973');
select ok((select (r -> 'before' ->> 'tax_total_minor')::bigint = 0 and (r -> 'totals' ->> 'tax_total_minor')::bigint = 723
                  and (r -> 'totals' ->> 'discount_total_minor')::bigint = 450 from t_c1),
  '15 C1 R-008: the stored untaxed 0 is corrected by a WHOLE-order recompute (723, not a 153 delta on the added line)');
select is(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000c001'), 'ok', '16 C1 money identity holds after an ADD');

-- C2 Accepted: Fries x3 4500 (taxed 765 at submit) + Cola 800 added untaxed:
--    stored 5300 / 765 / 6065. Reduce Fries 3 -> 1: 2300, tax 391, 2691 (a
--    delta-adjusted tax would be 765 - 510 = 255).
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000c002', 'accepted');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c2001', 'e4ed0000-0000-0000-0000-00000000c002', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 3, 1500, 4500);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c2002', 'e4ed0000-0000-0000-0000-00000000c002', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000c002', 0, 765);
create temp table t_c2 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c2', 'e4ed0000-0000-0000-0000-00000000c002',
  '{"reason_code": "entry_mistake",
    "expected": {"subtotal_minor": 2300, "tax_total_minor": 391, "grand_total_minor": 2691},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000c2001", "quantity": 1}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_c2)
      and (select subtotal_minor = 2300 and tax_total_minor = 391 and grand_total_minor = 2691
             from orders where id = 'e4ed0000-0000-0000-0000-00000000c002'),
  '17 C2 a REDUCE re-taxes the whole order (391), never by delta (255)');
select is(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000c002'), 'ok', '18 C2 money identity holds after a REDUCE');

-- C3 inclusive mode: refused while tax is enabled; with tax disabled the edit
--    applies with tax 0.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000c003', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c3001', 'e4ed0000-0000-0000-0000-00000000c003', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000c003', 0, 136);
select pg_temp.snap('e4ed0000-0000-0000-0000-00000000c003');
update branches set tax_mode = 'inclusive' where id = 'e4ed0000-0000-0000-0000-0000000000ab';
insert into t_res select 'c3-incl', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c3-x', 'e4ed0000-0000-0000-0000-00000000c003',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 272, "grand_total_minor": 1872},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000c3001", "quantity": 2}]}'::jsonb);
select ok(pg_temp.refused('c3-incl', 'e4ed0000-0000-0000-0000-00000000c003', 'tax_mode_unsupported')
          and exists (select 1 from audit_events where action = 'order.edit_denied'
                       and new_values ->> 'denied_reason' = 'tax_mode_unsupported'
                       and new_values ->> 'order_id' = 'e4ed0000-0000-0000-0000-00000000c003'),
  '19 C3 inclusive + tax enabled: tax_mode_unsupported (audited), nothing written');
update branches set tax_enabled = false where id = 'e4ed0000-0000-0000-0000-0000000000ab';
create temp table t_c3 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c3', 'e4ed0000-0000-0000-0000-00000000c003',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 0, "grand_total_minor": 1600},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000c3001", "quantity": 2}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_c3)
      and (select subtotal_minor = 1600 and tax_total_minor = 0 and grand_total_minor = 1600
             from orders where id = 'e4ed0000-0000-0000-0000-00000000c003')
      and pg_temp.money_check('e4ed0000-0000-0000-0000-00000000c003') = 'ok',
  '20 C3 inclusive + tax DISABLED: the INCREASE applies and the current settings give tax 0');
update branches set tax_enabled = true, tax_mode = 'exclusive' where id = 'e4ed0000-0000-0000-0000-0000000000ab';

-- C4 no tax rate is snapshotted: the order was taxed at 1700 bp; the branch
--    now charges 1800 bp, so the edit re-taxes the WHOLE order at 1800.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000c004', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c4001', 'e4ed0000-0000-0000-0000-00000000c004', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000c004', 0, 136);
update branches set tax_rate_bp = 1800 where id = 'e4ed0000-0000-0000-0000-0000000000ab';
create temp table t_c4 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c4', 'e4ed0000-0000-0000-0000-00000000c004',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 288, "grand_total_minor": 1888},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000c4001", "quantity": 2}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_c4)
      and (select subtotal_minor = 1600 and tax_total_minor = 288 and grand_total_minor = 1888
             from orders where id = 'e4ed0000-0000-0000-0000-00000000c004')
      and pg_temp.money_check('e4ed0000-0000-0000-0000-00000000c004') = 'ok',
  '21 C4 the branch''s CURRENT rate (1800 bp) re-taxes the whole order: 288, not 136 + 136 at the submit rate');
update branches set tax_rate_bp = 1700 where id = 'e4ed0000-0000-0000-0000-0000000000ab';

-- C5 M5 re-roll: the stored subtotal (3000) has drifted from the live lines
--    (3800). The edit RE-ROLLS the subtotal from live lines (4700), never
--    stored + delta (3900).
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000c005', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c5001', 'e4ed0000-0000-0000-0000-00000000c005', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 3000);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000c5002', 'e4ed0000-0000-0000-0000-00000000c005', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
update orders set subtotal_minor = 3000, tax_total_minor = 510, grand_total_minor = 3510
 where id = 'e4ed0000-0000-0000-0000-00000000c005';
create temp table t_c5 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'c5', 'e4ed0000-0000-0000-0000-00000000c005',
  '{"expected": {"subtotal_minor": 4700, "tax_total_minor": 799, "grand_total_minor": 5499},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
      "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and (r -> 'before' ->> 'subtotal_minor')::bigint = 3000 from t_c5)
      and (select subtotal_minor = 4700 and tax_total_minor = 799 and grand_total_minor = 5499
             from orders where id = 'e4ed0000-0000-0000-0000-00000000c005')
      and pg_temp.money_check('e4ed0000-0000-0000-0000-00000000c005') = 'ok',
  '22 C5 M5: the subtotal is RE-ROLLED from the live lines (4700), never the drifted stored 3000 + a 900 delta');

-- ===== D. the absolute order discount (M6) and the zero-out guard (M8) ========
-- D1 In kitchen: Fries x2 3000 + Cola 800 = 3800, discount 2000, tax 306.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000d001', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000d1001', 'e4ed0000-0000-0000-0000-00000000d001', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 3000);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000d1002', 'e4ed0000-0000-0000-0000-00000000d001', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000d001', 2000, 306);
select pg_temp.snap('e4ed0000-0000-0000-0000-00000000d001');
insert into t_res select 'd1-exceeds', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'd1-x', 'e4ed0000-0000-0000-0000-00000000d001',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 0},
    "changes": [{"op": "remove", "order_item_id": "e4ed0000-0000-0000-0000-0000000d1001"}]}'::jsonb);
select ok(pg_temp.refused('d1-exceeds', 'e4ed0000-0000-0000-0000-00000000d001', 'invalid_discount', 'discount_exceeds_order_total'),
  '23 D1 a new subtotal (800) below the kept discount (2000) is invalid_discount / discount_exceeds_order_total; nothing written');
create temp table t_d1 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'd1', 'e4ed0000-0000-0000-0000-00000000d001',
  '{"reason_code": "entry_mistake", "expected": {"subtotal_minor": 2300, "tax_total_minor": 51, "grand_total_minor": 351},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000d1001", "quantity": 1}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_d1)
      and (select subtotal_minor = 2300 and discount_total_minor = 2000 and tax_total_minor = 51 and grand_total_minor = 351
             from orders where id = 'e4ed0000-0000-0000-0000-00000000d001'),
  '24 D1 reduce: discount 2000 KEPT as an absolute amount (not re-derived); tax on 300 = 51; grand 351');
select ok(exists (select 1 from audit_events where action = 'order.edited'
                   and new_values ->> 'order_id' = 'e4ed0000-0000-0000-0000-00000000d001'
                   and (old_values ->> 'discount_ratio_bp')::int = 5263 and (new_values ->> 'discount_ratio_bp')::int = 8696
                   and (old_values ->> 'discount_total_minor')::bigint = 2000 and (new_values ->> 'discount_total_minor')::bigint = 2000
                   and (old_values ->> 'grand_total_minor')::bigint = 2106 and (new_values ->> 'grand_total_minor')::bigint = 351),
  '25 D1 the order.edited audit records the effective discount ratio before (5263 bp) and after (8696 bp) and both totals');
select is(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000d001'), 'ok', '26 D1 money identity holds with a kept discount');

-- D2 In kitchen: Fries 1500 + Cola 800 = 2300, discount 800, tax 255, grand
--    1755. Removing the fries leaves subtotal 800 = discount -> grand 0.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000d002', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000d2001', 'e4ed0000-0000-0000-0000-00000000d002', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000d2002', 'e4ed0000-0000-0000-0000-00000000d002', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000d002', 800, 255);
select pg_temp.snap('e4ed0000-0000-0000-0000-00000000d002');
insert into t_res select 'd2-cashier', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'd2-x', 'e4ed0000-0000-0000-0000-00000000d002',
  '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 0},
    "changes": [{"op": "remove", "order_item_id": "e4ed0000-0000-0000-0000-0000000d2001"}]}'::jsonb);
select ok(pg_temp.refused('d2-cashier', 'e4ed0000-0000-0000-0000-00000000d002', 'permission_denied', 'full_comp_permission_required'),
  '27 D2 a cashier zeroing the order THROUGH the discount is full_comp_permission_required; nothing written');
create temp table t_d2 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009b', 'd2', 'e4ed0000-0000-0000-0000-00000000d002',
  '{"reason_code": "customer_changed_mind", "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 0},
    "changes": [{"op": "remove", "order_item_id": "e4ed0000-0000-0000-0000-0000000d2001"}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_d2)
      and (select subtotal_minor = 800 and discount_total_minor = 800 and tax_total_minor = 0 and grand_total_minor = 0
             from orders where id = 'e4ed0000-0000-0000-0000-00000000d002')
      and pg_temp.money_check('e4ed0000-0000-0000-0000-00000000d002') = 'ok',
  '28 D2 a manager may: a discount EQUAL to the new subtotal is kept (never clamped), grand 0, identity holds after a REMOVE');

-- ===== E. settlement (M10) and editability ===================================
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000f001', 'served');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000f1001', 'e4ed0000-0000-0000-0000-00000000f001', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000f001', 0, 136);
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id,
  resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('e4ed0000-0000-0000-0000-0000000f10a1', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
   'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000f001', 'e4ed0000-0000-0000-0000-0000000000d1',
   'e4ed0000-0000-0000-0000-00000000008a', 'e4ed0000-0000-0000-0000-00000000007a', 'cash', 'completed', 936, 1000, 64, 'ILS', 'pay-f001');
select pg_temp.snap('e4ed0000-0000-0000-0000-00000000f001');
insert into t_res select 'f1-paid', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'f1-x', 'e4ed0000-0000-0000-0000-00000000f001',
  '{"expected": {"subtotal_minor": 1700, "tax_total_minor": 289, "grand_total_minor": 1989},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
      "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);
select ok(pg_temp.refused('f1-paid', 'e4ed0000-0000-0000-0000-00000000f001', 'order_already_settled'),
  '29 F1 a live COMPLETED payment -> order_already_settled; nothing written');
-- F2: only a failed payment and a soft-deleted completed one: not settled.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000f002', 'served');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000f2001', 'e4ed0000-0000-0000-0000-00000000f002', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000f002', 0, 136);
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id,
  resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, deleted_at) values
  ('e4ed0000-0000-0000-0000-0000000f20a1', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
   'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000f002', 'e4ed0000-0000-0000-0000-0000000000d1',
   'e4ed0000-0000-0000-0000-00000000008a', 'e4ed0000-0000-0000-0000-00000000007a', 'cash', 'failed', 936, 936, 0, 'ILS', 'pay-f002-a', null),
  ('e4ed0000-0000-0000-0000-0000000f20a2', 'e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1',
   'e4ed0000-0000-0000-0000-0000000000ab', 'e4ed0000-0000-0000-0000-00000000f002', 'e4ed0000-0000-0000-0000-0000000000d1',
   'e4ed0000-0000-0000-0000-00000000008a', 'e4ed0000-0000-0000-0000-00000000007a', 'cash', 'completed', 936, 936, 0, 'ILS', 'pay-f002-b', now());
create temp table t_f2 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'f2', 'e4ed0000-0000-0000-0000-00000000f002',
  '{"expected": {"subtotal_minor": 1700, "tax_total_minor": 289, "grand_total_minor": 1989},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
      "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_f2)
      and (select grand_total_minor = 1989 from orders where id = 'e4ed0000-0000-0000-0000-00000000f002'),
  '30 F2 a failed and a soft-deleted completed payment are not LIVE completed payments: the edit applies');
-- F3..F6: completed / voided / cancelled / draft orders are not editable.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000f003', 'completed');
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000f004', 'voided');
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000f005', 'cancelled');
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000f006', 'draft');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000f3001', 'e4ed0000-0000-0000-0000-00000000f003', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000f4001', 'e4ed0000-0000-0000-0000-00000000f004', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000f5001', 'e4ed0000-0000-0000-0000-00000000f005', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000f6001', 'e4ed0000-0000-0000-0000-00000000f006', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle(x.id, 0, 136) from (values ('e4ed0000-0000-0000-0000-00000000f003'::uuid), ('e4ed0000-0000-0000-0000-00000000f004'),
  ('e4ed0000-0000-0000-0000-00000000f005'), ('e4ed0000-0000-0000-0000-00000000f006')) x(id);
select pg_temp.snap(x.id) from (values ('e4ed0000-0000-0000-0000-00000000f003'::uuid), ('e4ed0000-0000-0000-0000-00000000f004'),
  ('e4ed0000-0000-0000-0000-00000000f005'), ('e4ed0000-0000-0000-0000-00000000f006')) x(id);
insert into t_res select 'f' || x.n, pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'f-x' || x.n, x.id,
  jsonb_build_object('expected', '{"subtotal_minor": 1600, "tax_total_minor": 272, "grand_total_minor": 1872}'::jsonb,
                     'changes', jsonb_build_array(jsonb_build_object('op', 'set_quantity', 'order_item_id', x.item, 'quantity', 2))))
  from (values (3, 'e4ed0000-0000-0000-0000-00000000f003'::uuid, 'e4ed0000-0000-0000-0000-0000000f3001'::uuid),
               (4, 'e4ed0000-0000-0000-0000-00000000f004', 'e4ed0000-0000-0000-0000-0000000f4001'),
               (5, 'e4ed0000-0000-0000-0000-00000000f005', 'e4ed0000-0000-0000-0000-0000000f5001'),
               (6, 'e4ed0000-0000-0000-0000-00000000f006', 'e4ed0000-0000-0000-0000-0000000f6001')) x(n, id, item);
select ok(pg_temp.refused('f3', 'e4ed0000-0000-0000-0000-00000000f003', 'order_not_editable'),
  '31 a COMPLETED order is order_not_editable; nothing written');
select ok(pg_temp.refused('f4', 'e4ed0000-0000-0000-0000-00000000f004', 'order_not_editable'),
  '32 a VOIDED order is order_not_editable; nothing written');
select ok(pg_temp.refused('f5', 'e4ed0000-0000-0000-0000-00000000f005', 'order_not_editable'),
  '33 a CANCELLED order is order_not_editable; nothing written');
select ok(pg_temp.refused('f6', 'e4ed0000-0000-0000-0000-00000000f006', 'order_not_editable'),
  '34 a DRAFT order is order_not_editable; nothing written');

-- ===== F. snapshots copied server-side after the live menu moved (D-008) ======
-- S1 In kitchen (placed under the ORIGINAL menu):
--   a1001 Burger Large/Brioche x2, unit 4500, +tomato 0 +bacon 400 (meat 50 g,
--         classifier cheese = false), prep Patty(cheese=false) + Bun -> 9800
--   a1002 Fries x3, +ketchup 100 -> 4800
--   a1003 Cola x1, +lemon 50 -> 850                       subtotal 15450
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000a001', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a1001', 'e4ed0000-0000-0000-0000-00000000a001', 'e4ed0000-0000-0000-0000-000000001001', 'Burger', 2, 4500, 9800,
  'no salt',
  '[{"name": "Patty", "quantity": 180, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "classifier_option_name": "cheese", "classifier_selected": false},
    {"name": "Bun", "quantity": 1, "unit": "pc"}]',
  '{"name": "Large"}', '{"name": "Brioche"}');
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a1001', 'e4ed0000-0000-0000-0000-00000000e001', 'Extras', 'tomato', 0);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a1001', 'e4ed0000-0000-0000-0000-00000000e004', 'Meat', 'bacon', 400,
  '{"quantity": 50, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "classifier_option_name": "cheese", "classifier_selected": false}');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a1002', 'e4ed0000-0000-0000-0000-00000000a001', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 3, 1500, 4800,
  'extra salt', '[{"name": "Potato", "quantity": 200, "unit": "g"}]', '{"name": "Large"}', null);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a1002', 'e4ed0000-0000-0000-0000-00000000e005', 'Sauce', 'ketchup', 100,
  '{"quantity": 15, "unit": "ml"}');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a1003', 'e4ed0000-0000-0000-0000-00000000a001', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 850,
  'no ice', null, null, '{"name": "Zero"}');
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a1003', 'e4ed0000-0000-0000-0000-00000000e006', 'Garnish', 'lemon', 50);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000a001', 0, 2627);

select ok((select bool_and(case id
                    when 'e4ed0000-0000-0000-0000-0000000a1001' then item_display_order_snapshot = 1 and category_display_order_snapshot = 1 and line_position = 1
                    when 'e4ed0000-0000-0000-0000-0000000a1002' then item_display_order_snapshot = 2 and category_display_order_snapshot = 1 and line_position = 2
                    when 'e4ed0000-0000-0000-0000-0000000a1003' then item_display_order_snapshot = 1 and category_display_order_snapshot = 2 and line_position = 3 end)
             from order_items where order_id = 'e4ed0000-0000-0000-0000-00000000a001')
      and (select bool_and(case modifier_option_id
                    when 'e4ed0000-0000-0000-0000-00000000e001' then modifier_group_display_order_snapshot = 1 and modifier_option_display_order_snapshot = 1
                    when 'e4ed0000-0000-0000-0000-00000000e004' then modifier_group_display_order_snapshot = 2 and modifier_option_display_order_snapshot = 1
                    else modifier_group_display_order_snapshot = 1 and modifier_option_display_order_snapshot = 1 end)
             from order_item_modifiers m join order_items i on i.id = m.order_item_id
            where i.order_id = 'e4ed0000-0000-0000-0000-00000000a001'),
  '35 precondition: S1 rows carry the ORDER-TIME menu ranks (Burger 1/1, Fries 2/1, Cola 1/2; tomato 1/1, bacon 2/1)');

-- S2 READY (also placed under the original menu): Burger x1 unit 4000
-- +tomato 0 +bacon 400 = 4400; Cola x1 (Zero, 'no ice') +lemon 50 = 850.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000a003', 'ready');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a3001', 'e4ed0000-0000-0000-0000-00000000a003', 'e4ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4400);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a3001', 'e4ed0000-0000-0000-0000-00000000e001', 'Extras', 'tomato', 0);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a3001', 'e4ed0000-0000-0000-0000-00000000e004', 'Meat', 'bacon', 400,
  '{"quantity": 50, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "classifier_option_name": "cheese", "classifier_selected": false}');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a3002', 'e4ed0000-0000-0000-0000-00000000a003', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 850,
  'no ice', null, null, '{"name": "Zero"}');
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a3002', 'e4ed0000-0000-0000-0000-00000000e006', 'Garnish', 'lemon', 50);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000a003', 0, 893);

-- The LIVE menu moves after the orders were placed (the sanctioned reorder
-- gate), prices and names change, and the live prep / meat configuration
-- changes.
set local app.menu_reordering to 'on';
update menu_categories set display_order = 5 where id = 'e4ed0000-0000-0000-0000-0000000000c1';
update menu_categories set display_order = 6 where id = 'e4ed0000-0000-0000-0000-0000000000c2';
update menu_items set display_order = 7 where id = 'e4ed0000-0000-0000-0000-000000001001';
update menu_items set display_order = 8 where id = 'e4ed0000-0000-0000-0000-000000001002';
update menu_items set display_order = 9 where id = 'e4ed0000-0000-0000-0000-000000001003';
update menu_items set display_order = 4 where id = 'e4ed0000-0000-0000-0000-000000001004';
update modifiers set display_order = 3 where id = 'e4ed0000-0000-0000-0000-00000000d101';
update modifiers set display_order = 4 where id = 'e4ed0000-0000-0000-0000-00000000d102';
update modifiers set display_order = 8 where id = 'e4ed0000-0000-0000-0000-00000000d103';
update modifiers set display_order = 10 where id = 'e4ed0000-0000-0000-0000-00000000d104';
update modifier_options set display_order = 6 where id = 'e4ed0000-0000-0000-0000-00000000e001';
update modifier_options set display_order = 7 where id = 'e4ed0000-0000-0000-0000-00000000e003';
update modifier_options set display_order = 5 where id = 'e4ed0000-0000-0000-0000-00000000e004';
update modifier_options set display_order = 9 where id = 'e4ed0000-0000-0000-0000-00000000e005';
update modifier_options set display_order = 11 where id = 'e4ed0000-0000-0000-0000-00000000e006';
set local app.menu_reordering to 'off';
update menu_items set base_price_minor = 4800 where id = 'e4ed0000-0000-0000-0000-000000001001';
update menu_items set base_price_minor = 1700 where id = 'e4ed0000-0000-0000-0000-000000001002';
update menu_items set base_price_minor = 1000 where id = 'e4ed0000-0000-0000-0000-000000001003';
update modifier_options set price_delta_minor = 50  where id = 'e4ed0000-0000-0000-0000-00000000e001';
update modifier_options set price_delta_minor = 350 where id = 'e4ed0000-0000-0000-0000-00000000e003';
update modifier_options set price_delta_minor = 600, kitchen_meat = '{"quantity": 80, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003"}'
  where id = 'e4ed0000-0000-0000-0000-00000000e004';
update modifier_options set price_delta_minor = 150 where id = 'e4ed0000-0000-0000-0000-00000000e005';
update modifier_options set price_delta_minor = 70  where id = 'e4ed0000-0000-0000-0000-00000000e006';
update menu_items set attributes = '{"prep_components": [{"name": "Patty", "quantity": 200, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003"}]}'
  where id = 'e4ed0000-0000-0000-0000-000000001001';
update menu_items set name = 'Chips' where id = 'e4ed0000-0000-0000-0000-000000001002';
update menu_items set name = 'Coke' where id = 'e4ed0000-0000-0000-0000-000000001003';
update modifier_options set name = 'Tomato sauce' where id = 'e4ed0000-0000-0000-0000-00000000e005';
update modifier_options set name = 'Streaky bacon' where id = 'e4ed0000-0000-0000-0000-00000000e004';

create temp table t_s1_pre as
  select id, status, quantity, line_total_minor, unit_price_minor_snapshot from order_items
   where order_id = 'e4ed0000-0000-0000-0000-00000000a001';

-- Edit 1 (cashier, In kitchen):
--   Fries 3 -> 2 (remainder 2 x 1600 = 3200), Cola 1 -> 3 (+2 delta x 850 =
--   1700), Burger split: 1 continuation (tomato, bacon; kept bacon sent with
--   the LIVE price and a new name, both ignored) = 4900 + 1 replacement adding
--   cheese at 350 (meat 20 g, the trusted snapshot) = 5250, + Lemonade 900.
--   subtotal 16800, tax 2856, grand 19656.
create temp table t_s1 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 's1', 'e4ed0000-0000-0000-0000-00000000a001',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 16800, "tax_total_minor": 2856, "grand_total_minor": 19656},
    "changes": [
      {"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000a1002", "quantity": 2},
      {"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000a1003", "quantity": 3},
      {"op": "modify", "order_item_id": "e4ed0000-0000-0000-0000-0000000a1001", "replacements": [
        {"quantity": 1, "notes": "no salt", "modifiers": [
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"},
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e004", "option_name_snapshot": "Bacon NEW", "price_minor_snapshot": 600}]},
        {"quantity": 1, "notes": "extra crispy", "modifiers": [
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"},
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e004"},
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "modifier_name_snapshot": "Extras",
           "option_name_snapshot": "cheese", "price_minor_snapshot": 350, "meat_snapshot": {"quantity": 20, "unit": "g"}}]}]},
      {"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;
-- the rows the edit wrote, by role
create temp view v_s1 as
  select n.*,
         case when n.replaces_order_item_id = 'e4ed0000-0000-0000-0000-0000000a1002' then 'remainder'
              when n.menu_item_id = 'e4ed0000-0000-0000-0000-000000001003' then 'delta'
              when n.replaces_order_item_id = 'e4ed0000-0000-0000-0000-0000000a1001'
                   and not exists (select 1 from order_item_modifiers m where m.order_item_id = n.id
                                     and m.modifier_option_id = 'e4ed0000-0000-0000-0000-00000000e003') then 'continuation'
              when n.replaces_order_item_id = 'e4ed0000-0000-0000-0000-0000000a1001' then 'replacement'
              when n.menu_item_id = 'e4ed0000-0000-0000-0000-000000001004' then 'added' end as role
    from order_items n
   where n.order_id = 'e4ed0000-0000-0000-0000-00000000a001'
     and n.edit_id = (select (r ->> 'order_edit_id')::uuid from t_s1);
create temp view v_s1_mods as
  select v.role, m.* from v_s1 v join order_item_modifiers m on m.order_item_id = v.id;

select ok((select r ->> 'status' = 'applied' and (r ->> 'kitchen_ack_required')::boolean
                  and (r ->> 'new_round_number')::int = 2 from t_s1)
      and (select string_agg(role, ',' order by role) from v_s1) = 'added,continuation,delta,remainder,replacement',
  '36 S1 applied: five rows written (remainder, delta, continuation, replacement, added)');
select ok((select count(*) = 1 and bool_and(n.quantity = 2 and n.item_display_order_snapshot = 2 and n.category_display_order_snapshot = 1
                  and n.line_position = 2 and n.unit_price_minor_snapshot = 1500 and n.line_total_minor = 3200
                  and n.line_discount_minor = 0 and n.service_round_id is null and n.status = 'pending'
                  and n.menu_item_name_snapshot = 'Fries' and n.item_size_snapshot = '{"name": "Large"}'::jsonb
                  and n.notes = 'extra salt' and n.prep_snapshot = o.prep_snapshot)
             from v_s1 n join order_items o on o.id = 'e4ed0000-0000-0000-0000-0000000a1002' where n.role = 'remainder'),
  '37 S1 reduce remainder: OLD ranks (2/1, not live 8/5), old line_position 2, OLD price 1500 (live 1700), name / size / note / prep copied');
select ok((select count(*) = 1 and bool_and(modifier_group_display_order_snapshot = 1 and modifier_option_display_order_snapshot = 1
                  and price_minor_snapshot = 100 and option_name_snapshot = 'ketchup' and modifier_name_snapshot = 'Sauce'
                  and meat_snapshot = '{"quantity": 15, "unit": "ml"}'::jsonb)
             from v_s1_mods where role = 'remainder'),
  '38 S1 remainder kept ketchup: OLD ranks (1/1, not live 8/9), OLD price 100 (live 150), OLD name, frozen meat copied');
select ok((select count(*) = 1 and bool_and(quantity = 2 and replaces_order_item_id is null and item_display_order_snapshot = 1
                  and category_display_order_snapshot = 2 and line_position = 3 and unit_price_minor_snapshot = 800
                  and line_total_minor = 1700 and service_round_id is null and menu_item_name_snapshot = 'Cola'
                  and item_variant_snapshot = '{"name": "Zero"}'::jsonb and notes = 'no ice')
             from v_s1 where role = 'delta')
      and (select count(*) = 1 and bool_and(modifier_group_display_order_snapshot = 1 and modifier_option_display_order_snapshot = 1
                  and price_minor_snapshot = 50 and option_name_snapshot = 'lemon')
             from v_s1_mods where role = 'delta'),
  '39 S1 increase delta (+2, no replaces): OLD ranks 1/2 (live 9/6), old line_position 3, OLD prices 800 + lemon 50, name / variant / note copied');
select ok((select count(*) = 1 and bool_and(n.quantity = 1 and n.item_display_order_snapshot = 1 and n.category_display_order_snapshot = 1
                  and n.line_position = 1 and n.unit_price_minor_snapshot = 4500 and n.line_total_minor = 4900
                  and n.item_size_snapshot = o.item_size_snapshot and n.item_variant_snapshot = o.item_variant_snapshot
                  and n.menu_item_name_snapshot = 'Burger' and n.notes = 'no salt' and n.service_round_id is null)
             from v_s1 n join order_items o on o.id = 'e4ed0000-0000-0000-0000-0000000a1001'
            where n.role = 'continuation'),
  '40 S1 modify continuation: OLD ranks 1/1 (live 7/5), old line_position, base 4500 (live 4800), size/variant/name copied');
select ok((select count(*) = 2 and bool_and(case option_name_snapshot
                    when 'tomato' then modifier_group_display_order_snapshot = 1 and modifier_option_display_order_snapshot = 1
                                       and price_minor_snapshot = 0 and modifier_name_snapshot = 'Extras'
                    when 'bacon'  then modifier_group_display_order_snapshot = 2 and modifier_option_display_order_snapshot = 1
                                       and price_minor_snapshot = 400 and modifier_name_snapshot = 'Meat'
                                       and (meat_snapshot ->> 'quantity')::int = 50 end)
             from v_s1_mods where role = 'continuation'),
  '41 S1 continuation kept options: OLD ranks, OLD prices (bacon 400 although the client sent 600), OLD names, frozen meat 50 g');
select ok((select count(*) = 1 and bool_and(n.quantity = 1 and n.item_display_order_snapshot = 1 and n.category_display_order_snapshot = 1
                  and n.line_position = 1 and n.unit_price_minor_snapshot = 4500 and n.line_total_minor = 5250
                  and n.item_size_snapshot = o.item_size_snapshot and n.item_variant_snapshot = o.item_variant_snapshot
                  and n.notes = 'extra crispy' and n.service_round_id is null and n.line_discount_minor = 0)
             from v_s1 n join order_items o on o.id = 'e4ed0000-0000-0000-0000-0000000a1001'
            where n.role = 'replacement'),
  '42 S1 modify replacement: OLD item ranks, old line_position, base / size / variant copied, priced 4500 + 0 + 400 + 350');
select ok((select count(*) = 3 and bool_and(case option_name_snapshot
                    when 'tomato' then modifier_group_display_order_snapshot = 1 and modifier_option_display_order_snapshot = 1 and price_minor_snapshot = 0
                    when 'bacon'  then modifier_group_display_order_snapshot = 2 and modifier_option_display_order_snapshot = 1 and price_minor_snapshot = 400
                    when 'cheese' then modifier_group_display_order_snapshot = 3 and modifier_option_display_order_snapshot = 7
                                       and price_minor_snapshot = 350 and modifier_name_snapshot = 'Extras'
                                       and meat_snapshot = '{"quantity": 20, "unit": "g"}'::jsonb end)
             from v_s1_mods where role = 'replacement'),
  '43 S1 replacement: kept tomato/bacon keep the OLD ranks; the NEW cheese carries the LIVE ranks 3/7 and its client snapshot');
select ok((select count(*) = 1 and bool_and(n.item_display_order_snapshot = 4 and n.category_display_order_snapshot = 6
                  and n.line_position > 3 and n.replaces_order_item_id is null and n.unit_price_minor_snapshot = 900
                  and n.line_total_minor = 900 and n.service_round_id = (select (r ->> 'new_round_id')::uuid from t_s1))
             from v_s1 n where n.role = 'added'),
  '44 S1 an ADDED line carries the LIVE ranks 4/6 and a trigger-assigned line_position (into the edit''s round)');
select ok((select prep_snapshot = '[{"name": "Patty", "quantity": 180, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "classifier_option_name": "cheese", "classifier_selected": true},
                                    {"name": "Bun", "quantity": 1, "unit": "pc"}]'::jsonb
             from v_s1 where role = 'replacement')
      and (select meat_snapshot = '{"quantity": 50, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "classifier_option_name": "cheese", "classifier_selected": true}'::jsonb
             from v_s1_mods where role = 'replacement' and option_name_snapshot = 'bacon'),
  '45 S1 adding cheese re-answers classifier_selected TRUE in the item prep_snapshot AND the kept bacon meat_snapshot (frozen 180 g / 50 g kept)');
select ok((select n.prep_snapshot = o.prep_snapshot from v_s1 n, order_items o
            where n.role = 'continuation' and o.id = 'e4ed0000-0000-0000-0000-0000000a1001')
      and (select (meat_snapshot ->> 'classifier_selected')::boolean = false from v_s1_mods where role = 'continuation' and option_name_snapshot = 'bacon'),
  '46 S1 the continuation (no cheese) keeps classifier_selected FALSE (prep copied unchanged)');
select ok((select bool_and(case p.id
                    when 'e4ed0000-0000-0000-0000-0000000a1001' then n.status = 'voided' and n.removed_by_edit_id is not null
                    when 'e4ed0000-0000-0000-0000-0000000a1002' then n.status = 'voided' and n.removed_by_edit_id is not null
                    else n.status = 'pending' and n.removed_by_edit_id is null end
                  and n.quantity = p.quantity and n.line_total_minor = p.line_total_minor
                  and n.unit_price_minor_snapshot = p.unit_price_minor_snapshot)
             from t_s1_pre p join order_items n on n.id = p.id),
  '47 S1 retired lines (burger 9800, fries 4800) keep their rows and amounts; the increased cola line is kept untouched');
select ok((select subtotal_minor = 16800 and tax_total_minor = 2856 and grand_total_minor = 19656
             from orders where id = 'e4ed0000-0000-0000-0000-00000000a001'),
  '48 S1 order totals 16800 / 2856 / 19656');
select is(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000a001'), 'ok',
  '49 S1 money identity holds after a mixed reduce / increase / modify / add edit');
select is(pg_temp.m13('e4ed0000-0000-0000-0000-00000000a001'),
  '{"removed_minor": 0, "replaced_out_minor": 14600, "replaced_in_minor": 13350, "added_minor": 2600, "net_change_minor": 1350}'::jsonb,
  '50 S1 M13 classification: replaced_out 14600, replaced_in 13350, added 2600 (delta + lemonade), net +1350 = 16800 - 15450');
select is((select jsonb_agg(jsonb_build_array(c ->> 'kind', c -> 'before_quantity', c -> 'after_quantity',
                                              c -> 'before_total_minor', c -> 'after_total_minor') order by o)
             from audit_events a, jsonb_array_elements(a.new_values -> 'changes') with ordinality x(c, o)
            where a.action = 'order.edited' and a.new_values ->> 'order_edit_id' = (select r ->> 'order_edit_id' from t_s1)),
  '[["set_quantity", 3, 2, 4800, 3200], ["set_quantity", 1, 3, 850, 2550], ["modify", 2, 2, 9800, 10150], ["add", null, 1, null, 900]]'::jsonb,
  '51 S1 the order.edited audit carries the per-line before / after quantities and totals');

-- Edit 2: the cheese replacement is modified again WITHOUT cheese -> the
-- classifier flips back; the kept ranks still come from the original order.
-- subtotal 16800 - 5250 + 4900 = 16450, tax 2796.5 -> 2797, grand 19247.
create temp table t_s1b as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 's1b', 'e4ed0000-0000-0000-0000-00000000a001',
  jsonb_build_object(
    'reason_code', 'customer_changed_mind',
    'expected', '{"subtotal_minor": 16450, "tax_total_minor": 2797, "grand_total_minor": 19247}'::jsonb,
    'changes', jsonb_build_array(jsonb_build_object(
      'op', 'modify', 'order_item_id', (select id from v_s1 where role = 'replacement'),
      'replacements', '[{"quantity": 1, "notes": "extra crispy", "modifiers": [
                          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"},
                          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e004"}]}]'::jsonb)))) as r;
select ok((select r ->> 'status' = 'applied' from t_s1b)
      and (select count(*) = 1 and bool_and(n.line_total_minor = 4900 and n.unit_price_minor_snapshot = 4500
                  and n.item_display_order_snapshot = 1 and n.category_display_order_snapshot = 1
                  and n.prep_snapshot -> 0 ->> 'classifier_selected' = 'false'
                  and (n.prep_snapshot -> 0 ->> 'quantity')::int = 180)
             from order_items n where n.replaces_order_item_id = (select id from v_s1 where role = 'replacement'))
      and (select count(*) = 2 and bool_and(case m.option_name_snapshot
                    when 'tomato' then m.modifier_group_display_order_snapshot = 1 and m.modifier_option_display_order_snapshot = 1
                    when 'bacon'  then m.modifier_group_display_order_snapshot = 2 and m.modifier_option_display_order_snapshot = 1
                                       and m.price_minor_snapshot = 400
                                       and m.meat_snapshot ->> 'classifier_selected' = 'false' end)
             from order_items n join order_item_modifiers m on m.order_item_id = n.id
            where n.replaces_order_item_id = (select id from v_s1 where role = 'replacement')),
  '52 S1 edit 2 removing cheese flips classifier_selected back to FALSE; old ranks and prices survive the chain');
select ok(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000a001') = 'ok'
      and (select subtotal_minor = 16450 and tax_total_minor = 2797 and grand_total_minor = 19247
             from orders where id = 'e4ed0000-0000-0000-0000-00000000a001'),
  '53 S1 edit 2 money: 16450, tax 2796.5 -> 2797 (half away), 19247; identity holds after a MODIFY');

-- S2 (Ready unit): the burger modify only DOUBLES the kept bacon (a changed
-- replacement -> REMAKE in the edit's round, priced 4000 + 2 x OLD 400 = 4800),
-- Cola 1 -> 2 (+1 in the edit's round, 850), and an ADD of Burger x2 with
-- cheese 350 and bacon x2 at the live 600: 2 x (4800 + 350 + 1200) = 12700.
-- subtotal 4800 + 850 + 850 + 12700 = 19200, tax 3264, grand 22464.
create temp table t_s2 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 's2', 'e4ed0000-0000-0000-0000-00000000a003',
  '{"reason_code": "kitchen_issue",
    "expected": {"subtotal_minor": 19200, "tax_total_minor": 3264, "grand_total_minor": 22464},
    "changes": [
      {"op": "modify", "order_item_id": "e4ed0000-0000-0000-0000-0000000a3001", "replacements": [
        {"quantity": 1, "modifiers": [{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"},
                                      {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e004", "quantity": 2}]}]},
      {"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000a3002", "quantity": 2},
      {"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001001", "quantity": 2,
        "unit_price_minor_snapshot": 4800, "menu_item_name_snapshot": "Burger", "modifiers": [
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "modifier_name_snapshot": "Extras",
           "option_name_snapshot": "cheese", "price_minor_snapshot": 350, "meat_snapshot": {"quantity": 20, "unit": "g"}},
          {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e004", "modifier_name_snapshot": "Meat",
           "option_name_snapshot": "Streaky bacon", "price_minor_snapshot": 600, "quantity": 2,
           "meat_snapshot": {"quantity": 80, "unit": "g", "classifier_option_id": "e4ed0000-0000-0000-0000-00000000e003",
                             "classifier_option_name": "cheese", "classifier_selected": true}}]}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'new_round_number')::int = 2
                  and (r -> 'changes' -> 0 ->> 'remake')::boolean and r -> 'changes' -> 0 ->> 'landing' = 'edit_round'
                  and r -> 'changes' -> 1 ->> 'landing' = 'edit_round' from t_s2),
  '54 S2 applied on a Ready unit: the changed replacement is a REMAKE in the edit''s round, the +1 lands there too');
select ok((select count(*) = 1 and bool_and(n.service_round_id = (select (r ->> 'new_round_id')::uuid from t_s2)
                  and n.item_display_order_snapshot = 1 and n.category_display_order_snapshot = 1
                  and n.unit_price_minor_snapshot = 4000 and n.line_total_minor = 4800 and n.line_discount_minor = 0)
             from order_items n where n.replaces_order_item_id = 'e4ed0000-0000-0000-0000-0000000a3001')
      and (select count(*) = 2 and bool_and(case m.option_name_snapshot
                    when 'tomato' then m.modifier_group_display_order_snapshot = 1 and m.modifier_option_display_order_snapshot = 1
                    when 'bacon'  then m.modifier_group_display_order_snapshot = 2 and m.modifier_option_display_order_snapshot = 1
                                       and m.quantity = 2 and m.price_minor_snapshot = 400 end)
             from order_items n join order_item_modifiers m on m.order_item_id = n.id
            where n.replaces_order_item_id = 'e4ed0000-0000-0000-0000-0000000a3001'),
  '55 S2 the REMAKE row (edit''s round) keeps the OLD ranks and base 4000; the kept bacon x2 is priced at its OLD 400 per unit');
select ok((select count(*) = 1 and bool_and(n.quantity = 1 and n.replaces_order_item_id is null
                  and n.service_round_id = (select (r ->> 'new_round_id')::uuid from t_s2)
                  and n.item_display_order_snapshot = 1 and n.category_display_order_snapshot = 2
                  and n.unit_price_minor_snapshot = 800 and n.line_total_minor = 850
                  and n.item_variant_snapshot = '{"name": "Zero"}'::jsonb and n.notes = 'no ice'
                  and n.menu_item_name_snapshot = 'Cola')
             from order_items n where n.order_id = 'e4ed0000-0000-0000-0000-00000000a003'
              and n.edit_id is not null and n.menu_item_id = 'e4ed0000-0000-0000-0000-000000001003'),
  '56 S2 the +1 delta in the edit''s round still carries the OLD ranks 1/2, price, variant, note and name');
select ok((select count(*) = 1 and bool_and(n.item_display_order_snapshot = 7 and n.category_display_order_snapshot = 5
                  and n.line_total_minor = 12700 and n.unit_price_minor_snapshot = 4800 and n.replaces_order_item_id is null)
             from order_items n where n.order_id = 'e4ed0000-0000-0000-0000-00000000a003'
              and n.edit_id is not null and n.menu_item_id = 'e4ed0000-0000-0000-0000-000000001001'
              and n.replaces_order_item_id is null)
      and (select count(*) = 2 and bool_and(case m.modifier_option_id
                    when 'e4ed0000-0000-0000-0000-00000000e003' then m.modifier_group_display_order_snapshot = 3
                         and m.modifier_option_display_order_snapshot = 7 and m.meat_snapshot = '{"quantity": 20, "unit": "g"}'::jsonb
                    when 'e4ed0000-0000-0000-0000-00000000e004' then m.modifier_group_display_order_snapshot = 4
                         and m.modifier_option_display_order_snapshot = 5 and m.quantity = 2 and m.price_minor_snapshot = 600
                         and m.meat_snapshot = app.trusted_modifier_prep_snapshot('e4ed0000-0000-0000-0000-0000000000a0',
                               'e4ed0000-0000-0000-0000-000000001001', 'e4ed0000-0000-0000-0000-00000000e004',
                               '[{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003"}, {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e004"}]'::jsonb) end)
             from order_items n join order_item_modifiers m on m.order_item_id = n.id
            where n.order_id = 'e4ed0000-0000-0000-0000-00000000a003' and n.edit_id is not null
              and n.menu_item_id = 'e4ed0000-0000-0000-0000-000000001001' and n.replaces_order_item_id is null),
  '57 S2 the ADDED burger: LIVE ranks (item 7/5, cheese 3/7, bacon 4/5), per-unit 2 x (4800 + 350 + 2 x 600) = 12700, trusted meat');
select ok(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000a003') = 'ok'
      and (select subtotal_minor = 19200 and tax_total_minor = 3264 and grand_total_minor = 22464
             from orders where id = 'e4ed0000-0000-0000-0000-00000000a003')
      and pg_temp.m13('e4ed0000-0000-0000-0000-00000000a003') =
          '{"removed_minor": 0, "replaced_out_minor": 4400, "replaced_in_minor": 4800, "added_minor": 13550, "net_change_minor": 13950}'::jsonb,
  '58 S2 money identity + M13 (replaced 4400 -> 4800, added 850 + 12700, net +13950 = 19200 - 5250)');

-- ===== G. new-option and sellability validation (nothing written) ============
-- V1 In kitchen: Burger x1 4000 +tomato; Fries x2 (1500 + ketchup 100) 3200.
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000b001', 'preparing');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000b1001', 'e4ed0000-0000-0000-0000-00000000b001', 'e4ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000b1001', 'e4ed0000-0000-0000-0000-00000000e001', 'Extras', 'tomato', 0);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000b1002', 'e4ed0000-0000-0000-0000-00000000b001', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 3200);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000b1002', 'e4ed0000-0000-0000-0000-00000000e005', 'Sauce', 'ketchup', 100);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000b001', 0, 1224);
select pg_temp.snap('e4ed0000-0000-0000-0000-00000000b001');
-- a modify of the burger that adds ONE new option p_new
create function pg_temp.vmod(p_new jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'reason_code', 'customer_changed_mind',
    'expected', '{"subtotal_minor": 0, "tax_total_minor": 0, "grand_total_minor": 0}'::jsonb,
    'changes', jsonb_build_array(jsonb_build_object(
      'op', 'modify', 'order_item_id', 'e4ed0000-0000-0000-0000-0000000b1001',
      'replacements', jsonb_build_array(jsonb_build_object('quantity', 1, 'modifiers', jsonb_build_array(
        '{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"}'::jsonb, p_new))))));
$$;
insert into t_res select 'g-foreign', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g1', 'e4ed0000-0000-0000-0000-00000000b001',
  pg_temp.vmod('{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e005", "option_name_snapshot": "ketchup", "price_minor_snapshot": 150}'));
insert into t_res select 'g-random', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g2', 'e4ed0000-0000-0000-0000-00000000b001',
  pg_temp.vmod('{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000beef", "option_name_snapshot": "ghost", "price_minor_snapshot": 0}'));
insert into t_res select 'g-noname', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g3', 'e4ed0000-0000-0000-0000-00000000b001',
  pg_temp.vmod('{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "price_minor_snapshot": 350, "meat_snapshot": {"quantity": 20, "unit": "g"}}'));
insert into t_res select 'g-noprice', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g4', 'e4ed0000-0000-0000-0000-00000000b001',
  pg_temp.vmod('{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "option_name_snapshot": "cheese", "meat_snapshot": {"quantity": 20, "unit": "g"}}'));
insert into t_res select 'g-stale', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g5', 'e4ed0000-0000-0000-0000-00000000b001',
  pg_temp.vmod('{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "option_name_snapshot": "cheese", "price_minor_snapshot": 350, "meat_snapshot": {"quantity": 30, "unit": "g"}}'));
insert into t_res select 'g-nomeat', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g6', 'e4ed0000-0000-0000-0000-00000000b001',
  pg_temp.vmod('{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e003", "option_name_snapshot": "cheese", "price_minor_snapshot": 350}'));
select ok(pg_temp.refused('g-foreign', 'e4ed0000-0000-0000-0000-00000000b001', 'modifier_option_not_in_scope')
          and (select r -> 'modifiers' = '[{"menu_item_id": "e4ed0000-0000-0000-0000-000000001001", "option_name_snapshot": "ketchup"}]'::jsonb
                 from t_res where k = 'g-foreign'),
  '59 a new option of ANOTHER menu item (fries ketchup on the burger) is modifier_option_not_in_scope; nothing written');
select ok(pg_temp.refused('g-random', 'e4ed0000-0000-0000-0000-00000000b001', 'modifier_option_not_in_scope'),
  '60 a nonexistent option id is the SAME modifier_option_not_in_scope; nothing written');
select ok(pg_temp.refused('g-noname', 'e4ed0000-0000-0000-0000-00000000b001', 'invalid_item_payload', 'option_name_snapshot_required'),
  '61 a new option without option_name_snapshot is invalid_item_payload; nothing written');
select ok(pg_temp.refused('g-noprice', 'e4ed0000-0000-0000-0000-00000000b001', 'invalid_item_payload', 'price_minor_snapshot_required'),
  '62 a new option without a price is invalid_item_payload; nothing written');
select ok(pg_temp.refused('g-stale', 'e4ed0000-0000-0000-0000-00000000b001', 'modifier_prep_snapshot_stale')
          and (select r -> 'modifiers' = '[{"menu_item_id": "e4ed0000-0000-0000-0000-000000001001", "option_name_snapshot": "cheese"}]'::jsonb
                 from t_res where k = 'g-stale'),
  '63 a new option whose client meat_snapshot differs from the menu (30 g vs 20 g) is modifier_prep_snapshot_stale; nothing written');
select ok(pg_temp.refused('g-nomeat', 'e4ed0000-0000-0000-0000-00000000b001', 'modifier_prep_snapshot_stale'),
  '64 a new option sent WITHOUT the meat_snapshot its menu row configures is modifier_prep_snapshot_stale; nothing written');
insert into t_res select 'g-linedisc', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g9', 'e4ed0000-0000-0000-0000-00000000b001',
  '{"expected": {"subtotal_minor": 8000, "tax_total_minor": 1360, "grand_total_minor": 9360},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
      "unit_price_minor_snapshot": 900, "line_discount_minor": 100, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb);
select ok(pg_temp.refused('g-linedisc', 'e4ed0000-0000-0000-0000-00000000b001', 'invalid_item_payload', 'line_discount_not_allowed'),
  '65 an ADD carrying a line discount is invalid_item_payload / line_discount_not_allowed (M4: item discount 0); nothing written');
-- sellability: Salad sold out; then Fries paused.
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab',
   'e4ed0000-0000-0000-0000-000000001005', 'unavailable', 'sold_out');
insert into t_res select 'g-add-unavail', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g7', 'e4ed0000-0000-0000-0000-00000000b001',
  '{"expected": {"subtotal_minor": 9200, "tax_total_minor": 1564, "grand_total_minor": 10764},
    "changes": [{"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001005", "quantity": 1,
      "unit_price_minor_snapshot": 2000, "menu_item_name_snapshot": "Salad", "modifiers": []}}]}'::jsonb);
select ok(pg_temp.refused('g-add-unavail', 'e4ed0000-0000-0000-0000-00000000b001', 'item_unavailable')
          and (select r -> 'items' -> 0 ->> 'menu_item_id' = 'e4ed0000-0000-0000-0000-000000001005'
                      and r -> 'items' -> 0 ->> 'reason' = 'sold_out' from t_res where k = 'g-add-unavail'),
  '66 an ADD of an unavailable (sold out) item is item_unavailable; nothing written');
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab',
   'e4ed0000-0000-0000-0000-000000001002', 'unavailable', 'paused');
insert into t_res select 'g-inc-unavail', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g8', 'e4ed0000-0000-0000-0000-00000000b001',
  '{"expected": {"subtotal_minor": 8800, "tax_total_minor": 1496, "grand_total_minor": 10296},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000b1002", "quantity": 3}]}'::jsonb);
select ok(pg_temp.refused('g-inc-unavail', 'e4ed0000-0000-0000-0000-00000000b001', 'item_unavailable'),
  '67 an INCREASE of a line whose item is now unavailable is item_unavailable; nothing written');
-- a modify that RAISES the burger's total quantity re-checks sellability.
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('e4ed0000-0000-0000-0000-0000000000a0', 'e4ed0000-0000-0000-0000-0000000000a1', 'e4ed0000-0000-0000-0000-0000000000ab',
   'e4ed0000-0000-0000-0000-000000001001', 'unavailable', 'paused');
insert into t_res select 'g-mod-raise', pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'g10', 'e4ed0000-0000-0000-0000-00000000b001',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 11200, "tax_total_minor": 1904, "grand_total_minor": 13104},
    "changes": [{"op": "modify", "order_item_id": "e4ed0000-0000-0000-0000-0000000b1001", "replacements": [
      {"quantity": 1, "modifiers": [{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"}]},
      {"quantity": 1, "modifiers": []}]}]}'::jsonb);
select ok(pg_temp.refused('g-mod-raise', 'e4ed0000-0000-0000-0000-00000000b001', 'item_unavailable'),
  '68 a MODIFY that raises the total quantity (1 -> 2) of a now-unavailable item is item_unavailable; nothing written');
-- a REDUCTION and a modify that does NOT raise the quantity need no
-- sellability; a new option with no kitchen_meat needs no meat_snapshot.
-- Fries 2 -> 1 (1600) + burger 1 -> 1 with cucumber (4000) = 5600.
create temp table t_v1 as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'v1', 'e4ed0000-0000-0000-0000-00000000b001',
  '{"reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 5600, "tax_total_minor": 952, "grand_total_minor": 6552},
    "changes": [{"op": "set_quantity", "order_item_id": "e4ed0000-0000-0000-0000-0000000b1002", "quantity": 1},
                {"op": "modify", "order_item_id": "e4ed0000-0000-0000-0000-0000000b1001", "replacements": [
                  {"quantity": 1, "modifiers": [{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e001"},
                    {"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e002", "modifier_name_snapshot": "Extras",
                     "option_name_snapshot": "cucumber", "price_minor_snapshot": 0}]}]}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_v1)
      and (select count(*) = 1 and bool_and(m.meat_snapshot is null and m.price_minor_snapshot = 0)
             from order_items n join order_item_modifiers m on m.order_item_id = n.id
            where n.replaces_order_item_id = 'e4ed0000-0000-0000-0000-0000000b1001'
              and m.modifier_option_id = 'e4ed0000-0000-0000-0000-00000000e002'),
  '69 V1 a REDUCTION of paused fries and a same-quantity MODIFY of the paused burger apply (no sellability check); a new option with no kitchen_meat stores no meat');
select is(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000b001'), 'ok', '70 V1 money identity holds');
update menu_item_branch_availability set availability = 'available', reason = null
 where organization_id = 'e4ed0000-0000-0000-0000-0000000000a0'
   and menu_item_id in ('e4ed0000-0000-0000-0000-000000001001', 'e4ed0000-0000-0000-0000-000000001002');

-- ===== H. the MONEY §9.2 worked example + the §13 Order edits bucket =========
-- Tax OFF (as in the worked example). Burger 4000 (+tomato, +cucumber), Fries
-- 1500, Cola 800 = 6300 -> burger without tomato, fries removed, + Lemonade
-- 900 = 5700.
update branches set tax_enabled = false where id = 'e4ed0000-0000-0000-0000-0000000000ab';
select pg_temp.mk_order('e4ed0000-0000-0000-0000-00000000a002', 'submitted');
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a2001', 'e4ed0000-0000-0000-0000-00000000a002', 'e4ed0000-0000-0000-0000-000000001001', 'Burger', 1, 4000, 4000);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a2001', 'e4ed0000-0000-0000-0000-00000000e001', 'Extras', 'tomato', 0);
select pg_temp.mk_mod('e4ed0000-0000-0000-0000-0000000a2001', 'e4ed0000-0000-0000-0000-00000000e002', 'Extras', 'cucumber', 0);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a2002', 'e4ed0000-0000-0000-0000-00000000a002', 'e4ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e4ed0000-0000-0000-0000-0000000a2003', 'e4ed0000-0000-0000-0000-00000000a002', 'e4ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle('e4ed0000-0000-0000-0000-00000000a002', 0, 0);
create temp table t_w as select pg_temp.edit('e4ed0000-0000-0000-0000-00000000009a', 'w1', 'e4ed0000-0000-0000-0000-00000000a002',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 5700, "tax_total_minor": 0, "grand_total_minor": 5700},
    "changes": [
      {"op": "modify", "order_item_id": "e4ed0000-0000-0000-0000-0000000a2001",
       "replacements": [{"quantity": 1, "modifiers": [{"modifier_option_id": "e4ed0000-0000-0000-0000-00000000e002"}]}]},
      {"op": "remove", "order_item_id": "e4ed0000-0000-0000-0000-0000000a2002"},
      {"op": "add", "item": {"menu_item_id": "e4ed0000-0000-0000-0000-000000001004", "quantity": 1,
        "unit_price_minor_snapshot": 900, "menu_item_name_snapshot": "Lemonade", "modifiers": []}}]}'::jsonb) as r;
select ok((select r ->> 'status' = 'applied' from t_w)
      and (select subtotal_minor = 5700 and tax_total_minor = 0 and grand_total_minor = 5700
             from orders where id = 'e4ed0000-0000-0000-0000-00000000a002')
      and exists (select 1 from audit_events where action = 'order.edited'
                   and new_values ->> 'order_edit_id' = (select r ->> 'order_edit_id' from t_w)
                   and (old_values ->> 'grand_total_minor')::bigint = 6300 and (new_values ->> 'grand_total_minor')::bigint = 5700),
  '71 worked example: 6300 -> 5700 (tax off), the audit records 6300 -> 5700');
select is(pg_temp.m13('e4ed0000-0000-0000-0000-00000000a002'),
  '{"removed_minor": 1500, "replaced_out_minor": 4000, "replaced_in_minor": 4000, "added_minor": 900, "net_change_minor": -600}'::jsonb,
  '72 worked example M13: removed 1500, replaced_out 4000, replaced_in 4000, added 900, net -600 = 5700 - 6300');
select is(pg_temp.money_check('e4ed0000-0000-0000-0000-00000000a002'), 'ok', '73 worked example money identity holds (tax off)');
update branches set tax_enabled = true where id = 'e4ed0000-0000-0000-0000-0000000000ab';
select ok((select bool_and(o.status in ('voided', 'cancelled') and o.line_total_minor = case o.id
                    when 'e4ed0000-0000-0000-0000-0000000a2001' then 4000 else 1500 end)
             from order_items o where o.order_id = 'e4ed0000-0000-0000-0000-00000000a002' and o.removed_by_edit_id is not null)
      and (select count(*) = 2 from order_items where order_id = 'e4ed0000-0000-0000-0000-00000000a002' and removed_by_edit_id is not null),
  '74 worked example: the two retired lines keep their amounts (M2) and are the only edit-retired rows');

-- ===== I. M11 revision, the kitchen "Got it", M12 / T-003 =====================
select ok((select revision = 3 and edit_count = 2 from orders where id = 'e4ed0000-0000-0000-0000-00000000a001')
      and (select revision = 2 and edit_count = 1 from orders where id = 'e4ed0000-0000-0000-0000-00000000c001'),
  '75 M11 every applied edit bumps revision by exactly one (S1: 1 -> 3 over two edits); refusals bumped nothing');
create temp table t_ack as select pg_temp.ack('e4ed0000-0000-0000-0000-00000000009c', 'ack-s1', 'e4ed0000-0000-0000-0000-00000000a001', 2) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 2 from t_ack)
      and (select revision = 3 and subtotal_minor = 16450 and tax_total_minor = 2797 and grand_total_minor = 19247
             from orders where id = 'e4ed0000-0000-0000-0000-00000000a001')
      and (select count(*) = 2 and bool_and(kitchen_ack_at is not null) from order_edits where order_id = 'e4ed0000-0000-0000-0000-00000000a001'),
  '76 M11 the KDS "Got it" (order.edit_ack via sync_push) stamps both edits and never bumps revision or touches money');
select ok(not exists (select 1 from information_schema.columns
                       where table_schema = 'public' and table_name in ('order_edits', 'order_service_rounds')
                         and column_name ~ '(^|_)minor($|_)'),
  '77 M12 / T-003: order_edits and service rounds carry no money column');
select ok((select created_at = now() and receipt_number is null and currency_code = 'ILS'
             from orders where id = 'e4ed0000-0000-0000-0000-00000000a001'),
  '78 M12 the edited order keeps its report bucket (created_at), receipt number and currency');
select ok((select count(*) = 0 from order_edits e
            where e.organization_id = 'e4ed0000-0000-0000-0000-0000000000a0'
              and e.order_id in ('e4ed0000-0000-0000-0000-00000000c003', 'e4ed0000-0000-0000-0000-00000000d001',
                                 'e4ed0000-0000-0000-0000-00000000d002', 'e4ed0000-0000-0000-0000-00000000f001',
                                 'e4ed0000-0000-0000-0000-00000000f003', 'e4ed0000-0000-0000-0000-00000000f004',
                                 'e4ed0000-0000-0000-0000-00000000f005', 'e4ed0000-0000-0000-0000-00000000f006')
              and e.local_operation_id like '%-x%')
      and (select count(*) = 0 from order_edits e
            where e.organization_id = 'e4ed0000-0000-0000-0000-0000000000a0'
              and e.local_operation_id in ('g1', 'g2', 'g3', 'g4', 'g5', 'g6', 'g7', 'g8', 'g9', 'g10')),
  '79 no refused operation left an order_edits row behind');

select * from finish();
rollback;
