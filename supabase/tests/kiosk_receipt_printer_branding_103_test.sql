-- ============================================================================
-- KIOSK-001-103 — pgTAP: kiosk receipt branding + receipt-only printer context.
--
-- A. restaurant-logos DEVICE read gate after the 20260824090000 widening:
--    pos + kiosk allowed (own restaurant only), KDS denied, RF-118 expiry
--    enforced for EVERY device principal, all liveness/binding denials, and
--    the continued ABSENCE of any device write path.
-- B. get_device_printer_assignments: the NEW kiosk principal is receipt-only
--    (customer_receipt, never kitchen_ticket, never connection_config) with
--    RF-118 expiry enforced; POS and KDS answers are UNCHANGED.
-- Fixtures seeded by the BYPASSRLS connection; assertions as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(36);

-- ===================== fixtures (connection role / BYPASSRLS) ================
insert into auth.users (id, email) values
  ('c1000000-0000-0000-0000-0000000d0001', 'k103-dev-pos-a@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0002', 'k103-dev-kds-a@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0003', 'k103-dev-kiosk-a@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0004', 'k103-dev-kiosk-b@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0005', 'k103-dev-kiosk-exp@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0006', 'k103-dev-kiosk-rev@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0007', 'k103-dev-kiosk-inact@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0008', 'k103-dev-kiosk-deadpair@ex.test'),
  ('c1000000-0000-0000-0000-0000000d0009', 'k103-dev-kiosk-deaddev@ex.test'),
  ('c1000000-0000-0000-0000-0000000d000a', 'k103-dev-pos-exp@ex.test'),
  ('c1000000-0000-0000-0000-0000000d000b', 'k103-unbound@ex.test');

insert into organizations (id, name, slug, default_currency) values
  ('c1000000-0000-0000-0000-0000000000a0', 'Org A', 'k103-a', 'ILS'),
  ('c1000000-0000-0000-0000-0000000000b0', 'Org B', 'k103-b', 'EUR');
insert into restaurants (id, organization_id, name, receipt_logo_path, receipt_logo_enabled, receipt_logo_version) values
  ('c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000000a0', 'Rest A1',
   'c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a1/logo/c1000000-0000-0000-0000-0000000000f1.png', true, 7),
  ('c1000000-0000-0000-0000-0000000000a2', 'c1000000-0000-0000-0000-0000000000a0', 'Rest A2', null, false, 0),
  ('c1000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-0000000000b0', 'Rest B1',
   'c1000000-0000-0000-0000-0000000000b0/c1000000-0000-0000-0000-0000000000b1/logo/c1000000-0000-0000-0000-0000000000f4.png', true, 3);
insert into branches (id, organization_id, restaurant_id, name) values
  ('c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('c1000000-0000-0000-0000-0000000a2a00', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a2', 'Branch A2a'),
  ('c1000000-0000-0000-0000-0000000b1a00', 'c1000000-0000-0000-0000-0000000000b0', 'c1000000-0000-0000-0000-0000000000b1', 'Branch B1a');

