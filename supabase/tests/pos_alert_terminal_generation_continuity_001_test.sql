-- Platform onboarding and real public RPCs. Synthetic, rollback-only; no HTTP.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.tc_id(label text) returns uuid language sql immutable as $$
  select md5('bizbot-terminal-continuity-synthetic-'||label)::uuid; $$;
create function pg_temp.tc_client(n integer) returns uuid language sql immutable as $$
  select ('35300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create temp table _tc_rest as select label,
  pg_temp.tc_id(case when label='b1' then 'org-b' else 'org-a' end) org,
  pg_temp.tc_id('restaurant-'||label) restaurant,pg_temp.tc_id('branch-'||label) branch,
  pg_temp.tc_id('category-'||label) category,pg_temp.tc_id('item-'||label) item
  from unnest(array['a1','a2','b1']) label;
insert into organizations(id,name,slug,default_currency,status) values
  (pg_temp.tc_id('org-a'),'Platform A','terminal-continuity-a','ILS','active'),
  (pg_temp.tc_id('org-b'),'Platform B','terminal-continuity-b','ILS','active');
insert into restaurants(id,organization_id,name,timezone) select restaurant,org,'Synthetic '||label,'UTC' from _tc_rest;
insert into branches(id,organization_id,restaurant_id,name,timezone,kitchen_workflow_mode)
  select branch,org,restaurant,'Synthetic branch '||label,'UTC',case when label='a2' then 'kds' else 'printer_only' end from _tc_rest;
insert into menu_categories(id,organization_id,restaurant_id,name) select category,org,restaurant,'Synthetic Food' from _tc_rest;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
  select item,org,restaurant,category,'Saved product '||label,1000,'ILS' from _tc_rest;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,
  pickup_enabled,opening_hours,is_published)
select restaurant,org,branch,'terminal-continuity-'||label,'Synthetic '||label,true,
  jsonb_build_object('weekly',(select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c))
    from generate_series(0,6) d cross join(values('00:00','12:00'),('11:00','00:00')) w(o,c)),'exceptions','[]'::jsonb),true
  from _tc_rest;
select is((select count(*) from app.online_order_settings where organization_id in(pg_temp.tc_id('org-a'),pg_temp.tc_id('org-b'))),3::bigint,
  'three arbitrary branches auto-provision before their storefront publication');
select is((select count(*) from web_order_channel_settings where submission_enabled),3::bigint,'channels automatically enabled without backend operator');
select ok((public.storefront_menu('terminal-continuity-'||label)#>>'{service,ordering_enabled}')::boolean,label||' published Pickup checkout enabled') from _tc_rest;
select ok(not exists(select 1 from app.online_order_live_requests),'onboarding never backfills old requests');
select ok(not exists(select 1 from public.web_order_print_attempts),'onboarding never creates print attempts');
create temp table _tc_staff as
  select n,r.*,pg_temp.tc_id('device-'||n) device,pg_temp.tc_id('pairing-'||n) pairing,
    pg_temp.tc_id('session-'||n) session,pg_temp.tc_id('staff-'||n) staff,
    pg_temp.tc_id('membership-'||n) membership,pg_temp.tc_id('employee-'||n) employee,
    pg_temp.tc_id('pin-'||n) pin,pg_temp.tc_id('shift-'||n) shift
  from generate_series(1,4) n join _tc_rest r on r.label=case when n=3 then 'b1' when n=4 then 'a2' else 'a1' end;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type) select device,org,restaurant,branch,'pos' from _tc_staff;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status) select pairing,org,restaurant,branch,device,'active' from _tc_staff;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
  select session,org,restaurant,branch,device,pairing,app.hash_provisioning_secret('synthetic-platform353-token-'||n),now()+interval '30 days' from _tc_staff;
insert into app_users(id,email) select staff,'platform353-'||n||'@example.test' from _tc_staff;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) select membership,staff,org,restaurant,branch,'cashier' from _tc_staff;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
  select employee,org,restaurant,branch,staff,membership,'Synthetic cashier '||n from _tc_staff;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
  select pin,org,restaurant,branch,session,employee,membership,now()+interval '6 hours' from _tc_staff;
