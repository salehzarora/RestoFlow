-- BIZBOT-STOREFRONT-SEO-CONSENT-001. Synthetic, rollback-only, no HTTP.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.sid(label text) returns uuid language sql immutable as $$select md5('storefront-seo-consent-001-'||label)::uuid;$$;
create function pg_temp.seo_as(label text) returns text language sql volatile as $$select set_config('request.jwt.claim.sub',pg_temp.sid('auth-'||label)::text,true);$$;
create function pg_temp.seo_read(restaurant text default 'a') returns jsonb language sql volatile as $$
  select public.get_storefront_seo_consent_v1(pg_temp.sid(case when restaurant='b' then 'org-b' else 'org-a' end),pg_temp.sid('restaurant-'||restaurant));$$;
create function pg_temp.seo_save(request text,consent boolean,revision bigint default null,restaurant text default 'a') returns jsonb language sql volatile as $$
  select public.set_storefront_seo_consent_v1(pg_temp.sid('request-'||request),pg_temp.sid(case when restaurant='b' then 'org-b' else 'org-a' end),pg_temp.sid('restaurant-'||restaurant),
    coalesce(revision,(pg_temp.seo_read(restaurant)->>'revision')::bigint),consent);$$;
create function pg_temp.seo_check(request text,consent boolean,revision bigint,restaurant text default 'a') returns jsonb language sql volatile as $$
  select public.reconcile_storefront_seo_consent_v1(pg_temp.sid('request-'||request),pg_temp.sid(case when restaurant='b' then 'org-b' else 'org-a' end),pg_temp.sid('restaurant-'||restaurant),revision,consent);$$;
insert into organizations(id,name,slug,default_currency) values
  (pg_temp.sid('org-a'),'SEO consent A','seo-consent-a','ILS'),(pg_temp.sid('org-b'),'SEO consent B','seo-consent-b','ILS');
insert into restaurants(id,organization_id,name,timezone) select pg_temp.sid('restaurant-'||r),pg_temp.sid(case when r='b' then 'org-b' else 'org-a' end),'SEO consent '||r,'UTC' from unnest(array['a','a2','b']) r;
insert into branches(id,organization_id,restaurant_id,name,timezone) select pg_temp.sid('branch-'||b),pg_temp.sid(case when b='b' then 'org-b' else 'org-a' end),pg_temp.sid(case when b='a-alt' then 'restaurant-a' else 'restaurant-'||b end),'SEO consent '||b,'UTC' from unnest(array['a','a-alt','a2','b']) b;
insert into restaurant_storefront_profiles(organization_id,restaurant_id,storefront_branch_id,slug,display_name,is_published)
  select pg_temp.sid(case when r='b' then 'org-b' else 'org-a' end),pg_temp.sid('restaurant-'||r),pg_temp.sid('branch-'||r),'seo-consent-'||r,'SEO consent '||r,true from unnest(array['a','a2','b']) r;
