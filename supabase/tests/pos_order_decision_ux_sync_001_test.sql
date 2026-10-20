-- Issue356: explicit public rejection and terminal reconciliation; synthetic rollback-only.
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
create function pg_temp.p353_request(n integer) returns uuid language sql stable security definer set search_path='' as $$
  select id from public.web_order_requests where client_request_id=pg_temp.p353_client(n); $$;
create function pg_temp.p353_inbox(n integer) returns jsonb language sql volatile as $$
  select public.pos_web_order_inbox(pg_temp.p353_id('pin-'||n),pg_temp.p353_id('device-'||n),'synthetic-platform353-token-'||n); $$;
create function pg_temp.p353_accept(n integer,device integer default 1) returns jsonb language sql volatile as $$
  select public.pos_accept_web_order(pg_temp.p353_id('pin-'||device),pg_temp.p353_id('device-'||device),
    'synthetic-platform353-token-'||device,pg_temp.p353_request(n),pg_temp.p353_client(1000+n+device)); $$;
create function pg_temp.p353_register(n integer) returns jsonb language sql volatile as $$
  select public.pos_register_order_alert(pg_temp.p353_id('installation-'||n),'synthetic-platform353-fcm-token-'||n,repeat('a',64),
    pg_temp.p353_id('device-'||n),pg_temp.p353_id('pin-'||n),'synthetic-platform353-token-'||n); $$;
create function pg_temp.p353_print(n integer,device integer,action text,attempt uuid default null) returns jsonb language sql volatile as $$
  select app.pos_web_order_print_operation(pg_temp.p353_id('pin-'||device),pg_temp.p353_id('device-'||device),
    'synthetic-platform353-token-'||device,pg_temp.p353_request(n),action,attempt); $$;
create temp table _p353_results(label text primary key,r jsonb);
grant all on _p353_results to authenticated,service_role;
select set_config('request.jwt.claim.sub',pg_temp.p353_id('transport-user')::text,true);
select app.set_pos_order_alerts(true,'Synthetic platform notification gate','platform353-test');

create function pg_temp.p356_reject(n integer,reason text,device integer default 1) returns jsonb language sql volatile as $$
  select public.pos_reject_web_order_customer(pg_temp.p353_id('pin-'||device),pg_temp.p353_id('device-'||device),
    'synthetic-platform353-token-'||device,pg_temp.p353_request(n),pg_temp.p353_client(2000+n),reason); $$;
create function pg_temp.p356_status(n integer,capability text default repeat('a',64),slug text default 'platform-353-a1')
returns jsonb language sql volatile as $$
  select public.get_web_order_request_status(slug,pg_temp.p353_client(n),capability); $$;

select ok(relrowsecurity and relforcerowsecurity,'customer reason ledger has forced RLS')
  from pg_class where oid='app.web_order_customer_rejection_reasons'::regclass;
select ok(not has_table_privilege(role,'app.web_order_customer_rejection_reasons','SELECT')
  and not has_table_privilege(role,'app.web_order_customer_rejection_reasons','INSERT'),role||' cannot read/write public reasons directly')
  from unnest(array['anon','authenticated','service_role']) role;
select ok(not prosecdef and proconfig @> array['search_path=""'],'public explicit rejection wrapper remains invoker')
  from pg_proc where oid='public.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text)'::regprocedure;
select ok(not has_function_privilege('anon',oid,'EXECUTE') and not has_function_privilege('service_role',oid,'EXECUTE')
  and has_function_privilege('authenticated',oid,'EXECUTE'),'only authenticated callers may explicitly reject')
  from pg_proc where oid='public.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text)'::regprocedure;
set local role anon;
select throws_ok($$select pg_temp.p356_reject(1,'Public')$$,'42501',null,'anon cannot invoke customer rejection');
reset role;
set local role authenticated;
select throws_ok($$select * from app.web_order_customer_rejection_reasons$$,'42501',null,'authenticated cannot directly read customer reason ledger');
select is(pg_temp.p353_register(1)->>'ok','true','POS A registers dynamically');
select is(pg_temp.p353_register(2)->>'ok','true','POS B registers dynamically');
reset role;
set local role service_role;
select is(pg_temp.p353_submit(n)->>'ok','true','synthetic request '||n||' submitted') from generate_series(1,7) n;
select is(pg_temp.p353_submit(8,'b1')->>'ok','true','foreign tenant request submitted');
insert into _p353_results values('initial-deliveries',public.pos_claim_order_alert_deliveries());
select is(jsonb_array_length((select r->'deliveries' from _p353_results where label='initial-deliveries')),10,'unchanged dispatcher claims max ten pending hints');
reset role;

-- Old RPC remains deliberately staff-private, including a later explicit retry.
set local role authenticated;
select is(public.pos_reject_web_order(pg_temp.p353_id('pin-1'),pg_temp.p353_id('device-1'),
  'synthetic-platform353-token-1',pg_temp.p353_request(1),pg_temp.p353_client(2001),'Private historical reason')->>'ok',
  'true','legacy rejection succeeds without publishing its private reason');