insert into shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
  select shift,org,restaurant,branch,device,employee,membership,'platform353-open-'||n,'open' from _tc_staff;
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
  select pg_temp.tc_id('printer-'||label),org,restaurant,branch,'Synthetic kitchen','network','kitchen','80mm',true from _tc_rest where label<>'a2';
insert into kitchen_printer_readiness_reports(organization_id,restaurant_id,branch_id,device_id,capability,app_build,
  printer_purpose,transport_kind,paper_width,printer_fingerprint,secure_spool_available,unresolved_local_jobs,
  mode_revision,printer_assignment_id,expires_at)
  select org,restaurant,branch,device,'kitchen_printer_only_v1','synthetic-platform353','kitchen_ticket','network','80mm',repeat('a',64),
    true,0,1,pg_temp.tc_id('printer-'||label),clock_timestamp()+interval '10 minutes' from _tc_staff where n<4;
create function pg_temp.tc_submit(n integer,label text default 'a1') returns jsonb language sql volatile as $$
  select public.submit_web_order_platform_request('terminal-continuity-'||label,pg_temp.tc_client(n),repeat('a',64),
    jsonb_build_object('order_type','takeaway','customer',jsonb_build_object('name','Synthetic Guest','phone','+9725200'||lpad(n::text,5,'0')),
      'notes','Saved customer note','items',jsonb_build_array(jsonb_build_object('menu_item_id',pg_temp.tc_id('item-'||label),
        'quantity',2,'notes','Saved item note','modifiers','[]'::jsonb)))); $$;
create function pg_temp.tc_request(n integer) returns uuid language sql stable security definer set search_path='' as $$
  select id from public.web_order_requests where client_request_id=pg_temp.tc_client(n); $$;
create function pg_temp.tc_inbox(n integer) returns jsonb language sql volatile as $$
  select public.pos_web_order_inbox(pg_temp.tc_id('pin-'||n),pg_temp.tc_id('device-'||n),'synthetic-platform353-token-'||n); $$;
create function pg_temp.tc_accept(n integer,device integer default 1) returns jsonb language sql volatile as $$
  select public.pos_accept_web_order(pg_temp.tc_id('pin-'||device),pg_temp.tc_id('device-'||device),
    'synthetic-platform353-token-'||device,pg_temp.tc_request(n),pg_temp.tc_client(1000+n+device)); $$;
create function pg_temp.tc_register(n integer) returns jsonb language sql volatile as $$
  select public.pos_register_order_alert(pg_temp.tc_id('installation-'||n),'synthetic-platform353-fcm-token-'||n,repeat('a',64),
    pg_temp.tc_id('device-'||n),pg_temp.tc_id('pin-'||n),'synthetic-platform353-token-'||n); $$;
create temp table _tc_results(label text primary key,r jsonb);
grant all on _tc_results to authenticated,service_role;
select set_config('request.jwt.claim.sub',pg_temp.tc_id('transport-user')::text,true);
select app.set_pos_order_alerts(true,'Synthetic platform notification gate','platform353-test');

-- This suite uses synthetic transactions only. No HTTP, FCM send, print operation
-- or owner reconciliation approval is invoked. All fixture writes roll back.
create function pg_temp.tc_reject(n integer,device integer default 2) returns jsonb language sql volatile as $$
  select public.pos_reject_web_order_customer(pg_temp.tc_id('pin-'||device),pg_temp.tc_id('device-'||device),
    'synthetic-platform353-token-'||device,pg_temp.tc_request(n),pg_temp.tc_client(2000+n+device),'Synthetic unavailable'); $$;
create function pg_temp.tc_finish(label text,outcome text default 'sent') returns boolean language sql volatile as $$
  select bool_and((public.pos_finish_order_alert_delivery((x->>'delivery_id')::uuid,(x->>'lease_id')::uuid,outcome)->>'ok')::boolean)
  from jsonb_array_elements((select r->'deliveries' from _tc_results where _tc_results.label=tc_finish.label)) x; $$;
create function pg_temp.tc_finish_registration(label text,registration uuid,outcome text) returns boolean language sql volatile as $$
  select bool_and((public.pos_finish_order_alert_delivery((x->>'delivery_id')::uuid,(x->>'lease_id')::uuid,outcome)->>'ok')::boolean)
  from jsonb_array_elements((select r->'deliveries' from _tc_results where _tc_results.label=tc_finish_registration.label)) x
  where (x->>'registration_id')::uuid=registration; $$;
