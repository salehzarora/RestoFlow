-- BIZBOT-STOREFRONT-HOME-CONTENT-001: synthetic, rollback-only contracts.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();

create function pg_temp.hid(label text) returns uuid language sql immutable as $$
  select md5('bizbot-home-content-001-'||label)::uuid; $$;
create function pg_temp.patch(head text default 'Headline',sub text default 'Subline',announcement text default 'Announcement')
returns jsonb language sql immutable as $$
  select jsonb_build_object('hero_headline',head,'hero_subline',sub,'announcement_text',announcement); $$;
create function pg_temp.save(label text,expected integer,patch jsonb,restaurant text default 'a') returns jsonb
language sql volatile as $$
  select public.set_restaurant_storefront_home_content(pg_temp.hid('request-'||label),
    pg_temp.hid(case when restaurant='b' then 'org-b' else 'org-a' end),pg_temp.hid('restaurant-'||restaurant),expected,patch); $$;
insert into organizations(id,name,slug,default_currency) values
  (pg_temp.hid('org-a'),'Home A','home-content-a','ILS'),(pg_temp.hid('org-b'),'Home B','home-content-b','ILS');
insert into restaurants(id,organization_id,name,timezone)
select pg_temp.hid('restaurant-'||r),pg_temp.hid(case when r='b' then 'org-b' else 'org-a' end),'Home '||r,'UTC'
from unnest(array['a','b','missing']) r;
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
select pg_temp.hid('branch-'||r),pg_temp.hid(case when r='b' then 'org-b' else 'org-a' end),pg_temp.hid('restaurant-'||r),'Branch '||r,'UTC',false,'exclusive'
from unnest(array['a','b','missing']) r;
insert into menu_categories(id,organization_id,restaurant_id,name)
select pg_temp.hid('category-'||r),pg_temp.hid('org-'||r),pg_temp.hid('restaurant-'||r),'Food '||r from unnest(array['a','b']) r;
insert into menu_items(organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
select pg_temp.hid('org-'||r),pg_temp.hid('restaurant-'||r),pg_temp.hid('category-'||r),'Stored product '||r,1234,'ILS'
from unnest(array['a','b']) r;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,tagline,
  public_phone,opening_hours,is_published,version)
select pg_temp.hid('restaurant-'||r),pg_temp.hid('org-'||r),pg_temp.hid('branch-'||r),'home-content-'||r,'Home '||r,'Original tagline',
  '0521234567',jsonb_build_object('weekly',(select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c))
    from generate_series(0,6) d cross join(values('00:00','12:00'),('11:00','00:00')) w(o,c)),'exceptions','[]'::jsonb),true,10
from unnest(array['a','b']) r;
insert into app_users(id,email) select pg_temp.hid('user-'||u),'home-content-'||u||'@example.test'
from unnest(array['owner','manager','cashier','foreign','branch-manager']) u;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values
  (pg_temp.hid('membership-owner'),pg_temp.hid('user-owner'),pg_temp.hid('org-a'),null,null,'org_owner'),
  (pg_temp.hid('membership-manager'),pg_temp.hid('user-manager'),pg_temp.hid('org-a'),pg_temp.hid('restaurant-a'),null,'manager'),
  (pg_temp.hid('membership-cashier'),pg_temp.hid('user-cashier'),pg_temp.hid('org-a'),pg_temp.hid('restaurant-a'),null,'cashier'),
  (pg_temp.hid('membership-foreign'),pg_temp.hid('user-foreign'),pg_temp.hid('org-b'),null,null,'org_owner'),
  (pg_temp.hid('membership-branch-manager'),pg_temp.hid('user-branch-manager'),pg_temp.hid('org-a'),pg_temp.hid('restaurant-a'),pg_temp.hid('branch-a'),'manager');
create temp table home_initial as select to_jsonb(p) profile,public.storefront_menu('home-content-a') menu
  from restaurant_storefront_profiles p where restaurant_id=pg_temp.hid('restaurant-a');

select is((select count(*)::int from information_schema.columns where table_schema='public' and table_name='restaurant_storefront_profiles'
  and column_name in('hero_headline','hero_subline','announcement_text') and data_type='text' and is_nullable='YES'),3,'three nullable text fields only');
