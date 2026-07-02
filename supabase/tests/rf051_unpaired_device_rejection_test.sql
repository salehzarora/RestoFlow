-- ============================================================================
-- RF-051 — pgTAP: PIN session cannot be established on an unpaired/revoked
--          device (AC#1, RISK R-007). Exercised through app.start_pin_session.
-- ============================================================================
-- The RF-016 backing guard already rejects an active pin_session whose backing
-- is invalid (23514, tested in rf016_constraints_test). Here we prove the RPC
-- entry path itself refuses (42501) on every bad-backing case and succeeds on a
-- valid paired device. Fixtures inserted as the BYPASSRLS connection role; the
-- RPC is SECURITY DEFINER (validates scope itself; no GUC context needed).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(7);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r51u-org-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
-- pairings: active / suspended / revoked
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'suspended'),
  ('00000000-0000-0000-0000-00000000fa13', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'revoked');
-- device_sessions: ok / inactive / revoked / on-suspended-pairing / on-revoked-pairing
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', true,  null),   -- OK
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', false, null),   -- inactive
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11', true,  now()),  -- revoked
  ('00000000-0000-0000-0000-0000000005a4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa12', true,  null),   -- on suspended pairing
  ('00000000-0000-0000-0000-0000000005a5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa13', true,  null);   -- on revoked pairing
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'r51u-user@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01', extensions.crypt('ref:test-correct', extensions.gen_salt('bf')));

-- valid paired device + correct verifier => a session is created ------------- 1-2
select ok(
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) is not null,
  'valid active paired device + correct verifier: a PIN session is created');
select is((select count(*) from pin_sessions where device_session_id='00000000-0000-0000-0000-0000000005a1' and is_active)::int, 1,
  'valid case created exactly one ACTIVE pin_session');

-- every bad-backing case is rejected by the RPC (42501) ---------------------- 3-7
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a2','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) $$, '42501', NULL,
  'INACTIVE device session: PIN session rejected');
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a3','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) $$, '42501', NULL,
  'REVOKED device session: PIN session rejected');
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a4','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) $$, '42501', NULL,
  'device session on a SUSPENDED pairing: PIN session rejected');
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a5','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) $$, '42501', NULL,
  'device session on a REVOKED pairing: PIN session rejected');
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-00000000dead','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) $$, '42501', NULL,
  'unknown device session: PIN session rejected');

select * from finish();
rollback;
