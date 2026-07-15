-- ============================================================================
-- MVP — pgTAP: `public.tables` + dining-table RPCs (DOMAIN_MODEL §5.1;
-- D-001/D-011/D-012/D-013/D-017/D-020/D-033; RISK R-003)
-- ============================================================================
-- Schema/RLS basics (enabled+forced, per-command policies, direct writes
-- denied, money-free). Manager+ management happy paths (upsert create/update,
-- idempotent replay, conflicting-reuse 42501, set_table_status, soft_delete,
-- list ordering + inactive-included/tombstone-excluded). Live-label uniqueness
-- per branch (duplicate + case-insensitive rejected; same label at ANOTHER
-- branch fine). Cashier -> permission_denied envelope + COMMITTED denial audit.
-- Non-member / cross-org -> 42501. set_table_status authorizes against the
-- ROW's actual scope (a sibling-branch manager is 42501-denied; its own branch
-- succeeds). pos_tables: paired device + valid PIN session sees ONLY its
-- branch's ACTIVE live tables (inactive/tombstoned/other-branch/other-org
-- excluded); kitchen PIN role allowed (money-free); invalid session / device
-- mismatch 42501. sync_pull: kitchen can pull `tables` (strict branch scope;
-- tombstones inline; redact_money harmless). Fixtures inserted as the
-- BYPASSRLS connection role; RPCs called as `authenticated` with the identity
-- GUC only (never the org GUC).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(52);

