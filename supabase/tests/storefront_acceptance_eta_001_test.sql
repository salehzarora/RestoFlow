-- ETA R2: synthetic real authority/canonical writer; rollback-only, no HTTP or printer transport.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.p353_id(label text) returns uuid language sql immutable as $$
  select md5('bizbot-platform-353-synthetic-'||label)::uuid; $$;
create function pg_temp.p353_client(n integer) returns uuid language sql immutable as $$
  select ('35300000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid; $$;
create temp table _p353_rest as select label,
  pg_temp.p353_id(case when label='b1' then 'org-b' else 'org-a' end) org,
  pg_temp.p353_id('restaurant-'||label) restaurant,pg_temp.p353_id('branch-'||label) branch,
  pg_temp.p353_id('category-'||label) category,pg_temp.p353_id('item-'||label) item
  from unnest(array['a1','a2','b1']) label;
insert into organizations(id,name,slug,default_currency,status) values
  (pg_temp.p353_id('org-a'),'Platform A','platform-353-a','ILS','active'),
  (pg_temp.p353_id('org-b'),'Platform B','platform-353-b','ILS','active');
insert into restaurants(id,organization_id,name,timezone) select restaurant,org,'Synthetic '||label,'UTC' from _p353_rest;
insert into branches(id,organization_id,restaurant_id,name,timezone,kitchen_workflow_mode)
  select branch,org,restaurant,'Synthetic branch '||label,'UTC',case when label='a2' then 'kds' else 'printer_only' end from _p353_rest;
insert into menu_categories(id,organization_id,restaurant_id,name) select category,org,restaurant,'Synthetic Food' from _p353_rest;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
  select item,org,restaurant,category,'Saved product '||label,1000,'ILS' from _p353_rest;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,
  pickup_enabled,opening_hours,is_published)
select restaurant,org,branch,'platform-353-'||label,'Synthetic '||label,true,
  jsonb_build_object('weekly',(select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c))
    from generate_series(0,6) d cross join(values('00:00','12:00'),('11:00','00:00')) w(o,c)),'exceptions','[]'::jsonb),true
  from _p353_rest;
select is((select count(*) from app.online_order_settings where organization_id in(pg_temp.p353_id('org-a'),pg_temp.p353_id('org-b'))),3::bigint,
  'three arbitrary branches auto-provision before their storefront publication');
select is((select count(*) from web_order_channel_settings where submission_enabled),3::bigint,'channels automatically enabled without backend operator');
select ok((public.storefront_menu('platform-353-'||label)#>>'{service,ordering_enabled}')::boolean,label||' published Pickup checkout enabled') from _p353_rest;
select ok(not exists(select 1 from app.online_order_live_requests),'onboarding never backfills old requests');
select ok(not exists(select 1 from public.web_order_print_attempts),'onboarding never creates print attempts');
create temp table _p353_staff as
  select n,r.*,pg_temp.p353_id('device-'||n) device,pg_temp.p353_id('pairing-'||n) pairing,
    pg_temp.p353_id('session-'||n) session,pg_temp.p353_id('staff-'||n) staff,
    pg_temp.p353_id('membership-'||n) membership,pg_temp.p353_id('employee-'||n) employee,
    pg_temp.p353_id('pin-'||n) pin,pg_temp.p353_id('shift-'||n) shift
  from generate_series(1,4) n join _p353_rest r on r.label=case when n=3 then 'b1' when n=4 then 'a2' else 'a1' end;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type) select device,org,restaurant,branch,'pos' from _p353_staff;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status) select pairing,org,restaurant,branch,device,'active' from _p353_staff;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
  select session,org,restaurant,branch,device,pairing,app.hash_provisioning_secret('synthetic-platform353-token-'||n),now()+interval '30 days' from _p353_staff;
insert into app_users(id,email) select staff,'platform353-'||n||'@example.test' from _p353_staff;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) select membership,staff,org,restaurant,branch,'cashier' from _p353_staff;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
  select employee,org,restaurant,branch,staff,membership,'Synthetic cashier '||n from _p353_staff;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
  select pin,org,restaurant,branch,session,employee,membership,now()+interval '6 hours' from _p353_staff;
