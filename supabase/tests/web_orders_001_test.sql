-- WEB-ORDERS-001: pending website requests, authoritative catalogue pricing,
-- private polling, fail-closed channel gates, quotas, and no operational order.
-- Synthetic fixtures only. Real SQL roles exercise privileges. No hosted calls.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';
select no_plan();

create temp table _wo_ids(label text primary key, id uuid not null);
insert into _wo_ids
select label, md5('web-orders-001-test-' || label)::uuid
from unnest(array['org_a','org_b','rest_a','rest_b','branch_a','branch_sibling',
 'branch_b','category_a','category_b','item_a','item_plain','item_multiple',
 'item_sibling','item_dead','item_b','single','extras','required_multiple',
 'wrong_item_group','sibling_group','foreign_group','classic','double',
 'cheese','sauce','onion','negative','dead_option','tombstoned_option',
 'sibling_option','sibling_group_option','wrong_item_option','foreign_option',
 'multiple_one','multiple_two']) label;
grant select on _wo_ids to anon, authenticated, service_role;
create function pg_temp.wo_ref(p_label text) returns uuid
language sql stable as $$select id from _wo_ids where label=p_label$$;
create function pg_temp.wo_client(p_n integer) returns uuid
language sql immutable as $$select ('10000000-0000-4000-8000-' || lpad(p_n::text,12,'0'))::uuid$$;
create function pg_temp.wo_option(p_label text, p_quantity integer default 1) returns jsonb
language sql stable as $$select jsonb_build_object('modifier_option_id',pg_temp.wo_ref(p_label),'quantity',p_quantity)$$;
create function pg_temp.wo_order(
 p_item text default 'item_a', p_quantity integer default 1,
 p_modifiers jsonb default null, p_phone text default '+972520000001') returns jsonb
language sql stable as $$
 select jsonb_build_object('order_type','takeaway',
  'customer',jsonb_build_object('name','Synthetic Website Guest','phone',p_phone),
  'notes','', 'items',jsonb_build_array(jsonb_build_object(
   'menu_item_id',pg_temp.wo_ref(p_item),'quantity',p_quantity,
   'modifiers',coalesce(p_modifiers,case when p_item='item_a'
    then jsonb_build_array(pg_temp.wo_option('classic')) else '[]'::jsonb end))))
$$;
create function pg_temp.wo_submit(p_order jsonb, p_n integer default 900,
 p_slug text default 'wo001-alpha', p_token text default repeat('a',64)) returns jsonb
language sql volatile as $$
 select public.submit_web_order_request(p_slug,pg_temp.wo_client(p_n),p_token,p_order)
$$;
create function pg_temp.wo_refused(p_order jsonb, p_description text) returns text
language sql volatile as $$
 select extensions.is(pg_temp.wo_submit(p_order)->>'ok','false',p_description)
$$;
create temp table _wo_results(label text primary key,r jsonb not null);
grant all on _wo_results to service_role;
create temp table _wo_before as select
 (select count(*) from orders) orders,
 (select count(*) from order_items) order_items,
 (select count(*) from order_item_modifiers) order_item_modifiers,
 (select count(*) from order_service_rounds) service_rounds,
 (select count(*) from kitchen_print_dispatches) dispatches,
 (select count(*) from payments) payments,
 (select count(*) from app_users) app_users;

