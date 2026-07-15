-- ============================================================================
-- RF-060 — CANONICAL mandatory security gate: cross-tenant isolation
-- ============================================================================
-- The named governance suite mapping to SECURITY_AND_THREAT_MODEL §14 / TESTING_STRATEGY
-- §2. This file: T-001 (cross-organization read isolation incl. IDOR-by-id), T-002
-- (cross-restaurant/branch write isolation — direct DML revoked + RPC scope rejection),
-- deny-by-default (no membership => zero rows), and the canonical idempotency/replay
-- (exactly-once) assertion. seed_isolation fixture: Org-A {R-A1/B-A1a, R-A2/B-A2a} and
-- Org-B {R-B1/B-B1a}. Fixtures inserted as the BYPASSRLS connection role; RLS assertions
-- run under `set local role authenticated` + the GUC principal; RPCs derive scope from
-- the PIN session and are invoked as the connection role (RF-052..062 pattern).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf060iso-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf060iso-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fb11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-00000000fb11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf060iso-cashier-a@example.test'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf060iso-cashier-b@example.test'),
  ('00000000-0000-0000-0000-00000000ee0c', 'rf060iso-nomember@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-00000000ab0b');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c50b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-00000000ab0b', now() + interval '1 hour');
-- one order per org (direct insert as the owner; each in its own branch)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a01a', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'oa1a-fixt'),
  ('00000000-0000-0000-0000-00000000b01a', '00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1d1','00000000-0000-0000-0000-00000000db11','00000000-0000-0000-0000-00000000c50b','00000000-0000-0000-0000-0000000ef00b','00000000-0000-0000-0000-00000000ab0b','dine_in','submitted','EUR',3000,3000,'ob1a-fixt');
-- live active dining table in Org A / Rest A1 / Branch A1a (RESTAURANT-OPERATIONS-V1-001:
-- dine_in submits now require a live, active same-scope table)
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-000000007ab1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF060 T1', true);
-- sellable menu fixture for the Org A submit_order payload (RESTAURANT-OPERATIONS-V1-001:
-- submit_order now refuses line items that are not proven-sellable menu items)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item', 1000, 'USD', 1);

-- ===== idempotency / replay (exactly-once) via submit_order ================== 1-3
select is((app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0e1','00000000-0000-0000-0000-00000000da11','op-rep','dine_in','00000000-0000-0000-0000-000000007ab1',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) ->> 'ok')::boolean, true,
  'first submit_order applies');
select is((app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0e1','00000000-0000-0000-0000-00000000da11','op-rep','dine_in','00000000-0000-0000-0000-000000007ab1',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null) ->> 'idempotency_replay')::boolean, true,
  'replay of the same (device_id, local_operation_id) returns idempotency_replay=true (exactly-once)');
select is((select count(*) from orders where local_operation_id='op-rep')::int, 1, 'the replay created exactly ONE order (no double effect)');

-- ===== T-002 (RPC scope): an Org A principal cannot mutate an Org B order ===== 4
select throws_ok(
  $$ select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000b01a','00000000-0000-0000-0000-00000000da11','op-x','x',null) $$,
  '42501', NULL, 'T-002: an Org A cashier cannot void an Org B order via RPC (scope derived from the session, not the payload)');

-- ===== T-001 cross-org read isolation + control (authenticated) ============== 5-7
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from orders where id = '00000000-0000-0000-0000-00000000b01a')::int, 0,
  'T-001: an Org A cashier cannot read an Org B order by id (IDOR blocked)');
select is((select count(*) from orders where organization_id = '00000000-0000-0000-0000-0000000000b0')::int, 0,
  'T-001: an Org A cashier sees ZERO Org B orders');
select ok((select count(*) from orders where id = '00000000-0000-0000-0000-00000000a01a') >= 1,
  'T-001 control: the Org A cashier CAN read its own-branch order (read policy not over-tight)');

-- ===== T-002 cross-tenant WRITE isolation (direct DML revoked) =============== 8-9
select throws_ok(
  $$ insert into restaurants (organization_id, name) values ('00000000-0000-0000-0000-0000000000b0', 'rogue') $$,
  '42501', NULL, 'T-002: cashier cannot INSERT a restaurant into Org B (direct writes revoked, RF-059)');
select throws_ok(
  $$ insert into branches (organization_id, restaurant_id, name) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2','rogue') $$,
  '42501', NULL, 'T-002: cashier cannot INSERT a branch under another restaurant (direct writes revoked)');

-- ===== deny-by-default: a principal with NO membership sees zero rows ======== 10-11
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0c';
select is((select count(*) from orders)::int,      0, 'deny-by-default: a no-membership principal sees zero orders');
select is((select count(*) from restaurants)::int, 0, 'deny-by-default: a no-membership principal sees zero restaurants');
reset role;

select * from finish();
rollback;
