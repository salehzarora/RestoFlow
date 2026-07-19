-- ============================================================================
-- KITCHEN-MODE-001A — pgTAP: auto-completion in BOTH workflow modes.
--
-- Branch K stays in the default 'kds' mode; Branch P is flipped to
-- 'printer_only' by PRIVILEGED SQL only (no setter exists — the dormancy is
-- proven in kitchen_mode_001a_foundation_test.sql).
--
--   KDS-MODE REGRESSION (must be byte-equivalent to pre-KITCHEN-MODE):
--     K1 submitted 1000, pay in full  -> payment ok, order STAYS submitted
--        (settlement alone NEVER completes a kds order — THE dormancy pin)
--     K2 served    800, pay in full  -> AUTO-COMPLETES; audit old status
--        'served' and NO kitchen_workflow_mode key (byte-compatible payload)
--     K3 served    400 + ACTIVE round, pay -> rounds gate HOLDS it open
--
--   PRINTER-ONLY (dormant; reachable only via the privileged fixture):
--     P1..P5 submitted/accepted/preparing/ready/served, pay in full
--        -> ALL auto-complete on settlement alone; audit names the REAL
--           source status + kitchen_workflow_mode=printer_only
--     P6 submitted UNPAID     -> stays; direct helper => not_fully_paid
--     P7 UNDER-COVERED (completed 400 of 1000) -> stays submitted
--     P8/P9/P10 completed/voided/cancelled -> TERMINAL, never revived
--     P11 served + ACTIVE round, pay -> completes (rounds gate skipped:
--         kitchen progression has no writer in printer-only mode)
--     idempotent re-run on P1; cross-tenant helper call fails closed;
--     NO payment is ever fabricated; ready_at stays NULL and the POS ready
--     feed stays EMPTY (printer-only orders never alert).
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth (GUC-free).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(36);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0001a2000a00', 'Org A', 'km1a2-a', 'ILS'),
  ('00000000-0000-0000-0000-0001a2000b00', 'Org B', 'km1a2-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a00', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0001a2000b10', '00000000-0000-0000-0000-0001a2000b00', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', 'Branch P (printer-only)'),
  ('00000000-0000-0000-0000-0001a2000b1a', '00000000-0000-0000-0000-0001a2000b00', '00000000-0000-0000-0000-0001a2000b10', 'Branch B1a');
-- the ONLY write path in this phase: privileged SQL (see foundation suite).
update branches set kitchen_workflow_mode = 'printer_only'
  where id in ('00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000b1a');

insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001a200d001', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', 'pos'),
  ('00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001a200c001', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a200d001', 'active'),
  ('00000000-0000-0000-0000-0001a200c002', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0001a200e001', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a200d001', '00000000-0000-0000-0000-0001a200c001'),
  ('00000000-0000-0000-0000-0001a200e002', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a200c002');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0001a2000f01', 'km1a2-cashier-k@example.test'),
  ('00000000-0000-0000-0000-0001a2000f02', 'km1a2-cashier-p@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0001a20ab001', '00000000-0000-0000-0000-0001a2000f01', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', 'cashier'),
  ('00000000-0000-0000-0000-0001a20ab002', '00000000-0000-0000-0000-0001a2000f02', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0001a20ef001', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a2000f01', '00000000-0000-0000-0000-0001a20ab001', 'Cashier K'),
  ('00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000f02', '00000000-0000-0000-0000-0001a20ab002', 'Cashier P');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a200e001', '00000000-0000-0000-0000-0001a20ef001', '00000000-0000-0000-0000-0001a20ab001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200e002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', now() + interval '1 hour');

-- ---- Orders. P* live in Branch P (printer_only); K* live in Branch K (kds). --
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001a2000101', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'submitted', 'ILS', 1000, 0, 0, 1000, 'km-p1',  1),
  ('00000000-0000-0000-0000-0001a2000102', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'accepted',  'ILS',  800, 0, 0,  800, 'km-p2',  1),
  ('00000000-0000-0000-0000-0001a2000103', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'preparing', 'ILS',  700, 0, 0,  700, 'km-p3',  1),
  ('00000000-0000-0000-0000-0001a2000104', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'ready',     'ILS',  600, 0, 0,  600, 'km-p4',  1),
  ('00000000-0000-0000-0000-0001a2000105', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'dine_in',  'served',    'ILS',  500, 0, 0,  500, 'km-p5',  1),
  ('00000000-0000-0000-0000-0001a2000106', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'submitted', 'ILS',  900, 0, 0,  900, 'km-p6',  1),
  ('00000000-0000-0000-0000-0001a2000107', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'submitted', 'ILS', 1000, 0, 0, 1000, 'km-p7',  1),
  ('00000000-0000-0000-0000-0001a2000108', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'completed', 'ILS',  500, 0, 0,  500, 'km-p8',  1),
  ('00000000-0000-0000-0000-0001a2000109', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'voided',    'ILS',  200, 0, 0,  200, 'km-p9',  1),
  ('00000000-0000-0000-0000-0001a200010a', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'takeaway', 'cancelled', 'ILS',  100, 0, 0,  100, 'km-p10', 1),
  ('00000000-0000-0000-0000-0001a200010b', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'dine_in',  'served',    'ILS',  300, 0, 0,  300, 'km-p11', 1),
  ('00000000-0000-0000-0000-0001a2000201', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a200d001', '00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a20ef001', '00000000-0000-0000-0000-0001a20ab001', 'takeaway', 'submitted', 'ILS', 1000, 0, 0, 1000, 'km-k1',  1),
  ('00000000-0000-0000-0000-0001a2000202', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a200d001', '00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a20ef001', '00000000-0000-0000-0000-0001a20ab001', 'dine_in',  'served',    'ILS',  800, 0, 0,  800, 'km-k2',  1),
  ('00000000-0000-0000-0000-0001a2000203', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a200d001', '00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a20ef001', '00000000-0000-0000-0000-0001a20ab001', 'dine_in',  'served',    'ILS',  400, 0, 0,  400, 'km-k3',  1);

-- P7 UNDER-COVERED (completed 400 of 1000); P8 fully paid but already TERMINAL.
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0001a20af007', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000107', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'cash', 'completed', 400, 400, 0, 'ILS', 'km-pp7'),
  ('00000000-0000-0000-0000-0001a20af008', '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000108', '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20ef002', '00000000-0000-0000-0000-0001a20ab002', 'cash', 'completed', 500, 500, 0, 'ILS', 'km-pp8');

-- ACTIVE (non-served) additional rounds on P11 and K3.
insert into order_service_rounds (organization_id, restaurant_id, branch_id, order_id, round_number, device_id, opened_by_employee_profile_id) values
  ('00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200010b', 2, '00000000-0000-0000-0000-0001a200d002', '00000000-0000-0000-0000-0001a20ef002'),
  ('00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10', '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a2000203', 2, '00000000-0000-0000-0000-0001a200d001', '00000000-0000-0000-0000-0001a20ef001');

-- open shifts + bound drawers so app.record_payment can run (RF-055).
select app.open_shift('00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a20aff01',
                      '00000000-0000-0000-0000-0001a20add01', '00000000-0000-0000-0000-0001a200d001', 'km-sh-k', 0);
select app.open_shift('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a20aff02',
                      '00000000-0000-0000-0000-0001a20add02', '00000000-0000-0000-0000-0001a200d002', 'km-sh-p', 0);

-- =============================================================================
-- A. PRINTER-ONLY: settlement ALONE completes from EVERY active state  (1-12)
-- =============================================================================
create temp table t_p1 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a2000101',
                            '00000000-0000-0000-0000-0001a200d002', 'km-pay-p1', 'cash', 1000, null) as res;
select ok((select (res ->> 'ok')::boolean and res ->> 'payment_id' is not null from t_p1),
  'P1: the payment itself succeeds (completion is a consequence, never a precondition)');            -- 1
select ok((select (res ->> 'auto_completed')::boolean = true and res ->> 'order_status' = 'completed' from t_p1),
  'P1: paying a SUBMITTED printer-only order in full AUTO-COMPLETES it (settlement alone)');         -- 2
select ok((select o.status = 'completed' and o.revision = 3 from orders o
            where o.id = '00000000-0000-0000-0000-0001a2000101'),
  'P1: persisted completed; revision advanced by the two REAL steps (receipt stamp + completion)');  -- 3
select ok(
  (select count(*) = 1
     and bool_and(old_values ->> 'status' = 'submitted')
     and bool_and(new_values ->> 'kitchen_workflow_mode' = 'printer_only')
     and bool_and(new_values ->> 'completion_trigger' = 'payment_recorded')
   from audit_events
   where action = 'order.status_updated'
     and new_values ->> 'order_id' = '00000000-0000-0000-0000-0001a2000101'
     and new_values ->> 'status' = 'completed'),
  'P1: ONE completion audit; old_values names the REAL source status (submitted, not a fake served); mode + trigger recorded'); -- 4

create temp table t_p2 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a2000102',
                            '00000000-0000-0000-0000-0001a200d002', 'km-pay-p2', 'cash', 800, null) as res;
select ok((select (res ->> 'auto_completed')::boolean = true from t_p2),
  'P2: an ACCEPTED printer-only order completes on full settlement');                                -- 5
select ok(
  (select o.status = 'completed' from orders o where o.id = '00000000-0000-0000-0000-0001a2000102')
  and (select old_values ->> 'status' = 'accepted' from audit_events
        where action = 'order.status_updated'
          and new_values ->> 'order_id' = '00000000-0000-0000-0000-0001a2000102'
          and new_values ->> 'status' = 'completed'),
  'P2: persisted completed and the audit trail keeps the honest source status (accepted)');          -- 6

create temp table t_p3 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a2000103',
                            '00000000-0000-0000-0000-0001a200d002', 'km-pay-p3', 'cash', 700, null) as res;
select ok((select (res ->> 'auto_completed')::boolean = true from t_p3)
  and (select status = 'completed' from orders where id = '00000000-0000-0000-0000-0001a2000103'),
  'P3: a PREPARING printer-only order completes on full settlement');                                -- 7

create temp table t_p4 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a2000104',
                            '00000000-0000-0000-0000-0001a200d002', 'km-pay-p4', 'cash', 600, null) as res;
