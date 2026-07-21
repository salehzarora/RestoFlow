-- ============================================================================
-- KITCHEN-MODE-001C1 — pgTAP: the DORMANT kitchen print dispatch ledger +
-- readiness foundation.
--
--   * schema: mode revision, readiness table, dispatch table, forced RLS,
--     no direct app-role access, shape CHECKs;
--   * recursive money-free/PII guard (top-level, nested, deeply nested,
--     mixed-case; oversized payload; legit quantities + optional
--     customer_display_name pass);
--   * transactional dispatch creation: submit (initial), add_order_items
--     (round delta), void (conservative kitchen-may-have-seen + supersede),
--     each idempotent on retry, each ABSENT for kds branches and failed
--     mutations; 001A zero-total completion preserved;
--   * device readiness reports (POS-only, closed vocabularies, 10-min
--     validity, one row per device, stale-revision rejection, no endpoint
--     columns exist at all);
--   * atomic claim-and-pull (readiness-gated deploy-ahead guard, KDS denied,
--     deterministic order, own-claim re-serve, stale-claim recovery,
--     tenant/branch isolation, superseded/possibly_printed never served);
--   * acknowledgement (closed NON-PHYSICAL vocabulary, claim ownership,
--     idempotent completion, permanent possibly_printed hold, order state
--     untouched);
--   * transition-readiness inspection (typed blockers + safe counts only);
--   * dormancy: no setter, kds byte-identical, all branches default kds.
-- Session pinned to UTC; hex-only UUIDs; GUC/token conventions per house style.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(157);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0001c1000a00', 'Org A', 'kmc1-a', 'ILS'),
  ('00000000-0000-0000-0000-0001c1000b00', 'Org B', 'kmc1-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a00', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0001c1000b10', '00000000-0000-0000-0000-0001c1000b00', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001c1000a1a', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', 'Branch P (printer-only)'),
  ('00000000-0000-0000-0000-0001c1000b1a', '00000000-0000-0000-0000-0001c1000b00', '00000000-0000-0000-0000-0001c1000b10', 'Branch B (printer-only)');
-- privileged fixture flips (the ONLY write path; no setter exists).
update branches set kitchen_workflow_mode = 'printer_only'
  where id in ('00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000b1a');
-- KITCHEN-MODE-001C3B1A: readiness now requires a stable valid kitchen 80mm
-- assignment; the activation-ready/pull fixtures below pin these.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-0000-0001c1000ba2', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'C1 Kitchen 80 A', 'network', 'kitchen', '80mm', true),
  ('00000000-0000-0000-0000-0001c1000bb1', '00000000-0000-0000-0000-0001c1000b00', '00000000-0000-0000-0000-0001c1000b10', '00000000-0000-0000-0000-0001c1000b1a', 'C1 Kitchen 80 B', 'network', 'kitchen', '80mm', true);

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0001c1000e01', 'kmc1-owner@example.test'),
  ('00000000-0000-0000-0000-0001c1000e02', 'kmc1-cashier-p@example.test'),
  ('00000000-0000-0000-0000-0001c1000e03', 'kmc1-cashier-k@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0001c1000f01', '00000000-0000-0000-0000-0001c1000e01', '00000000-0000-0000-0000-0001c1000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0001c1000f02', '00000000-0000-0000-0000-0001c1000e02', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'cashier'),
  ('00000000-0000-0000-0000-0001c1000f03', '00000000-0000-0000-0000-0001c1000e03', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', 'cashier');

-- devices: pos@P d001, kds@P d002, pos@K d003, second pos@P d005, pos@B d00b.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'pos'),
  ('00000000-0000-0000-0000-0001c100d002', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'kds'),
  ('00000000-0000-0000-0000-0001c100d003', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', 'pos'),
  ('00000000-0000-0000-0000-0001c100d005', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'pos'),
  ('00000000-0000-0000-0000-0001c100d00b', '00000000-0000-0000-0000-0001c1000b00', '00000000-0000-0000-0000-0001c1000b10', '00000000-0000-0000-0000-0001c1000b1a', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001c100c001', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', 'active'),
  ('00000000-0000-0000-0000-0001c100c002', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d002', 'active'),
  ('00000000-0000-0000-0000-0001c100c003', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', '00000000-0000-0000-0000-0001c100d003', 'active'),
  ('00000000-0000-0000-0000-0001c100c005', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d005', 'active'),
  ('00000000-0000-0000-0000-0001c100c00b', '00000000-0000-0000-0000-0001c1000b00', '00000000-0000-0000-0000-0001c1000b10', '00000000-0000-0000-0000-0001c1000b1a', '00000000-0000-0000-0000-0001c100d00b', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0001c100e001', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c100c001', app.hash_provisioning_secret('tok-c1-posp'), true, null),
  ('00000000-0000-0000-0000-0001c100e002', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d002', '00000000-0000-0000-0000-0001c100c002', app.hash_provisioning_secret('tok-c1-kdsp'), true, null),
  ('00000000-0000-0000-0000-0001c100e003', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', '00000000-0000-0000-0000-0001c100d003', '00000000-0000-0000-0000-0001c100c003', app.hash_provisioning_secret('tok-c1-posk'), true, null),
  ('00000000-0000-0000-0000-0001c100e005', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d005', '00000000-0000-0000-0000-0001c100c005', app.hash_provisioning_secret('tok-c1-posp2'), true, null),
  ('00000000-0000-0000-0000-0001c100e00b', '00000000-0000-0000-0000-0001c1000b00', '00000000-0000-0000-0000-0001c1000b10', '00000000-0000-0000-0000-0001c1000b1a', '00000000-0000-0000-0000-0001c100d00b', '00000000-0000-0000-0000-0001c100c00b', app.hash_provisioning_secret('tok-c1-posb'), true, null);

insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000e02', '00000000-0000-0000-0000-0001c1000f02', 'Cashier P'),
  ('00000000-0000-0000-0000-0001c10ef003', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', '00000000-0000-0000-0000-0001c1000e03', '00000000-0000-0000-0000-0001c1000f03', 'Cashier K');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100e001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0001c10c5003', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', '00000000-0000-0000-0000-0001c100e003', '00000000-0000-0000-0000-0001c10ef003', '00000000-0000-0000-0000-0001c1000f03', now() + interval '1 hour');

insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-0001c100ca01', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0001c10000f1', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', null, '00000000-0000-0000-0000-0001c100ca01', 'Falafel', 500, 'ILS', 1),
  ('00000000-0000-0000-0000-0001c10000f0', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', null, '00000000-0000-0000-0000-0001c100ca01', 'Water', 0, 'ILS', 2);
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('00000000-0000-0000-0000-0001c100ab2b', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'P1'),
  ('00000000-0000-0000-0000-0001c100ab1a', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', 'K1');

-- ===== A. schema =============================================================
select is(
  (select kitchen_workflow_mode_revision from branches where id = '00000000-0000-0000-0000-0001c1000a1a'),
  1, 'branches.kitchen_workflow_mode_revision defaults to 1');                                                   -- 1
select throws_ok(
  $$ update branches set kitchen_workflow_mode_revision = 0
       where id = '00000000-0000-0000-0000-0001c1000a1a' $$,
  '23514', NULL, 'the revision CHECK rejects non-positive values');                                              -- 2
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'kitchen_printer_readiness_reports')
  and not has_table_privilege('authenticated', 'public.kitchen_printer_readiness_reports', 'select'),
  'readiness table: RLS enabled+forced and NO direct authenticated access');                                     -- 3
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'kitchen_print_dispatches')
  and not has_table_privilege('authenticated', 'public.kitchen_print_dispatches', 'select'),
  'dispatch table: RLS enabled+forced and NO direct authenticated access');                                      -- 4
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c10000d0', 'reprint', '{}'::jsonb, 'x:bad-type') $$,
  '23514', NULL, 'an unknown dispatch_type is rejected');                                                        -- 5
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c10000d0', 'service_round', '{}'::jsonb, 'x:round-shape') $$,
  '23514', NULL, 'a service_round dispatch without a round id is rejected (shape CHECK)');                       -- 6

-- ===== B. recursive money-free / PII guard ==================================
-- (an order row to satisfy the dispatch FK for direct guard-tests)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d99', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'takeaway', 'submitted', 'ILS', 100, 0, 0, 100, 'c1-guard', 1);
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order', '{"price": 5}'::jsonb, 'x:g1') $$,
  '23514', NULL, 'guard: a TOP-LEVEL hostile key (price) is rejected');                                          -- 7
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order',
             '{"items": [{"qty": 1, "unit_price_minor": 500}]}'::jsonb, 'x:g2') $$,
  '23514', NULL, 'guard: a NESTED *_minor key inside an array element is rejected');                             -- 8
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order',
             '{"items": [{"modifiers": [{"name": "x", "extra": {"price": 3}}]}]}'::jsonb, 'x:g3') $$,
  '23514', NULL, 'guard: a DEEPLY nested hostile key is rejected');                                              -- 9
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order', '{"note": {"Grand_Total": 9}}'::jsonb, 'x:g4') $$,
  '23514', NULL, 'guard: MIXED-CASE hostile keys are rejected (case-insensitive matching)');                     -- 10
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order', '{"customer": {"phone": "05"}}'::jsonb, 'x:g5') $$,
  '23514', NULL, 'guard: customer PHONE is rejected at any nesting level');                                      -- 11
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order', '{"printer": {"host": "10.0.0.1"}}'::jsonb, 'x:g6') $$,
  '23514', NULL, 'guard: endpoint keys (host/connection_config family) are rejected');                           -- 12
insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
  values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
          '00000000-0000-0000-0000-0001c1000d99', 'initial_order',
          '{"v": 1, "kind": "initial_order", "order_code": "#TEST01", "customer_display_name": "Layla", "items": [{"qty": 3, "name": "Falafel", "modifiers": []}]}'::jsonb,
          'x:g-ok');
select is(
  (select count(*)::int from kitchen_print_dispatches where idempotency_key = 'x:g-ok'),
  1, 'guard: a legitimate money-free payload (numeric quantities + optional customer_display_name) is accepted'); -- 13
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d99', 'initial_order',
             jsonb_build_object('note', repeat('x', 40000)), 'x:g-big') $$,
  '23514', NULL, 'guard: an oversized payload (> 32KB) is rejected');                                            -- 14
delete from kitchen_print_dispatches where idempotency_key like 'x:%';

-- ===== C. transactional INITIAL dispatch (submit_order) ======================
create temp table t_s1 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d01',
    '00000000-0000-0000-0000-0001c100d001', 'c1-s1', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    1000, 0, 0, 1000, null) as res;
