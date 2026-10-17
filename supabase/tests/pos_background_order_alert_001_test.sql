-- BIZBOT-POS-BACKGROUND-ORDER-ALERT-001: rollback-only synthetic security tests.
-- Uses the established synthetic Maps Burger fixture; no network/printer call.
-- This scoped rollout pins these scope UUIDs. All rows below are synthetic
-- fixtures in the disposable CI database, never hosted restaurant operations.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
set local timezone to 'UTC';
select no_plan();

create function pg_temp.mp_id(label text) returns uuid language sql immutable as
$$select case when label='device-1' then 'bb80c0d8-6893-4e24-8eea-5a14cf545ecd'::uuid
 else md5('manual-order-pilot-001-synthetic-'||label)::uuid end$$;
create function pg_temp.mp_client(n integer) returns uuid language sql immutable as
$$select ('62000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
create function pg_temp.mp_org() returns uuid language sql immutable as
$$select '20605c2b-3145-4803-a990-bbec3d9c1096'::uuid$$;
create function pg_temp.mp_rest() returns uuid language sql immutable as
$$select 'de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid$$;
create function pg_temp.mp_branch() returns uuid language sql immutable as
$$select '2847c0be-3e31-45a5-957c-508729f1971e'::uuid$$;
create function pg_temp.mp_order() returns jsonb language sql immutable as $$
 select jsonb_build_object('order_type','takeaway',
  'customer',jsonb_build_object('name','Synthetic Pilot Guest','phone','+972520000123'),
  'notes','Synthetic manual Pickup test',
  'items',jsonb_build_array(jsonb_build_object('menu_item_id',pg_temp.mp_id('item'),
   'quantity',2,'notes','Synthetic line note',
   'modifiers',jsonb_build_array(jsonb_build_object(
    'modifier_option_id',pg_temp.mp_id('option'),'quantity',2)))))
$$;
create temp table _mp_results(label text primary key,r jsonb not null);
grant all on _mp_results to service_role;

insert into organizations(id,name,slug,default_currency,status) values
 (pg_temp.mp_org(),'Manual Pilot Synthetic A','manual-pilot-synthetic-a','ILS','active'),
 (pg_temp.mp_id('org_b'),'Manual Pilot Synthetic B','manual-pilot-synthetic-b','ILS','active');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.mp_rest(),pg_temp.mp_org(),'Manual Pilot Synthetic A','UTC'),
 (pg_temp.mp_id('rest_b'),pg_temp.mp_id('org_b'),'Manual Pilot Synthetic B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_rate_bp,tax_mode) values
 (pg_temp.mp_branch(),pg_temp.mp_org(),pg_temp.mp_rest(),'Synthetic target','UTC',true,1800,'exclusive'),
 (pg_temp.mp_id('sibling'),pg_temp.mp_org(),pg_temp.mp_rest(),'Synthetic sibling','UTC',true,1800,'exclusive'),
 (pg_temp.mp_id('branch_b'),pg_temp.mp_id('org_b'),pg_temp.mp_id('rest_b'),'Synthetic foreign','UTC',false,0,'exclusive');
insert into menu_categories(id,organization_id,restaurant_id,name) values
 (pg_temp.mp_id('category'),pg_temp.mp_org(),pg_temp.mp_rest(),'Synthetic Food'),
 (pg_temp.mp_id('category_b'),pg_temp.mp_id('org_b'),pg_temp.mp_id('rest_b'),'Synthetic Foreign Food');
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
values(pg_temp.mp_id('item'),pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_id('category'),
 'Synthetic Pilot Product',1000,'ILS'),
 (pg_temp.mp_id('item_b'),pg_temp.mp_id('org_b'),pg_temp.mp_id('rest_b'),pg_temp.mp_id('category_b'),
 'Synthetic Foreign Product',1000,'ILS');
insert into modifiers(id,organization_id,restaurant_id,menu_item_id,name,selection_type,min_select,max_select,
 is_required,allow_quantity,max_quantity)
values(pg_temp.mp_id('modifier'),pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_id('item'),
 'Synthetic Extras','multiple',0,1,false,true,3);
insert into modifier_options(id,organization_id,restaurant_id,modifier_id,name,price_delta_minor)
values(pg_temp.mp_id('option'),pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_id('modifier'),
 'Synthetic Extra',125);
create temp table _mp_hours as select jsonb_build_object('weekly',
 (select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c)) from generate_series(0,6) d
 cross join (values('00:00','12:00'),('11:00','00:00')) w(o,c)),'exceptions','[]'::jsonb) h;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,
 display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.mp_rest(),pg_temp.mp_org(),pg_temp.mp_branch(),'mapsburger','Synthetic Pilot',true,h,true from _mp_hours;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,
 display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.mp_id('rest_b'),pg_temp.mp_id('org_b'),pg_temp.mp_id('branch_b'),
 'manual-pilot-foreign','Synthetic Foreign',true,h,true from _mp_hours;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),true);
