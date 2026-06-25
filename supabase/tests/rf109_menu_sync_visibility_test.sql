-- RF-109 Stage 3 -- menu sync_pull visibility / role gates / kitchen exclusion / tombstones / cursor
-- (DECISION D-031; API_CONTRACT §4.15; SECURITY T-013/T-003).
-- All sync_pull principals share one POS device on Branch A1a (Rest A1, Org A); each role has its
-- own PIN session. Menu rows have explicit updated_at so the (updated_at,id) cursor is deterministic.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(23);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109sync-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf109sync-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-00000000a2a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-00000000b1a0', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');

-- one POS device on Branch A1a; one device session shared by all the role PIN sessions
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da1a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa1a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000da1a', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000da1a', '00000000-0000-0000-0000-00000000fa1a');

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf109sync-owner@example.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'rf109sync-restowner@example.test'),
  ('00000000-0000-0000-0000-0000000000e3', 'rf109sync-manager@example.test'),
  ('00000000-0000-0000-0000-0000000000e4', 'rf109sync-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000000e5', 'rf109sync-acct@example.test'),
  ('00000000-0000-0000-0000-0000000000e6', 'rf109sync-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000ab001', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000ab002', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-0000000ab003', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'manager'),
  ('00000000-0000-0000-0000-0000000ab004', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'cashier'),
  ('00000000-0000-0000-0000-0000000ab005', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000000a0', null, null, 'accountant'),
  ('00000000-0000-0000-0000-0000000ab006', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000ab001'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000ab002'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000ab003'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-0000000ab004'),
  ('00000000-0000-0000-0000-0000000ef005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000e5', '00000000-0000-0000-0000-0000000ab005'),
  ('00000000-0000-0000-0000-0000000ef006', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000000e6', '00000000-0000-0000-0000-0000000ab006');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000c5001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000ab001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c5002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c5003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c5004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000ab004', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c5005', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef005', '00000000-0000-0000-0000-0000000ab005', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000c5006', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef006', '00000000-0000-0000-0000-0000000ab006', now() + interval '1 hour');

-- categories (restaurant-scoped; org B category for the cross-org item)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Cat A1'),
  ('00000000-0000-0000-0000-00000000ca02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', null, 'Cat A2'),
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1a0', 'Cat B1');
-- visibility items (old updated_at), + cursor items (distinct updated_at), CITEM3 a tombstone
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, updated_at, deleted_at) values
  ('00000000-0000-0000-0000-0000000d1a01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000ca01', 'Item A1a',  1500, 'USD', '2026-01-01 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000d1e01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   '00000000-0000-0000-0000-00000000ca01', 'Item Rest', 1600, 'USD', '2026-01-01 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000d1b01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b0', '00000000-0000-0000-0000-00000000ca01', 'Item A1b',  1700, 'USD', '2026-01-01 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000d2e01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', null,                                   '00000000-0000-0000-0000-00000000ca02', 'Item A2Rest', 1800, 'USD', '2026-01-01 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000d1f01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1a0', '00000000-0000-0000-0000-00000000cb01', 'Item B',    2000, 'EUR', '2026-01-01 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000c1001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000ca01', 'Cursor 1',  1000, 'USD', '2026-03-01 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000c2001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000ca01', 'Cursor 2',  1000, 'USD', '2026-03-02 00:00:00+00', null),
  ('00000000-0000-0000-0000-0000000c3001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1a0', '00000000-0000-0000-0000-00000000ca01', 'Cursor 3',  1000, 'USD', '2026-03-03 00:00:00+00', '2026-03-03 00:00:00+00');

set local role authenticated;

-- ===== contract / entities (3) =====
select is((app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) ->> 'ok')::boolean,
  true, 'sync_pull accepts a menu entity for a price-capable role (cashier)');
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['not_a_real_entity'],'{}'::jsonb,500) $$,
  '42501', NULL, 'sync_pull still rejects an unknown entity');
