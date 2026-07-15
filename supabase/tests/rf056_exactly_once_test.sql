-- ============================================================================
-- RF-056 — pgTAP: exactly-once via the ledger (AC#1, R-002)
-- ============================================================================
-- A pushed operation is applied exactly once; replaying the same
-- (org, device, local_operation_id) returns the stored result without
-- re-dispatching — no duplicate payment, no duplicate business audit, no receipt
-- counter advance. Fixtures inserted as the BYPASSRLS connection role; sync_push
-- and the dispatched RPCs are SECURITY DEFINER.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf056e-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf056e-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF056E T1', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- setup: push shift.open then order.submit (each its own single-op batch)
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-shift","operation_type":"shift.open","payload":{"shift_id":"00000000-0000-0000-0000-00000000a5f1","cash_drawer_session_id":"00000000-0000-0000-0000-00000000acd1","opening_float_minor":0}}]'::jsonb);
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-order","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ab1e","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);

-- first payment.create push -> applied -------------------------------------- 1-6
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-pay","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'payment.create is applied');
select is((select count(*) from payments)::int, 1, 'exactly one payment row created');
select is((select receipt_number from orders where id='00000000-0000-0000-0000-00000000a0d1'), '1', 'receipt number 1 assigned');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 1::bigint, 'receipt counter advanced to 1');
select is((select count(*) from audit_events where action='payment.recorded')::int, 1, 'one payment.recorded business audit');
select is((select status from sync_operations where local_operation_id='op-pay')::text, 'applied', 'sync_operations(op-pay) is applied');

-- replay the SAME payment.create -> stored result, no re-dispatch ------------ 7-11
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-pay","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'idempotency_replay')::boolean, true, 'replay is flagged idempotency_replay');
select is((select count(*) from payments)::int, 1, 'replay created NO second payment');
select is((select last_issued_value from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 1::bigint, 'replay did NOT advance the receipt counter');
select is((select count(*) from audit_events where action='payment.recorded')::int, 1, 'replay wrote NO duplicate business audit');
select is((select count(*) from sync_operations where local_operation_id='op-pay')::int, 1, 'exactly one ledger row for op-pay');

select * from finish();
rollback;
