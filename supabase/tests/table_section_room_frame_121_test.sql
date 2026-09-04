-- ============================================================================
-- TABLE-ROOM-FRAME-121 — pgTAP: per-section room frame preset
-- (D-001/D-011/D-012/D-013/D-017; RISK R-003)
-- ============================================================================
-- Additive nullable presentation key (table_sections.room_frame_preset) with
-- the structural CHECK PLUS server-side SEMANTIC vocabulary (compact|square|
-- wide|portrait|long_narrow; NULL = Standard). Dedicated setter (target-row-
-- first, manager+, ledger idempotency, no-change without audit, denial audit,
-- cross-org 42501, blank clears); additive read projections on all three
-- wires with exact key pins; kiosk withheld fields unchanged; hardened grant
-- posture (anon denied at BOTH layers); saved coordinates untouched.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(35);

-- ===== fixtures: Org A (one branch), Org B ===================================
insert into organizations (id, name, slug, default_currency) values
  ('64000000-0000-0000-0000-0000000000a0', 'Org A', 'trf-a', 'USD'),
  ('64000000-0000-0000-0000-0000000000b0', 'Org B', 'trf-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('64000000-0000-0000-0000-0000000000b1', '64000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('64000000-0000-0000-0000-00000000b1b1', '64000000-0000-0000-0000-0000000000b0', '64000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('64000000-0000-0000-0000-00000000ee01', 'trf-owner-a@example.test'),
  ('64000000-0000-0000-0000-00000000ee02', 'trf-cashier@example.test'),
  ('64000000-0000-0000-0000-00000000ee0b', 'trf-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('64000000-0000-0000-0000-00000000ab01', '64000000-0000-0000-0000-00000000ee01', '64000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('64000000-0000-0000-0000-00000000ab02', '64000000-0000-0000-0000-00000000ee02', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('64000000-0000-0000-0000-00000000ab0b', '64000000-0000-0000-0000-00000000ee0b', '64000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('64000000-0000-0000-0000-00000000da11', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', 'pos',   'Front POS'),
  ('64000000-0000-0000-0000-00000000da21', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', 'kiosk', 'Kiosk One');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('64000000-0000-0000-0000-00000000fa11', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-00000000da11', 'active'),
  ('64000000-0000-0000-0000-00000000fa21', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-00000000da21', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('64000000-0000-0000-0000-0000000005a1', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-00000000da11', '64000000-0000-0000-0000-00000000fa11');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at) values
  ('64000000-0000-0000-0000-0000000005a2', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-00000000da21', '64000000-0000-0000-0000-00000000fa21', app.hash_provisioning_secret('tok-kiosk-121'), true, null, now() + interval '1 day');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('64000000-0000-0000-0000-0000000ef002', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-00000000ee02', '64000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('64000000-0000-0000-0000-00000000c501', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', '64000000-0000-0000-0000-0000000005a1', '64000000-0000-0000-0000-0000000ef002', '64000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');
insert into table_sections (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('64000000-0000-0000-0000-00000000ec01', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', 'Main Hall', 0),
  ('64000000-0000-0000-0000-00000000ec0b', '64000000-0000-0000-0000-0000000000b0', '64000000-0000-0000-0000-0000000000b1', '64000000-0000-0000-0000-00000000b1b1', 'B Hall',    0);
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, area, section_id, layout_x, layout_y) values
  ('64000000-0000-0000-0000-000000000001', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1', '64000000-0000-0000-0000-00000000a1b1', 'Alpha', 4, 'Main',
   '64000000-0000-0000-0000-00000000ec01', 2500, 7500);

-- ===== (1-5) schema =========================================================
select has_column('public', 'table_sections', 'room_frame_preset', 'table_sections.room_frame_preset exists');
select ok((select room_frame_preset is null from table_sections where id = '64000000-0000-0000-0000-00000000ec01'),
  'existing rows carry NULL (= Standard) — no backfill, no default');
select throws_ok(
  $$ update table_sections set room_frame_preset = 'Wide' where id = '64000000-0000-0000-0000-00000000ec01' $$,
  '23514', NULL, 'an upper-case key violates the structural CHECK');
select has_function('app', 'set_table_section_room_frame_preset', array['uuid', 'uuid', 'uuid', 'text'],
  'app.set_table_section_room_frame_preset exists');
select has_function('public', 'set_table_section_room_frame_preset', array['uuid', 'uuid', 'uuid', 'text'],
  'public wrapper exists');

-- ===== (6-19) setter ========================================================
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee01';
create temp table f_set as select app.set_table_section_room_frame_preset(
  '64000000-0000-0000-0000-00000000c001', '64000000-0000-0000-0000-0000000000a0',
  '64000000-0000-0000-0000-00000000ec01', 'portrait') as res;
create temp table f_replay as select app.set_table_section_room_frame_preset(
  '64000000-0000-0000-0000-00000000c001', '64000000-0000-0000-0000-0000000000a0',
  '64000000-0000-0000-0000-00000000ec01', 'portrait') as res;
create temp table f_same as select app.set_table_section_room_frame_preset(
  '64000000-0000-0000-0000-00000000c002', '64000000-0000-0000-0000-0000000000a0',
  '64000000-0000-0000-0000-00000000ec01', '  portrait  ') as res;
reset role;
select is((select (res->>'ok')::boolean from f_set), true, 'org_owner sets a room frame (ok:true)');
select is((select res->>'action' from f_set), 'room_frame_preset_set', 'action = room_frame_preset_set');
select is((select room_frame_preset from table_sections where id = '64000000-0000-0000-0000-00000000ec01'),
          'portrait', 'the key is stored');
select is((select (res->>'idempotent_replay')::boolean from f_replay), true, 'replay returns idempotent_replay=true');
select is((select (res->>'ok')::boolean from f_same), true, 'no-change (trimmed) is an idempotent success');
select is(
  (select count(*) from audit_events
   where organization_id = '64000000-0000-0000-0000-0000000000a0'
     and action = 'table_section.room_frame_preset_set')::int, 1,
  'the change is audited exactly once');
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.set_table_section_room_frame_preset(
       '64000000-0000-0000-0000-00000000c003', '64000000-0000-0000-0000-0000000000a0',
       '64000000-0000-0000-0000-00000000ec01', 'banana') $$,
  '42501', NULL, 'a well-formed but UNAPPROVED key is refused (semantic vocabulary)');
select throws_ok(
  $$ select app.set_table_section_room_frame_preset(
       '64000000-0000-0000-0000-00000000c004', '64000000-0000-0000-0000-0000000000a0',
       '64000000-0000-0000-0000-00000000ec01', 'standard') $$,
  '42501', NULL, 'standard is NULL, never a stored key — refused');
reset role;
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee02';
create temp table f_denied as select app.set_table_section_room_frame_preset(
  '64000000-0000-0000-0000-00000000c005', '64000000-0000-0000-0000-0000000000a0',
  '64000000-0000-0000-0000-00000000ec01', 'wide') as res;
reset role;
select is((select res->>'error' from f_denied), 'permission_denied', 'a cashier is denied');
select is(
  (select count(*) from audit_events
   where organization_id = '64000000-0000-0000-0000-0000000000a0'
     and action = 'table_section.room_frame_preset_denied')::int, 1,
  'the denial is audited');
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.set_table_section_room_frame_preset(
       '64000000-0000-0000-0000-00000000c006', '64000000-0000-0000-0000-0000000000b0',
       '64000000-0000-0000-0000-00000000ec01', 'wide') $$,
  '42501', NULL, 'Org B owner targeting an Org A section raises 42501 (R-003)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee01';
create temp table f_all as
  select (select (app.set_table_section_room_frame_preset('64000000-0000-0000-0000-00000000c010', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-00000000ec01', 'compact')->>'ok')::boolean)
     and (select (app.set_table_section_room_frame_preset('64000000-0000-0000-0000-00000000c011', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-00000000ec01', 'square')->>'ok')::boolean)
     and (select (app.set_table_section_room_frame_preset('64000000-0000-0000-0000-00000000c012', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-00000000ec01', 'wide')->>'ok')::boolean)
     and (select (app.set_table_section_room_frame_preset('64000000-0000-0000-0000-00000000c013', '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-00000000ec01', 'long_narrow')->>'ok')::boolean)
     as all_ok;
create temp table f_clear as select app.set_table_section_room_frame_preset(
  '64000000-0000-0000-0000-00000000c014', '64000000-0000-0000-0000-0000000000a0',
  '64000000-0000-0000-0000-00000000ec01', '') as res;
reset role;
select ok((select all_ok from f_all), 'every approved key is accepted');
select ok(
  (select (res->>'ok')::boolean from f_clear)
  and (select room_frame_preset is null from table_sections where id = '64000000-0000-0000-0000-00000000ec01'),
  'a blank clears back to NULL (= Standard)');
select is(
  (select (layout_x, layout_y) = (2500, 7500) from tables where id = '64000000-0000-0000-0000-000000000001'),
  true, 'saved coordinates were NEVER touched by frame changes');

-- ===== (20-27) read wires ====================================================
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee01';
create temp table f_set2 as select app.set_table_section_room_frame_preset(
  '64000000-0000-0000-0000-00000000c015', '64000000-0000-0000-0000-0000000000a0',
  '64000000-0000-0000-0000-00000000ec01', 'square') as res;
create temp table lt as select app.list_tables(
  '64000000-0000-0000-0000-0000000000a0', '64000000-0000-0000-0000-0000000000a1',
  '64000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'sections'->0) order by 1) from lt),
  array['branch_id','display_order','floor_preset','id','is_active','name','room_frame_preset'],
  'list_tables sections pin the 118 six keys + room_frame_preset');
select is((select s->>'room_frame_preset' from lt, jsonb_array_elements(res->'sections') s where s->>'name' = 'Main Hall'),
          'square', 'the sections catalog serves the stored frame');
set local role authenticated;
create temp table pos_read as select app.pos_tables(
  '64000000-0000-0000-0000-00000000c501', '64000000-0000-0000-0000-00000000da11') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from pos_read),
  array['active_order_count','active_orders','area','effective_state','group_id','id','label','layout_x',
        'layout_y','seats','section_display_order','section_floor_preset','section_id','section_name',
        'section_room_frame_preset','status','visual_material','visual_preset'],
  'pos_tables rows pin the 120 sixteen keys + section_room_frame_preset');
select is(
  (select t->>'section_room_frame_preset' from pos_read, jsonb_array_elements(res->'tables') t where t->>'label' = 'Alpha'),
  'square', 'the POS row carries the section frame');
create temp table kt as select public.kiosk_tables(
  '64000000-0000-0000-0000-00000000da21', 'tok-kiosk-121') as res;
select is((select (res->>'ok')::boolean from kt), true, 'kiosk_tables succeeds on a live kiosk token');
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from kt),
  array['area','effective_state','id','label','layout_x','layout_y','seats','section_display_order',
        'section_floor_preset','section_id','section_name','section_room_frame_preset',
        'visual_material','visual_preset'],
  'kiosk_tables rows pin the 120 thirteen keys + section_room_frame_preset');
select is(
  (select t->>'section_room_frame_preset' from kt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Alpha'),
  'square', 'the kiosk row carries the SAME frame');
select ok((select not exists (select 1 from jsonb_array_elements(res->'tables') t
             where t ? 'status' or t ? 'active_order_count' or t ? 'group_id') from kt),
  'STILL withheld from the customer: manual status / counts / groups');

-- ===== (28-38) posture ======================================================
select ok(
  (select p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'set_table_section_room_frame_preset'),
  'the setter is SECURITY DEFINER with a pinned search_path');
select ok(has_function_privilege('authenticated', 'app.set_table_section_room_frame_preset(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute the app setter');
select ok(not has_function_privilege('anon', 'app.set_table_section_room_frame_preset(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute the app setter');
select ok(has_function_privilege('authenticated', 'public.set_table_section_room_frame_preset(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute the wrapper');
select ok(not has_function_privilege('anon', 'public.set_table_section_room_frame_preset(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute the wrapper (hardened)');
select throws_ok(
  $$ select app.set_table_section_room_frame_preset(
       '64000000-0000-0000-0000-00000000c016', '64000000-0000-0000-0000-0000000000b0',
       '64000000-0000-0000-0000-00000000ffff', 'wide') $$,
  '42501', NULL, 'an unknown section raises 42501');
update table_sections set deleted_at = now() where id = '64000000-0000-0000-0000-00000000ec0b';
set local role authenticated;
set local app.current_app_user_id = '64000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.set_table_section_room_frame_preset(
       '64000000-0000-0000-0000-00000000c017', '64000000-0000-0000-0000-0000000000b0',
       '64000000-0000-0000-0000-00000000ec0b', 'wide') $$,
  '42501', NULL, 'a tombstoned section raises 42501');
reset role;
set local app.current_app_user_id = '';
select throws_ok(
  $$ select app.set_table_section_room_frame_preset(
       '64000000-0000-0000-0000-00000000c018', '64000000-0000-0000-0000-0000000000a0',
       '64000000-0000-0000-0000-00000000ec01', 'wide') $$,
  '42501', NULL, 'an unauthenticated caller raises 42501');

select * from finish();
rollback;
