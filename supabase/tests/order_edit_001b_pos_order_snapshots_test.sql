-- ORDER-EDIT-001B — the POS order snapshot read gains the edit / round flags
-- (API_CONTRACT §4.30c, §4.45.10, §4.46; DECISION D-043 / D-044; migration
-- 20261008190000): app.pos_order_snapshots (and its public pass-through).
-- Covers the three additive, money-free row keys (edit_count,
-- kitchen_edit_ack_pending, has_active_round) beside the unchanged safe key
-- set; edit_count after real edits; kitchen_edit_ack_pending through the real
-- order.edit / order.edit_ack sync path (required, acknowledged, not required,
-- paper, tombstoned, and FALSE on a voided order); has_active_round across
-- every round status, a tombstoned round, an edit-created round and a round
-- voided by an edit; THE WIDER SYNC STAMP (greatest of the order, its
-- completed payment, its rounds' and its edits' updated_at), proven with
-- backdated rows and a real acknowledgement that writes no orders row; and
-- the unchanged invariants (invalid_cursor, no audit from a read).
begin;
set local search_path to extensions, public, pg_catalog;

select plan(44);

-- ===== fixture ==============================================================
-- Org A, one restaurant, two branches (order editing ON on both):
--   K (..ab) kds mode:          POS d1, KDS d2
--   P (..ac) printer_only mode: POS d3
-- PIN sessions: cashier (9a) on the POS d1, kitchen_staff (9c) on the KDS d2,
-- cashier (9d) on the paper POS d3.
insert into organizations (id, name, slug, default_currency) values
  ('b1e00000-0000-0000-0000-0000000000a0', 'Org Edit Snapshots', 'org-edit-snapshots-001b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000a0', 'Rest Edit Snapshots');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, order_edit_enabled) values
  ('b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'Branch Snap KDS', 'kds', true),
  ('b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'Branch Snap Paper', 'printer_only', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b1e00000-0000-0000-0000-0000000000d1', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'pos'),
  ('b1e00000-0000-0000-0000-0000000000d2', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'kds'),
  ('b1e00000-0000-0000-0000-0000000000d3', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ac', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b1e00000-0000-0000-0000-0000000000f1', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000d1', 'active'),
  ('b1e00000-0000-0000-0000-0000000000f2', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000d2', 'active'),
  ('b1e00000-0000-0000-0000-0000000000f3', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-0000000000d3', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b1e00000-0000-0000-0000-00000000005a', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000d1', 'b1e00000-0000-0000-0000-0000000000f1'),
  ('b1e00000-0000-0000-0000-00000000005b', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000d2', 'b1e00000-0000-0000-0000-0000000000f2'),
  ('b1e00000-0000-0000-0000-00000000005c', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-0000000000d3', 'b1e00000-0000-0000-0000-0000000000f3');
insert into app_users (id, email) values
  ('b1e00000-0000-0000-0000-00000000006a', 'snap-cashier@example.test'),
  ('b1e00000-0000-0000-0000-00000000006c', 'snap-kitchen@example.test'),
  ('b1e00000-0000-0000-0000-00000000006d', 'snap-paper-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('b1e00000-0000-0000-0000-00000000007a', 'b1e00000-0000-0000-0000-00000000006a', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('b1e00000-0000-0000-0000-00000000007c', 'b1e00000-0000-0000-0000-00000000006c', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb),
  ('b1e00000-0000-0000-0000-00000000007d', 'b1e00000-0000-0000-0000-00000000006d', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ac', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('b1e00000-0000-0000-0000-00000000008a', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-00000000006a', 'b1e00000-0000-0000-0000-00000000007a', 'Sara Cashier'),
  ('b1e00000-0000-0000-0000-00000000008c', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-00000000006c', 'b1e00000-0000-0000-0000-00000000007c', 'Kim Kitchen'),
  ('b1e00000-0000-0000-0000-00000000008d', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-00000000006d', 'b1e00000-0000-0000-0000-00000000007d', 'Pia Paper');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('b1e00000-0000-0000-0000-00000000009a', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-00000000005a', 'b1e00000-0000-0000-0000-00000000008a', 'b1e00000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('b1e00000-0000-0000-0000-00000000009c', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-00000000005b', 'b1e00000-0000-0000-0000-00000000008c', 'b1e00000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  ('b1e00000-0000-0000-0000-00000000009d', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', 'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-00000000005c', 'b1e00000-0000-0000-0000-00000000008d', 'b1e00000-0000-0000-0000-00000000007d', now() + interval '1 hour');

-- Menu (restaurant-scoped, so both branches sell it): Fries 1500, Cola 800.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('b1e00000-0000-0000-0000-0000000000c1', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('b1e00000-0000-0000-0000-000000001002', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', null, 'b1e00000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 1),
  ('b1e00000-0000-0000-0000-000000001003', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1', null, 'b1e00000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 2);

-- Builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire). Branch K unless stated.
-- A live order created NOW (optionally with a private note and a customer name).
create function pg_temp.mk_order(p_id uuid, p_status text, p_notes text default null,
  p_customer text default null) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at, notes, customer_name)
  values (p_id, 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
    'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000d1',
    'b1e00000-0000-0000-0000-00000000009a', 'b1e00000-0000-0000-0000-00000000008a',
    'b1e00000-0000-0000-0000-00000000007a', 'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end, p_notes, p_customer);
$$;
-- A BACKDATED order: created 4 hours ago (inside the 2-day window) with an
-- explicit updated_at, which an INSERT keeps (set_updated_at is BEFORE UPDATE
-- only). It is never updated afterwards by the fixture.
create function pg_temp.mk_bd_order(p_id uuid, p_status text, p_updated_at timestamptz,
  p_edit_count int default 0) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at, edit_count,
    created_at, updated_at)
  values (p_id, 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
    'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-0000000000d1',
    'b1e00000-0000-0000-0000-00000000009a', 'b1e00000-0000-0000-0000-00000000008a',
    'b1e00000-0000-0000-0000-00000000007a', 'dine_in', 'ILS', 1000, 1000, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '230 minutes' end, p_edit_count,
    now() - interval '4 hours', p_updated_at);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_round uuid default null) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor, service_round_id)
  values (p_id, 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
    'b1e00000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, 0, p_total, p_round);
$$;
-- A service round with an explicit updated_at (kept by the INSERT) and an
-- optional tombstone.
create function pg_temp.mk_round(p_id uuid, p_order uuid, p_no int, p_status text,
  p_updated_at timestamptz default now(), p_deleted boolean default false) returns void
language sql as $$
  insert into order_service_rounds (id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, ready_at, created_at, updated_at, deleted_at)
  values (p_id, 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
    'b1e00000-0000-0000-0000-0000000000ab', p_order, p_no, p_status,
    'b1e00000-0000-0000-0000-0000000000d1', 'b1e00000-0000-0000-0000-00000000008a',
    case when p_status in ('ready', 'served') then p_updated_at - interval '5 minutes' end,
    p_updated_at - interval '10 minutes', p_updated_at,
    case when p_deleted then p_updated_at end);
$$;
-- A KDS-channel order_edits row needing the kitchen's confirmation, inserted
-- DIRECTLY (the append-only guard fires on UPDATE / DELETE only) with an
-- explicit updated_at and an optional tombstone. Actor = the K cashier on d1,
-- exactly as app.edit_order would record it.
create function pg_temp.mk_edit_row(p_id uuid, p_order uuid, p_updated_at timestamptz,
  p_deleted boolean default false) returns void
language sql as $$
  insert into order_edits (id, organization_id, restaurant_id, branch_id, order_id, edit_number,
    device_id, local_operation_id, pin_session_id, employee_profile_id, membership_id,
    reason_code, kitchen_channel, kitchen_ack_required, created_at, updated_at, deleted_at)
  values (p_id, 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
    'b1e00000-0000-0000-0000-0000000000ab', p_order, 1,
    'b1e00000-0000-0000-0000-0000000000d1', 'direct-' || p_id::text,
    'b1e00000-0000-0000-0000-00000000009a', 'b1e00000-0000-0000-0000-00000000008a',
    'b1e00000-0000-0000-0000-00000000007a', null, 'kds', true,
    p_updated_at - interval '10 minutes', p_updated_at,
    case when p_deleted then p_updated_at end);
$$;
-- re-roll an order's stored totals from its live lines (tax off, no discount)
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push (default: the K POS)
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'b1e00000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- one order.edit_ack up to edit N through public.sync_push (default: the K KDS)
create function pg_temp.ack(p_pin uuid, p_op text, p_order uuid, p_n int,
  p_dev uuid default 'b1e00000-0000-0000-0000-0000000000d2') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit_ack', 'target_entity', 'order',
    'target_id', p_order, 'payload', jsonb_build_object('order_id', p_order, 'up_to_edit_number', p_n)))) -> 'results' -> 0;
$$;
-- the snapshot row of one order inside a stored envelope (NULL when absent)
create function pg_temp.row_of(p_env jsonb, p_order uuid) returns jsonb
language sql immutable as $$
  select o from jsonb_array_elements(p_env -> 'orders') o where o ->> 'order_id' = p_order::text;
$$;
-- the K cashier's snapshot read (window mode unless a cursor / id list is given)
create function pg_temp.snap(p_since_at timestamptz default null, p_since_id uuid default null,
  p_before_at timestamptz default null, p_before_id uuid default null, p_ids uuid[] default null) returns jsonb
language sql stable as $$
  select app.pos_order_snapshots(
    p_pin_session_id => 'b1e00000-0000-0000-0000-00000000009a',
    p_device_id      => 'b1e00000-0000-0000-0000-0000000000d1',
    p_since_at => p_since_at, p_since_id => p_since_id,
    p_before_at => p_before_at, p_before_id => p_before_id,
    p_order_ids => p_ids, p_limit => 100, p_window_days => 2);
$$;

-- Orders on branch K (created NOW unless backdated):
--   N  (a001) preparing, never edited; carries a private note + customer name
--   R  (a002) preparing -> edit 1 Cola 1 -> 2 in place (confirmation required) -> acknowledged
--   M  (a003) preparing -> edit 1 add Cola, edit 2 add Fries (new rounds only: no confirmation)
--   V  (a004) preparing -> edit 1 Cola 1 -> 2 (confirmation required) -> VOIDED, still pending
--   W  (a005) served + a live round (preparing) -> edit removes the round's only line (round voided by the edit)
--   S1..S4 (b001..b004) served + one round in submitted / accepted / preparing / ready
--   S5..S7 (b005..b007) served + one round served / voided / preparing-but-tombstoned
--   S8 (b008) served + a served round 2 AND a submitted round 3
--   T0 (c000) backdated, updated 3 hours ago, nothing else (the cursor control)
--   T1 (c001) backdated 3 hours, a PREPARING round updated 1 hour ago
--   T2 (c002) backdated 3 hours, a SERVED round updated 90 minutes ago
--   T3 (c003) backdated 3 hours, a TOMBSTONED preparing round updated 80 minutes ago
--   E1 (c004) backdated 3 hours, edit_count 1, a pending required edit row updated 30 minutes ago
--   P1 (c005) backdated 3 hours, a completed payment updated 2 hours ago, a served round updated 150 minutes ago
--   E2 (c006) backdated 3 hours, edit_count 1, a TOMBSTONED pending required edit row updated 45 minutes ago
-- Order on branch P: PP (d001) submitted -> edit 1 Cola 1 -> 2 on paper (lands in an edit round).
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000a001', 'preparing', 'PRIVATE NOTE', 'Jane Doe');
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0011', 'b1e00000-0000-0000-0000-00000000a001', 'b1e00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.settle_totals('b1e00000-0000-0000-0000-00000000a001');

select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000a002', 'preparing');
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0021', 'b1e00000-0000-0000-0000-00000000a002', 'b1e00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0022', 'b1e00000-0000-0000-0000-00000000a002', 'b1e00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1e00000-0000-0000-0000-00000000a002');

select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000a003', 'preparing');
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0031', 'b1e00000-0000-0000-0000-00000000a003', 'b1e00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0032', 'b1e00000-0000-0000-0000-00000000a003', 'b1e00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1e00000-0000-0000-0000-00000000a003');

select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000a004', 'preparing');
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0041', 'b1e00000-0000-0000-0000-00000000a004', 'b1e00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0042', 'b1e00000-0000-0000-0000-00000000a004', 'b1e00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1e00000-0000-0000-0000-00000000a004');

select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000a005', 'served');
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0051', 'b1e00000-0000-0000-0000-00000000a005', 'b1e00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f0a5', 'b1e00000-0000-0000-0000-00000000a005', 2, 'preparing');
select pg_temp.mk_item('b1e00000-0000-0000-0000-0000000a0052', 'b1e00000-0000-0000-0000-00000000a005', 'b1e00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'b1e00000-0000-0000-0000-00000000f0a5');
select pg_temp.settle_totals('b1e00000-0000-0000-0000-00000000a005');

select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b001', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f001', 'b1e00000-0000-0000-0000-00000000b001', 2, 'submitted');
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b002', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f002', 'b1e00000-0000-0000-0000-00000000b002', 2, 'accepted');
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b003', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f003', 'b1e00000-0000-0000-0000-00000000b003', 2, 'preparing');
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b004', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f004', 'b1e00000-0000-0000-0000-00000000b004', 2, 'ready');
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b005', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f005', 'b1e00000-0000-0000-0000-00000000b005', 2, 'served');
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b006', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f006', 'b1e00000-0000-0000-0000-00000000b006', 2, 'voided');
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b007', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f007', 'b1e00000-0000-0000-0000-00000000b007', 2, 'preparing', now(), true);
select pg_temp.mk_order('b1e00000-0000-0000-0000-00000000b008', 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f008', 'b1e00000-0000-0000-0000-00000000b008', 2, 'served');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f009', 'b1e00000-0000-0000-0000-00000000b008', 3, 'submitted');

