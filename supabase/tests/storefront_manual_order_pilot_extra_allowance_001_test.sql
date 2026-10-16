-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: one additional expired-request allowance.
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
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
values(pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),true);
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

select ok(c.relrowsecurity and c.relforcerowsecurity,
 'additional allowance has enabled and forced RLS') from pg_class c
 where c.oid='app.storefront_manual_order_pilot_extra_allowance'::regclass;
select ok(not has_table_privilege(role_name,'app.storefront_manual_order_pilot_extra_allowance',
 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),role_name||' has no additional-allowance table access')
 from unnest(array['anon','authenticated','service_role']) role_name;
select ok(not has_function_privilege(role_name,
 'app.manual_order_pilot_extra_allowed(app.storefront_manual_order_pilots,timestamptz)','EXECUTE'),
 role_name||' cannot invoke private additional-authorization predicate')
 from unnest(array['anon','authenticated','service_role']) role_name;
select is((select count(*)::int from app.storefront_manual_order_pilot_extra_allowance),0,
 'migration installs no additional allowance or activation');
set local role service_role;
select throws_ok($$select count(*) from app.storefront_manual_order_pilot_extra_allowance$$,
 '42501',null,'actual service role cannot inspect or mint an allowance');
reset role;

-- An unexpired pending request must not be displaced by a new authorization.
create function pg_temp.mp_live_parent_denied() returns text language plpgsql as $$
declare p uuid; r uuid; t timestamptz; result text;
begin
 begin
  p:=pg_temp.mp_insert_pilot();
  perform pg_temp.mp_submit(10);
  select consumed_request_id into r from app.storefront_manual_order_pilots where id=p;
  t:=clock_timestamp();
  begin
   perform pg_temp.mp_install_extra(pg_temp.mp_id('extra'),p,r,t,t+interval '10 minutes');
   result:='unexpected_success';
  exception when insufficient_privilege then result:='42501'; end;
  raise exception using errcode='MPT01',message='rollback synthetic live predecessor';
 exception when sqlstate 'MPT01' then return result; end;
end$$;
select is(pg_temp.mp_live_parent_denied(),'42501',
 'an unexpired predecessor cannot authorize a replacement');
select is((select count(*)::int from web_order_requests),0,
 'negative predecessor case leaves no committed synthetic request');

select set_config('test.mp_backdate_parent','true',true);
create temp table _mp_parent as select pg_temp.mp_insert_pilot() id;
insert into _mp_results values('parent_submit',pg_temp.mp_submit(11));
select set_config('test.mp_backdate_parent','false',true);
select ok((select r->>'ok'='true' and r->>'replayed'='false' from _mp_results where label='parent_submit'),
 'expired synthetic predecessor uses real submission/price/idempotency orchestration');
create temp table _mp_parent_request as select w.id from web_order_requests w
 join app.storefront_manual_order_pilots p on p.consumed_request_id=w.id
 where p.id=(select id from _mp_parent);
select ok((select expires_at<=clock_timestamp() and canonical_order_id is null
 from web_order_requests where id=(select id from _mp_parent_request)),
 'predecessor is expired without canonical mapping');
insert into _mp_results select 'parent_pilot_snapshot',to_jsonb(p)
 from app.storefront_manual_order_pilots p where id=(select id from _mp_parent);
insert into _mp_results select 'parent_request_snapshot',to_jsonb(w)
 from web_order_requests w where id=(select id from _mp_parent_request);

select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,
 'expired consumption alone does not automatically reset or renew the budget');
select throws_ok($$select pg_temp.mp_install_extra(pg_temp.mp_id('extra'),
 (select id from _mp_parent),pg_temp.mp_id('wrong_request'),clock_timestamp(),
 clock_timestamp()+interval '10 minutes')$$,'42501',null,
 'wrong predecessor request cannot mint an allowance');
select throws_ok($$select pg_temp.mp_install_extra(pg_temp.mp_id('extra'),
 (select id from _mp_parent),(select id from _mp_parent_request),clock_timestamp()+interval '2 minutes',
 clock_timestamp()+interval '12 minutes')$$,'42501',null,
 'operator cannot install a distant future authorization');
select throws_ok($$select pg_temp.mp_install_extra(pg_temp.mp_id('extra'),
 (select id from _mp_parent),(select id from _mp_parent_request),clock_timestamp(),
 clock_timestamp()+interval '16 minutes')$$,'23514',null,
 'additional authorization remains bounded to fifteen minutes');