-- devices: pos/kds/kiosk @ A1a; kiosk @ B1a; a DEAD kiosk device @ A1a.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label, is_active) values
  ('c1000000-0000-0000-0000-0000000d1001', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'pos',   'POS A',        true),
  ('c1000000-0000-0000-0000-0000000d1002', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'kds',   'KDS A',        true),
  ('c1000000-0000-0000-0000-0000000d1003', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'kiosk', 'Kiosk A',      true),
  ('c1000000-0000-0000-0000-0000000d1004', 'c1000000-0000-0000-0000-0000000000b0', 'c1000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-0000000b1a00', 'kiosk', 'Kiosk B',      true),
  ('c1000000-0000-0000-0000-0000000d1005', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'kiosk', 'Kiosk A dead', false);
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('c1000000-0000-0000-0000-0000000d2001', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1001', 'active'),
  ('c1000000-0000-0000-0000-0000000d2002', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1002', 'active'),
  ('c1000000-0000-0000-0000-0000000d2003', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'active'),
  ('c1000000-0000-0000-0000-0000000d2004', 'c1000000-0000-0000-0000-0000000000b0', 'c1000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-0000000b1a00', 'c1000000-0000-0000-0000-0000000d1004', 'active'),
  ('c1000000-0000-0000-0000-0000000d2005', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'revoked'),
  ('c1000000-0000-0000-0000-0000000d2006', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1005', 'active');

-- sessions: token-proven + auth-bound. Live ones expire in the future
-- (RF-118); the EXPIRED ones are otherwise perfectly live.
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, auth_user_id, session_token_ref, is_active, revoked_at, expires_at) values
  ('c1000000-0000-0000-0000-0000000d3001', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1001', 'c1000000-0000-0000-0000-0000000d2001', 'c1000000-0000-0000-0000-0000000d0001', app.hash_provisioning_secret('k103-pos-a'),          true,  null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3002', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1002', 'c1000000-0000-0000-0000-0000000d2002', 'c1000000-0000-0000-0000-0000000d0002', app.hash_provisioning_secret('k103-kds-a'),          true,  null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3003', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'c1000000-0000-0000-0000-0000000d2003', 'c1000000-0000-0000-0000-0000000d0003', app.hash_provisioning_secret('k103-kiosk-a'),        true,  null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3004', 'c1000000-0000-0000-0000-0000000000b0', 'c1000000-0000-0000-0000-0000000000b1', 'c1000000-0000-0000-0000-0000000b1a00', 'c1000000-0000-0000-0000-0000000d1004', 'c1000000-0000-0000-0000-0000000d2004', 'c1000000-0000-0000-0000-0000000d0004', app.hash_provisioning_secret('k103-kiosk-b'),        true,  null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3005', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'c1000000-0000-0000-0000-0000000d2003', 'c1000000-0000-0000-0000-0000000d0005', app.hash_provisioning_secret('k103-kiosk-exp'),      true,  null,  now() - interval '1 minute'),
  ('c1000000-0000-0000-0000-0000000d3006', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'c1000000-0000-0000-0000-0000000d2003', 'c1000000-0000-0000-0000-0000000d0006', app.hash_provisioning_secret('k103-kiosk-rev'),      true,  now(), now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3007', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'c1000000-0000-0000-0000-0000000d2003', 'c1000000-0000-0000-0000-0000000d0007', app.hash_provisioning_secret('k103-kiosk-inact'),    false, null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3008', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1003', 'c1000000-0000-0000-0000-0000000d2005', 'c1000000-0000-0000-0000-0000000d0008', app.hash_provisioning_secret('k103-kiosk-deadpair'), true,  null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d3009', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1005', 'c1000000-0000-0000-0000-0000000d2006', 'c1000000-0000-0000-0000-0000000d0009', app.hash_provisioning_secret('k103-kiosk-deaddev'),  true,  null,  now() + interval '1 hour'),
  ('c1000000-0000-0000-0000-0000000d300a', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'c1000000-0000-0000-0000-0000000d1001', 'c1000000-0000-0000-0000-0000000d2001', 'c1000000-0000-0000-0000-0000000d000a', app.hash_provisioning_secret('k103-pos-exp'),        true,  null,  now() - interval '1 minute');

-- logo objects: Org A / Rest A1, Org A / Rest A2 (wrong restaurant for the
-- kiosk), Org B / Rest B1, and a MALFORMED path.
insert into storage.objects (bucket_id, name) values
  ('restaurant-logos', 'c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a1/logo/c1000000-0000-0000-0000-0000000000f1.png'),
  ('restaurant-logos', 'c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a2/logo/c1000000-0000-0000-0000-0000000000f2.png'),
  ('restaurant-logos', 'c1000000-0000-0000-0000-0000000000b0/c1000000-0000-0000-0000-0000000000b1/logo/c1000000-0000-0000-0000-0000000000f4.png'),
  ('restaurant-logos', 'not-a-uuid/junk/logo/k103-malformed.png');

-- printers @ A1a: dedicated receipt, dedicated kitchen, and a 'both'.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role) values
  ('c1000000-0000-0000-0000-0000000e0001', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'Receipt P1', 'network', 'receipt'),
  ('c1000000-0000-0000-0000-0000000e0002', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'Kitchen P2', 'network', 'kitchen'),
  ('c1000000-0000-0000-0000-0000000e0003', 'c1000000-0000-0000-0000-0000000000a0', 'c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-0000000a1a00', 'Both P3',    'network', 'both');

set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';

-- ==================== A. STORAGE DEVICE READ GATE (17) ======================
-- 1-2: POS unchanged + the NEW global RF-118 parity on the logo gate.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0001"}';
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f1.png'), 1,
  'a live POS device session still reads its own restaurant logo (POS preserved)');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d000a"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'an EXPIRED POS session reads ZERO logos (RF-118 parity now applies to every device principal)');
-- 3-4: kiosk allowed, own restaurant only.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0003"}';
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f1.png'), 1,
  'a live KIOSK device session CAN read its own restaurant logo (the 103 widening)');
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f4.png'), 0,
  'the Org A kiosk sees ZERO Org B logos (cross-tenant)');