insert into organizations(id,name,slug,default_currency,status) values
 (pg_temp.wo_ref('org_a'),'WO001 Synthetic A','wo001-org-a','ILS','active'),
 (pg_temp.wo_ref('org_b'),'WO001 Synthetic B','wo001-org-b','ILS','active');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('org_a'),'WO001 A','UTC'),
 (pg_temp.wo_ref('rest_b'),pg_temp.wo_ref('org_b'),'WO001 B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_rate_bp,tax_mode) values
 (pg_temp.wo_ref('branch_a'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),'A','UTC',true,1800,'exclusive'),
 (pg_temp.wo_ref('branch_sibling'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),'Sibling','UTC',true,1800,'exclusive'),
 (pg_temp.wo_ref('branch_b'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('rest_b'),'B','UTC',false,0,'exclusive');
insert into menu_categories(id,organization_id,restaurant_id,name) values
 (pg_temp.wo_ref('category_a'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),'WO001 Food A'),
 (pg_temp.wo_ref('category_b'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('rest_b'),'WO001 Food B');
insert into menu_items(id,organization_id,restaurant_id,branch_id,menu_category_id,name,base_price_minor,currency_code,is_active)
select pg_temp.wo_ref(label),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),
 case when label='item_sibling' then pg_temp.wo_ref('branch_sibling') end,
 pg_temp.wo_ref('category_a'),'WO001 '||label,1001,'ILS',label<>'item_dead'
from unnest(array['item_a','item_plain','item_multiple','item_sibling','item_dead']) label;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code) values
 (pg_temp.wo_ref('item_b'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('rest_b'),pg_temp.wo_ref('category_b'),'WO001 Foreign',1001,'ILS');
insert into modifiers(id,organization_id,restaurant_id,branch_id,menu_item_id,name,selection_type,min_select,max_select,is_required,allow_quantity,max_quantity) values
 (pg_temp.wo_ref('single'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),null,pg_temp.wo_ref('item_a'),'WO001 Choice','single',1,1,true,false,null),
 (pg_temp.wo_ref('extras'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),null,pg_temp.wo_ref('item_a'),'WO001 Extras','multiple',0,2,false,true,3),
 (pg_temp.wo_ref('required_multiple'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),null,pg_temp.wo_ref('item_multiple'),'WO001 Required','multiple',2,2,true,true,3),
 (pg_temp.wo_ref('wrong_item_group'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),null,pg_temp.wo_ref('item_plain'),'WO001 Other item','multiple',0,2,false,false,null),
 (pg_temp.wo_ref('sibling_group'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('branch_sibling'),pg_temp.wo_ref('item_a'),'WO001 Sibling','multiple',0,2,false,false,null),
 (pg_temp.wo_ref('foreign_group'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('rest_b'),null,pg_temp.wo_ref('item_b'),'WO001 Foreign','multiple',0,2,false,false,null);
insert into modifier_options(id,organization_id,restaurant_id,branch_id,modifier_id,name,price_delta_minor,is_active,deleted_at)
select pg_temp.wo_ref(label),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),
 case when label='sibling_option' then pg_temp.wo_ref('branch_sibling') end,
 pg_temp.wo_ref(case
  when label in ('classic','double','negative','dead_option','tombstoned_option','sibling_option') then 'single'
  when label='wrong_item_option' then 'wrong_item_group'
  when label='sibling_group_option' then 'sibling_group'
  when label in ('multiple_one','multiple_two') then 'required_multiple' else 'extras' end),
 'WO001 '||label,
 case when label='negative' then -1 when label='classic' then 0 else 199 end,
 label<>'dead_option',case when label='tombstoned_option' then now() end
from unnest(array['classic','double','cheese','sauce','onion','negative','dead_option',
 'tombstoned_option','sibling_option','wrong_item_option','sibling_group_option','multiple_one','multiple_two']) label;
insert into modifier_options(id,organization_id,restaurant_id,modifier_id,name,price_delta_minor) values
 (pg_temp.wo_ref('foreign_option'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('rest_b'),pg_temp.wo_ref('foreign_group'),'WO001 Foreign option',199);
create temp table _wo_hours as
select jsonb_build_object('weekly',
 (select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c))
  from generate_series(0,6) d cross join (values('00:00','12:00'),('11:00','00:00')) w(o,c)),
 'exceptions','[]'::jsonb) always_open;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('branch_a'),'wo001-alpha','WO001 Alpha',true,always_open,true from _wo_hours;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.wo_ref('rest_b'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('branch_b'),'wo001-bravo','WO001 Bravo',true,always_open,true from _wo_hours;

-- The browser has no capability to submit or read stored requests directly.
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order(),1,'wo001-alpha'),
 pg_temp.wo_submit(pg_temp.wo_order(),1,'wo001-unknown'),
 'unpublished slug without channel is indistinguishable from unknown slug');
select is(pg_temp.wo_submit(pg_temp.wo_order(),1)->>'error','not_found',
 'unpublished slug is not_found before channel existence is disclosed');
reset role;
update restaurant_storefront_profiles set is_published=true where restaurant_id=pg_temp.wo_ref('rest_a');
select is((select count(*)::int from pg_proc where pronamespace='public'::regnamespace
 and proname='submit_web_order_request'),1,'submit has exactly one public overload');
select is((select count(*)::int from pg_proc where pronamespace='public'::regnamespace
 and proname='get_web_order_request_status'),1,'status has exactly one public overload');
select ok((select not prosecdef from pg_proc where oid='public.submit_web_order_request(text,uuid,text,jsonb)'::regprocedure),
 'public submit is SECURITY INVOKER');
select ok((select not prosecdef from pg_proc where oid='public.get_web_order_request_status(text,uuid,text)'::regprocedure),
 'public status is SECURITY INVOKER');
select ok(has_function_privilege('service_role','public.submit_web_order_request(text,uuid,text,jsonb)','EXECUTE')
 and has_function_privilege('service_role','public.get_web_order_request_status(text,uuid,text)','EXECUTE'),
 'backend service_role can invoke both wrappers');
select ok(not has_function_privilege(r,fn,'EXECUTE'),r||' cannot execute '||fn)
from unnest(array['anon','authenticated']) r
cross join unnest(array['public.submit_web_order_request(text,uuid,text,jsonb)',
 'public.get_web_order_request_status(text,uuid,text)']) fn;
select ok(not has_table_privilege(r,'public.'||t,'SELECT')
 and not has_table_privilege(r,'public.'||t,'INSERT')
 and not has_table_privilege(r,'public.'||t,'UPDATE')
 and not has_table_privilege(r,'public.'||t,'DELETE'),r||' has no direct access to '||t)
from unnest(array['anon','authenticated']) r
cross join unnest(array['web_order_channel_settings','web_order_requests','web_order_request_events']) t;
select ok(relrowsecurity and relforcerowsecurity,relname||' has enabled and forced RLS')
from pg_class where oid in ('public.web_order_channel_settings'::regclass,
 'public.web_order_requests'::regclass,'public.web_order_request_events'::regclass);
-- RF059 policy coverage requires explicit command policies on tenant tables.
select is((select array_agg(cmd order by cmd)::text[] from pg_policies
 where schemaname='public' and tablename=t),array['DELETE','INSERT','SELECT','UPDATE']::text[],
 t||' has exactly one policy per command')
from unnest(array['web_order_channel_settings','web_order_requests','web_order_request_events']) t;
select is((select count(*)::int from pg_policies
 where schemaname='public' and tablename=t and cmd='ALL'),0,t||' has no FOR ALL policy')
from unnest(array['web_order_channel_settings','web_order_requests','web_order_request_events']) t;
set local role anon;
select throws_ok($$select public.submit_web_order_request('wo001-alpha',pg_temp.wo_client(1),repeat('a',64),pg_temp.wo_order())$$,
 '42501',null,'real anon cannot submit');
select throws_ok($$select public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('a',64))$$,
 '42501',null,'real anon cannot poll');