select ok((select (res ->> 'auto_completed')::boolean = true from t_p4)
  and (select status = 'completed' from orders where id = '00000000-0000-0000-0000-0001a2000104'),
  'P4: a READY printer-only order completes on full settlement');                                    -- 8
select ok((select ready_at is null from orders where id = '00000000-0000-0000-0000-0001a2000104'),
  'P4: ready_at was NEVER stamped (only the KDS preparing->ready transition writes it)');            -- 9

create temp table t_p5 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a2000105',
                            '00000000-0000-0000-0000-0001a200d002', 'km-pay-p5', 'cash', 500, null) as res;
select ok((select (res ->> 'auto_completed')::boolean = true from t_p5)
  and (select status = 'completed' from orders where id = '00000000-0000-0000-0000-0001a2000105'),
  'P5: a SERVED printer-only order still completes (the widened gate contains the old one)');        -- 10

create temp table t_p11 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a200010b',
                            '00000000-0000-0000-0000-0001a200d002', 'km-pay-p11', 'cash', 300, null) as res;
select ok((select (res ->> 'auto_completed')::boolean = true from t_p11)
  and (select status = 'completed' from orders where id = '00000000-0000-0000-0000-0001a200010b'),
  'P11: the ROUNDS GATE IS SKIPPED in printer-only mode — an active round cannot strand the order'); -- 11
select ok(
  (select bool_and(r.status <> 'served') from order_service_rounds r
    where r.order_id = '00000000-0000-0000-0000-0001a200010b'),
  'P11: the round itself was NOT rewritten to served — completion never fabricates kitchen work');   -- 12

-- =============================================================================
-- B. PRINTER-ONLY: unpaid / partial / terminal stay EXACTLY where they are (13-19)
-- =============================================================================
select ok(
  (select o.status = 'submitted' and o.revision = 1 from orders o
    where o.id = '00000000-0000-0000-0000-0001a2000106')
  and not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-0001a2000106'),
  'P6: an UNPAID printer-only order stays submitted — nothing spontaneous, nothing fabricated');     -- 13
create temp table t_p6 as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
    '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000106',
    'payment_recorded', null, null, null, null, null, null) as res;
select ok((select (res ->> 'completed')::boolean = false and res ->> 'reason' = 'not_fully_paid' from t_p6),
  'P6: the helper itself refuses an unpaid printer-only order (amount-aware settlement holds)');     -- 14