-- 5: wrong restaurant, same org.
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f2.png'), 0,
  'the Rest A1 kiosk sees ZERO Rest A2 logos (wrong restaurant)');
-- 6: malformed path.
select is((select count(*)::int from storage.objects where name = 'not-a-uuid/junk/logo/k103-malformed.png'), 0,
  'a malformed logo path is invisible (strict parser => no row => deny)');
-- 7-8: KDS stays excluded; Org B kiosk control.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0002"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'a KDS device session sees ZERO logos (KDS remains excluded)');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0004"}';
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f4.png'), 1,
  'the Org B kiosk CAN read its own org logo (control)');
-- 9: Org B kiosk cross-check on Org A.
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f1.png'), 0,
  'the Org B kiosk sees ZERO Org A logos');
-- 10-12: expired / revoked / inactive kiosk sessions.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0005"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'an EXPIRED kiosk session reads ZERO logos (RF-118)');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0006"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'a REVOKED kiosk session reads ZERO logos');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0007"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'an INACTIVE kiosk session reads ZERO logos');
-- 13: an auth user with NO device session binding.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d000b"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'an auth user with no bound device session reads ZERO logos (auth_user mismatch)');
-- 14-15: dead pairing / dead device.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0008"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'a kiosk session on a REVOKED pairing reads ZERO logos');
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0009"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'a kiosk session on an INACTIVE device reads ZERO logos');
-- 16-17: the kiosk principal has NO write path.
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0003"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a1/logo/c1000000-0000-0000-0000-000000000fd0.png') $$,
  '42501', null, 'a KIOSK device principal CANNOT INSERT a logo (no device write policy)');
-- An UPDATE without any device UPDATE policy silently touches zero rows: the
-- rename below must leave the original object exactly where it was.
update storage.objects
   set name = 'c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a1/logo/c1000000-0000-0000-0000-000000000fee.png'
 where name = 'c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a1/logo/c1000000-0000-0000-0000-0000000000f1.png';
select is((select count(*)::int from storage.objects where name like '%/c1000000-0000-0000-0000-0000000000f1.png'), 1,
  'a KIOSK device principal UPDATES zero logo rows (no device write policy)');

-- ==================== B. PRINTER/BRANDING CONTEXT RPC (18) ==================
set local request.jwt.claims = '{"sub":"c1000000-0000-0000-0000-0000000d0003"}';
-- 18-21: kiosk valid answer + branding pointer.
select ok((public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') ->> 'ok')::boolean,
  'a valid kiosk token gets device printer/branding context');
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'device' ->> 'device_type',
  'kiosk', 'the kiosk answer carries device_type=kiosk');
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'device' ->> 'restaurant_name',
  'Rest A1', 'the kiosk answer carries the authoritative restaurant name');
select ok(
  (select d ->> 'receipt_logo_path' = 'c1000000-0000-0000-0000-0000000000a0/c1000000-0000-0000-0000-0000000000a1/logo/c1000000-0000-0000-0000-0000000000f1.png'
      and (d ->> 'receipt_logo_enabled')::boolean
      and (d ->> 'receipt_logo_version')::int = 7
     from (select public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'device' as d) s),
  'the kiosk answer carries the Dashboard receipt-logo pointer (path + enabled + version)');
