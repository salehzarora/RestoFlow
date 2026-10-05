-- BIZBOT-DEVICE-SESSION-FIX-001: real renewal/revocation concurrency.
-- Local pgTAP only; same dblink harness as zz_kitchen_dispatch_enforce_001.
-- The inert fixtures must be committed for separate sessions to see them.
-- Direct revocation changes ONLY synthetic flags, in the owner RPC's lock order.
-- No audit-producing RPC is committed; no audit deletion or trigger bypass.
-- Blocking proofs require pg_stat_activity Lock + the exact blocking backend,
-- as well as dblink_is_busy. Every poll and remote statement is bounded.
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

insert into organizations (id, name, slug, default_currency) values
  ('bf510000-0000-0000-0000-000000000001', 'BIZBOT session concurrency', 'bizbot-device-session-fix-001-zz', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name, timezone) values
  ('bf510000-0000-0000-0000-000000000002', 'bf510000-0000-0000-0000-000000000001', 'Session concurrency restaurant', 'UTC')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name) values
  ('bf510000-0000-0000-0000-000000000003', 'bf510000-0000-0000-0000-000000000001', 'bf510000-0000-0000-0000-000000000002', 'Session concurrency branch')
  on conflict (id) do nothing;
create temp table bds_fixtures (scenario text primary key, device_id uuid, pairing_id uuid, session_id uuid, token text);
insert into bds_fixtures values
  ('a', 'bf510000-0000-0000-0000-000000000101', 'bf510000-0000-0000-0000-000000000201', 'bf510000-0000-0000-0000-000000000301', 'synthetic-bizbot-session-race-a'),
  ('b', 'bf510000-0000-0000-0000-000000000102', 'bf510000-0000-0000-0000-000000000202', 'bf510000-0000-0000-0000-000000000302', 'synthetic-bizbot-session-race-b'),
  ('c', 'bf510000-0000-0000-0000-000000000103', 'bf510000-0000-0000-0000-000000000203', 'bf510000-0000-0000-0000-000000000303', 'synthetic-bizbot-session-race-c');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, is_active, last_seen_at)
  select device_id, 'bf510000-0000-0000-0000-000000000001', 'bf510000-0000-0000-0000-000000000002',
    'bf510000-0000-0000-0000-000000000003', 'pos', true, '2000-01-01 00:00:00+00'::timestamptz
  from bds_fixtures
  on conflict (id) do update set is_active = true, last_seen_at = excluded.last_seen_at;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
  select pairing_id, 'bf510000-0000-0000-0000-000000000001', 'bf510000-0000-0000-0000-000000000002',
    'bf510000-0000-0000-0000-000000000003', device_id, 'active'
  from bds_fixtures
  on conflict (id) do update set status = 'active', revoked_at = null;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                             session_token_ref, is_active, expires_at)
  select session_id, 'bf510000-0000-0000-0000-000000000001', 'bf510000-0000-0000-0000-000000000002',
    'bf510000-0000-0000-0000-000000000003', device_id, pairing_id,
    app.hash_provisioning_secret(token), true, now() + interval '1 day'
  from bds_fixtures
  on conflict (id) do update set is_active = true, revoked_at = null, expires_at = excluded.expires_at;

create function pg_temp.bds_state(p_scenario text) returns jsonb language sql stable as $$
  select jsonb_build_object('expires_at', s.expires_at, 'last_seen_at', d.last_seen_at,
    'updated_at', s.updated_at, 'session_active', s.is_active, 'revoked', s.revoked_at is not null,
    'device_active', d.is_active, 'pairing_status', dp.status)
  from bds_fixtures f join device_sessions s on s.id = f.session_id
    join devices d on d.id = f.device_id join device_pairings dp on dp.id = f.pairing_id
  where f.scenario = p_scenario;
$$;
create temp table bds_before as select scenario, pg_temp.bds_state(scenario) as state from bds_fixtures;
create temp table bds_conn as
  select 'host=' || host(inet_server_addr()) || ' port=' || inet_server_port()
    || ' dbname=' || current_database() || ' user=postgres password=postgres' as cs;
