-- ============================================================================
-- RF-054 — pgTAP: append-only audit (A8, D-013)
-- ============================================================================
-- A successful payment writes exactly two append-only audit rows: payment.recorded
-- (with amounts + order/payment/receipt context) and receipt_number.assigned (with
-- branch + receipt number; old_values records the prior NULL receipt). The actor is
-- the attempting employee profile. A replay writes NEITHER row a second time.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(10);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf054a-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee02', 'rf054a-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'ord-1');

-- record a payment (tendered 1500, total 1000 => change 500)
select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-audit','cash',1500,null);

-- exactly the two expected audit rows ---------------------------------------- 1-2
select is((select count(*) from audit_events where action='payment.recorded')::int,        1, 'success wrote one payment.recorded audit row');
select is((select count(*) from audit_events where action='receipt_number.assigned')::int, 1, 'success wrote one receipt_number.assigned audit row');

-- payment.recorded new_values carry the amounts + receipt + order/payment ----- 3-5
select is((select new_values->>'amount_minor'   from audit_events where action='payment.recorded'), '1000', 'payment.recorded new_values.amount_minor = 1000');
select is((select new_values->>'change_minor'   from audit_events where action='payment.recorded'), '500',  'payment.recorded new_values.change_minor = 500');
select is((select new_values->>'receipt_number' from audit_events where action='payment.recorded'), '1',    'payment.recorded new_values.receipt_number = 1');

-- receipt_number.assigned new_values + old_values ---------------------------- 6-7
select is((select new_values->>'receipt_number' from audit_events where action='receipt_number.assigned'), '1', 'receipt_number.assigned new_values.receipt_number = 1');
select ok((select old_values ? 'receipt_number' from audit_events where action='receipt_number.assigned'), 'receipt_number.assigned old_values records the prior (NULL) receipt_number key');

-- the actor is the attempting employee profile ------------------------------- 8
select is((select actor_employee_profile_id from audit_events where action='payment.recorded'), '00000000-0000-0000-0000-0000000ef002'::uuid, 'the payment.recorded audit records the acting employee profile');

-- a replay does NOT duplicate either audit row ------------------------------- 9-10
select app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-audit','cash',1500,null);
select is((select count(*) from audit_events where action='payment.recorded')::int,        1, 'replay wrote NO second payment.recorded audit row');
select is((select count(*) from audit_events where action='receipt_number.assigned')::int, 1, 'replay wrote NO second receipt_number.assigned audit row');

select * from finish();
rollback;
