-- ============================================================================
-- ACTIVE-ORDERS-002 — pgTAP: operational QUEUES + server-side SORT + keyset
-- pagination for app.owner_active_orders.
--
-- Fixture: Org A (Rest A1: Branch A1a + Branch A1b) + Org B (isolation).
-- Branch A1a — one order at EVERY canonical active state, plus all three terminal
-- states, plus a same-timestamp pair to prove stable tie-breaking:
--   #03A001  10:00  submitted  unpaid
--   #03A002  11:00  accepted   PAID
--   #03A003  12:00  preparing  unpaid
--   #03A004  13:00  ready      PAID
--   #03A005  14:00  served     unpaid          <- awaiting_close, UNPAID
--   #03A006  14:00  served     PAID            <- SAME instant as #03A005 (tie-break)
--   #03A007  15:00  completed  PAID            -> TERMINAL, never on the board
--   #03A008  16:00  cancelled  unpaid          -> TERMINAL
--   #03A009  17:00  voided     unpaid          -> TERMINAL
-- Branch A1b: #03B001 12:30 preparing (sibling-branch denial / branch filter)
-- Org B:      #03C001 12:00 preparing (cross-tenant isolation)
--
-- Actors: f001 org_owner(A) | f002 manager(A, Branch A1a ONLY)
--         f003 kitchen_staff(A) | f005 org_owner(B)
--
-- Asserts: in_progress = submitted/accepted/preparing/ready and EXCLUDES served;
-- awaiting_close = served ONLY; all_active = all five; terminal never appears;
-- paid/unpaid stay a SEPARATE axis (an unpaid served order is awaiting_close);
-- newest = created_at DESC,id DESC and oldest = ASC,ASC (SERVER-side); equal
-- timestamps paginate stably in BOTH directions with no duplicate and no gap; a
-- cursor minted under one sort is REJECTED under the other; unknown queue/sort
-- rejected; a status outside the selected queue rejected; the page cap is kept;
-- `matching` is the FULL filtered count (not the page) and `summary` is
-- SCOPE-wide (not the queue, not the page); cross-tenant + sibling-branch denied;
-- kitchen_staff denied; only safe fields; and the ACL (anon/PUBLIC revoked).
-- Session pinned to UTC; hex-only UUIDs; GUC-free (identity GUC only).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(30);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'aq-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'aq-b', 'EUR');
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
  ('00000000-0000-0000-0000-00000000f001', 'aq-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f002', 'aq-manager-a1a@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'aq-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'aq-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0002', '00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001', 'Amira K.'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005', 'Bianca O.');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');