select ok((select (res ->> 'ok')::boolean from t_s1),
  'printer-only submit succeeds');                                                                               -- 15
select ok(
  (select count(*) = 1 from kitchen_print_dispatches
    where organization_id = '00000000-0000-0000-0000-0001c1000a00'
      and order_id = '00000000-0000-0000-0000-0001c1000d01')
  and (select dispatch_type = 'initial_order' and branch_id = '00000000-0000-0000-0000-0001c1000a2b'
         and idempotency_key = 'initial:00000000-0000-0000-0000-0001c1000d01'
       from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d01'),
  'EXACTLY ONE initial dispatch was created in the SAME transaction');                                           -- 16
select ok(
  (select p ->> 'kind' = 'initial_order' and (p ->> 'v')::int = 1
      and p ->> 'order_code' like '#%'
      and jsonb_array_length(p -> 'items') = 1
      and (p -> 'items' -> 0 ->> 'qty')::int = 2
      and p -> 'items' -> 0 ->> 'name' = 'Falafel'
      and (p -> 'items' -> 0) ? 'modifiers'
   from (select money_free_payload p from kitchen_print_dispatches
          where order_id = '00000000-0000-0000-0000-0001c1000d01') s),
  'the initial payload is the exact money-free kitchen snapshot (qty/name/modifiers)');                          -- 17
select ok(
  (select p::text not like '%_minor%' and p::text not ilike '%price%'
      and p::text not ilike '%currency%' and not (p ? 'customer_display_name')
   from (select money_free_payload p from kitchen_print_dispatches
          where order_id = '00000000-0000-0000-0000-0001c1000d01') s),
  'no money vocabulary anywhere in the payload; no customer key when the order has no name');                    -- 18
update orders set customer_name = repeat('n', 100) where id = '00000000-0000-0000-0000-0001c1000d99';
select is(
  (select length(app.kitchen_dispatch_payload_initial(
     '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000d99') ->> 'customer_display_name')),
  80, 'customer_display_name is safely truncated to 80 characters');                                             -- 19
create temp table t_s1r as
  select app.submit_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d01',
    '00000000-0000-0000-0000-0001c100d001', 'c1-s1', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    1000, 0, 0, 1000, null) as res;
select ok(
  (select (res ->> 'idempotency_replay')::boolean from t_s1r)
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d01'),
  'an idempotent submit retry creates NO duplicate dispatch');                                                   -- 20
create temp table t_s2 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001c10c5003', '00000000-0000-0000-0000-0001c1000d02',
    '00000000-0000-0000-0000-0001c100d003', 'c1-s2', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    500, 0, 0, 500, null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_s2)
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d02'),
  'a KDS-branch submit creates NO dispatch (byte-identical dormant behavior)');                                  -- 21
create temp table t_s3 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d03',
    '00000000-0000-0000-0000-0001c100d001', 'c1-s3', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c1dead01","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Ghost","modifiers":[]}]'::jsonb,
    500, 0, 0, 500, null) as res;
select ok(
  (select res ->> 'error' = 'item_unavailable' from t_s3)
  and not exists (select 1 from orders where id = '00000000-0000-0000-0000-0001c1000d03')
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d03'),
  'a REFUSED submit leaves no order and NO dispatch');                                                           -- 22
create temp table t_s4 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d04',
    '00000000-0000-0000-0000-0001c100d001', 'c1-s4', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f0","quantity":1,"unit_price_minor_snapshot":0,"menu_item_name_snapshot":"Water","modifiers":[]}]'::jsonb,
    0, 0, 0, 0, null) as res;
select ok(
  (select (res ->> 'auto_completed')::boolean and res ->> 'order_status' = 'completed' from t_s4)
  and (select status = 'completed' from orders where id = '00000000-0000-0000-0000-0001c1000d04'),
  '001A zero-total completion is PRESERVED alongside the new dispatch tail');                                    -- 23
select is(
  (select count(*)::int from kitchen_print_dispatches
    where order_id = '00000000-0000-0000-0000-0001c1000d04' and dispatch_type = 'initial_order'),
  1, 'the zero-total completed order STILL got its kitchen dispatch (job state independent of order state)');    -- 24

-- ===== D. transactional SERVICE-ROUND dispatch ==============================
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, table_id, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d05', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'dine_in', 'submitted', 'ILS', 500, 0, 0, 500, '00000000-0000-0000-0000-0001c100ab2b', 'c1-d05', 1),
  ('00000000-0000-0000-0000-0001c1000d06', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a', '00000000-0000-0000-0000-0001c100d003', '00000000-0000-0000-0000-0001c10c5003', '00000000-0000-0000-0000-0001c10ef003', '00000000-0000-0000-0000-0001c1000f03', 'dine_in', 'submitted', 'ILS', 500, 0, 0, 500, '00000000-0000-0000-0000-0001c100ab1a', 'c1-d06', 1);
create temp table t_r1 as
  select app.add_order_items(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d05',
    '00000000-0000-0000-0000-0001c100d001', 'c1-r1',
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":3,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    null) as res;
select ok((select (res ->> 'ok')::boolean and (res ->> 'round_number')::int = 2 from t_r1),
  'the printer-only service round is accepted (round 2)');                                                       -- 25
select ok(
  (select count(*) = 1 from kitchen_print_dispatches d, t_r1 t
    where d.service_round_id = (t.res ->> 'round_id')::uuid and d.dispatch_type = 'service_round'),
  'EXACTLY ONE service_round dispatch was created in the SAME transaction (keyed by round id)');                 -- 26
select ok(
  (select d.money_free_payload ->> 'kind' = 'service_round'
      and (d.money_free_payload ->> 'round_number')::int = 2
      and jsonb_array_length(d.money_free_payload -> 'items') = 1
      and (d.money_free_payload -> 'items' -> 0 ->> 'qty')::int = 3
      and d.money_free_payload::text not like '%_minor%'
      and d.money_free_payload::text not ilike '%price%'
   from kitchen_print_dispatches d, t_r1 t
   where d.service_round_id = (t.res ->> 'round_id')::uuid),
  'the round payload is the DELTA ONLY (1 new item, money-free) — no initial items resurface');                  -- 27
create temp table t_r1r as
  select app.add_order_items(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d05',
    '00000000-0000-0000-0000-0001c100d001', 'c1-r1',
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":3,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    null) as res;
select ok(
  (select (res ->> 'idempotency_replay')::boolean from t_r1r)
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d05' and dispatch_type = 'service_round'),
  'an idempotent round retry creates NO duplicate dispatch');                                                    -- 28
create temp table t_r2 as
  select app.add_order_items(
    '00000000-0000-0000-0000-0001c10c5003', '00000000-0000-0000-0000-0001c1000d06',
    '00000000-0000-0000-0000-0001c100d003', 'c1-r2',
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_r2)
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d06'),
  'a KDS-branch service round creates NO dispatch');                                                             -- 29
select is(
  (select round_number from order_service_rounds r, t_r1 t
    where r.id = (t.res ->> 'round_id')::uuid),
  2, 'round numbering is untouched by the dispatch tail');                                                       -- 30

-- ===== E. transactional VOID dispatch =======================================
create temp table t_v1 as
  select app.void_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d01',
    '00000000-0000-0000-0000-0001c100d001', 'c1-v1', 'wrong order', null) as res;
select ok((select (res ->> 'ok')::boolean and res ->> 'status' = 'voided' from t_v1),
  'the printer-only void succeeds (existing contract untouched)');                                               -- 31
select ok(
  (select count(*) = 1 from kitchen_print_dispatches
    where order_id = '00000000-0000-0000-0000-0001c1000d01' and dispatch_type = 'void'
      and idempotency_key = 'void:00000000-0000-0000-0000-0001c1000d01'),
  'EXACTLY ONE void dispatch was created in the SAME transaction');                                              -- 32
select ok(
  (select i.superseded_by_dispatch_id = v.id
   from kitchen_print_dispatches i, kitchen_print_dispatches v
   where i.order_id = '00000000-0000-0000-0000-0001c1000d01' and i.dispatch_type = 'initial_order'
     and v.order_id = '00000000-0000-0000-0000-0001c1000d01' and v.dispatch_type = 'void'),
  'the UNCLAIMED initial dispatch is SUPERSEDED by the void (the kitchen never saw it)');                        -- 33
select ok(
  (select p ->> 'kind' = 'void' and (p ->> 'void')::boolean and p ->> 'reason' = 'wrong order'
      and p::text not like '%_minor%' and p::text not ilike '%price%'
   from (select money_free_payload p from kitchen_print_dispatches
          where order_id = '00000000-0000-0000-0000-0001c1000d01' and dispatch_type = 'void') s),
  'the VOID payload carries the marker + safe reason and stays money-free');                                     -- 34
create temp table t_v1r as
  select app.void_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d01',
    '00000000-0000-0000-0000-0001c100d001', 'c1-v1', 'wrong order', null) as res;
select ok(
  (select (res ->> 'idempotency_replay')::boolean from t_v1r)
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d01' and dispatch_type = 'void'),
  'an idempotent void retry creates NO duplicate dispatch');                                                     -- 35
create temp table t_v2 as
  select app.void_order(
    '00000000-0000-0000-0000-0001c10c5003', '00000000-0000-0000-0000-0001c1000d06',
    '00000000-0000-0000-0000-0001c100d003', 'c1-v2', 'kds void', null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_v2)
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d06'),
  'a KDS-branch void creates NO dispatch (PSC-001D semantics untouched)');                                       -- 36
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d07', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'takeaway', 'served', 'ILS', 300, 0, 0, 300, 'c1-d07', 1);
create temp table t_v3 as
  select app.void_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d07',
    '00000000-0000-0000-0000-0001c100d001', 'c1-v3', 'served void', null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_v3)
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d07'),
  'a SERVED-source void with NO prior dispatch creates none (the conservative predicate is respected)');         -- 37
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d08', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'takeaway', 'submitted', 'ILS', 400, 0, 0, 400, 'c1-d08', 1);
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0001c10af008', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000d08', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'cash', 'completed', 400, 400, 0, 'ILS', 'c1-p08');
create temp table t_v4 as
  select app.void_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d08',
    '00000000-0000-0000-0000-0001c100d001', 'c1-v4', 'paid void', null) as res;
select ok(
  (select res ->> 'error' = 'permission_denied'
      and res ->> 'detail' = 'order_has_completed_payment' from t_v4)
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d08'),
  'the PAID-order void restriction is unchanged, and a refused void creates NO dispatch');                       -- 38

