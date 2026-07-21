-- ============================================================================
-- KITCHEN-MODE-001C1 — REAL two-session concurrency for the kitchen dispatch
-- ledger: dispatch creation is TRANSACTIONAL with its order mutation, and the
-- pull claim is ATOMIC, so neither a duplicate submit nor a two-device pull
-- race can ever fork the ledger or double-serve a ticket.
-- ============================================================================
-- Scenarios (genuinely separate database sessions via dblink — the
-- repository's accepted zz_ harness; never two sequential calls in one
-- transaction):
--
--   V. transactional visibility + duplicate-submit race. Session A submits a
--      printer-only order inside an OPEN transaction; a concurrent puller
--      sees NEITHER the order NOR its dispatch (no partial state is ever
--      visible — the dispatch exists exactly iff the order does). Session B
--      races the SAME submit (same order id + local_operation_id): it BLOCKS
--      on the ledger identity and, after A commits, fails with the unique
--      violation (23505) — the pre-existing submit contract; the POS outbox
--      treats it as retryable and the sequential retry converges on the
--      stored idempotent replay. EXACTLY ONE order and ONE initial dispatch
--      survive the race.
--   C. two READY POS devices race the claim-and-pull for the same dispatch.
--      Device 1 claims inside an open transaction; device 2 BLOCKS on the
--      row lock (inner FOR UPDATE), then re-proves claimability after the
--      winner's commit and converges on an EMPTY ok envelope — exactly ONE
--      winner, no error, no double-claim, a ~10-minute lease for the winner
--      alone.
--
-- HARNESS NOTES: dblink sessions cannot see uncommitted fixtures, so this
-- file COMMITS its fixtures (fixed 7e-prefixed hex ids, upsert-tolerant) and
-- deletes them at the tail (append-only audit_events excepted — they stay
-- under THIS file's own 7e org only; other suites scope their audit counts to
-- their own orgs). The zz_ prefix keeps committing files at the END of the
-- alphabetical run. Local pgTAP harness only; nothing here can run hosted.
-- ============================================================================
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

-- ===== fixtures (COMMITTED; upsert-tolerant for re-runs) =====================
insert into organizations (id, name, slug, default_currency) values
  ('7e000000-0000-0000-0000-0000000000a0', 'Org KC', 'kmc1zz-a', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name) values
  ('7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-0000000000a0', 'Rest KC1')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode) values
  ('7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', 'Branch KC1', 'printer_only')
  on conflict (id) do nothing;
-- KITCHEN-MODE-001C3B1A: readiness now requires a stable, valid kitchen 80mm
-- assignment; both devices report against this one.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('7e000000-0000-0000-0000-00000000ba11', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', 'ZZ Kitchen 80', 'network', 'kitchen', '80mm', true)
  on conflict (id) do nothing;
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7e000000-0000-0000-0000-00000000da11', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('7e000000-0000-0000-0000-00000000da22', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', 'pos')
  on conflict (id) do nothing;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7e000000-0000-0000-0000-00000000fa11', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-00000000da11', 'active'),
  ('7e000000-0000-0000-0000-00000000fa22', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-00000000da22', 'active')
  on conflict (id) do nothing;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('7e000000-0000-0000-0000-0000000005a1', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-00000000da11', '7e000000-0000-0000-0000-00000000fa11', app.hash_provisioning_secret('tok-zz-c1-1'), true, null),
  ('7e000000-0000-0000-0000-0000000005a2', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-00000000da22', '7e000000-0000-0000-0000-00000000fa22', app.hash_provisioning_secret('tok-zz-c1-2'), true, null)
  on conflict (id) do nothing;
insert into app_users (id, email) values
  ('7e000000-0000-0000-0000-00000000ee03', 'kmc1zz-cashier@example.test')
  on conflict (id) do nothing;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7e000000-0000-0000-0000-00000000ab03', '7e000000-0000-0000-0000-00000000ee03', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', 'cashier')
  on conflict (id) do nothing;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7e000000-0000-0000-0000-0000000ef003', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-00000000ee03', '7e000000-0000-0000-0000-00000000ab03', 'Casey')
  on conflict (id) do nothing;
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7e000000-0000-0000-0000-00000000c501', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', '7e000000-0000-0000-0000-00000000a1b1', '7e000000-0000-0000-0000-0000000005a1', '7e000000-0000-0000-0000-0000000ef003', '7e000000-0000-0000-0000-00000000ab03', now() + interval '1 hour')
  on conflict (id) do update set expires_at = now() + interval '1 hour';
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7e000000-0000-0000-0000-00000000ca01', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', null, 'Food', 1)
  on conflict (id) do nothing;
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('7e000000-0000-0000-0000-0000000000f1', '7e000000-0000-0000-0000-0000000000a0', '7e000000-0000-0000-0000-0000000000a1', null, '7e000000-0000-0000-0000-00000000ca01', 'Falafel', 500, 'ILS', 1)
  on conflict (id) do nothing;
