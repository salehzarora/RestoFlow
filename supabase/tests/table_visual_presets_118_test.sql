-- ============================================================================
-- TABLE-VISUAL-LAYOUT-118 — pgTAP: table visual presets + section floor presets
-- (D-001/D-011/D-012/D-013/D-017; RISK R-003)
-- ============================================================================
-- Additive nullable presentation keys (tables.visual_preset,
-- table_sections.floor_preset) with the structural key CHECK; the two
-- dedicated setters (validation, target-row-first authorization, ledger
-- idempotency, conflicting reuse, no-change without audit, denial audit,
-- cross-org 42501, clear with NULL); the additive read projections
-- (list_tables rows + sections, pos_tables rows, kiosk_tables rows + the new
-- fixture catalog) with exact key-set pins; the kiosk still withholds the
-- manual status / counts / groups; SECURITY DEFINER + grant posture.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(53);

-- ===== fixtures: Org A (Rest A1: branches A1a, A1b), Org B ===================
insert into organizations (id, name, slug, default_currency) values
  ('62000000-0000-0000-0000-0000000000a0', 'Org A', 'tvp-a', 'USD'),
  ('62000000-0000-0000-0000-0000000000b0', 'Org B', 'tvp-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('62000000-0000-0000-0000-0000000000b1', '62000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('62000000-0000-0000-0000-00000000a1b2', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('62000000-0000-0000-0000-00000000b1b1', '62000000-0000-0000-0000-0000000000b0', '62000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('62000000-0000-0000-0000-00000000ee01', 'tvp-owner-a@example.test'),
  ('62000000-0000-0000-0000-00000000ee02', 'tvp-cashier@example.test'),
  ('62000000-0000-0000-0000-00000000ee0b', 'tvp-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('62000000-0000-0000-0000-00000000ab01', '62000000-0000-0000-0000-00000000ee01', '62000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('62000000-0000-0000-0000-00000000ab02', '62000000-0000-0000-0000-00000000ee02', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('62000000-0000-0000-0000-00000000ab0b', '62000000-0000-0000-0000-00000000ee0b', '62000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');

-- POS device + PIN plumbing at Branch A1a (pos_tables) + a KIOSK device with a
-- live token (kiosk_tables) ---------------------------------------------------
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('62000000-0000-0000-0000-00000000da11', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'pos',   'Front POS'),
  ('62000000-0000-0000-0000-00000000da21', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'kiosk', 'Kiosk One');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('62000000-0000-0000-0000-00000000fa11', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-00000000da11', 'active'),
  ('62000000-0000-0000-0000-00000000fa21', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-00000000da21', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('62000000-0000-0000-0000-0000000005a1', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-00000000da11', '62000000-0000-0000-0000-00000000fa11');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at) values
  ('62000000-0000-0000-0000-0000000005a2', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-00000000da21', '62000000-0000-0000-0000-00000000fa21', app.hash_provisioning_secret('tok-kiosk-118'), true, null, now() + interval '1 day');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('62000000-0000-0000-0000-0000000ef002', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-00000000ee02', '62000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('62000000-0000-0000-0000-00000000c501', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-0000000005a1', '62000000-0000-0000-0000-0000000ef002', '62000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- sections + tables + one fixture ---------------------------------------------
insert into table_sections (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('62000000-0000-0000-0000-00000000ec01', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'Main Hall', 0),
  ('62000000-0000-0000-0000-00000000ec02', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'Terrace',   1),
  ('62000000-0000-0000-0000-00000000ec0b', '62000000-0000-0000-0000-0000000000b0', '62000000-0000-0000-0000-0000000000b1', '62000000-0000-0000-0000-00000000b1b1', 'B Hall',    0);
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, area, section_id, layout_x, layout_y) values
  ('62000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'Alpha', 4, 'Main',
   '62000000-0000-0000-0000-00000000ec01', 2500, 7500),
  ('62000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', 'Beta', 2, null,
   null, null, null),
  ('62000000-0000-0000-0000-00000000000b', '62000000-0000-0000-0000-0000000000b0', '62000000-0000-0000-0000-0000000000b1', '62000000-0000-0000-0000-00000000b1b1', 'Bravo', 2, null,
   null, null, null);
insert into table_floor_elements (id, organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm) values
  ('62000000-0000-0000-0000-00000000fe01', '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1', '62000000-0000-0000-0000-00000000a1b1', '62000000-0000-0000-0000-00000000ec01', 'wall', 100, 9000, 5000, 150);

-- ===== (1-7) schema: additive nullable keys + the structural CHECK ===========
select has_column('public', 'tables', 'visual_preset', 'tables.visual_preset exists');
select has_column('public', 'table_sections', 'floor_preset', 'table_sections.floor_preset exists');
select ok(
  (select visual_preset is null from tables where id = '62000000-0000-0000-0000-000000000001')
  and (select floor_preset is null from table_sections where id = '62000000-0000-0000-0000-00000000ec01'),
  'existing rows carry NULL (the default look) — no backfill, no default');
select throws_ok(
  $$ update tables set visual_preset = 'Round' where id = '62000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'an upper-case preset key violates the tables key CHECK');
select throws_ok(
  $$ update table_sections set floor_preset = '1wood' where id = '62000000-0000-0000-0000-00000000ec01' $$,
  '23514', NULL, 'a digit-led floor key violates the table_sections key CHECK');
select has_function('app', 'set_table_visual_preset', array['uuid', 'uuid', 'uuid', 'text'],
  'app.set_table_visual_preset(uuid, uuid, uuid, text) exists');
select has_function('app', 'set_table_section_floor_preset', array['uuid', 'uuid', 'uuid', 'text'],
  'app.set_table_section_floor_preset(uuid, uuid, uuid, text) exists');

-- ===== (8-19) set_table_visual_preset ========================================
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee01';
create temp table p_set as select app.set_table_visual_preset(
  '62000000-0000-0000-0000-00000000c001', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-000000000001', 'round_table') as res;
create temp table p_replay as select app.set_table_visual_preset(
  '62000000-0000-0000-0000-00000000c001', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-000000000001', 'round_table') as res;
create temp table p_same as select app.set_table_visual_preset(
  '62000000-0000-0000-0000-00000000c002', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-000000000001', '  round_table  ') as res;
reset role;
select is((select (res->>'ok')::boolean from p_set), true, 'org_owner sets a table visual preset (ok:true)');
select is((select res->>'action' from p_set), 'visual_preset_set', 'the setter reports action=visual_preset_set');
select is((select visual_preset from tables where id = '62000000-0000-0000-0000-000000000001'),
          'round_table', 'the preset key is stored');
select is((select (res->>'idempotent_replay')::boolean from p_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
select is((select (res->>'ok')::boolean from p_same), true,
          'a NEW request with the SAME (trimmed) value is an idempotent success');
select is(
  (select count(*) from audit_events
   where organization_id = '62000000-0000-0000-0000-0000000000a0'
     and action = 'table.visual_preset_set')::int, 1,
  'the change is audited exactly once (the no-change call adds no audit)');
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.set_table_visual_preset(
       '62000000-0000-0000-0000-00000000c001', '62000000-0000-0000-0000-0000000000a0',
       '62000000-0000-0000-0000-000000000001', 'booth_table') $$,
  '42501', NULL, 'reusing a client_request_id with a DIFFERENT preset raises 42501');
select throws_ok(
  $$ select app.set_table_visual_preset(
       '62000000-0000-0000-0000-00000000c003', '62000000-0000-0000-0000-0000000000a0',
       '62000000-0000-0000-0000-000000000001', 'Round Table') $$,
  '42501', NULL, 'an invalid preset key is refused by the RPC (before the CHECK)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee02';
create temp table p_denied as select app.set_table_visual_preset(
  '62000000-0000-0000-0000-00000000c004', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-000000000001', 'booth_table') as res;
reset role;
select is((select res->>'error' from p_denied), 'permission_denied', 'a cashier is denied (permission_denied)');
select is(
  (select count(*) from audit_events
   where organization_id = '62000000-0000-0000-0000-0000000000a0'
     and action = 'table.visual_preset_denied')::int, 1,
  'the denial is audited (table.visual_preset_denied)');
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.set_table_visual_preset(
       '62000000-0000-0000-0000-00000000c005', '62000000-0000-0000-0000-0000000000b0',
       '62000000-0000-0000-0000-000000000001', 'booth_table') $$,
  '42501', NULL, 'Org B owner targeting an Org A table raises 42501 (R-003)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee01';
create temp table p_clear as select app.set_table_visual_preset(
  '62000000-0000-0000-0000-00000000c006', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-000000000001', null) as res;
reset role;
select ok(
  (select (res->>'ok')::boolean from p_clear)
  and (select visual_preset is null from tables where id = '62000000-0000-0000-0000-000000000001'),
  'NULL clears the preset back to the default look');
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee01';
create temp table p_booth as select app.set_table_visual_preset(
  '62000000-0000-0000-0000-00000000c007', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-000000000001', 'booth_table') as res;
reset role;
select is((select visual_preset from tables where id = '62000000-0000-0000-0000-000000000001'),
          'booth_table', 'the preset can be set again after a clear');

-- ===== (20-27) set_table_section_floor_preset ===============================
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee01';
create temp table f_set as select app.set_table_section_floor_preset(
  '62000000-0000-0000-0000-00000000c101', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-00000000ec01', 'wood_dark') as res;
create temp table f_replay as select app.set_table_section_floor_preset(
  '62000000-0000-0000-0000-00000000c101', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-00000000ec01', 'wood_dark') as res;
reset role;
select is((select (res->>'ok')::boolean from f_set), true, 'org_owner sets a section floor preset (ok:true)');
select is((select res->>'action' from f_set), 'floor_preset_set', 'the setter reports action=floor_preset_set');
select is((select floor_preset from table_sections where id = '62000000-0000-0000-0000-00000000ec01'),
          'wood_dark', 'the floor key is stored on the section');
select is((select (res->>'idempotent_replay')::boolean from f_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
select is(
  (select count(*) from audit_events
   where organization_id = '62000000-0000-0000-0000-0000000000a0'
     and action = 'table_section.floor_preset_set')::int, 1,
  'the section change is audited exactly once');
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee02';
create temp table f_denied as select app.set_table_section_floor_preset(
  '62000000-0000-0000-0000-00000000c102', '62000000-0000-0000-0000-0000000000a0',
  '62000000-0000-0000-0000-00000000ec01', 'tile_modern') as res;
reset role;
select is((select res->>'error' from f_denied), 'permission_denied', 'a cashier cannot change a floor preset');
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.set_table_section_floor_preset(
       '62000000-0000-0000-0000-00000000c103', '62000000-0000-0000-0000-0000000000b0',
       '62000000-0000-0000-0000-00000000ec01', 'tile_modern') $$,
  '42501', NULL, 'Org B owner targeting an Org A section raises 42501 (R-003)');
select throws_ok(
  $$ select app.set_table_section_floor_preset(
       '62000000-0000-0000-0000-00000000c104', '62000000-0000-0000-0000-0000000000b0',
       '62000000-0000-0000-0000-00000000ffff', 'tile_modern') $$,
  '42501', NULL, 'an unknown section raises 42501');
reset role;

-- ===== (28-32) list_tables: additive keys, exact pins =======================
set local role authenticated;
set local app.current_app_user_id = '62000000-0000-0000-0000-00000000ee01';
create temp table lt as select app.list_tables(
  '62000000-0000-0000-0000-0000000000a0', '62000000-0000-0000-0000-0000000000a1',
  '62000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from lt),
  array['active_order_count','area','branch_id','effective_state','group_id','id','is_active',
        'label','layout_x','layout_y','seats','section_display_order','section_id','section_name',
        'status','visual_preset'],
  'list_tables rows pin EXACTLY the 027 fifteen keys + visual_preset');
select is((select t->>'visual_preset' from lt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Alpha'),
          'booth_table', 'list_tables serves the stored table preset');
select ok((select t->>'visual_preset' is null from lt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Beta'),
          'a legacy row serves a NULL preset (client default)');
select is(
  (select array(select jsonb_object_keys(res->'sections'->0) order by 1) from lt),
  array['branch_id','display_order','floor_preset','id','is_active','name'],
  'list_tables sections pin EXACTLY the 021 five keys + floor_preset');
select ok(
  (select (select s->>'floor_preset' from jsonb_array_elements(res->'sections') s where s->>'name' = 'Main Hall') = 'wood_dark'
      and (select s->>'floor_preset' is null from jsonb_array_elements(res->'sections') s where s->>'name' = 'Terrace')
     from lt),
  'the sections catalog serves the stored floor preset (NULL for an untouched section)');

-- ===== (33-36) pos_tables: additive keys, exact pins ========================
set local role authenticated;
create temp table pos_read as select app.pos_tables(
  '62000000-0000-0000-0000-00000000c501', '62000000-0000-0000-0000-00000000da11') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from pos_read),
  array['active_order_count','area','effective_state','group_id','id','label','layout_x',
        'layout_y','seats','section_display_order','section_floor_preset','section_id','section_name',
        'status','visual_preset'],
  'pos_tables rows pin EXACTLY the 021 thirteen keys + visual_preset + section_floor_preset');
select is(
  (select (t->>'visual_preset', t->>'section_floor_preset') = ('booth_table', 'wood_dark')
     from pos_read, jsonb_array_elements(res->'tables') t where t->>'label' = 'Alpha'),
  true, 'a placed table carries its preset AND its section floor preset');
select ok(
  (select t->>'visual_preset' is null and t->>'section_floor_preset' is null
     from pos_read, jsonb_array_elements(res->'tables') t where t->>'label' = 'Beta'),
  'an unsectioned legacy table carries NULL for both keys');
select is((select jsonb_array_length(res->'floor_elements') from pos_read), 1,
          'the 027 fixture catalog is unchanged on pos_tables');

-- ===== (37-44) kiosk_tables: the SAME map — placement + presets + fixtures ===
create temp table kt as select public.kiosk_tables(
  '62000000-0000-0000-0000-00000000da21', 'tok-kiosk-118') as res;
select is((select (res->>'ok')::boolean from kt), true, 'kiosk_tables succeeds on a live kiosk token');
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from kt),
  array['area','effective_state','id','label','layout_x','layout_y','seats','section_display_order',
        'section_floor_preset','section_id','section_name','visual_preset'],
  'kiosk_tables rows pin EXACTLY the Phase-2 eight keys + layout_x/layout_y/visual_preset/section_floor_preset');
select is(
  (select (t->>'layout_x', t->>'layout_y', t->>'visual_preset', t->>'section_floor_preset')
        = ('2500', '7500', 'booth_table', 'wood_dark')
     from kt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Alpha'),
  true, 'the kiosk reads the SAME saved placement + presets the POS reads');
select ok(
  (select t->>'layout_x' is null and t->>'layout_y' is null
     from kt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Beta'),
  'an unplaced table carries NULL coordinates (kiosk keeps it in the list strip)');
select ok((select not exists (select 1 from jsonb_array_elements(res->'tables') t
             where t ? 'status' or t ? 'active_order_count' or t ? 'group_id') from kt),
  'STILL withheld from the customer: manual status / counts / groups');
select is((select jsonb_array_length(res->'floor_elements') from kt), 1,
          'kiosk_tables gains the floor_elements fixture catalog (the wall)');
select is(
  (select array(select jsonb_object_keys(res->'floor_elements'->0) order by 1) from kt),
  array['height_norm','id','kind','label','layout_x','layout_y','orientation_quarter_turns',
        'section_id','width_norm'],
  'the kiosk fixture rows carry the SAME nine keys as pos_tables');
select ok((select not exists (select 1 from jsonb_array_elements(res->'tables') t where t->>'label' = 'Bravo') from kt),
  'a foreign-org table is never served to the kiosk');

-- ===== (45-52) posture: SECURITY DEFINER, search_path, grants, wrappers =====
select ok(
  (select p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'set_table_visual_preset'),
  'app.set_table_visual_preset is SECURITY DEFINER with a pinned search_path');
select ok(
  (select p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'set_table_section_floor_preset'),
  'app.set_table_section_floor_preset is SECURITY DEFINER with a pinned search_path');
select ok(has_function_privilege('authenticated', 'app.set_table_visual_preset(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute app.set_table_visual_preset');
select ok(not has_function_privilege('anon', 'app.set_table_visual_preset(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute app.set_table_visual_preset');
select ok(has_function_privilege('authenticated', 'app.set_table_section_floor_preset(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute app.set_table_section_floor_preset');
select ok(not has_function_privilege('anon', 'app.set_table_section_floor_preset(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute app.set_table_section_floor_preset');
select has_function('public', 'set_table_visual_preset', array['uuid', 'uuid', 'uuid', 'text'],
  'public.set_table_visual_preset wrapper exists');
select has_function('public', 'set_table_section_floor_preset', array['uuid', 'uuid', 'uuid', 'text'],
  'public.set_table_section_floor_preset wrapper exists');

select * from finish();
rollback;
