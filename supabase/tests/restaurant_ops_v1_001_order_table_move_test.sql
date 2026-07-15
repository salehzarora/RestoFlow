-- ============================================================================
-- RESTAURANT-OPERATIONS-V1-001 — pgTAP: atomic order table move + Activity Log
-- classification for the phase's two new action families
-- ============================================================================
-- Covers: a valid move (row + revision + before/after audit + ledger); ORDER-
-- BOUND idempotent replay (no second audit row, no revision drift) and the
-- 40001 on key reuse against a DIFFERENT order; expected_revision conflict
-- (40001); moving a LEGACY tableless dine-in order (assign/recovery) onto an
-- OCCUPIED table (both are allowed); takeaway refusal (table_not_allowed +
-- audited takeaway_order); terminal refusal (invalid_transition +
-- order_not_movable + order_status); foreign-branch and inactive targets are
-- one identical table_not_available (R-003); same-table no-op (ok/no_change,
-- ledgered, NOT audited, revision unchanged); kitchen_staff denial
-- (permission_denied + audit); a cross-branch order raises 42501; the
-- 'order.table_move' op dispatches end-to-end through app.sync_push (applied +
-- ledger row) and a stale expected_revision surfaces as the per-op typed
-- conflict; a wrong op token is still unknown_operation_type; audit
-- classification (categories, has_detail, exact safe_detail projections for
-- BOTH new families; other menu.* actions stay metadata-only); ACLs.
-- Fixtures as the BYPASSRLS connection role; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(30);

