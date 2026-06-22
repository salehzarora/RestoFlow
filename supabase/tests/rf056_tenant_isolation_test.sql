-- ============================================================================
-- RF-056 — pgTAP: tenant isolation (RISK R-003)
-- ============================================================================
-- Scope is derived server-side from the session/device, never the payload, so a
-- push can only affect the caller's org/branch. The same local_operation_id used by
-- a device in org A and a device in org B yields two SEPARATE ledger rows (the
-- identity is org-scoped) with no cross-org leak; RLS confines SELECT to the active
-- org. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(5);

-- ---- Org A ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf056t-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf056t-a@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab0a', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef00a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab0a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c50a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef00a', '00000000-0000-0000-0000-00000000ab0a', now() + interval '1 hour');
-- ---- Org B ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf056t-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fb11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-00000000fb11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0b', 'rf056t-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-00000000ab0b');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c50b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-00000000ab0b', now() + interval '1 hour');

-- the SAME local_operation_id ('op-1') pushed by org A and org B ------------- 1-2
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c50a','00000000-0000-0000-0000-00000000da11',
    '[{"local_operation_id":"op-1","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000da","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'org A push of op-1 applies');
select is(
  (app.sync_push('00000000-0000-0000-0000-00000000c50b','00000000-0000-0000-0000-00000000db11',
    '[{"local_operation_id":"op-1","operation_type":"order.submit","payload":{"order_id":"00000000-0000-0000-0000-0000000000db","order_type":"dine_in","currency_code":"USD","order_items":[{"menu_item_id":"00000000-0000-0000-0000-0000000000f2","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}],"subtotal_minor":1000,"discount_total_minor":0,"tax_total_minor":0,"grand_total_minor":1000}}]'::jsonb)
   -> 'results' -> 0 ->> 'status'), 'applied', 'org B push of the SAME op-1 applies independently (org-scoped identity)');

-- two separate ledger rows, two separate orgs -- no cross-org leak/replay ---- 3-4
select is((select count(*) from sync_operations where local_operation_id='op-1')::int, 2, 'op-1 yields two separate ledger rows (one per org/device)');
select is((select count(distinct organization_id) from sync_operations where local_operation_id='op-1')::int, 2, 'the two op-1 rows belong to two different organizations');

-- RLS: as an org A principal, only org A''s ledger row is visible ------------- 5
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0a';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from sync_operations where local_operation_id='op-1')::int, 1, 'RLS confines an org A principal to only org A''s ledger row');
reset role;

select * from finish();
rollback;