select is((app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['orders'],'{}'::jsonb,500) ->> 'ok')::boolean,
  true, 'existing operational entity (orders) still works');

-- ===== allowed roles can pull menu (Item A1a present) (5) =====
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5001','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1a01')::int,
  1, 'org_owner can pull menu');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5002','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1a01')::int,
  1, 'restaurant_owner can pull menu');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5003','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1a01')::int,
  1, 'manager can pull menu');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1a01')::int,
  1, 'cashier can pull menu');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5005','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1a01')::int,
  1, 'accountant can pull menu (price-capable read role per the existing sync allowlist)');

-- ===== branch/restaurant/org scope (cashier on Branch A1a) (4) =====
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1e01')::int,
  1, 'restaurant-scoped (branch null) item of the device restaurant IS pulled');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1b01')::int,
  0, 'a sibling-branch (A1b) item is NOT pulled');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d2e01')::int,
  0, 'a restaurant-scoped item of ANOTHER restaurant (A2) is NOT pulled');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1f01')::int,
  0, 'a cross-organization (Org B) item is NOT pulled');

-- ===== kitchen denial (3) =====
-- positive control: the kitchen PIN session itself is valid and CAN pull an allowed entity,
-- so the 42501 below is the role gate (menu not permitted), not a session/device failure.
select is((app.sync_pull('00000000-0000-0000-0000-0000000c5006','00000000-0000-0000-0000-00000000da1a',array['orders'],'{}'::jsonb,500) ->> 'ok')::boolean,
  true, 'kitchen_staff CAN pull an allowed operational entity (orders) -- session is valid');
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-0000000c5006','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) $$,
  '42501', NULL, 'kitchen_staff requesting a menu entity is denied (42501; menu carries money, T-003)');
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-0000000c5006','00000000-0000-0000-0000-00000000da1a',array['orders','menu_items'],'{}'::jsonb,500) $$,
  '42501', NULL, 'kitchen_staff mixed list (orders + menu_items) is denied safely (whole request fails)');

-- ===== tombstone + cursor (cashier) (5) =====
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000c3001' and (r->>'deleted_at') is not null)::int,
  1, 'a soft-deleted (tombstoned) menu item IS returned to an allowed role (deleted_at present)');
select is(jsonb_typeof(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'next_cursor'),
  'object', 'menu_items pull returns a next_cursor object');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{"menu_items":{"updated_at":"2026-03-02 00:00:00+00","id":"00000000-0000-0000-0000-0000000c2001"}}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000c3001')::int,
  1, 'cursor advance: a row with updated_at AFTER the cursor (Cursor 3) is included');
select is((select count(*) from jsonb_array_elements(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{"menu_items":{"updated_at":"2026-03-02 00:00:00+00","id":"00000000-0000-0000-0000-0000000c2001"}}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000c1001')::int,
  0, 'cursor advance: rows with updated_at BEFORE the cursor (Cursor 1) are excluded');
select is(jsonb_array_length(app.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{"menu_items":{"updated_at":"2026-03-03 00:00:00+00","id":"00000000-0000-0000-0000-0000000c3001"}}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows'),
  0, 'cursor past the last row returns zero menu rows');

-- ===== security / public wrapper (3) =====
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'sync_pull'), false,
  'public.sync_pull wrapper remains SECURITY INVOKER (signature/security preserved)');
select is((select count(*) from jsonb_array_elements(public.sync_pull('00000000-0000-0000-0000-0000000c5004','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) -> 'changes' -> 'menu_items' -> 'rows') r where r->>'id' = '00000000-0000-0000-0000-0000000d1a01')::int,
  1, 'public.sync_pull wrapper forwards verbatim and returns menu for an allowed role');
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-00000000dead','00000000-0000-0000-0000-00000000da1a',array['menu_items'],'{}'::jsonb,500) $$,
  '42501', NULL, 'a non-existent / non-member PIN session is denied (no tenant sync bypass)');

reset role;
select * from finish();
rollback;
