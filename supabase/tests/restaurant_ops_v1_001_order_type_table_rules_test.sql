-- ============================================================================
-- RESTAURANT-OPERATIONS-V1-001 — pgTAP: order-type table rules at submit,
-- availability-at-acceptance, replay stability, takeaway lifecycle, occupancy
-- ============================================================================
-- Covers: valid dine-in creation with a live branch table; dine_in without a
-- table (table_required); takeaway with a table (table_not_allowed); takeaway
-- without one (ok, table_id null); foreign-branch / inactive / tombstoned /
-- unknown tables (one identical table_not_available, R-003) with NO row
-- created; item_unavailable at acceptance naming the blocked line, with NO
-- partial order; a mixed cart is blocked whole; recovery after re-enable;
-- idempotency-replay stability against TIME-VARYING state (table deactivated /
-- item sold out AFTER first acceptance still replays ok); the takeaway
-- lifecycle rides the UNCHANGED machinery (served stays active unpaid;
-- picked-up-then-paid and paid-then-picked-up both auto-complete; zero-total
-- completes not-chargeable with NO payment row; illegal step refused); legacy
-- tableless dine-in rows remain insertable/updatable (no schema constraint);
-- pos_tables/list_tables carry honest DERIVED active_order_count (multiple
-- active orders per table are valid; terminal orders release occupancy);
-- catalog: the partial index exists and submit_order has no overloads.
-- Fixtures as the BYPASSRLS connection role; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(33);

-- ===== fixture: org A — Rest A1, branches B1 + B2; cashier stack on B1 ======
insert into organizations (id, name, slug, default_currency) values
  ('7b000000-0000-0000-0000-0000000000a0', 'Org A', 'ropsv1b-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', 'Branch B1'),
  ('7b000000-0000-0000-0000-00000000a1b2', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', 'Branch B2');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7b000000-0000-0000-0000-00000000da11', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7b000000-0000-0000-0000-00000000fa11', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('7b000000-0000-0000-0000-0000000005a1', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-00000000da11', '7b000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('7b000000-0000-0000-0000-00000000ee03', 'ropsv1b-cashier@example.test'),
  ('7b000000-0000-0000-0000-00000000ee01', 'ropsv1b-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7b000000-0000-0000-0000-00000000ab03', '7b000000-0000-0000-0000-00000000ee03', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('7b000000-0000-0000-0000-00000000ab01', '7b000000-0000-0000-0000-00000000ee01', '7b000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7b000000-0000-0000-0000-0000000ef003', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-00000000ee03', '7b000000-0000-0000-0000-00000000ab03', 'Casey Cashier');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-0000000005a1', '7b000000-0000-0000-0000-0000000ef003', '7b000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- tables: T1 live B1, T2 inactive B1, T3 tombstoned B1, T4 live in SIBLING B2, T5 live B1 (empty).
insert into tables (id, organization_id, restaurant_id, branch_id, label, status, is_active, deleted_at) values
  ('7b000000-0000-0000-0000-0000000c0b01', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', 'T1', 'available', true,  null),
  ('7b000000-0000-0000-0000-0000000c0b02', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', 'T2', 'available', false, null),
  ('7b000000-0000-0000-0000-0000000c0b03', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', 'T3', 'available', true,  now()),
  ('7b000000-0000-0000-0000-0000000c0b04', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b2', 'T4', 'available', true,  null),
  ('7b000000-0000-0000-0000-0000000c0b05', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', 'T5', 'available', true,  null);

-- menu: category + I1 (sellable) + I2 (sold out in B1 via a fixture override row).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7b000000-0000-0000-0000-00000000ca01', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('7b000000-0000-0000-0000-0000000000f1', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', null, '7b000000-0000-0000-0000-00000000ca01', 'Falafel', 2500, 'ILS', 1),
  ('7b000000-0000-0000-0000-0000000000f2', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', null, '7b000000-0000-0000-0000-00000000ca01', 'Shakshuka', 3800, 'ILS', 2);
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1', '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-0000000000f2', 'unavailable', 'sold_out');

-- ===== (1-4) dine-in acceptance: valid table required and validated ==========
create temp table t_b1 as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0001',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-1', 'dine_in',
  '7b000000-0000-0000-0000-0000000c0b01', null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 1,
    'unit_price_minor_snapshot', 2500)),
  2500, 0, 0, 2500) as res;
select is((select (res->>'ok')::boolean from t_b1), true,
  'a dine-in order with a live table of the session branch is ACCEPTED');
select is(
  (select order_type || '|' || table_id::text || '|' || status
     from orders where id = '7b000000-0000-0000-0000-0000000d0001'),
  'dine_in|7b000000-0000-0000-0000-0000000c0b01|submitted',
  'the stored row carries dine_in + the table + status submitted');
select is(
  (select new_values->>'order_type' || '|' || (new_values->>'table_id')
     from audit_events
    where organization_id = '7b000000-0000-0000-0000-0000000000a0'
      and action = 'order.submitted'
      and new_values->>'order_id' = '7b000000-0000-0000-0000-0000000d0001'),
  'dine_in|7b000000-0000-0000-0000-0000000c0b01',
  'the order.submitted audit still carries order_type + table_id');
create temp table t_b2 as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0002',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-2', 'dine_in',
  null, null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 1,
    'unit_price_minor_snapshot', 2500)),
  2500, 0, 0, 2500) as res;
select is((select res->>'error' from t_b2), 'table_required',
  'a NEW dine-in order without a table is refused: table_required');

-- ===== (5-7) takeaway: no table, and a contradictory table is refused ========
create temp table t_b3 as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0003',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-3', 'takeaway',
  '7b000000-0000-0000-0000-0000000c0b01', null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 1,
    'unit_price_minor_snapshot', 2500)),
  2500, 0, 0, 2500) as res;
