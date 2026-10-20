-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: rollback-only SQL security tests.
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

-- MP_FIXTURE_END: all persistent fixture rows above are synthetic and scoped.
select ok(c.relrowsecurity and c.relforcerowsecurity,'private pilot table has enabled and forced RLS')
from pg_class c where c.oid='app.storefront_manual_order_pilots'::regclass;
select ok(not has_table_privilege(role_name,'app.storefront_manual_order_pilots','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),
 role_name||' has no direct pilot-table privilege')
from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege('anon',p.oid,'EXECUTE')
 and not has_function_privilege('authenticated',p.oid,'EXECUTE')
 and has_function_privilege('service_role',p.oid,'EXECUTE')
 and not exists(select 1 from aclexplode(p.proacl) a where a.grantee=0 and a.privilege_type='EXECUTE'),
 n.nspname||' pilot submit is service-only')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('app','public') and p.proname='submit_web_order_pilot_request';
select ok(p.prosecdef=(n.nspname='app') and p.proconfig @> array['search_path=""'],
 n.nspname||' pilot submission pins search_path and the intended definer/invoker boundary')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('app','public') and p.proname='submit_web_order_pilot_request';
select ok(not has_function_privilege(role_name,'app.storefront_manual_order_pilot_open(text)','EXECUTE')
 and not has_function_privilege(role_name,'app.storefront_menu_browse_only_manual_pilot_001(text)','EXECUTE'),
 role_name||' cannot invoke private pilot hint or original reader directly')
from unnest(array['anon','authenticated','service_role']) role_name;
set local role anon;
select throws_ok($$select pg_temp.mp_submit(1)$$,'42501',null,'real anon role cannot bypass Edge via pilot RPC');
select throws_ok($$select count(*) from app.storefront_manual_order_pilots$$,'42501',null,
 'real anon role cannot inspect pilot salt/contact/consumption');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false',
 'public reader remains browse-only when pilot row is absent');
reset role;
set local role authenticated;
select throws_ok($$select pg_temp.mp_submit(1)$$,'42501',null,'real authenticated role cannot bypass Edge via pilot RPC');
reset role;
set local role service_role;
select is(pg_temp.mp_submit(1)->>'error','ordering_unavailable','absent pilot refuses real service-only submit');
reset role;

-- Scope/window CHECKs cannot be bypassed by constructing a different pilot row.
select throws_ok($$insert into app.storefront_manual_order_pilots(
 organization_id,restaurant_id,branch_id,starts_at,expires_at,contact_salt,contact_hash,operator_reference)
 values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_id('sibling'),clock_timestamp(),
 clock_timestamp()+interval '1 minute',repeat('c',64),pg_temp.mp_contact_hash(),'synthetic wrong scope')$$,
 '23514',null,'enabled same-restaurant sibling cannot be selected as pilot scope');
select throws_ok($$insert into app.storefront_manual_order_pilots(
 organization_id,restaurant_id,branch_id,starts_at,expires_at,contact_salt,contact_hash,operator_reference)
 values(pg_temp.mp_id('org_b'),pg_temp.mp_id('rest_b'),pg_temp.mp_id('branch_b'),clock_timestamp(),
 clock_timestamp()+interval '1 minute',repeat('c',64),pg_temp.mp_contact_hash(),'synthetic wrong tenant')$$,
 '23514',null,'foreign organization/restaurant/branch cannot be pilot scope');
select throws_ok($$select pg_temp.mp_insert_pilot(true,clock_timestamp(),clock_timestamp()+interval '16 minutes')$$,
 '23514',null,'pilot cannot have an admission window longer than fifteen minutes');
select throws_ok($$select pg_temp.mp_insert_pilot(true,clock_timestamp(),'infinity'::timestamptz)$$,
 '23514',null,'pilot cannot have infinite expiry');

