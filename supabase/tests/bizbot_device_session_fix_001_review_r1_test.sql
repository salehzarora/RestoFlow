-- BIZBOT-DEVICE-SESSION-FIX-001: idle renewal, refusal, compatibility and admin contracts.
-- Synthetic fixtures only; every mutation, including audit, rolls back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
select no_plan();

insert into organizations (id, name, slug, default_currency) values
  ('be510002-0000-0000-0000-00000000a000', 'BIZBOT session test A', 'bizbot-session-fix-r1-a', 'USD'),
  ('be510002-0000-0000-0000-00000000b000', 'BIZBOT session test B', 'bizbot-session-fix-r1-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('be510002-0000-0000-0000-00000000a100', 'be510002-0000-0000-0000-00000000a000', 'Test restaurant'),
  ('be510002-0000-0000-0000-00000000b100', 'be510002-0000-0000-0000-00000000b000', 'Other test restaurant');
insert into branches (id, organization_id, restaurant_id, name) values
  ('be510002-0000-0000-0000-00000000a110', 'be510002-0000-0000-0000-00000000a000',
   'be510002-0000-0000-0000-00000000a100', 'Test branch'),
  ('be510002-0000-0000-0000-00000000b110', 'be510002-0000-0000-0000-00000000b000',
   'be510002-0000-0000-0000-00000000b100', 'Other test branch');
insert into app_users (id, email) values
  ('be510002-0000-0000-0000-00000000a900', 'bizbot-session-owner@example.test'),
  ('be510002-0000-0000-0000-00000000a901', 'bizbot-session-manager@example.test'),
  ('be510002-0000-0000-0000-00000000a902', 'bizbot-session-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('be510002-0000-0000-0000-00000000f001', 'be510002-0000-0000-0000-00000000a900',
   'be510002-0000-0000-0000-00000000a000', null, null, 'org_owner'),
  ('be510002-0000-0000-0000-00000000f002', 'be510002-0000-0000-0000-00000000a901',
   'be510002-0000-0000-0000-00000000a000', 'be510002-0000-0000-0000-00000000a100',
   'be510002-0000-0000-0000-00000000a110', 'manager'),
  ('be510002-0000-0000-0000-00000000f003', 'be510002-0000-0000-0000-00000000a902',
   'be510002-0000-0000-0000-00000000a000', 'be510002-0000-0000-0000-00000000a100',
   'be510002-0000-0000-0000-00000000a110', 'cashier');

create temp table _bizbot_devices (kind text primary key, device_id uuid, pairing_id uuid, session_id uuid, proof text);
insert into _bizbot_devices values
  ('pos', 'be510002-0000-0000-0000-00000000d001', 'be510002-0000-0000-0000-00000000c001', 'be510002-0000-0000-0000-00000000e001', 'bizbot-fixture-pos'),
  ('kds', 'be510002-0000-0000-0000-00000000d002', 'be510002-0000-0000-0000-00000000c002', 'be510002-0000-0000-0000-00000000e002', 'bizbot-fixture-kds'),
  ('kiosk', 'be510002-0000-0000-0000-00000000d003', 'be510002-0000-0000-0000-00000000c003', 'be510002-0000-0000-0000-00000000e003', 'bizbot-fixture-kiosk');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label)
select device_id, 'be510002-0000-0000-0000-00000000a000', 'be510002-0000-0000-0000-00000000a100',
       'be510002-0000-0000-0000-00000000a110', kind, 'BIZBOT test ' || kind from _bizbot_devices;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at)
select pairing_id, 'be510002-0000-0000-0000-00000000a000', 'be510002-0000-0000-0000-00000000a100',
       'be510002-0000-0000-0000-00000000a110', device_id, 'active', now() from _bizbot_devices;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, expires_at)
select session_id, 'be510002-0000-0000-0000-00000000a000', 'be510002-0000-0000-0000-00000000a100',
       'be510002-0000-0000-0000-00000000a110', device_id, pairing_id, app.hash_provisioning_secret(proof), now() + interval '7 days'
from _bizbot_devices;

insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('be510002-0000-0000-0000-00000000d004', 'be510002-0000-0000-0000-00000000b000',
   'be510002-0000-0000-0000-00000000b100', 'be510002-0000-0000-0000-00000000b110', 'pos', 'Other tenant device');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('be510002-0000-0000-0000-00000000c004', 'be510002-0000-0000-0000-00000000b000',
   'be510002-0000-0000-0000-00000000b100', 'be510002-0000-0000-0000-00000000b110',
   'be510002-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, expires_at) values
  ('be510002-0000-0000-0000-00000000e004', 'be510002-0000-0000-0000-00000000b000',
   'be510002-0000-0000-0000-00000000b100', 'be510002-0000-0000-0000-00000000b110',
   'be510002-0000-0000-0000-00000000d004', 'be510002-0000-0000-0000-00000000c004',
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
  update organizations set status = 'active', deleted_at = null where id = 'be510002-0000-0000-0000-00000000a000';
  update restaurants set status = 'active', deleted_at = null where id = 'be510002-0000-0000-0000-00000000a100';
  update branches set status = 'active', deleted_at = null where id = 'be510002-0000-0000-0000-00000000a110';
  update devices set is_active = true, deleted_at = null, last_seen_at = null where id = 'be510002-0000-0000-0000-00000000d001';
  update device_pairings set status = 'active', revoked_at = null, deleted_at = null where id = 'be510002-0000-0000-0000-00000000c001';
  update device_sessions set is_active = true, revoked_at = null, expires_at = p_expiry where id = 'be510002-0000-0000-0000-00000000e001';
end
$$;

-- Review-round regression cases. Every test fixture and audit write rolls back.
set local app.current_app_user_id='be510002-0000-0000-0000-00000000a900';
create function pg_temp.listed() returns jsonb language sql as $$
  select e from jsonb_array_elements(app.list_devices('be510002-0000-0000-0000-00000000a000')->'devices') e
  where e->>'device_id'='be510002-0000-0000-0000-00000000d001'
$$;
create function pg_temp.activity(p_path text) returns jsonb language plpgsql as $$
declare d uuid; t text; rev integer;
begin
  select device_id, proof into d,t from _bizbot_devices where kind=case when p_path like 'kiosk%' then 'kiosk' else 'pos' end;
  select kitchen_workflow_mode_revision into rev from branches where id='be510002-0000-0000-0000-00000000a110';
  case p_path
    when 'readiness12' then return public.report_kitchen_printer_readiness(d,t,'kitchen_printer_only_v1','test-build','kitchen_ticket','network','80mm','0123456789abcdef',true,0,rev,null);
    when 'readiness11' then return public.report_kitchen_printer_readiness(d,t,'kitchen_printer_only_v1','test-build','kitchen_ticket','network','80mm','0123456789abcdef',true,0,rev);
    when 'status7' then return public.report_kitchen_pos_status(d,t,'test-build',rev,true,0,'counted');
    when 'status6' then return public.report_kitchen_pos_status(d,t,'test-build',rev,true,0);
    when 'pull' then return public.pull_kitchen_print_dispatches(d,t);
    when 'ack' then return public.acknowledge_kitchen_print_dispatch(d,t,'be510002-0000-0000-0000-00000000ffff','transport_accepted',null);
    when 'kiosk_menu' then return public.kiosk_menu(d,t);
    when 'kiosk_tables' then return public.kiosk_tables(d,t);
    when 'kiosk_submit' then return public.kiosk_submit_order(
      d,t,gen_random_uuid(),'r2-synthetic-'||gen_random_uuid()::text,
      'takeaway',null,'USD',null,null,null,
      jsonb_build_array(jsonb_build_object(
        'menu_item_id','be510002-0000-0000-0000-000000007002',
        'menu_item_name_snapshot','BIZBOT test drink','quantity',1,
        'unit_price_minor_snapshot',100)),100,0,0,100);
    when 'kiosk_context' then return (select jsonb_build_object('ok',o_session is not null,'error',case when o_session is null then 'invalid_session' end) from app.kiosk_session_context(d,t));
    else raise exception 'unknown test path %',p_path;
  end case;
end
$$;
create temp table _r1_paths(path text primary key);
insert into _r1_paths values ('readiness12'),('readiness11'),('status7'),('status6'),('pull'),('ack'),('kiosk_menu'),('kiosk_tables'),('kiosk_submit'),('kiosk_context');

-- G1: exercise a real accepted kiosk submit, not merely a payload refusal
-- after token proof. These synthetic orders and their audit writes roll back.
insert into menu_categories(id,organization_id,restaurant_id,name,is_active) values
  ('be510002-0000-0000-0000-000000007001','be510002-0000-0000-0000-00000000a000',
   'be510002-0000-0000-0000-00000000a100','BIZBOT test category',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active) values
  ('be510002-0000-0000-0000-000000007002','be510002-0000-0000-0000-00000000a000',
   'be510002-0000-0000-0000-00000000a100','be510002-0000-0000-0000-000000007001',
   'BIZBOT test drink',100,'USD',true);

create function pg_temp.suspension(p_table text,p_id uuid) returns setof text language plpgsql as $$
declare p record; kind text; before_expiry timestamptz; result jsonb;
begin
  perform pg_temp.reset_pos();
  execute format('update public.%I set status=''suspended'' where id=$1',p_table) using p_id;
  return next is(pg_temp.restore()->>'ok','true','F2 '||p_table||': restore accepts reversible suspension');
  return next is(pg_temp.deadline(),now()+interval '30 days','F2 '||p_table||': suspended restore renews');
  update device_sessions set expires_at=now()+interval '7 days' where id='be510002-0000-0000-0000-00000000e001';
  return next is(pg_temp.heartbeat()->>'ok','true','F2 '||p_table||': heartbeat accepts reversible suspension');
  return next is(pg_temp.deadline(),now()+interval '30 days','F2 '||p_table||': suspended heartbeat renews');
  return next is(pg_temp.listed()->>'has_open_session','true','F2 '||p_table||': Dashboard session stays valid while scope suspended');
  for p in select path from _r1_paths order by path loop
    kind := case when p.path like 'kiosk%' then 'kiosk' else 'pos' end;
    update device_sessions set expires_at=now()+interval '7 days' where id in (select session_id from _bizbot_devices);
    update devices set last_seen_at=null where id in (select device_id from _bizbot_devices);
    result := pg_temp.activity(p.path);
    if kind='kiosk' then
      return next is(result->>'ok','true','G1 '||p_table||' '||p.path||': suspended scope preserves main kiosk behavior');
      return next is(pg_temp.deadline(kind),now()+interval '30 days','G1 '||p_table||' '||p.path||': suspended kiosk activity renews');
      return next is(pg_temp.seen(kind),now(),'G1 '||p_table||' '||p.path||': suspended kiosk activity is recorded');
      if p.path='kiosk_submit' then
        return next ok(exists(select 1 from orders
          where id=(result->>'order_id')::uuid and status='submitted'
            and device_id='be510002-0000-0000-0000-00000000d003'
            and grand_total_minor=100),
          'G1 '||p_table||': suspended kiosk submit persists the real order');
      end if;
    else
      return next is(result->>'ok','false','G1 '||p_table||' '||p.path||': kitchen scope gate refuses');
      return next is(pg_temp.deadline(kind),now()+interval '7 days','G1 '||p_table||' '||p.path||': kitchen gate precedes renewal');
      return next is(pg_temp.seen(kind),null::timestamptz,'G1 '||p_table||' '||p.path||': denied kitchen work records no activity');
    end if;
  end loop;
  execute format('update public.%I set status=''active'' where id=$1',p_table) using p_id;
  return next is(pg_temp.restore()->>'ok','true','F2 '||p_table||': same token works after reactivation');
end
$$;
select * from pg_temp.suspension('organizations','be510002-0000-0000-0000-00000000a000');
select * from pg_temp.suspension('restaurants','be510002-0000-0000-0000-00000000a100');
select * from pg_temp.suspension('branches','be510002-0000-0000-0000-00000000a110');

-- S5: activity has its own strict hourly throttle, independent of deadline.
select pg_temp.reset_pos(now()+interval '40 days');
select is(pg_temp.heartbeat()->>'ok','true','S5 fresh device heartbeat succeeds');
select is(pg_temp.seen(),now(),'S5 NULL activity initializes even with a far-future expiry');
select is(pg_temp.deadline(),now()+interval '40 days','S5 activity-only update never shortens expiry');
update devices set last_seen_at=now()-interval '1 hour' where id='be510002-0000-0000-0000-00000000d001';
select pg_temp.heartbeat();
select is(pg_temp.seen(),now()-interval '1 hour','S5 exact activity boundary does not write');
update devices set last_seen_at=now()-interval '1 hour 1 microsecond' where id='be510002-0000-0000-0000-00000000d001';
select pg_temp.heartbeat();
select is(pg_temp.seen(),now(),'S5 older activity refreshes despite throttled expiry');
update device_sessions set expires_at=now()+interval '7 days' where id='be510002-0000-0000-0000-00000000e001';
update devices set last_seen_at=now()-interval '10 minutes' where id='be510002-0000-0000-0000-00000000d001';
select pg_temp.heartbeat();
select is(pg_temp.deadline(),now()+interval '30 days','S5 due expiry still renews');
select is(pg_temp.seen(),now(),'S5 due expiry renewal records activity even within activity throttle');

-- S8: latest VALID row wins over a later revoked row, then latest overall if none.
select pg_temp.reset_pos(now()+interval '3 days');
update device_sessions set started_at=now()-interval '2 days' where id='be510002-0000-0000-0000-00000000e001';
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,started_at,expires_at,is_active,revoked_at)
select 'be510002-0000-0000-0000-00000000e005',organization_id,restaurant_id,branch_id,device_id,device_pairing_id,
 app.hash_provisioning_secret('r1-newer-revoked'),now()-interval '1 day',now()+interval '9 days',false,now()
from device_sessions where id='be510002-0000-0000-0000-00000000e001';
select is(pg_temp.listed()->>'has_open_session','true','S8 older valid session keeps device active despite newer revoked session');
select is((pg_temp.listed()->>'session_expires_at')::timestamptz,now()+interval '3 days','S8 metadata comes from older valid session');
update device_sessions set expires_at=now() where id='be510002-0000-0000-0000-00000000e001';
select is(pg_temp.listed()->>'has_open_session','false','S8 no valid sessions means no open session');
select is((pg_temp.listed()->>'session_expires_at')::timestamptz,now()+interval '9 days','S8 no valid sessions exposes latest historical deadline');

-- Every volatile entry point refuses both expiry and revocation without writes.
create function pg_temp.refused_activity(p_condition text) returns setof text language plpgsql as $$
declare p record; kind text; result jsonb; before_expiry timestamptz;
begin
  for p in select path from _r1_paths order by path loop
    kind := case when p.path like 'kiosk%' then 'kiosk' else 'pos' end;
    update device_sessions set is_active=true,revoked_at=null,expires_at=now()+interval '7 days' where id in (select session_id from _bizbot_devices);
    update devices set last_seen_at=null where id in (select device_id from _bizbot_devices);
    if p_condition='revoked' then
      update device_sessions set is_active=false,revoked_at=now() where id in (select session_id from _bizbot_devices);
    else
      update device_sessions set expires_at=now() where id in (select session_id from _bizbot_devices);
    end if;
    before_expiry := pg_temp.deadline(kind);
    result := pg_temp.activity(p.path);
    return next is(result->>'error','invalid_session','S8 '||p.path||' refuses '||p_condition||' session');
    return next is(pg_temp.deadline(kind),before_expiry,'S8 '||p.path||' '||p_condition||': no deadline write');
    return next is(pg_temp.seen(kind),null::timestamptz,'S8 '||p.path||' '||p_condition||': no activity write');
  end loop;
end
$$;
select * from pg_temp.refused_activity('revoked');
select * from pg_temp.refused_activity('expired');

-- F5 + S8: latest code metadata; issuing does not revoke, redemption does.
select pg_temp.reset_pos();
update device_pairings set created_at=now()-interval '1 day' where id='be510002-0000-0000-0000-00000000c001';
create temp table _r1_code as select app.issue_device_enrollment_code(gen_random_uuid(),'be510002-0000-0000-0000-00000000d001') as response;
select ok(pg_temp.listed() ? 'code_expires_at','F5 list includes additive code_expires_at');
select is((pg_temp.listed()->>'code_expires_at')::timestamptz,
 (select code_expires_at from device_pairings where id=(select (response->>'device_pairing_id')::uuid from _r1_code)),
 'F5 list returns latest issued pairing code deadline');
select is(pg_temp.restore()->>'ok','true','S8 old token still restores after issuing a replacement code');
select is(pg_temp.listed()->>'has_open_session','true','S8 issued replacement code does not hide old valid session');
update device_pairings set code_expires_at=now()-interval '1 second' where id=(select (response->>'device_pairing_id')::uuid from _r1_code);
select is((pg_temp.listed()->>'code_expires_at')::timestamptz,now()-interval '1 second','F5 expired unused code deadline stays visible');
select is(pg_temp.restore()->>'ok','true','S8 unused expired replacement code does not revoke old token');
update device_pairings set code_expires_at=now()+interval '10 minutes' where id=(select (response->>'device_pairing_id')::uuid from _r1_code);
create temp table _r1_redeem as select app.redeem_device_pairing((select response->>'enrollment_code' from _r1_code),'pos') as response;
select is((select response->>'ok' from _r1_redeem),'true','S8 replacement redemption succeeds');
select is(pg_temp.restore()->>'reason','revoked','S8 old token is explicitly revoked after replacement redemption');
select is(pg_temp.heartbeat()->>'reason','revoked','S8 old heartbeat token is revoked after replacement redemption');
select * from finish();
rollback;