select is((select res->>'error' from t_b3), 'table_not_allowed',
  'takeaway + a table payload is refused: table_not_allowed (never silently fixed)');
create temp table t_b4 as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0004',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-4', 'takeaway',
  null, null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 2,
    'unit_price_minor_snapshot', 2500)),
  5000, 0, 0, 5000) as res;
select is((select (res->>'ok')::boolean from t_b4), true,
  'a takeaway order without a table is ACCEPTED');
select is(
  (select order_type || '|' || coalesce(table_id::text, 'NULL')
     from orders where id = '7b000000-0000-0000-0000-0000000d0004'),
  'takeaway|NULL', 'the stored takeaway row carries NO table');

-- ===== (8-12) invalid tables: foreign / inactive / tombstoned / unknown ======
create temp table t_bad_tables as select
  (app.submit_order('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0005',
    '7b000000-0000-0000-0000-00000000da11', 'rops-b-5', 'dine_in',
    '7b000000-0000-0000-0000-0000000c0b04', null, 'ILS', null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500)),
    2500, 0, 0, 2500)) as foreign_branch,
  (app.submit_order('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0006',
    '7b000000-0000-0000-0000-00000000da11', 'rops-b-6', 'dine_in',
    '7b000000-0000-0000-0000-0000000c0b02', null, 'ILS', null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500)),
    2500, 0, 0, 2500)) as inactive,
  (app.submit_order('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0007',
    '7b000000-0000-0000-0000-00000000da11', 'rops-b-7', 'dine_in',
    '7b000000-0000-0000-0000-0000000c0b03', null, 'ILS', null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500)),
    2500, 0, 0, 2500)) as tombstoned,
  (app.submit_order('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0008',
    '7b000000-0000-0000-0000-00000000da11', 'rops-b-8', 'dine_in',
    '7b000000-0000-0000-0000-000000000bad', null, 'ILS', null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500)),
    2500, 0, 0, 2500)) as unknown;
select is((select foreign_branch->>'error' from t_bad_tables), 'table_not_available',
  'a SIBLING-BRANCH table is refused (cross-branch assignment unreachable)');
select is((select inactive->>'error' from t_bad_tables), 'table_not_available',
  'an is_active=false table is refused');
select is((select tombstoned->>'error' from t_bad_tables), 'table_not_available',
  'a tombstoned table is refused');
select is((select unknown->>'error' from t_bad_tables), 'table_not_available',
  'an unknown table id gets the SAME refusal (no existence oracle, R-003)');
select is(
  (select count(*)::int from orders
    where organization_id = '7b000000-0000-0000-0000-0000000000a0'
      and local_operation_id in ('rops-b-2','rops-b-3','rops-b-5','rops-b-6','rops-b-7','rops-b-8')),
  0, 'NONE of the refused submissions created an order row');

