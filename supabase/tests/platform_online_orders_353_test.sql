-- Platform onboarding and real public RPCs. Synthetic, rollback-only; no HTTP.
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
set local role authenticated;
select is(pg_temp.p353_register(n)->>'ok','true','new paired authenticated device '||n||' joins dynamically') from generate_series(1,4) n;
reset role;
select is((select count(*) from app.pos_order_alert_registrations),4::bigint,'all eligible devices registered without UUID lists');
set local role service_role;
insert into _p353_results values('submit-a1',pg_temp.p353_submit(1)),('submit-a2',pg_temp.p353_submit(2,'a2')),('submit-b1',pg_temp.p353_submit(3,'b1'));
select is((select r->>'ok' from _p353_results where label='submit-a1'),'true','normal platform writer accepts published arbitrary storefront');
select is(pg_temp.p353_submit(1)->>'replayed','true','same canonical request replays');
insert into _p353_results values('fanout',public.pos_claim_order_alert_deliveries());
reset role;
select is((select count(*) from app.online_order_live_requests),3::bigint,'replay never enrolls twice');
select is(jsonb_array_length((select r->'deliveries' from _p353_results where label='fanout')),4,'one request fans out to both A1 devices and isolated A2/B1');
select is((select count(distinct registration_id) from app.pos_order_alert_deliveries),4::bigint,'each authorized installation has its own delivery');
set local role authenticated;
select is(jsonb_array_length(pg_temp.p353_inbox(1)->'requests'),1,'A1 first POS sees A1');
select is(jsonb_array_length(pg_temp.p353_inbox(2)->'requests'),1,'A1 second POS sees same pending set');
select is(pg_temp.p353_inbox(3)#>>'{requests,0,request_id}',pg_temp.p353_request(3)::text,'B1 never sees A1/A2');
reset role;
-- Pair a third A1 device AFTER submission and initial fanout; no static list,
-- environment change or backend operator enrollment accompanies this pairing.
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
  select pg_temp.p353_id('device-5'),org,restaurant,branch,'pos' from _p353_staff where n=1;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
  select pg_temp.p353_id('pairing-5'),org,restaurant,branch,pg_temp.p353_id('device-5'),'active' from _p353_staff where n=1;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
  select pg_temp.p353_id('session-5'),org,restaurant,branch,pg_temp.p353_id('device-5'),pg_temp.p353_id('pairing-5'),
    app.hash_provisioning_secret('synthetic-platform353-token-5'),now()+interval '30 days' from _p353_staff where n=1;
insert into app_users(id,email) values(pg_temp.p353_id('staff-5'),'platform353-late@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
  select pg_temp.p353_id('membership-5'),pg_temp.p353_id('staff-5'),org,restaurant,branch,'cashier' from _p353_staff where n=1;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
  select pg_temp.p353_id('employee-5'),org,restaurant,branch,pg_temp.p353_id('staff-5'),pg_temp.p353_id('membership-5'),'Late A3' from _p353_staff where n=1;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
  select pg_temp.p353_id('pin-5'),org,restaurant,branch,pg_temp.p353_id('session-5'),pg_temp.p353_id('employee-5'),
    pg_temp.p353_id('membership-5'),now()+interval '6 hours' from _p353_staff where n=1;
set local role authenticated;
select is(pg_temp.p353_register(5)->>'ok','true','new late-paired A3 joins automatically without UUID/schema/config changes');
select is(pg_temp.p353_inbox(5)#>>'{requests,0,request_id}',pg_temp.p353_request(1)::text,'late-paired A3 synchronizes the existing pending request');
select is(pg_temp.p353_accept(1,3)->>'error','not_found','cross-organization accept denied');
select is(pg_temp.p353_accept(1,4)->>'error','not_found','same-organization other restaurant accept denied');
insert into _p353_results values('accept-a1',pg_temp.p353_accept(1));
select is((select r->>'ok' from _p353_results where label='accept-a1'),'true','one device accepts');
select is(pg_temp.p353_accept(1,2)->>'error','decision_conflict','second device cannot win a different acceptance intent');
select is(pg_temp.p353_accept(1)->>'replayed','true','same winning device and exact decision may reconcile without new work');
select is(pg_temp.p353_inbox(2)->'requests','[]'::jsonb,'second POS pending set clears after accepted decision');
select is(pg_temp.p353_accept(2,4)->>'ok','true','KDS branch acceptance uses existing kitchen workflow');
reset role;
select is((select count(*) from web_order_decisions where request_id=pg_temp.p353_request(1)),1::bigint,'one accepted decision');
select is((select count(*) from kitchen_print_dispatches where order_id=(select canonical_order_id from web_order_requests where id=pg_temp.p353_request(1))
  and dispatch_type='initial_order'),1::bigint,'one initial dispatch');
select is((select count(*) from web_order_print_attempts where request_id=pg_temp.p353_request(2)),0::bigint,'KDS creates no printer-only target');
select is(pg_temp.p353_print(1,2,'claim')->>'error','containment_blocked','nonaccepting device cannot claim exact callback');
select is(pg_temp.p353_print(1,1,'claim')->>'state','claimed','acceptor claims fresh exact target');
select is(pg_temp.p353_print(1,1,'begin',pg_temp.p353_client(9901))->>'send_authorized','true','one irreversible begin authorizes one send');
select is(pg_temp.p353_print(1,1,'begin',pg_temp.p353_client(9901))->>'send_authorized','false','lost begin response cannot authorize second transmission');
select is(pg_temp.p353_print(1,2,'begin',pg_temp.p353_client(9902))->>'send_authorized','false','other POS cannot obtain send after first begin');
create temp table _p353_registration_before as select id,generation,registered_at,refreshed_at,authority_expires_at,setting_revision from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('device-1');
grant select on _p353_registration_before to service_role;
set local role service_role;
select is(public.pos_refresh_order_alert_token(pg_temp.p353_id('installation-1'),repeat('b',64),'synthetic-refreshed-fcm-token-1',
  (select generation from _p353_registration_before))->>'error','unauthorized','wrong token capability denied');
select is(public.pos_refresh_order_alert_token(pg_temp.p353_id('installation-1'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  'synthetic-platform353-fcm-token-2',(select generation from _p353_registration_before))->>'error','unauthorized','cannot take another device token');
select is(public.pos_refresh_order_alert_token(pg_temp.p353_id('installation-1'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  'synthetic-refreshed-fcm-token-1',(select generation from _p353_registration_before))->>'ok','true','authorized native token refresh succeeds');
reset role;
select ok((select row(r.id,r.registered_at,r.refreshed_at,r.authority_expires_at,r.setting_revision)=
  row(b.id,b.registered_at,b.refreshed_at,b.authority_expires_at,b.setting_revision)
  from app.pos_order_alert_registrations r join _p353_registration_before b using(id)),'token rotation never renews authority or arrival cutoff');
select ok((select r.generation<>b.generation from app.pos_order_alert_registrations r join _p353_registration_before b using(id)),
  'changed FCM token rotates generation to fence old leased-token outcomes');
set local role service_role;
select is(public.pos_finish_order_alert_delivery(
  (select (x->>'delivery_id')::uuid from jsonb_array_elements((select r->'deliveries' from _p353_results where label='fanout')) x
    where x->>'registration_id'=(select id::text from _p353_registration_before)),
  (select (x->>'lease_id')::uuid from jsonb_array_elements((select r->'deliveries' from _p353_results where label='fanout')) x
    where x->>'registration_id'=(select id::text from _p353_registration_before)),'invalid_token')->>'ok','true','old leased token outcome may finish');
reset role;
select ok((select enabled from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('device-1')),
  'old invalid-token outcome cannot disable the newly refreshed registration');
create temp table _p353_delayed_native as select generation from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('device-1');
grant select on _p353_delayed_native to service_role;
set local role authenticated;
select is(pg_temp.p353_register(1)->>'ok','true','foreground registration commits a newer SDK token');
reset role;
create temp table _p353_foreground_authority as select generation,fcm_token,authority_expires_at,registered_at,refreshed_at
  from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('device-1');
set local role service_role;
select is(public.pos_refresh_order_alert_token(pg_temp.p353_id('installation-1'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  'synthetic-delayed-older-native-token',(select generation from _p353_delayed_native))->>'error','unauthorized',
  'delayed native refresh cannot overwrite a later foreground registration');
reset role;
select ok((select row(r.generation,r.fcm_token,r.authority_expires_at,r.registered_at,r.refreshed_at)=
  row(b.generation,b.fcm_token,b.authority_expires_at,b.registered_at,b.refreshed_at)
  from app.pos_order_alert_registrations r cross join _p353_foreground_authority b where r.device_id=pg_temp.p353_id('device-1')),
  'generation CAS preserves the new foreground token and all authority metadata');
create temp table _p353_same_token_generation as select generation from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('device-1');
grant select on _p353_same_token_generation to service_role;
set local role authenticated;
select is(pg_temp.p353_register(1)->>'ok','true','same-token foreground renewal is genuine authenticated activity');
reset role;
select ok((select r.generation<>old.generation from app.pos_order_alert_registrations r cross join _p353_same_token_generation old
  where r.device_id=pg_temp.p353_id('device-1')),'same-token foreground renewal also fences the prior native generation');
set local role service_role;
select is(public.pos_refresh_order_alert_token(pg_temp.p353_id('installation-1'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),
  'synthetic-delayed-older-native-token',(select generation from _p353_same_token_generation))->>'error','unauthorized',
  'delayed native candidate cannot overwrite even after a same-token foreground renewal');
reset role;

-- Real scoped management authority, independent of the paired transport
-- principal. Manager may stop future intake; cashier and another tenant cannot.
insert into auth.users(id,email) values(pg_temp.p353_id('manager-auth'),'platform353-manager@example.test'),
  (pg_temp.p353_id('cashier-auth'),'platform353-cashier@example.test');
update app_users set auth_user_id=pg_temp.p353_id('manager-auth') where id=pg_temp.p353_id('staff-1');
update app_users set auth_user_id=pg_temp.p353_id('cashier-auth') where id=pg_temp.p353_id('staff-2');
update memberships set role='manager' where id=pg_temp.p353_id('membership-1');
select set_config('request.jwt.claim.sub',pg_temp.p353_id('cashier-auth')::text,true);
set local role authenticated;
select is(public.set_online_order_settings(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),pg_temp.p353_id('branch-a1'),
  false,false,false)->>'error','permission_denied','cashier cannot alter branch admission or printing settings');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.p353_id('manager-auth')::text,true);
set local role authenticated;
select is(public.get_online_order_settings(pg_temp.p353_id('org-b'),pg_temp.p353_id('restaurant-b1'),pg_temp.p353_id('branch-b1'))->>'error',
  'not_found','manager cannot read another tenant configuration');
select is(public.set_online_order_settings(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a2'),pg_temp.p353_id('branch-a2'),
  false,false,false)->>'error','not_found','A1 manager cannot mutate sibling restaurant configuration');
select is(public.set_online_order_settings(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),pg_temp.p353_id('branch-a1'),
  false,true,true)->>'ordering_enabled','false','scoped manager can pause intake');
reset role;
select ok(not(public.storefront_menu('platform-353-a1')#>>'{service,ordering_enabled}')::boolean,'manager pause reaches browser metadata');
set local role service_role;
select is(pg_temp.p353_submit(10)->>'error','ordering_unavailable','paused new intake fails closed');
reset role;
set local role authenticated;
select is(public.set_online_order_settings(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),pg_temp.p353_id('branch-a1'),
  true,true,true)->>'ordering_enabled','true','scoped manager resumes normal intake');
reset role;
set local role service_role;
select is(pg_temp.p353_submit(10)->>'ok','true','next genuinely fresh request enters after pause');
reset role;
-- Genuine no-printer readiness is not a reason to lose an accepted order.
update kitchen_printer_readiness_reports set secure_spool_available=false where device_id=pg_temp.p353_id('device-1');
set local role authenticated;
select is(pg_temp.p353_accept(10)->>'ok','true','unready printer does not roll back accepted canonical order');
reset role;
select is(pg_temp.p353_print(10,1,'claim')->>'error','readiness_required','no readiness means zero send authorization');
select ok((select canonical_order_id is not null from web_order_requests where id=pg_temp.p353_request(10)),'accepted order survives printer blocker');
select ok((select attempt_id is null from web_order_print_attempts where request_id=pg_temp.p353_request(10)),'unready printer has no irreversible send reservation');
update kitchen_printer_readiness_reports set secure_spool_available=true where device_id=pg_temp.p353_id('device-1');
select is(pg_temp.p353_print(10,1,'claim')->>'state','claimed','fresh readiness permits exact held callback claim');
set local role authenticated;
select is(public.set_online_order_settings(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),pg_temp.p353_id('branch-a1'),
  true,false,true)->>'printing_enabled','false','manager emergency print disable advances print generation');
reset role;
select is(pg_temp.p353_print(10,1,'begin',pg_temp.p353_client(9910))->>'error','containment_blocked','disable after claim prevents irreversible begin');
set local role authenticated;
select public.set_online_order_settings(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),pg_temp.p353_id('branch-a1'),true,true,true);
reset role;
select is(pg_temp.p353_print(10,1,'claim')->>'error','containment_blocked','re-enable never revives earlier generation claim');
set local role service_role;
select pg_temp.p353_submit(11);
reset role;
set local role authenticated;
select pg_temp.p353_accept(11);
reset role;
select is(pg_temp.p353_print(11,1,'claim')->>'state','claimed','new generation supports only new request');
insert into kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
  values(pg_temp.p353_id('org-a'),pg_temp.p353_id('restaurant-a1'),pg_temp.p353_id('branch-a1'),'blocked','Synthetic emergency fence','platform353-test');
select is(pg_temp.p353_print(11,1,'begin',pg_temp.p353_client(9911))->>'error','containment_blocked','new BLOCKED revision kills a claimed target without altering its evidence');
select set_config('request.jwt.claim.sub',pg_temp.p353_id('transport-user')::text,true);
update device_pairings set status='revoked',revoked_at=clock_timestamp() where id=pg_temp.p353_id('pairing-2');
set local role authenticated;
select is(pg_temp.p353_register(2)->>'error','invalid_session','revoked pairing cannot rejoin');
reset role;
update memberships set status='revoked' where id=pg_temp.p353_id('membership-3');
set local role service_role;
select is(public.pos_order_alert_status(pg_temp.p353_id('installation-3'),encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'))->>'error',
  'unauthorized','removed employee membership immediately revokes notification authority');
reset role;
update web_order_channel_settings set submission_enabled=false where branch_id=pg_temp.p353_id('branch-a1');
update restaurant_storefront_profiles set display_name='Unrelated display edit',is_published=true where restaurant_id=pg_temp.p353_id('restaurant-a1');
select ok(not(select submission_enabled from web_order_channel_settings where branch_id=pg_temp.p353_id('branch-a1')),'publication update does not override explicit channel OFF');
select ok(not(public.storefront_menu('platform-353-a1')#>>'{service,ordering_enabled}')::boolean,'website follows explicit branch pause');

-- Twelve additional busy tenants and five idle tenants exercise the bounded
-- global worker, not only an isolated two-device registration case.
create function pg_temp.p353_more_tenant(n integer,busy boolean,publish boolean default true) returns void language plpgsql as $$
declare v_rest uuid:=pg_temp.p353_id('fair-rest-'||n); v_branch uuid:=pg_temp.p353_id('fair-branch-'||n);
  v_device uuid:=pg_temp.p353_id('fair-device-'||n); v_pair uuid:=pg_temp.p353_id('fair-pair-'||n);
  v_session uuid:=pg_temp.p353_id('fair-session-'||n); v_staff uuid:=pg_temp.p353_id('fair-staff-'||n);
  v_member uuid:=pg_temp.p353_id('fair-member-'||n); v_employee uuid:=pg_temp.p353_id('fair-employee-'||n);
  v_pin uuid:=pg_temp.p353_id('fair-pin-'||n); v_request uuid; v_i integer;
begin
  insert into public.restaurants(id,organization_id,name,timezone) values(v_rest,pg_temp.p353_id('org-a'),'Synthetic fairness '||n,'UTC');
  insert into public.branches(id,organization_id,restaurant_id,name,timezone) values(v_branch,pg_temp.p353_id('org-a'),v_rest,'Synthetic fairness '||n,'UTC');
  if publish then
    insert into public.restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
      select v_rest,pg_temp.p353_id('org-a'),v_branch,'platform-353-fair-'||n,'Synthetic fairness '||n,true,opening_hours,true
      from public.restaurant_storefront_profiles where restaurant_id=pg_temp.p353_id('restaurant-a1');
  end if;
  insert into public.devices(id,organization_id,restaurant_id,branch_id,device_type) values(v_device,pg_temp.p353_id('org-a'),v_rest,v_branch,'pos');
  insert into public.device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status) values(v_pair,pg_temp.p353_id('org-a'),v_rest,v_branch,v_device,'active');
  insert into public.device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
    values(v_session,pg_temp.p353_id('org-a'),v_rest,v_branch,v_device,v_pair,app.hash_provisioning_secret('synthetic-fair-token-'||n),now()+interval '30 days');
  insert into public.app_users(id,email) values(v_staff,'platform353-fair-'||n||'@example.test');
  insert into public.memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values(v_member,v_staff,pg_temp.p353_id('org-a'),v_rest,v_branch,'cashier');
  insert into public.employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
    values(v_employee,pg_temp.p353_id('org-a'),v_rest,v_branch,v_staff,v_member,'Synthetic fairness '||n);
  insert into public.pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
    values(v_pin,pg_temp.p353_id('org-a'),v_rest,v_branch,v_session,v_employee,v_member,now()+interval '6 hours');
  perform public.pos_register_order_alert(pg_temp.p353_id('fair-installation-'||n),'synthetic-fair-fcm-token-'||n,repeat('a',64),v_device,v_pin,'synthetic-fair-token-'||n);
  if busy then
    for v_i in 1..case when n=1 then 20 else 1 end loop
      insert into public.web_order_requests(organization_id,restaurant_id,branch_id,client_request_id,status_token_hash,payload_hash,
        customer_name,customer_phone,priced_items,currency_code,subtotal_minor,tax_total_minor,grand_total_minor,created_at,expires_at,status_until)
      values(pg_temp.p353_id('org-a'),v_rest,v_branch,pg_temp.p353_client(20000+n*100+v_i),repeat('a',64),repeat('b',64),
        'Synthetic fairness','+972520000001','[{}]','ILS',1000,0,1000,clock_timestamp(),clock_timestamp()+interval '14 minutes',clock_timestamp()+interval '23 hours') returning id into v_request;
      insert into public.web_order_request_events(organization_id,restaurant_id,branch_id,request_id,event_type)
        values(pg_temp.p353_id('org-a'),v_rest,v_branch,v_request,'received');
      insert into app.online_order_live_requests(request_id,organization_id,restaurant_id,branch_id,print_generation)
        select v_request,organization_id,restaurant_id,branch_id,print_generation from app.online_order_settings where branch_id=v_branch;
    end loop;
  end if;
end; $$;
select pg_temp.p353_more_tenant(n,n<=12) from generate_series(1,17) n;
set local role service_role;
insert into _p353_results values('fair-1',public.pos_claim_order_alert_deliveries()),('fair-2',public.pos_claim_order_alert_deliveries());
reset role;
select ok(jsonb_array_length(r->'deliveries')<=10,label||' globally capped at ten claims') from _p353_results where label like 'fair-%';
select is((select count(distinct r.branch_id) from app.pos_order_alert_deliveries d join app.pos_order_alert_registrations r on r.id=d.registration_id
  where r.device_id in(select pg_temp.p353_id('fair-device-'||n) from generate_series(1,12)n) and d.state='leased'),12::bigint,
  'all twelve busy tenants served within two worker calls despite hot tenant backlog');
select ok(not exists(select 1 from app.pos_order_alert_branch_cursors where branch_id in
  (select pg_temp.p353_id('fair-branch-'||n) from generate_series(13,17)n) and scanned_at<>'epoch'),'idle tenants never consume a busy election slot');
select pg_temp.p353_more_tenant(18,false,false);
select ok(exists(select 1 from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('fair-device-18') and enabled),
  'pairing and authenticated notification registration work before storefront publication');
select ok(not exists(select 1 from web_order_channel_settings where branch_id=pg_temp.p353_id('fair-branch-18')),
  'branch-only onboarding does not create a public submission channel');
create temp table _p353_prepublication as select generation from app.pos_order_alert_registrations where device_id=pg_temp.p353_id('fair-device-18');
insert into menu_categories(id,organization_id,restaurant_id,name) values(pg_temp.p353_id('category-fair-18'),pg_temp.p353_id('org-a'),pg_temp.p353_id('fair-rest-18'),'Synthetic publication');
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
  values(pg_temp.p353_id('item-fair-18'),pg_temp.p353_id('org-a'),pg_temp.p353_id('fair-rest-18'),pg_temp.p353_id('category-fair-18'),'Synthetic publication item',1000,'ILS');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
  select pg_temp.p353_id('fair-rest-18'),pg_temp.p353_id('org-a'),pg_temp.p353_id('fair-branch-18'),'platform-353-fair-18','Synthetic publication',true,opening_hours,true
  from restaurant_storefront_profiles where restaurant_id=pg_temp.p353_id('restaurant-a1');
set local role service_role;
select is(pg_temp.p353_submit(1800,'fair-18')->>'ok','true','normal publication alone enables canonical-priced online submission');
reset role;
select ok((select r.generation=p.generation from app.pos_order_alert_registrations r cross join _p353_prepublication p where r.device_id=pg_temp.p353_id('fair-device-18')),
  'publication requires no device registration or authority change');

select ok(not has_function_privilege('authenticated','public.pos_refresh_order_alert_token(uuid,text,text,uuid)','EXECUTE'),'native refresh is gateway-only');
select ok(c.relrowsecurity and c.relforcerowsecurity,c.relname||' forced RLS') from pg_class c where c.oid in
  ('app.online_order_settings'::regclass,'app.online_order_live_requests'::regclass,'app.online_order_print_leases'::regclass,
   'app.pos_order_alert_branch_cursors'::regclass);
select ok(not has_table_privilege(role_name,tbl,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),role_name||' denied direct '||tbl)
  from unnest(array['anon','authenticated','service_role']) role_name cross join unnest(array[
    'app.online_order_settings','app.online_order_live_requests','app.online_order_print_leases','app.pos_order_alert_branch_cursors']) tbl;
select * from finish();
rollback;
