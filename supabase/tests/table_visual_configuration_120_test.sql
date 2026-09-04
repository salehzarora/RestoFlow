-- ============================================================================
-- TABLE-VISUAL-CONFIGURATION-120 — pgTAP: persisted table material + fixture
-- style (D-001/D-011/D-012/D-013/D-017; RISK R-003)
-- ============================================================================
-- Additive nullable presentation keys (tables.visual_material,
-- table_floor_elements.visual_style) with the structural key CHECK PLUS
-- server-side SEMANTIC vocabulary validation (the 120 correction to the 118
-- registry-only precedent): the material setter accepts only the six approved
-- material keys, the element setter validates the style against the approved
-- registry FOR THE TARGET ELEMENT'S AUTHORITATIVE KIND (cross-kind values are
-- refused). Dedicated setters (target-row-first authorization, ledger
-- idempotency, no-change without audit, denial audit, cross-org 42501, clear
-- with NULL/blank); additive read projections on all three wires with exact
-- key-set pins; kiosk withheld fields unchanged; SECURITY DEFINER + grant
-- posture pinned at BOTH the app layer and the public wrappers (anon denied
-- on the wrappers too — the hardened pattern; the older wrappers' default-
-- grant debt is tracked separately and deliberately untouched here).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(66);

-- ===== fixtures: Org A (Rest A1: branch A1a), Org B ==========================
insert into organizations (id, name, slug, default_currency) values
  ('63000000-0000-0000-0000-0000000000a0', 'Org A', 'tvc-a', 'USD'),
  ('63000000-0000-0000-0000-0000000000b0', 'Org B', 'tvc-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('63000000-0000-0000-0000-0000000000b1', '63000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('63000000-0000-0000-0000-00000000b1b1', '63000000-0000-0000-0000-0000000000b0', '63000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('63000000-0000-0000-0000-00000000ee01', 'tvc-owner-a@example.test'),
  ('63000000-0000-0000-0000-00000000ee02', 'tvc-cashier@example.test'),
  ('63000000-0000-0000-0000-00000000ee0b', 'tvc-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('63000000-0000-0000-0000-00000000ab01', '63000000-0000-0000-0000-00000000ee01', '63000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('63000000-0000-0000-0000-00000000ab02', '63000000-0000-0000-0000-00000000ee02', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('63000000-0000-0000-0000-00000000ab0b', '63000000-0000-0000-0000-00000000ee0b', '63000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');

-- POS device + PIN plumbing (pos_tables) + a live KIOSK token (kiosk_tables) --
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('63000000-0000-0000-0000-00000000da11', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', 'pos',   'Front POS'),
  ('63000000-0000-0000-0000-00000000da21', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', 'kiosk', 'Kiosk One');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('63000000-0000-0000-0000-00000000fa11', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000da11', 'active'),
  ('63000000-0000-0000-0000-00000000fa21', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000da21', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('63000000-0000-0000-0000-0000000005a1', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000da11', '63000000-0000-0000-0000-00000000fa11');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at) values
  ('63000000-0000-0000-0000-0000000005a2', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000da21', '63000000-0000-0000-0000-00000000fa21', app.hash_provisioning_secret('tok-kiosk-120'), true, null, now() + interval '1 day');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('63000000-0000-0000-0000-0000000ef002', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ee02', '63000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('63000000-0000-0000-0000-00000000c501', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-0000000005a1', '63000000-0000-0000-0000-0000000ef002', '63000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- sections + tables + one fixture of EVERY kind (per-kind vocabulary) + one
-- extra wall reserved for the tombstone case -----------------------------------
insert into table_sections (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('63000000-0000-0000-0000-00000000ec01', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', 'Main Hall', 0),
  ('63000000-0000-0000-0000-00000000ec0b', '63000000-0000-0000-0000-0000000000b0', '63000000-0000-0000-0000-0000000000b1', '63000000-0000-0000-0000-00000000b1b1', 'B Hall',    0);
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, area, section_id, layout_x, layout_y) values
  ('63000000-0000-0000-0000-000000000001', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', 'Alpha', 4, 'Main',
   '63000000-0000-0000-0000-00000000ec01', 2500, 7500),
  ('63000000-0000-0000-0000-000000000002', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', 'Beta', 2, null,
   null, null, null),
  ('63000000-0000-0000-0000-00000000000b', '63000000-0000-0000-0000-0000000000b0', '63000000-0000-0000-0000-0000000000b1', '63000000-0000-0000-0000-00000000b1b1', 'Bravo', 2, null,
   null, null, null);
insert into table_floor_elements (id, organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm) values
  ('63000000-0000-0000-0000-00000000fe01', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ec01', 'wall',    100, 9000, 5000, 150),
  ('63000000-0000-0000-0000-00000000fe02', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ec01', 'plant',  9000,  100,  900, 900),
  ('63000000-0000-0000-0000-00000000fe03', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ec01', 'door',    300,    0,  900, 150),
  ('63000000-0000-0000-0000-00000000fe04', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ec01', 'cashier',6800,    0,  900, 900),
  ('63000000-0000-0000-0000-00000000fe05', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ec01', 'window', 4600,    0, 2000, 150),
  ('63000000-0000-0000-0000-00000000fe06', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1', '63000000-0000-0000-0000-00000000a1b1', '63000000-0000-0000-0000-00000000ec01', 'wall',    100,  100, 3000, 150);

-- ===== (1-8) schema: additive nullable keys + the structural CHECK ===========
select has_column('public', 'tables', 'visual_material', 'tables.visual_material exists');
select has_column('public', 'table_floor_elements', 'visual_style', 'table_floor_elements.visual_style exists');
select ok(
  (select visual_material is null from tables where id = '63000000-0000-0000-0000-000000000001')
  and (select visual_style is null from table_floor_elements where id = '63000000-0000-0000-0000-00000000fe01'),
  'existing rows carry NULL (Auto / default artwork) — no backfill, no default');
select throws_ok(
  $$ update tables set visual_material = 'Wood' where id = '63000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'an upper-case material key violates the tables key CHECK');
select throws_ok(
  $$ update table_floor_elements set visual_style = '1brick' where id = '63000000-0000-0000-0000-00000000fe01' $$,
  '23514', NULL, 'a digit-led style key violates the elements key CHECK');
select has_function('app', 'set_table_visual_material', array['uuid', 'uuid', 'uuid', 'text'],
  'app.set_table_visual_material(uuid, uuid, uuid, text) exists');
select has_function('app', 'set_floor_element_style', array['uuid', 'uuid', 'uuid', 'text'],
  'app.set_floor_element_style(uuid, uuid, uuid, text) exists');
select ok(
  (select visual_material is null from tables where id = '63000000-0000-0000-0000-000000000002'),
  'a legacy unsectioned row also stays NULL');

-- ===== (9-24) set_table_visual_material ======================================
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
create temp table m_set as select app.set_table_visual_material(
  '63000000-0000-0000-0000-00000000c001', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-000000000001', 'dark_wood') as res;
create temp table m_replay as select app.set_table_visual_material(
  '63000000-0000-0000-0000-00000000c001', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-000000000001', 'dark_wood') as res;
create temp table m_same as select app.set_table_visual_material(
  '63000000-0000-0000-0000-00000000c002', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-000000000001', '  dark_wood  ') as res;
reset role;
select is((select (res->>'ok')::boolean from m_set), true, 'org_owner sets a table material (ok:true)');
select is((select res->>'action' from m_set), 'visual_material_set', 'the setter reports action=visual_material_set');
select is((select visual_material from tables where id = '63000000-0000-0000-0000-000000000001'),
          'dark_wood', 'the material key is stored');
select is((select (res->>'idempotent_replay')::boolean from m_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
select is((select (res->>'ok')::boolean from m_same), true,
          'a NEW request with the SAME (trimmed) value is an idempotent success');
select is(
  (select count(*) from audit_events
   where organization_id = '63000000-0000-0000-0000-0000000000a0'
     and action = 'table.visual_material_set')::int, 1,
  'the change is audited exactly once (the no-change call adds no audit)');
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.set_table_visual_material(
       '63000000-0000-0000-0000-00000000c003', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-000000000001', 'banana') $$,
  '42501', NULL, 'a well-formed but UNAPPROVED material key is refused (semantic vocabulary)');
select throws_ok(
  $$ select app.set_table_visual_material(
       '63000000-0000-0000-0000-00000000c004', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-000000000001', 'Dark Wood') $$,
  '42501', NULL, 'a malformed material key is refused before the CHECK');
reset role;
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee02';
create temp table m_denied as select app.set_table_visual_material(
  '63000000-0000-0000-0000-00000000c005', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-000000000001', 'wood') as res;
reset role;
select is((select res->>'error' from m_denied), 'permission_denied', 'a cashier is denied (permission_denied)');
select is(
  (select count(*) from audit_events
   where organization_id = '63000000-0000-0000-0000-0000000000a0'
     and action = 'table.visual_material_denied')::int, 1,
  'the denial is audited (table.visual_material_denied)');
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.set_table_visual_material(
       '63000000-0000-0000-0000-00000000c006', '63000000-0000-0000-0000-0000000000b0',
       '63000000-0000-0000-0000-000000000001', 'wood') $$,
  '42501', NULL, 'Org B owner targeting an Org A table raises 42501 (R-003)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
create temp table m_clear as select app.set_table_visual_material(
  '63000000-0000-0000-0000-00000000c007', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-000000000001', '   ') as res;
reset role;
select ok(
  (select (res->>'ok')::boolean from m_clear)
  and (select visual_material is null from tables where id = '63000000-0000-0000-0000-000000000001'),
  'a blank material clears back to NULL (= Auto)');
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
create temp table m_all as
  select (select (app.set_table_visual_material('63000000-0000-0000-0000-00000000c010', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-000000000001', 'wood')->>'ok')::boolean)
     and (select (app.set_table_visual_material('63000000-0000-0000-0000-00000000c011', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-000000000001', 'light_wood')->>'ok')::boolean)
     and (select (app.set_table_visual_material('63000000-0000-0000-0000-00000000c012', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-000000000001', 'rustic_wood')->>'ok')::boolean)
     and (select (app.set_table_visual_material('63000000-0000-0000-0000-00000000c013', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-000000000001', 'plastic')->>'ok')::boolean)
     and (select (app.set_table_visual_material('63000000-0000-0000-0000-00000000c014', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-000000000001', 'dark_wood')->>'ok')::boolean)
     and (select (app.set_table_visual_material('63000000-0000-0000-0000-00000000c015', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-000000000001', 'neutral_modern')->>'ok')::boolean)
     as all_ok;
reset role;
select ok((select all_ok from m_all), 'every approved material key is accepted');
select is((select visual_material from tables where id = '63000000-0000-0000-0000-000000000001'),
          'neutral_modern', 'the last approved material sticks');
set local app.current_app_user_id = '';
select throws_ok(
  $$ select app.set_table_visual_material(
       '63000000-0000-0000-0000-00000000c016', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-000000000001', 'wood') $$,
  '42501', NULL, 'an unauthenticated caller (no principal) raises 42501');

-- ===== (25-44) set_floor_element_style =======================================
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
create temp table s_set as select app.set_floor_element_style(
  '63000000-0000-0000-0000-00000000c101', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-00000000fe02', 'palm') as res;
create temp table s_replay as select app.set_floor_element_style(
  '63000000-0000-0000-0000-00000000c101', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-00000000fe02', 'palm') as res;
create temp table s_same as select app.set_floor_element_style(
  '63000000-0000-0000-0000-00000000c102', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-00000000fe02', ' palm ') as res;
reset role;
select is((select (res->>'ok')::boolean from s_set), true, 'org_owner sets a plant style (ok:true)');
select is((select res->>'action' from s_set), 'style_set', 'the setter reports action=style_set');
select is((select visual_style from table_floor_elements where id = '63000000-0000-0000-0000-00000000fe02'),
          'palm', 'the style key is stored on the element');
select is((select (res->>'idempotent_replay')::boolean from s_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
select is((select (res->>'ok')::boolean from s_same), true,
          'a NEW request with the SAME (trimmed) style is an idempotent success');
select is(
  (select count(*) from audit_events
   where organization_id = '63000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.style_set')::int, 1,
  'the element change is audited exactly once (no-change adds no audit)');
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c103', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-00000000fe02', 'banana') $$,
  '42501', NULL, 'a well-formed but UNKNOWN style is refused');
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c104', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-00000000fe02', 'glass') $$,
  '42501', NULL, 'CROSS-KIND: plant + glass is refused (glass belongs to doors)');
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c105', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-00000000fe03', 'leafy') $$,
  '42501', NULL, 'CROSS-KIND: door + leafy is refused (leafy belongs to plants)');
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c106', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-00000000fe04', 'brick') $$,
  '42501', NULL, 'CROSS-KIND: cashier + brick is refused (brick belongs to walls)');
reset role;
-- every valid style per kind is accepted (the last one per element sticks) ----
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
create temp table s_wall as
  select (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c110', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe01', 'plain')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c111', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe01', 'brick')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c112', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe01', 'wood_partition')->>'ok')::boolean)
     as all_ok;
create temp table s_door as
  select (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c113', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe03', 'wood')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c114', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe03', 'glass')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c115', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe03', 'modern')->>'ok')::boolean)
     as all_ok;
create temp table s_cashier as
  select (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c116', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe04', 'modern')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c117', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe04', 'wood')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c118', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe04', 'dark')->>'ok')::boolean)
     as all_ok;
create temp table s_window as
  select (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c119', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe05', 'modern_glass')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c11a', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe05', 'framed')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c11b', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe05', 'dark_frame')->>'ok')::boolean)
     as all_ok;
create temp table s_plant as
  select (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c11c', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe02', 'leafy')->>'ok')::boolean)
     and (select (app.set_floor_element_style('63000000-0000-0000-0000-00000000c11d', '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-00000000fe02', 'compact_pot')->>'ok')::boolean)
     as all_ok;
reset role;
select ok((select all_ok from s_wall), 'every wall style is accepted (plain|brick|wood_partition)');
select ok((select all_ok from s_door), 'every door style is accepted (wood|glass|modern)');
select ok((select all_ok from s_cashier), 'every cashier style is accepted (modern|wood|dark)');
select ok((select all_ok from s_window), 'every window style is accepted (modern_glass|framed|dark_frame)');
select ok((select all_ok from s_plant), 'every plant style is accepted (leafy|palm|compact_pot)');
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee02';
create temp table s_denied as select app.set_floor_element_style(
  '63000000-0000-0000-0000-00000000c120', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-00000000fe01', 'brick') as res;
reset role;
select is((select res->>'error' from s_denied), 'permission_denied', 'a cashier cannot set an element style');
select is(
  (select count(*) from audit_events
   where organization_id = '63000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.style_denied')::int, 1,
  'the element denial is audited (floor_element.style_denied)');
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c121', '63000000-0000-0000-0000-0000000000b0',
       '63000000-0000-0000-0000-00000000fe01', 'brick') $$,
  '42501', NULL, 'Org B owner targeting an Org A element raises 42501 (R-003)');
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c122', '63000000-0000-0000-0000-0000000000b0',
       '63000000-0000-0000-0000-00000000ffff', 'brick') $$,
  '42501', NULL, 'an unknown element raises 42501');
reset role;
update table_floor_elements set deleted_at = now() where id = '63000000-0000-0000-0000-00000000fe06';
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.set_floor_element_style(
       '63000000-0000-0000-0000-00000000c123', '63000000-0000-0000-0000-0000000000a0',
       '63000000-0000-0000-0000-00000000fe06', 'brick') $$,
  '42501', NULL, 'a tombstoned element raises 42501 (not found or deleted)');
create temp table s_clear as select app.set_floor_element_style(
  '63000000-0000-0000-0000-00000000c124', '63000000-0000-0000-0000-0000000000a0',
  '63000000-0000-0000-0000-00000000fe02', '') as res;
reset role;
select ok(
  (select (res->>'ok')::boolean from s_clear)
  and (select visual_style is null from table_floor_elements where id = '63000000-0000-0000-0000-00000000fe02'),
  'a blank style clears back to NULL (= the kind''s default artwork)');

-- ===== (45-52) read wires: additive keys, exact pins =========================
set local role authenticated;
set local app.current_app_user_id = '63000000-0000-0000-0000-00000000ee01';
create temp table lt as select app.list_tables(
  '63000000-0000-0000-0000-0000000000a0', '63000000-0000-0000-0000-0000000000a1',
  '63000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from lt),
  array['active_order_count','area','branch_id','effective_state','group_id','id','is_active',
        'label','layout_x','layout_y','seats','section_display_order','section_id','section_name',
        'status','visual_material','visual_preset'],
  'list_tables rows pin EXACTLY the 118 sixteen keys + visual_material');
select is((select t->>'visual_material' from lt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Alpha'),
          'neutral_modern', 'list_tables serves the stored table material');
select ok((select t->>'visual_material' is null from lt, jsonb_array_elements(res->'tables') t where t->>'label' = 'Beta'),
          'a legacy row serves a NULL material (client Auto)');
select is(
  (select array(select jsonb_object_keys(res->'floor_elements'->0) order by 1) from lt),
  array['height_norm','id','kind','label','layout_x','layout_y','orientation_quarter_turns',
        'section_id','visual_style','width_norm'],
  'list_tables fixture rows pin EXACTLY the 027 nine keys + visual_style');
set local role authenticated;
create temp table pos_read as select app.pos_tables(
  '63000000-0000-0000-0000-00000000c501', '63000000-0000-0000-0000-00000000da11') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from pos_read),
  array['active_order_count','active_orders','area','effective_state','group_id','id','label','layout_x',
        'layout_y','seats','section_display_order','section_floor_preset','section_id','section_name',
        'section_room_frame_preset','status','visual_material','visual_preset'],
  'pos_tables rows pin EXACTLY the 118 fifteen keys + visual_material');
select is(
  (select e->>'visual_style' from pos_read, jsonb_array_elements(res->'floor_elements') e
    where e->>'id' = '63000000-0000-0000-0000-00000000fe01'),
  'wood_partition', 'pos_tables serves the stored element style');
create temp table kt as select public.kiosk_tables(
  '63000000-0000-0000-0000-00000000da21', 'tok-kiosk-120') as res;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from kt),
  array['area','effective_state','id','label','layout_x','layout_y','seats','section_display_order',
        'section_floor_preset','section_id','section_name','section_room_frame_preset',
        'visual_material','visual_preset'],
  'kiosk_tables rows pin EXACTLY the 118 twelve keys + visual_material');
select is(
  (select array(select jsonb_object_keys(res->'floor_elements'->0) order by 1) from kt),
  array['height_norm','id','kind','label','layout_x','layout_y','orientation_quarter_turns',
        'section_id','visual_style','width_norm'],
  'kiosk fixture rows pin EXACTLY the same nine keys + visual_style');

-- ===== (53-56) kiosk safety unchanged ========================================
select is((select (res->>'ok')::boolean from kt), true, 'kiosk_tables succeeds on a live kiosk token');
select ok((select not exists (select 1 from jsonb_array_elements(res->'tables') t
             where t ? 'status' or t ? 'active_order_count' or t ? 'group_id') from kt),
  'STILL withheld from the customer: manual status / counts / groups');
select ok((select not exists (select 1 from jsonb_array_elements(res->'tables') t where t->>'label' = 'Bravo') from kt),
  'a foreign-org table is never served to the kiosk');
select is((select jsonb_array_length(res->'floor_elements') from kt), 5,
          'the tombstoned wall is excluded from the kiosk catalog (5 live fixtures)');

-- ===== (57-66) posture: SECURITY DEFINER, grants, wrappers (BOTH layers) =====
select ok(
  (select p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'set_table_visual_material'),
  'app.set_table_visual_material is SECURITY DEFINER with a pinned search_path');
select ok(
  (select p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'app' and p.proname = 'set_floor_element_style'),
  'app.set_floor_element_style is SECURITY DEFINER with a pinned search_path');
select ok(has_function_privilege('authenticated', 'app.set_table_visual_material(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute app.set_table_visual_material');
select ok(not has_function_privilege('anon', 'app.set_table_visual_material(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute app.set_table_visual_material');
select ok(has_function_privilege('authenticated', 'app.set_floor_element_style(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute app.set_floor_element_style');
select ok(not has_function_privilege('anon', 'app.set_floor_element_style(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute app.set_floor_element_style');
select ok(has_function_privilege('authenticated', 'public.set_table_visual_material(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute the public.set_table_visual_material wrapper');
select ok(not has_function_privilege('anon', 'public.set_table_visual_material(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute the public.set_table_visual_material wrapper (hardened)');
select ok(has_function_privilege('authenticated', 'public.set_floor_element_style(uuid, uuid, uuid, text)', 'execute'),
  'authenticated may execute the public.set_floor_element_style wrapper');
select ok(not has_function_privilege('anon', 'public.set_floor_element_style(uuid, uuid, uuid, text)', 'execute'),
  'anon may NOT execute the public.set_floor_element_style wrapper (hardened)');

select * from finish();
rollback;
