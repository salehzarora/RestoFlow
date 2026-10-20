-- Historical HOME identities retain authentication/isolation coverage after
-- BIZBOT-PLATFORM-ONLINE-ORDERS-353 removes the obsolete UUID admission list.
-- Real public registration boundary; no HTTP/FCM/order/printer transport.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
set local timezone to 'UTC';
select no_plan();

create function pg_temp.rt_id(label text) returns uuid language sql immutable as $$
 select case label
  when 'old' then 'bb80c0d8-6893-4e24-8eea-5a14cf545ecd'::uuid
  when 'new' then 'd9f876fb-57e8-44ee-be94-f2284c6fc905'::uuid
  when 'org' then '20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
  when 'restaurant' then 'de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
  when 'branch' then '2847c0be-3e31-45a5-957c-508729f1971e'::uuid
  else md5('notification-retarget-001-synthetic-'||label)::uuid end
$$;
insert into organizations(id,name,slug,default_currency,status) values
 (pg_temp.rt_id('org'),'Retarget synthetic A','retarget-synthetic-a','ILS','active'),
 (pg_temp.rt_id('foreign-org'),'Retarget synthetic B','retarget-synthetic-b','ILS','active');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.rt_id('restaurant'),pg_temp.rt_id('org'),'Retarget A','UTC'),
 (pg_temp.rt_id('other-restaurant'),pg_temp.rt_id('org'),'Retarget sibling','UTC'),
 (pg_temp.rt_id('foreign-restaurant'),pg_temp.rt_id('foreign-org'),'Retarget B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone) values
 (pg_temp.rt_id('branch'),pg_temp.rt_id('org'),pg_temp.rt_id('restaurant'),'Target','UTC'),
 (pg_temp.rt_id('other-branch'),pg_temp.rt_id('org'),pg_temp.rt_id('restaurant'),'Sibling','UTC'),
 (pg_temp.rt_id('other-restaurant-branch'),pg_temp.rt_id('org'),pg_temp.rt_id('other-restaurant'),'Sibling restaurant','UTC'),
 (pg_temp.rt_id('foreign-branch'),pg_temp.rt_id('foreign-org'),pg_temp.rt_id('foreign-restaurant'),'Foreign','UTC');
insert into app.online_order_settings(organization_id,restaurant_id,branch_id,print_generation,containment_revision)
  select organization_id,restaurant_id,id,nextval('app.kitchen_print_containment_revision'),0 from branches
  where organization_id in(pg_temp.rt_id('org'),pg_temp.rt_id('foreign-org')) on conflict(branch_id) do nothing;
create temp table _rt_devices as
select label,
 case when label='foreign' then pg_temp.rt_id('foreign-org') else pg_temp.rt_id('org') end org,
 case when label='foreign' then pg_temp.rt_id('foreign-restaurant')
  when label='other-restaurant' then pg_temp.rt_id('other-restaurant') else pg_temp.rt_id('restaurant') end restaurant,
 case when label='foreign' then pg_temp.rt_id('foreign-branch')
  when label='other-restaurant' then pg_temp.rt_id('other-restaurant-branch')
  when label='other-branch' then pg_temp.rt_id('other-branch') else pg_temp.rt_id('branch') end branch,
 pg_temp.rt_id(label) device,pg_temp.rt_id(label||'-pairing') pairing,
 pg_temp.rt_id(label||'-session') session,pg_temp.rt_id(label||'-user') app_user,
 pg_temp.rt_id(label||'-membership') membership,pg_temp.rt_id(label||'-employee') employee,
 pg_temp.rt_id(label||'-pin') pin
from unnest(array['old','new','third','foreign','other-restaurant','other-branch']) label;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
 select device,org,restaurant,branch,'pos' from _rt_devices;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
 select pairing,org,restaurant,branch,device,'active' from _rt_devices;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
 select session,org,restaurant,branch,device,pairing,
  app.hash_provisioning_secret('synthetic-retarget-token-'||label),clock_timestamp()+interval '30 days' from _rt_devices;
insert into app_users(id,email) select app_user,'retarget-'||label||'@example.test' from _rt_devices;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
 select membership,app_user,org,restaurant,branch,'cashier' from _rt_devices;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
 select employee,org,restaurant,branch,app_user,membership,'Synthetic '||label from _rt_devices;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
 select pin,org,restaurant,branch,session,employee,membership,clock_timestamp()+interval '6 hours' from _rt_devices;
select set_config('request.jwt.claim.sub',pg_temp.rt_id('transport-user')::text,true);
create function pg_temp.rt_register(label text default 'new',token text default null) returns jsonb
 language sql volatile as $$
 select public.pos_register_order_alert(pg_temp.rt_id(label||'-installation'),
  'synthetic-retarget-fcm-token-'||label,repeat('a',64),pg_temp.rt_id(label),
  pg_temp.rt_id(label||'-pin'),coalesce(token,'synthetic-retarget-token-'||label))
$$;

-- Old/new have distinct, valid sessions/PINs. Denial cannot rely on production
-- hg's revoked session, a shared credential, missing shift or print readiness.
select ok(app.pos_web_order_context(pg_temp.rt_id(label||'-pin'),pg_temp.rt_id(label),
 'synthetic-retarget-token-'||label)->>'ok'='true',label||' has genuine valid independent POS proof')
from unnest(array['old','new','third','foreign','other-restaurant','other-branch']) label;
set local role authenticated;
select is(pg_temp.rt_register()->>'error','disabled','NEW remains unregistered with missing operator gate');
reset role;
select app.set_pos_order_alerts(false,'Synthetic explicit OFF','retarget-001-off');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','disabled','NEW remains unregistered with explicit OFF');
reset role;
select is((select count(*) from app.pos_order_alert_registrations),0::bigint,'OFF created no registration');
select app.set_pos_order_alerts(true,'Synthetic notification-only ON','retarget-001-on');
set local role authenticated;
select is(pg_temp.rt_register()->>'ok','true','NEW registers through unchanged v65 public RPC');
select is(pg_temp.rt_register('old')->>'ok','true','old identity with genuine current authority joins its own branch');
select is(pg_temp.rt_register('third')->>'ok','true','third independently paired same-branch POS joins dynamically');
select is(pg_temp.rt_register('foreign')->>'ok','true','another organization joins only through its own session and PIN');
select is(pg_temp.rt_register('other-restaurant')->>'ok','true','sibling restaurant joins through its own authority');
select is(pg_temp.rt_register('other-branch')->>'ok','true','sibling branch joins through its own authority');
select is(pg_temp.rt_register('new','wrong-synthetic-token')->>'error','invalid_session','invalid device token denied');
reset role;
select is((select count(distinct device_id) from app.pos_order_alert_registrations),6::bigint,
 'six real paired identities join their own scopes without a static UUID list');

-- Authentication failures exercise the actual public entry point. Restore
-- only the deliberately changed synthetic fields; the suite's final ROLLBACK
-- preserves the database. TAP assertions stay outside rolled-back savepoints.
create temp table _rt_session_deadline as select expires_at from device_sessions where id=pg_temp.rt_id('new-session');
create temp table _rt_pin_deadline as select expires_at from pin_sessions where id=pg_temp.rt_id('new-pin');
update devices set device_type='kds' where id=pg_temp.rt_id('new');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','wrong device type denied by real authentication');
reset role;
update devices set device_type='pos' where id=pg_temp.rt_id('new');
update devices set is_active=false where id=pg_temp.rt_id('new');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','inactive device denied');
reset role;
update devices set is_active=true where id=pg_temp.rt_id('new');
update device_sessions set is_active=false,revoked_at=clock_timestamp() where id=pg_temp.rt_id('new-session');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','revoked device session denied');
reset role;
update device_sessions set is_active=true,revoked_at=null where id=pg_temp.rt_id('new-session');
update device_sessions set expires_at=clock_timestamp()-interval '1 minute' where id=pg_temp.rt_id('new-session');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','expired device session denied');
reset role;
update device_sessions set expires_at=(select expires_at from _rt_session_deadline) where id=pg_temp.rt_id('new-session');
update device_pairings set revoked_at=clock_timestamp(),status='revoked' where id=pg_temp.rt_id('new-pairing');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','revoked pairing denied');
reset role;
update device_pairings set revoked_at=null,status='active' where id=pg_temp.rt_id('new-pairing');
update pin_sessions set is_active=false,ended_at=clock_timestamp() where id=pg_temp.rt_id('new-pin');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','ended PIN denied');
reset role;
update pin_sessions set is_active=true,ended_at=null where id=pg_temp.rt_id('new-pin');
update pin_sessions set expires_at=clock_timestamp()-interval '1 minute' where id=pg_temp.rt_id('new-pin');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','expired PIN denied');
reset role;
update pin_sessions set expires_at=(select expires_at from _rt_pin_deadline) where id=pg_temp.rt_id('new-pin');
update employee_profiles set employment_status='suspended' where id=pg_temp.rt_id('new-employee');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','inactive staff denied');
reset role;
update employee_profiles set employment_status='active' where id=pg_temp.rt_id('new-employee');
update memberships set status='revoked' where id=pg_temp.rt_id('new-membership');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','inactive membership denied');
reset role;
update memberships set status='active' where id=pg_temp.rt_id('new-membership');
update memberships set role='kitchen_staff' where id=pg_temp.rt_id('new-membership');
set local role authenticated;
select is(pg_temp.rt_register()->>'error','invalid_session','unsupported staff role remains denied');
reset role;
update memberships set role='cashier' where id=pg_temp.rt_id('new-membership');
set local role authenticated;
select is(public.pos_register_order_alert(pg_temp.rt_id('new-installation'),
 'synthetic-retarget-fcm-token-new',repeat('a',64),pg_temp.rt_id('new'),
 pg_temp.rt_id('old-pin'),'synthetic-retarget-token-new')->>'error','invalid_session','wrong device PIN cannot register NEW');
reset role;

-- Full tenant scope remains structural even without a fixed device CHECK.
create function pg_temp.rt_insert(p_org uuid,p_rest uuid,p_branch uuid,p_device uuid) returns void
 language sql volatile as $$
 insert into app.pos_order_alert_registrations(installation_id,setting_revision,
  organization_id,restaurant_id,branch_id,device_id,device_session_id,pin_session_id,
  employee_profile_id,resolved_membership_id,fcm_token,token_hash,status_secret_hash,
  enabled,registered_at,refreshed_at,authority_expires_at)
 select gen_random_uuid(),setting_revision,p_org,p_rest,p_branch,p_device,
  device_session_id,pin_session_id,employee_profile_id,resolved_membership_id,
  'synthetic-direct-retarget-token',repeat('d',64),repeat('e',64),false,
  registered_at,refreshed_at,authority_expires_at from app.pos_order_alert_registrations
 where device_id=pg_temp.rt_id('new')
$$;
select lives_ok(format('select pg_temp.rt_insert(%L,%L,%L,%L)',
 pg_temp.rt_id('org'),pg_temp.rt_id('restaurant'),pg_temp.rt_id('branch'),pg_temp.rt_id(label)),
 label||' same-scope identity is no longer rejected by a pilot UUID CHECK') from unnest(array['old','third']) label;
select throws_ok(format('select pg_temp.rt_insert(%L,%L,%L,%L)',
 pg_temp.rt_id('foreign-org'),pg_temp.rt_id('restaurant'),pg_temp.rt_id('branch'),pg_temp.rt_id('new')),
 '23503',null,'NEW with wrong organization hits structural tenant FK');
select throws_ok(format('select pg_temp.rt_insert(%L,%L,%L,%L)',
 pg_temp.rt_id('org'),pg_temp.rt_id('other-restaurant'),pg_temp.rt_id('branch'),pg_temp.rt_id('new')),
 '23503',null,'NEW with wrong restaurant hits structural restaurant FK');
select throws_ok(format('select pg_temp.rt_insert(%L,%L,%L,%L)',
 pg_temp.rt_id('org'),pg_temp.rt_id('restaurant'),pg_temp.rt_id('other-branch'),pg_temp.rt_id('new')),
 '23503',null,'NEW with wrong branch hits structural branch FK');
select is((select count(*) from pg_constraint where conrelid='app.pos_order_alert_registrations'::regclass
  and conname in('pos_order_alert_device_scope','pos_order_alert_session_scope','pos_order_alert_pin_scope') and convalidated),3::bigint,
  'device, session and PIN composite scope FKs are validated');

select ok(not has_table_privilege(role_name,'app.pos_order_alert_registrations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),
 role_name||' direct table ACL remains denied') from unnest(array['anon','authenticated','service_role']) role_name;
set local role anon;
select throws_ok('insert into app.pos_order_alert_registrations default values','42501',null,'anon direct INSERT denied');
reset role;
set local role authenticated;
select throws_ok('insert into app.pos_order_alert_registrations default values','42501',null,'authenticated direct INSERT denied');
reset role;
set local role service_role;
select throws_ok('insert into app.pos_order_alert_registrations default values','42501',null,'service_role direct INSERT denied');
reset role;
select ok(relrowsecurity and relforcerowsecurity,'notification registration forced RLS preserved')
 from pg_class where oid='app.pos_order_alert_registrations'::regclass;
select ok(prosecdef and proowner='postgres'::regrole and proconfig=array['search_path=""'],
 'registration owner/SECURITY DEFINER/empty search_path preserved') from pg_proc
 where oid='app.pos_register_order_alert(uuid,text,text,uuid,uuid,text)'::regprocedure;
select ok(not prosecdef and proconfig=array['search_path=""'],'v65 public wrapper remains INVOKER with empty search_path')
 from pg_proc where oid='public.pos_register_order_alert(uuid,text,text,uuid,uuid,text)'::regprocedure;

-- A notification registration does not enroll a printer or change business
-- state. Existing comprehensive printing fixtures remain on OLD device-1.
select is((select count(*) from kitchen_printer_readiness_reports),0::bigint,'NEW notification needs no fabricated readiness');
select is((select count(*) from web_order_requests),0::bigint,'registration creates no order request');
select is((select count(*) from orders),0::bigint,'registration creates no canonical order');
select is((select count(*) from kitchen_print_dispatches),0::bigint,'registration creates no dispatch');
select is((select count(*) from web_order_print_attempts),0::bigint,'registration creates no print attempt');
select is((select count(*) from app.mapsburger_web_order_rollouts),0::bigint,'notification registration creates no printing rollout');
select is((select count(*) from app.pos_order_alert_deliveries),0::bigint,'registration does not send or queue a notification');
select * from finish();
rollback;
