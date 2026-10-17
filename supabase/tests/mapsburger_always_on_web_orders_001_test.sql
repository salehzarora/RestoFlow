-- BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001: rollback-only synthetic security tests.
-- This scoped rollout pins these scope UUIDs. All rows below are synthetic
-- fixtures in the disposable CI database, never hosted restaurant operations.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
set local timezone to 'UTC';
select no_plan();

create function pg_temp.mp_id(label text) returns uuid language sql immutable as
$$select md5('manual-order-pilot-001-synthetic-'||label)::uuid$$;
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
create function pg_temp.ao_print(action text,n integer,device integer default 1) returns jsonb language plpgsql volatile as $$
begin
 if action='claim' then return public.pos_claim_web_order_print(pg_temp.mp_id('pin-'||device),pg_temp.mp_id('device-'||device),
  'synthetic-live-token-'||device,pg_temp.ao_request(n));
 elsif action='begin' then return public.pos_begin_web_order_print(pg_temp.mp_id('pin-'||device),pg_temp.mp_id('device-'||device),
  'synthetic-live-token-'||device,pg_temp.ao_request(n),pg_temp.mp_client(20000+n));
 elsif action='finish' then return public.pos_finish_web_order_print(pg_temp.mp_id('pin-'||device),pg_temp.mp_id('device-'||device),
  'synthetic-live-token-'||device,pg_temp.ao_request(n),pg_temp.mp_client(20000+n),'transport_accepted');
 end if;
 raise exception 'unsupported synthetic action';
end $$;
create function pg_temp.ao_config(intake boolean,printing boolean,devices integer default 1) returns bigint language sql volatile as $$
 select app.set_mapsburger_web_orders(intake,printing,case when devices=1 then array[pg_temp.mp_id('device-1')]
 else array[pg_temp.mp_id('device-1'),pg_temp.mp_id('device-2')] end,'Synthetic rollback-only test','always-on-security-test') $$;
create temp table _ao_results(label text primary key,r jsonb);
grant all on _ao_results to service_role,authenticated;
select set_config('request.jwt.claim.sub',pg_temp.mp_id('transport-user')::text,true);
-- ALWAYS_ON_FIXTURE_END: the optional two-connection harness uses only synthetic data.

select ok(c.relrowsecurity and c.relforcerowsecurity,c.relname||' has forced RLS') from pg_class c where c.oid in
 ('app.mapsburger_web_order_rollouts'::regclass,'app.mapsburger_live_web_requests'::regclass,
  'app.mapsburger_web_print_leases'::regclass,'app.mapsburger_web_print_lease_closures'::regclass);
select ok(not has_table_privilege(role_name,tbl,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),role_name||' denied '||tbl)
from unnest(array['anon','authenticated','service_role']) role_name cross join unnest(array[
 'app.mapsburger_web_order_rollouts','app.mapsburger_live_web_requests','app.mapsburger_web_print_leases',
 'app.mapsburger_web_print_lease_closures']) tbl;
select ok(not has_function_privilege(role_name,'app.set_mapsburger_web_orders(boolean,boolean,uuid[],text,text)','EXECUTE'),
 role_name||' cannot activate or deactivate rollout') from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('authenticated',p.oid,'EXECUTE')
 and has_function_privilege('service_role',p.oid,'EXECUTE'),n.nspname||' live submit is service-only')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='submit_web_order_live_request';
set local role service_role;
select is(pg_temp.ao_submit(1)->>'error','ordering_unavailable','migration is default OFF even with an enabled channel');
reset role;
select is((select count(*) from app.mapsburger_live_web_requests),0::bigint,'default OFF creates no enrollment');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false','default OFF reader is browse-only');

-- Capture an old accepted request before rollout. Never eligible despite a
-- valid unconsumed targeted enrollment and a later replayed Accept response.
insert into _ao_results values('old-submit',app.submit_web_order_request('mapsburger',pg_temp.mp_client(90),repeat('a',64),pg_temp.mp_order()));
insert into _ao_results values('old-pending-submit',app.submit_web_order_request('mapsburger',pg_temp.mp_client(91),repeat('a',64),pg_temp.mp_order()));
set local role authenticated;
insert into _ao_results values('old-accept',pg_temp.ao_accept(90));
reset role;
create temp table _ao_old as select to_jsonb(a) row from public.web_order_print_attempts a where request_id=pg_temp.ao_request(90);
select pg_temp.ao_config(true,true);
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','true','persistent rollout exposes live Pickup checkout');
select ok(not (select ordering_enabled from public.restaurant_storefront_profiles where slug='mapsburger'),
 'browse-only profile CHECK and stored flag remain intact');
