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
--   A. the submit locks first  -> the mode update WAITS for it. The submit is
--      accepted INSIDE its own open transaction under the mode that is
--      authoritative for that transaction.
--   B. the mode update commits first -> the racing submit WAITS on the locked
--      read, then sees the committed 'kds' and rejects typed, with NO business
--      rows.
--
-- There is NO third outcome in which a direct_print op commits as newly
-- ACCEPTED on a stale printer_only read — that is what the blocking assertions
-- prove.
--
--   C. the COMMON path (absent / 'kds' dispatch) takes NO branch row lock: it
--      completes while the branch row is held exclusively by an open mode
--      update.
--
-- RESIDUE DISCIPLINE (why every remote session runs in an explicit transaction)
-- ---------------------------------------------------------------------------
-- `public.audit_events` is APPEND-ONLY: `app.enforce_audit_append_only()`
-- raises on DELETE/UPDATE, and that guard must never be bypassed or disabled.
-- app.sync_push legitimately writes audit rows on BOTH the accepted path
-- (order.status_updated) and the rejection path (sync.operation_rejected), so a
-- suite that COMMITTED its sync_push calls could never clean up after itself —
-- and suites that count an audit action globally (e.g.
-- rf056_per_operation_result_test.sql) would become order-dependent.
--
-- The fix is transaction OWNERSHIP, not deletion: every dblink session that
-- calls app.sync_push runs inside an explicit `begin` and is ROLLED BACK after
-- its assertions, so its orders / items / dispatches / sync_operations / audit
-- rows are never committed and there is nothing to delete. Only the inert
-- FIXTURE rows are committed (dblink sessions cannot see uncommitted fixtures)
-- and they are removed by id at the tail. The blocking proofs are unaffected:
-- row locks are held for the life of the transaction whether it commits or
-- rolls back.
--
-- Fixture namespace `7f…` is unique to this suite (7c = psc_001c, 7d =
-- restaurant_ops_v1, 7e = kitchen_mode_001c1); no id is shared with any other
-- test, and cleanup only ever names this suite's own ids.
--
-- HARNESS: genuinely separate sessions via dblink (the repository's accepted
-- zz_ pattern). The zz_ prefix keeps committing files at the END of the
-- alphabetical run. Local pgTAP harness only; nothing here can run hosted.
-- ============================================================================
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

-- ===== fixtures (COMMITTED — dblink cannot see uncommitted rows) =============
insert into organizations (id, name, slug, default_currency) values
  ('7f000000-0000-0000-0000-0000000000a0', 'Org KDE 7f', 'kde-enforce-7f', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name, timezone) values
  ('7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-0000000000a0', 'Rest KDE', 'UTC')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('7f000000-0000-0000-0000-00000000a1b1', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', 'Branch KDE', 'printer_only')
  on conflict (id) do update set kitchen_workflow_mode = 'printer_only';
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('7f000000-0000-0000-0000-00000000ba11', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', 'ZZ KDE Kitchen 80', 'network', 'kitchen', '80mm', true)
  on conflict (id) do nothing;
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7f000000-0000-0000-0000-00000000da11', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', 'pos')
  on conflict (id) do nothing;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7f000000-0000-0000-0000-00000000fa11', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', '7f000000-0000-0000-0000-00000000da11', 'active')
  on conflict (id) do nothing;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('7f000000-0000-0000-0000-0000000005a1', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', '7f000000-0000-0000-0000-00000000da11', '7f000000-0000-0000-0000-00000000fa11', true, null)
  on conflict (id) do nothing;
insert into app_users (id, email) values
  ('7f000000-0000-0000-0000-00000000ee03', 'kdezz-cashier@example.test')
  on conflict (id) do nothing;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7f000000-0000-0000-0000-00000000ab03', '7f000000-0000-0000-0000-00000000ee03', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', 'cashier')
  on conflict (id) do nothing;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7f000000-0000-0000-0000-0000000ef003', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', '7f000000-0000-0000-0000-00000000ee03', '7f000000-0000-0000-0000-00000000ab03', 'Casey KDE')
  on conflict (id) do nothing;
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7f000000-0000-0000-0000-00000000c501', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', '7f000000-0000-0000-0000-00000000a1b1', '7f000000-0000-0000-0000-0000000005a1', '7f000000-0000-0000-0000-0000000ef003', '7f000000-0000-0000-0000-00000000ab03', now() + interval '1 hour')
  on conflict (id) do update set expires_at = now() + interval '1 hour';
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7f000000-0000-0000-0000-00000000ca01', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', null, 'Food', 1)
  on conflict (id) do nothing;
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('7f000000-0000-0000-0000-0000000000f1', '7f000000-0000-0000-0000-0000000000a0', '7f000000-0000-0000-0000-0000000000a1', null, '7f000000-0000-0000-0000-00000000ca01', 'Falafel', 500, 'ILS', 1)
  on conflict (id) do nothing;

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
             ''menu_item_id'', ''7f000000-0000-0000-0000-0000000000f1'', ''quantity'', 1,
             ''unit_price_minor_snapshot'', 500,
             ''menu_item_name_snapshot'', ''Falafel'', ''modifiers'', jsonb_build_array())),
          ''subtotal_minor'', 500, ''discount_total_minor'', 0,
          ''tax_total_minor'', 0, ''grand_total_minor'', 500)%s)))::text',
    '7f000000-0000-0000-0000-00000000c501', '7f000000-0000-0000-0000-00000000da11',
    p_op, p_order, p_order,
    case when p_mode is null then ''
         else format(' || jsonb_build_object(''dispatch_mode'', %L)', p_mode) end);
