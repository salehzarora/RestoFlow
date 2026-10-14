-- POS-ONLINE-INBOX-001: rollback-only, synthetic fixtures and real SQL roles.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions,public,pg_catalog;
set local timezone to 'UTC';
select no_plan();

create function pg_temp.pi_id(label text) returns uuid language sql immutable as
$$select md5('pos-online-inbox-001-'||label)::uuid$$;
create function pg_temp.pi_uuid(n integer) returns uuid language sql immutable as
$$select ('30000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid$$;
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.pi_id('org'),'PI001 Synthetic A','pi001-a','ILS'),
 (pg_temp.pi_id('org_b'),'PI001 Synthetic B','pi001-b','ILS');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.pi_id('restaurant'),pg_temp.pi_id('org'),'PI001 A','UTC'),
 (pg_temp.pi_id('restaurant_b'),pg_temp.pi_id('org_b'),'PI001 B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_rate_bp,tax_mode)
select pg_temp.pi_id(label),pg_temp.pi_id(case when label='branch_b' then 'org_b' else 'org' end),
 pg_temp.pi_id(case when label='branch_b' then 'restaurant_b' else 'restaurant' end),label,'UTC',true,1800,'exclusive'
from unnest(array['branch','sibling','branch_b']) label;
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
values(pg_temp.pi_id('printer'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'),
 'PI001 Synthetic Kitchen','network','kitchen','80mm',true);
insert into menu_categories(id,organization_id,restaurant_id,name) values
 (pg_temp.pi_id('category'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),'PI001 Food'),
 (pg_temp.pi_id('category_b'),pg_temp.pi_id('org_b'),pg_temp.pi_id('restaurant_b'),'PI001 Foreign Food');
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
select pg_temp.pi_id(label),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('category'),
 'PI001 '||label,case when label='free' then 0 else 1000 end,'ILS'
from unnest(array['paid','free']) label;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
values(pg_temp.pi_id('paid_b'),pg_temp.pi_id('org_b'),pg_temp.pi_id('restaurant_b'),pg_temp.pi_id('category_b'),'PI001 Foreign',1000,'ILS');
insert into modifiers(id,organization_id,restaurant_id,menu_item_id,name,selection_type,min_select,max_select,is_required)
values(pg_temp.pi_id('group'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('paid'),'PI001 Choice','single',1,1,true);
insert into modifier_options(id,organization_id,restaurant_id,modifier_id,name,price_delta_minor)
values(pg_temp.pi_id('option'),pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('group'),'PI001 Option',250);
create temp table _pi_hours as select jsonb_build_object('weekly',
 (select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c)) from generate_series(0,6) d
 cross join (values('00:00','12:00'),('11:00','00:00')) w(o,c)),'exceptions','[]'::jsonb) h;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.pi_id('restaurant'),pg_temp.pi_id('org'),pg_temp.pi_id('branch'),'pi001-alpha','PI001 Alpha',true,h,true from _pi_hours;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,pickup_enabled,opening_hours,is_published)
select pg_temp.pi_id('restaurant_b'),pg_temp.pi_id('org_b'),pg_temp.pi_id('branch_b'),'pi001-bravo','PI001 Bravo',true,h,true from _pi_hours;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
select organization_id,restaurant_id,id,true from branches where id in
 (pg_temp.pi_id('branch'),pg_temp.pi_id('sibling'),pg_temp.pi_id('branch_b'));

-- Two POS tills in the same branch, one sibling branch and one foreign tenant.
create temp table _pi_staff as select n,
 pg_temp.pi_id(case when n=4 then 'org_b' else 'org' end) org,
 pg_temp.pi_id(case when n=4 then 'restaurant_b' else 'restaurant' end) restaurant,
 pg_temp.pi_id(case when n=4 then 'branch_b' when n=3 then 'sibling' else 'branch' end) branch,
 pg_temp.pi_id('device-'||n) device,pg_temp.pi_id('pairing-'||n) pairing,
 pg_temp.pi_id('session-'||n) session,pg_temp.pi_id('staff-'||n) staff,
 pg_temp.pi_id('membership-'||n) membership,pg_temp.pi_id('employee-'||n) employee,
 pg_temp.pi_id('pin-'||n) pin,pg_temp.pi_id('shift-'||n) shift