-- Per-case subtransactions remove only synthetic fixtures. They respect the
-- immutable real table contract and keep pgTAP assertions outside rollback.
create function pg_temp.mp_closed_case(kind text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
 begin
  perform pg_temp.mp_insert_pilot(kind<>'disabled',
   case when kind='future' then clock_timestamp()+interval '1 minute' else clock_timestamp()-interval '2 minutes' end,
   case when kind='expired' then clock_timestamp()-interval '1 minute' else clock_timestamp()+interval '2 minutes' end);
  v:=jsonb_build_object('response',pg_temp.mp_submit(2),
   'ordering',public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}',
   'consumed',(select consumed_request_id is not null from app.storefront_manual_order_pilots));
  raise exception using errcode='MPT01',message='rollback synthetic pilot case';
 exception when sqlstate 'MPT01' then return v;
 end;
end$$;
insert into _mp_results select kind,pg_temp.mp_closed_case(kind)
from unnest(array['disabled','future','expired']) kind;
select ok(r#>>'{response,error}'='ordering_unavailable' and r->>'ordering'='false'
 and r->>'consumed'='false',label||' pilot closes submission and public checkout without consuming budget')
from _mp_results where label in ('disabled','future','expired') order by label;
select is((select count(*)::int from app.storefront_manual_order_pilots),0,
 'closed-case synthetic subtransactions leave no pilot rows');

-- A deterministic received-event trigger crosses the pilot deadline after the
-- unchanged delegate has inserted a request. nextval proves that execution
-- even though the guard must roll back request/event/counter mutations.
create temporary sequence mp_received_hits;
select nextval('pg_temp.mp_received_hits');
create function pg_temp.mp_delay_received() returns trigger language plpgsql as $$
declare deadline timestamptz:=nullif(current_setting('test.mp_expiry',true),'')::timestamptz;
begin
 if new.organization_id=pg_temp.mp_org() and deadline is not null then
  perform nextval('pg_temp.mp_received_hits');
  perform pg_sleep(greatest(0,extract(epoch from deadline-clock_timestamp()))+0.05);
 end if;
 return new;
end$$;
create trigger zz_mp_delay_received after insert on web_order_request_events
for each row execute function pg_temp.mp_delay_received();
create function pg_temp.mp_expiry_case() returns jsonb language plpgsql as $$
declare v jsonb; before_state jsonb; deadline timestamptz; before_hits bigint;
begin
 begin
  deadline:=clock_timestamp()+interval '1 second';
  perform pg_temp.mp_insert_pilot(true,clock_timestamp()-interval '1 second',deadline);
  before_state:=pg_temp.mp_counts();
  select last_value into before_hits from pg_temp.mp_received_hits;
  perform set_config('test.mp_expiry',deadline::text,true);
  v:=pg_temp.mp_submit(3);
  v:=jsonb_build_object('response',v,'delegate_reached',
   (select last_value>before_hits from pg_temp.mp_received_hits),
   'all_mutations_rolled_back',pg_temp.mp_counts()=before_state);
  raise exception using errcode='MPT01',message='rollback synthetic deadline case';
 exception when sqlstate 'MPT01' then return v;
 end;
