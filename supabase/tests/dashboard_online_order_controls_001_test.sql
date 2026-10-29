-- BIZBOT-DASHBOARD-ONLINE-ORDER-CONTROLS-001. Synthetic, rollback-only.
-- No HTTP, dispatch, registration, status, order submission or printer RPC.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.ocid(label text) returns uuid language sql immutable as $$select md5('online-controls-001-'||label)::uuid;$$;
create function pg_temp.oc_as(label text) returns text language sql volatile as $$select set_config('request.jwt.claim.sub',pg_temp.ocid('auth-'||label)::text,true);$$;
create function pg_temp.oc_read(branch text default 'a') returns jsonb language sql volatile as $$
  select public.get_online_order_settings_v2(pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-'||branch));$$;
create function pg_temp.oc_save(request text,ordering boolean,printing boolean,alerts boolean,revision bigint default null,branch text default 'a')
returns jsonb language sql volatile as $$
  select public.set_online_order_settings_v2(pg_temp.ocid('request-'||request),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-'||branch),
    coalesce(revision,(pg_temp.oc_read(branch)->>'revision')::bigint),ordering,printing,alerts);$$;
create function pg_temp.oc_check(request text,ordering boolean,printing boolean,alerts boolean,revision bigint,branch text default 'a')
returns jsonb language sql volatile as $$
  select public.reconcile_online_order_settings_v2(pg_temp.ocid('request-'||request),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-'||branch),revision,ordering,printing,alerts);$$;
insert into organizations(id,name,slug,default_currency) values
  (pg_temp.ocid('org-a'),'Online controls A','online-controls-a','ILS'),(pg_temp.ocid('org-b'),'Online controls B','online-controls-b','ILS');
insert into restaurants(id,organization_id,name,timezone) select pg_temp.ocid('restaurant-'||r),pg_temp.ocid('org-'||r),'Controls '||r,'UTC' from unnest(array['a','b']) r;
insert into branches(id,organization_id,restaurant_id,name,timezone) select pg_temp.ocid('branch-'||b),pg_temp.ocid('org-'||left(b,1)),pg_temp.ocid('restaurant-'||left(b,1)),'Controls '||b,'UTC' from unnest(array['a','a2','b']) b;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
  select organization_id,restaurant_id,id,true from branches where id in(pg_temp.ocid('branch-a'),pg_temp.ocid('branch-a2'),pg_temp.ocid('branch-b'));
insert into auth.users(id,instance_id,email) select pg_temp.ocid('auth-'||u),'00000000-0000-0000-0000-000000000000','online-controls-'||u||'@example.test' from unnest(array['manager','manager2','branch','cashier','owner','foreign']) u;
insert into app_users(id,email,auth_user_id) select pg_temp.ocid('user-'||u),'online-controls-'||u||'@example.test',pg_temp.ocid('auth-'||u) from unnest(array['manager','manager2','branch','cashier','owner','foreign']) u;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values
  (pg_temp.ocid('member-manager'),pg_temp.ocid('user-manager'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),null,'manager'),
  (pg_temp.ocid('member-manager2'),pg_temp.ocid('user-manager2'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),null,'manager'),
  (pg_temp.ocid('member-branch'),pg_temp.ocid('user-branch'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),'manager'),
  (pg_temp.ocid('member-cashier'),pg_temp.ocid('user-cashier'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),null,'cashier'),
  (pg_temp.ocid('member-owner'),pg_temp.ocid('user-owner'),pg_temp.ocid('org-a'),null,null,'org_owner'),
  (pg_temp.ocid('member-foreign'),pg_temp.ocid('user-foreign'),pg_temp.ocid('org-b'),null,null,'org_owner');
-- An inert pending request with its original generation: settings cannot
-- mutate or newly enroll it, and printing OFF/ON must not revive its eligibility.
insert into web_order_requests(id,organization_id,restaurant_id,branch_id,client_request_id,status_token_hash,payload_hash,
  customer_name,customer_phone,priced_items,currency_code,subtotal_minor,tax_total_minor,grand_total_minor,expires_at,status_until)
  values(pg_temp.ocid('pending'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),pg_temp.ocid('pending-client'),repeat('a',64),repeat('b',64),
    'Synthetic only','+972520000001','[{}]'::jsonb,'ILS',1000,0,1000,now()+interval '10 minutes',now()+interval '1 hour');
insert into app.online_order_live_requests(request_id,organization_id,restaurant_id,branch_id,print_generation)
  select pg_temp.ocid('pending'),organization_id,restaurant_id,branch_id,print_generation from app.online_order_settings where branch_id=pg_temp.ocid('branch-a');
-- Nonempty, authorized synthetic notification state. These are direct local
-- fixtures only, with no registration/dispatch/status RPC and no network.
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
  values(pg_temp.ocid('device'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),'pos');
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
  values(pg_temp.ocid('pairing'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),pg_temp.ocid('device'),'active');
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
  values(pg_temp.ocid('session'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),pg_temp.ocid('device'),pg_temp.ocid('pairing'),
    app.hash_provisioning_secret('synthetic-online-controls-session'),now()+interval '1 day');
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
  values(pg_temp.ocid('employee'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),pg_temp.ocid('user-cashier'),pg_temp.ocid('member-cashier'),'Synthetic employee');
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
  values(pg_temp.ocid('pin'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),pg_temp.ocid('session'),pg_temp.ocid('employee'),pg_temp.ocid('member-cashier'),now()+interval '4 hours');
insert into app.pos_order_alert_settings(enabled,reason,operator_reference) values(true,'Synthetic online-controls global state','ONLINE-CONTROLS-001-LOCAL');
insert into app.pos_order_alert_installation_owners(installation_id,organization_id,restaurant_id,branch_id,device_id)
  values(pg_temp.ocid('installation'),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),pg_temp.ocid('device'));
insert into app.pos_order_alert_registrations(id,installation_id,setting_revision,organization_id,restaurant_id,branch_id,device_id,device_session_id,pin_session_id,
  employee_profile_id,resolved_membership_id,fcm_token,token_hash,status_secret_hash,authority_expires_at)
  values(pg_temp.ocid('registration'),pg_temp.ocid('installation'),(select max(revision) from app.pos_order_alert_settings),pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),
    pg_temp.ocid('device'),pg_temp.ocid('session'),pg_temp.ocid('pin'),pg_temp.ocid('employee'),pg_temp.ocid('member-cashier'),
    'synthetic-online-controls-fcm-only',repeat('d',64),repeat('e',64),clock_timestamp()+interval '1 hour');
