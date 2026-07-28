-- ============================================================================
-- KITCHEN-DISPATCH-ENFORCE-001 — REAL two-session concurrency for the
-- server-side dispatch-mode guard.
--
-- The guard's `direct_print` arm reads branches.kitchen_workflow_mode FOR
-- SHARE, held to transaction end. FOR SHARE conflicts with the FOR NO KEY
-- UPDATE row lock a `update branches set kitchen_workflow_mode = ...` takes,
-- so acceptance is SERIALIZED against mode changes. Only two orders are
-- possible, and both are asserted here as genuine races:
--
--   A. the submit locks first  -> it commits under the mode that was
--      authoritative for its transaction; the mode update WAITS and applies
--      strictly afterwards. A fresh direct_print is then rejected.
--   B. the mode update commits first -> the racing submit WAITS on the locked
--      read, then sees the committed 'kds' and rejects typed, with NO business
--      rows at all.
--
-- There is NO third outcome in which a direct_print op commits as newly
-- ACCEPTED on a stale printer_only read — that is what the blocking assertions
-- prove.
--
--   C. the COMMON path (absent / 'kds' dispatch) takes NO branch row lock: it
--      completes while the branch row is held exclusively by an open mode
--      update.
--   D. a race-rejected op replays its typed rejection verbatim.
--
-- HARNESS: genuinely separate sessions via dblink (the repository's accepted
-- zz_ pattern, mirroring zz_kitchen_mode_001c1_concurrency_test.sql). dblink
-- sessions cannot see uncommitted fixtures, so this file COMMITS its fixtures
-- (fixed 7d-prefixed hex ids, upsert-tolerant) and deletes them at the tail.
-- The zz_ prefix keeps committing files at the END of the alphabetical run.
-- Local pgTAP harness only; nothing here can run hosted.
-- ============================================================================
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

-- ===== fixtures (COMMITTED; upsert-tolerant for re-runs) =====================
insert into organizations (id, name, slug, default_currency) values
  ('7d000000-0000-0000-0000-0000000000a0', 'Org KDE', 'kdezz-a', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name, timezone) values
  ('7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-0000000000a0', 'Rest KDE', 'UTC')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', 'Branch KDE', 'printer_only')
  on conflict (id) do update set kitchen_workflow_mode = 'printer_only';
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('7d000000-0000-0000-0000-00000000ba11', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', 'ZZ KDE Kitchen 80', 'network', 'kitchen', '80mm', true)
  on conflict (id) do nothing;
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7d000000-0000-0000-0000-00000000da11', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', 'pos')
  on conflict (id) do nothing;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7d000000-0000-0000-0000-00000000fa11', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-00000000da11', 'active')
  on conflict (id) do nothing;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('7d000000-0000-0000-0000-0000000005a1', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-00000000da11', '7d000000-0000-0000-0000-00000000fa11', true, null)
  on conflict (id) do nothing;
insert into app_users (id, email) values
  ('7d000000-0000-0000-0000-00000000ee03', 'kdezz-cashier@example.test')
  on conflict (id) do nothing;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7d000000-0000-0000-0000-00000000ab03', '7d000000-0000-0000-0000-00000000ee03', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', 'cashier')
  on conflict (id) do nothing;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7d000000-0000-0000-0000-0000000ef003', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-00000000ee03', '7d000000-0000-0000-0000-00000000ab03', 'Casey KDE')
  on conflict (id) do nothing;
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7d000000-0000-0000-0000-00000000c501', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', '7d000000-0000-0000-0000-00000000a1b1', '7d000000-0000-0000-0000-0000000005a1', '7d000000-0000-0000-0000-0000000ef003', '7d000000-0000-0000-0000-00000000ab03', now() + interval '1 hour')
  on conflict (id) do update set expires_at = now() + interval '1 hour';
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7d000000-0000-0000-0000-00000000ca01', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', null, 'Food', 1)
  on conflict (id) do nothing;
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('7d000000-0000-0000-0000-0000000000f1', '7d000000-0000-0000-0000-0000000000a0', '7d000000-0000-0000-0000-0000000000a1', null, '7d000000-0000-0000-0000-00000000ca01', 'Falafel', 500, 'ILS', 1)
  on conflict (id) do nothing;