select throws_ok($$select * from public.web_order_requests$$,'42501',null,'real anon cannot read requests');
select is(public.storefront_menu('wo001-alpha')->'service'->>'ordering_enabled','true',
 'published platform storefront advertises authoritative ordering');
reset role;
set local role authenticated;
select throws_ok($$select public.submit_web_order_request('wo001-alpha',pg_temp.wo_client(1),repeat('a',64),pg_temp.wo_order())$$,
 '42501',null,'real authenticated cannot submit');
select throws_ok($$select public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('a',64))$$,
 '42501',null,'real authenticated cannot poll');
select throws_ok($$select * from public.web_order_requests$$,'42501',null,'real authenticated cannot read requests');
reset role;

delete from web_order_channel_settings where organization_id=pg_temp.wo_ref('org_a');
select is((select count(*)::int from web_order_channel_settings where organization_id=pg_temp.wo_ref('org_a')),0,
 'synthetic missing-channel fixture removes automatic onboarding configuration');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order(),1)->>'ok','false','missing channel settings fail closed');
reset role;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id)
values(pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('branch_a')) on conflict(branch_id) do update set submission_enabled=excluded.submission_enabled;
select is((select submission_enabled from web_order_channel_settings where branch_id=pg_temp.wo_ref('branch_a')),false,
 'explicit channel defaults to disabled');
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order(),1,'wo001-alpha'),
 pg_temp.wo_submit(pg_temp.wo_order(),1,'wo001-unknown'),
 'unpublished slug with disabled channel is indistinguishable from unknown slug');
reset role;
update restaurant_storefront_profiles set is_published=true where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order(),1)->>'ok','false','disabled channel refuses submission');
reset role;
select throws_ok($$insert into web_order_channel_settings(organization_id,restaurant_id,branch_id)
 values(pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('branch_b'))
 on conflict(branch_id) do update set organization_id=excluded.organization_id,restaurant_id=excluded.restaurant_id$$,
 '23503',null,'composite FK refuses another tenant branch');
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.wo_ref('branch_a');
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
values(pg_temp.wo_ref('org_b'),pg_temp.wo_ref('rest_b'),pg_temp.wo_ref('branch_b'),true) on conflict(branch_id) do update set submission_enabled=excluded.submission_enabled;
set local role anon;
select is(public.storefront_menu('wo001-alpha')->'service'->>'ordering_enabled','true',
 'enabled published platform channel exposes browser ordering');
reset role;
create procedure pg_temp.wo_reset_counters() language sql as $$
 update public.web_order_channel_settings set
  submit_window_started_at=clock_timestamp(),submit_attempt_count=0,submitted_in_window=0,
  submit_day=current_date,submitted_today=0,
  status_window_started_at=clock_timestamp(),status_attempt_count=0
 where organization_id=pg_temp.wo_ref('org_a')
$$;