-- ===== F. readiness reports =================================================
create temp table t_rr1 as
  select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    'kitchen_printer_only_v1', 'build-2026-07-20', 'kitchen_ticket',
    'network', '80mm', repeat('ab', 16), true, 0, 1,
    '00000000-0000-0000-0000-0001c1000ba2') as res;
select ok(
  (select (res ->> 'ok')::boolean and (res ->> 'activation_ready')::boolean
      and res ->> 'meaning' = 'transport_accepted_not_paper_confirmed' from t_rr1),
  'a valid POS readiness report succeeds — and says HONESTLY what it means');                                    -- 39
select ok(
  (select expires_at > now() + interval '9 minutes'
      and expires_at < now() + interval '11 minutes'
   from kitchen_printer_readiness_reports
   where device_id = '00000000-0000-0000-0000-0001c100d001'),
  'the server owns the clock: validity is reported_at + 10 minutes');                                            -- 40
create temp table t_rr2 as
  select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    'kitchen_printer_only_v1', 'build-2026-07-20b', 'kitchen_ticket',
    'network', '80mm', repeat('ab', 16), true, 0, 1) as res;
select ok(
  (select count(*) = 1 from kitchen_printer_readiness_reports
    where device_id = '00000000-0000-0000-0000-0001c100d001')
  and (select app_build = 'build-2026-07-20b' from kitchen_printer_readiness_reports
        where device_id = '00000000-0000-0000-0000-0001c100d001'),
  'ONE current report per device (upsert replaces, never accumulates)');                                         -- 41
select is(
  (select res ->> 'error' from (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d002', 'tok-c1-kdsp',
    'kitchen_printer_only_v1', 'b', 'kitchen_ticket', 'network', '80mm',
    repeat('ab', 16), true, 0, 1) as res) s),
  'invalid_session', 'a KDS device is explicitly DENIED readiness reporting');                                   -- 42
select is(
  (select res ->> 'error' from (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    'kitchen_printer_only_v1', 'b', 'kitchen_ticket', 'network', '80mm',
    repeat('ab', 16), true, 0, 99) as res) s),
  'stale_mode_revision', 'a stale branch mode revision is rejected');                                            -- 43
create temp table t_rr3 as
  select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    'kitchen_printer_only_v1', 'b58', 'kitchen_ticket',
    'network', '58mm', repeat('ab', 16), true, 0, 1) as res;
select ok(
  (select (res ->> 'ok')::boolean and not (res ->> 'activation_ready')::boolean from t_rr3),
  'a 58mm report is recorded but is NOT activation-ready (80mm required)');                                      -- 44
-- restore the activation-ready report for the pull tests below.
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
  'kitchen_printer_only_v1', 'build-2026-07-20', 'kitchen_ticket',
  'network', '80mm', repeat('ab', 16), true, 0, 1,
  '00000000-0000-0000-0000-0001c1000ba2');
select is(
  (select res ->> 'error' from (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    'kitchen_printer_only_v1', 'b', 'kitchen_ticket', 'network', '80mm',
    'NOT-HEX!', true, 0, 1) as res) s),
  'invalid_fingerprint', 'a malformed fingerprint is rejected (digest shape only)');                             -- 45
select is(
  (select res ->> 'error' from (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    'other_capability', 'b', 'kitchen_ticket', 'network', '80mm',
    repeat('ab', 16), true, 0, 1) as res) s),
  'unsupported_capability', 'an unknown capability is rejected');                                                -- 46
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'kitchen_printer_readiness_reports'
      and column_name in ('host', 'port', 'bluetooth_address', 'connection_config', 'address')),
  0, 'the readiness table has NO endpoint columns at all — endpoints cannot be stored');                         -- 47

-- ===== G. atomic claim-and-pull =============================================
select is(
  (select res ->> 'error' from (select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d003', 'tok-c1-posk', 20, null, null) as res) s),
  'branch_not_printer_only', 'a kds-mode branch cannot pull (typed refusal)');                                   -- 48
select is(
  (select res ->> 'error' from (select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d002', 'tok-c1-kdsp', 20, null, null) as res) s),
  'invalid_session', 'a KDS device is explicitly DENIED the dispatch pull');                                     -- 49
select is(
  (select res ->> 'error' from (select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null) as res) s),
  'readiness_required', 'a device WITHOUT a fresh activation-capable readiness report cannot claim (deploy-ahead guard)'); -- 50
create temp table t_p1 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null) as res;
select ok(
  (select (res ->> 'ok')::boolean and jsonb_array_length(res -> 'dispatches') = 3 from t_p1),
  'the ready POS claims the three ELIGIBLE dispatches (the superseded initial is never served)');                -- 51
select ok(
  (select (res -> 'dispatches' -> 0 ->> 'dispatch_type') = 'initial_order'
      and (res -> 'dispatches' -> 0 ->> 'order_id') = '00000000-0000-0000-0000-0001c1000d04'
      and (res -> 'dispatches' -> 1 ->> 'dispatch_type') = 'service_round'
      and (res -> 'dispatches' -> 2 ->> 'dispatch_type') = 'void'
   from t_p1),
  'deterministic order: initial (d04) -> round (d05) -> void (d01) by creation time and type rank');             -- 52
select ok(
  (select bool_and(claimed_by_device_id = '00000000-0000-0000-0000-0001c100d001'
             and claim_expires_at > now() + interval '9 minutes')
   from kitchen_print_dispatches
   where completed_at is null and superseded_by_dispatch_id is null
     and branch_id = '00000000-0000-0000-0000-0001c1000a2b'),
  'every claimed row belongs to the claiming device with a ~10-minute claim');                                   -- 53
select ok(
  (select (res -> 'dispatches' -> 0) ? 'payload' from t_p1),
  'the payload is returned ONLY to the claiming POS (present in its pull)');                                     -- 54
create temp table t_p2 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null) as res;
select ok(
  (select jsonb_array_length(res -> 'dispatches') = 3 from t_p2),
  'the SAME device re-pulls its own claims (idempotent import after a crash)');                                  -- 55
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2',
  'kitchen_printer_only_v1', 'build-2', 'kitchen_ticket',
  'network', '80mm', repeat('cd', 16), true, 0, 1,
  '00000000-0000-0000-0000-0001c1000ba2');
create temp table t_p3 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null) as res;
select ok(
  (select (res ->> 'ok')::boolean and jsonb_array_length(res -> 'dispatches') = 0 from t_p3),
  'a SECOND ready POS gets a valid EMPTY envelope while claims are held elsewhere');                             -- 56
update kitchen_print_dispatches
  set claim_expires_at = now() - interval '1 minute'
  where order_id = '00000000-0000-0000-0000-0001c1000d05' and dispatch_type = 'service_round';
create temp table t_p4 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null) as res;
select ok(
  (select jsonb_array_length(res -> 'dispatches') = 1
      and res -> 'dispatches' -> 0 ->> 'dispatch_type' = 'service_round' from t_p4)
  and (select claimed_by_device_id = '00000000-0000-0000-0000-0001c100d005'
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d05' and dispatch_type = 'service_round'),
  'a STALE claim is reclaimable by another device after expiry');                                                -- 57
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d00b', 'tok-c1-posb',
  'kitchen_printer_only_v1', 'build-b', 'kitchen_ticket',
  'network', '80mm', repeat('ef', 16), true, 0, 1,
  '00000000-0000-0000-0000-0001c1000bb1');
create temp table t_p5 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d00b', 'tok-c1-posb', 20, null, null) as res;
select ok(
  (select (res ->> 'ok')::boolean and jsonb_array_length(res -> 'dispatches') = 0 from t_p5),
  'TENANT ISOLATION: an Org-B printer-only POS sees ZERO Org-A dispatches');                                     -- 58

-- ===== H. acknowledgement ===================================================
create temp table t_a1 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d04'),
    'imported', null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_a1)
  and (select last_client_status = 'imported' and claim_expires_at > now() + interval '9 minutes'
       from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d04'),
  'ack imported: recorded, and the claim is EXTENDED for the importing device');                                 -- 59
create temp table t_a2 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d04'),
    'transport_accepted', null) as res;
select ok(
  (select (res ->> 'ok')::boolean and (res ->> 'completed')::boolean from t_a2)
  and (select completed_at is not null from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d04'),
  'ack transport_accepted COMPLETES the dispatch (bytes accepted — never a paper claim)');                       -- 60
create temp table t_a3 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d04'),
    'transport_accepted', null) as res;
select ok(
  (select (res ->> 'ok')::boolean and (res ->> 'idempotency_replay')::boolean from t_a3),
  'a repeated completion ack is an idempotent replay');                                                          -- 61
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2',
    (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d04'),
    'transport_accepted', null) as res) s),
  'conflict', 'another device acking a COMPLETED dispatch gets a typed conflict');                               -- 62
create temp table t_a4 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches
      where order_id = '00000000-0000-0000-0000-0001c1000d01' and dispatch_type = 'void'),
    'possibly_printed', 'crash_during_send') as res;
select ok(
  (select (res ->> 'ok')::boolean and not (res ->> 'completed')::boolean from t_a4)
  and (select last_client_status = 'possibly_printed' and completed_at is null and claim_expires_at is null
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d01' and dispatch_type = 'void'),
  'ack possibly_printed: recorded, NOT completed, and the claim becomes a PERMANENT hold');                      -- 63
create temp table t_p6 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null) as res;
select ok(
  (select not (res::text like '%void:%')
      and not exists (
        select 1 from jsonb_array_elements(res -> 'dispatches') e
         where e ->> 'dispatch_type' = 'void')
   from t_p6),
  'a possibly_printed dispatch is NEVER re-served (a blind retry could duplicate paper)');                       -- 64
create temp table t_a5 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2',
    (select id from kitchen_print_dispatches
      where order_id = '00000000-0000-0000-0000-0001c1000d05' and dispatch_type = 'service_round'),
    'failed_retryable', 'printer_unreachable') as res;
select ok(
  (select (res ->> 'ok')::boolean from t_a5)
  and (select last_client_status = 'failed_retryable' and last_error_code = 'printer_unreachable'
           and completed_at is null
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d05' and dispatch_type = 'service_round'),
  'ack failed_retryable: typed error recorded; the dispatch stays unresolved and retryable');                    -- 65
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches
      where order_id = '00000000-0000-0000-0000-0001c1000d05' and dispatch_type = 'service_round'),
    'transport_accepted', null) as res) s),
  'not_claim_owner', 'a device that does not hold the claim cannot acknowledge');                                -- 66
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    '00000000-0000-0000-0000-0001c1deadbe', 'transport_accepted', null) as res) s),
  'not_found', 'acking a non-existent dispatch is a typed not_found');                                           -- 67
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d04'),
    'printed', null) as res) s),
  'invalid_status', 'the vocabulary is NON-PHYSICAL: ''printed'' does not exist');                               -- 68
