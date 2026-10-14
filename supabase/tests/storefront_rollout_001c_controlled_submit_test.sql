-- STOREFRONT-ROLLOUT-001C-PREP: atomic controlled-submit guard.
-- Rollback-only synthetic fixtures and existing normal submission orchestration.
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
 p_slug text default 'mapsburger', p_token text default repeat('a',64)) returns jsonb
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
select pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('org_a'),pg_temp.wo_ref('branch_a'),'mapsburger','WO001 Alpha',true,always_open,true from _wo_hours;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.wo_ref('rest_b'),pg_temp.wo_ref('org_b'),pg_temp.wo_ref('branch_b'),'otherburger','WO001 Bravo',true,always_open,true from _wo_hours;

insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
select organization_id,restaurant_id,id,true from branches where id in
 (pg_temp.wo_ref('branch_a'),pg_temp.wo_ref('branch_sibling'),pg_temp.wo_ref('branch_b'));
create function pg_temp.ct_submit(p_n integer,p_overrides jsonb default '{}') returns jsonb
language plpgsql as $$
declare a jsonb;
begin
 a:=jsonb_build_object('slug','mapsburger','client',pg_temp.wo_client(p_n),
  'token',repeat('a',64),'body',jsonb_set(pg_temp.wo_order(),'{items,0,notes}','"Controlled item note"'),
  'org',pg_temp.wo_ref('org_a'),'restaurant',pg_temp.wo_ref('rest_a'),
  'branch',pg_temp.wo_ref('branch_a'),'request',pg_temp.wo_client(p_n),
  'not_before',clock_timestamp()-interval '1 second','expires_at',clock_timestamp()+interval '5 minutes')||p_overrides;
 return public.submit_web_order_test_request(a->>'slug',(a->>'client')::uuid,a->>'token',a->'body',
  (a->>'org')::uuid,(a->>'restaurant')::uuid,(a->>'branch')::uuid,(a->>'request')::uuid,
  (a->>'not_before')::timestamptz,(a->>'expires_at')::timestamptz);
end$$;
create function pg_temp.ct_counts() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object(
  'requests',(select count(*) from public.web_order_requests where organization_id=pg_temp.wo_ref('org_a')),
  'events',(select count(*) from public.web_order_request_events where organization_id=pg_temp.wo_ref('org_a')),
  'channels',(select jsonb_agg(to_jsonb(c) order by c.branch_id) from public.web_order_channel_settings c
              where c.organization_id=pg_temp.wo_ref('org_a')),
  'orders',(select count(*) from public.orders where organization_id=pg_temp.wo_ref('org_a')),
  'dispatch',(select count(*) from public.kitchen_print_dispatches where organization_id=pg_temp.wo_ref('org_a')))
$$;

select ok(prosecdef=(n.nspname='app') and proconfig @> array['search_path=""'],
 n.nspname||' controlled wrapper has the intended security mode and pinned search_path')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('app','public') and p.proname='submit_web_order_test_request';
select ok(not has_function_privilege('anon',p.oid,'EXECUTE')
 and not has_function_privilege('authenticated',p.oid,'EXECUTE')
 and has_function_privilege('service_role',p.oid,'EXECUTE')
 and not exists(select 1 from aclexplode(p.proacl) a where a.grantee=0 and a.privilege_type='EXECUTE'),
 n.nspname||' controlled submit is service-role only')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('app','public') and p.proname='submit_web_order_test_request';
