-- ============================================================================
-- RF-054 — pgTAP: payment state legality + no auto-advance (AC#4, D-024/D-025)
-- ============================================================================
-- record_payment succeeds from submitted/accepted/preparing/ready/served and is
-- rejected from draft/cancelled/voided/completed. A second completed payment on
-- an already-paid order is rejected. The order's status is UNCHANGED after a
-- payment (payment does not auto-advance fulfillment, D-025), but its
-- receipt_number is set. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf054s-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee02', 'rf054s-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
-- one order per state (connection-role inserts can set any legal status value)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-0000000a5b01'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'s-sub'),
  ('00000000-0000-0000-0000-0000000a5b02'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','accepted','USD',1000,1000,'s-acc'),
  ('00000000-0000-0000-0000-0000000a5b03'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','preparing','USD',1000,1000,'s-prep'),
  ('00000000-0000-0000-0000-0000000a5b04'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','ready','USD',1000,1000,'s-ready'),
  ('00000000-0000-0000-0000-0000000a5b05'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','served','USD',1000,1000,'s-served'),
  ('00000000-0000-0000-0000-0000000a5b06'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','draft','USD',1000,1000,'s-draft'),
  ('00000000-0000-0000-0000-0000000a5b07'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','cancelled','USD',1000,1000,'s-canc'),
  ('00000000-0000-0000-0000-0000000a5b08'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','voided','USD',1000,1000,'s-void'),
  ('00000000-0000-0000-0000-0000000a5b09'::uuid, '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','completed','USD',1000,1000,'s-comp');

-- legal source states -> payment succeeds ----------------------------------- 1-5
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b01'::uuid,'00000000-0000-0000-0000-00000000da11','s-p1','cash',1000,null) ->> 'ok')::boolean, true, 'payment from submitted succeeds');
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b02'::uuid,'00000000-0000-0000-0000-00000000da11','s-p2','cash',1000,null) ->> 'ok')::boolean, true, 'payment from accepted succeeds');
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b03'::uuid,'00000000-0000-0000-0000-00000000da11','s-p3','cash',1000,null) ->> 'ok')::boolean, true, 'payment from preparing succeeds');
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b04'::uuid,'00000000-0000-0000-0000-00000000da11','s-p4','cash',1000,null) ->> 'ok')::boolean, true, 'payment from ready succeeds');
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b05'::uuid,'00000000-0000-0000-0000-00000000da11','s-p5','cash',1000,null) ->> 'ok')::boolean, true, 'payment from served succeeds');

-- forbidden source states -> rejected --------------------------------------- 6-9
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b06'::uuid,'00000000-0000-0000-0000-00000000da11','s-p6','cash',1000,null) $$, '42501', NULL, 'payment from draft rejected');
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b07'::uuid,'00000000-0000-0000-0000-00000000da11','s-p7','cash',1000,null) $$, '42501', NULL, 'payment from cancelled rejected');
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b08'::uuid,'00000000-0000-0000-0000-00000000da11','s-p8','cash',1000,null) $$, '42501', NULL, 'payment from voided rejected');
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b09'::uuid,'00000000-0000-0000-0000-00000000da11','s-p9','cash',1000,null) $$, '42501', NULL, 'payment from completed rejected (terminal)');

-- a second completed payment on the same order is rejected ------------------ 10
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000a5b01'::uuid,'00000000-0000-0000-0000-00000000da11','s-p1b','cash',1000,null) $$, '42501', NULL, 'a second completed payment on an already-paid order is rejected');

-- payment does NOT auto-advance the order status (D-025) -------------------- 11
select is((select status from orders where id='00000000-0000-0000-0000-0000000a5b01'::uuid)::text, 'submitted', 'order status is UNCHANGED after payment (no auto-advance to completed; D-025)');

-- but the receipt number IS set --------------------------------------------- 12
select isnt((select receipt_number from orders where id='00000000-0000-0000-0000-0000000a5b01'::uuid), null, 'the paid order has its receipt_number set');

select * from finish();
rollback;