select is(
  (select status from orders where id = '00000000-0000-0000-0000-0001c1000d04'),
  'completed', 'acknowledgement NEVER touches order state (the completed order is untouched)');                  -- 69

-- ===== I. transition-readiness inspection ===================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c1000e01';
create temp table t_b1 as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a2b') as res;
select ok(
  (select (res ->> 'ok')::boolean and res ->> 'mode' = 'printer_only'
      and (res ->> 'mode_revision')::int = 1 from t_b1),
  'the owner reads the printer-only branch''s transition readiness');                                            -- 70
select ok(
  (select (res -> 'to_kds' -> 'blockers') @> '"unresolved_dispatches"'::jsonb
      and (res -> 'to_kds' -> 'blockers') @> '"pending_void_dispatches"'::jsonb
      and (res -> 'to_kds' -> 'blockers') @> '"active_orders"'::jsonb
      and not (res -> 'to_kds' ->> 'ready')::boolean
   from t_b1),
  'printer_only -> kds blockers name the unresolved dispatches, pending void and active orders');                -- 71
select ok(
  (select (res -> 'counts' ->> 'unresolved_dispatches')::int >= 2
      and (res -> 'counts' ->> 'pending_void_dispatches')::int = 1
      and res::text not ilike '%money_free_payload%'
      and res::text not like '%_minor%'
   from t_b1),
  'counts are SAFE SCALARS only — no payloads, no money vocabulary in the envelope');                            -- 72
create temp table t_b2 as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a1a') as res;
select ok(
  (select (res -> 'to_printer_only' -> 'blockers') @> '"active_orders"'::jsonb
      and (res -> 'to_printer_only' -> 'blockers') @> '"no_fresh_pos_readiness"'::jsonb
      and not (res -> 'to_printer_only' ->> 'ready')::boolean
   from t_b2),
  'kds -> printer_only blockers name the active orders and the missing POS readiness');                          -- 73
select is(
  (select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000b00', '00000000-0000-0000-0000-0001c1000b10',
    '00000000-0000-0000-0000-0001c1000b1a') ->> 'error'),
  'not_found', 'cross-tenant inspection reveals nothing (not_found)');                                           -- 74
set local app.current_app_user_id = '';
select throws_ok(
  $$ select app.get_kitchen_workflow_transition_readiness(
       '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
       '00000000-0000-0000-0000-0001c1000a2b') $$,
  '42501', NULL, 'an unauthenticated inspection is rejected');                                                   -- 75
reset role;

-- ===== J. dormancy + security ===============================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.prosrc ~* 'update\s+(public\.)?branches\y'
      and p.prosrc ilike '%kitchen_workflow_mode%'),
  0, 'STILL no function updates branches.kitchen_workflow_mode (001C1 added no setter, no activation path)');    -- 76
select ok(
  not has_function_privilege('authenticated', 'app.create_kitchen_dispatch(uuid,uuid,uuid,uuid,uuid,text,jsonb,uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_dispatch_payload_initial(uuid,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_payload_offending_key(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_payload_normalize_key(text)', 'execute')
  and not has_function_privilege('authenticated', 'app.kitchen_prep_projection(jsonb)', 'execute'),
  'the INTERNAL helpers are inaccessible to client roles');                                                      -- 77
select ok(
  has_function_privilege('authenticated', 'public.report_kitchen_printer_readiness(uuid,text,text,text,text,text,text,text,boolean,integer,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.pull_kitchen_print_dispatches(uuid,text,integer,timestamptz,uuid,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.acknowledge_kitchen_print_dispatch(uuid,text,uuid,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_kitchen_workflow_transition_readiness(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'app.pull_kitchen_print_dispatches(uuid,text,integer,timestamptz,uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'public.pull_kitchen_print_dispatches(uuid,text,integer,timestamptz,uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'app.report_kitchen_printer_readiness(uuid,text,text,text,text,text,text,text,boolean,integer,integer)', 'execute')
  and not has_function_privilege('anon', 'app.acknowledge_kitchen_print_dispatch(uuid,text,uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'app.get_kitchen_workflow_transition_readiness(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'app.submit_order(uuid,uuid,uuid,text,text,uuid,uuid,text,text,jsonb,bigint,bigint,bigint,bigint,timestamptz)', 'execute')
  and not has_function_privilege('anon', 'app.add_order_items(uuid,uuid,uuid,text,jsonb,timestamptz)', 'execute')
  and not has_function_privilege('anon', 'app.void_order(uuid,uuid,uuid,text,text,integer)', 'execute')
  and not has_function_privilege('anon', 'app.sync_push(uuid,uuid,jsonb)', 'execute'),
  'grants: authenticated may execute the new RPCs; anon may reach NOTHING (explicit posture)');                  -- 78
select ok(
  (select bool_and(p.prosecdef and p.proconfig::text like '%search_path%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('report_kitchen_printer_readiness', 'pull_kitchen_print_dispatches',
                        'acknowledge_kitchen_print_dispatch', 'get_kitchen_workflow_transition_readiness',
                        'submit_order', 'add_order_items', 'void_order', 'create_kitchen_dispatch',
                        'sync_push'))
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = 'submit_order') = 1
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = 'void_order') = 1
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = 'sync_push') = 1
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = 'pull_kitchen_print_dispatches') = 1,
  'SECURITY DEFINER + pinned search_path everywhere; no stale overloads of the re-created RPCs');                -- 79
select ok(
  (select count(*) >= 3 from audit_events
    where action = 'kitchen.dispatch_created'
      and organization_id = '00000000-0000-0000-0000-0001c1000a00'
      and actor_employee_profile_id is not null
      and new_values ->> 'dispatch_type' is not null)
  and (select count(*) = 1 from audit_events
        where action = 'kitchen.dispatch_void_created'
          and organization_id = '00000000-0000-0000-0000-0001c1000a00')
  and app.audit_category('kitchen.dispatch_created') = 'orders'
  and app.audit_action_has_detail('kitchen.dispatch_created')
  and (app.audit_safe_detail('kitchen.dispatch_created',
        jsonb_build_object('dispatch_type', 'initial_order', 'order_code', '#X',
                           'amount_minor', 5, 'money_free_payload', jsonb_build_object('a', 1)))
       = jsonb_build_object('dispatch_type', 'initial_order', 'order_code', '#X')),
  'dispatch creation is audited with the PIN-session actor; classification + safe-detail drop money and payloads'); -- 80

-- ============================================================================
-- CORRECTION-001 regressions (K..T).
-- ============================================================================

-- ===== K. REAL sync_push path: customer_display_name ========================
create temp table t_k1 as
  select public.sync_push('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c100d001',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', 'c1-k1', 'operation_type', 'order.submit', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', '00000000-0000-0000-0000-0001c1000d0a', 'order_type', 'takeaway',
        'currency_code', 'ILS', 'customer_name', repeat('n', 100),
        'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel')))))) as res;
select is((select res -> 'results' -> 0 ->> 'status' from t_k1), 'applied',
  'K1: the REAL public.sync_push order.submit path applies');                                                    -- 81
select is(
  (select length(customer_name) from orders where id = '00000000-0000-0000-0000-0001c1000d0a'),
  80, 'K2: the stored order name keeps the current stamping behavior (80-char cap)');                            -- 82
select is(
  (select money_free_payload ->> 'customer_display_name' from kitchen_print_dispatches
    where order_id = '00000000-0000-0000-0000-0001c1000d0a' and dispatch_type = 'initial_order'),
  repeat('n', 80),
  'K3: the dispatch payload carries the SAFELY TRUNCATED stored name on the REAL push path');                    -- 83
create temp table t_k1r as
  select public.sync_push('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c100d001',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', 'c1-k1', 'operation_type', 'order.submit', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', '00000000-0000-0000-0000-0001c1000d0a', 'order_type', 'takeaway',
        'currency_code', 'ILS', 'customer_name', repeat('n', 100),
        'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel')))))) as res;
select ok(
  (select (res -> 'results' -> 0 ->> 'idempotency_replay')::boolean from t_k1r)
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d0a')
  and (select count(*) = 1 from audit_events
        where action = 'kitchen.dispatch_created'
          and organization_id = '00000000-0000-0000-0000-0001c1000a00'
          and restaurant_id = '00000000-0000-0000-0000-0001c1000a10'
          and branch_id = '00000000-0000-0000-0000-0001c1000a2b'
          and new_values ->> 'order_code'
              = '#' || upper(right(replace('00000000-0000-0000-0000-0001c1000d0a', '-', ''), 6))),
  'K4: a REAL push replay neither duplicates the dispatch nor re-audits');                                       -- 84
create temp table t_k2 as
  select public.sync_push('00000000-0000-0000-0000-0001c10c5003', '00000000-0000-0000-0000-0001c100d003',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', 'c1-k2', 'operation_type', 'order.submit', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', '00000000-0000-0000-0000-0001c1000d0b', 'order_type', 'takeaway',
        'currency_code', 'ILS', 'customer_name', 'Kds Customer',
        'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel')))))) as res;
select ok(
  (select res -> 'results' -> 0 ->> 'status' = 'applied' from t_k2)
  and not exists (select 1 from kitchen_print_dispatches
                   where order_id = '00000000-0000-0000-0000-0001c1000d0b'),
  'K5: the kds-branch REAL push path still creates NO dispatch');                                                -- 85
create temp table t_k3 as
  select public.sync_push('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c100d001',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', 'c1-k3', 'operation_type', 'order.submit', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', '00000000-0000-0000-0000-0001c1000d0c', 'order_type', 'takeaway',
        'currency_code', 'ILS',
        'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel')))))) as res;
select ok(
  (select res -> 'results' -> 0 ->> 'status' = 'applied' from t_k3)
  and (select not (money_free_payload ? 'customer_display_name')
           and money_free_payload::text not ilike '%phone%'
           and money_free_payload::text not ilike '%address%'
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d0c' and dispatch_type = 'initial_order'),
  'K6: a nameless REAL push carries NO customer key — and never phone/address');                                 -- 86

-- ===== L. order-level kitchen note ==========================================
select public.sync_push('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c100d001',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'c1-l1', 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', '00000000-0000-0000-0000-0001c1000d0d', 'order_type', 'takeaway',
      'currency_code', 'ILS', 'customer_name', 'Dana', 'notes', 'no onions please',
      'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel'))))));