-- ---- Orders (see the header table). ----------------------------------------
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, notes, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000003a001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'submitted', 'ILS', 100, 0, 0, 100, 'PRIVATE-NOTE', 'aq-1', (current_date + interval '10 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'accepted',  'ILS', 200, 0, 0, 200, null, 'aq-2', (current_date + interval '11 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'preparing', 'ILS', 300, 0, 0, 300, null, 'aq-3', (current_date + interval '12 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'ready',     'ILS', 400, 0, 0, 400, null, 'aq-4', (current_date + interval '13 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 500, 0, 0, 500, null, 'aq-5', (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 600, 0, 0, 600, null, 'aq-6', (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 700, 0, 0, 700, null, 'aq-7', (current_date + interval '15 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a008', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'cancelled', 'ILS', 800, 0, 0, 800, null, 'aq-8', (current_date + interval '16 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003a009', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'voided',    'ILS', 900, 0, 0, 900, null, 'aq-9', (current_date + interval '17 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003b001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000d002', '00000000-0000-0000-0000-0000000b0002', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'preparing', 'ILS', 250, 0, 0, 250, null, 'aq-b1', (current_date + interval '12 hours 30 minutes') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000003c001', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'preparing', 'EUR', 777, 0, 0, 777, null, 'aq-c1', (current_date + interval '12 hours') at time zone 'UTC');

-- ---- Completed cash payments: #03A002, #03A004, #03A006, #03A007. ------------
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-00000005a002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000003a002', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 200, 200, 0, 'ILS', 'aq-p2'),
  ('00000000-0000-0000-0000-00000005a004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000003a004', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 400, 400, 0, 'ILS', 'aq-p4'),
  ('00000000-0000-0000-0000-00000005a006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000003a006', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 600, 600, 0, 'ILS', 'aq-p6'),
  ('00000000-0000-0000-0000-00000005a007', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000003a007', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'cash', 'completed', 700, 700, 0, 'ILS', 'aq-p7');

-- ===== calls (org_owner, Branch A1a) =========================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_prog as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_queue => 'in_progress') as res;
create temp table t_wait as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_queue => 'awaiting_close') as res;
create temp table t_all  as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_queue => 'all_active') as res;
create temp table t_dflt as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00') as res;
reset role;

-- ===== (1-5) IN PROGRESS = submitted/accepted/preparing/ready, EXCLUDES served =
select is((select jsonb_array_length(res->'orders') from t_prog), 4,
  'in_progress returns exactly the 4 preparation-stage orders');
select ok(
  (select bool_and(o->>'status' in ('submitted','accepted','preparing','ready'))
   from t_prog, lateral jsonb_array_elements(res->'orders') o),
  'in_progress includes submitted + accepted + preparing + ready (and nothing else)');
select ok(
  (select count(*) = 4 from t_prog, lateral jsonb_array_elements(res->'orders') o
   where o->>'status' in ('submitted','accepted','preparing','ready')),
  'each of the four preparation stages is represented');
select ok(
  (select not exists (
     select 1 from t_prog, lateral jsonb_array_elements(res->'orders') o
     where o->>'status' = 'served')),
  'in_progress EXCLUDES served (the awaiting-close backlog never buries live work)');
select is((select res->>'queue' from t_prog), 'in_progress',
  'the response echoes the queue it served');

-- ===== (6-8) AWAITING CLOSE = served ONLY ====================================
select is((select jsonb_array_length(res->'orders') from t_wait), 2,
  'awaiting_close returns exactly the 2 served orders');
select ok(
  (select bool_and(o->>'status' = 'served')
   from t_wait, lateral jsonb_array_elements(res->'orders') o),
  'awaiting_close contains ONLY served orders');
select ok(
  (select not exists (
     select 1 from t_wait, lateral jsonb_array_elements(res->'orders') o
     where o->>'status' in ('submitted','accepted','preparing','ready','completed','cancelled','voided'))),
  'awaiting_close excludes every other status');

-- ===== (9-10) ALL ACTIVE = the five canonical states; TERMINAL never appears ==
select is((select jsonb_array_length(res->'orders') from t_all), 6,
  'all_active returns all six active orders (4 in progress + 2 served)');
select ok(
  (select not exists (
     select 1 from t_all, lateral jsonb_array_elements(res->'orders') o
     where o->>'status' in ('completed','cancelled','voided','draft')))
  and (select not exists (
     select 1 from t_prog, lateral jsonb_array_elements(res->'orders') o
     where o->>'status' in ('completed','cancelled','voided')))
  and (select not exists (
     select 1 from t_wait, lateral jsonb_array_elements(res->'orders') o
     where o->>'status' in ('completed','cancelled','voided'))),
  'TERMINAL orders (completed/cancelled/voided) never appear in ANY queue');

-- ===== (11) payment stays a SEPARATE axis: an UNPAID served order is awaiting =
select ok(
  (select count(*) = 2 from t_wait, lateral jsonb_array_elements(res->'orders') o
    where o->>'status' = 'served')
  and (select count(*) = 1 from t_wait, lateral jsonb_array_elements(res->'orders') o
    where o->>'order_code' = '#03A005' and o->>'payment_status' = 'unpaid')
  and (select count(*) = 1 from t_wait, lateral jsonb_array_elements(res->'orders') o
    where o->>'order_code' = '#03A006' and o->>'payment_status' = 'paid'),
  'payment is a SEPARATE axis: BOTH the paid and the UNPAID served order sit in awaiting_close (D-025)');

-- ===== (12-14) SORT is server-side: newest is the DEFAULT ====================
select is((select res->>'sort' from t_dflt), 'newest',
  'the DEFAULT sort is NEWEST first');
select ok(
  (select res->'orders'->0->>'order_code' = '#03A006'
      and res->'orders'->1->>'order_code' = '#03A005'
      and res->'orders'->5->>'order_code' = '#03A001' from t_all),
  'newest: created_at DESC, id DESC (the same-instant pair orders #03A006 before #03A005)');
select ok(
  (select r->'orders'->0->>'order_code' = '#03A001'
      and r->'orders'->4->>'order_code' = '#03A005'
      and r->'orders'->5->>'order_code' = '#03A006'
   from app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_sort => 'oldest') as r),
  'oldest: created_at ASC, id ASC (the same-instant pair reverses to #03A005 before #03A006)');

-- ===== (15-17) KEYSET pagination: stable, no duplicate, no gap ===============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_p1 as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, 2, 'all_active', 'newest', null) as res;
create temp table t_p2 as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, 2, 'all_active', 'newest', (select res->>'next_cursor' from t_p1)) as res;
create temp table t_p3 as select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, 2, 'all_active', 'newest', (select res->>'next_cursor' from t_p2)) as res;
reset role;

select ok(
  (select (res->>'has_more')::boolean = true
      and res->'orders'->0->>'order_code' = '#03A006'
      and res->'orders'->1->>'order_code' = '#03A005'
      and res->>'next_cursor' like 'newest|%' from t_p1),
  'page 1 (newest, limit 2): the two newest, has_more, and a SORT-TAGGED cursor');
select ok(
  (select res->'orders'->0->>'order_code' = '#03A004'
      and res->'orders'->1->>'order_code' = '#03A003' from t_p2)
  and (select res->'orders'->0->>'order_code' = '#03A002'
      and res->'orders'->1->>'order_code' = '#03A001' from t_p3),
  'pages 2 and 3 continue with NO duplicate and NO skipped row (the same-instant pair split cleanly across the boundary)');
select ok(
  (select (res->>'has_more')::boolean = false and res->>'next_cursor' is null from t_p3),
  'the last page reports has_more = false and no cursor');

-- ===== (18) a cursor is REJECTED under the OTHER sort direction ==============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select throws_ok(
  format($$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', null, null, null, null, 2, 'all_active', 'oldest', %L) $$,
         (select res->>'next_cursor' from t_p1)),
  '22023', NULL, 'a cursor minted under NEWEST is REJECTED when replayed under OLDEST (never a silently mis-paged board)');
reset role;

-- ===== (19-22) validated controls ===========================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_queue => 'bogus') $$,
  '22023', NULL, 'an unknown QUEUE is rejected (22023)');
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_sort => 'priority') $$,
  '22023', NULL, 'an unknown SORT is rejected (22023) — there is no invented priority ranking');
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', 'served', null, null, null, 100, 'in_progress') $$,
  '22023', NULL, 'a status OUTSIDE the selected queue is rejected (served is not in in_progress)');
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', 'completed') $$,
  '22023', NULL, 'a TERMINAL status filter is still rejected (22023)');
