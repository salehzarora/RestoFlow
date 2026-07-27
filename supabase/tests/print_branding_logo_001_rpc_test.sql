-- ============================================================================
-- PRINT-BRANDING-LOGO-001 — pgTAP: the versioned CAS write RPC
-- app.set_restaurant_receipt_logo + read app.get_restaurant_receipt_logo.
-- Named-role authorization (org_owner/restaurant_owner/manager allowed;
-- cashier/kitchen/accountant/cross-tenant/anonymous denied), path-ownership
-- validation, enabled<->path coupling, optimistic compare-and-set on the
-- version, idempotent replay, before/after audit, and no cross-tenant leak.
-- Fixtures seeded by BYPASSRLS; RPC calls run as authenticated principals.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(39);

insert into auth.users (id, email) values
  ('c3000000-0000-0000-0000-0000000a0001', 'pbl-rpc-owner@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0002', 'pbl-rpc-restowner@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0003', 'pbl-rpc-manager@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0004', 'pbl-rpc-cashier@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0005', 'pbl-rpc-kitchen@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0006', 'pbl-rpc-acct@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0007', 'pbl-rpc-ownerb@ex.test'),
  ('c3000000-0000-0000-0000-0000000a0008', 'pbl-rpc-nobody@ex.test');
insert into organizations (id, name, slug, default_currency) values
  ('c3000000-0000-0000-0000-0000000000a0', 'Org A', 'pblrpc-a', 'USD'),
  ('c3000000-0000-0000-0000-0000000000b0', 'Org B', 'pblrpc-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('c3000000-0000-0000-0000-0000000000a1', 'c3000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('c3000000-0000-0000-0000-0000000000a2', 'c3000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('c3000000-0000-0000-0000-0000000000a3', 'c3000000-0000-0000-0000-0000000000a0', 'Rest A3'),
  ('c3000000-0000-0000-0000-0000000000a4', 'c3000000-0000-0000-0000-0000000000a0', 'Rest A4'),
  ('c3000000-0000-0000-0000-0000000000b1', 'c3000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into app_users (id, email, auth_user_id) values
  ('c3000000-0000-0000-0000-00000000ee01', 'pbl-rpc-owner@ex.test',     'c3000000-0000-0000-0000-0000000a0001'),
  ('c3000000-0000-0000-0000-00000000ee02', 'pbl-rpc-restowner@ex.test', 'c3000000-0000-0000-0000-0000000a0002'),
  ('c3000000-0000-0000-0000-00000000ee03', 'pbl-rpc-manager@ex.test',   'c3000000-0000-0000-0000-0000000a0003'),
  ('c3000000-0000-0000-0000-00000000ee04', 'pbl-rpc-cashier@ex.test',   'c3000000-0000-0000-0000-0000000a0004'),
  ('c3000000-0000-0000-0000-00000000ee05', 'pbl-rpc-kitchen@ex.test',   'c3000000-0000-0000-0000-0000000a0005'),
  ('c3000000-0000-0000-0000-00000000ee06', 'pbl-rpc-acct@ex.test',      'c3000000-0000-0000-0000-0000000a0006'),
  ('c3000000-0000-0000-0000-00000000ee07', 'pbl-rpc-ownerb@ex.test',    'c3000000-0000-0000-0000-0000000a0007'),
  ('c3000000-0000-0000-0000-00000000ee08', 'pbl-rpc-nobody@ex.test',    'c3000000-0000-0000-0000-0000000a0008');
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('c3000000-0000-0000-0000-00000000ee01', 'c3000000-0000-0000-0000-0000000000a0', null,                                   null, 'org_owner'),
  ('c3000000-0000-0000-0000-00000000ee02', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1', null, 'restaurant_owner'),
  ('c3000000-0000-0000-0000-00000000ee03', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a2', null, 'manager'),
  ('c3000000-0000-0000-0000-00000000ee04', 'c3000000-0000-0000-0000-0000000000a0', null,                                   null, 'cashier'),
  ('c3000000-0000-0000-0000-00000000ee05', 'c3000000-0000-0000-0000-0000000000a0', null,                                   null, 'kitchen_staff'),
  ('c3000000-0000-0000-0000-00000000ee06', 'c3000000-0000-0000-0000-0000000000a0', null,                                   null, 'accountant'),
  ('c3000000-0000-0000-0000-00000000ee07', 'c3000000-0000-0000-0000-0000000000b0', null,                                   null, 'org_owner');

create temp table _res (label text primary key, r jsonb);
grant select, insert on _res to authenticated;

set local role authenticated;
set local app.current_app_user_id = '';

-- ===== restaurant_owner sets A1 (v0 -> v1) ==================================
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0002","aal":"aal2"}';
insert into _res values ('ro_set', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0001', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f1.png', true, 0));
select is((select r ->> 'ok' from _res where label='ro_set'), 'true', 'restaurant_owner CAN set the logo');
select is((select (r ->> 'receipt_logo_version')::int from _res where label='ro_set'), 1, 'first accepted set bumps version 0 -> 1');
select is((select r ->> 'receipt_logo_enabled' from _res where label='ro_set'), 'true', 'the set result reports enabled=true');
select is((select r ->> 'receipt_logo_path' from _res where label='ro_set'),
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f1.png',
  'the set result echoes the authoritative path');

-- ===== stale expected_version -> version_conflict (no ledger claim) =========
insert into _res values ('conflict', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0002', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f9.png', true, 0));
select is((select r ->> 'error' from _res where label='conflict'), 'version_conflict', 'a stale expected_version returns version_conflict');
select is((select (r ->> 'receipt_logo_version')::int from _res where label='conflict'), 1, 'the conflict result carries the CURRENT authoritative version');
select is((select r ->> 'receipt_logo_path' from _res where label='conflict'),
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f1.png',
  'the conflict result carries the CURRENT authoritative path (so the client can refresh)');

-- ===== idempotent replay (same request id + same input) -> stored result ====
insert into _res values ('ro_replay', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0001', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f1.png', true, 0));
select is((select r ->> 'idempotent_replay' from _res where label='ro_replay'), 'true', 'replaying the same request id returns idempotent_replay=true');
select is((select (r ->> 'receipt_logo_version')::int from _res where label='ro_replay'), 1, 'the replay returns the ORIGINAL version (CAS not re-run)');

-- ===== same request id, different input -> 42501 ============================
select throws_ok($$ select public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0001', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-000000000fbb.png', false, 0) $$,
  '42501', null, 'reusing a client_request_id with different input raises (idempotency guard)');

-- ===== toggle OFF (keep path, disable) v1 -> v2 =============================
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
insert into _res values ('toggle_off', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0003', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f1.png', false, 1));
select is((select r ->> 'ok' from _res where label='toggle_off'), 'true', 'org_owner CAN toggle the logo off');
select is((select (r ->> 'receipt_logo_version')::int from _res where label='toggle_off'), 2, 'toggle bumps version 1 -> 2');
select is((select r ->> 'receipt_logo_enabled' from _res where label='toggle_off'), 'false', 'toggle-off reports enabled=false');
select is((select r ->> 'receipt_logo_path' from _res where label='toggle_off'),
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a1/logo/c3000000-0000-0000-0000-0000000000f1.png',
  'toggle-off PRESERVES the path');

