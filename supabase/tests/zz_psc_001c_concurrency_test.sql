-- ============================================================================
-- PSC-001C (correction, Finding 1) — REAL two-session concurrency: the sync
-- ledger claim is ATOMIC, so a same-key race can never overwrite a terminal
-- applied row, re-dispatch, or fork the business mutation.
-- ============================================================================
-- app.sync_push now CLAIMS the (organization_id, device_id,
-- local_operation_id) ledger identity with ONE INSERT .. ON CONFLICT DO
-- NOTHING; the losing claimant LOCKS the existing row (waiting out the
-- winner's COMMIT) and replays its stored terminal result. These scenarios
-- run on GENUINELY SEPARATE database sessions via dblink (the repository's
-- accepted zz_ concurrency harness — never two sequential calls in one
-- transaction):
--
--   R. two sessions push the SAME order.round_status op (same
--      local_operation_id + payload): the loser BLOCKS on the claim, then
--      converges on the winner's applied result (idempotency_replay) — the
--      round advanced ONCE, ONE success audit, the ledger stays applied.
--   A. two sessions push the SAME order.items_add op: ONE round, ONE item
--      set, ONE success audit; both callers reference the SAME round. Then
--      (final correction, Finding 5) the LEDGER truth is asserted explicitly:
--      exactly one applied sync_operations row whose stored result names the
--      created round, never overwritten by a rejection/conflict — and an
--      EXACT terminal replay of the same op returns that stored result
--      (idempotency_replay) while creating no second round, item set or
--      audit and leaving the ledger row byte-identical.
--   F. the same key with a DIFFERENT fingerprint after terminality: the
--      conflict contract fires, nothing dispatches, the terminal row stands.
--   T. an exact terminal replay after the race remains successful.
--
-- HARNESS NOTES: dblink sessions cannot see uncommitted fixtures, so this
-- file COMMITS its fixtures (fixed 7c-prefixed hex ids, upsert-tolerant) and
-- deletes them at the tail (append-only audit_events excepted — they stay
-- under THIS file's own 7c org only; other suites scope their audit counts to
-- their own orgs). The zz_ prefix keeps committing files at the END of the
-- alphabetical run. Local pgTAP harness only; nothing here can run hosted.
-- ============================================================================
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

-- ===== fixtures (COMMITTED; upsert-tolerant for re-runs) =====================
insert into organizations (id, name, slug, default_currency) values
  ('7c000000-0000-0000-0000-0000000000a0', 'Org C', 'psc001c-c', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name) values
  ('7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-0000000000a0', 'Rest C1')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name) values
  ('7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', 'Branch C1')
  on conflict (id) do nothing;
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('7c000000-0000-0000-0000-00000000da22', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'kds')
  on conflict (id) do nothing;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7c000000-0000-0000-0000-00000000fa11', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', 'active'),
  ('7c000000-0000-0000-0000-00000000fa22', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da22', 'active')
  on conflict (id) do nothing;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('7c000000-0000-0000-0000-0000000005a1', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da11', '7c000000-0000-0000-0000-00000000fa11'),
  ('7c000000-0000-0000-0000-0000000005a2', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000da22', '7c000000-0000-0000-0000-00000000fa22')
  on conflict (id) do nothing;
insert into app_users (id, email) values
  ('7c000000-0000-0000-0000-00000000ee03', 'psc001c-cashier@example.test'),
  ('7c000000-0000-0000-0000-00000000ee04', 'psc001c-kitchen@example.test')
  on conflict (id) do nothing;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7c000000-0000-0000-0000-00000000ab03', '7c000000-0000-0000-0000-00000000ee03', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('7c000000-0000-0000-0000-00000000ab04', '7c000000-0000-0000-0000-00000000ee04', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'kitchen_staff')
  on conflict (id) do nothing;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000ee03', '7c000000-0000-0000-0000-00000000ab03', 'Casey'),
  ('7c000000-0000-0000-0000-0000000ef004', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-00000000ee04', '7c000000-0000-0000-0000-00000000ab04', 'Kim')
  on conflict (id) do nothing;
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-0000000005a1', '7c000000-0000-0000-0000-0000000ef003', '7c000000-0000-0000-0000-00000000ab03', now() + interval '1 hour'),
  ('7c000000-0000-0000-0000-00000000c502', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', '7c000000-0000-0000-0000-0000000005a2', '7c000000-0000-0000-0000-0000000ef004', '7c000000-0000-0000-0000-00000000ab04', now() + interval '1 hour')
  on conflict (id) do update set expires_at = now() + interval '1 hour';
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('7c000000-0000-0000-0000-00000000ca01', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', null, 'Food', 1)
  on conflict (id) do nothing;
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('7c000000-0000-0000-0000-0000000000f1', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', null, '7c000000-0000-0000-0000-00000000ca01', 'Falafel', 500, 'ILS', 1)
  on conflict (id) do nothing;
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('7c000000-0000-0000-0000-00000000ba01', '7c000000-0000-0000-0000-0000000000a0', '7c000000-0000-0000-0000-0000000000a1', '7c000000-0000-0000-0000-00000000a1b1', 'CT1')
  on conflict (id) do nothing;
-- clean any previous run's operational residue BEFORE the scenarios.
delete from order_item_modifiers where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from order_items          where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from order_service_rounds where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from order_operations     where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from sync_operations      where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from orders               where organization_id = '7c000000-0000-0000-0000-0000000000a0';

-- per-run identities + the scenario clock floor for audit scoping.
create temp table t_ids as select
  gen_random_uuid() as order_c,
  gen_random_uuid()::text as op_submit,
  gen_random_uuid()::text as op_add0,
  gen_random_uuid()::text as op_rs,
  gen_random_uuid()::text as op_add1,
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

-- one canonical SQL text per op, so BOTH sessions send byte-identical calls.
create or replace function pg_temp.rs_sql() returns text language sql as $$
  select format(
    'select public.sync_push(%L, %L, jsonb_build_array(jsonb_build_object(
       ''local_operation_id'', %L, ''operation_type'', ''order.round_status'',
       ''target_entity'', ''order_service_round'', ''target_id'', r.id::text,
       ''payload'', jsonb_build_object(''round_id'', r.id, ''new_status'', ''accepted''))))::text
     from public.order_service_rounds r
     where r.order_id = %L and r.round_number = 2',
    '7c000000-0000-0000-0000-00000000c502', '7c000000-0000-0000-0000-00000000da22',
    (select op_rs from t_ids), (select order_c from t_ids));
$$;
create or replace function pg_temp.add_sql() returns text language sql as $$
  select format(
    'select public.sync_push(%L, %L, jsonb_build_array(jsonb_build_object(
       ''local_operation_id'', %L, ''operation_type'', ''order.items_add'',
       ''target_entity'', ''order'', ''target_id'', %L,
       ''payload'', jsonb_build_object(''order_id'', %L,
         ''order_items'', jsonb_build_array(jsonb_build_object(
           ''menu_item_id'', %L, ''quantity'', 1,
           ''unit_price_minor_snapshot'', 500, ''menu_item_name_snapshot'', ''Falafel''))))))::text',
    '7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-00000000da11',
    (select op_add1 from t_ids), (select order_c from t_ids), (select order_c from t_ids),
    '7c000000-0000-0000-0000-0000000000f1');
$$;

select plan(26);

-- ===== setup (sequential, committed): submit order + round 2 =================
create temp table t_setup1 as
  select public.sync_push('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-00000000da11',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', (select op_submit from t_ids), 'operation_type', 'order.submit', 'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', (select order_c from t_ids), 'order_type', 'dine_in',
        'table_id', '7c000000-0000-0000-0000-00000000ba01', 'currency_code', 'ILS',
        'subtotal_minor', 500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 500,
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', '7c000000-0000-0000-0000-0000000000f1', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel')))))) as r;
select is((select r -> 'results' -> 0 ->> 'status' from t_setup1), 'applied',
  'setup: the parent dine-in order is accepted');
