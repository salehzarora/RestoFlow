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

select plan(80);

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
    'network', '80mm', repeat('ab', 16), true, 0, 1) as res;
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
  'network', '80mm', repeat('ab', 16), true, 0, 1);
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
  'network', '80mm', repeat('cd', 16), true, 0, 1);
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
  'network', '80mm', repeat('ef', 16), true, 0, 1);
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
  and not has_function_privilege('authenticated', 'app.kitchen_payload_offending_key(jsonb)', 'execute'),
  'the INTERNAL helpers are inaccessible to client roles');                                                      -- 77
select ok(
  has_function_privilege('authenticated', 'public.report_kitchen_printer_readiness(uuid,text,text,text,text,text,text,text,boolean,integer,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.pull_kitchen_print_dispatches(uuid,text,integer,timestamptz,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.acknowledge_kitchen_print_dispatch(uuid,text,uuid,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_kitchen_workflow_transition_readiness(uuid,uuid,uuid)', 'execute')
  and not has_function_privilege('anon', 'app.pull_kitchen_print_dispatches(uuid,text,integer,timestamptz,uuid)', 'execute')
  and not has_function_privilege('anon', 'app.report_kitchen_printer_readiness(uuid,text,text,text,text,text,text,text,boolean,integer,integer)', 'execute'),
  'grants: authenticated may execute the new RPCs; anon may not reach the app functions');                       -- 78
select ok(
  (select bool_and(p.prosecdef and p.proconfig::text like '%search_path%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('report_kitchen_printer_readiness', 'pull_kitchen_print_dispatches',
                        'acknowledge_kitchen_print_dispatch', 'get_kitchen_workflow_transition_readiness',
                        'submit_order', 'add_order_items', 'void_order', 'create_kitchen_dispatch'))
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = 'submit_order') = 1
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'app' and p.proname = 'void_order') = 1,
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

select * from finish();
rollback;