select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c000', 'served', now() - interval '3 hours');
select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c001', 'served', now() - interval '3 hours');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f0c1', 'b1e00000-0000-0000-0000-00000000c001', 2, 'preparing', now() - interval '1 hour');
select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c002', 'served', now() - interval '3 hours');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f0c2', 'b1e00000-0000-0000-0000-00000000c002', 2, 'served', now() - interval '90 minutes');
select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c003', 'served', now() - interval '3 hours');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f0c3', 'b1e00000-0000-0000-0000-00000000c003', 2, 'preparing', now() - interval '80 minutes', true);
select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c004', 'preparing', now() - interval '3 hours', 1);
select pg_temp.mk_edit_row('b1e00000-0000-0000-0000-00000000e0c4', 'b1e00000-0000-0000-0000-00000000c004', now() - interval '30 minutes');
select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c005', 'preparing', now() - interval '3 hours');
select pg_temp.mk_round('b1e00000-0000-0000-0000-00000000f0c5', 'b1e00000-0000-0000-0000-00000000c005', 2, 'served', now() - interval '150 minutes');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id,
  resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id,
  created_at, updated_at) values
  ('b1e00000-0000-0000-0000-00000000a5c5', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
   'b1e00000-0000-0000-0000-0000000000ab', 'b1e00000-0000-0000-0000-00000000c005', 'b1e00000-0000-0000-0000-0000000000d1',
   'b1e00000-0000-0000-0000-00000000008a', 'b1e00000-0000-0000-0000-00000000007a', 'cash', 'completed', 1000, 1000, 0, 'ILS',
   'snap-pay-c005', now() - interval '2 hours', now() - interval '2 hours');