insert into kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),'blocked',
 'Synthetic SQL test; no printer operation','manual-pilot-001-synthetic');

update public.branches set kitchen_workflow_mode='printer_only' where id=pg_temp.mp_branch();
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
values(pg_temp.mp_id('printer'),pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),
 'Synthetic Kitchen','network','kitchen','80mm',true);
create temp table _ao_staff as select n,
 case when n=3 then pg_temp.mp_id('org_b') else pg_temp.mp_org() end org,
 case when n=3 then pg_temp.mp_id('rest_b') else pg_temp.mp_rest() end restaurant,
 case when n=3 then pg_temp.mp_id('branch_b') else pg_temp.mp_branch() end branch,
 pg_temp.mp_id('device-'||n) device,pg_temp.mp_id('pairing-'||n) pairing,
 pg_temp.mp_id('session-'||n) session,pg_temp.mp_id('staff-'||n) staff,
 pg_temp.mp_id('membership-'||n) membership,pg_temp.mp_id('employee-'||n) employee,
 pg_temp.mp_id('pin-'||n) pin,pg_temp.mp_id('shift-'||n) shift from generate_series(1,3) n;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
select device,org,restaurant,branch,'pos' from _ao_staff;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
select pairing,org,restaurant,branch,device,'active' from _ao_staff;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
select session,org,restaurant,branch,device,pairing,app.hash_provisioning_secret('synthetic-live-token-'||n),now()+interval '30 days' from _ao_staff;
insert into app_users(id,email) select staff,'mapsburger-live-'||n||'@example.test' from _ao_staff;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
select membership,staff,org,restaurant,branch,'cashier' from _ao_staff;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
select employee,org,restaurant,branch,staff,membership,'Synthetic Staff '||n from _ao_staff;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
select pin,org,restaurant,branch,session,employee,membership,now()+interval '6 hours' from _ao_staff;
insert into shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
select shift,org,restaurant,branch,device,employee,membership,'live-open-'||n,'open' from _ao_staff;
insert into public.kitchen_printer_readiness_reports(organization_id,restaurant_id,branch_id,device_id,
 capability,app_build,printer_purpose,transport_kind,paper_width,printer_fingerprint,secure_spool_available,
 unresolved_local_jobs,mode_revision,printer_assignment_id,expires_at)
select org,restaurant,branch,device,'kitchen_printer_only_v1','synthetic-v63','kitchen_ticket','network','80mm',
 repeat('a',64),true,0,1,pg_temp.mp_id('printer'),clock_timestamp()+interval '10 minutes' from _ao_staff where n<=2;

create function pg_temp.ao_submit(n integer,p_body jsonb default null,p_token text default repeat('a',64),p_slug text default 'mapsburger')
returns jsonb language sql volatile as $$ select public.submit_web_order_live_request(p_slug,pg_temp.mp_client(n),p_token,
 coalesce(p_body,jsonb_set(pg_temp.mp_order(),'{customer,phone}',to_jsonb('+9725200'||lpad(n::text,5,'0'))))) $$;
create function pg_temp.ao_request(n integer) returns uuid language sql security definer set search_path='' as $$
 select id from public.web_order_requests where restaurant_id=pg_temp.mp_rest() and client_request_id=pg_temp.mp_client(n) $$;
create function pg_temp.ao_accept(n integer,device integer default 1) returns jsonb language sql volatile as $$
 select public.pos_accept_web_order(pg_temp.mp_id('pin-'||device),pg_temp.mp_id('device-'||device),
 'synthetic-live-token-'||device,pg_temp.ao_request(n),pg_temp.mp_client(10000+n)) $$;
create function pg_temp.ao_policy(device integer default 1) returns jsonb language sql volatile as $$
 select public.pos_kitchen_print_containment(pg_temp.mp_id('device-'||device),'synthetic-live-token-'||device) $$;
