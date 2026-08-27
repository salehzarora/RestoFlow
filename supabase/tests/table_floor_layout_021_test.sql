-- ============================================================================
-- TABLE-FLOOR-LAYOUT-021 — pgTAP: table_sections + freeform table layout
-- (D-001/D-011/D-012/D-013/D-017/D-020/D-033; RISK R-003)
-- ============================================================================
-- Schema/RLS for the new catalog; the structural coordinate contract (both-or-
-- neither, 0..10000, section required, same-branch FK); section upsert/rename
-- (append display_order, live-name uniqueness, ledger idempotency, conflicting
-- reuse, denial audits, cross-org 42501); set_table_section (same-branch only,
-- target-row-first auth, clears placement on change); set_table_layout_position
-- (bounds, sectionless refusal, audited, no-change idempotent WITHOUT audit,
-- replay); stale app.upsert_table can NOT erase layout; section soft-delete
-- DETACHES tables (never deletes them); reorder_table_sections (complete live
-- set only, cashier denied); pos_tables / list_tables row shapes pin EVERY
-- existing + new key, legacy null-section rows stay readable, and list_tables
-- gains the `sections` catalog. SECURITY DEFINER/search_path/grant posture for
-- all five new functions; the `tables` policy set is untouched.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(54);

-- ===== fixtures: Org A (Rest A1: branches A1a, A1b), Org B ===================
insert into organizations (id, name, slug, default_currency) values
  ('60000000-0000-0000-0000-0000000000a0', 'Org A', 'tfl-a', 'USD'),
  ('60000000-0000-0000-0000-0000000000b0', 'Org B', 'tfl-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('60000000-0000-0000-0000-0000000000b1', '60000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('60000000-0000-0000-0000-00000000a1b2', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('60000000-0000-0000-0000-00000000b1b1', '60000000-0000-0000-0000-0000000000b0', '60000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('60000000-0000-0000-0000-00000000ee01', 'tfl-owner-a@example.test'),
  ('60000000-0000-0000-0000-00000000ee02', 'tfl-cashier@example.test'),
  ('60000000-0000-0000-0000-00000000ee03', 'tfl-mgr-a1b@example.test'),
  ('60000000-0000-0000-0000-00000000ee0b', 'tfl-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('60000000-0000-0000-0000-00000000ab01', '60000000-0000-0000-0000-00000000ee01', '60000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('60000000-0000-0000-0000-00000000ab02', '60000000-0000-0000-0000-00000000ee02', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('60000000-0000-0000-0000-00000000ab03', '60000000-0000-0000-0000-00000000ee03', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b2', 'manager'),
  ('60000000-0000-0000-0000-00000000ab0b', '60000000-0000-0000-0000-00000000ee0b', '60000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');

-- device + PIN plumbing at Branch A1a (POS + cashier) for pos_tables ----------
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('60000000-0000-0000-0000-00000000da11', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('60000000-0000-0000-0000-00000000fa11', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('60000000-0000-0000-0000-0000000005a1', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000da11', '60000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('60000000-0000-0000-0000-0000000ef002', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-00000000ee02', '60000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('60000000-0000-0000-0000-00000000c501', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', '60000000-0000-0000-0000-0000000005a1', '60000000-0000-0000-0000-0000000ef002', '60000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- sections: two live @A1a, one live @A1b, one EMPTY live @A1a -----------------
insert into table_sections (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('60000000-0000-0000-0000-00000000ec01', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'Main Hall', 0),
  ('60000000-0000-0000-0000-00000000ec02', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'Terrace',   1),
  ('60000000-0000-0000-0000-00000000ec03', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b2', 'B-Side',    0);

-- tables: placed @A1a, legacy null-section @A1a, sectionless @A1b -------------
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, area, section_id, layout_x, layout_y) values
  ('60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'Alpha', 4, 'Main',
   '60000000-0000-0000-0000-00000000ec01', 2500, 7500),
  ('60000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'Bravo', 2, 'Legacy corner',
   null, null, null),
  ('60000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b2', 'Delta', 4, null,
   null, null, null),
  -- Zulu stays UNTOUCHED by every RPC test: the permanent legacy row proving
  -- null-section rows remain readable (sorts last by label).
  ('60000000-0000-0000-0000-000000000004', '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'Zulu', 2, 'Old corner',
   null, null, null);

-- ===== (1-6) schema / RLS basics =============================================
select has_table('table_sections', 'public.table_sections exists');
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'table_sections'),
  'table_sections has RLS enabled + FORCED');
select is(
  (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname = 'table_sections')::int, 4,
  'table_sections has the four per-command policies (sel + ins/upd/del deny)');
select is(
  (select count(*) from information_schema.columns
   where table_schema = 'public' and table_name = 'table_sections' and column_name like '%minor%')::int, 0,
  'table_sections is money-free (no *_minor column; D-007 vacuously safe)');
select ok(
  (select count(*) = 3 from information_schema.columns
   where table_schema = 'public' and table_name = 'tables'
     and column_name in ('section_id', 'layout_x', 'layout_y')),
  'tables gained exactly section_id + layout_x + layout_y');
set local role authenticated;
select throws_ok(
  $$ insert into table_sections (organization_id, restaurant_id, branch_id, name)
     values ('60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1', 'Rogue') $$,
  '42501', NULL, 'authenticated direct INSERT into table_sections is denied (writes are RPC-only)');
reset role;

-- ===== (7-10) the structural coordinate contract =============================
select throws_ok(
  $$ update tables set layout_x = 100 where id = '60000000-0000-0000-0000-000000000002' $$,
  '23514', NULL, 'one coordinate without the other violates tables_layout_xy_together');
select throws_ok(
  $$ update tables set layout_x = 10001, layout_y = 0 where id = '60000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'layout_x above 10000 violates the range check');
select throws_ok(
  $$ update tables set layout_x = 1, layout_y = 1 where id = '60000000-0000-0000-0000-000000000002' $$,
  '23514', NULL, 'coordinates on a sectionless table violate tables_layout_requires_section');
select throws_ok(
  $$ update tables set section_id = '60000000-0000-0000-0000-00000000ec03'
     where id = '60000000-0000-0000-0000-000000000001' $$,
  '23503', NULL, 'a section from ANOTHER branch violates the composite same-branch FK');

-- ===== (11-15) upsert_table_section: create/append/replay/conflict ===========
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table s_create as select app.upsert_table_section(
  '60000000-0000-0000-0000-00000000c001', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
  '60000000-0000-0000-0000-00000000ec04', 'Garden', true) as res;
create temp table s_replay as select app.upsert_table_section(
  '60000000-0000-0000-0000-00000000c001', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
  '60000000-0000-0000-0000-00000000ec04', 'Garden', true) as res;
reset role;
select is((select (res->>'ok')::boolean from s_create), true, 'org_owner creates a section (ok:true)');
select is((select res->>'action' from s_create), 'created', 'section upsert on a new id reports action=created');
select is((select display_order from table_sections where id = '60000000-0000-0000-0000-00000000ec04'), 2,
          'a created section APPENDS after the live siblings (max+1 = 2)');
select is((select (res->>'idempotent_replay')::boolean from s_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_table_section(
       '60000000-0000-0000-0000-00000000c001', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
       '60000000-0000-0000-0000-00000000ec04', 'DIFFERENT NAME', true) $$,
  '42501', NULL, 'reusing a client_request_id with DIFFERENT input raises 42501');
reset role;

-- ===== (16-17) live-name uniqueness per branch ===============================
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_table_section(
       '60000000-0000-0000-0000-00000000c002', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
       null, 'main hall', true) $$,
  '23505', NULL, 'a duplicate LIVE section name in the branch (case-insensitive) is rejected');
create temp table s_other_branch as select app.upsert_table_section(
  '60000000-0000-0000-0000-00000000c003', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b2',
  null, 'Main Hall', true) as res;
reset role;
select is((select (res->>'ok')::boolean from s_other_branch), true,
          'the SAME name at ANOTHER branch is fine (uniqueness is per branch)');

-- ===== (18-20) denials: cashier audit envelope; cross-org 42501 ==============
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee02';
create temp table s_cashier as select app.upsert_table_section(
  '60000000-0000-0000-0000-00000000c004', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
  null, 'Cashier Wing', true) as res;
reset role;
select is((select res->>'error' from s_cashier), 'permission_denied',
          'an in-scope cashier gets the permission_denied envelope');
select is(
  (select count(*) from audit_events
   where organization_id = '60000000-0000-0000-0000-0000000000a0'
     and action = 'table_section.upsert_denied')::int, 1,
  'the cashier denial is a COMMITTED table_section.upsert_denied audit');
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee0b';
select throws_ok(
  $$ select app.upsert_table_section(
       '60000000-0000-0000-0000-00000000c005', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
       null, 'Foreign Wing', true) $$,
  '42501', NULL, 'an Org-B owner writing into Org A raises 42501 (no covering membership)');
reset role;

-- ===== (21-24) set_table_section =============================================
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table a_assign as select app.set_table_section(
  '60000000-0000-0000-0000-00000000c006', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-00000000ec01') as res;
reset role;
select is((select (res->>'ok')::boolean from a_assign), true, 'owner assigns the legacy table to a section');
select is((select section_id from tables where id = '60000000-0000-0000-0000-000000000002'),
          '60000000-0000-0000-0000-00000000ec01'::uuid, 'the assignment is stored');
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.set_table_section(
       '60000000-0000-0000-0000-00000000c007', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-00000000ec03') $$,
  '42501', NULL, 'assigning a section from ANOTHER branch raises 42501');
select throws_ok(
  $$ select app.set_table_section(
       '60000000-0000-0000-0000-00000000c008', '60000000-0000-0000-0000-0000000000b0',
       '60000000-0000-0000-0000-000000000001', null) $$,
  '42501', NULL, 'a mismatched organization_id on the target table raises 42501');
reset role;

-- ===== (25) sibling-branch manager: rank 0 at the table's ACTUAL scope =======
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee03';
select throws_ok(
  $$ select app.set_table_section(
       '60000000-0000-0000-0000-00000000c009', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-000000000001', null) $$,
  '42501', NULL, 'a SIBLING-branch manager has no covering membership -> 42501 (target-row-first)');
reset role;

-- ===== (26-31) set_table_layout_position =====================================
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table p_place as select app.set_table_layout_position(
  '60000000-0000-0000-0000-00000000c00a', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-000000000002', 5000, 5000) as res;
create temp table p_replay as select app.set_table_layout_position(
  '60000000-0000-0000-0000-00000000c00a', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-000000000002', 5000, 5000) as res;
reset role;
select is((select (res->>'ok')::boolean from p_place), true, 'owner places the table at (5000,5000)');
select is(
  (select count(*) from audit_events
   where organization_id = '60000000-0000-0000-0000-0000000000a0'
     and action = 'table.layout_moved')::int, 1,
  'the placement is audited exactly once (table.layout_moved)');
select is((select (res->>'idempotent_replay')::boolean from p_replay), true,
          'replaying the SAME placement request id returns idempotent_replay=true');
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
-- a FRESH request id with the SAME coordinates: idempotent success, NO new audit
create temp table p_nochange as select app.set_table_layout_position(
  '60000000-0000-0000-0000-00000000c00b', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-000000000002', 5000, 5000) as res;
select throws_ok(
  $$ select app.set_table_layout_position(
       '60000000-0000-0000-0000-00000000c00c', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-000000000002', 7000, null) $$,
  '42501', NULL, 'one coordinate without the other raises 42501');
select throws_ok(
  $$ select app.set_table_layout_position(
       '60000000-0000-0000-0000-00000000c00d', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-000000000002', 10001, 5) $$,
  '42501', NULL, 'an out-of-range coordinate raises 42501');
select throws_ok(
  $$ select app.set_table_layout_position(
       '60000000-0000-0000-0000-00000000c00e', '60000000-0000-0000-0000-0000000000a0',
       '60000000-0000-0000-0000-000000000003', 5, 5) $$,
  '42501', NULL, 'placing a SECTIONLESS table raises 42501 (assign a section first)');
reset role;
select is((select (res->>'ok')::boolean from p_nochange), true,
          'a no-change placement is an idempotent success');
select is(
  (select count(*) from audit_events
   where organization_id = '60000000-0000-0000-0000-0000000000a0'
     and action = 'table.layout_moved')::int, 1,
  'the no-change placement wrote NO second audit row');

-- ===== (32-33) stale full-replace upsert_table can NOT erase layout ==========
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table u_stale as select app.upsert_table(
  '60000000-0000-0000-0000-00000000c00f', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-0000000000a1', '60000000-0000-0000-0000-00000000a1b1',
  '60000000-0000-0000-0000-000000000002', 'Bravo', 2, 'Legacy corner', true) as res;
reset role;
select is((select (res->>'ok')::boolean from u_stale), true,
          'a legacy-shaped upsert_table call still succeeds');
select is(
  (select (section_id, layout_x, layout_y) = ('60000000-0000-0000-0000-00000000ec01'::uuid, 5000, 5000)
     from tables where id = '60000000-0000-0000-0000-000000000002'),
  true, 'the stale upsert did NOT erase section_id or layout coordinates');

-- ===== (34-37) pos_tables row shape ==========================================
set local role authenticated;
create temp table pos_read as select app.pos_tables(
  '60000000-0000-0000-0000-00000000c501', '60000000-0000-0000-0000-00000000da11') as res;
reset role;
select is(
  (select array(select jsonb_object_keys(res->'tables'->0) order by 1) from pos_read),
  array['active_order_count','area','effective_state','group_id','id','label','layout_x',
        'layout_y','seats','section_display_order','section_floor_preset','section_id','section_name',
        'section_room_frame_preset','status','visual_material','visual_preset'],
  'pos_tables rows pin EXACTLY the eight existing + five new keys (+ the 118/120 presentation keys)');
select is(
  (select res->'tables'->0->>'label' from pos_read), 'Alpha',
  'pos_tables still orders by label (Alpha first)');
select is(
  (select (res->'tables'->0->>'section_name', res->'tables'->0->>'layout_x', res->'tables'->0->>'layout_y')
     = ('Main Hall', '2500', '7500') from pos_read),
  true, 'the placed table carries section_name + normalized coordinates');
select is(
  (select (res->'tables'->2->'section_id', res->'tables'->2->'layout_x')
     = ('null'::jsonb, 'null'::jsonb) from pos_read),
  true, 'the legacy null-section row (Zulu) stays readable with null section/layout keys');

-- ===== (38-40) list_tables: row keys + sections catalog ======================
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table list_read as select app.list_tables(
  '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1',
  '60000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select ok(
  (select (res->'tables'->0) ?& array['id','label','seats','area','status','is_active','branch_id',
     'active_order_count','effective_state','group_id','section_id','section_name',
     'section_display_order','layout_x','layout_y'] from list_read),
  'list_tables rows carry every existing key PLUS the five new layout keys');
select ok(
  (select (res ? 'sections') and jsonb_array_length(res->'sections') >= 3 from list_read),
  'list_tables gains the sections catalog (incl. the EMPTY Garden section)');
select is(
  (select res->'sections'->0->>'name' from list_read), 'Main Hall',
  'the sections catalog is display-ordered (Main Hall first)');

-- ===== (41-44) soft_delete_table_section DETACHES, never deletes =============
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table d_sec as select app.soft_delete_table_section(
  '60000000-0000-0000-0000-00000000c010', '60000000-0000-0000-0000-0000000000a0',
  '60000000-0000-0000-0000-00000000ec01') as res;
reset role;
select is((select (res->>'ok')::boolean from d_sec), true, 'owner soft-deletes a section');
select ok(
  (select deleted_at is not null from table_sections where id = '60000000-0000-0000-0000-00000000ec01'),
  'the section is TOMBSTONED (deleted_at set), not physically removed');
select is(
  (select count(*) from tables
   where id in ('60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002')
     and deleted_at is null)::int, 2,
  'the section''s tables are NOT deleted — both remain live');
select is(
  (select count(*) from tables
   where section_id is null and layout_x is null and layout_y is null
     and id in ('60000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000002'))::int, 2,
  'both tables were DETACHED (section + placement cleared -> legacy fallback)');

-- ===== (45-48) reorder_table_sections ========================================
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee01';
create temp table r_ok as select app.reorder_table_sections(
  '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1',
  '60000000-0000-0000-0000-00000000a1b1',
  array['60000000-0000-0000-0000-00000000ec04', '60000000-0000-0000-0000-00000000ec02']::uuid[]) as res;
select throws_ok(
  $$ select app.reorder_table_sections(
       '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1',
       '60000000-0000-0000-0000-00000000a1b1',
       array['60000000-0000-0000-0000-00000000ec02']::uuid[]) $$,
  '42501', NULL, 'a PARTIAL id list (not the complete live set) raises 42501');
reset role;
select is((select (res->>'ok')::boolean from r_ok), true, 'owner reorders the complete live set');
select is(
  (select (s2.display_order, s4.display_order) = (1, 0)
     from table_sections s2, table_sections s4
     where s2.id = '60000000-0000-0000-0000-00000000ec02'
       and s4.id = '60000000-0000-0000-0000-00000000ec04'),
  true, 'display_order matches the submitted order (Garden 0, Terrace 1)');
set local role authenticated;
set local app.current_app_user_id = '60000000-0000-0000-0000-00000000ee02';
create temp table r_cashier as select app.reorder_table_sections(
  '60000000-0000-0000-0000-0000000000a0', '60000000-0000-0000-0000-0000000000a1',
  '60000000-0000-0000-0000-00000000a1b1',
  array['60000000-0000-0000-0000-00000000ec04', '60000000-0000-0000-0000-00000000ec02']::uuid[]) as res;
reset role;
select is((select res->>'error' from r_cashier), 'permission_denied',
          'an in-scope cashier reorder gets the permission_denied envelope');

-- ===== (49-52) function posture + no unrelated policy changes ================
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('upsert_table_section', 'soft_delete_table_section',
                       'set_table_section', 'set_table_layout_position',
                       'reorder_table_sections')
     and p.prosecdef
     and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')::int, 5,
  'all five new app functions are SECURITY DEFINER with a pinned search_path');
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('upsert_table_section', 'soft_delete_table_section',
                       'set_table_section', 'set_table_layout_position',
                       'reorder_table_sections')
     and has_function_privilege('anon', p.oid, 'execute'))::int, 0,
  'anon can execute NONE of the five new app functions');
select is(
  (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname = 'tables')::int, 4,
  'the tables policy set is UNTOUCHED (still exactly four policies)');
select ok(
  has_function_privilege('authenticated', 'public.set_table_layout_position(uuid, uuid, uuid, integer, integer)', 'execute'),
  'the public wrappers are executable by authenticated (spot check)');

select * from finish();
rollback;