-- clean any previous run's operational residue BEFORE the scenarios.
delete from kitchen_print_dispatches           where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from kitchen_printer_readiness_reports  where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_item_modifiers where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_items          where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_service_rounds where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_operations     where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from sync_operations      where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from orders               where organization_id = '7e000000-0000-0000-0000-0000000000a0';

-- per-run identities.
create temp table t_ids as select
  gen_random_uuid() as order_x,
  gen_random_uuid()::text as op_submit,
  clock_timestamp() as started_at;

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

-- like drain(), but a remote ERROR is expected: returns 'ERR:<sqlstate>'.
create or replace function pg_temp.drain_err(conn text) returns text
language plpgsql as $$
declare
  v text;
  r record;
begin
  for i in 1..200 loop
    exit when dblink_is_busy(conn) = 0;
    perform pg_sleep(0.05);
  end loop;
  begin
    for r in select * from dblink_get_result(conn) as t(x text) loop
      v := r.x;
    end loop;
  exception when others then
    v := 'ERR:' || SQLSTATE;
  end;
  begin
    perform * from dblink_get_result(conn) as t(x text);
  exception when others then null;
  end;
  return v;
end;
$$;

-- one canonical SQL text per op, so BOTH sessions send byte-identical calls.
create or replace function pg_temp.submit_sql() returns text language sql as $$
  select format(
    'select app.submit_order(%L, %L, %L, %L, ''takeaway'', null, null, ''ILS'', null,
       jsonb_build_array(jsonb_build_object(
         ''menu_item_id'', %L, ''quantity'', 1,
         ''unit_price_minor_snapshot'', 500, ''menu_item_name_snapshot'', ''Falafel'',
         ''modifiers'', jsonb_build_array())),
       500, 0, 0, 500, null)::text',
    '7e000000-0000-0000-0000-00000000c501', (select order_x from t_ids),
    '7e000000-0000-0000-0000-00000000da11', (select op_submit from t_ids),
    '7e000000-0000-0000-0000-0000000000f1');
$$;
create or replace function pg_temp.pull_sql(dev uuid, tok text) returns text language sql as $$
  select format('select app.pull_kitchen_print_dispatches(%L, %L, 20, null, null)::text', dev, tok);
$$;

select plan(12);

-- ===== setup: BOTH devices file activation-capable readiness (sequential) ====
create temp table t_s1 as
  select app.report_kitchen_printer_readiness(
    '7e000000-0000-0000-0000-00000000da11', 'tok-zz-c1-1',
    'kitchen_printer_only_v1', 'zz-build', 'kitchen_ticket',
    'network', '80mm', repeat('7e', 16), true, 0, 1,
    '7e000000-0000-0000-0000-00000000ba11') as res;
select ok((select (res ->> 'ok')::boolean and (res ->> 'activation_ready')::boolean from t_s1),
  'setup: device 1 files an activation-capable readiness report');
create temp table t_s2 as
  select app.report_kitchen_printer_readiness(
    '7e000000-0000-0000-0000-00000000da22', 'tok-zz-c1-2',
    'kitchen_printer_only_v1', 'zz-build', 'kitchen_ticket',
    'network', '80mm', repeat('7e', 16), true, 0, 1,
    '7e000000-0000-0000-0000-00000000ba11') as res;
select ok((select (res ->> 'ok')::boolean and (res ->> 'activation_ready')::boolean from t_s2),
  'setup: device 2 files an activation-capable readiness report');

select dblink_connect('sess_a', (select cs from t_conn));
select dblink_connect('sess_b', (select cs from t_conn));

-- ============================================================================
-- SCENARIO V — transactional visibility + the duplicate-submit race.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_v_a as
  select r::jsonb as res from dblink('sess_a', pg_temp.submit_sql()) as t(r text);