select pg_temp.mk_bd_order('b1e00000-0000-0000-0000-00000000c006', 'preparing', now() - interval '3 hours', 1);
select pg_temp.mk_edit_row('b1e00000-0000-0000-0000-00000000e0c6', 'b1e00000-0000-0000-0000-00000000c006', now() - interval '45 minutes', true);

-- PP on branch P (its own device / PIN stack)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
  subtotal_minor, grand_total_minor, local_operation_id, status) values
  ('b1e00000-0000-0000-0000-00000000d001', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
   'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-0000000000d3', 'b1e00000-0000-0000-0000-00000000009d',
   'b1e00000-0000-0000-0000-00000000008d', 'b1e00000-0000-0000-0000-00000000007d', 'dine_in', 'ILS', 2300, 2300,
   'submit-paper-d001', 'submitted');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor) values
  ('b1e00000-0000-0000-0000-0000000d0011', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
   'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-00000000d001', 'b1e00000-0000-0000-0000-000000001002',
   1, 'Fries', 1500, 0, 1500),
  ('b1e00000-0000-0000-0000-0000000d0012', 'b1e00000-0000-0000-0000-0000000000a0', 'b1e00000-0000-0000-0000-0000000000a1',
   'b1e00000-0000-0000-0000-0000000000ac', 'b1e00000-0000-0000-0000-00000000d001', 'b1e00000-0000-0000-0000-000000001003',
   1, 'Cola', 800, 0, 800);

