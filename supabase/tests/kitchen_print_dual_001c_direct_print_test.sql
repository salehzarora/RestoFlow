-- ============================================================================
-- KITCHEN-PRINT-DUAL-001C — pgTAP: the direct_print DISPATCH MODE.
--
--   * A chargeable direct_print order (via app.sync_push order.submit, payload
--     dispatch_mode='direct_print') is routed OUT of the KDS active workflow IN
--     THE SAME transaction: persisted `served` + dispatch_mode='direct_print' +
--     ready_at + revision 2, items served, one money-free order.status_updated
--     audit. It is NOT completed (unpaid — settlement is NEVER bypassed).
--   * A ZERO-TOTAL direct_print order auto-completes at the tail (the UNCHANGED
--     served+paid rule: nothing to pay) -> completed, revision 3, no payment row.
--   * A default (kds) submit is byte-identical to before: submitted, dispatch_mode
--     ='kds', revision 1 (the dormancy pin).
--   * An order.submit REPLAY is idempotent: no duplicate transition, ONE audit.
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth (GUC-free).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(18);

-- ===== fixture ==============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00d1c0000a00', 'Org DP', 'dp-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a00', 'Rest DP', 'UTC');
-- KITCHEN-DISPATCH-ENFORCE-001 fixture split: `direct_print` is now only legal
-- on a branch whose authoritative kitchen_workflow_mode is `printer_only`, so
-- the direct_print scenarios (A/B/D) run on Branch (printer_only) while the
-- kds-default dormancy pin (C) keeps its original Branch (kds).
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('00000000-0000-0000-0000-00d1c0000a1a', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', 'Branch (kds)', 'kds'),
  ('00000000-0000-0000-0000-00d1c0000a1b', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', 'Branch (printer_only)', 'printer_only');
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-0000-00d1c000b011', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', 'DP Kitchen 80', 'network', 'kitchen', '80mm', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00d1c000d001', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1a', 'pos'),
  ('00000000-0000-0000-0000-00d1c000d002', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00d1c000c001', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1a', '00000000-0000-0000-0000-00d1c000d001', 'active'),
  ('00000000-0000-0000-0000-00d1c000c002', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', '00000000-0000-0000-0000-00d1c000d002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00d1c000e001', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1a', '00000000-0000-0000-0000-00d1c000d001', '00000000-0000-0000-0000-00d1c000c001'),
  ('00000000-0000-0000-0000-00d1c000e002', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', '00000000-0000-0000-0000-00d1c000d002', '00000000-0000-0000-0000-00d1c000c002');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00d1c0000f01', 'dp-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00d1c00ab001', '00000000-0000-0000-0000-00d1c0000f01', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1a', 'cashier'),
  ('00000000-0000-0000-0000-00d1c00ab002', '00000000-0000-0000-0000-00d1c0000f01', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00d1c00ef001', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1a', '00000000-0000-0000-0000-00d1c0000f01', '00000000-0000-0000-0000-00d1c00ab001', 'Cashier DP'),
  ('00000000-0000-0000-0000-00d1c00ef002', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', '00000000-0000-0000-0000-00d1c0000f01', '00000000-0000-0000-0000-00d1c00ab002', 'Cashier PO');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00d1c00c5001', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1a', '00000000-0000-0000-0000-00d1c000e001', '00000000-0000-0000-0000-00d1c00ef001', '00000000-0000-0000-0000-00d1c00ab001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00d1c00c5002', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', '00000000-0000-0000-0000-00d1c0000a1b', '00000000-0000-0000-0000-00d1c000e002', '00000000-0000-0000-0000-00d1c00ef002', '00000000-0000-0000-0000-00d1c00ab002', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00d1c000ca01', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-00d1c00000f0', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', null, '00000000-0000-0000-0000-00d1c000ca01', 'Tap Water', 0, 'ILS', 1),
  ('00000000-0000-0000-0000-00d1c00000f5', '00000000-0000-0000-0000-00d1c0000a00', '00000000-0000-0000-0000-00d1c0000a10', null, '00000000-0000-0000-0000-00d1c000ca01', 'Burger', 500, 'ILS', 2);

-- Helper: one order.submit op through app.sync_push with an explicit
-- dispatch_mode, from a caller-chosen PIN session / device (so a scenario can
-- pick the kds or the printer_only branch).
create or replace function pg_temp.dp_submit(
  p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_item uuid, p_price bigint, p_mode text)
  returns jsonb language sql as $$
  select app.sync_push(
    p_pin, p_dev,
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op,
      'operation_type', 'order.submit',
      'target_entity', 'order',
      'target_id', p_order::text,
      'payload', jsonb_build_object(
        'order_id', p_order::text, 'order_type', 'takeaway',
        'currency_code', 'ILS',
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', p_item::text, 'quantity', 1,
          'unit_price_minor_snapshot', p_price,
          'menu_item_name_snapshot', 'Item', 'modifiers', '[]'::jsonb)),
        'subtotal_minor', p_price, 'discount_total_minor', 0,
        'tax_total_minor', 0, 'grand_total_minor', p_price,
        'dispatch_mode', p_mode)))) ;
$$;

-- ===== A. direct_print CHARGEABLE -> served + contained, NOT completed ========
create temp table t_dp as select pg_temp.dp_submit(
  '00000000-0000-0000-0000-00d1c00c5002', '00000000-0000-0000-0000-00d1c000d002',
  'dp-chg', '00000000-0000-0000-0000-00d1c00d0001', '00000000-0000-0000-0000-00d1c00000f5', 500, 'direct_print') as res;

