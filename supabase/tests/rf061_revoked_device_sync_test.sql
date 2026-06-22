-- ============================================================================
-- RF-061 — pgTAP: a revoked device's sync_push records rejected ops (AC1)
-- ============================================================================
-- After app.revoke_device, the device's queued offline operations pushed on reconnect
-- are RECORDED as rejected (revoked_device) in sync_operations + audited
-- (sync.operation_rejected), create NO business state, and are returned as rejected
-- results — instead of a silent batch raise. sync_pull from the revoked device still
-- rejects (the reconnect signal). Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf061rds-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf061rds-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf061rds-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- revoke the device (manager), then the cashier on that device pushes a queued op
select app.revoke_device('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000da11','op-rd','device lost');

-- ===== revoked-device sync_push records rejected ops (no business state) ==== 1-6
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da11','[{"local_operation_id":"op-a","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'rejected',
  'a revoked device''s queued op is returned as rejected');
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da11','[{"local_operation_id":"op-a","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'detail'), 'revoked_device',
  'the rejected result carries detail=revoked_device');
select is((select status from sync_operations where local_operation_id='op-a')::text, 'rejected',
  'the op is RECORDED in sync_operations as rejected (AC1: rejected and recorded)');
select is((select last_error_code from sync_operations where local_operation_id='op-a')::text, 'revoked_device',
  'the recorded op carries last_error_code=revoked_device');
select ok(exists(select 1 from audit_events where action='sync.operation_rejected' and reason='revoked_device' and (new_values->>'local_operation_id')='op-a'),
  'a sync.operation_rejected audit (reason revoked_device) was written');
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000a0d1')::int, 0,
  'NO order (business state) was created from the revoked-device push');

-- ===== sync_pull from the revoked device still rejects (reconnect signal) ==== 7
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'sync_pull from a revoked device still rejects (42501) — the reconnect signal');

select * from finish();
rollback;