create function pg_temp.bds_heartbeat_sql(p_scenario text) returns text language sql as $$
  select format('select public.heartbeat_device_session(%L::uuid, %L)::text', device_id, token)
  from bds_fixtures where scenario = p_scenario;
$$;
-- Dependent CTEs enforce device -> pairing -> session; one SELECT result makes
-- the async result shape deterministic. These are private fixture flags only.
create function pg_temp.bds_revoke_sql(p_scenario text) returns text language sql as $$
  select format(
    'with device_off as (
       update public.devices set is_active = false where id = %L::uuid returning id
     ), pairing_off as (
       update public.device_pairings set status = ''revoked'', revoked_at = now()
       where id = %L::uuid and device_id in (select id from device_off) returning id
     ), session_off as (
       update public.device_sessions set is_active = false, revoked_at = now()
       where id = %L::uuid and device_pairing_id in (select id from pairing_off) returning id
     ) select count(*)::text from session_off', device_id, pairing_id, session_id)
  from bds_fixtures where scenario = p_scenario;
$$;
create function pg_temp.bds_wait_for_lock(p_conn text, p_waiter integer, p_blocker integer)
  returns boolean language plpgsql as $$
begin
  for i in 1..500 loop
    perform pg_stat_clear_snapshot();
    if dblink_is_busy(p_conn) = 0 then return false; end if;
    if exists (select 1 from pg_stat_activity where pid = p_waiter
      and wait_event_type = 'Lock' and p_blocker = any(pg_blocking_pids(pid))) then
      return true;
    end if;
    perform pg_sleep(0.01);
  end loop;
  return false;
end;
$$;
create function pg_temp.bds_drain(p_conn text) returns text language plpgsql as $$
declare v_result text;
begin
  for i in 1..500 loop
    exit when dblink_is_busy(p_conn) = 0;
    perform pg_sleep(0.01);
  end loop;
  if dblink_is_busy(p_conn) <> 0 then
    perform dblink_cancel_query(p_conn);
    raise exception 'BIZBOT concurrency query exceeded the bounded drain';
  end if;
  select result into v_result from dblink_get_result(p_conn) as r(result text);
  perform * from dblink_get_result(p_conn) as r(result text);
  return v_result;
end;
$$;

select plan(36);
select dblink_connect('bds_fix_a', (select cs from bds_conn));
select dblink_connect('bds_fix_b', (select cs from bds_conn));
select dblink_exec('bds_fix_a', 'set statement_timeout = ''15s''');
select dblink_exec('bds_fix_b', 'set statement_timeout = ''15s''');
select dblink_exec('bds_fix_a', 'set lock_timeout = ''12s''');
select dblink_exec('bds_fix_b', 'set lock_timeout = ''12s''');
create temp table bds_pids as
  select 'a'::text as connection, pid from dblink('bds_fix_a', 'select pg_backend_pid()') as r(pid integer)
  union all
  select 'b'::text, pid from dblink('bds_fix_b', 'select pg_backend_pid()') as r(pid integer);

-- A: in-flight revocation owns rows first; renewal must wait and re-read.
select dblink_exec('bds_fix_a', 'begin');
create temp table bds_a_revoke as
  select result from dblink('bds_fix_a', pg_temp.bds_revoke_sql('a')) as r(result text);
select is((select result from bds_a_revoke), '1', 'A1: revoker changes exactly its synthetic session in an open transaction');
select dblink_exec('bds_fix_b', 'begin');
select dblink_send_query('bds_fix_b', pg_temp.bds_heartbeat_sql('a'));
select ok(pg_temp.bds_wait_for_lock('bds_fix_b', (select pid from bds_pids where connection = 'b'),
  (select pid from bds_pids where connection = 'a')), 'A2: renewal has a real Lock wait on the uncommitted revoker');
