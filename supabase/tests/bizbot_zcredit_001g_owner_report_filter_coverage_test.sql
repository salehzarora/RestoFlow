-- ============================================================================
-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-SERVER-FILTER-COVERAGE-001 — pgTAP: the
-- owner report counts ONLY completed, non-deleted payments.
--
-- app.owner_report_range filters `p.deleted_at is null and p.status =
-- 'completed'` twice: in payment_win (collected / cash / last cash / tenders)
-- and in shift_sales (each closed shift's orders / collected / cash). This file
-- seeds, inside ONE organization, restaurant, branch and today's window:
--
--   P1 card completed 3200 · P2 cash completed 6400 (the two that count)
--   P3 card pending 100 · P4 card tendered 200 · P5 card failed 400 ·
--   P6 card voided 800 · P7 card completed 1600, soft-deleted by the deletion
--   control between two reads · P11 cash tendered 102400 · P12 cash completed
--   204800, soft-deleted at insert, the latest cash row of the day — so cash,
--   the last cash payment and the shift's cash must follow BOTH predicates too.
--
-- Every payment has its own order (payments_one_completed_per_order_uidx) and
-- its own local_operation_id, and all nine are stamped to one closed shift.
-- The amounts are distinct powers of two times 100, so any leaked row changes a
-- total by a unique amount and a bit test can name it. Scope rows outside the
-- branch: P8 on Branch A1b (12800), P9 on Restaurant A2 (25600), P10 in Org B
-- (51200).
--
-- Fixture pattern (as rf_report_004 / dashboard_owner_analytics_b): rows are
-- written by this session's own connection role; as in rf_report_004
-- (analytics_b never switches role and reads as the connection role), each
-- report is then read after `set local role authenticated`. The diag lines
-- below record the connection role and the three tables.
-- In the Supabase image the role is `postgres`, NOT a superuser, with
-- BYPASSRLS. It owns orders / payments / shifts, but row-level security on them
-- is FORCED and every policy binds `authenticated`, so ownership exempts
-- nothing: BYPASSRLS alone lets the fixture DML through. What that skips:
--   * row-level security and the write RPCs: payments are inserted directly,
--     not through app.record_payment / app.sync_push (no payment.recorded
--     audit, no receipt number, no auto-completion — O7 stays served while P7
--     is live, a state auto-completion would not leave); orders are inserted
--     directly in their final status, not through the order writers;
--   * the RF-055 shift lifecycle: the shift is inserted already closed with
--     hand-set expected / counted / variance (no open or close RPC, no shift
--     or drawer audit), its drawer stays at the default 'active' (close_shift
--     would close it), its closed_at (20:00 UTC) may lie in the future of the
--     run, and the payments are stamped to it although it was never open;
--   * the payment states themselves: every production insert into payments
--     writes status 'completed' and no migration updates or soft-deletes a
--     payment, so P3-P6, P11, the deleted P12 and the soft-delete of P7 exist
--     only through this pattern (the coverage is defensive, as rf062's is).
-- Every CHECK, unique index and foreign key still applies, and so does
-- payments_set_updated_at (the only trigger on payments); no trigger is
-- disabled and no constraint is altered.
--
-- Every report is read through the public SECURITY INVOKER wrapper
-- public.owner_report_range as `authenticated`, the caller set by the identity
-- GUC app.current_app_user_id (the existing report tests' convention).
-- Session pinned to UTC; hex-only UUIDs.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(29);

select diag(format('fixture role %s: superuser=%s, bypassrls=%s', r.rolname, r.rolsuper, r.rolbypassrls))
  from pg_roles r where r.rolname = current_user;
select diag(format('table %s: owner %s, row security enabled=%s, forced=%s',
                   c.relname, pg_get_userbyid(c.relowner), c.relrowsecurity, c.relforcerowsecurity))
  from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relname in ('orders', 'payments', 'shifts')
 order by c.relname;

-- ===== fixture: Org A (Rest A1: A1a + A1b; Rest A2: A2a) and Org B (B1a) =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0001-0000000a0000', 'SFC Org A', 'sfc-org-a', 'ILS'),
  ('00000000-0000-0000-0001-0000000b0000', 'SFC Org B', 'sfc-org-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a0000', 'SFC Rest A1', 'UTC'),
  ('00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a0000', 'SFC Rest A2', 'UTC'),
  ('00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b0000', 'SFC Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', 'SFC Branch A1a', null),
  ('00000000-0000-0000-0001-0000000a1b00', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', 'SFC Branch A1b', null),
  ('00000000-0000-0000-0001-0000000a2a00', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', 'SFC Branch A2a', null),
  ('00000000-0000-0000-0001-0000000b1a00', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', 'SFC Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0001-00000000d1b1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1b00', 'pos'),
  ('00000000-0000-0000-0001-00000000d2a1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a2a00', 'pos'),
  ('00000000-0000-0000-0001-00000000db1a', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0001-00000000c1a1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', 'active'),
  ('00000000-0000-0000-0001-00000000c1b1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1b00', '00000000-0000-0000-0001-00000000d1b1', 'active'),
  ('00000000-0000-0000-0001-00000000c2a1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a2a00', '00000000-0000-0000-0001-00000000d2a1', 'active'),
  ('00000000-0000-0000-0001-00000000cb1a', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b1a00', '00000000-0000-0000-0001-00000000db1a', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0001-00000000e1a1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000c1a1'),
  ('00000000-0000-0000-0001-00000000e1b1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1b00', '00000000-0000-0000-0001-00000000d1b1', '00000000-0000-0000-0001-00000000c1b1'),
  ('00000000-0000-0000-0001-00000000e2a1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a2a00', '00000000-0000-0000-0001-00000000d2a1', '00000000-0000-0000-0001-00000000c2a1'),
  ('00000000-0000-0000-0001-00000000eb1a', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b1a00', '00000000-0000-0000-0001-00000000db1a', '00000000-0000-0000-0001-00000000cb1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0001-00000000f0a1', 'sfc-owner-a'),
  ('00000000-0000-0000-0001-00000000f0b1', 'sfc-owner-b');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-00000000f0a1', '00000000-0000-0000-0001-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0001-0000000b0001', '00000000-0000-0000-0001-00000000f0b1', '00000000-0000-0000-0001-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0000', null, null, '00000000-0000-0000-0001-00000000f0a1', '00000000-0000-0000-0001-0000000a0001', 'SFC Owner A'),
  ('00000000-0000-0000-0001-0000000e0fb1', '00000000-0000-0000-0001-0000000b0000', null, null, '00000000-0000-0000-0001-00000000f0b1', '00000000-0000-0000-0001-0000000b0001', 'SFC Owner B');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000e1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0001-00000000aa1b', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1b00', '00000000-0000-0000-0001-00000000e1b1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0001-00000000aa2a', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a2a00', '00000000-0000-0000-0001-00000000e2a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0001-00000000ab1a', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b1a00', '00000000-0000-0000-0001-00000000eb1a', '00000000-0000-0000-0001-0000000e0fb1', '00000000-0000-0000-0001-0000000b0001', now() + interval '1 hour');

-- ---- Branch A1a, today: O1 / O2 completed and paid; O3–O7, O11 and O12 served
-- (billed, still owing unless a live completed payment covers them). Net =
-- subtotal (no items).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0001-0000000001d1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in',  'completed', 'ILS', 3200, 0, 0, 3200, 'sfc-o1', (current_date + interval '9 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d2', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'takeaway', 'completed', 'ILS', 6400, 0, 0, 6400, 'sfc-o2', (current_date + interval '9 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d3', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in',  'served',    'ILS',  100, 0, 0,  100, 'sfc-o3', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d4', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in',  'served',    'ILS',  200, 0, 0,  200, 'sfc-o4', (current_date + interval '10 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d5', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'takeaway', 'served',    'ILS',  400, 0, 0,  400, 'sfc-o5', (current_date + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d6', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in',  'served',    'ILS',  800, 0, 0,  800, 'sfc-o6', (current_date + interval '11 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d7', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'takeaway', 'served',    'ILS', 1600, 0, 0, 1600, 'sfc-o7', (current_date + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001db', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in',  'served',    'ILS', 102400, 0, 0, 102400, 'sfc-o11', (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001dc', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-00000000aa1a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'takeaway', 'served',    'ILS', 204800, 0, 0, 204800, 'sfc-o12', (current_date + interval '14 hours 30 minutes') at time zone 'UTC');

-- ---- Scope orders, today, each paid by one completed card: Branch A1b (same
-- restaurant), Branch A2a (another restaurant of Org A), Branch B1a (Org B).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0001-0000000001d8', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1b00', '00000000-0000-0000-0001-00000000d1b1', '00000000-0000-0000-0001-00000000aa1b', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in', 'completed', 'ILS', 12800, 0, 0, 12800, 'sfc-o8', (current_date + interval '12 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001d9', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a2a00', '00000000-0000-0000-0001-00000000d2a1', '00000000-0000-0000-0001-00000000aa2a', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'dine_in', 'completed', 'ILS', 25600, 0, 0, 25600, 'sfc-o9', (current_date + interval '13 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000001da', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b1a00', '00000000-0000-0000-0001-00000000db1a', '00000000-0000-0000-0001-00000000ab1a', '00000000-0000-0000-0001-0000000e0fb1', '00000000-0000-0000-0001-0000000b0001', 'dine_in', 'completed', 'EUR', 51200, 0, 0, 51200, 'sfc-o10', (current_date + interval '13 hours 30 minutes') at time zone 'UTC');

-- ---- One CLOSED shift on A1a today (08:00 -> 20:00) with its drawer. The close
-- values are hand-set: expected = float 5000 + the live completed cash P2 6400
-- = 11400. app.close_shift's own cash sum has no deleted_at filter, so on this
-- fixture it would also count the deleted P12; no production path soft-deletes
-- a payment, so the two agree in production. SFC-22 reads the stored values.
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, closed_by_employee_profile_id, status, expected_total_minor, counted_total_minor, variance_minor, opened_at, closed_at, local_operation_id) values
  ('00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-0000000e0fa1', 'closed', 11400, 11400, 0, (current_date + interval '8 hours') at time zone 'UTC', (current_date + interval '20 hours') at time zone 'UTC', 'sfc-st1');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('00000000-0000-0000-0001-00000000cd51', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-0000000e0fa1', 5000, 'sfc-cds1');

-- ---- Branch A1a payments P1–P7 and P11, all stamped to the closed shift and its
-- drawer. Every row is tendered = amount, change 0 (record_payment's non-cash
-- shape; the cash rows simply had exact cash).
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0001-0000000003b1', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d1', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'card', 'completed', 3200, 3200, 0, 'ILS', 'sfc-p1', (current_date + interval '9 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b2', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d2', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'cash', 'completed', 6400, 6400, 0, 'ILS', 'sfc-p2', (current_date + interval '9 hours 35 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b3', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d3', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'card', 'pending',    100,  100, 0, 'ILS', 'sfc-p3', (current_date + interval '10 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b4', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d4', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'card', 'tendered',   200,  200, 0, 'ILS', 'sfc-p4', (current_date + interval '10 hours 35 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b5', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d5', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'card', 'failed',     400,  400, 0, 'ILS', 'sfc-p5', (current_date + interval '11 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b6', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d6', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'card', 'voided',     800,  800, 0, 'ILS', 'sfc-p6', (current_date + interval '11 hours 35 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b7', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001d7', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'card', 'completed', 1600, 1600, 0, 'ILS', 'sfc-p7', (current_date + interval '12 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003bb', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001db', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'cash', 'tendered', 102400, 102400, 0, 'ILS', 'sfc-p11', (current_date + interval '14 hours 5 minutes') at time zone 'UTC');

-- ---- P12: a completed cash payment soft-deleted at insert, the latest cash row
-- of the day (so a lost deleted_at filter would make it cash and the last cash).
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at, deleted_at) values
  ('00000000-0000-0000-0001-0000000003bc', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', '00000000-0000-0000-0001-0000000001dc', '00000000-0000-0000-0001-00000000d1a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', '00000000-0000-0000-0001-000000005f01', '00000000-0000-0000-0001-00000000cd51', 'cash', 'completed', 204800, 204800, 0, 'ILS', 'sfc-p12', (current_date + interval '14 hours 35 minutes') at time zone 'UTC', (current_date + interval '14 hours 45 minutes') at time zone 'UTC');

-- ---- Scope payments: one completed card each, not shift-stamped.
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0001-0000000003b8', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1b00', '00000000-0000-0000-0001-0000000001d8', '00000000-0000-0000-0001-00000000d1b1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'card', 'completed', 12800, 12800, 0, 'ILS', 'sfc-p8', (current_date + interval '12 hours 35 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003b9', '00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a2000', '00000000-0000-0000-0001-0000000a2a00', '00000000-0000-0000-0001-0000000001d9', '00000000-0000-0000-0001-00000000d2a1', '00000000-0000-0000-0001-0000000e0fa1', '00000000-0000-0000-0001-0000000a0001', 'card', 'completed', 25600, 25600, 0, 'ILS', 'sfc-p9', (current_date + interval '13 hours 5 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0001-0000000003ba', '00000000-0000-0000-0001-0000000b0000', '00000000-0000-0000-0001-0000000b1000', '00000000-0000-0000-0001-0000000b1a00', '00000000-0000-0000-0001-0000000001da', '00000000-0000-0000-0001-00000000db1a', '00000000-0000-0000-0001-0000000e0fb1', '00000000-0000-0000-0001-0000000b0001', 'card', 'completed', 51200, 51200, 0, 'EUR', 'sfc-p10', (current_date + interval '13 hours 35 minutes') at time zone 'UTC');

-- ===== (1-5) fixture sanity: the exclusion can only come from the payment rows =====
select is(
  (select array_agg(p.method || ':' || p.status || case when p.deleted_at is null then '' else ':deleted' end
                    order by p.amount_minor)
     from payments p where p.branch_id = '00000000-0000-0000-0001-0000000a1a00'),
  array['card:pending', 'card:tendered', 'card:failed', 'card:voided', 'card:completed', 'card:completed',
        'cash:completed', 'cash:tendered', 'cash:completed:deleted'],
  'SFC-01 Branch A1a holds P3 pending / P4 tendered / P5 failed / P6 voided / P7, P1 completed card / P2 completed cash / P11 tendered cash / P12 deleted completed cash');
select is(
  (select count(*)::int
     from payments p
     join orders o on o.organization_id = p.organization_id and o.id = p.order_id
    where p.branch_id = '00000000-0000-0000-0001-0000000a1a00'
      and (p.created_at at time zone 'UTC')::date = current_date
      and o.deleted_at is null
      and o.status not in ('cancelled', 'voided', 'draft')),
  9,
  'SFC-02 all nine A1a payments are inside today''s branch-local window on live billed orders');
select ok(
  (select count(*) = 12 and count(distinct amount_minor) = 12 and count(distinct local_operation_id) = 12
     from payments
    where organization_id in ('00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000b0000'))
  and (select count(*) = 12 and count(distinct grand_total_minor) = 12 and count(distinct local_operation_id) = 12
     from orders
    where organization_id in ('00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000b0000')),
  'SFC-03 the twelve payments and twelve orders have pairwise-distinct amounts and operation identities');
select is(
  (select count(*)::int from payments
    where branch_id = '00000000-0000-0000-0001-0000000a1a00'
      and shift_id = '00000000-0000-0000-0001-000000005f01'
      and cash_drawer_session_id = '00000000-0000-0000-0001-00000000cd51'),
  9,
  'SFC-04 all nine A1a payments are stamped to the closed shift and its drawer');
select is(
  (select array_agg(app.order_is_fully_settled('00000000-0000-0000-0001-0000000a0000', o.id) order by o.grand_total_minor)
     from orders o where o.branch_id = '00000000-0000-0000-0001-0000000a1a00'),
  array[false, false, false, false, true, true, true, false, false],
  'SFC-05 before the deletion only O7 (live P7), O1 and O2 are settled; O3-O6, O11 and O12 (non-completed or deleted payments) still owe');

-- ===== the deletion control, read 1: P7 still live ==========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0001-00000000f0a1';
create temp table t_pre as select public.owner_report_range('00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', 'today') as res;
reset role;

-- ===== (6-9) before the deletion: the completed P7 counts ===================
select is((select (res->'current'->>'collected_minor')::bigint from t_pre), 11200::bigint,
  'SFC-06 before the deletion collected = 11200 (P1 3200 + P2 6400 + live P7 1600)');
select is((select res->'current'->'tenders' from t_pre),
  '[{"method": "card", "count": 2, "total_minor": 4800}, {"method": "cash", "count": 1, "total_minor": 6400}]'::jsonb,
  'SFC-07 before the deletion tenders = card 2 / 4800 (P1 + P7) and cash 1 / 6400 (P2)');
select is((select (res->'current'->>'unpaid_count')::int from t_pre), 6,
  'SFC-08 before the deletion unpaid = 6 (O3-O6, O11 and O12)');
select ok(
  (select (res->'shift_cash'->'last_closed_shift'->>'order_count')::int = 3
      and (res->'shift_cash'->'last_closed_shift'->>'collected_minor')::bigint = 11200
      and (res->'shift_cash'->'last_closed_shift'->>'cash_sales_minor')::bigint = 6400 from t_pre),
  'SFC-09 before the deletion the closed shift has 3 orders, collected 11200, cash 6400 (P1, P2, P7)');

-- ===== the deletion control: soft-delete the SAME completed card row =========
update payments set deleted_at = now()
 where organization_id = '00000000-0000-0000-0001-0000000a0000' and id = '00000000-0000-0000-0001-0000000003b7';

-- ===== (10-11) the fixture after the deletion ===============================
select ok(
  (select method = 'card' and status = 'completed' and amount_minor = 1600 and deleted_at is not null
          and order_id = '00000000-0000-0000-0001-0000000001d7'
     from payments where id = '00000000-0000-0000-0001-0000000003b7'),
  'SFC-10 P7 is now a completed card with deleted_at set; method, status, amount and order are unchanged');
select is(
  (select array_agg(app.order_is_fully_settled('00000000-0000-0000-0001-0000000a0000', o.id) order by o.grand_total_minor)
     from orders o where o.branch_id = '00000000-0000-0000-0001-0000000a1a00'),
  array[false, false, false, false, false, true, true, false, false],
  'SFC-11 after the deletion only O1 and O2 are settled (a deleted payment settles nothing)');

-- ===== read 2 (Branch A1a), the scope reads, and Org B's own read ============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0001-00000000f0a1';
create temp table t_post as select public.owner_report_range('00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', '00000000-0000-0000-0001-0000000a1a00', 'today') as res;
create temp table t_rest as select public.owner_report_range('00000000-0000-0000-0001-0000000a0000', '00000000-0000-0000-0001-0000000a1000', null, 'today') as res;
create temp table t_org  as select public.owner_report_range('00000000-0000-0000-0001-0000000a0000', null, null, 'today') as res;
set local app.current_app_user_id = '00000000-0000-0000-0001-00000000f0b1';
create temp table t_orgb as select public.owner_report_range('00000000-0000-0000-0001-0000000b0000', null, null, 'today') as res;
reset role;

-- ===== (12-23) Branch A1a after the deletion =================================
select ok(
  (select (res->>'ok')::boolean and res->>'entity' = 'owner_report_range' and res->>'range' = 'today'
      and res->>'currency_code' = 'ILS' from t_post),
  'SFC-12 the public wrapper answers ok / owner_report_range / today / ILS');
select is((select (res->'current'->>'collected_minor')::bigint from t_post), 9600::bigint,
  'SFC-13 collected = 9600: only P1 card 3200 + P2 cash 6400');
select is((select (res->'current'->>'cash_minor')::bigint from t_post), 6400::bigint,
  'SFC-14 cash = 6400: only the completed cash P2, never the tendered P11 or the deleted P12');
select is((select res->'current'->'tenders' from t_post),
  '[{"method": "card", "count": 1, "total_minor": 3200}, {"method": "cash", "count": 1, "total_minor": 6400}]'::jsonb,
  'SFC-15 tenders = card 1 / 3200 and cash 1 / 6400, nothing else');
select is(
  (select count(*)::int from t_post, jsonb_array_elements(res->'current'->'tenders') t where t->>'method' = 'card'),
  1,
  'SFC-16 Card appears exactly once in tenders');
-- Each excluded row is a distinct power of two times 100 (P3 1, P4 2, P5 4,
-- P6 8, P7 16, P11 1024, P12 2048 in units of 100; mask 3103), so a leaked row
-- sets its bit.
select ok(
  (select ((res->'current'->>'collected_minor')::bigint / 100) & 3103 = 0
      and ((res->'current'->>'cash_minor')::bigint / 100) & 3103 = 0
      and not exists (select 1 from jsonb_array_elements(res->'current'->'tenders') t
                       where ((t->>'total_minor')::bigint / 100) & 3103 <> 0)
     from t_post),
  'SFC-17 no pending / tendered / failed / voided / deleted amount appears in collected, cash or any tender');
select is((select (res->'current'->>'last_cash_payment_minor')::bigint from t_post), 6400::bigint,
  'SFC-18 last cash payment = 6400 (the completed P2, not the later tendered P11 or deleted P12)');
select ok(
  (select (b.res->'current'->>'order_count')::int = 9
      and (b.res->'current'->>'completed_count')::int = 2
      and (b.res->'current'->>'open_count')::int = 7
      and (b.res->'current'->>'net_minor')::bigint = 319900
      and b.res->'current'->'order_count'     = a.res->'current'->'order_count'
      and b.res->'current'->'completed_count' = a.res->'current'->'completed_count'
      and b.res->'current'->'net_minor'       = a.res->'current'->'net_minor'
     from t_pre a, t_post b),
  'SFC-19 order metrics follow the orders: 9 billed / 2 completed / 7 open / net 319900, unchanged by the deletion');
select ok(
  (select (res->'current'->>'unpaid_count')::int = 7
      and (res->'current'->>'unpaid_count')::int =
          (select count(*)::int from orders o
            where o.branch_id = '00000000-0000-0000-0001-0000000a1a00'
              and o.status not in ('voided', 'cancelled', 'draft')
              and not app.order_is_fully_settled(o.organization_id, o.id))
     from t_post),
  'SFC-20 unpaid = 7 = the billed A1a orders app.order_is_fully_settled does not settle (O3-O7, O11, O12)');
select ok(
  (select (res->'shift_cash'->'last_closed_shift'->>'order_count')::int = 2
      and (res->'shift_cash'->'last_closed_shift'->>'collected_minor')::bigint = 9600
      and (res->'shift_cash'->'last_closed_shift'->>'cash_sales_minor')::bigint = 6400
      and ((res->'shift_cash'->'last_closed_shift'->>'collected_minor')::bigint / 100) & 3103 = 0
      and ((res->'shift_cash'->'last_closed_shift'->>'cash_sales_minor')::bigint / 100) & 3103 = 0
     from t_post),
  'SFC-21 the closed shift breakdown: 2 orders, collected 9600, cash 6400; no excluded amount');
select ok(
  (select (res->'shift_cash'->>'closed_shift_count')::int = 1
      and (res->'shift_cash'->>'expected_cash_minor')::bigint = 11400
      and (res->'shift_cash'->>'counted_cash_minor')::bigint = 11400
      and (res->'shift_cash'->>'cash_variance_minor')::bigint = 0
      and (res->'shift_cash'->'last_closed_shift'->>'opening_float_minor')::bigint = 5000
      and jsonb_array_length(res->'shift_cash'->'recent_closed_shifts') = 1
      and res->'shift_cash'->'recent_closed_shifts'->0 = res->'shift_cash'->'last_closed_shift'
     from t_post),
  'SFC-22 the stored close values stand: 1 closed shift, expected = counted = 11400, variance 0, float 5000');
select ok(
  (select (a.res->'current'->>'collected_minor')::bigint - (b.res->'current'->>'collected_minor')::bigint = 1600
      and (a.res->'shift_cash'->'last_closed_shift'->>'collected_minor')::bigint
          - (b.res->'shift_cash'->'last_closed_shift'->>'collected_minor')::bigint = 1600
      and (a.res->'current'->>'unpaid_count')::int + 1 = (b.res->'current'->>'unpaid_count')::int
     from t_pre a, t_post b),
  'SFC-23 the deletion control: soft-deleting P7 removes exactly its 1600 from collected and the shift, and O7 turns unpaid');

-- ===== (24-27) scope: branch / restaurant / organization ====================
select ok(
  (select (res->'current'->>'collected_minor')::bigint = 22400
      and (res->'current'->>'cash_minor')::bigint = 6400
      and res->'current'->'tenders' = '[{"method": "card", "count": 2, "total_minor": 16000}, {"method": "cash", "count": 1, "total_minor": 6400}]'::jsonb
      and (res->'current'->>'order_count')::int = 10
      and (res->'current'->>'unpaid_count')::int = 7
     from t_rest),
  'SFC-24 Restaurant A1 (A1a + A1b): collected 22400, cash 6400, card 2 / 16000, 10 orders, 7 unpaid');
select ok(
  (select (res->'current'->>'collected_minor')::bigint = 48000
      and (res->'current'->>'cash_minor')::bigint = 6400
      and res->'current'->'tenders' = '[{"method": "card", "count": 3, "total_minor": 41600}, {"method": "cash", "count": 1, "total_minor": 6400}]'::jsonb
      and (res->'current'->>'order_count')::int = 11
      and (res->'current'->>'net_minor')::bigint = 358300
     from t_org),
  'SFC-25 Organization A (all branches): collected 48000, card 3 / 41600, 11 orders, net 358300');
-- Scope rows are 128 (P8, Branch A1b), 256 (P9, Restaurant A2) and 512 (P10,
-- Org B) in units of 100.
select ok(
  (select ((p.res->'current'->>'collected_minor')::bigint / 100) & 896 = 0
      and ((r.res->'current'->>'collected_minor')::bigint / 100) & 896 = 128
      and ((o.res->'current'->>'collected_minor')::bigint / 100) & 896 = 384
     from t_post p, t_rest r, t_org o),
  'SFC-26 the branch read holds no other branch, the restaurant read adds only A1b, the org read adds A2a and never Org B');
select ok(
  (select (res->>'ok')::boolean and res->>'currency_code' = 'EUR'
      and (res->'current'->>'collected_minor')::bigint = 51200
      and res->'current'->'tenders' = '[{"method": "card", "count": 1, "total_minor": 51200}]'::jsonb
     from t_orgb),
  'SFC-27 Org B''s own read counts its completed card P10 (51200): a real payment kept out of Org A by scope');

-- ===== (28-29) cross-organization reads are refused ==========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0001-00000000f0a1';
select throws_ok(
  $$ select public.owner_report_range('00000000-0000-0000-0001-0000000b0000', null, null, 'today') $$,
  '42501', NULL, 'SFC-28 an Org A owner cannot read the Org B report (42501)');
set local app.current_app_user_id = '00000000-0000-0000-0001-00000000f0b1';
select throws_ok(
  $$ select public.owner_report_range('00000000-0000-0000-0001-0000000a0000', null, null, 'today') $$,
  '42501', NULL, 'SFC-29 an Org B owner cannot read the Org A report (42501)');
reset role;

select * from finish();
rollback;