-- Every pre-read edit, through public.sync_push (order.edit), in this order.
create temp table t_edits (k text, r jsonb);
insert into t_edits select 'r1', pg_temp.edit('b1e00000-0000-0000-0000-00000000009a', 'snap-r-e1', 'b1e00000-0000-0000-0000-00000000a002',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "b1e00000-0000-0000-0000-0000000a0022", "quantity": 2}]}'::jsonb);
insert into t_edits select 'm1', pg_temp.edit('b1e00000-0000-0000-0000-00000000009a', 'snap-m-e1', 'b1e00000-0000-0000-0000-00000000a003',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "add", "item": {"menu_item_id": "b1e00000-0000-0000-0000-000000001003", "quantity": 1,
      "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola"}}]}'::jsonb);
insert into t_edits select 'm2', pg_temp.edit('b1e00000-0000-0000-0000-00000000009a', 'snap-m-e2', 'b1e00000-0000-0000-0000-00000000a003',
  '{"expected": {"subtotal_minor": 4600, "tax_total_minor": 0, "grand_total_minor": 4600},
    "changes": [{"op": "add", "item": {"menu_item_id": "b1e00000-0000-0000-0000-000000001002", "quantity": 1,
      "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb);
insert into t_edits select 'v1', pg_temp.edit('b1e00000-0000-0000-0000-00000000009a', 'snap-v-e1', 'b1e00000-0000-0000-0000-00000000a004',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "b1e00000-0000-0000-0000-0000000a0042", "quantity": 2}]}'::jsonb);
insert into t_edits select 'p1', pg_temp.edit('b1e00000-0000-0000-0000-00000000009d', 'snap-p-e1', 'b1e00000-0000-0000-0000-00000000d001',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "b1e00000-0000-0000-0000-0000000d0012", "quantity": 2}]}'::jsonb,
  'b1e00000-0000-0000-0000-0000000000d3');
-- V is voided by the cashier (the default-on void_order capability) with its edit still unconfirmed.
create temp table t_void as select app.void_order('b1e00000-0000-0000-0000-00000000009a', 'b1e00000-0000-0000-0000-00000000a004',
  'b1e00000-0000-0000-0000-0000000000d1', 'snap-void-v', 'snapshot void with a pending edit') as r;

-- ===== READ 1 (before W's edit and before any acknowledgement) =============
create temp table t_s1 as select pg_temp.snap() as r;
create temp table t_inc_t1 as select pg_temp.snap(now() - interval '3 hours', 'b1e00000-0000-0000-0000-00000000c001') as r;
create temp table t_inc_e1_pre as select pg_temp.snap(now() - interval '30 minutes', 'b1e00000-0000-0000-0000-00000000c004') as r;
create temp table t_paper as select app.pos_order_snapshots(
  p_pin_session_id => 'b1e00000-0000-0000-0000-00000000009d', p_device_id => 'b1e00000-0000-0000-0000-0000000000d3',
  p_limit => 100) as r;
create temp table t_e1_before as select updated_at, revision from orders where id = 'b1e00000-0000-0000-0000-00000000c004';

-- ===== WRITES between the reads ==============================================
-- W: remove the live round's only line (an in-kitchen removal: confirmation required).
insert into t_edits select 'w1', pg_temp.edit('b1e00000-0000-0000-0000-00000000009a', 'snap-w-e1', 'b1e00000-0000-0000-0000-00000000a005',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 800, "tax_total_minor": 0, "grand_total_minor": 800},
    "changes": [{"op": "remove", "order_item_id": "b1e00000-0000-0000-0000-0000000a0052"}]}'::jsonb);