select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='public.restaurant_storefront_profiles'::regclass),'forced profile RLS preserved');
select is((select provolatile::text from pg_proc where oid='public.storefront_menu_v2(text)'::regprocedure),'s','v2 read is STABLE');
select is((select count(*)::int from regexp_matches(pg_get_functiondef('public.storefront_menu_v2(text)'::regprocedure),'public\.storefront_menu\(p_slug\)','g')),1,'exactly one legacy menu invocation');
select ok((select prosecdef and proowner='postgres'::regrole and proconfig=array['search_path=""'] from pg_proc
  where oid='public.storefront_menu_v2(text)'::regprocedure),'public reader fixed owner/search path');
select ok((select prosecdef and proowner='postgres'::regrole and proconfig=array['search_path=""'] from pg_proc
  where oid='app.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb)'::regprocedure),'internal writer fixed owner/search path');
select ok(not (select prosecdef from pg_proc where oid='public.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb)'::regprocedure),'public mutation wrapper remains INVOKER');
select is(has_function_privilege(role,'public.storefront_menu_v2(text)','execute'),has_function_privilege(role,'public.storefront_menu(text)','execute'),'v2 mirrors old read ACL for '||role)
  from unnest(array['anon','authenticated','service_role']) role;
select ok(not has_function_privilege('anon','public.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb)','execute'),'anonymous cannot edit');
select ok(not has_function_privilege('service_role','public.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb)','execute'),'no service-role mutation grant');
select ok(pg_get_functiondef('app.set_restaurant_storefront_profile(uuid,uuid,uuid,integer,jsonb)'::regprocedure) !~ 'hero_headline|hero_subline|announcement_text','generic writer is unchanged and does not route new fields');
set local role anon;
select is(public.storefront_menu_v2('home-content-a')->'home_content',pg_temp.patch(null,null,null),'unconfigured content honestly null');
select throws_ok($$select public.set_restaurant_storefront_home_content(null,null,null,0,'{}')$$,'42501',null,'anon blocked at function ACL');
reset role;
select set_config('app.current_app_user_id',pg_temp.hid('user-cashier')::text,true);
set local role authenticated;
select is(pg_temp.save('cashier',10,pg_temp.patch())->>'error','permission_denied','real cashier denied');
select throws_ok($$update public.restaurant_storefront_profiles set hero_headline='bypass'$$,'42501',null,'no direct authenticated table update');
reset role;
select is((select count(*) from audit_events where organization_id=pg_temp.hid('org-a') and action='settings.storefront.update_denied'),1::bigint,'denial audited');
select set_config('app.current_app_user_id',pg_temp.hid('user-foreign')::text,true);
set local role authenticated;
select throws_ok($$select pg_temp.save('foreign',10,pg_temp.patch())$$,'42501',null,'cross-tenant manager cannot edit');
reset role;
select set_config('app.current_app_user_id',pg_temp.hid('user-branch-manager')::text,true);
select throws_ok($$select pg_temp.save('branch-manager',10,pg_temp.patch())$$,'42501',null,'branch manager does not cover restaurant-level content');
select set_config('app.current_app_user_id',pg_temp.hid('user-owner')::text,true);
select is(pg_temp.save('missing',0,pg_temp.patch(),'missing')->>'error','not_found','missing profile not silently created');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.hid('request-missing')),'missing profile claims no identity');
select set_config('app.current_app_user_id',pg_temp.hid('user-manager')::text,true);
set local role authenticated;
select is(pg_temp.save('first',10,pg_temp.patch('  أهلاً <script>  ',U&'\00A0\2003Subline\FEFF',null))->>'version','11','manager content save bumps shared version once');
reset role;
select is((select hero_headline from restaurant_storefront_profiles where restaurant_id=pg_temp.hid('restaurant-a')),'أهلاً <script>','merchant characters preserved; outer space trimmed');
select is((select hero_subline from restaurant_storefront_profiles where restaurant_id=pg_temp.hid('restaurant-a')),'Subline','explicit Unicode whitespace normalized');
select is((select to_jsonb(p)-array['hero_headline','hero_subline','announcement_text','version','updated_at'] from restaurant_storefront_profiles p where restaurant_id=pg_temp.hid('restaurant-a')),
  (select profile-array['hero_headline','hero_subline','announcement_text','version','updated_at'] from home_initial),'ordinary profile/media fields unchanged');
