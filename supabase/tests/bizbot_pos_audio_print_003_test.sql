-- BIZBOT-POS-AUDIO-PRINT-003: rollback-only target/fence security and lifecycle.
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

-- PRINT-003 HARNESS SETUP END: definitions above are reused without assertions.
select ok(relrowsecurity and relforcerowsecurity,'private attempt ledger has forced RLS')
 from pg_class where oid='public.web_order_print_attempts'::regclass;
select is((select array_agg(cmd order by cmd)::text[] from pg_policies
 where schemaname='public' and tablename='web_order_print_attempts'),
 array['DELETE','INSERT','SELECT','UPDATE']::text[],'four explicit deny policies');
select ok(not has_table_privilege(role_name,'public.web_order_print_attempts','SELECT')
 and not has_table_privilege(role_name,'public.web_order_print_attempts','INSERT'),role_name||' has no private table grants')
 from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege('anon',p.oid,'EXECUTE') and has_function_privilege('authenticated',p.oid,'EXECUTE'),
 p.proname||' is authenticated-only') from pg_proc p where p.pronamespace='public'::regnamespace
 and p.proname in ('pos_claim_web_order_print','pos_begin_web_order_print','pos_finish_web_order_print','pos_web_order_print_status');
select ok(not p.prosecdef and p.proconfig @> array['search_path=""'],p.proname||' is a pinned public INVOKER')
 from pg_proc p where p.pronamespace='public'::regnamespace
 and p.proname in ('pos_claim_web_order_print','pos_begin_web_order_print','pos_finish_web_order_print','pos_web_order_print_status');
select ok(not has_function_privilege('authenticated','app.pos_web_order_print_operation(uuid,uuid,text,uuid,text,uuid,text,text)','EXECUTE'),
 'action router is internal only');
set local role anon;
select throws_ok($$select pg_temp.tp_claim(pg_temp.pi_id('request-1'))$$,'42501',null,'anonymous target denied');
reset role;

-- Historical unresolved accepted ticket existed before this feature. Model
-- installation timing, not deletion/backfill; its contents must stay untouched.
update public.branches set kitchen_workflow_mode='printer_only' where id=pg_temp.pi_id('branch');
select pg_temp.tp_readiness();
select pg_temp.pi_request(90);
alter table public.web_order_decisions disable trigger web_order_decisions_reserve_print;
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-90'),90)->>'ok','true','historical accepted fixture');
reset role;
alter table public.web_order_decisions enable trigger web_order_decisions_reserve_print;
create temp table _tp_historical as select d.* from public.kitchen_print_dispatches d
 join public.web_order_requests w on w.canonical_order_id=d.order_id where w.id=pg_temp.pi_id('request-90');
select pg_temp.pi_request(n) from generate_series(1,6) n;
set local role authenticated;
insert into _pi_results values('accept1',pg_temp.pi_accept(pg_temp.pi_id('request-1'),1));
select is((select r->>'ok' from _pi_results where label='accept1'),'true','existing writer accepts normally');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-90'))->>'error','target_unavailable','no historical backfill or targeted historical claim');
reset role;
select is((select count(*) from public.web_order_print_attempts where request_id=pg_temp.pi_id('request-1')),1::bigint,
 'same acceptance transaction seeds one exact initial target');
select ok((select a.canonical_order_id=w.canonical_order_id and a.decision_id=wd.decision_id
 and a.dispatch_id=d.id and d.dispatch_type='initial_order' from public.web_order_print_attempts a
 join public.web_order_requests w on w.id=a.request_id join public.web_order_decisions wd on wd.request_id=a.request_id
 join public.kitchen_print_dispatches d on d.id=a.dispatch_id where a.request_id=pg_temp.pi_id('request-1')),
 'request, decision, canonical order and initial dispatch are server-resolved');
select ok(not exists(select 1 from public.kitchen_print_dispatches d join _tp_historical h on h.id=d.id
 where to_jsonb(d) is distinct from to_jsonb(h)),'target claim leaves historical unacknowledged ticket byte-identical');
select throws_ok($$update public.web_order_print_attempts set decision_id=pg_temp.pi_uuid(99999)
 where request_id=pg_temp.pi_id('request-1')$$,'42501',null,'decision identity immutable');
select throws_ok($$delete from public.web_order_print_attempts where request_id=pg_temp.pi_id('request-1')$$,
 '42501',null,'fence history cannot be deleted');
