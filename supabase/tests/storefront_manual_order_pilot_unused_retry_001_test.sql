-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: one replacement for an unused additional window.
-- The pilot deliberately pins these scope UUIDs. All rows below are synthetic
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
create function pg_temp.mp_submit(n integer,p_body jsonb default null,
 p_token text default repeat('a',64),p_slug text default 'mapsburger')
returns jsonb language sql volatile as $$
 select public.submit_web_order_pilot_request(p_slug,pg_temp.mp_client(n),p_token,
  coalesce(p_body,pg_temp.mp_order()))
$$;
create function pg_temp.mp_contact_hash() returns text language sql immutable as $$
 select encode(sha256(convert_to(repeat('c',64)||E'\nsynthetic pilot guest\n+972520000123','UTF8')),'hex')
$$;
create function pg_temp.mp_insert_pilot(p_enabled boolean default true,
 p_starts timestamptz default clock_timestamp()-interval '1 second',
 p_expires timestamptz default clock_timestamp()+interval '10 minutes')
returns uuid language plpgsql as $$
declare v_id uuid;
begin
 insert into app.storefront_manual_order_pilots(
  organization_id,restaurant_id,branch_id,enabled,starts_at,expires_at,
  contact_salt,contact_hash,operator_reference)
 values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),p_enabled,p_starts,p_expires,
  repeat('c',64),pg_temp.mp_contact_hash(),'synthetic rollback-only SQL security test')
 returning id into v_id;
 return v_id;
end$$;
create function pg_temp.mp_counts() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object(
  'requests',(select count(*) from public.web_order_requests where organization_id=pg_temp.mp_org()),
  'events',(select count(*) from public.web_order_request_events where organization_id=pg_temp.mp_org()),
  'orders',(select count(*) from public.orders where organization_id=pg_temp.mp_org()),
  'decisions',(select count(*) from public.web_order_decisions where organization_id=pg_temp.mp_org()),
  'dispatches',(select count(*) from public.kitchen_print_dispatches where organization_id=pg_temp.mp_org()),
  'attempts',(select count(*) from public.web_order_print_attempts where organization_id=pg_temp.mp_org()),
  'channel',(select to_jsonb(c) from public.web_order_channel_settings c where branch_id=pg_temp.mp_branch()),
  'pilots',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]'::jsonb)
   from app.storefront_manual_order_pilots p where branch_id=pg_temp.mp_branch()))
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
-- Exercise the retained legacy pilot/rollout contract independently of the
-- new platform entitlement (covered by platform_online_orders_353_test.sql).
update app.online_order_settings set ordering_enabled=false where organization_id in (pg_temp.mp_org(),pg_temp.mp_id('org_b'));
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),true) on conflict(branch_id) do update set submission_enabled=excluded.submission_enabled;
insert into kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),'blocked',
 'Synthetic SQL test; no printer operation','manual-pilot-001-synthetic');


-- Fixture-only BEFORE INSERT backdating creates a genuinely expired synthetic
-- predecessor through the actual price/idempotency writer. No production
-- trigger, guard or credential is disabled and no hosted data is used.
create function pg_temp.mp_backdate_request() returns trigger language plpgsql as $$
begin
 if new.organization_id=pg_temp.mp_org()
   and current_setting('test.mp_backdate_parent',true)='true' then
  new.created_at:=new.created_at-interval '16 minutes';
  new.expires_at:=new.expires_at-interval '16 minutes';
  new.status_until:=new.status_until-interval '16 minutes';
 end if;
 return new;
end$$;
create trigger zz_mp_backdate_request before insert on web_order_requests
 for each row execute function pg_temp.mp_backdate_request();

create function pg_temp.mp_install_extra(
 p_id uuid,p_previous uuid,p_request uuid,p_starts timestamptz,p_expires timestamptz,
 p_pilot_expires timestamptz default null,p_reference text default 'synthetic additional allowance'
) returns uuid language plpgsql as $$
begin
 perform app.lock_kitchen_print_containment(pg_temp.mp_branch(),true);
 insert into app.storefront_manual_order_pilot_extra_allowance(
  pilot_id,previous_pilot_id,previous_request_id,organization_id,restaurant_id,branch_id,
  starts_at,expires_at,operator_reference)
 values(p_id,p_previous,p_request,pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),
  p_starts,p_expires,p_reference);
 insert into app.storefront_manual_order_pilots(
  id,organization_id,restaurant_id,branch_id,enabled,starts_at,expires_at,
  contact_salt,contact_hash,operator_reference)
 values(p_id,pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),true,p_starts,
  coalesce(p_pilot_expires,p_expires),repeat('c',64),pg_temp.mp_contact_hash(),p_reference);
 return p_id;
