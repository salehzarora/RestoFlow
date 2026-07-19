-- ============================================================================
-- KITCHEN-MODE-001A — pgTAP: the dormant ZERO-TOTAL submit path and the
-- AUTHORITATIVE kitchen sync exclusion.
--
-- Branch K stays 'kds'; Branch P is flipped to 'printer_only' by PRIVILEGED
-- SQL only (no setter exists — proven in the foundation suite).
--
--   ZERO-TOTAL SUBMIT (app.submit_order tail):
--     * printer-only, grand 0  -> the order COMPLETES inside the same submit
--       transaction (settled-with-nothing-to-pay; no payment.create will ever
--       arrive); the envelope carries the ADDITIVE auto_completed/order_status
--       keys, reports the REAL revision (2), and NO payment row is fabricated;
--       the completion audit names trigger order_submitted.
--     * an idempotent REPLAY reads back the SAME truth (completed, rev 2).
--     * kds, grand 0           -> stays submitted, revision 1 — byte-identical
--       to pre-KITCHEN-MODE behavior (THE dormancy pin for the submit tail).
--     * printer-only, grand>0  -> stays submitted (completion belongs to the
--       payment, which the completion suite proves).
--
--   KITCHEN SYNC EXCLUSION (app.sync_pull, authoritative — not cosmetic):
--     * kitchen_staff @ printer-only branch: the DEFAULT pull resolves ONLY
--       the money-free `tables` floor entity — no orders / order_items /
--       order_item_modifiers / order_service_rounds, and NO order id ever
--       appears anywhere in the response; an EXPLICIT order-entity request
--       rejects with the existing not-permitted 42501 (fail closed).
--     * (review HIGH-1) the operation_statuses feed is SUPPRESSED to an empty
--       collection for that session — proven against REAL order-bearing
--       sync_operations rows whose target_id names an order and whose
--       result/conflict_info carry the money-shaped key change_due_minor —
--       even when operation_statuses is requested explicitly.
--     * kitchen_staff @ kds branch: allow-list AND op-status feed unchanged.
--     * cashier @ printer-only branch: POS exposure AND op-status unchanged.
-- Session pinned to UTC; hex-only UUIDs; PIN-session auth (GUC-free).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(30);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0001a3000a00', 'Org A', 'km1a3-a', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a00', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', 'Branch P (printer-only)');
update branches set kitchen_workflow_mode = 'printer_only'
  where id = '00000000-0000-0000-0000-0001a3000a2b';