end$$;
insert into _mp_results values('late_expiry',pg_temp.mp_expiry_case());
select is((select r#>>'{response,error}' from _mp_results where label='late_expiry'),
 'ordering_unavailable','deadline crossed after delegated insertion fails closed');
select is((select r->>'delegate_reached' from _mp_results where label='late_expiry'),'true',
 'deadline test actually reached the unchanged delegate received-event INSERT');
select is((select r->>'all_mutations_rolled_back' from _mp_results where label='late_expiry'),'true',
 'late expiry rolls back request, event, channel counters and pilot budget atomically');

-- Recovery must survive the deadline as well as automatic closure. A bounded
-- wait here establishes expiry itself; it is not a timing workaround for a
-- flaky assertion. This entire synthetic successful submission is rolled back.
create function pg_temp.mp_expired_replay_case() returns jsonb language plpgsql as $$
declare v jsonb; deadline timestamptz;
begin
 begin
  deadline:=clock_timestamp()+interval '1 second';
  perform pg_temp.mp_insert_pilot(true,clock_timestamp()-interval '1 second',deadline);
  v:=jsonb_build_object('first',pg_temp.mp_submit(30));
  perform pg_sleep(greatest(0,extract(epoch from deadline-clock_timestamp()))+0.05);
  v:=v||jsonb_build_object('expired',clock_timestamp()>=deadline,
   'replay',pg_temp.mp_submit(30),'second',pg_temp.mp_submit(31),
   'requests',(select count(*) from public.web_order_requests where organization_id=pg_temp.mp_org()),
   'events',(select count(*) from public.web_order_request_events where organization_id=pg_temp.mp_org()));
  raise exception using errcode='MPT01',message='rollback synthetic expired-replay case';
 exception when sqlstate 'MPT01' then return v;
 end;
end$$;
insert into _mp_results values('expired_replay',pg_temp.mp_expired_replay_case());
select ok((select r#>>'{first,status}'='pending' and r->>'expired'='true'
 and r#>>'{replay,replayed}'='true' and r#>>'{second,error}'='ordering_unavailable'
 and r->>'requests'='1' and r->>'events'='1' from _mp_results where label='expired_replay'),
 'same identity recovers after real pilot expiry without reopening admission or creating another request/event');

-- An expired, explicitly closed UNUSED window remains byte-identical when a
-- new bounded window is installed. The branch still owns only one lifetime
-- successful-request budget; a new row never resets that budget.
create temp table _mp_prior_window as select pg_temp.mp_insert_pilot(false,
 clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute') id;
update app.storefront_manual_order_pilots set closed_at=clock_timestamp()
where id=(select id from _mp_prior_window);
insert into _mp_results select 'prior_window_snapshot',to_jsonb(p)
from app.storefront_manual_order_pilots p where id=(select id from _mp_prior_window);
create temp table _mp_window_bounds as select clock_timestamp() t;
create temp table _mp_current_window as select pg_temp.mp_insert_pilot(true,t,t+interval '15 minutes') id
from _mp_window_bounds;
select is((select count(*)::int from app.storefront_manual_order_pilots),2,
 'expired unused window permits one fresh bounded window without replacing history');
select is((select to_jsonb(p) from app.storefront_manual_order_pilots p where id=(select id from _mp_prior_window)),
 (select r from _mp_results where label='prior_window_snapshot'),
 'renewal leaves the full old window row byte-identical');
select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,
 'a second enabled window cannot coexist with the renewed window');
select throws_ok($$update app.storefront_manual_order_pilots set enabled=true
 where id=(select id from _mp_prior_window)$$,'42501',null,
 'renewal does not rearm the expired historical window');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','true',
 'exact open/pickup/BLOCKED scope with unconsumed active pilot advertises checkout');
select is(public.storefront_menu('manual-pilot-foreign')#>>'{service,ordering_enabled}','false',
 'another published restaurant remains browse-only');
select is(public.storefront_menu('mapsburger')-'server_ts',
 jsonb_set(app.storefront_menu_browse_only_manual_pilot_001('mapsburger'),
 '{service,ordering_enabled}','true')-'server_ts',
 'pilot reader preserves every existing public field and changes only the ordering boolean');
select ok(not (public.storefront_menu('mapsburger')::text like '%'||repeat('c',64)||'%')
 and not (public.storefront_menu('mapsburger')::text like '%'||pg_temp.mp_contact_hash()||'%')
 and not (public.storefront_menu('mapsburger')::text like '%'||pg_temp.mp_org()::text||'%')
 and not (public.storefront_menu('mapsburger')::text like '%'||pg_temp.mp_branch()::text||'%'),
 'reader exposes no pilot salt/hash or private tenant/branch identifiers');
insert into _mp_results values('before_invalid',pg_temp.mp_counts());
set local role service_role;
select is(pg_temp.mp_submit(4,p_slug=>'manual-pilot-foreign')->>'error','ordering_unavailable',
 'wrong slug cannot select the active exact-scope pilot');
select is(pg_temp.mp_submit(4,jsonb_set(pg_temp.mp_order(),'{customer,name}','"Other Synthetic Guest"'))->>'error',
 'ordering_unavailable','wrong approved customer name cannot consume the single slot');
select is(pg_temp.mp_submit(4,jsonb_set(pg_temp.mp_order(),'{customer,phone}','"+972520000999"'))->>'error',
 'ordering_unavailable','wrong approved customer phone cannot consume the single slot');
select is(pg_temp.mp_submit(4,jsonb_set(pg_temp.mp_order(),'{order_type}','"delivery"'))->>'error',
 'ordering_unavailable','pilot permits Pickup only');
