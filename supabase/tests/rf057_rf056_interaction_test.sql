-- ============================================================================
-- RF-057 — pgTAP: interaction with RF-056 (status visibility + read-only)
-- ============================================================================
-- A status recorded by RF-056 sync_push (applied / rejected) is visible to the same
-- device via sync_pull's operation_statuses feed; sync_pull mutates NOTHING (the
-- ledger rows/statuses are unchanged after a pull) and is idempotent across repeated
-- pulls. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057x-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf057x-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into public.tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-0000007ab001'::uuid, '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'T1', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca57', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca57', 'Item', 1000, 'USD', 1);

-- RF-056: push an applied order and a rejected payment (no open shift)
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-a","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","table_id":"00000000-0000-0000-0000-0000007ab001","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-r","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb);

-- RF-056 statuses are visible via RF-057 sync_pull --------------------------- 1-2
select ok((select bool_or(e->>'local_operation_id'='op-a' and e->>'status'='applied')  from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), 'the sync_push-applied op is visible via sync_pull');
select ok((select bool_or(e->>'local_operation_id'='op-r' and e->>'status'='rejected') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), 'the sync_push-rejected op is visible via sync_pull');

-- sync_pull mutates NOTHING in sync_operations ------------------------------- 3-5
select is((select count(*) from sync_operations)::int, 2, 'two ledger rows exist before/independent of the pull');
select app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500);
select is((select count(*) from sync_operations)::int, 2, 'sync_pull did not insert/delete any sync_operations row');
select is((select status from sync_operations where local_operation_id='op-r')::text, 'rejected', 'sync_pull did not mutate the rejected op''s status');

-- pull is idempotent across repeated calls ----------------------------------- 6
select is(
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows')::int,
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows')::int,
  'two consecutive pulls return the same operation_statuses (idempotent read)');

select * from finish();
rollback;
