-- ============================================================================
-- TABLE-FLOOR-MAP-POLISH-027 — pgTAP: visual-only floor fixtures
-- (D-001/D-011/D-012/D-013/D-017/D-020; RISK R-003)
-- ============================================================================
-- Schema/RLS for table_floor_elements; the structural geometry contract (kind
-- whitelist, 0..10000 coordinates, footprint bounds, orientation 0..3, labels
-- only on cashier/door, same-branch composite section FK); upsert_floor_element
-- (per-kind defaults, wall/window-only resize, fixed-size refusal, label/kind/
-- section immutability, ledger idempotency, conflicting reuse, denial audits,
-- cross-org 42501); delete_floor_element (target-row-first, tombstone, replay,
-- denial audit); soft_delete_table_section now TOMBSTONES the section's
-- fixtures (tables still only detached; elements_removed audited); pos_tables /
-- list_tables gain the ADDITIVE `floor_elements` envelope catalog while the
-- per-table ROW shape stays byte-identical (older suites pin it). SECURITY
-- DEFINER/search_path/grant posture for both new functions; the tables +
-- table_sections policy sets are untouched.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(54);

-- ===== fixtures: Org A (Rest A1: branches A1a, A1b), Org B ===================
insert into organizations (id, name, slug, default_currency) values
  ('61000000-0000-0000-0000-0000000000a0', 'Org A', 'tfe-a', 'USD'),
  ('61000000-0000-0000-0000-0000000000b0', 'Org B', 'tfe-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('61000000-0000-0000-0000-0000000000b1', '61000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('61000000-0000-0000-0000-00000000a1b2', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('61000000-0000-0000-0000-00000000b1b1', '61000000-0000-0000-0000-0000000000b0', '61000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('61000000-0000-0000-0000-00000000ee01', 'tfe-owner-a@example.test'),
  ('61000000-0000-0000-0000-00000000ee02', 'tfe-cashier@example.test'),
  ('61000000-0000-0000-0000-00000000ee0b', 'tfe-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('61000000-0000-0000-0000-00000000ab01', '61000000-0000-0000-0000-00000000ee01', '61000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('61000000-0000-0000-0000-00000000ab02', '61000000-0000-0000-0000-00000000ee02', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('61000000-0000-0000-0000-00000000ab0b', '61000000-0000-0000-0000-00000000ee0b', '61000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');

-- device + PIN plumbing at Branch A1a (POS + cashier) for pos_tables ----------
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('61000000-0000-0000-0000-00000000da11', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('61000000-0000-0000-0000-00000000fa11', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('61000000-0000-0000-0000-0000000005a1', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000da11', '61000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('61000000-0000-0000-0000-0000000ef002', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ee02', '61000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('61000000-0000-0000-0000-00000000c501', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-0000000005a1', '61000000-0000-0000-0000-0000000ef002', '61000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- sections: two live @A1a, one live @A1b; one placed table @A1a ---------------
insert into table_sections (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('61000000-0000-0000-0000-00000000ec01', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', 'Main Hall', 0),
  ('61000000-0000-0000-0000-00000000ec02', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', 'Terrace',   1),
  ('61000000-0000-0000-0000-00000000ec03', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b2', 'B-Side',    0);
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, area, section_id, layout_x, layout_y) values
  ('61000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', 'Alpha', 4, 'Main',
   '61000000-0000-0000-0000-00000000ec01', 2500, 7500);

-- ===== (1-5) schema / RLS basics =============================================
select has_table('table_floor_elements', 'public.table_floor_elements exists');
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'table_floor_elements'),
  'table_floor_elements has RLS enabled + FORCED');
select is(
  (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname = 'table_floor_elements')::int, 4,
  'table_floor_elements has the four per-command policies (sel + ins/upd/del deny)');
select is(
  (select count(*) from information_schema.columns
   where table_schema = 'public' and table_name = 'table_floor_elements' and column_name like '%minor%')::int, 0,
  'table_floor_elements is money-free (no *_minor column; D-007 vacuously safe)');
set local role authenticated;
select throws_ok(
  $$ insert into table_floor_elements (organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm)
     values ('61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ec01', 'wall', 0, 0, 3000, 150) $$,
  '42501', NULL, 'authenticated direct INSERT into table_floor_elements is denied (writes are RPC-only)');
reset role;

-- ===== (6-10) the structural geometry contract ===============================
select throws_ok(
  $$ insert into table_floor_elements (organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm)
     values ('61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ec01', 'sofa', 0, 0, 900, 900) $$,
  '23514', NULL, 'an unknown fixture kind violates the kind CHECK');
select throws_ok(
  $$ insert into table_floor_elements (organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm, label)
     values ('61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ec01', 'plant', 0, 0, 900, 900, 'Fern') $$,
  '23514', NULL, 'a label on a non-cashier/door kind violates the label CHECK');
select throws_ok(
  $$ insert into table_floor_elements (organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm)
     values ('61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ec01', 'wall', 0, 0, 50, 150) $$,
  '23514', NULL, 'a footprint below 100 units violates the width bound CHECK');
select throws_ok(
  $$ insert into table_floor_elements (organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm, orientation_quarter_turns)
     values ('61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ec01', 'wall', 0, 0, 3000, 150, 4) $$,
  '23514', NULL, 'orientation_quarter_turns above 3 violates the orientation CHECK');
select throws_ok(
  $$ insert into table_floor_elements (organization_id, restaurant_id, branch_id, section_id, kind, layout_x, layout_y, width_norm, height_norm)
     values ('61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1', '61000000-0000-0000-0000-00000000ec03', 'wall', 0, 0, 3000, 150) $$,
  '23503', NULL, 'a section from ANOTHER branch violates the composite same-branch FK');

-- ===== (11-17) upsert_floor_element: create/defaults/replay/conflict =========
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
create temp table e_wall as select app.upsert_floor_element(
  '61000000-0000-0000-0000-00000000c001', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
  '61000000-0000-0000-0000-00000000ec01', 'wall',
  '61000000-0000-0000-0000-00000000fe01', 100, 9000) as res;
create temp table e_replay as select app.upsert_floor_element(
  '61000000-0000-0000-0000-00000000c001', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
  '61000000-0000-0000-0000-00000000ec01', 'wall',
  '61000000-0000-0000-0000-00000000fe01', 100, 9000) as res;
reset role;
select is((select (res->>'ok')::boolean from e_wall), true, 'org_owner creates a wall fixture (ok:true)');
select is((select res->>'action' from e_wall), 'created', 'fixture upsert on a new id reports action=created');
select is(
  (select (width_norm, height_norm, orientation_quarter_turns)
     from table_floor_elements where id = '61000000-0000-0000-0000-00000000fe01'),
  (3000, 150, 0), 'an unspecified footprint takes the per-kind default (wall 3000x150, orient 0)');
select is((select (res->>'idempotent_replay')::boolean from e_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c001', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'wall',
       '61000000-0000-0000-0000-00000000fe01', 200, 9000) $$,
  '42501', NULL, 'reusing a client_request_id with DIFFERENT input raises 42501');
create temp table e_door as select app.upsert_floor_element(
  '61000000-0000-0000-0000-00000000c002', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
  '61000000-0000-0000-0000-00000000ec01', 'door',
  '61000000-0000-0000-0000-00000000fe02', 4500, 0, null, null, 2, '  Front door  ') as res;
reset role;
select is((select (res->>'ok')::boolean from e_door), true, 'a door with a label is created');
select is(
  (select (label, width_norm, height_norm, orientation_quarter_turns) = ('Front door', 900, 150, 2)
     from table_floor_elements where id = '61000000-0000-0000-0000-00000000fe02'),
  true, 'the door label is TRIMMED and the fixed 900x150 default applies');

-- ===== (18-24) per-kind policy + immutability (42501s) =======================
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c003', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'cashier', null, 5000, 5000, 1000, 900) $$,
  '42501', NULL, 'an explicit non-default size on a FIXED-SIZE kind (cashier) is refused, never corrected');
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c004', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'wall', null, 5000, 5000, null, null, 0, 'North wall') $$,
  '42501', NULL, 'a label on a wall is refused (labels exist only on cashier/door)');
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c005', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'window',
       '61000000-0000-0000-0000-00000000fe01', 100, 9000) $$,
  '42501', NULL, 'kind is IMMUTABLE on update (delete + recreate to change it)');
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c006', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec02', 'wall',
       '61000000-0000-0000-0000-00000000fe01', 100, 9000) $$,
  '42501', NULL, 'section is IMMUTABLE on update (delete + recreate to move sections)');
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c007', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'sofa', null, 0, 0) $$,
  '42501', NULL, 'an unknown kind raises 42501 before any write');
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c008', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'wall', null, 100, null) $$,
  '42501', NULL, 'a missing coordinate raises 42501 (both are required)');
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c009', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-0000000dead0', 'wall', null, 0, 0) $$,
  '42501', NULL, 'an unknown/tombstoned section raises 42501');
reset role;

-- ===== (25-27) wall resize (allowed) is audited as updated ===================
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
create temp table e_resize as select app.upsert_floor_element(
  '61000000-0000-0000-0000-00000000c00a', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
  '61000000-0000-0000-0000-00000000ec01', 'wall',
  '61000000-0000-0000-0000-00000000fe01', 100, 9000, 5000, 150) as res;
reset role;
select is((select (res->>'ok')::boolean and (res->>'action') = 'updated' from e_resize), true,
          'a wall RESIZE succeeds as action=updated (wall/window are resizable)');
select is((select width_norm from table_floor_elements where id = '61000000-0000-0000-0000-00000000fe01'),
          5000, 'the resized wall width is stored');
select is(
  (select count(*) from audit_events
   where organization_id = '61000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.updated')::int, 1,
  'the resize is audited exactly once (floor_element.updated)');

-- ===== (28-31) denials: cashier audit envelope; cross-org 42501 ==============
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee02';
create temp table e_cashier as select app.upsert_floor_element(
  '61000000-0000-0000-0000-00000000c00b', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
  '61000000-0000-0000-0000-00000000ec01', 'plant', null, 8000, 8000) as res;
reset role;
select is((select res->>'error' from e_cashier), 'permission_denied',
          'an in-scope cashier gets the permission_denied envelope');
select is(
  (select count(*) from audit_events
   where organization_id = '61000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.upsert_denied')::int, 1,
  'the cashier denial is a COMMITTED floor_element.upsert_denied audit');
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.upsert_floor_element(
       '61000000-0000-0000-0000-00000000c00c', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
       '61000000-0000-0000-0000-00000000ec01', 'wall', null, 0, 0) $$,
  '42501', NULL, 'an Org-B owner writing into Org A raises 42501 (no covering membership)');
