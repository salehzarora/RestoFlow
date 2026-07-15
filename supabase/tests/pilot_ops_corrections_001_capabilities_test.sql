-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 — pgTAP: the two DEFAULT-ON operational
-- capabilities (manage_menu_availability + manage_table_operations)
-- ============================================================================
-- Exercises (lazy-plan coverage + security): app.cashier_capability_allowed for
-- the two new keys; app.pin_session_capabilities returns all six effective
-- booleans; app.set_staff_capabilities (8-arg) denies + re-enables (deny-only
-- storage); app.list_staff reports the two booleans; app.create_staff_member
-- accepts a deny-only override and rejects a bogus grant; the audit projection
-- carries the two keys; ACLs on the 8-arg function.
-- Fixtures inserted as the BYPASSRLS test role; hex-only UUIDs (prefix 9c).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

insert into organizations (id, name, slug, default_currency) values
  ('9c000000-0000-0000-0000-0000000000a0', 'Org C', 'pilotcaps-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('9c000000-0000-0000-0000-00000000a1b1', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', 'Branch B1');
insert into app_users (id, email) values
  ('9c000000-0000-0000-0000-00000000ee01', 'pilotcaps-owner@example.test'),
  ('9c000000-0000-0000-0000-00000000ee03', 'pilotcaps-cashier@example.test'),
  ('9c000000-0000-0000-0000-00000000ee04', 'pilotcaps-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('9c000000-0000-0000-0000-00000000ab01', '9c000000-0000-0000-0000-00000000ee01', '9c000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('9c000000-0000-0000-0000-00000000ab03', '9c000000-0000-0000-0000-00000000ee03', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('9c000000-0000-0000-0000-00000000ab04', '9c000000-0000-0000-0000-00000000ee04', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', 'manager');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('9c000000-0000-0000-0000-00000000da11', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('9c000000-0000-0000-0000-00000000fa11', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', '9c000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('9c000000-0000-0000-0000-0000000005a1', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', '9c000000-0000-0000-0000-00000000da11', '9c000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('9c000000-0000-0000-0000-0000000ef003', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', '9c000000-0000-0000-0000-00000000ee03', '9c000000-0000-0000-0000-00000000ab03');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9c000000-0000-0000-0000-00000000c503', '9c000000-0000-0000-0000-0000000000a0', '9c000000-0000-0000-0000-0000000000a1', '9c000000-0000-0000-0000-00000000a1b1', '9c000000-0000-0000-0000-0000000005a1', '9c000000-0000-0000-0000-0000000ef003', '9c000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- ===== (1-4) pin_session_capabilities: cashier default-ON for the two new caps =
create temp table t_caps as select app.pin_session_capabilities(
  '9c000000-0000-0000-0000-00000000c503', '9c000000-0000-0000-0000-00000000da11') as res;
select is((select (res->'capabilities'->>'manage_menu_availability')::boolean from t_caps), true,
  'cashier holds manage_menu_availability by default (deny-only default ON)');
select is((select (res->'capabilities'->>'manage_table_operations')::boolean from t_caps), true,
  'cashier holds manage_table_operations by default');
select is((select (res->'capabilities' ? 'apply_discount') from t_caps), true,
  'the prior apply_discount capability key is still present (no regression)');
select is((select (res->'capabilities' ? 'apply_full_comp') from t_caps), true,
  'the prior apply_full_comp capability key is still present');

-- ===== (5-8) owner DENIES manage_menu_availability; deny-only storage ==========
set local role authenticated;
set local app.current_app_user_id = '9c000000-0000-0000-0000-00000000ee01';
create temp table t_deny as select app.set_staff_capabilities(
  '9c000000-0000-0000-0000-00000000cc01'::uuid, '9c000000-0000-0000-0000-0000000ef003'::uuid,
  true, true, true, false, false, true) as res;   -- deny menu-availability only
reset role;
select is((select (res->>'ok')::boolean from t_deny), true, 'owner set_staff_capabilities (8-arg) succeeds');
select is(
  (select permissions->>'manage_menu_availability' from memberships where id = '9c000000-0000-0000-0000-00000000ab03'),
  'false', 'a DENY stores the canonical JSON string "false" (deny-only storage)');
select is(
  (select permissions ? 'manage_table_operations' from memberships where id = '9c000000-0000-0000-0000-00000000ab03'),
  false, 'an ENABLED default-ON capability stores NO key (role default)');
select is(
  (select (app.pin_session_capabilities('9c000000-0000-0000-0000-00000000c503','9c000000-0000-0000-0000-00000000da11')
             ->'capabilities'->>'manage_menu_availability')::boolean),
  false, 'after the deny, the POS capability projection reports manage_menu_availability=false');

-- ===== (9-10) re-enable removes the key (back to role default) =================
set local role authenticated;
set local app.current_app_user_id = '9c000000-0000-0000-0000-00000000ee01';
create temp table t_reenable as select app.set_staff_capabilities(
  '9c000000-0000-0000-0000-00000000cc02'::uuid, '9c000000-0000-0000-0000-0000000ef003'::uuid,
  true, true, true, false, true, true) as res;
reset role;
select is(
  (select permissions ? 'manage_menu_availability' from memberships where id = '9c000000-0000-0000-0000-00000000ab03'),
  false, 'ENABLING removes the deny key (back to the default-ON role default)');
select is(
  (select app.cashier_capability_allowed('cashier', permissions, 'manage_menu_availability') from memberships where id = '9c000000-0000-0000-0000-00000000ab03'),
  true, 'the resolver again reports the capability ALLOWED after re-enable');

-- ===== (11-12) list_staff reports the two effective booleans ==================
set local role authenticated;
set local app.current_app_user_id = '9c000000-0000-0000-0000-00000000ee01';
create temp table t_list as select app.list_staff('9c000000-0000-0000-0000-0000000000a0'::uuid) as res;
reset role;
select is(
  (select s->'capabilities'->>'manage_menu_availability' from t_list, jsonb_array_elements(res->'staff') s
    where s->>'employee_profile_id' = '9c000000-0000-0000-0000-0000000ef003'),
  'true', 'list_staff reports manage_menu_availability for the cashier row');
select is(
  (select s->'capabilities'->>'manage_table_operations' from t_list, jsonb_array_elements(res->'staff') s
    where s->>'employee_profile_id' = '9c000000-0000-0000-0000-0000000ef003'),
  'true', 'list_staff reports manage_table_operations for the cashier row');

-- ===== (13-14) create_staff_member: deny-only key accepted; bogus grant rejected
set local role authenticated;
set local app.current_app_user_id = '9c000000-0000-0000-0000-00000000ee01';
create temp table t_new as select app.create_staff_member(
  '9c000000-0000-0000-0000-00000000cf01'::uuid, '9c000000-0000-0000-0000-0000000000a0'::uuid,
  '9c000000-0000-0000-0000-0000000000a1'::uuid, '9c000000-0000-0000-0000-00000000a1b1'::uuid,
  'Deny Cashier', 'cashier', '{"manage_table_operations":"false"}'::jsonb) as res;
reset role;
select is((select (res->>'ok')::boolean from t_new), true,
  'create_staff_member accepts an initial DENY of a default-ON operational capability');
set local role authenticated;
set local app.current_app_user_id = '9c000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$select app.create_staff_member('9c000000-0000-0000-0000-00000000cf02'::uuid, '9c000000-0000-0000-0000-0000000000a0'::uuid, '9c000000-0000-0000-0000-0000000000a1'::uuid, '9c000000-0000-0000-0000-00000000a1b1'::uuid, 'Bad', 'cashier', '{"manage_menu_availability":"true"}'::jsonb)$$,
  '42501', NULL,
  'create_staff_member REJECTS a "true" grant of a deny-only operational capability (fail-closed)');
reset role;

-- ===== (15) the capabilities_updated audit projects the two new keys ==========
select is(
  (select (app.audit_safe_detail('staff.capabilities_updated', new_values) -> 'capabilities' ? 'manage_menu_availability')
     from audit_events
    where organization_id = '9c000000-0000-0000-0000-0000000000a0' and action = 'staff.capabilities_updated'
    order by created_at limit 1),
  true, 'the staff.capabilities_updated audit projection carries manage_menu_availability');

-- ===== (16-18) ACLs on the 8-arg set_staff_capabilities =======================
select is(
  (select has_function_privilege('authenticated', 'app.set_staff_capabilities(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean)', 'execute')),
  true, 'authenticated may execute the 8-arg app.set_staff_capabilities');
select is(
  (select has_function_privilege('anon', 'public.set_staff_capabilities(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean)', 'execute')),
  false, 'anon may NOT execute the 8-arg public.set_staff_capabilities');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'set_staff_capabilities'),
  1, 'exactly ONE app.set_staff_capabilities overload exists (no ambiguous 6-arg left behind)');

select * from finish();
rollback;