select is(dblink_is_busy('bds_fix_b'), 1, 'A3: renewal remains pending until revocation commits');
select is(pg_temp.bds_state('a') ->> 'session_active', 'true', 'A4: observer still sees active state while revocation is uncommitted');
select dblink_exec('bds_fix_a', 'commit');
create temp table bds_a_result as select pg_temp.bds_drain('bds_fix_b')::jsonb as result;
select dblink_exec('bds_fix_b', 'commit');
select is((select result ->> 'error' from bds_a_result), 'invalid_session', 'A5: renewal refuses after the revocation commit');
select is((select result ->> 'reason' from bds_a_result), 'revoked', 'A6: correct token gets the committed revoked reason');
select is((select result ->> 'ok' from bds_a_result), 'false', 'A7: revoked session is never restored');
select is(pg_temp.bds_state('a') ->> 'expires_at', (select state ->> 'expires_at' from bds_before where scenario = 'a'),
  'A8: rejected renewal leaves deadline unchanged');
select is(pg_temp.bds_state('a') ->> 'last_seen_at', (select state ->> 'last_seen_at' from bds_before where scenario = 'a'),
  'A9: rejected renewal leaves activity unchanged');
select ok(pg_temp.bds_state('a') @> '{"session_active":false,"revoked":true}'::jsonb,
  'A10: committed session stays inactive and revoked');

-- B: renewal owns rows first. Revocation must wait, then commit last.
select dblink_exec('bds_fix_a', 'begin');
create temp table bds_b_result as
  select result::jsonb as result from dblink('bds_fix_a', pg_temp.bds_heartbeat_sql('b')) as r(result text);
select is((select result ->> 'ok' from bds_b_result), 'true', 'B1: renewal succeeds inside its still-open transaction');
select is((select (result ->> 'session_expires_at')::timestamptz from bds_b_result),
  (select (result ->> 'server_now')::timestamptz + interval '30 days' from bds_b_result), 'B2: winner sets exactly its 30-day deadline');
select is(pg_temp.bds_state('b') ->> 'expires_at', (select state ->> 'expires_at' from bds_before where scenario = 'b'),
  'B3: uncommitted renewal is invisible to observer');
select dblink_exec('bds_fix_b', 'begin');
select dblink_send_query('bds_fix_b', pg_temp.bds_revoke_sql('b'));
select ok(pg_temp.bds_wait_for_lock('bds_fix_b', (select pid from bds_pids where connection = 'b'),
  (select pid from bds_pids where connection = 'a')), 'B4: revocation has a real Lock wait on the renewing transaction');
select is(dblink_is_busy('bds_fix_b'), 1, 'B5: revocation remains pending until renewal commits');
select dblink_exec('bds_fix_a', 'commit');
create temp table bds_b_revoke as select pg_temp.bds_drain('bds_fix_b') as result;
select dblink_exec('bds_fix_b', 'commit');
select is((select result from bds_b_revoke), '1', 'B6: revocation proceeds and changes exactly its session');
select ok(pg_temp.bds_state('b') @> '{"session_active":false,"revoked":true,"device_active":false,"pairing_status":"revoked"}'::jsonb,
  'B7: final device, pairing and session are all revoked/inactive');
select is((pg_temp.bds_state('b') ->> 'expires_at')::timestamptz,
  (select (result ->> 'session_expires_at')::timestamptz from bds_b_result), 'B8: revocation preserves the committed deadline without reviving it');
select is((pg_temp.bds_state('b') ->> 'last_seen_at')::timestamptz,
  (select (result ->> 'server_now')::timestamptz from bds_b_result), 'B9: only the successful renewal recorded activity');
select is(public.heartbeat_device_session('bf510000-0000-0000-0000-000000000102', 'synthetic-bizbot-session-race-b') ->> 'reason',
  'revoked', 'B10: another heartbeat still cannot revive the revoked session');