create function pg_temp.ao_config(intake boolean,printing boolean,devices integer default 1) returns bigint language sql volatile as $$
 select app.set_mapsburger_web_orders(intake,printing,case when devices=1 then array[pg_temp.mp_id('device-1')]
 else array[pg_temp.mp_id('device-1'),pg_temp.mp_id('device-2')] end,'Synthetic rollback-only test','always-on-security-test') $$;
create temp table _ao_results(label text primary key,r jsonb);
grant all on _ao_results to service_role,authenticated;
select set_config('request.jwt.claim.sub',pg_temp.mp_id('transport-user')::text,true);

create function pg_temp.alert_register(p_secret text default repeat('a',64),p_token text default 'synthetic-fcm-token-123456789',p_device integer default 1)
returns jsonb language sql volatile as $$
 select public.pos_register_order_alert(pg_temp.mp_client(700),p_token,p_secret,pg_temp.mp_id('device-'||p_device),
   pg_temp.mp_id('pin-'||p_device),'synthetic-live-token-'||p_device);
$$;
create function pg_temp.alert_status(p_secret text default repeat('a',64),p_installation uuid default pg_temp.mp_client(700))
returns jsonb language sql stable as $$
 select public.pos_order_alert_status(p_installation,encode(sha256(convert_to(p_secret,'UTF8')),'hex'));
$$;
select ok(c.relrowsecurity and c.relforcerowsecurity,c.relname||' forced RLS') from pg_class c where c.oid in
 ('app.pos_order_alert_settings'::regclass,'app.pos_order_alert_registrations'::regclass,'app.pos_order_alert_deliveries'::regclass);
select ok(not has_table_privilege(role_name,tbl,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),role_name||' has no direct '||tbl)
from unnest(array['anon','authenticated','service_role']) role_name cross join unnest(array[
 'app.pos_order_alert_settings','app.pos_order_alert_registrations','app.pos_order_alert_deliveries']) tbl;
select ok(not has_function_privilege(role_name,'app.set_pos_order_alerts(boolean,text,text)','EXECUTE'),role_name||' cannot activate push')
from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege('anon',signature,'EXECUTE') and not has_function_privilege('authenticated',signature,'EXECUTE')
 and has_function_privilege('service_role',signature,'EXECUTE'),signature||' is service-only') from unnest(array[
 'public.pos_order_alert_status(uuid,text)','public.pos_disable_order_alert(uuid,text)',
 'public.pos_claim_order_alert_deliveries(integer)','public.pos_finish_order_alert_delivery(uuid,uuid,text)']) signature;
select ok(has_function_privilege('authenticated','public.pos_register_order_alert(uuid,text,text,uuid,uuid,text)','EXECUTE')
 and not has_function_privilege('anon','public.pos_register_order_alert(uuid,text,text,uuid,uuid,text)','EXECUTE')
 and not has_function_privilege('service_role','public.pos_register_order_alert(uuid,text,text,uuid,uuid,text)','EXECUTE'),'registration is genuine authenticated POS only');
select is((select count(*) from app.pos_order_alert_settings),0::bigint,'no configuration installed: OFF');
set local role authenticated;
select is(pg_temp.alert_register()->>'error','disabled','valid foreground registration is default OFF');
reset role;
select is((select count(*) from app.pos_order_alert_registrations),0::bigint,'OFF creates no token/delegation');
select pg_temp.ao_config(true,true);
-- An actual committed receipt can exist before push configuration. It must not
-- be retroactively interpreted as a new arrival when push is later installed.
set local role service_role;
insert into _ao_results values('historical-pending',pg_temp.ao_submit(90));
reset role;
select app.set_pos_order_alerts(true,'Synthetic notification gate','background-alert-test');
set local role authenticated;
select is(pg_temp.alert_register(p_secret=>'wrong')->>'error','invalid_request','malformed delegation rejected');
select is(pg_temp.alert_register(p_device=>2)->>'error','permission_denied','same-branch nonenabled device denied');
select is(pg_temp.alert_register(p_device=>3)->>'error','permission_denied','foreign tenant/device denied');
select is(public.pos_register_order_alert(pg_temp.mp_client(700),'synthetic-fcm-token-123456789',repeat('a',64),
 pg_temp.mp_id('device-1'),pg_temp.mp_id('pin-1'),'wrong-token')->>'error','invalid_session','paired secret must prove device');