set local role anon;
select throws_ok($$select pg_temp.ct_submit(1)$$,'42501',null,'real anon cannot invoke controlled submit');
reset role;
set local role authenticated;
select throws_ok($$select pg_temp.ct_submit(1)$$,'42501',null,'real authenticated cannot invoke controlled submit');
reset role;
select ok(not has_table_privilege('service_role','public.web_order_requests','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('service_role','public.web_order_channel_settings','SELECT,INSERT,UPDATE,DELETE'),
 'controlled guard grants no direct request/channel access');

insert into _wo_results values('before_invalid',pg_temp.ct_counts());
set local role service_role;
select is(pg_temp.ct_submit(1,overrides)->>'error','ordering_unavailable','guard refuses '||label)
from (values
 ('wrong slug','{"slug":"otherburger"}'::jsonb),
 ('null slug','{"slug":null}'::jsonb),
 ('null organization','{"org":null}'::jsonb),
 ('null restaurant','{"restaurant":null}'::jsonb),
 ('null branch','{"branch":null}'::jsonb),
 ('wrong organization',jsonb_build_object('org',pg_temp.wo_ref('org_b'))),
 ('wrong restaurant',jsonb_build_object('restaurant',pg_temp.wo_ref('rest_b'))),
 ('wrong enabled sibling branch',jsonb_build_object('branch',pg_temp.wo_ref('branch_sibling'))),
 ('wrong enabled foreign branch',jsonb_build_object('branch',pg_temp.wo_ref('branch_b'))),
 ('null request','{"request":null}'::jsonb),
 ('null client','{"client":null}'::jsonb),
 ('different request',jsonb_build_object('request',pg_temp.wo_client(2))),
 ('non-v4 identity','{"client":"10000000-0000-3000-8000-000000000001","request":"10000000-0000-3000-8000-000000000001"}'::jsonb),
 ('null not-before','{"not_before":null}'::jsonb),
 ('null expiry','{"expires_at":null}'::jsonb),
 ('infinite not-before','{"not_before":"-infinity"}'::jsonb),
 ('infinite expiry','{"expires_at":"infinity"}'::jsonb),
 ('future window',jsonb_build_object('not_before',clock_timestamp()+interval '1 minute','expires_at',clock_timestamp()+interval '2 minutes')),
 ('expired window',jsonb_build_object('not_before',clock_timestamp()-interval '2 minutes','expires_at',clock_timestamp()-interval '1 minute')),
 ('reversed window',jsonb_build_object('not_before',clock_timestamp()+interval '1 minute','expires_at',clock_timestamp()-interval '1 minute')),
 ('oversized window',jsonb_build_object('not_before',clock_timestamp()-interval '1 minute','expires_at',clock_timestamp()+interval '15 minutes'))
) invalid(label,overrides);
reset role;
select is(pg_temp.ct_counts(),(select r from _wo_results where label='before_invalid'),
 'invalid scope/identity/windows leave every request/event/channel/order/dispatch unchanged');

-- Correct scope still delegates ordinary SQL admission and pricing unchanged.
delete from web_order_channel_settings where branch_id=pg_temp.wo_ref('branch_a');
set local role service_role;
select is(pg_temp.ct_submit(3)->>'error','ordering_unavailable','missing exact channel fails closed');
reset role;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
values(pg_temp.wo_ref('org_a'),pg_temp.wo_ref('rest_a'),pg_temp.wo_ref('branch_a'),false);
set local role service_role;
select is(pg_temp.ct_submit(3)->>'error','ordering_unavailable','controlled guard does not bypass disabled SQL admission');
reset role;
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.wo_ref('branch_a');
update restaurant_storefront_profiles set paused_until=clock_timestamp()+interval '5 minutes'
 where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.ct_submit(3)->>'error','ordering_unavailable','controlled guard still requires open storefront pricing');
reset role;
update restaurant_storefront_profiles set paused_until=null,pickup_enabled=false
 where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.ct_submit(3)->>'error','ordering_unavailable','controlled guard still requires pickup');
reset role;
update restaurant_storefront_profiles set pickup_enabled=true where restaurant_id=pg_temp.wo_ref('rest_a');
set local role service_role;
select is(pg_temp.ct_submit(3,jsonb_build_object('body',jsonb_set(pg_temp.wo_order(),'{items,0,unit_price_minor}','0')))->>'error',
 'invalid_request','controlled submit preserves strict client price-authority rejection');
