-- ============================================================================
-- RF-056 — pgTAP: same-key / different-payload conflict (AC#7, A4)
-- ============================================================================
-- The identity is (org, device, local_operation_id). Reusing a key with a
-- DIFFERENT payload or a DIFFERENT operation_type is a conflict (not a replay and
-- not a second mutation): the second push returns conflict, dispatches nothing, and
-- the stored row is unchanged. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf056k-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf056k-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-000000ab1e01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'T1', true);

-- first push of op-1 (order.submit, grand 1000) -> applied ------------------- 1
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-1","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","table_id":"00000000-0000-0000-0000-000000ab1e01","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'first op-1 (order.submit) applied');

-- second push of op-1 with a DIFFERENT payload -> conflict ------------------- 2-4
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-1","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","table_id":"00000000-0000-0000-0000-000000ab1e01","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":2000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":2000}}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'conflict', 'reusing op-1 with a different payload returns conflict');
select is((select count(*) from orders)::int, 1, 'the conflicting push dispatched nothing (still one order)');
select is((select count(*) from audit_events where action='sync.operation_conflict')::int, 1, 'one sync.operation_conflict audit row');

-- second push of op-1 with a DIFFERENT operation_type -> conflict ------------ 5
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-1","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'error'), 'conflict', 'reusing op-1 with a different operation_type returns conflict');

-- the stored ledger row is unchanged (still applied) ------------------------- 6
select is((select status from sync_operations where local_operation_id='op-1')::text, 'applied', 'the stored op-1 row is unchanged by the conflicting attempts');

select * from finish();
rollback;
