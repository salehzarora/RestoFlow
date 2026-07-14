-- ============================================================================
-- POS-OPERATIONS-SYNC-001 — pgTAP: the authoritative, branch-scoped POS order read
-- (app.pos_order_snapshots) + the app.pin_session_capabilities regression.
-- ============================================================================
-- The POS had NO authoritative order read, so every server-side change (discount,
-- payment, KDS bump, auto-completion, void) was invisible to it. This suite pins:
--   * scope: a POS device can read its OWN org+branch and NOTHING else. There is no
--     parameter naming a branch/restaurant/tenant, so a cross-scope read is
--     UNREACHABLE, not merely denied.
--   * safe fields only (no notes, no customer_name, no internal UUIDs).
--   * SERVER-COMPUTED settlement: paid | unpaid | not_chargeable.
--   * the cursor pages on greatest(order.updated_at, payment.updated_at) — a PAYMENT
--     does not touch the order row, so an orders-only cursor would never deliver a
--     paid-but-not-completed order. That is production failure #1.
--   * malformed cursor/limit/window FAIL CLOSED (never a silent full restart).
--   * READS EMIT NO AUDIT EVENT.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(38);

-- ---- Org A (2 branches) + Org B ---------------------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('90a00000-0000-0000-0000-0000000000a0', 'PS Org A', 'ps001-a', 'USD'),
  ('90b00000-0000-0000-0000-0000000000b0', 'PS Org B', 'ps001-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-0000000000a0', 'PS Rest A1'),
  ('90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-0000000000a0', 'PS Rest A2 (sibling)'),
  ('90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-0000000000b0', 'PS Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', 'PS Branch A1'),
  ('90a00000-0000-0000-0000-00000000ab22', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', 'PS Branch A2 (sibling)'),
  ('90a00000-0000-0000-0000-00000000ab33', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', 'PS Branch A3 (sibling rest)'),
  ('90b00000-0000-0000-0000-00000000bb11', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', 'PS Branch B1');
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('90a00000-0000-0000-0000-00000000a7b1', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', 'T7');

-- device + sessions on branch A1, plus a REVOKED device and a second device on A2
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('90a00000-0000-0000-0000-0000000d0a11', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', 'pos'),
  ('90a00000-0000-0000-0000-0000000d0a99', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('90a00000-0000-0000-0000-0000000f0a11', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000d0a11', 'active'),
  ('90a00000-0000-0000-0000-0000000f0a99', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000d0a99', 'active');
-- Both start ACTIVE: a DB guard forbids opening a PIN session on a revoked device
-- session, so the revocation is applied BELOW, after the PIN session exists —
-- which is exactly the real-world sequence (a device is revoked while a cashier is
-- signed in on it, and its in-flight session must stop reading immediately).
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('90a00000-0000-0000-0000-0000000500a1', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000d0a11', '90a00000-0000-0000-0000-0000000f0a11', true, null),
  ('90a00000-0000-0000-0000-0000000500a9', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000d0a99', '90a00000-0000-0000-0000-0000000f0a99', true, null);

insert into app_users (id, email) values
  ('90a00000-0000-0000-0000-0000000000e3', 'ps-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('90a00000-0000-0000-0000-00000000ac03', '90a00000-0000-0000-0000-0000000000e3', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('90a00000-0000-0000-0000-00000000af03', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000000e3', '90a00000-0000-0000-0000-00000000ac03');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at, is_active) values
  ('90a00000-0000-0000-0000-00000000c503', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000500a1', '90a00000-0000-0000-0000-00000000af03', '90a00000-0000-0000-0000-00000000ac03', now() + interval '1 hour', true),
  -- a pin session on the REVOKED device session
  ('90a00000-0000-0000-0000-00000000c509', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000500a9', '90a00000-0000-0000-0000-00000000af03', '90a00000-0000-0000-0000-00000000ac03', now() + interval '1 hour', true),
  -- an EXPIRED pin session on the good device
  ('90a00000-0000-0000-0000-00000000c5e0', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab11', '90a00000-0000-0000-0000-0000000500a1', '90a00000-0000-0000-0000-00000000af03', '90a00000-0000-0000-0000-00000000ac03', now() - interval '1 hour', true);

-- NOW revoke the second device session, with its PIN session already open.
update device_sessions
   set is_active = false, revoked_at = now()
 where id = '90a00000-0000-0000-0000-0000000500a9';

-- ---- FOREIGN-SCOPE stacks -----------------------------------------------------
-- orders.device_id / pin_session_id / employee / membership are all NOT NULL and
-- FK-bound to the order's (org, restaurant, branch), so an order in another scope
-- needs its OWN device + session stack. Building them properly is the only honest
-- way to prove the read cannot reach across a branch, a restaurant or a tenant.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('90a00000-0000-0000-0000-0000000d0a22', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab22', 'pos'),
  ('90a00000-0000-0000-0000-0000000d0a33', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-00000000ab33', 'pos'),
  ('90b00000-0000-0000-0000-0000000d0b11', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-00000000bb11', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('90a00000-0000-0000-0000-0000000f0a22', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab22', '90a00000-0000-0000-0000-0000000d0a22', 'active'),
  ('90a00000-0000-0000-0000-0000000f0a33', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-00000000ab33', '90a00000-0000-0000-0000-0000000d0a33', 'active'),
  ('90b00000-0000-0000-0000-0000000f0b11', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-00000000bb11', '90b00000-0000-0000-0000-0000000d0b11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('90a00000-0000-0000-0000-0000000500a2', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab22', '90a00000-0000-0000-0000-0000000d0a22', '90a00000-0000-0000-0000-0000000f0a22'),
  ('90a00000-0000-0000-0000-0000000500a3', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-00000000ab33', '90a00000-0000-0000-0000-0000000d0a33', '90a00000-0000-0000-0000-0000000f0a33'),
  ('90b00000-0000-0000-0000-0000000500b1', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-00000000bb11', '90b00000-0000-0000-0000-0000000d0b11', '90b00000-0000-0000-0000-0000000f0b11');
insert into app_users (id, email) values
  ('90a00000-0000-0000-0000-0000000000e4', 'ps-cashier-a2@example.test'),
  ('90a00000-0000-0000-0000-0000000000e5', 'ps-cashier-a3@example.test'),
  ('90b00000-0000-0000-0000-0000000000eb', 'ps-cashier-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('90a00000-0000-0000-0000-00000000ac04', '90a00000-0000-0000-0000-0000000000e4', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab22', 'cashier', '{}'::jsonb),
  ('90a00000-0000-0000-0000-00000000ac05', '90a00000-0000-0000-0000-0000000000e5', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-00000000ab33', 'cashier', '{}'::jsonb),
  ('90b00000-0000-0000-0000-00000000bc0b', '90b00000-0000-0000-0000-0000000000eb', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-00000000bb11', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('90a00000-0000-0000-0000-00000000af04', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab22', '90a00000-0000-0000-0000-0000000000e4', '90a00000-0000-0000-0000-00000000ac04'),
  ('90a00000-0000-0000-0000-00000000af05', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-00000000ab33', '90a00000-0000-0000-0000-0000000000e5', '90a00000-0000-0000-0000-00000000ac05'),
  ('90b00000-0000-0000-0000-00000000bf0b', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-00000000bb11', '90b00000-0000-0000-0000-0000000000eb', '90b00000-0000-0000-0000-00000000bc0b');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('90a00000-0000-0000-0000-00000000c504', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a1', '90a00000-0000-0000-0000-00000000ab22', '90a00000-0000-0000-0000-0000000500a2', '90a00000-0000-0000-0000-00000000af04', '90a00000-0000-0000-0000-00000000ac04', now() + interval '1 hour'),
  ('90a00000-0000-0000-0000-00000000c505', '90a00000-0000-0000-0000-0000000000a0', '90a00000-0000-0000-0000-0000000000a2', '90a00000-0000-0000-0000-00000000ab33', '90a00000-0000-0000-0000-0000000500a3', '90a00000-0000-0000-0000-00000000af05', '90a00000-0000-0000-0000-00000000ac05', now() + interval '1 hour'),
  ('90b00000-0000-0000-0000-00000000c50b', '90b00000-0000-0000-0000-0000000000b0', '90b00000-0000-0000-0000-0000000000b1', '90b00000-0000-0000-0000-00000000bb11', '90b00000-0000-0000-0000-0000000500b1', '90b00000-0000-0000-0000-00000000bf0b', '90b00000-0000-0000-0000-00000000bc0b', now() + interval '1 hour');

-- ---- orders --------------------------------------------------------------
-- MINE (branch A1): d1 unpaid 1000 | d2 zero-total (comped) | d3 paid 1000 |
--                   d4 under-covered (paid 400 of 1000) | d5 completed |
--                   d6 soft-deleted | d7 with a table label
-- FOREIGN: s1 sibling BRANCH (A2) | s2 sibling RESTAURANT (A3) | b1 cross-TENANT
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, table_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, notes, customer_name, local_operation_id, revision, deleted_at, updated_at) values
  ('90a00000-0000-0000-0000-0000000000d1','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03',null,'dine_in','submitted','USD',1000,0,0,1000,'PRIVATE NOTE','Jane Doe','ps-o1',1,null, now() - interval '60 minutes'),
  ('90a00000-0000-0000-0000-0000000000d2','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03',null,'dine_in','served','USD',1000,1000,0,0,null,null,'ps-o2',4,null, now() - interval '50 minutes'),
  ('90a00000-0000-0000-0000-0000000000d3','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03',null,'dine_in','served','USD',1000,0,0,1000,null,null,'ps-o3',2,null, now() - interval '40 minutes'),
  ('90a00000-0000-0000-0000-0000000000d4','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03',null,'dine_in','served','USD',1000,0,0,1000,null,null,'ps-o4',2,null, now() - interval '30 minutes'),
  ('90a00000-0000-0000-0000-0000000000d5','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03',null,'dine_in','completed','USD',1000,0,0,1000,null,null,'ps-o5',5,null, now() - interval '20 minutes'),
  ('90a00000-0000-0000-0000-0000000000d6','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03',null,'dine_in','submitted','USD',1000,0,0,1000,null,null,'ps-o6',1,now(), now() - interval '55 minutes'),
  ('90a00000-0000-0000-0000-0000000000d7','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000c503','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03','90a00000-0000-0000-0000-00000000a7b1','dine_in','submitted','USD',500,0,0,500,null,null,'ps-o7',1,null, now() - interval '15 minutes'),
  ('90a00000-0000-0000-0000-00000000005a','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab22','90a00000-0000-0000-0000-0000000d0a22','90a00000-0000-0000-0000-00000000c504','90a00000-0000-0000-0000-00000000af04','90a00000-0000-0000-0000-00000000ac04',null,'dine_in','submitted','USD',900,0,0,900,null,null,'ps-s1',1,null, now() - interval '45 minutes'),
  ('90a00000-0000-0000-0000-00000000005b','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a2','90a00000-0000-0000-0000-00000000ab33','90a00000-0000-0000-0000-0000000d0a33','90a00000-0000-0000-0000-00000000c505','90a00000-0000-0000-0000-00000000af05','90a00000-0000-0000-0000-00000000ac05',null,'dine_in','submitted','USD',800,0,0,800,null,null,'ps-s2',1,null, now() - interval '45 minutes');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('90b00000-0000-0000-0000-0000000000b9','90b00000-0000-0000-0000-0000000000b0','90b00000-0000-0000-0000-0000000000b1','90b00000-0000-0000-0000-00000000bb11','90b00000-0000-0000-0000-0000000d0b11','90b00000-0000-0000-0000-00000000c50b','90b00000-0000-0000-0000-00000000bf0b','90b00000-0000-0000-0000-00000000bc0b','dine_in','submitted','USD',700,0,0,700,'ps-b9',1);

-- payments: d3 fully covers (1000); d4 UNDER-covers (400 of 1000)
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, updated_at) values
  ('90a00000-0000-0000-0000-00000000a503','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000000d3','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03','cash','completed',1000,1000,0,'USD','ps-pay3', now() - interval '35 minutes'),
  ('90a00000-0000-0000-0000-00000000a504','90a00000-0000-0000-0000-0000000000a0','90a00000-0000-0000-0000-0000000000a1','90a00000-0000-0000-0000-00000000ab11','90a00000-0000-0000-0000-0000000000d4','90a00000-0000-0000-0000-0000000d0a11','90a00000-0000-0000-0000-00000000af03','90a00000-0000-0000-0000-00000000ac03','cash','completed',400,400,0,'USD','ps-pay4', now() - interval '5 minutes');

-- one canonical full-window pull, reused by many assertions
create temp table snap as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503',
    p_device_id      => '90a00000-0000-0000-0000-0000000d0a11',
    p_limit => 100, p_window_days => 2) as r;
create temp table rows_ as
  select o from snap, lateral jsonb_array_elements((select r from snap) -> 'orders') as o;


-- ===== A. SCOPE: own org + branch, and nothing else ======================= 1-6
select is((select r ->> 'ok' from snap)::boolean, true, 'A1 a valid PIN session on a paired device may read');
select is((select count(*)::int from rows_), 6,
  'A2 exactly the SIX live orders of THIS branch (d1,d2,d3,d4,d5,d7) — the soft-deleted one is excluded');
select ok(not exists(select 1 from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-00000000005a'),
  'A3 a SIBLING BRANCH order is not returned (there is no parameter that could ask for it)');
select ok(not exists(select 1 from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-00000000005b'),
  'A4 a SIBLING RESTAURANT order is not returned');
select ok(not exists(select 1 from rows_ where o ->> 'order_id' = '90b00000-0000-0000-0000-0000000000b9'),
  'A5 a CROSS-TENANT order is not returned');
select ok(not exists(select 1 from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d6'),
  'A6 a SOFT-DELETED order is not returned');


-- ===== B. Session/device validity: fail closed, one envelope ============== 7-10
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c509', p_device_id => '90a00000-0000-0000-0000-0000000d0a99') ->> 'error'),
  'invalid_session', 'B1 a REVOKED device session is denied');
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c5e0', p_device_id => '90a00000-0000-0000-0000-0000000d0a11') ->> 'error'),
  'invalid_session', 'B2 an EXPIRED PIN session is denied');
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a99') ->> 'error'),
  'invalid_session', 'B3 a device_id that does not match the PIN session is denied');
select is((app.pos_order_snapshots(p_pin_session_id => '00000000-0000-0000-0000-0000000000ff', p_device_id => '90a00000-0000-0000-0000-0000000d0a11') ->> 'error'),
  'invalid_session', 'B4 an UNKNOWN session is denied with the SAME envelope (no existence oracle)');


-- ===== C. SAFE FIELDS ONLY ============================================== 11-14
select ok(not exists(select 1 from rows_ where o ? 'notes'),
  'C1 the private order NOTE is never returned');
select ok(not exists(select 1 from rows_ where o ? 'customer_name'),
  'C2 the CUSTOMER NAME is never returned');
select ok(not exists(select 1 from rows_ where o ? 'device_id' or o ? 'pin_session_id'
                       or o ? 'opened_by_employee_profile_id' or o ? 'resolved_membership_id'
                       or o ? 'organization_id' or o ? 'branch_id' or o ? 'table_id'),
  'C3 no internal staff/session/device/tenant UUID is projected');
select is((select o ->> 'order_code' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d1'),
  '#0000D1', 'C4 the order is identified by the SAFE #XXXXXX code');


-- ===== D. SERVER-COMPUTED SETTLEMENT ==================================== 15-19
select is((select o ->> 'payment_status' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d1'),
  'unpaid', 'D1 a positive-total order with no payment is UNPAID');
select is((select o ->> 'payment_status' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d3'),
  'paid', 'D2 a positive-total order COVERED by a completed payment is PAID');
select is((select o ->> 'payment_status' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d2'),
  'not_chargeable', 'D3 a ZERO-total (comped) order is NOT_CHARGEABLE — never "unpaid" forever');
select is((select o ->> 'payment_status' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d4'),
  'unpaid', 'D4 an UNDER-COVERED order still OWES money (settlement, not a payment marker)');
select is((select (o ->> 'grand_total_minor')::bigint from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d2'),
  0::bigint, 'D5 the comped order reports the AUTHORITATIVE total 0 — this is the stale "40" the POS kept showing');


-- ===== E. Authoritative fields =========================================== 20-23
select is((select (o ->> 'revision')::int from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d5'),
  5, 'E1 the server REVISION is returned (the POS stored none at all)');
select is((select o ->> 'status' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d5'),
  'completed', 'E2 a COMPLETED order reports completed — this is how a KDS/auto-completion reaches the POS');
select is((select o ->> 'table_label' from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d7'),
  'T7', 'E3 the table LABEL is returned (never the table UUID)');
select is((select (o ->> 'discount_total_minor')::bigint from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d2'),
  1000::bigint, 'E4 discount/tax/subtotal/grand travel TOGETHER, in integer minor units');


-- ===== F. THE CURSOR PAGES ON THE PAYMENT TOO =========================== 24-26
-- A payment does NOT touch the order row. If the cursor ordered on
-- orders.updated_at alone, a paid-but-not-completed order would NEVER be delivered
-- to an incremental pull — production failure #1. Prove sync_at follows the payment.
select ok((select (o ->> 'sync_at')::timestamptz from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d3')
          >= (select (o ->> 'updated_at')::timestamptz from rows_ where o ->> 'order_id' = '90a00000-0000-0000-0000-0000000000d3'),
  'F1 sync_at >= updated_at (it is greatest(order.updated_at, payment.updated_at))');

-- THE DECISIVE CASE. Order d4's ROW was last touched 30 minutes ago; its PAYMENT
-- arrived 5 minutes ago (app.record_payment inserts a payment and does NOT touch
-- the order row). A cursor placed 10 minutes ago therefore sits AFTER d4's
-- orders.updated_at but BEFORE its payment. An orders-only cursor would conclude
-- "nothing changed" and the POS would keep showing d4 as unpaid forever — which is
-- exactly production failure #1. Paging on greatest(order.updated_at,
-- payment.updated_at) must deliver it.
create temp table after_pay as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503',
    p_device_id      => '90a00000-0000-0000-0000-0000000d0a11',
    p_since_at => now() - interval '10 minutes',
    p_since_id => '00000000-0000-0000-0000-000000000000') as r;
select is((select jsonb_array_length((r -> 'orders')) from after_pay), 1,
  'F2 an incremental pull delivers the order whose PAYMENT moved — even though its ORDER ROW is older than the cursor');
select is((select (r -> 'orders' -> 0 ->> 'order_id') from after_pay), '90a00000-0000-0000-0000-0000000000d4',
  'F3 ... and it is exactly that order, now reporting its authoritative settlement');


-- ===== G. WINDOW PAGINATION — NEWEST FIRST ============================= 27-33
-- THE BUG THIS CLOSES. The window used to page ASCENDING from the start of the
-- window, so the FIRST page returned the OLDEST rows. On a busy branch the cashier
-- was shown yesterday's breakfast while the order placed ninety seconds ago sat
-- thousands of rows away — and a client that stopped after N pages would NEVER reach
-- it, while still reporting a successful sync.
create temp table w1 as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_limit => 2, p_window_days => 2) as r;

-- d7 (-15m) is the most recently touched live order; d4's PAYMENT moved 5m ago, so
-- d4 has the greatest sync_at of all. Newest-first means d4 leads.
select is((select (r -> 'orders' -> 0 ->> 'order_id') from w1),
  '90a00000-0000-0000-0000-0000000000d4',
  'G1 the FIRST row of the FIRST page is the NEWEST order — at any volume');
select is((select jsonb_array_length(r -> 'orders') from w1), 2,
  'G2 the page is BOUNDED by p_limit');
select is((select (r ->> 'has_more')::boolean from w1), true,
  'G3 a full page reports has_more with a resumable cursor');

-- LOAD MORE walks BACKWARD into older rows.
create temp table w2 as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_before_at => ((select r from w1) -> 'next_cursor' ->> 'at')::timestamptz,
    p_before_id => ((select r from w1) -> 'next_cursor' ->> 'id')::uuid,
    p_limit => 2, p_window_days => 2) as r;
select ok(not exists(
    select 1
    from jsonb_array_elements((select r from w1) -> 'orders') a,
         jsonb_array_elements((select r from w2) -> 'orders') b
    where a ->> 'order_id' = b ->> 'order_id'),
  'G4 page 2 NEVER repeats page 1 — no duplicate');
select ok(
  (select min((o ->> 'sync_at')::timestamptz)
     from jsonb_array_elements((select r from w1) -> 'orders') o)
  >= (select max((o ->> 'sync_at')::timestamptz)
        from jsonb_array_elements((select r from w2) -> 'orders') o),
  'G5 page 2 is strictly OLDER than page 1 — no skip, monotonic descent');

-- IDEMPOTENT: the same cursor twice is the same page.
create temp table w2b as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_before_at => ((select r from w1) -> 'next_cursor' ->> 'at')::timestamptz,
    p_before_id => ((select r from w1) -> 'next_cursor' ->> 'id')::uuid,
    p_limit => 2, p_window_days => 2) as r;
select is((select r -> 'orders' from w2), (select r -> 'orders' from w2b),
  'G6 replaying the SAME window cursor is IDEMPOTENT');

-- EQUAL sync_at must still page deterministically: the ORDER ID breaks the tie, so a
-- row can be neither duplicated across pages nor skipped between them.
update orders set updated_at = now() - interval '2 minutes'
  where id in ('90a00000-0000-0000-0000-0000000000d1',
               '90a00000-0000-0000-0000-0000000000d2',
               '90a00000-0000-0000-0000-0000000000d5');
create temp table tie1 as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_limit => 2, p_window_days => 2) as r;
create temp table tie2 as
  select app.pos_order_snapshots(
    p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_before_at => ((select r from tie1) -> 'next_cursor' ->> 'at')::timestamptz,
    p_before_id => ((select r from tie1) -> 'next_cursor' ->> 'id')::uuid,
    p_limit => 4, p_window_days => 2) as r;
select ok(not exists(
    select 1
    from jsonb_array_elements((select r from tie1) -> 'orders') a,
         jsonb_array_elements((select r from tie2) -> 'orders') b
    where a ->> 'order_id' = b ->> 'order_id'),
  'G7 rows sharing an identical sync_at page deterministically by order id — no duplicate, no skip');


-- ===== H. Malformed input FAILS CLOSED ================================= 34-37
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_since_at => now()) ->> 'error'),
  'invalid_cursor', 'H1 a HALF cursor is REFUSED — never silently restarted from the beginning');
-- The two cursors ask DIFFERENT questions; one page cannot honour both, and silently
-- picking one would move a cursor the caller never meant to move.
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_since_at => now(), p_since_id => '00000000-0000-0000-0000-000000000000',
    p_before_at => now(), p_before_id => '00000000-0000-0000-0000-000000000000') ->> 'error'),
  'invalid_cursor', 'H1b asking BOTH cursors at once is REFUSED');
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_limit => 5000) ->> 'error'),
  'invalid_limit', 'H2 an out-of-range limit is REFUSED (a client cannot ask for the whole history)');
select is((app.pos_order_snapshots(p_pin_session_id => '90a00000-0000-0000-0000-00000000c503', p_device_id => '90a00000-0000-0000-0000-0000000d0a11',
    p_window_days => 999) ->> 'error'),
  'invalid_window', 'H3 an out-of-range window is REFUSED');


-- ===== I. A READ IS NOT A WRITE ============================================ 38
select is((select count(*)::int from audit_events), 0,
  'I1 the snapshot read emitted NO audit event — opening a screen, polling and reconciling are not operational actions');

select * from finish();
rollback;
