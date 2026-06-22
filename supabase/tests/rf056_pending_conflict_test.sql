-- ============================================================================
-- RF-056 — pgTAP: same-key/different-payload conflict on a NON-TERMINAL row (RF056-B1)
-- ============================================================================
-- The operation identity (operation_type + payload_fingerprint) is compared for
-- EVERY existing status, not only terminal ones. A key parked as `pending`
-- (dependency_not_ready) that is re-pushed with a different payload or a different
-- operation_type is a CONFLICT — it never dispatches and never overwrites the stored
-- op. The original SAME-payload operation can still apply once its dependency is
-- satisfied, and a later replay returns the stored result. Fixtures inserted as the
-- BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(10);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf056c-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf056c-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- setup: open a shift so the eventual payment has an active drawer
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-shift","operation_type":"shift.open","payload":{"shift_id":"00000000-0000-0000-0000-00000000a5f1","cash_drawer_session_id":"00000000-0000-0000-0000-00000000acd1","opening_float_minor":0}}]'::jsonb);

-- (1) op-x parks as pending: its dependency op-order has not been pushed ------ 1
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-x","operation_type":"payment.create","depends_on":["op-order"],"payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'dependency_not_ready', 'op-x is parked as pending (dependency_not_ready)');

-- (2/3) retry op-x with a DIFFERENT payload, and with a DIFFERENT op_type -> conflict  2-3
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-x","operation_type":"payment.create","depends_on":["op-order"],"payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":2000}}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'conflict', 'pending op-x re-pushed with a DIFFERENT payload returns conflict (RF056-B1)');
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-x","operation_type":"order.discount","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","scope":"order","discount_type":"fixed","value":100,"reason":"x"}}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'conflict', 'pending op-x re-pushed with a DIFFERENT operation_type returns conflict (RF056-B1)');

-- (4) no business mutation from the conflicting attempts --------------------- 4
select is((select count(*) from payments)::int, 0, 'no payment created by the conflicting re-pushes');

-- (5) the stored op-x row is UNCHANGED (operation_type / payload / status) ---- 5-7
select is((select operation_type from sync_operations where local_operation_id='op-x')::text, 'payment.create', 'stored operation_type is unchanged');
select is((select status from sync_operations where local_operation_id='op-x')::text, 'pending', 'stored status is still pending (not overwritten)');
select is((select payload->>'amount_tendered_minor' from sync_operations where local_operation_id='op-x'), '1000', 'stored payload is the ORIGINAL (1000, not the conflicting 2000)');

-- (6) satisfy the dependency, then (7) retry op-x with the ORIGINAL payload -- 8
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-order","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-x","operation_type":"payment.create","depends_on":["op-order"],"payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'the ORIGINAL same-payload op-x applies once its dependency is satisfied');

-- (8/9) it applied exactly once, and a later replay returns the stored result  9-10
select is((select count(*) from payments)::int, 1, 'exactly one payment row after the successful retry');
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-x","operation_type":"payment.create","depends_on":["op-order"],"payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'idempotency_replay')::boolean, true, 'replay after apply returns the stored result (no re-dispatch)');

select * from finish();
rollback;
