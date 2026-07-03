-- ============================================================================
-- RF-113 — pgTAP: branches.pos_shift_close_enabled + its three RPCs.
--  * app.set_branch_pos_shift_close_enabled — OWNER write (rank >= restaurant_owner;
--    manager/cashier DENIED -> permission_denied; cross-tenant -> 42501; persists;
--    append-only settings.branch.updated audit; public wrapper).
--  * app.get_branch_pos_shift_close_enabled — Dashboard READ (any active member of
--    the branch; cross-tenant / no membership -> not_found; reflects persisted).
--  * app.get_device_pos_shift_close_enabled — TOKEN-PROVEN POS read (invalid/wrong/
--    revoked token -> invalid_session, fail closed; reflects persisted).
--  * default TRUE for an untouched branch (no fabricated default anywhere).
-- Fixtures inserted as the BYPASSRLS harness role; RPCs run as authenticated
-- (members via the identity GUC; device as an anonymous authenticated principal).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(17);

-- ===== fixtures: Org A (Rest A1 / Branch A1a) + Org B (Rest B1 / Branch B1a) =====
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000119000a00', 'Org A', 'rf113scls-a', 'ILS'),
  ('00000000-0000-0000-0000-000119000b00', 'Org B', 'rf113scls-b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a00', 'Rest A1'),
  ('00000000-0000-0000-0000-000119000b10', '00000000-0000-0000-0000-000119000b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000119000a1a', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-000119000b1a', '00000000-0000-0000-0000-000119000b00', '00000000-0000-0000-0000-000119000b10', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000119000e01', 'rf113scls-owner@example.test'),
  ('00000000-0000-0000-0000-000119000e02', 'rf113scls-restowner@example.test'),
  ('00000000-0000-0000-0000-000119000e03', 'rf113scls-manager@example.test'),
  ('00000000-0000-0000-0000-000119000e04', 'rf113scls-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000119000f01', '00000000-0000-0000-0000-000119000e01', '00000000-0000-0000-0000-000119000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000119000f02', '00000000-0000-0000-0000-000119000e02', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', null, 'restaurant_owner'),
  ('00000000-0000-0000-0000-000119000f03', '00000000-0000-0000-0000-000119000e03', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a1a', 'manager'),
  ('00000000-0000-0000-0000-000119000f04', '00000000-0000-0000-0000-000119000e04', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a1a', 'cashier');
-- a paired POS device @ A1a with a LIVE + a REVOKED token-proven session (RF-161 shape).
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-000119004001', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a1a', 'pos', 'Front POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000119004011', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a1a', '00000000-0000-0000-0000-000119004001', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-000119004051', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a1a', '00000000-0000-0000-0000-000119004001', '00000000-0000-0000-0000-000119004011', app.hash_provisioning_secret('tok-scls-pos'),     true,  null),
  ('00000000-0000-0000-0000-000119004052', '00000000-0000-0000-0000-000119000a00', '00000000-0000-0000-0000-000119000a10', '00000000-0000-0000-0000-000119000a1a', '00000000-0000-0000-0000-000119004001', '00000000-0000-0000-0000-000119004011', app.hash_provisioning_secret('tok-scls-revoked'), false, now());

set local role authenticated;

-- ===== A. OWNER write (rank gate) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e01';  -- org_owner
select is(
  (app.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000c01','00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a', false) ->> 'ok'),
  'true', 'org_owner may set pos_shift_close_enabled');                                                          -- 1

set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e02';  -- restaurant_owner @ A1
select is(
  (app.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000c02','00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a', true) ->> 'ok'),
  'true', 'restaurant_owner may set a branch of its restaurant');                                                -- 2

set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e03';  -- manager (rank 2 < restaurant_owner)
select is(
  (app.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000c03','00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a', false) ->> 'error'),
  'permission_denied', 'manager cannot change the policy (permission_denied)');                                  -- 3

set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e04';  -- cashier
select is(
  (app.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000c04','00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a', false) ->> 'error'),
  'permission_denied', 'cashier cannot change the policy (permission_denied)');                                  -- 4

set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e01';  -- org_owner of Org A
select throws_ok(
  $$ select app.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000c05','00000000-0000-0000-0000-000119000b00','00000000-0000-0000-0000-000119000b10','00000000-0000-0000-0000-000119000b1a', false) $$,
  '42501', NULL, 'org_owner of Org A cannot reach Org B''s branch (cross-tenant; 42501)');                       -- 5

-- public wrapper (org_owner) sets the branch to FALSE (final persisted state).
select is(
  (public.set_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000c06','00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a', false) ->> 'ok'),
  'true', 'public.set_branch_pos_shift_close_enabled wrapper works (org_owner)');                                -- 6

-- ===== B. Dashboard READ (membership) =====
select is(
  (app.get_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a') ->> 'ok'),
  'true', 'org_owner may read the branch policy');                                                               -- 7
select is(
  (app.get_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a') ->> 'pos_shift_close_enabled'),
  'false', 'the read reflects the persisted state (owner set it false)');                                        -- 8

set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e04';  -- cashier (read is permissive)
select is(
  (app.get_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000a00','00000000-0000-0000-0000-000119000a10','00000000-0000-0000-0000-000119000a1a') ->> 'ok'),
  'true', 'any active member (cashier) may READ the policy (only WRITE is owner-gated)');                        -- 9

set local app.current_app_user_id = '00000000-0000-0000-0000-000119000e01';  -- org_owner of Org A
select is(
  (app.get_branch_pos_shift_close_enabled('00000000-0000-0000-0000-000119000b00','00000000-0000-0000-0000-000119000b10','00000000-0000-0000-0000-000119000b1a') ->> 'error'),
  'not_found', 'org_owner of Org A cannot read Org B''s branch policy (not_found, no scope leak)');              -- 10

-- ===== C. TOKEN-PROVEN POS device READ =====
set local app.current_app_user_id = '';   -- anonymous authenticated device: NO app_user
select is(
  (app.get_device_pos_shift_close_enabled('00000000-0000-0000-0000-000119004001', 'tok-scls-pos') ->> 'ok'),
  'true', 'a valid device token reads its own branch policy');                                                   -- 11
select is(
  (app.get_device_pos_shift_close_enabled('00000000-0000-0000-0000-000119004001', 'tok-scls-pos') ->> 'pos_shift_close_enabled'),
  'false', 'the device read reflects the persisted state (false)');                                              -- 12
select is(
  (app.get_device_pos_shift_close_enabled('00000000-0000-0000-0000-000119004001', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong device token fails closed (invalid_session, no scope leak)');                      -- 13
select is(
  (app.get_device_pos_shift_close_enabled('00000000-0000-0000-0000-000119004001', 'tok-scls-revoked') ->> 'error'),
  'invalid_session', 'a REVOKED device session fails closed (invalid_session)');                                 -- 14

-- ===== D. DB state + default + audit (as the BYPASSRLS owner) =====
reset role;
select is(
  (select pos_shift_close_enabled from branches where id = '00000000-0000-0000-0000-000119000a1a'),
  false, 'the owner write actually persisted pos_shift_close_enabled = false');                                 -- 15
select is(
  (select pos_shift_close_enabled from branches where id = '00000000-0000-0000-0000-000119000b1a'),
  true, 'an untouched branch defaults to pos_shift_close_enabled = true (no fabricated default)');               -- 16
select ok(
  (select count(*) from audit_events where action = 'settings.branch.updated'
     and branch_id = '00000000-0000-0000-0000-000119000a1a') >= 1,
  'at least one append-only settings.branch.updated audit row was written');                                    -- 17

select * from finish();
rollback;