update public.restaurant_storefront_profiles set paused_until=clock_timestamp()+interval '1 hour' where slug='mapsburger';
set local role service_role;
select is(pg_temp.ao_submit(1)->>'error','ordering_unavailable','PAUSED service refuses intake despite persistent switch');
reset role;
update public.restaurant_storefront_profiles set paused_until=null,opening_hours='{"weekly":[],"exceptions":[]}'::jsonb where slug='mapsburger';
set local role service_role;
select is(pg_temp.ao_submit(1)->>'error','ordering_unavailable','CLOSED service refuses intake despite persistent switch');
reset role;
update public.restaurant_storefront_profiles set opening_hours=(select h from _mp_hours) where slug='mapsburger';
set local role service_role;
insert into _ao_results values('one-submit',pg_temp.ao_submit(1)),('two-submit',pg_temp.ao_submit(2)),('three-submit',pg_temp.ao_submit(3));
select is((select r->>'status' from _ao_results where label='one-submit'),'pending','first ordinary customer is pending');
select is((select r->>'status' from _ao_results where label='two-submit'),'pending','independent second customer is pending');
select is(pg_temp.ao_submit(1)->>'replayed','true','exact normal retry preserves identity');
select is(pg_temp.ao_submit(1,p_token=>repeat('b',64))->>'error','idempotency_conflict','wrong capability cannot recover another order');
select is(pg_temp.ao_submit(4,p_slug=>'manual-pilot-foreign')->>'error','ordering_unavailable','ordinary path never enables another restaurant');
select is(pg_temp.ao_submit(4,p_body=>pg_temp.mp_order()||'{"grand_total_minor":1}'::jsonb)->>'error','invalid_request','customer total tampering rejected');
reset role;
select is((select count(*) from app.mapsburger_live_web_requests),3::bigint,'three fresh requests enrolled; old request never backfilled');
select is((select count(*) from public.orders),1::bigint,'submissions create no additional canonical orders');
set local role authenticated;
select is(pg_temp.ao_policy()->>'mode','blocked','no accepted lease grants no printing or ordinary authority');
select is(pg_temp.ao_accept(91)->>'error','ordering_unavailable','pre-activation pending request cannot enroll through acceptance');
select is(pg_temp.ao_accept(1,2)->>'error','ordering_unavailable','non-whitelisted POS cannot accept live printing request');
insert into _ao_results values('one-accept',pg_temp.ao_accept(1));
select is((select r->>'status' from _ao_results where label='one-accept'),'accepted','first trusted acceptance succeeds');
select is(pg_temp.ao_policy()->>'mode','target_only','unchanged v63 receives exact target-only wire mode');
select is(pg_temp.ao_policy()->>'target_request_id',pg_temp.ao_request(1)::text,'lease is exact internal request');
select is(pg_temp.ao_policy(2)->>'mode','blocked','other device gets no target projection');
select is(pg_temp.ao_print('claim',1,3)->>'error','not_found','cross-tenant POS cannot claim target');
select is(public.pos_kitchen_print_containment(pg_temp.mp_id('device-1'),'forged-device-token')->>'error',
 'invalid_session','forged session cannot read target authorization');
select is(public.pull_kitchen_print_dispatches(pg_temp.mp_id('device-1'),'synthetic-live-token-1')->>'error',
 'containment_blocked','ordinary broad pull remains BLOCKED during target printing');
select is(pg_temp.ao_accept(2)->>'error','order_rejected','second acceptance is retryably busy before canonical creation');
select is(pg_temp.ao_print('claim',90)->>'error','containment_blocked','old accepted request cannot be claimed');
select is(pg_temp.ao_print('begin',1)->>'error','not_claim_owner','begin without claim fails closed');
reset role;
update public.kitchen_printer_readiness_reports set secure_spool_available=false where device_id=pg_temp.mp_id('device-1');
set local role authenticated;
select is(pg_temp.ao_print('claim',1)->>'error','readiness_required','HTTP/session success never fabricates secure-spool readiness');
reset role;
update public.kitchen_printer_readiness_reports set secure_spool_available=true where device_id=pg_temp.mp_id('device-1');
set local role authenticated;
insert into _ao_results values('one-claim',pg_temp.ao_print('claim',1));
reset role;
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
values(pg_temp.mp_id('printer-2'),pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),
 'Synthetic changed assignment','network','kitchen','80mm',true);
