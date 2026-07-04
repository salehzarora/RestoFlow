-- ============================================================================
-- RF-117 — pgTAP: per-branch tax setting (branches.tax_enabled/tax_rate_bp) +
-- its three RPCs (owner write / member read / token-proven device read).
--  * app.set_branch_tax  — rank >= restaurant_owner; manager/cashier DENIED;
--    cross-tenant 42501; rate_bp bounds; persists; audit.
--  * app.get_branch_tax  — any active member; cross-tenant => not_found.
--  * app.get_device_branch_tax — token-proven; wrong/revoked token => invalid_session.
--  * default OFF (tax_enabled false, rate_bp 0) on an untouched branch.
-- Fixtures inserted as the BYPASSRLS harness role; RPCs run as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000121000a00', 'Org A', 'rf117tax-a', 'ILS'),
  ('00000000-0000-0000-0000-000121000b00', 'Org B', 'rf117tax-b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000121000a10', '00000000-0000-0000-0000-000121000a00', 'Rest A1'),
  ('00000000-0000-0000-0000-000121000b10', '00000000-0000-0000-0000-000121000b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000121000a1a', '00000000-0000-0000-0000-000121000a00', '00000000-0000-0000-0000-000121000a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-000121000b1a', '00000000-0000-0000-0000-000121000b00', '00000000-0000-0000-0000-000121000b10', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000121000e01', 'rf117tax-owner@example.test'),
  ('00000000-0000-0000-0000-000121000e03', 'rf117tax-manager@example.test'),
  ('00000000-0000-0000-0000-000121000e04', 'rf117tax-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000121000f01', '00000000-0000-0000-0000-000121000e01', '00000000-0000-0000-0000-000121000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000121000f03', '00000000-0000-0000-0000-000121000e03', '00000000-0000-0000-0000-000121000a00', '00000000-0000-0000-0000-000121000a10', '00000000-0000-0000-0000-000121000a1a', 'manager'),
  ('00000000-0000-0000-0000-000121000f04', '00000000-0000-0000-0000-000121000e04', '00000000-0000-0000-0000-000121000a00', '00000000-0000-0000-0000-000121000a10', '00000000-0000-0000-0000-000121000a1a', 'cashier');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-000121004001', '00000000-0000-0000-0000-000121000a00', '00000000-0000-0000-0000-000121000a10', '00000000-0000-0000-0000-000121000a1a', 'pos', 'Front POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-000121004011', '00000000-0000-0000-0000-000121000a00', '00000000-0000-0000-0000-000121000a10', '00000000-0000-0000-0000-000121000a1a', '00000000-0000-0000-0000-000121004001', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-000121004051', '00000000-0000-0000-0000-000121000a00', '00000000-0000-0000-0000-000121000a10', '00000000-0000-0000-0000-000121000a1a', '00000000-0000-0000-0000-000121004001', '00000000-0000-0000-0000-000121004011', app.hash_provisioning_secret('tok-tax-pos'), true, null);

set local role authenticated;

-- ===== A. OWNER write (rank gate + bounds) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-000121000e01';  -- org_owner
select is(
  (app.set_branch_tax('00000000-0000-0000-0000-000121000c01','00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a', true, 1700) ->> 'ok'),
  'true', 'org_owner may enable tax at 17.00%% (1700 bp)');                                                      -- 1

set local app.current_app_user_id = '00000000-0000-0000-0000-000121000e03';  -- manager
select is(
  (app.set_branch_tax('00000000-0000-0000-0000-000121000c03','00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a', true, 500) ->> 'error'),
  'permission_denied', 'manager cannot change tax (permission_denied)');                                        -- 2
set local app.current_app_user_id = '00000000-0000-0000-0000-000121000e04';  -- cashier
select is(
  (app.set_branch_tax('00000000-0000-0000-0000-000121000c04','00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a', true, 500) ->> 'error'),
  'permission_denied', 'cashier cannot change tax (permission_denied)');                                        -- 3

set local app.current_app_user_id = '00000000-0000-0000-0000-000121000e01';  -- org_owner
select throws_ok(
  $$ select app.set_branch_tax('00000000-0000-0000-0000-000121000c05','00000000-0000-0000-0000-000121000b00','00000000-0000-0000-0000-000121000b10','00000000-0000-0000-0000-000121000b1a', true, 1700) $$,
  '42501', NULL, 'org_owner of Org A cannot set tax on Org B''s branch (cross-tenant; 42501)');                  -- 4
select throws_ok(
  $$ select app.set_branch_tax('00000000-0000-0000-0000-000121000c06','00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a', true, 10001) $$,
  '42501', NULL, 'a rate above 10000 basis points is rejected (42501)');                                         -- 5
select throws_ok(
  $$ select app.set_branch_tax('00000000-0000-0000-0000-000121000c07','00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a', true, -1) $$,
  '42501', NULL, 'a negative rate is rejected (42501)');                                                         -- 6

-- public wrapper (org_owner) sets rate to 1800.
select is(
  (public.set_branch_tax('00000000-0000-0000-0000-000121000c08','00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a', true, 1800) ->> 'ok'),
  'true', 'public.set_branch_tax wrapper works (org_owner)');                                                    -- 7

-- ===== B. Dashboard READ =====
select is(
  (app.get_branch_tax('00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a') ->> 'tax_rate_bp'),
  '1800', 'the member read reflects the persisted rate (1800)');                                                 -- 8
select is(
  (app.get_branch_tax('00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a') ->> 'tax_enabled'),
  'true', 'the member read reflects tax_enabled');                                                               -- 9
set local app.current_app_user_id = '00000000-0000-0000-0000-000121000e04';  -- cashier (permissive read)
select is(
  (app.get_branch_tax('00000000-0000-0000-0000-000121000a00','00000000-0000-0000-0000-000121000a10','00000000-0000-0000-0000-000121000a1a') ->> 'ok'),
  'true', 'any active member (cashier) may READ the tax setting');                                               -- 10
set local app.current_app_user_id = '00000000-0000-0000-0000-000121000e01';  -- org_owner of Org A
select is(
  (app.get_branch_tax('00000000-0000-0000-0000-000121000b00','00000000-0000-0000-0000-000121000b10','00000000-0000-0000-0000-000121000b1a') ->> 'error'),
  'not_found', 'org_owner of Org A cannot read Org B''s tax setting (not_found)');                               -- 11

-- ===== C. TOKEN-PROVEN POS device READ =====
set local app.current_app_user_id = '';   -- anonymous authenticated device
select is(
  (app.get_device_branch_tax('00000000-0000-0000-0000-000121004001', 'tok-tax-pos') ->> 'tax_rate_bp'),
  '1800', 'a valid device token reads its own branch tax rate');                                                 -- 12
select is(
  (app.get_device_branch_tax('00000000-0000-0000-0000-000121004001', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong device token fails closed (invalid_session)');                                     -- 13

-- ===== D. DB state + default (as the BYPASSRLS owner) =====
reset role;
select is(
  (select tax_rate_bp from branches where id = '00000000-0000-0000-0000-000121000a1a')::int,
  1800, 'the owner write persisted tax_rate_bp = 1800');                                                         -- 14
select is(
  (select (tax_enabled, tax_rate_bp)::text from branches where id = '00000000-0000-0000-0000-000121000b1a'),
  (false, 0)::text, 'an untouched branch defaults to tax OFF (disabled, rate 0)');                               -- 15

select * from finish();
rollback;
