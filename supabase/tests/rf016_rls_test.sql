-- ============================================================================
-- RF-016 — pgTAP device-isolation RLS test  (RISK R-003, CRITICAL)
-- ============================================================================
-- Under the non-privileged `authenticated` role with the RF-015 GUCs
-- (app.current_app_user_id + app.current_organization_id) — reused UNCHANGED —
-- exercises ALL FOUR device tables (devices, device_pairings, device_sessions,
-- pin_sessions):
--   * no tenant context => zero rows (deny-by-default) on every table;
--   * Org A user cannot see Org B rows (org isolation);
--   * a cashier scoped to Restaurant A1 cannot see Restaurant A2 rows in the
--     same org (restaurant narrowing);
--   * a branch-scoped membership cannot see a sibling branch's rows (branch narrowing);
--   * cross-org / cross-scope writes are denied by RLS WITH CHECK (42501);
--   * a valid scoped user can read+write its allowed branch rows.
-- Fixtures inserted as the BYPASSRLS connection role; assertions run as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(37);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r16-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'r16-org-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1'),
  ('00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Branch A2'),
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),  -- RA1/BA1
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', 'kds'),  -- RA1/BA1b
  ('00000000-0000-0000-0000-00000000da21', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a2b1', 'pos'),  -- RA2/BA2
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', 'pos');  -- Org B
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da12', 'active'),
  ('00000000-0000-0000-0000-00000000fa21', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-00000000da21', 'active'),
  ('00000000-0000-0000-0000-00000000fab1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-00000000db11', 'active');  -- Org B
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),  -- RA1/BA1
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12'),  -- RA1/BA1b
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-00000000da21', '00000000-0000-0000-0000-00000000fa21'),  -- RA2/BA2
  ('00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-00000000fab1');  -- Org B

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'r16-multi@example.test'),
  ('00000000-0000-0000-0000-00000000ee02', 'r16-owner@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'r16-cashier-ra1@example.test'),
  ('00000000-0000-0000-0000-00000000ee05', 'r16-cashier-ba1@example.test');
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000b0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   'cashier'),
  ('00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
-- explicit-id memberships used as pin_sessions.resolved_membership_id (same-org FK target)
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ce01', '00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', 'org_owner'),
  ('00000000-0000-0000-0000-00000000ce02', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000b0', 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, display_name) values
  ('00000000-0000-0000-0000-0000000ef0a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Emp A1'),
  ('00000000-0000-0000-0000-0000000ef0a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', 'Emp A2'),
  ('00000000-0000-0000-0000-0000000ef0b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Emp B1');
-- pin_sessions: one in RA1, one in RA2 (Org A), one in Org B; each on an ACTIVE session+pairing
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id) values
  ('00000000-0000-0000-0000-00000000c5a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef0a1', '00000000-0000-0000-0000-00000000ce01'),
  ('00000000-0000-0000-0000-00000000c5a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000a2b1', '00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000ef0a2', '00000000-0000-0000-0000-00000000ce01'),
  ('00000000-0000-0000-0000-00000000c5a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b2', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef0a1', '00000000-0000-0000-0000-00000000ce01'),  -- RA1/BA1b sibling-branch pin_session (for CB branch-isolation, RF016-B1)
  ('00000000-0000-0000-0000-00000000c5b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000005b1', '00000000-0000-0000-0000-0000000ef0b1', '00000000-0000-0000-0000-00000000ce02');

set local role authenticated;

-- deny-by-default on ALL FOUR tables ----------------------------------------- 1-4
select is((select count(*) from devices)::int,         0, 'no context: zero devices');
select is((select count(*) from device_sessions)::int, 0, 'no context: zero device_sessions');
select is((select count(*) from device_pairings)::int, 0, 'no context: zero device_pairings');
select is((select count(*) from pin_sessions)::int,    0, 'no context: zero pin_sessions');

-- multi-org isolation (M) ---------------------------------------------------- 5-13
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from devices)::int,         3, 'M @ Org A: 3 devices');
select is((select count(*) from device_pairings)::int, 3, 'M @ Org A: 3 device_pairings');
select is((select count(*) from pin_sessions)::int,    3, 'M @ Org A: 3 pin_sessions (BA1, BA1b, RA2)');
select is((select count(*) from devices where id = '00000000-0000-0000-0000-00000000db11')::int, 0, 'M @ Org A: cannot see the Org B device');
select is((select count(*) from device_pairings where id = '00000000-0000-0000-0000-00000000fab1')::int, 0, 'M @ Org A: cannot see the Org B pairing');
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from devices)::int,         1, 'M @ Org B: 1 device');
select is((select count(*) from device_pairings)::int, 1, 'M @ Org B: 1 device_pairing');
select is((select count(*) from pin_sessions)::int,    1, 'M @ Org B: 1 pin_session');
select is((select count(*) from devices where id = '00000000-0000-0000-0000-00000000da11')::int, 0, 'M @ Org B: cannot see an Org A device');