create function pg_temp.tc_status(device integer default 1,secret text default repeat('a',64)) returns jsonb language sql volatile as $$
  select public.pos_order_alert_status(pg_temp.tc_id('installation-'||device),encode(sha256(convert_to(secret,'UTF8')),'hex')); $$;
create temp table _tc_unrelated_functions as select oid,pg_get_functiondef(oid) definition,proacl
  from pg_proc where oid in('app.pos_order_alert_authority(app.pos_order_alert_registrations)'::regprocedure,
    'app.pos_register_order_alert(uuid,text,text,uuid,uuid,text)'::regprocedure,
    'app.pos_refresh_order_alert_token(uuid,text,text,uuid)'::regprocedure,
    'app.pos_finish_order_alert_delivery(uuid,uuid,text)'::regprocedure);
create temp table _tc_history_before as select count(*) n from supabase_migrations.schema_migrations;
set local role authenticated;
select is(pg_temp.tc_register(n)->>'ok','true','synthetic paired device registers: '||n) from generate_series(1,4) n;
reset role;
create temp table _tc_peer_registration as select to_jsonb(r) value from app.pos_order_alert_registrations r where device_id=pg_temp.tc_id('device-2');
create temp table _tc_foreign_registration as select to_jsonb(r) value from app.pos_order_alert_registrations r where device_id=pg_temp.tc_id('device-4');
create temp table _tc_original_generation as select id,generation from app.pos_order_alert_registrations where device_id=pg_temp.tc_id('device-1');
grant select on _tc_original_generation to service_role;

-- Exact incident: initial fanout -> same-registration foreground generation
-- rollover -> another POS rejects -> only the current generation may send cancel.
set local role service_role;
select is(pg_temp.tc_submit(1)->>'ok','true','natural-writer synthetic request enters');
insert into _tc_results values('initial',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('initial'),true,'both initial pending deliveries finish');
reset role;
create temp table _tc_initial_pending as select id,to_jsonb(d) value from app.pos_order_alert_deliveries d where request_id=pg_temp.tc_request(1) and kind='pending';
set local role authenticated;
select is(pg_temp.tc_register(1)->>'ok','true','foreground renewal succeeds without weakening generation fencing');
select is(pg_temp.tc_reject(1)->>'ok','true','other POS commits rejection');
reset role;
select ok((select r.generation<>b.generation from app.pos_order_alert_registrations r join _tc_original_generation b using(id)),
  'foreground renewal actually changed generation');
set local role service_role;
insert into _tc_results values('resolved',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where r.device_id=pg_temp.tc_id('device-1') and d.request_id=pg_temp.tc_request(1) and d.kind='terminal' and d.generation=r.generation),1::bigint,
  'current generation receives terminal after foreground renewal');
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where r.device_id=pg_temp.tc_id('device-2') and d.request_id=pg_temp.tc_request(1) and d.kind='terminal' and d.generation=r.generation),1::bigint,
  'unchanged peer generation still receives terminal');
select ok(not exists(select 1 from _tc_initial_pending b join app.pos_order_alert_deliveries d using(id) where to_jsonb(d)<>b.value),
  'sent pending history is byte-for-byte unchanged by terminal synthesis');
set local role service_role;
select is(pg_temp.tc_finish('resolved'),true,'current terminal delivery leases finish normally');
insert into _tc_results values('resolved-replay',public.pos_claim_order_alert_deliveries());
select is(jsonb_array_length((select r->'deliveries' from _tc_results where label='resolved-replay')),0,'repeated claim does not replay completed terminal hints');
reset role;

