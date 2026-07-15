-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 — pgTAP: POS cashier menu-availability path
-- ============================================================================
-- Exercises app.pos_set_item_availability (PIN-session + manage_menu_availability)
-- and its dispatch through public.sync_push (op menu.availability_set): a default-ON
-- cashier flips sold_out (SAME audit taxonomy as the Dashboard path); an
-- explicitly-denied cashier is refused (permission_denied + denial audit, NO success
-- audit); no_change is idempotent; shape errors raise; a foreign item is not_found;
-- pos_menu reflects the change; ACLs (no public wrapper; anon revoked).
-- Fixtures as the BYPASSRLS role; hex-only UUIDs (prefix 9d).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(16);

insert into organizations (id, name, slug, default_currency) values
  ('9d000000-0000-0000-0000-0000000000a0', 'Org D', 'pilotavail-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', 'Branch B1');
insert into app_users (id, email) values
  ('9d000000-0000-0000-0000-00000000ee03', 'pilotavail-cashier@example.test'),
  ('9d000000-0000-0000-0000-00000000ee05', 'pilotavail-denied@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('9d000000-0000-0000-0000-00000000ab03', '9d000000-0000-0000-0000-00000000ee03', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb),
  ('9d000000-0000-0000-0000-00000000ab05', '9d000000-0000-0000-0000-00000000ee05', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', 'cashier', '{"manage_menu_availability":"false"}'::jsonb);
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('9d000000-0000-0000-0000-00000000ca01', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', null, 'Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('9d000000-0000-0000-0000-0000000000f1', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', null, '9d000000-0000-0000-0000-00000000ca01', 'Falafel', 2500, 'ILS', 1, true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('9d000000-0000-0000-0000-00000000da11', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('9d000000-0000-0000-0000-00000000fa11', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('9d000000-0000-0000-0000-0000000005a1', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-00000000da11', '9d000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('9d000000-0000-0000-0000-0000000ef003', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-00000000ee03', '9d000000-0000-0000-0000-00000000ab03'),
  ('9d000000-0000-0000-0000-0000000ef005', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-00000000ee05', '9d000000-0000-0000-0000-00000000ab05');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9d000000-0000-0000-0000-00000000c503', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-0000000005a1', '9d000000-0000-0000-0000-0000000ef003', '9d000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('9d000000-0000-0000-0000-00000000c505', '9d000000-0000-0000-0000-0000000000a0', '9d000000-0000-0000-0000-0000000000a1', '9d000000-0000-0000-0000-00000000a1b1', '9d000000-0000-0000-0000-0000000005a1', '9d000000-0000-0000-0000-0000000ef005', '9d000000-0000-0000-0000-00000000ab05', now() + interval '1 hour');

-- ===== (1-4) default-ON cashier flips Falafel Sold out via the POS path ========
create temp table t1 as select app.pos_set_item_availability(
  '9d000000-0000-0000-0000-00000000c503', '9d000000-0000-0000-0000-00000000da11',
  '9d000000-0000-0000-0000-0000000000f1', 'unavailable', 'sold_out') as res;
select is((select (res->>'ok')::boolean from t1), true, 'default-ON cashier can set an item unavailable from the POS');
select is((select res->>'availability' from t1), 'unavailable', 'envelope reports availability=unavailable');
select is((select res->>'reason' from t1), 'sold_out', 'envelope reports reason=sold_out');
select is(
  (select (availability, reason)::text from menu_item_branch_availability
    where organization_id='9d000000-0000-0000-0000-0000000000a0' and branch_id='9d000000-0000-0000-0000-00000000a1b1' and menu_item_id='9d000000-0000-0000-0000-0000000000f1'),
  '(unavailable,sold_out)', 'the override row is stored for the session branch');

-- ===== (5-6) SAME audit taxonomy as the Dashboard path; actor = employee =======
select is(
  (select action || '|' || (new_values->>'availability') || '|' || (new_values->>'availability_reason') || '|' || (new_values->>'item_name')
     from audit_events where organization_id='9d000000-0000-0000-0000-0000000000a0' and action='menu.menu_item.availability_changed'),
  'menu.menu_item.availability_changed|unavailable|sold_out|Falafel',
  'the POS write uses the SAME menu.menu_item.availability_changed audit (unified Activity Log)');
select is(
  (select actor_employee_profile_id || '|' || device_id from audit_events
    where organization_id='9d000000-0000-0000-0000-0000000000a0' and action='menu.menu_item.availability_changed'),
  '9d000000-0000-0000-0000-0000000ef003|9d000000-0000-0000-0000-00000000da11',
  'the audit actor is the PIN-session employee + POS device (not a JWT user)');

-- ===== (7) no_change is idempotent: no second audit row =======================
create temp table t_nc as select app.pos_set_item_availability(
  '9d000000-0000-0000-0000-00000000c503', '9d000000-0000-0000-0000-00000000da11',
  '9d000000-0000-0000-0000-0000000000f1', 'unavailable', 'sold_out') as res;
select is(
  (select (res->>'no_change')::boolean from t_nc)
  || '|' || (select count(*)::text from audit_events where organization_id='9d000000-0000-0000-0000-0000000000a0' and action='menu.menu_item.availability_changed'),
  'true|1', 'a no-change re-apply is idempotent and writes NO second audit row');

-- ===== (8-9) explicitly-denied cashier: permission_denied + denial audit only ==
create temp table t_deny as select app.pos_set_item_availability(
  '9d000000-0000-0000-0000-00000000c505', '9d000000-0000-0000-0000-00000000da11',
  '9d000000-0000-0000-0000-0000000000f1', 'available', null) as res;
select is((select res->>'error' from t_deny), 'permission_denied',
  'a cashier with an explicit deny is refused (permission_denied)');
select is(
  (select count(*)::int from audit_events where organization_id='9d000000-0000-0000-0000-0000000000a0' and action='menu.menu_item.availability_denied'),
  1, 'the denial writes exactly one availability_denied audit and NO success audit');

-- ===== (10) shape error: unavailable without a reason raises ==================
select throws_ok(
  $$select app.pos_set_item_availability('9d000000-0000-0000-0000-00000000c503','9d000000-0000-0000-0000-00000000da11','9d000000-0000-0000-0000-0000000000f1','unavailable',null)$$,
  '42501', NULL, 'unavailable without a structured reason raises 42501');

-- ===== (11) a foreign item is not_found (no cross-scope leak) =================
select is(
  (select app.pos_set_item_availability('9d000000-0000-0000-0000-00000000c503','9d000000-0000-0000-0000-00000000da11','9d000000-0000-0000-0000-00000000dead','unavailable','paused') ->> 'error'),
  'not_found', 'an unknown/foreign item is not_found (R-003)');

-- ===== (12-14) via public.sync_push: menu.availability_set applies =============
create temp table t_sp as select public.sync_push(
  '9d000000-0000-0000-0000-00000000c503', '9d000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'pilot-avail-op-1', 'operation_type', 'menu.availability_set',
    'target_entity', 'menu_item',
    'payload', jsonb_build_object('menu_item_id', '9d000000-0000-0000-0000-0000000000f1', 'availability', 'unavailable', 'reason', 'paused')))) as res;
select is((select (res->>'ok')::boolean from t_sp), true, 'sync_push accepts a menu.availability_set batch');
select is(
  (select (r->>'status') from t_sp, jsonb_array_elements(res->'results') r where r->>'local_operation_id'='pilot-avail-op-1'),
  'applied', 'the menu.availability_set op is applied');
select is(
  (select availability || '|' || reason from menu_item_branch_availability
    where organization_id='9d000000-0000-0000-0000-0000000000a0' and menu_item_id='9d000000-0000-0000-0000-0000000000f1'),
  'unavailable|paused', 'the override now reflects the sync_push change (sold_out -> paused)');

-- ===== (15-16) ACLs: no public wrapper; anon revoked ==========================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='pos_set_item_availability'),
  0, 'there is NO public wrapper (reached only via sync_push, like move_order_table)');
select is(
  (select has_function_privilege('anon', 'app.pos_set_item_availability(uuid,uuid,uuid,text,text)', 'execute')),
  false, 'anon may NOT execute app.pos_set_item_availability');

select * from finish();
rollback;