-- ===== (13-17) availability at acceptance =====================================
create temp table t_unavail as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0009',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-9', 'dine_in',
  '7b000000-0000-0000-0000-0000000c0b01', null, 'ILS', null,
  jsonb_build_array(
    jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500),
    jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f2',
      'menu_item_name_snapshot', 'Shakshuka', 'quantity', 1, 'unit_price_minor_snapshot', 3800)),
  6300, 0, 0, 6300) as res;
select is((select res->>'error' from t_unavail), 'item_unavailable',
  'a cart containing a sold-out item is refused whole: item_unavailable');
select is(
  (select res->'items' from t_unavail),
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f2',
    'name', 'Shakshuka', 'reason', 'sold_out')),
  'the refusal NAMES exactly the blocked line: id + snapshot name + structured reason');
select is(
  (select count(*)::int from orders where id = '7b000000-0000-0000-0000-0000000d0009')
  + (select count(*)::int from order_items
      where organization_id = '7b000000-0000-0000-0000-0000000000a0'
        and order_id = '7b000000-0000-0000-0000-0000000d0009'),
  0, 'NO partial order: neither the header nor any line was created');
-- re-enable and retry the SAME payload under a fresh op id -> accepted.
update menu_item_branch_availability
  set availability = 'available', reason = null
  where organization_id = '7b000000-0000-0000-0000-0000000000a0'
    and menu_item_id = '7b000000-0000-0000-0000-0000000000f2';
create temp table t_avail as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d000a',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-10', 'dine_in',
  '7b000000-0000-0000-0000-0000000c0b01', null, 'ILS', null,
  jsonb_build_array(
    jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500),
    jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f2',
      'menu_item_name_snapshot', 'Shakshuka', 'quantity', 1, 'unit_price_minor_snapshot', 3800)),
  6300, 0, 0, 6300) as res;
select is((select (res->>'ok')::boolean from t_avail), true,
  'after the manager re-enables the item, the corrected retry is ACCEPTED');
select is(
  (select count(*)::int from order_items
    where organization_id = '7b000000-0000-0000-0000-0000000000a0'
      and order_id = '7b000000-0000-0000-0000-0000000d000a'),
  2, 'the accepted retry stored BOTH lines');

-- ===== (18-19) idempotency replay is stable against time-varying state =======
-- deactivate the accepted order's table, then replay the EXACT same op.
update tables set is_active = false where id = '7b000000-0000-0000-0000-0000000c0b01';
create temp table t_replay1 as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0001',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-1', 'dine_in',
  '7b000000-0000-0000-0000-0000000c0b01', null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 1,
    'unit_price_minor_snapshot', 2500)),
  2500, 0, 0, 2500) as res;
select ok(
  (select (res->>'ok')::boolean and (res->>'idempotency_replay')::boolean from t_replay1),
  'an ALREADY-ACCEPTED op replays ok even after its table was deactivated');
-- restore the table; sell out an item of the accepted order and replay again.
update tables set is_active = true where id = '7b000000-0000-0000-0000-0000000c0b01';
update menu_item_branch_availability
  set availability = 'unavailable', reason = 'sold_out'
  where organization_id = '7b000000-0000-0000-0000-0000000000a0'
    and menu_item_id = '7b000000-0000-0000-0000-0000000000f2';
create temp table t_replay2 as select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d000a',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-10', 'dine_in',
  '7b000000-0000-0000-0000-0000000c0b01', null, 'ILS', null,
  jsonb_build_array(
    jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
      'menu_item_name_snapshot', 'Falafel', 'quantity', 1, 'unit_price_minor_snapshot', 2500),
    jsonb_build_object('menu_item_id', '7b000000-0000-0000-0000-0000000000f2',
      'menu_item_name_snapshot', 'Shakshuka', 'quantity', 1, 'unit_price_minor_snapshot', 3800)),
  6300, 0, 0, 6300) as res;
select ok(
  (select (res->>'ok')::boolean and (res->>'idempotency_replay')::boolean from t_replay2),
  'an ALREADY-ACCEPTED op replays ok even after one of its items sold out');
update menu_item_branch_availability
  set availability = 'available', reason = null
  where organization_id = '7b000000-0000-0000-0000-0000000000a0'
    and menu_item_id = '7b000000-0000-0000-0000-0000000000f2';

