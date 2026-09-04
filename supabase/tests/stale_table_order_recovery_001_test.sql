-- ============================================================================
-- STALE-TABLE-ORDER-RECOVERY-001 — pgTAP: stale active dine-in orders stay
-- RECOVERABLE through canonical operations; occupancy is DERIVED and is never
-- freed by age, by manual table state, or by a replay.
--
-- Mirrors the 2026-09-04 incident: a KIOSK dine-in order submitted with a
-- table, never paid, aged for days on a printer-only branch. Proves:
--   A. only the canonical ACTIVE dine-in statuses occupy; terminal + takeaway
--      rows never do; old age alone never releases (40-day-old row still counts)
--   B. manual table state cannot fake-release a live order
--   C. pos_tables.active_orders projects the SAME rows, money-free, with the
--      identity a cashier needs to OPEN them (+ the 18-key row contract)
--   D. the canonical recoveries: an unauthorized void is refused with a
--      reason; a manager void releases the table + writes the audit + the
--      printer-only VOID dispatch; a replay of the original kiosk submit can
--      NOT resurrect the voided order
--   E. closed-shift semantics are EXPLICIT: the originating shift being closed
--      never blocks settlement — record_payment needs an OPEN shift on the
--      PAYING device (42501 without one) and attaches the payment to THAT
--      shift; full settlement auto-completes the order and releases the table
--   F. the Dashboard read projects shift_status + kitchen_work_open and stays
--      STABLE (display only); owner_complete_order is NOT a recovery path
--      from `submitted`
-- Fixtures as the BYPASSRLS harness role; hex UUIDs (prefix 9f).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(73);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('9f000000-0000-0000-0000-0000000000a0', 'Stale Org', 'stale-001', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-0000000000a0', 'Stale Rest', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', 'Stale B1', 'UTC');
-- the incident branch runs printer-only (privileged SQL, as the kitchen-mode suites do)
update branches set kitchen_workflow_mode = 'printer_only' where id = '9f000000-0000-0000-0000-00000000a1b1';

insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, status, is_active) values
  ('9f000000-0000-0000-0000-0000000000d1', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'T1', 4, 'available', true),
  ('9f000000-0000-0000-0000-0000000000d2', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'T2', 4, 'available', true),
  ('9f000000-0000-0000-0000-0000000000d3', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'T3', 4, 'available', true),
  ('9f000000-0000-0000-0000-0000000000d4', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'T4', 4, 'available', true),
  ('9f000000-0000-0000-0000-0000000000d5', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'T5', 4, 'available', true),
  ('9f000000-0000-0000-0000-0000000000d6', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'T6', 4, 'available', true);

