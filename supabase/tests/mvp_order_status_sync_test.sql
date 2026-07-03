-- ============================================================================
-- MVP — pgTAP: order.status through the sync architecture (D-010/D-018/D-022, T-003)
-- ============================================================================
-- app.update_order_status enforces the FROZEN single-step forward order state
-- machine (STATE_MACHINES §1.1): kitchen_staff may drive submitted->accepted->
-- preparing->ready->served (ready->served is the KDS "bump") but NOT
-- served->completed (permission_denied, audited, no write); cashier settles
-- the completion step. Skips, from==to,
-- unknown targets, and terminal sources are invalid_transition with NO write.
-- Cross-org is fail-closed (42501, no cross-tenant write). The op rides the
-- EXISTING outbox/ledger end-to-end: an ops-array envelope through
-- public.sync_push applies + records in sync_operations, a same-key replay
-- returns the stored result WITHOUT re-applying (D-022), sync_pull surfaces the
-- updated order to the kitchen session and still refuses the payments entity.
-- Kitchen-actor audit rows carry NO money keys (T-003). Fixtures inserted as the
-- BYPASSRLS connection role (pin_sessions inserted directly — the RF-056/RF-057
-- convention); the RPCs are SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(32);

-- ===== fixtures: org A (POS + cashier session, KDS + kitchen session) ========
insert into organizations (id, name, slug, default_currency) values
  ('10000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpst-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('10000000-0000-0000-0000-00000000da11', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('10000000-0000-0000-0000-00000000da22', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('10000000-0000-0000-0000-00000000fa11', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-00000000da11', 'active'),
  ('10000000-0000-0000-0000-00000000fa22', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('10000000-0000-0000-0000-0000000005a1', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-00000000da11', '10000000-0000-0000-0000-00000000fa11'),
  ('10000000-0000-0000-0000-0000000005a2', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-00000000da22', '10000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('10000000-0000-0000-0000-00000000ee01', 'mvpst-cashier@example.test'),
  ('10000000-0000-0000-0000-00000000ee04', 'mvpst-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('10000000-0000-0000-0000-00000000ab01', '10000000-0000-0000-0000-00000000ee01', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('10000000-0000-0000-0000-00000000ab04', '10000000-0000-0000-0000-00000000ee04', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('10000000-0000-0000-0000-0000000ef001', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-00000000ee01', '10000000-0000-0000-0000-00000000ab01'),
  ('10000000-0000-0000-0000-0000000ef004', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-00000000ee04', '10000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-0000000005a1', '10000000-0000-0000-0000-0000000ef001', '10000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-0000000000a0', '10000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000a1b1', '10000000-0000-0000-0000-0000000005a2', '10000000-0000-0000-0000-0000000ef004', '10000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ===== fixtures: org B (its own device + cashier session + order) ============
insert into organizations (id, name, slug, default_currency) values
  ('20000000-0000-0000-0000-0000000000b0', 'Org B', 'mvpst-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('20000000-0000-0000-0000-00000000b1b1', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('20000000-0000-0000-0000-00000000db11', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000b1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('20000000-0000-0000-0000-00000000fb11', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000b1b1', '20000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('20000000-0000-0000-0000-0000000005b1', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000b1b1', '20000000-0000-0000-0000-00000000db11', '20000000-0000-0000-0000-00000000fb11');
insert into app_users (id, email) values
  ('20000000-0000-0000-0000-00000000ee02', 'mvpst-b-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('20000000-0000-0000-0000-00000000ab02', '20000000-0000-0000-0000-00000000ee02', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000b1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('20000000-0000-0000-0000-0000000ef002', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000b1b1', '20000000-0000-0000-0000-00000000ee02', '20000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('20000000-0000-0000-0000-00000000c502', '20000000-0000-0000-0000-0000000000b0', '20000000-0000-0000-0000-0000000000b1', '20000000-0000-0000-0000-00000000b1b1', '20000000-0000-0000-0000-0000000005b1', '20000000-0000-0000-0000-0000000ef002', '20000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- ===== setup: three submitted orders via app.submit_order (status 'submitted')
select app.submit_order('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000a0d1',
  '10000000-0000-0000-0000-00000000da11', 'op-sub-1', 'dine_in', null, null, 'USD', null,
  '[{"menu_item_id":"10000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
  1000, 0, 0, 1000, null);
select app.submit_order('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000a0d2',
  '10000000-0000-0000-0000-00000000da11', 'op-sub-2', 'dine_in', null, null, 'USD', null,
  '[{"menu_item_id":"10000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
  1000, 0, 0, 1000, null);
select app.submit_order('20000000-0000-0000-0000-00000000c502', '20000000-0000-0000-0000-00000000b0d1',
  '20000000-0000-0000-0000-00000000db11', 'op-sub-b1', 'dine_in', null, null, 'EUR', null,
  '[{"menu_item_id":"20000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":900,"menu_item_name_snapshot":"B Item"}]'::jsonb,
  900, 0, 0, 900, null);

-- ===== (1) sanity: submit_order left the order at 'submitted' ================
select is((select status from orders where id = '10000000-0000-0000-0000-00000000a0d1'),
  'submitted', 'order A1 starts at status submitted (via app.submit_order)');

-- ===== (2-5) kitchen_staff submitted->accepted applies =======================
select ok(
  (select r ->> 'ok' = 'true' and r ->> 'entity' = 'order' and r ->> 'status' = 'accepted'
   from app.update_order_status('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
     '10000000-0000-0000-0000-00000000a0d1', 'accepted', 'los-st-1') as r),
  'kitchen_staff submitted->accepted returns ok/entity=order/status=accepted');
select is((select status from orders where id = '10000000-0000-0000-0000-00000000a0d1'),
  'accepted', 'order A1 is persisted at accepted');
select is((select revision from orders where id = '10000000-0000-0000-0000-00000000a0d1')::int,
  2, 'order A1 revision bumped to 2');
select ok(
  exists (select 1 from audit_events
          where action = 'order.status_updated'
            and actor_employee_profile_id = '10000000-0000-0000-0000-0000000ef004'
            and old_values ->> 'status' = 'submitted'
            and new_values ->> 'status' = 'accepted'
            and new_values ->> 'order_id' = '10000000-0000-0000-0000-00000000a0d1'),
  'order.status_updated audit exists (kitchen actor, old submitted -> new accepted)');

-- ===== (6-8) accepted->preparing and preparing->ready apply (kitchen) ========
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
    '10000000-0000-0000-0000-00000000a0d1', 'preparing', 'los-st-2') ->> 'status'),
  'preparing', 'kitchen_staff accepted->preparing applies');
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
    '10000000-0000-0000-0000-00000000a0d1', 'ready', 'los-st-3') ->> 'status'),
  'ready', 'kitchen_staff preparing->ready applies');
