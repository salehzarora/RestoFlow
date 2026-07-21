-- ============================================================================
-- KITCHEN-MODE-001C3A — pgTAP: trusted workflow revision + safe kitchen
-- observability foundation.
--
--   * device mode getter: additive server-authoritative mode_revision for
--     BOTH modes; envelope otherwise byte-compatible; invalid-session
--     taxonomy unchanged; KDS devices may still read; grant hygiene;
--   * member dispatch inspection: rank>0 read, scope-leak-free not_found,
--     closed filter/limit/cursor vocabularies, deterministic newest-first
--     keyset pagination, SAFE SCALAR fields only (never payload/claim
--     internals/idempotency keys);
--   * audit safe-surface: the 001C3 kitchen-mode scalars project; kitchen.%
--     money hardening intact; human-actor constraint + append-only intact;
--   * dormancy: NO setter exists; branches default kds/revision 1.
-- Session pinned to UTC; hex-only UUIDs; GUC conventions per house style.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(44);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0001c3a00a00', 'Org A', 'kmc3a-a', 'ILS'),
  ('00000000-0000-0000-0000-0001c3a00b00', 'Org B', 'kmc3a-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a00', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0001c3a00b10', '00000000-0000-0000-0000-0001c3a00b00', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001c3a00a1a', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', 'Branch P (printer-only)'),
  ('00000000-0000-0000-0000-0001c3a00b1a', '00000000-0000-0000-0000-0001c3a00b00', '00000000-0000-0000-0000-0001c3a00b10', 'Branch B');
-- privileged fixture flips (the ONLY write path; no setter exists).
update branches set kitchen_workflow_mode = 'printer_only',
                    kitchen_workflow_mode_revision = 4
  where id = '00000000-0000-0000-0000-0001c3a00a2b';

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0001c3a00e01', 'kmc3a-owner@example.test'),
  ('00000000-0000-0000-0000-0001c3a00e02', 'kmc3a-cashier-k@example.test'),
  ('00000000-0000-0000-0000-0001c3a00e03', 'kmc3a-owner-b@example.test'),
  ('00000000-0000-0000-0000-0001c3a00e04', 'kmc3a-cashier-p@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0001c3a00f01', '00000000-0000-0000-0000-0001c3a00e01', '00000000-0000-0000-0000-0001c3a00a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0001c3a00f02', '00000000-0000-0000-0000-0001c3a00e02', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', 'cashier'),
  ('00000000-0000-0000-0000-0001c3a00f03', '00000000-0000-0000-0000-0001c3a00e03', '00000000-0000-0000-0000-0001c3a00b00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0001c3a00f04', '00000000-0000-0000-0000-0001c3a00e04', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', 'cashier');

-- devices: pos@K d001, pos@P d002, kds@K d003.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001c3a0d001', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', 'pos'),
  ('00000000-0000-0000-0000-0001c3a0d002', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', 'pos'),
  ('00000000-0000-0000-0000-0001c3a0d003', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001c3a0c001', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', '00000000-0000-0000-0000-0001c3a0d001', 'active'),
  ('00000000-0000-0000-0000-0001c3a0c002', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a0d002', 'active'),
  ('00000000-0000-0000-0000-0001c3a0c003', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', '00000000-0000-0000-0000-0001c3a0d003', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0001c3a0e001', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', '00000000-0000-0000-0000-0001c3a0d001', '00000000-0000-0000-0000-0001c3a0c001', app.hash_provisioning_secret('tok-c3a-posk'), true, null),
  ('00000000-0000-0000-0000-0001c3a0e002', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a0d002', '00000000-0000-0000-0000-0001c3a0c002', app.hash_provisioning_secret('tok-c3a-posp'), true, null),
  ('00000000-0000-0000-0000-0001c3a0e003', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a1a', '00000000-0000-0000-0000-0001c3a0d003', '00000000-0000-0000-0000-0001c3a0c003', app.hash_provisioning_secret('tok-c3a-kdsk'), true, null);

insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('00000000-0000-0000-0000-0001c3a0ef04', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00e04', '00000000-0000-0000-0000-0001c3a00f04', 'Cashier P');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0001c3a0c504', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a0e002', '00000000-0000-0000-0000-0001c3a0ef04', '00000000-0000-0000-0000-0001c3a00f04', now() + interval '1 hour');

-- orders on branch P (dispatch FK targets).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision) values
  ('00000000-0000-0000-0000-0001c3a00d01', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a0d002', '00000000-0000-0000-0000-0001c3a0c504', '00000000-0000-0000-0000-0001c3a0ef04', '00000000-0000-0000-0000-0001c3a00f04', 'takeaway', 'submitted', 'ILS', 100, 0, 0, 100, 'c3a-o1', 1),
  ('00000000-0000-0000-0000-0001c3a00d02', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a0d002', '00000000-0000-0000-0000-0001c3a0c504', '00000000-0000-0000-0000-0001c3a0ef04', '00000000-0000-0000-0000-0001c3a00f04', 'takeaway', 'submitted', 'ILS', 200, 0, 0, 200, 'c3a-o2', 1);

-- dispatch ledger fixture (direct privileged inserts; payloads are money-free
-- and carry a DISTINCTIVE token to prove the inspection RPC never leaks them).
-- dA: unresolved initial (oldest). dC: unresolved possibly_printed (claimed).
-- dD: completed. dV: unresolved void (order 2). dE: superseded initial (by dV).
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, created_at) values
  ('00000000-0000-0000-0000-0001c3a0aa01', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00d01', 'initial_order', '{"v": 1, "kind": "initial_order", "items": [{"qty": 1, "name": "SecretFixtureDish"}]}'::jsonb, 'c3a:a', timestamptz '2026-07-20 10:00:00+00');
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, created_at, claimed_at, claimed_by_device_id, claim_expires_at, last_client_status, last_error_code) values
  ('00000000-0000-0000-0000-0001c3a0aa03', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00d01', 'void', '{"v": 1, "kind": "void", "void": true}'::jsonb, 'c3a:c', timestamptz '2026-07-20 10:02:00+00', timestamptz '2026-07-20 10:03:00+00', '00000000-0000-0000-0000-0001c3a0d002', null, 'possibly_printed', 'kitchen_transport_ambiguous');
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, created_at, completed_at, last_client_status) values
  ('00000000-0000-0000-0000-0001c3a0aa04', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00d01', 'initial_order', '{"v": 1, "kind": "initial_order", "items": []}'::jsonb, 'c3a:d', timestamptz '2026-07-20 10:01:00+00', timestamptz '2026-07-20 10:05:00+00', 'transport_accepted');
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, created_at) values
  ('00000000-0000-0000-0000-0001c3a0aa05', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00d02', 'void', '{"v": 1, "kind": "void", "void": true}'::jsonb, 'c3a:v', timestamptz '2026-07-20 10:04:00+00');
insert into kitchen_print_dispatches (id, organization_id, restaurant_id, branch_id, order_id, dispatch_type, money_free_payload, idempotency_key, created_at, superseded_by_dispatch_id) values
  ('00000000-0000-0000-0000-0001c3a0aa06', '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10', '00000000-0000-0000-0000-0001c3a00a2b', '00000000-0000-0000-0000-0001c3a00d02', 'initial_order', '{"v": 1, "kind": "initial_order", "items": []}'::jsonb, 'c3a:e', timestamptz '2026-07-20 09:59:00+00', '00000000-0000-0000-0000-0001c3a0aa05');

-- ===== A. device mode getter: additive mode_revision ========================
select is(
  (select public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d001', 'tok-c3a-posk') ->> 'kitchen_workflow_mode'),
  'kds', 'getter: kds branch still reports kds');                                                                -- 1
select is(
  (select (public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d001', 'tok-c3a-posk') ->> 'mode_revision')::int),
  1, 'getter: kds branch carries its server revision (default 1)');                                              -- 2
select is(
  (select array_agg(k order by k) from jsonb_object_keys(
     public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d001', 'tok-c3a-posk')) as k),
  array['entity','kitchen_workflow_mode','mode_revision','ok','server_ts'],
  'getter: success envelope = old keys + EXACTLY one additive mode_revision');                                   -- 3
select is(
  (select public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d002', 'tok-c3a-posp') ->> 'kitchen_workflow_mode'),
  'printer_only', 'getter: printer_only branch reports printer_only');                                           -- 4
select is(
  (select (public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d002', 'tok-c3a-posp') ->> 'mode_revision')::int),
  4, 'getter: printer_only branch carries the CURRENT server revision (4)');                                     -- 5
select is(
  (select jsonb_typeof(public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d002', 'tok-c3a-posp') -> 'mode_revision')),
  'number', 'getter: mode_revision is a JSON number (positive integer)');                                        -- 6

-- server-authoritative: a privileged bump is reflected immediately.
update branches set kitchen_workflow_mode_revision = 5
  where id = '00000000-0000-0000-0000-0001c3a00a2b';
select is(
  (select (public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d002', 'tok-c3a-posp') ->> 'mode_revision')::int),
  5, 'getter: revision is SERVER-AUTHORITATIVE (privileged bump reflected)');                                    -- 7

select is(
  (select public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d001', 'tok-wrong')),
  jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_workflow_mode'),
  'getter: bad token = UNCHANGED typed invalid_session (no mode_revision key)');                                 -- 8

-- expired session: same typed failure (RF-118 gate preserved).
update device_sessions set expires_at = now() - interval '1 hour'
  where id = '00000000-0000-0000-0000-0001c3a0e001';
select is(
  (select public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d001', 'tok-c3a-posk') ->> 'error'),
  'invalid_session', 'getter: EXPIRED session still fails closed (invalid_session)');                            -- 9
update device_sessions set expires_at = null
  where id = '00000000-0000-0000-0000-0001c3a0e001';

select is(
  (select public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d003', 'tok-c3a-kdsk') ->> 'kitchen_workflow_mode'),
  'kds', 'getter: a KDS device may still read its branch mode (behavior preserved)');                            -- 10
select is(
  (select public.get_device_kitchen_workflow_mode('00000000-0000-0000-0000-0001c3a0d002', 'tok-c3a-posk') ->> 'error'),
  'invalid_session', 'getter: token/device mismatch stays invalid_session');                                     -- 11
select ok(
  not has_function_privilege('anon', 'public.get_device_kitchen_workflow_mode(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'app.get_device_kitchen_workflow_mode(uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'public.get_device_kitchen_workflow_mode(uuid, text)', 'execute'),
  'getter: anon denied on BOTH signatures; authenticated granted');                                              -- 12

-- ===== B. member dispatch inspection ========================================
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c3a00e01';

-- default (unresolved) = dC (10:02), dA (10:00), dE? no — dE is superseded;
-- dV (10:04) IS unresolved. Newest-first: dV, dC, dA.
create temp table t_c3a_p1 as
  select public.list_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
    '00000000-0000-0000-0000-0001c3a00a2b') as r;
select is(
  (select jsonb_array_length(r -> 'dispatches') from t_c3a_p1),
  3, 'inspection: default filter = the 3 UNRESOLVED dispatches only');                                           -- 13
select is(
  (select array_agg(e ->> 'dispatch_id') from (
     select jsonb_array_elements(r -> 'dispatches') as e from t_c3a_p1) s),
  array['00000000-0000-0000-0000-0001c3a0aa05',
        '00000000-0000-0000-0000-0001c3a0aa03',
        '00000000-0000-0000-0000-0001c3a0aa01'],
  'inspection: deterministic NEWEST-FIRST (created_at, id) ordering');                                           -- 14
select is(
  (select array_agg(k order by k) from jsonb_object_keys((select r -> 'dispatches' -> 0 from t_c3a_p1)) as k),
  array['claimed','completed_at','created_at','dispatch_id','dispatch_type','last_client_status',
        'last_error_code','order_id','possibly_printed','superseded'],
  'inspection: row fields are EXACTLY the 10 safe scalars');                                                     -- 15
select ok(
  (select r::text not like '%SecretFixtureDish%'
      and r::text not like '%money_free_payload%'
      and r::text not like '%idempotency%'
      and r::text not like '%claimed_by_device_id%'
      and r::text not like '%c3a:%' from t_c3a_p1),
  'inspection: payload content, idempotency keys and claim internals NEVER leak');                               -- 16
select is(
  (select e ->> 'claimed' from (
     select jsonb_array_elements(r -> 'dispatches') as e from t_c3a_p1) s
    where e ->> 'dispatch_id' = '00000000-0000-0000-0000-0001c3a0aa03'),
  'true', 'inspection: the claimed possibly_printed row reports claimed=true');                                  -- 17
select is(
  (select e ->> 'possibly_printed' from (
     select jsonb_array_elements(r -> 'dispatches') as e from t_c3a_p1) s
    where e ->> 'dispatch_id' = '00000000-0000-0000-0000-0001c3a0aa03'),
  'true', 'inspection: the ambiguous hold surfaces possibly_printed=true');                                      -- 18

create temp table t_c3a_pp as
  select public.list_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
    '00000000-0000-0000-0000-0001c3a00a2b', 'possibly_printed') as r;
select is(
  (select array_agg(e ->> 'dispatch_id') from (
     select jsonb_array_elements(r -> 'dispatches') as e from t_c3a_pp) s),
  array['00000000-0000-0000-0000-0001c3a0aa03'],
  'inspection: possibly_printed filter isolates the hold');                                                      -- 19
select is(
  (select array_agg(e ->> 'dispatch_id') from (
     select jsonb_array_elements(
       public.list_kitchen_print_dispatches(
         '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
         '00000000-0000-0000-0000-0001c3a00a2b', 'completed') -> 'dispatches') as e) s),
  array['00000000-0000-0000-0000-0001c3a0aa04'],
  'inspection: completed filter');                                                                               -- 20
select is(
  (select array_agg(e ->> 'dispatch_id') from (
     select jsonb_array_elements(
       public.list_kitchen_print_dispatches(
         '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
         '00000000-0000-0000-0000-0001c3a00a2b', 'superseded') -> 'dispatches') as e) s),
  array['00000000-0000-0000-0000-0001c3a0aa06'],
  'inspection: superseded filter (void supersession evidence preserved)');                                       -- 21
select is(
  (select jsonb_array_length(
     public.list_kitchen_print_dispatches(
       '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
       '00000000-0000-0000-0000-0001c3a00a2b', 'all') -> 'dispatches')),
  5, 'inspection: all filter returns the whole ledger for the branch');                                          -- 22
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
     '00000000-0000-0000-0000-0001c3a00a2b', 'bogus') ->> 'error'),
  'invalid_status_filter', 'inspection: filter vocabulary is CLOSED');                                           -- 23
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
     '00000000-0000-0000-0000-0001c3a00a2b', null, 0) ->> 'error'),
  'invalid_limit', 'inspection: limit 0 rejected');                                                              -- 24
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
     '00000000-0000-0000-0000-0001c3a00a2b', null, 51) ->> 'error'),
  'invalid_limit', 'inspection: limit 51 rejected (max 50)');                                                    -- 25

-- keyset pagination: limit 1 over the 3 unresolved rows, walked to the end.
create temp table t_c3a_pg1 as
  select public.list_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
    '00000000-0000-0000-0000-0001c3a00a2b', null, 1) as r;
select ok(
  (select (r -> 'dispatches' -> 0 ->> 'dispatch_id') = '00000000-0000-0000-0000-0001c3a0aa05'
      and (r ->> 'has_more')::boolean
      and (r -> 'next_cursor') is not null from t_c3a_pg1),
  'inspection: page 1 = newest row, truthful has_more, cursor present');                                         -- 26
create temp table t_c3a_pg2 as
  select public.list_kitchen_print_dispatches(
    '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
    '00000000-0000-0000-0000-0001c3a00a2b', null, 1,
    (select ((r -> 'next_cursor' ->> 'created_at')::timestamptz) from t_c3a_pg1),
    (select ((r -> 'next_cursor' ->> 'id')::uuid) from t_c3a_pg1)) as r;
select ok(
  (select (r -> 'dispatches' -> 0 ->> 'dispatch_id') = '00000000-0000-0000-0000-0001c3a0aa03'
      and (r ->> 'has_more')::boolean from t_c3a_pg2),
  'inspection: page 2 continues WITHOUT overlap (deterministic keyset)');                                        -- 27
select ok(
  (select not (r ->> 'has_more')::boolean and (r -> 'next_cursor') = 'null'::jsonb
     from (select public.list_kitchen_print_dispatches(
       '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
       '00000000-0000-0000-0000-0001c3a00a2b', null, 1,
       (select ((r -> 'next_cursor' ->> 'created_at')::timestamptz) from t_c3a_pg2),
       (select ((r -> 'next_cursor' ->> 'id')::uuid) from t_c3a_pg2)) as r) s),
  'inspection: final page ends the walk (has_more=false, null cursor)');                                         -- 28
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
     '00000000-0000-0000-0000-0001c3a00a2b', null, 1, now(), null) ->> 'error'),
  'invalid_cursor', 'inspection: a HALF cursor is rejected (all-or-nothing)');                                   -- 29

-- authorization matrix.
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a99',
     '00000000-0000-0000-0000-0001c3a00a2b') ->> 'error'),
  'not_found', 'inspection: wrong restaurant scope = scope-leak-free not_found');                                -- 30
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c3a00e02';
select is(
  (select jsonb_array_length(
     public.list_kitchen_print_dispatches(
       '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
       '00000000-0000-0000-0000-0001c3a00a1a') -> 'dispatches')),
  0, 'inspection: a rank-1 member (cashier) may read ITS OWN branch (empty ledger)');                            -- 31
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
     '00000000-0000-0000-0000-0001c3a00a2b') ->> 'error'),
  'not_found', 'inspection: the SAME cashier gets not_found for a branch outside coverage');                     -- 32
set local app.current_app_user_id = '00000000-0000-0000-0000-0001c3a00e03';
select is(
  (select public.list_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
     '00000000-0000-0000-0000-0001c3a00a2b') ->> 'error'),
  'not_found', 'inspection: a CROSS-TENANT owner (org B) gets not_found');                                       -- 33
set local app.current_app_user_id = '';
select throws_ok(
  $$ select public.list_kitchen_print_dispatches(
       '00000000-0000-0000-0000-0001c3a00a00', '00000000-0000-0000-0000-0001c3a00a10',
       '00000000-0000-0000-0000-0001c3a00a2b') $$,
  '42501', null, 'inspection: an unauthenticated caller is a hard 42501');                                       -- 34
select ok(
  not has_function_privilege('anon', 'public.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)', 'execute')
  and not has_function_privilege('anon', 'app.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)', 'execute'),
  'inspection: anon denied on BOTH signatures; authenticated granted');                                          -- 35

-- ===== C. audit safe-surface ================================================
select ok(
  app.audit_action_has_detail('settings.branch.kitchen_mode_updated')
  and app.audit_action_has_detail('settings.branch.kitchen_mode_update_denied')
  and app.audit_action_has_detail('kitchen.dispatch_hold_resolved'),
  'audit: the 001C3 action family passes the detail gate (existing prefixes)');                                  -- 36
select is(
  app.audit_safe_detail('settings.branch.kitchen_mode_updated',
    '{"kitchen_workflow_mode": "printer_only", "kitchen_workflow_mode_revision": 2,
      "reason_code": "pilot_activation", "connection_config": {"host": "10.0.0.9"},
      "session_token": "zz", "printer_fingerprint": "abcd1234abcd1234"}'::jsonb),
  '{"kitchen_workflow_mode": "printer_only", "kitchen_workflow_mode_revision": 2, "reason_code": "pilot_activation"}'::jsonb,
  'audit: mode-change projection keeps ONLY the safe scalars (endpoints/tokens/fingerprints dropped)');          -- 37
select is(
  app.audit_safe_detail('kitchen.dispatch_hold_resolved',
    '{"resolution": "operator_confirmed_printed", "dispatch_type": "initial_order",
      "order_code": "#ABC123", "amount_minor": 500, "payload": {"items": []}}'::jsonb),
  '{"resolution": "operator_confirmed_printed", "dispatch_type": "initial_order", "order_code": "#ABC123"}'::jsonb,
  'audit: hold-resolution keeps resolution/dispatch_type/order_code; kitchen.% stays MONEY-FREE');               -- 38
select is(
  app.audit_safe_detail('some.unknown_action', '{"kitchen_workflow_mode": "kds"}'::jsonb),
  '{}'::jsonb, 'audit: unknown actions still project NOTHING');                                                  -- 39
select is(
  app.audit_safe_detail('settings.branch.updated',
    '{"kitchen_workflow_mode": "kds", "kitchen_workflow_mode_revision": 1, "pin_hash": "x"}'::jsonb),
  '{"kitchen_workflow_mode": "kds", "kitchen_workflow_mode_revision": 1}'::jsonb,
  'audit: full-row settings.branch.updated snapshots now surface the mode scalars (documented)');                -- 40
select throws_ok(
  $$ insert into audit_events (organization_id, action, device_id)
     values ('00000000-0000-0000-0000-0001c3a00a00', 'kitchen.dispatch_created',
             '00000000-0000-0000-0000-0001c3a0d002') $$,
  '23514', null, 'audit: the RF-017 HUMAN-ACTOR constraint is UNCHANGED (device-only actor impossible)');        -- 41
insert into audit_events (organization_id, action, actor_app_user_id, new_values)
  values ('00000000-0000-0000-0000-0001c3a00a00', 'settings.branch.kitchen_mode_updated',
          '00000000-0000-0000-0000-0001c3a00e01', '{"kitchen_workflow_mode": "kds"}'::jsonb);
select throws_ok(
  $$ update audit_events set reason = 'tamper'
      where organization_id = '00000000-0000-0000-0000-0001c3a00a00'
        and action = 'settings.branch.kitchen_mode_updated' $$,
  '42501', null, 'audit: append-only enforcement is UNCHANGED (update refused)');                                -- 42

-- ===== D. dormancy ==========================================================
select is(
  (select count(*)::int from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.proname in ('set_branch_kitchen_workflow_mode', 'set_kitchen_workflow_mode')),
  0, 'dormancy: NO workflow-mode setter function exists');                                                       -- 43
select ok(
  (select kitchen_workflow_mode = 'kds' and kitchen_workflow_mode_revision = 1
     from branches where id = '00000000-0000-0000-0000-0001c3a00a1a'),
  'dormancy: untouched branches remain kds at revision 1');                                                      -- 44

select * from finish();
rollback;