select throws_ok($$select pg_temp.mp_install_extra(pg_temp.mp_id('extra'),
 (select id from _mp_parent),(select id from _mp_parent_request),clock_timestamp(),
 clock_timestamp()+interval '10 minutes',clock_timestamp()+interval '11 minutes')$$,
 '42501',null,'a future pilot cannot change its authorized deadline');
select is((select count(*)::int from app.storefront_manual_order_pilot_extra_allowance),0,
 'failed installations roll back authorization and pilot together');

-- Force the deferred check without committing any synthetic fixture.
create function pg_temp.mp_orphan_authorization() returns void language plpgsql as $$
declare t timestamptz:=clock_timestamp();
begin
 insert into app.storefront_manual_order_pilot_extra_allowance(
  pilot_id,previous_pilot_id,previous_request_id,organization_id,restaurant_id,branch_id,
  starts_at,expires_at,operator_reference)
 values(pg_temp.mp_id('missing_future_pilot'),(select id from _mp_parent),
  (select id from _mp_parent_request),pg_temp.mp_org(),pg_temp.mp_rest(),pg_temp.mp_branch(),
  t,t+interval '10 minutes','synthetic orphan must roll back');
 set constraints all immediate;
end$$;
select throws_ok($$select pg_temp.mp_orphan_authorization()$$,'42501',null,
 'deferred commit check refuses authorization without its exact future pilot');
select is((select count(*)::int from app.storefront_manual_order_pilot_extra_allowance),0,
 'orphan refusal rolls back the authorization row');

create temporary sequence mp_extra_received_hits;
select nextval('pg_temp.mp_extra_received_hits');
create function pg_temp.mp_extra_delay_received() returns trigger language plpgsql as $$
declare deadline timestamptz:=nullif(current_setting('test.mp_extra_expiry',true),'')::timestamptz;
begin
 if new.organization_id=pg_temp.mp_org() and deadline is not null then
  perform nextval('pg_temp.mp_extra_received_hits');
  perform pg_sleep(greatest(0,extract(epoch from deadline-clock_timestamp()))+0.03);
 end if;
 return new;
end$$;
create trigger zz_mp_extra_delay_received after insert on web_order_request_events
 for each row execute function pg_temp.mp_extra_delay_received();
create function pg_temp.mp_extra_late_case() returns jsonb language plpgsql as $$
declare t timestamptz; deadline timestamptz; before_state jsonb;
 before_auth jsonb; before_hits bigint; result jsonb;
begin
 begin
  t:=clock_timestamp()-interval '1 second'; deadline:=clock_timestamp()+interval '1 second';
  perform pg_temp.mp_install_extra(pg_temp.mp_id('extra_late'),(select id from _mp_parent),
   (select id from _mp_parent_request),t,deadline);
  update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.mp_branch();
  before_state:=pg_temp.mp_counts();
  select to_jsonb(g) into before_auth from app.storefront_manual_order_pilot_extra_allowance g;
  select last_value into before_hits from pg_temp.mp_extra_received_hits;
  perform set_config('test.mp_extra_expiry',deadline::text,true);
  result:=pg_temp.mp_submit(22);
  result:=jsonb_build_object('response',result,
   'delegate_reached',(select last_value>before_hits from pg_temp.mp_extra_received_hits),
   'all_state_unchanged',pg_temp.mp_counts()=before_state,
   'authorization_unchanged',(select to_jsonb(g)=before_auth from app.storefront_manual_order_pilot_extra_allowance g));
  raise exception using errcode='MPT01',message='rollback synthetic extra expiry case';
 exception when sqlstate 'MPT01' then return result; end;
end$$;
insert into _mp_results values('extra_late',pg_temp.mp_extra_late_case());
select is((select r#>>'{response,error}' from _mp_results where label='extra_late'),
 'ordering_unavailable','additional deadline crossed during delegation refuses submission');
select ok((select (r->>'delegate_reached')::boolean from _mp_results where label='extra_late'),
 'additional expiry test proves real received-event insertion was reached');
select ok((select (r->>'all_state_unchanged')::boolean and (r->>'authorization_unchanged')::boolean
 from _mp_results where label='extra_late'),
 'additional late expiry rolls back request/event/counter/consumption mutations and preserves authorization');

create temp table _mp_extra_bounds as select clock_timestamp() t;
select pg_temp.mp_install_extra(pg_temp.mp_id('extra'),(select id from _mp_parent),
 (select id from _mp_parent_request),t,t+interval '10 minutes') from _mp_extra_bounds;
set constraints all immediate;
select is((select count(*)::int from app.storefront_manual_order_pilot_extra_allowance),1,
 'one exact append-only additional allowance is installed');
select throws_ok($$update app.storefront_manual_order_pilot_extra_allowance
 set expires_at=expires_at+interval '1 minute'$$,'42501',null,
 'operator cannot extend or rewrite additional authorization');
select throws_ok($$delete from app.storefront_manual_order_pilot_extra_allowance$$,
 '42501',null,'operator cannot delete the extra allowance to reset its budget');
select throws_ok($$truncate app.storefront_manual_order_pilot_extra_allowance$$,
 '42501',null,'operator cannot truncate the extra allowance');
select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,
 'unbound competing pilot cannot use the extra allowance');
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.mp_branch();
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','true',
 'only exact enabled additional pilot advertises real website checkout');
