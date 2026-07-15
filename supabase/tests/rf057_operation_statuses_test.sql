-- ============================================================================
-- RF-057 — pgTAP: current-device operation-status / conflict feed (A4)
-- ============================================================================
-- sync_pull returns a CURRENT-ORG + CURRENT-DEVICE sync_operations feed so the
-- client can reconcile its outbox: applied, rejected, and conflict statuses (with
-- conflict_info) all surface; a different device's operations do NOT; the raw
-- `payload` is never exposed. Statuses come from RF-056 sync_push (push-side
-- detection/recording). Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf057o-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa22', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da22', '00000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf057o-c1@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf057o-c2@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ba01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF057-T1', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- da11 pushes: applied order, rejected payment (no shift), conflict discount (stale revision)
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-a","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ba01","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-r","operation_type":"payment.create","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","tender_type":"cash","amount_tendered_minor":1000}}]'::jsonb);
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-c","operation_type":"order.discount","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","scope":"order","discount_type":"fixed","value":100,"reason":"x","expected_revision":99}}]'::jsonb);
-- da22 pushes an applied order
select app.sync_push('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da22',
  '[{"local_operation_id":"op-d22","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d2","order_type":"dine_in","table_id":"00000000-0000-0000-0000-00000000ba01","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);

-- da11's operation_statuses feed: exactly its 3 ops, with the right statuses ---- 1-7
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows')::int, 3, 'da11 sees exactly its own 3 operations');
select ok((select bool_or(e->>'local_operation_id'='op-a' and e->>'status'='applied')  from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), 'the applied order op (op-a) is visible');
select ok((select bool_or(e->>'local_operation_id'='op-r' and e->>'status'='rejected') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), 'the rejected payment op (op-r) is visible');
select ok((select bool_or(e->>'local_operation_id'='op-c' and e->>'status'='conflict') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), 'the conflict discount op (op-c) is visible');
select ok((select bool_or(e->>'local_operation_id'='op-c' and (e->'conflict_info') is not null and e->>'conflict_info' <> 'null') from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), 'the conflict op carries conflict_info');
select ok(not exists(select 1 from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e where e->>'local_operation_id'='op-d22'), 'a DIFFERENT device''s operation (op-d22) is NOT in da11''s feed');
select ok(not exists(select 1 from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e where e ? 'payload'), 'raw payload is never exposed in the operation_statuses feed');

select * from finish();
rollback;