insert into shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
  select shift,org,restaurant,branch,device,employee,membership,'platform353-open-'||n,'open' from _p353_staff;
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
  select pg_temp.p353_id('printer-'||label),org,restaurant,branch,'Synthetic kitchen','network','kitchen','80mm',true from _p353_rest where label<>'a2';
insert into kitchen_printer_readiness_reports(organization_id,restaurant_id,branch_id,device_id,capability,app_build,
  printer_purpose,transport_kind,paper_width,printer_fingerprint,secure_spool_available,unresolved_local_jobs,
  mode_revision,printer_assignment_id,expires_at)
  select org,restaurant,branch,device,'kitchen_printer_only_v1','synthetic-platform353','kitchen_ticket','network','80mm',repeat('a',64),
    true,0,1,pg_temp.p353_id('printer-'||label),clock_timestamp()+interval '10 minutes' from _p353_staff where n<4;
create function pg_temp.p353_submit(n integer,label text default 'a1') returns jsonb language sql volatile as $$
  select public.submit_web_order_platform_request('platform-353-'||label,pg_temp.p353_client(n),repeat('a',64),
    jsonb_build_object('order_type','takeaway','customer',jsonb_build_object('name','Synthetic Guest','phone','+9725200'||lpad(n::text,5,'0')),
      'notes','Saved customer note','items',jsonb_build_array(jsonb_build_object('menu_item_id',pg_temp.p353_id('item-'||label),
        'quantity',2,'notes','Saved item note','modifiers','[]'::jsonb)))); $$;
create function pg_temp.eta_legacy_submit(n integer,label text default 'a1') returns jsonb language sql volatile as $$
  select public.submit_web_order_request('platform-353-'||label,pg_temp.p353_client(n),repeat('a',64),
    jsonb_build_object('order_type','takeaway','customer',jsonb_build_object('name','Synthetic Guest','phone','+9725200'||lpad(n::text,5,'0')),
      'notes','Saved customer note','items',jsonb_build_array(jsonb_build_object('menu_item_id',pg_temp.p353_id('item-'||label),
        'quantity',2,'notes','Saved item note','modifiers','[]'::jsonb)))); $$;
create function pg_temp.p353_request(n integer) returns uuid language sql stable security definer set search_path='' as $$
  select id from public.web_order_requests where client_request_id=pg_temp.p353_client(n); $$;
create function pg_temp.p353_inbox(n integer) returns jsonb language sql volatile as $$
  select public.pos_web_order_inbox(pg_temp.p353_id('pin-'||n),pg_temp.p353_id('device-'||n),'synthetic-platform353-token-'||n); $$;
create function pg_temp.p353_accept(n integer,device integer default 1) returns jsonb language sql volatile as $$
  select public.pos_accept_web_order(pg_temp.p353_id('pin-'||device),pg_temp.p353_id('device-'||device),
    'synthetic-platform353-token-'||device,pg_temp.p353_request(n),pg_temp.p353_client(1000+n+device)); $$;
create temp table _eta_results(label text primary key,r jsonb);
grant all on _eta_results to authenticated,service_role;
select set_config('request.jwt.claim.sub',pg_temp.p353_id('transport-user')::text,true);
create function pg_temp.eta_accept(n integer,minutes integer,device integer default 1,decision integer default null)
returns jsonb language sql volatile as $$
 select public.pos_accept_web_order_with_eta(pg_temp.p353_id('pin-'||device),pg_temp.p353_id('device-'||device),
  'synthetic-platform353-token-'||device,pg_temp.p353_request(n),pg_temp.p353_client(coalesce(decision,1000+n+device)),minutes); $$;
create function pg_temp.eta_status(n integer,capability text default repeat('a',64),slug text default 'platform-353-a1')
returns jsonb language sql volatile as $$
 select public.get_web_order_request_status_v2(slug,pg_temp.p353_client(n),capability); $$;