insert into app.pos_order_alert_deliveries(id,registration_id,generation,request_id,kind,state)
  select pg_temp.ocid('delivery'),id,generation,pg_temp.ocid('pending'),'pending','queued' from app.pos_order_alert_registrations where id=pg_temp.ocid('registration');
-- Nonempty historical preservation fixtures in the other tenant. All foreign
-- keys and triggers remain enabled. No submission/decision/print RPC is used;
-- every synthetic dispatch is held before any settings API is exercised.
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
  values(pg_temp.ocid('history-device'),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),'pos');
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
  values(pg_temp.ocid('history-pairing'),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),pg_temp.ocid('history-device'),'active');
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
  values(pg_temp.ocid('history-session'),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),pg_temp.ocid('history-device'),pg_temp.ocid('history-pairing'),
    app.hash_provisioning_secret('synthetic-history-session'),now()+interval '1 day');
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
  values(pg_temp.ocid('history-employee'),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),pg_temp.ocid('user-foreign'),pg_temp.ocid('member-foreign'),'Synthetic history employee');
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
  values(pg_temp.ocid('history-pin'),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),pg_temp.ocid('history-session'),pg_temp.ocid('history-employee'),pg_temp.ocid('member-foreign'),now()+interval '4 hours');
insert into orders(id,organization_id,restaurant_id,branch_id,device_id,pin_session_id,opened_by_employee_profile_id,resolved_membership_id,
  order_type,status,currency_code,subtotal_minor,grand_total_minor,local_operation_id)
  select pg_temp.ocid('history-order-'||n),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),pg_temp.ocid('history-device'),pg_temp.ocid('history-pin'),
    pg_temp.ocid('history-employee'),pg_temp.ocid('member-foreign'),'takeaway','cancelled','ILS',0,0,'synthetic-history-order-'||n from generate_series(1,625) n;