select is((select res #>> '{results,0,order_status}' from t_dp), 'served',
  'A1: the envelope reports order_status=served (merged from the dispatch)');            -- 1
select is((select res #>> '{results,0,revision}' from t_dp), '2',
  'A2: the envelope reports the REAL revision (2 = insert + serve)');                     -- 2
select ok((select o.status = 'served' and o.dispatch_mode = 'direct_print' and o.revision = 2
             from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0001'),
  'A3: persisted served + dispatch_mode=direct_print at revision 2');                     -- 3
select ok((select o.ready_at is not null from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0001'),
  'A4: a write-once ready_at was stamped on the dispatch');                               -- 4
select ok(not exists (select 1 from order_items where order_id = '00000000-0000-0000-0000-00d1c00d0001' and status <> 'served'),
  'A5: the items are dispatched to served too');                                          -- 5
select ok((select o.status not in ('submitted','accepted','preparing','ready')
             from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0001'),
  'A6: the order is OUT of the KDS ACTIVE statuses (contained)');                          -- 6
select ok(not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-00d1c00d0001'),
  'A7: NOT completed and NO payment fabricated — settlement is never bypassed');          -- 7

-- the ONE money-free order.status_updated audit carrying the dispatch marker.
select ok(exists (select 1 from audit_events
    where action = 'order.status_updated'
      and new_values ->> 'dispatch_mode' = 'direct_print'
      and new_values ->> 'from_status' = 'submitted'
      and new_values ->> 'to_status' = 'served'
      and (new_values ->> 'order_code') = '#' || upper(right(replace('00000000-0000-0000-0000-00d1c00d0001', '-', ''), 6))),
  'A8: one order.status_updated audit names the submitted->served direct_print dispatch'); -- 8
select ok(not exists (select 1 from audit_events, jsonb_object_keys(new_values) k
      where action = 'order.status_updated' and new_values ->> 'dispatch_mode' = 'direct_print'
        and k like '%_minor'),
  'A9: the dispatch audit is MONEY-FREE (no *_minor key; T-003)');                         -- 9

-- ===== B. direct_print ZERO-TOTAL -> auto-completes (unchanged rule) ==========
create temp table t_zt as select pg_temp.dp_submit(
  '00000000-0000-0000-0000-00d1c00c5002', '00000000-0000-0000-0000-00d1c000d002',
  'dp-zt', '00000000-0000-0000-0000-00d1c00d0002', '00000000-0000-0000-0000-00d1c00000f0', 0, 'direct_print') as res;
select is((select res #>> '{results,0,order_status}' from t_zt), 'completed',
  'B1: a ZERO-TOTAL direct_print order completes at the tail (nothing to pay)');           -- 10
-- KITCHEN-DISPATCH-ENFORCE-001 fixture split: on a `printer_only` branch
-- app.submit_order ITSELF auto-completes a zero-total order (20260725090000
-- :1185-1193) BEFORE app.apply_direct_print_dispatch runs, so the dispatch is
-- correctly `not_eligible` (dispatched=false), dispatch_mode stays 'kds' and
-- the revision is 2 (insert + complete) rather than 3. That is the UNCHANGED
-- printer_only behavior — pre- and post-migration identical; only the fixture
-- branch moved, because direct_print is no longer legal on a kds branch.
select ok((select o.status = 'completed' and o.dispatch_mode = 'kds' and o.revision = 2
             from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0002'),
  'B2: persisted completed at revision 2 — submit_order settled it before dispatch (not_eligible)'); -- 11
select ok(not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-00d1c00d0002'),
  'B3: NO payment row for the settled-with-nothing-to-pay direct_print order');            -- 12

-- ===== C. default (kds) submit is UNCHANGED — the dormancy pin ================
create temp table t_kds as select pg_temp.dp_submit(
  '00000000-0000-0000-0000-00d1c00c5001', '00000000-0000-0000-0000-00d1c000d001',
  'dp-kds', '00000000-0000-0000-0000-00d1c00d0003', '00000000-0000-0000-0000-00d1c00000f5', 500, 'kds') as res;
select ok((select o.status = 'submitted' and o.dispatch_mode = 'kds' and o.revision = 1
             from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0003'),
  'C1: a kds (default) order is byte-identical to before: submitted, dispatch_mode=kds, rev 1'); -- 13
select ok((select o.status in ('submitted','accepted','preparing','ready')
             from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0003'),
  'C2: a kds order IS in the KDS active statuses (appears on the board)');                 -- 14
select ok(not exists (select 1 from audit_events
      where action = 'order.status_updated'
        and (new_values ->> 'order_code') = '#' || upper(right(replace('00000000-0000-0000-0000-00d1c00d0003', '-', ''), 6))),
  'C3: a kds submit writes NO status_updated audit (no serve transition happened)');       -- 15

-- ===== D. order.submit REPLAY is idempotent ==================================
create temp table t_rp as select pg_temp.dp_submit(
  '00000000-0000-0000-0000-00d1c00c5002', '00000000-0000-0000-0000-00d1c000d002',
  'dp-chg', '00000000-0000-0000-0000-00d1c00d0001', '00000000-0000-0000-0000-00d1c00000f5', 500, 'direct_print') as res;
select is((select res #>> '{results,0,idempotency_replay}' from t_rp), 'true',
  'D1: replaying the direct_print order.submit is an idempotency replay');                 -- 16
select ok((select o.status = 'served' and o.revision = 2
             from orders o where o.id = '00000000-0000-0000-0000-00d1c00d0001'),
  'D2: the replay leaves the order unchanged (served, revision still 2)');                 -- 17
select is((select count(*) from audit_events
      where action = 'order.status_updated'
        and (new_values ->> 'order_code') = '#' || upper(right(replace('00000000-0000-0000-0000-00d1c00d0001', '-', ''), 6)))::text,
  '1', 'D3: exactly ONE dispatch audit — the replay wrote no duplicate');                  -- 18

select * from finish();
rollback;
