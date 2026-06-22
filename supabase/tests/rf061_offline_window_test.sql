-- ============================================================================
-- RF-061 — pgTAP: offline-window bound (expired PIN session) (AC3)
-- ============================================================================
-- A PIN session past the bounded offline window (app.pin_session_offline_window(),
-- the interim 8h Q-009 config-point — NOT changed by RF-061) is invalid: sensitive
-- RPCs (submit_order / sync_pull / sync_push) reject it, forcing re-auth. This bounds
-- how long a (possibly revoked) actor can keep acting offline. Fixtures inserted as the
-- BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf061ow-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf061ow-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000005e1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() - interval '1 hour');  -- EXPIRED (past the window)

-- ===== the offline window is the existing 8h config-point (Q-009 NOT changed) = 1
select is(app.pin_session_offline_window(), interval '8 hours',
  'the offline window helper is unchanged (interim 8h; Q-009 not frozen/altered by RF-061)');

-- ===== validity ============================================================= 2-3
select is(app.is_pin_session_valid('00000000-0000-0000-0000-0000000005e1'), false,
  'an EXPIRED PIN session (past the offline window) is invalid');
select is(app.is_pin_session_valid('00000000-0000-0000-0000-00000000c501'), true,
  'a PIN session within the window is valid (control)');

-- ===== sensitive RPCs reject the expired session (forced re-auth) =========== 4-6
select throws_ok(
  $$ select app.submit_order('00000000-0000-0000-0000-0000000005e1','00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-00000000da11','op-ow','dine_in',null,null,'USD',null,'[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) $$,
  '42501', NULL, 'submit_order with an expired PIN session is rejected (offline window exceeded)');
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-0000000005e1','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'sync_pull with an expired PIN session is rejected');
select throws_ok(
  $$ select app.sync_push('00000000-0000-0000-0000-0000000005e1','00000000-0000-0000-0000-00000000da11','[{"local_operation_id":"op-ow2","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000d2","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb) $$,
  '42501', NULL, 'sync_push with an expired PIN session is rejected (PIN-validity raises before the device-revoked branch)');

select * from finish();
rollback;