from generate_series(1,4) n;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
select device,org,restaurant,branch,'pos' from _pi_staff;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
select pairing,org,restaurant,branch,device,'active' from _pi_staff;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
select session,org,restaurant,branch,device,pairing,app.hash_provisioning_secret('synthetic-pos-token-'||n),now()+interval '30 days' from _pi_staff;
insert into app_users(id,email) select staff,'pi001-staff-'||n||'@example.test' from _pi_staff;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
select membership,staff,org,restaurant,branch,case when n=2 then 'manager' else 'cashier' end from _pi_staff;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
select employee,org,restaurant,branch,staff,membership,'PI001 Staff '||n from _pi_staff;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
select pin,org,restaurant,branch,session,employee,membership,now()+interval '6 hours' from _pi_staff;
insert into shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
select shift,org,restaurant,branch,device,employee,membership,'pi001-open-'||n,'open' from _pi_staff;

create function pg_temp.pi_order(item text default 'paid') returns jsonb language sql immutable as $$
 select jsonb_build_object('order_type','takeaway','customer',jsonb_build_object('name','PI001 Guest','phone','+972520001001'),
 'notes','PI001 Pickup note','items',jsonb_build_array(jsonb_build_object('menu_item_id',pg_temp.pi_id(item),
 'quantity',2,'modifiers',case when item='paid' then jsonb_build_array(jsonb_build_object(
 'modifier_option_id',pg_temp.pi_id('option'),'quantity',1)) else '[]'::jsonb end)))
$$;
create function pg_temp.pi_request(n integer,item text default 'paid',scope text default 'branch') returns uuid
language plpgsql as $$
declare q jsonb; b public.branches; body jsonb:=pg_temp.pi_order(item); rid uuid:=pg_temp.pi_id('request-'||n);
begin
 select * into b from public.branches where id=pg_temp.pi_id(scope);
 q:=app.price_web_order(case when scope='branch_b' then 'pi001-bravo' else 'pi001-alpha' end,body->'items');
 if q->>'ok'<>'true' then raise exception 'synthetic quote failed: %',q; end if;
 insert into public.web_order_requests(id,organization_id,restaurant_id,branch_id,client_request_id,status_token_hash,payload_hash,
 customer_name,customer_phone,notes,priced_items,currency_code,subtotal_minor,tax_total_minor,grand_total_minor,expires_at,status_until)
 values(rid,b.organization_id,b.restaurant_id,b.id,pg_temp.pi_uuid(n),repeat('a',64),repeat('b',64),
 'PI001 Guest','+972520'||lpad(n::text,6,'0'),'PI001 Pickup note',q->'priced_items','ILS',
 (q->>'subtotal_minor')::bigint,(q->>'tax_total_minor')::bigint,(q->>'grand_total_minor')::bigint,
 now()+interval '15 minutes',now()+interval '24 hours');
 return rid;
end$$;
create function pg_temp.pi_inbox(rid uuid default null,n integer default 1,token text default null) returns jsonb
language sql volatile as $$select public.pos_web_order_inbox(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
 coalesce(token,'synthetic-pos-token-'||n),rid)$$;
create function pg_temp.pi_accept(rid uuid,decision integer default 1,n integer default 1,token text default null) returns jsonb
language sql volatile as $$select public.pos_accept_web_order(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
 coalesce(token,'synthetic-pos-token-'||n),rid,pg_temp.pi_uuid(10000+decision))$$;
create function pg_temp.pi_reject(rid uuid,decision integer default 1,reason text default 'Unavailable',n integer default 1) returns jsonb
language sql volatile as $$select public.pos_reject_web_order(pg_temp.pi_id('pin-'||n),pg_temp.pi_id('device-'||n),
 'synthetic-pos-token-'||n,rid,pg_temp.pi_uuid(10000+decision),reason)$$;
create function pg_temp.pi_counts() returns jsonb language sql security definer set search_path='' as $$
select jsonb_build_object('orders',(select count(*) from public.orders where organization_id=pg_temp.pi_id('org')),
 'items',(select count(*) from public.order_items where organization_id=pg_temp.pi_id('org')),
 'modifiers',(select count(*) from public.order_item_modifiers where organization_id=pg_temp.pi_id('org')),
 'sync',(select count(*) from public.sync_operations where organization_id=pg_temp.pi_id('org')),
 'audit',(select count(*) from public.audit_events where organization_id=pg_temp.pi_id('org')),
 'dispatch',(select count(*) from public.kitchen_print_dispatches where organization_id=pg_temp.pi_id('org')),
 'payments',(select count(*) from public.payments where organization_id=pg_temp.pi_id('org')),
 'decisions',(select count(*) from public.web_order_decisions where organization_id=pg_temp.pi_id('org')))