-- ===== fixtures: Org A (Rest A1: branches A1a, A1b, dead A1x), Org B =========
insert into organizations (id, name, slug, default_currency) values
  ('50000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpdt-a', 'USD'),
  ('50000000-0000-0000-0000-0000000000b0', 'Org B', 'mvpdt-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('50000000-0000-0000-0000-0000000000b1', '50000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name, deleted_at) values
  ('50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', 'Branch A1a', null),
  ('50000000-0000-0000-0000-00000000a1b2', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', 'Branch A1b', null),
  ('50000000-0000-0000-0000-00000000a1b3', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', 'Branch A1x (dead)', now()),
  ('50000000-0000-0000-0000-00000000b1b1', '50000000-0000-0000-0000-0000000000b0', '50000000-0000-0000-0000-0000000000b1', 'Branch B1a', null);
insert into app_users (id, email) values
  ('50000000-0000-0000-0000-00000000ee01', 'mvpdt-owner-a@example.test'),
  ('50000000-0000-0000-0000-00000000ee02', 'mvpdt-cashier@example.test'),
  ('50000000-0000-0000-0000-00000000ee03', 'mvpdt-mgr-a1b@example.test'),
  ('50000000-0000-0000-0000-00000000ee04', 'mvpdt-kitchen@example.test'),
  ('50000000-0000-0000-0000-00000000ee0b', 'mvpdt-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('50000000-0000-0000-0000-00000000ab01', '50000000-0000-0000-0000-00000000ee01', '50000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('50000000-0000-0000-0000-00000000ab02', '50000000-0000-0000-0000-00000000ee02', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('50000000-0000-0000-0000-00000000ab03', '50000000-0000-0000-0000-00000000ee03', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b2', 'manager'),
  ('50000000-0000-0000-0000-00000000ab04', '50000000-0000-0000-0000-00000000ee04', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'kitchen_staff'),
  ('50000000-0000-0000-0000-00000000ab0b', '50000000-0000-0000-0000-00000000ee0b', '50000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');

-- device + PIN plumbing at Branch A1a (POS + cashier; KDS + kitchen) ----------
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('50000000-0000-0000-0000-00000000da11', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('50000000-0000-0000-0000-00000000da22', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('50000000-0000-0000-0000-00000000fa11', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-00000000da11', 'active'),
  ('50000000-0000-0000-0000-00000000fa22', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('50000000-0000-0000-0000-0000000005a1', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-00000000da11', '50000000-0000-0000-0000-00000000fa11'),
  ('50000000-0000-0000-0000-0000000005a2', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-00000000da22', '50000000-0000-0000-0000-00000000fa22');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('50000000-0000-0000-0000-0000000ef002', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-00000000ee02', '50000000-0000-0000-0000-00000000ab02'),
  ('50000000-0000-0000-0000-0000000ef004', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-00000000ee04', '50000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-0000000005a1', '50000000-0000-0000-0000-0000000ef002', '50000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('50000000-0000-0000-0000-00000000c504', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', '50000000-0000-0000-0000-0000000005a2', '50000000-0000-0000-0000-0000000ef004', '50000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- dining-table fixtures: live/inactive/tombstoned @A1a; live @A1b; live Org B --
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, area, status, is_active, deleted_at) values
  ('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'Alpha',   4,    'Main',    'available', true,  null),
  ('50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'Bravo',   2,    'Main',    'available', false, null),
  ('50000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'Charlie', 6,    'Terrace', 'available', true,  now()),
  ('50000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b2', 'Delta',   4,    null,      'available', true,  null),
  ('50000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-0000000000b0', '50000000-0000-0000-0000-0000000000b1', '50000000-0000-0000-0000-00000000b1b1', 'Omega',   8,    null,      'available', true,  null);

-- ===== (1-5) schema / RLS basics ==============================================
select has_table('tables', 'public.tables exists (D-017 canonical name)');
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'tables'),
  'tables has RLS enabled + FORCED');
select is(
  (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname = 'tables')::int, 4,
  'tables has the four per-command policies (sel + ins/upd/del deny)');
select is(
  (select count(*) from information_schema.columns
   where table_schema = 'public' and table_name = 'tables' and column_name like '%minor%')::int, 0,
  'tables is money-free (no *_minor column; D-007 vacuously safe)');
set local role authenticated;
select throws_ok(
  $$ insert into tables (organization_id, restaurant_id, branch_id, label)
     values ('50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1', 'Rogue') $$,
  '42501', NULL, 'authenticated direct INSERT into tables is denied (writes are RPC-only)');
reset role;

-- ===== (6-10) owner: upsert CREATE + idempotent replay ========================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
create temp table t_create as select app.upsert_table(
  '50000000-0000-0000-0000-00000000c001', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
  '50000000-0000-0000-0000-000000000010', 'Echo', 4, 'Patio', true) as res;
create temp table t_replay as select app.upsert_table(
  '50000000-0000-0000-0000-00000000c001', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
  '50000000-0000-0000-0000-000000000010', 'Echo', 4, 'Patio', true) as res;
reset role;
select is((select (res->>'ok')::boolean from t_create), true, 'org_owner creates a table (ok:true)');
select is((select res->>'action' from t_create), 'created', 'upsert on a new id reports action=created');
select is((select status from tables where id = '50000000-0000-0000-0000-000000000010'), 'available',
          'a created table starts at the default floor status (available)');
select is((select (res->>'idempotent_replay')::boolean from t_replay), true,
          'replaying the SAME client_request_id returns idempotent_replay=true');
select is((select count(*) from tables where id = '50000000-0000-0000-0000-000000000010')::int, 1,
          'the idempotent replay did NOT create a second row');

-- ===== (11) conflicting reuse of a client_request_id -> 42501 ================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_table(
       '50000000-0000-0000-0000-00000000c001', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
       '50000000-0000-0000-0000-000000000010', 'DIFFERENT LABEL', 4, 'Patio', true) $$,
  '42501', NULL, 'reusing a client_request_id with DIFFERENT input raises 42501');
reset role;

-- ===== (12-13) owner: upsert UPDATE ===========================================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
create temp table t_update as select app.upsert_table(
  '50000000-0000-0000-0000-00000000c002', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
  '50000000-0000-0000-0000-000000000010', 'Echo Prime', 6, 'Patio', true) as res;
reset role;
select is((select res->>'action' from t_update), 'updated', 'upsert on an existing id reports action=updated');
select ok(
  (select label = 'Echo Prime' and seats = 6 from tables where id = '50000000-0000-0000-0000-000000000010'),
  'the update actually replaced label + seats');

-- ===== (14-16) live-label uniqueness per branch ===============================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_table(
       '50000000-0000-0000-0000-00000000c003', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
       null, 'Alpha', 2, null, true) $$,
  '23505', NULL, 'a duplicate LIVE label at the same branch is rejected (unique_violation)');
select throws_ok(
  $$ select app.upsert_table(
       '50000000-0000-0000-0000-00000000c004', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
       null, 'ALPHA', 2, null, true) $$,
  '23505', NULL, 'label uniqueness is case-insensitive (lower(label) partial index)');
create temp table t_other_branch as select app.upsert_table(
  '50000000-0000-0000-0000-00000000c005', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b2',
  '50000000-0000-0000-0000-000000000011', 'Alpha', 4, null, true) as res;
reset role;
select is((select res->>'action' from t_other_branch), 'created',
          'the SAME label at a DIFFERENT branch is fine (uniqueness is per branch)');

-- ===== (17) dead-branch target is structurally rejected =======================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_table(
       '50000000-0000-0000-0000-00000000c006', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b3',
       null, 'Ghost', 2, null, true) $$,
  '42501', NULL, 'creating a table on a soft-deleted branch is rejected (42501)');
reset role;

-- ===== (18-21) set_table_status happy path + validation =======================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
create temp table t_status as select app.set_table_status(
  '50000000-0000-0000-0000-00000000c007', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-000000000010', 'occupied') as res;
create temp table t_status_replay as select app.set_table_status(
  '50000000-0000-0000-0000-00000000c007', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-000000000010', 'occupied') as res;
select throws_ok(
  $$ select app.set_table_status(
       '50000000-0000-0000-0000-00000000c008', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-000000000010', 'exploded') $$,
  '42501', NULL, 'an unknown status value is rejected (42501)');
reset role;
select ok((select (res->>'ok')::boolean and res->>'status' = 'occupied' from t_status),
          'set_table_status returns ok + the new status');
select is((select status from tables where id = '50000000-0000-0000-0000-000000000010'), 'occupied',
          'the row status actually changed (any -> any transition allowed)');
select is((select (res->>'idempotent_replay')::boolean from t_status_replay), true,
          'set_table_status replays idempotently on the same client_request_id');

-- ===== (22-24) soft_delete_table ==============================================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
create temp table t_delete as select app.soft_delete_table(
  '50000000-0000-0000-0000-00000000c009', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-000000000010') as res;
select throws_ok(
  $$ select app.soft_delete_table(
       '50000000-0000-0000-0000-00000000c00a', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-000000000010') $$,
  '42501', NULL, 're-deleting an already-tombstoned table raises not-found 42501');
reset role;
select ok((select (res->>'ok')::boolean and res->>'action' = 'deleted' from t_delete),
          'soft_delete_table returns ok + action=deleted');
select ok((select deleted_at is not null from tables where id = '50000000-0000-0000-0000-000000000010'),
          'the row is tombstoned (deleted_at set, never physically deleted — D-020)');

-- ===== (25-29) list_tables: management view ===================================
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';
create temp table t_list as select app.list_tables(
  '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1', null) as res;
create temp table t_list_branch as select app.list_tables(
  '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1',
  '50000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select is((select (res->>'ok')::boolean from t_list), true, 'org_owner lists tables (ok:true)');
select ok(
  (select exists (select 1 from t_list, jsonb_array_elements(res->'tables') e
                  where e->>'label' = 'Bravo' and (e->>'is_active')::boolean = false)),
  'an INACTIVE table IS listed (management view shows disabled entries)');
select ok(
  (select not exists (select 1 from t_list, jsonb_array_elements(res->'tables') e
                      where e->>'label' in ('Charlie', 'Echo Prime'))),
  'tombstoned tables are NOT listed (fixture + RPC-deleted both excluded)');
select is((select res->'tables'->0->>'label' from t_list), 'Alpha', 'tables are ordered by label');
select ok(
  (select not exists (select 1 from t_list_branch, jsonb_array_elements(res->'tables') e
                      where e->>'label' = 'Delta')),
  'the branch filter narrows the list (Branch A1b table excluded)');

-- ===== (30-33) role denial: in-scope cashier -> permission_denied + audit =====
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee02';
create temp table t_cashier_upsert as select app.upsert_table(
  '50000000-0000-0000-0000-00000000c00b', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
  null, 'Cashier Table', 2, null, true) as res;
create temp table t_cashier_status as select app.set_table_status(
  '50000000-0000-0000-0000-00000000c00c', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-000000000001', 'reserved') as res;
-- the cashier covers ONLY its branch (downward-only coverage): a branch-null,
-- restaurant-wide list would be rank 0 -> 42501; the ROLE denial needs its own branch.
create temp table t_cashier_list as select app.list_tables(
  '50000000-0000-0000-0000-0000000000a0', '50000000-0000-0000-0000-0000000000a1',
  '50000000-0000-0000-0000-00000000a1b1') as res;
reset role;
select is((select res->>'error' from t_cashier_upsert), 'permission_denied',
          'an in-scope cashier upsert is role-denied (permission_denied envelope, not 42501)');
select is(
  (select count(*) from audit_events where action = 'table.upsert_denied'
     and actor_app_user_id = '50000000-0000-0000-0000-00000000ee02')::int, 1,
  'the cashier denial wrote the COMMITTED table.upsert_denied audit row');
select is((select res->>'error' from t_cashier_status), 'permission_denied',
          'an in-scope cashier set_table_status is role-denied');
select is((select res->>'error' from t_cashier_list), 'permission_denied',
          'an in-scope cashier cannot list tables (management view is manager+)');

-- ===== (34-36) non-member / cross-org -> 42501 (fail closed, R-003) ===========
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee0b';  -- Org B owner
select throws_ok(
  $$ select app.upsert_table(
       '50000000-0000-0000-0000-00000000c00d', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-0000000000a1', '50000000-0000-0000-0000-00000000a1b1',
       null, 'Intruder', 2, null, true) $$,
  '42501', NULL, 'an Org B owner cannot create a table in Org A (42501)');
select throws_ok(
  $$ select app.set_table_status(
       '50000000-0000-0000-0000-00000000c00e', '50000000-0000-0000-0000-0000000000b0',
       '50000000-0000-0000-0000-000000000001', 'occupied') $$,
  '42501', NULL, 'an Org A table id under an Org B organization_id is cross-org rejected (42501)');
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee01';  -- Org A owner
select throws_ok(
  $$ select app.list_tables('50000000-0000-0000-0000-0000000000b0', '50000000-0000-0000-0000-0000000000b1', null) $$,
  '42501', NULL, 'an Org A owner cannot list Org B tables (cross-org 42501)');
reset role;

-- ===== (37-38) set_table_status authorizes against the ROW's OWN scope ========
set local role authenticated;
set local app.current_app_user_id = '50000000-0000-0000-0000-00000000ee03';  -- manager scoped to Branch A1b
select throws_ok(
  $$ select app.set_table_status(
       '50000000-0000-0000-0000-00000000c00f', '50000000-0000-0000-0000-0000000000a0',
       '50000000-0000-0000-0000-000000000001', 'occupied') $$,
  '42501', NULL, 'a Branch-A1b manager cannot set status on a Branch-A1a table (row-scope 42501)');
create temp table t_mgr_own as select app.set_table_status(
  '50000000-0000-0000-0000-00000000c010', '50000000-0000-0000-0000-0000000000a0',
  '50000000-0000-0000-0000-000000000004', 'reserved') as res;
reset role;
select ok((select (res->>'ok')::boolean and res->>'status' = 'reserved' from t_mgr_own),
          'the SAME manager CAN set status on its OWN branch''s table (positive control)');

-- ===== (39-46) pos_tables: session-derived device read ========================
select ok(
  (select (m->>'ok')::boolean and m->>'entity' = 'tables'
   from (select app.pos_tables('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-00000000da11') as m) s),
  'cashier pos_tables returns ok:true, entity=tables');
select is(
  jsonb_array_length(app.pos_tables('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-00000000da11') -> 'tables'),
  1, 'the session branch has exactly ONE live active table (inactive/tombstoned/other-branch/other-org excluded)');
select is(
  (select count(*) from (select jsonb_object_keys(
     app.pos_tables('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-00000000da11') -> 'tables' -> 0) as k) s)::int,
  6, 'a pos_tables row carries exactly the six keys {id,label,seats,area,status,active_order_count}');
select ok(
  (select r->>'label' = 'Alpha' and (r->>'seats')::int = 4 and r->>'area' = 'Main' and r->>'status' = 'available'
   from (select app.pos_tables('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-00000000da11') -> 'tables' -> 0 as r) s),
  'the visible table is Alpha with seats/area/status');
select ok(
  not exists (
    select 1 from jsonb_array_elements(app.pos_tables('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-00000000da11') -> 'tables') e
    where e->>'label' in ('Bravo', 'Charlie', 'Delta', 'Omega')),
  'inactive (Bravo), tombstoned (Charlie), other-branch (Delta) and other-org (Omega) tables are all excluded');
select is(
  (app.pos_tables('50000000-0000-0000-0000-00000000c504', '50000000-0000-0000-0000-00000000da22') -> 'tables' -> 0 ->> 'label'),
  'Alpha', 'a KITCHEN PIN session also reads the floor map (money-free; all PIN roles allowed)');
select throws_ok(
  $$ select app.pos_tables('50000000-0000-0000-0000-0000000000ff', '50000000-0000-0000-0000-00000000da11') $$,
  '42501', NULL, 'a non-existent PIN session is rejected fail-closed (42501)');
select throws_ok(
  $$ select app.pos_tables('50000000-0000-0000-0000-00000000c501', '50000000-0000-0000-0000-00000000da22') $$,
  '42501', NULL, 'a device_id not matching the PIN session device is rejected (42501)');

-- ===== (47-50) sync_pull: the `tables` entity reaches devices =================
select is(
  (app.sync_pull('50000000-0000-0000-0000-00000000c504', '50000000-0000-0000-0000-00000000da22',
                 array['tables'], '{}'::jsonb, 500) ->> 'ok')::boolean,
  true, 'kitchen_staff CAN pull the tables entity (money-free; KDS maps orders.table_id -> label)');
select ok(
  exists (
    select 1 from jsonb_array_elements(
      app.sync_pull('50000000-0000-0000-0000-00000000c504', '50000000-0000-0000-0000-00000000da22',
                    array['tables'], '{}'::jsonb, 500) -> 'changes' -> 'tables' -> 'rows') r
    where r->>'id' = '50000000-0000-0000-0000-000000000001' and r ? 'label'),
  'the kitchen pull returns the branch table WITH its label (redact_money is a harmless no-op)');
select ok(
  exists (
    select 1 from jsonb_array_elements(
      app.sync_pull('50000000-0000-0000-0000-00000000c504', '50000000-0000-0000-0000-00000000da22',
                    array['tables'], '{}'::jsonb, 500) -> 'changes' -> 'tables' -> 'rows') r
    where r->>'id' = '50000000-0000-0000-0000-000000000003' and (r->>'deleted_at') is not null),
  'the sync feed INCLUDES the tombstoned table (deleted_at inline — D-020; unlike pos_tables)');
select ok(
  not exists (
    select 1 from jsonb_array_elements(
      app.sync_pull('50000000-0000-0000-0000-00000000c504', '50000000-0000-0000-0000-00000000da22',
                    array['tables'], '{}'::jsonb, 500) -> 'changes' -> 'tables' -> 'rows') r
    where r->>'id' in ('50000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-000000000005')),
  'the pull is STRICTLY branch-scoped (other-branch and other-org tables never appear)');

-- ===== (51-52) wrapper posture ================================================
select ok(
  (select not prosecdef from pg_proc where proname = 'pos_tables' and pronamespace = 'public'::regnamespace)
  and has_function_privilege('authenticated', 'public.pos_tables(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.pos_tables(uuid, uuid)', 'execute')
  and not has_function_privilege('public', 'public.pos_tables(uuid, uuid)', 'execute'),
  'public.pos_tables is SECURITY INVOKER, authenticated-only (never anon/PUBLIC)');
select ok(
  (select prosecdef from pg_proc where proname = 'upsert_table' and pronamespace = 'app'::regnamespace)
  and has_function_privilege('authenticated', 'public.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.list_tables(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.list_tables(uuid, uuid, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.set_table_status(uuid, uuid, uuid, text)', 'execute')
  and has_function_privilege('authenticated', 'public.soft_delete_table(uuid, uuid, uuid)', 'execute'),
  'app.upsert_table is SECURITY DEFINER; all four public management wrappers are authenticated-only');

select * from finish();
rollback;
