-- ============================================================================
-- ORDER-COMPLETION-001 — pgTAP: app.owner_complete_order (the JWT Dashboard
-- front) + the shared core app.apply_order_status_transition.
--
-- Fixture: Org A (Rest A1: Branch A1a + Branch A1b) + Org B (isolation).
-- Branch A1a orders (code = last 6 hex of the id, uppercased):
--   #02A001  served,    PAID cash 1000   -> the completable one
--   #02A002  served,    UNPAID           -> D-025 blocks completion
--   #02A003  preparing, PAID             -> not an eligible source state
--   #02A004  completed, PAID             -> already terminal (idempotency target)
--   #02A005  voided,    UNPAID           -> terminal, never revivable
--   #02A006  cancelled, UNPAID           -> terminal, never revivable
-- Branch A1b: #02B001 served + PAID (sibling-branch denial for the A1a manager)
-- Org B:      #02C001 served + PAID (cross-tenant denial)
--
-- Actors: f001 org_owner(A) | f002 manager(A, Branch A1a ONLY) | f003 kitchen_staff(A)
--         f004 accountant(A) | f005 org_owner(B)
--
-- Asserts: served->completed applies for a permitted actor; the order leaves the
-- active set and lands in history as completed; UNPAID is rejected (D-025) with NO
-- write and NO payment created; non-served / completed / cancelled / voided sources
-- are rejected and terminal states are never revived; IDEMPOTENT retry returns a
-- stable success with NO second write and NO duplicate audit event; stale
-- expected_revision -> revision_mismatch; anonymous / kitchen_staff / accountant /
-- cross-tenant / sibling-branch are all denied; the client cannot spoof actor,
-- timestamp or next status (they are not parameters); payments, totals and every
-- unrelated field are untouched; the audit event is correct, safely projected and
-- money-free; and the ACL (DEFINER/INVOKER, search_path, no anon/PUBLIC).
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(38);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'oc-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'oc-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', 'pos'),
  ('00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', 'active'),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-00000000c002'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'oc-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'oc-manager-a1a@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'oc-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f004', 'oc-accountant@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'oc-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0004', '00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'accountant'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Bianca O.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');

