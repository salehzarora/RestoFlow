-- ============================================================================
-- RF-059 — pgTAP: RPC regression under the new per-command / DENY policies
-- ============================================================================
-- The full mutation surface must still work: the SECURITY DEFINER RPCs (owned by a
-- BYPASSRLS role) keep writing despite the explicit INSERT/UPDATE/DELETE DENY
-- policies + revoked grants added by RF-059. End-to-end: open_shift -> submit_order
-- -> apply_discount -> record_payment -> submit_order -> void_order -> close_shift
-- -> reconcile_shift -> sync_push -> sync_pull. Plus: pagination (RF057-B1 limit+1)
-- still works, and kitchen money redaction does NOT break the cursor/has_more.
-- Calls run as the BYPASSRLS connection role (the RPCs derive the app role from the
-- PIN session, not the DB role) — matching the RF-052..057 functional test pattern.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(16);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059rpc-a', 'USD');
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
  ('00000000-0000-0000-0000-00000000ee01', 'rf059rpc-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf059rpc-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf059rpc-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF059 T1', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ===== full mutation flow via the SECURITY DEFINER RPCs ====================== 1-8
select is((app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000) ->> 'ok')::boolean, true,
  'open_shift still works under RF-059 policies');                                                                                            -- 1
select is((app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-subX','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) ->> 'ok')::boolean, true,
  'submit_order still works');                                                                                                                -- 2
select is((app.apply_discount('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-disc','order',null,'fixed',100,'promo',null) ->> 'ok')::boolean, true,
  'apply_discount (manager) still works');                                                                                                    -- 3
select is((app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-pay','cash',900,null) ->> 'ok')::boolean, true,
  'record_payment still works (grand 900 after 100 discount)');                                                                               -- 4
select is((app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-subY','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) ->> 'ok')::boolean, true,
  'submit_order (second order) still works');                                                                                                 -- 5
select is((app.void_order('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-void','mistake',null) ->> 'ok')::boolean, true,
  'void_order (manager) still works');                                                                                                        -- 6
select is((app.close_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','op-close',5900,null,null) ->> 'ok')::boolean, true,
  'close_shift (cashier own shift) still works (expected 5000 float + 900 cash = 5900)');                                                     -- 7
select is((app.reconcile_shift('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','op-rec',null,null) ->> 'ok')::boolean, true,
  'reconcile_shift (manager) still works');                                                                                                   -- 8

-- ===== sync_pull + pagination (RF057-B1) unchanged =========================== 9-11
select is(
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows')::int,
  2, 'sync_pull (cashier) returns both orders');                                                                                              -- 9
select is(
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' -> 'rows')::int,
  1, 'sync_pull pagination: limit 1 returns exactly one row');                                                                                -- 10
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' ->> 'has_more')::boolean,
  true, 'sync_pull pagination: has_more is true with two orders and limit 1 (RF057-B1)');                                                      -- 11

-- ===== kitchen redaction does NOT break pagination/cursor ==================== 12-14
select is(
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' -> 'rows')::int,
  1, 'kitchen sync_pull pagination: limit 1 returns one (redacted) row');                                                                     -- 12
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' ->> 'has_more')::boolean,
  true, 'kitchen sync_pull pagination: has_more still true (redaction does not break paging)');                                               -- 13
select ok(
  ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' -> 'next_cursor') ? 'updated_at')
  and not ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' -> 'rows' -> 0) ? 'grand_total_minor'),
  'kitchen sync_pull: next_cursor intact (updated_at present) AND the row is money-redacted');                                                -- 14

-- ===== sync_push still dispatches under the new policies ===================== 15-16
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-z","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d3","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ab1e","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'sync_push still dispatches order.submit -> applied under RF-059');                              -- 15
select is(
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows')::int,
  3, 'sync_pull now returns all three orders (the sync_push order applied)');                                                                  -- 16

select * from finish();
rollback;