-- Multiple pending requests: renewing cannot replay old arrivals, and resolving
-- one must not remove the other's authoritative notification coverage.
set local role service_role;
select is(pg_temp.tc_submit(2)->>'ok','true','second pending request enters');
select is(pg_temp.tc_submit(3)->>'ok','true','third pending request enters');
insert into _tc_results values('multiple-pending',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('multiple-pending'),true,'multiple pending leases finish');
reset role;
set local role authenticated;
select is(pg_temp.tc_register(1)->>'ok','true','same installation renews before remote resolution');
select is(pg_temp.tc_reject(2)->>'ok','true','other POS resolves only the second request');
reset role;
set local role service_role;
insert into _tc_results values('one-of-many',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('one-of-many'),true,'resolved subset terminal leases finish');
select is(jsonb_array_length(pg_temp.tc_status()->'requests'),1,'full status retains the genuinely pending third request');
select is(pg_temp.tc_status()#>>'{requests,0,request_id}',pg_temp.tc_request(3)::text,'remaining request identity is exact');
reset role;
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where r.device_id=pg_temp.tc_id('device-1') and d.request_id=pg_temp.tc_request(3) and d.kind='pending' and d.generation=r.generation),1::bigint,
  'fresh generation retains exactly one wake for genuinely pending coverage');
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where r.device_id=pg_temp.tc_id('device-1') and d.request_id=pg_temp.tc_request(1) and d.kind='pending' and d.generation=r.generation),0::bigint,
  'resolved historical request never acquires a new pending wake');
set local role authenticated;
select is(pg_temp.tc_accept(3,2)->>'ok','true','accepted terminal state also uses the ordinary synthetic SQL writer');
reset role;
set local role service_role;
insert into _tc_results values('accepted',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('accepted'),true,'acceptance terminal leases finish');
select is(jsonb_array_length(pg_temp.tc_status()->'requests'),0,'accepted final request leaves an empty authoritative set');
reset role;

-- Claim -> token generation rollover -> old finish is uncertain/invalid_token.
-- Its historical ledger may finish, but cannot disable or restore the new token.
set local role service_role;
select is(pg_temp.tc_submit(4)->>'ok','true','token-race request enters');
insert into _tc_results values('token-old-lease',public.pos_claim_order_alert_deliveries());
reset role;
create temp table _tc_token_before as select id,generation,authority_expires_at,registered_at from app.pos_order_alert_registrations where device_id=pg_temp.tc_id('device-1');
create temp table _tc_token_peer as select id from app.pos_order_alert_registrations where device_id=pg_temp.tc_id('device-2');
grant select on _tc_token_before,_tc_token_peer to service_role;
set local role service_role;
select is(public.pos_refresh_order_alert_token(pg_temp.tc_id('installation-1'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  'synthetic-terminal-rotated-token-1',(select generation from _tc_token_before))->>'ok','true','authorized token refresh wins a new generation');
select is(pg_temp.tc_finish_registration('token-old-lease',(select id from _tc_token_before),'invalid_token'),true,
  'old leased outcome may finish without owning the new token');
select is(pg_temp.tc_finish_registration('token-old-lease',(select id from _tc_token_peer),'sent'),true,
  'unrelated peer finishes normally and is never disabled');
reset role;
select ok((select r.enabled and r.generation<>b.generation and r.authority_expires_at=b.authority_expires_at and r.registered_at=b.registered_at
  from app.pos_order_alert_registrations r join _tc_token_before b using(id)),
  'old invalid-token finish neither disables nor extends the new registration');
set local role authenticated;
select is(pg_temp.tc_reject(4)->>'ok','true','token-race request resolves');
reset role;
set local role service_role;
insert into _tc_results values('token-current-terminal',public.pos_claim_order_alert_deliveries());
reset role;
select ok(exists(select 1 from jsonb_array_elements((select r->'deliveries' from _tc_results where label='token-current-terminal')) x
  join app.pos_order_alert_registrations r on r.id=(x->>'registration_id')::uuid
  where r.device_id=pg_temp.tc_id('device-1') and x->>'generation'=r.generation::text and x->>'kind'='terminal'
    and x->>'fcm_token'='synthetic-terminal-rotated-token-1'),'new terminal lease uses only the current generation/token');
set local role service_role;
select is(pg_temp.tc_finish('token-current-terminal'),true,'new token terminal leases finish');
select is(public.pos_refresh_order_alert_token(pg_temp.tc_id('installation-1'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  'synthetic-stale-token-must-not-restore',(select generation from _tc_token_before))->>'error','unauthorized','stale token refresh CAS remains rejected');
reset role;

-- More than 100 old generations of A must not consume the terminal fanout
-- bound and starve B. These rows are synthetic historical evidence only.
insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind,state,attempt_count,sent_at)
select r.id,pg_temp.tc_id('old-duplicate-'||n),pg_temp.tc_request(1),'pending','sent',1,clock_timestamp()
  from app.pos_order_alert_registrations r cross join generate_series(1,105) n where r.device_id=pg_temp.tc_id('device-1');
create temp table _tc_duplicate_history as select id,to_jsonb(d) value from app.pos_order_alert_deliveries d where state='sent';
set local role authenticated;
select is(pg_temp.tc_register(1)->>'ok','true','fresh foreground generation for folded historical coverage');
reset role;
set local role service_role;
insert into _tc_results values('folded-history',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where r.device_id=pg_temp.tc_id('device-1') and d.generation=r.generation and d.kind='terminal' and d.request_id in
    (pg_temp.tc_request(1),pg_temp.tc_request(2),pg_temp.tc_request(3),pg_temp.tc_request(4))),4::bigint,
  'historical generations are folded before the 100-row terminal bound');
