-- BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001: rollback-only synthetic containment proof.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
set local timezone to 'UTC';
select no_plan();

create function pg_temp.pi_id(label text) returns uuid language sql immutable as
$$select md5('pos-online-inbox-001-'||label)::uuid$$;
create function pg_temp.pi_uuid(n integer) returns uuid language sql immutable as
$$select ('30000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.pi_id('org'),'PI001 Synthetic A','pi001-a','ILS'),
 (pg_temp.pi_id('org_b'),'PI001 Synthetic B','pi001-b','ILS');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.pi_id('restaurant'),pg_temp.pi_id('org'),'PI001 A','UTC'),
 (pg_temp.pi_id('restaurant_b'),pg_temp.pi_id('org_b'),'PI001 B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_rate_bp,tax_mode)
select pg_temp.pi_id(label),pg_temp.pi_id(case when label='branch_b' then 'org_b' else 'org' end),
 pg_temp.pi_id(case when label='branch_b' then 'restaurant_b' else 'restaurant' end),label,'UTC',true,1800,'exclusive'
from unnest(array['branch','sibling','branch_b']) label;
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
values(pg_temp.pi_id('printer'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'),
 'PI001 Synthetic Kitchen','network','kitchen','80mm',true);
insert into menu_categories(id,organization_id,restaurant_id,name) values
 (pg_temp.pi_id('category'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),'PI001 Food'),
 (pg_temp.pi_id('category_b'),pg_temp.pi_id('org_b'),pg_temp.pi_id('restaurant_b'),'PI001 Foreign Food');
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
select pg_temp.pi_id(label),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('category'),
 'PI001 '||label,case when label='free' then 0 else 1000 end,'ILS'
from unnest(array['paid','free']) label;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
values(pg_temp.pi_id('paid_b'),pg_temp.pi_id('org_b'),pg_temp.pi_id('restaurant_b'),pg_temp.pi_id('category_b'),'PI001 Foreign',1000,'ILS');
insert into modifiers(id,organization_id,restaurant_id,menu_item_id,name,selection_type,min_select,max_select,is_required)
values(pg_temp.pi_id('group'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('paid'),'PI001 Choice','single',1,1,true);
insert into modifier_options(id,organization_id,restaurant_id,modifier_id,name,price_delta_minor)
values(pg_temp.pi_id('option'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('group'),'PI001 Option',250);
create temp table _pi_hours as select jsonb_build_object('weekly',
 (select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c)) from generate_series(0,6) d
 cross join (values('00:00','12:00'),('11:00','00:00')) w(o,c)),'exceptions','[]'::jsonb) h;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.pi_id('restaurant'),pg_temp.pi_id('org'),pg_temp.pi_id('branch'),'pi001-alpha','PI001 Alpha',true,h,true from _pi_hours;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.pi_id('restaurant_b'),pg_temp.pi_id('org_b'),pg_temp.pi_id('branch_b'),'pi001-bravo','PI001 Bravo',true,h,true from _pi_hours;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
select organization_id,restaurant_id,id,true from branches where id in
 (pg_temp.pi_id('branch'),pg_temp.pi_id('sibling'),pg_temp.pi_id('branch_b')) on conflict(branch_id) do update set submission_enabled=excluded.submission_enabled;

-- Two POS tills in the same branch, one sibling branch and one foreign tenant.
create temp table _pi_staff as select n,
 pg_temp.pi_id(case when n=4 then 'org_b' else 'org' end) org,
 pg_temp.pi_id(case when n=4 then 'restaurant_b' else 'restaurant' end) restaurant,
 pg_temp.pi_id(case when n=4 then 'branch_b' when n=3 then 'sibling' else 'branch' end) branch,
 pg_temp.pi_id('device-'||n) device,pg_temp.pi_id('pairing-'||n) pairing,
 pg_temp.pi_id('session-'||n) session,pg_temp.pi_id('staff-'||n) staff,
 pg_temp.pi_id('membership-'||n) membership,pg_temp.pi_id('employee-'||n) employee,
 pg_temp.pi_id('pin-'||n) pin,pg_temp.pi_id('shift-'||n) shift
from generate_series(1,4) n;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
select device,org,restaurant,branch,'pos' from _pi_staff;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
select pairing,org,restaurant,branch,device,'active' from _pi_staff;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
select session,org,restaurant,branch,device,pairing,app.hash_provisioning_secret('synthetic-pos-token-'||n),now()+interval '30 days' from _pi_staff;
insert into app_users(id,email) select staff,'pi001-staff-'||n||'@example.test' from _pi_staff;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
select membership,staff,org,restaurant,branch,case when n=2 then 'manager' else 'cashier' end from _pi_staff;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
select employee,org,restaurant,branch,staff,membership,'PI001 Staff '||n from _pi_staff;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
select pin,org,restaurant,branch,session,employee,membership,now()+interval '6 hours' from _pi_staff;
insert into shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
select shift,org,restaurant,branch,device,employee,membership,'pi001-open-'||n,'open' from _pi_staff;

create function pg_temp.pi_order(item text default 'paid') returns jsonb language sql immutable as $$
 select jsonb_build_object('order_type','takeaway','customer',jsonb_build_object('name','PI001 Guest','phone','+972520001001'),
 'notes','PI001 Pickup note','items',jsonb_build_array(jsonb_build_object('menu_item_id',pg_temp.pi_id(item),
 'quantity',2,'modifiers',case when item='paid' then jsonb_build_array(jsonb_build_object(
 'modifier_option_id',pg_temp.pi_id('option'),'quantity',1)) else '[]'::jsonb end)))
$$;
create function pg_temp.pi_request(n integer,item text default 'paid',scope text default 'branch') returns uuid
language plpgsql as $$
declare q jsonb; b public.branches; body jsonb:=pg_temp.pi_order(item); rid uuid:=pg_temp.pi_id('request-'||n);
begin
 select * into b from public.branches where id=pg_temp.pi_id(scope);
 q:=app.price_web_order(case when scope='branch_b' then 'pi001-bravo' else 'pi001-alpha' end,body->'items');
 if q->>'ok'<>'true' then raise exception 'synthetic quote failed: %',q; end if;
 insert into public.web_order_requests(id,organization_id,restaurant_id,branch_id,client_request_id,status_token_hash,payload_hash,
 customer_name,customer_phone,notes,priced_items,currency_code,subtotal_minor,tax_total_minor,grand_total_minor,expires_at,status_until)
 values(rid,b.organization_id,b.restaurant_id,b.id,pg_temp.pi_uuid(n),repeat('a',64),repeat('b',64),
 'PI001 Guest','+972520'||lpad(n::text,6,'0'),'PI001 Pickup note',q->'priced_items','ILS',
 (q->>'subtotal_minor')::bigint,(q->>'tax_total_minor')::bigint,(q->>'grand_total_minor')::bigint,
 now()+interval '15 minutes',now()+interval '24 hours');
 return rid;
end$$;
create function pg_temp.pi_inbox(rid uuid default null,n integer default 1,token text default null) returns jsonb
language sql volatile as $$select public.pos_web_order_inbox(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
 coalesce(token,'synthetic-pos-token-'||n),rid)$$;
create function pg_temp.pi_accept(rid uuid,decision integer default 1,n integer default 1,token text default null) returns jsonb
language sql volatile as $$select public.pos_accept_web_order(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
 coalesce(token,'synthetic-pos-token-'||n),rid,pg_temp.pi_uuid(10000+decision))$$;
create function pg_temp.pi_reject(rid uuid,decision integer default 1,reason text default 'Unavailable',n integer default 1) returns jsonb
language sql volatile as $$select public.pos_reject_web_order(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
 'synthetic-pos-token-'||n,rid,pg_temp.pi_uuid(10000+decision),reason)$$;
create function pg_temp.pi_counts() returns jsonb language sql security definer set search_path='' as $$
select jsonb_build_object('orders',(select count(*) from public.orders where organization_id=pg_temp.pi_id('org')),
 'items',(select count(*) from public.order_items where organization_id=pg_temp.pi_id('org')),
 'modifiers',(select count(*) from public.order_item_modifiers where organization_id=pg_temp.pi_id('org')),
 'sync',(select count(*) from public.sync_operations where organization_id=pg_temp.pi_id('org')),
 'audit',(select count(*) from public.audit_events where organization_id=pg_temp.pi_id('org')),
 'dispatch',(select count(*) from public.kitchen_print_dispatches where organization_id=pg_temp.pi_id('org')),
 'payments',(select count(*) from public.payments where organization_id=pg_temp.pi_id('org')),
 'decisions',(select count(*) from public.web_order_decisions where organization_id=pg_temp.pi_id('org')))
$$;
create temp table _pi_results(label text primary key,r jsonb);
grant all on _pi_results to authenticated;
select set_config('request.jwt.claim.sub',pg_temp.pi_id('transport-only')::text,true);
-- PRINT-003 FIXTURE END: the local two-connection harness commits this prefix.

create function pg_temp.tp_claim(rid uuid,n integer default 1,token text default null) returns jsonb
language sql volatile as $$select public.pos_claim_web_order_print(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
coalesce(token,'synthetic-pos-token-'||n),rid)$$;
create function pg_temp.tp_begin(rid uuid,attempt integer default 1,n integer default 1) returns jsonb
language sql volatile as $$select public.pos_begin_web_order_print(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
'synthetic-pos-token-'||n,rid,pg_temp.pi_uuid(20000+attempt))$$;
create function pg_temp.tp_finish(rid uuid,attempt integer,status text,n integer default 1) returns jsonb
language sql volatile as $$select public.pos_finish_web_order_print(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
'synthetic-pos-token-'||n,rid,pg_temp.pi_uuid(20000+attempt),status)$$;
create function pg_temp.tp_status(rid uuid,n integer default 1) returns jsonb
language sql volatile as $$select public.pos_web_order_print_status(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
'synthetic-pos-token-'||n,rid)$$;
create function pg_temp.tp_pull(n integer default 1) returns jsonb
language sql volatile as $$select public.pull_kitchen_print_dispatches(pg_temp.pi_id('device-'||n),'synthetic-pos-token-'||n)$$;
create function pg_temp.tp_readiness() returns void language sql as $$
 insert into public.kitchen_printer_readiness_reports(organization_id,restaurant_id,branch_id,device_id,
 capability,app_build,printer_purpose,transport_kind,paper_width,printer_fingerprint,secure_spool_available,
 unresolved_local_jobs,mode_revision,printer_assignment_id,expires_at)
 select org,restaurant,branch,device,'kitchen_printer_only_v1','print-003-synthetic','kitchen_ticket','network','80mm',
 repeat('a',64),true,0,1,pg_temp.pi_id('printer'),clock_timestamp()+interval '10 minutes'
 from _pi_staff where n in (1,2)
 on conflict(organization_id,device_id) do update set expires_at=excluded.expires_at;
$$;


create function pg_temp.lc_hold(did uuid) returns void language sql as $$
 insert into public.kitchen_print_dispatch_holds(dispatch_id,organization_id,restaurant_id,branch_id,
 snapshot_at,dispatch_fingerprint,manifest_sha256,reason,operator_reference)
 select d.id,d.organization_id,d.restaurant_id,d.branch_id,clock_timestamp(),md5(to_jsonb(d)::text),repeat('a',64),
 'automatic retransmission prohibited pending review','synthetic-local-test' from public.kitchen_print_dispatches d where d.id=did;
$$;
create function pg_temp.lc_policy(m text,target uuid default null,expiry timestamptz default null) returns void language sql as $$
 insert into public.kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,target_request_id,expires_at,reason,operator_reference)
 values(pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'),m,target,expiry,'synthetic policy','synthetic-local-test');
$$;
create function pg_temp.lc_state(n integer default 1) returns jsonb language sql as $$
 select public.pos_kitchen_print_containment(pg_temp.pi_id('device-'||n),'synthetic-pos-token-'||n);
$$;
update public.branches set kitchen_workflow_mode='printer_only' where id=pg_temp.pi_id('branch');
select pg_temp.tp_readiness();
select pg_temp.pi_request(n) from generate_series(1,9) n;
alter table public.web_order_decisions disable trigger web_order_decisions_reserve_print;
set local role authenticated;
select pg_temp.pi_accept(pg_temp.pi_id('request-'||n),n) from generate_series(1,8) n;
reset role;
alter table public.web_order_decisions enable trigger web_order_decisions_reserve_print;
create temp table _lc_initials as select d.*,w.id request_id from public.kitchen_print_dispatches d
 join public.web_order_requests w on w.canonical_order_id=d.order_id;
insert into public.order_service_rounds(id,organization_id,restaurant_id,branch_id,order_id,round_number,device_id,opened_by_employee_profile_id)
 select pg_temp.pi_id('round'),organization_id,restaurant_id,branch_id,order_id,2,pg_temp.pi_id('device-1'),pg_temp.pi_id('employee-1')
 from _lc_initials where request_id=pg_temp.pi_id('request-1');
insert into public.order_edits(id,organization_id,restaurant_id,branch_id,order_id,edit_number,device_id,local_operation_id,pin_session_id,
 employee_profile_id,membership_id,kitchen_channel)
 select pg_temp.pi_id('edit'),organization_id,restaurant_id,branch_id,order_id,1,pg_temp.pi_id('device-1'),'local-edit-test',
 pg_temp.pi_id('pin-1'),pg_temp.pi_id('employee-1'),pg_temp.pi_id('membership-1'),'paper'
 from _lc_initials where request_id=pg_temp.pi_id('request-1');
insert into public.kitchen_print_dispatches(id,organization_id,restaurant_id,branch_id,order_id,service_round_id,order_edit_id,
 dispatch_type,money_free_payload,idempotency_key,created_at)
 select pg_temp.pi_id('legacy-'||kind),organization_id,restaurant_id,branch_id,order_id,
 case when kind='service_round' then pg_temp.pi_id('round') end,case when kind='order_edit' then pg_temp.pi_id('edit') end,
 kind,jsonb_build_object('v',1,'kind',kind),'legacy-'||kind,created_at
 from _lc_initials cross join unnest(array['service_round','void','order_edit']) kind where request_id=pg_temp.pi_id('request-1');
-- Own live and expired foreign claims are held too; they must not leak in
-- the returned-page or has_more paths even though claim eligibility differs.
update public.kitchen_print_dispatches set claimed_at=clock_timestamp(),claimed_by_device_id=pg_temp.pi_id('device-1'),
 claim_expires_at=clock_timestamp()+interval '10 minutes' where id=pg_temp.pi_id('legacy-void');
update public.kitchen_print_dispatches set claimed_at=clock_timestamp()-interval '20 minutes',claimed_by_device_id=pg_temp.pi_id('device-2'),
 claim_expires_at=clock_timestamp()-interval '10 minutes' where id=pg_temp.pi_id('legacy-order_edit');
create temp table _lc_held_before as select * from public.kitchen_print_dispatches where
 id in(select id from _lc_initials where request_id=pg_temp.pi_id('request-1')) or id in
 (pg_temp.pi_id('legacy-service_round'),pg_temp.pi_id('legacy-void'),pg_temp.pi_id('legacy-order_edit'));
select pg_temp.lc_hold(id) from _lc_held_before;
-- CONTAINMENT-001 HARNESS SETUP END: committed synthetic fixture only.
select is((select count(*) from public.kitchen_print_dispatch_holds),4::bigint,'all four historical types held');
select ok(not exists(select 1 from public.kitchen_print_dispatches d join _lc_held_before h using(id)
 where to_jsonb(d) is distinct from to_jsonb(h)),'holds preserve every historical dispatch byte');
select is((select count(*) from public.web_order_print_attempts),0::bigint,'holds never enroll historical attempts');
select ok(relrowsecurity and relforcerowsecurity,relname||' forced RLS') from pg_class where oid in
 ('public.kitchen_print_dispatch_holds'::regclass,'public.kitchen_print_containment_policies'::regclass);
select ok(not has_table_privilege(role_name,tbl,'SELECT') and not has_table_privilege(role_name,tbl,'INSERT'),
 role_name||' denied private '||tbl) from unnest(array['anon','authenticated','service_role']) role_name
 cross join unnest(array['public.kitchen_print_dispatch_holds','public.kitchen_print_containment_policies']) tbl;
select throws_ok($$delete from public.kitchen_print_dispatch_holds$$,'42501',null,'holds cannot be deleted');
select throws_ok($$update public.kitchen_print_dispatch_holds set reason='release'$$,'42501',null,'holds cannot be rewritten');
select throws_ok($$truncate public.kitchen_print_dispatch_holds$$,'42501',null,'holds cannot be truncated');
select throws_ok($$insert into public.kitchen_print_dispatch_holds(dispatch_id,organization_id,restaurant_id,branch_id,
 snapshot_at,dispatch_fingerprint,manifest_sha256,reason,operator_reference)
 select id,pg_temp.pi_id('org_b'),restaurant_id,branch_id,clock_timestamp(),md5(to_jsonb(d)::text),repeat('a',64),'test','test'
 from public.kitchen_print_dispatches d where id=(select id from _lc_initials where request_id=pg_temp.pi_id('request-2'))$$,
 '23514',null,'operator hold is still exactly tenant scoped');
select throws_ok($$insert into public.kitchen_print_dispatch_holds(dispatch_id,organization_id,restaurant_id,branch_id,
 snapshot_at,dispatch_fingerprint,manifest_sha256,reason,operator_reference)
 select id,organization_id,restaurant_id,branch_id,clock_timestamp(),repeat('f',32),repeat('a',64),'test','test'
 from public.kitchen_print_dispatches d where id=(select id from _lc_initials where request_id=pg_temp.pi_id('request-2'))$$,
 '23514',null,'changed snapshot cannot silently become a hold');
set local role anon;
select throws_ok($$select pg_temp.lc_state()$$,'42501',null,'anonymous containment read denied');
reset role;
set local role authenticated;
select throws_ok($$select * from public.kitchen_print_dispatch_holds$$,'42501',null,'paired client cannot read private hold audit');
select throws_ok($$insert into public.kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
 values(pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'),'ordinary','forged','client')$$,'42501',null,'paired client cannot release or alter branch policy');
select is(pg_temp.lc_state()->>'mode','ordinary','ordinary mode absent a reviewed policy');
select is(jsonb_array_length(pg_temp.lc_state()->'held_dispatch_ids'),4,'paired POS receives exact branch holds');
select is(jsonb_array_length(pg_temp.lc_state(3)->'held_dispatch_ids'),0,'sibling branch cannot read holds');
select is(jsonb_array_length(pg_temp.lc_state(4)->'held_dispatch_ids'),0,'foreign tenant cannot read holds');
select is(public.pos_kitchen_print_containment(pg_temp.pi_id('device-1'),'forged')->>'error','invalid_session','forged token rejected');
insert into _pi_results values('page1',public.pull_kitchen_print_dispatches(pg_temp.pi_id('device-1'),'synthetic-pos-token-1',3));
select is(jsonb_array_length((select r->'dispatches' from _pi_results where label='page1')),3,'mixed page fills with unheld jobs');
select is((select r->>'has_more' from _pi_results where label='page1'),'true','unheld remainder makes truthful has_more');
insert into _pi_results values('page2',(select public.pull_kitchen_print_dispatches(pg_temp.pi_id('device-1'),'synthetic-pos-token-1',3,
 (r->'next_cursor'->>'created_at')::timestamptz,(r->'next_cursor'->>'id')::uuid,(r->'next_cursor'->>'type_rank')::integer)
 from _pi_results where label='page1'));
insert into _pi_results values('page3',(select public.pull_kitchen_print_dispatches(pg_temp.pi_id('device-1'),'synthetic-pos-token-1',3,
 (r->'next_cursor'->>'created_at')::timestamptz,(r->'next_cursor'->>'id')::uuid,(r->'next_cursor'->>'type_rank')::integer)
 from _pi_results where label='page2'));
select is(jsonb_array_length((select r->'dispatches' from _pi_results where label='page3')),1,'last page contains only last unheld job');
select is((select r->>'has_more' from _pi_results where label='page3'),'false','held tail does not fabricate has_more');
reset role;
select ok(not exists(select 1 from _pi_results r cross join lateral jsonb_array_elements(r.r->'dispatches') d
 join public.kitchen_print_dispatch_holds h on h.dispatch_id=(d->>'id')::uuid where r.label like 'page%'),'no candidate/page held leakage');
select ok(not exists(select 1 from public.kitchen_print_dispatches d join _lc_held_before h using(id)
 where to_jsonb(d) is distinct from to_jsonb(h)),'held own/expired claims remain byte-identical after broad pull');
select pg_temp.pi_request(10);
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-10'),10)->>'ok','true','second future target accepted before controlled policy');
reset role;
select pg_temp.lc_policy('target_only',pg_temp.pi_id('request-9'),clock_timestamp()+interval '10 minutes');
set local role authenticated;
select is(pg_temp.lc_state()->>'mode','target_only','explicit bounded target mode returned');
select is(pg_temp.tp_pull()->>'error','containment_blocked','qualifying readiness cannot unlock broad feed');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-10'))->>'error','containment_blocked','another genuine target cannot bypass exact request policy');
select is(pg_temp.pi_accept(pg_temp.pi_id('request-9'),9)->>'ok','true','ordinary acceptance behavior retained');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-9'))->>'state','claimed','exact intended target can be claimed');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-9'),9)->>'send_authorized','true','only initial begin authorizes target send');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-9'),9)->>'send_authorized','false','lost/replayed begin never reauthorizes');
reset role;
select pg_temp.lc_policy('blocked');
set local role authenticated;
select is(pg_temp.tp_finish(pg_temp.pi_id('request-9'),9,'transport_accepted')->>'state','transport_accepted','finish remains available under a later block');
select is(pg_temp.tp_finish(pg_temp.pi_id('request-9'),9,'transport_accepted')->>'replayed','true','lost finish retry is idempotent');
reset role;
select pg_temp.lc_policy('ordinary');
select is((app.kitchen_print_containment_state(pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'))->>'mode'),'ordinary','ending target mode requires explicit operator successor');
select is(jsonb_array_length(app.kitchen_print_containment_state(pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'))->'held_dispatch_ids'),4,'legacy holds survive ordinary successor');
select throws_ok($$update public.kitchen_print_containment_policies set mode='ordinary'$$,'42501',null,'policy audit history immutable');
select throws_ok($$delete from public.kitchen_print_containment_policies$$,'42501',null,'policy deletion cannot release backlog');
update public.device_sessions set is_active=false where device_id=pg_temp.pi_id('device-1');
set local role authenticated;
select is(pg_temp.lc_state()->>'error','invalid_session','revoked real session cannot read scope policy');
reset role;
select * from finish();
rollback;