-- ===== removal (path null) forces disabled, v2 -> v3 ========================
insert into _res values ('remove', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0004', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1',
  null, false, 2));
select is((select r ->> 'ok' from _res where label='remove'), 'true', 'org_owner CAN remove the logo');
select is((select (r -> 'receipt_logo_path') from _res where label='remove'), 'null'::jsonb, 'removal stores a NULL path');
select is((select r ->> 'receipt_logo_enabled' from _res where label='remove'), 'false', 'removal forces disabled');
select is((select (r ->> 'receipt_logo_version')::int from _res where label='remove'), 3, 'removal bumps version 2 -> 3');

-- ===== manager (A2) + org_owner (A3) allowed ================================
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
insert into _res values ('mgr_set', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0005', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a2',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a2/logo/c3000000-0000-0000-0000-0000000000f2.png', true, 0));
select is((select r ->> 'ok' from _res where label='mgr_set'), 'true', 'a restaurant-scoped MANAGER CAN set the logo (§2)');
select is((select (r ->> 'receipt_logo_version')::int from _res where label='mgr_set'), 1, 'the manager set bumps version to 1');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
insert into _res values ('owner_set', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0006', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a3',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a3/logo/c3000000-0000-0000-0000-0000000000f3.png', true, 0));
select is((select r ->> 'ok' from _res where label='owner_set'), 'true', 'org_owner CAN set the logo');

-- ===== denials on A4 (never bump version) ===================================
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
insert into _res values ('cashier', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0007', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a4/logo/c3000000-0000-0000-0000-0000000000f4.png', true, 0));
select is((select r ->> 'error' from _res where label='cashier'), 'permission_denied', 'cashier is DENIED');
select ok((select not (r ? 'receipt_logo_version') and not (r ? 'receipt_logo_path') from _res where label='cashier'),
  'the denial result leaks NO current path/version (§6.11)');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
insert into _res values ('kitchen', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0008', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a4/logo/c3000000-0000-0000-0000-0000000000f4.png', true, 0));
select is((select r ->> 'error' from _res where label='kitchen'), 'permission_denied', 'kitchen_staff is DENIED');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
insert into _res values ('acct', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c0009', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a4/logo/c3000000-0000-0000-0000-0000000000f4.png', true, 0));
select is((select r ->> 'error' from _res where label='acct'), 'permission_denied', 'accountant is DENIED');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0008","aal":"aal2"}';
select throws_ok($$ select public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c000a', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a4/logo/c3000000-0000-0000-0000-0000000000f4.png', true, 0) $$,
  '42501', null, 'a non-member (no covering membership) is DENIED (raises)') ;
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0007","aal":"aal2"}';
select throws_ok($$ select public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c000b', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'c3000000-0000-0000-0000-0000000000a0/c3000000-0000-0000-0000-0000000000a4/logo/c3000000-0000-0000-0000-0000000000f4.png', true, 0) $$,
  '42501', null, 'an Org B owner is DENIED on Org A (cross-tenant, raises)');