-- devices: a POS (staff PIN sessions) and the KIOSK that submits the stale order
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'pos',   'Stale POS'),
  ('9f000000-0000-0000-0000-00000000da22', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'kiosk', 'Stale Kiosk');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('9f000000-0000-0000-0000-00000000fa11', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', 'active'),
  ('9f000000-0000-0000-0000-00000000fa22', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, expires_at) values
  ('9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000fa11', app.hash_provisioning_secret('tok-stale-pos'),   true, now() + interval '1 day'),
  ('9f000000-0000-0000-0000-0000000005a2', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da22', '9f000000-0000-0000-0000-00000000fa22', app.hash_provisioning_secret('tok-stale-kiosk'), true, now() + interval '1 day');

-- people: a manager, a cashier whose void capability is OFF, and the org owner (JWT)
insert into auth.users (id, email) values
  ('9f000000-0000-0000-0000-00000000adf1', 'stale-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('9f000000-0000-0000-0000-00000000ee01', 'stale-manager@example.test', null),
  ('9f000000-0000-0000-0000-00000000ee02', 'stale-cashier@example.test', null),
  ('9f000000-0000-0000-0000-00000000ee03', 'stale-owner@example.test',   '9f000000-0000-0000-0000-00000000adf1');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('9f000000-0000-0000-0000-00000000ab01', '9f000000-0000-0000-0000-00000000ee01', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'manager', '{}'::jsonb),
  ('9f000000-0000-0000-0000-00000000ab02', '9f000000-0000-0000-0000-00000000ee02', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', 'cashier', '{"void_order":"false"}'::jsonb),
  ('9f000000-0000-0000-0000-00000000ab03', '9f000000-0000-0000-0000-00000000ee03', '9f000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000ee01', '9f000000-0000-0000-0000-00000000ab01', 'Stale Manager'),
  ('9f000000-0000-0000-0000-0000000ef002', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000ee02', '9f000000-0000-0000-0000-00000000ab02', 'Stale Cashier');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('9f000000-0000-0000-0000-00000000c502', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-0000000005a1', '9f000000-0000-0000-0000-0000000ef002', '9f000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- a menu item the kiosk can order
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('9f000000-0000-0000-0000-00000000c100', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', null, 'Stale Cat', 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('9f000000-0000-0000-0000-000000011701', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', null, '9f000000-0000-0000-0000-00000000c100', 'Stale Burger', 4000, 'ILS', 0, true);
create temp table _items as select jsonb_build_array(jsonb_build_object(
  'menu_item_id', '9f000000-0000-0000-0000-000000011701',
  'menu_item_name_snapshot', 'Stale Burger', 'quantity', 1,
  'unit_price_minor_snapshot', 4000)) as items;

-- a CLOSED originating shift (for the served order) — nothing open yet
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, opened_at, closed_at, local_operation_id) values
  ('9f000000-0000-0000-0000-00000000f001', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', '9f000000-0000-0000-0000-0000000ef001', 'closed', now() - interval '3 days', now() - interval '2 days', 'stale-shift-closed'),
  -- ...and a RECONCILED one (the terminal state after closed): must read as 'closed'
  ('9f000000-0000-0000-0000-00000000f003', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', '9f000000-0000-0000-0000-0000000ef001', 'reconciled', now() - interval '5 days', now() - interval '4 days', 'stale-shift-reconciled');

-- ===== the STALE KIOSK ORDER: submitted through the REAL kiosk path ==========
create temp table k1 as select public.kiosk_submit_order(
  '9f000000-0000-0000-0000-00000000da22', 'tok-stale-kiosk',
  '9f000000-0000-0000-0000-00000000a001', 'kiosk-stale-op-1', 'dine_in',
  '9f000000-0000-0000-0000-0000000000d1', 'ILS', null, null, null,
  (select items from _items), 4000, 0, 0, 4000) as res;
select is((select res ->> 'ok' from k1), 'true', 'fixture: the kiosk dine-in submit on T1 is accepted');
-- ...and it has been sitting there for 40 days (the incident shape, exaggerated)
update orders set created_at = now() - interval '40 days', client_created_at = now() - interval '40 days'
  where id = '9f000000-0000-0000-0000-00000000a001';

-- other rows: a served+unpaid dine-in from the CLOSED shift (T2); a COMPLETED
-- dine-in on T3; a VOIDED dine-in on T4; a historical TAKEAWAY carrying T4.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, shift_id, table_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision, created_at) values
  ('9f000000-0000-0000-0000-00000000a002', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', '9f000000-0000-0000-0000-00000000f001', '9f000000-0000-0000-0000-0000000000d2', 'dine_in', 'served',    'ILS', 2500, 0, 0, 2500, 'stale-o2', 3, now() - interval '3 days'),
  ('9f000000-0000-0000-0000-00000000a003', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', null, '9f000000-0000-0000-0000-0000000000d3', 'dine_in', 'completed', 'ILS', 1000, 0, 0, 1000, 'stale-o3', 5, now() - interval '3 days'),
  ('9f000000-0000-0000-0000-00000000a004', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', null, '9f000000-0000-0000-0000-0000000000d4', 'dine_in', 'voided',    'ILS', 1000, 0, 0, 1000, 'stale-o4', 2, now() - interval '3 days'),
  ('9f000000-0000-0000-0000-00000000a005', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', null, '9f000000-0000-0000-0000-0000000000d4', 'takeaway', 'submitted', 'ILS', 1000, 0, 0, 1000, 'stale-o5', 1, now() - interval '1 hour'),
  -- O6: served + unpaid from the RECONCILED shift (T5); O7: submitted, unpaid, no dispatch (T6) - the kds-leg subject
  ('9f000000-0000-0000-0000-00000000a006', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', '9f000000-0000-0000-0000-00000000f003', '9f000000-0000-0000-0000-0000000000d5', 'dine_in', 'served',    'ILS', 3000, 0, 0, 3000, 'stale-o6', 2, now() - interval '5 days'),
  ('9f000000-0000-0000-0000-00000000a007', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', null, '9f000000-0000-0000-0000-0000000000d6', 'dine_in', 'submitted', 'ILS', 4000, 0, 0, 4000, 'stale-o7', 1, now() - interval '2 hours');

-- helper: the POS floor read as the manager
create function pg_temp.floor_read() returns jsonb language sql as $$
  select app.pos_tables('9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000da11');
$$;
create function pg_temp.tbl(p_label text) returns jsonb language sql as $$
  select e from jsonb_array_elements(pg_temp.floor_read() -> 'tables') e where e ->> 'label' = p_label;
$$;
-- helper: one owner_active_orders row by code, read AS THE ORG OWNER (JWT); restores the harness role
create function pg_temp.owner_row(p_code text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '9f000000-0000-0000-0000-00000000adf1', true);
  perform set_config('request.jwt.claims', '{"sub":"9f000000-0000-0000-0000-00000000adf1","aal":"aal1"}', true);
  select o into v from jsonb_array_elements(public.owner_active_orders('9f000000-0000-0000-0000-0000000000a0') -> 'orders') o where o ->> 'order_code' = p_code;
  perform set_config('role', 'postgres', true);
  return v;
end $$;
-- helper: one order-status hop through the REAL sync_push funnel (manager PIN on the POS)
create function pg_temp.hop(p_op text, p_order uuid, p_to text) returns jsonb language sql as $$
  select public.sync_push('9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000da11',
    jsonb_build_array(jsonb_build_object('local_operation_id', p_op, 'operation_type', 'order.status',
      'target_entity', 'order', 'payload', jsonb_build_object('order_id', p_order, 'new_status', p_to))));
$$;

-- ===== A. only canonical ACTIVE dine-in rows occupy; age is irrelevant ======
select is((pg_temp.tbl('T1') ->> 'active_order_count')::int, 1,
  'A1. a 40-day-old SUBMITTED dine-in order still occupies its table (NO age cutoff)');
select is((pg_temp.tbl('T2') ->> 'active_order_count')::int, 1,
  'A2. a served, unpaid dine-in order occupies its table');
select is((pg_temp.tbl('T3') ->> 'active_order_count')::int, 0,
  'A3. a COMPLETED order releases its table (terminal)');
select is((pg_temp.tbl('T4') ->> 'active_order_count')::int, 0,
  'A4. a VOIDED dine-in and a TAKEAWAY carrying a table_id never occupy');
select is(pg_temp.tbl('T1') ->> 'effective_state', 'occupied',
  'A5. effective_state is derived: occupied while the manual status is available');

-- ===== B. manual table state cannot fake-release a live order ================
create temp table b1 as select app.pos_set_table_status(
  '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000da11',
  '9f000000-0000-0000-0000-0000000000d1', 'available') as res;
select is((select status from tables where id = '9f000000-0000-0000-0000-0000000000d1'), 'available',
  'B1. the manual status write itself is accepted (it is a manual hint)');
select is(pg_temp.tbl('T1') ->> 'effective_state', 'occupied',
  'B2. ...but the table stays OCCUPIED: a live order overrides manual state');
select is((pg_temp.tbl('T1') ->> 'active_order_count')::int, 1,
  'B3. ...and the count is untouched (manual state never edits orders)');

-- ===== C. active_orders: the same rows, projected for recovery ===============
select is(jsonb_array_length(pg_temp.tbl('T1') -> 'active_orders'), 1,
  'C1. T1 projects exactly the ONE order that makes its count');
select is(jsonb_array_length(pg_temp.tbl('T3') -> 'active_orders'), 0,
  'C2. a free table projects an EMPTY array (never null, never a stale row)');
select is(
  (select array(select jsonb_object_keys(pg_temp.tbl('T1') -> 'active_orders' -> 0) order by 1)),
  array['created_at','kitchen_work_open','order_code','order_id','order_type','payment_status','revision','shift_status','status'],
  'C3. an active_orders entry pins EXACTLY its nine identity/state keys');
select ok(
  not exists (
    select 1 from jsonb_object_keys(pg_temp.tbl('T1') -> 'active_orders' -> 0) k
    where k ~* 'minor|amount|total|receipt|price'),
  'C4. active_orders is MONEY-FREE (every PIN role reads the floor)');
select is(pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'order_id', '9f000000-0000-0000-0000-00000000a001',
  'C5. the entry names the order id the POS needs for the by-id snapshot fetch');
select is(pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'order_code', '#00A001',
  'C6. the display code is the canonical last-6-hex code');
select is(pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'payment_status', 'unpaid',
  'C7. payment_status comes from the ONE settlement predicate (unpaid)');
select is(pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'shift_status', null,
  'C8. a kiosk order carries NO shift (shift_status null, not fabricated)');
select is(pg_temp.tbl('T2') -> 'active_orders' -> 0 ->> 'shift_status', 'closed',
  'C9. an order from a CLOSED shift says so');
select is((pg_temp.tbl('T2') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, false,
  'C10. printer-only, no open dispatch, no round: the kitchen holds nothing');
select is(
  (select count(*) from jsonb_object_keys(pg_temp.tbl('T1')))::int, 18,
  'C11. the pos_tables row contract is now EIGHTEEN keys (the 17 prior + active_orders)');
select is(pg_temp.tbl('T5') -> 'active_orders' -> 0 ->> 'shift_status', 'closed',
  'C12. a RECONCILED originating shift is normalized to closed (never the raw enum)');
select is((pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, true,
  'C13. the kiosk submit left an UNRESOLVED initial dispatch: the kitchen holds it (open-dispatch disjunct)');
update kitchen_print_dispatches set completed_at = now(), last_client_status = 'transport_accepted'
  where order_id = '9f000000-0000-0000-0000-00000000a001' and completed_at is null;
select is((pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, false,
  'C14. ...and once that dispatch completes (the incident shape) the kitchen holds nothing');
select is((pg_temp.tbl('T6') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, false,
  'C15. printer-only + no dispatch + no round: a submitted order has no live kitchen work');
select is(pg_temp.owner_row('#00A006') ->> 'shift_status', 'closed',
  'C16. owner_active_orders: the reconciled shift reads closed');
select is(pg_temp.owner_row('#00A002') ->> 'shift_status', 'closed',
  'C17. owner_active_orders: the closed shift reads closed');
select is(pg_temp.owner_row('#00A005') ->> 'shift_status', null,
  'C18. owner_active_orders: no shift reads null');
select is((pg_temp.owner_row('#00A007') ->> 'kitchen_work_open')::boolean, false,
  'C19. owner_active_orders: printer-only, nothing held -> false');

-- ===== E1/E2. with NO open shift on the paying device, settlement is refused (precondition) =====
select throws_ok(
  $$ select app.record_payment('9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000a002',
       '9f000000-0000-0000-0000-00000000da11', 'stale-pay-noshift', 'cash', 2500, null, null) $$,
  '42501', null,
  'E1. with NO open shift on the paying device, settlement is refused (precondition), never faked');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a002'), 'served',
  'E2. ...and the served order is untouched');

-- ===== K. the KDS leg: the mode flips the kitchen predicate; a PAID but still-active order =====
update branches set kitchen_workflow_mode = 'kds' where id = '9f000000-0000-0000-0000-00000000a1b1';
select is((pg_temp.tbl('T6') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, true,
  'K1. kds mode: a SUBMITTED order is a live KDS ticket (kds disjunct) even with no dispatch');
select is((pg_temp.tbl('T5') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, false,
  'K2. kds mode: a SERVED order is no longer with the kitchen');
select is((pg_temp.owner_row('#00A007') ->> 'kitchen_work_open')::boolean, true,
  'K3. owner_active_orders agrees (kds, submitted -> true)');
-- the manager opens today's shift + drawer on the POS (needed for any settlement)
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, status, opened_at, local_operation_id) values
  ('9f000000-0000-0000-0000-00000000f002', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-0000000ef001', '9f000000-0000-0000-0000-00000000ab01', 'open', now(), 'stale-shift-open');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, status, opened_at, local_operation_id) values
  ('9f000000-0000-0000-0000-00000000cd02', '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-0000000000a1', '9f000000-0000-0000-0000-00000000a1b1', '9f000000-0000-0000-0000-00000000da11', '9f000000-0000-0000-0000-00000000f002', '9f000000-0000-0000-0000-0000000ef001', 0, 'active', now(), 'stale-drawer-open');
create temp table kk1 as select app.record_payment(
  '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000a007',
  '9f000000-0000-0000-0000-00000000da11', 'stale-pay-o7', 'cash', 4000, null, null) as res;
select is((select res ->> 'ok' from kk1), 'true', 'K4. kds mode: paying a SUBMITTED order is accepted');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a007'), 'submitted',
  'K5. ...but kds mode does NOT auto-complete before served: the order is PAID and still ACTIVE');
select is(pg_temp.tbl('T6') -> 'active_orders' -> 0 ->> 'payment_status', 'paid',
  'K6. the floor now says paid (the ONE settlement predicate) and the table is still occupied');
select is((pg_temp.tbl('T6') ->> 'active_order_count')::int, 1, 'K7. ...occupied indeed');
create temp table kk2 as select app.void_order(
  '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000a007',
  '9f000000-0000-0000-0000-00000000da11', 'stale-void-o7', 'trying to cancel a paid order', null) as res;
select is((select res ->> 'ok' from kk2), 'false', 'K8. a PAID order can NOT be voided...');
select is((select res ->> 'detail' from kk2), 'order_has_completed_payment',
  'K9. ...with the exact refusal (order_has_completed_payment) for the UI to surface');
select is((pg_temp.tbl('T6') ->> 'active_order_count')::int, 1, 'K10. the refusal mutated nothing');
-- the canonical exit for paid + active in kds mode: the kitchen lifecycle to served, which auto-completes
select is((pg_temp.hop('stale-hop-1', '9f000000-0000-0000-0000-00000000a007', 'accepted') -> 'results' -> 0 ->> 'status'), 'applied', 'K11. submitted -> accepted');
select is((pg_temp.hop('stale-hop-2', '9f000000-0000-0000-0000-00000000a007', 'preparing') -> 'results' -> 0 ->> 'status'), 'applied', 'K12. accepted -> preparing');
select is((pg_temp.hop('stale-hop-3', '9f000000-0000-0000-0000-00000000a007', 'ready') -> 'results' -> 0 ->> 'status'), 'applied', 'K13. preparing -> ready');
select is((pg_temp.hop('stale-hop-4', '9f000000-0000-0000-0000-00000000a007', 'served') -> 'results' -> 0 ->> 'status'), 'applied', 'K14. ready -> served');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a007'), 'completed',
  'K15. served + paid AUTO-COMPLETES (the canonical repair for paid-but-active)');
select is((pg_temp.tbl('T6') ->> 'active_order_count')::int, 0, 'K16. ...and the table is released');
update branches set kitchen_workflow_mode = 'printer_only' where id = '9f000000-0000-0000-0000-00000000a1b1';
select is((pg_temp.tbl('T1') -> 'active_orders' -> 0 ->> 'kitchen_work_open')::boolean, false,
  'K17. back in printer-only the completed-dispatch order reads not-held again (the mode is read per call)');

-- ===== D. canonical recovery: refusal with a reason, then the manager void ===
create temp table d1 as select app.void_order(
  '9f000000-0000-0000-0000-00000000c502', '9f000000-0000-0000-0000-00000000a001',
  '9f000000-0000-0000-0000-00000000da11', 'stale-void-cashier', 'wrong table', null) as res;
select is((select res ->> 'ok' from d1), 'false',
  'D1. a cashier WITHOUT the void capability is refused...');
select is((select res ->> 'error' from d1), 'permission_denied',
  'D2. ...with the exact reason (permission_denied) for the UI to surface');
select is((pg_temp.tbl('T1') ->> 'active_order_count')::int, 1,
  'D3. ...and the table stays occupied (a refusal mutates nothing)');

create temp table d2 as select app.void_order(
  '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000a001',
  '9f000000-0000-0000-0000-00000000da11', 'stale-void-manager', 'abandoned kiosk order', null) as res;
select is((select res ->> 'ok' from d2), 'true',
  'D4. the manager void of the unpaid stale order is ACCEPTED (canonical recovery)');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a001'), 'voided',
  'D5. the order is voided by the canonical operation (never a direct status edit)');
select is((pg_temp.tbl('T1') ->> 'active_order_count')::int, 0,
  'D6. the table is RELEASED as a consequence of the transition');
select is(pg_temp.tbl('T1') ->> 'effective_state', 'available',
  'D7. ...and reads available again (derived, not edited)');
select is(jsonb_array_length(pg_temp.tbl('T1') -> 'active_orders'), 0,
  'D8. ...with nothing left to recover');
select ok(exists (
    select 1 from audit_events
    where organization_id = '9f000000-0000-0000-0000-0000000000a0'
      and action = 'order.voided'
      and reason = 'abandoned kiosk order'
      and old_values ->> 'status' = 'submitted'
      and new_values ->> 'status' = 'voided'
      and device_id = '9f000000-0000-0000-0000-00000000da11'
      and actor_employee_profile_id = '9f000000-0000-0000-0000-0000000ef001'),
  'D9. the recovery is AUDITED (order.voided: reason, actor, device, submitted -> voided)');
select ok(exists (
    select 1 from kitchen_print_dispatches
    where organization_id = '9f000000-0000-0000-0000-0000000000a0'
      and order_id = '9f000000-0000-0000-0000-00000000a001'
      and dispatch_type = 'void'),
  'D10. printer-only: the void produced the durable VOID kitchen dispatch');

-- replay of the ORIGINAL kiosk submit (same device, same local_operation_id)
create temp table d3 as select public.kiosk_submit_order(
  '9f000000-0000-0000-0000-00000000da22', 'tok-stale-kiosk',
  '9f000000-0000-0000-0000-00000000a001', 'kiosk-stale-op-1', 'dine_in',
  '9f000000-0000-0000-0000-0000000000d1', 'ILS', null, null, null,
  (select items from _items), 4000, 0, 0, 4000) as res;
select is((select res ->> 'idempotency_replay' from d3), 'true',
  'D11. re-sending the original submit is recognised as an idempotent REPLAY');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a001'), 'voided',
  'D12. ...and it can NOT resurrect the voided order');
select is((pg_temp.tbl('T1') ->> 'active_order_count')::int, 0,
  'D13. ...so the table stays free');

-- ===== E. closed-shift semantics are EXPLICIT (the open shift + drawer were opened in K) =====
-- (E1/E2 ran above, BEFORE any shift was open)
create temp table e1 as select app.record_payment(
  '9f000000-0000-0000-0000-00000000c501', '9f000000-0000-0000-0000-00000000a002',
  '9f000000-0000-0000-0000-00000000da11', 'stale-pay-1', 'cash', 2500, null, null) as res;
select is((select res ->> 'ok' from e1), 'true',
  'E3. the served order from the CLOSED shift is settled under TODAY''S open shift');
select is((select shift_id from payments where order_id = '9f000000-0000-0000-0000-00000000a002' and status = 'completed'),
  '9f000000-0000-0000-0000-00000000f002',
  'E4. the payment is attached to the PAYING device''s open shift, never to the closed one');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a002'), 'completed',
  'E5. full settlement AUTO-COMPLETES the order (served + paid)');
select is((pg_temp.tbl('T2') ->> 'active_order_count')::int, 0,
  'E6. ...which releases the table');
select is((select string_agg(upper(right(id::text, 6)), ',' order by id) from orders where organization_id = '9f000000-0000-0000-0000-0000000000a0' and table_id is not null and order_type = 'dine_in' and deleted_at is null and status in ('submitted','accepted','preparing','ready','served')), '00A006',
  'E7. the ONLY dine-in row still occupying is the untouched served+unpaid O6: every other release came from a canonical transition, none from editing table_id/status');

-- ===== F. the Dashboard read: flags only, never a mutation ===================
set local role authenticated;
set local request.jwt.claim.sub = '9f000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"9f000000-0000-0000-0000-00000000adf1","aal":"aal1"}';
create temp table f1 as select public.owner_active_orders('9f000000-0000-0000-0000-0000000000a0') as res;
create temp table f2 as select public.owner_complete_order(
  '9f000000-0000-0000-0000-0000000000a0', '9f000000-0000-0000-0000-00000000a005', null) as res;
reset role;
select ok(
  (select bool_and((o ? 'shift_status') and (o ? 'kitchen_work_open')) from f1, lateral jsonb_array_elements(res -> 'orders') o),
  'F1. every owner_active_orders row carries the additive shift_status + kitchen_work_open flags');
select is(
  (select o ->> 'shift_status' from f1, lateral jsonb_array_elements(res -> 'orders') o where o ->> 'order_code' = '#00A006'), 'closed',
  'F1b. ...with VALUES: the reconciled-shift order reads closed');
select is(
  (select (o ->> 'kitchen_work_open')::boolean from f1, lateral jsonb_array_elements(res -> 'orders') o where o ->> 'order_code' = '#00A006'), false,
  'F1c. ...and a served printer-only order holds no kitchen work');
select is(
  (select o ->> 'shift_status' from f1, lateral jsonb_array_elements(res -> 'orders') o where o ->> 'order_code' = '#00A005'), null,
  'F1d. ...and a shift-less order reads null, never a fabricated state');
select is((select res ->> 'ok' from f2), 'false',
  'F2. owner_complete_order from SUBMITTED is refused...');
select is((select res ->> 'error' from f2), 'invalid_transition',
  'F3. ...as an invalid transition: the Dashboard has NO fake recovery for a submitted order');
select is((select status from orders where id = '9f000000-0000-0000-0000-00000000a005'), 'submitted',
  'F4. ...and the order is untouched');
select ok(
  (select provolatile = 's' from pg_proc where proname = 'pos_tables' and pronamespace = 'app'::regnamespace)
  and (select provolatile = 's' from pg_proc where proname = 'owner_active_orders' and pronamespace = 'app'::regnamespace),
  'F5. both reads stay STABLE: they structurally cannot mutate an order or a table');

select * from finish();
rollback;