reset role;
select is(pg_temp.mp_counts(),(select r from _mp_results where label='before_invalid'),
 'scope/contact/type refusals leave pilot, requests, events, channel and order/print state unchanged');

-- Preserve ordinary price authority and validation while keeping the slot free.
set local role service_role;
select is(pg_temp.mp_submit(4,jsonb_set(pg_temp.mp_order(),'{items,0,unit_price_minor}','0'))->>'error',
 'invalid_request','customer-supplied prices remain invalid');
select is(pg_temp.mp_submit(4,jsonb_set(pg_temp.mp_order(),'{items,0,modifiers,0,quantity}','4'))->>'error',
 'modifier_selection_invalid','authoritative modifier quantity bound remains enforced');
select is(pg_temp.mp_submit(4,jsonb_set(pg_temp.mp_order(),'{items,0,menu_item_id}',
 to_jsonb(pg_temp.mp_id('item_b')::text)))->>'error','item_unavailable','cross-tenant item cannot be purchased');
reset role;
select ok((select enabled and consumed_request_id is null and consumed_at is null
 from app.storefront_manual_order_pilots where id=(select id from _mp_current_window)),
 'pricing/validation failures leave the one-request pilot budget unconsumed');
select is((select count(*)::int from web_order_requests where organization_id=pg_temp.mp_org()),0,
 'failed pricing creates no pending request');

update restaurant_storefront_profiles set paused_until=clock_timestamp()+interval '5 minutes'
where restaurant_id=pg_temp.mp_rest();
set local role service_role;
select is(pg_temp.mp_submit(4)->>'error','ordering_unavailable','closed service refuses submission despite active pilot');
reset role;
update restaurant_storefront_profiles set paused_until=null,pickup_enabled=false where restaurant_id=pg_temp.mp_rest();
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false','pickup-off also closes public pilot hint');
set local role service_role;
select is(pg_temp.mp_submit(4)->>'error','ordering_unavailable','pickup-off refuses submission');
reset role;
update restaurant_storefront_profiles set pickup_enabled=true where restaurant_id=pg_temp.mp_rest();
update web_order_channel_settings set submission_enabled=false where branch_id=pg_temp.mp_branch();
set local role service_role;
select is(pg_temp.mp_submit(4)->>'error','ordering_unavailable','pilot cannot bypass disabled independent channel');
reset role;
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.mp_branch();
update restaurant_storefront_profiles set storefront_branch_id=pg_temp.mp_id('sibling')
where restaurant_id=pg_temp.mp_rest();
set local role service_role;
select is(pg_temp.mp_submit(4)->>'error','ordering_unavailable','profile moved to sibling branch fails exact authoritative scope');
reset role;
update restaurant_storefront_profiles set storefront_branch_id=pg_temp.mp_branch() where restaurant_id=pg_temp.mp_rest();
insert into kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),'ordinary',
 'Synthetic negative test only; no printing','manual-pilot-001-synthetic');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false',
 'pilot refuses to advertise checkout outside BLOCKED containment');
set local role service_role;
select is(pg_temp.mp_submit(4)->>'error','ordering_unavailable','ordinary containment cannot authorize manual pilot submission');
reset role;
insert into kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),'blocked',
 'Synthetic restored test condition; no printing','manual-pilot-001-synthetic');

