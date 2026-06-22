-- ============================================================================
-- RF-059 — pgTAP: cross-tenant + cross-branch read isolation (T-001/T-002, R-003)
-- ============================================================================
-- Across two orgs (each with an order + a payment) and two branches in Org A:
--   * an Org A branch-scoped cashier sees ONLY its branch's order/payment — never
--     Org B's (cross-org) and never the sibling branch's (cross-branch);
--   * an Org A org_owner sees ALL Org A orders but no Org B order;
--   * selecting a NON-member org (forged GUC) yields zero rows — app.current_org_id()
--     validates membership and never returns an arbitrary org.
-- Fixtures (incl. orders/payments) inserted as the BYPASSRLS connection role;
-- assertions run under `set local role authenticated`.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(12);

-- ---- Org A: two branches (a1b1, a1b2), one order + payment each-branch order ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf059xt-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf059xt-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', 'pos'),
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da12', 'active'),
  ('00000000-0000-0000-0000-00000000fb11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12'),
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-00000000fb11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf059xt-cashier-a1b1@example.test'),
  ('00000000-0000-0000-0000-00000000ee05', 'rf059xt-cashier-a1b2@example.test'),
  ('00000000-0000-0000-0000-0000000000e9', 'rf059xt-owner-a@example.test'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf059xt-cashier-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab05', '00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', 'cashier'),
  ('00000000-0000-0000-0000-0000000000c9', '00000000-0000-0000-0000-0000000000e9', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-00000000ab05'),
  ('00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-00000000ab0b');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c5a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab05', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c50b', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000ef00b', '00000000-0000-0000-0000-00000000ab0b', now() + interval '1 hour');
-- one order per Org A branch + one Org B order
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,1000,'oa1'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b2','00000000-0000-0000-0000-00000000da12','00000000-0000-0000-0000-00000000c5a2','00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-00000000ab05','dine_in','submitted','USD',2000,2000,'oa2'),
  ('00000000-0000-0000-0000-00000000b0d1', '00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1d1','00000000-0000-0000-0000-00000000db11','00000000-0000-0000-0000-00000000c50b','00000000-0000-0000-0000-0000000ef00b','00000000-0000-0000-0000-00000000ab0b','dine_in','submitted','EUR',3000,3000,'ob1');
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0000000a0fa1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','cash','completed',1000,1000,0,'USD','pa1'),
  ('00000000-0000-0000-0000-0000000b0fb1', '00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1d1','00000000-0000-0000-0000-00000000b0d1','00000000-0000-0000-0000-00000000db11','00000000-0000-0000-0000-0000000ef00b','00000000-0000-0000-0000-00000000ab0b','cash','completed',3000,3000,0,'EUR','pb1');

set local role authenticated;

-- ===== Org A branch-a1b1 cashier: own branch only ============================ 1-5
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from orders)::int,   1, 'cashier @ A1b1: sees only its branch order (1)');
select is((select count(*) from payments)::int, 1, 'cashier @ A1b1: sees only its branch payment (1)');
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000a0d2')::int, 0, 'cashier @ A1b1: CANNOT see the sibling-branch (A1b2) order (cross-branch)');
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000b0d1')::int, 0, 'cashier @ A1b1: CANNOT see the Org B order (cross-org, T-001)');
select is((select count(*) from payments where id='00000000-0000-0000-0000-0000000b0fb1')::int, 0, 'cashier @ A1b1: CANNOT see the Org B payment (cross-org)');

-- ===== Org A branch-a1b2 cashier: the other branch only ====================== 6-7
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee05';
select is((select count(*) from orders)::int, 1, 'cashier @ A1b2: sees only its branch order (1)');
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000a0d1')::int, 0, 'cashier @ A1b2: CANNOT see the sibling-branch (A1b1) order');

-- ===== Org A org_owner: all of Org A, none of Org B ========================== 8-9
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e9';
select is((select count(*) from orders)::int, 2, 'org_owner @ Org A: sees BOTH Org A orders');
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000b0d1')::int, 0, 'org_owner @ Org A: still CANNOT see the Org B order');

-- ===== Org B cashier: symmetric ============================================== 10
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0b';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from orders where id='00000000-0000-0000-0000-00000000a0d1')::int, 0, 'cashier @ Org B: CANNOT see an Org A order (symmetric isolation)');

-- ===== forged GUC: select a NON-member org => zero rows ====================== 11-12
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';   -- Org A member only
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';  -- assert membership in Org B
select is(app.current_org_id(), null, 'forged GUC: selecting a non-member org resolves current_org_id() to NULL (never an arbitrary org)');
select is((select count(*) from orders)::int, 0, 'forged GUC: a non-member org selection yields zero rows (no cross-tenant escape)');

select * from finish();
rollback;