-- ===== (20-26) takeaway lifecycle rides the UNCHANGED machinery ==============
select app.open_shift('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000cff01',
                      '7b000000-0000-0000-0000-0000000cdd01', '7b000000-0000-0000-0000-00000000da11', 'rops-sh', 0);
-- TW-A (order d0004, takeaway, 5000): picked up first, then paid.
select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                               '7b000000-0000-0000-0000-0000000d0004', 'accepted',  'rops-tw-a1');
select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                               '7b000000-0000-0000-0000-0000000d0004', 'preparing', 'rops-tw-a2');
select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                               '7b000000-0000-0000-0000-0000000d0004', 'ready',     'rops-tw-a3');
create temp table t_tw_served as
  select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                                 '7b000000-0000-0000-0000-0000000d0004', 'served',    'rops-tw-a4') as res;
select ok(
  (select (res->>'ok')::boolean and res->>'status' = 'served'
      and (res->>'auto_completed')::boolean = false from t_tw_served),
  'takeaway: the persisted picked-up state IS served — unpaid, it stays ACTIVE (no new status)');
create temp table t_tw_paid as
  select app.record_payment('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d0004',
                            '7b000000-0000-0000-0000-00000000da11', 'rops-tw-a5', 'cash', 5000, null) as res;
select ok(
  (select (res->>'ok')::boolean and (res->>'auto_completed')::boolean
      and res->>'order_status' = 'completed' from t_tw_paid),
  'takeaway picked up FIRST then paid -> auto-completes on the payment');
-- TW-B (fresh takeaway): paid first, then picked up.
select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d000b',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-11', 'takeaway',
  null, null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 1,
    'unit_price_minor_snapshot', 2500)),
  2500, 0, 0, 2500);
create temp table t_twb_paid as
  select app.record_payment('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d000b',
                            '7b000000-0000-0000-0000-00000000da11', 'rops-tw-b1', 'cash', 2500, null) as res;
select ok(
  (select (res->>'ok')::boolean and (res->>'auto_completed')::boolean = false
      and res->>'order_status' = 'submitted' from t_twb_paid),
  'takeaway paid BEFORE pickup does NOT complete (the kitchen still owes food)');
select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                               '7b000000-0000-0000-0000-0000000d000b', 'accepted',  'rops-tw-b2');
select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                               '7b000000-0000-0000-0000-0000000d000b', 'preparing', 'rops-tw-b3');
select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                               '7b000000-0000-0000-0000-0000000d000b', 'ready',     'rops-tw-b4');
create temp table t_twb_served as
  select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                                 '7b000000-0000-0000-0000-0000000d000b', 'served',    'rops-tw-b5') as res;
select ok(
  (select (res->>'ok')::boolean and res->>'status' = 'completed'
      and (res->>'auto_completed')::boolean from t_twb_served)
  and (select status = 'completed' from orders where id = '7b000000-0000-0000-0000-0000000d000b'),
  'takeaway paid first then picked up -> the served step auto-completes');
-- TW-C zero-total at ready (fixture): the not-chargeable pickup completes with NO payment.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
                    opened_by_employee_profile_id, resolved_membership_id, order_type, status,
                    currency_code, subtotal_minor, discount_total_minor, tax_total_minor,
                    grand_total_minor, local_operation_id, revision) values
  ('7b000000-0000-0000-0000-0000000d000c', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1',
   '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-00000000da11', '7b000000-0000-0000-0000-00000000c501',
   '7b000000-0000-0000-0000-0000000ef003', '7b000000-0000-0000-0000-00000000ab03', 'takeaway', 'ready',
   'ILS', 0, 0, 0, 0, 'rops-tw-c0', 1);
create temp table t_twc_served as
  select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                                 '7b000000-0000-0000-0000-0000000d000c', 'served', 'rops-tw-c1') as res;
select ok(
  (select (res->>'ok')::boolean and res->>'status' = 'completed' from t_twc_served)
  and (select count(*)::int from payments
        where order_id = '7b000000-0000-0000-0000-0000000d000c') = 0,
  'zero-total takeaway pickup completes not-chargeable with NO payment row fabricated');
-- TW-D illegal step: a fresh takeaway cannot jump submitted -> ready.
select app.submit_order(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-0000000d000d',
  '7b000000-0000-0000-0000-00000000da11', 'rops-b-12', 'takeaway',
  null, null, 'ILS', null,
  jsonb_build_array(jsonb_build_object(
    'menu_item_id', '7b000000-0000-0000-0000-0000000000f1',
    'menu_item_name_snapshot', 'Falafel', 'quantity', 1,
    'unit_price_minor_snapshot', 2500)),
  2500, 0, 0, 2500);