-- Invalid JSON cannot supply money, tenant scope, IDs, or permissive coercions.
set local role service_role;
select pg_temp.wo_refused(b,description)
from (values
 ('null'::jsonb,'null order refused'),
 ('[]'::jsonb,'array order refused'),
 (pg_temp.wo_order()||'{"grand_total_minor":1}'::jsonb,'caller total refused'),
 (pg_temp.wo_order()||'{"subtotal_minor":1}'::jsonb,'caller subtotal refused'),
 (pg_temp.wo_order()||'{"currency_code":"ILS"}'::jsonb,'caller currency refused'),
 (pg_temp.wo_order()||jsonb_build_object('organization_id',pg_temp.wo_ref('org_b')),'caller tenant refused'),
 (pg_temp.wo_order()||'{"order_type":"delivery"}'::jsonb,'delivery refused'),
 (pg_temp.wo_order()-'notes','missing notes refused'),
 (jsonb_set(pg_temp.wo_order(),'{notes}','123'::jsonb),'numeric notes refused'),
 (jsonb_set(pg_temp.wo_order(),'{customer,name}','1'::jsonb),'numeric name refused'),
 (jsonb_set(pg_temp.wo_order(),'{customer,name}','""'::jsonb),'empty name refused'),
 (jsonb_set(pg_temp.wo_order(),'{customer,name}',to_jsonb(repeat('n',81))),'customer name over eighty characters refused'),
 (jsonb_set(pg_temp.wo_order(),'{customer,phone}','"0520000001"'::jsonb),'non E164 phone refused'),
 (jsonb_set(pg_temp.wo_order(),'{customer,phone}','123'::jsonb),'numeric phone refused'),
 (jsonb_set(pg_temp.wo_order(),'{notes}',to_jsonb(repeat('n',501))),'notes over five hundred characters refused'),
 (jsonb_set(pg_temp.wo_order(),'{customer}',(pg_temp.wo_order()->'customer')||'{"email":"test@example.test"}'),'extra customer key refused'),
 (jsonb_set(pg_temp.wo_order(),'{items}','[]'::jsonb),'empty items refused'),
 (jsonb_set(pg_temp.wo_order(),'{items}','{}'::jsonb),'object items refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,quantity}','"1"'::jsonb),'string line quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,quantity}','1.5'::jsonb),'fractional line quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,quantity}','0'::jsonb),'zero line quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,quantity}','-1'::jsonb),'negative line quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,quantity}','21'::jsonb),'line quantity over twenty refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0}',(pg_temp.wo_order()->'items'->0)||'{"unit_price_minor":1}'),'line price refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0}',(pg_temp.wo_order()->'items'->0)||'{"currency_code":"ILS"}'),'line currency refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers}','{}'::jsonb),'object modifiers refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0,quantity}','"1"'::jsonb),'string modifier quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0,quantity}','0'::jsonb),'zero modifier quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0,quantity}','-1'::jsonb),'negative modifier quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0,quantity}','1.5'::jsonb),'fractional modifier quantity refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0,quantity}','21'::jsonb),'modifier quantity over twenty refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0}',pg_temp.wo_option('classic')||'{"price_delta_minor":0}'),'modifier price refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0}',pg_temp.wo_option('classic')||'{"modifier_id":"ignored"}'),'modifier group key refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,menu_item_id}','"invalid-uuid"'::jsonb),'invalid item UUID refused'),
 (jsonb_set(pg_temp.wo_order(),'{items,0,modifiers,0,modifier_option_id}','"invalid-uuid"'::jsonb),'invalid option UUID refused')
) invalid(b,description);
select is(public.submit_web_order_request('wo001-alpha','10000000-0000-1000-8000-000000000002',repeat('a',64),pg_temp.wo_order())->>'ok',
 'false','client request ID must be UUID v4');
select is(public.submit_web_order_request('wo001-alpha',pg_temp.wo_client(2),repeat('A',64),pg_temp.wo_order())->>'ok',
 'false','status token digest must use lowercase hexadecimal');
select is(public.submit_web_order_request('wo001-alpha',pg_temp.wo_client(2),repeat('a',63),pg_temp.wo_order())->>'ok',
 'false','status token digest must be exactly SHA256 length');
select pg_temp.wo_refused(jsonb_set(pg_temp.wo_order('item_plain'),'{items}',
 (select jsonb_agg(pg_temp.wo_order('item_plain')->'items'->0) from generate_series(1,21))),
 'twenty one item lines refused');
select pg_temp.wo_refused(jsonb_set(pg_temp.wo_order('item_plain'),'{items}',
 jsonb_build_array(pg_temp.wo_order('item_plain',20)->'items'->0,
 pg_temp.wo_order('item_plain',20)->'items'->0,pg_temp.wo_order('item_plain',11)->'items'->0)),
 'fifty one item units refused');
select pg_temp.wo_refused(pg_temp.wo_order('item_a',1,
 (select jsonb_agg(pg_temp.wo_option('classic')) from generate_series(1,21))),
 'twenty one modifier selections refused');
reset role;

call pg_temp.wo_reset_counters();

-- Catalogue selection rules are evaluated against the live storefront branch.
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order('item_a',1,mods),description)
from (values
 ('[]'::jsonb,'required single selection missing'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('double')),'single group accepts only one distinct option'),
 (jsonb_build_array(pg_temp.wo_option('classic',2)),'quantity forbidden by single group'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('classic')),'duplicate option per line refused'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('cheese',4)),'modifier maximum quantity enforced'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('cheese'),pg_temp.wo_option('sauce'),pg_temp.wo_option('onion')),'multiple maximum counts distinct options'),
 (jsonb_build_array(pg_temp.wo_option('negative')),'negative live catalogue delta refused'),
 (jsonb_build_array(pg_temp.wo_option('dead_option')),'inactive live catalogue option refused'),
 (jsonb_build_array(pg_temp.wo_option('tombstoned_option')),'tombstoned live catalogue option refused'),
 (jsonb_build_array(pg_temp.wo_option('sibling_option')),'sibling branch option refused'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('sibling_group_option')),'sibling branch group refused'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('wrong_item_option')),'different item option refused'),
 (jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('foreign_option')),'different tenant option refused')
) invalid(mods,description);
select pg_temp.wo_refused(pg_temp.wo_order('item_multiple',1,jsonb_build_array(pg_temp.wo_option('multiple_one',2))),
 'required multiple minimum counts distinct options rather than option quantity');