set local role authenticated;
select throws_ok($$select * from public.web_order_print_attempts$$,'42501',null,'real authenticated private read denied');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'),1,'wrong-token')->>'error','invalid_session','device token required');
select is(public.pos_claim_web_order_print(pg_temp.pi_id('pin-2'),pg_temp.pi_id('device-1'),
 'synthetic-pos-token-1',pg_temp.pi_id('request-1'))->>'error','invalid_session','PIN must belong to proven device');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'),3)->>'error','not_found','sibling branch cannot claim');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'),4)->>'error','not_found','cross tenant cannot claim');
reset role;
update public.memberships set role='kitchen_staff' where id=pg_temp.pi_id('membership-1');
set local role authenticated;
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'))->>'error','permission_denied','kitchen role cannot use POS target');
reset role;
update public.memberships set role='cashier' where id=pg_temp.pi_id('membership-1');
update public.pin_sessions set is_active=false where id=pg_temp.pi_id('pin-1');
set local role authenticated;
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'))->>'error','invalid_session','revoked PIN refused');
reset role;
update public.pin_sessions set is_active=true where id=pg_temp.pi_id('pin-1');
update public.kitchen_printer_readiness_reports set expires_at=clock_timestamp()-interval '1 second'
 where device_id=pg_temp.pi_id('device-1');
set local role authenticated;
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'))->>'error','readiness_required','fresh qualifying readiness required');
reset role;
select pg_temp.tp_readiness();
update public.shifts set status='closed',closed_at=clock_timestamp() where id=pg_temp.pi_id('shift-1');
set local role authenticated;
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'))->>'error','shift_required','live shift required');
reset role;
update public.shifts set status='open',closed_at=null where id=pg_temp.pi_id('shift-1');
update public.branches set kitchen_workflow_mode='kds' where id=pg_temp.pi_id('branch');
set local role authenticated;
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'))->>'error','branch_not_printer_only','KDS mode refuses competing POS printing');
reset role;
update public.branches set kitchen_workflow_mode='printer_only' where id=pg_temp.pi_id('branch');

-- A broad pull may still claim ordinary/history rows exactly as before, but
-- can never include new web initial targets, even before the target claim.
set local role authenticated;
insert into _pi_results values('broad',pg_temp.tp_pull());
select is((select jsonb_array_length(r->'dispatches') from _pi_results where label='broad'),1,'broad feed contains history only');
select isnt((select r->'dispatches'->0->>'order_id' from _pi_results where label='broad'),
 (select r->>'canonical_order_id' from _pi_results where label='accept1'),'broad feed never exposes accepted web target');
reset role;
-- The new target is not claimed by the older broad API.
select ok((select d.claimed_by_device_id is null from public.web_order_print_attempts a
 join public.kitchen_print_dispatches d on d.id=a.dispatch_id where a.request_id=pg_temp.pi_id('request-1')),
 'broad feed does not race target claim');
set local role authenticated;
insert into _pi_results values('claim1',pg_temp.tp_claim(pg_temp.pi_id('request-1')));
select is((select r->>'state' from _pi_results where label='claim1'),'claimed','exact target claim succeeds');
select ok((select r->'dispatch'->>'id'=r->>'dispatch_id' and r->'dispatch'->>'order_id'=r->>'canonical_order_id'
 and r->'dispatch'->>'dispatch_type'='initial_order' and r->>'printer_assignment_id'=pg_temp.pi_id('printer')::text
 from _pi_results where label='claim1'),'claim envelope pins initial dispatch and assigned printer');
select ok((select r::text not like '%customer_phone%' and r::text not like '%status_token_hash%'
 and r::text not like '%synthetic-pos-token%' from _pi_results where label='claim1'),'claim omits contacts and credentials');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'),2)->>'state','busy','second device cannot steal live target');
select ok(not(pg_temp.tp_claim(pg_temp.pi_id('request-1'),2)?'dispatch'),'busy response has no payload');
reset role;
-- Crash before reservation: lease can be reassigned, but stale holder may not send.
update public.web_order_print_attempts set claim_expires_at=clock_timestamp()-interval '1 second'
 where request_id=pg_temp.pi_id('request-1');
update public.kitchen_print_dispatches set claim_expires_at=clock_timestamp()-interval '1 second'
 where id=(select dispatch_id from public.web_order_print_attempts where request_id=pg_temp.pi_id('request-1'));
