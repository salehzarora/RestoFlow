-- BIZBOT-STOREFRONT-CONTENT-CONTRACT-001 followup-001: synthetic, rollback-only.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.nid(label text) returns uuid language sql immutable as $$select md5('storefront-content-format-numeric-001-'||label)::uuid;$$;
create function pg_temp.numeric_document(p_format jsonb default '{"text":"Alpha Beta","highlight":{"start":0.0,"end":5.0},"break_before":6.0}'::jsonb) returns jsonb language sql immutable as $$
 select jsonb_build_object('hero_headline','Alpha Beta','hero_subline',null,'announcement_text',null,
 'hero',jsonb_build_object('mode','editorial','item_id',null,'format',p_format,'eyebrow',null,'stamp',null,'footnote',null),
 'announcement_segments',null,'promo',null,'story',null,'category_presentation','[]'::jsonb,'item_presentation','[]'::jsonb);
$$;
create function pg_temp.numeric_version() returns integer language sql stable as $$select (public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))->>'version')::integer;$$;
create function pg_temp.numeric_save(label text,document jsonb,ver integer default null) returns jsonb language sql volatile as $$
 select public.set_restaurant_storefront_content_v1(pg_temp.nid('request-'||label),pg_temp.nid('org'),pg_temp.nid('restaurant'),coalesce(ver,pg_temp.numeric_version()),pg_temp.nid('branch'),document);
$$;
create function pg_temp.numeric_state() returns jsonb language sql volatile as $$
 select jsonb_build_object(
 'profile',(select to_jsonb(p) from public.restaurant_storefront_profiles p where restaurant_id=pg_temp.nid('restaurant')),
 'content',(select coalesce(jsonb_agg(to_jsonb(c) order by c.storefront_branch_id),'[]'::jsonb) from app.storefront_content_profiles c where restaurant_id=pg_temp.nid('restaurant')),
 'categories',(select coalesce(jsonb_agg(to_jsonb(c) order by c.category_id),'[]'::jsonb) from app.storefront_category_presentation c where restaurant_id=pg_temp.nid('restaurant')),
 'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.item_id),'[]'::jsonb) from app.storefront_item_presentation i where restaurant_id=pg_temp.nid('restaurant')),
 'ledger',(select coalesce(jsonb_agg(to_jsonb(r) order by r.client_request_id),'[]'::jsonb) from public.management_request_results r where actor_app_user_id=pg_temp.nid('manager')),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]'::jsonb) from public.audit_events a where restaurant_id=pg_temp.nid('restaurant')));