end$$;


create function pg_temp.mp_install_retry(p_id uuid,p_unused uuid,p_starts timestamptz,p_expires timestamptz,
 p_salt text default repeat('c',64),p_hash text default pg_temp.mp_contact_hash(),
 p_pilot_expires timestamptz default null,p_ref text default 'synthetic unused retry')
returns uuid language plpgsql as $$
begin
 perform app.lock_kitchen_print_containment(pg_temp.mp_branch(),true);
 insert into app.storefront_manual_order_pilot_unused_retry(
  pilot_id,unused_extra_pilot_id,organization_id,restaurant_id,branch_id,starts_at,expires_at,operator_reference)
 values(p_id,p_unused,pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),p_starts,p_expires,p_ref);
 insert into app.storefront_manual_order_pilots(id,organization_id,restaurant_id,branch_id,
  enabled,starts_at,expires_at,contact_salt,contact_hash,operator_reference)
 values(p_id,pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),true,p_starts,
  coalesce(p_pilot_expires,p_expires),p_salt,p_hash,p_ref);
 return p_id;
end$$;

select ok(c.relrowsecurity and c.relforcerowsecurity,'unused retry has forced RLS')
 from pg_class c where c.oid='app.storefront_manual_order_pilot_unused_retry'::regclass;
select ok(not has_table_privilege(role_name,'app.storefront_manual_order_pilot_unused_retry',
 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),role_name||' has no retry table access')
 from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege(role_name,f,'EXECUTE'),role_name||' cannot invoke '||f)
 from unnest(array['anon','authenticated','service_role']) role_name cross join
 unnest(array['app.guard_manual_order_pilot_unused_retry()',
 'app.verify_manual_order_pilot_unused_retry_link()',
 'app.manual_order_pilot_extra_allowed(app.storefront_manual_order_pilots,timestamptz)']) f;
select is((select count(*)::int from app.storefront_manual_order_pilot_unused_retry),0,
 'migration installs no retry authorization or active window');
set local role service_role;
select throws_ok($$select count(*) from app.storefront_manual_order_pilot_unused_retry$$,
 '42501',null,'actual service role cannot inspect or mint retry');
reset role;

select set_config('test.mp_backdate_parent','true',true);
create temp table _mp_parent as select pg_temp.mp_insert_pilot() id;
insert into _mp_results values('parent_submit',pg_temp.mp_submit(401));
select set_config('test.mp_backdate_parent','false',true);
create temp table _mp_parent_request as select consumed_request_id id
 from app.storefront_manual_order_pilots where id=(select id from _mp_parent);
select ok((select r->>'ok'='true' and r->>'replayed'='false' from _mp_results where label='parent_submit'),
 'real writer creates only the expired synthetic predecessor');
create temp table _mp_bounds as select clock_timestamp() t;
select pg_temp.mp_install_extra(pg_temp.mp_id('unused_extra'),(select id from _mp_parent),
 (select id from _mp_parent_request),t,t+interval '10 minutes') from _mp_bounds;
set constraints all immediate;
set constraints all deferred;
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.mp_branch();
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp(),clock_timestamp()+interval '10 minutes')$$,'42501',null,
 'an open extra window cannot acquire a competing retry');

create function pg_temp.mp_consumed_retry_denied() returns text language plpgsql as $$
declare r jsonb; result text;
begin
 begin
  r:=pg_temp.mp_submit(402);
  if r->>'ok' is distinct from 'true' then raise exception 'fixture must consume extra'; end if;
  begin
   perform pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
    clock_timestamp(),clock_timestamp()+interval '10 minutes');
   result:='unexpected_success';
  exception when insufficient_privilege then result:='42501'; end;
  raise exception using errcode='MPT01',message='rollback consumed synthetic extra';
 exception when sqlstate 'MPT01' then return result; end;
end$$;
select is(pg_temp.mp_consumed_retry_denied(),'42501','a consumed extra cannot create a third-request allowance');
insert into _mp_results select 'before_wrong_contact',pg_temp.mp_counts();
set local role service_role;
select is(pg_temp.mp_submit(403,jsonb_set(pg_temp.mp_order(),'{customer,name}','"Different Synthetic Guest"'))->>'error',
 'ordering_unavailable','different contact is denied without creating a request');
reset role;
select is(pg_temp.mp_counts(),(select r from _mp_results where label='before_wrong_contact'),
 'wrong contact preserves requests, counters, pilots and original allowance');
update app.storefront_manual_order_pilots set enabled=false,closed_at=clock_timestamp()
 where id=pg_temp.mp_id('unused_extra');