$$;
create temp table _pi_results(label text primary key,r jsonb);
grant all on _pi_results to authenticated;
select set_config('request.jwt.claim.sub',pg_temp.pi_id('transport-only')::text,true);
-- POS-INBOX FIXTURE END: concurrency harness commits only the prefix above.

select pg_temp.pi_request(n) from generate_series(1,12) n;
select pg_temp.pi_request(13,'paid','sibling');
select pg_temp.pi_request(14,'paid_b','branch_b');
select pg_temp.pi_request(15,'free');
select pg_temp.pi_request(16,'free');

select ok(not prosecdef and proconfig @> array['search_path=""'],proname||' is a pinned INVOKER')
from pg_proc where pronamespace='public'::regnamespace and proname in
 ('pos_web_order_inbox','pos_accept_web_order','pos_reject_web_order');
select ok(not has_function_privilege('anon',p.oid,'EXECUTE') and has_function_privilege('authenticated',p.oid,'EXECUTE'),
 p.proname||' is authenticated only') from pg_proc p where p.pronamespace='public'::regnamespace
 and p.proname in ('pos_web_order_inbox','pos_accept_web_order','pos_reject_web_order');
select ok(not has_table_privilege('authenticated','public.'||t,'SELECT')
 and not has_table_privilege('authenticated','public.'||t,'INSERT'),t||' denies direct staff access')
from unnest(array['web_order_requests','web_order_request_events','web_order_decisions']) t;
select ok(relrowsecurity and relforcerowsecurity,'decision ledger has forced RLS') from pg_class where oid='public.web_order_decisions'::regclass;
select is((select array_agg(cmd order by cmd)::text[] from pg_policies where schemaname='public' and tablename='web_order_decisions'),
 array['DELETE','INSERT','SELECT','UPDATE']::text[],'decision ledger uses four explicit per-command policies');
set local role anon;
select throws_ok($$select pg_temp.pi_inbox()$$,'42501',null,'real anon cannot read inbox');
reset role;
set local role authenticated;
select throws_ok($$select * from public.web_order_decisions$$,'42501',null,'real authenticated cannot read private decisions');
insert into _pi_results values('inbox',pg_temp.pi_inbox());
select is((select r->>'ok' from _pi_results where label='inbox'),'true','token-proven cashier reads through unrelated transport subject');
select is((select jsonb_array_length(r->'requests') from _pi_results where label='inbox'),14,'list includes only own pending branch requests');
select ok((select r::text not like '%status_token_hash%' and r::text not like '%payload_hash%'
 and r::text not like '%synthetic-pos-token%' and r::text not like '%resolved_membership_id%'
 from _pi_results where label='inbox'),'inbox projection omits hashes, device token and staff attribution');
select is(pg_temp.pi_inbox(null,1,'wrong-synthetic-token')->>'error','invalid_session','PIN ID alone cannot replace raw device token');
select is(pg_temp.pi_inbox(pg_temp.pi_id('request-13'))->>'error','not_found','sibling branch targeted read denied');
select is(pg_temp.pi_accept(pg_temp.pi_id('request-13'))->>'error','not_found','sibling branch accept denied');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-14'))->>'error','not_found','foreign tenant reject denied');
select is(pg_temp.pi_inbox(pg_temp.pi_id('request-14'))->>'error','not_found','foreign tenant targeted read denied');
select is(public.pos_web_order_inbox(pg_temp.pi_id('pin-2'),pg_temp.pi_id('device-1'),'synthetic-pos-token-1')->>'error',
 'invalid_session','PIN from another device is refused');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select is(pg_temp.pi_inbox()->>'error','invalid_session','authenticated role without transport subject is refused');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.pi_id('transport-only')::text,true);

