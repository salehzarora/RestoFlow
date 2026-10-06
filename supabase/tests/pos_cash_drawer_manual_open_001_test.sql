-- ============================================================================
-- POS-CASH-DRAWER-MANUAL-OPEN-001 — pgTAP: the audited, permissioned manual
-- ("no-sale") cash-drawer open.
-- ============================================================================
-- Exercises: the grant-only open_cash_drawer capability (resolver, POS projection,
-- 9-arg set_staff_capabilities with NULL = unchanged, list_staff, create_staff_member,
-- audit projection); app/public.pos_verify_drawer_pin (permission before PIN work,
-- wrong PIN audit + shared lockout, success resets + returns the session expiry,
-- invalid session / device type / device mismatch); the cash_drawer.no_sale_open
-- sync op (applied + audited with actor/device/shift, replay is idempotent,
-- denied for an ungranted cashier / kitchen staff, revoked-device path ledgered);
-- CHECK constraint, ACLs and the global public surface. Fixtures as BYPASSRLS;
-- hex UUIDs (prefix d7).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(56);

insert into organizations (id, name, slug, default_currency) values
  ('d7000000-0000-0000-0000-0000000000a0', 'Org Drawer', 'drawer-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('d7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('d7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'Branch B1');
insert into app_users (id, email) values
  ('d7000000-0000-0000-0000-00000000ee01', 'drawer-owner@example.test'),
  ('d7000000-0000-0000-0000-00000000ee03', 'drawer-cashier-a@example.test'),
  ('d7000000-0000-0000-0000-00000000ee04', 'drawer-manager@example.test'),
  ('d7000000-0000-0000-0000-00000000ee05', 'drawer-cashier-b@example.test'),
  ('d7000000-0000-0000-0000-00000000ee06', 'drawer-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('d7000000-0000-0000-0000-00000000ab01', 'd7000000-0000-0000-0000-00000000ee01', 'd7000000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb),
  ('d7000000-0000-0000-0000-00000000ab03', 'd7000000-0000-0000-0000-00000000ee03', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb),
  ('d7000000-0000-0000-0000-00000000ab04', 'd7000000-0000-0000-0000-00000000ee04', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'manager', '{}'::jsonb),
  ('d7000000-0000-0000-0000-00000000ab05', 'd7000000-0000-0000-0000-00000000ee05', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb),
  ('d7000000-0000-0000-0000-00000000ab06', 'd7000000-0000-0000-0000-00000000ee06', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'kitchen_staff', '{}'::jsonb);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('d7000000-0000-0000-0000-00000000da11', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('d7000000-0000-0000-0000-00000000da22', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('d7000000-0000-0000-0000-00000000fa11', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000da11', 'active'),
  ('d7000000-0000-0000-0000-00000000fa22', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('d7000000-0000-0000-0000-0000000005a1', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000da11', 'd7000000-0000-0000-0000-00000000fa11'),
  ('d7000000-0000-0000-0000-0000000005a2', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000da22', 'd7000000-0000-0000-0000-00000000fa22');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('d7000000-0000-0000-0000-0000000ef003', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000ee03', 'd7000000-0000-0000-0000-00000000ab03', extensions.crypt('1234', extensions.gen_salt('bf'))),
  ('d7000000-0000-0000-0000-0000000ef004', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000ee04', 'd7000000-0000-0000-0000-00000000ab04', extensions.crypt('4321', extensions.gen_salt('bf'))),
  ('d7000000-0000-0000-0000-0000000ef005', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000ee05', 'd7000000-0000-0000-0000-00000000ab05', extensions.crypt('5555', extensions.gen_salt('bf'))),
  ('d7000000-0000-0000-0000-0000000ef006', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000ee06', 'd7000000-0000-0000-0000-00000000ab06', extensions.crypt('6666', extensions.gen_salt('bf')));
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-0000000005a1', 'd7000000-0000-0000-0000-0000000ef003', 'd7000000-0000-0000-0000-00000000ab03', now() + interval '6 hours'),
  ('d7000000-0000-0000-0000-00000000c504', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-0000000005a1', 'd7000000-0000-0000-0000-0000000ef004', 'd7000000-0000-0000-0000-00000000ab04', now() + interval '6 hours'),
  ('d7000000-0000-0000-0000-00000000c505', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-0000000005a1', 'd7000000-0000-0000-0000-0000000ef005', 'd7000000-0000-0000-0000-00000000ab05', now() + interval '6 hours'),
  ('d7000000-0000-0000-0000-00000000c506', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-0000000005a1', 'd7000000-0000-0000-0000-0000000ef006', 'd7000000-0000-0000-0000-00000000ab06', now() + interval '6 hours'),
  ('d7000000-0000-0000-0000-00000000c524', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-0000000005a2', 'd7000000-0000-0000-0000-0000000ef004', 'd7000000-0000-0000-0000-00000000ab04', now() + interval '6 hours');

-- ===== (1-4) the grant-only resolver ==========================================
select is(app.cashier_capability_granted('cashier', '{}'::jsonb, 'open_cash_drawer'), false,
  'a cashier with no override does NOT hold open_cash_drawer (default OFF)');
select is(app.cashier_capability_granted('cashier', '{"open_cash_drawer":"true"}'::jsonb, 'open_cash_drawer'), true,
  'the canonical string "true" grants open_cash_drawer to a cashier');
select is(app.cashier_capability_granted('cashier', '{"open_cash_drawer":true}'::jsonb, 'open_cash_drawer'), false,
  'a JSON boolean true is malformed and DENIES (no coercion)');
select is(app.cashier_capability_granted('kitchen_staff', '{"open_cash_drawer":"true"}'::jsonb, 'open_cash_drawer'), false,
  'the resolver never grants a non-cashier role');

-- ===== (5-7) POS advisory projection ==========================================
select is((app.pin_session_capabilities('d7000000-0000-0000-0000-00000000c505', 'd7000000-0000-0000-0000-00000000da11') -> 'capabilities' ->> 'open_cash_drawer')::boolean,
  false, 'an ungranted cashier sees open_cash_drawer=false');
select is((app.pin_session_capabilities('d7000000-0000-0000-0000-00000000c504', 'd7000000-0000-0000-0000-00000000da11') -> 'capabilities' ->> 'open_cash_drawer')::boolean,
  true, 'a manager holds open_cash_drawer by role');
select is((app.pin_session_capabilities('d7000000-0000-0000-0000-00000000c506', 'd7000000-0000-0000-0000-00000000da11') -> 'capabilities' ->> 'open_cash_drawer')::boolean,
  false, 'kitchen staff never hold open_cash_drawer');

-- ===== (8-14) the owner grants cashier A through the 9-arg setter ==============
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
create temp table t_grant as select app.set_staff_capabilities(
  'd7000000-0000-0000-0000-00000000cc01'::uuid, 'd7000000-0000-0000-0000-0000000ef003'::uuid,
  true, true, true, false, true, true, true) as res;
reset role;
select is((select (res->>'ok')::boolean from t_grant), true, 'owner set_staff_capabilities (9-arg) succeeds');
select is((select permissions->>'open_cash_drawer' from memberships where id = 'd7000000-0000-0000-0000-00000000ab03'),
  'true', 'a grant stores the canonical JSON string "true" (grant-only storage)');
select is((select (res->'capabilities'->>'open_cash_drawer')::boolean from t_grant), true,
  'the result envelope reports the effective grant');
select is((select (app.audit_safe_detail('staff.capabilities_updated', new_values) -> 'capabilities' ->> 'open_cash_drawer')::boolean
             from audit_events
            where organization_id = 'd7000000-0000-0000-0000-0000000000a0' and action = 'staff.capabilities_updated'
            order by created_at desc limit 1),
  true, 'the staff.capabilities_updated Activity Log projection carries open_cash_drawer');

-- an OLDER client (8 positional args; p_open_cash_drawer omitted = NULL) leaves it untouched
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
create temp table t_legacy as select app.set_staff_capabilities(
  'd7000000-0000-0000-0000-00000000cc02'::uuid, 'd7000000-0000-0000-0000-0000000ef003'::uuid,
  false, true, true, false, true, true) as res;
reset role;
select is((select (res->>'ok')::boolean from t_legacy), true, 'an 8-arg (pre-drawer) save still succeeds');
select is((select permissions->>'open_cash_drawer' from memberships where id = 'd7000000-0000-0000-0000-00000000ab03'),
  'true', 'an 8-arg save (p_open_cash_drawer NULL) NEVER revokes an existing drawer grant');
select is((select permissions->>'apply_discount' from memberships where id = 'd7000000-0000-0000-0000-00000000ab03'),
  'false', 'the 8-arg save still applied its own toggles');

-- ===== (15-16) list_staff reports the effective value per row =================
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
create temp table t_list as select app.list_staff('d7000000-0000-0000-0000-0000000000a0', null, null) as res;
reset role;
select is((select s->'capabilities'->>'open_cash_drawer' from t_list, jsonb_array_elements(res->'staff') s
            where s->>'employee_profile_id' = 'd7000000-0000-0000-0000-0000000ef003'),
  'true', 'list_staff reports open_cash_drawer=true for the granted cashier');
select is((select s->'capabilities'->>'open_cash_drawer' from t_list, jsonb_array_elements(res->'staff') s
            where s->>'employee_profile_id' = 'd7000000-0000-0000-0000-0000000ef005'),
  'false', 'list_staff reports open_cash_drawer=false for an ungranted cashier');

-- ===== (17-18) revoke, then re-grant ===========================================
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
select app.set_staff_capabilities('d7000000-0000-0000-0000-00000000cc03'::uuid, 'd7000000-0000-0000-0000-0000000ef003'::uuid,
  true, true, true, false, true, true, false);
reset role;
select is((select permissions ? 'open_cash_drawer' from memberships where id = 'd7000000-0000-0000-0000-00000000ab03'),
  false, 'revoking REMOVES the key (absence denies)');
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
select app.set_staff_capabilities('d7000000-0000-0000-0000-00000000cc04'::uuid, 'd7000000-0000-0000-0000-0000000ef003'::uuid,
  true, true, true, false, true, true, true);
reset role;
select is((select permissions->>'open_cash_drawer' from memberships where id = 'd7000000-0000-0000-0000-00000000ab03'),
  'true', 're-granting restores the canonical "true"');

-- ===== (19-20) create_staff_member: grant accepted; a "false" rejected ========
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
create temp table t_new as select app.create_staff_member(
  'd7000000-0000-0000-0000-00000000cf01'::uuid, 'd7000000-0000-0000-0000-0000000000a0'::uuid,
  'd7000000-0000-0000-0000-0000000000a1'::uuid, 'd7000000-0000-0000-0000-00000000a1b1'::uuid,
  'Drawer Cashier', 'cashier', '{"open_cash_drawer":"true"}'::jsonb) as res;
reset role;
select is((select (res->>'ok')::boolean from t_new), true,
  'create_staff_member accepts an initial GRANT of open_cash_drawer');
set local role authenticated;
set local app.current_app_user_id = 'd7000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$select app.create_staff_member('d7000000-0000-0000-0000-00000000cf02'::uuid, 'd7000000-0000-0000-0000-0000000000a0'::uuid, 'd7000000-0000-0000-0000-0000000000a1'::uuid, 'd7000000-0000-0000-0000-00000000a1b1'::uuid, 'Bad', 'cashier', '{"open_cash_drawer":"false"}'::jsonb)$$,
  '42501', NULL,
  'create_staff_member REJECTS a "false" for the grant-only drawer key (fail-closed)');
reset role;

-- ===== (21-23) verify: permission is checked BEFORE any PIN work ===============
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c505', 'd7000000-0000-0000-0000-00000000da11', '5555') ->> 'error'),
  'permission_denied', 'an ungranted cashier cannot unlock the drawer even with the right PIN');
select is((select count(*)::int from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.no_sale_denied' and actor_employee_profile_id = 'd7000000-0000-0000-0000-0000000ef005'
             and new_values->>'stage' = 'unlock'),
  1, 'the refused unlock is audited as cash_drawer.no_sale_denied (stage unlock)');
select is((select count(*)::int from pin_attempt_states where employee_profile_id = 'd7000000-0000-0000-0000-0000000ef005'),
  0, 'a refused (unpermitted) unlock does no PIN work at all');

-- ===== (24-27) verify: a wrong PIN ============================================
create temp table t_wrong as select app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11', '9999') as res;
select is((select res->>'error' from t_wrong), 'invalid_pin', 'a wrong PIN is refused (invalid_pin)');
select is((select failed_attempt_count from pin_attempt_states where employee_profile_id = 'd7000000-0000-0000-0000-0000000ef003'
             and device_id = 'd7000000-0000-0000-0000-00000000da11'),
  1, 'a wrong drawer PIN counts in the SAME sign-in attempt ledger');
select is((select (new_values->>'failed_attempt_count')::int from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.unlock_failed' order by created_at desc limit 1),
  1, 'a wrong PIN is audited as cash_drawer.unlock_failed with the attempt count');
select is((select count(*)::int from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and (coalesce(new_values::text, '') like '%9999%' or coalesce(reason, '') like '%9999%')),
  0, 'the typed PIN is never recorded anywhere in the audit');

-- ===== (28-30) verify: the right PIN ==========================================
create temp table t_ok as select app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11', '1234') as res;
select is((select (res->>'ok')::boolean from t_ok), true, 'the granted cashier unlocks with their OWN PIN');
select is((select (res->>'session_expires_at')::timestamptz from t_ok),
  (select expires_at from pin_sessions where id = 'd7000000-0000-0000-0000-00000000c503'),
  'success returns the server PIN-session expiry (the offline-open bound)');
select is((select failed_attempt_count from pin_attempt_states where employee_profile_id = 'd7000000-0000-0000-0000-0000000ef003'
             and device_id = 'd7000000-0000-0000-0000-00000000da11'),
  0, 'success resets the shared attempt counter like a sign-in');

-- ===== (31-32) verify: lockout after 5 wrong PINs; locked refuses the right PIN =
select app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11', '0000') from generate_series(1, 4);
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11', '0000') ->> 'error'),
  'pin_locked', 'the 5th wrong PIN locks (shared 5-attempt cap)');
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11', '1234') ->> 'error'),
  'pin_locked', 'while locked even the right PIN is refused (no oracle)');
update pin_attempt_states set failed_attempt_count = 0, locked_until = null
  where employee_profile_id = 'd7000000-0000-0000-0000-0000000ef003';

-- ===== (33-37) verify: manager, kitchen, invalid session, KDS device, mismatch ==
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c504', 'd7000000-0000-0000-0000-00000000da11', '4321') ->> 'ok')::boolean,
  true, 'a manager unlocks by role with their own PIN');
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c506', 'd7000000-0000-0000-0000-00000000da11', '6666') ->> 'error'),
  'permission_denied', 'kitchen staff can never unlock the drawer');
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-0000000fffff', 'd7000000-0000-0000-0000-00000000da11', '1234') ->> 'error'),
  'invalid_session', 'an unknown PIN session collapses to invalid_session');
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c524', 'd7000000-0000-0000-0000-00000000da22', '4321') ->> 'error'),
  'invalid_device_type', 'only a POS till can unlock a drawer (a KDS session is refused)');
select is((app.pos_verify_drawer_pin('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da22', '1234') ->> 'error'),
  'invalid_session', 'a device that is not the PIN session''s device collapses to invalid_session');

-- ===== (38-43) the no-sale op through sync_push (no open shift yet) ============
create temp table t_ns1 as select public.sync_push('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'drawer-ns-1', 'operation_type', 'cash_drawer.no_sale_open',
    'target_entity', 'cash_drawer', 'payload', jsonb_build_object('client_occurred_at', '2026-10-06T10:00:00Z')))) as res;
select is((select r->>'status' from t_ns1, jsonb_array_elements(res->'results') r where r->>'local_operation_id' = 'drawer-ns-1'),
  'applied', 'sync_push applies cash_drawer.no_sale_open for a granted cashier');
select is((select count(*)::int from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.no_sale_opened' and actor_employee_profile_id = 'd7000000-0000-0000-0000-0000000ef003'
             and device_id = 'd7000000-0000-0000-0000-00000000da11' and branch_id = 'd7000000-0000-0000-0000-00000000a1b1'),
  1, 'the open is audited with the actor, the device and the branch');
select is((select (new_values->>'client_occurred_at')::timestamptz from audit_events
            where organization_id = 'd7000000-0000-0000-0000-0000000000a0' and action = 'cash_drawer.no_sale_opened'),
  '2026-10-06T10:00:00Z'::timestamptz, 'the client occurrence time rides in new_values (occurred_at stays server time)');
select is((select new_values->>'shift_id' from audit_events
            where organization_id = 'd7000000-0000-0000-0000-0000000000a0' and action = 'cash_drawer.no_sale_opened'),
  null, 'with no open shift the event binds no shift');

-- replay: the SAME local_operation_id returns the stored result; still ONE audit row
create temp table t_ns1b as select public.sync_push('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'drawer-ns-1', 'operation_type', 'cash_drawer.no_sale_open',
    'target_entity', 'cash_drawer', 'payload', jsonb_build_object('client_occurred_at', '2026-10-06T10:00:00Z')))) as res;
select is((select (r->>'idempotency_replay')::boolean from t_ns1b, jsonb_array_elements(res->'results') r where r->>'local_operation_id' = 'drawer-ns-1'),
  true, 'a replayed no-sale returns the stored result (D-022)');
select is((select count(*)::int from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.no_sale_opened'),
  1, 'a replay never writes a second audit row');

-- ===== (44-45) with an open shift + active drawer the event binds both =========
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id, resolved_membership_id, local_operation_id, status) values
  ('d7000000-0000-0000-0000-000000005f01', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000da11', 'd7000000-0000-0000-0000-0000000ef003', 'd7000000-0000-0000-0000-00000000ab03', 'drawer-shift-open', 'open');
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id, opened_by_employee_profile_id, opening_float_minor, local_operation_id) values
  ('d7000000-0000-0000-0000-000000006d01', 'd7000000-0000-0000-0000-0000000000a0', 'd7000000-0000-0000-0000-0000000000a1', 'd7000000-0000-0000-0000-00000000a1b1', 'd7000000-0000-0000-0000-00000000da11', 'd7000000-0000-0000-0000-000000005f01', 'd7000000-0000-0000-0000-0000000ef003', 0, 'drawer-drawer-open');
create temp table t_ns2 as select public.sync_push('d7000000-0000-0000-0000-00000000c504', 'd7000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'drawer-ns-2', 'operation_type', 'cash_drawer.no_sale_open',
    'target_entity', 'cash_drawer', 'payload', jsonb_build_object('client_occurred_at', '2026-10-06T11:00:00Z')))) as res;
select is((select new_values->>'shift_id' from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.no_sale_opened' and actor_employee_profile_id = 'd7000000-0000-0000-0000-0000000ef004'),
  'd7000000-0000-0000-0000-000000005f01', 'a manager''s open binds the till''s open shift');
select is((select new_values->>'cash_drawer_session_id' from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.no_sale_opened' and actor_employee_profile_id = 'd7000000-0000-0000-0000-0000000ef004'),
  'd7000000-0000-0000-0000-000000006d01', '...and its active drawer session');
select is((select count(*)::int from cash_drawer_sessions where id = 'd7000000-0000-0000-0000-000000006d01' and status = 'active' and revision = 1),
  1, 'a no-sale is audit-only: the drawer session state is untouched');

-- ===== (47-50) refusals through sync_push =====================================
create temp table t_ns3 as select public.sync_push('d7000000-0000-0000-0000-00000000c505', 'd7000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'drawer-ns-3', 'operation_type', 'cash_drawer.no_sale_open',
    'target_entity', 'cash_drawer', 'payload', jsonb_build_object()))) as res;
select is((select r->>'status' || '/' || (r->>'error') from t_ns3, jsonb_array_elements(res->'results') r where r->>'local_operation_id' = 'drawer-ns-3'),
  'rejected/permission_denied', 'an ungranted cashier''s no-sale is rejected permission_denied');
select is((select count(*)::int from audit_events where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and action = 'cash_drawer.no_sale_denied' and actor_employee_profile_id = 'd7000000-0000-0000-0000-0000000ef005'
             and new_values->>'denied_reason' = 'permission_denied' and new_values->>'stage' is null),
  1, 'the refused no-sale is audited cash_drawer.no_sale_denied');
create temp table t_ns4 as select public.sync_push('d7000000-0000-0000-0000-00000000c506', 'd7000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'drawer-ns-4', 'operation_type', 'cash_drawer.no_sale_open',
    'target_entity', 'cash_drawer', 'payload', jsonb_build_object()))) as res;