select is((select revision from orders where id = '10000000-0000-0000-0000-00000000a0d1')::int,
  4, 'order A1 revision bumped to 4 after two more steps');

-- ===== (9-10) kitchen_staff ready->served (the KDS bump) APPLIES =============
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
    '10000000-0000-0000-0000-00000000a0d1', 'served', 'los-st-4') ->> 'status'),
  'served', 'kitchen_staff ready->served (KDS bump) applies');
select ok(
  (select o.status = 'served' and o.revision = 5 from orders o where o.id = '10000000-0000-0000-0000-00000000a0d1'),
  'the kitchen bump persisted (A1 served, revision 5)');

-- ===== (11-13) kitchen_staff served->completed is permission_denied, no write
select ok(
  (select r ->> 'ok' = 'false' and r ->> 'error' = 'permission_denied'
   from app.update_order_status('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
     '10000000-0000-0000-0000-00000000a0d1', 'completed', 'los-st-5') as r),
  'kitchen_staff served->completed is REJECTED with permission_denied (kitchen may not complete)');
select is((select status from orders where id = '10000000-0000-0000-0000-00000000a0d1'),
  'served', 'the denied complete attempt wrote NO state change (still served)');
select ok(
  exists (select 1 from audit_events
          where action = 'order.status_update_denied'
            and new_values ->> 'role' = 'kitchen_staff'
            and new_values ->> 'to' = 'completed'
            and new_values ->> 'order_id' = '10000000-0000-0000-0000-00000000a0d1'),
  'the kitchen complete denial is audited (order.status_update_denied)');

-- ===== (14-15) cashier served->completed applies =============================
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000da11',
    '10000000-0000-0000-0000-00000000a0d1', 'completed', 'los-st-6') ->> 'status'),
  'completed', 'cashier served->completed applies');
select ok(
  (select o.status = 'completed' and o.revision = 6 from orders o where o.id = '10000000-0000-0000-0000-00000000a0d1'),
  'order A1 is persisted at completed with revision 6 across the full lifecycle');

-- ===== (16-20) illegal transitions: skip / from==to / terminal-backward / unknown
select ok(
  (select r ->> 'error' = 'invalid_transition' and r ->> 'from' = 'submitted' and r ->> 'to' = 'ready'
   from app.update_order_status('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000da11',
     '10000000-0000-0000-0000-00000000a0d2', 'ready', 'los-st-7') as r),
  'a skip (submitted->ready) is rejected invalid_transition with from/to surfaced');