create temp table _eta_legacy_functions as select oid::regprocedure::text signature,md5(prosrc) body from pg_proc
where oid in('app.pos_accept_web_order(uuid,uuid,text,uuid,uuid)'::regprocedure,
 'app.decide_pos_web_order(uuid,uuid,text,uuid,uuid,text,text)'::regprocedure,
 'app.web_order_public_result(public.web_order_requests,boolean)'::regprocedure,
 'app.get_web_order_request_status(text,uuid,text)'::regprocedure);
select ok(relrowsecurity and relforcerowsecurity,'ETA private ledger has forced RLS')
 from pg_class where oid='app.web_order_acceptance_estimates'::regclass;
select ok(not has_table_privilege(role,'app.web_order_acceptance_estimates','SELECT')
 and not has_table_privilege(role,'app.web_order_acceptance_estimates','INSERT')
 and not has_table_privilege(role,'app.web_order_acceptance_estimates','UPDATE'),role||' has no ledger CRUD')
 from unnest(array['anon','authenticated','service_role']) role;
select ok(has_function_privilege('authenticated',oid,'EXECUTE') and not has_function_privilege('service_role',oid,'EXECUTE')
 and not has_function_privilege('anon',oid,'EXECUTE'),'accept ETA is authenticated only')
 from pg_proc where oid='public.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer)'::regprocedure;
select ok(not prosecdef and proconfig @> array['search_path=""'],'public accept ETA is invoker with fixed search path')
 from pg_proc where oid='public.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer)'::regprocedure;
select ok(has_function_privilege('service_role',oid,'EXECUTE') and not has_function_privilege('authenticated',oid,'EXECUTE')
 and not has_function_privilege('anon',oid,'EXECUTE'),'customer v2 status is service only')
 from pg_proc where oid='public.get_web_order_request_status_v2(text,uuid,text)'::regprocedure;
set local role anon;
select throws_ok($$select pg_temp.eta_accept(1,15)$$,'42501',null,'anon cannot accept ETA');
select throws_ok($$select pg_temp.eta_status(1)$$,'42501',null,'anon cannot bypass Edge status');
reset role;
set local role service_role;
select throws_ok($$select pg_temp.eta_accept(1,15)$$,'42501',null,'service role cannot impersonate a POS');
select is(pg_temp.p353_submit(n)->>'ok','true','synthetic pending order '||n) from generate_series(1,9) n;
select is(pg_temp.eta_legacy_submit(10)->>'ok','true','old submission path creates a scoped unenrolled request');
select is(pg_temp.p353_submit(14,'b1')->>'ok','true','other tenant pending order');
insert into _eta_results values('pending',pg_temp.eta_status(1));
select ok(not((select r from _eta_results where label='pending')?'acceptance_eta'),'pending has no ETA key');
reset role;
set local role authenticated;
select is(pg_temp.eta_accept(1,15)->>'ok','true','new explicit ETA acceptance succeeds');
select is(pg_temp.eta_accept(1,15)->>'replayed','true','same identity and duration replays');
select is(pg_temp.eta_accept(1,20)->>'error','decision_conflict','changed duration cannot mutate winner');
select is(pg_temp.eta_accept(1,15,2)->>'error','decision_conflict','other device cannot adopt winner');
select is(pg_temp.eta_accept(1,15,1,9991)->>'error','decision_conflict','different decision UUID cannot adopt winner');
select is(pg_temp.eta_accept(14,15)->>'error','not_found','foreign tenant is isolated');
select is(pg_temp.eta_accept(2,0)->>'error','invalid_request','zero rejected');
select is(pg_temp.eta_accept(2,241)->>'error','invalid_request','241 rejected');
select is(pg_temp.eta_accept(2,null)->>'error','invalid_request','missing chooser value rejected');
select is(public.pos_accept_web_order_with_eta(pg_temp.p353_id('pin-2'),pg_temp.p353_id('device-1'),
 'synthetic-platform353-token-1',pg_temp.p353_request(2),pg_temp.p353_client(1003),15)->>'error',
 'invalid_session','wrong device/PIN rejected');