-- ---- Orders (see the header table). Every order starts at revision 1. --------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, notes, local_operation_id, revision) values
  ('00000000-0000-0000-0000-00000002a001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 1000, 0, 0, 1000, 'Layla', 'PRIVATE-NOTE', 'oc-a1', 1),
  ('00000000-0000-0000-0000-00000002a002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway','served',    'ILS',  900, 0, 0,  900, null, null, 'oc-a2', 1),
  ('00000000-0000-0000-0000-00000002a003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'preparing', 'ILS',  800, 0, 0,  800, null, null, 'oc-a3', 1),
  ('00000000-0000-0000-0000-00000002a004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS',  700, 0, 0,  700, null, null, 'oc-a4', 1),
  ('00000000-0000-0000-0000-00000002a005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'voided',    'ILS',  600, 0, 0,  600, null, null, 'oc-a5', 1),
  ('00000000-0000-0000-0000-00000002a006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'cancelled', 'ILS',  500, 0, 0,  500, null, null, 'oc-a6', 1),
  ('00000000-0000-0000-0000-00000002b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 2500, 0, 0, 2500, null, null, 'oc-b1', 1),
  ('00000000-0000-0000-0000-00000002c001', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'served',    'EUR', 7777, 0, 0, 7777, null, null, 'oc-c1', 1);

-- ---- Completed cash payments for A001 / A003 / A004 / B001 / C001. -----------
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-00000004a001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a001', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'oc-p1'),
  ('00000000-0000-0000-0000-00000004a003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a003', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed',  800,  800, 0, 'ILS', 'oc-p3'),
  ('00000000-0000-0000-0000-00000004a004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000002a004', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed',  700,  700, 0, 'ILS', 'oc-p4'),
  ('00000000-0000-0000-0000-00000004b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000002b001', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 2500, 2500, 0, 'ILS', 'oc-pb1'),
  ('00000000-0000-0000-0000-00000004c001', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000002c001', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'cash', 'completed', 7777, 7777, 0, 'EUR', 'oc-pc1');

-- ===== (1) UNAUTHENTICATED is denied =========================================
set local role authenticated;
set local app.current_app_user_id = '';
select throws_ok(
  $$ select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a001') $$,
  '42501', NULL, 'an unauthenticated caller cannot complete an order (42501)');
reset role;

-- ===== (2-3) kitchen_staff + accountant are DENIED (audited), no write ========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';  -- kitchen_staff
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a001') ->> 'error'),
  'permission_denied', 'kitchen_staff cannot complete an order (permission_denied)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f004';  -- accountant (read-only)
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a001') ->> 'error'),
  'permission_denied', 'accountant (read-only) cannot complete an order (permission_denied)');
reset role;

select is((select status from orders where id = '00000000-0000-0000-0000-00000002a001'),
  'served', 'neither denial wrote any state change (still served)');                       -- (4)
select ok(
  (select count(*) = 2 from audit_events
    where action = 'order.status_update_denied'
      and new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001'
      and new_values ->> 'to' = 'completed'
      and actor_app_user_id is not null),
  'both denials are AUDITED with the JWT actor (order.status_update_denied)');             -- (5)

-- ===== (6-7) cross-tenant is DENIED, and there is NO existence oracle =========
-- The TENANT GATE fires BEFORE the order is looked up, so an out-of-org caller is
-- rejected identically whether the order exists or not (42501). An IN-org caller
-- naming another tenant's order id simply gets not_found.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_complete_order('00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-00000002c001') $$,
  '42501', NULL, 'an Org A owner cannot act in Org B at all (42501 BEFORE any order lookup — no existence oracle)');
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002c001') ->> 'error'),
  'not_found', 'an Org B order id under Org A scope is not_found (cross-tenant, no leak)');
reset role;

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';  -- manager of Branch A1a ONLY
select throws_ok(
  $$ select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002b001') $$,
  '42501', NULL, 'a Branch A1a manager cannot complete a SIBLING Branch A1b order (42501)');  -- (8)
reset role;
select ok(
  (select o.status = 'served' and o.revision = 1 from orders o where o.id = '00000000-0000-0000-0000-00000002b001'),
  'the sibling-branch order is untouched (served, revision 1)');                            -- (9)
select ok(
  (select o.status = 'served' and o.revision = 1 from orders o where o.id = '00000000-0000-0000-0000-00000002c001'),
  'the cross-tenant order is untouched (served, revision 1)');                              -- (10)

-- ===== (11-13) D-025: an UNPAID served order CANNOT be completed ==============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a002') ->> 'error'),
  'order_not_paid', 'D-025: completing an UNPAID served order is REJECTED (order_not_paid)');
reset role;
select ok(
  (select o.status = 'served' and o.revision = 1 from orders o where o.id = '00000000-0000-0000-0000-00000002a002'),
  'the unpaid order is untouched (still served, revision 1)');
select is(
  (select count(*)::int from payments where order_id = '00000000-0000-0000-0000-00000002a002'),
  0, 'the rejected completion created NO payment (payment is never fabricated)');

-- ===== (14-16) ineligible SOURCE states are rejected ==========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a003') ->> 'error'),
  'invalid_transition', 'a PREPARING order cannot be completed (invalid_transition — no skipping)');
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a005') ->> 'error'),
  'invalid_transition', 'a VOIDED order can never be completed (terminal, never revived)');
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a006') ->> 'error'),
  'invalid_transition', 'a CANCELLED order can never be completed (terminal, never revived)');
reset role;

-- ===== (17-18) IDEMPOTENCY: an ALREADY-completed order -> stable success ======
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select ok(
  (select r ->> 'ok' = 'true' and (r ->> 'already_completed')::boolean = true
      and r ->> 'status' = 'completed'
   from app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a004') as r),
  'completing an ALREADY-completed order returns a STABLE SUCCESS (already_completed), not an error');
reset role;
select ok(
  (select o.status = 'completed' and o.revision = 1 from orders o where o.id = '00000000-0000-0000-0000-00000002a004'),
  'the idempotent call wrote NOTHING (revision still 1 — no second transition)');

-- ===== (19) a stale expected_revision -> revision_mismatch, no write ==========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select ok(
  (select r ->> 'error' = 'revision_mismatch' and (r ->> 'server_revision')::int = 1
   from app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a001', 99) as r),
  'a STALE client (expected_revision 99) is rejected with revision_mismatch + the server revision');
reset role;
select is((select status from orders where id = '00000000-0000-0000-0000-00000002a001'),
  'served', 'the stale attempt wrote NO state change (still served)');                     -- (20)

-- ===== (21-26) THE HAPPY PATH: a permitted actor completes a PAID served order =
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';  -- manager of A1a
create temp table t_done as
  select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a001', 1) as res;
reset role;

select ok(
  (select (res ->> 'ok')::boolean = true and res ->> 'status' = 'completed'
      and res ->> 'order_code' = '#02A001' and (res ->> 'revision')::int = 2 from t_done),
  'a permitted actor COMPLETES an eligible PAID served order (ok, completed, revision 2)');
select is((select status from orders where id = '00000000-0000-0000-0000-00000002a001'),
  'completed', 'the order is PERSISTED at completed (it leaves the ACTIVE set -> the board drains)');
-- NOTE: now() is the TRANSACTION timestamp, so updated_at cannot be observed to
-- advance past created_at inside this test's single transaction. The revision bump
-- is the observable optimistic-concurrency signal; the updated_at cursor bump is
-- owned (and tested) by the RF-052 set_updated_at trigger.
select ok(
  (select o.revision = 2 and o.updated_at is not null and o.updated_at >= o.created_at
   from orders o where o.id = '00000000-0000-0000-0000-00000002a001'),
  'the persisted row carries the bumped revision 2 (optimistic-concurrency signal)');
-- payment untouched, totals untouched, unrelated fields untouched
select ok(
  (select count(*) = 1 and max(p.amount_minor) = 1000 and bool_and(p.status = 'completed')
   from payments p where p.order_id = '00000000-0000-0000-0000-00000002a001'),
  'the payment row is UNTOUCHED (still exactly one completed cash payment of 1000)');
select ok(
  (select o.grand_total_minor = 1000 and o.subtotal_minor = 1000 and o.discount_total_minor = 0
      and o.tax_total_minor = 0 and o.currency_code = 'ILS'
   from orders o where o.id = '00000000-0000-0000-0000-00000002a001'),
  'integer-minor TOTALS are unchanged by completion (no money is recomputed)');
select ok(
  (select o.customer_name = 'Layla' and o.notes = 'PRIVATE-NOTE' and o.order_type = 'dine_in'
      and o.table_id is null and o.receipt_number is null and o.void_reason is null
   from orders o where o.id = '00000000-0000-0000-0000-00000002a001'),
  'every UNRELATED order field is unchanged (customer/notes/type/table/receipt/void_reason)');

-- ===== (27-31) the AUDIT event ===============================================
select ok(
  (select count(*) = 1 from audit_events
    where action = 'order.status_updated'
      and new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001'
      and new_values ->> 'status' = 'completed'),
  'the completion emits EXACTLY ONE order.status_updated audit event');
select ok(
  (select ae.old_values ->> 'status' = 'served'
      and ae.new_values ->> 'status' = 'completed'
      and ae.new_values ->> 'order_code' = '#02A001'
      and ae.new_values ->> 'payment_status' = 'paid'
      and ae.new_values ->> 'role' = 'manager'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001'),
  'the audit records previous=served, new=completed, the SAFE order_code, payment_status=paid, and the role');
select ok(
  (select ae.organization_id = '00000000-0000-0000-0000-0000000a0000'
      and ae.restaurant_id   = '00000000-0000-0000-0000-0000000a1000'
      and ae.branch_id       = '00000000-0000-0000-0000-0000000a1a00'
      and ae.actor_app_user_id = '00000000-0000-0000-0000-00000000f002'   -- the JWT actor, server-derived
      and ae.actor_employee_profile_id is null
      and ae.device_id is null
      and ae.occurred_at <= now()                                          -- authoritative server UTC
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001'),
  'the audit carries the SERVER-DERIVED actor + full org/restaurant/branch scope + authoritative UTC time');
select ok(
  (select not exists (
     select 1 from audit_events ae, lateral jsonb_object_keys(ae.new_values || coalesce(ae.old_values,'{}'::jsonb)) k
     where ae.action = 'order.status_updated'
       and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001'
       and (k like '%_minor' or k in ('customer_name','notes','phone','email','address','pin','token','device_id')))),
  'the audit payload is MONEY-FREE (T-003) and carries no customer/private key');
-- the SAFE PROJECTION the Dashboard actually receives
select ok(
  (select app.audit_safe_detail('order.status_updated', ae.new_values) ?& array['status','order_code','payment_status','role']
      and not (app.audit_safe_detail('order.status_updated', ae.new_values) ?| array['order_id','revision','resolved_membership_id','local_operation_id'])
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001'),
  'audit_safe_detail projects ONLY status/order_code/payment_status/role — the order UUID, revision, membership id and op id are DROPPED');

-- ===== (32-33) classification: orders, never Other ===========================
select is(app.audit_category('order.status_updated'), 'orders',
  'order.status_updated classifies as ORDERS (never Other)');
select is(app.audit_category('order.status_update_denied'), 'orders',
  'order.status_update_denied classifies as ORDERS (never Other)');

-- ===== (34) a SECOND completion after success is idempotent, NOT a duplicate ==
-- (audit_events is read AFTER `reset role`: under the `authenticated` role its
--  RLS policies are GUC-bound and would hide the rows.)
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';
create temp table t_retry as
  select app.owner_complete_order('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-00000002a001') as res;
reset role;
select ok(
  (select (res ->> 'ok')::boolean = true and (res ->> 'already_completed')::boolean = true from t_retry)
  and (select count(*) = 1 from audit_events
        where action = 'order.status_updated'
          and new_values ->> 'order_id' = '00000000-0000-0000-0000-00000002a001')
  and (select o.revision = 2 and o.status = 'completed' from orders o
        where o.id = '00000000-0000-0000-0000-00000002a001'),
  'a RETRY after a confirmed completion returns a stable success, creates NO duplicate audit event, and does NOT re-transition');

-- ===== (35) the client cannot choose the next status =========================
select ok(
  (select count(*) = 0 from information_schema.parameters
    where specific_schema = 'app'
      and specific_name in (select specific_name from information_schema.routines
                             where routine_schema = 'app' and routine_name = 'owner_complete_order')
      and parameter_name in ('p_new_status', 'p_status', 'p_actor_id', 'p_occurred_at', 'p_actor_app_user_id')),
  'owner_complete_order exposes NO next-status, NO actor and NO timestamp parameter (they cannot be spoofed)');

-- ===== (36) the state-machine CORE is internal (no client role may call it) ===
select ok(
  not has_function_privilege('authenticated', 'app.apply_order_status_transition(uuid,text,uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,text,integer)', 'execute')
  and not has_function_privilege('anon',   'app.apply_order_status_transition(uuid,text,uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,text,integer)', 'execute')
  and not has_function_privilege('public', 'app.apply_order_status_transition(uuid,text,uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,text,integer)', 'execute'),
  'the shared state-machine CORE is INTERNAL — no client role (authenticated/anon/PUBLIC) may execute it');

-- ===== (37) app.update_order_status STILL has no public wrapper ==============
select hasnt_function('public', 'update_order_status',
  'app.update_order_status STILL has no public wrapper (the JWT front is owner_complete_order, not a second state machine)');

-- ===== (38) ACL: DEFINER/INVOKER + search_path + authenticated-only ==========
select ok(
  (select prosecdef = true  from pg_proc where proname='owner_complete_order' and pronamespace='app'::regnamespace)
  and (select prosecdef = false from pg_proc where proname='owner_complete_order' and pronamespace='public'::regnamespace)
  and exists (select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
              where p.proname='owner_complete_order' and p.pronamespace='app'::regnamespace and cfg like 'search_path=%')
  and exists (select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig,'{}'::text[])) as cfg
              where p.proname='owner_complete_order' and p.pronamespace='public'::regnamespace and cfg like 'search_path=%')
  and not has_function_privilege('anon',   'public.owner_complete_order(uuid,uuid,integer)', 'execute')
  and not has_function_privilege('public', 'public.owner_complete_order(uuid,uuid,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_complete_order(uuid,uuid,integer)', 'execute')
  and not has_function_privilege('anon',   'app.owner_complete_order(uuid,uuid,integer)', 'execute')
  and has_function_privilege('authenticated', 'app.owner_complete_order(uuid,uuid,integer)', 'execute'),
  'app fn is DEFINER + public wrapper is INVOKER, both search_path-locked, authenticated-only (anon + PUBLIC revoked)');

select * from finish();
rollback;