create temp table t_setup2 as
  select public.sync_push('7c000000-0000-0000-0000-00000000c501', '7c000000-0000-0000-0000-00000000da11',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', (select op_add0 from t_ids), 'operation_type', 'order.items_add', 'target_entity', 'order',
      'target_id', (select order_c from t_ids)::text,
      'payload', jsonb_build_object(
        'order_id', (select order_c from t_ids),
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', '7c000000-0000-0000-0000-0000000000f1', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Falafel')))))) as r;
select is((select r -> 'results' -> 0 ->> 'status' from t_setup2), 'applied',
  'setup: round 2 exists');

select dblink_connect('sess_a', (select cs from t_conn));
select dblink_connect('sess_b', (select cs from t_conn));

-- ============================================================================
-- SCENARIO R — SAME order.round_status key from two sessions.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_r_a as
  select r::jsonb as res from dblink('sess_a', pg_temp.rs_sql()) as t(r text);
select is((select res -> 'results' -> 0 ->> 'status' from t_r_a), 'applied',
  'R1: session A applies the round transition inside its OPEN transaction');
select dblink_send_query('sess_b', pg_temp.rs_sql());
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'R2: session B BLOCKS on the atomic ledger claim while A holds it');
select dblink_exec('sess_a', 'commit');
create temp table t_r_b as select pg_temp.drain('sess_b')::jsonb as res;
select ok(
  (select (res -> 'results' -> 0 ->> 'status') = 'applied'
      and (res -> 'results' -> 0 ->> 'idempotency_replay')::boolean from t_r_b),
  'R3: session B converges on the winner''s stored APPLIED result (replay)');