select pg_temp.wo_refused(pg_temp.wo_order('item_sibling'),'sibling branch menu item refused');
select pg_temp.wo_refused(pg_temp.wo_order('item_dead'),'inactive menu item refused');
select pg_temp.wo_refused(pg_temp.wo_order('item_b'),'foreign tenant menu item refused');
reset role;
insert into menu_item_branch_availability(organization_id,restaurant_id,branch_id,menu_item_id,availability,reason)
values(pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('branch_a'),pg_temp.wo_ref('item_a'),'unavailable','sold_out');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'sold out branch override refuses submission');
reset role;
update menu_item_branch_availability set availability='available',reason=null
where branch_id=pg_temp.wo_ref('branch_a') and menu_item_id=pg_temp.wo_ref('item_a');
update menu_categories set is_active=false where id=pg_temp.wo_ref('category_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'inactive category refuses submission');
reset role;
update menu_categories set is_active=true where id=pg_temp.wo_ref('category_a');
update modifiers set is_active=false where id=pg_temp.wo_ref('single');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'inactive modifier group refuses selected option');
reset role;
update modifiers set is_active=true where id=pg_temp.wo_ref('single');
update modifiers set max_select=1 where id=pg_temp.wo_ref('required_multiple');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order('item_multiple',1,
 jsonb_build_array(pg_temp.wo_option('multiple_one'),pg_temp.wo_option('multiple_two'))),
 'impossible live group configuration fails closed');
reset role;
update modifiers set max_select=2 where id=pg_temp.wo_ref('required_multiple');

-- Every current storefront gate is checked at submission time.
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order(),2)->>'error','not_found',
 'unpublished storefront with enabled channel is uniformly not_found');
reset role;
update restaurant_storefront_profiles set is_published=true,paused_until=now()+interval '1 hour' where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'paused storefront refuses submission');
reset role;
update restaurant_storefront_profiles set paused_until=null,pickup_enabled=false where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'pickup disabled refuses submission');
reset role;
update restaurant_storefront_profiles set pickup_enabled=true,opening_hours=
 jsonb_build_object('weekly',jsonb_build_array(jsonb_build_object(
 'dow',(extract(dow from now())::int+3)%7,'open','10:00','close','11:00')),'exceptions','[]'::jsonb)