select ok(not exists(select 1 from _tc_duplicate_history b join app.pos_order_alert_deliveries d using(id) where to_jsonb(d)<>b.value),
  'all previously sent history remains unchanged');
set local role service_role;
select is(pg_temp.tc_finish('folded-history'),true,'folded terminal leases finish');
reset role;

-- Only actionable native cancel deadlines, including recent logical expiry.
-- Insert new historical synthetic rows. Never rewrite the immutable identity,
-- quote or timestamps of an existing request just to manufacture elapsed time.
create function pg_temp.tc_seed_expired(n integer,expired_seconds integer) returns void language plpgsql as $$
declare w public.web_order_requests; t timestamptz:=clock_timestamp();
begin
  select * into w from public.web_order_requests where id=pg_temp.tc_request(1);
  w.id:=pg_temp.tc_id('historical-expiry-'||n);w.client_request_id:=pg_temp.tc_client(n);
  w.status:='pending';w.canonical_order_id:=null;w.rejection_reason:=null;w.decided_at:=null;
  w.created_at:=t-interval '20 minutes';w.expires_at:=t-make_interval(secs=>expired_seconds);
  if expired_seconds<300 then w.created_at:=t-interval '15 minutes';end if;
  w.status_until:=t+interval '1 hour';
  insert into public.web_order_requests select (w).*;
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind,state,attempt_count,sent_at)
    select r.id,r.generation,w.id,'pending','sent',1,t from app.pos_order_alert_registrations r
      where r.device_id in(pg_temp.tc_id('device-1'),pg_temp.tc_id('device-2')) and r.retired_at is null;
end;$$;
select pg_temp.tc_seed_expired(5,300);
select pg_temp.tc_seed_expired(6,110);
set local role service_role;
insert into _tc_results values('expiry-terminal',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.pos_order_alert_deliveries where request_id=pg_temp.tc_request(5) and kind='terminal'),0::bigint,
  'old expired history never creates a cancel backlog');
select is((select count(*) from app.pos_order_alert_deliveries where request_id=pg_temp.tc_request(6) and kind='terminal'),2::bigint,
  'recent genuine expiry still creates bounded native refresh hints');
set local role service_role;
select is(pg_temp.tc_finish('expiry-terminal'),true,'recent expiry terminal leases finish');
reset role;

-- Defense in depth: an inconsistent historical ledger must not expose another
-- tenant's opaque request ID to this registration. Current authority still wins.
set local role service_role;
select is(pg_temp.tc_submit(7,'b1')->>'ok','true','other tenant synthetic request enters');
insert into _tc_results values('foreign-pending',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('foreign-pending'),true,'other tenant pending lease finishes');
reset role;
insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind,state,attempt_count,sent_at)
select r.id,pg_temp.tc_id('inconsistent-foreign-generation'),pg_temp.tc_request(7),'pending','sent',1,clock_timestamp()
  from app.pos_order_alert_registrations r where r.device_id=pg_temp.tc_id('device-1');
