-- ============================================================================
-- STAFF-CASHIER-PERMISSIONS-001 — pgTAP: default-on cashier capabilities with
-- explicit deny overrides (resolver + discount/void/close_shift enforcement +
-- set_staff_capabilities + list_staff).
-- ============================================================================
-- The three cashier capabilities (apply_discount, void_order, close_shift) are
-- ALLOWED by default and denied only by an explicit permissions->>key='false'
-- override. PAID-order void stays blocked; managers/owners keep their role grants;
-- kitchen/other roles are unaffected. Deny overrides are set via the owner/manager
-- set_staff_capabilities RPC (tenant+branch+role-rank scoped, audited). Fixtures
-- inserted as the BYPASSRLS connection role; PIN-driven RPCs read the actor from
-- the session, management RPCs from app.current_app_user_id() (GUC test path).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(46);

-- ---- Org A + Org B tenants ------------------------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('caa00000-0000-0000-0000-0000000000a0', 'Org A', 'scp001-a', 'USD'),
  ('cbb00000-0000-0000-0000-0000000000b0', 'Org B', 'scp001-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('cbb00000-0000-0000-0000-00000000b1b1', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'Branch B1');
-- two Org-A devices: da = order actions, db = shift actions
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('caa00000-0000-0000-0000-0000000d0a11', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'pos'),
  ('caa00000-0000-0000-0000-0000000d0b22', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'pos'),
  ('cbb00000-0000-0000-0000-0000000d0b11', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-00000000b1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('caa00000-0000-0000-0000-0000000f0a11', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000d0a11', 'active'),
  ('caa00000-0000-0000-0000-0000000f0b22', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000d0b22', 'active'),
  ('cbb00000-0000-0000-0000-0000000f0b11', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-00000000b1b1', 'cbb00000-0000-0000-0000-0000000d0b11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('caa00000-0000-0000-0000-0000000500a1', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000d0a11', 'caa00000-0000-0000-0000-0000000f0a11'),
  ('caa00000-0000-0000-0000-0000000500b2', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000d0b22', 'caa00000-0000-0000-0000-0000000f0b22'),
  ('cbb00000-0000-0000-0000-0000000500b1', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-00000000b1b1', 'cbb00000-0000-0000-0000-0000000d0b11', 'cbb00000-0000-0000-0000-0000000f0b11');

-- ---- operators: owner, manager, default cashier, deny cashier, kitchen (Org A);
--      cashier (Org B) ------------------------------------------------------
insert into app_users (id, email) values
  ('caa00000-0000-0000-0000-000000000e01', 'scp-owner@example.test'),
  ('caa00000-0000-0000-0000-000000000e02', 'scp-mgr@example.test'),
  ('caa00000-0000-0000-0000-000000000e03', 'scp-cashier-default@example.test'),
  ('caa00000-0000-0000-0000-000000000e04', 'scp-cashier-deny@example.test'),
  ('caa00000-0000-0000-0000-000000000e05', 'scp-kitchen@example.test'),
  ('cbb00000-0000-0000-0000-000000000e0b', 'scp-cashier-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('caa00000-0000-0000-0000-000000000a01', 'caa00000-0000-0000-0000-000000000e01', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'org_owner', '{}'::jsonb),
  ('caa00000-0000-0000-0000-000000000a02', 'caa00000-0000-0000-0000-000000000e02', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'manager', '{}'::jsonb),
  ('caa00000-0000-0000-0000-000000000a03', 'caa00000-0000-0000-0000-000000000e03', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'cashier', '{}'::jsonb),
  ('caa00000-0000-0000-0000-000000000a04', 'caa00000-0000-0000-0000-000000000e04', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'cashier', '{"apply_discount":"false","void_order":"false","close_shift":"false"}'::jsonb),
  ('caa00000-0000-0000-0000-000000000a05', 'caa00000-0000-0000-0000-000000000e05', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'kitchen_staff', '{}'::jsonb),
  ('cbb00000-0000-0000-0000-000000000b0b', 'cbb00000-0000-0000-0000-000000000e0b', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-00000000b1b1', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('caa00000-0000-0000-0000-000000000f01', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-000000000e01', 'caa00000-0000-0000-0000-000000000a01'),
  ('caa00000-0000-0000-0000-000000000f02', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-000000000e02', 'caa00000-0000-0000-0000-000000000a02'),
  ('caa00000-0000-0000-0000-000000000f03', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-000000000e03', 'caa00000-0000-0000-0000-000000000a03'),
  ('caa00000-0000-0000-0000-000000000f04', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-000000000e04', 'caa00000-0000-0000-0000-000000000a04'),
  ('caa00000-0000-0000-0000-000000000f05', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-000000000e05', 'caa00000-0000-0000-0000-000000000a05'),
  ('cbb00000-0000-0000-0000-000000000f0b', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-00000000b1b1', 'cbb00000-0000-0000-0000-000000000e0b', 'cbb00000-0000-0000-0000-000000000b0b');
-- PIN sessions: default cashier + manager on BOTH da (orders) and db (shift);
-- deny cashier on da (orders) + db (shift); kitchen on da; Org B cashier on B.
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('caa00000-0000-0000-0000-00000000c503', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000500a1', 'caa00000-0000-0000-0000-000000000f03', 'caa00000-0000-0000-0000-000000000a03', now() + interval '1 hour'),
  ('caa00000-0000-0000-0000-00000000c504', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000500a1', 'caa00000-0000-0000-0000-000000000f04', 'caa00000-0000-0000-0000-000000000a04', now() + interval '1 hour'),
  ('caa00000-0000-0000-0000-00000000c505', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000500a1', 'caa00000-0000-0000-0000-000000000f05', 'caa00000-0000-0000-0000-000000000a05', now() + interval '1 hour'),
  ('caa00000-0000-0000-0000-00000000d503', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000500b2', 'caa00000-0000-0000-0000-000000000f03', 'caa00000-0000-0000-0000-000000000a03', now() + interval '1 hour'),
  ('caa00000-0000-0000-0000-00000000d504', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000500b2', 'caa00000-0000-0000-0000-000000000f04', 'caa00000-0000-0000-0000-000000000a04', now() + interval '1 hour'),
  ('caa00000-0000-0000-0000-00000000d502', 'caa00000-0000-0000-0000-0000000000a0', 'caa00000-0000-0000-0000-0000000000a1', 'caa00000-0000-0000-0000-0000000000b1', 'caa00000-0000-0000-0000-0000000500b2', 'caa00000-0000-0000-0000-000000000f02', 'caa00000-0000-0000-0000-000000000a02', now() + interval '1 hour'),
  ('cbb00000-0000-0000-0000-00000000c50b', 'cbb00000-0000-0000-0000-0000000000b0', 'cbb00000-0000-0000-0000-0000000000b1', 'cbb00000-0000-0000-0000-00000000b1b1', 'cbb00000-0000-0000-0000-0000000500b1', 'cbb00000-0000-0000-0000-000000000f0b', 'cbb00000-0000-0000-0000-000000000b0b', now() + interval '1 hour');

-- submitted orders (direct insert) for discount/void; a paid order for the block.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('caa00000-0000-0000-0000-00000000a0d1', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-000000000f03','caa00000-0000-0000-0000-000000000a03','dine_in','submitted','USD',1000,0,0,1000,'o1'),
  ('caa00000-0000-0000-0000-00000000a0d2', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c504','caa00000-0000-0000-0000-000000000f04','caa00000-0000-0000-0000-000000000a04','dine_in','submitted','USD',1000,0,0,1000,'o2'),
  ('caa00000-0000-0000-0000-00000000a0d3', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-000000000f03','caa00000-0000-0000-0000-000000000a03','dine_in','submitted','USD',1000,0,0,1000,'o3'),
  ('caa00000-0000-0000-0000-00000000a0d4', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c504','caa00000-0000-0000-0000-000000000f04','caa00000-0000-0000-0000-000000000a04','dine_in','submitted','USD',1000,0,0,1000,'o4'),
  ('caa00000-0000-0000-0000-00000000a0d5', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-000000000f03','caa00000-0000-0000-0000-000000000a03','dine_in','submitted','USD',1000,0,0,1000,'o5'),
  ('caa00000-0000-0000-0000-00000000a0d6', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-000000000f03','caa00000-0000-0000-0000-000000000a03','dine_in','submitted','USD',1000,0,0,1000,'o6'),
  ('caa00000-0000-0000-0000-00000000a0d8', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-000000000f03','caa00000-0000-0000-0000-000000000a03','dine_in','submitted','USD',1000,0,0,1000,'o8');
-- a live COMPLETED payment on o5 (direct insert; the paid-void guard reads this).
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('caa00000-0000-0000-0000-00000000a505', 'caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','caa00000-0000-0000-0000-00000000a0d5','caa00000-0000-0000-0000-0000000d0a11','caa00000-0000-0000-0000-000000000f03','caa00000-0000-0000-0000-000000000a03','cash','completed',1000,1000,0,'USD','pay-o5');

-- ===== 1. Effective resolver (app.cashier_capability_allowed) =============== 1-9
select ok(app.cashier_capability_allowed('cashier', '{}'::jsonb, 'apply_discount'), 'default cashier: apply_discount allowed');
select ok(app.cashier_capability_allowed('cashier', '{}'::jsonb, 'void_order'),     'default cashier: void_order allowed');
select ok(app.cashier_capability_allowed('cashier', '{}'::jsonb, 'close_shift'),     'default cashier: close_shift allowed');
select ok(not app.cashier_capability_allowed('cashier', '{"apply_discount":"false"}'::jsonb, 'apply_discount'), 'explicit deny: apply_discount=false denies');
select ok(not app.cashier_capability_allowed('cashier', '{"void_order":"false"}'::jsonb, 'void_order'),         'explicit deny: void_order=false denies');
select ok(not app.cashier_capability_allowed('cashier', '{"close_shift":"false"}'::jsonb, 'close_shift'),       'explicit deny: close_shift=false denies');
select ok(not app.cashier_capability_allowed('cashier', '{"void_order":"true"}'::jsonb, 'void_order'), 'fail-closed: a PRESENT non-canonical value ("true") denies (deny-only storage never writes "true")');
select ok(not app.cashier_capability_allowed('manager', '{}'::jsonb, 'void_order'), 'non-cashier (manager): resolver returns false (never widens another role)');
select ok(not app.cashier_capability_allowed('cashier', '{"apply_discount":"true"}'::jsonb, 'refund'), 'missing/unrelated capability key is NOT granted (no universal allow)');

-- ===== 2. Discount enforcement ============================================= 10-11
select is((app.apply_discount('caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-00000000a0d1','caa00000-0000-0000-0000-0000000d0a11','op-d1','order',null,'fixed',200,'promo',null) ->> 'ok')::boolean,
  true, 'a DEFAULT cashier (no override) may apply a discount');
select is((app.apply_discount('caa00000-0000-0000-0000-00000000c504','caa00000-0000-0000-0000-00000000a0d2','caa00000-0000-0000-0000-0000000d0a11','op-d2','order',null,'fixed',200,'promo',null) ->> 'error'),
  'permission_denied', 'a cashier with apply_discount=false is denied');

-- ===== 3. Void enforcement ================================================= 12-15
select is((app.void_order('caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-00000000a0d3','caa00000-0000-0000-0000-0000000d0a11','op-v1','wrong',null) ->> 'ok')::boolean,
  true, 'a DEFAULT cashier (no override) may void an eligible UNPAID order');
select is((app.void_order('caa00000-0000-0000-0000-00000000c504','caa00000-0000-0000-0000-00000000a0d4','caa00000-0000-0000-0000-0000000d0a11','op-v2','wrong',null) ->> 'error'),
  'permission_denied', 'a cashier with void_order=false is denied');
select is((app.void_order('caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-00000000a0d5','caa00000-0000-0000-0000-0000000d0a11','op-v3','wrong',null) ->> 'detail'),
  'order_has_completed_payment', 'a DEFAULT cashier voiding a PAID order is STILL blocked (paid void deferred)');
select is((select status from orders where id='caa00000-0000-0000-0000-00000000a0d5')::text, 'submitted',
  'the paid order is UNCHANGED after the blocked void');

-- ===== 4. Non-cashier roles unchanged ====================================== 16-17
-- manager (session on db, but any Org-A device works for its own order) voids o6
select is((app.void_order('caa00000-0000-0000-0000-00000000d502','caa00000-0000-0000-0000-00000000a0d6','caa00000-0000-0000-0000-0000000d0b22','op-v6','mgr void',null) ->> 'ok')::boolean,
  true, 'a manager may still void by role (non-cashier behavior unchanged)');
select is((app.void_order('caa00000-0000-0000-0000-00000000c505','caa00000-0000-0000-0000-00000000a0d8','caa00000-0000-0000-0000-0000000d0a11','op-vk','kitchen',null) ->> 'error'),
  'permission_denied', 'kitchen_staff is still denied (non-cashier behavior unchanged)');

-- ===== 5. Cross-tenant rejected ============================================ 18
select throws_ok(
  $$ select app.void_order('cbb00000-0000-0000-0000-00000000c50b','caa00000-0000-0000-0000-00000000a0d8','cbb00000-0000-0000-0000-0000000d0b11','op-xt','cross',null) $$,
  '42501', NULL, 'an Org B cashier cannot void an Org A order (cross-tenant rejected)');

-- ===== 6. Shift close: own / deny / other-person =========================== 19-21
-- default cashier opens + closes their OWN shift on db (allowed); manager frees it.
select app.open_shift('caa00000-0000-0000-0000-00000000d503','caa00000-0000-0000-0000-0000000501f1','caa00000-0000-0000-0000-000000050cd1','caa00000-0000-0000-0000-0000000d0b22','op-osd',0);
select is((app.close_shift('caa00000-0000-0000-0000-00000000d503','caa00000-0000-0000-0000-0000000501f1','caa00000-0000-0000-0000-0000000d0b22','op-csd',0,null) ->> 'ok')::boolean,
  true, 'a DEFAULT cashier may close their OWN shift');
select app.reconcile_shift('caa00000-0000-0000-0000-00000000d502','caa00000-0000-0000-0000-0000000501f1','caa00000-0000-0000-0000-0000000d0b22','op-rsd',null);
-- deny cashier opens a shift (open is by role, unaffected) then is denied the close.
select app.open_shift('caa00000-0000-0000-0000-00000000d504','caa00000-0000-0000-0000-0000000501f2','caa00000-0000-0000-0000-000000050cd2','caa00000-0000-0000-0000-0000000d0b22','op-ose',0);
select is((app.close_shift('caa00000-0000-0000-0000-00000000d504','caa00000-0000-0000-0000-0000000501f2','caa00000-0000-0000-0000-0000000d0b22','op-cse',0,null) ->> 'error'),
  'permission_denied', 'a cashier with close_shift=false is denied closing their own shift');
-- a DEFAULT (close-capable) cashier still cannot close ANOTHER cashier's shift.
select is((app.close_shift('caa00000-0000-0000-0000-00000000d503','caa00000-0000-0000-0000-0000000501f2','caa00000-0000-0000-0000-0000000d0b22','op-csx',0,null) ->> 'error'),
  'permission_denied', 'a cashier cannot close ANOTHER person''s shift (ownership preserved)');

-- ===== 7. set_staff_capabilities (owner/manager write path) ================ 22-29
-- owner disables the default cashier's void_order.
set local app.current_app_user_id = 'caa00000-0000-0000-0000-000000000e01';
select is((public.set_staff_capabilities('caa00000-0000-0000-0000-00000000c1d1','caa00000-0000-0000-0000-000000000f03', true, false, true) ->> 'ok')::boolean,
  true, 'owner may disable a cashier''s void capability via the public wrapper');
select is((select permissions ->> 'void_order' from memberships where id='caa00000-0000-0000-0000-000000000a03'), 'false',
  'the deny override is persisted (permissions.void_order = false)');
-- end-to-end: the now-denied cashier is rejected by void_order.
select is((app.void_order('caa00000-0000-0000-0000-00000000c503','caa00000-0000-0000-0000-00000000a0d8','caa00000-0000-0000-0000-0000000d0a11','op-v8','wrong',null) ->> 'error'),
  'permission_denied', 'after the deny override, the cashier''s void is rejected (backend-enforced)');
-- re-enabling removes the key (deny-only storage -> back to the role default ON).
select is((app.set_staff_capabilities('caa00000-0000-0000-0000-00000000c1d2','caa00000-0000-0000-0000-000000000f03', true, true, true) ->> 'ok')::boolean,
  true, 'owner may re-enable the capability');
select ok((select not (permissions ? 'void_order') from memberships where id='caa00000-0000-0000-0000-000000000a03'),
  're-enabling REMOVES the deny key (back to default ON)');
-- a non-cashier target is refused.
select throws_ok(
  $$ select app.set_staff_capabilities('caa00000-0000-0000-0000-00000000c1d3','caa00000-0000-0000-0000-000000000f05', true, false, true) $$,
  '42501', NULL, 'setting capabilities on a non-cashier (kitchen) is refused');
-- a cashier actor (rank 1) cannot set capabilities.
set local app.current_app_user_id = 'caa00000-0000-0000-0000-000000000e03';
select is((app.set_staff_capabilities('caa00000-0000-0000-0000-00000000c1d4','caa00000-0000-0000-0000-000000000f04', true, false, true) ->> 'error'),
  'permission_denied', 'a cashier cannot set another cashier''s capabilities (rank guard)');
-- cross-tenant: an Org B actor cannot edit an Org A cashier.
set local app.current_app_user_id = 'cbb00000-0000-0000-0000-000000000e0b';
select throws_ok(
  $$ select app.set_staff_capabilities('caa00000-0000-0000-0000-00000000c1d5','caa00000-0000-0000-0000-000000000f03', true, false, true) $$,
  '42501', NULL, 'an Org B actor cannot edit an Org A cashier''s capabilities (cross-tenant, no oracle)');

-- ===== 8. audit + list_staff output ======================================== 30-31
select ok(exists(select 1 from audit_events where action='staff.capabilities_updated'),
  'a staff.capabilities_updated audit row was written');
-- list_staff returns each cashier's effective capabilities.
set local app.current_app_user_id = 'caa00000-0000-0000-0000-000000000e01';
select is(
  (select (s ->> 'capabilities')::jsonb ->> 'void_order'
     from jsonb_array_elements(app.list_staff('caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1') -> 'staff') s
    where s ->> 'employee_profile_id' = 'caa00000-0000-0000-0000-000000000f04'),
  'false', 'list_staff reports the deny-cashier''s void_order capability as false');

-- ===== 9. ATOMIC cashier creation with initial deny overrides ============== 32-43
-- Owner is the creating actor (GUC); target is Org A branch b1.
set local app.current_app_user_id = 'caa00000-0000-0000-0000-000000000e01';

-- helper: the permissions jsonb of the membership behind a display_name.
create or replace function pg_temp.perms_of(p_name text) returns jsonb language sql as $$
  select m.permissions from public.memberships m
    join public.employee_profiles ep on ep.membership_id = m.id
   where ep.display_name = p_name limit 1;
$$;
create or replace function pg_temp.count_of(p_name text) returns integer language sql as $$
  select count(*)::int from public.employee_profiles where display_name = p_name;
$$;

-- (32) all-default cashier => created, NO deny keys stored.
select is((public.create_staff_member('caa00000-0000-0000-0000-0000000000c1','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Default','cashier') ->> 'ok')::boolean,
  true, 'creating an all-default cashier succeeds');
select is(pg_temp.perms_of('ATOM Default'), '{}'::jsonb, 'an all-default cashier stores NO deny keys (permissions = {})');

-- (33-35) one switch OFF => exactly that one deny key stored (atomically).
select is((app.create_staff_member('caa00000-0000-0000-0000-0000000000c2','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM DiscOff','cashier','{"apply_discount":"false"}'::jsonb) ->> 'ok')::boolean, true, 'create with apply_discount OFF succeeds');
select is(pg_temp.perms_of('ATOM DiscOff'), '{"apply_discount":"false"}'::jsonb, 'apply_discount OFF stores ONLY apply_discount=false');
select app.create_staff_member('caa00000-0000-0000-0000-0000000000c3','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM VoidOff','cashier','{"void_order":"false"}'::jsonb);
select is(pg_temp.perms_of('ATOM VoidOff'), '{"void_order":"false"}'::jsonb, 'void_order OFF stores ONLY void_order=false');
select app.create_staff_member('caa00000-0000-0000-0000-0000000000c4','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM ShiftOff','cashier','{"close_shift":"false"}'::jsonb);
select is(pg_temp.perms_of('ATOM ShiftOff'), '{"close_shift":"false"}'::jsonb, 'close_shift OFF stores ONLY close_shift=false');

-- (36) multiple OFF => all selected denies stored in ONE transaction.
select app.create_staff_member('caa00000-0000-0000-0000-0000000000c5','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Multi','cashier','{"apply_discount":"false","close_shift":"false"}'::jsonb);
select is(pg_temp.perms_of('ATOM Multi'), '{"apply_discount":"false","close_shift":"false"}'::jsonb, 'multiple OFF stores all selected denies atomically (void_order left ON)');

-- (37) malformed key => rejected AND nothing created (fail-closed rollback).
select throws_ok($$ select app.create_staff_member('caa00000-0000-0000-0000-0000000000c6','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM BadKey','cashier','{"refund":"false"}'::jsonb) $$, '42501', NULL, 'an unknown capability key is rejected (42501)');
select is(pg_temp.count_of('ATOM BadKey'), 0, 'the rejected create left NO staff row (atomic rollback)');

-- (38) malformed value (not deny-only) => rejected AND nothing created.
select throws_ok($$ select app.create_staff_member('caa00000-0000-0000-0000-0000000000c7','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM BadVal','cashier','{"void_order":"true"}'::jsonb) $$, '42501', NULL, 'a non-deny capability value is rejected (deny-only, 42501)');

-- (39) non-cashier + capabilities => rejected AND nothing created.
select throws_ok($$ select app.create_staff_member('caa00000-0000-0000-0000-0000000000c8','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Kitchen','kitchen_staff','{"void_order":"false"}'::jsonb) $$, '42501', NULL, 'capabilities on a non-cashier role are rejected (42501)');

-- (40) insufficient rank (a cashier actor) => permission_denied, no staff created.
set local app.current_app_user_id = 'caa00000-0000-0000-0000-000000000e03';
select is((app.create_staff_member('caa00000-0000-0000-0000-0000000000c9','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Rank','cashier','{"void_order":"false"}'::jsonb) ->> 'error'),
  'permission_denied', 'an insufficient-rank actor (cashier) cannot create staff');

-- (41) cross-tenant actor => rejected (42501, no covering membership).
set local app.current_app_user_id = 'cbb00000-0000-0000-0000-000000000e0b';
select throws_ok($$ select app.create_staff_member('caa00000-0000-0000-0000-0000000000ca','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Cross','cashier','{"void_order":"false"}'::jsonb) $$, '42501', NULL, 'a cross-tenant actor cannot create Org A staff');

-- (42) idempotent retry (SAME client_request_id) => ONE staff member.
set local app.current_app_user_id = 'caa00000-0000-0000-0000-000000000e01';
select app.create_staff_member('caa00000-0000-0000-0000-0000000000cb','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Retry','cashier','{"void_order":"false"}'::jsonb);
select app.create_staff_member('caa00000-0000-0000-0000-0000000000cb','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM Retry','cashier','{"void_order":"false"}'::jsonb);
select is(pg_temp.count_of('ATOM Retry'), 1, 'a retried create (same client_request_id) does NOT create a duplicate (idempotent)');

-- (43) backward compatibility: a 6-arg call (no capabilities) => default behavior.
select app.create_staff_member('caa00000-0000-0000-0000-0000000000cc','caa00000-0000-0000-0000-0000000000a0','caa00000-0000-0000-0000-0000000000a1','caa00000-0000-0000-0000-0000000000b1','ATOM SixArg','cashier');
select is(pg_temp.perms_of('ATOM SixArg'), '{}'::jsonb, 'a 6-arg caller (no capabilities) keeps current behavior (permissions = {})');

select * from finish();
rollback;
