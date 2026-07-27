-- ============================================================================
-- PRINT-BRANDING-LOGO-001 — pgTAP: get_device_printer_assignments carries the
-- three ADDITIVE branding keys for the device's own proven restaurant, with
-- default-safe values for a legacy restaurant, while every prior key/behavior
-- is preserved and connection_config is still never exposed. Token-proven
-- device calls run as anonymous authenticated principals.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

insert into organizations (id, name, slug, default_currency) values
  ('d4000000-0000-0000-0000-0000000000a0', 'Org A', 'pbldpa-a', 'USD');
insert into restaurants (id, organization_id, name, receipt_logo_path, receipt_logo_enabled, receipt_logo_version) values
  ('d4000000-0000-0000-0000-0000000000a1', 'd4000000-0000-0000-0000-0000000000a0', 'Rest A1',
   'd4000000-0000-0000-0000-0000000000a0/d4000000-0000-0000-0000-0000000000a1/logo/d4000000-0000-0000-0000-0000000000f1.png', true, 5),
  ('d4000000-0000-0000-0000-0000000000a2', 'd4000000-0000-0000-0000-0000000000a0', 'Rest A2 (legacy)', null, false, 0);
insert into branches (id, organization_id, restaurant_id, name) values
  ('d4000000-0000-0000-0000-0000000a1a00', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('d4000000-0000-0000-0000-0000000a2a00', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a2', 'Branch A2a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('d4000000-0000-0000-0000-0000000d1001', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a1', 'd4000000-0000-0000-0000-0000000a1a00', 'pos', 'POS A1'),
  ('d4000000-0000-0000-0000-0000000d1002', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a2', 'd4000000-0000-0000-0000-0000000a2a00', 'pos', 'POS A2');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('d4000000-0000-0000-0000-0000000d2001', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a1', 'd4000000-0000-0000-0000-0000000a1a00', 'd4000000-0000-0000-0000-0000000d1001', 'active'),
  ('d4000000-0000-0000-0000-0000000d2002', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a2', 'd4000000-0000-0000-0000-0000000a2a00', 'd4000000-0000-0000-0000-0000000d1002', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active) values
  ('d4000000-0000-0000-0000-0000000d3001', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a1', 'd4000000-0000-0000-0000-0000000a1a00', 'd4000000-0000-0000-0000-0000000d1001', 'd4000000-0000-0000-0000-0000000d2001', app.hash_provisioning_secret('tok-pbl-pos-a1'), true),
  ('d4000000-0000-0000-0000-0000000d3002', 'd4000000-0000-0000-0000-0000000000a0', 'd4000000-0000-0000-0000-0000000000a2', 'd4000000-0000-0000-0000-0000000a2a00', 'd4000000-0000-0000-0000-0000000d1002', 'd4000000-0000-0000-0000-0000000d2002', app.hash_provisioning_secret('tok-pbl-pos-a2'), true);

create temp table _res (label text primary key, r jsonb);
grant select, insert on _res to authenticated;

set local role authenticated;
set local app.current_app_user_id = '';

-- ===== the branded restaurant's POS device ==================================
insert into _res values ('pos_a1', public.get_device_printer_assignments(
  'd4000000-0000-0000-0000-0000000d1001', 'tok-pbl-pos-a1'));
select is((select r ->> 'ok' from _res where label='pos_a1'), 'true',
  'the POS device opens its assignments (public wrapper delegation)');
select is((select r -> 'device' ->> 'receipt_logo_path' from _res where label='pos_a1'),
  'd4000000-0000-0000-0000-0000000000a0/d4000000-0000-0000-0000-0000000000a1/logo/d4000000-0000-0000-0000-0000000000f1.png',
  'the device block carries the restaurant''s receipt_logo_path');
select is((select r -> 'device' ->> 'receipt_logo_enabled' from _res where label='pos_a1'), 'true',
  'the device block carries receipt_logo_enabled=true');
select is((select (r -> 'device' ->> 'receipt_logo_version')::int from _res where label='pos_a1'), 5,
  'the device block carries receipt_logo_version=5');

-- prior keys/behaviors preserved
select is((select r -> 'device' ->> 'restaurant_name' from _res where label='pos_a1'), 'Rest A1',
  'the prior restaurant_name key is preserved');
select is((select r -> 'device' ->> 'device_type' from _res where label='pos_a1'), 'pos',
  'the prior device_type key is preserved');
select is(
  (select array_agg(k order by k)::text from _res, jsonb_object_keys(r -> 'device') k where label='pos_a1'),
  '{branch_id,branch_name,device_id,device_type,label,receipt_logo_enabled,receipt_logo_path,receipt_logo_version,restaurant_name}',
  'the device block carries the six prior keys PLUS the three additive branding keys');
select ok(
  (select (r ? 'printers') and (r ? 'routes') and (r ? 'stations') and (r ? 'server_ts')
      and (r ->> 'entity') = 'device_printer_assignments' from _res where label='pos_a1'),
  'the prior top-level keys (printers/routes/stations/server_ts/entity) are preserved');
select ok(
  (select position('connection_config' in r::text) = 0 from _res where label='pos_a1'),
  'connection_config is still NEVER exposed');

-- ===== the legacy (no-logo) restaurant's POS device -> default-safe values ==
insert into _res values ('pos_a2', public.get_device_printer_assignments(
  'd4000000-0000-0000-0000-0000000d1002', 'tok-pbl-pos-a2'));
select is((select r ->> 'ok' from _res where label='pos_a2'), 'true',
  'the legacy restaurant device opens its assignments (control)');
select is((select r -> 'device' ->> 'receipt_logo_path' from _res where label='pos_a2'), null,
  'a legacy restaurant device returns a NULL receipt_logo_path');
select is((select r -> 'device' ->> 'receipt_logo_enabled' from _res where label='pos_a2'), 'false',
  'a legacy restaurant device returns receipt_logo_enabled=false');
select is((select (r -> 'device' ->> 'receipt_logo_version')::int from _res where label='pos_a2'), 0,
  'a legacy restaurant device returns receipt_logo_version=0');

-- ===== failure modes unchanged ==============================================
select is((app.get_device_printer_assignments('d4000000-0000-0000-0000-0000000d1001', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong token still fails closed (invalid_session)');
select is((app.get_device_printer_assignments('d4000000-0000-0000-0000-0000000d1002', 'tok-pbl-pos-a1') ->> 'error'),
  'invalid_session', 'another device''s token does not open this device (invalid_session)');

reset role;
select * from finish();
rollback;