select ok(
  (select money_free_payload ->> 'order_note' = 'no onions please'
      and (length(money_free_payload::text)
           - length(replace(money_free_payload::text, '"order_note"', '')))
          / length('"order_note"') = 1
   from kitchen_print_dispatches
   where order_id = '00000000-0000-0000-0000-0001c1000d0d' and dispatch_type = 'initial_order'),
  'L1: the initial dispatch carries the order-level kitchen note EXACTLY ONCE');                                 -- 87
select is(
  (select notes from orders where id = '00000000-0000-0000-0000-0001c1000d0d'),
  'no onions please', 'L2: KDS parity — orders.notes (what the KDS row sweep serves) is stored verbatim');       -- 88
select public.sync_push('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c100d001',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'c1-l3', 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', '00000000-0000-0000-0000-0001c1000d0e', 'order_type', 'takeaway',
      'currency_code', 'ILS', 'notes', '   ',
      'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel'))))));
select ok(
  (select not (money_free_payload ? 'order_note') from kitchen_print_dispatches
    where order_id = '00000000-0000-0000-0000-0001c1000d0e' and dispatch_type = 'initial_order'),
  'L3: an empty/whitespace order note is OMITTED');                                                              -- 89
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, table_id, notes, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d0f', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'dine_in', 'submitted', 'ILS', 500, 0, 0, 500, '00000000-0000-0000-0000-0001c100ab2b', 'standing table note', 'c1-d0f', 1);
create temp table t_l4 as
  select app.add_order_items(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d0f',
    '00000000-0000-0000-0000-0001c100d001', 'c1-l4',
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_l4)
  and (select not (money_free_payload ? 'order_note')
           and jsonb_array_length(money_free_payload -> 'items') = 1
       from kitchen_print_dispatches d, t_l4 t
       where d.service_round_id = (t.res ->> 'round_id')::uuid),
  'L4: the ROUND delta ticket does NOT repeat the standing order note (KDS shows it on the order card)');        -- 90

-- ===== M. STICKY possibly_printed hold (on the d01 VOID dispatch from H) ====
create temp table t_m0 as
  select id as vd from kitchen_print_dispatches
    where order_id = '00000000-0000-0000-0000-0001c1000d01' and dispatch_type = 'void';
select ok(
  (select (res ->> 'ok')::boolean and (res ->> 'idempotency_replay')::boolean
       and not (res ->> 'completed')::boolean
   from (select app.acknowledge_kitchen_print_dispatch(
          '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
          (select vd from t_m0), 'possibly_printed', null) as res) s),
  'M1: the owner may REPLAY possibly_printed idempotently');                                                     -- 91
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select vd from t_m0), 'imported', null) as res) s),
  'ambiguous_print_hold', 'M2: possibly_printed -> imported is REFUSED (sticky hold)');                          -- 92
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select vd from t_m0), 'failed_retryable', 'printer_unreachable') as res) s),
  'ambiguous_print_hold', 'M3: possibly_printed -> failed_retryable is REFUSED');                                -- 93
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select vd from t_m0), 'blocked_configuration', 'printer_not_configured') as res) s),
  'ambiguous_print_hold', 'M4: possibly_printed -> blocked_configuration is REFUSED');                           -- 94
select is(
  (select res ->> 'error' from (select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select vd from t_m0), 'transport_accepted', null) as res) s),
  'ambiguous_print_hold', 'M5: possibly_printed -> transport_accepted is REFUSED (never silent success)');       -- 95
select ok(
  (select last_client_status = 'possibly_printed' and claim_expires_at is null and completed_at is null
   from kitchen_print_dispatches where id = (select vd from t_m0))
  and (select status = 'voided' from orders where id = '00000000-0000-0000-0000-0001c1000d01'),
  'M6: the row stays a PERMANENT unresolved hold; order state untouched');                                       -- 96
create temp table t_m7 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null) as res;
select ok(
  (select not exists (
     select 1 from jsonb_array_elements(res -> 'dispatches') e
      where (e ->> 'id')::uuid = (select vd from t_m0)) from t_m7),
  'M7: even its OWNER can never re-pull a possibly_printed dispatch');                                           -- 97

-- ===== N. one stable tuple for ORDER BY + cursor (tied timestamps) ==========
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d11',
  '00000000-0000-0000-0000-0001c100d001', 'c1-n1', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d14',
  '00000000-0000-0000-0000-0001c100d001', 'c1-n4', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, table_id, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d13', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'dine_in', 'submitted', 'ILS', 500, 0, 0, 500, '00000000-0000-0000-0000-0001c100ab2b', 'c1-d13', 1);
create temp table t_n3 as
  select app.add_order_items(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d13',
    '00000000-0000-0000-0000-0001c100d001', 'c1-n3',
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
    null) as res;
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d12',
  '00000000-0000-0000-0000-0001c100d001', 'c1-n2', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
select app.void_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d12',
  '00000000-0000-0000-0000-0001c100d001', 'c1-vn2', 'tie fixture', null);
create temp table t_nids as
  select (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d11' and dispatch_type = 'initial_order') as init_a,
         (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d14' and dispatch_type = 'initial_order') as init_b,
         (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d13' and dispatch_type = 'service_round') as round_c,
         (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d12' and dispatch_type = 'void') as void_d,
         (select (res ->> 'round_id')::uuid from t_n3) as round_c_round;
update kitchen_print_dispatches
  set created_at = now() - interval '1 hour'
  where id in (select unnest(array[init_a, init_b, round_c, void_d]) from t_nids);
create function pg_temp.drain_pages(p_dev uuid, p_tok text)
  returns table(seq int, id uuid, dtype text, first_has_more boolean)
  language plpgsql as $$
declare
  v_res jsonb; v_cur jsonb := null; v_page int := 0; v_e jsonb;
  v_seq int := 0; v_first boolean := null;
begin
  loop
    v_page := v_page + 1;
    exit when v_page > 60;
    if v_cur is null then
      v_res := app.pull_kitchen_print_dispatches(p_dev, p_tok, 1, null, null, null);
    else
      v_res := app.pull_kitchen_print_dispatches(p_dev, p_tok, 1,
                 (v_cur ->> 'created_at')::timestamptz, (v_cur ->> 'id')::uuid,
                 (v_cur ->> 'type_rank')::int);
    end if;
    exit when not (v_res ->> 'ok')::boolean;
    if v_first is null then
      v_first := (v_res ->> 'has_more')::boolean;
    end if;
    for v_e in select * from jsonb_array_elements(v_res -> 'dispatches') loop
      v_seq := v_seq + 1;
      seq := v_seq; id := (v_e ->> 'id')::uuid; dtype := v_e ->> 'dispatch_type';
      first_has_more := v_first;
      return next;
    end loop;
    exit when jsonb_array_length(v_res -> 'dispatches') = 0;
    exit when not (v_res ->> 'has_more')::boolean;
    v_cur := v_res -> 'next_cursor';
  end loop;
end;
$$;
create temp table t_drain as
  select * from pg_temp.drain_pages('00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2');
select ok(
  (select count(*) = 1 from t_drain where id = (select init_a from t_nids))
  and (select count(*) = 1 from t_drain where id = (select init_b from t_nids))
  and (select count(*) = 1 from t_drain where id = (select round_c from t_nids))
  and (select count(*) = 1 from t_drain where id = (select void_d from t_nids)),
  'N1: a limit-1 drain over TIED timestamps receives every dispatch EXACTLY once (no skips)');                   -- 98
select ok(
  (select count(*) = count(distinct id) from t_drain),
  'N2: no dispatch is duplicated across pages');                                                                 -- 99
select ok(
  (select array_agg(id order by seq) from (select seq, id from t_drain order by seq limit 4) f)
  = (select array[least(init_a, init_b), greatest(init_a, init_b), round_c, void_d] from t_nids),
  'N3: tied rows drain in the STABLE tuple order — initial < initial (id), round, void');                        -- 100
create temp table t_n4 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 1, null, null, null) as res;
select ok(
  (select jsonb_array_length(res -> 'dispatches') = 1 and (res ->> 'has_more')::boolean from t_n4),
  'N4: OWN ACTIVE CLAIMS never inflate the page past p_limit, and has_more stays truthful');                     -- 101
select ok(
  (select app.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 1, now(), gen_random_uuid(), 9) ->> 'error')
    = 'invalid_cursor'
  and (select app.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 1, now(), null, null) ->> 'error')
    = 'invalid_cursor',
  'N5: an invalid or partial cursor (bad rank / missing components) is REJECTED');                               -- 102
select is(
  (select app.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 51, null, null, null) ->> 'error'),
  'invalid_limit', 'N6: p_limit stays capped at 50');                                                            -- 103

-- ===== O. VOID vs original: no resurrection, ever ===========================
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d21',
  '00000000-0000-0000-0000-0001c100d001', 'c1-o1', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
create temp table t_o1 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null) as res;
create temp table t_oids as
  select (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d21' and dispatch_type = 'initial_order') as f_init;
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                   where (e ->> 'id')::uuid = (select f_init from t_oids)) from t_o1)
  and (select claimed_by_device_id = '00000000-0000-0000-0000-0001c100d001'
       from kitchen_print_dispatches where id = (select f_init from t_oids)),
  'O1: device 1 ACTIVELY CLAIMS the original initial ticket');                                                   -- 104
select app.void_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d21',
  '00000000-0000-0000-0000-0001c100d001', 'c1-vo21', 'changed mind', null);
select ok(
  (select d.superseded_by_dispatch_id = v.id
       and d.claimed_by_device_id = '00000000-0000-0000-0000-0001c100d001'
       and d.claimed_at is not null
   from kitchen_print_dispatches d,
        kitchen_print_dispatches v
   where d.id = (select f_init from t_oids)
     and v.order_id = '00000000-0000-0000-0000-0001c1000d21' and v.dispatch_type = 'void'),
  'O2: the VOID links the ACTIVELY CLAIMED original (claim provenance preserved, never erased)');                -- 105
create temp table t_o3 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null, null) as res;
select ok(
  (select not exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                       where (e ->> 'id')::uuid = (select f_init from t_oids))
      and exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                   where e ->> 'dispatch_type' = 'void'
                     and e ->> 'order_id' = '00000000-0000-0000-0000-0001c1000d21')
   from t_o3),
  'O3: another device can never claim the superseded original — but pulls the VOID');                            -- 106
create temp table t_o4 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select f_init from t_oids), 'imported', null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_o4)
  and (select superseded_by_dispatch_id is not null and last_client_status = 'imported'
       from kitchen_print_dispatches where id = (select f_init from t_oids)),
  'O4: the claim OWNER may still acknowledge its already-imported original; supersession is NEVER cleared');     -- 107
