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

-- Use actor identities separate from the four POS transport principals.
select app.set_pos_order_alerts(true,'Synthetic duty fixtures','local regression');
insert into auth.users(id) values(pg_temp.tc_id('owner-auth')), (pg_temp.tc_id('manager-auth'));
insert into public.app_users(id,auth_user_id,email) values
 (pg_temp.tc_id('owner'),pg_temp.tc_id('owner-auth'),'owner-shift@example.test'),
 (pg_temp.tc_id('manager'),pg_temp.tc_id('manager-auth'),'manager-shift@example.test');
insert into public.memberships(id,organization_id,restaurant_id,branch_id,app_user_id,role)
select pg_temp.tc_id('owner-m'),org,restaurant,branch,pg_temp.tc_id('owner'),'restaurant_owner' from _tc_rest where label='a1'
union all select pg_temp.tc_id('manager-m'),org,restaurant,branch,pg_temp.tc_id('manager'),'manager' from _tc_rest where label='a1';
create function pg_temp.actor(n text,aal text default 'aal2') returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claim.sub',pg_temp.tc_id(n)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.tc_id(n),'aal',aal)::text,true);
end $$;
create function pg_temp.digest(v text) returns text language sql immutable as $$
 select encode(sha256(convert_to(v,'UTF8')),'hex'); $$;
create function pg_temp.preview(k text,n integer default 1) returns jsonb language sql volatile as $$
 select public.pos_preview_shift_order_alert(pg_temp.tc_id('installation-'||n),pg_temp.tc_id('device-'||n),pg_temp.tc_id('pin-'||n),
 'synthetic-platform353-token-'||n,pg_temp.tc_id('duty-'||k),pg_temp.digest('synthetic-revoke-'||k)); $$;
create function pg_temp.issue(k text,flag jsonb default 'true'::jsonb,n integer default 1) returns jsonb language sql volatile as $$
 select public.pos_register_shift_order_alert(pg_temp.tc_id('installation-'||n),pg_temp.tc_id('device-'||n),pg_temp.tc_id('pin-'||n),
 'synthetic-platform353-token-'||n,pg_temp.tc_id('duty-'||k),pg_temp.tc_id('shift-'||n),(r->>'policy_revision')::uuid,
 (r->>'authority_expires_at')::timestamptz,pg_temp.digest('status-'||k),'synthetic-duty-token-for-device-'||n,flag)
 from _tc_results where label='preview-'||k; $$;
create function pg_temp.status(k text,n integer default 1) returns jsonb language sql stable as $$
 select public.pos_shift_order_alert_status(pg_temp.tc_id('installation-'||n),pg_temp.tc_id('duty-'||k),
 pg_temp.digest(pg_temp.digest('status-'||k))); $$;
create function pg_temp.revoke(k text,n integer default 1) returns jsonb language sql volatile as $$
 select public.pos_revoke_shift_order_alert(pg_temp.tc_id('installation-'||n),pg_temp.tc_id('duty-'||k),pg_temp.digest('synthetic-revoke-'||k)); $$;
