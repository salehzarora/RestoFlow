-- ============================================================================
-- FULL-COMP-PERMISSION-001 — pgTAP: a SEPARATE staff permission for making an
-- order FREE (grant-only resolver + resulting-total gate + write RPCs + audit).
-- ============================================================================
-- "Apply a discount" and "make the order free" are now TWO capabilities.
--   apply_discount   — ordinary discounts.  Cashier default ON  (deny-only).
--   apply_full_comp  — make the order FREE. Cashier default OFF (grant-only).
--
-- A FULL COMP is DEFINED as a mutation whose RESULTING AUTHORITATIVE
-- grand_total_minor is EXACTLY 0 — never inferred from a "100%" UI choice. The
-- suite therefore proves the rule holds for PERCENTAGE and FIXED alike, that a
-- TAXED order zeroed to grand = tax is NOT a comp, and that zeroing ONE line of a
-- multi-line order is NOT a comp.
--
-- Fixtures inserted as the BYPASSRLS connection role; PIN-driven RPCs read the
-- actor from the pin session, management RPCs from app.current_app_user_id().
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(48);

-- ---- tenants: Org A (2 restaurants) + Org B ---------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('fca00000-0000-0000-0000-0000000000a0', 'FC Org A', 'fc001-a', 'USD'),
  ('fcb00000-0000-0000-0000-0000000000b0', 'FC Org B', 'fc001-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-0000000000a0', 'FC Rest A1'),
  ('fca00000-0000-0000-0000-0000000000a2', 'fca00000-0000-0000-0000-0000000000a0', 'FC Rest A2 (sibling)'),
  ('fcb00000-0000-0000-0000-0000000000b1', 'fcb00000-0000-0000-0000-0000000000b0', 'FC Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'FC Branch A1'),
  ('fca00000-0000-0000-0000-00000000ab22', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a2', 'FC Branch A2'),
  ('fcb00000-0000-0000-0000-00000000bb11', 'fcb00000-0000-0000-0000-0000000000b0', 'fcb00000-0000-0000-0000-0000000000b1', 'FC Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('fca00000-0000-0000-0000-0000000d0a11', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('fca00000-0000-0000-0000-0000000f0a11', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000d0a11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000d0a11', 'fca00000-0000-0000-0000-0000000f0a11');

-- ---- actors -----------------------------------------------------------------
-- e01 org_owner | e02 manager | e03 cashier PLAIN (discount ON, NO comp)
-- e04 cashier COMP (comp GRANTED) | e05 cashier comp-granted but DISCOUNT DENIED
-- e06 restaurant_owner | e07 sibling-restaurant manager | e0b Org-B org_owner
insert into app_users (id, email) values
  ('fca00000-0000-0000-0000-0000000000e1', 'fc-owner@example.test'),
  ('fca00000-0000-0000-0000-0000000000e2', 'fc-mgr@example.test'),
  ('fca00000-0000-0000-0000-0000000000e3', 'fc-cashier-plain@example.test'),
  ('fca00000-0000-0000-0000-0000000000e4', 'fc-cashier-comp@example.test'),
  ('fca00000-0000-0000-0000-0000000000e5', 'fc-cashier-nodisc@example.test'),
  ('fca00000-0000-0000-0000-0000000000e6', 'fc-restowner@example.test'),
  ('fca00000-0000-0000-0000-0000000000e7', 'fc-sibling-mgr@example.test'),
  ('fcb00000-0000-0000-0000-0000000000eb', 'fc-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('fca00000-0000-0000-0000-00000000ac01', 'fca00000-0000-0000-0000-0000000000e1', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'org_owner', '{}'::jsonb),
  ('fca00000-0000-0000-0000-00000000ac02', 'fca00000-0000-0000-0000-0000000000e2', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'manager', '{}'::jsonb),
  ('fca00000-0000-0000-0000-00000000ac03', 'fca00000-0000-0000-0000-0000000000e3', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'cashier', '{}'::jsonb),
  ('fca00000-0000-0000-0000-00000000ac04', 'fca00000-0000-0000-0000-0000000000e4', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'cashier', '{"apply_full_comp":"true"}'::jsonb),
  ('fca00000-0000-0000-0000-00000000ac05', 'fca00000-0000-0000-0000-0000000000e5', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'cashier', '{"apply_discount":"false","apply_full_comp":"true"}'::jsonb),
  ('fca00000-0000-0000-0000-00000000ac06', 'fca00000-0000-0000-0000-0000000000e6', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'restaurant_owner', '{}'::jsonb),
  ('fca00000-0000-0000-0000-00000000ac07', 'fca00000-0000-0000-0000-0000000000e7', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a2', 'fca00000-0000-0000-0000-00000000ab22', 'manager', '{}'::jsonb),
  ('fcb00000-0000-0000-0000-00000000bc0b', 'fcb00000-0000-0000-0000-0000000000eb', 'fcb00000-0000-0000-0000-0000000000b0', 'fcb00000-0000-0000-0000-0000000000b1', 'fcb00000-0000-0000-0000-00000000bb11', 'org_owner', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('fca00000-0000-0000-0000-00000000af01', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000e1', 'fca00000-0000-0000-0000-00000000ac01'),
  ('fca00000-0000-0000-0000-00000000af02', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000e2', 'fca00000-0000-0000-0000-00000000ac02'),
  ('fca00000-0000-0000-0000-00000000af03', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000e3', 'fca00000-0000-0000-0000-00000000ac03'),
  ('fca00000-0000-0000-0000-00000000af04', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000e4', 'fca00000-0000-0000-0000-00000000ac04'),
  ('fca00000-0000-0000-0000-00000000af05', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000e5', 'fca00000-0000-0000-0000-00000000ac05'),
  ('fca00000-0000-0000-0000-00000000af06', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000000e6', 'fca00000-0000-0000-0000-00000000ac06'),
  ('fca00000-0000-0000-0000-00000000af07', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a2', 'fca00000-0000-0000-0000-00000000ab22', 'fca00000-0000-0000-0000-0000000000e7', 'fca00000-0000-0000-0000-00000000ac07');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('fca00000-0000-0000-0000-00000000c501', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-00000000af01', 'fca00000-0000-0000-0000-00000000ac01', now() + interval '1 hour'),
  ('fca00000-0000-0000-0000-00000000c502', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-00000000af02', 'fca00000-0000-0000-0000-00000000ac02', now() + interval '1 hour'),
  ('fca00000-0000-0000-0000-00000000c503', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-00000000af03', 'fca00000-0000-0000-0000-00000000ac03', now() + interval '1 hour'),
  ('fca00000-0000-0000-0000-00000000c504', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-00000000af04', 'fca00000-0000-0000-0000-00000000ac04', now() + interval '1 hour'),
  ('fca00000-0000-0000-0000-00000000c505', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-00000000af05', 'fca00000-0000-0000-0000-00000000ac05', now() + interval '1 hour'),
  ('fca00000-0000-0000-0000-00000000c506', 'fca00000-0000-0000-0000-0000000000a0', 'fca00000-0000-0000-0000-0000000000a1', 'fca00000-0000-0000-0000-00000000ab11', 'fca00000-0000-0000-0000-0000000500a1', 'fca00000-0000-0000-0000-00000000af06', 'fca00000-0000-0000-0000-00000000ac06', now() + interval '1 hour');

-- ---- orders: all subtotal 1000, tax 0 unless stated -------------------------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('fca00000-0000-0000-0000-0000000000d1','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-00000000af03','fca00000-0000-0000-0000-00000000ac03','dine_in','submitted','USD',1000,0,0,1000,'fc-o1'),
  ('fca00000-0000-0000-0000-0000000000d2','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-00000000af04','fca00000-0000-0000-0000-00000000ac04','dine_in','submitted','USD',1000,0,0,1000,'fc-o2'),
  ('fca00000-0000-0000-0000-0000000000d3','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-00000000af03','fca00000-0000-0000-0000-00000000ac03','dine_in','submitted','USD',1000,0,0,1000,'fc-o3'),
  ('fca00000-0000-0000-0000-0000000000d4','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-00000000af04','fca00000-0000-0000-0000-00000000ac04','dine_in','submitted','USD',1000,0,0,1000,'fc-o4'),
  ('fca00000-0000-0000-0000-0000000000d5','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-00000000af03','fca00000-0000-0000-0000-00000000ac03','dine_in','submitted','USD',1000,0,0,1000,'fc-o5'),
  ('fca00000-0000-0000-0000-0000000000d6','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c501','fca00000-0000-0000-0000-00000000af01','fca00000-0000-0000-0000-00000000ac01','dine_in','submitted','USD',1000,0,0,1000,'fc-o6'),
  ('fca00000-0000-0000-0000-0000000000d7','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c506','fca00000-0000-0000-0000-00000000af06','fca00000-0000-0000-0000-00000000ac06','dine_in','submitted','USD',1000,0,0,1000,'fc-o7'),
  ('fca00000-0000-0000-0000-0000000000d8','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c502','fca00000-0000-0000-0000-00000000af02','fca00000-0000-0000-0000-00000000ac02','dine_in','submitted','USD',1000,0,0,1000,'fc-o8'),
  ('fca00000-0000-0000-0000-0000000000d9','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c505','fca00000-0000-0000-0000-00000000af05','fca00000-0000-0000-0000-00000000ac05','dine_in','submitted','USD',1000,0,0,1000,'fc-o9'),
  -- TAXED order: subtotal 1000 + tax 100 => grand 1100. Zeroing the SUBTOTAL is NOT a comp.
  ('fca00000-0000-0000-0000-000000000d10','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-00000000af03','fca00000-0000-0000-0000-00000000ac03','dine_in','submitted','USD',1000,0,100,1100,'fc-o10'),
  -- PAID order (freeze regression) and a TERMINAL order (guard regression)
  ('fca00000-0000-0000-0000-000000000d11','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-00000000af04','fca00000-0000-0000-0000-00000000ac04','dine_in','submitted','USD',1000,0,0,1000,'fc-o11'),
  ('fca00000-0000-0000-0000-000000000d12','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-00000000af04','fca00000-0000-0000-0000-00000000ac04','dine_in','completed','USD',1000,0,0,1000,'fc-o12'),
  -- TWO-LINE order (600 + 400). Zeroing ONE line leaves the ORDER owing money.
  ('fca00000-0000-0000-0000-000000000d13','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-00000000af03','fca00000-0000-0000-0000-00000000ac03','dine_in','submitted','USD',1000,0,0,1000,'fc-o13'),
  -- SINGLE-LINE order: zeroing that line DOES make the ORDER free => a comp.
  ('fca00000-0000-0000-0000-000000000d14','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-00000000af03','fca00000-0000-0000-0000-00000000ac03','dine_in','submitted','USD',1000,0,0,1000,'fc-o14'),
  -- NEGATIVE case: a pre-existing ORDER-level discount of 900 on a 1000 subtotal
  -- (grand 100). Zeroing the only line would drive subtotal to 0 => grand = -900.
  ('fca00000-0000-0000-0000-000000000d15','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-00000000af04','fca00000-0000-0000-0000-00000000ac04','dine_in','submitted','USD',1000,900,0,100,'fc-o15');

insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('fca00000-0000-0000-0000-00000000e131','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-000000000d13','fca00000-0000-0000-0000-0000000000f1',1,'Line A',600,600),
  ('fca00000-0000-0000-0000-00000000e132','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-000000000d13','fca00000-0000-0000-0000-0000000000f1',1,'Line B',400,400),
  ('fca00000-0000-0000-0000-00000000e141','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-000000000d14','fca00000-0000-0000-0000-0000000000f1',1,'Only line',1000,1000),
  ('fca00000-0000-0000-0000-00000000e151','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-000000000d15','fca00000-0000-0000-0000-0000000000f1',1,'Only line',1000,1000);

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('fca00000-0000-0000-0000-00000000a511','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','fca00000-0000-0000-0000-000000000d11','fca00000-0000-0000-0000-0000000d0a11','fca00000-0000-0000-0000-00000000af04','fca00000-0000-0000-0000-00000000ac04','cash','completed',1000,1000,0,'USD','fc-pay-o11');


-- ===== A. The GRANT-ONLY resolver is FAIL-CLOSED ========================== 1-6
-- ABSENCE must be a hard FALSE, never SQL NULL: `jsonb -> missing_key` is NULL and
-- `NULL = '"true"'` is NULL, which would make `not v_may_comp` NULL and the caller's
-- gate NEVER FIRE — a fail-OPEN on the one permission that gives food away.
select is(app.cashier_capability_granted('cashier', '{}'::jsonb, 'apply_full_comp'), false,
  'A1 ABSENT key => hard FALSE (not NULL): the default-OFF cashier is denied');
select ok(app.cashier_capability_granted('cashier', '{"apply_full_comp":"true"}'::jsonb, 'apply_full_comp'),
  'A2 the canonical JSON string "true" GRANTS');
select is(app.cashier_capability_granted('cashier', '{"apply_full_comp":true}'::jsonb, 'apply_full_comp'), false,
  'A3 a JSON BOOLEAN true DENIES (malformed can never manufacture a grant)');
select is(app.cashier_capability_granted('cashier', '{"apply_full_comp":"false"}'::jsonb, 'apply_full_comp'), false,
  'A4 the string "false" DENIES');
select is(app.cashier_capability_granted('cashier', 'null'::jsonb, 'apply_full_comp'), false,
  'A5 JSON-null permissions DENIES (fail-closed)');
select is(app.cashier_capability_granted('manager', '{"apply_full_comp":"true"}'::jsonb, 'apply_full_comp'), false,
  'A6 a NON-cashier role always resolves false (the resolver never widens another role)');


-- ===== B. Role defaults may make an order free ============================ 7-9
create temp table t_owner as select app.apply_discount('fca00000-0000-0000-0000-00000000c501','fca00000-0000-0000-0000-0000000000d6','fca00000-0000-0000-0000-0000000d0a11','fc-owner','order',null,'percentage',10000,'comp',null) as r;
select is((select r ->> 'ok' from t_owner)::boolean, true, 'B1 an ORG OWNER may make an order free');
create temp table t_rowner as select app.apply_discount('fca00000-0000-0000-0000-00000000c506','fca00000-0000-0000-0000-0000000000d7','fca00000-0000-0000-0000-0000000d0a11','fc-rowner','order',null,'percentage',10000,'comp',null) as r;
select is((select r ->> 'ok' from t_rowner)::boolean, true, 'B2 a RESTAURANT OWNER may make an order free');
create temp table t_mgr as select app.apply_discount('fca00000-0000-0000-0000-00000000c502','fca00000-0000-0000-0000-0000000000d8','fca00000-0000-0000-0000-0000000d0a11','fc-mgr','order',null,'percentage',10000,'comp',null) as r;
select is((select r ->> 'ok' from t_mgr)::boolean, true, 'B3 a MANAGER may make an order free');


-- ===== C. Cashier: the two permissions are SEPARATE ===================== 10-17
create temp table t_c1 as select app.apply_discount('fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-0000000000d1','fca00000-0000-0000-0000-0000000d0a11','fc-c1','order',null,'percentage',10000,'comp',null) as r;
select is((select r ->> 'error' from t_c1), 'permission_denied',
  'C1 a cashier with ONLY the ordinary discount permission CANNOT make an order free');
select is((select r ->> 'detail' from t_c1), 'full_comp_permission_required',
  'C2 the refusal carries the STABLE domain detail (it survives sync_push because it is RETURNED, not raised)');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-0000000000d1'), 1000::bigint,
  'C3 the refused order is COMPLETELY UNCHANGED (no write, no clamp)');

create temp table t_c2 as select app.apply_discount('fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-0000000000d2','fca00000-0000-0000-0000-0000000d0a11','fc-c2','order',null,'percentage',10000,'comp',null) as r;
select is((select r ->> 'ok' from t_c2)::boolean, true,
  'C4 a cashier with BOTH permissions MAY make an order free');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-0000000000d2'), 0::bigint,
  'C5 ... and the resulting authoritative total is EXACTLY 0');

-- full comp must NEVER bypass the ordinary discount permission
create temp table t_c3 as select app.apply_discount('fca00000-0000-0000-0000-00000000c505','fca00000-0000-0000-0000-0000000000d9','fca00000-0000-0000-0000-0000000d0a11','fc-c3','order',null,'percentage',10000,'comp',null) as r;
select is((select r ->> 'error' from t_c3), 'permission_denied',
  'C6 a cashier with full-comp STORED but ordinary discount DISABLED is refused (no bypass)');
select isnt((select r ->> 'detail' from t_c3), 'full_comp_permission_required',
  'C7 ... and is refused by the ORDINARY discount gate (which runs FIRST), not the comp gate');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-0000000000d9'), 1000::bigint,
  'C8 ... leaving the order untouched — revoking apply_discount makes a stored grant INERT');


-- ===== D. FIXED and PERCENTAGE are gated identically ==================== 18-21
create temp table t_fix1 as select app.apply_discount('fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-0000000000d3','fca00000-0000-0000-0000-0000000d0a11','fc-fx1','order',null,'fixed',1000,'comp by fixed',null) as r;
select is((select r ->> 'detail' from t_fix1), 'full_comp_permission_required',
  'D1 a FIXED discount covering the whole order needs full-comp too (never inferred from "100%")');
create temp table t_fix2 as select app.apply_discount('fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-0000000000d4','fca00000-0000-0000-0000-0000000d0a11','fc-fx2','order',null,'fixed',1000,'comp by fixed',null) as r;
select is((select r ->> 'ok' from t_fix2)::boolean, true, 'D2 a granted cashier may comp via a FIXED discount');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-0000000000d4'), 0::bigint, 'D3 ... resulting in exactly 0');
-- a PARTIAL discount leaving the order owing money needs only the ordinary permission
create temp table t_part as select app.apply_discount('fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-0000000000d5','fca00000-0000-0000-0000-0000000d0a11','fc-part','order',null,'fixed',400,'partial',null) as r;
select is((select r ->> 'ok' from t_part)::boolean, true,
  'D4 a cashier WITHOUT full-comp may still apply a partial discount that leaves the total ABOVE zero');


-- ===== E. The gate is the RESULTING TOTAL, not the base ================= 22-23
-- A TAXED order zeroed at the SUBTOTAL still owes the tax — so it is NOT a comp.
create temp table t_tax as select app.apply_discount('fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-000000000d10','fca00000-0000-0000-0000-0000000d0a11','fc-tax','order',null,'percentage',10000,'subtotal to zero',null) as r;
select is((select r ->> 'ok' from t_tax)::boolean, true,
  'E1 a 100% discount on a TAXED order is NOT a comp (grand = tax > 0): the ordinary permission suffices');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-000000000d10'), 100::bigint,
  'E2 ... and the order still owes exactly the tax');


-- ===== F. Item scope: the ORDER total decides, and no negative ========== 24-29
-- zeroing ONE line of a TWO-line order leaves the ORDER owing money => NOT a comp
create temp table t_i1 as select app.apply_discount('fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-000000000d13','fca00000-0000-0000-0000-0000000d0a11','fc-i1','order_item','fca00000-0000-0000-0000-00000000e132','percentage',10000,'zero one line',null) as r;
select is((select r ->> 'ok' from t_i1)::boolean, true,
  'F1 zeroing ONE line of a MULTI-line order is an ORDINARY discount (the order is not free)');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-000000000d13'), 600::bigint,
  'F2 ... and the order still owes the other line');

-- zeroing the ONLY line DOES make the order free => a comp
create temp table t_i2 as select app.apply_discount('fca00000-0000-0000-0000-00000000c503','fca00000-0000-0000-0000-000000000d14','fca00000-0000-0000-0000-0000000d0a11','fc-i2','order_item','fca00000-0000-0000-0000-00000000e141','percentage',10000,'zero only line',null) as r;
select is((select r ->> 'detail' from t_i2), 'full_comp_permission_required',
  'F3 zeroing the ONLY line makes the ORDER free => the comp permission is required');
select is((select grand_total_minor from orders where id='fca00000-0000-0000-0000-000000000d14'), 1000::bigint,
  'F4 ... and the refused order is unchanged — the item write is HOISTED BELOW the gate, so no partial write leaks');
select is((select line_total_minor from order_items where id='fca00000-0000-0000-0000-00000000e141'), 1000::bigint,
  'F5 ... including the LINE itself (the old code wrote the line BEFORE it could refuse)');

-- a NEGATIVE prospective total is REFUSED, never floored to 0 (which would have
-- manufactured a FREE order that no gate saw). Actor holds full-comp, so this
-- proves the negative guard is not merely the comp gate in disguise.
create temp table t_neg as select app.apply_discount('fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-000000000d15','fca00000-0000-0000-0000-0000000d0a11','fc-neg','order_item','fca00000-0000-0000-0000-00000000e151','percentage',10000,'drive negative',null) as r;
select is((select r ->> 'detail' from t_neg), 'discount_exceeds_order_total',
  'F6 a NEGATIVE prospective total is REFUSED (fail-closed), not silently floored to zero');


-- ===== G. No fabricated payment; settlement unchanged =================== 30-32
select is((select count(*) from payments where order_id='fca00000-0000-0000-0000-0000000000d2'), 0::bigint,
  'G1 a comped order has NO payment row — nothing is fabricated');
select ok(app.order_is_fully_settled('fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000d2'),
  'G2 the comped (zero-total) order is NON-CHARGEABLE and therefore SETTLED (predicate unchanged)');
select ok(not app.order_is_fully_settled('fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000d5'),
  'G3 a partially-discounted order still OWES money and is NOT settled');


-- ===== H. Pre-existing guards still hold =============================== 33-34
create temp table t_paid as select app.apply_discount('fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-000000000d11','fca00000-0000-0000-0000-0000000d0a11','fc-paid','order',null,'percentage',10000,'comp a paid order',null) as r;
select is((select r ->> 'detail' from t_paid), 'order_has_completed_payment',
  'H1 the discount-after-payment FREEZE still wins, even for a full-comp-granted cashier');
select throws_ok($$select app.apply_discount('fca00000-0000-0000-0000-00000000c504','fca00000-0000-0000-0000-000000000d12','fca00000-0000-0000-0000-0000000d0a11','fc-term','order',null,'percentage',10000,'comp a completed order',null)$$,
  '42501', null, 'H2 a TERMINAL (completed) order still refuses every discount');


-- ===== I. Denial audit is safe + categorized ========================== 35-38
select ok(exists(select 1 from audit_events
   where action='order.discount_denied'
     and new_values->>'denied_reason'='full_comp_permission_required'
     and new_values->>'resulting_charge_state'='not_chargeable'),
  'I1 a denied full comp is AUDITED with the stable reason + the resulting charge state');
select ok(exists(select 1 from audit_events
   where action='order.discount_denied' and new_values->>'denied_reason'='full_comp_permission_required'
     and new_values ? 'order_code'),
  'I2 ... carrying the SAFE order code');
select ok(not exists(select 1 from audit_events
   where action='order.discount_denied' and new_values->>'denied_reason'='full_comp_permission_required'
     and (new_values ? 'pin' or new_values ? 'pin_verifier' or new_values ? 'resolved_membership_id')),
  'I3 ... and NO PIN material, token, or internal membership id');
select is(app.audit_safe_detail('order.discount_denied',
    jsonb_build_object('denied_reason','full_comp_permission_required','resulting_charge_state','not_chargeable',
                       'order_code','#ABC123','order_id','fca00000-0000-0000-0000-0000000000d1','secret','x'))
    - 'order_code',
  jsonb_build_object('denied_reason','full_comp_permission_required','resulting_charge_state','not_chargeable'),
  'I4 audit_safe_detail PROJECTS the new tokens and DROPS the order_id + unknown keys');


-- ===== J. Permission editing: scope, rank, tenancy ==================== 39-45
set local app.current_app_user_id = 'fca00000-0000-0000-0000-0000000000e1';   -- Org-A org_owner
create temp table t_grant as select app.set_staff_capabilities(
  'fca00000-0000-0000-0000-00000000fa01','fca00000-0000-0000-0000-00000000af03', true, true, true, true) as r;
select is((select r -> 'capabilities' ->> 'apply_full_comp' from t_grant)::boolean, true,
  'J1 an owner may GRANT full-comp to an individual cashier');
select is((select permissions from memberships where id='fca00000-0000-0000-0000-00000000ac03'),
  '{"apply_full_comp":"true"}'::jsonb,
  'J2 ... stored GRANT-ONLY (the canonical string "true"); the deny-only keys stay ABSENT');
select ok(exists(select 1 from audit_events where action='staff.capabilities_updated'
   and (new_values->'capabilities'->>'apply_full_comp')::boolean = true
   and (old_values->'capabilities'->>'apply_full_comp')::boolean = false),
  'J3 the grant is AUDITED with BEFORE (false) and AFTER (true) — never a silent capability change');

-- an OLD client that omits the new argument must FAIL CLOSED (revoke), never grant
create temp table t_old as select app.set_staff_capabilities(
  'fca00000-0000-0000-0000-00000000fa02','fca00000-0000-0000-0000-00000000af03', true, true, true) as r;
select is((select r -> 'capabilities' ->> 'apply_full_comp' from t_old)::boolean, false,
  'J4 an OLD client omitting the new argument defaults to FALSE — it can never silently grant');
select is((select permissions from memberships where id='fca00000-0000-0000-0000-00000000ac03'), '{}'::jsonb,
  'J5 ... and the key is REMOVED (absence denies)');

-- cross-tenant + sibling-restaurant + insufficient rank
set local app.current_app_user_id = 'fcb00000-0000-0000-0000-0000000000eb';   -- Org-B owner
select throws_ok($$select app.set_staff_capabilities('fca00000-0000-0000-0000-00000000fa03','fca00000-0000-0000-0000-00000000af03', true, true, true, true)$$,
  '42501', null, 'J6 CROSS-TENANT permission editing is denied (indistinguishable from not-found — no R-003 oracle)');
set local app.current_app_user_id = 'fca00000-0000-0000-0000-0000000000e7';   -- sibling-restaurant manager
select throws_ok($$select app.set_staff_capabilities('fca00000-0000-0000-0000-00000000fa04','fca00000-0000-0000-0000-00000000af03', true, true, true, true)$$,
  '42501', null, 'J7 a SIBLING-RESTAURANT manager cannot reach this branch''s staff');


-- ===== K. Provisioning: polarity-aware validator + visible audit ====== 46-48
set local app.current_app_user_id = 'fca00000-0000-0000-0000-0000000000e1';
create temp table t_create as select app.create_staff_member(
  'fca00000-0000-0000-0000-00000000fb01','fca00000-0000-0000-0000-0000000000a0',
  'fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11',
  'Comped Cashier', 'cashier', '{"apply_full_comp":"true"}'::jsonb) as r;
select is((select r ->> 'ok' from t_create)::boolean, true,
  'K1 a cashier may be PROVISIONED with the full-comp grant, atomically');
select throws_ok($$select app.create_staff_member('fca00000-0000-0000-0000-00000000fb02','fca00000-0000-0000-0000-0000000000a0','fca00000-0000-0000-0000-0000000000a1','fca00000-0000-0000-0000-00000000ab11','Bad','cashier','{"apply_full_comp":"false"}'::jsonb)$$,
  '42501', null, 'K2 a MALFORMED capability payload fails closed (the grant-only key may only be GRANTED)');
select ok(app.audit_action_has_detail('staff.created'),
  'K3 staff.created is PROJECTED, so a capability granted at provisioning time can never be invisible');

select * from finish();
rollback;
