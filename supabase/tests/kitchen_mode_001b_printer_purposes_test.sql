-- ============================================================================
-- KITCHEN-MODE-001B — pgTAP: printer purposes (`both` role), purpose-aware
-- device assignments, Activity-Log classification, and dormancy regression.
--
--   * printer_devices.role CHECK: receipt | kitchen | both; invalid rejected;
--     existing rows preserved; named constraint.
--   * upsert_printer_device: manager+ may create/update through all three
--     roles; cashier denied; invalid role rejected; cross-tenant rejected;
--     before/after role audited.
--   * get_device_printer_assignments: KDS -> kitchen+both (never receipt-only);
--     POS@kds -> receipt+both (never kitchen-only; both = customer purpose
--     ONLY); POS@printer_only (privileged fixture — no setter exists) ->
--     receipt+kitchen+both with full purpose derivation. OLD-CLIENT
--     COMPATIBILITY: the legacy `role` key NEVER carries 'both' (device-
--     perspective mapping); configured_role/supported_purposes are additive;
--     connection_config still never leaks.
--   * Activity Log: printer.% classifies as settings, carries ONLY the safe
--     scalars, drops endpoints (nested) + hostile money keys.
--   * Dormancy: the 001A no-activation guarantees still hold verbatim.
-- Session pinned to UTC; hex-only UUIDs; GUC/token conventions per RF-113/161.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(35);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0001b0000a00', 'Org A', 'km1b-a', 'ILS'),
  ('00000000-0000-0000-0000-0001b0000b00', 'Org B', 'km1b-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a00', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0001b0000b10', '00000000-0000-0000-0000-0001b0000b00', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-0001b0000a2b', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', 'Branch P (printer-only)'),
  ('00000000-0000-0000-0000-0001b0000b1a', '00000000-0000-0000-0000-0001b0000b00', '00000000-0000-0000-0000-0001b0000b10', 'Branch B1a');
-- privileged fixture flip (the ONLY write path; dormancy proven below + in 001A).
update branches set kitchen_workflow_mode = 'printer_only'
  where id = '00000000-0000-0000-0000-0001b0000a2b';

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0001b0000e01', 'km1b-owner@example.test'),
  ('00000000-0000-0000-0000-0001b0000e02', 'km1b-manager@example.test'),
  ('00000000-0000-0000-0000-0001b0000e03', 'km1b-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0001b0000f01', '00000000-0000-0000-0000-0001b0000e01', '00000000-0000-0000-0000-0001b0000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0001b0000f02', '00000000-0000-0000-0000-0001b0000e02', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'manager'),
  ('00000000-0000-0000-0000-0001b0000f03', '00000000-0000-0000-0000-0001b0000e03', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'cashier');

-- POS + KDS devices @ Branch K, POS @ Branch P — with token-proven sessions;
-- one FOREIGN Org-B device (no session) for the forged-device assertion.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0001b000d001', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'pos'),
  ('00000000-0000-0000-0000-0001b000d002', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'kds'),
  ('00000000-0000-0000-0000-0001b000d003', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a2b', 'pos'),
  ('00000000-0000-0000-0000-0001b000d00b', '00000000-0000-0000-0000-0001b0000b00', '00000000-0000-0000-0000-0001b0000b10', '00000000-0000-0000-0000-0001b0000b1a', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0001b000c001', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000d001', 'active'),
  ('00000000-0000-0000-0000-0001b000c002', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000d002', 'active'),
  ('00000000-0000-0000-0000-0001b000c003', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a2b', '00000000-0000-0000-0000-0001b000d003', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0001b000e001', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000d001', '00000000-0000-0000-0000-0001b000c001', app.hash_provisioning_secret('tok-km1b-posk'), true, null),
  ('00000000-0000-0000-0000-0001b000e002', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000d002', '00000000-0000-0000-0000-0001b000c002', app.hash_provisioning_secret('tok-km1b-kdsk'), true, null),
  ('00000000-0000-0000-0000-0001b000e003', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a2b', '00000000-0000-0000-0000-0001b000d003', '00000000-0000-0000-0000-0001b000c003', app.hash_provisioning_secret('tok-km1b-posp'), true, null);

-- printers. Branch K: receipt R1 (with a REAL endpoint that must never leak),
-- kitchen K1, both B1, both-DISABLED D1. Branch P: receipt R2, kitchen K2,
-- both B2. Org B: one receipt printer.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, connection_config, is_enabled) values
  ('00000000-0000-0000-0000-0001b000f001', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'Front R1',   'network',   'receipt', '80mm', '{"host": "10.9.9.9", "port": 9100}', true),
  ('00000000-0000-0000-0000-0001b000f002', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'Kitchen K1', 'network',   'kitchen', '80mm', '{}', true),
  ('00000000-0000-0000-0000-0001b000f003', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'Both B1',    'bluetooth', 'both',    '80mm', '{}', true),
  ('00000000-0000-0000-0000-0001b000f004', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a1a', 'Both D1',    'network',   'both',    '58mm', '{}', false),
  ('00000000-0000-0000-0000-0001b000f011', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a2b', 'P R2',       'network',   'receipt', '80mm', '{}', true),
  ('00000000-0000-0000-0000-0001b000f012', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a2b', 'P K2',       'network',   'kitchen', '80mm', '{}', true),
  ('00000000-0000-0000-0000-0001b000f013', '00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10', '00000000-0000-0000-0000-0001b0000a2b', 'P B2',       'network',   'both',    '80mm', '{}', true),
  ('00000000-0000-0000-0000-0001b000f0b1', '00000000-0000-0000-0000-0001b0000b00', '00000000-0000-0000-0000-0001b0000b10', '00000000-0000-0000-0000-0001b0000b1a', 'B R1',       'network',   'receipt', '80mm', '{}', true);

-- ===== RPC calls (as the app roles) ==========================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0001b0000e02';  -- manager @ K
create temp table t_up1 as
  select app.upsert_printer_device('00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10',
    '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000f0e1', 'Managed U1', 'network', 'receipt', '80mm', '{}'::jsonb, true) as res;
create temp table t_up2 as
  select app.upsert_printer_device('00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10',
    '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000f0e1', 'Managed U1', 'network', 'both', '80mm', '{}'::jsonb, true) as res;
create temp table t_up3 as
  select app.upsert_printer_device('00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10',
    '00000000-0000-0000-0000-0001b0000a1a', '00000000-0000-0000-0000-0001b000f0e1', 'Managed U1', 'network', 'kitchen', '80mm', '{}'::jsonb, true) as res;
select throws_ok(
  $$ select app.upsert_printer_device('00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10',
       '00000000-0000-0000-0000-0001b0000a1a', null, 'Bad', 'network', 'ticket', '80mm', '{}'::jsonb, true) $$,
  '42501', NULL, 'an INVALID role (ticket) is rejected by upsert validation');                                    -- 1
select throws_ok(
  $$ select app.upsert_printer_device('00000000-0000-0000-0000-0001b0000b00', '00000000-0000-0000-0000-0001b0000b10',
       '00000000-0000-0000-0000-0001b0000b1a', null, 'Cross', 'network', 'both', '80mm', '{}'::jsonb, true) $$,
  '42501', NULL, 'the Org-A manager cannot upsert a printer into Org B (cross-tenant, 42501)');                  -- 2

set local app.current_app_user_id = '00000000-0000-0000-0000-0001b0000e03';  -- cashier
create temp table t_up4 as
  select app.upsert_printer_device('00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10',
    '00000000-0000-0000-0000-0001b0000a1a', null, 'Cashier try', 'network', 'both', '80mm', '{}'::jsonb, true) as res;

set local app.current_app_user_id = '';
create temp table t_kds  as select app.get_device_printer_assignments('00000000-0000-0000-0000-0001b000d002', 'tok-km1b-kdsk') as res;
create temp table t_posk as select app.get_device_printer_assignments('00000000-0000-0000-0000-0001b000d001', 'tok-km1b-posk') as res;
create temp table t_posp as select app.get_device_printer_assignments('00000000-0000-0000-0000-0001b000d003', 'tok-km1b-posp') as res;
create temp table t_bad  as select app.get_device_printer_assignments('00000000-0000-0000-0000-0001b000d001', 'wrong-token') as res;
create temp table t_forg as select app.get_device_printer_assignments('00000000-0000-0000-0000-0001b000d00b', 'tok-km1b-posk') as res;

reset role;

-- ===== A. schema =============================================================
select is((select role from printer_devices where id = '00000000-0000-0000-0000-0001b000f003'),
  'both', 'the CHECK accepts role = both (fixture row persisted)');                                              -- 3
select throws_ok(
  $$ insert into printer_devices (organization_id, restaurant_id, branch_id, display_name, connection_type, role)
       values ('00000000-0000-0000-0000-0001b0000a00', '00000000-0000-0000-0000-0001b0000a10',
               '00000000-0000-0000-0000-0001b0000a1a', 'Invalid', 'network', 'labels') $$,
  '23514', NULL, 'the CHECK rejects any role outside (receipt, kitchen, both)');                                 -- 4
select ok(
  (select role from printer_devices where id = '00000000-0000-0000-0000-0001b000f001') = 'receipt'
  and (select role from printer_devices where id = '00000000-0000-0000-0000-0001b000f002') = 'kitchen',
  'existing receipt and kitchen rows remain valid and untouched');                                               -- 5
select ok(
  (select pg_get_constraintdef(c.oid) like '%both%'
     from pg_constraint c join pg_class t on t.oid = c.conrelid
    where t.relname = 'printer_devices' and c.conname = 'printer_devices_role_check'),
  'the NAMED constraint printer_devices_role_check carries the three-value set');                                -- 6

-- ===== B. upsert =============================================================
select ok((select (res ->> 'ok')::boolean and res ->> 'action' = 'created' from t_up1),
  'manager creates a printer (receipt) through upsert_printer_device');                                          -- 7
select ok((select (res ->> 'ok')::boolean and res ->> 'action' = 'updated' from t_up2),
  'manager updates the printer receipt -> both');                                                                -- 8
select ok(
  (select count(*) = 1
     and bool_and(old_values ->> 'role' = 'receipt')
     and bool_and(new_values ->> 'role' = 'both')
   from audit_events
   where action = 'printer.printer_device.updated'
     and new_values ->> 'id' = '00000000-0000-0000-0000-0001b000f0e1'
     and new_values ->> 'role' = 'both'),
  'the role change is audited with the before/after role (receipt -> both)');                                    -- 9
select ok((select (res ->> 'ok')::boolean from t_up3)
  and (select role = 'kitchen' from printer_devices where id = '00000000-0000-0000-0000-0001b000f0e1'),
  'manager updates the printer both -> kitchen (persisted)');                                                    -- 10
select is((select res ->> 'error' from t_up4), 'permission_denied',
  'a cashier cannot manage printers (permission_denied, printer_guard unchanged)');                              -- 11

-- ===== C. assignments ========================================================
select ok(
  (select (res ->> 'ok')::boolean
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f002')
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f003')
      and not exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f001')
   from t_kds),
  'KDS receives kitchen + both printers and NEVER a receipt-only printer');                                      -- 12
select ok(
  (select p ->> 'role' = 'kitchen' and p ->> 'configured_role' = 'both'
      and p -> 'supported_purposes' = '["kitchen_ticket"]'::jsonb
   from t_kds, jsonb_array_elements((select res from t_kds) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f003'),
  'KDS both-printer: legacy role=kitchen, configured_role=both, purposes=[kitchen_ticket]');                     -- 13
select ok(
  (select p ->> 'role' = 'kitchen' and p ->> 'configured_role' = 'kitchen'
      and p -> 'supported_purposes' = '["kitchen_ticket"]'::jsonb
   from t_kds, jsonb_array_elements((select res from t_kds) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f002'),
  'KDS kitchen-printer: role and configured_role agree (kitchen), purposes=[kitchen_ticket]');                   -- 14
select ok(
  (select (res ->> 'ok')::boolean
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f001')
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f003')
      and not exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f002')
   from t_posk),
  'POS in a kds-mode branch receives receipt + both and NEVER a kitchen-only printer');                          -- 15
select ok(
  (select p ->> 'role' = 'receipt' and p ->> 'configured_role' = 'both'
      and p -> 'supported_purposes' = '["customer_receipt"]'::jsonb
   from t_posk, jsonb_array_elements((select res from t_posk) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f003'),
  'POS@kds both-printer: legacy role=receipt, configured_role=both, purposes LIMITED to customer_receipt');      -- 16
select ok(
  (select p ->> 'role' = 'receipt' and p ->> 'configured_role' = 'receipt'
      and p -> 'supported_purposes' = '["customer_receipt"]'::jsonb
   from t_posk, jsonb_array_elements((select res from t_posk) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f001'),
  'POS@kds receipt-printer: role and configured_role agree (receipt), purposes=[customer_receipt]');             -- 17
select ok(
  (select (p ->> 'is_enabled')::boolean = false
   from t_posk, jsonb_array_elements((select res from t_posk) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f004'),
  'a DISABLED both-printer is still listed with is_enabled=false (existing contract preserved)');                -- 18
select ok(
  (select (res ->> 'ok')::boolean
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f011')
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f012')
      and exists (select 1 from jsonb_array_elements(res -> 'printers') p where p ->> 'id' = '00000000-0000-0000-0000-0001b000f013')
   from t_posp),
  'POS in a PRINTER-ONLY branch (privileged fixture) receives receipt + kitchen + both');                        -- 19
select ok(
  (select p ->> 'role' = 'receipt' and p ->> 'configured_role' = 'both'
      and p -> 'supported_purposes' = '["customer_receipt", "kitchen_ticket"]'::jsonb
   from t_posp, jsonb_array_elements((select res from t_posp) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f013'),
  'POS@printer_only both-printer: BOTH purposes supported; legacy role still receipt');                          -- 20
select ok(
  (select p ->> 'role' = 'kitchen' and p ->> 'configured_role' = 'kitchen'
      and p -> 'supported_purposes' = '["kitchen_ticket"]'::jsonb
   from t_posp, jsonb_array_elements((select res from t_posp) -> 'printers') p
   where p ->> 'id' = '00000000-0000-0000-0000-0001b000f012'),
  'POS@printer_only kitchen-printer: purposes=[kitchen_ticket] (legacy role kitchen is a known value)');         -- 21
select ok(
  not exists (select 1 from t_kds,  jsonb_array_elements((select res from t_kds)  -> 'printers') p where p ->> 'role' = 'both')
  and not exists (select 1 from t_posk, jsonb_array_elements((select res from t_posk) -> 'printers') p where p ->> 'role' = 'both')
  and not exists (select 1 from t_posp, jsonb_array_elements((select res from t_posp) -> 'printers') p where p ->> 'role' = 'both'),
  'OLD-CLIENT COMPATIBILITY: the legacy role key NEVER carries both on any device response');                    -- 22
select ok(
  (select res::text not like '%connection_config%' and res::text not like '%10.9.9.9%' from t_posk)
  and (select res::text not like '%connection_config%' from t_kds)
  and (select res::text not like '%connection_config%' from t_posp),
  'connection_config (endpoints) still NEVER leaks into any device assignment payload');                         -- 23
select is((select res ->> 'error' from t_bad), 'invalid_session',
  'a wrong token still fails closed (invalid_session)');                                                         -- 24
select is((select res ->> 'error' from t_forg), 'invalid_session',
  'a FORGED Org-B device id with an Org-A token still fails closed');                                            -- 25

-- ===== D. Activity-Log classification ========================================
select is(app.audit_category('printer.printer_device.updated'), 'settings',
  'printer.% now classifies under settings (was the other bucket)');                                             -- 26
select ok(app.audit_action_has_detail('printer.printer_device.updated')
  and app.audit_action_has_detail('printer.printer_route.updated'),
  'printer actions may carry a safe detail projection');                                                         -- 27
create temp table t_det as select app.audit_safe_detail('printer.printer_device.updated', jsonb_build_object(
  'display_name', 'Front R1', 'role', 'both', 'paper_width', '80mm', 'is_enabled', true,
  'connection_type', 'network',
  'connection_config', jsonb_build_object('host', '10.9.9.9', 'port', 9100),
  'id', '00000000-0000-0000-0000-0001b000f001',
  'organization_id', '00000000-0000-0000-0000-0001b0000a00',
  'amount_minor', 1234)) as det;
select ok(
  (select det ->> 'display_name' = 'Front R1' and det ->> 'role' = 'both'
      and det ->> 'paper_width' = '80mm' and det ->> 'is_enabled' = 'true'
      and det ->> 'connection_type' = 'network'
   from t_det),
  'audit_safe_detail projects exactly the five safe printer scalars');                                           -- 28
select ok(
  (select not (det ? 'connection_config') and not (det ? 'id')
      and not (det ? 'organization_id') and not (det ? 'amount_minor')
   from t_det),
  'endpoints (nested), identifiers and HOSTILE money keys are all dropped for printer.%');                       -- 29

-- ===== E. dormancy regression (001A guarantees hold verbatim) ================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.proname like '%kitchen_workflow_mode%'
      and p.proname not like 'get\_%'),
  0, 'STILL no setter/updater function for kitchen_workflow_mode anywhere in app/public');                       -- 30
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and p.prosrc ~* 'update\s+(public\.)?branches\y'
      and p.prosrc ilike '%kitchen_workflow_mode%'),
  0, 'STILL no function that UPDATEs branches touches kitchen_workflow_mode (001B added none)');                 -- 31
set local role authenticated;
select throws_ok(
  $$ update branches set kitchen_workflow_mode = 'printer_only'
       where id = '00000000-0000-0000-0000-0001b0000a1a' $$,
  '42501', NULL, 'an app role STILL cannot write branches directly (revoked privilege => 42501)');               -- 32
reset role;

-- ===== F. security posture ===================================================
select ok(
  has_function_privilege('authenticated', 'app.upsert_printer_device(uuid,uuid,uuid,uuid,text,text,text,text,jsonb,boolean)', 'execute')
  and has_function_privilege('authenticated', 'app.get_device_printer_assignments(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'app.upsert_printer_device(uuid,uuid,uuid,uuid,text,text,text,text,jsonb,boolean)', 'execute')
  and not has_function_privilege('anon', 'app.get_device_printer_assignments(uuid,text)', 'execute'),
  'grants unchanged: authenticated may execute both re-created RPCs, anon may not');                             -- 33
select ok(
  (select bool_and(p.prosecdef and p.proconfig::text like '%search_path%')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.proname in ('upsert_printer_device', 'get_device_printer_assignments')),
  'both re-created RPCs stay SECURITY DEFINER with a pinned search_path');                                       -- 34
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'printer_devices'),
  'RLS on printer_devices is still ENABLED and FORCED');                                                         -- 35

select * from finish();
rollback;
