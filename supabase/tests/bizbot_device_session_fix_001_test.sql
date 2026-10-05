-- BIZBOT-DEVICE-SESSION-FIX-001: idle renewal, refusal, compatibility and admin contracts.
-- Synthetic fixtures only; every mutation, including audit, rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
select no_plan();

insert into organizations (id, name, slug, default_currency) values
  ('be510001-0000-0000-0000-00000000a000', 'BIZBOT session test A', 'bizbot-session-fix-a', 'USD'),
  ('be510001-0000-0000-0000-00000000b000', 'BIZBOT session test B', 'bizbot-session-fix-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('be510001-0000-0000-0000-00000000a100', 'be510001-0000-0000-0000-00000000a000', 'Test restaurant'),
  ('be510001-0000-0000-0000-00000000b100', 'be510001-0000-0000-0000-00000000b000', 'Other test restaurant');
insert into branches (id, organization_id, restaurant_id, name) values
  ('be510001-0000-0000-0000-00000000a110', 'be510001-0000-0000-0000-00000000a000',
   'be510001-0000-0000-0000-00000000a100', 'Test branch'),
  ('be510001-0000-0000-0000-00000000b110', 'be510001-0000-0000-0000-00000000b000',
   'be510001-0000-0000-0000-00000000b100', 'Other test branch');
insert into app_users (id, email) values
  ('be510001-0000-0000-0000-00000000a900', 'bizbot-session-owner@example.test'),
  ('be510001-0000-0000-0000-00000000a901', 'bizbot-session-manager@example.test'),
  ('be510001-0000-0000-0000-00000000a902', 'bizbot-session-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('be510001-0000-0000-0000-00000000f001', 'be510001-0000-0000-0000-00000000a900',
   'be510001-0000-0000-0000-00000000a000', null, null, 'org_owner'),
  ('be510001-0000-0000-0000-00000000f002', 'be510001-0000-0000-0000-00000000a901',
   'be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
   'be510001-0000-0000-0000-00000000a110', 'manager'),
  ('be510001-0000-0000-0000-00000000f003', 'be510001-0000-0000-0000-00000000a902',
   'be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
   'be510001-0000-0000-0000-00000000a110', 'cashier');

create temp table _bizbot_devices (kind text primary key, device_id uuid, pairing_id uuid, session_id uuid, proof text);
insert into _bizbot_devices values
  ('pos', 'be510001-0000-0000-0000-00000000d001', 'be510001-0000-0000-0000-00000000c001', 'be510001-0000-0000-0000-00000000e001', 'bizbot-fixture-pos'),
  ('kds', 'be510001-0000-0000-0000-00000000d002', 'be510001-0000-0000-0000-00000000c002', 'be510001-0000-0000-0000-00000000e002', 'bizbot-fixture-kds'),
  ('kiosk', 'be510001-0000-0000-0000-00000000d003', 'be510001-0000-0000-0000-00000000c003', 'be510001-0000-0000-0000-00000000e003', 'bizbot-fixture-kiosk');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label)
select device_id, 'be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
       'be510001-0000-0000-0000-00000000a110', kind, 'BIZBOT test ' || kind from _bizbot_devices;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at)
select pairing_id, 'be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
       'be510001-0000-0000-0000-00000000a110', device_id, 'active', now() from _bizbot_devices;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, expires_at)
select session_id, 'be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
       'be510001-0000-0000-0000-00000000a110', device_id, pairing_id, app.hash_provisioning_secret(proof), now() + interval '7 days'
from _bizbot_devices;

insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('be510001-0000-0000-0000-00000000d004', 'be510001-0000-0000-0000-00000000b000',
   'be510001-0000-0000-0000-00000000b100', 'be510001-0000-0000-0000-00000000b110', 'pos', 'Other tenant device');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('be510001-0000-0000-0000-00000000c004', 'be510001-0000-0000-0000-00000000b000',
   'be510001-0000-0000-0000-00000000b100', 'be510001-0000-0000-0000-00000000b110',
   'be510001-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, expires_at) values
  ('be510001-0000-0000-0000-00000000e004', 'be510001-0000-0000-0000-00000000b000',
   'be510001-0000-0000-0000-00000000b100', 'be510001-0000-0000-0000-00000000b110',
   'be510001-0000-0000-0000-00000000d004', 'be510001-0000-0000-0000-00000000c004',
   app.hash_provisioning_secret('bizbot-fixture-other-tenant'), now()+interval '7 days');

create function pg_temp.deadline(p_kind text default 'pos') returns timestamptz language sql as $$
  select s.expires_at from device_sessions s join _bizbot_devices f on f.session_id = s.id where f.kind = p_kind
$$;
create function pg_temp.seen(p_kind text default 'pos') returns timestamptz language sql as $$
  select d.last_seen_at from devices d join _bizbot_devices f on f.device_id = d.id where f.kind = p_kind
$$;
create function pg_temp.restore(p_kind text default 'pos') returns jsonb language sql as $$
  select app.restore_device_session(device_id, proof) from _bizbot_devices where kind = p_kind
$$;
create function pg_temp.heartbeat(p_kind text default 'pos') returns jsonb language sql as $$
  select public.heartbeat_device_session(device_id, proof) from _bizbot_devices where kind = p_kind
$$;
create function pg_temp.reset_pos(p_expiry timestamptz default now() + interval '7 days') returns void language plpgsql as $$
begin
  update organizations set status = 'active', deleted_at = null where id = 'be510001-0000-0000-0000-00000000a000';
  update restaurants set status = 'active', deleted_at = null where id = 'be510001-0000-0000-0000-00000000a100';
  update branches set status = 'active', deleted_at = null where id = 'be510001-0000-0000-0000-00000000a110';
  update devices set is_active = true, deleted_at = null, last_seen_at = null where id = 'be510001-0000-0000-0000-00000000d001';
  update device_pairings set status = 'active', revoked_at = null, deleted_at = null where id = 'be510001-0000-0000-0000-00000000c001';
  update device_sessions set is_active = true, revoked_at = null, expires_at = p_expiry where id = 'be510001-0000-0000-0000-00000000e001';
end
$$;

select is(app.device_session_idle_window(), interval '30 days', 'the approved idle window is 30 days');
select is(app.device_session_max_age(), interval '30 days', 'existing redeem issuance uses the new window');
select is(pg_temp.restore()->>'ok', 'true', 'token-proven restore succeeds');
select is(pg_temp.deadline(), now() + interval '30 days', 'restore extends an eligible session');
select is(pg_temp.seen(), now(), 'renewal records device activity');
select ok(pg_temp.restore() ?& array['ok','entity','device_session_id','organization_id','restaurant_id','branch_id','device_id','device_type'],
  'restore retains every existing success field');
select ok(not (pg_temp.restore() ? 'session_token'), 'restore does not reveal a token');

-- Strict throttle boundary: equality does not write; one microsecond below does.
select pg_temp.reset_pos(now() + interval '30 days' - interval '1 hour');
select is(pg_temp.heartbeat()->>'ok', 'true', 'heartbeat succeeds at the throttle boundary');
select is(pg_temp.deadline(), now() + interval '30 days' - interval '1 hour', 'exact throttle boundary retains expiry');
select is(pg_temp.seen(), null::timestamptz, 'throttled heartbeat does not write last_seen_at');
select pg_temp.reset_pos(now() + interval '30 days' - interval '1 hour' - interval '1 microsecond');
select is(pg_temp.heartbeat()->>'ok', 'true', 'heartbeat below the throttle boundary succeeds');
select is(pg_temp.deadline(), now() + interval '30 days', 'below boundary renews to now plus 30 days');
select is(pg_temp.seen(), now(), 'heartbeat renewal writes activity');
select pg_temp.reset_pos(now() + interval '30 days' - interval '1 hour' + interval '1 microsecond');
select is(pg_temp.heartbeat()->>'ok', 'true', 'heartbeat above throttle boundary succeeds');
select is(pg_temp.seen(), null::timestamptz, 'above boundary avoids a write');
select pg_temp.reset_pos(now());
select is(pg_temp.restore()->>'reason', 'expired', 'exact expiry is rejected with expired reason');
select is(pg_temp.heartbeat()->>'error', 'invalid_session', 'expired heartbeat is explicit invalid_session');
select is(pg_temp.deadline(), now(), 'exact expiry is never resurrected');
select is(pg_temp.seen(), null::timestamptz, 'expired requests do not count as activity');
select pg_temp.reset_pos(now() + interval '1 microsecond');
select is(pg_temp.restore()->>'ok', 'true', 'one microsecond before expiry remains eligible');
select is(pg_temp.deadline(), now() + interval '30 days', 'eligible boundary renews');
select pg_temp.reset_pos(null);
select is(pg_temp.heartbeat()->>'ok', 'true', 'legacy NULL works on heartbeat');
select is(pg_temp.deadline(), now() + interval '30 days', 'legacy NULL gains an idle deadline');
select pg_temp.reset_pos(null);
select is(pg_temp.restore()->>'ok', 'true', 'legacy NULL works on restore');
select is(pg_temp.deadline(), now() + interval '30 days', 'restore also converts legacy NULL');
select pg_temp.reset_pos();
update device_sessions set started_at = now() - interval '400 days' where id = 'be510001-0000-0000-0000-00000000e001';
select is(pg_temp.heartbeat()->>'ok', 'true', 'an in-use old session has no absolute age cap');
select is((select started_at from device_sessions where id = 'be510001-0000-0000-0000-00000000e001'),
          now() - interval '400 days', 'renewal does not replace the original issuance time');

-- Every refusal verifies both RPCs and both mutation targets.
create function pg_temp.denial(p_name text, p_mutation text, p_reason text) returns setof text language plpgsql as $$
declare v_restore jsonb; v_heartbeat jsonb; v_expiry timestamptz;
begin
  perform pg_temp.reset_pos();
  execute p_mutation;
  v_expiry := pg_temp.deadline();
  v_restore := pg_temp.restore();
  v_heartbeat := pg_temp.heartbeat();
  return next is(v_restore->>'error', 'invalid_session', p_name || ': restore refuses');
  return next is(v_restore->>'reason', p_reason, p_name || ': restore reason');
  return next is(v_heartbeat->>'error', 'invalid_session', p_name || ': heartbeat refuses');
  return next is(pg_temp.deadline(), v_expiry, p_name || ': expiry unchanged');
  return next is(pg_temp.seen(), null::timestamptz, p_name || ': no activity write');
end
$$;
select * from pg_temp.denial('revoked session', $$update device_sessions set is_active=false, revoked_at=now() where id='be510001-0000-0000-0000-00000000e001'$$, 'revoked');
select * from pg_temp.denial('inactive session', $$update device_sessions set is_active=false where id='be510001-0000-0000-0000-00000000e001'$$, 'invalid');
select * from pg_temp.denial('revoked pairing', $$update device_pairings set status='revoked', revoked_at=now() where id='be510001-0000-0000-0000-00000000c001'$$, 'revoked');
select * from pg_temp.denial('suspended pairing', $$update device_pairings set status='suspended' where id='be510001-0000-0000-0000-00000000c001'$$, 'invalid');
select * from pg_temp.denial('deleted pairing', $$update device_pairings set deleted_at=now() where id='be510001-0000-0000-0000-00000000c001'$$, 'invalid');
select * from pg_temp.denial('inactive device', $$update devices set is_active=false where id='be510001-0000-0000-0000-00000000d001'$$, 'invalid');
select * from pg_temp.denial('deleted device', $$update devices set deleted_at=now() where id='be510001-0000-0000-0000-00000000d001'$$, 'invalid');
select * from pg_temp.denial('suspended organization', $$update organizations set status='suspended' where id='be510001-0000-0000-0000-00000000a000'$$, 'invalid');
select * from pg_temp.denial('deleted organization', $$update organizations set deleted_at=now() where id='be510001-0000-0000-0000-00000000a000'$$, 'invalid');
select * from pg_temp.denial('suspended restaurant', $$update restaurants set status='suspended' where id='be510001-0000-0000-0000-00000000a100'$$, 'invalid');
select * from pg_temp.denial('deleted restaurant', $$update restaurants set deleted_at=now() where id='be510001-0000-0000-0000-00000000a100'$$, 'invalid');
select * from pg_temp.denial('suspended branch', $$update branches set status='suspended' where id='be510001-0000-0000-0000-00000000a110'$$, 'invalid');
select * from pg_temp.denial('deleted branch', $$update branches set deleted_at=now() where id='be510001-0000-0000-0000-00000000a110'$$, 'invalid');
select * from pg_temp.denial('expired session', $$update device_sessions set expires_at=now()-interval '1 second' where id='be510001-0000-0000-0000-00000000e001'$$, 'expired');
select pg_temp.reset_pos();
select is(app.restore_device_session('be510001-0000-0000-0000-00000000d001', 'wrong-proof')->>'reason', 'invalid', 'wrong token gives no validity detail');
select is(public.heartbeat_device_session('be510001-0000-0000-0000-00000000d002', 'bizbot-fixture-pos')->>'reason', 'invalid', 'token cannot authorize another device');
select is(public.heartbeat_device_session('be510001-0000-0000-0000-00000000d004', 'bizbot-fixture-pos')->>'reason', 'invalid', 'token cannot authorize another tenant device');
select is((select expires_at from device_sessions where id='be510001-0000-0000-0000-00000000e004'), now()+interval '7 days', 'cross-tenant request does not renew the target');
select is((select last_seen_at from devices where id='be510001-0000-0000-0000-00000000d004'), null::timestamptz, 'cross-tenant request does not write target activity');
select is(public.heartbeat_device_session('be510001-0000-0000-0000-00000000ffff', 'bizbot-fixture-pos')->>'reason', 'invalid', 'unknown device is invalid');
select is(public.heartbeat_device_session(null, null)->>'error', 'invalid_session', 'missing proof fails closed');
select is(pg_temp.deadline(), now() + interval '7 days', 'wrong proof never renews the real session');
select is(pg_temp.seen(), null::timestamptz, 'wrong proof never advances activity');
select is(pg_temp.heartbeat('kds')->>'ok', 'true', 'KDS heartbeat is supported');
select is(pg_temp.heartbeat('kiosk')->>'ok', 'true', 'Kiosk heartbeat is supported');

-- Volatile activity extends sessions without depending on the new client RPC.
select pg_temp.reset_pos();
select is((app.report_kitchen_pos_status('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos',
  'test-build', (select kitchen_workflow_mode_revision from branches where id='be510001-0000-0000-0000-00000000a110'), true, 0, 'counted')->>'ok'),
  'true', 'existing POS status report succeeds');
select is(pg_temp.deadline(), now() + interval '30 days', 'existing POS status report renews');
select pg_temp.reset_pos();
select is((app.report_kitchen_pos_status('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos',
  'test-build', (select kitchen_workflow_mode_revision from branches where id='be510001-0000-0000-0000-00000000a110'), true, 0)->>'ok'),
  'true', 'legacy POS status overload succeeds');
select is(pg_temp.deadline(), now() + interval '30 days', 'legacy POS status overload renews');
select pg_temp.reset_pos();
select is((app.report_kitchen_printer_readiness('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos',
  'kitchen_printer_only_v1', 'test-build', 'kitchen_ticket', 'network', '80mm', '0123456789abcdef', true, 0,
  (select kitchen_workflow_mode_revision from branches where id='be510001-0000-0000-0000-00000000a110'), null)->>'ok'),
  'true', 'existing readiness report succeeds');
select is(pg_temp.deadline(), now() + interval '30 days', 'existing readiness report renews');
select pg_temp.reset_pos();
select isnt(app.pull_kitchen_print_dispatches('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos')->>'error',
  'invalid_session', 'dispatch pull accepts the device proof');
select is(pg_temp.deadline(), now()+interval '30 days', 'dispatch pull renews proven activity even with no dispatch work');
select pg_temp.reset_pos();
select isnt(app.acknowledge_kitchen_print_dispatch('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos',
  'be510001-0000-0000-0000-00000000ffff', 'transport_accepted', null)->>'error',
  'invalid_session', 'dispatch acknowledgement validates device proof before a missing business row');
select is(pg_temp.deadline(), now()+interval '30 days', 'dispatch acknowledgement counts proven activity');
update device_sessions set expires_at=now()+interval '7 days' where id='be510001-0000-0000-0000-00000000e003';
select is(public.kiosk_menu('be510001-0000-0000-0000-00000000d003', 'bizbot-fixture-kiosk')->>'ok', 'true', 'public kiosk menu works through volatile context');
select is(pg_temp.deadline('kiosk'), now() + interval '30 days', 'kiosk menu renews through its context');
update device_sessions set expires_at=now()+interval '7 days' where id='be510001-0000-0000-0000-00000000e003';
select is(public.kiosk_tables('be510001-0000-0000-0000-00000000d003', 'bizbot-fixture-kiosk')->>'ok', 'true', 'public kiosk tables works through volatile context');
select is(pg_temp.deadline('kiosk'), now() + interval '30 days', 'kiosk tables renews through its context');

-- Public/app privileges and the global surface must survive either migration order.
select ok(has_function_privilege('authenticated', 'public.heartbeat_device_session(uuid,text)', 'EXECUTE'), 'authenticated can call public heartbeat');
select ok(has_function_privilege('authenticated', 'app.heartbeat_device_session(uuid,text)', 'EXECUTE'), 'invoker wrapper can reach app heartbeat');
select ok(not has_function_privilege('anon', 'public.heartbeat_device_session(uuid,text)', 'EXECUTE'), 'anon cannot call public heartbeat');
select ok(not has_function_privilege('anon', 'app.heartbeat_device_session(uuid,text)', 'EXECUTE'), 'anon cannot call app heartbeat');
select ok(not has_function_privilege('authenticated', 'app.renew_device_session(uuid,text)', 'EXECUTE'), 'internal renewal is not a client API');
select is((select prosecdef from pg_proc where oid='public.heartbeat_device_session(uuid,text)'::regprocedure), false, 'public heartbeat is SECURITY INVOKER');
select is((select prosecdef from pg_proc where oid='app.heartbeat_device_session(uuid,text)'::regprocedure), true, 'app heartbeat is SECURITY DEFINER');
select is((select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and has_function_privilege('anon', p.oid, 'EXECUTE')),
  array['storefront_menu(text)'], 'anonymous executable surface remains exactly storefront_menu(text)');
select is((select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind='f' and p.prosecdef),
  array['storefront_menu(text)'], 'public definer surface remains exactly storefront_menu(text)');
select ok(not has_schema_privilege('anon', 'app', 'USAGE'), 'anon still has no app schema usage');
set local role anon;
select throws_ok($$select public.heartbeat_device_session('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos')$$,
  '42501', null, 'anonymous role is denied at heartbeat execution');
reset role;
set local role authenticated;
select throws_ok($$select app.renew_device_session('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos')$$,
  '42501', null, 'authenticated role cannot bypass the heartbeat wrapper through the internal helper');
select is(public.heartbeat_device_session('be510001-0000-0000-0000-00000000d001', 'bizbot-fixture-pos')->>'ok',
  'true', 'authenticated role reaches the helper through the authorized wrapper');
reset role;

-- Current Dashboard truth, including legacy NULL, and unchanged authorization.
set local app.current_app_user_id='be510001-0000-0000-0000-00000000a900';
select pg_temp.reset_pos(now()+interval '3 days');
update device_sessions set expires_at=null where id='be510001-0000-0000-0000-00000000e002';
update device_sessions set expires_at=now() where id='be510001-0000-0000-0000-00000000e003';
update devices set last_seen_at=now()-interval '2 hours' where id='be510001-0000-0000-0000-00000000d001';
create function pg_temp.listed(p_kind text) returns jsonb language sql as $$
  select e from jsonb_array_elements(app.list_devices('be510001-0000-0000-0000-00000000a000',
    'be510001-0000-0000-0000-00000000a100', 'be510001-0000-0000-0000-00000000a110')->'devices') e
  where e->>'device_id'=(select device_id::text from _bizbot_devices where kind=p_kind)
$$;
select is((app.list_devices('be510001-0000-0000-0000-00000000a000')->>'server_now')::timestamptz, now(), 'list_devices supplies authoritative server time');
select is(pg_temp.listed('pos')->>'has_open_session', 'true', 'live finite session is active');
select is((pg_temp.listed('pos')->>'session_expires_at')::timestamptz, now()+interval '3 days', 'list_devices supplies expiry');
select is((pg_temp.listed('pos')->>'last_seen_at')::timestamptz, now()-interval '2 hours', 'list_devices supplies last activity');
select is(pg_temp.listed('kds')->>'has_open_session', 'true', 'legacy NULL is still an active session');
select ok(pg_temp.listed('kds') ? 'session_expires_at' and pg_temp.listed('kds')->>'session_expires_at' is null, 'legacy NULL is explicit metadata');
select is(pg_temp.listed('kiosk')->>'has_open_session', 'false', 'exactly expired session is not active');
update device_sessions set is_active=false where id='be510001-0000-0000-0000-00000000e001';
select is(pg_temp.listed('pos')->>'has_open_session', 'false', 'inactive unrevoked session is not active');
update device_sessions set is_active=true, revoked_at=now() where id='be510001-0000-0000-0000-00000000e001';
select is(pg_temp.listed('pos')->>'has_open_session', 'false', 'revoked session is not active');
select pg_temp.reset_pos();
update device_pairings set status='suspended' where id='be510001-0000-0000-0000-00000000c001';
select is(pg_temp.listed('pos')->>'has_open_session', 'false', 'non-active authorizing pairing is not active');
select pg_temp.reset_pos();
set local app.current_app_user_id='be510001-0000-0000-0000-00000000a901';
select is(app.list_devices('be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
  'be510001-0000-0000-0000-00000000a110')->>'ok', 'true', 'manager retains scoped list authorization');
set local app.current_app_user_id='be510001-0000-0000-0000-00000000a902';
select is(app.list_devices('be510001-0000-0000-0000-00000000a000', 'be510001-0000-0000-0000-00000000a100',
  'be510001-0000-0000-0000-00000000a110')->>'error', 'permission_denied', 'cashier cannot list device management data');
set local app.current_app_user_id='be510001-0000-0000-0000-00000000a900';
select throws_ok($$select app.list_devices('be510001-0000-0000-0000-00000000b000')$$, '42501', null, 'owner cannot list another organization');
select ok(app.list_devices('be510001-0000-0000-0000-00000000a000')::text !~ '(session_token|enrollment_code_hash|session_token_ref)', 'list_devices discloses no credential fields');

-- Owner/manager can re-enroll the SAME identity; issue does not revoke, redeem does.
create temp table _bizbot_codes (kind text, response jsonb);
insert into _bizbot_codes values ('active', app.issue_device_enrollment_code(gen_random_uuid(), 'be510001-0000-0000-0000-00000000d001'));
select ok((select response->>'enrollment_code' is not null from _bizbot_codes where kind='active'), 'owner can issue a new code for an active device');
select is((select revoked_at from device_sessions where id='be510001-0000-0000-0000-00000000e001'), null::timestamptz, 'issuing the replacement code does not revoke the current session');
select pg_temp.reset_pos(now()-interval '1 day');
set local app.current_app_user_id='be510001-0000-0000-0000-00000000a901';
insert into _bizbot_codes values ('expired', app.issue_device_enrollment_code(gen_random_uuid(), 'be510001-0000-0000-0000-00000000d001'));
select ok((select response->>'enrollment_code' is not null from _bizbot_codes where kind='expired'), 'manager can issue a code for an expired session on the same active device');
create temp table _bizbot_redeem as
select app.redeem_device_pairing((select response->>'enrollment_code' from _bizbot_codes where kind='expired'), 'pos') as response;
select is((select response->>'ok' from _bizbot_redeem), 'true', 'same-device replacement code redeems');
select is((select response->>'device_id' from _bizbot_redeem), 'be510001-0000-0000-0000-00000000d001', 'redemption preserves device identity');
select ok((select revoked_at is not null and not is_active from device_sessions where id='be510001-0000-0000-0000-00000000e001'), 'redemption revokes the prior session');
select is((select expires_at from device_sessions where id=(select (response->>'device_session_id')::uuid from _bizbot_redeem)), now()+interval '30 days', 'redeemed replacement receives the 30-day window');
select is((select count(*)::integer from devices where organization_id='be510001-0000-0000-0000-00000000a000'), 3, 'same-device re-enrollment creates no replacement device row');
select is((select count(*)::integer from audit_events where organization_id='be510001-0000-0000-0000-00000000a000'
  and action='device.enrollment_code_issued'), 2, 'both owner and manager code issuances remain audited');

-- The legacy management minting path must not leave another uncapped session.
set local app.current_app_user_id='be510001-0000-0000-0000-00000000a900';
create temp table _bizbot_legacy as
select app.start_device_session(gen_random_uuid(), 'be510001-0000-0000-0000-00000000c002') as response;
select is((select response->>'ok' from _bizbot_legacy), 'true', 'legacy start_device_session still succeeds');
select is((select expires_at from device_sessions where id=(select (response->>'device_session_id')::uuid from _bizbot_legacy)), now()+interval '30 days', 'legacy start_device_session now mints a finite 30-day lease');

select * from finish();
rollback;