-- The kitchen confirms R's edit and E1's edit (order.edit_ack from the KDS kitchen_staff).
create temp table t_ack_r  as select pg_temp.ack('b1e00000-0000-0000-0000-00000000009c', 'snap-ack-r',  'b1e00000-0000-0000-0000-00000000a002', 1) as r;
create temp table t_ack_e1 as select pg_temp.ack('b1e00000-0000-0000-0000-00000000009c', 'snap-ack-e1', 'b1e00000-0000-0000-0000-00000000c004', 1) as r;

-- ===== READ 2 (after), bracketed by an audit count ===========================
create temp table t_audit0 as select count(*)::int as n from audit_events where organization_id = 'b1e00000-0000-0000-0000-0000000000a0';
create temp table t_s2 as select pg_temp.snap() as r;
create temp table t_inc_e1_post as select pg_temp.snap(now() - interval '30 minutes', 'b1e00000-0000-0000-0000-00000000c004') as r;
create temp table t_tgt as select pg_temp.snap(p_ids => array['b1e00000-0000-0000-0000-00000000a002', 'b1e00000-0000-0000-0000-00000000a004',
  'b1e00000-0000-0000-0000-00000000c004']::uuid[]) as r;
create temp table t_pub as select public.pos_order_snapshots(
  'b1e00000-0000-0000-0000-00000000009a', 'b1e00000-0000-0000-0000-0000000000d1',
  null, null, null, null, null, 100, 2) as r;
create temp table t_bad (k text, r jsonb);
insert into t_bad select 'since_at_only', pg_temp.snap(p_since_at => now());
insert into t_bad select 'since_id_only', pg_temp.snap(p_since_id => 'b1e00000-0000-0000-0000-00000000c001');
insert into t_bad select 'before_at_only', pg_temp.snap(p_before_at => now());
insert into t_bad select 'both', pg_temp.snap(now() - interval '3 hours', 'b1e00000-0000-0000-0000-00000000c001',
  now(), 'b1e00000-0000-0000-0000-00000000c001');
create temp table t_audit1 as select count(*)::int as n from audit_events where organization_id = 'b1e00000-0000-0000-0000-0000000000a0';

-- ===== A. fixture: the real edits ============================================
select is((select string_agg(k || '=' || coalesce(r ->> 'status', 'null'), ',' order by k) from t_edits),
  'm1=applied,m2=applied,p1=applied,r1=applied,v1=applied,w1=applied',
  '01 every fixture edit is applied through sync_push (order.edit)');
select is((select string_agg(o.code || ':' || e.edit_number || ':' || e.kitchen_channel || ':' || e.kitchen_ack_required, ','
                             order by o.code, e.edit_number)
             from order_edits e
             join (values ('M', 'b1e00000-0000-0000-0000-00000000a003'::uuid), ('P', 'b1e00000-0000-0000-0000-00000000d001'),
                          ('R', 'b1e00000-0000-0000-0000-00000000a002'), ('V', 'b1e00000-0000-0000-0000-00000000a004'),
                          ('W', 'b1e00000-0000-0000-0000-00000000a005')) o(code, id) on o.id = e.order_id),
  'M:1:kds:false,M:2:kds:false,P:1:paper:false,R:1:kds:true,V:1:kds:true,W:1:kds:true',
  '02 fixture: R, V and W edits need the kitchen''s confirmation; M''s add-only edits and the paper edit do not');
select ok((select (r ->> 'ok')::boolean from t_void)
      and (select status = 'voided' from orders where id = 'b1e00000-0000-0000-0000-00000000a004')
      and (select kitchen_ack_required and kitchen_ack_at is null
             from order_edits where order_id = 'b1e00000-0000-0000-0000-00000000a004' and edit_number = 1),
  '03 fixture: V is voided while its required edit confirmation is still pending in order_edits');

-- ===== B. the row shape ======================================================
select ok((select (r ->> 'ok')::boolean and r ->> 'entity' = 'order_snapshot' from t_s2)
      and (select count(*) = 20 from jsonb_array_elements((select r from t_s2) -> 'orders')),
  '04 the window read is ok and returns the 20 live orders of branch K');
select ok(not exists (
    select 1 from (select x1 as o from jsonb_array_elements((select r from t_s1) -> 'orders') x1
           union all select x2 from jsonb_array_elements((select r from t_s2) -> 'orders') x2) u
     where (select array_agg(k order by k collate "C") from jsonb_object_keys(o) k)
           is distinct from
           (select array_agg(x order by x collate "C") from unnest(array[
              'order_id', 'order_code', 'revision', 'status', 'order_type', 'table_label', 'currency_code',
              'created_at', 'updated_at', 'sync_at', 'subtotal_minor', 'discount_total_minor', 'tax_total_minor',
              'grand_total_minor', 'payment_status', 'edit_count', 'kitchen_edit_ack_pending', 'has_active_round']) x)),
  '05 every row carries EXACTLY the 15 previous keys + edit_count, kitchen_edit_ack_pending, has_active_round');
select ok((select bool_and(jsonb_typeof(o -> 'edit_count') = 'number'
                           and jsonb_typeof(o -> 'kitchen_edit_ack_pending') = 'boolean'
                           and jsonb_typeof(o -> 'has_active_round') = 'boolean')
             from jsonb_array_elements((select r from t_s2) -> 'orders') o),
  '06 edit_count is a number and both flags are booleans (never null) on every row');
