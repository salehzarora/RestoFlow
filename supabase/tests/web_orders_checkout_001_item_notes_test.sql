-- WEB-ORDERS-CHECKOUT-001: rollback-only notes contract, synthetic fixtures and real SQL roles.
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
 (pg_temp.pi_id('branch'),pg_temp.pi_id('sibling'),pg_temp.pi_id('branch_b')) on conflict(branch_id) do update set submission_enabled=excluded.submission_enabled;

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

-- The fixture prefix is copied from POS-ONLINE-INBOX-001 for the exact same
-- synthetic authority path, with all assertions below focused on this contract.
grant all on _pi_results to service_role,anon;
update modifiers set selection_type='multiple',allow_quantity=true,max_quantity=3 where id=pg_temp.pi_id('group');
create function pg_temp.co_body() returns jsonb language sql immutable as $$
 select jsonb_set(pg_temp.pi_order(),'{items}',jsonb_build_array(
   jsonb_set(jsonb_set(pg_temp.pi_order()->'items'->0,'{notes}',to_jsonb(U&'\00a0' || 'No onion 🍽' || U&'\3000')),
     '{modifiers,0,quantity}','2'::jsonb),
   jsonb_set(jsonb_set(pg_temp.pi_order()->'items'->0,'{notes}',to_jsonb(E'بدون بصل\nבלי בצל'::text)),
     '{modifiers,0,quantity}','2'::jsonb)))
$$;
create function pg_temp.co_submit(n integer,body jsonb default pg_temp.co_body()) returns jsonb
language sql volatile as $$select public.submit_web_order_request('pi001-alpha',pg_temp.pi_uuid(n),repeat('a',64),body)$$;
create function pg_temp.co_rid(n integer) returns uuid language sql stable security definer set search_path='' as $$
 select id from public.web_order_requests where restaurant_id=pg_temp.pi_id('restaurant')
   and client_request_id=pg_temp.pi_uuid(n)
$$;

select ok(not has_function_privilege('anon','app.normalize_web_order_item_notes(jsonb)','EXECUTE')
 and not has_function_privilege('authenticated','app.normalize_web_order_item_notes(jsonb)','EXECUTE')
 and not has_function_privilege('service_role','app.normalize_web_order_item_notes(jsonb)','EXECUTE'),
 'new normalization helper is private and non-callable by client or service roles');

-- The public catalog adds exactly the two customer quantity constraints.
set local role anon;
insert into _pi_results values ('catalog',public.storefront_menu('pi001-alpha'));
reset role;
select is((select r->'modifiers'->0->>'allow_quantity' from _pi_results where label='catalog'),'true',
 'anonymous storefront projects modifier quantity availability');
select is((select r->'modifiers'->0->>'max_quantity' from _pi_results where label='catalog'),'3',
 'anonymous storefront projects authoritative maximum modifier quantity');
select is((select array_agg(k order by k) from _pi_results,
 jsonb_object_keys(r->'modifiers'->0) k where label='catalog'),
 array['allow_quantity','display_order','id','is_required','item_id','max_quantity','max_select','min_select','name','selection_type']::text[],
 'modifier publication is limited to the existing allowlist plus two quantity keys');
select ok(not exists(select 1 from _pi_results,jsonb_array_elements(r->'items') i
 where label='catalog' and i->>'id'=pg_temp.pi_id('paid_b')::text),
 'quantity publication preserves tenant-scoped item visibility');
update modifiers set allow_quantity=false,max_quantity=null where id=pg_temp.pi_id('group');
select is(public.storefront_menu('pi001-alpha')->'modifiers'->0->'max_quantity','null'::jsonb,
 'unbounded quantity maximum is published as JSON null');
select is(app.price_web_order('pi001-alpha',pg_temp.co_body()->'items')->>'error','modifier_selection_invalid',
 'published constraints never replace SQL quantity enforcement');
update modifiers set allow_quantity=true,max_quantity=3 where id=pg_temp.pi_id('group');

-- SQL validates notes independently from Edge validation; note text has no price authority.
select is(app.price_web_order('pi001-alpha',pg_temp.co_body()->'items')->>'subtotal_minor','6000',
 'notes do not change authoritative item/modifier unit pricing');
select is(app.price_web_order('pi001-alpha',jsonb_set(pg_temp.co_body()->'items','{0,notes}',to_jsonb(repeat('🍽',140))))->>'ok','true',
 '140 Unicode scalar notes are accepted without counting UTF16 code units');
select is(app.price_web_order('pi001-alpha',jsonb_set(pg_temp.co_body()->'items','{0,notes}',bad))->>'error','invalid_request',
 'SQL rejects invalid item notes: '||label)