-- Mutate only synthetic authority rows and restore after each denial.
update device_sessions set revoked_at=now() where id=pg_temp.pi_id('session-1');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-1'))->>'error','invalid_session','revoked token session cannot accept');
reset role;
update device_sessions set revoked_at=null where id=pg_temp.pi_id('session-1');
update device_pairings set status='revoked',revoked_at=now() where id=pg_temp.pi_id('pairing-1');
set local role authenticated;
select is(pg_temp.pi_inbox()->>'error','invalid_session','revoked pairing cannot read');
reset role;
update device_pairings set status='active',revoked_at=null where id=pg_temp.pi_id('pairing-1');
update devices set device_type='kds' where id=pg_temp.pi_id('device-1');
set local role authenticated;
select is(pg_temp.pi_inbox()->>'error','permission_denied','non-POS device class cannot read');
reset role;
update devices set device_type='pos' where id=pg_temp.pi_id('device-1');
update pin_sessions set expires_at=now()-interval '1 second' where id=pg_temp.pi_id('pin-1');
set local role authenticated;
select is(pg_temp.pi_inbox()->>'error','invalid_session','expired PIN cannot read');
reset role;
update pin_sessions set expires_at=now()+interval '6 hours' where id=pg_temp.pi_id('pin-1');
update memberships set status='revoked' where id=pg_temp.pi_id('membership-1');
set local role authenticated;
select is(pg_temp.pi_reject(pg_temp.pi_id('request-1'))->>'error','invalid_session','removed membership cannot reject');
reset role;
update memberships set status='active',role='kitchen_staff' where id=pg_temp.pi_id('membership-1');
set local role authenticated;
select is(pg_temp.pi_inbox()->>'error','permission_denied','kitchen staff cannot inspect customer money or contact');
reset role;
update memberships set role='accountant' where id=pg_temp.pi_id('membership-1');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-1'))->>'error','permission_denied','accountant cannot accept');
reset role;
update memberships set role='cashier' where id=pg_temp.pi_id('membership-1');
update employee_profiles set employment_status='terminated' where id=pg_temp.pi_id('employee-1');
set local role authenticated;
select is(pg_temp.pi_inbox()->>'error','invalid_session','terminated employee cannot inspect inbox');
reset role;
update employee_profiles set employment_status='active' where id=pg_temp.pi_id('employee-1');
update shifts set status='closed',closed_at=now() where id=pg_temp.pi_id('shift-1');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-1'))->>'error','shift_required','another till open shift is not authority for this till');
reset role;
update shifts set status='open',closed_at=null where id=pg_temp.pi_id('shift-1');

-- Current quote/configuration is authoritative; request snapshot remains frozen.
insert into _pi_results values('before_refusals',pg_temp.pi_counts());
update menu_items set base_price_minor=1001 where id=pg_temp.pi_id('paid');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-2'),2)->>'error','quote_changed','changed live base price refuses frozen quote');
reset role;
update menu_items set base_price_minor=1000 where id=pg_temp.pi_id('paid');
update modifier_options set price_delta_minor=251 where id=pg_temp.pi_id('option');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-3'),3)->>'error','quote_changed','changed live option price refuses frozen quote');
reset role;
update modifier_options set price_delta_minor=250 where id=pg_temp.pi_id('option');
update branches set tax_rate_bp=1900 where id=pg_temp.pi_id('branch');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-4'),4)->>'error','quote_changed','changed live branch tax refuses frozen quote');
reset role;
update branches set tax_rate_bp=1800 where id=pg_temp.pi_id('branch');
insert into menu_item_branch_availability(organization_id,restaurant_id,branch_id,menu_item_id,availability,reason)
values(pg_temp.pi_id('org'),pg_temp.pi_id('restaurant'),pg_temp.pi_id('branch'),pg_temp.pi_id('paid'),'unavailable','sold_out');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-5'),5)->>'error','item_unavailable','current sold-out override refuses acceptance');
reset role;
update menu_item_branch_availability set availability='available',reason=null where menu_item_id=pg_temp.pi_id('paid');
update modifier_options set is_active=false where id=pg_temp.pi_id('option');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-6'),6)->>'error','modifier_selection_invalid','inactive option refuses acceptance');
reset role;
update modifier_options set is_active=true where id=pg_temp.pi_id('option');
update restaurant_storefront_profiles set storefront_branch_id=pg_temp.pi_id('sibling') where restaurant_id=pg_temp.pi_id('restaurant');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-7'),7)->>'error','ordering_unavailable','profile moved to sibling branch fails closed');
reset role;
update restaurant_storefront_profiles set storefront_branch_id=pg_temp.pi_id('branch') where restaurant_id=pg_temp.pi_id('restaurant');
select is(pg_temp.pi_counts(),(select r from _pi_results where label='before_refusals'),'authority and quote refusals create no operational or decision effects');