-- clean any previous run's operational residue BEFORE the scenarios.
delete from kitchen_print_dispatches where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_item_modifiers where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_items          where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_service_rounds where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_operations     where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from sync_operations      where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from orders               where organization_id = '7d000000-0000-0000-0000-0000000000a0';

create temp table t_conn as
  select 'host=' || host(inet_server_addr())
      || ' port=' || inet_server_port()
      || ' dbname=' || current_database()
      || ' user=postgres password=postgres' as cs;

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
  begin
    perform * from dblink_get_result(conn) as t(x text);
  exception when others then null;
  end;
  return v;
end;
$$;

-- ONE canonical order.submit text, so both sessions send byte-identical calls.
-- p_mode NULL omits the dispatch_mode key entirely (the deployed old-client shape).
create or replace function pg_temp.push_sql(p_op text, p_order text, p_mode text)
  returns text language sql as $$
  select format(
    'select app.sync_push(%L, %L, jsonb_build_array(jsonb_build_object(
       ''local_operation_id'', %L,
       ''operation_type'', ''order.submit'',
       ''target_entity'', ''order'',
       ''target_id'', %L,
       ''payload'', jsonb_build_object(
          ''order_id'', %L, ''order_type'', ''takeaway'', ''currency_code'', ''ILS'',
          ''order_items'', jsonb_build_array(jsonb_build_object(
             ''menu_item_id'', ''7d000000-0000-0000-0000-0000000000f1'', ''quantity'', 1,
             ''unit_price_minor_snapshot'', 500,
             ''menu_item_name_snapshot'', ''Falafel'', ''modifiers'', jsonb_build_array())),
          ''subtotal_minor'', 500, ''discount_total_minor'', 0,
          ''tax_total_minor'', 0, ''grand_total_minor'', 500)%s)))::text',
    '7d000000-0000-0000-0000-00000000c501', '7d000000-0000-0000-0000-00000000da11',
    p_op, p_order, p_order,
    case when p_mode is null then ''
         else format(' || jsonb_build_object(''dispatch_mode'', %L)', p_mode) end);
$$;

create or replace function pg_temp.mode_sql(p_mode text) returns text language sql as $$
  select format(
    'update public.branches set kitchen_workflow_mode = %L where id = %L',
    p_mode, '7d000000-0000-0000-0000-00000000a1b1');
$$;

select plan(12);

select dblink_connect('sess_a', (select cs from t_conn));
select dblink_connect('sess_b', (select cs from t_conn));

-- ============================================================================
-- SCENARIO A — the SUBMIT locks first; the mode update must WAIT.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_a as
  select r::jsonb as res
  from dblink('sess_a', pg_temp.push_sql('zz-kde-a', '7d000000-0000-0000-0000-00000000d0a1', 'direct_print')) as t(r text);