-- POS + KDS device per branch (4 devices, pairings, sessions).
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001a300d001', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', 'pos'),
  ('00000000-0000-0000-0000-0001a300d002', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', 'pos'),
  ('00000000-0000-0000-0000-0001a300d003', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', 'kds'),
  ('00000000-0000-0000-0000-0001a300d004', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001a300c001', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300d001', 'active'),
  ('00000000-0000-0000-0000-0001a300c002', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300d002', 'active'),
  ('00000000-0000-0000-0000-0001a300c003', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300d003', 'active'),
  ('00000000-0000-0000-0000-0001a300c004', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0001a300e001', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300d001', '00000000-0000-0000-0000-0001a300c001'),
  ('00000000-0000-0000-0000-0001a300e002', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300d002', '00000000-0000-0000-0000-0001a300c002'),
  ('00000000-0000-0000-0000-0001a300e003', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300d003', '00000000-0000-0000-0000-0001a300c003'),
  ('00000000-0000-0000-0000-0001a300e004', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300d004', '00000000-0000-0000-0000-0001a300c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0001a3000f01', 'km1a3-cashier-k@example.test'),
  ('00000000-0000-0000-0000-0001a3000f02', 'km1a3-cashier-p@example.test'),
  ('00000000-0000-0000-0000-0001a3000f03', 'km1a3-kitchen-k@example.test'),
  ('00000000-0000-0000-0000-0001a3000f04', 'km1a3-kitchen-p@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0001a30ab001', '00000000-0000-0000-0000-0001a3000f01', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', 'cashier'),
  ('00000000-0000-0000-0000-0001a30ab002', '00000000-0000-0000-0000-0001a3000f02', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', 'cashier'),
  ('00000000-0000-0000-0000-0001a30ab003', '00000000-0000-0000-0000-0001a3000f03', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0001a30ab004', '00000000-0000-0000-0000-0001a3000f04', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0001a30ef001', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a3000f01', '00000000-0000-0000-0000-0001a30ab001', 'Cashier K'),
  ('00000000-0000-0000-0000-0001a30ef002', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a3000f02', '00000000-0000-0000-0000-0001a30ab002', 'Cashier P'),
  ('00000000-0000-0000-0000-0001a30ef003', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a3000f03', '00000000-0000-0000-0000-0001a30ab003', 'Kitchen K'),
  ('00000000-0000-0000-0000-0001a30ef004', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a3000f04', '00000000-0000-0000-0000-0001a30ab004', 'Kitchen P');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0001a30c5001', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300e001', '00000000-0000-0000-0000-0001a30ef001', '00000000-0000-0000-0000-0001a30ab001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0001a30c5002', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300e002', '00000000-0000-0000-0000-0001a30ef002', '00000000-0000-0000-0000-0001a30ab002', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0001a30c5003', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300e003', '00000000-0000-0000-0000-0001a30ef003', '00000000-0000-0000-0000-0001a30ab003', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0001a30c5004', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300e004', '00000000-0000-0000-0000-0001a30ef004', '00000000-0000-0000-0000-0001a30ab004', now() + interval '1 hour');

-- menu: a FREE item (base price 0) and a paid item; floor tables in both branches.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-0001a300ca01', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0001a30000f0', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', null, '00000000-0000-0000-0000-0001a300ca01', 'Tap Water', 0, 'ILS', 1),
  ('00000000-0000-0000-0000-0001a30000f5', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', null, '00000000-0000-0000-0000-0001a300ca01', 'Burger', 500, 'ILS', 2);
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('00000000-0000-0000-0000-0001a300ab1a', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', 'K1'),
  ('00000000-0000-0000-0000-0001a300ab2b', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', 'P1');

-- REAL order-bearing sync operations (review HIGH-1) for ALL THREE devices:
-- target_id names an order (soft reference — the orders are created by
-- submit_order later in this file), and result + conflict_info carry the
-- money-shaped key change_due_minor. Under the PRE-correction behavior the
-- printer-only kitchen device (d004) would receive ALL of this verbatim.
insert into sync_operations (id, organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type, target_entity, target_id, payload, payload_fingerprint, status, result, conflict_info) values
  ('00000000-0000-0000-0000-0001a3050001', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300d004', 'km-op-p1', 'payment.create', 'payments', '00000000-0000-0000-0000-0001a3000d01', '{"amount_minor": 500}', 'km-fp-1', 'applied',  '{"ok": true, "order_id": "00000000-0000-0000-0000-0001a3000d01", "change_due_minor": 150}', '{"change_due_minor": 150}'),
  ('00000000-0000-0000-0000-0001a3050002', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a1a', '00000000-0000-0000-0000-0001a300d003', 'km-op-k1', 'payment.create', 'payments', '00000000-0000-0000-0000-0001a3000d02', '{"amount_minor": 300}', 'km-fp-2', 'applied',  '{"ok": true, "order_id": "00000000-0000-0000-0000-0001a3000d02", "change_due_minor": 50}',  '{"change_due_minor": 50}'),
  ('00000000-0000-0000-0000-0001a3050003', '00000000-0000-0000-0000-0001a3000a00', '00000000-0000-0000-0000-0001a3000a10', '00000000-0000-0000-0000-0001a3000a2b', '00000000-0000-0000-0000-0001a300d002', 'km-op-p2', 'payment.create', 'payments', '00000000-0000-0000-0000-0001a3000d01', '{"amount_minor": 500}', 'km-fp-3', 'applied',  '{"ok": true, "order_id": "00000000-0000-0000-0000-0001a3000d01", "change_due_minor": 150}', '{"change_due_minor": 150}');

-- =============================================================================
-- A. ZERO-TOTAL submit in the PRINTER-ONLY branch — completes at the tail (1-8)
-- =============================================================================
create temp table t_z1 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001a30c5002', '00000000-0000-0000-0000-0001a3000d01',
    '00000000-0000-0000-0000-0001a300d002', 'km-z1', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001a30000f0","quantity":1,"unit_price_minor_snapshot":0,"menu_item_name_snapshot":"Tap Water","modifiers":[]}]'::jsonb,
    0, 0, 0, 0, null) as res;
select ok((select (res ->> 'ok')::boolean = true and (res ->> 'idempotency_replay')::boolean = false from t_z1),
  'Z1: the zero-total submit itself succeeds (first delivery)');                                     -- 1
select ok((select (res ->> 'auto_completed')::boolean = true and res ->> 'order_status' = 'completed' from t_z1),
  'Z1: a zero-total printer-only order COMPLETES inside the submit (settled with nothing to pay)');  -- 2
select is((select res ->> 'revision' from t_z1), '2',
  'Z1: the envelope reports the REAL revision (2 — insert + completion), never a stale 1');          -- 3
select ok((select o.status = 'completed' and o.revision = 2 from orders o
            where o.id = '00000000-0000-0000-0000-0001a3000d01'),
  'Z1: persisted completed at revision 2');                                                          -- 4
select ok(not exists (select 1 from payments where order_id = '00000000-0000-0000-0000-0001a3000d01'),
  'Z1: NO payment row was fabricated for the settled-with-nothing-to-pay order');                    -- 5
select ok(
  (select count(*) = 1
     and bool_and(old_values ->> 'status' = 'submitted')
     and bool_and(new_values ->> 'completion_trigger' = 'order_submitted')
     and bool_and(new_values ->> 'kitchen_workflow_mode' = 'printer_only')
   from audit_events
   where action = 'order.status_updated'
     and new_values ->> 'order_id' = '00000000-0000-0000-0000-0001a3000d01'
     and new_values ->> 'status' = 'completed'),
  'Z1: ONE completion audit naming the order_submitted trigger and the printer-only mode');          -- 6
create temp table t_z1r as
  select app.submit_order(
    '00000000-0000-0000-0000-0001a30c5002', '00000000-0000-0000-0000-0001a3000d01',
    '00000000-0000-0000-0000-0001a300d002', 'km-z1', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001a30000f0","quantity":1,"unit_price_minor_snapshot":0,"menu_item_name_snapshot":"Tap Water","modifiers":[]}]'::jsonb,
    0, 0, 0, 0, null) as res;
select ok(
  (select (res ->> 'idempotency_replay')::boolean = true
      and (res ->> 'auto_completed')::boolean = true
      and res ->> 'order_status' = 'completed'
      and res ->> 'revision' = '2'
      and (res ->> 'order_id')::uuid = '00000000-0000-0000-0000-0001a3000d01'::uuid
   from t_z1r),
  'Z1 replay: the SAME truth reads back — completed, revision 2, same order (consistent envelope)'); -- 7
select is((select count(*)::int from orders where local_operation_id = 'km-z1'), 1,
  'Z1 replay: no duplicate order was created');                                                      -- 8

-- =============================================================================
-- B. the SAME zero-total submit in the KDS branch stays put  (9-11)
-- =============================================================================
create temp table t_z2 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001a30c5001', '00000000-0000-0000-0000-0001a3000d02',
    '00000000-0000-0000-0000-0001a300d001', 'km-z2', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001a30000f0","quantity":1,"unit_price_minor_snapshot":0,"menu_item_name_snapshot":"Tap Water","modifiers":[]}]'::jsonb,
    0, 0, 0, 0, null) as res;
select ok(
  (select (res ->> 'ok')::boolean = true
      and (res ->> 'auto_completed')::boolean = false
      and res ->> 'order_status' = 'submitted'
      and res ->> 'revision' = '1'
   from t_z2),
  'Z2: THE DORMANCY PIN — a kds-branch zero-total submit stays submitted at revision 1');            -- 9
select ok((select o.status = 'submitted' and o.revision = 1 from orders o
            where o.id = '00000000-0000-0000-0000-0001a3000d02'),
  'Z2: persisted submitted — kds zero-total behavior is byte-identical to before this migration');   -- 10
select is(
  (select count(*)::int from audit_events
    where action = 'order.status_updated'
      and new_values ->> 'order_id' = '00000000-0000-0000-0000-0001a3000d02'
      and new_values ->> 'status' = 'completed'),
  0, 'Z2: no completion audit was emitted in the kds branch');                                       -- 11

-- =============================================================================
-- C. a NON-ZERO printer-only submit stays submitted  (12-13)
-- =============================================================================
create temp table t_z3 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001a30c5002', '00000000-0000-0000-0000-0001a3000d03',
    '00000000-0000-0000-0000-0001a300d002', 'km-z3', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001a30000f5","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[]}]'::jsonb,
    500, 0, 0, 500, null) as res;
select ok(
  (select (res ->> 'ok')::boolean = true
      and (res ->> 'auto_completed')::boolean = false
      and res ->> 'order_status' = 'submitted'
   from t_z3),
  'Z3: a CHARGEABLE printer-only order is NOT completed at submit (completion belongs to payment)'); -- 12
select ok((select o.status = 'submitted' and o.revision = 1 from orders o
            where o.id = '00000000-0000-0000-0000-0001a3000d03'),
  'Z3: persisted submitted at revision 1');                                                          -- 13

-- =============================================================================
-- D. the ready feed stays EMPTY in the printer-only branch  (14)
-- =============================================================================
select is(
  (select jsonb_array_length(public.pos_ready_feed('00000000-0000-0000-0000-0001a30c5002',
                                                   '00000000-0000-0000-0000-0001a300d002') -> 'ready')),
  0, 'the POS ready feed in the printer-only branch is EMPTY (no ready_at is ever stamped)');        -- 14

-- =============================================================================
-- E. AUTHORITATIVE kitchen sync exclusion  (15-25)
-- =============================================================================
create temp table t_kp as
  select app.sync_pull('00000000-0000-0000-0000-0001a30c5004', '00000000-0000-0000-0000-0001a300d004',
                       null, '{}'::jsonb, 500) as res;
select ok((select (res ->> 'ok')::boolean from t_kp),
  'kitchen@printer-only: the default pull itself succeeds (safe EMPTY board, not an error loop)');   -- 15
select ok((select (res -> 'changes') ? 'tables' from t_kp),
  'kitchen@printer-only: the money-free `tables` floor entity is still served');                     -- 16
select ok(
  (select not ((res -> 'changes') ? 'orders')
      and not ((res -> 'changes') ? 'order_items')
      and not ((res -> 'changes') ? 'order_item_modifiers')
      and not ((res -> 'changes') ? 'order_service_rounds')
   from t_kp),
  'kitchen@printer-only: NO actionable order entity is served (orders/items/modifiers/rounds all withheld)'); -- 17
select ok(
  (select res::text not like '%0001a3000d01%' and res::text not like '%0001a3000d03%' from t_kp),
  'kitchen@printer-only: no printer-only order id leaks ANYWHERE in the pull response');             -- 18
select ok((select res ? 'operation_statuses' from t_kp),
  'kitchen@printer-only: the current-device operation_statuses feed stays intact');                  -- 19
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-0001a30c5004', '00000000-0000-0000-0000-0001a300d004',
                          array['orders'], '{}'::jsonb, 500) $$,
  '42501', NULL, 'kitchen@printer-only: an EXPLICIT orders request is rejected (fail closed, 42501)'); -- 20
select throws_ok(
  $$ select app.sync_pull('00000000-0000-0000-0000-0001a30c5004', '00000000-0000-0000-0000-0001a300d004',
                          array['order_service_rounds'], '{}'::jsonb, 500) $$,
  '42501', NULL, 'kitchen@printer-only: an EXPLICIT rounds request is rejected (fail closed, 42501)'); -- 21
select ok(
  ((app.sync_pull('00000000-0000-0000-0000-0001a30c5004', '00000000-0000-0000-0000-0001a300d004',
                  array['tables'], '{}'::jsonb, 500) ->> 'ok')::boolean),
  'kitchen@printer-only: an explicit `tables` request still works');                                 -- 22
create temp table t_kk as
  select app.sync_pull('00000000-0000-0000-0000-0001a30c5003', '00000000-0000-0000-0000-0001a300d003',
                       null, '{}'::jsonb, 500) as res;
select ok(
  (select ((res -> 'changes') ? 'orders')
      and ((res -> 'changes') ? 'order_items')
      and ((res -> 'changes') ? 'order_item_modifiers')
      and ((res -> 'changes') ? 'order_service_rounds')
      and ((res -> 'changes') ? 'tables')
   from t_kk),
  'kitchen@kds: the PSC-001C allow-list is UNCHANGED (regression — the KDS board still syncs)');     -- 23
select ok(
  (select res::text not like '%0001a3000d01%' and res::text not like '%0001a3000d03%' from t_kk),
  'kitchen@kds: branch isolation holds — the OTHER branch''s printer-only orders never leak');       -- 24
create temp table t_cp as
  select app.sync_pull('00000000-0000-0000-0000-0001a30c5002', '00000000-0000-0000-0000-0001a300d002',
                       null, '{}'::jsonb, 500) as res;
select ok(
  (select ((res -> 'changes') ? 'orders')
      and exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') r
                   where r ->> 'id' = '00000000-0000-0000-0000-0001a3000d01')
   from t_cp),
  'cashier@printer-only: the POS is UNAFFECTED — it still pulls orders (incl. the auto-completed one)'); -- 25

-- =============================================================================
-- F. operation-status feed exclusion  (26-30, review HIGH-1)
--    The fixture REALLY holds an order-bearing sync operation for the
--    printer-only kitchen device — target_id = the zero-total order,
--    result/conflict_info carrying change_due_minor. t_kp above was pulled
--    with that row in place.
-- =============================================================================
select is(
  (select jsonb_array_length(res -> 'operation_statuses' -> 'rows') from t_kp),
  0, 'kitchen@printer-only: the op-status feed is an EMPTY collection despite a REAL op row for this exact device'); -- 26
select ok(
  (select res::text not like '%change_due_minor%' and res::text not like '%km-op-p1%' from t_kp),
  'kitchen@printer-only: neither the money-shaped key nor the operation identity leaks anywhere in the serialized response'); -- 27
create temp table t_kpo as
  select app.sync_pull('00000000-0000-0000-0000-0001a30c5004', '00000000-0000-0000-0000-0001a300d004',
                       array['operation_statuses'], '{}'::jsonb, 500) as res;
select ok(
  (select (res ->> 'ok')::boolean
      and jsonb_array_length(res -> 'operation_statuses' -> 'rows') = 0
      and res::text not like '%change_due_minor%'
      and res::text not like '%0001a3000d01%'
   from t_kpo),
  'kitchen@printer-only: an EXPLICIT operation_statuses request is still an empty collection (suppression is authoritative)'); -- 28
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'operation_statuses' -> 'rows') e
                   where e ->> 'local_operation_id' = 'km-op-k1')
   from t_kk),
  'kitchen@kds: the existing op-status behavior is UNCHANGED — the kds kitchen device still receives its row'); -- 29
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'operation_statuses' -> 'rows') e
                   where e ->> 'local_operation_id' = 'km-op-p2')
   from t_cp),
  'cashier@printer-only: the POS op-status feed is UNCHANGED (only the printer-only KITCHEN session is suppressed)'); -- 30

select * from finish();
rollback;