update kitchen_print_dispatches
  set claim_expires_at = now() - interval '1 minute'
  where id = (select f_init from t_oids);
create temp table t_o5 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null, null) as res;
select ok(
  (select not exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                       where (e ->> 'id')::uuid = (select f_init from t_oids)) from t_o5),
  'O5: even after the claim EXPIRES, stale-claim recovery cannot resurrect a superseded original');              -- 108
create temp table t_o6 as
  select app.void_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d21',
    '00000000-0000-0000-0000-0001c100d001', 'c1-vo21', 'changed mind', null) as res;
select ok(
  (select (res ->> 'idempotency_replay')::boolean from t_o6)
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d21' and dispatch_type = 'void')
  and (select count(*) = 1 from audit_events
        where action = 'kitchen.dispatch_void_created'
          and organization_id = '00000000-0000-0000-0000-0001c1000a00'
          and restaurant_id = '00000000-0000-0000-0000-0001c1000a10'
          and branch_id = '00000000-0000-0000-0000-0001c1000a2b'
          and new_values ->> 'order_code'
              = '#' || upper(right(replace('00000000-0000-0000-0000-0001c1000d21', '-', ''), 6))),
  'O6: a VOID replay is idempotent — no duplicate void, no repeated supersession, no duplicate audit');          -- 109
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d22',
  '00000000-0000-0000-0000-0001c100d001', 'c1-o2', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
select app.pull_kitchen_print_dispatches(
  '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null);
select app.acknowledge_kitchen_print_dispatch(
  '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
  (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d22' and dispatch_type = 'initial_order'),
  'transport_accepted', null);
select app.void_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d22',
  '00000000-0000-0000-0000-0001c100d001', 'c1-vo22', 'printed then voided', null);
select ok(
  (select completed_at is not null and superseded_by_dispatch_id is null
   from kitchen_print_dispatches
   where order_id = '00000000-0000-0000-0000-0001c1000d22' and dispatch_type = 'initial_order')
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = '00000000-0000-0000-0000-0001c1000d22' and dispatch_type = 'void')
  and (select status = 'voided' from orders where id = '00000000-0000-0000-0000-0001c1000d22'),
  'O7: a COMPLETED original stays unlinked history; the VOID slip still dispatches; order state is the RPC''s'); -- 110
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d23',
  '00000000-0000-0000-0000-0001c100d001', 'c1-o3', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
select app.pull_kitchen_print_dispatches(
  '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null);
select app.acknowledge_kitchen_print_dispatch(
  '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
  (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d23' and dispatch_type = 'initial_order'),
  'possibly_printed', 'crash_during_send');
select app.void_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d23',
  '00000000-0000-0000-0000-0001c100d001', 'c1-vo23', 'ambiguous then voided', null);
create temp table t_o8 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2', 20, null, null, null) as res;
select ok(
  (select d.superseded_by_dispatch_id = v.id
       and d.last_client_status = 'possibly_printed'
       and d.claim_expires_at is null
   from kitchen_print_dispatches d, kitchen_print_dispatches v
   where d.order_id = '00000000-0000-0000-0000-0001c1000d23' and d.dispatch_type = 'initial_order'
     and v.order_id = '00000000-0000-0000-0000-0001c1000d23' and v.dispatch_type = 'void')
  and (select not exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                           where e ->> 'order_id' = '00000000-0000-0000-0000-0001c1000d23'
                             and e ->> 'dispatch_type' = 'initial_order')
          and exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                       where e ->> 'order_id' = '00000000-0000-0000-0000-0001c1000d23'
                         and e ->> 'dispatch_type' = 'void')
       from t_o8),
  'O8: a possibly_printed original is LINKED to the void, stays sticky-ambiguous, never re-serves; the VOID prints'); -- 111

-- ===== P. readiness selection + retention ===================================
-- CORRECTION-001 cleanup (deterministic shadow test): make the qualifying
-- 80mm report (device d001) STRICTLY OLDER than the non-qualifying 58mm report
-- (device d005) — but still fresh — instead of relying on a tied transaction
-- timestamp. Under the CORRECT qualifying selection the 80mm report is still
-- chosen; under a regressed newest-report-wins selection the newer 58mm would
-- shadow it and this test would FAIL, which is exactly the regression P1 must
-- catch.
update kitchen_printer_readiness_reports
  set reported_at = now() - interval '5 minutes', expires_at = now() + interval '5 minutes'
  where device_id = '00000000-0000-0000-0000-0001c100d001';
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d005', 'tok-c1-posp2',
  'kitchen_printer_only_v1', 'build-58', 'kitchen_ticket',
  'network', '58mm', repeat('cd', 16), true, 0, 1);
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c1000e01';
create temp table t_p1c as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a2b') as res;
reset role;
select ok(
  -- the fixture genuinely presents a NEWER non-qualifying report:
  (select r58.reported_at > r80.reported_at
     from kitchen_printer_readiness_reports r58, kitchen_printer_readiness_reports r80
     where r58.device_id = '00000000-0000-0000-0000-0001c100d005'
       and r80.device_id = '00000000-0000-0000-0000-0001c100d001')
  -- yet the OLDER qualifying 80mm report is still selected, never shadowed:
  and (select not ((res -> 'to_printer_only' -> 'blockers') @> '"paper_width_80mm_required"'::jsonb)
      and (res -> 'readiness_report' ->> 'qualifying')::boolean
      and res -> 'readiness_report' ->> 'paper_width' = '80mm'
   from t_p1c),
  'P1: a NEWER 58mm report can never SHADOW another POS''s valid fresh 80mm report');                            -- 112
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d24',
  '00000000-0000-0000-0000-0001c100d001', 'c1-p2', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
update kitchen_print_dispatches
  set created_at = now() - interval '40 days'
  where order_id = '00000000-0000-0000-0000-0001c1000d24' and dispatch_type = 'initial_order';
create temp table t_pp2 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null) as res;
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                   where e ->> 'order_id' = '00000000-0000-0000-0000-0001c1000d24') from t_pp2)
  and (select claimed_by_device_id = '00000000-0000-0000-0000-0001c100d001'
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d24' and dispatch_type = 'initial_order'),
  'P2: a >30-day-old UNRESOLVED dispatch is STILL pullable (unresolved work never ages out)');                   -- 113
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c1000e01';
create temp table t_pp3 as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a2b') as res;
reset role;
select ok(
  (select (res -> 'counts' ->> 'unresolved_dispatches')::int from t_pp3)
  = (select count(*)::int from kitchen_print_dispatches
      where organization_id = '00000000-0000-0000-0000-0001c1000a00'
        and branch_id = '00000000-0000-0000-0000-0001c1000a2b'
        and completed_at is null and superseded_by_dispatch_id is null),
  'P3: transition blockers count unresolved rows with NO age filter (the 40-day row still blocks)');             -- 114
update kitchen_print_dispatches
  set created_at = now() - interval '40 days'
  where order_id = '00000000-0000-0000-0000-0001c1000d04' and dispatch_type = 'initial_order';
create temp table t_pp4 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null) as res;
select ok(
  exists (select 1 from kitchen_print_dispatches
           where order_id = '00000000-0000-0000-0000-0001c1000d04' and completed_at is not null)
  and (select not exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                           where e ->> 'order_id' = '00000000-0000-0000-0000-0001c1000d04') from t_pp4),
  'P4: a >30-day COMPLETED row remains permanent HISTORY (still stored, still excluded from the feed)');         -- 115
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001c1000a3c', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', 'Branch Q (printer-only)');
update branches set kitchen_workflow_mode = 'printer_only'
  where id = '00000000-0000-0000-0000-0001c1000a3c';
-- KITCHEN-MODE-001C3B1A: branch Q's kitchen 80mm assignment for the P5 tests.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-0000-0001c1000bc3', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a3c', 'C1 Kitchen 80 Q', 'network', 'kitchen', '80mm', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001c100d006', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a3c', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001c100c006', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a3c', '00000000-0000-0000-0000-0001c100d006', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0001c100e006', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a3c', '00000000-0000-0000-0000-0001c100d006', '00000000-0000-0000-0000-0001c100c006', app.hash_provisioning_secret('tok-c1-posq'), true, null);
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d006', 'tok-c1-posq',
  'kitchen_printer_only_v1', 'build-q', 'kitchen_ticket',
  'network', '80mm', repeat('ee', 16), true, 0, 1,
  '00000000-0000-0000-0000-0001c1000bc3');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c1000e01';
create temp table t_p5a as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a3c') as res;
reset role;
select ok(
  (select not ((res -> 'to_printer_only' -> 'blockers') @> '"no_fresh_pos_readiness"'::jsonb)
      and (res -> 'readiness_report' ->> 'qualifying')::boolean from t_p5a),
  'P5a: a live, qualifying POS readiness report satisfies the blocker');                                         -- 116
update branches set kitchen_workflow_mode_revision = 2
  where id = '00000000-0000-0000-0000-0001c1000a3c';
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c1000e01';
create temp table t_p5b as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a3c') as res;
reset role;
select ok(
  (select (res -> 'to_printer_only' -> 'blockers') @> '"stale_mode_revision"'::jsonb from t_p5b),
  'P5b: after a revision bump the report is diagnosed STALE, not silently accepted');                            -- 117
select is(
  (select app.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c100d006', 'tok-c1-posq', 20, null, null, null) ->> 'error'),
  'readiness_required', 'P5c: the PULL rechecks readiness.mode_revision against the branch');                    -- 118
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d006', 'tok-c1-posq',
  'kitchen_printer_only_v1', 'build-q2', 'kitchen_ticket',
  'network', '80mm', repeat('ee', 16), true, 0, 2,
  '00000000-0000-0000-0000-0001c1000bc3');
select ok(
  (select (res ->> 'ok')::boolean and jsonb_array_length(res -> 'dispatches') = 0
   from (select app.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c100d006', 'tok-c1-posq', 20, null, null, null) as res) s),
  'P5d: a re-report at the CURRENT revision restores the claim path');                                           -- 119
update devices set is_active = false where id = '00000000-0000-0000-0000-0001c100d006';
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c1000e01';
create temp table t_p5e as
  select app.get_kitchen_workflow_transition_readiness(
    '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10',
    '00000000-0000-0000-0000-0001c1000a3c') as res;
reset role;
select ok(
  (select (res -> 'to_printer_only' -> 'blockers') @> '"no_fresh_pos_readiness"'::jsonb from t_p5e),
  'P5e: a DEACTIVATED device''s report stops counting — readiness demands a LIVE reporter');                     -- 120

-- ===== Q. acknowledgement extras ============================================
select is(
  (select app.acknowledge_kitchen_print_dispatch(
     '00000000-0000-0000-0000-0001c100d002', 'tok-c1-kdsp',
     (select f_init from t_oids), 'imported', null) ->> 'error'),
  'invalid_session', 'Q1: a KDS device is explicitly DENIED acknowledgement');                                   -- 121
select app.submit_order(
  '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d25',
  '00000000-0000-0000-0000-0001c100d001', 'c1-q2', 'takeaway', null, null, 'ILS', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[]}]'::jsonb,
  500, 0, 0, 500, null);
