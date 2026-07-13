-- ============================================================================
-- MONEY-SETTLEMENT-CONSISTENCY-001 — pgTAP: the discount freeze, the zero-value tender
-- refusal, and settlement-consistent reporting.
--
-- ONE canonical rule (app.order_is_fully_settled, shipped by ORDER-AUTO-COMPLETION-001):
--   total < 0 -> fail closed | total = 0 -> SETTLED (non-chargeable) |
--   total > 0 -> settled only when a live completed payment COVERS the current total.
--
-- Fixture: Org A / Rest A1 / Branch A1a, one POS device, a cashier + a manager + an
-- org_owner + kitchen_staff. Org B holds a real settled order (tenant isolation).
--   #CAFE001  submitted, 1000, UNPAID              -> an authorized discount still applies
--   #CAFE002  served,    1000, PAID 1000           -> the FINANCIAL SNAPSHOT IS FROZEN
--   #CAFE003  served,       0, no payment          -> NON-CHARGEABLE: zero tender refused
--   #CAFE004  submitted,  700, UNPAID              -> a normal payment is unchanged
--   #CAFE005  ready,        0, no payment          -> auto-completes with NO payment
--   #CAFE006  served,    1000, PAID 400            -> UNDER-COVERED: still owes money
--   #CAFE007  served,     500, PAID 500            -> fully covered: settled
--   #CAFE008  served,     300, payment SOFT-DELETED-> a tombstoned payment settles nothing
--   Org B #CAFE0B1 served, 900, PAID 900           -> settled in ITS OWN tenant only
--
-- Asserts: an unpaid order is still discountable; a LIVE COMPLETED payment refuses ANY
-- discount (in either direction) with NO order/payment/revision/ledger change, audited on
-- the existing order.discount_denied action with denied_reason=order_has_completed_payment
-- and projected through the SAFE allowlist; cross-tenant and role denials are preserved;
-- a NON-CHARGEABLE order refuses a payment BEFORE the receipt number is allocated and
-- before anything is written; a normal payment and its idempotent replay are untouched; a
-- zero-total order still auto-completes with NO payment; and every report/board classifier
-- now agrees with the ONE predicate (zero-total = settled, under-covered = unsettled).
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth for the writers, JWT for reads.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(27);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00000cafe0a0', 'Org A', 'msc-a', 'ILS'),
  ('00000000-0000-0000-0000-00000cafe0b0', 'Org B', 'msc-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafe0a0', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafe0b0', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', 'Branch A1a', 'UTC'),
  ('00000000-0000-0000-0000-00000cafeba0', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', 'Branch B1a', 'UTC');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', 'pos'),
  ('00000000-0000-0000-0000-00000cafed02', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000cafec01', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', 'active'),
  ('00000000-0000-0000-0000-00000cafec02', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed02', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000cafee01', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec01'),
  ('00000000-0000-0000-0000-00000cafee02', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed02', '00000000-0000-0000-0000-00000cafec02');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000cafef01', 'msc-cashier@example.test'),
  ('00000000-0000-0000-0000-00000cafef02', 'msc-manager@example.test'),
  ('00000000-0000-0000-0000-00000cafef03', 'msc-owner@example.test'),
  ('00000000-0000-0000-0000-00000cafef04', 'msc-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000cafeb11', '00000000-0000-0000-0000-00000cafef01', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', 'cashier'),
  ('00000000-0000-0000-0000-00000cafeb12', '00000000-0000-0000-0000-00000cafef02', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', 'manager'),
  ('00000000-0000-0000-0000-00000cafeb13', '00000000-0000-0000-0000-00000cafef03', '00000000-0000-0000-0000-00000cafe0a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000cafeb14', '00000000-0000-0000-0000-00000cafef04', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafef01', '00000000-0000-0000-0000-00000cafeb11', 'Cashier C.'),
  ('00000000-0000-0000-0000-00000cafea12', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafef02', '00000000-0000-0000-0000-00000cafeb12', 'Manager M.'),
  ('00000000-0000-0000-0000-00000cafea13', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafef04', '00000000-0000-0000-0000-00000cafeb14', 'Kitchen K.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafee01', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000cafec52', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafee01', '00000000-0000-0000-0000-00000cafea12', '00000000-0000-0000-0000-00000cafeb12', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000cafec53', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafee02', '00000000-0000-0000-0000-00000cafea13', '00000000-0000-0000-0000-00000cafeb14', now() + interval '1 hour');

insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-00000cafe001', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'submitted', 'ILS', 1000, 0, 0, 1000, 'msc-1', 1),
  ('00000000-0000-0000-0000-00000cafe002', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'served',    'ILS', 1000, 0, 0, 1000, 'msc-2', 1),
  ('00000000-0000-0000-0000-00000cafe003', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'served',    'ILS',    0, 0, 0,    0, 'msc-3', 1),
  ('00000000-0000-0000-0000-00000cafe004', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'submitted', 'ILS',  700, 0, 0,  700, 'msc-4', 1),
  ('00000000-0000-0000-0000-00000cafe005', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'ready',     'ILS',    0, 0, 0,    0, 'msc-5', 1),
  ('00000000-0000-0000-0000-00000cafe006', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'served',    'ILS', 1000, 0, 0, 1000, 'msc-6', 1),
  ('00000000-0000-0000-0000-00000cafe007', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'served',    'ILS',  500, 0, 0,  500, 'msc-7', 1),
  ('00000000-0000-0000-0000-00000cafe008', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'dine_in', 'served',    'ILS',  300, 0, 0,  300, 'msc-8', 1);
-- Org B (isolation): its OWN device chain + a REAL order, genuinely settled in its tenant.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000cafed0b', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafeba0', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000cafec0b', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafeba0', '00000000-0000-0000-0000-00000cafed0b', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000cafee0b', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafeba0', '00000000-0000-0000-0000-00000cafed0b', '00000000-0000-0000-0000-00000cafec0b');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000cafef0b', 'msc-orgb@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000cafeb1b', '00000000-0000-0000-0000-00000cafef0b', '00000000-0000-0000-0000-00000cafe0b0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-00000cafea1b', '00000000-0000-0000-0000-00000cafe0b0', null, null, '00000000-0000-0000-0000-00000cafef0b', '00000000-0000-0000-0000-00000cafeb1b', 'Org B Owner');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000cafec5b', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafeba0', '00000000-0000-0000-0000-00000cafee0b', '00000000-0000-0000-0000-00000cafea1b', '00000000-0000-0000-0000-00000cafeb1b', now() + interval '1 hour');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-00000cafe0b1', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafeba0', '00000000-0000-0000-0000-00000cafed0b', '00000000-0000-0000-0000-00000cafec5b', '00000000-0000-0000-0000-00000cafea1b', '00000000-0000-0000-0000-00000cafeb1b', 'dine_in', 'served', 'EUR', 900, 0, 0, 900, 'msc-b1', 1);

insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, deleted_at) values
  -- #CAFE002 fully paid -> its financial snapshot is FROZEN
  ('00000000-0000-0000-0000-00000cafefa2', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafe002', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'cash', 'completed', 1000, 1000, 0, 'ILS', 'msc-p2', null),
  -- #CAFE006 UNDER-COVERED (400 of 1000) -> still owes money
  ('00000000-0000-0000-0000-00000cafefa6', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafe006', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'cash', 'completed',  400,  400, 0, 'ILS', 'msc-p6', null),
  -- #CAFE007 fully covered
  ('00000000-0000-0000-0000-00000cafefa7', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafe007', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'cash', 'completed',  500,  500, 0, 'ILS', 'msc-p7', null),
  -- #CAFE008 SOFT-DELETED payment -> a tombstone settles nothing
  ('00000000-0000-0000-0000-00000cafefa8', '00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe1a0', '00000000-0000-0000-0000-00000cafeaa0', '00000000-0000-0000-0000-00000cafe008', '00000000-0000-0000-0000-00000cafed01', '00000000-0000-0000-0000-00000cafea11', '00000000-0000-0000-0000-00000cafeb11', 'cash', 'completed',  300,  300, 0, 'ILS', 'msc-p8', now()),
  -- Org B, settled in its own tenant
  ('00000000-0000-0000-0000-00000cafefb1', '00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe1b0', '00000000-0000-0000-0000-00000cafeba0', '00000000-0000-0000-0000-00000cafe0b1', '00000000-0000-0000-0000-00000cafed0b', '00000000-0000-0000-0000-00000cafea1b', '00000000-0000-0000-0000-00000cafeb1b', 'cash', 'completed',  900,  900, 0, 'EUR', 'msc-pb1', null);

select app.open_shift('00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafeff1',
                      '00000000-0000-0000-0000-00000cafedd1', '00000000-0000-0000-0000-00000cafed01', 'msc-sh', 0);

-- =============================================================================
-- A. THE DISCOUNT FREEZE  (1-10)
-- =============================================================================
-- (1) An UNPAID active order is still freely discountable — the guard closes a hole, it
--     does not break the feature.
--     (The call is MATERIALIZED first: Postgres may evaluate the operands of an AND in
--      any order, so a read in the same expression could race the write.)
create temp table t_ok as
  select app.apply_discount('00000000-0000-0000-0000-00000cafec52', '00000000-0000-0000-0000-00000cafe001',
                            '00000000-0000-0000-0000-00000cafed01', 'msc-d1', 'order', null,
                            'fixed', 200, 'staff meal', null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_ok)
  and (select o.discount_total_minor = 200 and o.grand_total_minor = 800
       from orders o where o.id = '00000000-0000-0000-0000-00000cafe001'),
  'an UNPAID active order still accepts an authorized discount (1000 - 200 = 800)');       -- 1

-- (2-5) A LIVE COMPLETED payment FREEZES the snapshot. Even a discount that would LOWER
--       the total is refused: post-payment, a price change is a refund, and there is none.
create temp table t_frozen as
  select app.apply_discount('00000000-0000-0000-0000-00000cafec52', '00000000-0000-0000-0000-00000cafe002',
                            '00000000-0000-0000-0000-00000cafed01', 'msc-d2', 'order', null,
                            'fixed', 100, 'late discount', null) as res;
select ok(
  (select (res ->> 'ok')::boolean = false
      and res ->> 'error'  = 'permission_denied'
      and res ->> 'detail' = 'order_has_completed_payment' from t_frozen),
  'a PAID order REFUSES a discount with the stable order_has_completed_payment domain error');  -- 2
select ok(
  (select o.discount_total_minor = 0 and o.grand_total_minor = 1000 and o.subtotal_minor = 1000
   from orders o where o.id = '00000000-0000-0000-0000-00000cafe002'),
  'the refusal wrote NO order change — the financial snapshot is untouched');                 -- 3
select ok(
  (select count(*) = 1 and max(p.amount_minor) = 1000 and bool_and(p.status = 'completed')
   from payments p where p.order_id = '00000000-0000-0000-0000-00000cafe002'),
  'the refusal wrote NO payment change');                                                     -- 4
select ok(
  (select o.revision = 1 from orders o where o.id = '00000000-0000-0000-0000-00000cafe002')
  and (select count(*) = 0 from order_operations
        where order_id = '00000000-0000-0000-0000-00000cafe002' and action = 'apply_discount'),
  'the refusal did NOT bump the revision and wrote NO idempotency-ledger row');               -- 5

-- (6) CONCURRENCY. pgTAP runs in ONE session, so a true two-session race cannot be staged
--     here (the repo proves locking the same way in rf055_concurrency_locking_test). We
--     therefore pin BOTH halves of the protection:
--       (a) the LOCK exists — apply_discount now takes `for update` on orders, which is the
--           FIRST lock record_payment takes too, so the two serialize on the same row; and
--       (b) the OUTCOME the lock protects is unreachable in either interleaving:
--           pay-then-discount is REFUSED (tests 2-5, so the total can never be re-based
--           above a frozen payment), and discount-then-pay makes the payment cover the NEW
--           total (test 6b below) — so NO interleaving can produce an under-covered PAID
--           order.
-- (6b) discount THEN pay: the payment is computed from the CURRENT total (800 after test
--      1), so it covers it exactly and the order lands SETTLED — never under-covered.
create temp table t_race as
  select app.record_payment('00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafe001',
                            '00000000-0000-0000-0000-00000cafed01', 'msc-pay-1', 'cash', 800, null) as res;
select ok(
  (select pg_get_functiondef(p.oid) ilike '%from public.orders o where o.id = p_order_id%for update%'
   from pg_proc p
   where p.pronamespace = 'app'::regnamespace and p.proname = 'apply_discount')
  and (select pg_get_functiondef(p.oid) ilike '%from public.orders o where o.id = p_order_id%for update%'
       from pg_proc p
       where p.pronamespace = 'app'::regnamespace and p.proname = 'record_payment')
  and (select (res ->> 'ok')::boolean from t_race)
  and app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe001'),
  'CONCURRENCY: both writers lock the ORDER row first, and neither interleaving can leave an UNDER-COVERED paid order');  -- 6

-- (7) CROSS-TENANT denial preserved: an Org A session cannot discount an Org B order.
select throws_ok(
  $$ select app.apply_discount('00000000-0000-0000-0000-00000cafec52', '00000000-0000-0000-0000-00000cafe0b1',
                               '00000000-0000-0000-0000-00000cafed01', 'msc-dx', 'order', null,
                               'fixed', 100, 'cross', null) $$,
  '42501', NULL,
  'CROSS-TENANT: an Org A actor cannot discount an Org B order (42501) — preserved');       -- 7

-- (8) ROLE denial preserved: kitchen_staff may not discount (audited, not raised).
select is(
  (select app.apply_discount('00000000-0000-0000-0000-00000cafec53', '00000000-0000-0000-0000-00000cafe004',
                             '00000000-0000-0000-0000-00000cafed02', 'msc-dk', 'order', null,
                             'fixed', 100, 'kitchen tries', null) ->> 'error'),
  'permission_denied',
  'ROLE: kitchen_staff is still denied a discount (permission_denied) — preserved');        -- 8

-- (9) The denial AUDIT follows the EXISTING convention: the canonical order.discount_denied
--     action (no new action key), classified under `discounts` (never Other), with the safe
--     order_code, the actor, the scope and the stable denied_reason.
select ok(
  (select count(*) = 1 from audit_events ae
    where ae.action = 'order.discount_denied'
      and ae.new_values ->> 'order_id'      = '00000000-0000-0000-0000-00000cafe002'
      and ae.new_values ->> 'denied_reason' = 'order_has_completed_payment'
      and ae.new_values ->> 'order_code'    = '#AFE002'
      and ae.new_values ->> 'attempted_action' = 'apply_discount'
      and ae.actor_employee_profile_id = '00000000-0000-0000-0000-00000cafea12'   -- the manager
      and ae.device_id                 = '00000000-0000-0000-0000-00000cafed01'
      and ae.organization_id           = '00000000-0000-0000-0000-00000cafe0a0'
      and ae.restaurant_id             = '00000000-0000-0000-0000-00000cafe1a0'
      and ae.branch_id                 = '00000000-0000-0000-0000-00000cafeaa0'
      and ae.occurred_at <= now())
  and app.audit_category('order.discount_denied') = 'discounts',
  'the denial reuses order.discount_denied (category `discounts`, never Other) with the actor, scope, safe order_code and denied_reason');  -- 9

-- (10) The SAFE projection: denied_reason is now allowlisted so the owner can see WHY, and
--      the raw identifiers are still DROPPED. Money-free (T-003).
select ok(
  (select app.audit_safe_detail('order.discount_denied', ae.new_values)
            ?& array['denied_reason', 'order_code', 'attempted_action', 'role', 'scope']
   from audit_events ae
   where ae.action = 'order.discount_denied'
     and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000cafe002')
  and (select not (app.audit_safe_detail('order.discount_denied', ae.new_values)
                     ?| array['order_id', 'resolved_membership_id', 'local_operation_id'])
       from audit_events ae
       where ae.action = 'order.discount_denied'
         and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000cafe002')
  and (select not exists (
         select 1 from audit_events ae,
           lateral jsonb_object_keys(app.audit_safe_detail('order.discount_denied', ae.new_values)) k
         where ae.action = 'order.discount_denied'
           and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-00000cafe002'
           and k like '%_minor')),
  'audit_safe_detail now EXPOSES denied_reason (the owner learns WHY) and still DROPS every identifier; money-free');  -- 10

-- =============================================================================
-- B. ZERO-VALUE TENDER IS REFUSED  (11-17)
--    #CAFE003 is served with grand_total_minor = 0.
-- =============================================================================
-- The per-branch receipt sequence is GAPLESS and monotonic (D-021): a burned number can
-- never be reclaimed. Snapshot it, so the refusal can be proven not to have consumed one.
create temp table t_receipt_before as
  select coalesce((select last_issued_value from branch_receipt_counters
                    where branch_id = '00000000-0000-0000-0000-00000cafeaa0'), 0) as v;

select throws_ok(
  $$ select app.record_payment('00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafe003',
                               '00000000-0000-0000-0000-00000cafed01', 'msc-pay-z', 'cash', 0, null) $$,
  '42501', NULL,
  'a NON-CHARGEABLE (zero-total) order REFUSES a payment (order_not_chargeable, 42501)');   -- 11
select is((select count(*)::int from payments where order_id = '00000000-0000-0000-0000-00000cafe003'), 0,
  'NO payment row was inserted for the non-chargeable order (no zero-value payment)');      -- 12
select ok(
  (select coalesce((select last_issued_value from branch_receipt_counters
                     where branch_id = '00000000-0000-0000-0000-00000cafeaa0'), 0)
          = (select v from t_receipt_before)),
  'NO receipt number was allocated or BURNED — the gapless per-branch counter did not move');  -- 13
select ok(
  (select o.status = 'served' and o.revision = 1 and o.grand_total_minor = 0
      and o.receipt_number is null
   from orders o where o.id = '00000000-0000-0000-0000-00000cafe003')
  and (select s.status = 'open' from shifts s where s.id = '00000000-0000-0000-0000-00000cafeff1')
  and (select c.status = 'active' from cash_drawer_sessions c where c.id = '00000000-0000-0000-0000-00000cafedd1')
  and (select count(*) = 0 from order_operations
        where order_id = '00000000-0000-0000-0000-00000cafe003' and action = 'record_payment'),
  'the refusal mutated NOTHING: no order change, no shift change, no cash-drawer change, no ledger row');  -- 14

-- (15) A NORMAL positive payment is completely unchanged.
create temp table t_pos as
  select app.record_payment('00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafe004',
                            '00000000-0000-0000-0000-00000cafed01', 'msc-pay-4', 'cash', 1000, null) as res;
select ok(
  (select (res ->> 'ok')::boolean = true and (res ->> 'change_due_minor')::bigint = 300 from t_pos)
  and (select count(*) = 1 and max(p.amount_minor) = 700 and max(p.tendered_minor) = 1000
          and max(p.change_minor) = 300
       from payments p where p.order_id = '00000000-0000-0000-0000-00000cafe004')
  and (select o.receipt_number is not null from orders o where o.id = '00000000-0000-0000-0000-00000cafe004'),
  'a normal positive cash payment is UNCHANGED (amount 700, tendered 1000, change 300, receipt assigned)');  -- 15

-- (16) Idempotent replay of that normal payment — unchanged.
select ok(
  (select (app.record_payment('00000000-0000-0000-0000-00000cafec51', '00000000-0000-0000-0000-00000cafe004',
                              '00000000-0000-0000-0000-00000cafed01', 'msc-pay-4', 'cash', 1000, null)
           ->> 'idempotency_replay')::boolean)
  and (select count(*) = 1 from payments where order_id = '00000000-0000-0000-0000-00000cafe004'),
  'the idempotent replay still returns the SAME result and creates NO duplicate payment');   -- 16

-- (17) A zero-total order still auto-completes — WITHOUT any payment (the whole point).
create temp table t_zero_auto as
  select app.update_order_status('00000000-0000-0000-0000-00000cafec53', '00000000-0000-0000-0000-00000cafed02',
                                 '00000000-0000-0000-0000-00000cafe005', 'served', 'msc-bump-5') as res;
select ok(
  (select (res ->> 'auto_completed')::boolean from t_zero_auto)
  and (select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-00000cafe005')
  and (select count(*) = 0 from payments where order_id = '00000000-0000-0000-0000-00000cafe005'),
  'a ZERO-TOTAL order still AUTO-COMPLETES on served, with NO record_payment and NO payment row');  -- 17

-- =============================================================================
-- C. REPORTS + BOARD NOW AGREE WITH THE ONE RULE  (18-24)
-- =============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000cafef03';   -- org_owner
create temp table t_board as
  select app.owner_active_orders('00000000-0000-0000-0000-00000cafe0a0') as res;
create temp table t_daily as
  select app.owner_daily_report('00000000-0000-0000-0000-00000cafe0a0') as res;
reset role;

-- (18) The owner's unpaid_count no longer counts an order that owes nothing.
select ok(
  (select (res -> 'today' ->> 'unpaid_count')::bigint
          = (select count(*) from orders o
              where o.organization_id = '00000000-0000-0000-0000-00000cafe0a0'
                and o.status not in ('voided', 'cancelled', 'draft')
                and o.deleted_at is null
                and not app.order_is_fully_settled(o.organization_id, o.id))
   from t_daily)
  -- ...and concretely: the zero-total orders are NOT among them.
  and app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe003')
  and app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe005'),
  'owner_daily_report.unpaid_count == the count of orders that are NOT settled — a zero-total order is never counted unpaid');  -- 18

-- (19) The board LABELS a zero-total order honestly: not_chargeable — never "paid" (no
--      payment was taken) and never "unpaid" (nothing is owed).
select is(
  (select r ->> 'payment_status'
   from t_board, lateral jsonb_array_elements(res -> 'orders') r
   where r ->> 'order_id' = '00000000-0000-0000-0000-00000cafe003'),
  'not_chargeable',
  'the board labels a ZERO-TOTAL order `not_chargeable` (never paid, never unpaid)');       -- 19
select ok(
  (select r ->> 'payment_status' = 'paid'
   from t_board, lateral jsonb_array_elements(res -> 'orders') r
   where r ->> 'order_id' = '00000000-0000-0000-0000-00000cafe007')
  and app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe007'),
  'a POSITIVE, FULLY COVERED order is settled and labelled `paid`');                        -- 20
select ok(
  (select r ->> 'payment_status' = 'unpaid'
   from t_board, lateral jsonb_array_elements(res -> 'orders') r
   where r ->> 'order_id' = '00000000-0000-0000-0000-00000cafe006')
  and not app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe006'),
  'an UNDER-COVERED order (400 of 1000) stays visibly UNSETTLED — a marker would have called it paid');  -- 21
select ok(
  not app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe008')
  and (select r ->> 'payment_status' = 'unpaid'
       from t_board, lateral jsonb_array_elements(res -> 'orders') r
       where r ->> 'order_id' = '00000000-0000-0000-0000-00000cafe008'),
  'a SOFT-DELETED (tombstoned) completed payment settles NOTHING — the order still owes');  -- 22
select ok(
  app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0b0', '00000000-0000-0000-0000-00000cafe0b1')
  and not app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000cafe0b1')
  and not app.order_is_fully_settled('00000000-0000-0000-0000-00000cafe0a0', '00000000-0000-0000-0000-00000000dead'),
  'FAIL CLOSED: an Org B order is settled only under Org B; a missing order is false, never NULL');  -- 23

-- (24) PARITY: the scalar helper and the three-branch rule the reports rely on agree for
--      EVERY order in the fixture — there is ONE definition, not two that drift.
select ok(
  not exists (
    select 1
    from orders o
    where o.deleted_at is null
      and app.order_is_fully_settled(o.organization_id, o.id) <> (
        case
          when o.grand_total_minor < 0 then false
          when o.grand_total_minor = 0 then true
          else exists (select 1 from payments p
                        where p.organization_id = o.organization_id
                          and p.order_id        = o.id
                          and p.deleted_at is null
                          and p.status          = 'completed'
                          and p.amount_minor   >= o.grand_total_minor)
        end)),
  'PARITY: the scalar helper and the three-branch rule agree for EVERY order (no competing definition)');  -- 24

-- =============================================================================
-- D. ACL — nothing was granted, nothing was opened  (25-27)
-- =============================================================================
select ok(
  not has_function_privilege('authenticated', 'app.order_is_fully_settled(uuid,uuid)', 'execute')
  and not has_function_privilege('anon',   'app.order_is_fully_settled(uuid,uuid)', 'execute')
  and not has_function_privilege('public', 'app.order_is_fully_settled(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.try_auto_complete_order(uuid,uuid,uuid,uuid,text,uuid,uuid,uuid,text,uuid,text)', 'execute'),
  'the internal settlement helpers gained NO client grant (still revoked from authenticated/anon/PUBLIC)');  -- 25
select ok(
  not has_function_privilege('anon',   'app.apply_discount(uuid,uuid,uuid,text,text,uuid,text,bigint,text,integer)', 'execute')
  and not has_function_privilege('public', 'app.apply_discount(uuid,uuid,uuid,text,text,uuid,text,bigint,text,integer)', 'execute')
  and not has_function_privilege('anon',   'app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)', 'execute')
  and not has_function_privilege('public', 'app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)', 'execute')
  and not exists (select 1 from pg_proc
                   where pronamespace = 'public'::regnamespace
                     and proname in ('apply_discount', 'record_payment')),
  'the re-created WRITERS keep NO anon/PUBLIC grant and STILL have no public wrapper (dispatcher-reachable only)');  -- 26
select ok(
  has_function_privilege('authenticated', 'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,integer,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,integer,text,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_daily_report(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.owner_daily_report(uuid,uuid,uuid)', 'execute'),
  'the re-created READ RPCs keep their authenticated-only public wrappers (anon still revoked)');  -- 27

select * from finish();
rollback;