update public.kitchen_printer_readiness_reports set printer_assignment_id=pg_temp.mp_id('printer-2') where device_id=pg_temp.mp_id('device-1');
set local role authenticated;
select is(pg_temp.ao_print('begin',1)->>'error','not_claim_owner','assignment mutation between claim and begin fails closed');
reset role;
update public.kitchen_printer_readiness_reports set printer_assignment_id=pg_temp.mp_id('printer') where device_id=pg_temp.mp_id('device-1');
set local role authenticated;
insert into _ao_results values('one-begin',pg_temp.ao_print('begin',1));
select is((select r->>'state' from _ao_results where label='one-claim'),'claimed','fresh genuine readiness permits exact claim');
select is((select r->>'send_authorized' from _ao_results where label='one-begin'),'true','one irreversible begin authorizes one send');
select is(pg_temp.ao_print('begin',1)->>'send_authorized','false','begin replay never authorizes a second send');
insert into _ao_results values('one-finish',pg_temp.ao_print('finish',1));
select is(pg_temp.ao_policy()->>'mode','blocked','terminal target projects BLOCKED without ordinary authority');
insert into _ao_results values('two-accept',pg_temp.ao_accept(2));
select is((select r->>'status' from _ao_results where label='two-accept'),'accepted','next customer accepts once prior callback is terminal');
select is(pg_temp.ao_policy()->>'target_request_id',pg_temp.ao_request(2)::text,'second exact target supersedes only terminal first lease');
select is(pg_temp.ao_accept(1)->>'replayed','true','accepted replay returns mapping without target reselection');
select is(pg_temp.ao_policy()->>'target_request_id',pg_temp.ao_request(2)::text,'old replay cannot displace active target');
select pg_temp.ao_print('claim',2),pg_temp.ao_print('begin',2),pg_temp.ao_print('finish',2);
reset role;
select is((select count(*) from public.orders),3::bigint,'busy denial created no duplicate canonical order');
select is((select to_jsonb(a) from public.web_order_print_attempts a where request_id=pg_temp.ao_request(90)),
 (select row from _ao_old),'old failed/unstarted accepted enrollment remains byte-identical');

set local role service_role;
insert into _ao_results values('four-submit',pg_temp.ao_submit(4));
reset role;
create function pg_temp.ao_fail_lease() returns trigger language plpgsql as $$
begin raise exception 'synthetic lease enrollment failure' using errcode='23514'; end $$;
create trigger synthetic_fail_lease before insert on app.mapsburger_web_print_leases
 for each row execute function pg_temp.ao_fail_lease();
set local role authenticated;
select throws_ok($$select pg_temp.ao_accept(4)$$,'23514','synthetic lease enrollment failure',
 'lease insertion failure rolls back acceptance orchestration');
reset role;
drop trigger synthetic_fail_lease on app.mapsburger_web_print_leases;
select is((select status from public.web_order_requests where id=pg_temp.ao_request(4)),'pending','failed lease leaves original pending request');
select is((select count(*) from public.orders),3::bigint,'failed lease creates no canonical order, dispatch or decision');
select ok(not exists(select 1 from public.web_order_decisions where request_id=pg_temp.ao_request(4)),
 'failed lease rolls back attributed accepted decision');

select pg_temp.ao_config(false,true);
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false','operator OFF closes actual website checkout');
set local role service_role;
select is(pg_temp.ao_submit(5)->>'error','ordering_unavailable','OFF rejects fresh customer submission');
select is(pg_temp.ao_submit(1)->>'replayed','true','OFF retains exact capability recovery');
reset role;
set local role authenticated;
select is(pg_temp.ao_accept(3)->>'status','accepted','intake OFF preserves admitted pending acceptance');
reset role;
select pg_temp.ao_config(false,false);
set local role authenticated;
select is(pg_temp.ao_policy()->>'mode','blocked','emergency print OFF revokes active target projection');
select is(pg_temp.ao_print('claim',3)->>'error','containment_blocked','emergency OFF blocks new claim');
reset role;
select pg_temp.ao_config(true,true);
set local role authenticated;
select is(pg_temp.ao_accept(3)->>'replayed','true','old accepted identity still recoverable after re-enable');
select is(pg_temp.ao_policy()->>'mode','blocked','re-enable never resurrects old generation lease');
reset role;
select throws_ok($$update app.mapsburger_web_order_rollouts set reason='overwrite'$$,'42501',null,'rollout audit is immutable');
select throws_ok($$delete from app.mapsburger_live_web_requests$$,'42501',null,'eligibility evidence cannot be removed');
select throws_ok($$truncate app.mapsburger_web_print_leases,app.mapsburger_web_print_lease_closures$$,'42501',null,'exact lease history cannot be truncated');
select is(app.kitchen_print_containment_state(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch())->>'mode','blocked',
 'global ordinary policy remained BLOCKED throughout');
select is((select count(*) from app.storefront_manual_order_pilots),0::bigint,'persistent feature never mutates pilot history');
select * from finish();
rollback;