insert into _ao_results values('registered',pg_temp.alert_register());
select is((select r->>'ok' from _ao_results where label='registered'),'true','real paired/PIN registration succeeds');
reset role;
select ok((select authority_expires_at<=clock_timestamp()+interval '8 hours' and
 authority_expires_at<=(select expires_at from pin_sessions where id=pg_temp.mp_id('pin-1'))
 and authority_expires_at<=(select expires_at from device_sessions where id=pg_temp.mp_id('session-1'))
 from app.pos_order_alert_registrations),'delegation is bounded by real PIN, device and eight hours');
create temp table _alert_registration as select id,generation,registered_at from app.pos_order_alert_registrations;
set local role authenticated;
select is(pg_temp.alert_register()->>'ok','true','same foreground registration may refresh');
reset role;
select ok((select r.id=old.id and r.generation=old.generation and r.registered_at=old.registered_at
 from app.pos_order_alert_registrations r cross join _alert_registration old),'same identity refresh preserves generation/cutoff');
-- Simulate a nearing-expiry delegation without changing the real PIN/session.
-- Refresh keeps arrival cutoff but bounds its NEW deadline by refreshed_at.
update app.pos_order_alert_registrations set registered_at=clock_timestamp()-interval '7 hours 58 minutes',
 refreshed_at=clock_timestamp()-interval '7 hours 58 minutes',authority_expires_at=clock_timestamp()+interval '1 minute';
create temp table _alert_renewal as select generation,registered_at from app.pos_order_alert_registrations;
set local role authenticated;
select is(pg_temp.alert_register()->>'ok','true','normal near-eight-hour renewal succeeds');
reset role;
select ok((select r.generation=old.generation and r.registered_at=old.registered_at
 and r.authority_expires_at<=r.refreshed_at+interval '8 hours' and r.authority_expires_at>r.registered_at+interval '8 hours'
 from app.pos_order_alert_registrations r cross join _alert_renewal old),'renewal preserves cutoff and has an independently bounded refreshed deadline');