-- ===== path-ownership + enabled/path coupling (org_owner; invalid) ==========
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
insert into _res values ('xtenant_path', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c000c', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'c3000000-0000-0000-0000-0000000000b0/c3000000-0000-0000-0000-0000000000b1/logo/c3000000-0000-0000-0000-0000000000f4.png', true, 0));
select is((select r ->> 'reason' from _res where label='xtenant_path'), 'path_scope_mismatch', 'a cross-tenant object path is rejected as invalid');
insert into _res values ('malformed_path', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c000d', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  'not/a/valid-logo-key.png', true, 0));
select is((select r ->> 'reason' from _res where label='malformed_path'), 'malformed_path', 'a malformed object path is rejected as invalid');
insert into _res values ('enabled_null', public.set_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000c000e', 'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a4',
  null, true, 0));
select is((select r ->> 'reason' from _res where label='enabled_null'), 'enabled_requires_path', 'enabling with a NULL path is rejected as invalid');

-- ===== read RPC =============================================================
insert into _res values ('get_a1', public.get_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1'));
select is((select (r ->> 'receipt_logo_version')::int from _res where label='get_a1'), 3, 'the read RPC returns A1''s final version (3)');
select is((select (r -> 'receipt_logo_path') from _res where label='get_a1'), 'null'::jsonb, 'the read RPC returns A1''s NULL path (removed)');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0008","aal":"aal2"}';
insert into _res values ('get_nobody', public.get_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1'));
select is((select r ->> 'error' from _res where label='get_nobody'), 'not_found', 'a non-member read returns not_found (no leak)');
set local request.jwt.claims = '{"sub":"c3000000-0000-0000-0000-0000000a0007","aal":"aal2"}';
insert into _res values ('get_xorg', public.get_restaurant_receipt_logo(
  'c3000000-0000-0000-0000-0000000000a0', 'c3000000-0000-0000-0000-0000000000a1'));
select is((select r ->> 'error' from _res where label='get_xorg'), 'not_found', 'a cross-org read returns not_found (no leak)');

-- ===== audit + final DB state (connection role) =============================
reset role;
select ok(exists(select 1 from public.audit_events
  where action='settings.restaurant.logo_updated' and restaurant_id='c3000000-0000-0000-0000-0000000000a1'),
  'an accepted change writes settings.restaurant.logo_updated');
select ok(exists(select 1 from public.audit_events
  where action='settings.restaurant.logo_update_denied' and restaurant_id='c3000000-0000-0000-0000-0000000000a4'),
  'a denied change writes settings.restaurant.logo_update_denied');
select is((select receipt_logo_version from public.restaurants where id='c3000000-0000-0000-0000-0000000000a1'), 3,
  'A1 persisted at version 3');
select is((select receipt_logo_path from public.restaurants where id='c3000000-0000-0000-0000-0000000000a1'), null,
  'A1 persisted with a NULL path');
select is((select receipt_logo_version from public.restaurants where id='c3000000-0000-0000-0000-0000000000a4'), 0,
  'A4 never mutated by any denied/invalid attempt (still version 0)');

select * from finish();
rollback;