select app.pull_kitchen_print_dispatches(
  '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null);
create temp table t_q2 as
  select app.acknowledge_kitchen_print_dispatch(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
    (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d25' and dispatch_type = 'initial_order'),
    'blocked_configuration', 'printer_not_configured') as res;
select ok(
  (select (res ->> 'ok')::boolean and not (res ->> 'completed')::boolean from t_q2)
  and (select last_client_status = 'blocked_configuration'
           and last_error_code = 'printer_not_configured'
           and completed_at is null and claim_expires_at is not null
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d25' and dispatch_type = 'initial_order'),
  'Q2: blocked_configuration is recorded, unresolved, and keeps the natural claim expiry');                      -- 122
select is(
  (select app.acknowledge_kitchen_print_dispatch(
     '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp',
     (select id from kitchen_print_dispatches where order_id = '00000000-0000-0000-0000-0001c1000d25' and dispatch_type = 'initial_order'),
     'failed_retryable', 'NOT VALID!!') ->> 'error'),
  'invalid_error_code', 'Q3: a malformed error code is rejected (allowlisted shape only)');                      -- 123

-- ===== R. full device-liveness negative matrix (readiness probe) ============
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001c100d007', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001c100c007', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d007', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0001c100e007', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d007', '00000000-0000-0000-0000-0001c100c007', app.hash_provisioning_secret('tok-c1-neg7'), true, null);
select ok(
  (select (app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d007', 'tok-c1-neg7',
    'kitchen_printer_only_v1', 'b7', 'kitchen_ticket', 'network', '80mm',
    repeat('77', 16), true, 0, 1) ->> 'ok')::boolean),
  'R0: the liveness-matrix device reports successfully at baseline');                                            -- 124
update device_sessions set expires_at = now() - interval '1 minute' where id = '00000000-0000-0000-0000-0001c100e007';
select is(
  (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d007', 'tok-c1-neg7',
    'kitchen_printer_only_v1', 'b7', 'kitchen_ticket', 'network', '80mm',
    repeat('77', 16), true, 0, 1) ->> 'error'),
  'invalid_session', 'R1: an EXPIRED session is denied (indistinguishably)');                                    -- 125
update device_sessions set expires_at = null, revoked_at = now() where id = '00000000-0000-0000-0000-0001c100e007';
select is(
  (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d007', 'tok-c1-neg7',
    'kitchen_printer_only_v1', 'b7', 'kitchen_ticket', 'network', '80mm',
    repeat('77', 16), true, 0, 1) ->> 'error'),
  'invalid_session', 'R2: a REVOKED session is denied');                                                         -- 126
update device_sessions set revoked_at = null, is_active = false where id = '00000000-0000-0000-0000-0001c100e007';
select is(
  (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d007', 'tok-c1-neg7',
    'kitchen_printer_only_v1', 'b7', 'kitchen_ticket', 'network', '80mm',
    repeat('77', 16), true, 0, 1) ->> 'error'),
  'invalid_session', 'R3: an INACTIVE session is denied');                                                       -- 127
update device_sessions set is_active = true where id = '00000000-0000-0000-0000-0001c100e007';
update device_pairings set status = 'revoked' where id = '00000000-0000-0000-0000-0001c100c007';
select is(
  (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d007', 'tok-c1-neg7',
    'kitchen_printer_only_v1', 'b7', 'kitchen_ticket', 'network', '80mm',
    repeat('77', 16), true, 0, 1) ->> 'error'),
  'invalid_session', 'R4: a REVOKED pairing is denied');                                                         -- 128
update device_pairings set status = 'active' where id = '00000000-0000-0000-0000-0001c100c007';
update devices set is_active = false where id = '00000000-0000-0000-0000-0001c100d007';
select is(
  (select app.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0001c100d007', 'tok-c1-neg7',
    'kitchen_printer_only_v1', 'b7', 'kitchen_ticket', 'network', '80mm',
    repeat('77', 16), true, 0, 1) ->> 'error'),
  'invalid_session', 'R5: a DEACTIVATED device is denied');                                                      -- 129

-- ===== S. structural FK negatives ===========================================
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a1a',
             '00000000-0000-0000-0000-0001c1000d01', 'initial_order', '{"v":1}'::jsonb, 'x:s1') $$,
  '23503', NULL, 'S1: a CROSS-BRANCH order reference is structurally impossible');                               -- 130
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, service_round_id, dispatch_type, money_free_payload, idempotency_key)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d05',
             (select round_c_round from t_nids),
             'service_round', '{"v":1}'::jsonb, 'x:s2') $$,
  '23503', NULL, 'S2: a service-round dispatch cannot reference ANOTHER order''s round');                        -- 131
select throws_ok(
  $$ update kitchen_print_dispatches
       set claimed_at = now(), claimed_by_device_id = '00000000-0000-0000-0000-0001c1deadd0', claim_expires_at = now() + interval '10 minutes'
       where order_id = '00000000-0000-0000-0000-0001c1000d0c' and dispatch_type = 'initial_order' $$,
  '23503', NULL, 'S3: a claim by a NONEXISTENT device is structurally impossible');                              -- 132
select throws_ok(
  $$ update kitchen_print_dispatches
       set claimed_at = now(), claimed_by_device_id = '00000000-0000-0000-0000-0001c100d003', claim_expires_at = now() + interval '10 minutes'
       where order_id = '00000000-0000-0000-0000-0001c1000d0c' and dispatch_type = 'initial_order' $$,
  '23503', NULL, 'S4: a claim by ANOTHER BRANCH''s device is structurally impossible');                          -- 133
select throws_ok(
  $$ update kitchen_print_dispatches
       set superseded_by_dispatch_id = '00000000-0000-0000-0000-0001c1deadbe'
       where order_id = '00000000-0000-0000-0000-0001c1000d0c' and dispatch_type = 'initial_order' $$,
  '23503', NULL, 'S5: a DANGLING supersession target is structurally impossible');                               -- 134
select throws_ok(
  $$ insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
     values ('00000000-0000-0000-0000-0001c15e1f00', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d0c', 'initial_order', '{"v":1}'::jsonb, 'x:s6',
             '00000000-0000-0000-0000-0001c15e1f00') $$,
  '23514', NULL, 'S6: SELF-supersession is rejected by CHECK');                                                  -- 135
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d0a', 'initial_order', '{"v":1}'::jsonb, 'x:s7',
             (select id from kitchen_print_dispatches
               where order_id = '00000000-0000-0000-0000-0001c1000d0a' and dispatch_type = 'initial_order')) $$,
  '23514', NULL, 'S7: supersession must target a VOID dispatch — an initial can never supersede');               -- 136
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d26', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d001', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'takeaway', 'submitted', 'ILS', 100, 0, 0, 100, 'c1-d26', 1);
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key) values
  ('00000000-0000-0000-0000-0001c1a11d01', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000d26', 'void', '{"v":1,"kind":"void"}'::jsonb, 'x:v1-od26'),
  ('00000000-0000-0000-0000-0001c1a11d02', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000d26', 'void', '{"v":1,"kind":"void"}'::jsonb, 'x:v2-od26');
update kitchen_print_dispatches
  set superseded_by_dispatch_id = '00000000-0000-0000-0000-0001c1a11d02'
  where id = '00000000-0000-0000-0000-0001c1a11d01';
select throws_ok(
  $$ insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, superseded_by_dispatch_id)
     values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
             '00000000-0000-0000-0000-0001c1000d26', 'initial_order', '{"v":1}'::jsonb, 'x:s8',
             '00000000-0000-0000-0000-0001c1a11d01') $$,
  '23514', NULL, 'S8: a supersession CHAIN (target itself superseded) is rejected — cycles are impossible');     -- 137

-- ===== T. guard canaries + prep allowlist ===================================
create function pg_temp.guard_rejects(p_payload jsonb) returns boolean
  language plpgsql as $$
begin
  insert into public.kitchen_print_dispatches
    (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
  values
    ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
     '00000000-0000-0000-0000-0001c1000d26', 'initial_order', p_payload, 'x:guard-' || md5(p_payload::text));
  delete from public.kitchen_print_dispatches where idempotency_key = 'x:guard-' || md5(p_payload::text);
  return false;
exception when check_violation then
  return true;
end;
$$;
select ok(
  (select bool_and(pg_temp.guard_rejects(jsonb_build_object(k, 1)))
   from unnest(array[
     'unitPrice', 'unit-price', 'priceMinor', 'totalValue', 'amountDue',
     'paymentInfo', 'taxAmount', 'serviceFee', 'tipAmount', 'customerPhone',
     'deliveryAddress', 'bluetoothAddress', 'connectionConfig', 'apiKey',
     'accessToken']) as k),
  'T1: every CamelCase / kebab / dotted hostile variant is rejected after normalization');                       -- 138
select ok(
  pg_temp.guard_rejects('{"a": [{"b": {"amountDue": 1}}]}'::jsonb)
  and pg_temp.guard_rejects('{"items": [{"meta": {"access-token": "x"}}]}'::jsonb),
  'T2: nested and array-borne hostile variants are rejected at every depth');                                    -- 139
insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
  values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
          '00000000-0000-0000-0000-0001c1000d26', 'initial_order',
          '{"tenderness": "extra", "chicken_tenders": 2, "tenderloin_name": "x", "quantity": 3, "round_number": 1}'::jsonb,
          'x:t3');
select is(
  (select count(*)::int from kitchen_print_dispatches where idempotency_key = 'x:t3'),
  1, 'T3: token-boundary matching never false-positives on tenderness / chicken_tenders / tenderloin_name');     -- 140
select throws_ok(
  $$ update kitchen_print_dispatches
       set money_free_payload = money_free_payload || '{"serviceFee": 1}'::jsonb
       where idempotency_key = 'x:t3' $$,
  '23514', NULL, 'T4: the guard covers UPDATE — a hostile key can never be introduced later');                   -- 141
