-- ============================================================================
-- ORDER-AUTO-COMPLETION-001 — pgTAP: a SERVED order that is FULLY PAID completes
-- itself, automatically, from BOTH trigger directions.
--
--   A. the order reaches `served` and is ALREADY paid   (the KDS bump)
--   B. the order is ALREADY `served` and BECOMES paid   (the POS payment)
--
-- Both chain app.try_auto_complete_order at the tail of the operation, under the
-- order row lock the operation ALREADY holds. An UNPAID served order stays ACTIVE.
--
-- Fixture: Org A / Rest A1 / Branch A1a, one POS device (cashier PIN session) and
-- one KDS device (kitchen_staff PIN session). Orders (code = last 6 hex, uppercased):
--   #0AC001  ready,     PAID 1000        -> A: bump to served  => AUTO-COMPLETES
--   #0AC002  ready,     UNPAID  900      -> A: bump to served  => stays served
--   #0AC003  served,    UNPAID  800      -> B: take payment    => AUTO-COMPLETES
--   #0AC004  submitted, UNPAID  700      -> B: take payment    => stays submitted
--   #0AC005  served,    UNDER-COVERED (completed payment 500 vs total 1000)
--   #0AC006  served,    PAID  600        -> the MANUAL recovery path still works
--   #0AC007  completed, PAID  500        -> terminal, never revived
--   #0AC008  served,    total 0, NO payment  -> NON-CHARGEABLE => settled, completes
--   #0AC009  served,    SOFT-DELETED completed payment
--   #0AC00A  served,    PENDING (non-completed) payment
--   #0AC00B  preparing, PAID 1200        -> A: bump to READY   => NOT completed
--   #0AC00C  voided,    UNPAID           -> terminal, never revived
--   #0AC00D  cancelled, UNPAID           -> terminal, never revived
--   #0AC00E  ready,     total 0, NO payment  -> A: bump to served => AUTO-COMPLETES
--   #0AC00F  served,    total 0, NO payment  -> the MANUAL path must AGREE (settled)
--   #0AC010  served,    250, NO payment      -> CHARGEABLE => D-025 keeps it served
--
-- Asserts: both directions complete a served+settled order in the SAME transaction and
-- report the FINAL status; an unpaid served order stays ACTIVE; a payment on a
-- not-yet-served order never completes it; NO payment is ever created, modified or
-- fabricated by the automatic path and NO money figure moves; the settlement test is
-- amount-aware (integer minor units) and ignores soft-deleted / non-completed /
-- under-covering payments; a ZERO-TOTAL order is NON-CHARGEABLE (settled with NO
-- payment row, and none is ever created) while a POSITIVE-total order keeps the full
-- D-025 gate; the MANUAL and AUTOMATIC paths AGREE because they share the one
-- predicate; a negative/missing/cross-tenant order FAILS CLOSED; terminal orders are
-- NEVER revived; the automatic step is idempotent (no second transition, no duplicate
-- audit); a genuine failure inside the helper is FAIL-SOFT but DIAGNOSABLE and leaves
-- NOTHING partial and NO fake success audit; and both new helpers are INTERNAL.
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth (GUC-free).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(51);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000ac0a0', 'Org A', 'ac-a', 'ILS'),
  -- A REAL second tenant holding a REAL settled order, so the cross-tenant assertion
  -- below is a genuine isolation test and not a disguised "missing order" case.
  ('00000000-0000-0000-0000-0000000ac0b0', 'Org B', 'ac-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000ac0a0', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000ac0b0', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000acba0', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', 'Branch B1a');

-- two devices: the POS (payments) and the KDS (status bumps)
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', 'pos'),
  ('00000000-0000-0000-0000-0000000acd02', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0000000acc01', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', 'active'),
  ('00000000-0000-0000-0000-0000000acc02', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd02', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000aced1', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc01'),
  ('00000000-0000-0000-0000-0000000aced2', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd02', '00000000-0000-0000-0000-0000000acc02');

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000acf01', 'ac-cashier@example.test'),
  ('00000000-0000-0000-0000-0000000acf02', 'ac-kitchen@example.test'),
  ('00000000-0000-0000-0000-0000000acf03', 'ac-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000acb11', '00000000-0000-0000-0000-0000000acf01', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', 'cashier'),
  ('00000000-0000-0000-0000-0000000acb12', '00000000-0000-0000-0000-0000000acf02', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000acb13', '00000000-0000-0000-0000-0000000acf03', '00000000-0000-0000-0000-0000000ac0a0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acf01', '00000000-0000-0000-0000-0000000acb11', 'Cashier C.'),
  ('00000000-0000-0000-0000-0000000acea2', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acf02', '00000000-0000-0000-0000-0000000acb12', 'Kitchen K.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000aced1', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000acc52', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000aced2', '00000000-0000-0000-0000-0000000acea2', '00000000-0000-0000-0000-0000000acb12', now() + interval '1 hour');

-- ---- Orders (see the header table). Every order starts at revision 1. --------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, customer_name, notes, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0000000ac001', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'ready',     'ILS', 1000, 0, 0, 1000, 'Layla', 'PRIVATE-NOTE', 'ac-o1',  1),
  ('00000000-0000-0000-0000-0000000ac002', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'ready',     'ILS',  900, 0, 0,  900, null, null, 'ac-o2',  1),
  ('00000000-0000-0000-0000-0000000ac003', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',  800, 0, 0,  800, null, null, 'ac-o3',  1),
  ('00000000-0000-0000-0000-0000000ac004', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'takeaway', 'submitted', 'ILS',  700, 0, 0,  700, null, null, 'ac-o4',  1),
  ('00000000-0000-0000-0000-0000000ac005', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS', 1000, 0, 0, 1000, null, null, 'ac-o5',  1),
  ('00000000-0000-0000-0000-0000000ac006', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',  600, 0, 0,  600, null, null, 'ac-o6',  1),
  ('00000000-0000-0000-0000-0000000ac007', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'completed', 'ILS',  500, 0, 0,  500, null, null, 'ac-o7',  1),
  ('00000000-0000-0000-0000-0000000ac008', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',    0, 0, 0,    0, null, null, 'ac-o8',  1),
  ('00000000-0000-0000-0000-0000000ac009', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',  400, 0, 0,  400, null, null, 'ac-o9',  1),
  ('00000000-0000-0000-0000-0000000ac00a', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',  300, 0, 0,  300, null, null, 'ac-o10', 1),
  ('00000000-0000-0000-0000-0000000ac00b', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'preparing', 'ILS', 1200, 0, 0, 1200, null, null, 'ac-o11', 1),
  ('00000000-0000-0000-0000-0000000ac00c', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'voided',    'ILS',  200, 0, 0,  200, null, null, 'ac-o12', 1),
  ('00000000-0000-0000-0000-0000000ac00d', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'cancelled', 'ILS',  100, 0, 0,  100, null, null, 'ac-o13', 1),
  -- ZERO-TOTAL (non-chargeable) fixtures — comped / 100%-discounted orders that owe
  -- NOTHING and therefore carry NO payment row and never will.
  ('00000000-0000-0000-0000-0000000ac00e', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'ready',     'ILS',    0, 0, 0,    0, null, null, 'ac-o14', 1),
  ('00000000-0000-0000-0000-0000000ac00f', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',    0, 0, 0,    0, null, null, 'ac-o15', 1),
  ('00000000-0000-0000-0000-0000000ac010', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'dine_in',  'served',    'ILS',  250, 0, 0,  250, null, null, 'ac-o16', 1);

-- ---- Pre-existing payments (fixture-inserted; the RPC-written ones come later) --
--  ac001 fully paid | ac005 UNDER-COVERED (500 of 1000 — the discount re-base case)
--  ac006 fully paid | ac007 fully paid | ac009 SOFT-DELETED | ac00a PENDING | ac00b fully paid
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, deleted_at) values
  ('00000000-0000-0000-0000-0000000acaf1', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac001', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'ac-p1', null),
  ('00000000-0000-0000-0000-0000000acaf5', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac005', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'completed',  500,  500, 0, 'ILS', 'ac-p5', null),
  ('00000000-0000-0000-0000-0000000acaf6', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac006', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'completed',  600,  600, 0, 'ILS', 'ac-p6', null),
  ('00000000-0000-0000-0000-0000000acaf7', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac007', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'completed',  500,  500, 0, 'ILS', 'ac-p7', null),
  ('00000000-0000-0000-0000-0000000acaf9', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac009', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'completed',  400,  400, 0, 'ILS', 'ac-p9', now()),
  ('00000000-0000-0000-0000-0000000acafa', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac00a', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'pending',    300,  300, 0, 'ILS', 'ac-p10', null),
  ('00000000-0000-0000-0000-0000000acafb', '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0', '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac00b', '00000000-0000-0000-0000-0000000acd01', '00000000-0000-0000-0000-0000000acea1', '00000000-0000-0000-0000-0000000acb11', 'cash', 'completed', 1200, 1200, 0, 'ILS', 'ac-p11', null);

-- ---- ORG B (isolation): a REAL order that IS settled under its OWN tenant. ------
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0000000acd0b', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000acba0', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0000000acc0b', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000acba0', '00000000-0000-0000-0000-0000000acd0b', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-000000aced0b', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000acba0', '00000000-0000-0000-0000-0000000acd0b', '00000000-0000-0000-0000-0000000acc0b');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000acf0b', 'ac-orgb@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000acb1b', '00000000-0000-0000-0000-0000000acf0b', '00000000-0000-0000-0000-0000000ac0b0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000aceab', '00000000-0000-0000-0000-0000000ac0b0', null, null, '00000000-0000-0000-0000-0000000acf0b', '00000000-0000-0000-0000-0000000acb1b', 'Org B Owner');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000acc5b', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000acba0', '00000000-0000-0000-0000-000000aced0b', '00000000-0000-0000-0000-0000000aceab', '00000000-0000-0000-0000-0000000acb1b', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0000000ac0b1', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000acba0', '00000000-0000-0000-0000-0000000acd0b', '00000000-0000-0000-0000-0000000acc5b', '00000000-0000-0000-0000-0000000aceab', '00000000-0000-0000-0000-0000000acb1b', 'dine_in', 'served', 'EUR', 7777, 0, 0, 7777, 'ac-ob1', 1);
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-000000acafb1', '00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac1b0', '00000000-0000-0000-0000-0000000acba0', '00000000-0000-0000-0000-0000000ac0b1', '00000000-0000-0000-0000-0000000acd0b', '00000000-0000-0000-0000-0000000aceab', '00000000-0000-0000-0000-0000000acb1b', 'cash', 'completed', 7777, 7777, 0, 'EUR', 'ac-pb1');

-- an open shift + active bound drawer, so app.record_payment can run (RF-055).
select app.open_shift('00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000acff1',
                      '00000000-0000-0000-0000-0000000acdd1', '00000000-0000-0000-0000-0000000acd01', 'ac-sh', 0);

-- =============================================================================
-- A. TRIGGER DIRECTION A — the KDS bumps a PAID order to `served`  (tests 1-7)
--    The kitchen actor is kitchen_staff, who is DENIED `-> completed` by the role
--    gate on the MANUAL path. The automatic path must still complete the order —
--    authorization already passed on the bump, and the completion is a system-rule
--    consequence of it, not a second human decision.
-- =============================================================================
create temp table t_a as
  select app.update_order_status('00000000-0000-0000-0000-0000000acc52', '00000000-0000-0000-0000-0000000acd02',
                                 '00000000-0000-0000-0000-0000000ac001', 'served', 'ac-bump-1') as res;

select ok((select (res ->> 'ok')::boolean = true and res ->> 'status' = 'completed' from t_a),
  'A: bumping a PAID order to served reports the FINAL status — completed, not served');            -- 1
select ok((select (res ->> 'auto_completed')::boolean = true from t_a),
  'A: the envelope reports auto_completed = true');                                                 -- 2
select is((select res ->> 'completion_trigger' from t_a), 'order_served',
  'A: the envelope names the trigger (order_served)');                                              -- 3
select is((select status from orders where id = '00000000-0000-0000-0000-0000000ac001'), 'completed',
  'A: the order is PERSISTED at completed (it leaves the ACTIVE board by itself)');                 -- 4
select is((select revision from orders where id = '00000000-0000-0000-0000-0000000ac001'), 3,
  'A: revision advanced by exactly TWO (1 -> served 2 -> completed 3): two real transitions');      -- 5
select ok(
  (select count(*) = 1 and max(p.amount_minor) = 1000 and bool_and(p.status = 'completed')
   from payments p where p.order_id = '00000000-0000-0000-0000-0000000ac001'),
  'A: the payment row is UNTOUCHED — auto-completion creates and modifies NO payment');             -- 6
select ok(
  (select o.grand_total_minor = 1000 and o.subtotal_minor = 1000 and o.discount_total_minor = 0
      and o.tax_total_minor = 0 and o.currency_code = 'ILS' and o.customer_name = 'Layla'
   from orders o where o.id = '00000000-0000-0000-0000-0000000ac001'),
  'A: integer-minor TOTALS and every unrelated field are unchanged (no money is recomputed)');      -- 7

-- =============================================================================
-- B. DIRECTION A, UNPAID — a served order that nobody paid STAYS ACTIVE (8-11)
-- =============================================================================
create temp table t_b as
  select app.update_order_status('00000000-0000-0000-0000-0000000acc52', '00000000-0000-0000-0000-0000000acd02',
                                 '00000000-0000-0000-0000-0000000ac002', 'served', 'ac-bump-2') as res;

select ok((select (res ->> 'ok')::boolean = true and res ->> 'status' = 'served'
              and (res ->> 'auto_completed')::boolean = false from t_b),
  'A-unpaid: the served transition SUCCEEDS on its own and does NOT auto-complete');                -- 8
select ok((select o.status = 'served' and o.revision = 2 from orders o
            where o.id = '00000000-0000-0000-0000-0000000ac002'),
  'A-unpaid: the order stays SERVED and stays ACTIVE (visible in Awaiting close — the exception)'); -- 9
select is((select count(*)::int from payments where order_id = '00000000-0000-0000-0000-0000000ac002'), 0,
  'A-unpaid: NO payment was fabricated to force a completion');                                     -- 10
select is((select count(*)::int from audit_events
            where action = 'order.status_updated'
              and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac002'
              and new_values ->> 'status' = 'completed'), 0,
  'A-unpaid: NO completion audit event was emitted');                                               -- 11

-- =============================================================================
-- C. DIRECTION A landing on a NON-served state — never completes early (12-13)
-- =============================================================================
create temp table t_c as
  select app.update_order_status('00000000-0000-0000-0000-0000000acc52', '00000000-0000-0000-0000-0000000acd02',
                                 '00000000-0000-0000-0000-0000000ac00b', 'ready', 'ac-bump-3') as res;

select ok((select (res ->> 'ok')::boolean = true and res ->> 'status' = 'ready'
              and (res ->> 'auto_completed')::boolean = false from t_c),
  'A: a PAID order bumped preparing -> READY is NOT auto-completed (only `served` triggers)');      -- 12
select is((select status from orders where id = '00000000-0000-0000-0000-0000000ac00b'), 'ready',
  'A: a paid order is never completed before it is actually served (fulfillment still matters)');   -- 13

-- =============================================================================
-- D. TRIGGER DIRECTION B — a SERVED order BECOMES fully paid  (14-19)
-- =============================================================================
create temp table t_d as
  select app.record_payment('00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000ac003',
                            '00000000-0000-0000-0000-0000000acd01', 'ac-pay-3', 'cash', 800, null) as res;

select ok((select (res ->> 'ok')::boolean = true and res ->> 'payment_id' is not null from t_d),
  'B: the payment itself SUCCEEDS (the auto-completion is a consequence, never a precondition)');   -- 14
select ok((select (res ->> 'auto_completed')::boolean = true from t_d),
  'B: paying a SERVED order reports auto_completed = true');                                        -- 15
select is((select res ->> 'order_status' from t_d), 'completed',
  'B: the payment envelope reports the order''s FINAL status (completed)');                         -- 16
-- revision 3, and every step is real: 1 -> record_payment stamps the receipt number
-- on the order (2) -> the automatic completion (3). The envelope reports the FINAL
-- revision, so a client that writes it back can never be stale by construction.
select ok((select o.status = 'completed' and o.revision = 3 from orders o
            where o.id = '00000000-0000-0000-0000-0000000ac003')
          and (select (res ->> 'order_revision')::int = 3 from t_d),
  'B: the order is PERSISTED at completed and the envelope reports the FINAL revision');            -- 17
select ok(
  (select count(*) = 1 and max(p.amount_minor) = 800 and max(p.tendered_minor) = 800
      and bool_and(p.status = 'completed') and bool_and(p.deleted_at is null)
   from payments p where p.order_id = '00000000-0000-0000-0000-0000000ac003'),
  'B: exactly ONE completed payment, amount = the order total (the payment row is never rewritten)'); -- 18
select ok((select o.receipt_number is not null from orders o
            where o.id = '00000000-0000-0000-0000-0000000ac003'),
  'B: the receipt number was still assigned (D-021) — the payment pipeline is unbroken');           -- 19

-- =============================================================================
-- E. DIRECTION B on a NOT-YET-SERVED order — pays, does NOT complete  (20-22)
-- =============================================================================
create temp table t_e as
  select app.record_payment('00000000-0000-0000-0000-0000000acc51', '00000000-0000-0000-0000-0000000ac004',
                            '00000000-0000-0000-0000-0000000acd01', 'ac-pay-4', 'cash', 700, null) as res;

select ok((select (res ->> 'auto_completed')::boolean = false and res ->> 'order_status' = 'submitted' from t_e),
  'B: paying a SUBMITTED order does NOT complete it (payment alone is not fulfillment — D-025)');   -- 20
-- (revision 2 = the receipt-number stamp record_payment always writes; the STATUS is
--  what matters here, and it did not move.)
select ok((select o.status = 'submitted' and o.receipt_number is not null from orders o
            where o.id = '00000000-0000-0000-0000-0000000ac004'),
  'B: the paid-but-unserved order stays SUBMITTED and stays ACTIVE (the kitchen still owes food)'); -- 21
select ok(
  (select count(*) = 1 and bool_and(p.status = 'completed') and max(p.amount_minor) = 700
   from payments p where p.order_id = '00000000-0000-0000-0000-0000000ac004'),
  'B: the payment itself still SUCCEEDED — a non-firing auto-completion never fails a payment');    -- 22

-- =============================================================================
-- F. THE SETTLEMENT GATE — amount-aware, not a marker  (23-29)
--    app.order_is_fully_settled compares INTEGER MINOR UNITS. A bare
--    exists()-a-completed-payment MARKER would call #0AC005 paid: it carries a
--    genuine completed payment of 500 against a CURRENT total of 1000 (what
--    app.apply_discount's total re-base leaves behind).
-- =============================================================================
select ok(app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac006'),
  'settled: a completed payment covering the CURRENT grand_total settles the order');               -- 23
select ok(not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac005'),
  'settled: an UNDER-COVERING completed payment (500 of 1000) does NOT settle it — a marker test would have');  -- 24
select ok(not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac002'),
  'settled: an order with NO payment at all is not settled');                                       -- 25
select ok(not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac009'),
  'settled: a SOFT-DELETED (tombstoned) payment does not settle an order');                         -- 26
select ok(not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac00a'),
  'settled: a PENDING (non-completed) payment does not settle an order');                           -- 27

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000acf03';   -- org_owner
select is(
  (select app.owner_complete_order('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac005') ->> 'error'),
  'order_not_paid',
  'D-025 HARDENED: the MANUAL path now also refuses an UNDER-COVERED order (settlement, not marker)');  -- 28
reset role;
select ok((select o.status = 'served' and o.revision = 1 from orders o
            where o.id = '00000000-0000-0000-0000-0000000ac005'),
  'the under-covered order is untouched and stays ACTIVE — it is a real exception, kept visible');   -- 29

-- =============================================================================
-- G. TERMINAL + IDEMPOTENCY — nothing is ever revived, nothing fires twice (30-33)
--    (app.try_auto_complete_order is called directly here: it is the ONE decision
--     both directions share, and these are its guard rails.)
-- =============================================================================
select ok(
  (select not (app.try_auto_complete_order(
      '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
      '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac007',
      'payment_recorded', null, '00000000-0000-0000-0000-0000000acea1',
      '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-retry')
    ->> 'completed')::boolean)
  and (select o.revision = 1 and o.status = 'completed' from orders o
        where o.id = '00000000-0000-0000-0000-0000000ac007'),
  'IDEMPOTENT: an ALREADY-completed order is left alone (completed=false, no second transition)');   -- 30
select ok(
  (select not (app.try_auto_complete_order(
      '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
      '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac00c',
      'payment_recorded', null, '00000000-0000-0000-0000-0000000acea1',
      '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-void')
    ->> 'completed')::boolean)
  and (select o.status = 'voided' from orders o where o.id = '00000000-0000-0000-0000-0000000ac00c'),
  'a VOIDED order is NEVER revived into completed by the automatic rule');                           -- 31
select ok(
  (select not (app.try_auto_complete_order(
      '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
      '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac00d',
      'payment_recorded', null, '00000000-0000-0000-0000-0000000acea1',
      '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-canc')
    ->> 'completed')::boolean)
  and (select o.status = 'cancelled' from orders o where o.id = '00000000-0000-0000-0000-0000000ac00d'),
  'a CANCELLED order is NEVER revived into completed by the automatic rule');                        -- 32
-- A ZERO-TOTAL order is NON-CHARGEABLE: it owes nothing, so it is SETTLED with NO
-- payment row — and none is ever created for it. (Before the correction this order
-- was permanently STUCK: the rule would not close it AND the manual recovery RPC
-- refused it with `order_not_paid`, because both consult this one predicate.)
-- (The call is materialized FIRST: Postgres may evaluate the operands of an AND in
--  any order, so a status read in the same expression could race the write.)
create temp table t_zero8 as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
    '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac008',
    'order_served', null, '00000000-0000-0000-0000-0000000acea1',
    '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-zero') as res;
select ok(
  (select (res ->> 'completed')::boolean from t_zero8)
  and (select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-0000000ac008'),
  'a ZERO-TOTAL served order with NO payment row IS settled and auto-completes (non-chargeable)');    -- 33

-- =============================================================================
-- H. ACL — both new helpers are INTERNAL  (34-35)
-- =============================================================================
select ok(
  not has_function_privilege('authenticated', 'app.order_is_fully_settled(uuid,uuid)', 'execute')
  and not has_function_privilege('anon',   'app.order_is_fully_settled(uuid,uuid)', 'execute')
  and not has_function_privilege('public', 'app.order_is_fully_settled(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.try_auto_complete_order(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,uuid,text)', 'execute')
  and not has_function_privilege('anon',   'app.try_auto_complete_order(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,uuid,text)', 'execute')
  and not has_function_privilege('public', 'app.try_auto_complete_order(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,uuid,text)', 'execute')
  and not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                   and proname in ('order_is_fully_settled', 'try_auto_complete_order')),
  'both helpers are INTERNAL: no anon/authenticated/PUBLIC execute, and NO public wrapper exists');  -- 34
select ok(
  (select bool_and(p.prosecdef) from pg_proc p where p.pronamespace = 'app'::regnamespace
     and p.proname in ('order_is_fully_settled', 'try_auto_complete_order'))
  and (select count(*) = 2 from pg_proc p
        cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
        where p.pronamespace = 'app'::regnamespace
          and p.proname in ('order_is_fully_settled', 'try_auto_complete_order')
          and cfg like 'search_path=%'),
  'both helpers are SECURITY DEFINER and search_path-locked');                                       -- 35

-- =============================================================================
-- I. ZERO-TOTAL = NON-CHARGEABLE = SETTLED  (36-47)
--    The human decision: a zero-total order owes NOTHING, so it is fully settled
--    WITHOUT a payment row and NO payment row is ever created for it. This is the
--    schema's definition of D-025's previously-undefined "chargeable order":
--    grand_total_minor > 0. There is ONE predicate; the automatic and manual paths
--    must AGREE, because both consult it.
-- =============================================================================
select ok(app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac00f'),
  'ZERO-TOTAL with NO payment row is SETTLED (non-chargeable: it owes nothing)');                    -- 36
select is((select count(*)::int from payments where order_id = '00000000-0000-0000-0000-0000000ac008'), 0,
  'the zero-total completion created NO payment row — a zero-value payment is NEVER fabricated');    -- 37
select is((select count(*)::int from audit_events
            where action = 'order.status_updated'
              and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac008'), 1,
  'the zero-total completion emits EXACTLY ONE semantic completion audit event');                    -- 38
-- THE AUDIT MUST NOT LIE (D-013, append-only): the order was completed WITHOUT a
-- payment row, so it must NOT claim payment_status = 'paid'.
select ok(
  (select ae.old_values ->> 'status' = 'served'
      and ae.new_values ->> 'status' = 'completed'
      and ae.new_values ->> 'completion_mode' = 'automatic'
      and ae.new_values ->> 'payment_status' = 'not_chargeable'
      and ae.new_values ->> 'payment_status' <> 'paid'
   from audit_events ae
   where ae.action = 'order.status_updated'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac008'),
  'the zero-total audit records served -> completed, mode=automatic, and payment_status=NOT_CHARGEABLE (never the false literal "paid")');  -- 39
-- RETRY: the order is now `completed`, so the helper's status re-read refuses it.
select ok(
  (select not (app.try_auto_complete_order(
      '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
      '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac008',
      'order_served', null, '00000000-0000-0000-0000-0000000acea1',
      '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-zero-retry')
    ->> 'completed')::boolean)
  and (select o.revision = 2 from orders o where o.id = '00000000-0000-0000-0000-0000000ac008')
  and (select count(*) = 1 from audit_events
        where action = 'order.status_updated'
          and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac008'),
  'a RETRY on the zero-total order is INERT: no second transition and no duplicate audit event');    -- 40

-- DIRECTION A on a zero-total order: the KDS bump closes it, with no payment at all.
create temp table t_zero as
  select app.update_order_status('00000000-0000-0000-0000-0000000acc52', '00000000-0000-0000-0000-0000000acd02',
                                 '00000000-0000-0000-0000-0000000ac00e', 'served', 'ac-bump-zero') as res;
select ok((select (res ->> 'ok')::boolean = true and res ->> 'status' = 'completed'
              and (res ->> 'auto_completed')::boolean = true
              and res ->> 'completion_trigger' = 'order_served' from t_zero),
  'DIRECTION A: serving a ZERO-TOTAL order auto-completes it (trigger = order_served)');             -- 41
select ok((select o.status = 'completed' and o.revision = 3 from orders o
            where o.id = '00000000-0000-0000-0000-0000000ac00e'),
  'the zero-total order is PERSISTED completed (two real transitions: served, then completed)');     -- 42
select is((select count(*)::int from payments where order_id = '00000000-0000-0000-0000-0000000ac00e'), 0,
  'DIRECTION A on a zero-total order created NO payment row');                                       -- 43
select ok(
  (select count(*) = 1 from audit_events ae
    where ae.action = 'order.status_updated'
      and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac00e'
      and ae.new_values ->> 'status' = 'completed'
      and ae.new_values ->> 'completion_mode' = 'automatic'
      and ae.new_values ->> 'completion_trigger' = 'order_served'
      and ae.new_values ->> 'payment_status' = 'not_chargeable'),
  'exactly ONE automatic completion event: mode=automatic, trigger=order_served, payment_status=not_chargeable');  -- 44

-- MANUAL/AUTOMATIC AGREEMENT: the same predicate, so the manual recovery path must
-- NOT return `order_not_paid` for an order the automatic rule considers settled.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000acf03';   -- org_owner
create temp table t_zero_manual as
  select app.owner_complete_order('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac00f') as res;
reset role;
select ok(
  (select (res ->> 'ok')::boolean = true and res ->> 'status' = 'completed'
      and res ->> 'error' is null from t_zero_manual)
  and (select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-0000000ac00f')
  and (select count(*) = 0 from payments where order_id = '00000000-0000-0000-0000-0000000ac00f')
  -- ...and the MANUAL audit is equally honest: mode=manual, payment_status=not_chargeable.
  and (select ae.new_values ->> 'completion_mode' = 'manual'
          and ae.new_values ->> 'payment_status' = 'not_chargeable'
       from audit_events ae
       where ae.action = 'order.status_updated'
         and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac00f'),
  'MANUAL and AUTOMATIC AGREE on settlement: the manual path completes a zero-total order (NOT order_not_paid), creates no payment, and audits payment_status=not_chargeable');  -- 45

-- D-025 is NOT weakened for a CHARGEABLE (positive-total) order.
select ok(
  not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac010')
  and (select app.try_auto_complete_order(
      '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
      '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac010',
      'order_served', null, '00000000-0000-0000-0000-0000000acea1',
      '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-pos') ->> 'completed')::boolean = false
  and (select o.status = 'served' from orders o where o.id = '00000000-0000-0000-0000-0000000ac010'),
  'a POSITIVE-total served order with NO payment is NOT settled and STAYS SERVED (D-025 intact)');   -- 46
-- FAIL CLOSED: a negative total is unreachable by construction (layer 4 — the DB
-- CHECK), and the predicate's `< 0` branch would refuse it anyway. A missing or
-- cross-tenant order is fail-closed to `false` rather than NULL.
select throws_ok(
  $$ update public.orders set grand_total_minor = -1 where id = '00000000-0000-0000-0000-0000000ac010' $$,
  '23514', NULL,
  'the orders CHECK makes a NEGATIVE grand_total_minor unreachable (layer 4); the predicate fails closed regardless');  -- 47
-- Org B's #0AC0B1 IS genuinely settled under its OWN tenant (7777 of 7777), so this
-- is a REAL isolation test: the predicate must refuse to answer for it under Org A,
-- and must never leak its settled state across the tenant boundary (RISK R-003).
select ok(
  app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac0b1')
  and not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac0b1')
  and not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0b0', '00000000-0000-0000-0000-0000000ac00f')
  and not app.order_is_fully_settled('00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-000000000bad'),
  'FAIL CLOSED + TENANT-ISOLATED: an order settled in Org B is NOT settled when asked under Org A (and vice versa); a missing order is `false`, never NULL');  -- 48

-- =============================================================================
-- J. FAIL-SOFT — a REAL failure inside the helper, not a source-level pin  (49-51)
--    A transaction-local BEFORE INSERT trigger makes the helper's audit write fail
--    for one order. That exercises the actual `exception when others` path.
-- =============================================================================
create function pg_temp.ac_boom() returns trigger language plpgsql as $fn$
begin
  raise exception 'injected audit failure' using errcode = 'P0001';
end;
$fn$;
create trigger ac_boom_trg before insert on public.audit_events
  for each row
  when (new.new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac006')
  execute function pg_temp.ac_boom();

create temp table t_soft as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0000000ac0a0', '00000000-0000-0000-0000-0000000ac1a0',
    '00000000-0000-0000-0000-0000000acaa0', '00000000-0000-0000-0000-0000000ac006',
    'payment_recorded', null, '00000000-0000-0000-0000-0000000acea1',
    '00000000-0000-0000-0000-0000000acb11', 'cashier', '00000000-0000-0000-0000-0000000acd01', 'ac-soft') as res;

select ok(
  (select (res ->> 'completed')::boolean = false
      and res ->> 'reason' = 'auto_completion_failed'
      and res ->> 'error_code' = 'P0001'                       -- DIAGNOSABLE, not silent
   from t_soft),
  'FAIL SOFT: a genuine failure does NOT propagate (the payment/serve still succeeds) and returns a DIAGNOSABLE error_code');  -- 49
select ok(
  (select o.status = 'served' and o.revision = 1 from orders o
    where o.id = '00000000-0000-0000-0000-0000000ac006')
  and (select count(*) = 0 from audit_events
        where action = 'order.status_updated'
          and new_values ->> 'order_id' = '00000000-0000-0000-0000-0000000ac006'),
  'NOTHING PARTIAL, NO FAKE SUCCESS: the failed block rolled BOTH the status write and the audit back — the order is still served and NO completion audit event exists');  -- 50
drop trigger ac_boom_trg on public.audit_events;
-- ...and the failure is not swallowed silently: the handler captures the SQLSTATE via
-- GET STACKED DIAGNOSTICS and RAISEs a WARNING, which reaches the PostgreSQL server
-- log at the default log_min_messages (a WARNING cannot abort the transaction).
select ok(
  (select pg_get_functiondef(p.oid) ilike '%get stacked diagnostics%'
      and pg_get_functiondef(p.oid) ilike '%raise warning%'
   from pg_proc p
   where p.pronamespace = 'app'::regnamespace and p.proname = 'try_auto_complete_order'),
  'the fail-soft handler is NOT SILENT: it captures the SQLSTATE and RAISEs a WARNING to the server log');  -- 51

select * from finish();
rollback;