select is(pg_temp.ct_submit(3,jsonb_build_object('token','invalid'))->>'error','invalid_request',
 'controlled submit preserves capability-hash validation');
insert into _wo_results values('controlled',pg_temp.ct_submit(3));
select is((select r->>'status' from _wo_results where label='controlled'),'pending','controlled valid submission creates pending only');
select is(pg_temp.ct_submit(3)->>'replayed','true','controlled same UUID/capability/body replays original request');
select is(pg_temp.ct_submit(3,jsonb_build_object('token',repeat('b',64)))->>'error','idempotency_conflict',
 'changed capability still conflicts under the existing identity');
select is(pg_temp.ct_submit(3,jsonb_build_object('body',pg_temp.wo_order()))->>'error','idempotency_conflict',
 'changed item notes still conflict under the existing identity');
reset role;
select is((select count(*)::int from web_order_requests where restaurant_id=pg_temp.wo_ref('rest_a')),1,
 'exact controlled retries create one immutable pending request');
select is((select priced_items->0->>'notes' from web_order_requests where client_request_id=pg_temp.wo_client(3)),
 'Controlled item note','existing immutable pricing retains controlled item notes');
select ok((select not ordering_enabled and not delivery_enabled from restaurant_storefront_profiles
 where restaurant_id=pg_temp.wo_ref('rest_a')),'public profile CHECK and ordering/delivery flags remain off');
select is(public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}','false',
 'controlled submission never changes public ordering advertisement');
update web_order_channel_settings set submission_enabled=false where branch_id=pg_temp.wo_ref('branch_a');
set local role service_role;
select is(pg_temp.ct_submit(3)->>'replayed','true','normal exact replay remains valid while SQL intake is closed');
select is(pg_temp.ct_submit(3,jsonb_build_object('not_before',clock_timestamp()-interval '2 minutes',
 'expires_at',clock_timestamp()-interval '1 minute'))->>'error','ordering_unavailable','controlled permit expiry closes replays too');
select is(public.get_web_order_request_status('mapsburger',pg_temp.wo_client(3),repeat('a',64))->>'status','pending',
 'existing status remains usable after controlled permit expiry');
reset role;
update web_order_channel_settings set submission_enabled=true where branch_id=pg_temp.wo_ref('branch_a');

-- Witness the unchanged real delegate reaching its received-event INSERT.
-- nextval is nontransactional, so it proves execution even when guard rollback
-- correctly removes the request/event and all admission-counter changes.
create temporary sequence ct_received_hits;
select nextval('pg_temp.ct_received_hits');
create function pg_temp.ct_delay_received() returns trigger language plpgsql as $$
declare deadline timestamptz:=nullif(current_setting('test.ct_expiry',true),'')::timestamptz;
begin
 if new.organization_id=pg_temp.wo_ref('org_a') then
  perform nextval('pg_temp.ct_received_hits');
  if deadline is not null then
   perform pg_sleep(greatest(0,extract(epoch from deadline-clock_timestamp()))+0.05);
  end if;
 end if;
 return new;
end$$;
create trigger zz_ct_delay_received after insert on web_order_request_events
 for each row execute function pg_temp.ct_delay_received();
insert into _wo_results values('before_runtime_expiry',pg_temp.ct_counts());
create temporary table _ct_hit_before as select last_value from pg_temp.ct_received_hits;
select set_config('test.ct_expiry',(clock_timestamp()+interval '1 second')::text,true);
set local role service_role;
select is(pg_temp.ct_submit(4,jsonb_build_object('expires_at',current_setting('test.ct_expiry')))->>'error',
 'ordering_unavailable','expiry after real delegate writes returns a fixed refusal');
reset role;
select ok((select last_value from pg_temp.ct_received_hits)>(select last_value from _ct_hit_before),
 'runtime expiry proof reached the real delegate received-event insert');
