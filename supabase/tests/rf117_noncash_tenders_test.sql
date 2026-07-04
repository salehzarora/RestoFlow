-- ============================================================================
-- RF-117 — pgTAP: non-cash tenders in app.record_payment + the money-safety
-- invariant that non-cash NEVER inflates expected cash (MONEY §14).
--  * cash keeps tendered>=grand + change=tendered-grand (RF-054 preserved).
--  * card/bit/external record method=<tender>, tendered=grand, change=0.
--  * a bogus tender is rejected (42501) by the RPC; the DB CHECK rejects a
--    direct bad method (layer 4).
--  * close_shift.expected_total_minor = opening + CASH completed only.
-- Fixtures inserted as the BYPASSRLS harness role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000122000a00', 'Org A', 'rf117tnd-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a00', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000122000a1a', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-000122004001', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a1a', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000122004011', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a1a', '00000000-0000-0000-0000-000122004001', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-000122004051', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a1a', '00000000-0000-0000-0000-000122004001', '00000000-0000-0000-0000-000122004011');
insert into app_users (id, email) values ('00000000-0000-0000-0000-000122000e01', 'rf117tnd-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000122000f01', '00000000-0000-0000-0000-000122000e01', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a1a', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-000122000ef1', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a1a', '00000000-0000-0000-0000-000122000e01', '00000000-0000-0000-0000-000122000f01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-000122000c51', '00000000-0000-0000-0000-000122000a00', '00000000-0000-0000-0000-000122000a10', '00000000-0000-0000-0000-000122000a1a', '00000000-0000-0000-0000-000122004051', '00000000-0000-0000-0000-000122000ef1', '00000000-0000-0000-0000-000122000f01', now() + interval '1 hour');
-- four submitted orders: cash 1000, card 2000, bit 3000, external 4000
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-000122000d01', '00000000-0000-0000-0000-000122000a00','00000000-0000-0000-0000-000122000a10','00000000-0000-0000-0000-000122000a1a','00000000-0000-0000-0000-000122004001','00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000ef1','00000000-0000-0000-0000-000122000f01','dine_in','submitted','ILS',1000,1000,'ord-cash'),
  ('00000000-0000-0000-0000-000122000d02', '00000000-0000-0000-0000-000122000a00','00000000-0000-0000-0000-000122000a10','00000000-0000-0000-0000-000122000a1a','00000000-0000-0000-0000-000122004001','00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000ef1','00000000-0000-0000-0000-000122000f01','dine_in','submitted','ILS',2000,2000,'ord-card'),
  ('00000000-0000-0000-0000-000122000d03', '00000000-0000-0000-0000-000122000a00','00000000-0000-0000-0000-000122000a10','00000000-0000-0000-0000-000122000a1a','00000000-0000-0000-0000-000122004001','00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000ef1','00000000-0000-0000-0000-000122000f01','dine_in','submitted','ILS',3000,3000,'ord-bit'),
  ('00000000-0000-0000-0000-000122000d04', '00000000-0000-0000-0000-000122000a00','00000000-0000-0000-0000-000122000a10','00000000-0000-0000-0000-000122000a1a','00000000-0000-0000-0000-000122004001','00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000ef1','00000000-0000-0000-0000-000122000f01','dine_in','submitted','ILS',4000,4000,'ord-ext');

-- All RPCs authorize via the PIN session (not the role/GUC), so the whole test
-- runs as the BYPASSRLS connection role — direct `payments` selects then bypass
-- RLS to inspect what the SECURITY DEFINER RPC wrote (rf055_payment_linkage pattern).

-- open the shift + active drawer (opening float 0)
select app.open_shift('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122005f01','00000000-0000-0000-0000-000122005cd1','00000000-0000-0000-0000-000122004001','o-sh',0);

-- CASH: tendered 1500 over a 1000 order -> change 500 (RF-054 preserved) ------ 1-2
select is(app.record_payment('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000d01','00000000-0000-0000-0000-000122004001','lp-cash','cash',1500,null) ->> 'method', 'cash', 'a cash payment records method=cash');
select is((select change_minor from payments where order_id='00000000-0000-0000-0000-000122000d01')::bigint, 500::bigint, 'cash change = tendered - total = 1500 - 1000 = 500');

-- CARD: change 0, method card ------------------------------------------------- 3-4
select is(app.record_payment('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000d02','00000000-0000-0000-0000-000122004001','lp-card','card',2000,null) ->> 'method', 'card', 'a card payment records method=card');
select is((select (method, change_minor)::text from payments where order_id='00000000-0000-0000-0000-000122000d02'), ('card', 0)::text, 'card records method=card with change 0');

-- BIT: change 0, amount = grand_total --------------------------------------- 5-6
select is(app.record_payment('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000d03','00000000-0000-0000-0000-000122004001','lp-bit','bit',0,null) ->> 'method', 'bit', 'a Bit payment records method=bit');
select is((select (change_minor, amount_minor)::text from payments where order_id='00000000-0000-0000-0000-000122000d03'), (0, 3000)::text, 'bit change 0, amount = grand_total 3000');

-- EXTERNAL: change 0, amount = grand_total ---------------------------------- 7-8
select is(app.record_payment('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000d04','00000000-0000-0000-0000-000122004001','lp-ext','external',0,null) ->> 'method', 'external', 'an external payment records method=external');
select is((select (change_minor, amount_minor)::text from payments where order_id='00000000-0000-0000-0000-000122000d04'), (0, 4000)::text, 'external change 0, amount = grand_total 4000');

-- a bogus tender is rejected by the RPC -------------------------------------- 9
select throws_ok($$ select app.record_payment('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122000d01','00000000-0000-0000-0000-000122004001','lp-x','crypto',1000,null) $$, '42501', NULL, 'an unsupported tender type is rejected (42501)');

-- the DB CHECK rejects a direct bad method (layer 4) ------------------------- 10
select throws_ok($$ insert into public.payments (organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values ('00000000-0000-0000-0000-000122000a00','00000000-0000-0000-0000-000122000a10','00000000-0000-0000-0000-000122000a1a','00000000-0000-0000-0000-000122000d01','00000000-0000-0000-0000-000122004001','00000000-0000-0000-0000-000122000ef1','00000000-0000-0000-0000-000122000f01','crypto','completed',1000,1000,0,'ILS','x-bad') $$, '23514', NULL, 'the payments.method CHECK rejects an unknown method (layer 4)');

-- four completed payments recorded ------------------------------------------ 11
select is((select count(*) from payments where organization_id='00000000-0000-0000-0000-000122000a00' and status='completed')::int, 4, 'all four tenders recorded a completed payment');

-- THE INVARIANT: close_shift expected = opening + CASH only (non-cash excluded) 12
select is(
  app.close_shift('00000000-0000-0000-0000-000122000c51','00000000-0000-0000-0000-000122005f01','00000000-0000-0000-0000-000122004001','c-sh',1000,null) ->> 'expected_total_minor',
  '1000',
  'close_shift expected cash = opening 0 + CASH 1000 ONLY (card/bit/external excluded; MONEY 14)');

select * from finish();
rollback;