select is(public.storefront_menu_v2('home-content-a')-'home_content',public.storefront_menu('home-content-a'),'v2 preserves entire current legacy envelope');
select is(public.storefront_menu('home-content-a')-array['menu_version','server_ts'],(select menu-array['menu_version','server_ts'] from home_initial),'menu prices/media/availability/authority unchanged; version evolves normally');
select is((select count(*) from audit_events where organization_id=pg_temp.hid('org-a') and action='settings.storefront.updated'),1::bigint,'successful copy save audited once');
select is(pg_temp.save('first',10,pg_temp.patch('  أهلاً <script>  ',U&'\00A0\2003Subline\FEFF',null))->>'idempotent_replay','true','exact raw replay returns original result before CAS');
select throws_ok($$select pg_temp.save('first',10,pg_temp.patch('أهلاً <script>','Subline',null))$$,'42501',null,'normalization-equivalent changed raw patch is not replay');
select throws_ok($$select pg_temp.save('first',11,pg_temp.patch('  أهلاً <script>  ',U&'\00A0\2003Subline\FEFF',null))$$,'42501',null,'changed expected version under same identity denied');
select is(pg_temp.save('stale',10,pg_temp.patch())->>'error','version_conflict','stale base/content version denied');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.hid('request-stale')),'CAS conflict claims no request');
update memberships set deleted_at=now() where id=pg_temp.hid('membership-manager');
select throws_ok($$select pg_temp.save('first',10,pg_temp.patch('  أهلاً <script>  ',U&'\00A0\2003Subline\FEFF',null))$$,'42501',null,'revoked manager cannot retrieve replay');
update memberships set deleted_at=null where id=pg_temp.hid('membership-manager');
select is(pg_temp.save('wrong-type',11,'[]')->>'reason','patch_not_object','non-object rejected');
select is(pg_temp.save('missing-key',11,'{"hero_headline":null,"hero_subline":null}')->>'reason','missing_field','all three keys required');
select is(pg_temp.save('extra-key',11,pg_temp.patch()||'{"ordering_enabled":true}')->>'reason','unknown_field','cannot smuggle operational configuration');
select is(pg_temp.save('invalid-'||k||'-'||t,11,jsonb_set(pg_temp.patch(),array[k],v))->>'reason',k||'_invalid','reject '||t||' for '||k)
from unnest(array['hero_headline','hero_subline','announcement_text']) k
cross join(values('number','9'::jsonb),('boolean','false'::jsonb),('array','[]'::jsonb),('object','{}'::jsonb),
  ('control',to_jsonb(E'X\tY'::text)),('del',to_jsonb('X'||chr(127)))) bad(t,v);
select is(pg_temp.save('too-long-'||k,11,jsonb_set(pg_temp.patch(),array[k],to_jsonb(repeat('😀',cap+1))))->>'reason',k||'_invalid','code-point limit for '||k)
from(values('hero_headline',120),('hero_subline',180),('announcement_text',240)) caps(k,cap);
select is(pg_temp.save('bounds',11,pg_temp.patch(repeat('😀',120),repeat('א',180),repeat('ع',240)))->>'version','12','exact code-point boundaries accepted');
select is(pg_temp.save('blank',12,pg_temp.patch(U&'\0085\00A0\2003',null,'   '))->>'version','13','blank values normalized to null');
select is(public.storefront_menu_v2('home-content-a')->'home_content',pg_temp.patch(null,null,null),'empty copy has no invented content');
select is(public.set_restaurant_storefront_profile(pg_temp.hid('base-edit'),pg_temp.hid('org-a'),pg_temp.hid('restaurant-a'),13,'{"tagline":"Changed base"}')->>'version','14','old generic writer shares the same CAS');
select is(pg_temp.save('old-after-base',13,pg_temp.patch())->>'error','version_conflict','content cannot overwrite concurrent base edit');
select is(public.set_restaurant_storefront_profile(pg_temp.hid('bad-base-edit'),pg_temp.hid('org-a'),pg_temp.hid('restaurant-a'),14,'{"hero_headline":"wrong route"}')->>'reason','unknown_field','old writer still refuses new field');
select is(pg_temp.save('after-base',14,pg_temp.patch())->>'version','15','content can save after explicit refresh');
select is(public.set_restaurant_storefront_profile(pg_temp.hid('preserving-base'),pg_temp.hid('org-a'),pg_temp.hid('restaurant-a'),15,'{"public_city":"Changed city"}')->>'version','16','old client ordinary edit succeeds');
select is(public.storefront_menu_v2('home-content-a')->'home_content',pg_temp.patch(),'old ordinary update preserves all content');
select is(public.storefront_menu_v2('home-content-b')->'home_content',pg_temp.patch(null,null,null),'Restaurant B receives only its own content');
select is(public.storefront_menu_v2('unknown-home'),public.storefront_menu('unknown-home'),'failure envelopes unchanged');