-- 22-25: kiosk printer projection is receipt-only.
select ok(
  (select exists (select 1 from jsonb_array_elements(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'printers') p
     where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0001' and p ->> 'role' = 'receipt')),
  'the kiosk sees the dedicated RECEIPT printer');
select ok(
  (select exists (select 1 from jsonb_array_elements(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'printers') p
     where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0003'
       and p ->> 'role' = 'receipt'
       and p -> 'supported_purposes' = '["customer_receipt"]'::jsonb)),
  'a BOTH printer collapses to receipt/customer_receipt for the kiosk');
select ok(
  (select not exists (select 1 from jsonb_array_elements(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'printers') p
     where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0002')),
  'the kiosk NEVER sees a kitchen printer');
select ok(
  (select not exists (select 1 from jsonb_array_elements(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a') -> 'printers') p
     where p -> 'supported_purposes' @> '["kitchen_ticket"]'::jsonb)),
  'no kiosk-visible printer carries the kitchen_ticket purpose');
-- 26: connection_config never leaves the server.
select ok(
  position('connection_config' in public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-a')::text) = 0,
  'the kiosk answer NEVER contains connection_config');
-- 27-28: POS unchanged (default kds workflow mode => receipt + both only).
select ok(
  (select (r ->> 'ok')::boolean
      and r -> 'device' ->> 'device_type' = 'pos'
      and jsonb_array_length(r -> 'printers') = 2
      and not exists (select 1 from jsonb_array_elements(r -> 'printers') p
            where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0002')
     from (select public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1001', 'k103-pos-a') as r) s),
  'POS answer is unchanged: receipt + both printers, kitchen excluded in kds mode');
select ok(
  (select exists (select 1 from jsonb_array_elements(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1001', 'k103-pos-a') -> 'printers') p
     where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0003'
       and p ->> 'role' = 'receipt'
       and p -> 'supported_purposes' = '["customer_receipt"]'::jsonb)),
  'POS both-printer projection is unchanged (receipt / customer_receipt)');
-- 29-30: KDS unchanged.
select ok(
  (select (r ->> 'ok')::boolean
      and jsonb_array_length(r -> 'printers') = 2
      and not exists (select 1 from jsonb_array_elements(r -> 'printers') p
            where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0001')
     from (select public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1002', 'k103-kds-a') as r) s),
  'KDS answer is unchanged: kitchen + both printers, receipt excluded');
select ok(
  (select exists (select 1 from jsonb_array_elements(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1002', 'k103-kds-a') -> 'printers') p
     where p ->> 'id' = 'c1000000-0000-0000-0000-0000000e0003'
       and p ->> 'role' = 'kitchen'
       and p -> 'supported_purposes' = '["kitchen_ticket"]'::jsonb)),
  'KDS both-printer projection is unchanged (kitchen / kitchen_ticket)');
-- 31-35: kiosk denials.
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-exp') ->> 'error',
  'invalid_session', 'an EXPIRED kiosk session is refused (RF-118)');
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-rev') ->> 'error',
  'invalid_session', 'a REVOKED kiosk session is refused');
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-inact') ->> 'error',
  'invalid_session', 'an INACTIVE kiosk session is refused');
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'k103-kiosk-deadpair') ->> 'error',
  'invalid_session', 'a kiosk session on a REVOKED pairing is refused');
select is(public.get_device_printer_assignments('c1000000-0000-0000-0000-0000000d1003', 'garbage-token') ->> 'error',
  'invalid_session', 'a garbage kiosk token is refused');
-- 36: no non-SELECT storage policy references the device logo gate.
select is(
  (select count(*)::int from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and cmd <> 'SELECT'
       and (coalesce(qual, '') || coalesce(with_check, '')) like '%device_can_read_restaurant_logo%'),
  0, 'the device logo gate is referenced by SELECT policies only (read-only device access)');

reset role;
select * from finish();
rollback;