update web_order_channel_settings set submission_enabled=false where branch_id=pg_temp.mp_branch();
insert into _mp_results select 'history',jsonb_build_object(
 'state',pg_temp.mp_counts(),
 'extra',(select to_jsonb(g) from app.storefront_manual_order_pilot_extra_allowance g));

select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('wrong_unused'),
 clock_timestamp(),clock_timestamp()+interval '10 minutes')$$,'42501',null,'retry must bind exact original extra');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp()+interval '2 minutes',clock_timestamp()+interval '12 minutes')$$,
 '42501',null,'retry cannot be installed for a distant future window');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute')$$,
 '42501',null,'already expired retry is refused');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp(),clock_timestamp()+interval '16 minutes')$$,'23514',null,'retry stays bounded to fifteen minutes');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp(),clock_timestamp()+interval '10 minutes',p_hash=>repeat('d',64))$$,
 '42501',null,'retry cannot change approved contact hash');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp(),clock_timestamp()+interval '10 minutes',p_salt=>repeat('d',64))$$,
 '42501',null,'retry cannot change approved contact salt');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),
 clock_timestamp(),clock_timestamp()+interval '10 minutes',p_pilot_expires=>clock_timestamp()+interval '11 minutes')$$,
 '42501',null,'future pilot cannot move retry deadline');
select is((select count(*)::int from app.storefront_manual_order_pilot_unused_retry),0,
 'failed bindings roll back retry and future pilot together');

create function pg_temp.mp_orphan_retry() returns void language plpgsql as $$
declare t timestamptz:=clock_timestamp();
begin
 insert into app.storefront_manual_order_pilot_unused_retry(
  pilot_id,unused_extra_pilot_id,organization_id,restaurant_id,branch_id,starts_at,expires_at,operator_reference)
 values(pg_temp.mp_id('orphan_retry'),pg_temp.mp_id('unused_extra'),pg_temp.mp_org(),pg_temp.mp_rest(),
 pg_temp.mp_branch(),t,t+interval '10 minutes','synthetic orphan retry');
 set constraints all immediate;
end$$;
select throws_ok($$select pg_temp.mp_orphan_retry()$$,'42501',null,'orphan retry cannot commit without exact future pilot');
select is((select count(*)::int from app.storefront_manual_order_pilot_unused_retry),0,'orphan refusal preserves empty retry ledger');
select throws_ok($$update app.storefront_manual_order_pilots set enabled=true,closed_at=null
 where id=pg_temp.mp_id('unused_extra')$$,'42501',null,'old unused window cannot be rearmed');

create temporary sequence mp_retry_received_hits;
select nextval('pg_temp.mp_retry_received_hits');
create function pg_temp.mp_retry_delay() returns trigger language plpgsql as $$
declare deadline timestamptz:=nullif(current_setting('test.mp_retry_expiry',true),'')::timestamptz;
begin
 if new.organization_id=pg_temp.mp_org() and deadline is not null then
  perform nextval('pg_temp.mp_retry_received_hits');
  perform pg_sleep(greatest(0,extract(epoch from deadline-clock_timestamp()))+0.03);
 end if;
 return new;
end$$;
create trigger zz_mp_retry_delay after insert on web_order_request_events
 for each row execute function pg_temp.mp_retry_delay();
create function pg_temp.mp_retry_late_case() returns jsonb language plpgsql as $$
declare deadline timestamptz; before_state jsonb; before_hits bigint; result jsonb;
begin
 begin
  deadline:=clock_timestamp()+interval '1 second';
  perform pg_temp.mp_install_retry(pg_temp.mp_id('late_retry'),pg_temp.mp_id('unused_extra'),
   clock_timestamp()-interval '1 second',deadline);
  set constraints all immediate;
  update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.mp_branch();
  before_state:=pg_temp.mp_counts();
  select last_value into before_hits from pg_temp.mp_retry_received_hits;
  perform set_config('test.mp_retry_expiry',deadline::text,true);
  result:=pg_temp.mp_submit(404);
  result:=jsonb_build_object('response',result,'delegate_reached',
   (select last_value>before_hits from pg_temp.mp_retry_received_hits),
   'all_state_unchanged',pg_temp.mp_counts()=before_state);
  raise exception using errcode='MPT01',message='rollback retry deadline fixture';
 exception when sqlstate 'MPT01' then return result; end;