-- C: two overlapping renewals. B starts FIRST, before A's winning renewal,
-- so the waiter has an older now() and must never shorten A's deadline/activity.
select dblink_exec('bds_fix_b', 'begin');
create temp table bds_c_older as select ts from dblink('bds_fix_b', 'select now()') as r(ts timestamptz);
select dblink_exec('bds_fix_a', 'begin');
create temp table bds_c_winner as
  select result::jsonb as result from dblink('bds_fix_a', pg_temp.bds_heartbeat_sql('c')) as r(result text);
select is((select result ->> 'ok' from bds_c_winner), 'true', 'C1: first locker renews inside its open transaction');
select ok((select ts from bds_c_older) < (select (result ->> 'server_now')::timestamptz from bds_c_winner),
  'C2: waiter transaction clock is strictly older than the winner clock');
select dblink_send_query('bds_fix_b', pg_temp.bds_heartbeat_sql('c'));
select ok(pg_temp.bds_wait_for_lock('bds_fix_b', (select pid from bds_pids where connection = 'b'),
  (select pid from bds_pids where connection = 'a')), 'C3: second renewal really blocks on the winning transaction');
select is(dblink_is_busy('bds_fix_b'), 1, 'C4: second renewal stays pending until first commit');
select dblink_exec('bds_fix_a', 'commit');
create temp table bds_c_waiter as select pg_temp.bds_drain('bds_fix_b')::jsonb as result;
select dblink_exec('bds_fix_b', 'commit');
select is((select result ->> 'ok' from bds_c_waiter), 'true', 'C5: waiter succeeds after reading committed session state');
select is((select (result ->> 'session_expires_at')::timestamptz from bds_c_waiter),
  (select (result ->> 'session_expires_at')::timestamptz from bds_c_winner), 'C6: both concurrent calls converge on exactly one deadline');
select is((pg_temp.bds_state('c') ->> 'expires_at')::timestamptz,
  (select (result ->> 'session_expires_at')::timestamptz from bds_c_winner), 'C7: older waiter never shortens persisted expiry');
select is((pg_temp.bds_state('c') ->> 'last_seen_at')::timestamptz,
  (select (result ->> 'server_now')::timestamptz from bds_c_winner), 'C8: throttle preserves winning activity timestamp');
select is((pg_temp.bds_state('c') ->> 'updated_at')::timestamptz,
  (select (result ->> 'server_now')::timestamptz from bds_c_winner), 'C9: second call performs no session update');
select ok(pg_temp.bds_state('c') @> '{"session_active":true,"revoked":false}'::jsonb, 'C10: concurrent renewal leaves session active and unrevoked');

select dblink_disconnect('bds_fix_a');
select dblink_disconnect('bds_fix_b');
select is((select count(*)::integer from audit_events where organization_id = 'bf510000-0000-0000-0000-000000000001'),
  0, 'R1: no append-only audit rows were committed');
select is((select count(*)::integer from sync_operations where organization_id = 'bf510000-0000-0000-0000-000000000001'),
  0, 'R2: no sync/outbox operation was created');
select is((select count(*)::integer from pin_sessions where organization_id = 'bf510000-0000-0000-0000-000000000001'),
  0, 'R3: renewal created no employee PIN authority');
select is((select count(*)::integer from device_sessions where id in (select session_id from bds_fixtures)),
  3, 'R4: concurrent calls neither minted nor deleted a session');
-- Exact private fixture ids ONLY; never touch append-only audit rows.
delete from device_sessions where id in (select session_id from bds_fixtures);
delete from device_pairings where id in (select pairing_id from bds_fixtures);
delete from devices where id in (select device_id from bds_fixtures);
delete from branches where id = 'bf510000-0000-0000-0000-000000000003';
delete from restaurants where id = 'bf510000-0000-0000-0000-000000000002';
delete from organizations where id = 'bf510000-0000-0000-0000-000000000001';
select is((select count(*)::integer from device_sessions where id in (select session_id from bds_fixtures)),
  0, 'R5: all synthetic sessions removed');
select ok(not exists (select 1 from organizations where id = 'bf510000-0000-0000-0000-000000000001'),
  'R6: hierarchy cleaned without global deletion or audit bypass');
select * from finish();
