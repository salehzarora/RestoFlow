-- ============================================================================
-- RF-059 — pgTAP: sync_operations has no direct read; status is current-device only (A4)
-- ============================================================================
-- A4: deny direct `authenticated` SELECT on sync_operations; current-device status
-- visibility stays via RF-057 app.sync_pull operation_statuses (current-device
-- filtered). Two devices in one branch each push an op; then:
--   * a direct SELECT on sync_operations is DENIED (42501) for authenticated;
--   * device A's operation_statuses includes its OWN op and NOT device B's op
--     (no cross-device leakage via the allowed app-facing path);
--   * operation_statuses rows never expose the raw payload.
-- Fixtures + sync_push/sync_pull run as the BYPASSRLS connection role; the direct-read
-- denial runs as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059so-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf059so-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- device A pushes op-a, device B pushes op-b (each a distinct order)
select app.sync_push('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',
  '[{"local_operation_id":"op-a","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d1","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);
select app.sync_push('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da12',
  '[{"local_operation_id":"op-b","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-00000000a0d2","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f2","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb);

-- ===== direct authenticated SELECT on sync_operations is DENIED (A4) ========= 1
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok($$ select count(*) from sync_operations $$, '42501', NULL,
  'A4: authenticated has NO direct SELECT on sync_operations (revoked)');
reset role;

-- ===== device A operation_statuses: own op only, no cross-device leak ======== 2-4
select ok(
  (select bool_or(e->>'local_operation_id' = 'op-a')
   from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e),
  'device A operation_statuses INCLUDES its own op (op-a)');
select ok(
  not coalesce((select bool_or(e->>'local_operation_id' = 'op-b')
   from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), false),
  'device A operation_statuses does NOT include device B op (op-b) — no cross-device leak (A4)');
select is(
  jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows')::int,
  1, 'device A sees exactly ONE operation status (its own)');

-- ===== device B sees its own op, not device A's ============================== 5
select ok(
  not coalesce((select bool_or(e->>'local_operation_id' = 'op-a')
   from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da12',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows') e), false),
  'device B operation_statuses does NOT include device A op (op-a) — symmetric isolation');

-- ===== raw payload is never exposed in operation_statuses =================== 6
select ok(
  not ((app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['operation_statuses'],'{}'::jsonb,500) -> 'operation_statuses' -> 'rows' -> 0) ? 'payload'),
  'operation_statuses rows do NOT expose the raw payload (minimised exposure)');

select * from finish();
rollback;