select is(pg_temp.ct_counts(),(select r from _wo_results where label='before_runtime_expiry'),
 'post-delegate deadline failure rolls back all request/event/channel effects');
select set_config('test.ct_expiry','',true);

-- Real separate-session identity-lock wait; no committed fixture is needed.
-- The blocker releases only after observing the main guard WAITING on its lock,
-- then holding beyond the main call's one-second window. This avoids a sleep race.
create extension if not exists dblink with schema extensions;
select dblink_connect('ct_lock_holder',
 'host='||host(inet_server_addr())||' port='||inet_server_port()||' dbname='||current_database()||
 ' user=postgres password=postgres');
select dblink_exec('ct_lock_holder','begin');
select dblink_exec('ct_lock_holder','set statement_timeout=''8s''');
set local lock_timeout='8s';
select dblink_exec('ct_lock_holder',$remote$
 create function pg_temp.ct_release_after_wait(p_main integer,p_key bigint) returns jsonb language plpgsql as $$
 declare seen boolean:=false;
 begin
  for i in 1..500 loop
   perform pg_stat_clear_snapshot();
   seen:=pg_backend_pid()=any(pg_blocking_pids(p_main));
   exit when seen;
   perform pg_sleep(0.01);
  end loop;
  if seen then perform pg_sleep(1.2); end if;
  perform pg_advisory_unlock(p_key);
  return jsonb_build_object('observed_wait',seen);
 exception when others then
  perform pg_advisory_unlock(p_key);
  raise;
 end$$
 $remote$);
select * from dblink('ct_lock_holder',format('select pg_advisory_lock(%s)',
 hashtextextended(pg_temp.wo_ref('rest_a')::text||':'||pg_temp.wo_client(5)::text,0))) as t(locked text);
insert into _wo_results values('before_lock_expiry',pg_temp.ct_counts());
create temporary table _ct_lock_hit_before as select last_value from pg_temp.ct_received_hits;
select dblink_send_query('ct_lock_holder',format('select pg_temp.ct_release_after_wait(%s,%s)',pg_backend_pid(),
 hashtextextended(pg_temp.wo_ref('rest_a')::text||':'||pg_temp.wo_client(5)::text,0)));
set local role service_role;
select is(pg_temp.ct_submit(5,jsonb_build_object('expires_at',clock_timestamp()+interval '1 second'))->>'error',
 'ordering_unavailable','guard samples expiry after waiting for identity lock');
reset role;
select is(r->>'observed_wait','true','second session observed actual guard blocking before release')
from dblink_get_result('ct_lock_holder') as t(r jsonb);
select count(*) from dblink_get_result('ct_lock_holder') as t(r jsonb);
select dblink_exec('ct_lock_holder','rollback');
select dblink_disconnect('ct_lock_holder');
select is((select last_value from pg_temp.ct_received_hits),(select last_value from _ct_lock_hit_before),
 'expired-after-lock guard never reaches real submit');
select is(pg_temp.ct_counts(),(select r from _wo_results where label='before_lock_expiry'),
 'expired-after-lock guard leaves all request/event/channel effects unchanged');

-- The guarded deadline rollback never leaves an identity poisoned for retry.
set local role service_role;
select is(pg_temp.ct_submit(4)->>'status','pending','same controlled identity succeeds after rolled-back deadline failure');
select is(pg_temp.wo_submit(pg_temp.wo_order(),6)->>'status','pending','ordinary non-test submit remains unchanged');
reset role;
select is((select count(*)::int from orders where organization_id=pg_temp.wo_ref('org_a')),0,
 'all pending controlled/ordinary submissions create no canonical orders');
select is((select count(*)::int from kitchen_print_dispatches where organization_id=pg_temp.wo_ref('org_a')),0,
 'all pending controlled/ordinary submissions create no kitchen dispatch');

select * from finish();
rollback;