where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'closed storefront refuses submission');
reset role;
update restaurant_storefront_profiles set opening_hours=(select always_open from _wo_hours) where restaurant_id=pg_temp.wo_ref('rest_a');
update organizations set status='suspended' where id=pg_temp.wo_ref('org_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'suspended tenant refuses submission');
reset role;
update organizations set status='active' where id=pg_temp.wo_ref('org_a');
update branches set deleted_at=now() where id=pg_temp.wo_ref('branch_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'tombstoned storefront branch refuses submission');
reset role;
update branches set deleted_at=null where id=pg_temp.wo_ref('branch_a');
update restaurants set status='suspended' where id=pg_temp.wo_ref('rest_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'suspended restaurant refuses submission');
reset role;
update restaurants set status='active' where id=pg_temp.wo_ref('rest_a');
update branches set status='suspended' where id=pg_temp.wo_ref('branch_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'suspended branch refuses submission');
reset role;
update branches set status='active',tax_mode='inclusive' where id=pg_temp.wo_ref('branch_a');
set local role service_role;
select pg_temp.wo_refused(pg_temp.wo_order(),'inclusive branch tax fails closed');
reset role;
update branches set tax_mode='exclusive' where id=pg_temp.wo_ref('branch_a');

call pg_temp.wo_reset_counters();

-- Formula B uses catalogue base and per-unit option deltas; tax is server-owned.
set local role service_role;
insert into _wo_results values('created',pg_temp.wo_submit(pg_temp.wo_order('item_a',2,
 jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('cheese',3))),1));
select is((select r->>'ok' from _wo_results where label='created'),'true','valid pending request accepted');
select is((select r->>'request_id' from _wo_results where label='created'),pg_temp.wo_client(1)::text,'response uses client reference');
select is((select r->>'status' from _wo_results where label='created'),'pending','new request remains pending');
select is((select r->>'replayed' from _wo_results where label='created'),'false','first response is not replayed');
select is((select r->'totals' from _wo_results where label='created'),
 '{"currency_code":"ILS","subtotal_minor":3196,"tax_total_minor":575,"grand_total_minor":3771}'::jsonb,
 'authoritative formula: 2 * (1001 + 199 * 3), exclusive 18 percent tax');
select ok((select (r->>'expires_at')::timestamptz between now()+interval '14 minutes' and now()+interval '16 minutes'
 from _wo_results where label='created'),'request expires in fifteen minutes');
reset role;
select is((select count(*)::int from web_order_requests where organization_id=pg_temp.wo_ref('org_a')),1,
 'every invalid attempt was atomic: only accepted request exists');
select ok((select id<>client_request_id and branch_id=pg_temp.wo_ref('branch_a')
 and organization_id=pg_temp.wo_ref('org_a') and restaurant_id=pg_temp.wo_ref('rest_a')
 and subtotal_minor=3196 and tax_total_minor=575 and grand_total_minor=3771
 and status_token_hash=repeat('a',64) and payload_hash ~ '^[0-9a-f]{64}$'
 and status_until between now()+interval '23 hours' and now()+interval '25 hours'
 from web_order_requests where client_request_id=pg_temp.wo_client(1)),
 'stored scope, totals, private ID, digest and status lifetime come from backend');
select is((select priced_items->0->>'unit_price_minor_snapshot' from web_order_requests
 where client_request_id=pg_temp.wo_client(1)),'1001','stored base price is a server-owned catalogue snapshot');
select is((select priced_items->0->>'line_total_minor' from web_order_requests
 where client_request_id=pg_temp.wo_client(1)),'3196','stored line total includes per-unit modifier quantities');
select is((select o->>'price_minor_snapshot' from web_order_requests w,
 jsonb_array_elements(w.priced_items->0->'modifiers') o
 where w.client_request_id=pg_temp.wo_client(1) and o->>'modifier_option_id'=pg_temp.wo_ref('cheese')::text),
 '199','stored option price comes from current catalogue');
select throws_ok($$update web_order_requests set customer_phone='+972520000002'
 where client_request_id=pg_temp.wo_client(1)$$,'42501',null,'accepted request contact snapshot is immutable');
select throws_ok($$update web_order_requests set subtotal_minor=1,grand_total_minor=576
 where client_request_id=pg_temp.wo_client(1)$$,'42501',null,'accepted request price snapshot is immutable');
select throws_ok($$update web_order_requests set expires_at=expires_at+interval '1 second'
 where client_request_id=pg_temp.wo_client(1)$$,'42501',null,'request capability lifetime cannot be extended');
select is((select count(*)::int from web_order_request_events where organization_id=pg_temp.wo_ref('org_a')),1,
 'exactly one request event accompanies accepted insert');
select ok((select e.event_type='received' and e.request_id=w.id
 and e.organization_id=w.organization_id and e.restaurant_id=w.restaurant_id and e.branch_id=w.branch_id
 and to_jsonb(e)->>'app_user_id' is null and to_jsonb(e)->>'actor_app_user_id' is null
 and to_jsonb(e)::text not like '%Synthetic Website Guest%'
 and to_jsonb(e)::text not like '%+972%'
 from web_order_request_events e join web_order_requests w on w.id=e.request_id
 where w.client_request_id=pg_temp.wo_client(1)),
 'received event has matching tenant scope and no invented staff identity or PII');
select throws_ok($$update web_order_request_events set event_type='received'
 where organization_id=pg_temp.wo_ref('org_a')$$,'42501',null,'request events refuse even no-op updates');
select throws_ok($$delete from web_order_request_events
 where organization_id=pg_temp.wo_ref('org_a')$$,'42501',null,'request events refuse deletion');
select throws_ok($$truncate public.web_order_request_events$$,'42501',null,'request events refuse truncation');
select throws_ok($$insert into public.web_order_requests
 select z.* from public.web_order_requests w
 cross join lateral jsonb_populate_record(null::public.web_order_requests,
  to_jsonb(w)||jsonb_build_object('id',gen_random_uuid(),'client_request_id',pg_temp.wo_client(999),
  'branch_id',pg_temp.wo_ref('branch_b'))) z
 where w.client_request_id=pg_temp.wo_client(1)$$,
 '23503',null,'request composite FK refuses a foreign tenant branch');

-- A retry preserves the original amounts after catalogue changes.
update menu_items set base_price_minor=2001 where id=pg_temp.wo_ref('item_a');
update modifier_options set price_delta_minor=299 where id=pg_temp.wo_ref('cheese');
set local role service_role;
insert into _wo_results values('replay',pg_temp.wo_submit(pg_temp.wo_order('item_a',2,
 jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('cheese',3))),1));
select is((select r->>'replayed' from _wo_results where label='replay'),'true','identical retry is recognized');
select is((select r-'replayed' from _wo_results where label='replay'),
 (select r-'replayed' from _wo_results where label='created'),'retry preserves every original response field and total');
select is(pg_temp.wo_submit(pg_temp.wo_order(),1)->>'error','idempotency_conflict','changed body cannot reuse client request ID');
select is(pg_temp.wo_submit(pg_temp.wo_order('item_a',2,
 jsonb_build_array(pg_temp.wo_option('classic'),pg_temp.wo_option('cheese',3))),1,'wo001-alpha',repeat('b',64))->>'ok',
 'false','changed secret hash cannot reuse client request ID');
reset role;
select is((select count(*)::int from web_order_requests where organization_id=pg_temp.wo_ref('org_a')),1,'replay and conflicts create no additional request');
select is((select count(*)::int from web_order_request_events where organization_id=pg_temp.wo_ref('org_a')),1,'replay and conflicts create no additional event');

-- Only the slug, client reference, and matching digest authorize a minimal poll.
set local role service_role;
insert into _wo_results values('status',public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('a',64)));
select is((select r->>'ok' from _wo_results where label='status'),'true','correct status reference resolves');
select is((select r->>'status' from _wo_results where label='status'),'pending','correct reference reports pending');
select ok((select r::text not like '%Synthetic Website Guest%' and r::text not like '%+972%'
 and r::text not like '%customer%' and r::text not like '%priced_items%'
 and r::text not like '%status_token_hash%' and r::text not like '%payload_hash%'
 and r::text not like '%organization_id%' and r::text not like '%branch_id%'
 and r::text not like '%restaurant_id%' from _wo_results where label='status'),
 'status exposes no PII, private pricing snapshot, tenant IDs or token digest');
insert into _wo_results values
 ('wrong_token',public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('b',64))),
 ('unknown_request',public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(987),repeat('a',64))),
 ('wrong_slug',public.get_web_order_request_status('wo001-bravo',pg_temp.wo_client(1),repeat('a',64)));