from (values ('null','null'::jsonb),('number','7'::jsonb),('array','[]'::jsonb),('object','{}'::jsonb),
 ('oversize',to_jsonb(repeat('x',141))),('oversize emoji',to_jsonb(repeat('🍽',141))),
 ('oversize spaces',to_jsonb(repeat(' ',141))),('tab',to_jsonb(E'a\tb'::text)),('CR',to_jsonb(E'a\rb'::text)),
 ('DEL',to_jsonb('a'||chr(127)||'b')),('C1',to_jsonb('a'||chr(133)||'b'))) invalid(label,bad);
select is(app.normalize_web_order_item_notes(jsonb_set(pg_temp.pi_order()->'items','{0,notes}',to_jsonb(U&'\00a0\3000' || E' \n')))->'items',
 pg_temp.pi_order()->'items','empty Unicode whitespace notes normalize to exact old note-free shape');

set local role service_role;
insert into _pi_results values('submitted',pg_temp.co_submit(501));
insert into _pi_results values('replayed',pg_temp.co_submit(501,
 jsonb_set(pg_temp.co_body(),'{items,0,notes}',to_jsonb('No onion 🍽'::text))));
select is(pg_temp.co_submit(501,jsonb_set(pg_temp.co_body(),'{items,0,notes}',to_jsonb('Different note'::text)))->>'error',
 'idempotency_conflict','changed item notes conflict with the immutable request identity');
select is(pg_temp.co_submit(599,jsonb_set(pg_temp.co_body(),'{items,0,notes}','null'::jsonb))->>'error',
 'invalid_request','service RPC rejects invalid notes even without Edge validation');
reset role;
select is((select r->>'status' from _pi_results where label='submitted'),'pending','successful submission remains pending');
select is((select r->>'replayed' from _pi_results where label='replayed'),'true',
 'equivalent normalized notes use exact idempotent replay');
select is((select jsonb_array_length(priced_items) from web_order_requests where id=pg_temp.co_rid(501)),2,
 'same product and modifiers with different notes remain distinct frozen lines');
select is((select priced_items->0->>'notes' from web_order_requests where id=pg_temp.co_rid(501)),'No onion 🍽',
 'immutable quote stores normalized item notes');
select is((select priced_items->1->>'notes' from web_order_requests where id=pg_temp.co_rid(501)),E'بدون بصل\nבלי בצל',
 'immutable quote preserves multiline Arabic and Hebrew notes');
select is((select notes from web_order_requests where id=pg_temp.co_rid(501)),'PI001 Pickup note',
 'order-level notes stay independent from line notes');
select throws_ok($$update web_order_requests set priced_items=jsonb_set(priced_items,'{0,notes}','"changed"')
 where id=pg_temp.co_rid(501)$$,'42501',null,'request guard makes item notes immutable');
select is((select count(*)::int from orders where organization_id=pg_temp.pi_id('org')),0,
 'pending notes never create a premature canonical order');
select is((select count(*)::int from kitchen_print_dispatches where organization_id=pg_temp.pi_id('org')),0,
 'pending notes never dispatch to kitchen');

set local role authenticated;
insert into _pi_results values('inbox',pg_temp.pi_inbox(pg_temp.co_rid(501)));
insert into _pi_results values('accepted',pg_temp.pi_accept(pg_temp.co_rid(501),501));
insert into _pi_results values('accept_replay',pg_temp.pi_accept(pg_temp.co_rid(501),501));
reset role;
select is((select r->'requests'->0->'items'->0->>'notes' from _pi_results where label='inbox'),'No onion 🍽',
 'POS inbox exposes each immutable item note');
select is((select r->'requests'->0->>'notes' from _pi_results where label='inbox'),'PI001 Pickup note',
 'POS inbox keeps order-level notes separate');
select is((select r->>'status' from _pi_results where label='accepted'),'accepted',
 'trusted POS acceptance revalidates the note-bearing quote successfully');
select is((select r->>'replayed' from _pi_results where label='accept_replay'),'true',
 'repeated POS acceptance recovers the same canonical order');
select is((select array_agg(i.notes order by i.notes) from order_items i join web_order_requests w on w.canonical_order_id=i.order_id
 where w.id=pg_temp.co_rid(501)),array['No onion 🍽',E'بدون بصل\nבלי בצל']::text[],
 'both distinct line notes reach canonical order_items without merging');
select is((select count(*)::int from orders where organization_id=pg_temp.pi_id('org')),1,
 'submit replay and accept replay create exactly one canonical order');