$$;

create or replace function pg_temp.mode_sql(p_mode text) returns text language sql as $$
  select format(
    'update public.branches set kitchen_workflow_mode = %L where id = %L',
    p_mode, '7f000000-0000-0000-0000-00000000a1b1');
$$;

select plan(13);

select dblink_connect('sess_a', (select cs from t_conn));
select dblink_connect('sess_b', (select cs from t_conn));

-- ============================================================================
-- SCENARIO A — the SUBMIT locks first; the mode update must WAIT.
-- sess_a stays in an explicit transaction and is ROLLED BACK, so its accepted
-- order and its audit rows are never committed.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_a as
  select r::jsonb as res
  from dblink('sess_a', pg_temp.push_sql('zz-kde-a', '7f000000-0000-0000-0000-00000000d0a1', 'direct_print')) as t(r text);
select is((select res #>> '{results,0,status}' from t_a), 'applied',
  'A1: session A ACCEPTS a direct_print submit on the printer_only branch inside its OPEN transaction');
select is((select res #>> '{results,0,order_status}' from t_a), 'served',
  'A2: it was accepted under the mode authoritative for ITS transaction (served)');

select dblink_send_query('sess_b', pg_temp.mode_sql('kds'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'A3: the concurrent kitchen_workflow_mode update BLOCKS on the guard''s FOR SHARE lock');

-- Roll the accepted submit back: the LOCK proof is already made, and nothing it
-- wrote (order, items, dispatch, ledger, audit) may survive into the shared DB.
select dblink_exec('sess_a', 'rollback');
create temp table t_a_b as select pg_temp.drain('sess_b') as res;
select is((select kitchen_workflow_mode from branches where id = '7f000000-0000-0000-0000-00000000a1b1'), 'kds',
  'A4: the blocked mode update proceeds the instant the submit''s transaction ends');
select ok(not exists (select 1 from orders where id = '7f000000-0000-0000-0000-00000000d0a1'),
  'A5: the rolled-back submit committed NO order (residue-free by construction)');

-- ============================================================================
-- SCENARIO B — the MODE UPDATE commits first; the racing submit must WAIT,
-- then reject typed with no business rows.
-- ============================================================================
update public.branches set kitchen_workflow_mode = 'printer_only'
  where id = '7f000000-0000-0000-0000-00000000a1b1';

select dblink_exec('sess_a', 'begin');
select dblink_exec('sess_a', pg_temp.mode_sql('kds'));
select dblink_exec('sess_b', 'begin');
select dblink_send_query('sess_b', pg_temp.push_sql('zz-kde-b', '7f000000-0000-0000-0000-00000000d0b1', 'direct_print'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'B1: the racing direct_print submit BLOCKS on the uncommitted mode change');

select dblink_exec('sess_a', 'commit');
create temp table t_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select res #>> '{results,0,error}' from t_b), 'dispatch_mode_not_allowed',
  'B2: after the flip commits, the waiting submit sees kds and rejects TYPED');
select is((select res #>> '{results,0,status}' from t_b), 'rejected',
  'B3: the racing op is rejected, never accepted on the stale printer_only read');
select dblink_exec('sess_b', 'rollback');
select ok(
  not exists (select 1 from orders where id = '7f000000-0000-0000-0000-00000000d0b1')
  and not exists (select 1 from order_items where order_id = '7f000000-0000-0000-0000-00000000d0b1')
  and not exists (select 1 from kitchen_print_dispatches where order_id = '7f000000-0000-0000-0000-00000000d0b1')
  and not exists (select 1 from payments where order_id = '7f000000-0000-0000-0000-00000000d0b1'),
  'B4: the race-rejected op left NO business rows at all');

-- ============================================================================
-- SCENARIO C — the COMMON path takes NO branch row lock.
-- ============================================================================
update public.branches set kitchen_workflow_mode = 'printer_only'
  where id = '7f000000-0000-0000-0000-00000000a1b1';

select dblink_exec('sess_a', 'begin');
select dblink_exec('sess_a', pg_temp.mode_sql('kds'));   -- branch row now held EXCLUSIVELY
select dblink_exec('sess_b', 'begin');
select dblink_send_query('sess_b', pg_temp.push_sql('zz-kde-c', '7f000000-0000-0000-0000-00000000d0c1', null));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 0,
  'C1: an absent-key submit COMPLETES while the branch row is exclusively locked — the common path takes NO lock');
create temp table t_c as select pg_temp.drain('sess_b')::jsonb as res;
select is((select res #>> '{results,0,status}' from t_c), 'applied',
  'C2: and it is applied normally (no lock, no wait, no rejection)');
select dblink_exec('sess_b', 'rollback');
select dblink_exec('sess_a', 'rollback');

select dblink_disconnect('sess_a');
select dblink_disconnect('sess_b');

-- ===== RESIDUE PROOF (before cleanup) =======================================
-- Every remote business transaction was rolled back, so this suite must have
-- committed NOTHING beyond its inert fixtures — in particular NO audit rows,
-- which are append-only and could never be removed.
select is(
  (select count(*)::int from audit_events
    where organization_id = '7f000000-0000-0000-0000-0000000000a0'),
  0,
  'R1: this suite committed ZERO audit_events (nothing to delete from an append-only table)');
select is(
  (select (select count(*) from orders           where organization_id = '7f000000-0000-0000-0000-0000000000a0')
        + (select count(*) from order_items      where organization_id = '7f000000-0000-0000-0000-0000000000a0')
        + (select count(*) from sync_operations  where organization_id = '7f000000-0000-0000-0000-0000000000a0')
        + (select count(*) from kitchen_print_dispatches where organization_id = '7f000000-0000-0000-0000-0000000000a0')
        + (select count(*) from payments         where organization_id = '7f000000-0000-0000-0000-0000000000a0'))::int,
  0,
  'R2: and ZERO committed business rows — the shared full-suite database is left clean');

-- ===== CLEANUP: this suite's OWN fixture ids only, by equality ===============
-- No prefix/LIKE matching, no other suite's rows, and NOTHING against the
-- append-only audit_events table.
delete from menu_items       where id = '7f000000-0000-0000-0000-0000000000f1';
delete from menu_categories  where id = '7f000000-0000-0000-0000-00000000ca01';
delete from pin_sessions     where id = '7f000000-0000-0000-0000-00000000c501';
delete from employee_profiles where id = '7f000000-0000-0000-0000-0000000ef003';
delete from memberships      where id = '7f000000-0000-0000-0000-00000000ab03';
delete from app_users        where id = '7f000000-0000-0000-0000-00000000ee03';
delete from device_sessions  where id = '7f000000-0000-0000-0000-0000000005a1';
delete from device_pairings  where id = '7f000000-0000-0000-0000-00000000fa11';
delete from devices          where id = '7f000000-0000-0000-0000-00000000da11';
delete from printer_devices  where id = '7f000000-0000-0000-0000-00000000ba11';
delete from branches         where id = '7f000000-0000-0000-0000-00000000a1b1';
delete from restaurants      where id = '7f000000-0000-0000-0000-0000000000a1';
delete from organizations    where id = '7f000000-0000-0000-0000-0000000000a0';

select * from finish();
