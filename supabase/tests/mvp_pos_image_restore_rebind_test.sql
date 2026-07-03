-- ============================================================================
-- MVP (POS image fix) — pgTAP: restore_device_session re-binds the storage
-- read principal.
--
-- A device signs in anonymously with a FRESH principal every launch, so the
-- redeem-time device_sessions.auth_user_id binding goes stale after the first
-- restart and the menu_images_device_select policy denies every signed-URL
-- request (POS cards fall back to icons). Pins: a token-proven restore
-- re-binds to the CURRENT principal (new principal reads, stale principal
-- stops reading); an invalid token never rebinds; a legacy NULL binding heals
-- on restore (no re-pair); a KDS session rebinds but STILL reads zero images
-- (T-014); no-principal callers (auth.uid() null) restore without rebinding.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(14);

-- ===== fixtures (BYPASSRLS connection role) =================================
insert into organizations (id, name, slug, default_currency) values
  ('78000000-0000-0000-0000-0000000000a0', 'Org RB', 'rebind-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-0000000000a0', 'Rest RB1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', 'Branch RB1a');

-- Devices: pos1 (bound to the OLD principal A), pos2 (LEGACY: unbound), kds1.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('78000000-0000-0000-0000-00000000d001', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'pos'),
  ('78000000-0000-0000-0000-00000000d002', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'pos'),
  ('78000000-0000-0000-0000-00000000d003', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('78000000-0000-0000-0000-00000000fa01', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d001', 'active'),
  ('78000000-0000-0000-0000-00000000fa02', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d002', 'active'),
  ('78000000-0000-0000-0000-00000000fa03', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d003', 'active');
insert into device_sessions
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, auth_user_id, is_active, revoked_at) values
  -- pos1: bound at "redeem time" to principal A (the launch that paired).
  ('78000000-0000-0000-0000-000000005a01', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d001', '78000000-0000-0000-0000-00000000fa01', app.hash_provisioning_secret('rebind-tok-1'), '78000000-0000-0000-0000-00000000aa0a', true, null),
  -- pos2: LEGACY session minted before the binding column existed.
  ('78000000-0000-0000-0000-000000005a02', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d002', '78000000-0000-0000-0000-00000000fa02', app.hash_provisioning_secret('rebind-tok-2'), null, true, null),
  -- kds1: bound; rebinding must still never open images (T-014).
  ('78000000-0000-0000-0000-000000005a03', '78000000-0000-0000-0000-0000000000a0', '78000000-0000-0000-0000-0000000000a1', '78000000-0000-0000-0000-00000000a1a0', '78000000-0000-0000-0000-00000000d003', '78000000-0000-0000-0000-00000000fa03', app.hash_provisioning_secret('rebind-tok-3'), '78000000-0000-0000-0000-00000000aa0f', true, null);

-- One own-branch menu image object (BYPASSRLS seed).
insert into storage.objects (bucket_id, name) values
  ('menu-images', '78000000-0000-0000-0000-0000000000a0/78000000-0000-0000-0000-0000000000a1/78000000-0000-0000-0000-00000000a1a0/menu_item/78000000-0000-0000-0000-00000000e001/78000000-0000-0000-0000-0000000f0001.png');

-- ===== (1) the restore fn is now VOLATILE (it re-binds) ======================
select is(
  (select p.provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'restore_device_session'),
  'v', 'app.restore_device_session is volatile (rebinds on success)');

-- ===== (2-5) a restore under a NEW principal re-binds the read policy ========
set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';

-- Principal B = the FRESH anonymous sign-in of a later app launch.
set local request.jwt.claims = '{"sub":"78000000-0000-0000-0000-00000000aa0b"}';
select is(
  (app.restore_device_session('78000000-0000-0000-0000-00000000d001', 'rebind-tok-1') ->> 'ok'),
  'true', 'a token-proven restore under a fresh principal still succeeds');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'menu-images'), 1,
  'after restore, the CURRENT principal can read the own-branch menu image');

-- The stale redeem-time principal A no longer reads anything.
set local request.jwt.claims = '{"sub":"78000000-0000-0000-0000-00000000aa0a"}';
select is(
  (select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  'the STALE redeem-time principal reads ZERO images after the rebind');

reset role;
select is(
  (select auth_user_id from device_sessions where id = '78000000-0000-0000-0000-000000005a01'),
  '78000000-0000-0000-0000-00000000aa0b',
  'the session row is re-bound to the restoring principal');

-- ===== (6-7) an INVALID token never rebinds ==================================
set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
set local request.jwt.claims = '{"sub":"78000000-0000-0000-0000-00000000aa0c"}';
select is(
  (app.restore_device_session('78000000-0000-0000-0000-00000000d001', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong token still fails closed');
reset role;
select is(
  (select auth_user_id from device_sessions where id = '78000000-0000-0000-0000-000000005a01'),
  '78000000-0000-0000-0000-00000000aa0b',
  'a failed restore does NOT touch the binding');

-- ===== (8-10) a LEGACY (null-bound) session heals on restore =================
set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
set local request.jwt.claims = '{"sub":"78000000-0000-0000-0000-00000000aa0d"}';
select is(
  (app.restore_device_session('78000000-0000-0000-0000-00000000d002', 'rebind-tok-2') ->> 'ok'),
  'true', 'a legacy (pre-binding) session restores fine');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'menu-images'), 1,
  'the healed legacy POS session can now read menu images (no re-pair needed)');
reset role;
select is(
  (select auth_user_id from device_sessions where id = '78000000-0000-0000-0000-000000005a02'),
  '78000000-0000-0000-0000-00000000aa0d',
  'the legacy session is bound to its restoring principal');

-- ===== (11-12) a KDS session rebinds but STILL reads no images (T-014) =======
set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
set local request.jwt.claims = '{"sub":"78000000-0000-0000-0000-00000000aa0e"}';
select is(
  (app.restore_device_session('78000000-0000-0000-0000-00000000d003', 'rebind-tok-3') ->> 'ok'),
  'true', 'a KDS restore succeeds and re-binds like any device');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  'the freshly re-bound KDS session STILL reads ZERO menu images (device_type=pos only — T-014)');
reset role;

-- ===== (13-14) no principal (auth.uid() null) => restore ok, no rebind =======
-- `set local` GUCs survive `reset role` — clear the claims so auth.uid() is
-- genuinely null for the direct-call case.
set local request.jwt.claims = '';
select is(
  (app.restore_device_session('78000000-0000-0000-0000-00000000d001', 'rebind-tok-1') ->> 'ok'),
  'true', 'restore without an auth principal (direct DB call) still succeeds');
select is(
  (select auth_user_id from device_sessions where id = '78000000-0000-0000-0000-000000005a01'),
  '78000000-0000-0000-0000-00000000aa0b',
  'no-principal restores never null out or change the binding');

select * from finish();
rollback;