select ok(
  (select o.status = 'submitted' and o.revision = 1 from orders o where o.id = '10000000-0000-0000-0000-00000000a0d2'),
  'the skipped order A2 is untouched (submitted, revision 1)');
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000da11',
    '10000000-0000-0000-0000-00000000a0d2', 'submitted', 'los-st-8') ->> 'error'),
  'invalid_transition', 'from==to (submitted->submitted) is rejected invalid_transition');
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
    '10000000-0000-0000-0000-00000000a0d1', 'accepted', 'los-st-9') ->> 'error'),
  'invalid_transition', 'a terminal source (completed->accepted) is rejected invalid_transition');
select is(
  (app.update_order_status('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000da11',
    '10000000-0000-0000-0000-00000000a0d2', 'bogus', 'los-st-10') ->> 'error'),
  'invalid_transition', 'an unknown target status is rejected invalid_transition');

-- ===== (21-22) cross-org: fail-closed, no cross-tenant write =================
select throws_ok(
  $$ select app.update_order_status('10000000-0000-0000-0000-00000000c501', '10000000-0000-0000-0000-00000000da11',
       '20000000-0000-0000-0000-00000000b0d1', 'accepted', 'los-st-11') $$,
  '42501', NULL, 'an org A session cannot update an org B order (fail-closed 42501)');
select ok(
  (select o.status = 'submitted' and o.revision = 1 from orders o where o.id = '20000000-0000-0000-0000-00000000b0d1'),
  'the org B order is untouched by the cross-org attempt (no cross-tenant write)');

-- ===== (23-25) end-to-end: order.status through public.sync_push (ops array) =
select is(
  (public.sync_push('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
    '[{"local_operation_id":"op-status-1","operation_type":"order.status","payload":{"order_id":"10000000-0000-0000-0000-00000000a0d2","new_status":"accepted"}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied',
  'order.status pushed through public.sync_push (ops-array envelope) is applied');
select ok(
  (select o.status = 'accepted' and o.revision = 2 from orders o where o.id = '10000000-0000-0000-0000-00000000a0d2'),
  'the pushed status update persisted (A2 accepted, revision 2)');
select ok(
  (select so.status = 'applied' and so.operation_type = 'order.status'
     and so.target_id = '10000000-0000-0000-0000-00000000a0d2'
   from sync_operations so where so.local_operation_id = 'op-status-1'),
  'the ledger row for op-status-1 is applied with operation_type order.status (D-022)');

-- ===== (26-28) idempotent replay: same local_operation_id -> stored result ===
select is(
  (public.sync_push('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
    '[{"local_operation_id":"op-status-1","operation_type":"order.status","payload":{"order_id":"10000000-0000-0000-0000-00000000a0d2","new_status":"accepted"}}]'::jsonb)
   -> 'results' -> 0 ->> 'idempotency_replay')::boolean, true,
  'replaying op-status-1 through public.sync_push returns the stored result (idempotency_replay)');
select is((select revision from orders where id = '10000000-0000-0000-0000-00000000a0d2')::int,
  2, 'the replay did NOT re-apply (A2 revision still 2)');
select is(
  (select count(*) from audit_events
   where action = 'order.status_updated'
     and new_values ->> 'order_id' = '10000000-0000-0000-0000-00000000a0d2')::int,
  1, 'the replay wrote NO duplicate order.status_updated audit');

-- ===== (29-30) sync_pull: the kitchen session sees the update; payments refused
select ok(
  exists (select 1
          from jsonb_array_elements(
                 app.sync_pull('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
                   array['orders'], '{}'::jsonb, 500) -> 'changes' -> 'orders' -> 'rows') as r
          where r ->> 'id' = '10000000-0000-0000-0000-00000000a0d2'
            and r ->> 'status' = 'accepted'),
  'sync_pull for the kitchen session surfaces order A2 at status accepted');
select throws_ok(
  $$ select app.sync_pull('10000000-0000-0000-0000-00000000c504', '10000000-0000-0000-0000-00000000da22',
       array['payments'], '{}'::jsonb, 500) $$,
  '42501', NULL, 'the kitchen session still cannot pull the payments entity (T-003)');

-- ===== (31) kitchen-actor audit rows carry NO money keys (T-003) =============
select ok(
  not exists (
    select 1
    from audit_events ae
    cross join lateral (
      select jsonb_object_keys(coalesce(ae.old_values, '{}'::jsonb)) as k
      union all
      select jsonb_object_keys(coalesce(ae.new_values, '{}'::jsonb))
    ) as keys
    where ae.action in ('order.status_updated', 'order.status_update_denied')
      and keys.k like '%minor%'),
  'order.status_updated / order.status_update_denied audits contain NO money keys (T-003)');

-- ===== (32) exposure mirrors app.submit_order: no public wrapper =============
select hasnt_function('public', 'update_order_status',
  'no public.update_order_status wrapper (reachable ONLY via the sync_push dispatcher, like submit_order)');

select * from finish();
rollback;