select is((select r from _wo_results where label='wrong_token'),
 (select r from _wo_results where label='unknown_request'),'wrong token and unknown reference are indistinguishable');
select is((select r from _wo_results where label='wrong_slug'),
 (select r from _wo_results where label='unknown_request'),'cross-tenant slug and unknown reference are indistinguishable');
select is((select r->>'ok' from _wo_results where label='wrong_token'),'false','wrong token refuses status');
reset role;
-- Age only the synthetic fixture, with the identity guard disabled exclusively
-- for this harness update and restored before the real-role status call.
alter table web_order_requests disable trigger web_order_request_guard;
update web_order_requests set created_at=now()-interval '16 minutes',
 expires_at=now()-interval '1 minute',status_until=now()+interval '23 hours 44 minutes'
where client_request_id=pg_temp.wo_client(1);
alter table web_order_requests enable trigger web_order_request_guard;
set local role service_role;
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('a',64))->>'status',
 'expired','expiry is derived by polling');
reset role;
select is((select status from web_order_requests where client_request_id=pg_temp.wo_client(1)),'pending',
 'expiry poll does not mutate persisted status');
alter table web_order_requests disable trigger web_order_request_guard;
update web_order_requests set created_at=now()-interval '25 hours',
 expires_at=now()-interval '24 hours 45 minutes',status_until=now()-interval '1 hour'
where client_request_id=pg_temp.wo_client(1);
alter table web_order_requests enable trigger web_order_request_guard;
set local role service_role;
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('a',64)),
 (select r from _wo_results where label='unknown_request'),'status is unavailable after twenty four hour capability lifetime');
reset role;

-- Inclusive bounds remain usable; zero-priced options are valid catalogue data.
call pg_temp.wo_reset_counters();
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order('item_multiple',1,
 jsonb_build_array(pg_temp.wo_option('multiple_one'),pg_temp.wo_option('multiple_two')),
 '+972540000100'),100)->>'ok','true','two distinct options satisfy required multiple minimum');
select is(pg_temp.wo_submit(jsonb_set(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972540000101'),'{items}',
 (select jsonb_agg(pg_temp.wo_order('item_plain')->'items'->0) from generate_series(1,20))),101)->>'ok',
 'true','exactly twenty item lines remain permitted');
select is(pg_temp.wo_submit(jsonb_set(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972540000102'),'{items}',
 jsonb_build_array(pg_temp.wo_order('item_plain',20)->'items'->0,
 pg_temp.wo_order('item_plain',20)->'items'->0,pg_temp.wo_order('item_plain',10)->'items'->0)),102)->>'ok',
 'true','exactly fifty item units remain permitted');
reset role;
update modifiers set max_select=20 where id=pg_temp.wo_ref('extras');
insert into modifier_options(id,organization_id,restaurant_id,modifier_id,name,price_delta_minor)
select md5('web-orders-001-cap-option-'||n)::uuid,pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),
 pg_temp.wo_ref('extras'),'WO001 Free cap option '||n,0 from generate_series(1,20) n;
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order('item_a',1,
 jsonb_build_array(pg_temp.wo_option('classic'))||
 (select jsonb_agg(jsonb_build_object('modifier_option_id',md5('web-orders-001-cap-option-'||n)::uuid,'quantity',1))
 from generate_series(1,19) n),'+972540000103'),103)->>'ok',
 'true','exactly twenty distinct modifier selections remain permitted, including zero deltas');
select pg_temp.wo_refused(pg_temp.wo_order('item_a',1,
 jsonb_build_array(pg_temp.wo_option('classic'))||
 (select jsonb_agg(jsonb_build_object('modifier_option_id',md5('web-orders-001-cap-option-'||n)::uuid,'quantity',1))
 from generate_series(1,20) n)),
 'twenty one otherwise valid distinct modifier selections exceed per-line cap');
reset role;