select is(public.pos_accept_web_order_with_eta(pg_temp.p353_id('pin-1'),pg_temp.p353_id('device-1'),
 'synthetic-wrong-token',pg_temp.p353_request(2),pg_temp.p353_client(1003),15)->>'error',
 'invalid_session','wrong session token rejected');
select is(pg_temp.p353_accept(3)->>'ok','true','legacy accept is still supported');
select is(pg_temp.eta_accept(3,15)->>'error','decision_conflict','legacy acceptance is never backfilled');
select is(pg_temp.eta_accept(4,1)->>'ok','true','minimum duration accepted');
select is(pg_temp.eta_accept(5,240)->>'ok','true','maximum duration accepted');
select is(pg_temp.eta_accept(10,10)->>'ok','true','ordinary legacy resolver preserves context-first lock path');
select is(public.pos_reject_web_order_customer(pg_temp.p353_id('pin-1'),pg_temp.p353_id('device-1'),
 'synthetic-platform353-token-1',pg_temp.p353_request(6),pg_temp.p353_client(2006),'Sold out')->>'ok',
 'true','explicit rejection remains unchanged');
reset role;
select is((select count(*) from app.web_order_acceptance_estimates),4::bigint,'only new ETA acceptances create metadata');
select ok(not exists(select 1 from app.web_order_acceptance_estimates e join web_order_decisions d using(request_id)
 where e.accepted_at<>d.decided_at or e.ready_at<>d.decided_at+e.preparation_minutes*interval '1 minute'),
 'all timestamps are exact canonical decision time plus integer minutes');
select is((select count(*) from web_order_decisions where request_id=pg_temp.p353_request(1)),1::bigint,'winning decision exactly once');
select is((select count(*) from kitchen_print_dispatches where order_id=(select canonical_order_id from web_order_requests where id=pg_temp.p353_request(1))),1::bigint,'single dispatch unchanged');
select is((select count(*) from app.online_order_print_leases where request_id=pg_temp.p353_request(1)),1::bigint,'single winner lease unchanged');
select throws_ok($$update app.web_order_acceptance_estimates set preparation_minutes=20$$,'42501',null,'metadata update denied');
select throws_ok($$delete from app.web_order_acceptance_estimates$$,'42501',null,'metadata delete denied');
select throws_ok($$truncate app.web_order_acceptance_estimates$$,'42501',null,'metadata truncate denied');
select ok(not exists(select 1 from app.web_order_acceptance_estimates e where e.intent_fingerprint<>
 app.web_order_acceptance_intent_fingerprint(e.organization_id,e.restaurant_id,e.branch_id,e.request_id,e.decision_id,e.preparation_minutes)),
 'versioned fingerprint binds exact scope request decision action and duration');
select isnt(app.web_order_acceptance_intent_fingerprint(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),
 pg_temp.p353_id('branch-a1'),pg_temp.p353_request(1),pg_temp.p353_client(1002),15),
 app.web_order_acceptance_intent_fingerprint(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),
 pg_temp.p353_id('branch-a1'),pg_temp.p353_request(1),pg_temp.p353_client(1002),20),'duration changes new fingerprint only');