select is(public.storefront_menu('manual-pilot-foreign')#>>'{service,ordering_enabled}','false',
 'additional allowance does not open any other restaurant');
insert into _mp_results select 'before_replay',pg_temp.mp_counts();
set local role service_role;
select is(pg_temp.mp_submit(11)->>'replayed','true',
 'exact predecessor replay remains available while a new allowance is open');
select is(pg_temp.mp_submit(11,p_token=>repeat('b',64))->>'error','idempotency_conflict',
 'wrong historical capability cannot consume the new allowance');
reset role;
-- The existing delegate charges OPEN-channel replay attempts to its bounded
-- abuse counter. Preserve that contract; only identity/budget/received-event
-- state must remain unchanged (not the legitimate attempt counter/timestamp).
select is(pg_temp.mp_counts() #- '{channel,updated_at}' #- '{channel,submit_attempt_count}',
 (select r #- '{channel,updated_at}' #- '{channel,submit_attempt_count}'
 from _mp_results where label='before_replay'),
 'old replay preserves old evidence and the new allowance/channel admission state');
select is((select submit_attempt_count::int from web_order_channel_settings where branch_id=pg_temp.mp_branch()),
 (select (r#>>'{channel,submit_attempt_count}')::int+2 from _mp_results where label='before_replay'),
 'both old replay attempts retain existing OPEN-channel abuse accounting');
set local role service_role;
insert into _mp_results values('extra_submit',pg_temp.mp_submit(12));
select is((select r->>'status' from _mp_results where label='extra_submit'),'pending',
 'one new browser request is accepted only into pending state');
select is((select r->>'replayed' from _mp_results where label='extra_submit'),'false',
 'new authorized identity creates exactly one additional request');
select is(pg_temp.mp_submit(13)->>'error','ordering_unavailable',
 'third distinct browser identity is refused');
select is(pg_temp.mp_submit(12)->>'replayed','true',
 'exact new replay survives atomic pilot/channel closure');
select is(pg_temp.mp_submit(11)->>'replayed','true',
 'exact old replay still resolves the old request after new consumption');
reset role;
select is((select count(*)::int from web_order_requests),2,
 'exactly two preserved requests total: old expired and one new pending');
select is((select count(*)::int from web_order_request_events),2,
 'one received event per genuine request with no duplicate replay events');
select ok((select not enabled and consumed_client_request_id=pg_temp.mp_client(12)
 from app.storefront_manual_order_pilots where id=pg_temp.mp_id('extra')),
 'additional pilot is permanently closed and bound to the genuine new identity');
select ok((select not submission_enabled from web_order_channel_settings where branch_id=pg_temp.mp_branch()),
 'new successful request atomically closes the exact submission channel');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false',
 'website stops advertising admission after the single additional request');
select throws_ok($$select pg_temp.mp_insert_pilot()$$,'42501',null,
 'consumed additional allowance cannot be recycled into a third window');
select is((select to_jsonb(p) from app.storefront_manual_order_pilots p where id=(select id from _mp_parent)),
 (select r from _mp_results where label='parent_pilot_snapshot'),'old consumed pilot remains byte-identical');
select is((select to_jsonb(w) from web_order_requests w where id=(select id from _mp_parent_request)),
 (select r from _mp_results where label='parent_request_snapshot'),'old expired request remains byte-identical');
select is((select count(*)::int from orders),0,'additional allowance creates no canonical order');
select is((select count(*)::int from web_order_decisions),0,'additional allowance creates no decision');
select is((select count(*)::int from kitchen_print_dispatches),0,'additional allowance creates no dispatch');
select is((select count(*)::int from web_order_print_attempts),0,'additional allowance creates no print attempt');
select * from finish();
rollback;