insert into kitchen_print_dispatches(id,organization_id,restaurant_id,branch_id,order_id,dispatch_type,money_free_payload,idempotency_key,last_client_status,last_error_code)
  select pg_temp.ocid('inert-hold-'||n),pg_temp.ocid('org-b'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'),pg_temp.ocid('history-order-'||n),'initial_order','{}'::jsonb,
    'synthetic-history-dispatch-'||n,'possibly_printed','web_print_reconciliation_required' from generate_series(1,625) n;
insert into kitchen_print_dispatch_holds(dispatch_id,organization_id,restaurant_id,branch_id,snapshot_at,dispatch_fingerprint,manifest_sha256,reason,operator_reference)
  select d.id,d.organization_id,d.restaurant_id,d.branch_id,clock_timestamp(),md5(to_jsonb(d)::text),repeat('c',64),
    'Inert local preservation fixture','ONLINE-CONTROLS-001-LOCAL' from kitchen_print_dispatches d where d.organization_id=pg_temp.ocid('org-b');
create temp table oc_protected_before as select
  (select coalesce(jsonb_agg(to_jsonb(t) order by t.dispatch_id),'[]'::jsonb) from kitchen_print_dispatch_holds t) holds,
  (select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from app.pos_order_alert_registrations t) registrations,
  (select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from app.pos_order_alert_deliveries t) deliveries,
  (select coalesce(jsonb_agg(to_jsonb(t) order by t.revision),'[]'::jsonb) from app.pos_order_alert_settings t) global_alerts,
  (select coalesce(jsonb_agg(to_jsonb(t) order by t.revision),'[]'::jsonb) from kitchen_print_containment_policies t) containment,
  (select to_jsonb(t) from web_order_requests t where id=pg_temp.ocid('pending')) pending,
  (select to_jsonb(t) from app.online_order_live_requests t where request_id=pg_temp.ocid('pending')) enrollment;
create temp table oc_results(label text primary key,r jsonb);
grant all on oc_results to authenticated;
select ok((select app.pos_order_alert_authority(r) is not null from app.pos_order_alert_registrations r where id=pg_temp.ocid('registration')),'synthetic initial registration has valid notification authority before branch OFF');

select ok(relrowsecurity and relforcerowsecurity,'existing protected table remains forced RLS: '||relname)
  from pg_class where oid in('app.online_order_settings'::regclass,'app.online_order_settings_requests_v2'::regclass);
select ok(not has_table_privilege(r,'app.online_order_settings','INSERT,UPDATE,DELETE'),'no direct setting mutation grant: '||r) from unnest(array['anon','authenticated','service_role']) r;
select ok(not has_table_privilege(r,'app.online_order_settings_requests_v2','SELECT,INSERT,UPDATE,DELETE'),'no direct mutation receipt grant: '||r) from unnest(array['anon','authenticated','service_role']) r;
select ok(not has_function_privilege(r,f,'EXECUTE'),'RPC denied for '||r||': '||f) from unnest(array['anon','service_role']) r cross join unnest(array[
  'public.get_online_order_settings_v2(uuid,uuid,uuid)',
  'public.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)',
  'public.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)']) f;
select ok(has_function_privilege('authenticated',f,'EXECUTE'),'authenticated RPC grant: '||f) from unnest(array[
  'public.get_online_order_settings_v2(uuid,uuid,uuid)',
  'public.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)',
  'public.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)']) f;
select ok(not prosecdef,'public wrapper stays invoker: '||proname) from pg_proc where oid in(
  'public.get_online_order_settings_v2(uuid,uuid,uuid)'::regprocedure,
  'public.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)'::regprocedure,
  'public.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)'::regprocedure);
select ok(not has_function_privilege('authenticated',f,'EXECUTE'),'private helper not callable: '||f) from unnest(array[
  'app.online_order_settings_state_v2(uuid,uuid,uuid)','app.online_order_settings_authorize_v2(uuid,uuid,uuid,boolean)',
  'app.online_order_settings_intent_v2(uuid,uuid,uuid,bigint,boolean,boolean,boolean)','app.online_order_settings_claim_v2(uuid,uuid,uuid,uuid,uuid,text,jsonb)']) f;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
set local role authenticated;
select set_config('app.current_app_user_id','',true);
select throws_ok($$select pg_temp.oc_read()$$,'42501',null,'unlinked/absent identity cannot read');
select set_config('app.current_app_user_id',pg_temp.ocid('user-manager')::text,true);
select throws_ok($$select pg_temp.oc_read()$$,'42501',null,'a GUC-only identity without a JWT cannot authorize');
select pg_temp.oc_as('cashier');
select is(pg_temp.oc_save('cashier',false,true,true)->>'error','permission_denied','cashier cannot modify branch settings');
select is(pg_temp.oc_read()->>'error','permission_denied','cashier cannot read management settings');
select pg_temp.oc_as('foreign');
select is(pg_temp.oc_read()->>'error','not_found','foreign owner cannot read branch');
select is(pg_temp.oc_save('foreign',false,true,true,0)->>'error','not_found','foreign owner cannot mutate branch');
select is(pg_temp.oc_check('foreign',false,true,true,0)->>'error','not_found','foreign owner cannot inspect receipt');
select pg_temp.oc_as('branch');
select is(pg_temp.oc_read('a2')->>'error','not_found','branch manager cannot read sibling branch');
select is(pg_temp.oc_save('sibling',false,true,true,0,'a2')->>'error','not_found','branch manager cannot mutate sibling branch');
select is(public.get_online_order_settings_v2(pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-b'),pg_temp.ocid('branch-b'))->>'error','not_found','wrong ancestry refused before audit');
select pg_temp.oc_as('manager');
insert into oc_results values('initial',pg_temp.oc_read());
select is(jsonb_typeof(pg_temp.oc_read()->'revision'),'string','revision is lossless decimal string');
select is(jsonb_typeof(pg_temp.oc_read()->'print_generation'),'string','print generation is lossless decimal string');
select is(jsonb_typeof(pg_temp.oc_read()->'containment_revision'),'string','containment revision is lossless decimal string');
select is(pg_temp.oc_save('invalid',null,true,true)->>'error','invalid_request','null setting not coerced');
insert into oc_results values('intake',pg_temp.oc_save('intake',false,true,true));
select is((select r->>'ordering_enabled' from oc_results where label='intake'),'false','intake independent OFF');
select is((select r->>'alerts_enabled' from oc_results where label='intake'),'true','intake leaves alerts unchanged');
select is((select r->>'print_generation' from oc_results where label='intake'),(select r->>'print_generation' from oc_results where label='initial'),'intake does not rotate print generation');
select is(pg_temp.oc_save('intake',false,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))->>'idempotent_replay','true','same intent replays before current CAS');
select is(pg_temp.oc_save('intake',true,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))->>'error','request_conflict','same UUID with different flag is refused');
select is(pg_temp.oc_save('intake',false,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'),'a2')->>'error','request_conflict','same UUID cannot switch branch');
insert into oc_results values('alerts',pg_temp.oc_save('alerts',false,true,false));
select is((select r->>'alerts_enabled' from oc_results where label='alerts'),'false','branch alerts independently OFF');
select is((select r->>'ordering_enabled' from oc_results where label='alerts'),'false','alert change retains intake setting');
select is((select r->>'print_generation' from oc_results where label='alerts'),(select r->>'print_generation' from oc_results where label='initial'),'alert flag does not rotate print generation');
select is(pg_temp.oc_save('stale',true,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))->>'error','revision_conflict','stale manager cannot overwrite newer values');
select is(pg_temp.oc_save('stale',false,true,false)->>'error','request_conflict','a refused confirmed UUID cannot be rebound');
select is(pg_temp.oc_check('stale',true,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))->>'mutation_state','refused','CAS refusal is reconciled separately from committed change');
select is(pg_temp.oc_check('intake',false,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))#>>'{result,alerts_enabled}','true','original receipt retains its historical values');
select is(pg_temp.oc_check('intake',false,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))#>>'{current,alerts_enabled}','false','receipt reconciliation returns distinct fresh current state');
select is(pg_temp.oc_check('unseen',false,true,false,(pg_temp.oc_read()->>'revision')::bigint)->>'mutation_state','not_recorded','read-only uncertain result check does not invent a write');
insert into oc_results values('before-noop',pg_temp.oc_read()),('noop',pg_temp.oc_save('noop',false,true,false));
select is((select r->>'revision' from oc_results where label='noop'),(select r->>'revision' from oc_results where label='before-noop'),'true no-op does not rotate revision');
select is((select r->>'no_change' from oc_results where label='noop'),'true','no-op receipt explicit');
insert into oc_results values('print-off',pg_temp.oc_save('print-off',false,false,false));
select isnt((select r->>'print_generation' from oc_results where label='print-off'),(select r->>'print_generation' from oc_results where label='initial'),'printing eligibility OFF rotates generation');
insert into oc_results values('print-on',pg_temp.oc_save('print-on',false,true,false));
select isnt((select r->>'print_generation' from oc_results where label='print-on'),(select r->>'print_generation' from oc_results where label='print-off'),'printing ON creates another generation');
select is(pg_temp.oc_save('intake',false,true,true,(select (r->>'revision')::bigint from oc_results where label='initial'))->>'idempotent_replay','true','old successful intent remains replayable after later saves');
select is(pg_temp.oc_read()->>'alerts_enabled','false','replay never restores earlier manager settings');
reset role;
select is((select submission_enabled from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a')),false,'channel follows confirmed intake setting');
select is((select count(*) from audit_events where action='settings.online_orders.updated' and branch_id=pg_temp.ocid('branch-a')),4::bigint,'each actual change audited once, replay/refusal/no-op are not changes');
select ok((select old_values?'revision' and new_values?'client_request_id' and new_values?'print_generation' from audit_events where action='settings.online_orders.updated' and branch_id=pg_temp.ocid('branch-a') order by created_at,id limit 1),'audit links before/after revisions, generation and mutation UUID');
select ok(not exists(select 1 from app.online_order_settings_requests_v2 where client_request_id in(pg_temp.ocid('request-cashier'),pg_temp.ocid('request-foreign'),pg_temp.ocid('request-invalid'),pg_temp.ocid('request-unseen'))),'denied/invalid and read-only reconciliation do not claim mutation UUIDs');
select is((select count(*) from kitchen_print_dispatch_holds where operator_reference='ONLINE-CONTROLS-001-LOCAL'),625::bigint,'all 625 inert preservation holds remain present');
select is((select coalesce(jsonb_agg(to_jsonb(t) order by t.dispatch_id),'[]'::jsonb) from kitchen_print_dispatch_holds t),(select holds from oc_protected_before),'historical holds unchanged byte-for-byte');
select is((select to_jsonb(t) from web_order_requests t where id=pg_temp.ocid('pending')),(select pending from oc_protected_before),'existing pending request unchanged');
select is((select to_jsonb(t) from app.online_order_live_requests t where request_id=pg_temp.ocid('pending')),(select enrollment from oc_protected_before),'pending admission and original print generation never rewritten');
select ok((select l.print_generation<>s.print_generation from app.online_order_live_requests l join app.online_order_settings s using(branch_id) where l.request_id=pg_temp.ocid('pending')),'printing OFF/ON cannot revive old pending print eligibility');
select is((select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from app.pos_order_alert_registrations t),(select registrations from oc_protected_before),'device opt-in/authority registrations untouched');
select is((select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) from app.pos_order_alert_deliveries t),(select deliveries from oc_protected_before),'notification deliveries untouched');
select is((select coalesce(jsonb_agg(to_jsonb(t) order by t.revision),'[]'::jsonb) from app.pos_order_alert_settings t),(select global_alerts from oc_protected_before),'branch alerts never mutate global operator flag');
select is((select enabled from app.pos_order_alert_registrations where id=pg_temp.ocid('registration')),true,'branch OFF never rewrites per-device opt-in');
select ok((select app.pos_order_alert_authority(r) is null from app.pos_order_alert_registrations r where id=pg_temp.ocid('registration')),'branch alert OFF is an independent authority gate');
select is((select coalesce(jsonb_agg(to_jsonb(t) order by t.revision),'[]'::jsonb) from kitchen_print_containment_policies t),(select containment from oc_protected_before),'containment policies unchanged');

-- A containment revision change is meaningful even when all flags match.
insert into kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
  values(pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),'blocked','Synthetic containment revision','ONLINE-CONTROLS-001-LOCAL');
set local role authenticated;
select pg_temp.oc_as('manager');
insert into oc_results values('after-containment',pg_temp.oc_save('after-containment',false,true,false));
select is((select r->>'no_change' from oc_results where label='after-containment'),'false','same flags do not hide containment revision transition');
select isnt((select r->>'print_generation' from oc_results where label='after-containment'),(select r->>'print_generation' from oc_results where label='print-on'),'containment change rotates print generation using 353 rule');
reset role;

-- Deliberate local channel mismatch is preserved by an unrelated alerts edit.
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.ocid('branch-a');
set local role authenticated;
select is(pg_temp.oc_save('channel-preserved',false,true,true)->>'ok','true','independent alerts save remains possible with separate channel state');
reset role;
select is((select submission_enabled from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a')),true,'alerts save did not repair or overwrite independent channel state');
select ok((select app.pos_order_alert_authority(r) is not null from app.pos_order_alert_registrations r where id=pg_temp.ocid('registration')),'branch ON restores eligibility of the unchanged valid server registration');
update web_order_channel_settings set submission_enabled=false where branch_id=pg_temp.ocid('branch-a');

-- Post-claim, post-write failure must roll back settings/channel/receipt/audit.
create function pg_temp.oc_fail_audit() returns trigger language plpgsql as $$begin
  if new.action='settings.online_orders.updated' and new.branch_id=pg_temp.ocid('branch-a') then raise exception 'synthetic-online-controls-audit-failure';end if;return new;end;$$;
create trigger online_controls_test_audit_failure before insert on audit_events for each row execute function pg_temp.oc_fail_audit();
create temp table oc_before_failure as select to_jsonb(s) settings,(select to_jsonb(c) from web_order_channel_settings c where c.branch_id=s.branch_id) channel from app.online_order_settings s where s.branch_id=pg_temp.ocid('branch-a');
set local role authenticated;
select throws_ok($$select pg_temp.oc_save('audit-failure',true,true,false)$$,'P0001','synthetic-online-controls-audit-failure','post-write failure is explicit');
reset role;
drop trigger online_controls_test_audit_failure on audit_events;
select is((select to_jsonb(s) from app.online_order_settings s where branch_id=pg_temp.ocid('branch-a')),(select settings from oc_before_failure),'settings fully rolled back after failure');
select is((select to_jsonb(c) from web_order_channel_settings c where branch_id=pg_temp.ocid('branch-a')),(select channel from oc_before_failure),'channel fully rolled back after failure');
select ok(not exists(select 1 from app.online_order_settings_requests_v2 where client_request_id=pg_temp.ocid('request-audit-failure')),'failed transaction leaves no committed receipt');

-- Prepublication branches have settings but no channel. A configuration save
-- does not publish/activate them. Normal publication later provides the channel.
delete from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a2');
set local role authenticated;
select is(pg_temp.oc_save('prepublication',false,true,true,null,'a2')->>'ok','true','unpublished branch can configure intake OFF');
reset role;
select ok(not exists(select 1 from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a2')),'settings save did not create unpublished intake channel');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,is_published)
  values(pg_temp.ocid('restaurant-a'),pg_temp.ocid('org-a'),pg_temp.ocid('branch-a2'),'online-controls-publication','Synthetic publication',true);
select is((select ordering_enabled from app.online_order_settings where branch_id=pg_temp.ocid('branch-a2')),false,'publication preserves configured intake OFF');
select is((select submission_enabled from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a2')),true,'existing normal publication trigger supplies its separate channel');
set local role authenticated;
select is(pg_temp.oc_save('after-publication',true,true,true,null,'a2')->>'ok','true','prepublication OFF then publish then intake ON succeeds');
reset role;

-- An explicitly unprovisioned existing branch requires revision zero and does
-- not create or publish a missing channel as a side effect.
delete from app.online_order_settings where branch_id=pg_temp.ocid('branch-a2');
delete from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a2');
set local role authenticated;
select is(pg_temp.oc_read('a2')->>'revision','0','unprovisioned revision zero is explicit');
select is(pg_temp.oc_read('a2')->>'print_generation','0','unprovisioned generation string zero');
select is(pg_temp.oc_save('first-provision',true,false,true,0,'a2')->>'ok','true','exact initial revision can provision settings');
select pg_temp.oc_as('owner');
select is(pg_temp.oc_save('owner',false,false,true,null,'a2')->>'ok','true','covering org owner can manage branch');
reset role;
select ok(not exists(select 1 from web_order_channel_settings where branch_id=pg_temp.ocid('branch-a2')),'settings provisioning never substitutes for publication');

-- Existing 353 API remains available and shares the same authoritative state.
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select pg_temp.oc_as('manager');
select is(public.set_online_order_settings(pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'),true,true,true)->>'ok','true','legacy setter remains compatible');
select is(pg_temp.oc_read()->>'ordering_enabled','true','v2 observes legacy update');
select is(public.get_online_order_settings(pg_temp.ocid('org-a'),pg_temp.ocid('restaurant-a'),pg_temp.ocid('branch-a'))->>'alerts_enabled','true','legacy getter remains compatible');
reset role;
select * from finish();
rollback;