select is((select res #>> '{results,0,status}' from t_a), 'applied',
  'A1: session A accepts a direct_print submit on the printer_only branch (transaction still OPEN)');

select dblink_send_query('sess_b', pg_temp.mode_sql('kds'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'A2: the concurrent kitchen_workflow_mode update BLOCKS on the guard''s FOR SHARE lock');

select dblink_exec('sess_a', 'commit');
create temp table t_a_b as select pg_temp.drain('sess_b') as res;
select ok((select o.status = 'served' and o.dispatch_mode = 'direct_print'
             from orders o where o.id = '7d000000-0000-0000-0000-00000000d0a1'),
  'A3: the accepted order committed under the mode that was authoritative for ITS transaction');
select is((select kitchen_workflow_mode from branches where id = '7d000000-0000-0000-0000-00000000a1b1'), 'kds',
  'A4: the mode update applied strictly AFTER the in-flight submit committed');
create temp table t_a_fresh as
  select r::jsonb as res
  from dblink((select cs from t_conn), pg_temp.push_sql('zz-kde-a2', '7d000000-0000-0000-0000-00000000d0a2', 'direct_print')) as t(r text);
select is((select res #>> '{results,0,error}' from t_a_fresh), 'dispatch_mode_not_allowed',
  'A5: once the branch is kds, a FRESH direct_print submit is rejected');

-- ============================================================================
-- SCENARIO B — the MODE UPDATE locks first; the racing submit must WAIT, then
-- reject typed with no business rows.
-- ============================================================================
update public.branches set kitchen_workflow_mode = 'printer_only'
  where id = '7d000000-0000-0000-0000-00000000a1b1';

select dblink_exec('sess_a', 'begin');
select dblink_exec('sess_a', pg_temp.mode_sql('kds'));
select dblink_send_query('sess_b', pg_temp.push_sql('zz-kde-b', '7d000000-0000-0000-0000-00000000d0b1', 'direct_print'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'B1: the racing direct_print submit BLOCKS on the uncommitted mode change');

select dblink_exec('sess_a', 'commit');
create temp table t_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select res #>> '{results,0,error}' from t_b), 'dispatch_mode_not_allowed',
  'B2: after the flip commits, the waiting submit sees kds and rejects TYPED');
select ok(
  not exists (select 1 from orders where id = '7d000000-0000-0000-0000-00000000d0b1')
  and not exists (select 1 from order_items where order_id = '7d000000-0000-0000-0000-00000000d0b1')
  and not exists (select 1 from kitchen_print_dispatches where order_id = '7d000000-0000-0000-0000-00000000d0b1')
  and not exists (select 1 from payments where order_id = '7d000000-0000-0000-0000-00000000d0b1'),
  'B3: the race-rejected op created NO business rows at all');

-- ============================================================================
-- SCENARIO C — the COMMON path takes NO branch row lock.
-- ============================================================================
update public.branches set kitchen_workflow_mode = 'printer_only'
  where id = '7d000000-0000-0000-0000-00000000a1b1';

select dblink_exec('sess_a', 'begin');
select dblink_exec('sess_a', pg_temp.mode_sql('kds'));   -- branch row now held EXCLUSIVELY
select dblink_send_query('sess_b', pg_temp.push_sql('zz-kde-c', '7d000000-0000-0000-0000-00000000d0c1', null));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 0,
  'C1: an absent-key submit COMPLETES while the branch row is exclusively locked — the common path takes NO lock');
create temp table t_c as select pg_temp.drain('sess_b')::jsonb as res;
select is((select res #>> '{results,0,status}' from t_c), 'applied',
  'C2: and it is applied normally (no lock, no wait, no rejection)');
select dblink_exec('sess_a', 'rollback');

-- ============================================================================
-- SCENARIO D — a race-rejected op replays its typed rejection verbatim.
-- ============================================================================
create temp table t_d as
  select r::jsonb as res
  from dblink((select cs from t_conn), pg_temp.push_sql('zz-kde-b', '7d000000-0000-0000-0000-00000000d0b1', 'direct_print')) as t(r text);
select is((select res #>> '{results,0,error}' from t_d), 'dispatch_mode_not_allowed',
  'D1: replaying the race-rejected op returns the SAME typed rejection');
select is((select res #>> '{results,0,idempotency_replay}' from t_d), 'true',
  'D2: the replay is flagged idempotency_replay (rejection memory is idempotent)');

select dblink_disconnect('sess_a');
select dblink_disconnect('sess_b');

-- ===== CLEANUP (committed) ==================================================
-- Unlike zz_kitchen_mode_001c1 (which drives app.submit_order DIRECTLY and so
-- writes no sync audit), this suite pushes through app.sync_push, whose
-- rejection tail writes `sync.operation_rejected` audit rows. Some suites count
-- that action GLOBALLY rather than per-org (e.g.
-- rf056_per_operation_result_test.sql), so leaving this file's committed audit
-- residue behind would make THEM order-dependent on a re-run. These rows belong
-- to this file's own throwaway 7d org and are removed by the harness only —
-- the append-only guarantee (D-013) constrains APP roles, and nothing here runs
-- hosted.
delete from audit_events               where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from kitchen_print_dispatches where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_item_modifiers where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_items          where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_service_rounds where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from order_operations     where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from sync_operations      where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from orders               where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from menu_items           where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from menu_categories      where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from pin_sessions         where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from device_sessions      where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from device_pairings      where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from devices              where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from employee_profiles    where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from memberships          where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from app_users            where id::text like '7d000000%';
delete from printer_devices      where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from branches             where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from restaurants          where organization_id = '7d000000-0000-0000-0000-0000000000a0';
delete from organizations        where id = '7d000000-0000-0000-0000-0000000000a0';

select * from finish();