select ok(not exists (select 1 from jsonb_array_elements((select r from t_s2) -> 'orders') o
                       where o ? 'notes' or o ? 'customer_name' or o ? 'customer_phone' or o ? 'device_id'
                          or o ? 'pin_session_id' or o ? 'opened_by_employee_profile_id' or o ? 'resolved_membership_id'
                          or o ? 'organization_id' or o ? 'branch_id' or o ? 'table_id' or o ? 'edits'
                          or o ? 'kitchen_ack_required' or o ? 'dispatch_mode')
      and pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a001') is not null
      and (select (r::text not like '%PRIVATE NOTE%') and (r::text not like '%Jane Doe%') from t_s2),
  '07 still never notes / customer_name / staff, session, device or tenant ids (N carries both, neither leaks)');

-- ===== C. edit_count =========================================================
select ok(not exists (select 1 from jsonb_array_elements((select r from t_s2) -> 'orders') o
                        join orders x on x.id = (o ->> 'order_id')::uuid
                       where (o ->> 'edit_count')::int is distinct from x.edit_count),
  '08 edit_count equals orders.edit_count on every row');
select is((select string_agg(c.code || '=' || (pg_temp.row_of((select r from t_s2), c.id) ->> 'edit_count'), ',' order by c.code)
             from (values ('M', 'b1e00000-0000-0000-0000-00000000a003'::uuid), ('N', 'b1e00000-0000-0000-0000-00000000a001'),
                          ('R', 'b1e00000-0000-0000-0000-00000000a002'), ('V', 'b1e00000-0000-0000-0000-00000000a004'),
                          ('W', 'b1e00000-0000-0000-0000-00000000a005')) c(code, id)),
  'M=2,N=0,R=1,V=1,W=1',
  '09 edit_count after real edits: M 2, N 0, R 1, V 1, W 1');
select is((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a005') ->> 'edit_count')::int, 0,
  '10 W read before its edit: edit_count 0');

-- ===== D. kitchen_edit_ack_pending ===========================================
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a002') ->> 'kitchen_edit_ack_pending')::boolean,
  '11 R after a required edit (set_quantity up on the in-kitchen original ticket): kitchen_edit_ack_pending TRUE');
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack_r)
      and (select kitchen_ack_at = now() and kitchen_ack_by_employee_profile_id = 'b1e00000-0000-0000-0000-00000000008c'
             from order_edits where order_id = 'b1e00000-0000-0000-0000-00000000a002' and edit_number = 1),
  '12 the kitchen acknowledges R through sync_push (order.edit_ack, acknowledged_count 1)');