-- Full real sync invocation is performed, then a malformed inner result is
-- injected. Every canonical row, operation, audit and dispatch must roll back.
create temp table _pi_original_sync as select pg_get_functiondef('app.sync_push(uuid,uuid,jsonb)'::regprocedure) ddl;
create temporary sequence pi_sync_hits;
do $$begin execute replace((select ddl from _pi_original_sync),'CREATE OR REPLACE FUNCTION app.sync_push(',
 'CREATE OR REPLACE FUNCTION pg_temp.pi_real_sync('); end$$;
create or replace function app.sync_push(p_pin_session_id uuid,p_device_id uuid,p_operations jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb; fault text:=current_setting('test.pi_fault',true);
begin
 r:=pg_temp.pi_real_sync(p_pin_session_id,p_device_id,p_operations);
 perform nextval('pg_temp.pi_sync_hits');
 if fault='empty' then return jsonb_set(r,'{results}','[]'::jsonb); end if;
 if fault='inner_failed' then return jsonb_set(jsonb_set(r,'{results,0,ok}','false'::jsonb),'{results,0,status}','"rejected"'::jsonb); end if;
 if fault='wrong_order' then return jsonb_set(r,'{results,0,order_id}',to_jsonb(gen_random_uuid()::text)); end if;
 if fault='wrong_operation' then return jsonb_set(r,'{results,0,local_operation_id}','"wrong-operation"'::jsonb); end if;
 if fault='deadlock' then raise exception 'synthetic post-sync deadlock' using errcode='40P01'; end if;
 if fault='expiry' then perform pg_sleep(2.1); end if;
 return r;
end$$;
create function pg_temp.pi_fault_result(fault text) returns text language plpgsql as $$
begin perform set_config('test.pi_fault',fault,true);
 return extensions.is(pg_temp.pi_accept(pg_temp.pi_id('request-8'),8)->>'error',
 'order_rejected','malformed sync inner result is refused: '||fault); end$$;
select pg_temp.pi_fault_result(fault)
from unnest(array['empty','inner_failed','wrong_order','wrong_operation']) fault;
select set_config('test.pi_fault','deadlock',true);
select throws_ok($$select pg_temp.pi_accept(pg_temp.pi_id('request-8'),8)$$,'40P01',null,
 'post-sync deadlock propagates for same-decision whole-transaction recovery');
select is(pg_temp.pi_counts(),(select r from _pi_results where label='before_refusals'),'malformed post-sync result rolls back all canonical, ledger, audit and dispatch effects');
select is((select status from web_order_requests where id=pg_temp.pi_id('request-8')),'pending','failed inner result leaves request retryable');
select pg_temp.pi_request(18);
alter table web_order_requests disable trigger web_order_request_guard;
with t as(select clock_timestamp() now) update web_order_requests
set created_at=t.now-interval '14 minutes 58 seconds',expires_at=t.now+interval '2 seconds',
 status_until=t.now+interval '23 hours 45 minutes 2 seconds' from t where id=pg_temp.pi_id('request-18');
alter table web_order_requests enable trigger web_order_request_guard;
create temp table _pi_before_expiry_hits as select last_value from pg_temp.pi_sync_hits;
select set_config('test.pi_fault','expiry',true);
select is(pg_temp.pi_accept(pg_temp.pi_id('request-18'),18)->>'error','request_expired',
 'deadline crossed after real canonical sync returns safely refused');
select ok((select last_value from pg_temp.pi_sync_hits)>(select last_value from _pi_before_expiry_hits),
 'post-sync deadline test reached real canonical invocation before deliberate delay');
select is(pg_temp.pi_counts(),(select r from _pi_results where label='before_refusals'),
 'post-sync expiry rolls back canonical order, sync operation, audit, dispatch and mapping');
select is((select status from web_order_requests where id=pg_temp.pi_id('request-18')),'pending',
 'post-sync expiry leaves original request state unchanged');
do $$begin execute (select ddl from _pi_original_sync); end$$;
select set_config('test.pi_fault','',true);

-- Mapping faults occur after canonical submission and must roll back it too.
create function pg_temp.pi_fail_mapping() returns trigger language plpgsql as $$
begin if new.status='accepted' then raise exception 'synthetic mapping failure' using errcode='23514'; end if; return new; end$$;
create trigger zz_pi_fail_mapping before update on web_order_requests for each row execute function pg_temp.pi_fail_mapping();
set local role authenticated;
select throws_ok($$select pg_temp.pi_accept(pg_temp.pi_id('request-9'),9)$$,'23514',null,'unexpected mapping failure propagates outside complete rollback boundary');
reset role;
drop trigger zz_pi_fail_mapping on web_order_requests;
select is(pg_temp.pi_counts(),(select r from _pi_results where label='before_refusals'),'mapping failure rolls back canonical order, sync ledger, audit and dispatch');

set local role authenticated;
insert into _pi_results values('accepted',pg_temp.pi_accept(pg_temp.pi_id('request-8'),8));
select is((select r->>'ok' from _pi_results where label='accepted'),'true','same decision recovers after rolled-back sync failures');
select is((select r->>'status' from _pi_results where label='accepted'),'accepted','accept returns terminal accepted mapping');
insert into _pi_results values('replay',pg_temp.pi_accept(pg_temp.pi_id('request-8'),80,2));
select is((select r->>'replayed' from _pi_results where label='replay'),'true','second valid POS can reconcile same-action uncertain result');
select is((select r->>'canonical_order_id' from _pi_results where label='replay'),
 (select r->>'canonical_order_id' from _pi_results where label='accepted'),'same-action replay returns same canonical ID');
select is((select r->>'decision_id' from _pi_results where label='replay'),
 (select r->>'decision_id' from _pi_results where label='accepted'),'same-action replay returns original decision identity');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-8'),81)->>'error','decision_conflict','opposite terminal intent conflicts');
select is(pg_temp.pi_accept(pg_temp.pi_id('request-10'),8)->>'error','decision_conflict','decision identity cannot be reused for another request');
reset role;
select is((select count(*)::int from orders where organization_id=pg_temp.pi_id('org')),1,'accept and replay create exactly one canonical order');
update memberships set status='revoked' where id=pg_temp.pi_id('membership-1');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-8'),8)->>'error','invalid_session','terminal replay still requires active authority');
reset role;
update memberships set status='active' where id=pg_temp.pi_id('membership-1');
select ok((select o.order_type='takeaway' and o.shift_id=pg_temp.pi_id('shift-1')
 and o.customer_name='PI001 Guest' and o.customer_phone='+972520000008'
 and o.subtotal_minor=2500 and o.tax_total_minor=450 and o.grand_total_minor=2950
 from orders o join web_order_requests w on w.canonical_order_id=o.id where w.id=pg_temp.pi_id('request-8')),
 'canonical path preserves server shift, customer stamping and complete frozen totals');
select ok((select bool_and(i.prep_snapshot is null) from order_items i
 join web_order_requests w on w.canonical_order_id=i.order_id where w.id=pg_temp.pi_id('request-8')),
 'unconfigured item preparation remains SQL NULL through canonical acceptance');
select ok((select employee_profile_id=pg_temp.pi_id('employee-1') and device_id=pg_temp.pi_id('device-1')
 and pin_session_id=pg_temp.pi_id('pin-1') and resolved_membership_id=pg_temp.pi_id('membership-1')
 and to_jsonb(d)::text not like '%PI001 Guest%' and to_jsonb(d)::text not like '%+972%'
 from web_order_decisions d where request_id=pg_temp.pi_id('request-8')),
 'append-only decision attributes real staff/device/PIN and stores no customer PII');
select throws_ok($$update web_order_decisions set decision_id=decision_id$$,'42501',null,'decision ledger cannot be updated');
select throws_ok($$delete from web_order_decisions$$,'42501',null,'decision ledger cannot be deleted');
-- PRINT-003 adds a private referencing fence: PostgreSQL refuses the plain
-- TRUNCATE at the FK boundary before the existing append-only trigger runs.
select throws_ok($$truncate web_order_decisions$$,'0A000',null,'decision ledger cannot be truncated past print fence FK');
select throws_ok($$truncate web_order_decisions cascade$$,'42501',null,'CASCADE still reaches immutable history guard');

insert into _pi_results values('before_reject',pg_temp.pi_counts());
set local role authenticated;
select is(pg_temp.pi_reject(pg_temp.pi_id('request-10'),10,'   Sold out   ')->>'status','rejected','staff can reject without canonical submission');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-10'),100,'Sold out')->>'replayed','true','trimmed identical reason replays');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-10'),101,'Different reason')->>'error','decision_conflict','changed rejection reason conflicts');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-11'),11,'')->>'error','invalid_request','empty rejection reason refused');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-11'),11,E'bad\nreason')->>'error','invalid_request','control character rejection reason refused');
reset role;
select is(pg_temp.pi_counts()-'decisions',(select r-'decisions' from _pi_results where label='before_reject'),'reject and replay create no canonical/sync/audit/dispatch/payment effects');