set local role authenticated;
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'),2)->>'state','claimed','crash before attempted transmission allows safe claim recovery');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-1'),1,1)->>'error','not_claim_owner','stale holder cannot reserve send');
insert into _pi_results values('begin1',pg_temp.tp_begin(pg_temp.pi_id('request-1'),1,2));
select is((select r->>'send_authorized' from _pi_results where label='begin1'),'true','one irreversible reservation authorizes one transmission');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-1'),1,2)->>'send_authorized','false','lost begin reply replay NEVER authorizes send again');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-1'),2,2)->>'send_authorized','false','different callback UUID cannot reopen fence');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'),1)->>'state','reconciliation_required','other device cannot resend after possible send');
select ok(not(pg_temp.tp_claim(pg_temp.pi_id('request-1'),1)?'dispatch'),'uncertain recovery has no printable payload');
reset role;
-- Expired claim and old retryable ACK do not remove the new durable fence.
update public.kitchen_print_dispatches set claim_expires_at=clock_timestamp()-interval '1 second'
 where id=(select dispatch_id from public.web_order_print_attempts where request_id=pg_temp.pi_id('request-1'));
set local role authenticated;
select is(public.acknowledge_kitchen_print_dispatch(pg_temp.pi_id('device-2'),'synthetic-pos-token-2',
 (select r->>'dispatch_id' from _pi_results where label='claim1')::uuid,'failed_retryable','network.unavailable')->>'ok',
 'true','legacy ACK stays compatible but cannot alter fence');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-1'),3,1)->>'send_authorized','false','lost ACK and lease expiry do not reauthorize');
select is(pg_temp.tp_finish(pg_temp.pi_id('request-1'),1,'transport_accepted',1)->>'error','not_attempt_owner','other device cannot finish attempt');
select is(pg_temp.tp_finish(pg_temp.pi_id('request-1'),1,'transport_accepted',2)->>'state','transport_accepted','correct owner finalizes transport observation');
select is(pg_temp.tp_finish(pg_temp.pi_id('request-1'),1,'transport_accepted',2)->>'replayed','true','lost final ACK is safely idempotent');
select is(pg_temp.tp_finish(pg_temp.pi_id('request-1'),1,'possibly_printed',2)->>'error','outcome_conflict','terminal outcome cannot be rewritten');
select is(pg_temp.pi_accept(pg_temp.pi_id('request-1'),1)->>'replayed','true','acceptance replay remains unchanged');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-1'))->>'state','transport_accepted','repeated UI callback does not print accepted target again');
select is(pg_temp.tp_status(pg_temp.pi_id('request-1'))->>'state','transport_accepted','restart can reconcile confirmed outcome without send');
reset role;
select throws_ok($$update public.web_order_print_attempts set attempt_id=null,attempt_reserved_at=null,
 attempt_device_id=null,attempt_pin_session_id=null where request_id=pg_temp.pi_id('request-1')$$,
 '42501',null,'reservation fence cannot be cleared');
select is((select count(*) from public.web_order_print_attempts where request_id=pg_temp.pi_id('request-1')),1::bigint,'one target across accept replays');
select is((select count(*) from public.kitchen_print_dispatches d join public.web_order_requests w
 on w.canonical_order_id=d.order_id where w.id=pg_temp.pi_id('request-1')),1::bigint,'one immutable dispatch across callbacks');

-- A native failure after reservation is recorded honestly; no automatic retry.
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-2'),2)->>'ok','true','second synthetic request accepted');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-2'))->>'state','claimed','second exact target claim');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-2'),10)->>'send_authorized','true','second target has its own one-shot reservation');
select is(pg_temp.tp_finish(pg_temp.pi_id('request-2'),10,'failed_retryable')->>'state','reconciliation_required',
 'native retryable classification after reservation requires operator reconciliation');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-2'),2)->>'state','reconciliation_required','restart/other device cannot auto retry native failure');
select is(pg_temp.tp_begin(pg_temp.pi_id('request-2'),11)->>'send_authorized','false','native failure never clears send fence');
reset role;
-- Ordinary KDS-mode acceptance remains unchanged and creates no POS target.
update public.branches set kitchen_workflow_mode='kds' where id=pg_temp.pi_id('branch');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-3'),3)->>'ok','true','KDS acceptance preserved');
select is(pg_temp.tp_claim(pg_temp.pi_id('request-3'))->>'error','target_unavailable','KDS acceptance has no competing target');
reset role;
select is((select count(*) from public.web_order_print_attempts where request_id=pg_temp.pi_id('request-3')),0::bigint,
 'KDS writer creates no target ledger');
select * from finish();
rollback;