create temp table t_p7 as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
    '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000107',
    'payment_recorded', null, null, null, null, null, null) as res;
select ok((select (res ->> 'completed')::boolean = false and res ->> 'reason' = 'not_fully_paid' from t_p7),
  'P7: an UNDER-COVERED order (completed 400 of 1000) is NOT settled — the helper refuses');         -- 15
select is((select status from orders where id = '00000000-0000-0000-0000-0001a2000107'), 'submitted',
  'P7: the under-covered order stays submitted (integer-minor settlement is amount-aware)');         -- 16

create temp table t_p8 as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
    '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000108',
    'payment_recorded', null, null, null, null, null, null) as res;
select ok((select (res ->> 'completed')::boolean = false and res ->> 'reason' = 'not_eligible' from t_p8)
  and (select revision = 1 from orders where id = '00000000-0000-0000-0000-0001a2000108'),
  'P8: a COMPLETED order is terminal — not re-completed, revision untouched');                       -- 17
select ok(
  ((app.try_auto_complete_order(
      '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
      '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000109',
      'payment_recorded', null, null, null, null, null, null) ->> 'completed')::boolean = false)
  and ((app.try_auto_complete_order(
      '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
      '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a200010a',
      'payment_recorded', null, null, null, null, null, null) ->> 'completed')::boolean = false),
  'P9/P10: VOIDED and CANCELLED orders are NEVER revived in printer-only mode');                     -- 18
select ok(
  (select status = 'voided' from orders where id = '00000000-0000-0000-0000-0001a2000109')
  and (select status = 'cancelled' from orders where id = '00000000-0000-0000-0000-0001a200010a'),
  'P9/P10: the terminal states are persisted unchanged');                                            -- 19

-- =============================================================================
-- C. idempotency + isolation + no fabrication  (20-24)
-- =============================================================================
create temp table t_p1b as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
    '00000000-0000-0000-0000-0001a2000a2b', '00000000-0000-0000-0000-0001a2000101',
    'payment_recorded', null, null, null, null, null, null) as res;
select ok((select (res ->> 'completed')::boolean = false and res ->> 'reason' = 'not_eligible' from t_p1b),
  'idempotency: re-running the helper on an already-completed order is a clean no-op');              -- 20
select ok(
  (select revision = 3 from orders where id = '00000000-0000-0000-0000-0001a2000101')
  and (select count(*) = 1 from audit_events
        where action = 'order.status_updated'
          and new_values ->> 'order_id' = '00000000-0000-0000-0000-0001a2000101'
          and new_values ->> 'status' = 'completed'),
  'idempotency: no second transition, no duplicate completion audit');                               -- 21
select ok(
  ((app.try_auto_complete_order(
      '00000000-0000-0000-0000-0001a2000b00', '00000000-0000-0000-0000-0001a2000b10',
      '00000000-0000-0000-0000-0001a2000b1a', '00000000-0000-0000-0000-0001a2000106',
      'payment_recorded', null, null, null, null, null, null) ->> 'completed')::boolean = false),
  'isolation: Org B''s (printer-only) scope can NEVER complete an Org A order (fails closed)');      -- 22
select is((select status from orders where id = '00000000-0000-0000-0000-0001a2000106'), 'submitted',
  'isolation: the cross-tenant attempt left the order untouched');                                   -- 23
select ok(
  (select count(*) = 5 and bool_and(p.status = 'completed')
     from payments p
    where p.order_id in ('00000000-0000-0000-0000-0001a2000101', '00000000-0000-0000-0000-0001a2000102',
                         '00000000-0000-0000-0000-0001a2000103', '00000000-0000-0000-0000-0001a2000104',
                         '00000000-0000-0000-0000-0001a2000105'))
  and (select count(*) = 1 from payments where order_id = '00000000-0000-0000-0000-0001a200010b')
  and not exists (select 1 from payments
                   where order_id in ('00000000-0000-0000-0000-0001a2000106', '00000000-0000-0000-0000-0001a2000109',
                                      '00000000-0000-0000-0000-0001a200010a')),
  'NO payment was ever fabricated: exactly the RPC-written rows exist, and none on unpaid/terminal orders'); -- 24

