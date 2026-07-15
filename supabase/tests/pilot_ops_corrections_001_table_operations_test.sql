-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 — pgTAP: operational table system
-- ============================================================================
-- Exercises: app.pos_set_table_status (capability, out_of_service-while-occupied
-- refusal, no_change, audit before/after); app.pos_link_tables (create/grow group,
-- same-group no_change, different-groups + out_of_service refusals); app.pos_unlink_tables
-- (dissolve, orders untouched, not-grouped no_change); the effective_state fusion +
-- group_id in app.pos_tables; the reservation-clear trigger; dispatch through
-- public.sync_push (table.status_set / table.link / table.unlink); ACLs on the new
-- tables (direct DML denied). Fixtures as BYPASSRLS; hex UUIDs (prefix 9e).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(24);

insert into organizations (id, name, slug, default_currency) values
  ('9e000000-0000-0000-0000-0000000000a0', 'Org E', 'pilottbl-a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', 'Branch B1'),
  ('9e000000-0000-0000-0000-00000000a1b2', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', 'Branch B2');
insert into app_users (id, email) values
  ('9e000000-0000-0000-0000-00000000ee03', 'pilottbl-cashier@example.test'),
  ('9e000000-0000-0000-0000-00000000ee05', 'pilottbl-denied@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('9e000000-0000-0000-0000-00000000ab03', '9e000000-0000-0000-0000-00000000ee03', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'cashier', '{}'::jsonb),
  ('9e000000-0000-0000-0000-00000000ab05', '9e000000-0000-0000-0000-00000000ee05', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'cashier', '{"manage_table_operations":"false"}'::jsonb);
insert into tables (id, organization_id, restaurant_id, branch_id, label, status) values
  ('9e000000-0000-0000-0000-0000000000d1', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'T1', 'available'),
  ('9e000000-0000-0000-0000-0000000000d2', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'T2', 'available'),
  ('9e000000-0000-0000-0000-0000000000d3', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'T3', 'available'),
  ('9e000000-0000-0000-0000-0000000000d4', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'T4', 'out_of_service'),
  ('9e000000-0000-0000-0000-0000000000d5', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'Tocc', 'available'),
  ('9e000000-0000-0000-0000-0000000000d6', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'Tres', 'reserved'),
  ('9e000000-0000-0000-0000-0000000000e2', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b2', 'B2T1', 'available');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('9e000000-0000-0000-0000-00000000da11', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('9e000000-0000-0000-0000-00000000fa11', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('9e000000-0000-0000-0000-0000000005a1', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-00000000da11', '9e000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('9e000000-0000-0000-0000-0000000ef003', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-00000000ee03', '9e000000-0000-0000-0000-00000000ab03'),
  ('9e000000-0000-0000-0000-0000000ef005', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-00000000ee05', '9e000000-0000-0000-0000-00000000ab05');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('9e000000-0000-0000-0000-00000000c503', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-0000000005a1', '9e000000-0000-0000-0000-0000000ef003', '9e000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('9e000000-0000-0000-0000-00000000c505', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-0000000005a1', '9e000000-0000-0000-0000-0000000ef005', '9e000000-0000-0000-0000-00000000ab05', now() + interval '1 hour');

-- an active dine-in order on Tocc (occupancy fixture)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code, subtotal_minor, grand_total_minor, local_operation_id, table_id, status) values
  ('9e000000-0000-0000-0000-00000000a001', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-00000000da11', '9e000000-0000-0000-0000-00000000c503', '9e000000-0000-0000-0000-0000000ef003', '9e000000-0000-0000-0000-00000000ab03', 'dine_in', 'ILS', 2500, 2500, 'seed-occ-1', '9e000000-0000-0000-0000-0000000000d5', 'submitted');

-- ===== (1-3) cashier sets a table Reserved; audit before/after ================
create temp table t1 as select app.pos_set_table_status('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d1','reserved') as res;
select is((select (res->>'ok')::boolean from t1), true, 'default-ON cashier can set a table Reserved');
select is((select status from tables where id='9e000000-0000-0000-0000-0000000000d1'), 'reserved', 'the manual status is persisted');
select is(
  (select (new_values->>'from_status') || '->' || (new_values->>'to_status') from audit_events where organization_id='9e000000-0000-0000-0000-0000000000a0' and action='table.status_set'),
  'available->reserved', 'table.status_set audits the before/after manual status');

-- ===== (4) explicitly-denied cashier is refused ==============================
select is(
  (select app.pos_set_table_status('9e000000-0000-0000-0000-00000000c505','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d2','occupied') ->> 'error'),
  'permission_denied', 'a cashier denied manage_table_operations cannot change table status');

-- ===== (5) out_of_service refused while a live dine-in order sits there =======
select is(
  (select app.pos_set_table_status('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d5','out_of_service') ->> 'error'),
  'table_in_use', 'cannot mark a table out_of_service while a live dine-in order occupies it');

-- ===== (6) no_change is idempotent ===========================================
select is(
  (select (app.pos_set_table_status('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d1','reserved') ->> 'no_change')::boolean),
  true, 'setting the same status is an idempotent no_change');

-- ===== (7-8) effective_state fusion in pos_tables ============================
create temp table tpos as select app.pos_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11') as res;
select is(
  (select e->>'effective_state' from tpos, jsonb_array_elements(res->'tables') e where e->>'id'='9e000000-0000-0000-0000-0000000000d5'),
  'occupied', 'a table with an active dine-in order reads effective_state=occupied (derived overrides manual)');
select is(
  (select e->>'effective_state' from tpos, jsonb_array_elements(res->'tables') e where e->>'id'='9e000000-0000-0000-0000-0000000000d1'),
  'reserved', 'a manually reserved table with no order reads effective_state=reserved');

-- ===== (9) reservation-clear trigger: a dine-in order on a reserved table =====
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code, subtotal_minor, grand_total_minor, local_operation_id, table_id, status) values
  ('9e000000-0000-0000-0000-00000000a002', '9e000000-0000-0000-0000-0000000000a0', '9e000000-0000-0000-0000-0000000000a1', '9e000000-0000-0000-0000-00000000a1b1', '9e000000-0000-0000-0000-00000000da11', '9e000000-0000-0000-0000-00000000c503', '9e000000-0000-0000-0000-0000000ef003', '9e000000-0000-0000-0000-00000000ab03', 'dine_in', 'ILS', 2500, 2500, 'seed-res-1', '9e000000-0000-0000-0000-0000000000d6', 'submitted');
select is((select status from tables where id='9e000000-0000-0000-0000-0000000000d6'), 'available',
  'seating a live dine-in order clears the table''s manual Reserved (trigger -> derived occupancy shows Occupied)');

-- ===== (10-12) link two tables into an operational group =====================
create temp table tl as select app.pos_link_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d1','9e000000-0000-0000-0000-0000000000d2') as res;
select is((select (res->>'ok')::boolean from tl), true, 'a cashier can link two same-branch tables');
select is((select res->>'group_label' from tl), 'T1 + T2', 'the group label is the combined member labels');
select is(
  (select count(distinct e->>'group_id')::int from app.pos_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11') res, jsonb_array_elements(res->'tables') e
    where e->>'id' in ('9e000000-0000-0000-0000-0000000000d1','9e000000-0000-0000-0000-0000000000d2') and e->>'group_id' is not null),
  1, 'both linked tables carry the SAME group_id in pos_tables');

-- ===== (13) grow the group: link a third table ===============================
select is(
  (select (app.pos_link_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d2','9e000000-0000-0000-0000-0000000000d3') ->> 'ok')::boolean),
  true, 'linking a third table grows the existing group');
select is(
  (select count(*)::int from table_group_members where organization_id='9e000000-0000-0000-0000-0000000000a0'),
  3, 'the group now has three member rows');

-- ===== (15) out_of_service cannot be linked ==================================
select is(
  (select app.pos_link_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d3','9e000000-0000-0000-0000-0000000000d4') ->> 'error'),
  'table_not_available', 'an out_of_service table cannot be linked');

-- ===== (16) cross-branch cannot be linked ====================================
select is(
  (select app.pos_link_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d3','9e000000-0000-0000-0000-0000000000e2') ->> 'error'),
  'table_not_available', 'a table in another branch cannot be linked (scope isolation)');

-- ===== (17-18) unlink dissolves the group; orders untouched ==================
create temp table tu as select app.pos_unlink_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d2') as res;
select is((select (res->>'ok')::boolean from tu), true, 'a cashier can unlink (dissolve) the group');
select is(
  (select count(*)::int from table_groups where organization_id='9e000000-0000-0000-0000-0000000000a0')
  || '|' || (select count(*)::text from orders where organization_id='9e000000-0000-0000-0000-0000000000a0'),
  '0|2', 'the group is gone AND both orders are untouched (no merge/delete)');

-- ===== (19) unlink a not-grouped table is an idempotent no_change ============
select is(
  (select (app.pos_unlink_tables('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11','9e000000-0000-0000-0000-0000000000d1') ->> 'no_change')::boolean),
  true, 'unlinking a table that is not in a group is an idempotent no_change');

-- ===== (20-21) via sync_push: table.status_set + table.link =================
create temp table tsp as select public.sync_push('9e000000-0000-0000-0000-00000000c503','9e000000-0000-0000-0000-00000000da11',
  jsonb_build_array(
    jsonb_build_object('local_operation_id','pilot-tbl-1','operation_type','table.status_set','target_entity','table','payload',jsonb_build_object('table_id','9e000000-0000-0000-0000-0000000000d3','status','occupied')),
    jsonb_build_object('local_operation_id','pilot-tbl-2','operation_type','table.link','target_entity','table','payload',jsonb_build_object('table_id_a','9e000000-0000-0000-0000-0000000000d1','table_id_b','9e000000-0000-0000-0000-0000000000d2')))) as res;
select is(
  (select r->>'status' from tsp, jsonb_array_elements(res->'results') r where r->>'local_operation_id'='pilot-tbl-1'),
  'applied', 'sync_push applies table.status_set');
select is(
  (select r->>'status' from tsp, jsonb_array_elements(res->'results') r where r->>'local_operation_id'='pilot-tbl-2'),
  'applied', 'sync_push applies table.link');

-- ===== (22-24) ACLs: direct DML on the new tables is RLS-denied + revoked ====
select is(
  (select has_table_privilege('authenticated', 'public.table_groups', 'insert')),
  false, 'authenticated has NO direct INSERT on table_groups (writes go through the RPC)');
select is(
  (select has_table_privilege('authenticated', 'public.table_group_members', 'delete')),
  false, 'authenticated has NO direct DELETE on table_group_members');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('pos_set_table_status','pos_link_tables','pos_unlink_tables')),
  0, 'the POS table RPCs have NO public wrapper (reached only via sync_push)');

select * from finish();
rollback;
