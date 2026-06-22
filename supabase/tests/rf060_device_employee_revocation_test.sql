-- ============================================================================
-- RF-060 — CANONICAL gate: device & employee revocation (T-004, T-005)
-- ============================================================================
-- T-004: a wrong device, a revoked backing device session, and an expired PIN session
--   are each rejected by the order/sync RPCs (server-side, online path).
-- T-005: a removed/revoked employee (membership.status='revoked') cannot create new
--   valid operations — submit_order raises, and a sync_push op is recorded 'rejected'
--   and produces NO order.
-- SCOPE: this covers the ONLINE server-side rejection that exists today. The offline
-- "operations dated AFTER revocation, queued while disconnected" propagation is RF-061
-- and is NOT exercised here. Fixtures as the BYPASSRLS connection role; RPCs invoked as
-- the connection role (scope/actor derived from the PIN session).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf060dev-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');  -- a DIFFERENT device (wrong-device test)
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');  -- to be revoked
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf060dev-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee05', 'rf060dev-removed@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab05', '00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-00000000ab05');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000005e1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() - interval '1 hour'),  -- EXPIRED
  ('00000000-0000-0000-0000-00000000c5a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),  -- on the to-be-revoked session
  ('00000000-0000-0000-0000-00000000c5a5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef005', '00000000-0000-0000-0000-00000000ab05', now() + interval '1 hour');  -- removed employee
-- revoke the backing device session of c5rv1 (AFTER the backing-guard insert), and revoke the membership of the removed employee
update device_sessions set revoked_at = now(), is_active = false where id = '00000000-0000-0000-0000-0000000005a2';
update memberships set status = 'revoked' where id = '00000000-0000-0000-0000-00000000ab05';

-- ===== T-004 device rejection ============================================== 1-5
select throws_ok(
  $$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-00000000da12','op-wd','dine_in',null,null,'USD',null,'[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) $$,
  '42501', NULL, 'T-004: a device_id NOT matching the PIN session device is rejected (wrong device)');
select throws_ok(
  $$ select app.submit_order('00000000-0000-0000-0000-0000000005e1','00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-00000000da11','op-exp','dine_in',null,null,'USD',null,'[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) $$,
  '42501', NULL, 'T-004: an EXPIRED PIN session cannot submit');
select throws_ok(
  $$ select app.submit_order('00000000-0000-0000-0000-00000000c5a2','00000000-0000-0000-0000-0000000000d3','00000000-0000-0000-0000-00000000da11','op-rv','dine_in',null,null,'USD',null,'[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) $$,
  '42501', NULL, 'T-004: a REVOKED backing device session cannot submit');
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-00000000c5a2','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'T-004: a revoked backing device session cannot sync_pull');
select throws_ok(
  $$ select app.sync_push('00000000-0000-0000-0000-00000000c5a2','00000000-0000-0000-0000-00000000da11','[{"local_operation_id":"op-rvp","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000d4","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb) $$,
  '42501', NULL, 'T-004: a revoked backing device session fails the whole sync_push batch (R-007)');

-- ===== T-005 removed/revoked employee ====================================== 6-8
select throws_ok(
  $$ select app.submit_order('00000000-0000-0000-0000-00000000c5a5','00000000-0000-0000-0000-0000000000d5','00000000-0000-0000-0000-00000000da11','op-rm','dine_in',null,null,'USD',null,'[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) $$,
  '42501', NULL, 'T-005: a revoked-membership employee cannot submit_order (resolved membership not active)');
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c5a5','00000000-0000-0000-0000-00000000da11','[{"local_operation_id":"op-rmp","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000d6","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'rejected',
  'T-005: a revoked-membership op pushed via sync_push is recorded rejected (no valid mutation)');
select is((select count(*) from orders where id='00000000-0000-0000-0000-0000000000d6')::int, 0,
  'T-005: the rejected revoked-membership op created NO order');

-- ===== no-state-change sanity: NONE of the rejected attempts created an order = 9
select is((select count(*) from orders)::int, 0,
  'no rejected device/employee attempt created any order (no committed mutation)');

select * from finish();
rollback;
