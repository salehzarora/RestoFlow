-- ============================================================================
-- RF-061 — pgTAP: app.revoke_device
-- ============================================================================
-- A manager revokes a same-org, in-scope target device: its pairing -> revoked
-- (+revoked_at) and its device_sessions -> inactive +revoked_at, with a device.revoked
-- audit. A cashier is denied (device.revoke_denied + permission_denied). A cross-org
-- target is rejected. Re-revoking is idempotent (clean replay). Fixtures inserted as the
-- BYPASSRLS connection role; RPCs invoked as the connection role (actor from the PIN session).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(10);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf061rd-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf061rd-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),  -- actor device
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kds'),  -- TARGET device
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', 'pos');  -- cross-org device
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', 'active'),
  ('00000000-0000-0000-0000-00000000fb11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1d1', '00000000-0000-0000-0000-00000000db11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf061rd-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf061rd-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-00000000ab02', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef002', '00000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- ===== manager revokes the target device da12 =============================== 1-6
select is((app.revoke_device('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000da12','op-rd','lost device') ->> 'ok')::boolean, true,
  'manager can revoke a same-org, in-scope target device');
select is((select status from device_pairings where device_id='00000000-0000-0000-0000-00000000da12')::text, 'revoked', 'the target pairing is revoked');
select isnt((select revoked_at from device_pairings where device_id='00000000-0000-0000-0000-00000000da12'), null, 'the target pairing carries revoked_at');
select is((select is_active from device_sessions where id='00000000-0000-0000-0000-0000000005a2'), false, 'the target device_session is inactive');
select isnt((select revoked_at from device_sessions where id='00000000-0000-0000-0000-0000000005a2'), null, 'the target device_session carries revoked_at');
select ok(exists(select 1 from audit_events where action='device.revoked' and (new_values->>'target_device_id')='00000000-0000-0000-0000-00000000da12'),
  'a device.revoked audit row was written');

-- ===== a cashier cannot revoke (audited denial) ============================= 7-8
select is((app.revoke_device('00000000-0000-0000-0000-00000000c502','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000da12','op-rd2','try') ->> 'error'), 'permission_denied',
  'a cashier cannot revoke a device (permission_denied)');
select ok(exists(select 1 from audit_events where action='device.revoke_denied' and (new_values->>'role')='cashier'),
  'the denied device revoke is audited (device.revoke_denied)');

-- ===== cross-org target is rejected ========================================= 9
select throws_ok(
  $$ select app.revoke_device('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000db11','op-rd3','x') $$,
  '42501', NULL, 'a cross-org target device cannot be revoked');

-- ===== idempotent re-revoke ================================================= 10
select is((app.revoke_device('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000da12','op-rd4','again') ->> 'idempotency_replay')::boolean, true,
  're-revoking an already-revoked device is an idempotent clean replay (no extra mutation)');

select * from finish();
rollback;
