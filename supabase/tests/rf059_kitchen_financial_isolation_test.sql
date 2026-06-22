-- ============================================================================
-- RF-059 — pgTAP: kitchen_staff financial isolation + money redaction (A3, T-003)
-- ============================================================================
-- kitchen_staff must NOT receive any money figure:
--   * direct SELECT on financial tables (payments/shifts/cash_drawer_sessions/
--     branch_receipt_counters) AND money-bearing order tables returns ZERO rows
--     (RLS can_read_financials excludes kitchen_staff);
--   * sync_pull for kitchen_staff strips every *_minor / receipt field from
--     orders/order_items/order_item_modifiers rows (app.redact_money);
--   * non-kitchen financial roles (cashier) still SEE financial data and full
--     money in sync_pull (no over-redaction).
-- A real order + payment are created via the SECURITY DEFINER RPCs (fixture phase),
-- then visibility is checked as the authenticated kitchen vs cashier principals.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(14);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059kfi-a', 'USD');
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
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf059kfi-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf059kfi-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- create a real shift + order + cash payment via the SECURITY DEFINER RPCs (cashier)
select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-sub','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-pay','cash',1000,null);

-- ===== kitchen_staff: ZERO direct rows from money-bearing tables (T-003) ===== 1-5
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee04';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from payments)::int,               0, 'kitchen_staff: direct SELECT on payments returns ZERO rows');
select is((select count(*) from shifts)::int,                 0, 'kitchen_staff: direct SELECT on shifts returns ZERO rows');
select is((select count(*) from cash_drawer_sessions)::int,   0, 'kitchen_staff: direct SELECT on cash_drawer_sessions returns ZERO rows');
select is((select count(*) from branch_receipt_counters)::int,0, 'kitchen_staff: direct SELECT on branch_receipt_counters returns ZERO rows');
select is((select count(*) from orders)::int,                 0, 'kitchen_staff: direct SELECT on orders (money-bearing) returns ZERO rows');

-- ===== kitchen_staff: sync_pull strips ALL money keys (A3 redaction) ========= 6-9
select ok(
  (app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500)
   -> 'changes' -> 'orders' -> 'rows' -> 0) ? 'status',
  'kitchen sync_pull orders row keeps non-financial data (status present)');
select ok(
  not ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500)
        -> 'changes' -> 'orders' -> 'rows' -> 0) ? 'grand_total_minor'),
  'kitchen sync_pull orders row has NO grand_total_minor (redacted)');
select ok(
  not ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500)
        -> 'changes' -> 'orders' -> 'rows' -> 0) ? 'receipt_number'),
  'kitchen sync_pull orders row has NO receipt_number (redacted)');
select ok(
  not ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['order_items'],'{}'::jsonb,500)
        -> 'changes' -> 'order_items' -> 'rows' -> 0) ? 'line_total_minor'),
  'kitchen sync_pull order_items row has NO line_total_minor (redacted)');
-- RF059-B1: the INFIX snapshot money key must be redacted too (it ends in _snapshot, not _minor)
select ok(
  not ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['order_items'],'{}'::jsonb,500)
        -> 'changes' -> 'order_items' -> 'rows' -> 0) ? 'unit_price_minor_snapshot'),
  'kitchen sync_pull order_items row has NO unit_price_minor_snapshot (RF059-B1: infix _minor_ token redacted)');

-- ===== cashier (financial role): still SEES money — no over-redaction ======== 10-13
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
select is((select count(*) from payments)::int, 1, 'cashier: direct SELECT on payments returns the payment row (financial role)');
select is((select count(*) from orders)::int,   1, 'cashier: direct SELECT on orders returns the order row');
select ok(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500)
   -> 'changes' -> 'orders' -> 'rows' -> 0) ? 'grand_total_minor',
  'cashier sync_pull orders row KEEPS grand_total_minor (full money for financial role)');
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500)
   -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'grand_total_minor'),
  '1000', 'cashier sync_pull orders row shows the real grand_total_minor (1000)');

select * from finish();
rollback;