create function pg_temp.rollback_save() returns boolean language plpgsql as $$
begin
  begin
    perform pg_temp.save('rolled-back',16,pg_temp.patch('Rollback'));
    raise exception 'synthetic abort' using errcode='P0001';
  exception when raise_exception then return true; end;
end; $$;
select ok(pg_temp.rollback_save(),'synthetic transaction failure exercised');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.hid('restaurant-a')),16,'profile rollback atomic');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.hid('request-rolled-back')),'ledger rollback atomic');
select is((select count(*) from audit_events where organization_id=pg_temp.hid('org-a') and action='settings.storefront.updated'),6::bigint,'audit rollback atomic');

-- A volatile mutation inside the calling statement must not refresh either
-- STABLE menu read's snapshot. Subsequent statements see the committed edit.
create function pg_temp.change_during_statement() returns integer language plpgsql volatile as $$
begin
  update public.restaurant_storefront_profiles set hero_headline='Next statement',version=version+1
    where restaurant_id=pg_temp.hid('restaurant-a');
  return 1;
end; $$;
with changed as materialized(select pg_temp.change_during_statement())
select is(public.storefront_menu_v2('home-content-a')#>>'{home_content,hero_headline}','Headline','v2 retains calling-statement snapshot after intervening write') from changed;
select is(public.storefront_menu_v2('home-content-a')#>>'{home_content,hero_headline}','Next statement','next statement sees updated content');
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.hid('restaurant-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','unpublished content not disclosed');
update restaurant_storefront_profiles set is_published=true where restaurant_id=pg_temp.hid('restaurant-a');
update branches set status='suspended' where id=pg_temp.hid('branch-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','inactive storefront branch hidden');
update branches set status='active',deleted_at=now() where id=pg_temp.hid('branch-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','deleted storefront branch hidden');
update branches set deleted_at=null where id=pg_temp.hid('branch-a');
update restaurants set status='suspended' where id=pg_temp.hid('restaurant-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','inactive restaurant hidden');
update restaurants set status='active',deleted_at=now() where id=pg_temp.hid('restaurant-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','deleted restaurant hidden');
update restaurants set deleted_at=null where id=pg_temp.hid('restaurant-a');
update organizations set status='suspended' where id=pg_temp.hid('org-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','inactive organization hidden');
update organizations set status='active',deleted_at=now() where id=pg_temp.hid('org-a');
select is(public.storefront_menu_v2('home-content-a')->>'error','not_found','deleted organization hidden');
update organizations set deleted_at=null where id=pg_temp.hid('org-a');
select throws_ok(format('update public.restaurant_storefront_profiles set hero_headline=%L where restaurant_id=%L',repeat('X',121),pg_temp.hid('restaurant-a')),'23514',null,'table CHECK enforces headline bound');
select throws_ok(format('update public.restaurant_storefront_profiles set announcement_text=%L where restaurant_id=%L',E'control\n',pg_temp.hid('restaurant-a')),'23514',null,'table CHECK enforces controls');
select * from finish();
rollback;