select ok(not exists(select 1 from app.pos_shift_alert_policies),'default is disabled everywhere');
set local role authenticated;
select is(pg_temp.preview('A')->>'error','no_approved_duty','default denies preview with genuine cashier/device');
select pg_temp.actor('manager-auth');
select is(public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a1'),null,'true',720)->>'error','unauthorized','manager cannot set policy');
select pg_temp.actor('owner-auth','aal1');
select is(public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a1'),null,'true',720)->>'error','unauthorized','AAL1 owner refused');
select pg_temp.actor('owner-auth');
select is(public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-b1'),null,'true',720)->>'error','unauthorized','foreign tenant refused');
select is(public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a2'),null,'true',720)->>'error','unauthorized','other branch refused');
select is(public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a1'),null,v,720)->>'error','invalid_request','no coerced policy boolean')
 from unnest(array[null::jsonb,'"true"'::jsonb,'"false"'::jsonb,'null'::jsonb]) x(v);
insert into _tc_results values('policy',public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a1'),null,'true',720));
select is((select r->>'ok' from _tc_results where label='policy'),'true','scoped AAL2 owner established test cap');
select is(public.approve_pos_shift_alert_end(pg_temp.tc_id('shift-3'),(select(r->>'policy_revision')::uuid from _tc_results where label='policy'),now()+interval '13 hours')->>'error','unauthorized','foreign existing shift refused');
select is(pg_temp.preview('A')->>'error','no_approved_duty','policy alone grants nothing');
select is(public.approve_pos_shift_alert_end(pg_temp.tc_id('shift-1'),(select(r->>'policy_revision')::uuid from _tc_results where label='policy'),now()+interval '13 hours')->>'ok','true','owner approved only first existing open shift');
select pg_temp.actor('transport-user');
select is(pg_temp.preview('other',2)->>'error','no_approved_duty','peer cannot inherit first shift approval');
reset role;
set local role service_role;
select is(pg_temp.revoke('unknown')->>'error','unauthorized','unallocated revoke does not acknowledge');
reset role;
select is((select count(*) from app.pos_shift_alert_consents),0::bigint,'no unauthenticated tombstone allocation');
set local role authenticated;
insert into _tc_results values('preview-A',pg_temp.preview('A'));
select is((select r->>'ok' from _tc_results where label='preview-A'),'true','authenticated pending preview');
select is(pg_temp.preview('A')->>'authority_expires_at',(select r->>'authority_expires_at' from _tc_results where label='preview-A'),'pending retry stable deadline');
select is(pg_temp.preview('B')->>'error','busy','new pending cannot supersede A');
select is(pg_temp.issue('A',v)->>'error','invalid_request','literal consent true required') from unnest(array[null::jsonb,'null'::jsonb,'"true"'::jsonb,'"false"'::jsonb,'false'::jsonb]) x(v);
reset role;
set local role service_role;
select is(pg_temp.status('A')->>'error','unauthorized','pending cannot read');
select is(pg_temp.revoke('A')->>'ok','true','offline revoke cancels prepared consent before enrollment');
reset role;
set local role authenticated;
select is(pg_temp.issue('A')->>'error','stale_consent','late bind A cannot revive after prior cancellation');
select is(pg_temp.preview('A')->>'error','stale_consent','retired UUID never reopens');
insert into _tc_results values('preview-B',pg_temp.preview('B'));
insert into _tc_results values('issue-B',pg_temp.issue('B'));
select is((select r->>'ok' from _tc_results where label='issue-B'),'true','fresh explicit B activates');
select is(pg_temp.issue('B')->>'generation',(select r->>'generation' from _tc_results where label='issue-B'),'uncertain retry same active generation');
select is(pg_temp.tc_register(1)->>'error','invalid_request','old foreground RPC cannot replace duty');
reset role;
set local role service_role;
select is(pg_temp.revoke('A')->>'consent_id',pg_temp.tc_id('duty-A')::text,'lost response A retried after B acknowledges A only');
select is(pg_temp.status('B')->>'generation',(select r->>'generation' from _tc_results where label='issue-B'),'B still active after A retry');
select is(public.pos_disable_order_alert(pg_temp.tc_id('installation-1'),pg_temp.digest(pg_temp.digest('status-B')))->>'error','unauthorized','legacy no-CAS disable cannot cancel duty');
select is(public.pos_order_alert_status(pg_temp.tc_id('installation-1'),pg_temp.digest(pg_temp.digest('status-B')))->>'error','unauthorized','legacy endpoint cannot read duty');
select is(pg_temp.status('B',2)->>'error','unauthorized','installation mismatch refused');
select is(public.pos_shift_order_alert_status(pg_temp.tc_id('installation-1'),pg_temp.tc_id('duty-B'),pg_temp.digest('synthetic-revoke-B'))->>'error','unauthorized','revoke proof cannot read status');
select is(public.pos_revoke_shift_order_alert(pg_temp.tc_id('installation-1'),pg_temp.tc_id('duty-B'),pg_temp.digest(pg_temp.digest('status-B')))->>'error','unauthorized','status proof cannot cancel');
reset role;
-- Simulated passage of a real PIN deadline, and age both legacy timestamps
-- beyond eight hours without defeating its unchanged physical CHECK.
update public.pin_sessions set expires_at=now()-interval '1 minute' where id=pg_temp.tc_id('pin-1');
update app.pos_order_alert_registrations set registered_at=now()-interval '9 hours',refreshed_at=now()-interval '9 hours',
 authority_expires_at=now()-interval '1 hour' where duty_consent_id=pg_temp.tc_id('duty-B');
set local role authenticated;
select is(pg_temp.tc_inbox(1)->>'ok','false','expired PIN still denies cashier details');
select is(pg_temp.tc_register(2)->>'ok','true','ordinary peer can still register independently');
reset role;
set local role service_role;
select is(pg_temp.status('B')->>'ok','true','duty still authorizes hint-only status beyond PIN and eight hours');
select is((select(r->>'authority_expires_at')::timestamptz from _tc_results where label='issue-B'),now()+interval '12 hours','12h test cap starts at shift open');
select is(pg_temp.tc_submit(1)->>'ok','true','real synthetic pending order enters');
select is(pg_temp.tc_submit(2)->>'ok','true','second real synthetic pending order enters');
insert into _tc_results values('claims',public.pos_claim_order_alert_deliveries());
select is((select count(*) from _tc_results,jsonb_array_elements(r->'deliveries') d where label='claims' and d->>'consent_id'=pg_temp.tc_id('duty-B')::text),2::bigint,'each duty hint carries exact live consent');
select is((select count(*) from _tc_results,jsonb_array_elements(r->'deliveries') d where label='claims' and not d?'consent_id'),2::bigint,'legacy peer hints keep v1 shape');
select is(jsonb_array_length(pg_temp.status('B')->'requests'),2,'one bounded authoritative response tracks two orders');
reset role;
set local role authenticated;
select is(public.pos_reject_web_order_customer(pg_temp.tc_id('pin-2'),pg_temp.tc_id('device-2'),'synthetic-platform353-token-2',pg_temp.tc_request(1),pg_temp.tc_client(3991),'synthetic')->>'ok','true','ordinary peer resolves only first');
reset role;
set local role service_role;
select is(jsonb_array_length(pg_temp.status('B')->'requests'),1,'one pending continues');
select is(pg_temp.status('B')#>>'{requests,0,request_id}',pg_temp.tc_request(2)::text,'remaining identity is exact');
insert into _tc_results values('rotated',public.pos_refresh_shift_order_alert_token(pg_temp.tc_id('installation-1'),pg_temp.tc_id('duty-B'),
 pg_temp.digest(pg_temp.digest('status-B')),'synthetic-rotated-duty-token',(select(r->>'generation')::uuid from _tc_results where label='issue-B')));
select isnt((select r->>'generation' from _tc_results where label='rotated'),(select r->>'generation' from _tc_results where label='issue-B'),'transport generation advances');
select is((select r->>'consent_id' from _tc_results where label='rotated'),pg_temp.tc_id('duty-B')::text,'consent does not advance on token rotation');
select is((select r->>'authority_expires_at' from _tc_results where label='rotated'),(select r->>'authority_expires_at' from _tc_results where label='issue-B'),'rotation never renews deadline');
reset role;
-- Independent destructive transitions on the same proven active binding. Each
-- scenario rolls its fixture mutations back in its own PL/pgSQL subtransaction.
-- Assert inside/outside statuses so a pre-existing denial cannot pass the test.
create function pg_temp.terminated_after(k text) returns boolean language plpgsql as $$
declare verified boolean:=false;rot jsonb;selected jsonb;
begin
 if pg_temp.status('B')->'ok' is distinct from 'true'::jsonb then return false;end if;
 begin
  case k
  when 'shift closed/reopened' then
   update shifts set status='closing' where id=pg_temp.tc_id('shift-1');
   update shifts set status='open' where id=pg_temp.tc_id('shift-1');
  when 'role revoked/restored' then
   update memberships set role='kitchen_staff' where id=pg_temp.tc_id('membership-1');
   update memberships set role='cashier' where id=pg_temp.tc_id('membership-1');
  when 'member suspended/restored' then
   update memberships set status='revoked' where id=pg_temp.tc_id('membership-1');
   update memberships set status='active' where id=pg_temp.tc_id('membership-1');
  when 'account disabled/restored' then
   update app_users set is_active=false where id=pg_temp.tc_id('staff-1');
   update app_users set is_active=true where id=pg_temp.tc_id('staff-1');
  when 'future device deadline shortened/renewed' then
   update device_sessions set expires_at=now()+interval '2 hours' where id=pg_temp.tc_id('session-1');
   update device_sessions set expires_at=now()+interval '30 days' where id=pg_temp.tc_id('session-1');
  when 'explicit PIN end' then
   update pin_sessions set is_active=false,ended_at=now() where id=pg_temp.tc_id('pin-1');
  when 'branch disabled/restored' then
   update branches set status='suspended' where id=pg_temp.tc_id('branch-a1');
   update branches set status='active' where id=pg_temp.tc_id('branch-a1');
  when 'branch alerts disabled/restored' then
   update app.online_order_settings set alerts_enabled=false where branch_id=pg_temp.tc_id('branch-a1');
   update app.online_order_settings set alerts_enabled=true where branch_id=pg_temp.tc_id('branch-a1');
  when 'approved end changed' then
   perform pg_temp.actor('owner-auth');
   if public.approve_pos_shift_alert_end(pg_temp.tc_id('shift-1'),(select(r->>'policy_revision')::uuid from _tc_results where label='policy'),
     now()+interval '1 hour')->'ok' is distinct from 'true'::jsonb then return false;end if;
  when 'device unpaired' then
   update device_pairings set status='revoked',revoked_at=now() where id=pg_temp.tc_id('pairing-1');
  else raise exception 'unknown test';
  end case;
  rot:=public.pos_refresh_shift_order_alert_token(pg_temp.tc_id('installation-1'),pg_temp.tc_id('duty-B'),pg_temp.digest(pg_temp.digest('status-B')),
   'synthetic-nonreviving-token',(select(r->>'generation')::uuid from _tc_results where label='rotated'));
  selected:=public.pos_claim_order_alert_deliveries();
  verified:=(select state='ended' from app.pos_shift_alert_consents where id=pg_temp.tc_id('duty-B'))
   and pg_temp.status('B')->>'error'='unauthorized' and rot->>'error'='unauthorized' and selected->'ok'='true'::jsonb
   and not exists(select 1 from jsonb_array_elements(selected->'deliveries') d where d?'consent_id');
  raise exception using errcode='T0001',message='rollback scenario';
 exception when sqlstate 'T0001' then null;end;
 return verified and pg_temp.status('B')->'ok'='true'::jsonb;
end $$;
select ok(pg_temp.terminated_after(k),k||' fences status, rotation and claim permanently')
from unnest(array['shift closed/reopened','role revoked/restored','member suspended/restored','account disabled/restored',
 'future device deadline shortened/renewed','explicit PIN end','branch disabled/restored','branch alerts disabled/restored','approved end changed','device unpaired']) x(k);
select pg_temp.actor('owner-auth');
set local role authenticated;
insert into _tc_results values('off',public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a1'),(select(r->>'policy_revision')::uuid from _tc_results where label='policy'),'false',null));
select is((select r->>'ok' from _tc_results where label='off'),'true','owner disables policy atomically');
insert into _tc_results values('on',public.set_pos_shift_alert_policy(pg_temp.tc_id('branch-a1'),(select(r->>'policy_revision')::uuid from _tc_results where label='off'),'true',720));
reset role;
set local role service_role;
select is(pg_temp.status('B')->>'error','unauthorized','OFF then ON cannot revive B');
select is(public.pos_refresh_shift_order_alert_token(pg_temp.tc_id('installation-1'),pg_temp.tc_id('duty-B'),pg_temp.digest(pg_temp.digest('status-B')),
 'synthetic-blocked-duty-token',(select(r->>'generation')::uuid from _tc_results where label='rotated'))->>'error','unauthorized','policy revocation blocks token refresh');
select ok(not exists(select 1 from jsonb_array_elements(public.pos_claim_order_alert_deliveries()->'deliveries') d where d?'consent_id'),'revoked generation cannot be claimed');
reset role;
select ok(not has_table_privilege('authenticated','app.pos_shift_alert_consents','select'),'ordinary client cannot read secrets/grants');
select ok(not has_function_privilege('authenticated','app.pos_order_alert_status_core(uuid,text)','execute'),'internal unscoped core uncallable');
select ok(not has_function_privilege('anon','public.pos_register_shift_order_alert(uuid,uuid,uuid,text,uuid,uuid,uuid,timestamptz,text,text,jsonb)','execute'),'anon cannot issue consent');
select ok(not has_function_privilege('authenticated','public.pos_revoke_shift_order_alert(uuid,uuid,text)','execute'),'public authenticated cannot call delegated service RPC');
-- A second *existing* shift requires an independent approval, PIN, device
-- proof and consent. Preview freezes the pre-renewal device expiry, even
-- though proving the foreground session may slide that session's idle window.
select pg_temp.actor('owner-auth');
set local role authenticated;
select is(public.approve_pos_shift_alert_end(pg_temp.tc_id('shift-2'),(select(r->>'policy_revision')::uuid from _tc_results where label='on'),
 now()+interval '10 hours')->>'ok','true','owner separately approves the second existing shift');
reset role;
update public.device_sessions set expires_at=now()+interval '4 hours' where id=pg_temp.tc_id('session-2');
select pg_temp.actor('transport-user');
set local role authenticated;
insert into _tc_results values('preview-peer',pg_temp.preview('peer',2));
select is((select(r->>'authority_expires_at')::timestamptz from _tc_results where label='preview-peer'),now()+interval '4 hours',
 'initial pre-renewal device session deadline beats approved end and 12-hour cap');
select is(pg_temp.preview('peer',2)->>'authority_expires_at',(select r->>'authority_expires_at' from _tc_results where label='preview-peer'),
 'a replay after the session slides cannot move the approved deadline');
insert into _tc_results values('issue-peer',pg_temp.issue('peer','true',2));
select is((select r->>'ok' from _tc_results where label='issue-peer'),'true','independent peer opted in explicitly');
reset role;
set local role service_role;
select is(pg_temp.revoke('B')->>'ok','true','revoke prior other-device consent');
select is(pg_temp.status('peer',2)->>'ok','true','previous device revocation preserves peer');
select is(public.pos_refresh_order_alert_token(pg_temp.tc_id('installation-2'),pg_temp.digest(pg_temp.digest('status-peer')),
 'synthetic-legacy-replacement-token',(select(r->>'generation')::uuid from _tc_results where label='issue-peer'))->>'error',
 'unauthorized','legacy rotation cannot replace duty generation even with correct status proof');
reset role;
-- Fast-forward only immutable fixture timestamps. Selection, status and
-- rotation still execute their real entry points against the expired row.
update app.pos_shift_alert_consents set issued_at=now()-interval '6 hours',reserve_until=now()-interval '6 hours'+interval '5 minutes',
 deadline=now()-interval '1 minute' where id=pg_temp.tc_id('duty-peer');
set local role service_role;
select is(pg_temp.status('peer',2)->>'error','unauthorized','server deadline denies subsequent status');
select is(public.pos_refresh_shift_order_alert_token(pg_temp.tc_id('installation-2'),pg_temp.tc_id('duty-peer'),pg_temp.digest(pg_temp.digest('status-peer')),
 'synthetic-expired-duty-token',(select(r->>'generation')::uuid from _tc_results where label='issue-peer'))->>'error','unauthorized','deadline denies delegated rotation');
select ok(not exists(select 1 from jsonb_array_elements(public.pos_claim_order_alert_deliveries()->'deliveries') d where d?'consent_id'),'expired grant never selected');
reset role;
select is((select count(*) from public.shifts s join _tc_staff t on s.id=t.shift),4::bigint,'no financial shift created, closed or substituted during enrollment');
select * from finish();
rollback;