select ok(
  (select (status = 'accepted' and revision = 2)
     from order_service_rounds where order_id = (select order_c from t_ids)),
  'R4: the round advanced EXACTLY once (no double transition, no rollback)');
select is(
  (select count(*)::int from audit_events
     where organization_id = '7c000000-0000-0000-0000-0000000000a0'
       and action = 'order.round_status_updated'
       and occurred_at >= (select started_at from t_ids)),
  1, 'R5: exactly ONE success audit for the raced transition');
select is(
  (select status from sync_operations where local_operation_id = (select op_rs from t_ids)),
  'applied', 'R6: the ledger row remains APPLIED — never overwritten by the loser');

-- ============================================================================
-- SCENARIO A — SAME order.items_add key from two sessions.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_a_a as
  select r::jsonb as res from dblink('sess_a', pg_temp.add_sql()) as t(r text);
select is((select res -> 'results' -> 0 ->> 'status' from t_a_a), 'applied',
  'A1: session A applies the addition inside its OPEN transaction');
select dblink_send_query('sess_b', pg_temp.add_sql());
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1,
  'A2: session B BLOCKS on the atomic ledger claim');
select dblink_exec('sess_a', 'commit');
create temp table t_a_b as select pg_temp.drain('sess_b')::jsonb as res;
select ok(
  (select (b.res -> 'results' -> 0 ->> 'idempotency_replay')::boolean
      and (b.res -> 'results' -> 0 ->> 'round_id') = (a.res -> 'results' -> 0 ->> 'round_id')
     from t_a_b b, t_a_a a),
  'A3: both callers reference the SAME round (the loser replays the winner)');
select is(
  (select count(*)::int from order_service_rounds
     where order_id = (select order_c from t_ids) and round_number = 3),
  1, 'A4: exactly ONE round 3 exists — no duplicate round');
select is(
  (select count(*)::int from order_items oi
     join order_service_rounds r on r.id = oi.service_round_id
     where r.order_id = (select order_c from t_ids) and r.round_number = 3),
  1, 'A5: exactly ONE item set was inserted for the raced addition');
select is(
  (select count(*)::int from audit_events
     where organization_id = '7c000000-0000-0000-0000-0000000000a0'
       and action = 'order.items_added'
       and occurred_at >= (select started_at from t_ids)
       and (new_values ->> 'round_number')::int = 3),
  1, 'A6: exactly ONE items_added success audit for the raced addition');

-- ---- the raced key's LEDGER truth (final correction, Finding 5) ------------
select is(
  (select count(*)::int from sync_operations
     where organization_id = '7c000000-0000-0000-0000-0000000000a0'
       and device_id = '7c000000-0000-0000-0000-00000000da11'
       and local_operation_id = (select op_add1 from t_ids)),
  1, 'A7: exactly ONE sync_operations row exists for the raced items_add key');
select is(
  (select status from sync_operations
     where local_operation_id = (select op_add1 from t_ids)),
  'applied', 'A8: that ledger row is APPLIED');
select ok(
  (select (so.result ->> 'ok')::boolean
      and (so.result ->> 'round_id') = (a.res -> 'results' -> 0 ->> 'round_id')
     from sync_operations so, t_a_a a
     where so.local_operation_id = (select op_add1 from t_ids)),
  'A9: the STORED result references the created round');
select ok(
  (select so.last_error_code is null
      and so.rejection_reason is null
      and (so.result ->> 'error') is null
     from sync_operations so
     where so.local_operation_id = (select op_add1 from t_ids)),
  'A10: no rejected/conflict write ever overwrote the applied row');