reset role;
select is(
  (select count(*) from audit_events
   where organization_id = '61000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.created')::int, 2,
  'exactly the wall + door creations were audited (floor_element.created)');

-- ===== (32-37) delete_floor_element ==========================================
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee02';
create temp table d_cashier as select app.delete_floor_element(
  '61000000-0000-0000-0000-00000000c00d', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-00000000fe02') as res;
reset role;
select is((select res->>'error' from d_cashier), 'permission_denied',
          'an in-scope cashier delete gets the permission_denied envelope');
select is(
  (select count(*) from audit_events
   where organization_id = '61000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.delete_denied')::int, 1,
  'the cashier delete denial is a COMMITTED floor_element.delete_denied audit');
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
create temp table d_door as select app.delete_floor_element(
  '61000000-0000-0000-0000-00000000c00e', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-00000000fe02') as res;
create temp table d_replay as select app.delete_floor_element(
  '61000000-0000-0000-0000-00000000c00e', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-00000000fe02') as res;
select throws_ok(
  $$ select app.delete_floor_element(
       '61000000-0000-0000-0000-00000000c00f', '61000000-0000-0000-0000-0000000000a0',
       '61000000-0000-0000-0000-00000000fe02') $$,
  '42501', NULL, 'a FRESH delete of an already-tombstoned fixture raises 42501 (target-row-first)');
reset role;
select is((select (res->>'ok')::boolean and (res->>'action') = 'deleted' from d_door), true,
          'the owner tombstones the door fixture');
select is((select (res->>'idempotent_replay')::boolean from d_replay), true,
          'replaying the SAME delete request id returns idempotent_replay=true');
select is(
  (select count(*) from audit_events
   where organization_id = '61000000-0000-0000-0000-0000000000a0'
     and action = 'floor_element.deleted')::int, 1,
  'the tombstone is audited exactly once (floor_element.deleted)');

-- ===== (38-41) pos_tables: additive envelope, UNCHANGED row shape ============
set local role authenticated;
create temp table pos_read as select app.pos_tables(
  '61000000-0000-0000-0000-00000000c501', '61000000-0000-0000-0000-00000000da11') as res;
reset role;
select is(
  (select jsonb_array_length(res->'floor_elements') from pos_read), 1,
  'pos_tables gains floor_elements with exactly the branch''s LIVE fixtures (the wall)');
select is(
  (select array(select jsonb_object_keys(res->'floor_elements'->0) order by 1) from pos_read),
  array['height_norm','id','kind','label','layout_x','layout_y','orientation_quarter_turns',
        'section_id','width_norm'],
  'floor_elements rows pin EXACTLY the nine fixture keys');
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from pos_read),
  array['active_order_count','area','effective_state','group_id','id','label','layout_x',
        'layout_y','seats','section_display_order','section_floor_preset','section_id','section_name',
        'status','visual_preset'],
  'the per-TABLE row shape is the 021 thirteen keys + the two TABLE-VISUAL-LAYOUT-118 presentation keys');
select is(
  (select (res->'floor_elements'->0->>'kind', res->'floor_elements'->0->>'layout_x',
           res->'floor_elements'->0->>'width_norm') = ('wall', '100', '5000') from pos_read),
  true, 'the fixture row carries kind + coordinates + the resized footprint');

-- ===== (42-44) list_tables: additive envelope, branch scoping ================
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
create temp table list_read as select app.list_tables(
  '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1',
  '61000000-0000-0000-0000-00000000a1b1') as res;
create temp table list_read_b as select app.list_tables(
  '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1',
  '61000000-0000-0000-0000-00000000a1b2') as res;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee02';
create temp table list_cashier as select app.list_tables(
  '61000000-0000-0000-0000-0000000000a0', '61000000-0000-0000-0000-0000000000a1',
  '61000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select is(
  (select jsonb_array_length(res->'floor_elements') from list_read), 1,
  'list_tables gains floor_elements for the requested branch (the wall)');
select is(
  (select jsonb_array_length(res->'floor_elements') from list_read_b), 0,
  'the branch filter scopes fixtures (sibling branch A1b has none)');
select ok(
  (select (res->>'error') = 'permission_denied' and not (res ? 'floor_elements') from list_cashier),
  'a cashier still gets the bare permission_denied envelope (no fixture leak)');

-- ===== (45-49) section soft-delete TOMBSTONES its fixtures ===================
set local role authenticated;
set local app.current_app_user_id = '61000000-0000-0000-0000-00000000ee01';
create temp table e_terrace as select app.upsert_floor_element(
  '61000000-0000-0000-0000-00000000c010', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-0000000000a1', '61000000-0000-0000-0000-00000000a1b1',
  '61000000-0000-0000-0000-00000000ec02', 'window',
  '61000000-0000-0000-0000-00000000fe03', 2000, 0) as res;
create temp table d_sec as select app.soft_delete_table_section(
  '61000000-0000-0000-0000-00000000c011', '61000000-0000-0000-0000-0000000000a0',
  '61000000-0000-0000-0000-00000000ec02') as res;
reset role;
select is((select (res->>'ok')::boolean from e_terrace), true, 'a window fixture lands on the Terrace');
select is((select (res->>'ok')::boolean from d_sec), true, 'owner soft-deletes the Terrace section');
select ok(
  (select deleted_at is not null from table_floor_elements where id = '61000000-0000-0000-0000-00000000fe03'),
  'the section''s fixture is TOMBSTONED with it (never orphaned)');
select is(
  (select (new_values->>'elements_removed')::int from audit_events
   where organization_id = '61000000-0000-0000-0000-0000000000a0'
     and action = 'table_section.deleted'), 1,
  'the section-delete audit reports elements_removed=1 (and tables_detached stays present)');
set local role authenticated;
create temp table pos_read2 as select app.pos_tables(
  '61000000-0000-0000-0000-00000000c501', '61000000-0000-0000-0000-00000000da11') as res;
reset role;
select is(
  (select (jsonb_array_length(res->'floor_elements'), res->'floor_elements'->0->>'id')
     = (1, '61000000-0000-0000-0000-00000000fe01') from pos_read2),
  true, 'pos_tables now serves ONLY the surviving Main Hall wall (tombstones excluded)');

-- ===== (50-54) function posture + no unrelated policy changes ================
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('upsert_floor_element', 'delete_floor_element')
     and p.prosecdef
     and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')::int, 2,
  'both new app functions are SECURITY DEFINER with a pinned search_path');
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('upsert_floor_element', 'delete_floor_element')
     and has_function_privilege('anon', p.oid, 'execute'))::int, 0,
  'anon can execute NEITHER of the two new app functions');
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('upsert_floor_element', 'delete_floor_element')
     and has_function_privilege('anon', p.oid, 'execute'))::int, 0,
  'anon can execute NEITHER of the two public wrappers');
select ok(
  has_function_privilege('authenticated', 'public.delete_floor_element(uuid, uuid, uuid)', 'execute'),
  'the public wrappers are executable by authenticated (spot check)');
select is(
  (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname in ('tables', 'table_sections'))::int, 8,
  'the tables + table_sections policy sets are UNTOUCHED (still four each)');

select * from finish();
rollback;