select is(pg_temp.p356_reject(1,'Private historical reason')->>'replayed','true','explicit replay of old private decision stays replayed');
select is(pg_temp.p356_reject(2,'المنتج غير متوفر <script>not HTML</script>')->>'replayed','false','future explicit customer rejection commits once');
select is(pg_temp.p356_reject(2,'المنتج غير متوفر <script>not HTML</script>')->>'replayed','true','same explicit decision retry is stable');
select is(pg_temp.p356_reject(2,'Different reason')->>'error','decision_conflict','changed reason cannot alter immutable decision');
select is(pg_temp.p356_reject(2,'المنتج غير متوفر <script>not HTML</script>',2)->>'replayed','true','same terminal state on another device cannot append another public reason');
select is(pg_temp.p356_reject(3,'')->>'error','invalid_request','empty public reason rejected');
select is(pg_temp.p356_reject(3,repeat('😀',241))->>'error','invalid_request','overlong Unicode reason rejected');
select is(pg_temp.p356_reject(3,U&'\00A0Not canonical')->>'error','invalid_request','outer Unicode whitespace rejected before any decision');
select is(pg_temp.p356_reject(3,'Control'||chr(10))->>'error','invalid_request','control text rejected');
select is(pg_temp.p356_reject(8,'Cannot disclose another tenant')->>'error','not_found','foreign tenant request denied');
select is(public.pos_reject_web_order_customer(pg_temp.p353_id('pin-2'),pg_temp.p353_id('device-1'),
  'synthetic-platform353-token-1',pg_temp.p353_request(3),pg_temp.p353_client(2003),'Public')->>'error',
  'invalid_session','PIN from another device cannot designate customer text');
select is(pg_temp.p353_accept(4)->>'ok','true','acceptance still creates its canonical order once');
select is(pg_temp.p353_accept(4,2)->>'error','decision_conflict','second POS cannot accept an already accepted request');
select is(pg_temp.p356_reject(4,'Reject after acceptance')->>'error','decision_conflict','rejection cannot replace accepted canonical order');
reset role;
select is((select count(*) from app.web_order_customer_rejection_reasons),1::bigint,'only explicitly new public rejection was recorded');
select is((select count(*) from public.web_order_decisions where request_id=pg_temp.p353_request(3)),0::bigint,'invalid reasons/authority create no decision');
select is((select count(*) from public.web_order_decisions where request_id=pg_temp.p353_request(8)),0::bigint,'cross-tenant attempt creates no decision');
select throws_ok($$update app.web_order_customer_rejection_reasons set reason='changed'$$,'42501',null,'public reason update is append-only even for privileged SQL');
select throws_ok($$delete from app.web_order_customer_rejection_reasons$$,'42501',null,'public reason deletion is forbidden');
select throws_ok($$truncate app.web_order_customer_rejection_reasons$$,'42501',null,'public reason truncate is forbidden');

set local role service_role;
select ok(not(pg_temp.p356_status(1) ? 'customer_rejection_reason'),'historical/private reason never appears in capability status');
select is(pg_temp.p356_status(2)->>'customer_rejection_reason','المنتج غير متوفر <script>not HTML</script>','matching capability receives exact explicitly public plain text');
select ok(not(pg_temp.p356_status(2) ? 'rejection_reason'),'private field never leaks alongside explicit reason');
select is(pg_temp.p356_status(2,repeat('b',64))->>'error','not_found','wrong capability receives no request or public reason');
select is(pg_temp.p356_status(2,repeat('a',64),'platform-353-b1')->>'error','not_found','wrong tenant slug receives no reason');
select ok(not(pg_temp.p356_status(3) ? 'customer_rejection_reason'),'pending request has no rejection reason');
select ok(not(pg_temp.p356_status(4) ? 'customer_rejection_reason'),'accepted request has no rejection reason');
reset role;

-- A failed public-ledger insert rolls back the original rejection in the same
-- statement, rather than leaving a private terminal state after reported failure.
create function pg_temp.p356_block_insert() returns trigger language plpgsql as $$
begin raise exception 'synthetic public ledger failure' using errcode='23514'; end; $$;
create trigger p356_fail before insert on app.web_order_customer_rejection_reasons for each row execute function pg_temp.p356_block_insert();
set local role authenticated;
select throws_ok($$select pg_temp.p356_reject(5,'Must be atomic')$$,'23514','synthetic public ledger failure','public-ledger failure aborts entire decision');
reset role;
drop trigger p356_fail on app.web_order_customer_rejection_reasons;
select is((select status from web_order_requests where id=pg_temp.p353_request(5)),'pending','failed public reason insert leaves request pending');
select is((select count(*) from web_order_decisions where request_id=pg_temp.p353_request(5)),0::bigint,'failed public reason insert leaves no attributed decision');

-- No new request follows Accept/Reject. The existing delivery RPC materializes
-- terminal hints for A/B and full-set status retains other still-pending work.
set local role service_role;
insert into _p353_results values('terminal-deliveries',public.pos_claim_order_alert_deliveries());
reset role;
select ok(exists(select 1 from app.pos_order_alert_deliveries where request_id=pg_temp.p353_request(2) and kind='terminal'),
  'explicit rejection creates terminal delivery when woken without another submission');
select ok(exists(select 1 from app.pos_order_alert_deliveries where request_id=pg_temp.p353_request(4) and kind='terminal'),
  'acceptance creates terminal delivery when woken without another submission');
set local role authenticated;
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.p353_inbox(2)->'requests') r
  where r->>'request_id' in(pg_temp.p353_request(2)::text,pg_temp.p353_request(4)::text)),
  'POS B full pending set excludes both resolved requests');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.p353_inbox(2)->'requests') r
  where r->>'request_id'=pg_temp.p353_request(3)::text),'POS B retains different pending request while A resolves others');
reset role;
select is((select count(*) from kitchen_print_dispatches where order_id=(select canonical_order_id from web_order_requests where id=pg_temp.p353_request(4)))
  ,1::bigint,'accepted request still has exactly one initial dispatch');
select is((select count(*) from web_order_print_attempts where attempt_reserved_at is not null),0::bigint,'no SQL test claims/begins/sends printer transport');
select * from finish();
rollback;