set local role service_role;
insert into _eta_results values('accepted',pg_temp.eta_status(1));
select is((select count(*)::integer from jsonb_object_keys((select r->'acceptance_eta' from _eta_results where label='accepted'))),4,'exact complete tuple has four fields');
select is((select r#>>'{acceptance_eta,preparation_minutes}' from _eta_results where label='accepted'),'15','public duration exact');
select is((select r#>>'{acceptance_eta,timezone}' from _eta_results where label='accepted'),'UTC','server timezone captured');
select matches((select r#>>'{acceptance_eta,accepted_at}' from _eta_results where label='accepted'),
 '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$','timestamp has six microseconds and UTC Z');
select ok(not(public.get_web_order_request_status('platform-353-a1',pg_temp.p353_client(1),repeat('a',64))?'acceptance_eta'),
 'legacy status shape omits ETA even after new acceptance');
select ok(not(pg_temp.eta_status(3)?'acceptance_eta'),'versioned status omits legacy acceptance ETA');
select ok(not(pg_temp.eta_status(6)?'acceptance_eta'),'rejected has no ETA key');
select is(pg_temp.eta_status(6)->>'customer_rejection_reason','Sold out','existing customer reason preserved');
select is(pg_temp.eta_status(1,repeat('b',64))->>'error','not_found','wrong capability denied');
select is(pg_temp.eta_status(1,repeat('a',64),'platform-353-b1')->>'error','not_found','wrong tenant slug denied');
reset role;
-- Replay must not re-sample changed configuration, including a now-invalid zone.
create function pg_temp.eta_forbid_canonical() returns trigger language plpgsql as $$
begin raise exception 'INVALID_ZONE_REACHED_CANONICAL_WRITER' using errcode='23514'; end; $$;
create trigger eta_invalid_zone_probe before insert on public.orders for each row execute function pg_temp.eta_forbid_canonical();
update branches set timezone='Factory' where id=pg_temp.p353_id('branch-a1');
set local role authenticated;
select is(pg_temp.eta_accept(1,15)->>'replayed','true','replay ignores changed current timezone');
select is(pg_temp.eta_accept(7,15)->>'error','ordering_unavailable','unsupported zone denied before canonical acceptance');
reset role;
drop trigger eta_invalid_zone_probe on public.orders;
select is((select status from web_order_requests where id=pg_temp.p353_request(7)),'pending','invalid zone never reaches canonical acceptance');
select throws_ok($$insert into app.web_order_acceptance_estimates(request_id,organization_id,restaurant_id,branch_id,
 decision_id,intent_fingerprint,preparation_minutes,accepted_at,ready_at,timezone)
 select d.request_id,d.organization_id,d.restaurant_id,d.branch_id,d.decision_id,repeat('0',64),15,d.decided_at,
 d.decided_at+interval '15 minutes','UTC' from web_order_decisions d where d.request_id=pg_temp.p353_request(3)$$,
 '23514','ACCEPTANCE_ETA_MAPPING_UNAVAILABLE','insert guard rejects forged versioned fingerprint');
update branches set timezone='America/New_York' where id=pg_temp.p353_id('branch-a1');
set local role authenticated;
select is(pg_temp.eta_accept(8,30)->>'ok','true','valid IANA zone accepted');
reset role;
select is((select timezone from app.web_order_acceptance_estimates where request_id=pg_temp.p353_request(8)),'America/New_York','captured authoritative IANA identity');
-- A synthetic already-expired pending fixture exercises the real status/accept
-- paths without waiting, updating immutable request fields, or changing clocks.
insert into public.web_order_requests select (jsonb_populate_record(null::public.web_order_requests,
 to_jsonb(w)||jsonb_build_object('id',pg_temp.p353_id('eta-expired'),
 'client_request_id',pg_temp.p353_client(11),'created_at',clock_timestamp()-interval '20 minutes',
 'expires_at',clock_timestamp()-interval '6 minutes','status_until',clock_timestamp()+interval '1 hour'))).*
 from public.web_order_requests w where w.id=pg_temp.p353_request(2);
set local role authenticated;
select is(pg_temp.eta_accept(11,15)->>'error','request_expired','expired request cannot accept ETA');
reset role;
set local role service_role;
select is(pg_temp.eta_status(11)->>'status','expired','expired pending request projects expired');
select ok(not(pg_temp.eta_status(11)?'acceptance_eta'),'expired has no ETA key');
reset role;
select is((select count(*) from app.web_order_acceptance_estimates where request_id=pg_temp.p353_request(11)),0::bigint,'expired creates no metadata');
set local role service_role;
select is(pg_temp.eta_status(1)#>>'{acceptance_eta,timezone}','UTC','public replay retains original stored timezone');
reset role;
-- Fault is injected after old canonical/order/item/audit/decision/print-lease work.
create function pg_temp.eta_fault() returns trigger language plpgsql set search_path=public,pg_catalog as $$
begin
 if not exists(select 1 from web_order_decisions where request_id=new.request_id and decision='accepted')
  or not exists(select 1 from orders where id=(select canonical_order_id from web_order_requests where id=new.request_id))
  or not exists(select 1 from order_items where order_id=(select canonical_order_id from web_order_requests where id=new.request_id))
  or not exists(select 1 from kitchen_print_dispatches where order_id=(select canonical_order_id from web_order_requests where id=new.request_id))
  or not exists(select 1 from app.online_order_print_leases where request_id=new.request_id) then
  raise exception 'FAULT_DID_NOT_REACH_CANONICAL_LEASE_WORK' using errcode='23514';
 end if;
 raise exception 'SYNTHETIC_ETA_METADATA_FAILURE_AFTER_CANONICAL_LEASE' using errcode='23514';
end; $$;
create temp table _eta_before as select (select count(*) from orders) orders,(select count(*) from order_items) items,
 (select count(*) from audit_events) audits,(select count(*) from sync_operations) syncs,(select count(*) from kitchen_print_dispatches) dispatches,
 (select count(*) from web_order_decisions) decisions,(select count(*) from app.online_order_print_leases) leases;
create trigger eta_test_fault before insert on app.web_order_acceptance_estimates for each row execute function pg_temp.eta_fault();
set local role authenticated;
select throws_ok($$select pg_temp.eta_accept(9,15)$$,'23514','SYNTHETIC_ETA_METADATA_FAILURE_AFTER_CANONICAL_LEASE','metadata fault aborts actual old writer effects');
reset role;
drop trigger eta_test_fault on app.web_order_acceptance_estimates;
select is((select status from web_order_requests where id=pg_temp.p353_request(9)),'pending','fault leaves request pending');
select is((select canonical_order_id from web_order_requests where id=pg_temp.p353_request(9)),null::uuid,'fault leaves no canonical mapping');
select is((select count(*) from orders),(select orders from _eta_before),'canonical order rolled back');
select is((select count(*) from order_items),(select items from _eta_before),'canonical items rolled back');
select is((select count(*) from audit_events),(select audits from _eta_before),'audit side effects rolled back');
select is((select count(*) from sync_operations),(select syncs from _eta_before),'sync ledger rolled back');
select is((select count(*) from kitchen_print_dispatches),(select dispatches from _eta_before),'dispatch rolled back');
select is((select count(*) from web_order_decisions),(select decisions from _eta_before),'attributed decision rolled back');
select is((select count(*) from app.online_order_print_leases),(select leases from _eta_before),'print lease rolled back');
-- Admission is one increment per call; invalid capabilities never get quota oracle.
update web_order_channel_settings set status_attempt_count=0,status_window_started_at=clock_timestamp()
 where branch_id=pg_temp.p353_id('branch-a1');
set local role service_role;
select is(pg_temp.eta_status(1)->>'ok','true','v2 admitted once');
reset role;
select is((select status_attempt_count from web_order_channel_settings where branch_id=pg_temp.p353_id('branch-a1')),1,'v2 consumes quota once, not twice');
update web_order_channel_settings set status_attempt_count=600 where branch_id=pg_temp.p353_id('branch-a1');
set local role service_role;
select is(pg_temp.eta_status(1)->>'error','rate_limited','valid capability sees exhausted quota');
select is(pg_temp.eta_status(1,repeat('b',64))->>'error','not_found','exhausted quota hides invalid capability');
reset role;
select ok(not exists(select 1 from _eta_legacy_functions p join pg_proc f on f.oid=p.signature::regprocedure
 where md5(f.prosrc)<>p.body),'all four legacy function bodies unchanged');
select is((select count(*) from app.pos_order_alert_registrations),0::bigint,'no registrations created');
select is((select count(*) from app.pos_order_alert_deliveries),0::bigint,'no notification delivery created');
select is((select count(*) from web_order_print_attempts where attempt_reserved_at is not null),0::bigint,'no printer claims/transports');
select * from finish();
rollback;