create temp table t_twd as
  select app.update_order_status('7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11',
                                 '7b000000-0000-0000-0000-0000000d000d', 'ready', 'rops-tw-d1') as res;
select is((select res->>'error' from t_twd), 'invalid_transition',
  'takeaway obeys the SAME single-step machine: submitted -> ready is refused');

-- ===== (27-28) legacy compatibility: tableless dine-in rows stay valid =======
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
                    opened_by_employee_profile_id, resolved_membership_id, order_type, status,
                    currency_code, subtotal_minor, discount_total_minor, tax_total_minor,
                    grand_total_minor, local_operation_id, revision) values
  ('7b000000-0000-0000-0000-0000000d000e', '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1',
   '7b000000-0000-0000-0000-00000000a1b1', '7b000000-0000-0000-0000-00000000da11', '7b000000-0000-0000-0000-00000000c501',
   '7b000000-0000-0000-0000-0000000ef003', '7b000000-0000-0000-0000-00000000ab03', 'dine_in', 'served',
   'ILS', 900, 0, 0, 900, 'rops-legacy', 1);
select is(
  (select count(*)::int from orders where id = '7b000000-0000-0000-0000-0000000d000e'
     and table_id is null and order_type = 'dine_in'),
  1, 'a LEGACY tableless dine-in row inserts cleanly (no schema constraint was added)');
update orders set notes = 'legacy touch' where id = '7b000000-0000-0000-0000-0000000d000e';
select is(
  (select notes from orders where id = '7b000000-0000-0000-0000-0000000d000e'),
  'legacy touch', 'a LEGACY tableless dine-in row remains updatable (transitions cannot break)');

-- ===== (29-32) derived occupancy in pos_tables / list_tables =================
-- live active orders on T1 right now: d0001 (submitted) + d000a (submitted) = 2.
create temp table t_pt as select app.pos_tables(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11') as res;
select is(
  (select (e->>'active_order_count')::int from t_pt, jsonb_array_elements(res->'tables') e
    where e->>'id' = '7b000000-0000-0000-0000-0000000c0b01'),
  2, 'pos_tables reports BOTH active orders on T1 (multiple active orders per table are valid)');
select is(
  (select (e->>'active_order_count')::int from t_pt, jsonb_array_elements(res->'tables') e
    where e->>'id' = '7b000000-0000-0000-0000-0000000c0b05'),
  0, 'an empty table reports active_order_count 0');
-- one order completes -> occupancy releases.
update orders set status = 'completed' where id = '7b000000-0000-0000-0000-0000000d000a';
create temp table t_pt2 as select app.pos_tables(
  '7b000000-0000-0000-0000-00000000c501', '7b000000-0000-0000-0000-00000000da11') as res;
select is(
  (select (e->>'active_order_count')::int from t_pt2, jsonb_array_elements(res->'tables') e
    where e->>'id' = '7b000000-0000-0000-0000-0000000c0b01'),
  1, 'a terminal order RELEASES its occupancy (count drops to 1)');
set local role authenticated;
set local app.current_app_user_id = '7b000000-0000-0000-0000-00000000ee01';
create temp table t_lt as select app.list_tables(
  '7b000000-0000-0000-0000-0000000000a0', '7b000000-0000-0000-0000-0000000000a1',
  '7b000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select ok(
  (select (e->>'active_order_count')::int = 1 from t_lt, jsonb_array_elements(res->'tables') e
    where e->>'id' = '7b000000-0000-0000-0000-0000000c0b01')
  and (select (e->>'active_order_count')::int = 0 from t_lt, jsonb_array_elements(res->'tables') e
    where e->>'id' = '7b000000-0000-0000-0000-0000000c0b02'),
  'list_tables carries the same derived counts (management view incl. the inactive table at 0)');

-- ===== (33-34) catalog ========================================================
select ok(
  exists (select 1 from pg_indexes
           where schemaname = 'public' and tablename = 'orders'
             and indexname = 'orders_active_table_idx'),
  'the partial occupancy index orders_active_table_idx exists');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'submit_order'),
  1, 'submit_order still has exactly ONE definition (no accidental overload)');

select * from finish();
rollback;