alter table web_order_requests disable trigger web_order_request_guard;
update web_order_requests set created_at=now()-interval '16 minutes',expires_at=now()-interval '1 minute',
 status_until=now()+interval '23 hours 44 minutes' where id=pg_temp.pi_id('request-11');
alter table web_order_requests enable trigger web_order_request_guard;
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-11'),11)->>'error','request_expired','expired request cannot accept');
select is(pg_temp.pi_reject(pg_temp.pi_id('request-11'),11)->>'error','request_expired','expired request cannot reject');
select is(pg_temp.pi_inbox(pg_temp.pi_id('request-11'))->'requests'->0->>'status','expired','targeted reconciliation derives expired state');
reset role;
select is(pg_temp.pi_counts()-'decisions',(select r-'decisions' from _pi_results where label='before_reject'),'expiry creates no operational effects');

-- The unchanged canonical path retains both kitchen modes and free-order tails.
set local role authenticated;
insert into _pi_results values('kds_free',pg_temp.pi_accept(pg_temp.pi_id('request-16'),16));
reset role;
select is((select o.status from orders o join web_order_requests w on w.canonical_order_id=o.id
 where w.id=pg_temp.pi_id('request-16')),'submitted','zero-total KDS acceptance preserves submitted lifecycle');
update branches set kitchen_workflow_mode='printer_only' where id=pg_temp.pi_id('branch');
set local role authenticated;
insert into _pi_results values('printer_free',pg_temp.pi_accept(pg_temp.pi_id('request-15'),15));
insert into _pi_results values('printer_paid',pg_temp.pi_accept(pg_temp.pi_id('request-12'),12));
select is(pg_temp.pi_accept(pg_temp.pi_id('request-12'),120,2)->>'replayed','true','printer acceptance replay uses existing mapping');
reset role;
select is((select o.status from orders o join web_order_requests w on w.canonical_order_id=o.id
 where w.id=pg_temp.pi_id('request-15')),'completed','zero-total printer-only acceptance preserves canonical auto-completion');