select ok(
  (select (res ->> 'ok')::boolean and not (res ->> 'idempotency_replay')::boolean from t_v_a),
  'V1: session A submits the printer-only order inside its OPEN transaction');
create temp table t_v_pull as
  select app.pull_kitchen_print_dispatches(
    '7e000000-0000-0000-0000-00000000da22', 'tok-zz-c1-2', 20, null, null) as res;
select ok(
  (select (res ->> 'ok')::boolean and jsonb_array_length(res -> 'dispatches') = 0 from t_v_pull)
  and not exists (select 1 from orders where id = (select order_x from t_ids)),
  'V2: while the submit transaction is open, a concurrent puller sees NEITHER order NOR dispatch (no partial state, no blocking)');
select dblink_send_query('sess_b', pg_temp.submit_sql());
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'V3: the racing duplicate submit BLOCKS on the ledger identity — a second insert never happens');
select dblink_exec('sess_a', 'commit');
create temp table t_v_b as select pg_temp.drain_err('sess_b') as res;
select is((select res from t_v_b), 'ERR:23505',
  'V4: the losing duplicate fails on the unique identity (23505 — retryable), never a forked apply');
select ok(
  (select count(*) = 1 from orders where id = (select order_x from t_ids))
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = (select order_x from t_ids) and dispatch_type = 'initial_order'),
  'V5: EXACTLY ONE order and ONE initial dispatch survive the race');
create temp table t_v_r as
  select r::jsonb as res from dblink((select cs from t_conn), pg_temp.submit_sql()) as t(r text);
select ok(
  (select (res ->> 'ok')::boolean and (res ->> 'idempotency_replay')::boolean from t_v_r)
  and (select count(*) = 1 from kitchen_print_dispatches
        where order_id = (select order_x from t_ids)),
  'V6: the loser''s sequential retry converges on the stored idempotent replay — still one dispatch');

-- ============================================================================
-- SCENARIO C — two READY devices race the atomic claim-and-pull.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_c_a as
  select r::jsonb as res
  from dblink('sess_a', pg_temp.pull_sql('7e000000-0000-0000-0000-00000000da11', 'tok-zz-c1-1')) as t(r text);
select ok(
  (select (res ->> 'ok')::boolean
      and jsonb_array_length(res -> 'dispatches') = 1
      and res -> 'dispatches' -> 0 ->> 'order_id' = (select order_x from t_ids)::text
   from t_c_a),
  'C1: device 1 claims THE dispatch inside its open transaction');
select dblink_send_query('sess_b', pg_temp.pull_sql('7e000000-0000-0000-0000-00000000da22', 'tok-zz-c1-2'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'C2: device 2 BLOCKS on the row lock — the claim is serialized, never duplicated');
select dblink_exec('sess_a', 'commit');
create temp table t_c_b as select pg_temp.drain('sess_b')::jsonb as res;
select ok(
  (select (res ->> 'ok')::boolean and jsonb_array_length(res -> 'dispatches') = 0 from t_c_b),
  'C3: the loser re-proves claimability after the lock wait and converges on an EMPTY ok envelope — exactly ONE winner, no error');
select ok(
  (select claimed_by_device_id = '7e000000-0000-0000-0000-00000000da11'
      and claim_expires_at > now() + interval '9 minutes'
      and completed_at is null
   from kitchen_print_dispatches where order_id = (select order_x from t_ids)),
  'C4: the ~10-minute lease belongs to the winning device ALONE');

select dblink_disconnect('sess_a');
select dblink_disconnect('sess_b');

-- ===== CLEANUP (committed; audit_events stay — append-only by design) ========
delete from kitchen_print_dispatches           where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from kitchen_printer_readiness_reports  where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_item_modifiers where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_items          where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_service_rounds where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from order_operations     where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from sync_operations      where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from orders               where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from menu_items           where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from menu_categories      where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from pin_sessions         where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from device_sessions      where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from device_pairings      where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from devices              where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from employee_profiles    where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from memberships          where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from app_users            where id::text like '7e000000%';
delete from printer_devices      where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from branches             where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from restaurants          where organization_id = '7e000000-0000-0000-0000-0000000000a0';
delete from organizations        where id = '7e000000-0000-0000-0000-0000000000a0';

select * from finish();