-- ===== fixture: org A — Rest A1, branches B1 + B2 ============================
insert into organizations (id, name, slug, default_currency) values
  ('7c000000-0000-0000-0000-0000000000a0', 'Org A', 'ropsv1c-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', 'Branch B1'),
  ('7c000000-0000-0000-0000-00000000a1b2', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', 'Branch B2');
-- cashier stack on B1
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('7c000000-0000-0000-0000-00000000da22', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'kds'),
  ('7c000000-0000-0000-0000-00000000da33', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b2', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7c000000-0000-0000-0000-00000000fa11', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', 'active'),
  ('7c000000-0000-0000-0000-00000000fa22', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da22', 'active'),
  ('7c000000-0000-0000-0000-00000000fa33', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b2', '7c000000-0000-0000-0000-00000000da33', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('7c000000-0000-0000-0000-0000000005a1', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-00000000fa11'),
  ('7c000000-0000-0000-0000-0000000005a2', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da22', '7c000000-0000-0000-0000-00000000fa22'),
  ('7c000000-0000-0000-0000-0000000005a3', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b2', '7c000000-0000-0000-0000-00000000da33', '7c000000-0000-0000-0000-00000000fa33');
insert into app_users (id, email) values
  ('7c000000-0000-0000-0000-00000000ee03', 'ropsv1c-cashier@example.test'),
  ('7c000000-0000-0000-0000-00000000ee04', 'ropsv1c-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7c000000-0000-0000-0000-00000000ab03', '7c000000-0000-0000-0000-00000000ee03', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('7c000000-0000-0000-0000-00000000ab04', '7c000000-0000-0000-0000-00000000ee04', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000ee03', '7c000000-0000-0000-0000-00000000ab03', 'Casey'),
  ('7c000000-0000-0000-0000-0000000ef004', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000ee04', '7c000000-0000-0000-0000-00000000ab04', 'Kit');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-0000000005a1', '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('7c000000-0000-0000-0000-00000000c504', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-0000000005a2', '7c000000-0000-0000-0000-0000000ef004', '7c000000-0000-0000-0000-00000000ab04', now() + interval '1 hour'),
  ('7c000000-0000-0000-0000-00000000c505', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b2', '7c000000-0000-0000-0000-0000000005a3', '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- tables: T1/T2 live B1, T3 inactive B1, T4 live B2.
insert into tables (id, organization_id, restaurant_id, branch_id, label, status, is_active, deleted_at) values
  ('7c000000-0000-0000-0000-0000000c0b01', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'T1', 'available', true,  null),
  ('7c000000-0000-0000-0000-0000000c0b02', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'T2', 'available', true,  null),
  ('7c000000-0000-0000-0000-0000000c0b03', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'T3', 'available', false, null),
  ('7c000000-0000-0000-0000-0000000c0b04', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b2', 'T4', 'available', true,  null);

-- orders: O1 dine-in active on T1; O2 takeaway active; O3 dine-in COMPLETED on
-- T1; O4 LEGACY tableless dine-in active; O5 dine-in active in SIBLING B2.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
                    opened_by_employee_profile_id, resolved_membership_id, table_id, order_type, status,
                    currency_code, subtotal_minor, discount_total_minor, tax_total_minor,
                    grand_total_minor, local_operation_id, revision) values
  ('7c000000-0000-0000-0000-0000000d0001', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1',
   '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-00000000c501',
   '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', '7c000000-0000-0000-0000-0000000c0b01',
   'dine_in',  'submitted', 'ILS', 2500, 0, 0, 2500, 'ropsc-o1', 1),
  ('7c000000-0000-0000-0000-0000000d0002', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1',
   '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-00000000c501',
   '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', null,
   'takeaway', 'preparing', 'ILS', 1200, 0, 0, 1200, 'ropsc-o2', 1),
  ('7c000000-0000-0000-0000-0000000d0003', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1',
   '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-00000000c501',
   '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', '7c000000-0000-0000-0000-0000000c0b01',
   'dine_in',  'completed', 'ILS', 3000, 0, 0, 3000, 'ropsc-o3', 3),
  ('7c000000-0000-0000-0000-0000000d0004', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1',
   '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-00000000c501',
   '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', null,
   'dine_in',  'served',    'ILS', 1800, 0, 0, 1800, 'ropsc-o4', 1),
  ('7c000000-0000-0000-0000-0000000d0005', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1',
   '7c000000-0000-0000-0000-00000000a1b2', '7c000000-0000-0000-0000-00000000da33', '7c000000-0000-0000-0000-00000000c505',
   '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', '7c000000-0000-0000-0000-0000000c0b04',
   'dine_in',  'submitted', 'ILS', 700, 0, 0, 700, 'ropsc-o5', 1);

-- ===== (1-4) the valid move: row + revision + audit + ledger =================
create temp table t_mv1 as select app.move_order_table(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0001',
  '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-1',
  '7c000000-0000-0000-0000-0000000c0b02', 1) as res;
select ok(
  (select (res->>'ok')::boolean and res->>'table_label' = 'T2'
      and (res->>'revision')::int = 2 from t_mv1),
  'a cashier moves an active dine-in order T1 -> T2 (envelope: ok + label + revision 2)');
select is(
  (select table_id::text || '|' || revision::text from orders
    where id = '7c000000-0000-0000-0000-0000000d0001'),
  '7c000000-0000-0000-0000-0000000c0b02|2',
  'the order row now sits on T2 at revision 2');
select is(
  (select (old_values->>'table_label') || '>' || (new_values->>'from_table_label')
       || '>' || (new_values->>'to_table_label') || '|' || (new_values->>'revision')
     from audit_events
    where organization_id = '7c000000-0000-0000-0000-0000000000a0'
      and action = 'order.table_moved'),
  'T1>T1>T2|2',
  'order.table_moved audits BEFORE (T1) and AFTER (T2) labels + the new revision');
select is(
  (select count(*)::int from order_operations
    where organization_id = '7c000000-0000-0000-0000-0000000000a0'
      and action = 'move_table' and local_operation_id = 'ropsc-mv-1'
      and order_id = '7c000000-0000-0000-0000-0000000d0001'),
  1, 'the move is ledgered (order_operations action move_table)');

-- ===== (5-7) idempotency + conflicts ==========================================
create temp table t_mv1r as select app.move_order_table(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0001',
  '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-1',
  '7c000000-0000-0000-0000-0000000c0b02', 1) as res;
select ok(
  (select (res->>'ok')::boolean and (res->>'idempotency_replay')::boolean from t_mv1r)
  and (select revision = 2 from orders where id = '7c000000-0000-0000-0000-0000000d0001')
  and (select count(*)::int from audit_events
        where organization_id = '7c000000-0000-0000-0000-0000000000a0'
          and action = 'order.table_moved') = 1,
  'the SAME op replays its stored result: no revision drift, no second audit row');
select throws_ok(
  $$select app.move_order_table(
      '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0004',
      '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-1',
      '7c000000-0000-0000-0000-0000000c0b02', null)$$,
  '40001', null,
  'reusing the idempotency key on a DIFFERENT order is a 40001 conflict, never a replay leak');
select throws_ok(
  $$select app.move_order_table(
      '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0001',
      '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-stale',
      '7c000000-0000-0000-0000-0000000c0b01', 1)$$,
  '40001', null,
  'a stale expected_revision (another device moved first) raises 40001');

-- ===== (8-9) legacy tableless order moves; occupied target allowed ===========
create temp table t_mv4 as select app.move_order_table(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0004',
  '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-4',
  '7c000000-0000-0000-0000-0000000c0b02', null) as res;
select ok(
  (select (res->>'ok')::boolean and res->>'table_label' = 'T2' from t_mv4),
  'a LEGACY tableless dine-in order can be moved ONTO an occupied table (assign/recovery)');
select is(
  (select old_values->>'table_label' from audit_events
    where organization_id = '7c000000-0000-0000-0000-0000000000a0'
      and action = 'order.table_moved'
      and new_values->>'order_code' = '#0D0004'),
  null, 'the legacy move audits an honest NULL before-label (there was no table)');

-- ===== (10-13) typed refusals ================================================
create temp table t_ref as select
  (app.move_order_table('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0002',
    '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-tw', '7c000000-0000-0000-0000-0000000c0b02', null)) as takeaway,
  (app.move_order_table('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0003',
    '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-done', '7c000000-0000-0000-0000-0000000c0b02', null)) as terminal,
  (app.move_order_table('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0001',
    '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-foreign', '7c000000-0000-0000-0000-0000000c0b04', null)) as foreign_tbl,
  (app.move_order_table('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0001',
    '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-inactive', '7c000000-0000-0000-0000-0000000c0b03', null)) as inactive_tbl;
select ok(
  (select takeaway->>'error' = 'table_not_allowed' and takeaway->>'detail' = 'takeaway_order' from t_ref)
  and (select count(*)::int from audit_events
        where organization_id = '7c000000-0000-0000-0000-0000000000a0'
          and action = 'order.table_move_denied'
          and new_values->>'denied_reason' = 'takeaway_order') = 1,
  'a takeaway order refuses the move (table_not_allowed + audited takeaway_order)');
select ok(
  (select terminal->>'error' = 'invalid_transition' and terminal->>'detail' = 'order_not_movable'
      and terminal->>'order_status' = 'completed' from t_ref),
  'a terminal order refuses the move (order_not_movable + its status)');
select is((select foreign_tbl->>'error' from t_ref), 'table_not_available',
  'a SIBLING-BRANCH target table is table_not_available (cross-branch unreachable)');
select is((select inactive_tbl->>'error' from t_ref), 'table_not_available',
  'an inactive target table is the SAME refusal (no probe oracle, R-003)');

-- ===== (14-15) same-table no-op ==============================================
create temp table t_noop as select app.move_order_table(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0001',
  '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-noop',
  '7c000000-0000-0000-0000-0000000c0b02', null) as res;
select ok(
  (select (res->>'ok')::boolean and (res->>'no_change')::boolean
      and (res->>'revision')::int = 2 from t_noop),
  'moving an order onto its OWN table is an explicit ok/no_change with NO revision bump');
select is(
  (select count(*)::int from audit_events
    where organization_id = '7c000000-0000-0000-0000-0000000000a0'
      and action = 'order.table_moved'),
  2, 'the no-op wrote NO audit row (still exactly the two real moves)');

-- ===== (16-17) authorization + scope =========================================
create temp table t_kit as select app.move_order_table(
  '7c000000-0000-0000-0000-00000000c504', '7c000000-0000-0000-0000-0000000d0001',
  '7c000000-0000-0000-0000-00000000da22', 'ropsc-mv-kit',
  '7c000000-0000-0000-0000-0000000c0b01', null) as res;
select ok(
  (select res->>'error' = 'permission_denied' from t_kit)
  and (select count(*)::int from audit_events
        where organization_id = '7c000000-0000-0000-0000-0000000000a0'
          and action = 'order.table_move_denied'
          and new_values->>'denied_reason' = 'permission_denied'
          and new_values->>'role' = 'kitchen_staff') = 1,
  'kitchen_staff may not move tables (typed + audited denial)');
select throws_ok(
  $$select app.move_order_table(
      '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000d0005',
      '7c000000-0000-0000-0000-00000000da11', 'ropsc-mv-xbranch',
      '7c000000-0000-0000-0000-0000000c0b02', null)$$,
  '42501', null,
  'an order of a SIBLING BRANCH is out of the caller scope (42501 fail-closed)');

-- ===== (18-21) end-to-end through sync_push ==================================
create temp table t_push as select app.sync_push(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'ropsc-push-1',
    'operation_type', 'order.table_move',
    'target_entity', 'order',
    'target_id', '7c000000-0000-0000-0000-0000000d0001',
    'payload', jsonb_build_object(
      'order_id', '7c000000-0000-0000-0000-0000000d0001',
      'table_id', '7c000000-0000-0000-0000-0000000c0b01',
      'expected_revision', 2)))) as res;
select ok(
  (select (res->'results'->0->>'ok')::boolean
      and res->'results'->0->>'status' = 'applied'
      and res->'results'->0->>'table_label' = 'T1'
      and (res->'results'->0->>'revision')::int = 3 from t_push),
  'order.table_move dispatches through sync_push: applied, back on T1 at revision 3');
select is(
  (select status from sync_operations
    where organization_id = '7c000000-0000-0000-0000-0000000000a0'
      and local_operation_id = 'ropsc-push-1'),
  'applied', 'the transport ledger records the op applied (op-type CHECK accepts it)');
create temp table t_push2 as select app.sync_push(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'ropsc-push-2',
    'operation_type', 'order.table_move',
    'target_entity', 'order',
    'target_id', '7c000000-0000-0000-0000-0000000d0001',
    'payload', jsonb_build_object(
      'order_id', '7c000000-0000-0000-0000-0000000d0001',
      'table_id', '7c000000-0000-0000-0000-0000000c0b02',
      'expected_revision', 1)))) as res;
select ok(
  (select res->'results'->0->>'error' = 'conflict'
      and res->'results'->0->>'status' = 'conflict' from t_push2),
  'a stale expected_revision through sync_push is the TYPED per-op conflict');
create temp table t_push3 as select app.sync_push(
  '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'ropsc-push-3',
    'operation_type', 'order.table_moved',
    'payload', jsonb_build_object('order_id', '7c000000-0000-0000-0000-0000000d0001')))) as res;
select is(
  (select res->'results'->0->>'error' from t_push3), 'unknown_operation_type',
  'a wrong op token is still unknown_operation_type (the allowlist stays closed)');

-- ===== (22-27) Activity Log classification ===================================
select is(app.audit_category('order.table_moved'), 'orders',
  'order.table_moved classifies as orders');
select is(app.audit_category('menu.menu_item.availability_changed'), 'menu',
  'menu.menu_item.availability_changed classifies as menu');
select ok(
  app.audit_action_has_detail('order.table_moved')
  and app.audit_action_has_detail('order.table_move_denied')
  and app.audit_action_has_detail('menu.menu_item.availability_changed')
  and app.audit_action_has_detail('menu.menu_item.availability_denied'),
  'all four new actions may carry safe detail');
select is(
  app.audit_safe_detail('order.table_moved', jsonb_build_object(
    'table_id', '7c000000-0000-0000-0000-0000000c0b02',
    'table_label', 'T2', 'from_table_label', 'T1', 'to_table_label', 'T2',
    'order_code', '#0D0001', 'revision', 2,
    'resolved_membership_id', '7c000000-0000-0000-0000-00000000ab03')),
  jsonb_build_object('table_label', 'T2', 'from_table_label', 'T1',
                     'to_table_label', 'T2', 'order_code', '#0D0001'),
  'safe_detail projects the move labels + order_code and DROPS ids + revision');
select is(
  app.audit_safe_detail('menu.menu_item.availability_changed', jsonb_build_object(
    'availability', 'unavailable', 'availability_reason', 'sold_out',
    'item_name', 'Falafel', 'menu_item_id', '7c000000-0000-0000-0000-0000000000f1')),
  jsonb_build_object('availability', 'unavailable', 'availability_reason', 'sold_out',
                     'item_name', 'Falafel'),
  'safe_detail projects availability + reason + item name and DROPS the item id');
select is(
  app.audit_safe_detail('menu.menu_item.updated', jsonb_build_object('name', 'X')),
  '{}'::jsonb,
  'other menu.* actions remain metadata-only (no detail regression)');

-- ===== (28-30) ACL + catalog =================================================
select ok(
  not has_function_privilege('anon', 'app.move_order_table(uuid, uuid, uuid, text, uuid, integer)', 'execute')
  and has_function_privilege('authenticated', 'app.move_order_table(uuid, uuid, uuid, text, uuid, integer)', 'execute'),
  'move_order_table: anon nothing, authenticated execute');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'move_order_table'),
  0, 'NO public wrapper exists — the POS reaches the move only through sync_push');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'sync_push'),
  1, 'sync_push still has exactly ONE definition (no accidental overload)');

select * from finish();
rollback;