select is((select o.status from orders o join web_order_requests w on w.canonical_order_id=o.id
 where w.id=pg_temp.pi_id('request-12')),'served','chargeable printer-only acceptance preserves direct-print lifecycle');
select is((select count(*)::int from kitchen_print_dispatches where organization_id=pg_temp.pi_id('org')),2,
 'two printer acceptances create exactly two initial dispatches, including replay');
select is((select count(*)::int from payments where organization_id=pg_temp.pi_id('org')),0,'inbox acceptance fabricates no payment');
update menu_items set attributes='{"prep_components":[{"name":"Bun","quantity":1,"unit":"pc"}]}'::jsonb
where id=pg_temp.pi_id('paid');
update modifier_options set kitchen_meat='{"quantity":2,"unit":"pc"}'::jsonb where id=pg_temp.pi_id('option');
select pg_temp.pi_request(17);
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-17'),17)->>'ok','true','configured preparation snapshots also survive canonical acceptance');
reset role;
select is((select i.prep_snapshot from order_items i join web_order_requests w on w.canonical_order_id=i.order_id
 where w.id=pg_temp.pi_id('request-17')),'[{"name":"Bun","quantity":1,"unit":"pc"}]'::jsonb,
 'item preparation snapshot comes from trusted catalogue components');
select is((select m.meat_snapshot from order_item_modifiers m join order_items i on i.id=m.order_item_id
 join web_order_requests w on w.canonical_order_id=i.order_id where w.id=pg_temp.pi_id('request-17')),
 '{"quantity":2,"unit":"pc"}'::jsonb,'modifier preparation snapshot comes from trusted catalogue contribution');

select * from finish();
rollback;
