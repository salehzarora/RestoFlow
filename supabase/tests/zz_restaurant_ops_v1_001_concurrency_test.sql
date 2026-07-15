-- ============================================================================
-- RESTAURANT-OPERATIONS-V1-001 (review A2) — REAL two-session concurrency:
-- the availability TOCTOU race is closed by shared menu_items row locks
-- ============================================================================
-- Both app.submit_order and app.menu_set_item_availability lock the CANONICAL
-- menu_items row (submit: all distinct cart items, one statement, ascending id
-- order; setter: the one target row) BEFORE evaluating or mutating
-- availability. These scenarios run on GENUINELY SEPARATE database sessions
-- via dblink (never two sequential calls in one transaction):
--
--   A. submit locks first, holds its transaction open -> the setter BLOCKS ->
--      submit commits its accepted order -> the setter proceeds; the change
--      applies to later orders only.
--   B. the setter locks/commits 'unavailable' first -> a submit that raced in
--      BLOCKS, then re-evaluates under the lock and REFUSES item_unavailable;
--      no order is created.
--   C. two concurrent setters on one item: setter 1 holds its transaction
--      open after the production function returns -> setter 2 BLOCKS on the
--      canonical row lock, completes only after setter 1 commits, and audits
--      setter 1's COMMITTED state as its BEFORE (never a stale pre-lock read).
--
-- HARNESS NOTES: dblink sessions cannot see uncommitted fixtures, so this file
-- COMMITS its fixtures (fixed hex ids, upsert-tolerant so a re-run is safe)
-- instead of the usual begin..rollback envelope. Orders/audit rows created by
-- the scenarios use per-run identities / time-scoped assertions. The dblink
-- password matches the local test cluster default; nothing here can run
-- against hosted (local pgTAP harness only).
--
-- CLEANUP CONTRACT (why this file is named zz_*): the tail of this file
-- deletes EVERY committed 7d-prefixed fixture/scenario row it created —
-- EXCEPT its audit_events rows, which are append-only by design (D-013,
-- app.enforce_audit_append_only blocks DELETE for every role) and stay in the
-- local test db under THIS file's own 7d org only. Audit-count assertions in
-- other suites are scoped to their own fixture orgs (review delta, test
-- hygiene), so this residue is invisible to them: running this file
-- standalone and then the full suite WITHOUT a reset stays green, as does the
-- canonical `supabase db reset` + full-suite recipe. The zz_ prefix keeps the
-- one committing file at the END of the alphabetical run as extra isolation.
-- ============================================================================
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

-- ===== fixtures (COMMITTED; upsert-tolerant for re-runs) =====================
insert into organizations (id, name, slug, default_currency) values
  ('7d000000-0000-0000-0000-0000000000a0', 'Org A', 'ropsv1d-a', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name) values
  ('7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-0000000000a0', 'Rest A1')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name) values
  ('7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', 'Branch B1')
  on conflict (id) do nothing;
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7d000000-0000-0000-0000-00000000da11', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', 'pos')
  on conflict (id) do nothing;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7d000000-0000-0000-0000-00000000fa11', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-00000000da11', 'active')
  on conflict (id) do nothing;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('7d000000-0000-0000-0000-0000000005a1', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-00000000da11', '7d000000-0000-0000-0000-00000000fa11')
  on conflict (id) do nothing;
insert into app_users (id, email) values
  ('7d000000-0000-0000-0000-00000000ee03', 'ropsv1d-cashier@example.test'),
  ('7d000000-0000-0000-0000-00000000ee01', 'ropsv1d-owner@example.test')
  on conflict (id) do nothing;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7d000000-0000-0000-0000-00000000ab03', '7d000000-0000-0000-0000-00000000ee03', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('7d000000-0000-0000-0000-00000000ab01', '7d000000-0000-0000-0000-00000000ee01', '7d000000-0000-0000-0000-0000000000a0', null, null, 'org_owner')
  on conflict (id) do nothing;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7d000000-0000-0000-0000-0000000ef003', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-00000000ee03', '7d000000-0000-0000-0000-00000000ab03', 'Casey')
  on conflict (id) do nothing;