select is((select r->>'error' from t_ns4, jsonb_array_elements(res->'results') r where r->>'local_operation_id' = 'drawer-ns-4'),
  'permission_denied', 'kitchen staff are refused');

-- revoked device: the op is still ledgered + audited (it is in the revoked-path allowlist)
update device_sessions set revoked_at = now(), is_active = false where id = 'd7000000-0000-0000-0000-0000000005a1';
create temp table t_ns5 as select public.sync_push('d7000000-0000-0000-0000-00000000c503', 'd7000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'drawer-ns-5', 'operation_type', 'cash_drawer.no_sale_open',
    'target_entity', 'cash_drawer', 'payload', jsonb_build_object()))) as res;
select isnt((select r->>'error' from t_ns5, jsonb_array_elements(res->'results') r where r->>'local_operation_id' = 'drawer-ns-5'),
  'unknown_operation_type', 'a revoked till''s no-sale is NOT an unknown op (revoked-path allowlist)');
select is((select count(*)::int from sync_operations where organization_id = 'd7000000-0000-0000-0000-0000000000a0'
             and local_operation_id = 'drawer-ns-5' and status = 'rejected'),
  1, 'a revoked till''s no-sale is ledgered as rejected');

-- ===== (52-56) schema, ACLs, Activity Log classification, global surface =======
select ok((select pg_get_constraintdef(c.oid) like '%cash_drawer.no_sale_open%' from pg_constraint c
            where c.conname = 'sync_operations_operation_type_check'),
  'the sync_operations CHECK admits cash_drawer.no_sale_open');
select ok(has_function_privilege('authenticated', 'public.pos_verify_drawer_pin(uuid,uuid,text)', 'execute')
          and not has_function_privilege('anon', 'public.pos_verify_drawer_pin(uuid,uuid,text)', 'execute')
          and not has_function_privilege('anon', 'app.pos_record_drawer_no_sale(uuid,uuid,timestamptz)', 'execute'),
  'the verify wrapper is authenticated-only and the no-sale body is not anon-callable');
select hasnt_function('public', 'pos_record_drawer_no_sale', 'the no-sale body has NO public wrapper (reached only via sync_push)');
select is(app.audit_category('cash_drawer.no_sale_opened') || '/' || app.audit_safe_detail('cash_drawer.no_sale_denied',
            '{"role":"cashier","denied_reason":"permission_denied","resolved_membership_id":"x"}'::jsonb)::text,
  'shifts/{"role": "cashier", "denied_reason": "permission_denied"}',
  'drawer events land in the Shifts category and project only safe scalars');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname = 'set_staff_capabilities'),
  1, 'exactly ONE app.set_staff_capabilities overload exists');

select * from finish();
rollback;