select ok(not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a002') ->> 'kitchen_edit_ack_pending')::boolean
      and (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a002') ->> 'edit_count')::int = 1,
  '13 R after the acknowledgement: kitchen_edit_ack_pending FALSE (edit_count still 1)');
select ok(not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a001') ->> 'kitchen_edit_ack_pending')::boolean
      and not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a001') ->> 'kitchen_edit_ack_pending')::boolean,
  '14 N (never edited): kitchen_edit_ack_pending FALSE');
select ok(not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a003') ->> 'kitchen_edit_ack_pending')::boolean
      and not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a003') ->> 'kitchen_edit_ack_pending')::boolean,
  '15 M (two edits that did not require confirmation): kitchen_edit_ack_pending FALSE');
select ok((pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a004') ->> 'status') = 'voided'
      and not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a004') ->> 'kitchen_edit_ack_pending')::boolean
      and not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a004') ->> 'kitchen_edit_ack_pending')::boolean,
  '16 V (voided, its required edit never confirmed): kitchen_edit_ack_pending FALSE — the void supersedes it');
select ok(not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a005') ->> 'kitchen_edit_ack_pending')::boolean
      and (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a005') ->> 'kitchen_edit_ack_pending')::boolean,
  '17 W: FALSE before, TRUE after the edit that removed a line from its live round');
select ok(not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c006') ->> 'kitchen_edit_ack_pending')::boolean,
  '18 E2: a TOMBSTONED required, unconfirmed edit row is not pending');

-- ===== E. has_active_round ===================================================
select is((select string_agg(c.code || '=' || (pg_temp.row_of((select r from t_s1), c.id) ->> 'has_active_round'), ',' order by c.code)
             from (values ('S1', 'b1e00000-0000-0000-0000-00000000b001'::uuid), ('S2', 'b1e00000-0000-0000-0000-00000000b002'),
                          ('S3', 'b1e00000-0000-0000-0000-00000000b003'), ('S4', 'b1e00000-0000-0000-0000-00000000b004')) c(code, id)),
  'S1=true,S2=true,S3=true,S4=true',
  '19 a live round in submitted / accepted / preparing / ready: has_active_round TRUE');
select is((select string_agg(c.code || '=' || (pg_temp.row_of((select r from t_s1), c.id) ->> 'has_active_round'), ',' order by c.code)
             from (values ('S5', 'b1e00000-0000-0000-0000-00000000b005'::uuid), ('S6', 'b1e00000-0000-0000-0000-00000000b006'),
                          ('S7', 'b1e00000-0000-0000-0000-00000000b007')) c(code, id)),
  'S5=false,S6=false,S7=false',
  '20 a served, a voided or a tombstoned (preparing) round: has_active_round FALSE');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000b008') ->> 'has_active_round')::boolean,
  '21 a served round 2 beside a submitted round 3: has_active_round TRUE (any live round)');
select ok(not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a001') ->> 'has_active_round')::boolean
      and not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a002') ->> 'has_active_round')::boolean
      and not exists (select 1 from order_service_rounds where order_id in ('b1e00000-0000-0000-0000-00000000a001', 'b1e00000-0000-0000-0000-00000000a002')),
  '22 no round at all (N, and R whose edit landed in place): has_active_round FALSE');
select ok((pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a003') ->> 'has_active_round')::boolean
      and (select count(*) = 2 and bool_and(status = 'submitted' and edit_id is not null)
             from order_service_rounds where order_id = 'b1e00000-0000-0000-0000-00000000a003'),
  '23 M: the rounds its add edits created are submitted, has_active_round TRUE');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000a005') ->> 'has_active_round')::boolean
      and not (pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000a005') ->> 'has_active_round')::boolean
      and (select status = 'voided' and voided_by_edit_id is not null
             from order_service_rounds where id = 'b1e00000-0000-0000-0000-00000000f0a5'),
  '24 W: TRUE with its live round, FALSE once the edit emptied and voided that round');
select ok((select (r ->> 'ok')::boolean from t_paper)
      and (pg_temp.row_of((select r from t_paper), 'b1e00000-0000-0000-0000-00000000d001') ->> 'edit_count')::int = 1
      and not (pg_temp.row_of((select r from t_paper), 'b1e00000-0000-0000-0000-00000000d001') ->> 'kitchen_edit_ack_pending')::boolean
      and (pg_temp.row_of((select r from t_paper), 'b1e00000-0000-0000-0000-00000000d001') ->> 'has_active_round')::boolean
      and (select count(*) = 1 from jsonb_array_elements((select r from t_paper) -> 'orders'))
      and pg_temp.row_of((select r from t_s2), 'b1e00000-0000-0000-0000-00000000d001') is null,
  '25 paper branch: the edit (no confirmation) gives edit_count 1, ack pending FALSE, and its submitted edit round has_active_round TRUE; each branch sees only its own orders');

-- ===== F. THE SYNC STAMP =====================================================
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c001') ->> 'sync_at')::timestamptz = now() - interval '1 hour'
      and (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c001') ->> 'updated_at')::timestamptz = now() - interval '3 hours'
      and (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c001') ->> 'has_active_round')::boolean,
  '26 T1: sync_at is its round''s updated_at (1 hour ago), not the order''s (3 hours ago, still reported as updated_at)');
select ok(pg_temp.row_of((select r from t_inc_t1), 'b1e00000-0000-0000-0000-00000000c001') is not null
      and pg_temp.row_of((select r from t_inc_t1), 'b1e00000-0000-0000-0000-00000000c000') is null
      and (select greatest(o.updated_at, coalesce(p.updated_at, o.updated_at)) = now() - interval '3 hours'
             from orders o left join payments p on p.order_id = o.id and p.status = 'completed' and p.deleted_at is null
            where o.id = 'b1e00000-0000-0000-0000-00000000c001'),
  '27 an incremental read since (3 hours ago, T1) DELIVERS T1 (the old order+payment stamp equals that cursor), and still not T0');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c002') ->> 'sync_at')::timestamptz = now() - interval '90 minutes'
      and not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c002') ->> 'has_active_round')::boolean,
  '28 T2 (monotonic): a SERVED round still raises sync_at to its updated_at though it is not active');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c003') ->> 'sync_at')::timestamptz = now() - interval '80 minutes'
      and not (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c003') ->> 'has_active_round')::boolean,
  '29 T3: a TOMBSTONED round still raises sync_at (no tombstone filter on the max) but is not active');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c004') ->> 'sync_at')::timestamptz = now() - interval '30 minutes'
      and (pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c004') ->> 'kitchen_edit_ack_pending')::boolean,
  '30 E1 before the ack: sync_at is the edit row''s updated_at (30 minutes ago); kitchen_edit_ack_pending TRUE');
select ok((select (r ->> 'ok')::boolean from t_inc_e1_pre)
      and pg_temp.row_of((select r from t_inc_e1_pre), 'b1e00000-0000-0000-0000-00000000c004') is null,
  '31 E1 before the ack: an incremental read with the cursor AT its sync_at does not re-deliver it');
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack_e1)
      and (select updated_at = now() and kitchen_ack_at = now() and kitchen_ack_device_id = 'b1e00000-0000-0000-0000-0000000000d2'
             from order_edits where id = 'b1e00000-0000-0000-0000-00000000e0c4')
      and (select o.updated_at = b.updated_at and o.updated_at = now() - interval '3 hours' and o.revision = b.revision
             from orders o, t_e1_before b where o.id = 'b1e00000-0000-0000-0000-00000000c004'),
  '32 E1 ack through sync_push stamps the edit row (updated_at = now()) and writes NO orders row (updated_at, revision unchanged)');
select ok((pg_temp.row_of((select r from t_inc_e1_post), 'b1e00000-0000-0000-0000-00000000c004') ->> 'sync_at')::timestamptz = now()
      and not (pg_temp.row_of((select r from t_inc_e1_post), 'b1e00000-0000-0000-0000-00000000c004') ->> 'kitchen_edit_ack_pending')::boolean
      and (pg_temp.row_of((select r from t_inc_e1_post), 'b1e00000-0000-0000-0000-00000000c004') ->> 'updated_at')::timestamptz = now() - interval '3 hours'
      and pg_temp.row_of((select r from t_inc_e1_post), 'b1e00000-0000-0000-0000-00000000c001') is null,
  '33 E1 after the ack: the SAME cursor now delivers it with sync_at = now() and kitchen_edit_ack_pending FALSE (T1 stays behind the cursor)');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c006') ->> 'sync_at')::timestamptz = now() - interval '45 minutes',
  '34 E2: a TOMBSTONED edit row still raises sync_at to its updated_at');
