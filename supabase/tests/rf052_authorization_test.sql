-- ============================================================================
-- RF-052 — pgTAP: authorization (AC#2)
-- ============================================================================
-- submit_order authorizes the caller via the PIN session BEFORE writing:
--   * a valid cashier on a paired+active device succeeds;
--   * a kitchen_staff/accountant role is rejected (not a submit role);
--   * an expired PIN session is rejected;
--   * a revoked membership is rejected;
--   * a device_id not matching the PIN session's device is rejected.
-- Actor + org/restaurant/branch are derived from the PIN session, never from the
-- client, so a cross-tenant submit is structurally impossible. 42501 on denial.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

-- ---- base tenant + device + active device session --------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf052z-a', 'USD');
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

-- ---- four employees/memberships: cashier (valid), kitchen_staff, revoked, + an expired-session cashier
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'rf052z-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf052z-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000ee0c', 'rf052z-revoked@example.test'),
  ('00000000-0000-0000-0000-00000000ee0d', 'rf052z-accountant@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier',       'active'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff', 'active'),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee0c', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier',       'revoked'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee0d', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'accountant',    'active');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef0a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef0b0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-00000000ab02'),
  ('00000000-0000-0000-0000-0000000ef0c0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0c', '00000000-0000-0000-0000-00000000ab03'),
  ('00000000-0000-0000-0000-0000000ef0d0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0d', '00000000-0000-0000-0000-00000000ab04');
-- pin sessions: valid cashier, valid kitchen_staff, valid revoked-membership, expired cashier, valid accountant
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c5a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0a0', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0b0', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0c0', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5a4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0a0', '00000000-0000-0000-0000-00000000ab01', now() - interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5a5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0d0', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- a live, active dining table in the SAME org/restaurant/branch as the PIN
-- session (RESTAURANT-OPERATIONS-V1-001: dine_in submits now REQUIRE one)
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e'::uuid, '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'T1', true);

-- a minimal valid 1-line payload (qty 1 @ 1000; subtotal/grand 1000)
-- ===== valid cashier succeeds =============================================== 1
select ok(
  (app.submit_order('00000000-0000-0000-0000-00000000c5a1','00000000-0000-0000-0000-00000000a0d1',
    '00000000-0000-0000-0000-00000000da11','op-ok','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    1000,0,0,1000,null) ->> 'order_id') is not null,
  'valid cashier on a paired+active device submits an order');

-- ===== kitchen_staff role is rejected ======================================= 2
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c5a2','00000000-0000-0000-0000-00000000a0d2',
    '00000000-0000-0000-0000-00000000da11','op-ks','dine_in',null,null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    1000,0,0,1000,null) $$, '42501', NULL,
  'kitchen_staff may NOT submit orders (role rejected)');

-- ===== revoked membership is rejected ======================================= 3
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c5a3','00000000-0000-0000-0000-00000000a0d3',
    '00000000-0000-0000-0000-00000000da11','op-rev','dine_in',null,null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    1000,0,0,1000,null) $$, '42501', NULL,
  'a revoked membership may NOT submit orders');

-- ===== expired PIN session is rejected ====================================== 4
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c5a4','00000000-0000-0000-0000-00000000a0d4',
    '00000000-0000-0000-0000-00000000da11','op-exp','dine_in',null,null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    1000,0,0,1000,null) $$, '42501', NULL,
  'an expired PIN session may NOT submit orders');

-- ===== device_id not matching the PIN session's device is rejected ========== 5
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c5a1','00000000-0000-0000-0000-00000000a0d5',
    '00000000-0000-0000-0000-0000000000ff','op-dev','dine_in',null,null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    1000,0,0,1000,null) $$, '42501', NULL,
  'a device_id not matching the PIN session device is rejected (no acting on a foreign device)');

-- ===== accountant role is rejected (read-only back-office; not a submit role) = 6
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c5a5','00000000-0000-0000-0000-00000000a0d6',
    '00000000-0000-0000-0000-00000000da11','op-acc','dine_in',null,null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    1000,0,0,1000,null) $$, '42501', NULL,
  'an accountant may NOT submit orders (role rejected; allowlist excludes accountant)');

select * from finish();
rollback;
