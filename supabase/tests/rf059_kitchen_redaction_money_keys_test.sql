-- ============================================================================
-- RF-059 / RF059-B1 — pgTAP: kitchen sync_pull money-key redaction (token-based)
-- ============================================================================
-- app.redact_money must remove EVERY money key — not just suffix `_minor` keys but
-- also INFIX snapshot keys (unit_price_minor_snapshot, price_minor_snapshot) — for
-- kitchen_staff across orders / order_items / order_item_modifiers, while preserving
-- non-money fields (status, quantity, name snapshots, ids, timestamps, deleted_at).
-- A real order WITH a modifier (so order_item_modifiers carries price_minor_snapshot)
-- plus a tombstoned order are created in the fixture phase; redaction is then checked
-- for kitchen vs the full money kept for the cashier. The generic token pattern
-- (^|_)minor($|_) is asserted across every kitchen-visible row key.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059red-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf059red-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf059red-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- a live active dining table so the dine_in submit passes RESTAURANT-OPERATIONS-V1-001 table rules
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF059 T1', true);

-- sellable menu fixture so order.submit passes the RESTAURANT-OPERATIONS-V1-001 item sellability check
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item', 1000, 'USD', 1);

-- a real order WITH a modifier (order_item_modifiers gets price_minor_snapshot)
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-sub','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","option_name_snapshot":"Extra Cheese","price_minor_snapshot":100,"quantity":1}]}]'::jsonb,
  1100,0,0,1100,null);
-- a tombstoned order (deleted_at set) in the same branch (inserted as the owner)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, deleted_at) values
  ('00000000-0000-0000-0000-00000000a0d9', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','voided','USD',1000,1000,'o-tomb', now());
-- a kitchen push (denied -> rejected) so the kitchen device has an operation_status row
select app.sync_push('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',
  '[{"local_operation_id":"op-k","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0dk","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);

-- ===== generic token pattern: NO kitchen-visible row key matches (^|_)minor($|_) === 1-3
select is(
  (select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') as r
   cross join lateral jsonb_object_keys(r) as keys(key) where keys.key ~ '(^|_)minor($|_)')::int,
  0, 'kitchen orders rows: NO key matches the money token pattern (^|_)minor($|_)');
select is(
  (select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_items'],'{}'::jsonb,500) -> 'changes' -> 'order_items' -> 'rows') as r
   cross join lateral jsonb_object_keys(r) as keys(key) where keys.key ~ '(^|_)minor($|_)')::int,
  0, 'kitchen order_items rows: NO key matches the money token pattern (catches unit_price_minor_snapshot)');
select is(
  (select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_item_modifiers'],'{}'::jsonb,500) -> 'changes' -> 'order_item_modifiers' -> 'rows') as r
   cross join lateral jsonb_object_keys(r) as keys(key) where keys.key ~ '(^|_)minor($|_)')::int,
  0, 'kitchen order_item_modifiers rows: NO key matches the money token pattern (catches price_minor_snapshot)');

-- ===== explicit flagged keys absent ========================================= 4-7
select ok(
  (select bool_and(not (r ? 'unit_price_minor_snapshot')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_items'],'{}'::jsonb,500) -> 'changes' -> 'order_items' -> 'rows') r),
  'kitchen order_items: unit_price_minor_snapshot is redacted (RF059-B1)');
select ok(
  (select bool_and(not (r ? 'price_minor_snapshot')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_item_modifiers'],'{}'::jsonb,500) -> 'changes' -> 'order_item_modifiers' -> 'rows') r),
  'kitchen order_item_modifiers: price_minor_snapshot is redacted (RF059-B1)');
select ok(
  (select bool_and(not (r ? 'receipt_number') and not (r ? 'receipt_provisional_id')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'kitchen orders: receipt_number + receipt_provisional_id redacted (explicit denylist preserved)');
select ok(
  (select bool_and(not (r ? 'grand_total_minor') and not (r ? 'line_total_minor')) from
     (select r from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r
      union all
      select r from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_items'],'{}'::jsonb,500) -> 'changes' -> 'order_items' -> 'rows') r) all_rows(r)),
  'kitchen: suffix money keys grand_total_minor / line_total_minor remain redacted');

-- ===== non-money fields preserved =========================================== 8-12
select ok(
  (select bool_and(r ? 'status') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'kitchen orders: non-money field `status` preserved');
select ok(
  (select bool_and((r ? 'id') and (r ? 'updated_at') and (r ? 'order_type')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'kitchen orders: id/updated_at/order_type (sync + display fields) preserved');
select ok(
  (select bool_and((r ? 'menu_item_name_snapshot') and (r ? 'quantity') and (r ? 'status')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_items'],'{}'::jsonb,500) -> 'changes' -> 'order_items' -> 'rows') r),
  'kitchen order_items: non-money name snapshot + quantity + status preserved');
select ok(
  (select bool_and((r ? 'option_name_snapshot') and (r ? 'quantity')) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_item_modifiers'],'{}'::jsonb,500) -> 'changes' -> 'order_item_modifiers' -> 'rows') r),
  'kitchen order_item_modifiers: non-money option name + quantity preserved');
-- tombstone row present with deleted_at preserved (and, per assertion 1, no money keys)
select ok(
  (select bool_or((r ? 'deleted_at') and (r ->> 'deleted_at') is not null) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'kitchen orders: tombstone row carries deleted_at (tombstone behavior unchanged; money still redacted)');

-- ===== cursor / has_more / operation_statuses unchanged ===================== 13-15
select ok(
  ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'next_cursor') ? 'updated_at')
  and ((app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'next_cursor') ? 'id'),
  'kitchen orders next_cursor still carries (updated_at, id) — cursor model unchanged');
select is(
  (app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,1) -> 'changes' -> 'orders' ->> 'has_more')::boolean,
  true, 'kitchen orders has_more=true at limit 1 over 2 orders (RF057-B1 pagination intact under redaction)');
select is(
  (select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') r where r ? 'payload')::int,
  0, 'kitchen operation_statuses rows still do NOT expose the raw payload (1 rejected op present)');

-- ===== non-kitchen (cashier) still receives full money ====================== 16-18
select ok(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['order_items'],'{}'::jsonb,500) -> 'changes' -> 'order_items' -> 'rows' -> 0) ? 'unit_price_minor_snapshot',
  'cashier order_items KEEPS unit_price_minor_snapshot (no over-redaction for financial roles)');
select ok(
  (app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['order_item_modifiers'],'{}'::jsonb,500) -> 'changes' -> 'order_item_modifiers' -> 'rows' -> 0) ? 'price_minor_snapshot',
  'cashier order_item_modifiers KEEPS price_minor_snapshot');
select ok(
  (select bool_or((r ->> 'grand_total_minor') = '1100') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'cashier orders KEEPS the real grand_total_minor (a row with 1100 is present)');

select * from finish();
rollback;