select ok((pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c005') ->> 'sync_at')::timestamptz = now() - interval '2 hours'
      and pg_temp.row_of((select r from t_s1), 'b1e00000-0000-0000-0000-00000000c005') ->> 'payment_status' = 'paid',
  '35 P1: the completed payment (2 hours ago) outranks its older served round (150 minutes ago); paid');
select is((select count(*)::int
             from jsonb_array_elements((select r from t_s2) -> 'orders') o
             join orders x on x.id = (o ->> 'order_id')::uuid
            where (o ->> 'sync_at')::timestamptz is distinct from greatest(
                    x.updated_at,
                    coalesce((select max(p.updated_at) from payments p where p.organization_id = x.organization_id
                                and p.order_id = x.id and p.status = 'completed' and p.deleted_at is null), x.updated_at),
                    coalesce((select max(r.updated_at) from order_service_rounds r where r.organization_id = x.organization_id
                                and r.order_id = x.id), x.updated_at),
                    coalesce((select max(e.updated_at) from order_edits e where e.organization_id = x.organization_id
                                and e.order_id = x.id), x.updated_at))),
  0, '36 every row (read 2, the current state): sync_at = greatest(order, completed payment, newest round, newest edit updated_at)');
select ok((select bool_and((o ->> 'sync_at')::timestamptz >= greatest(x.updated_at, coalesce(p.updated_at, x.updated_at)))
             from jsonb_array_elements((select r from t_s2) -> 'orders') o
             join orders x on x.id = (o ->> 'order_id')::uuid
             left join payments p on p.organization_id = x.organization_id and p.order_id = x.id
                                 and p.status = 'completed' and p.deleted_at is null),
  '37 every row: sync_at is never lower than greatest(orders.updated_at, payment updated_at) — stored cursors stay valid');
select ok((select bool_and(prev is null or (prev_at, prev_id) > ((o ->> 'sync_at')::timestamptz, (o ->> 'order_id')::uuid))
             from (select o, lag(o) over (order by n) as prev,
                          (lag(o) over (order by n) ->> 'sync_at')::timestamptz as prev_at,
                          (lag(o) over (order by n) ->> 'order_id')::uuid as prev_id
                     from jsonb_array_elements((select r from t_s2) -> 'orders') with ordinality as t(o, n)) z),
  '38 the window still pages strictly DESCENDING on (the wider sync_at, id)');

-- ===== G. targeted mode, the public wrapper and the unchanged invariants =====
select is((select string_agg(o ->> 'order_id' || ':' || (o ->> 'kitchen_edit_ack_pending') || ':' || (o ->> 'edit_count'), ','
                             order by o ->> 'order_id')
             from jsonb_array_elements((select r from t_tgt) -> 'orders') o),
  'b1e00000-0000-0000-0000-00000000a002:false:1,b1e00000-0000-0000-0000-00000000a004:false:1,b1e00000-0000-0000-0000-00000000c004:false:1',
  '39 targeted mode carries the new keys too (R, V, E1 after the acks / void)');
select ok((select r from t_pub) = (select r from t_s2),
  '40 the public.pos_order_snapshots wrapper passes the widened envelope through unchanged');
select is((select string_agg(k || '=' || coalesce(r ->> 'error', 'null') || '/' || coalesce(r ->> 'ok', 'null'), ',' order by k) from t_bad),
  'before_at_only=invalid_cursor/false,both=invalid_cursor/false,since_at_only=invalid_cursor/false,since_id_only=invalid_cursor/false',
  '41 a half since cursor, a half before cursor and both cursors at once are still refused invalid_cursor');
select ok((select r -> 'orders' is null and r ->> 'entity' = 'order_snapshot' from t_bad where k = 'both'),
  '42 a refused cursor returns the bare error envelope (no rows)');
select is((select n from t_audit1) - (select n from t_audit0), 0,
  '43 the reads (window, incremental, targeted, wrapper, refused) wrote NO audit event');
select ok((select count(*) = 0 from sync_operations
            where organization_id = 'b1e00000-0000-0000-0000-0000000000a0'
              and operation_type not in ('order.edit', 'order.edit_ack')),
  '44 the reads wrote no sync ledger row either (only the fixture edits and acks are ledgered)');

select * from finish();
rollback;