-- the PIN session must be VALID on every run: refresh its expiry on conflict.
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7d000000-0000-0000-0000-00000000c501', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000005a1', '7d000000-0000-0000-0000-0000000ef003', '7d000000-0000-0000-0000-00000000ab03', now() + interval '1 hour')
  on conflict (id) do update set expires_at = now() + interval '1 hour';
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7d000000-0000-0000-0000-00000000ca01', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', null, 'Food', 1)
  on conflict (id) do nothing;
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('7d000000-0000-0000-0000-0000000000f1', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', null, '7d000000-0000-0000-0000-00000000ca01', 'Falafel', 2500, 'ILS', 1),
  -- scenario C's own item: the setter-vs-setter chain must start from
  -- 'available', and f1 ends scenario B as 'paused'.
  ('7d000000-0000-0000-0000-0000000000f2', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', null, '7d000000-0000-0000-0000-00000000ca01', 'Shakshuka', 3800, 'ILS', 2)
  on conflict (id) do nothing;
-- start every run from a clean availability state.
delete from menu_item_branch_availability
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';

-- helpers: per-run identities (no cross-run idempotency collisions) and the
-- scenario clock floor for audit scoping.
create temp table t_ids as select
  gen_random_uuid() as order_a,
  gen_random_uuid() as order_b,
  gen_random_uuid()::text as op_a,
  gen_random_uuid()::text as op_b,
  clock_timestamp() as started_at;

-- one connection string for both sessions: THIS server, reached over the same
-- TCP address the harness used (inet_server_addr) — that address falls under
-- the cluster's scram pg_hba rule, so the password is genuinely used, which is
-- what dblink requires for a non-superuser caller (a trust path would refuse).
-- The password matches the local test cluster default (never a hosted secret).
create temp table t_conn as
  select 'host=' || host(inet_server_addr())
      || ' port=' || inet_server_port()
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres' as cs;

-- a drain helper: wait for an async query to finish, then return its ONE text
-- result (and clear the connection for reuse).
create or replace function pg_temp.drain(conn text) returns text
language plpgsql as $$
declare
  v text;
  r record;
begin
  for i in 1..200 loop
    exit when dblink_is_busy(conn) = 0;
    perform pg_sleep(0.05);
  end loop;
  for r in select * from dblink_get_result(conn) as t(x text) loop
    v := r.x;
  end loop;
  -- clear the trailing empty result set
  begin
    perform * from dblink_get_result(conn) as t(x text);
  exception when others then null;
  end;
  return v;
end;
$$;

select plan(14);

select dblink_connect('sess_a', (select cs from t_conn));
select dblink_connect('sess_b', (select cs from t_conn));
-- session B acts as the org owner for the availability setter (GUC identity).
-- (dblink_exec refuses result-returning statements, so route through dblink.)
select x from dblink('sess_b',
  'select set_config(''app.current_app_user_id'', ''7d000000-0000-0000-0000-00000000ee01'', false)')
  as t(x text);

-- ============================================================================
-- SCENARIO A — submit locks first; the setter must WAIT; the order stands.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_a_submit as
  select r::jsonb as res from dblink('sess_a', format(
    'select app.submit_order(%L, %L, %L, %L, %L, null, null, %L, null,
       jsonb_build_array(jsonb_build_object(
         ''menu_item_id'', %L, ''menu_item_name_snapshot'', ''Falafel'',
         ''quantity'', 1, ''unit_price_minor_snapshot'', 2500)),
       2500, 0, 0, 2500)::text',
    '7d000000-0000-0000-0000-00000000c501', (select order_a from t_ids),
    '7d000000-0000-0000-0000-00000000da11', (select op_a from t_ids),
    'takeaway', 'ILS', '7d000000-0000-0000-0000-0000000000f1')) as t(r text);
select is((select res->>'ok' from t_a_submit), 'true',
  'A: the submit itself is accepted inside session A''s OPEN transaction');

-- session B now tries to mark the SAME item sold out — it must block on the
-- menu_items row lock session A still holds.
select dblink_send_query('sess_b', format(
  'select app.menu_set_item_availability(%L, %L, %L, %L, %L, %L)::text',
  '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1',
  '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000000f1',
  'unavailable', 'sold_out'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'A: the availability setter BLOCKS while the submit transaction holds the item lock');

-- A commits its accepted order -> B unblocks and applies AFTER it.
select dblink_exec('sess_a', 'commit');
select is((pg_temp.drain('sess_b')::jsonb)->>'ok', 'true',
  'A: the setter proceeds after the submit commits');
select is(
  (select count(*)::int from orders where id = (select order_a from t_ids)),
  1, 'A: the order accepted BEFORE the serialized unavailability change stands');
select is(
  (select availability || '|' || reason from menu_item_branch_availability
    where organization_id = '7d000000-0000-0000-0000-0000000000a0'
      and menu_item_id = '7d000000-0000-0000-0000-0000000000f1'),
  'unavailable|sold_out',
  'A: the unavailability applies to LATER orders (state committed after)');

-- ============================================================================
-- SCENARIO B — the setter (already committed above) wins; while a SECOND
-- setter transaction holds the lock, a racing submit must WAIT and then
-- REFUSE under the serialized state.
-- ============================================================================
select dblink_exec('sess_b', 'begin');
create temp table t_b_setter as
  select r::jsonb as res from dblink('sess_b', format(
    'select app.menu_set_item_availability(%L, %L, %L, %L, %L, %L)::text',
    '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1',
    '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000000f1',
    'unavailable', 'paused')) as t(r text);
select dblink_send_query('sess_a', format(
  'select app.submit_order(%L, %L, %L, %L, %L, null, null, %L, null,
     jsonb_build_array(jsonb_build_object(
       ''menu_item_id'', %L, ''menu_item_name_snapshot'', ''Falafel'',
       ''quantity'', 1, ''unit_price_minor_snapshot'', 2500)),
     2500, 0, 0, 2500)::text',
  '7d000000-0000-0000-0000-00000000c501', (select order_b from t_ids),
  '7d000000-0000-0000-0000-00000000da11', (select op_b from t_ids),
  'takeaway', 'ILS', '7d000000-0000-0000-0000-0000000000f1'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_a'), 1,
  'B: the racing submit BLOCKS on the setter''s item lock');
select dblink_exec('sess_b', 'commit');
create temp table t_b_submit as select pg_temp.drain('sess_a')::jsonb as res;
select is(
  (select res->>'error' || '|' || (res->'items'->0->>'reason') from t_b_submit),
  'item_unavailable|paused',
  'B: after the setter serializes first, the submit re-evaluates under the lock and REFUSES');
select is(
  (select count(*)::int from orders where id = (select order_b from t_ids)),
  0, 'B: no order was created after the serialized unavailability change');

-- ============================================================================
-- SCENARIO C — GENUINE setter-vs-setter concurrency (review delta MEDIUM).
-- Setter 1 (sess_b) runs the PRODUCTION app.menu_set_item_availability inside
-- an OPEN transaction (sold_out on the fresh item f2) and HOLDS the canonical
-- menu_items FOR UPDATE lock. Setter 2 (sess_a) races the same production
-- function (paused) from a separate session: it must BLOCK, complete only
-- after setter 1 commits, and audit setter 1's COMMITTED state as its BEFORE.
-- ============================================================================
-- setter 2's session needs the same owner identity GUC the setter path checks.
select x from dblink('sess_a',
  'select set_config(''app.current_app_user_id'', ''7d000000-0000-0000-0000-00000000ee01'', false)')
  as t(x text);

-- setter 1: BEGIN + the real function; the transaction stays OPEN afterwards,
-- so the f2 row lock is retained until the explicit COMMIT below.
select dblink_exec('sess_b', 'begin');
create temp table t_c_set1 as
  select r::jsonb as res from dblink('sess_b', format(
    'select app.menu_set_item_availability(%L, %L, %L, %L, %L, %L)::text',
    '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1',
    '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000000f2',
    'unavailable', 'sold_out')) as t(r text);
select is((select res->>'ok' from t_c_set1), 'true',
  'C: setter 1 (sold_out) succeeded inside its still-OPEN transaction');

-- setter 2 races from the OTHER session and must block on the same row lock.
select dblink_send_query('sess_a', format(
  'select app.menu_set_item_availability(%L, %L, %L, %L, %L, %L)::text',
  '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1',
  '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000000f2',
  'unavailable', 'paused'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_a'), 1,
  'C: setter 2 BLOCKS while setter 1''s transaction still holds the canonical item lock');

-- setter 1 commits -> setter 2 unblocks and applies AFTER it.
select dblink_exec('sess_b', 'commit');
select is((pg_temp.drain('sess_a')::jsonb)->>'ok', 'true',
  'C: setter 2 completes only after setter 1 commits');

-- the serialized audit chain on f2: available -> sold_out -> paused, with each
-- BEFORE captured under the lock (never a stale pre-lock read).
select is(
  (select coalesce(old_values->>'availability', 'available') || '>' || (new_values->>'availability_reason')
     from audit_events
    where organization_id = '7d000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'
      and occurred_at >= (select started_at from t_ids)
      and new_values->>'menu_item_id' = '7d000000-0000-0000-0000-0000000000f2'
      and new_values->>'availability_reason' = 'sold_out'),
  'available>sold_out',
  'C: setter 1 audited BEFORE = available, AFTER = sold_out');
select is(
  (select old_values->>'availability_reason' || '>' || (new_values->>'availability_reason')
     from audit_events
    where organization_id = '7d000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'
      and occurred_at >= (select started_at from t_ids)
      and new_values->>'menu_item_id' = '7d000000-0000-0000-0000-0000000000f2'
      and new_values->>'availability_reason' = 'paused'),
  'sold_out>paused',
  'C: setter 2 audited setter 1''s COMMITTED state as its BEFORE (captured under the lock, never stale)');
select is(
  (select count(*)::int from audit_events
    where organization_id = '7d000000-0000-0000-0000-0000000000a0'
      and action = 'menu.menu_item.availability_changed'
      and occurred_at >= (select started_at from t_ids)
      and new_values->>'menu_item_id' = '7d000000-0000-0000-0000-0000000000f2'
      and coalesce(old_values->>'availability', 'available') = 'available'),
  1, 'C: exactly ONE f2 audit row of this run started from available — the serialized chain has no fork');

select dblink_disconnect('sess_a');
select dblink_disconnect('sess_b');

-- ===== CLEANUP (committed; see the header contract) ==========================
-- Every committed row this file created is removed, children before parents,
-- EXCEPT audit_events (append-only by design, D-013 — deletion is blocked by
-- app.enforce_audit_append_only for every role including the owner). Global
-- count assertions in OTHER suites (pin_sessions, organizations, orders) must
-- never see this file's fixtures.
-- The committed scenario-A order fired the RF-058 KDS hint trigger, so its
-- broadcast rows in realtime.messages are committed too — remove them (a
-- leftover well-formed hint row can MASK an emission failure in rf058's
-- bool_and/count assertions on a later non-reset run).
delete from realtime.messages
  where topic like 'kds:branch:7d000000%';
delete from menu_item_branch_availability
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_items
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_operations
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from sync_operations
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from orders
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from menu_items
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from menu_categories
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from pin_sessions
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from device_sessions
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from device_pairings
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from devices
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from employee_profiles
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from memberships
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from app_users
  where id::text like '7d000000%';
delete from branches
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from restaurants
  where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from organizations
  where id = '7d000000-0000-0000-0000-0000000000a0';

select * from finish();