reset role;

-- ===== (23) a status INSIDE the queue is accepted ============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select jsonb_array_length(app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', 'ready', null, null, null, 100, 'in_progress')->'orders')),
  1, 'a status INSIDE the queue (ready in in_progress) is accepted');
reset role;

-- ===== (24-25) page-size CAP; `matching` is the FULL filtered count ==========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select ok(
  (select (app.owner_active_orders('00000000-0000-0000-0000-0000000a0000',null,null,null,null,null,null,999)->>'limit')::int = 200)
  and (select (app.owner_active_orders('00000000-0000-0000-0000-0000000a0000',null,null,null,null,null,null,0)->>'limit')::int = 1),
  'the page-size CAP is retained (999 -> 200, 0 -> 1)');
reset role;
select ok(
  (select (res->>'count')::int = 2 and (res->>'matching')::int = 6
      and (res->>'truncated')::boolean = true from t_p1),
  '`matching` is the FULL filtered count (6), NOT the loaded page (2) — the truncation message can be honest');

-- ===== (26) the SUMMARY is SCOPE-wide, not the queue and not the page ========
select ok(
  (select (res->'summary'->>'total')::int = 6
      and (res->'summary'->>'in_progress')::int = 4
      and (res->'summary'->>'awaiting_close')::int = 2
      and (res->'summary'->>'unpaid')::int = 3          -- #03A001, #03A003, #03A005
      and (res->'summary'->'by_status'->>'ready')::int = 1 from t_prog)
  and (select (res->'summary'->>'total')::int = 6
      and (res->'summary'->>'in_progress')::int = 4
      and (res->'summary'->>'awaiting_close')::int = 2 from t_wait),
  'the SUMMARY (total/in_progress/awaiting_close/unpaid) is SCOPE-wide and IDENTICAL in every queue — the cards never move when the operator switches queue');

-- ===== (27-28) tenant + branch isolation ====================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';   -- Org A owner
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000b0000', p_queue => 'in_progress') $$,
  '42501', NULL, 'cross-tenant: an Org A owner cannot read Org B queues (42501)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f002';   -- manager of A1a ONLY
select throws_ok(
  $$ select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1b00', p_queue => 'in_progress') $$,
  '42501', NULL, 'sibling-branch: a Branch A1a manager cannot read Branch A1b (42501)');
reset role;

-- ===== (29) kitchen_staff still DENIED; safe fields only =====================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is(
  (select app.owner_active_orders('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00', p_queue => 'awaiting_close')->>'error'),
  'permission_denied', 'kitchen_staff is still DENIED (the board carries order totals)');
reset role;

-- ===== (30) ACL: the widened signature keeps authenticated-only + no anon =====
select ok(
  (select not exists (
     select 1 from t_all, lateral jsonb_array_elements(res->'orders') o,
          lateral jsonb_object_keys(o) k
     where k in ('device_id','pin_session_id','organization_id','restaurant_id','branch_id',
                 'resolved_membership_id','opened_by_employee_profile_id','table_id',
                 'notes','metadata','local_operation_id','due_at','promised_at','late','priority')))
  and not has_function_privilege('anon',   'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int,text,text,text)', 'execute')
  and not has_function_privilege('public', 'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int,text,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int,text,text,text)', 'execute')
  and not has_function_privilege('anon', 'app.owner_active_orders(uuid,uuid,uuid,text,text,text,text,int,text,text,text)', 'execute'),
  'safe fields only (no ids/notes/metadata, and NO invented due/late/priority key) and the widened RPC stays authenticated-only (anon + PUBLIC revoked)');

select * from finish();
rollback;