-- =============================================================================
-- D. KDS-MODE REGRESSION — byte-equivalent to pre-KITCHEN-MODE  (25-33)
-- =============================================================================
create temp table t_k1 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a2000201',
                            '00000000-0000-0000-0000-0001a200d001', 'km-pay-k1', 'cash', 1000, null) as res;
select ok((select (res ->> 'ok')::boolean = true and res ->> 'payment_id' is not null from t_k1),
  'K1: the payment succeeds in the kds branch');                                                     -- 25
select ok((select (res ->> 'auto_completed')::boolean = false and res ->> 'order_status' = 'submitted' from t_k1),
  'K1: THE DORMANCY PIN — settlement alone NEVER completes a kds-mode order');                       -- 26
select ok((select o.status = 'submitted' from orders o where o.id = '00000000-0000-0000-0000-0001a2000201'),
  'K1: the paid-but-unserved kds order stays submitted, exactly as before this migration');          -- 27
create temp table t_k1h as
  select app.try_auto_complete_order(
    '00000000-0000-0000-0000-0001a2000a00', '00000000-0000-0000-0000-0001a2000a10',
    '00000000-0000-0000-0000-0001a2000a1a', '00000000-0000-0000-0000-0001a2000201',
    'payment_recorded', null, null, null, null, null, null) as res;
select ok((select (res ->> 'completed')::boolean = false and res ->> 'reason' = 'not_eligible' from t_k1h),
  'K1: the helper itself still refuses a non-served kds order (not_eligible, byte-equivalent gate)'); -- 28

create temp table t_k2 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a2000202',
                            '00000000-0000-0000-0000-0001a200d001', 'km-pay-k2', 'cash', 800, null) as res;
select ok((select (res ->> 'auto_completed')::boolean = true and res ->> 'order_status' = 'completed' from t_k2),
  'K2: a SERVED + fully-paid kds order still auto-completes (Direction B unchanged)');               -- 29
select ok((select o.status = 'completed' and o.revision = 3 from orders o
            where o.id = '00000000-0000-0000-0000-0001a2000202'),
  'K2: persisted completed at revision 3 (receipt stamp + completion), exactly as before');          -- 30
select ok(
  (select count(*) = 1
     and bool_and(old_values ->> 'status' = 'served')
     and bool_and(not (new_values ? 'kitchen_workflow_mode'))
   from audit_events
   where action = 'order.status_updated'
     and new_values ->> 'order_id' = '00000000-0000-0000-0000-0001a2000202'
     and new_values ->> 'status' = 'completed'),
  'K2: the kds completion audit is BYTE-COMPATIBLE — old status served, NO kitchen_workflow_mode key'); -- 31

create temp table t_k3 as
  select app.record_payment('00000000-0000-0000-0000-0001a20c5001', '00000000-0000-0000-0000-0001a2000203',
                            '00000000-0000-0000-0000-0001a200d001', 'km-pay-k3', 'cash', 400, null) as res;
select ok((select (res ->> 'ok')::boolean = true and (res ->> 'auto_completed')::boolean = false from t_k3),
  'K3: the PSC-001C rounds gate still HOLDS a kds order open while a round is active');              -- 32
select is((select status from orders where id = '00000000-0000-0000-0000-0001a2000203'), 'served',
  'K3: the kds order with an unserved round stays served (rounds gate byte-equivalent)');            -- 33

-- =============================================================================
-- E. the ready feed stays EMPTY for printer-only orders  (34-36)
-- =============================================================================
select ok(
  (select bool_and(ready_at is null) from orders
    where branch_id = '00000000-0000-0000-0000-0001a2000a2b'),
  'NO printer-only order ever received a ready_at stamp');                                           -- 34
create temp table t_feed as
  select public.pos_ready_feed('00000000-0000-0000-0000-0001a20c5002', '00000000-0000-0000-0000-0001a200d002') as r;
select ok((select (r ->> 'ok')::boolean from t_feed),
  'the POS ready feed itself still answers in a printer-only branch');                               -- 35
select is((select jsonb_array_length(r -> 'ready') from t_feed), 0,
  'the ready feed is EMPTY — auto-completed printer-only orders never surface as ready alerts');     -- 36

select * from finish();
rollback;
