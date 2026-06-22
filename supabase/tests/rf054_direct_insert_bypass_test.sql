-- ============================================================================
-- RF-054 — pgTAP: direct-write bypass prevention
-- ============================================================================
-- An `authenticated` client must NOT write payments / branch_receipt_counters
-- directly (that would bypass app.record_payment's authorization, tender/change
-- validation, receipt allocation, and idempotency), nor write a record_payment
-- row into the order_operations ledger. INSERT/UPDATE/DELETE on the new tables are
-- revoked; the SECURITY DEFINER RPC is the only writer (D-011). Fixtures inserted
-- as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf054b-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee02', 'rf054b-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','dine_in','submitted','USD',1000,1000,'ord-1');

-- ===== authenticated: direct writes to the new tables are DENIED ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee02';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select throws_ok($$
  insert into payments (organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, method, status,
    amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab02','cash','completed',1000,1000,0,'USD','direct-1')
$$, '42501', NULL, 'authenticated direct INSERT into payments is DENIED');                                     -- 1
select throws_ok($$ update payments set status='voided' where order_id='00000000-0000-0000-0000-00000000a0d1' $$, '42501', NULL, 'authenticated direct UPDATE on payments is DENIED');                                   -- 2
select throws_ok($$ delete from payments where order_id='00000000-0000-0000-0000-00000000a0d1' $$, '42501', NULL, 'authenticated direct DELETE on payments is DENIED');                                                 -- 3

select throws_ok($$
  insert into branch_receipt_counters (organization_id, restaurant_id, branch_id, last_issued_value)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1',5)
$$, '42501', NULL, 'authenticated direct INSERT into branch_receipt_counters is DENIED');                       -- 4
select throws_ok($$ update branch_receipt_counters set last_issued_value=99 where branch_id='00000000-0000-0000-0000-00000000a1b1' $$, '42501', NULL, 'authenticated direct UPDATE on branch_receipt_counters is DENIED'); -- 5
select throws_ok($$ delete from branch_receipt_counters where branch_id='00000000-0000-0000-0000-00000000a1b1' $$, '42501', NULL, 'authenticated direct DELETE on branch_receipt_counters is DENIED');                     -- 6

select throws_ok($$
  insert into order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
  values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','x','record_payment','00000000-0000-0000-0000-00000000a0d1','{}'::jsonb)
$$, '42501', NULL, 'authenticated cannot directly write a record_payment row into order_operations');           -- 7

reset role;

-- ===== the SECURITY DEFINER RPC path CAN record a payment =================== 8-9
select is((app.record_payment('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-rpc','cash',1000,null) ->> 'ok')::boolean, true, 'the SECURITY DEFINER RPC path CAN record a payment');
select is((select count(*) from payments where local_operation_id='op-rpc')::int, 1, 'the RPC created exactly one payment (the only write path)');

select * from finish();
rollback;