-- org-level role sees all of its org ----------------------------------------- 14
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee02';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from devices)::int, 3, 'org_owner @ Org A: sees all Org A devices');

-- cashier scoped to Restaurant A1: RESTAURANT-level isolation on all tables --- 15-22
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee03';
select is((select count(*) from devices)::int, 2, 'cashier @ RA1: 2 RA1 devices (not RA2)');
select is((select count(*) from devices where id = '00000000-0000-0000-0000-00000000da21')::int, 0, 'cashier @ RA1: CANNOT see the RA2 device');
select is((select count(*) from device_sessions)::int, 2, 'cashier @ RA1: 2 RA1 device_sessions');
select is((select count(*) from device_sessions where id = '00000000-0000-0000-0000-0000000005a3')::int, 0, 'cashier @ RA1: CANNOT see the RA2 device_session');
select is((select count(*) from device_pairings)::int, 2, 'cashier @ RA1: 2 RA1 device_pairings');
select is((select count(*) from device_pairings where id = '00000000-0000-0000-0000-00000000fa21')::int, 0, 'cashier @ RA1: CANNOT see the RA2 device_pairing');
select is((select count(*) from pin_sessions)::int, 2, 'cashier @ RA1: 2 RA1 pin_sessions (BA1 + BA1b, not RA2)');
select is((select count(*) from pin_sessions where id = '00000000-0000-0000-0000-00000000c5a2')::int, 0, 'cashier @ RA1: CANNOT see the RA2 pin_session');

-- branch-scoped cashier: BRANCH-level narrowing ------------------------------ 23-25
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee05';
select is((select count(*) from devices where id = '00000000-0000-0000-0000-00000000da11')::int, 1, 'branch cashier @ BA1: sees its own branch device');
select is((select count(*) from devices where id = '00000000-0000-0000-0000-00000000da12')::int, 0, 'branch cashier @ BA1: does NOT see the sibling branch (BA1b) device');
select is((select count(*) from devices)::int, 1, 'branch cashier @ BA1: sees only the BA1 device');
-- RF016-B1: sibling-branch isolation must hold for device_sessions, device_pairings AND pin_sessions too
select is((select count(*) from device_sessions where id = '00000000-0000-0000-0000-0000000005a1')::int, 1, 'branch cashier @ BA1: sees its own branch device_session (5a1)');
select is((select count(*) from device_sessions where id = '00000000-0000-0000-0000-0000000005a2')::int, 0, 'branch cashier @ BA1: does NOT see the sibling branch (BA1b) device_session (5a2)');
select is((select count(*) from device_pairings where id = '00000000-0000-0000-0000-00000000fa11')::int, 1, 'branch cashier @ BA1: sees its own branch device_pairing (fa11)');
select is((select count(*) from device_pairings where id = '00000000-0000-0000-0000-00000000fa12')::int, 0, 'branch cashier @ BA1: does NOT see the sibling branch (BA1b) device_pairing (fa12)');
select is((select count(*) from pin_sessions where id = '00000000-0000-0000-0000-00000000c5a1')::int, 1, 'branch cashier @ BA1: sees its own branch pin_session (c5a1)');
select is((select count(*) from pin_sessions where id = '00000000-0000-0000-0000-00000000c5a3')::int, 0, 'branch cashier @ BA1: does NOT see the sibling branch (BA1b) pin_session (c5a3)');

-- cross-org / cross-scope WRITES denied by RLS WITH CHECK (42501) ------------ 26-31
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee03';   -- cashier @ RA1
select throws_ok($$ insert into devices (organization_id,restaurant_id,branch_id,device_type) values ('00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1b1','pos') $$, '42501', NULL, 'cashier @ RA1: CANNOT insert a device into Org B');
select throws_ok($$ insert into devices (organization_id,restaurant_id,branch_id,device_type) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-00000000a2b1','pos') $$, '42501', NULL, 'cashier @ RA1: CANNOT insert a device into Restaurant A2');
select throws_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-00000000a2b1','00000000-0000-0000-0000-00000000da21') $$, '42501', NULL, 'cashier @ RA1: CANNOT insert a device_pairing in Restaurant A2');
select throws_ok($$ insert into device_sessions (organization_id,restaurant_id,branch_id,device_id,device_pairing_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-00000000a2b1','00000000-0000-0000-0000-00000000da21','00000000-0000-0000-0000-00000000fa21') $$, '42501', NULL, 'cashier @ RA1: CANNOT create a device_session in Restaurant A2');
select throws_ok($$ insert into pin_sessions (organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-00000000a2b1','00000000-0000-0000-0000-0000000005a3','00000000-0000-0000-0000-0000000ef0a2','00000000-0000-0000-0000-00000000ce01') $$, '42501', NULL, 'cashier @ RA1: CANNOT create a pin_session in Restaurant A2 (RLS WITH CHECK, backing is valid)');
select lives_ok($$ insert into devices (organization_id,restaurant_id,branch_id,device_type) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','pos') $$, 'cashier @ RA1: MAY insert a device in its own restaurant/branch (RA1/BA1)');

select * from finish();
rollback;