end$$;
insert into _mp_results values('late_retry',pg_temp.mp_retry_late_case());
select is((select r#>>'{response,error}' from _mp_results where label='late_retry'),
 'ordering_unavailable','retry deadline crossed during writer delegation refuses submission');
select ok((select (r->>'delegate_reached')::boolean from _mp_results where label='late_retry'),
 'expiry test reaches actual received-event writer');
select ok((select (r->>'all_state_unchanged')::boolean from _mp_results where label='late_retry'),
 'late expiry rolls back request, event, counters and consumption');

create temp table _mp_retry_bounds as select clock_timestamp() t;
select pg_temp.mp_install_retry(pg_temp.mp_id('retry'),pg_temp.mp_id('unused_extra'),t,t+interval '10 minutes')
 from _mp_retry_bounds;
set constraints all immediate;
select is((select count(*)::int from app.storefront_manual_order_pilot_unused_retry),1,'one exact retry authorization is installed');
insert into _mp_results select 'retry_auth',to_jsonb(r) from app.storefront_manual_order_pilot_unused_retry r;
select throws_ok($$update app.storefront_manual_order_pilot_unused_retry set expires_at=expires_at+interval '1 minute'$$,
 '42501',null,'retry deadline is immutable');
select throws_ok($$delete from app.storefront_manual_order_pilot_unused_retry$$,'42501',null,'retry cannot be deleted to reset budget');
select throws_ok($$truncate app.storefront_manual_order_pilot_unused_retry$$,'42501',null,'retry cannot be truncated');
select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,'unbound competing pilot is denied');
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.mp_branch();
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','true','retry advertises exact real website checkout');
select is(public.storefront_menu('manual-pilot-foreign')#>>'{service,ordering_enabled}','false','other restaurant remains closed');
set local role service_role;
select is(pg_temp.mp_submit(401)->>'replayed','true','original expired identity recovers without consuming retry');
select is(pg_temp.mp_submit(405,jsonb_set(pg_temp.mp_order(),'{customer,name}','"Different Synthetic Guest"'))->>'error',
 'ordering_unavailable','retry retains exact contact rejection');
reset role;
select is((select count(*)::int from web_order_requests),1,'wrong contact and old replay create no new request');
set local role service_role;
insert into _mp_results values('retry_submit',pg_temp.mp_submit(406));
select is((select r->>'status' from _mp_results where label='retry_submit'),'pending','correct contact creates one new pending request');
select is((select r->>'replayed' from _mp_results where label='retry_submit'),'false','replacement is a genuine new identity');
select is(pg_temp.mp_submit(407)->>'error','ordering_unavailable','second new customer is denied');
select is(pg_temp.mp_submit(406)->>'replayed','true','same request/capability replay survives closure');
select is(pg_temp.mp_submit(401)->>'replayed','true','old predecessor remains recoverable after retry success');
reset role;
select is((select count(*)::int from web_order_requests),2,'total success budget stays parent plus ONE additional request');
select is((select count(*)::int from web_order_request_events),2,'only two genuine received events exist');
select ok((select not enabled and consumed_request_id is not null from app.storefront_manual_order_pilots
 where id=pg_temp.mp_id('retry')),'successful retry closes permanently');
select ok((select not submission_enabled from web_order_channel_settings where branch_id=pg_temp.mp_branch()),
 'successful retry atomically disables exact channel');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false','checkout closes after one request');
select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,'no third window or successful request can be created');
select throws_ok($$select pg_temp.mp_install_retry(pg_temp.mp_id('retry_again'),pg_temp.mp_id('unused_extra'),
 clock_timestamp(),clock_timestamp()+interval '10 minutes')$$,'42501',null,'consumed retry cannot authorize another retry');
select is((select to_jsonb(r) from app.storefront_manual_order_pilot_unused_retry r),
 (select r from _mp_results where label='retry_auth'),'retry authorization remains unchanged by submission');
select is((select to_jsonb(g) from app.storefront_manual_order_pilot_extra_allowance g),
 (select r->'extra' from _mp_results where label='history'),'original extra authorization remains byte-identical');
select is((select to_jsonb(p) from app.storefront_manual_order_pilots p where id=pg_temp.mp_id('unused_extra')),
 (select p from _mp_results r cross join lateral jsonb_array_elements(r.r#>'{state,pilots}') p
 where r.label='history' and p->>'id'=pg_temp.mp_id('unused_extra')::text),'abandoned extra pilot remains byte-identical');
select is((select to_jsonb(p) from app.storefront_manual_order_pilots p where id=(select id from _mp_parent)),
 (select p from _mp_results r cross join lateral jsonb_array_elements(r.r#>'{state,pilots}') p
 where r.label='history' and p->>'id'=(select id::text from _mp_parent)),'original consumed pilot remains byte-identical');
select is((select count(*)::int from orders),0,'retry creates no canonical order');
select is((select count(*)::int from web_order_decisions),0,'retry creates no decision');
select is((select count(*)::int from kitchen_print_dispatches),0,'retry creates no dispatch');
select is((select count(*)::int from web_order_print_attempts),0,'retry creates no print attempt');
select * from finish();
rollback;