select is((select o.notes from orders o join web_order_requests w on w.canonical_order_id=o.id where w.id=pg_temp.co_rid(501)),
 'PI001 Pickup note','canonical order-level notes remain independent');
select is((select sum(m.quantity)::int from order_item_modifiers m join order_items i on i.id=m.order_item_id
 join web_order_requests w on w.canonical_order_id=i.order_id where w.id=pg_temp.co_rid(501)),4,
 'modifier quantities survive note-bearing acceptance');
select is((select sum(i.line_total_minor)::bigint from order_items i join web_order_requests w on w.canonical_order_id=i.order_id
 where w.id=pg_temp.co_rid(501)),6000::bigint,'canonical rows retain server-authoritative pricing');

-- Real KDS sync_pull consumes canonical notes without any reader changes.
update devices set device_type='kds' where id=pg_temp.pi_id('device-2');
update memberships set role='kitchen_staff' where id=pg_temp.pi_id('membership-2');
set local role authenticated;
insert into _pi_results values('kds',public.sync_pull(pg_temp.pi_id('pin-2'),pg_temp.pi_id('device-2'),array['orders','order_items']));
reset role;
select is((select r->>'ok' from _pi_results where label='kds'),'true','real KDS authority can read accepted order graph');
select is((select array_agg(i->>'notes' order by i->>'notes') from _pi_results,
 jsonb_array_elements(r#>'{changes,order_items,rows}') i where label='kds'),array['No onion 🍽',E'بدون بصل\nבלי בצל']::text[],
 'real KDS sync_pull sees both canonical item notes');
select is((select r#>>'{changes,orders,rows,0,notes}' from _pi_results where label='kds'),'PI001 Pickup note',
 'KDS order-level note stays separate');

-- Reprice malformed frozen notes before any canonical writer is invoked.
select pg_temp.pi_request(503);
alter table web_order_requests disable trigger web_order_request_guard;
update web_order_requests set priced_items=jsonb_set(priced_items,'{0,notes}',to_jsonb(repeat('x',141)))
 where id=pg_temp.pi_id('request-503');
alter table web_order_requests enable trigger web_order_request_guard;
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-503'),503)->>'ok','false',
 'POS reprice refuses invalid frozen notes before canonical dispatch');
reset role;
select is((select count(*)::int from orders where organization_id=pg_temp.pi_id('org')),1,
 'invalid frozen notes create no canonical order');

-- An older note-free snapshot keeps its exact shape and remains acceptable.
select pg_temp.pi_request(502);
select ok(not (select priced_items->0 ? 'notes' from web_order_requests where id=pg_temp.pi_id('request-502')),
 'note-free frozen snapshot retains the pre-checkout omitted notes shape');
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.pi_id('request-502'),502)->>'status','accepted',
 'older note-free frozen quote accepts without false quote_changed');
reset role;
select ok((select i.notes is null from order_items i join web_order_requests w on w.canonical_order_id=i.order_id
 where w.id=pg_temp.pi_id('request-502')),'old note-free line remains SQL NULL in canonical notes');

-- Existing direct-print dispatch uses the same canonical snapshots.
update branches set kitchen_workflow_mode='printer_only' where id=pg_temp.pi_id('branch');
set local role service_role;
insert into _pi_results values('printer_submit',pg_temp.co_submit(504));
reset role;
set local role authenticated;
select is(pg_temp.pi_accept(pg_temp.co_rid(504),504)->>'status','accepted','note-bearing printer-only acceptance succeeds');
reset role;
select is((select array_agg(i->>'note' order by i->>'note') from kitchen_print_dispatches d
 join web_order_requests w on w.canonical_order_id=d.order_id,
 jsonb_array_elements(d.money_free_payload->'items') i where w.id=pg_temp.co_rid(504)),array['No onion 🍽',E'بدون بصل\nבלי בצל']::text[],
 'unchanged kitchen dispatch sees complete per-item notes');
select is((select d.money_free_payload->>'order_note' from kitchen_print_dispatches d
 join web_order_requests w on w.canonical_order_id=d.order_id where w.id=pg_temp.co_rid(504)),'PI001 Pickup note',
 'unchanged kitchen dispatch sees separate order-level note');
select is((select count(*)::int from kitchen_print_dispatches where organization_id=pg_temp.pi_id('org')),1,
 'only the accepted printer-mode order creates one dispatch');
select is((select count(*)::int from payments where organization_id=pg_temp.pi_id('org')),0,
 'note-bearing checkout acceptance fabricates no payment');

select * from finish();
rollback;