-- New-request limits are distinct from request attempts and status polling.
call pg_temp.wo_reset_counters();
set local role service_role;
insert into _wo_results
select 'minute-'||n,pg_temp.wo_submit(pg_temp.wo_order('item_plain',1,'[]'::jsonb,
 '+972520'||lpad(n::text,6,'0')),n) from generate_series(200,209) n;
select is((select count(*)::int from _wo_results where label like 'minute-%' and r->>'ok'='true'),10,
 'ten new requests per minute are accepted');
select is(pg_temp.wo_submit(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972520000210'),210)->>'error',
 'rate_limited','eleventh new request in one minute is refused');
reset role;
call pg_temp.wo_reset_counters();
set local role service_role;
insert into _wo_results
select 'phone-'||n,pg_temp.wo_submit(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972520009999'),n)
from generate_series(300,302) n;
select is((select count(*)::int from _wo_results where label like 'phone-%' and r->>'ok'='true'),3,
 'three live pending requests for one phone are accepted');
select is(pg_temp.wo_submit(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972520009999'),303)->>'error',
 'capacity_reached','fourth live pending request for the same phone is refused');
reset role;
call pg_temp.wo_reset_counters();
update web_order_channel_settings set submitted_today=1000 where branch_id=pg_temp.wo_ref('branch_a');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972520000400'),400)->>'error',
 'rate_limited','daily accepted cap refuses request one thousand and one');
reset role;
call pg_temp.wo_reset_counters();
update web_order_channel_settings set submit_attempt_count=59 where branch_id=pg_temp.wo_ref('branch_a');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order('item_plain',0),600)->>'error','invalid_request',
 'sixtieth submit attempt reaches line validation');
select is(pg_temp.wo_submit(pg_temp.wo_order('item_plain'),601)->>'error','rate_limited',
 'sixty first submit attempt is refused');
reset role;
call pg_temp.wo_reset_counters();
-- Direct inserts only populate synthetic pending capacity. They do not invoke
-- operational order APIs or bypass the tested endpoint's quota behavior.
insert into public.web_order_requests
select z.* from public.web_order_requests w
cross join generate_series(1,50-(select count(*)::int from web_order_requests
 where branch_id=pg_temp.wo_ref('branch_a') and status='pending' and expires_at>now())) g
cross join lateral jsonb_populate_record(null::public.web_order_requests,
 to_jsonb(w)||jsonb_build_object('id',gen_random_uuid(),'client_request_id',pg_temp.wo_client(9000+g),
 'customer_phone','+972530'||lpad(g::text,6,'0'),'created_at',now(),
 'expires_at',now()+interval '15 minutes','status_until',now()+interval '24 hours')) z
where w.client_request_id=pg_temp.wo_client(1);
select is((select count(*)::int from web_order_requests where branch_id=pg_temp.wo_ref('branch_a')
 and status='pending' and expires_at>now()),50,'capacity fixture contains exactly fifty live pending requests');
set local role service_role;
select is(pg_temp.wo_submit(pg_temp.wo_order('item_plain',1,'[]'::jsonb,'+972520000500'),500)->>'error',
 'capacity_reached','fifty first live pending request is refused');
reset role;
call pg_temp.wo_reset_counters();
update web_order_channel_settings set status_attempt_count=599 where branch_id=pg_temp.wo_ref('branch_a');
set local role service_role;
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(200),repeat('a',64))->>'ok',
 'true','six hundredth status poll succeeds');
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(200),repeat('a',64))->>'error',
 'rate_limited','six hundred and first status poll is refused');
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(200),repeat('b',64))->>'error',
 'not_found','exhausted status quota does not disclose a wrong-token reference');
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(987),repeat('a',64)),
 public.get_web_order_request_status('wo001-unknown',pg_temp.wo_client(987),repeat('a',64)),
 'unknown reference at exhausted status quota matches unknown slug');
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(1),repeat('a',64))->>'error',
 'not_found','exhausted status quota does not disclose an expired capability');
reset role;
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(200),repeat('b',64)),
 public.get_web_order_request_status('wo001-unknown',pg_temp.wo_client(200),repeat('b',64)),
 'unpublished slug and exhausted quota retain uniform invalid-reference response');
select is(public.get_web_order_request_status('wo001-alpha',pg_temp.wo_client(200),repeat('a',64))->>'error',
 'rate_limited','a valid private capability retains bounded status recovery after unpublishing');
reset role;

-- This ticket cannot produce an operational order or invent a staff principal.
select is((select count(*) from orders),(select orders from _wo_before),'no canonical order delta');
select is((select count(*) from order_items),(select order_items from _wo_before),'no canonical order item delta');
select is((select count(*) from order_item_modifiers),(select order_item_modifiers from _wo_before),'no canonical order modifier delta');
select is((select count(*) from order_service_rounds),(select service_rounds from _wo_before),'no service round delta');
select is((select count(*) from kitchen_print_dispatches),(select dispatches from _wo_before),'no kitchen dispatch delta');
select is((select count(*) from payments),(select payments from _wo_before),'no payment delta');
select is((select count(*) from app_users),(select app_users from _wo_before),'no fake application user delta');

select * from finish();
rollback;
