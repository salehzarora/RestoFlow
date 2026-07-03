-- ============================================================================
-- MVP — pgTAP: app.revoke_device_management (JWT/dashboard device revocation).
-- Role/rank matrix over the DEVICE'S ACTUAL scope, cross-tenant isolation
-- (RISK R-003), revocation effects (device off + pairings/sessions revoked,
-- mirroring RF-061), committed denial audit, ledger idempotency (no
-- double-revoke / double-audit), and public-wrapper introspection.
-- GUC-FREE (identity GUC only), mirroring rf160_list_devices_test.sql.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(24);

-- ===== fixture: two orgs; Org A has one restaurant with two branches ==========
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00000de10a00', 'Org A', 'mvpdmr-a', 'USD'),
  ('00000000-0000-0000-0000-00000de10b00', 'Org B', 'mvpdmr-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a00', 'Rest A1'),
  ('00000000-0000-0000-0000-00000de10b10', '00000000-0000-0000-0000-00000de10b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000de10a1a', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000de10a1b', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', 'Branch A1b'),
  ('00000000-0000-0000-0000-00000de10b1a', '00000000-0000-0000-0000-00000de10b00', '00000000-0000-0000-0000-00000de10b10', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000de10e01', 'mvpdmr-owner@example.test'),
  ('00000000-0000-0000-0000-00000de10e02', 'mvpdmr-manager@example.test'),
  ('00000000-0000-0000-0000-00000de10e03', 'mvpdmr-cashier@example.test'),
  ('00000000-0000-0000-0000-00000de10e04', 'mvpdmr-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000de10f01', '00000000-0000-0000-0000-00000de10e01', '00000000-0000-0000-0000-00000de10a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000de10f02', '00000000-0000-0000-0000-00000de10e02', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', 'manager'),
  ('00000000-0000-0000-0000-00000de10f03', '00000000-0000-0000-0000-00000de10e03', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', 'cashier'),
  ('00000000-0000-0000-0000-00000de10f04', '00000000-0000-0000-0000-00000de10e04', '00000000-0000-0000-0000-00000de10b00', null, null, 'org_owner');
-- d1..d3 @ Branch A1a; d4 @ sibling Branch A1b; d5 @ Org B.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-00000de10d01', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', 'pos', 'Front POS'),
  ('00000000-0000-0000-0000-00000de10d02', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', 'kds', 'Kitchen KDS'),
  ('00000000-0000-0000-0000-00000de10d03', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', 'pos', 'Bar POS'),
  ('00000000-0000-0000-0000-00000de10d04', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1b', 'pos', 'Sibling POS'),
  ('00000000-0000-0000-0000-00000de10d05', '00000000-0000-0000-0000-00000de10b00', '00000000-0000-0000-0000-00000de10b10', '00000000-0000-0000-0000-00000de10b1a', 'pos', 'OrgB POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at) values
  ('00000000-0000-0000-0000-00000de11001', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', '00000000-0000-0000-0000-00000de10d01', 'active', now()),
  ('00000000-0000-0000-0000-00000de11002', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', '00000000-0000-0000-0000-00000de10d02', 'paired', now()),
  ('00000000-0000-0000-0000-00000de11003', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', '00000000-0000-0000-0000-00000de10d03', 'active', now()),
  ('00000000-0000-0000-0000-00000de11004', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1b', '00000000-0000-0000-0000-00000de10d04', 'active', now()),
  ('00000000-0000-0000-0000-00000de11005', '00000000-0000-0000-0000-00000de10b00', '00000000-0000-0000-0000-00000de10b10', '00000000-0000-0000-0000-00000de10b1a', '00000000-0000-0000-0000-00000de10d05', 'active', now());
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000de12001', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', '00000000-0000-0000-0000-00000de10d01', '00000000-0000-0000-0000-00000de11001'),
  ('00000000-0000-0000-0000-00000de12002', '00000000-0000-0000-0000-00000de10a00', '00000000-0000-0000-0000-00000de10a10', '00000000-0000-0000-0000-00000de10a1a', '00000000-0000-0000-0000-00000de10d02', '00000000-0000-0000-0000-00000de11002');

-- ===== (1-8) org_owner revokes d1: result + effects + audit ====================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e01';
create temp table t_rev1 as select app.revoke_device_management(
  '00000000-0000-0000-0000-00000de19901', '00000000-0000-0000-0000-00000de10d01', 'stolen device') as res;
reset role;
select is((select (res->>'ok')::boolean from t_rev1), true, 'org_owner revoke returns ok=true');
select is((select res->>'entity' from t_rev1), 'device', 'result entity is device');
select is((select (res->>'pairings_revoked')::int from t_rev1), 1, 'result reports 1 pairing revoked');
select is((select (res->>'sessions_revoked')::int from t_rev1), 1, 'result reports 1 session revoked');
select ok((select not is_active from devices where id='00000000-0000-0000-0000-00000de10d01'),
          'the device is inactive (devices.is_active=false)');
select is((select status || '/' || (revoked_at is not null)::text
             from device_pairings where id='00000000-0000-0000-0000-00000de11001'),
          'revoked/true', 'the live pairing is revoked with revoked_at set');
select is((select count(*) from device_sessions
            where device_id='00000000-0000-0000-0000-00000de10d01'
              and (is_active or revoked_at is null))::int,
          0, 'no live device session remains for the revoked device');
select is((select count(*) from audit_events
            where action='device.revoked_management'
              and actor_app_user_id='00000000-0000-0000-0000-00000de10e01'
              and new_values->>'device_id'='00000000-0000-0000-0000-00000de10d01')::int,
          1, 'success wrote a device.revoked_management audit (D-013)');

-- ===== (9-10) branch manager (A1a) revokes an in-scope device d2 ===============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e02';
create temp table t_rev2 as select app.revoke_device_management(
  '00000000-0000-0000-0000-00000de19902', '00000000-0000-0000-0000-00000de10d02', 'redeployed') as res;
reset role;
select is((select (res->>'ok')::boolean from t_rev2), true, 'branch manager revokes an own-branch device (ok=true)');
select ok((select not is_active from devices where id='00000000-0000-0000-0000-00000de10d02'),
          'the manager-revoked device is inactive');

-- ===== (11-13) cashier is role-denied: audited, nothing mutated ================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e03';
create temp table t_cashier as select app.revoke_device_management(
  '00000000-0000-0000-0000-00000de19903', '00000000-0000-0000-0000-00000de10d03', 'sneaky') as res;
reset role;
select is((select res->>'error' from t_cashier), 'permission_denied', 'cashier revoke is permission_denied (ok:false)');
select is((select (select is_active from devices where id='00000000-0000-0000-0000-00000de10d03')::text
             || '/' || (select status from device_pairings where id='00000000-0000-0000-0000-00000de11003')),
          'true/active', 'cashier denial mutated NOTHING (device active, pairing active)');
select is((select count(*) from audit_events
            where action='device.revoke_management_denied'
              and actor_app_user_id='00000000-0000-0000-0000-00000de10e03')::int,
          1, 'cashier denial wrote a committed revoke_management_denied audit');

-- ===== (14) cross-org caller: authorization is over the DEVICE'S actual scope ==
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e01';  -- Org A owner
select throws_ok(
  $$ select app.revoke_device_management('00000000-0000-0000-0000-00000de19911', '00000000-0000-0000-0000-00000de10d05', 'x') $$,
  '42501', NULL, 'an Org A owner cannot revoke an Org B device (cross-org 42501)');
reset role;

-- ===== (15) branch-A manager cannot revoke a sibling-branch-B device ===========
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e02';  -- manager @ A1a
select throws_ok(
  $$ select app.revoke_device_management('00000000-0000-0000-0000-00000de19912', '00000000-0000-0000-0000-00000de10d04', 'x') $$,
  '42501', NULL, 'manager(A1a) cannot revoke a Branch A1b device (actual-scope authorization; 42501)');
reset role;

-- ===== (16-18) idempotent replay: same actor + client_request_id + input =======
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e01';
create temp table t_rev1b as select app.revoke_device_management(
  '00000000-0000-0000-0000-00000de19901', '00000000-0000-0000-0000-00000de10d01', 'stolen device') as res;
reset role;
select is((select (res->>'idempotent_replay')::boolean from t_rev1b), true, 'replay is flagged idempotent_replay=true');
select is((select (res->>'pairings_revoked')::int from t_rev1b), 1, 'replay returns the STORED result (original counts)');
select is((select count(*) from audit_events
            where action='device.revoked_management'
              and actor_app_user_id='00000000-0000-0000-0000-00000de10e01'
              and new_values->>'device_id'='00000000-0000-0000-0000-00000de10d01')::int,
          1, 'replay wrote NO second audit (no double-revoke)');

-- ===== (19) public.* wrapper delegates verbatim ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000de10e01';
create temp table t_wrap as select public.revoke_device_management(
  '00000000-0000-0000-0000-00000de19904', '00000000-0000-0000-0000-00000de10d03') as res;
reset role;
select is((select (res->>'ok')::boolean from t_wrap), true, 'public.revoke_device_management wrapper delegates (ok=true; reason optional)');

-- ===== (20-24) wrapper introspection: invoker / search_path / grants ===========
select is(
  (select prosecdef from pg_proc where proname='revoke_device_management' and pronamespace='public'::regnamespace and pronargs=3),
  false, 'public.revoke_device_management is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='revoke_device_management' and p.pronamespace='public'::regnamespace and p.pronargs=3
       and cfg like 'search_path=%')),
  'public.revoke_device_management has a locked search_path');
select ok(
  not has_function_privilege('public', 'public.revoke_device_management(uuid, uuid, text)', 'execute'),
  'PUBLIC may NOT execute public.revoke_device_management (revoked)');
select ok(
  not has_function_privilege('anon', 'public.revoke_device_management(uuid, uuid, text)', 'execute'),
  'anon may NOT execute public.revoke_device_management');
select ok(
  has_function_privilege('authenticated', 'public.revoke_device_management(uuid, uuid, text)', 'execute'),
  'authenticated MAY execute public.revoke_device_management');

select * from finish();
rollback;