insert into auth.users(id,instance_id,email) select pg_temp.sid('auth-'||u),'00000000-0000-0000-0000-000000000000','seo-consent-'||u||'@example.test' from unnest(array['owner','owner2','orgowner','manager','cashier','kitchen','accountant','branchowner','foreign','platform','unlinked']) u;
insert into app_users(id,email,auth_user_id) select pg_temp.sid('user-'||u),'seo-consent-'||u||'@example.test',pg_temp.sid('auth-'||u) from unnest(array['owner','owner2','orgowner','manager','cashier','kitchen','accountant','branchowner','foreign','platform']) u;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values
  (pg_temp.sid('member-owner'),pg_temp.sid('user-owner'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,'restaurant_owner'),
  (pg_temp.sid('member-owner2'),pg_temp.sid('user-owner2'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,'restaurant_owner'),
  (pg_temp.sid('member-orgowner'),pg_temp.sid('user-orgowner'),pg_temp.sid('org-a'),null,null,'org_owner'),
  (pg_temp.sid('member-manager'),pg_temp.sid('user-manager'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,'manager'),
  (pg_temp.sid('member-cashier'),pg_temp.sid('user-cashier'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,'cashier'),
  (pg_temp.sid('member-kitchen'),pg_temp.sid('user-kitchen'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,'kitchen_staff'),
  (pg_temp.sid('member-accountant'),pg_temp.sid('user-accountant'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,'accountant'),
  (pg_temp.sid('member-branchowner'),pg_temp.sid('user-branchowner'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),pg_temp.sid('branch-a'),'restaurant_owner'),
  (pg_temp.sid('member-foreign'),pg_temp.sid('user-foreign'),pg_temp.sid('org-b'),null,null,'org_owner');
insert into platform_admin_grants(app_user_id,granted_by) values(pg_temp.sid('user-platform'),pg_temp.sid('user-orgowner'));
create temp table seo_results(label text primary key,r jsonb);
grant all on seo_results to authenticated;
create temp table seo_profile_before as select to_jsonb(p) p from restaurant_storefront_profiles p where restaurant_id=pg_temp.sid('restaurant-a');

-- Material protected state is snapshotted before consent-only operations.
create temp table seo_protected_before(relation text primary key,payload jsonb);
do $$declare rel text;v jsonb;begin
  foreach rel in array array['public.web_order_channel_settings','public.web_order_requests','public.web_order_decisions',
    'app.online_order_settings','app.online_order_live_requests','app.pos_order_alert_settings','app.pos_order_alert_registrations',
    'app.pos_order_alert_deliveries','public.kitchen_print_dispatches','public.kitchen_print_dispatch_holds','public.kitchen_print_containment_policies'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',rel) into v;
    insert into seo_protected_before values(rel,v);
  end loop;
end;$$;

select ok(relrowsecurity and relforcerowsecurity,'forced RLS: '||relname) from pg_class where oid in('app.restaurant_storefront_seo_consent_v1'::regclass,'app.storefront_seo_consent_requests_v1'::regclass);
select is((select count(*) from pg_policy where polrelid=relation::regclass),4::bigint,'explicit four deny policies: '||relation)
  from unnest(array['app.restaurant_storefront_seo_consent_v1','app.storefront_seo_consent_requests_v1']) relation;
select ok(not has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'no direct consent/receipt privilege: '||r||' '||t)
  from unnest(array['anon','authenticated','service_role']) r cross join unnest(array['app.restaurant_storefront_seo_consent_v1','app.storefront_seo_consent_requests_v1']) t;
select ok(not has_function_privilege(r,f,'EXECUTE'),'RPC denied: '||r||' '||f) from unnest(array['anon','service_role']) r cross join unnest(array[
  'public.get_storefront_seo_consent_v1(uuid,uuid)','public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)','public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)']) f;
select ok(has_function_privilege('authenticated',f,'EXECUTE'),'authenticated RPC grant: '||f) from unnest(array[
  'public.get_storefront_seo_consent_v1(uuid,uuid)','public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)','public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)']) f;
select ok(not prosecdef,'invoker wrapper: '||proname) from pg_proc where oid in(
  'public.get_storefront_seo_consent_v1(uuid,uuid)'::regprocedure,'public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)'::regprocedure,'public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)'::regprocedure);
select ok(not has_function_privilege(r,f,'EXECUTE'),'private helper denied: '||r||' '||f) from unnest(array['anon','authenticated','service_role']) r cross join unnest(array[
  'app.storefront_seo_eligibility_when_released_v1(uuid,uuid)','app.storefront_seo_consent_authorize_v1(uuid,uuid,integer,text)',
  'app.storefront_seo_consent_state_v1(uuid,uuid)','app.storefront_seo_consent_intent_v1(uuid,uuid,bigint,boolean)']) f;

set local role anon;
select throws_ok($$select pg_temp.seo_read()$$,'42501',null,'anonymous read denied');
select throws_ok($$select pg_temp.seo_save('anon',true,0)$$,'42501',null,'anonymous write denied');
reset role;
set local role service_role;
select throws_ok($$select pg_temp.seo_save('service',true,0)$$,'42501',null,'service role has no consent authority');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
select set_config('app.current_app_user_id',pg_temp.sid('user-orgowner')::text,true);
select throws_ok($$select pg_temp.seo_read()$$,'42501',null,'GUC-only identity cannot authorize');
select pg_temp.seo_as('unlinked');
select throws_ok($$select pg_temp.seo_read()$$,'42501',null,'unlinked JWT fails closed despite actor GUC');
select pg_temp.seo_as('platform');
select is(pg_temp.seo_save('platform',true,0)->>'error','not_found','platform administrator is not a tenant owner');
select pg_temp.seo_as('foreign');
select is(pg_temp.seo_read()->>'error','not_found','foreign tenant owner cannot read');
select is(pg_temp.seo_save('foreign',true,0)->>'error','not_found','foreign tenant owner cannot write');
select is(pg_temp.seo_check('foreign',true,0)->>'error','not_found','foreign tenant owner cannot inspect receipts');
select pg_temp.seo_as('branchowner');
select is(pg_temp.seo_read()->>'error','not_found','branch-scoped owner cannot read restaurant consent');
select is(pg_temp.seo_save('branch',true,0)->>'error','not_found','branch-scoped owner cannot write restaurant consent');
select pg_temp.seo_as('cashier');
select is(pg_temp.seo_read()->>'error','permission_denied','cashier cannot read owner setting');
select is(pg_temp.seo_save('cashier',true,0)->>'error','permission_denied','cashier write denied');
select pg_temp.seo_as('kitchen');
select is(pg_temp.seo_save('kitchen',true,0)->>'error','permission_denied','kitchen write denied');
select pg_temp.seo_as('accountant');
select is(pg_temp.seo_save('accountant',true,0)->>'error','permission_denied','accountant write denied');
select pg_temp.seo_as('manager');
select is(pg_temp.seo_read()->>'can_manage','false','manager can read with no consent-writing authority');
select is(pg_temp.seo_save('manager',true,0)->>'error','permission_denied','ordinary Storefront manager cannot opt in');
select is(pg_temp.seo_check('manager',true,0)->>'error','permission_denied','manager cannot reconcile an owner receipt');
select is(public.set_storefront_seo_consent_v1(pg_temp.sid('wrong-ancestry'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-b'),0,true)->>'error','not_found','wrong restaurant ancestry denied before audit');
select pg_temp.seo_as('owner');
select is(pg_temp.seo_read()->>'consent_enabled','false','existing published restaurant defaults OFF without inference');
select is(pg_temp.seo_read()->>'provisioned','false','read never seeds consent');
select is(pg_temp.seo_read()->>'revision','0','absence has revision zero');
select is(jsonb_typeof(pg_temp.seo_read()->'revision'),'string','revision is a lossless decimal string');
select is(pg_temp.seo_read()->>'can_manage','true','restaurant owner can manage exact restaurant');
select is(pg_temp.seo_read('a2')->>'error','not_found','restaurant owner cannot read sibling restaurant');
select is(pg_temp.seo_save('sibling',true,0,'a2')->>'error','not_found','restaurant owner cannot write sibling restaurant');
select is(pg_temp.seo_read('missing')->>'error','not_found','missing restaurant denied');
select is(public.get_storefront_seo_consent_v1(null,pg_temp.sid('restaurant-a'))->>'error','invalid_request','null scope rejected');
select is(pg_temp.seo_save('null',null,0)->>'error','invalid_request','null decision rejected');
select is(public.set_storefront_seo_consent_v1(null,pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),0,true)->>'error','invalid_request','null request ID rejected');
select is(public.set_storefront_seo_consent_v1(pg_temp.sid('null-rev'),pg_temp.sid('org-a'),pg_temp.sid('restaurant-a'),null,true)->>'error','invalid_request','null revision rejected');
select is(pg_temp.seo_save('negative',true,-1)->>'error','invalid_request','negative revision rejected');
insert into seo_results values('opt-in',pg_temp.seo_save('opt-in',true,0));
select is((select r->>'ok' from seo_results where label='opt-in'),'true','restaurant owner explicitly opts in');
select is(pg_temp.seo_read()->>'consent_enabled','true','authoritative read confirms opt-in');
select is(pg_temp.seo_read()->>'revision','1','first decision advances consent revision');
select is(pg_temp.seo_read()->>'updated_by_app_user_id',pg_temp.sid('user-owner')::text,'decision records server actor');
select ok(pg_temp.seo_read()->>'updated_at' is not null,'decision records server timestamp');
select is(pg_temp.seo_read()->>'indexing_active','false','saving consent never activates indexing');
select is(pg_temp.seo_read()->>'effective_indexing_eligible','false','effective indexing always disabled this release');
select is(pg_temp.seo_save('opt-in',true,0)->>'idempotent_replay','true','identical request replays before current CAS');
select is(pg_temp.seo_save('opt-in',false,0)->>'error','request_conflict','same UUID cannot change decision');
select is(pg_temp.seo_save('opt-in',true,1)->>'error','request_conflict','same UUID cannot change expected revision');
insert into seo_results values('stale',pg_temp.seo_save('stale',false,0));
select is((select r->>'error' from seo_results where label='stale'),'revision_conflict','stale write refused');
select is((select r#>>'{current,consent_enabled}' from seo_results where label='stale'),'true','conflict carries authoritative current state');
select is(pg_temp.seo_check('stale',false,0)->>'mutation_state','refused','CAS refusal has a recoverable receipt');
select is(pg_temp.seo_save('stale',false,0)->>'idempotent_replay','true','same stale intent deterministically replays refusal');
select is(pg_temp.seo_check('opt-in',true,0)->>'mutation_state','committed','lost response can recover its receipt');
select is(pg_temp.seo_check('opt-in',false,0)->>'error','request_conflict','reconcile binds complete original intent');
select is(pg_temp.seo_check('never-submitted',false,1)->>'mutation_state','not_recorded','read-only recovery does not invent a write');
insert into seo_results values('no-op',pg_temp.seo_save('no-op',true,1));
select is((select r->>'no_change' from seo_results where label='no-op'),'true','same decision records a no-change receipt');
select is(pg_temp.seo_read()->>'revision','1','no-change save leaves revision stable');
insert into seo_results values('revoke',pg_temp.seo_save('revoke',false,1));
select is(pg_temp.seo_read()->>'consent_enabled','false','explicit revocation is authoritative');
select is(pg_temp.seo_read()->>'revision','2','revocation advances revision');
select is(pg_temp.seo_save('opt-in',true,0)->>'idempotent_replay','true','old opt-in receipt can replay after revocation');
select is(pg_temp.seo_read()->>'consent_enabled','false','old receipt cannot restore revoked consent');
select is(pg_temp.seo_check('opt-in',true,0)#>>'{current,consent_enabled}','false','receipt recovery distinguishes old result from current revoked state');
select pg_temp.seo_as('manager');
select is(pg_temp.seo_read()->>'consent_enabled','false','manager read sees current owner decision');
select pg_temp.seo_as('orgowner');
select is(pg_temp.seo_save('org-opt-in',true,0,'a2')->>'ok','true','organization owner covers sibling restaurant');
select is(pg_temp.seo_save('org-opt-in',true,0,'a')->>'error','request_conflict','same actor+UUID cannot switch restaurant');
select is(pg_temp.seo_check('org-opt-in',true,0,'a')->>'error','request_conflict','reconcile cannot switch restaurant with same UUID');
reset role;
select is((select count(*) from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.sid('request-opt-in')),1::bigint,'duplicate opt-in has one receipt');
select is((select count(*) from audit_events where action='settings.storefront.seo_consent.updated' and new_values->>'client_request_id'=pg_temp.sid('request-opt-in')::text),1::bigint,'duplicate opt-in has one audit');
select is((select count(*) from audit_events where action='settings.storefront.seo_consent.updated' and new_values->>'client_request_id'=pg_temp.sid('request-no-op')::text),0::bigint,'no-change intent has no duplicate mutation audit');
select is((select count(*) from audit_events where action='settings.storefront.seo_consent.denied' and actor_app_user_id=pg_temp.sid('user-manager')),1::bigint,'manager write denial audited once');
select ok(not exists(select 1 from audit_events where restaurant_id=pg_temp.sid('restaurant-b') and actor_app_user_id=pg_temp.sid('user-manager')),'wrong ancestry denial creates no foreign audit');
select ok(not exists(select 1 from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.sid('request-never-submitted')),'reconciliation never claims a missing receipt');
select is((select to_jsonb(p) from restaurant_storefront_profiles p where restaurant_id=pg_temp.sid('restaurant-a')),(select p from seo_profile_before),'consent saves leave every Storefront/profile field unchanged');
create temp table seo_protected_after(relation text primary key,payload jsonb);
do $$declare rec record;v jsonb;begin for rec in select relation from seo_protected_before loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',rec.relation) into v;
  insert into seo_protected_after values(rec.relation,v);
end loop;end;$$;
select is(a.payload,b.payload,'consent-only operations preserve checkout/alerts/printing rows: '||a.relation) from seo_protected_before a join seo_protected_after b using(relation);
select throws_ok($$update app.storefront_seo_consent_requests_v1 set result='{}'$$,'42501',null,'receipt UPDATE append-only guard');
select throws_ok($$delete from app.storefront_seo_consent_requests_v1$$,'42501',null,'receipt DELETE append-only guard');
select throws_ok($$truncate app.storefront_seo_consent_requests_v1$$,'42501',null,'receipt TRUNCATE append-only guard');
select throws_ok($$insert into app.restaurant_storefront_seo_consent_v1(organization_id,restaurant_id,revision,updated_by_app_user_id) values(pg_temp.sid('org-a'),pg_temp.sid('restaurant-b'),1,pg_temp.sid('user-owner'))$$,'23503',null,'composite FK blocks cross-organization state');

-- Restaurants created after the migration also project OFF; no trigger/seed.
insert into restaurants(id,organization_id,name) values(pg_temp.sid('restaurant-new'),pg_temp.sid('org-a'),'New SEO restaurant');
set local role authenticated;
select pg_temp.seo_as('orgowner');
select is(pg_temp.seo_read('new')->>'consent_enabled','false','new restaurant defaults OFF');
select is(pg_temp.seo_read('new')->>'revision','0','new restaurant has no inferred revision');
select is(pg_temp.seo_save('explicit-off',false,0,'new')->>'revision','1','explicit initial OFF is a recorded decision');
select is(pg_temp.seo_read('new')->>'consent_enabled','false','explicit initial OFF remains OFF');
reset role;

-- All future eligibility inputs are checked against current private state.
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a')),'revoked consent fails future candidate check');
select ok(app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'consented live published restaurant is only a future candidate');
update restaurant_storefront_profiles set paused_until=clock_timestamp()+interval '1 day',pause_reason='Temporarily closed' where restaurant_id=pg_temp.sid('restaurant-a2');
select ok(app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'temporary closure does not revoke consent/candidate status');
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.sid('restaurant-a2');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'unpublished plus consent ON is ineligible');
update restaurant_storefront_profiles set is_published=true,deleted_at=clock_timestamp() where restaurant_id=pg_temp.sid('restaurant-a2');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'deleted profile is ineligible');
update restaurant_storefront_profiles set deleted_at=null where restaurant_id=pg_temp.sid('restaurant-a2');
update branches set status='suspended' where id=pg_temp.sid('branch-a2');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'suspended branch is ineligible');
update branches set status='active',deleted_at=clock_timestamp() where id=pg_temp.sid('branch-a2');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'deleted branch is ineligible');
update branches set deleted_at=null where id=pg_temp.sid('branch-a2');
update restaurants set status='suspended' where id=pg_temp.sid('restaurant-a2');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'suspended restaurant is ineligible');
set local role authenticated;
select pg_temp.seo_as('orgowner');
select is(pg_temp.seo_read('a2')->>'error','not_found','suspended restaurant consent is unavailable');
select is(pg_temp.seo_save('suspended',false,1,'a2')->>'error','not_found','suspended restaurant refuses consent write');
select is(pg_temp.seo_check('org-opt-in',true,0,'a2')->>'error','not_found','suspended restaurant does not reveal receipts');
reset role;
update restaurants set status='active',deleted_at=clock_timestamp() where id=pg_temp.sid('restaurant-a2');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'deleted restaurant is ineligible');
set local role authenticated;
select pg_temp.seo_as('orgowner');
select is(pg_temp.seo_save('deleted',false,1,'a2')->>'error','not_found','deleted restaurant refuses consent write');
reset role;
update restaurants set deleted_at=null where id=pg_temp.sid('restaurant-a2');
update organizations set status='suspended' where id=pg_temp.sid('org-a');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'suspended organization is ineligible');
set local role authenticated;
select pg_temp.seo_as('orgowner');
select is(pg_temp.seo_read('a2')->>'error','not_found','suspended organization consent is unavailable');
reset role;
update organizations set status='active',deleted_at=clock_timestamp() where id=pg_temp.sid('org-a');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-a2')),'deleted organization is ineligible');
update organizations set deleted_at=null where id=pg_temp.sid('org-a');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-a'),pg_temp.sid('restaurant-missing')),'missing restaurant is ineligible');
select ok(not app.storefront_seo_eligibility_when_released_v1(pg_temp.sid('org-b'),pg_temp.sid('restaurant-a2')),'wrong-tenant candidate check fails closed');
select is((select consent_enabled from app.restaurant_storefront_seo_consent_v1 where restaurant_id=pg_temp.sid('restaurant-a2')),true,'temporary closure/publication/status changes preserve stored consent');
select is((select count(*) from app.storefront_seo_consent_requests_v1 where client_request_id in(pg_temp.sid('request-suspended'),pg_temp.sid('request-deleted'))),0::bigint,'unavailable scopes do not claim receipts');

-- A failure after state+receipt insertion must roll back both and its audit.
create function pg_temp.fail_seo_audit() returns trigger language plpgsql as $$begin if new.action='settings.storefront.seo_consent.updated' then raise exception 'synthetic-seo-postwrite-failure';end if;return new;end;$$;
create trigger seo_test_postwrite_failure before insert on public.audit_events for each row execute function pg_temp.fail_seo_audit();
set local role authenticated;
select pg_temp.seo_as('owner');
select throws_ok($$select pg_temp.seo_save('rollback',true,2)$$,'P0001','synthetic-seo-postwrite-failure','late audit failure rolls back mutation and receipt');
select is(pg_temp.seo_read()->>'consent_enabled','false','failed write leaves revoked decision authoritative');
select is(pg_temp.seo_check('rollback',true,2)->>'mutation_state','not_recorded','failed write leaves no receipt');
reset role;
drop trigger seo_test_postwrite_failure on public.audit_events;
set local role authenticated;
select pg_temp.seo_as('owner');
select is(pg_temp.seo_save('rollback',true,2)->>'ok','true','identical explicit retry can commit after real rollback');
select pg_temp.seo_as('owner2');
select is(pg_temp.seo_save('opt-in',false,3)->>'ok','true','request identity is per actor');
reset role;
update memberships set status='revoked' where id=pg_temp.sid('member-owner');
set local role authenticated;
select pg_temp.seo_as('owner');
select is(pg_temp.seo_save('opt-in',true,0)->>'error','not_found','revoked membership cannot replay its prior receipt');
select is(pg_temp.seo_check('opt-in',true,0)->>'error','not_found','revoked membership cannot recover its prior receipt');
reset role;
select * from finish();
rollback;