set local role authenticated;
select is(pg_temp.tc_reject(7,3)->>'ok','true','other tenant resolves through its own valid device');
reset role;
set local role service_role;
insert into _tc_results values('foreign-terminal',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where d.request_id=pg_temp.tc_request(7) and d.kind='terminal' and r.device_id=pg_temp.tc_id('device-1')),0::bigint,
  'cross-tenant inconsistent history cannot create a terminal hint');
set local role service_role;
select is(pg_temp.tc_finish('foreign-terminal'),true,'legitimate other-tenant terminal finishes');
reset role;

set local role service_role;
select is(pg_temp.tc_submit(8)->>'ok','true','revocation fixture enters');
insert into _tc_results values('revoked-pending',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('revoked-pending'),true,'revocation fixture pending leases finish');
reset role;
set local role authenticated;
select is(pg_temp.tc_reject(8)->>'ok','true','revocation fixture resolves');
reset role;
update public.devices set is_active=false where id=pg_temp.tc_id('device-1');
set local role service_role;
insert into _tc_results values('revoked-terminal',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where d.request_id=pg_temp.tc_request(8) and d.kind='terminal' and r.device_id=pg_temp.tc_id('device-1')),0::bigint,
  'revoked current device has no terminal authority');
update public.devices set is_active=true where id=pg_temp.tc_id('device-1');
set local role service_role;
select is(pg_temp.tc_finish('revoked-terminal'),true,'eligible peer terminal still finishes');
reset role;

-- Retired registrations are historical identities, not generation continuity.
set local role service_role;
select is(pg_temp.tc_submit(9)->>'ok','true','retirement fixture enters');
insert into _tc_results values('retired-pending',public.pos_claim_order_alert_deliveries());
select is(pg_temp.tc_finish('retired-pending'),true,'retirement fixture pending leases finish');
reset role;
create temp table _tc_retired as select id from app.pos_order_alert_registrations where device_id=pg_temp.tc_id('device-1') and retired_at is null;
update app.pos_order_alert_registrations set enabled=false,retired_at=clock_timestamp(),generation=gen_random_uuid() where id in(select id from _tc_retired);
set local role authenticated;
select is(public.pos_register_order_alert(pg_temp.tc_id('installation-1'),'synthetic-fresh-after-retirement-token',repeat('b',64),
  pg_temp.tc_id('device-1'),pg_temp.tc_id('pin-1'),'synthetic-platform353-token-1')->>'ok','true','new historical identity gets a genuinely fresh capability');
select is(pg_temp.tc_reject(9)->>'ok','true','retired old coverage resolves');
reset role;
set local role service_role;
insert into _tc_results values('retired-terminal',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where d.request_id=pg_temp.tc_request(9) and d.kind='terminal' and r.device_id=pg_temp.tc_id('device-1')),0::bigint,
  'neither retired row nor replacement registration inherits historical delivery coverage');
select ok(not exists(select 1 from _tc_unrelated_functions b join pg_proc p using(oid) where pg_get_functiondef(p.oid)<>b.definition or p.proacl is distinct from b.proacl),
  'authority, registration, token refresh, finish definitions and ACL remain unchanged');
select is((select count(*) from supabase_migrations.schema_migrations),(select n from _tc_history_before),'ordinary worker calls never edit migration history');
select ok(not exists(select 1 from app.pos_order_alert_reconciliation_approvals),'terminal continuity never creates ownership approval');
select ok(not exists(select 1 from _tc_foreign_registration b cross join app.pos_order_alert_registrations r
  where r.device_id=pg_temp.tc_id('device-4') and to_jsonb(r)<>b.value),'unrelated registration stays unchanged');
select ok(not exists(select 1 from _tc_peer_registration b cross join app.pos_order_alert_registrations r
  where r.device_id=pg_temp.tc_id('device-2') and to_jsonb(r)<>b.value),'working peer registration remains byte-for-byte unchanged');
select ok(not has_function_privilege('anon','app.pos_claim_order_alert_deliveries(integer)','EXECUTE')
  and not has_function_privilege('authenticated','app.pos_claim_order_alert_deliveries(integer)','EXECUTE')
  and has_function_privilege('service_role','app.pos_claim_order_alert_deliveries(integer)','EXECUTE'),'private worker ACL remains service-only');
select * from finish();
rollback;
