-- ============================================================================
-- RF-057 — pgTAP: exact-limit final-page pagination (RF057-B1)
-- ============================================================================
-- Regression for the has_more bug: with EXACTLY p_limit rows and none beyond,
-- has_more must be FALSE; only a (p_limit + 1)-th row makes has_more TRUE, and that
-- extra row is NOT in the page but IS returned by the next page. Verified for both a
-- business entity (orders) and operation_statuses. Fixtures inserted as the BYPASSRLS
-- connection role; the lookahead (limit + 1) is the actual mechanism.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057x2-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf057x2-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- ===== BUSINESS ENTITY: exactly p_limit (=2) rows after the (null) cursor =====
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000c0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o1','2026-06-20 10:00:00+00','2026-06-20 10:00:00+00'),
  ('00000000-0000-0000-0000-00000000c0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o2','2026-06-20 10:01:00+00','2026-06-20 10:01:00+00');

-- exactly 2 rows, limit 2 -> 2 rows, has_more FALSE, next_cursor = last returned --- 1-3
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' -> 'rows')::int, 2, 'exactly-limit page returns p_limit rows');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' ->> 'has_more')::boolean, false, 'has_more is FALSE when exactly p_limit rows exist and no more (RF057-B1)');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' -> 'next_cursor' ->> 'id'), '00000000-0000-0000-0000-00000000c0d2', 'next_cursor is the last RETURNED row (o2)');

-- add one more row -> page1 has 2 (NOT the extra), has_more TRUE; page2 has the extra -- 4-7
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, created_at, updated_at) values
  ('00000000-0000-0000-0000-00000000c0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'o3','2026-06-20 10:02:00+00','2026-06-20 10:02:00+00');
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' -> 'rows')::int, 2, 'with an extra row, page 1 still returns only p_limit rows');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' ->> 'has_more')::boolean, true, 'has_more is TRUE once a (p_limit + 1)-th row exists');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,2) -> 'changes' -> 'orders' -> 'rows' -> 1 ->> 'id'), '00000000-0000-0000-0000-00000000c0d2', 'the extra row (o3) is NOT in page 1 (page ends at o2)');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'], jsonb_build_object('orders', jsonb_build_object('updated_at','2026-06-20 10:01:00+00','id','00000000-0000-0000-0000-00000000c0d2')),2) -> 'changes' -> 'orders' -> 'rows' -> 0 ->> 'id'), '00000000-0000-0000-0000-00000000c0d3', 'the next page (from next_cursor) returns the extra row o3');

-- ===== OPERATION_STATUSES: exactly p_limit (=2) op rows for the current device =====
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"ops1","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000e1","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"ops2","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000e2","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);

-- exactly 2 op rows, limit 2 -> 2 rows, has_more FALSE ----------------------- 8-9
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,2) -> 'operation_statuses' -> 'rows')::int, 2, 'operation_statuses exactly-limit page returns p_limit rows');
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,2) -> 'operation_statuses' ->> 'has_more')::boolean, false, 'operation_statuses has_more is FALSE at exactly p_limit (RF057-B1)');

-- add a 3rd op -> page1 has_more TRUE; next page returns the remaining op ----- 10-11
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"ops3","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000e3","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select is((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,2) -> 'operation_statuses' ->> 'has_more')::boolean, true, 'operation_statuses has_more is TRUE once a 3rd op exists');
select is(
  jsonb_array_length(
    app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],
      jsonb_build_object('operation_statuses',
        app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,2) -> 'operation_statuses' -> 'next_cursor'),
      2) -> 'operation_statuses' -> 'rows')::int,
  1, 'the next operation_statuses page (from next_cursor) returns the remaining op');

-- raw payload is never exposed ----------------------------------------------- 12
select ok(
  not exists(select 1 from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e where e ? 'payload'),
  'operation_statuses never exposes raw payload');

select * from finish();
rollback;