-- ---- the EXACT terminal replay of the raced op (same canonical add_sql) ----
create temp table t_a_ledger as
  select status, result from sync_operations
    where local_operation_id = (select op_add1 from t_ids);
create temp table t_a_replay as select r::jsonb as res
  from dblink((select cs from t_conn), pg_temp.add_sql()) as t(r text);
select ok(
  (select (rp.res -> 'results' -> 0 ->> 'status') = 'applied'
      and (rp.res -> 'results' -> 0 ->> 'idempotency_replay')::boolean
      and (rp.res -> 'results' -> 0 ->> 'round_id')
            = (a.res -> 'results' -> 0 ->> 'round_id')
     from t_a_replay rp, t_a_a a),
  'A11: an exact terminal replay returns the STORED applied result (replay flag, same round)');
select is(
  (select count(*)::int from order_service_rounds
     where order_id = (select order_c from t_ids) and round_number = 3),
  1, 'A12: the replay created NO second round');
select is(
  (select count(*)::int from order_items oi
     join order_service_rounds r on r.id = oi.service_round_id
     where r.order_id = (select order_c from t_ids) and r.round_number = 3),
  1, 'A13: the replay inserted NO second item set');
select is(
  (select count(*)::int from audit_events
     where organization_id = '7c000000-0000-0000-0000-0000000000a0'
       and action = 'order.items_added'
       and occurred_at >= (select started_at from t_ids)
       and (new_values ->> 'round_number')::int = 3),
  1, 'A14: the replay wrote NO second success audit for the raced round');
select ok(
  (select so.status = l.status and so.result = l.result
     from sync_operations so, t_a_ledger l
     where so.local_operation_id = (select op_add1 from t_ids)),
  'A15: the ledger status AND stored result are unchanged after the replay');

-- ============================================================================
-- SCENARIO F — same key, DIFFERENT fingerprint after terminality.
-- ============================================================================
create temp table t_f as
  select (public.sync_push('7c000000-0000-0000-0000-00000000c502', '7c000000-0000-0000-0000-00000000da22',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', (select op_rs from t_ids), 'operation_type', 'order.round_status',
      'target_entity', 'order_service_round',
      'target_id', (select id::text from order_service_rounds where order_id = (select order_c from t_ids) and round_number = 2),
      'payload', jsonb_build_object(
        'round_id', (select id from order_service_rounds where order_id = (select order_c from t_ids) and round_number = 2),
        'new_status', 'preparing')))) -> 'results' -> 0) as res;
select ok(
  (select (res ->> 'status') = 'conflict' and (res ->> 'error') = 'conflict' from t_f),
  'F1: the same key with a DIFFERENT payload is the idempotency-conflict contract');
select ok(
  (select status = 'applied' from sync_operations where local_operation_id = (select op_rs from t_ids))
  and (select status = 'accepted' from order_service_rounds
         where order_id = (select order_c from t_ids) and round_number = 2),
  'F2: nothing dispatched — the terminal ledger row AND the round are untouched');

-- ============================================================================
-- SCENARIO T — exact terminal replay after all the racing.
-- ============================================================================
create temp table t_t as select r::jsonb as res
  from dblink((select cs from t_conn), pg_temp.rs_sql()) as t(r text);
select ok(
  (select (res -> 'results' -> 0 ->> 'status') = 'applied'
      and (res -> 'results' -> 0 ->> 'idempotency_replay')::boolean from t_t),
  'T1: an exact terminal replay after the race still replays SUCCESS');

select dblink_disconnect('sess_a');
select dblink_disconnect('sess_b');

-- ===== CLEANUP (committed; audit_events stay — append-only by design) ========
delete from realtime.messages where topic like 'kds:branch:7c000000%';
delete from order_item_modifiers where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from order_items          where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from order_service_rounds where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from order_operations     where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from sync_operations      where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from orders               where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from tables               where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from menu_items           where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from menu_categories      where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from pin_sessions         where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from device_sessions      where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from device_pairings      where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from devices              where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from employee_profiles    where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from memberships          where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from app_users            where id::text like '7c000000%';
delete from branches             where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from restaurants          where organization_id = '7c000000-0000-0000-0000-0000000000a0';
delete from organizations        where id = '7c000000-0000-0000-0000-0000000000a0';

select * from finish();