create temp table t_t5 as
  select app.submit_order(
    '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c1000d27',
    '00000000-0000-0000-0000-0001c100d001', 'c1-t5', 'takeaway', null, null, 'ILS', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0001c10000f1","quantity":1,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Falafel","modifiers":[],"prep_snapshot":[{"name":"Extra tahini","quantity":2,"unit":"tbsp","internalNote":"x","supplierCode":"S9"}]}]'::jsonb,
    500, 0, 0, 500, null) as res;
select ok(
  (select (res ->> 'ok')::boolean from t_t5)
  and (select money_free_payload -> 'items' -> 0 -> 'prep'
        = '[{"name": "Extra tahini", "quantity": 2, "unit": "tbsp"}]'::jsonb
       from kitchen_print_dispatches
       where order_id = '00000000-0000-0000-0000-0001c1000d27' and dispatch_type = 'initial_order'),
  'T5: only the ALLOWLISTED prep fields survive into the dispatch — unknown client keys are dropped');           -- 142
select ok(
  app.kitchen_prep_projection('[{"name":"A","quantity":1,"unit":"g","x":9},{"junk":true},"notobj"]'::jsonb)
    = '[{"name": "A", "quantity": 1, "unit": "g"}]'::jsonb
  and app.kitchen_prep_projection('{"name":"A"}'::jsonb) is null
  and app.kitchen_prep_projection('[{"name":"B","quantity":"9"}]'::jsonb) = '[{"name": "B"}]'::jsonb,
  'T6: the projection is strict — non-arrays null out, non-objects and non-numeric quantities are dropped');     -- 143

-- ===== U. compact all-lowercase hostile keys (review cleanup) ================
-- CORRECTION-001 cleanup: a compact all-lowercase compound carries no boundary
-- to split on, so normalization leaves it a single token; the explicit
-- compact-compound deny list must reject each spelling. (T1 proved only the
-- boundary-carrying CamelCase/kebab/dotted variants.)
select ok(
  (select bool_and(pg_temp.guard_rejects(jsonb_build_object(k, 1)))
   from unnest(array[
     'unitprice', 'priceminor', 'totalvalue', 'amountdue', 'paymentinfo',
     'taxamount', 'servicefee', 'tipamount', 'customerphone', 'deliveryaddress',
     'bluetoothaddress', 'connectionconfig', 'apikey', 'accesstoken',
     'currencycode', 'paymentmethod']) as k),
  'U1: every COMPACT all-lowercase hostile compound is rejected (explicit deny list)');                          -- 144
select ok(
  pg_temp.guard_rejects('{"meta_apikey_field": "x"}'::jsonb)
  and pg_temp.guard_rejects('{"a": [{"b": {"amountdue": 1}}]}'::jsonb),
  'U2: a compact compound as a sub-token or nested/array key is rejected too');                                  -- 145
insert into kitchen_print_dispatches (organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key)
  values ('00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b',
          '00000000-0000-0000-0000-0001c1000d26', 'initial_order',
          '{"tenderness": "x", "chicken_tenders": 2, "tenderloin_name": "y", "quantity": 3, "round_number": 1, "order_note": "z"}'::jsonb,
          'x:u3');
select is(
  (select count(*)::int from kitchen_print_dispatches where idempotency_key = 'x:u3'),
  1, 'U3: the compact deny list never false-positives on tenderness / chicken_tenders / tenderloin_name / quantity / round_number / order_note'); -- 146

-- ===== V. prep projection value typing (review cleanup) =====================
-- CORRECTION-001 cleanup: name/unit survive ONLY as real JSON strings;
-- object/array/boolean values are DROPPED, never serialized to JSON text.
select is(
  app.kitchen_prep_projection('[{"name": {"amountdue": 5}, "quantity": 1}]'::jsonb),
  '[{"quantity": 1}]'::jsonb,
  'V1: an OBJECT-valued prep name is DROPPED (never serialized to text)');                                       -- 147
select is(
  app.kitchen_prep_projection('[{"name": "A", "unit": ["host", 1]}]'::jsonb),
  '[{"name": "A"}]'::jsonb,
  'V2: an ARRAY-valued prep unit is DROPPED');                                                                   -- 148
select is(
  app.kitchen_prep_projection('[{"name": "Extra tahini", "unit": "tbsp", "quantity": 2}]'::jsonb),
  '[{"name": "Extra tahini", "quantity": 2, "unit": "tbsp"}]'::jsonb,
  'V3: valid string name/unit and a numeric quantity are RETAINED');                                             -- 149
select is(
  app.kitchen_prep_projection('[{"name": "A", "quantity": {"price": 1}}]'::jsonb),
  '[{"name": "A"}]'::jsonb,
  'V4: an OBJECT-valued quantity is DROPPED (only a JSON number survives)');                                     -- 150

-- ===== W. note cap is payload-only, never a mutation (review cleanup) =======
select public.sync_push('00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c100d001',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'c1-w1', 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', '00000000-0000-0000-0000-0001c1000d31', 'order_type', 'takeaway',
      'currency_code', 'ILS', 'notes', repeat('o', 800),
      'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', '00000000-0000-0000-0000-0001c10000f1', 'quantity', 1,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel',
        'notes', repeat('i', 800)))))));
select ok(
  (select length(money_free_payload ->> 'order_note') = 500
      and length(money_free_payload -> 'items' -> 0 ->> 'note') = 500
   from kitchen_print_dispatches
   where order_id = '00000000-0000-0000-0000-0001c1000d31' and dispatch_type = 'initial_order'),
  'W1: an order note and an item note longer than 500 chars are each CAPPED to 500 in the payload copy');        -- 151
select ok(
  (select length(notes) = 800 from orders where id = '00000000-0000-0000-0000-0001c1000d31')
  and (select length(notes) = 800 from order_items
        where order_id = '00000000-0000-0000-0000-0001c1000d31' and service_round_id is null),
  'W2: the AUTHORITATIVE stored order/item notes keep their full length — the cap never mutated them');          -- 152
select ok(
  (select not (money_free_payload ? 'order_note')
      and money_free_payload::text not ilike '%phone%'
      and money_free_payload::text not ilike '%address%'
      and money_free_payload::text not like '%_minor%'
   from kitchen_print_dispatches
   where order_id = '00000000-0000-0000-0000-0001c1000d0e' and dispatch_type = 'initial_order'),
  'W3: an empty note stays omitted and the note-bearing payload introduces no money/privacy key');               -- 153

-- ===== X. revoked-pairing pull/ack liveness (review cleanup) ================
-- The pull and ack liveness JOINs are hand-duplicated; R only exercised the
-- report RPC's copy. Prove pull and ack both reject a revoked-pairing device
-- with the same non-enumerating invalid_session posture, never corrupt the
-- dispatch, and leave the claim-expiry recovery path open.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001c100d008', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001c100c008', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d008', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0001c100e008', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d008', '00000000-0000-0000-0000-0001c100c008', app.hash_provisioning_secret('tok-c1-x8'), true, null);
select app.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0001c100d008', 'tok-c1-x8',
  'kitchen_printer_only_v1', 'build-x8', 'kitchen_ticket',
  'network', '80mm', repeat('88', 16), true, 0, 1,
  '00000000-0000-0000-0000-0001c1000ba2');
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c1000d32', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c100d008', '00000000-0000-0000-0000-0001c10c5001', '00000000-0000-0000-0000-0001c10ef002', '00000000-0000-0000-0000-0001c1000f02', 'takeaway', 'submitted', 'ILS', 100, 0, 0, 100, 'c1-d32', 1);
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key) values
  ('00000000-0000-0000-0000-0001c1a11d32', '00000000-0000-0000-0000-0001c1000a00', '00000000-0000-0000-0000-0001c1000a10', '00000000-0000-0000-0000-0001c1000a2b', '00000000-0000-0000-0000-0001c1000d32', 'initial_order', '{"v":1,"kind":"initial_order"}'::jsonb, 'initial:00000000-0000-0000-0000-0001c1000d32');
-- device X claims its dispatch while its pairing is still active.
select app.pull_kitchen_print_dispatches('00000000-0000-0000-0000-0001c100d008', 'tok-c1-x8', 20, null, null, null);
-- now revoke the pairing.
update device_pairings set status = 'revoked', revoked_at = now() where id = '00000000-0000-0000-0000-0001c100c008';
select is(
  (select app.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c100d008', 'tok-c1-x8', 20, null, null, null) ->> 'error'),
  'invalid_session', 'X1: PULL by a revoked-pairing device returns the non-enumerating invalid_session');        -- 154
select is(
  (select app.acknowledge_kitchen_print_dispatch(
     '00000000-0000-0000-0000-0001c100d008', 'tok-c1-x8',
     '00000000-0000-0000-0000-0001c1a11d32', 'transport_accepted', null) ->> 'error'),
  'invalid_session', 'X2: ACK by a revoked-pairing device returns the same invalid_session (no payload, no state change)'); -- 155
select ok(
  (select claimed_by_device_id = '00000000-0000-0000-0000-0001c100d008'
      and completed_at is null and last_client_status is null
      and money_free_payload = '{"v":1,"kind":"initial_order"}'::jsonb
   from kitchen_print_dispatches where id = '00000000-0000-0000-0000-0001c1a11d32'),
  'X3: the dispatch ownership/state/payload is not corrupted by the denied calls');                              -- 156
-- expire the revoked device's claim; backdate created_at so this dispatch is
-- the OLDEST candidate and therefore claimed within the pull limit regardless
-- of other fixture rows (the retention window was removed, so age never hides
-- an unresolved row).
update kitchen_print_dispatches
  set claim_expires_at = now() - interval '1 minute', created_at = now() - interval '100 days'
  where id = '00000000-0000-0000-0000-0001c1a11d32';
-- capture the recovery pull in its OWN statement first (the pull is a
-- side-effecting claim; evaluating it in a sibling AND-operand would leave its
-- ordering vs the state read unspecified).
create temp table t_x4 as
  select app.pull_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c100d001', 'tok-c1-posp', 20, null, null, null) as res;
select ok(
  (select exists (select 1 from jsonb_array_elements(res -> 'dispatches') e
                   where (e ->> 'id')::uuid = '00000000-0000-0000-0000-0001c1a11d32') from t_x4)
  and (select claimed_by_device_id = '00000000-0000-0000-0000-0001c100d001'
       from kitchen_print_dispatches where id = '00000000-0000-0000-0000-0001c1a11d32'),
  'X4: the claim-expiry recovery path stays open — a live POS reclaims the dispatch after the lease lapses');    -- 157

select * from finish();
rollback;
