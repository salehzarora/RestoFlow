-- ============================================================================
-- RF-062 — pgTAP: only a LIVE completed payment blocks; both RPCs lock the order
-- ============================================================================
-- A3: only a live `payments.status='completed'` (deleted_at IS NULL) blocks a void;
-- a non-completed payment (`failed`) and a TOMBSTONED completed payment (deleted_at
-- set) do NOT block. Plus a static proof (A1/A4) that both app.void_order and
-- app.record_payment load the order row FOR UPDATE so they serialize on it.
-- The non-completed/tombstoned payment rows are inserted directly as the BYPASSRLS
-- connection role (the established fixture pattern; record_payment only ever produces
-- a live 'completed' payment, so these states cannot be reached through the RPC).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf062b-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf062b-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- O6 (with a FAILED payment) and O7 (with a TOMBSTONED completed payment), inserted
-- directly as the owner — these payment states are unreachable via record_payment.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d6', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o6-fixt'),
  ('00000000-0000-0000-0000-00000000a0d7', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o7-fixt');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('00000000-0000-0000-0000-0000000051d6', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d6','00000000-0000-0000-0000-0000000000f1','pending',1,'Item',1000,1000),
  ('00000000-0000-0000-0000-0000000051d7', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d7','00000000-0000-0000-0000-0000000000f1','pending',1,'Item',1000,1000);
-- O6: a FAILED payment (not settled money) — must NOT block the void
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-00000000fa06', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d6','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','cash','failed',0,0,0,'USD','p-failed');
-- O7: a TOMBSTONED completed payment (deleted_at set) — must NOT block the void (A3)
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, deleted_at) values
  ('00000000-0000-0000-0000-00000000fa07', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d7','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','cash','completed',1000,1000,0,'USD','p-tomb', now());

-- ===== T6: non-completed / tombstoned payments do NOT block the void ========= 1-4
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d6','00000000-0000-0000-0000-00000000da11','op-v6','void with failed payment',null) ->> 'ok')::boolean, true,
  'a FAILED payment does NOT block the void (only a live completed payment blocks)');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d6')::text, 'voided', 'O6 (failed payment) is voided');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d7','00000000-0000-0000-0000-00000000da11','op-v7','void with tombstoned payment',null) ->> 'ok')::boolean, true,
  'a TOMBSTONED completed payment (deleted_at set) does NOT block the void (A3 deleted_at filter)');
select is((select status from orders where id='00000000-0000-0000-0000-00000000a0d7')::text, 'voided', 'O7 (tombstoned completed payment) is voided');

-- ===== T8: static proof both RPCs load the order FOR UPDATE (A1/A4) ========== 5-6
select ok(
  pg_get_functiondef('app.void_order(uuid,uuid,uuid,text,text,integer)'::regprocedure)
    ~* 'orders o where o\.id = p_order_id[[:space:]]+for update',
  'app.void_order loads the order row FOR UPDATE (RF-062 A4: serializes with record_payment)');
select ok(
  pg_get_functiondef('app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)'::regprocedure)
    ~* 'orders o where o\.id = p_order_id[[:space:]]+for update',
  'app.record_payment loads the order row FOR UPDATE (RF-062 A1: serializes with void_order)');

select * from finish();
rollback;