set local role service_role;
select is(jsonb_array_length(pg_temp.alert_status()->'requests'),0,'historical pending request is not backfilled');
select is(jsonb_array_length(public.pos_claim_order_alert_deliveries()->'deliveries'),0,'no historical fresh notification');
insert into _ao_results values('new-pending',pg_temp.ao_submit(1));
select is(jsonb_array_length(pg_temp.alert_status()->'requests'),1,'new live-enrolled pending visible as opaque status');
select is(pg_temp.alert_status()#>>'{requests,0,request_id}',pg_temp.ao_request(1)::text,'status carries exact internal opaque UUID');
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','wrong delegation denied');
select is(pg_temp.alert_status(p_installation=>pg_temp.mp_client(701))->>'error','unauthorized','wrong installation denied uniformly');
insert into _ao_results values('claim',public.pos_claim_order_alert_deliveries());
select is(jsonb_array_length((select r->'deliveries' from _ao_results where label='claim')),1,'one pending receipt produces one hint lease');
select is(jsonb_array_length(public.pos_claim_order_alert_deliveries()->'deliveries'),0,'concurrent/duplicate worker cannot take active lease');
select is(public.pos_finish_order_alert_delivery(
 ((select r#>>'{deliveries,0,delivery_id}' from _ao_results where label='claim'))::uuid,
 pg_temp.mp_client(999),'sent')->>'error','stale_lease','wrong lease cannot finish');
select is(public.pos_finish_order_alert_delivery(
 ((select r#>>'{deliveries,0,delivery_id}' from _ao_results where label='claim'))::uuid,
 ((select r#>>'{deliveries,0,lease_id}' from _ao_results where label='claim'))::uuid,'sent')->>'ok','true','worker records FCM acceptance only');
select is(jsonb_array_length(public.pos_claim_order_alert_deliveries()->'deliveries'),0,'finished pending event never repeats every ten seconds');
reset role;
select ok(not exists(select 1 from jsonb_object_keys((select r from _ao_results where label='registered')) k
 where k not in ('ok','registration_id','authority_expires_at')),'registration never returns token, device secret or PIN');
-- Status must remain genuinely read-only, including device heartbeat and expiry.
create temp table _alert_before as select
 (select md5(jsonb_agg(to_jsonb(ds) order by ds.id)::text) from device_sessions ds) sessions,
 (select md5(jsonb_agg(to_jsonb(d) order by d.id)::text) from devices d) devices,
 (select md5(jsonb_agg(to_jsonb(w) order by w.id)::text) from web_order_requests w) requests,
 (select md5(jsonb_agg(to_jsonb(c) order by c.branch_id)::text) from web_order_channel_settings c) channels;
set local role service_role;
select ok(pg_temp.alert_status()->>'ok'='true','delegated read succeeds');
reset role;
select ok((select sessions=(select md5(jsonb_agg(to_jsonb(ds) order by ds.id)::text) from device_sessions ds)
 and devices=(select md5(jsonb_agg(to_jsonb(d) order by d.id)::text) from devices d)
 and requests=(select md5(jsonb_agg(to_jsonb(w) order by w.id)::text) from web_order_requests w)
 and channels=(select md5(jsonb_agg(to_jsonb(c) order by c.branch_id)::text) from web_order_channel_settings c) from _alert_before),
 'status writes no renewal, heartbeat, orders or quota');
select is((select provolatile::text from pg_proc where oid='public.pos_order_alert_status(uuid,text)'::regprocedure),'s','status is STABLE read-only');
set local role authenticated;
select is(public.pos_reject_web_order(pg_temp.mp_id('pin-1'),pg_temp.mp_id('device-1'),'synthetic-live-token-1',
 pg_temp.ao_request(1),pg_temp.mp_client(800),'Synthetic rejection')->>'status','rejected','genuine decision remains original authority');
reset role;
set local role service_role;
select is(jsonb_array_length(pg_temp.alert_status()->'requests'),0,'authoritative rejection clears pending status');
insert into _ao_results values('cancel',public.pos_claim_order_alert_deliveries());
select is((select r#>>'{deliveries,0,kind}' from _ao_results where label='cancel'),'terminal','committed rejection emits one bounded cancel hint');
reset role;
select is((select count(*) from orders),0::bigint,'notification/rejection creates no canonical order');
select is((select count(*) from kitchen_print_dispatches),0::bigint,'notification creates no print dispatch');
select is((select count(*) from web_order_print_attempts),0::bigint,'notification creates no print attempt');
-- Multiple pending requests share one opaque set; terminal decisions remove
-- only their own request. These are synthetic local canonical effects only.
set local role service_role;
insert into _ao_results values('second-pending',pg_temp.ao_submit(2)),('third-pending',pg_temp.ao_submit(3));
select is(jsonb_array_length(pg_temp.alert_status()->'requests'),2,'multiple requests remain one bounded status set');
reset role;
set local role authenticated;
select is(pg_temp.ao_accept(2)->>'status','accepted','existing trusted acceptance still succeeds');
reset role;
set local role service_role;
select is(jsonb_array_length(pg_temp.alert_status()->'requests'),1,'accepting one does not silence another pending request');
select is(pg_temp.alert_status()#>>'{requests,0,request_id}',pg_temp.ao_request(3)::text,'remaining request identity is exact');
reset role;
select is((select count(*) from orders),1::bigint,'only genuine synthetic Accept creates one canonical order');
select is((select count(*) from kitchen_print_dispatches),1::bigint,'notification path adds no duplicate accepted dispatch');
-- Preserve an already queued/sent synthetic receipt whose real deadline passed.
-- No order/request mutation is used to pretend that time advanced.
insert into web_order_requests(id,organization_id,restaurant_id,branch_id,client_request_id,status_token_hash,payload_hash,
 customer_name,customer_phone,notes,priced_items,currency_code,subtotal_minor,tax_total_minor,grand_total_minor,
 created_at,expires_at,status_until)
select pg_temp.mp_client(900),organization_id,restaurant_id,branch_id,pg_temp.mp_client(900),repeat('c',64),payload_hash,
 'Synthetic expired receipt','+972520000900','',priced_items,currency_code,subtotal_minor,tax_total_minor,grand_total_minor,
 statement_timestamp()-interval '16 minutes',statement_timestamp()-interval '1 minute',statement_timestamp()+interval '8 hours'
 from web_order_requests where id=pg_temp.ao_request(3);
insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind,state)
select id,generation,pg_temp.mp_client(900),'pending','sent' from app.pos_order_alert_registrations;
set local role service_role;
insert into _ao_results values('expired-cancel',public.pos_claim_order_alert_deliveries());
reset role;
select ok(exists(select 1 from jsonb_array_elements((select r->'deliveries' from _ao_results where label='expired-cancel')) x
 where x->>'request_id'=pg_temp.mp_client(900)::text and x->>'kind'='terminal'),'logical expiry emits bounded cancel without request mutation');
select is((select status from web_order_requests where id=pg_temp.mp_client(900)),'pending','expiry hint never rewrites request status');
-- Status response has no customer/money/printing fields, regardless of catalog.
set local role service_role;
insert into _ao_results values('safe-status',pg_temp.alert_status());
reset role;
select ok(not exists(select 1 from jsonb_object_keys((select r from _ao_results where label='safe-status')) k
 where k not in ('ok','registration_id','server_time','authority_expires_at','requests')),'status top-level projection is exact');
select ok(not exists(select 1 from jsonb_array_elements((select r->'requests' from _ao_results where label='safe-status')) x,
 jsonb_object_keys(x) k where k not in ('request_id','expires_at')),'status never carries customer/menu/money/print details');

-- Rotation invalidates the old status capability and old queued deliveries.
set local role authenticated;
select is(pg_temp.alert_register(p_secret=>repeat('b',64),p_token=>'synthetic-rotated-token-123456789')->>'ok','true','rotation remains foreground authenticated');
reset role;
select ok((select r.generation<>old.generation from app.pos_order_alert_registrations r cross join _alert_registration old),'rotation changes generation');
set local role service_role;
select is(pg_temp.alert_status()->>'error','unauthorized','old delegation rejected after rotation');
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'ok','true','new delegation succeeds');
select is(public.pos_finish_order_alert_delivery(
 ((select r#>>'{deliveries,0,delivery_id}' from _ao_results where label='expired-cancel'))::uuid,
 ((select r#>>'{deliveries,0,lease_id}' from _ao_results where label='expired-cancel'))::uuid,
 'invalid_token')->>'ok','true','stale-generation send outcome can be recorded');
reset role;
select is((select count(*) from app.pos_order_alert_registrations where enabled),1::bigint,'old invalid-token outcome cannot disable rotated registration');
update employee_profiles set employment_status='suspended' where id=pg_temp.mp_id('employee-1');
set local role service_role;
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','employee suspension invalidates delegated authority');
reset role;
update employee_profiles set employment_status='active' where id=pg_temp.mp_id('employee-1');
update memberships set role='kitchen_staff' where id=pg_temp.mp_id('membership-1');
set local role service_role;
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','role downgrade invalidates delegated authority');
reset role;
update memberships set role='cashier' where id=pg_temp.mp_id('membership-1');
update branches set status='suspended' where id=pg_temp.mp_branch();
set local role service_role;
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','branch suspension invalidates delegated authority');
reset role;
update branches set status='active' where id=pg_temp.mp_branch();
update pin_sessions set is_active=false,ended_at=clock_timestamp() where id=pg_temp.mp_id('pin-1');
set local role service_role;
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','ended PIN immediately removes delegated authority');
select is(jsonb_array_length(public.pos_claim_order_alert_deliveries()->'deliveries'),0,'ended PIN prevents worker delivery');
reset role;
update pin_sessions set is_active=true,ended_at=null where id=pg_temp.mp_id('pin-1');
update memberships set status='revoked' where id=pg_temp.mp_id('membership-1');
set local role service_role;
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','membership revocation invalidates delegation');
reset role;
update memberships set status='active' where id=pg_temp.mp_id('membership-1');
update device_sessions set is_active=false,revoked_at=clock_timestamp() where id=pg_temp.mp_id('session-1');
set local role service_role;
select is(pg_temp.alert_status(p_secret=>repeat('b',64))->>'error','unauthorized','revoked device session invalidates delegation');
reset role;
select app.set_pos_order_alerts(false,'Synthetic OFF','background-alert-test-off');
set local role service_role;
select is(public.pos_disable_order_alert(pg_temp.mp_client(700),encode(sha256(convert_to(repeat('b',64),'UTF8')),'hex'))->>'ok','true',
 'exact capability can disable even after OFF/revocation');
reset role;
select is((select count(*) from app.pos_order_alert_registrations where enabled),0::bigint,'disable durably revokes registration');
select is(app.kitchen_print_containment_state(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch())->>'mode','blocked','ordinary containment unchanged');
select * from finish();
rollback;