set local role service_role;
insert into _mp_results values('success',pg_temp.mp_submit(5));
select is((select r->>'status' from _mp_results where label='success'),'pending','one authorized browser identity creates pending only');
select is((select r->>'replayed' from _mp_results where label='success'),'false','first authorized request is a new request');
select is((select r#>>'{totals,subtotal_minor}' from _mp_results where label='success'),'2500',
 'database prices quantity two with two authoritative 125-minor modifiers per item');
select is((select r#>>'{totals,tax_total_minor}' from _mp_results where label='success'),'450','authoritative 18-percent tax is retained');
select is((select r#>>'{totals,grand_total_minor}' from _mp_results where label='success'),'2950','authoritative grand total is retained');
reset role;
select ok((select not enabled and consumed_client_request_id=pg_temp.mp_client(5)
 and consumed_request_id=(select id from web_order_requests where client_request_id=pg_temp.mp_client(5))
 and consumed_at is not null and closed_at=consumed_at from app.storefront_manual_order_pilots
 where id=(select id from _mp_current_window)),
 'success atomically consumes the exact request identity and permanently closes the pilot');
select ok((select not submission_enabled from web_order_channel_settings where branch_id=pg_temp.mp_branch()),
 'same successful transaction disables the scoped channel');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false','consumed pilot stops advertising new checkout');
select is((select count(*)::int from web_order_request_events where organization_id=pg_temp.mp_org()),1,
 'one new request has exactly one received event');
select is((select priced_items->0->>'notes' from web_order_requests where client_request_id=pg_temp.mp_client(5)),
 'Synthetic line note','authoritative pending snapshot preserves the item note');
select is((select notes from web_order_requests where client_request_id=pg_temp.mp_client(5)),
 'Synthetic manual Pickup test','order note remains separate');

set local role service_role;
select is(pg_temp.mp_submit(6)->>'error','ordering_unavailable','second distinct UUID cannot consume a second request slot');
select is(pg_temp.mp_submit(5)->>'replayed','true','exact original replay survives disabled pilot and channel');
select is(pg_temp.mp_submit(5,p_token=>repeat('b',64))->>'error','idempotency_conflict','changed replay capability fails closed');
select is(pg_temp.mp_submit(5,jsonb_set(pg_temp.mp_order(),'{notes}','"Changed synthetic note"'))->>'error',
 'idempotency_conflict','changed replay payload fails closed');
select is(public.get_web_order_request_status('mapsburger',pg_temp.mp_client(5),repeat('a',64))->>'status',
 'pending','ordinary capability status remains available after pilot closes');
reset role;
select is((select count(*)::int from web_order_requests where organization_id=pg_temp.mp_org()),1,
 'replay/conflict/second-UUID attempts leave exactly one request');
select is((select count(*)::int from web_order_request_events where organization_id=pg_temp.mp_org()),1,
 'recovery never creates a second received event');
select is((select count(*)::int from app.storefront_manual_order_pilots where consumed_request_id is not null),1,
 'one successful request total is recorded across every historical and current window');
select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,
 'a consumed branch budget cannot be renewed even when every window is closed');
select is((select to_jsonb(p) from app.storefront_manual_order_pilots p where id=(select id from _mp_prior_window)),
 (select r from _mp_results where label='prior_window_snapshot'),
 'success, replay and refused renewal preserve the full expired historical row');
select throws_ok($$update app.storefront_manual_order_pilots set enabled=true$$,'42501',null,
 'operator cannot reopen a disabled/consumed pilot slot');
select throws_ok($$update app.storefront_manual_order_pilots set consumed_client_request_id=pg_temp.mp_client(99)
 where id=(select id from _mp_current_window)$$,
 '42501',null,'consumed client identity is immutable');
select throws_ok($$update app.storefront_manual_order_pilots set expires_at=expires_at+interval '1 minute'$$,
 '42501',null,'operator cannot silently extend an installed pilot window');
select throws_ok($$update app.storefront_manual_order_pilots set contact_hash=repeat('d',64)$$,
 '42501',null,'approved contact binding is immutable');
select throws_ok($$delete from app.storefront_manual_order_pilots$$,'42501',null,'pilot audit cannot be deleted');
select throws_ok($$truncate app.storefront_manual_order_pilots$$,'42501',null,'pilot audit cannot be truncated');
select ok((select not ordering_enabled and not delivery_enabled from restaurant_storefront_profiles
 where restaurant_id=pg_temp.mp_rest()),'stored profile ordering/delivery CHECK remains intact');
select is((select count(*)::int from orders where organization_id=pg_temp.mp_org()),0,'pilot never creates a canonical order');
select is((select count(*)::int from web_order_decisions where organization_id=pg_temp.mp_org()),0,'pilot never accepts or rejects a request');
select is((select count(*)::int from kitchen_print_dispatches where organization_id=pg_temp.mp_org()),0,'pilot never creates a print dispatch');
select is((select count(*)::int from web_order_print_attempts where organization_id=pg_temp.mp_org()),0,'pilot never enrolls or claims a print attempt');

select * from finish();
rollback;