$$;
insert into organizations(id,name,slug,default_currency) values(pg_temp.nid('org'),'Numeric content fixture','numeric-content-001','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.nid('restaurant'),pg_temp.nid('org'),'Numeric content restaurant','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values(pg_temp.nid('branch'),pg_temp.nid('org'),pg_temp.nid('restaurant'),'Numeric content branch','UTC',false,'exclusive');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,hero_headline,is_published,version) values(pg_temp.nid('restaurant'),pg_temp.nid('org'),pg_temp.nid('branch'),'numeric-content-001','Numeric content','Old headline',true,10);
insert into app_users(id,email) values(pg_temp.nid('manager'),'numeric-content-manager@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values(pg_temp.nid('membership'),pg_temp.nid('manager'),pg_temp.nid('org'),pg_temp.nid('restaurant'),null,'manager');

-- jsonb numeric equality ignores scale, so assert the actual output spellings.
select is(app.storefront_content_document_shape_v1(pg_temp.numeric_document())#>>'{document,hero,format,highlight,start}','0','integral decimal start normalizes to integer JSON');
select is(app.storefront_content_document_shape_v1(pg_temp.numeric_document())#>>'{document,hero,format,highlight,end}','5','integral decimal end normalizes to integer JSON');
select is(app.storefront_content_document_shape_v1(pg_temp.numeric_document())#>>'{document,hero,format,break_before}','6','integral decimal break normalizes to integer JSON');
select is(app.storefront_content_document_shape_v1(pg_temp.numeric_document('{"text":"Alpha Beta","highlight":{"start":0e0,"end":5e0},"break_before":6e0}'))#>>'{document,hero,format,highlight,end}','5','integral exponent JSON supported');
select is(app.storefront_content_document_shape_v1(pg_temp.numeric_document('{"text":"Alpha Beta","highlight":{"start":-0.0,"end":5.000},"break_before":6.000}'))#>>'{document,hero,format,highlight,start}','0','negative zero normalizes without changing text');
select is(app.storefront_content_document_shape_v1(pg_temp.numeric_document('{"text":"Alpha Beta","highlight":null,"break_before":null}'))#>'{document,hero,format}','null'::jsonb,'empty optional tuple retains null normalization');

select set_config('app.current_app_user_id',pg_temp.nid('manager')::text,true);
set local role authenticated;
select is(pg_temp.numeric_save('decimal',pg_temp.numeric_document(),10)->>'version','11','actual RPC accepts complete integral decimal tuple once');
select is(public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))#>>'{document,hero,format,highlight,start}','0','private read emits integer start');
select is(public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))#>>'{document,hero,format,highlight,end}','5','private read emits integer end');
select is(public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))#>>'{document,hero,format,break_before}','6','private read emits integer break');
reset role;
set local role anon;
select is(public.storefront_menu_v4('numeric-content-001')#>>'{content_v1,hero,format,highlight,start}','0','public v4 emits integer start');
select is(public.storefront_menu_v4('numeric-content-001')#>>'{content_v1,hero,format,highlight,end}','5','public v4 emits integer end');
select is(public.storefront_menu_v4('numeric-content-001')#>>'{content_v1,hero,format,break_before}','6','public v4 emits integer break');
reset role;
create temp table before_decimal_replay as select pg_temp.numeric_state() state;
set local role authenticated;
select is(pg_temp.numeric_save('decimal',pg_temp.numeric_document(),10)->>'idempotent_replay','true','exact original decimal input replays original result');
select is(pg_temp.numeric_save('decimal',pg_temp.numeric_document(),10)->>'version','11','decimal replay returns original version');
select throws_ok($$select pg_temp.numeric_save('decimal',pg_temp.numeric_document('{"text":"Alpha Beta","highlight":{"start":0,"end":5},"break_before":6}'),10)$$,'42501',null,'integer-normalized equivalent same identity is still raw fingerprint mismatch');
reset role;
select is(pg_temp.numeric_state(),(select state from before_decimal_replay),'raw replay/mismatch leaves profile, all sidecars, ledger and audit unchanged');

create temp table numeric_invalid_inputs(label text primary key,format jsonb);
insert into numeric_invalid_inputs values
 ('fraction-start','{"text":"Alpha Beta","highlight":{"start":0.25,"end":5},"break_before":6}'),
 ('fraction-end','{"text":"Alpha Beta","highlight":{"start":0,"end":5.25},"break_before":6}'),
 ('fraction-break','{"text":"Alpha Beta","highlight":{"start":0,"end":5},"break_before":6.25}'),
 ('negative','{"text":"Alpha Beta","highlight":{"start":-1.0,"end":5},"break_before":6}'),
 ('negative-end','{"text":"Alpha Beta","highlight":{"start":0,"end":-1.0},"break_before":6}'),
 ('negative-break','{"text":"Alpha Beta","highlight":{"start":0,"end":5},"break_before":-1.0}'),
 ('out-of-bounds-start','{"text":"Alpha Beta","highlight":{"start":121.0,"end":5},"break_before":6}'),
 ('out-of-bounds','{"text":"Alpha Beta","highlight":{"start":0,"end":121.0},"break_before":6}'),
 ('out-of-bounds-break','{"text":"Alpha Beta","highlight":{"start":0,"end":5},"break_before":121.0}'),
 ('huge-number','{"text":"Alpha Beta","highlight":{"start":0,"end":1e1000},"break_before":6}'),
 ('string-number','{"text":"Alpha Beta","highlight":{"start":"0.0","end":5},"break_before":6}'),
 ('boolean-number','{"text":"Alpha Beta","highlight":{"start":false,"end":5},"break_before":6}'),
 ('mixed-null','{"text":"Alpha Beta","highlight":{"start":null,"end":5},"break_before":6}'),
 ('reversed','{"text":"Alpha Beta","highlight":{"start":5.0,"end":0.0},"break_before":6}'),
 ('within-word','{"text":"Alpha Beta","highlight":{"start":1.0,"end":5.0},"break_before":6}'),
 ('break-within-word','{"text":"Alpha Beta","highlight":{"start":0,"end":5},"break_before":1.0}'),
 ('missing-end','{"text":"Alpha Beta","highlight":{"start":0},"break_before":6}'),
 ('extra-format-key','{"text":"Alpha Beta","highlight":{"start":0,"end":5},"break_before":6,"extra":0}');
grant select on numeric_invalid_inputs to authenticated;
create temp table before_numeric_invalid as select pg_temp.numeric_state() state;
set local role authenticated;
select is(pg_temp.numeric_save('invalid-error-'||label,pg_temp.numeric_document(format))->>'error','invalid','invalid numeric format returns fixed error: '||label) from numeric_invalid_inputs order by label;
select is(pg_temp.numeric_save('invalid-reason-'||label,pg_temp.numeric_document(format))->>'reason','headline_format_invalid','invalid numeric format returns fixed reason: '||label) from numeric_invalid_inputs order by label;
select is(pg_temp.numeric_save('invalid-field-'||label,pg_temp.numeric_document(format))->>'field','hero.format','invalid numeric format returns fixed field: '||label) from numeric_invalid_inputs order by label;
reset role;
select is(pg_temp.numeric_state(),(select state from before_numeric_invalid),'all rejected numeric inputs preserve exact profile, sidecars, request claims and audit rows');

-- A later metadata failure must roll back the complete numeric success path.
create function pg_temp.fail_numeric_audit() returns trigger language plpgsql as $$begin if new.restaurant_id=pg_temp.nid('restaurant') and new.action='settings.storefront.content.updated' then raise exception 'synthetic-numeric-postwrite-failure';end if;return new;end;$$;
create trigger numeric_test_postwrite_failure before insert on public.audit_events for each row execute function pg_temp.fail_numeric_audit();
create temp table before_numeric_failure as select pg_temp.numeric_state() state;
set local role authenticated;
select throws_ok($$select pg_temp.numeric_save('postwrite-failure',pg_temp.numeric_document())$$,'P0001','synthetic-numeric-postwrite-failure','integral decimal path raises injected postwrite failure');
reset role;
drop trigger numeric_test_postwrite_failure on public.audit_events;
select is(pg_temp.numeric_state(),(select state from before_numeric_failure),'injected failure rolls back numeric row values, version, sidecars, claim and audit');

set local role authenticated;
select is(pg_temp.numeric_save('break-only',pg_temp.numeric_document('{"text":"Alpha Beta","highlight":null,"break_before":6.0}'))->>'ok','true','break-only integral decimal remains supported');
select is(public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))#>'{document,hero,format,highlight}','null'::jsonb,'break-only normalized highlight remains null');
select is(pg_temp.numeric_save('highlight-only',pg_temp.numeric_document('{"text":"Alpha Beta","highlight":{"start":0.0,"end":5.0},"break_before":null}'))->>'ok','true','highlight-only integral decimal remains supported');
select is(public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))#>'{document,hero,format,break_before}','null'::jsonb,'highlight-only normalized break remains null');
select is(pg_temp.numeric_save('null-format',pg_temp.numeric_document('null'::jsonb))->>'ok','true','null format remains supported');
select is(public.get_restaurant_storefront_content_v1(pg_temp.nid('org'),pg_temp.nid('restaurant'))#>'{document,hero,format}','null'::jsonb,'null format stays null through database read');
reset role;
select * from finish();
rollback;
