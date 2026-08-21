-- ============================================================================
-- KIOSK-001-PREREQ-083 — pgTAP: the POS+KIOSK menu-image device read gate.
--
-- The REAL storage.objects RLS boundary is exercised exactly like the shipped
-- mvp_menu_item_images suite: fixtures seeded as the BYPASSRLS harness, then
-- `set local role authenticated` + `request.jwt.claims` simulate each bound
-- anonymous device principal and plain SELECT/INSERT/UPDATE/DELETE against
-- storage.objects prove what the policy allows. Matrix: POS preserved, KIOSK
-- newly allowed (own branch + global), KDS still denied (T-014), tenant/
-- restaurant/branch isolation, malformed/wrong-bucket fail-closed, session/
-- pairing/device liveness, the write boundary, and the ACL surface.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(28);

-- ===== fixtures: Org A (rest A1: branches A1a/A1b + rest A2), Org B =========
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-008300000a00', 'IMG Org A', 'kmi-a', 'ILS'),
  ('00000000-0000-0000-0000-008300000b00', 'IMG Org B', 'kmi-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a00', 'IMG Rest A1'),
  ('00000000-0000-0000-0000-008300000a20', '00000000-0000-0000-0000-008300000a00', 'IMG Rest A2'),
  ('00000000-0000-0000-0000-008300000b10', '00000000-0000-0000-0000-008300000b00', 'IMG Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', 'A1a'),
  ('00000000-0000-0000-0000-008300000a1b', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', 'A1b'),
  ('00000000-0000-0000-0000-008300000a2a', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a20', 'A2a'),
  ('00000000-0000-0000-0000-008300000b1a', '00000000-0000-0000-0000-008300000b00', '00000000-0000-0000-0000-008300000b10', 'B1a');

-- devices @A1a: POS + KIOSK + KDS live; kiosk liveness variants; Org B kiosk.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label, is_active) values
  ('00000000-0000-0000-0000-008300004001', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', 'pos',   'IMG POS',   true),
  ('00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', 'kiosk', 'IMG Kiosk', true),
  ('00000000-0000-0000-0000-008300004003', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', 'kds',   'IMG KDS',   true),
  ('00000000-0000-0000-0000-008300004004', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', 'kiosk', 'IMG K-Dead', false),
  ('00000000-0000-0000-0000-008300004005', '00000000-0000-0000-0000-008300000b00', '00000000-0000-0000-0000-008300000b10', '00000000-0000-0000-0000-008300000b1a', 'kiosk', 'IMG K-B',   true);
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, revoked_at) values
  ('00000000-0000-0000-0000-008300004011', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004001', 'active',  null),
  ('00000000-0000-0000-0000-008300004012', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', 'active',  null),
  ('00000000-0000-0000-0000-008300004013', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004003', 'active',  null),
  ('00000000-0000-0000-0000-008300004014', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', 'revoked', now()),
  ('00000000-0000-0000-0000-008300004015', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004004', 'active',  null),
  ('00000000-0000-0000-0000-008300004016', '00000000-0000-0000-0000-008300000b00', '00000000-0000-0000-0000-008300000b10', '00000000-0000-0000-0000-008300000b1a', '00000000-0000-0000-0000-008300004005', 'active',  null);
-- principals: a801 POS · a802 KIOSK · a803 KDS · a804 kiosk-inactive-session ·
-- a805 kiosk-revoked-session · a806 kiosk-on-revoked-pairing ·
-- a807 kiosk-inactive-device · a808 Org-B kiosk · a809 unbound.
-- RF-118 (084): the three primary live sessions carry an explicit FUTURE
-- expires_at, so every allow-case below also proves the non-expired path.
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at, auth_user_id) values
  ('00000000-0000-0000-0000-008300004051', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004001', '00000000-0000-0000-0000-008300004011', app.hash_provisioning_secret('kmi-pos'),   true,  null,  now() + interval '1 day', '00000000-0000-0000-0000-008300000801'),
  ('00000000-0000-0000-0000-008300004052', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004012', app.hash_provisioning_secret('kmi-k1'),    true,  null,  now() + interval '1 day', '00000000-0000-0000-0000-008300000802'),
  ('00000000-0000-0000-0000-008300004053', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004003', '00000000-0000-0000-0000-008300004013', app.hash_provisioning_secret('kmi-kds'),   true,  null,  now() + interval '1 day', '00000000-0000-0000-0000-008300000803'),
  ('00000000-0000-0000-0000-008300004054', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004012', app.hash_provisioning_secret('kmi-k2'),    false, null,  null,                     '00000000-0000-0000-0000-008300000804'),
  ('00000000-0000-0000-0000-008300004055', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004012', app.hash_provisioning_secret('kmi-k3'),    true,  now(), null,                     '00000000-0000-0000-0000-008300000805'),
  ('00000000-0000-0000-0000-008300004056', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004014', app.hash_provisioning_secret('kmi-k4'),    true,  null,  null,                     '00000000-0000-0000-0000-008300000806'),
  ('00000000-0000-0000-0000-008300004057', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004004', '00000000-0000-0000-0000-008300004015', app.hash_provisioning_secret('kmi-k5'),    true,  null,  null,                     '00000000-0000-0000-0000-008300000807'),
  ('00000000-0000-0000-0000-008300004058', '00000000-0000-0000-0000-008300000b00', '00000000-0000-0000-0000-008300000b10', '00000000-0000-0000-0000-008300000b1a', '00000000-0000-0000-0000-008300004005', '00000000-0000-0000-0000-008300004016', app.hash_provisioning_secret('kmi-kb'),    true,  null,  now() + interval '1 day', '00000000-0000-0000-0000-008300000808');
-- RF-118 (084) expiry fixtures on the SAME live devices/pairings (the helper
-- keys purely off ds.auth_user_id, so each principal is its own identity):
-- a810 kiosk EXPIRED (past) · a811 kiosk BOUNDARY (exactly now()) ·
-- a812 kiosk NULL-legacy · a813 POS EXPIRED · a814 POS NULL-legacy.
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at, auth_user_id) values
  ('00000000-0000-0000-0000-008300004059', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004012', app.hash_provisioning_secret('kmi-k6'),    true,  null,  now() - interval '1 hour', '00000000-0000-0000-0000-008300000810'),
  ('00000000-0000-0000-0000-00830000405a', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004012', app.hash_provisioning_secret('kmi-k7'),    true,  null,  now(),                     '00000000-0000-0000-0000-008300000811'),
  ('00000000-0000-0000-0000-00830000405b', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004002', '00000000-0000-0000-0000-008300004012', app.hash_provisioning_secret('kmi-k8'),    true,  null,  null,                      '00000000-0000-0000-0000-008300000812'),
  ('00000000-0000-0000-0000-00830000405c', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004001', '00000000-0000-0000-0000-008300004011', app.hash_provisioning_secret('kmi-p2'),    true,  null,  now() - interval '1 hour', '00000000-0000-0000-0000-008300000813'),
  ('00000000-0000-0000-0000-00830000405d', '00000000-0000-0000-0000-008300000a00', '00000000-0000-0000-0000-008300000a10', '00000000-0000-0000-0000-008300000a1a', '00000000-0000-0000-0000-008300004001', '00000000-0000-0000-0000-008300004011', app.hash_provisioning_secret('kmi-p3'),    true,  null,  null,                      '00000000-0000-0000-0000-008300000814');

-- storage objects (BYPASSRLS seed): own-branch, global, sibling-branch,
-- other-restaurant, other-org, malformed key, wrong bucket.
insert into storage.buckets (id, name, public) values
  ('kmi-not-menu-images', 'kmi-not-menu-images', false)
  on conflict (id) do nothing;
insert into storage.objects (bucket_id, name) values
  ('menu-images', '00000000-0000-0000-0000-008300000a00/00000000-0000-0000-0000-008300000a10/00000000-0000-0000-0000-008300000a1a/menu_item/00000000-0000-0000-0000-00830000e001/00000000-0000-0000-0000-0083000f0001.png'),
  ('menu-images', '00000000-0000-0000-0000-008300000a00/00000000-0000-0000-0000-008300000a10/global/menu_item/00000000-0000-0000-0000-00830000e001/00000000-0000-0000-0000-0083000f0002.png'),
  ('menu-images', '00000000-0000-0000-0000-008300000a00/00000000-0000-0000-0000-008300000a10/00000000-0000-0000-0000-008300000a1b/menu_item/00000000-0000-0000-0000-00830000e001/00000000-0000-0000-0000-0083000f0003.png'),
  ('menu-images', '00000000-0000-0000-0000-008300000a00/00000000-0000-0000-0000-008300000a20/00000000-0000-0000-0000-008300000a2a/menu_item/00000000-0000-0000-0000-00830000e002/00000000-0000-0000-0000-0083000f0004.png'),
  ('menu-images', '00000000-0000-0000-0000-008300000b00/00000000-0000-0000-0000-008300000b10/00000000-0000-0000-0000-008300000b1a/menu_item/00000000-0000-0000-0000-00830000e003/00000000-0000-0000-0000-0083000f0005.png'),
  ('menu-images', 'kmi-not-a-valid-scope-key.png'),
  ('kmi-not-menu-images', '00000000-0000-0000-0000-008300000a00/00000000-0000-0000-0000-008300000a10/00000000-0000-0000-0000-008300000a1a/menu_item/00000000-0000-0000-0000-00830000e001/00000000-0000-0000-0000-0083000f0006.png');

-- ============================================================================
-- POS — PRESERVED (1-2)
-- ============================================================================
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000801"}';
select is((select count(*)::int from storage.objects where name like '%0083000f0001.png'), 1,
  '1. an ACTIVE NON-EXPIRED POS still reads its own-branch image (preserved)');
select is((select count(*)::int from storage.objects where name like '%0083000f0002.png'), 1,
  '2. POS still reads a restaurant-global image (preserved)');

-- ============================================================================
-- KIOSK — NEW (3-4) + isolation (6-9) + malformed/bucket (10-11)
-- ============================================================================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000802"}';
select is((select count(*)::int from storage.objects where name like '%0083000f0001.png'), 1,
  '3. an ACTIVE NON-EXPIRED KIOSK reads its own-branch image (083 widening)');
select is((select count(*)::int from storage.objects where name like '%0083000f0002.png'), 1,
  '4. a live KIOSK reads a restaurant-global image (NEW)');
select is((select count(*)::int from storage.objects where name like '%0083000f0005.png'), 0,
  '6. a KIOSK sees ZERO other-organization images (R-003)');
select is((select count(*)::int from storage.objects where name like '%0083000f0004.png'), 0,
  '7. a KIOSK sees ZERO other-restaurant images (same org)');
select is((select count(*)::int from storage.objects where name like '%0083000f0003.png'), 0,
  '8. a KIOSK sees ZERO sibling-branch images');
select is((select count(*)::int from storage.objects where name like 'kmi-not-a-valid%'), 0,
  '10. a malformed object key is invisible (scope parser fail-closed)');
select is((select count(*)::int from storage.objects where bucket_id = 'kmi-not-menu-images'), 0,
  '11. the menu-images policy grants nothing in any other bucket');

-- Org-B kiosk control: reads its OWN org image (9).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000808"}';
select is((select count(*)::int from storage.objects where name like '%0083000f0005.png'), 1,
  '9. the Org-B kiosk reads its own image (control: isolation, not breakage)');

-- ============================================================================
-- KDS — STILL DENIED (5)
-- ============================================================================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000803"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '5. a live NON-EXPIRED KDS still sees ZERO menu images (T-014 preserved)');

-- ============================================================================
-- SESSION / DEVICE LIVENESS (12-16)
-- ============================================================================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000804"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '12. an INACTIVE kiosk session sees ZERO images');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000805"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '13. a REVOKED kiosk session sees ZERO images');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000806"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '14. a kiosk session on a REVOKED pairing sees ZERO images');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000807"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '15. a session on an INACTIVE kiosk device sees ZERO images');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000809"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '16. an UNBOUND authenticated principal sees ZERO images');

-- ============================================================================
-- WRITE BOUNDARY (17-19) — the live kiosk principal has READ only.
-- ============================================================================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000802"}';
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values
     ('menu-images', '00000000-0000-0000-0000-008300000a00/00000000-0000-0000-0000-008300000a10/00000000-0000-0000-0000-008300000a1a/menu_item/00000000-0000-0000-0000-00830000e001/00000000-0000-0000-0000-0083000f0099.png') $$,
  '42501', null, '17. a kiosk cannot INSERT a storage object (no write policy)');
-- No UPDATE/DELETE policy exists for devices: both statements silently touch
-- ZERO rows (RLS filters them out), so the object must survive unchanged.
update storage.objects set name = name || '.moved'
  where name like '%0083000f0001.png';
select is((select count(*)::int from storage.objects
    where name like '%0083000f0001.png'), 1,
  '18. a kiosk cannot UPDATE a storage object (readable row survives rename)');
select throws_ok(
  $$ delete from storage.objects where name like '%0083000f0001.png' $$,
  '42501', null,
  '19. a kiosk cannot DELETE a storage object (refused outright)');

-- ============================================================================
-- RF-118 EXPIRY PARITY (23-27) — KIOSK-001-PREREQ-084. now() is frozen for
-- the whole pgTAP transaction, so the exactly-now boundary is deterministic.
-- ============================================================================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000810"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '23. an EXPIRED kiosk session (past expires_at) sees ZERO images');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000811"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '24. the exactly-now expiry boundary is DENIED (expires_at > now() is strict)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000812"}';
select is((select count(*)::int from storage.objects where name like '%0083000f0001.png'), 1,
  '25. a legacy NULL-expiry kiosk session is still accepted (restore parity)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000813"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  '26. an EXPIRED POS session sees ZERO images (RF-118 applied to POS too)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-008300000814"}';
select is((select count(*)::int from storage.objects where name like '%0083000f0001.png'), 1,
  '27. a legacy NULL-expiry POS session is still accepted (restore parity)');

-- ============================================================================
-- ROLE / ACL SURFACE (20-22)
-- ============================================================================
reset role;
select is((select array_agg(r order by r) from (
    select unnest(polroles::regrole[])::text as r
      from pg_policy where polname = 'menu_images_device_select') x),
  array['authenticated'],
  '20. the device SELECT policy still targets authenticated ONLY (no anon)');
select ok(
  has_function_privilege('authenticated', 'app.device_can_read_menu_image(text)', 'execute')
  and not has_function_privilege('anon', 'app.device_can_read_menu_image(text)', 'execute'),
  '21. the helper stays authenticated-only (anon cannot execute)');
select ok(
  (select pg_get_functiondef(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'device_can_read_menu_image')
  like '%in (''pos'', ''kiosk'')%',
  '22. the live allowlist is EXACTLY pos+kiosk (KDS excluded by construction)');
select ok(
  (select pg_get_functiondef(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'device_can_read_menu_image')
  like '%(ds.expires_at is null or ds.expires_at > now())%',
  '28. the LIVE definition carries the exact RF-118 expiry predicate (084)');

select * from finish();
rollback;
