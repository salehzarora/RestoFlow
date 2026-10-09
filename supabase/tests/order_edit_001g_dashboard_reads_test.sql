-- ============================================================================
-- ORDER-EDIT-001G — pgTAP: the Dashboard ORDER reads and the branch-switch
-- reader (API_CONTRACT §4.47a; migration 20261009100100):
--   A. app.owner_active_orders — every row + edit_count / has_active_round
--   B. app.owner_order_history — the same keys; completion ends the round
--   C. app.owner_order_detail  — edit_count, has_active_round,
--      active_rounds_ready and edits[] (oldest first, money-free, branch-local)
--   D. app.get_branch_order_edit_settings + its public wrapper
--   E. catalog / ACL / no audit / the support read-rank census
-- Real edits go through public.sync_push (order.edit / order.edit_ack); service
-- rounds are fixture rows (the readers are under test, not the round
-- lifecycle). Every read runs AS the authenticated role, identity GUC only.
-- Session pinned to UTC; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(36);

-- ===== fixture ===============================================================
-- Org C, restaurant C1 (UTC): branch K 'Asia/Jerusalem' (KDS, editing ON),
-- branch P 'UTC' (printer_only, editing ON), branch N (defaults), branch X
-- (soft-deleted). Org D: one branch with one order (isolation).
insert into organizations (id, name, slug, default_currency) values
  ('9e0c0000-0000-0000-0000-0000000000a0', 'Org Reads C', 'org-reads-001g-c', 'ILS'),
  ('9e0d0000-0000-0000-0000-0000000000a0', 'Org Reads D', 'org-reads-001g-d', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000a0', 'Rest C1', 'UTC'),
  ('9e0d0000-0000-0000-0000-0000000000a1', '9e0d0000-0000-0000-0000-0000000000a0', 'Rest D1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone, kitchen_workflow_mode, order_edit_enabled, deleted_at) values
  ('9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', 'Branch K', 'Asia/Jerusalem', 'kds', true, null),
  ('9e0c0000-0000-0000-0000-0000000000b2', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', 'Branch P', 'UTC', 'printer_only', true, null),
  ('9e0c0000-0000-0000-0000-0000000000b3', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', 'Branch N', null, 'kds', false, null),
  ('9e0c0000-0000-0000-0000-0000000000b4', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', 'Branch X', null, 'kds', true, now()),
  ('9e0d0000-0000-0000-0000-0000000000b1', '9e0d0000-0000-0000-0000-0000000000a0', '9e0d0000-0000-0000-0000-0000000000a1', 'Branch D', null, 'kds', true, null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('9e0c0000-0000-0000-0000-0000000000d1', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', 'pos'),
  ('9e0c0000-0000-0000-0000-0000000000d2', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', 'kds'),
  ('9e0c0000-0000-0000-0000-0000000000d3', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2', 'pos'),
  ('9e0d0000-0000-0000-0000-0000000000d1', '9e0d0000-0000-0000-0000-0000000000a0', '9e0d0000-0000-0000-0000-0000000000a1', '9e0d0000-0000-0000-0000-0000000000b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
  select replace(d.id::text, '00000000d', '00000000f')::uuid, d.organization_id, d.restaurant_id, d.branch_id, d.id, 'active'
    from devices d where d.id::text like '9e0_0000-0000-0000-0000-0000000000d_' and d.organization_id::text like '9e0c%'
       or d.id = '9e0d0000-0000-0000-0000-0000000000d1';
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id)
  select replace(d.id::text, '00000000d', '000000005')::uuid, d.organization_id, d.restaurant_id, d.branch_id, d.id,
         replace(d.id::text, '00000000d', '00000000f')::uuid
    from devices d where d.id::text like '9e0_0000-0000-0000-0000-0000000000d_' and d.organization_id::text like '9e0c%'
       or d.id = '9e0d0000-0000-0000-0000-0000000000d1';
insert into app_users (id, email) values
  ('9e0c0000-0000-0000-0000-00000000006a', 'r-cashier-k@example.test'),
  ('9e0c0000-0000-0000-0000-00000000006b', 'r-manager-k@example.test'),
  ('9e0c0000-0000-0000-0000-00000000006c', 'r-kitchen-k@example.test'),
  ('9e0c0000-0000-0000-0000-00000000006e', 'r-owner@example.test'),
  ('9e0c0000-0000-0000-0000-00000000006f', 'r-cashier-p@example.test'),
  ('9e0d0000-0000-0000-0000-00000000006a', 'r-other-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('9e0c0000-0000-0000-0000-00000000007a', '9e0c0000-0000-0000-0000-00000000006a', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', 'cashier', '{}'::jsonb),
  ('9e0c0000-0000-0000-0000-00000000007b', '9e0c0000-0000-0000-0000-00000000006b', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', 'manager', '{}'::jsonb),
  ('9e0c0000-0000-0000-0000-00000000007c', '9e0c0000-0000-0000-0000-00000000006c', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', 'kitchen_staff', '{}'::jsonb),
  ('9e0c0000-0000-0000-0000-00000000007e', '9e0c0000-0000-0000-0000-00000000006e', '9e0c0000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb),
  ('9e0c0000-0000-0000-0000-00000000007f', '9e0c0000-0000-0000-0000-00000000006f', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2', 'cashier', '{}'::jsonb),
  ('9e0d0000-0000-0000-0000-00000000007a', '9e0d0000-0000-0000-0000-00000000006a', '9e0d0000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('9e0c0000-0000-0000-0000-00000000008a', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-00000000006a', '9e0c0000-0000-0000-0000-00000000007a', 'Cara Cashier'),
  ('9e0c0000-0000-0000-0000-00000000008b', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-00000000006b', '9e0c0000-0000-0000-0000-00000000007b', 'Max Manager'),
  ('9e0c0000-0000-0000-0000-00000000008c', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-00000000006c', '9e0c0000-0000-0000-0000-00000000007c', 'Kai Kitchen'),
  ('9e0c0000-0000-0000-0000-00000000008e', '9e0c0000-0000-0000-0000-0000000000a0', null, null, '9e0c0000-0000-0000-0000-00000000006e', '9e0c0000-0000-0000-0000-00000000007e', 'Olga Owner'),
  ('9e0c0000-0000-0000-0000-00000000008f', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2', '9e0c0000-0000-0000-0000-00000000006f', '9e0c0000-0000-0000-0000-00000000007f', 'Pia Cashier'),
  ('9e0d0000-0000-0000-0000-00000000008a', '9e0d0000-0000-0000-0000-0000000000a0', null, null, '9e0d0000-0000-0000-0000-00000000006a', '9e0d0000-0000-0000-0000-00000000007a', 'Dan Other');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9e0c0000-0000-0000-0000-00000000009a', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000051', '9e0c0000-0000-0000-0000-00000000008a', '9e0c0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('9e0c0000-0000-0000-0000-00000000009b', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000051', '9e0c0000-0000-0000-0000-00000000008b', '9e0c0000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('9e0c0000-0000-0000-0000-00000000009c', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000052', '9e0c0000-0000-0000-0000-00000000008c', '9e0c0000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  ('9e0c0000-0000-0000-0000-00000000009f', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2', '9e0c0000-0000-0000-0000-000000000053', '9e0c0000-0000-0000-0000-00000000008f', '9e0c0000-0000-0000-0000-00000000007f', now() + interval '1 hour'),
  ('9e0d0000-0000-0000-0000-00000000009a', '9e0d0000-0000-0000-0000-0000000000a0', '9e0d0000-0000-0000-0000-0000000000a1', '9e0d0000-0000-0000-0000-0000000000b1', '9e0d0000-0000-0000-0000-000000000051', '9e0d0000-0000-0000-0000-00000000008a', '9e0d0000-0000-0000-0000-00000000007a', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('9e0c0000-0000-0000-0000-0000000000c1', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('9e0c0000-0000-0000-0000-000000001001', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', null, '9e0c0000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('9e0c0000-0000-0000-0000-000000001002', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', null, '9e0c0000-0000-0000-0000-0000000000c1', 'Fries',  1500, 'ILS', 2),
  ('9e0c0000-0000-0000-0000-000000001003', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', null, '9e0c0000-0000-0000-0000-0000000000c1', 'Cola',    800, 'ILS', 3);

-- Builders (direct inserts as the fixture role).
create function pg_temp.mk_order(p_id uuid, p_pin uuid, p_status text) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at)
  select p_id, ps.organization_id, ps.restaurant_id, ps.branch_id, ds.device_id, ps.id,
         ps.employee_profile_id, ps.resolved_membership_id, 'dine_in', 'ILS', 0, 0,
         'submit-' || p_id::text, p_status,
         case when p_status in ('ready', 'served', 'completed') then now() - interval '5 minutes' end
    from pin_sessions ps join device_sessions ds on ds.id = ps.device_session_id
   where ps.id = p_pin;
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_unit bigint) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor)
  select p_id, o.organization_id, o.restaurant_id, o.branch_id, o.id, p_menu, 1, p_name, p_unit, 0, p_unit
    from orders o where o.id = p_order;
$$;
create function pg_temp.settle(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, discount_total_minor = 0, tax_total_minor = 0,
                      grand_total_minor = s.t
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- a service round of the order, as a fixture row (round_number >= 2)
create function pg_temp.mk_round(p_order uuid, p_no int, p_status text, p_deleted boolean default false) returns void
language sql as $$
  insert into order_service_rounds (organization_id, restaurant_id, branch_id, order_id, round_number,
    status, ready_at, device_id, opened_by_employee_profile_id, deleted_at)
  select o.organization_id, o.restaurant_id, o.branch_id, o.id, p_no, p_status,
         case when p_status in ('ready', 'served') then now() end,
         o.device_id, o.opened_by_employee_profile_id, case when p_deleted then now() end
    from orders o where o.id = p_order;
$$;
create temp table t_ed (k text primary key, r jsonb);
create function pg_temp.edit(p_k text, p_pin uuid, p_order uuid, p_payload jsonb) returns void
language sql as $$
  insert into t_ed
  select p_k, public.sync_push(p_pin, ds.device_id, jsonb_build_array(jsonb_build_object(
           'local_operation_id', 'g-' || p_k, 'operation_type', 'order.edit', 'target_entity', 'order',
           'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0
    from pin_sessions ps join device_sessions ds on ds.id = ps.device_session_id
   where ps.id = p_pin;
$$;
create function pg_temp.ack(p_k text, p_pin uuid, p_order uuid, p_n int) returns void
language sql as $$
  insert into t_ed
  select p_k, public.sync_push(p_pin, ds.device_id, jsonb_build_array(jsonb_build_object(
           'local_operation_id', 'g-' || p_k, 'operation_type', 'order.edit_ack', 'target_entity', 'order',
           'target_id', p_order, 'payload', jsonb_build_object('order_id', p_order, 'up_to_edit_number', p_n)))) -> 'results' -> 0
    from pin_sessions ps join device_sessions ds on ds.id = ps.device_session_id
   where ps.id = p_pin;
$$;
-- the row of one order in a list result
create function pg_temp.row_of(p_res jsonb, p_order uuid) returns jsonb language sql as $$
  select o from jsonb_array_elements(p_res -> 'orders') o where o ->> 'order_id' = p_order::text;
$$;

-- ---- Branch K: served orders and their rounds (fixture rows) ----------------
--   R1 round submitted · R2 round ready · R3 round served · R4 round voided ·
--   R5 round submitted but soft-deleted · R6 rounds ready + preparing ·
--   R7 COMPLETED with a served round · R8 submitted, no round.
select pg_temp.mk_order(('9e0c0000-0000-0000-0000-0000000000' || n)::uuid, '9e0c0000-0000-0000-0000-00000000009a',
                        case n when '70' then 'completed' when '80' then 'submitted' else 'served' end)
  from unnest(array['10', '20', '30', '40', '50', '60', '70', '80']) n;
select pg_temp.mk_item(('9e0c0000-0000-0000-0000-00000000' || n || 'aa')::uuid, ('9e0c0000-0000-0000-0000-0000000000' || n)::uuid,
                       '9e0c0000-0000-0000-0000-000000001001', 'Burger', 4000)
  from unnest(array['10', '20', '30', '40', '50', '60', '70', '80']) n;
select pg_temp.settle(('9e0c0000-0000-0000-0000-0000000000' || n)::uuid)
  from unnest(array['10', '20', '30', '40', '50', '60', '70', '80']) n;
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000010', 2, 'submitted');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000020', 2, 'ready');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000030', 2, 'served');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000040', 2, 'voided');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000050', 2, 'submitted', true);
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000060', 2, 'ready');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000060', 3, 'preparing');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-000000000070', 2, 'served');

-- ---- Branch K: X1 edited twice (edit 1 acknowledged by the kitchen, edit 2
-- pending); X2 edited once, then voided (its pending confirmation is moot).
select pg_temp.mk_order('9e0c0000-0000-0000-0000-0000000000e1', '9e0c0000-0000-0000-0000-00000000009a', 'submitted');
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e101', '9e0c0000-0000-0000-0000-0000000000e1', '9e0c0000-0000-0000-0000-000000001001', 'Burger', 4000);
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e102', '9e0c0000-0000-0000-0000-0000000000e1', '9e0c0000-0000-0000-0000-000000001002', 'Fries', 1500);
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e103', '9e0c0000-0000-0000-0000-0000000000e1', '9e0c0000-0000-0000-0000-000000001003', 'Cola', 800);
select pg_temp.settle('9e0c0000-0000-0000-0000-0000000000e1');
select pg_temp.edit('x1e1', '9e0c0000-0000-0000-0000-00000000009a', '9e0c0000-0000-0000-0000-0000000000e1',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 4800, "tax_total_minor": 0, "grand_total_minor": 4800},
    "changes": [{"op": "remove", "order_item_id": "9e0c0000-0000-0000-0000-00000000e102"}]}'::jsonb);
select pg_temp.ack('x1ack', '9e0c0000-0000-0000-0000-00000000009c', '9e0c0000-0000-0000-0000-0000000000e1', 1);
select pg_temp.edit('x1e2', '9e0c0000-0000-0000-0000-00000000009b', '9e0c0000-0000-0000-0000-0000000000e1',
  '{"reason_code": "other", "reason_text": "no ice please",
    "expected": {"subtotal_minor": 4000, "tax_total_minor": 0, "grand_total_minor": 4000},
    "changes": [{"op": "remove", "order_item_id": "9e0c0000-0000-0000-0000-00000000e103"}]}'::jsonb);
select pg_temp.mk_order('9e0c0000-0000-0000-0000-0000000000e2', '9e0c0000-0000-0000-0000-00000000009a', 'submitted');
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e201', '9e0c0000-0000-0000-0000-0000000000e2', '9e0c0000-0000-0000-0000-000000001001', 'Burger', 4000);
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e202', '9e0c0000-0000-0000-0000-0000000000e2', '9e0c0000-0000-0000-0000-000000001002', 'Fries', 1500);
select pg_temp.settle('9e0c0000-0000-0000-0000-0000000000e2');
select pg_temp.edit('x2e1', '9e0c0000-0000-0000-0000-00000000009a', '9e0c0000-0000-0000-0000-0000000000e2',
  '{"reason_code": "entry_mistake",
    "expected": {"subtotal_minor": 4000, "tax_total_minor": 0, "grand_total_minor": 4000},
    "changes": [{"op": "remove", "order_item_id": "9e0c0000-0000-0000-0000-00000000e202"}]}'::jsonb);
create temp table t_void as
  select app.void_order('9e0c0000-0000-0000-0000-00000000009b', '9e0c0000-0000-0000-0000-0000000000e2',
                        '9e0c0000-0000-0000-0000-0000000000d1', 'g-void-x2', 'guest left') as r;

-- ---- Branch P (printer_only): X3 a PAPER edit; OP served with a round that
-- nothing on paper ever advances.
select pg_temp.mk_order('9e0c0000-0000-0000-0000-0000000000e3', '9e0c0000-0000-0000-0000-00000000009f', 'submitted');
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e301', '9e0c0000-0000-0000-0000-0000000000e3', '9e0c0000-0000-0000-0000-000000001001', 'Burger', 4000);
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000e302', '9e0c0000-0000-0000-0000-0000000000e3', '9e0c0000-0000-0000-0000-000000001002', 'Fries', 1500);
select pg_temp.settle('9e0c0000-0000-0000-0000-0000000000e3');
select pg_temp.edit('x3e1', '9e0c0000-0000-0000-0000-00000000009f', '9e0c0000-0000-0000-0000-0000000000e3',
  '{"reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 4000, "tax_total_minor": 0, "grand_total_minor": 4000},
    "changes": [{"op": "remove", "order_item_id": "9e0c0000-0000-0000-0000-00000000e302"}]}'::jsonb);
select pg_temp.mk_order('9e0c0000-0000-0000-0000-0000000000f0', '9e0c0000-0000-0000-0000-00000000009f', 'served');
select pg_temp.mk_item('9e0c0000-0000-0000-0000-00000000f001', '9e0c0000-0000-0000-0000-0000000000f0', '9e0c0000-0000-0000-0000-000000001003', 'Cola', 800);
select pg_temp.settle('9e0c0000-0000-0000-0000-0000000000f0');
select pg_temp.mk_round('9e0c0000-0000-0000-0000-0000000000f0', 2, 'submitted');

-- ---- Org D: one order (isolation)
select pg_temp.mk_order('9e0d0000-0000-0000-0000-0000000000e1', '9e0d0000-0000-0000-0000-00000000009a', 'submitted');

-- ===== the reads, AS the authenticated role ==================================
set local role authenticated;
create temp table t_r (k text primary key, r jsonb);
reset role;
create temp table t_audit0 as select count(*) as n from audit_events;
set local role authenticated;
set local app.current_app_user_id = '9e0c0000-0000-0000-0000-00000000006b';   -- Max, manager of K
insert into t_r values
  ('act_k',  public.owner_active_orders('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1')),
  ('his_k',  public.owner_order_history('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', 'today', p_limit => 100)),
  ('det_x1', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-0000000000e1')),
  ('det_x2', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-0000000000e2')),
  ('det_r1', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000010')),
  ('det_r2', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000020')),
  ('det_r3', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000030')),
  ('det_r6', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000060')),
  ('det_r8', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-000000000080'));
set local app.current_app_user_id = '9e0c0000-0000-0000-0000-00000000006c';   -- Kai, kitchen of K
insert into t_r values
  ('det_kit', public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1', '9e0c0000-0000-0000-0000-0000000000e1')),
  ('set_kit', public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1'));
set local app.current_app_user_id = '9e0c0000-0000-0000-0000-00000000006a';   -- Cara, cashier of K
insert into t_r values
  ('set_cash_k', public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1')),
  ('set_cash_p', public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2'));
set local app.current_app_user_id = '9e0c0000-0000-0000-0000-00000000006e';   -- Olga, org_owner
insert into t_r values
  ('act_p',    public.owner_active_orders('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2')),
  ('det_x3',   public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', null, null, '9e0c0000-0000-0000-0000-0000000000e3')),
  ('det_frn',  public.owner_order_detail('9e0c0000-0000-0000-0000-0000000000a0', null, null, '9e0d0000-0000-0000-0000-0000000000e1')),
  ('set_n',    public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b3')),
  ('set_p',    public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2')),
  ('set_frn',  public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0d0000-0000-0000-0000-0000000000b1')),
  ('set_frn2', public.get_branch_order_edit_settings('9e0d0000-0000-0000-0000-0000000000a0', '9e0d0000-0000-0000-0000-0000000000a1', '9e0d0000-0000-0000-0000-0000000000b1')),
  ('set_none', public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-000000000fff')),
  ('set_del',  public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b4')),
  ('set_null', public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', null, '9e0c0000-0000-0000-0000-0000000000b3'));
reset role;
create temp table t_audit1 as select count(*) as n from audit_events;

-- the owner turns both switches on for branch N; the reader follows
set local role authenticated;
set local app.current_app_user_id = '9e0c0000-0000-0000-0000-00000000006e';
insert into t_r values
  ('set_write', public.set_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000c9', '9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b3', true, true));
insert into t_r values
  ('set_n2', public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b3'));
reset role;

-- printer_only: OP completes on full settlement — completion closes its round.
insert into payments (organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id,
  resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
select o.organization_id, o.restaurant_id, o.branch_id, o.id, o.device_id, o.opened_by_employee_profile_id,
       o.resolved_membership_id, 'cash', 'completed', o.grand_total_minor, o.grand_total_minor, 0, 'ILS', 'g-pay-op'
  from orders o where o.id = '9e0c0000-0000-0000-0000-0000000000f0';
create temp table t_auto as
  select app.try_auto_complete_order('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1',
    '9e0c0000-0000-0000-0000-0000000000b2', '9e0c0000-0000-0000-0000-0000000000f0', 'payment_recorded', null,
    '9e0c0000-0000-0000-0000-00000000008f', '9e0c0000-0000-0000-0000-00000000007f', 'cashier',
    '9e0c0000-0000-0000-0000-0000000000d3', 'g-pay-op') as r;
set local role authenticated;
set local app.current_app_user_id = '9e0c0000-0000-0000-0000-00000000006e';
insert into t_r values
  ('his_p', public.owner_order_history('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b2', 'today'));
reset role;

select ok((select bool_and(r ->> 'status' = 'applied') and count(*) = 4 from t_ed where k like 'x_e_')
      and (select r ->> 'status' = 'applied' from t_ed where k = 'x1ack')
      and (select (r ->> 'ok')::boolean from t_void)
      and (select (r ->> 'completed')::boolean from t_auto),
  '00 fixture: four edits and one kitchen confirmation applied through sync_push; X2 voided; OP completed');

-- ===== A. owner_active_orders ================================================
select is((select jsonb_object_agg(right(o ->> 'order_id', 4), (o ->> 'has_active_round')::boolean)
             from t_r, jsonb_array_elements(r -> 'orders') o where k = 'act_k'),
  '{"0010": true, "0020": true, "0030": false, "0040": false, "0050": false, "0060": true, "0080": false, "00e1": false}'::jsonb,
  'A1 has_active_round: true for a submitted or ready round (and ready + preparing); false once served, voided, soft-deleted, or with no round');
select is((select jsonb_object_agg(right(o ->> 'order_id', 4), (o ->> 'edit_count')::int)
             from t_r, jsonb_array_elements(r -> 'orders') o where k = 'act_k'),
  (select jsonb_object_agg(right(id::text, 4), edit_count) from orders
    where branch_id = '9e0c0000-0000-0000-0000-0000000000b1'
      and status in ('submitted', 'accepted', 'preparing', 'ready', 'served')),
  'A2 edit_count is orders.edit_count on every row (X1 = 2, the rest 0)');
select is((select array_agg(x order by x collate "C") from (select distinct j.key as x
             from t_r, jsonb_array_elements(r -> 'orders') o, jsonb_object_keys(o) j(key) where t_r.k = 'act_k') s),
  array['branch_name', 'created_at', 'created_at_utc', 'currency_code', 'customer_name', 'customer_phone',
        'edit_count', 'grand_total_minor', 'has_active_round', 'item_count', 'kitchen_work_open', 'order_code',
        'order_id', 'order_type', 'paid_amount_minor', 'payment_method', 'payment_status', 'receipt_number',
        'shift_status', 'staff_name', 'status', 'table_label', 'timezone'],
  'A3 every row carries exactly the ACTIVE-ORDERS keys plus edit_count and has_active_round');
select ok((select (o ->> 'item_count')::int = 1 from t_r, jsonb_array_elements(r -> 'orders') o
            where k = 'act_k' and o ->> 'order_id' = '9e0c0000-0000-0000-0000-0000000000e1')
      and (select (r -> 'summary' ->> 'total')::int = 8 and (r -> 'summary' ->> 'in_progress')::int = 2
                  and (r -> 'summary' ->> 'awaiting_close')::int = 6 and (r ->> 'matching')::int = 8
             from t_r where k = 'act_k'),
  'A4 item_count still excludes edit-retired lines; summary and queues are unchanged by the new keys');
select ok((select (pg_temp.row_of(r, '9e0c0000-0000-0000-0000-0000000000f0') ->> 'has_active_round')::boolean
             from t_r where k = 'act_p'),
  'A5 printer_only: a served order''s round reads active (nothing on paper advances it) until completion');

-- ===== B. owner_order_history ================================================
select is((select jsonb_object_agg(right(o ->> 'order_id', 4),
                                   jsonb_build_array((o ->> 'has_active_round')::boolean, (o ->> 'edit_count')::int))
             from t_r, jsonb_array_elements(r -> 'orders') o where k = 'his_k'),
  '{"0010": [true, 0], "0020": [true, 0], "0030": [false, 0], "0040": [false, 0], "0050": [false, 0], "0060": [true, 0],
    "0070": [false, 0], "0080": [false, 0], "00e1": [false, 2], "00e2": [false, 1]}'::jsonb,
  'B1 history rows carry the same has_active_round and edit_count (a completed and a voided order read false)');
select is((select array_agg(x order by x collate "C") from (select distinct j.key as x
             from t_r, jsonb_array_elements(r -> 'orders') o, jsonb_object_keys(o) j(key) where t_r.k = 'his_k') s),
  array['created_at', 'currency_code', 'customer_name', 'customer_phone', 'discount_total_minor', 'edit_count',
        'grand_total_minor', 'has_active_round', 'item_count', 'order_code', 'order_id', 'order_type',
        'paid_amount_minor', 'payment_method', 'payment_status', 'receipt_number', 'staff_name', 'status',
        'subtotal_minor', 'table_label', 'tax_total_minor'],
  'B2 every history row carries exactly the ORDERS-HISTORY keys plus edit_count and has_active_round');
select ok((select o ->> 'status' = 'completed' and not (o ->> 'has_active_round')::boolean
             from t_r, jsonb_array_elements(r -> 'orders') o
            where k = 'his_p' and o ->> 'order_id' = '9e0c0000-0000-0000-0000-0000000000f0')
      and (select bool_and(status = 'served') from order_service_rounds where order_id = '9e0c0000-0000-0000-0000-0000000000f0'),
  'B3 printer_only: completion terminalizes the round, and the order then reads has_active_round false');
select ok((select (r ->> 'ok')::boolean and (r ->> 'count')::int = 10 and r ->> 'entity' = 'owner_order_history'
             from t_r where k = 'his_k'),
  'B4 the history envelope is unchanged (ok, entity, count)');

-- ===== C. owner_order_detail =================================================
select is((select jsonb_agg(jsonb_build_object('n', (e ->> 'edit_number')::int, 'r', e ->> 'reason_code', 't', e ->> 'reason_text',
                                               'ch', e ->> 'kitchen_channel', 'req', (e ->> 'kitchen_ack_required')::boolean,
                                               'acked', e ->> 'kitchen_ack_at' is not null,
                                               'pend', (e ->> 'kitchen_ack_pending')::boolean) order by o)
             from t_r, jsonb_array_elements(r -> 'order' -> 'edits') with ordinality x(e, o) where k = 'det_x1'),
  '[{"n": 1, "r": "customer_changed_mind", "t": null, "ch": "kds", "req": true, "acked": true, "pend": false},
    {"n": 2, "r": "other", "t": "no ice please", "ch": "kds", "req": true, "acked": false, "pend": true}]'::jsonb,
  'C1 edits[] oldest first: edit 1 confirmed by the kitchen (not pending), edit 2 still pending; reason_text shown');
select ok((select r -> 'order' -> 'edits' -> 0 ->> 'created_at'
                    = (select to_char(e.created_at at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI') from order_edits e
                        where e.order_id = '9e0c0000-0000-0000-0000-0000000000e1' and e.edit_number = 1)
                  and r -> 'order' -> 'edits' -> 0 ->> 'kitchen_ack_at'
                    = (select to_char(e.kitchen_ack_at at time zone 'Asia/Jerusalem', 'YYYY-MM-DD HH24:MI') from order_edits e
                        where e.order_id = '9e0c0000-0000-0000-0000-0000000000e1' and e.edit_number = 1)
                  and r -> 'order' -> 'edits' -> 1 -> 'kitchen_ack_at' = 'null'::jsonb
             from t_r where k = 'det_x1'),
  'C2 created_at and kitchen_ack_at are branch-local (Asia/Jerusalem) display strings; an unconfirmed edit has null');
select ok((select (r -> 'order' ->> 'status') = 'voided'
                  and (r -> 'order' -> 'edits' -> 0 ->> 'kitchen_ack_required')::boolean
                  and not (r -> 'order' -> 'edits' -> 0 ->> 'kitchen_ack_pending')::boolean
             from t_r where k = 'det_x2'),
  'C3 on a voided order a required, unconfirmed edit is NOT pending (the void supersedes it)');
select ok((select r -> 'order' -> 'edits' -> 0 ->> 'kitchen_channel' = 'paper'
                  and not (r -> 'order' -> 'edits' -> 0 ->> 'kitchen_ack_required')::boolean
                  and not (r -> 'order' -> 'edits' -> 0 ->> 'kitchen_ack_pending')::boolean
             from t_r where k = 'det_x3'),
  'C4 a paper edit (printer_only branch) requires no kitchen confirmation');
select is((select array_agg(x order by x collate "C") from (select distinct j.key as x
             from t_r, jsonb_array_elements(r -> 'order' -> 'edits') e, jsonb_object_keys(e) j(key)
            where t_r.k in ('det_x1', 'det_x2', 'det_x3')) s),
  array['created_at', 'edit_number', 'kitchen_ack_at', 'kitchen_ack_pending', 'kitchen_ack_required',
        'kitchen_channel', 'reason_code', 'reason_text'],
  'C5 an edits[] element has exactly the contract keys: no money, no order_edit_id, no staff / device / session id');
select is((select array_agg(j.key order by j.key collate "C") from t_r, jsonb_object_keys(r -> 'order') j(key) where t_r.k = 'det_x1'),
  array['active_rounds_ready', 'branch_name', 'created_at', 'currency_code', 'customer_name', 'customer_phone',
        'discount_total_minor', 'edit_count', 'edits', 'grand_total_minor', 'has_active_round', 'items', 'notes',
        'order_code', 'order_id', 'order_type', 'payments', 'receipt_number', 'staff_name', 'status',
        'subtotal_minor', 'table_label', 'tax_total_minor'],
  'C6 order carries exactly the ORDERS-HISTORY detail keys plus edit_count, has_active_round, active_rounds_ready and edits');
select ok((select (r -> 'order' ->> 'edit_count')::int = 2 and jsonb_array_length(r -> 'order' -> 'items') = 1
                  and r -> 'order' -> 'items' -> 0 ->> 'name' = 'Burger'
             from t_r where k = 'det_x1')
      and (select (r -> 'order' ->> 'edit_count')::int = 0 and r -> 'order' -> 'edits' = '[]'::jsonb from t_r where k = 'det_r8'),
  'C7 edit_count; items still exclude the lines edits retired (ORDER-EDIT-001A); an unedited order has edits []');
select is((select jsonb_object_agg(k, jsonb_build_array((r -> 'order' ->> 'has_active_round')::boolean,
                                                        (r -> 'order' ->> 'active_rounds_ready')::boolean))
             from t_r where k in ('det_r1', 'det_r2', 'det_r3', 'det_r6', 'det_r8')),
  '{"det_r1": [true, false], "det_r2": [true, true], "det_r3": [false, false], "det_r6": [true, false], "det_r8": [false, false]}'::jsonb,
  'C8 active_rounds_ready only when an active round exists and every active round is ready');
select is((select r from t_r where k = 'det_frn'),
  '{"ok": false, "error": "not_found", "entity": "owner_order_detail"}'::jsonb,
  'C9 another organization''s order is still not_found');
select is((select r from t_r where k = 'det_kit'),
  '{"ok": false, "error": "permission_denied", "entity": "owner_order_detail"}'::jsonb,
  'C10 kitchen_staff is still permission_denied');

-- ===== D. get_branch_order_edit_settings =====================================
set local role authenticated;
reset app.current_app_user_id;
select throws_ok(
  $$ select public.get_branch_order_edit_settings('9e0c0000-0000-0000-0000-0000000000a0', '9e0c0000-0000-0000-0000-0000000000a1', '9e0c0000-0000-0000-0000-0000000000b1') $$,
  '42501', 'get_branch_order_edit_settings: authentication required', 'D1 no identity -> 42501');
reset role;
select is((select r from t_r where k = 'set_n'),
  '{"ok": true, "entity": "branch", "branch_id": "9e0c0000-0000-0000-0000-0000000000b3", "order_edit_enabled": false, "order_edit_finished_food_manager_only": false, "kitchen_workflow_mode": "kds"}'::jsonb,
  'D2 a branch never configured reads both switches false (the shipped default) and its kitchen mode');
select is((select r from t_r where k = 'set_p'),
  '{"ok": true, "entity": "branch", "branch_id": "9e0c0000-0000-0000-0000-0000000000b2", "order_edit_enabled": true, "order_edit_finished_food_manager_only": false, "kitchen_workflow_mode": "printer_only"}'::jsonb,
  'D3 kitchen_workflow_mode is returned (printer_only), with the stored switches');
select ok((select (r ->> 'ok')::boolean and (r ->> 'idempotent_replay')::boolean = false from t_r where k = 'set_write')
      and (select r ->> 'order_edit_enabled' = 'true' and r ->> 'order_edit_finished_food_manager_only' = 'true' from t_r where k = 'set_n2'),
  'D4 after set_branch_order_edit_settings the reader returns the new values');
select ok((select r ->> 'ok' = 'true' and r ->> 'order_edit_enabled' = 'true' from t_r where k = 'set_kit')
      and (select r ->> 'ok' = 'true' from t_r where k = 'set_cash_k'),
  'D5 any member covering the branch may read (kitchen_staff and cashier included)');
select ok((select bool_and(r = '{"ok": false, "error": "not_found", "entity": "branch"}'::jsonb) and count(*) = 6
             from t_r where k in ('set_frn', 'set_frn2', 'set_none', 'set_del', 'set_null', 'set_cash_p')),
  'D6 another tenant''s branch (either org id), a nonexistent, a deleted branch, a null argument and a sibling branch all read the SAME not_found');

-- ===== E. catalog, ACL, no audit, census =====================================
select is((select string_agg(n.nspname || ':' || pg_get_function_identity_arguments(p.oid), ' ; ' order by n.nspname)
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname = 'get_branch_order_edit_settings'),
  'app:p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid ; public:p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid',
  'E1 app. and public.get_branch_order_edit_settings exist with the exact identity');
select ok((select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
             from pg_proc p where p.oid = 'app.get_branch_order_edit_settings(uuid,uuid,uuid)'::regprocedure)
      and (select not p.prosecdef and l.lanname = 'sql' and p.proconfig = array['search_path=""'] and p.proacl is not null
             from pg_proc p join pg_language l on l.oid = p.prolang
            where p.oid = 'public.get_branch_order_edit_settings(uuid,uuid,uuid)'::regprocedure),
  'E2 app: SECURITY DEFINER, STABLE, search_path pinned; public: SECURITY INVOKER sql wrapper with an explicit ACL');
select ok(has_function_privilege('authenticated', 'app.get_branch_order_edit_settings(uuid,uuid,uuid)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.get_branch_order_edit_settings(uuid,uuid,uuid)', 'EXECUTE')
      and not has_function_privilege('anon', 'app.get_branch_order_edit_settings(uuid,uuid,uuid)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.get_branch_order_edit_settings(uuid,uuid,uuid)', 'EXECUTE')
      and not has_function_privilege('public', 'app.get_branch_order_edit_settings(uuid,uuid,uuid)', 'EXECUTE')
      and not has_function_privilege('public', 'public.get_branch_order_edit_settings(uuid,uuid,uuid)', 'EXECUTE'),
  'E3 authenticated only: anon and PUBLIC may execute neither layer (D-037)');
select ok((select bool_and(p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""'])
             from pg_proc p
            where p.oid in ('app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,integer,text,text,text)'::regprocedure,
                            'app.owner_order_history(uuid,uuid,uuid,text,text,text,text,text,integer,text,date,date)'::regprocedure,
                            'app.owner_order_detail(uuid,uuid,uuid,uuid)'::regprocedure)),
  'E4 the three re-emitted readers are still SECURITY DEFINER, STABLE, search_path pinned');
select ok((select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
                           and not has_function_privilege('anon', p.oid, 'EXECUTE')
                           and not has_function_privilege('public', p.oid, 'EXECUTE'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.proname in ('owner_active_orders', 'owner_order_history', 'owner_order_detail')),
  'E5 both layers of the three readers keep their ACL: authenticated yes, anon and PUBLIC no');
select ok((select prosrc from pg_proc where oid = 'app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,integer,text,text,text)'::regprocedure)
            like U&'%selected queue \00E2\20AC\201D this is what the SUMMARY counts%',
  'E6 the historical mis-encoded comment bytes of owner_active_orders survive the re-emit byte for byte');
select is((select n from t_audit1), (select n from t_audit0),
  'E7 the reads wrote no audit_events row (D-013)');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.prokind = 'f' and p.proname <> 'actor_read_rank_in_scope'
              and pg_get_functiondef(p.oid) ~ 'actor_read_rank_in_scope'),
  13, 'E8 the ADMIN-126B support read-rank census is unchanged at 13 (the new readers use the member rank)');
select ok((select r ->> 'ok' = 'true' from t_r where k = 'act_k')
      and (select r ->> 'ok' = 'true' from t_r where k = 'act_p')
      and (select r ->> 'ok' = 'true' from t_r where k = 'det_x3'),
  'E9 the public wrappers return the widened reads AS authenticated (REPORT-123)');
select ok(not exists (select 1 from t_r, jsonb_array_elements(r -> 'orders') o
                       where k in ('act_k', 'act_p', 'his_k', 'his_p') and o ->> 'order_id' like '9e0d%'),
  'E10 no row of another organization appears in any list');

select * from finish();
rollback;
