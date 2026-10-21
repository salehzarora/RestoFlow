-- BIZBOT-STOREFRONT-FEATURED-ITEMS-001: synthetic rollback-only authority/DTO tests.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.fid(label text) returns uuid language sql immutable as $$
  select md5('bizbot-featured-items-001-'||label)::uuid; $$;
create function pg_temp.patch(ids jsonb default '[]') returns jsonb language sql immutable as $$
  select jsonb_build_object('featured_item_ids',ids); $$;
create function pg_temp.save(label text,ver integer,patch jsonb,restaurant text default 'a') returns jsonb
language sql volatile as $$
  select public.set_restaurant_storefront_featured_items(pg_temp.fid('request-'||label),
    pg_temp.fid(case when restaurant='b' then 'org-b' else 'org-a' end),
    pg_temp.fid('restaurant-'||restaurant),ver,patch); $$;
insert into organizations(id,name,slug,default_currency) values
  (pg_temp.fid('org-a'),'Featured A','featured-a','ILS'),(pg_temp.fid('org-b'),'Featured B','featured-b','ILS');
insert into restaurants(id,organization_id,name,timezone)
select pg_temp.fid('restaurant-'||r),pg_temp.fid(case when r='b' then 'org-b' else 'org-a' end),'Featured '||r,'UTC'
from unnest(array['a','b','missing']) r;
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
select pg_temp.fid('branch-'||r),pg_temp.fid(case when r='b' then 'org-b' else 'org-a' end),
  pg_temp.fid(case when r='a2' then 'restaurant-a' else 'restaurant-'||r end),'Branch '||r,'UTC',false,'exclusive'
from unnest(array['a','a2','b','missing']) r;
insert into menu_categories(id,organization_id,restaurant_id,branch_id,name,is_active)
select pg_temp.fid('category-'||c),pg_temp.fid(case when c='b' then 'org-b' else 'org-a' end),
  pg_temp.fid(case when c='b' then 'restaurant-b' else 'restaurant-a' end),
  case when c='a2' then pg_temp.fid('branch-a2') else null end,'Category '||c,c<>'inactive'
from unnest(array['a','a2','b','inactive']) c;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,display_order)
select pg_temp.fid('item-'||n),pg_temp.fid('org-a'),pg_temp.fid('restaurant-a'),pg_temp.fid('category-a'),
  'Stored product '||n,1234,'ILS',n from generate_series(1,14) n;
insert into menu_items(id,organization_id,restaurant_id,branch_id,menu_category_id,name,base_price_minor,currency_code,is_active,deleted_at)
select pg_temp.fid('item-'||n),pg_temp.fid(case when n='foreign' then 'org-b' else 'org-a' end),
  pg_temp.fid(case when n='foreign' then 'restaurant-b' else 'restaurant-a' end),
  case when n='branch' then pg_temp.fid('branch-a2') else null end,
  pg_temp.fid(case when n='foreign' then 'category-b' when n='parent-inactive' then 'category-inactive' when n='branch' then 'category-a2' else 'category-a' end),
  'Private product '||n,5678,'ILS',n<>'inactive',case when n='deleted' then now() else null end
from unnest(array['foreign','branch','parent-inactive','inactive','deleted']) n;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,
  hero_headline,hero_subline,announcement_text,public_phone,is_published,version)
select pg_temp.fid('restaurant-'||r),pg_temp.fid('org-'||r),pg_temp.fid('branch-'||r),
  'featured-'||r,'Featured '||r,'Existing headline','Existing subline','Existing notice','0521234567',true,10
from unnest(array['a','b']) r;
insert into app_users(id,email) select pg_temp.fid('user-'||u),'featured-'||u||'@example.test'
from unnest(array['manager','cashier','foreign','branch-manager','missing-profile-manager']) u;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values
  (pg_temp.fid('membership-manager'),pg_temp.fid('user-manager'),pg_temp.fid('org-a'),pg_temp.fid('restaurant-a'),null,'manager'),
  (pg_temp.fid('membership-cashier'),pg_temp.fid('user-cashier'),pg_temp.fid('org-a'),pg_temp.fid('restaurant-a'),null,'cashier'),
  (pg_temp.fid('membership-foreign'),pg_temp.fid('user-foreign'),pg_temp.fid('org-b'),null,null,'org_owner'),
  (pg_temp.fid('membership-branch-manager'),pg_temp.fid('user-branch-manager'),pg_temp.fid('org-a'),pg_temp.fid('restaurant-a'),pg_temp.fid('branch-a'),'manager'),
  (pg_temp.fid('membership-missing-profile-manager'),pg_temp.fid('user-missing-profile-manager'),pg_temp.fid('org-a'),pg_temp.fid('restaurant-missing'),null,'manager');
create temp table featured_initial as select to_jsonb(p) profile from restaurant_storefront_profiles p
  where restaurant_id=pg_temp.fid('restaurant-a');
create temp table featured_missing_initial as select to_jsonb(r) restaurant from restaurants r
  where id=pg_temp.fid('restaurant-missing');

select col_type_is('public','restaurant_storefront_profiles','featured_item_ids','uuid[]','bounded UUID set column');
select col_not_null('public','restaurant_storefront_profiles','featured_item_ids','non-null default selection');
select is((select featured_item_ids from restaurant_storefront_profiles where restaurant_id=pg_temp.fid('restaurant-a')),'{}'::uuid[],'existing profiles default empty');
select ok((select relforcerowsecurity from pg_class where oid='public.restaurant_storefront_profiles'::regclass),'existing forced RLS retained');
select is((select provolatile::text from pg_proc where oid='public.storefront_menu_v3(text)'::regprocedure),'s','public reader is STABLE');
select is((select count(*) from regexp_matches(pg_get_functiondef('public.storefront_menu_v3(text)'::regprocedure),'public.storefront_menu_v2\(p_slug\)','g')),1::bigint,'v2 called exactly once');
select ok((select prosecdef and proowner='postgres'::regrole and proconfig=array['search_path=""'] from pg_proc where oid='public.storefront_menu_v3(text)'::regprocedure),'v3 owner and fixed search path');
select ok(not (select prosecdef from pg_proc where oid='public.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb)'::regprocedure),'public mutation wrapper INVOKER');
select is(has_function_privilege(role,'public.storefront_menu_v3(text)','execute'),has_function_privilege(role,'public.storefront_menu_v2(text)','execute'),'v3 mirrors read ACL for '||role)
  from unnest(array['anon','authenticated','service_role']) role;
select ok(not has_function_privilege(role,'public.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb)','execute'),'no mutation grant to '||role)
  from unnest(array['anon','service_role']) role;
select ok(pg_get_functiondef('public.storefront_menu(text)'::regprocedure)!~'featured_item_ids','v1 SQL untouched');
select ok(pg_get_functiondef('public.storefront_menu_v2(text)'::regprocedure)!~'featured_item_ids','v2 SQL untouched');
select ok(pg_get_functiondef('app.set_restaurant_storefront_profile(uuid,uuid,uuid,integer,jsonb)'::regprocedure)!~'featured_item_ids','generic writer unchanged');
select ok(pg_get_functiondef('app.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb)'::regprocedure)!~'featured_item_ids','Home3 writer unchanged');
-- Actual statement snapshot: neither the selected set nor its public-item
-- intersection may jump to a CTE's newer row while v2 still sees old items.
update restaurant_storefront_profiles set featured_item_ids=array[pg_temp.fid('item-1')]
  where restaurant_id=pg_temp.fid('restaurant-a');
with changed_item as (
  update menu_items set is_active=false where id=pg_temp.fid('item-1') returning id
), changed_profile as (
  update restaurant_storefront_profiles set featured_item_ids='{}'::uuid[]
    where restaurant_id=pg_temp.fid('restaurant-a') returning restaurant_id
)
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids',jsonb_build_array(pg_temp.fid('item-1')),
  'one statement uses old selected set AND old public menu snapshot') from changed_item cross join changed_profile;
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids','[]'::jsonb,'next statement observes the committed fixture changes');
select ok(not exists(select 1 from jsonb_array_elements(public.storefront_menu_v3('featured-a')->'items') x where x->>'id'=pg_temp.fid('item-1')::text),'next statement item snapshot also advances');
update menu_items set is_active=true where id=pg_temp.fid('item-1');
set local role anon;
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids','[]'::jsonb,'public default selection empty');
select is((public.storefront_menu_v3('featured-a')-'featured_item_ids'-'server_ts'),(public.storefront_menu_v2('featured-a')-'server_ts'),'all existing public fields retained');
select throws_ok($$select public.set_restaurant_storefront_featured_items(null,null,null,0,'{}')$$,'42501',null,'anon mutation blocked');
reset role;
set local role authenticated;
select set_config('app.current_app_user_id',pg_temp.fid('user-cashier')::text,true);
select is(pg_temp.save('cashier',10,pg_temp.patch())->>'error','permission_denied','cashier refused');
select set_config('app.current_app_user_id',pg_temp.fid('user-foreign')::text,true);
select throws_ok($$select pg_temp.save('foreign',10,pg_temp.patch())$$,'42501',null,'foreign manager cannot read/write this profile');
select set_config('app.current_app_user_id',pg_temp.fid('user-branch-manager')::text,true);
select throws_ok($$select pg_temp.save('branch-manager',10,pg_temp.patch())$$,'42501',null,'branch-only authority cannot edit restaurant-wide profile');
select set_config('app.current_app_user_id',pg_temp.fid('user-manager')::text,true);
select throws_ok($$select pg_temp.save('missing-unauthorized',0,pg_temp.patch(),'missing')$$,'42501',
  'set_restaurant_storefront_featured_items: no covering membership','unauthorized caller cannot inspect or edit missing-profile restaurant');
select set_config('app.current_app_user_id',pg_temp.fid('user-missing-profile-manager')::text,true);
select is(pg_temp.save('missing',0,pg_temp.patch(),'missing')->>'error','not_found','authorized manager gets not_found for absent profile');
reset role;
select ok(not exists(select 1 from restaurant_storefront_profiles where restaurant_id=pg_temp.fid('restaurant-missing')),'missing-profile save creates no profile');
select ok(not exists(select 1 from management_request_results where client_request_id in
  (pg_temp.fid('request-missing-unauthorized'),pg_temp.fid('request-missing'))),'missing-profile refusals claim no request identity');
select ok(not exists(select 1 from audit_events where restaurant_id=pg_temp.fid('restaurant-missing')),'missing-profile refusals create no audit event');
select is((select to_jsonb(r) from restaurants r where id=pg_temp.fid('restaurant-missing')),
  (select restaurant from featured_missing_initial),'missing-profile refusals leave restaurant unchanged');
set local role authenticated;
select set_config('app.current_app_user_id',pg_temp.fid('user-manager')::text,true);
select is(pg_temp.save('stale',9,pg_temp.patch())->>'error','version_conflict','shared profile expected-version CAS');
select is(pg_temp.save('shape-'||n,10,p)->>'error','invalid','invalid complete patch shape '||n)
from (values(1,'null'::jsonb),(2,'[]'::jsonb),(3,'{}'::jsonb),(4,'{"featured_item_ids":[],"price":1}'::jsonb),
  (5,'{"featured_item_ids":null}'::jsonb),(6,'{"featured_item_ids":{}}'::jsonb),
  (7,'{"featured_item_ids":[null]}'::jsonb),(8,'{"featured_item_ids":[[]]}'::jsonb),
  (9,'{"featured_item_ids":[1]}'::jsonb),(10,'{"featured_item_ids":[true]}'::jsonb),
  (11,'{"featured_item_ids":["not-a-uuid"]}'::jsonb)) x(n,p);
select is(pg_temp.save('uuid-newline',10,pg_temp.patch(jsonb_build_array(pg_temp.fid('item-1')::text||E'\n')))->>'error','invalid','UUID suffix control rejected');
select is(pg_temp.save('duplicate-alias',10,pg_temp.patch(jsonb_build_array(pg_temp.fid('item-1')::text,upper(pg_temp.fid('item-1')::text))))->>'error','invalid','UUID aliases are semantic duplicates');
select is(pg_temp.save('thirteen',10,pg_temp.patch((select jsonb_agg(pg_temp.fid('item-'||n)) from generate_series(1,13) n)))->>'error','invalid','thirteen rejected without truncation');
select is(pg_temp.save('bad-'||n,10,pg_temp.patch(jsonb_build_array(pg_temp.fid('item-'||n))))->>'error','invalid','unselectable item '||n)
  from unnest(array['foreign','branch','parent-inactive','inactive','deleted','unknown']) n;
select is(pg_temp.save('valid',10,pg_temp.patch(jsonb_build_array(upper(pg_temp.fid('item-2')::text),pg_temp.fid('item-1'))))->>'version','11','manager saves raw-case valid selection');
select is(pg_temp.save('valid',10,pg_temp.patch(jsonb_build_array(upper(pg_temp.fid('item-2')::text),pg_temp.fid('item-1'))))->>'idempotent_replay','true','exact raw identity replay survives old version');
select throws_ok($$select pg_temp.save('valid',10,pg_temp.patch(jsonb_build_array(pg_temp.fid('item-2'),pg_temp.fid('item-1'))))$$,'42501',null,'normalization-equivalent raw change conflicts');
select is(pg_temp.save('max',11,pg_temp.patch((select jsonb_agg(pg_temp.fid('item-'||n) order by n desc) from generate_series(1,12) n)))->>'version','12','maximum twelve accepted');
select is(pg_temp.save('clear',12,pg_temp.patch())->>'version','13','empty selection deliberately clears');
select is(pg_temp.save('again',13,pg_temp.patch(jsonb_build_array(pg_temp.fid('item-2'),pg_temp.fid('item-1'))))->>'version','14','selection can be restored');
reset role;
select is((select featured_item_ids from restaurant_storefront_profiles where restaurant_id=pg_temp.fid('restaurant-a')),
  (select array_agg(id order by id) from unnest(array[pg_temp.fid('item-1'),pg_temp.fid('item-2')]) x(id)),'storage is canonical UUID set order');
select is((select to_jsonb(p)-'featured_item_ids'-'version'-'updated_at' from restaurant_storefront_profiles p where restaurant_id=pg_temp.fid('restaurant-a')),
  (select profile-'featured_item_ids'-'version'-'updated_at' from featured_initial),'all other merchant/operational/profile fields preserved');
select is((select count(*) from management_request_results where client_request_id=pg_temp.fid('request-valid')),1::bigint,'one request ledger claim');
select throws_ok($$update restaurant_storefront_profiles set featured_item_ids=array[null::uuid] where restaurant_id=pg_temp.fid('restaurant-a')$$,'23514',null,'table rejects null member');
select throws_ok($$update restaurant_storefront_profiles set featured_item_ids=array[[pg_temp.fid('item-1')]] where restaurant_id=pg_temp.fid('restaurant-a')$$,'23514',null,'table rejects multidimensional array');
select throws_ok($$update restaurant_storefront_profiles set featured_item_ids=array_fill(pg_temp.fid('item-1'),array[1],array[0]) where restaurant_id=pg_temp.fid('restaurant-a')$$,'23514',null,'table rejects noncanonical lower bound');
set local role anon;
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids',jsonb_build_array(pg_temp.fid('item-1'),pg_temp.fid('item-2')),'serialized selection follows menu order, not stored UUID/click order');
reset role;

-- REQUIRED RAW DTO NEGATIVE TEST: no adapter is involved. Seed valid-shaped
-- stale/private saved IDs as fixture owner; none may appear in serialized DTO.
update restaurant_storefront_profiles set featured_item_ids=(select array_agg(id order by id) from unnest(array[
  pg_temp.fid('item-1'),pg_temp.fid('item-2'),pg_temp.fid('item-foreign'),pg_temp.fid('item-branch'),
  pg_temp.fid('item-parent-inactive'),pg_temp.fid('item-inactive'),pg_temp.fid('item-deleted')]) x(id))
where restaurant_id=pg_temp.fid('restaurant-a');
set local role anon;
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids',jsonb_build_array(pg_temp.fid('item-1'),pg_temp.fid('item-2')),'raw DTO emits only IDs already in SAME public items');
select ok(position(pg_temp.fid('item-'||n)::text in public.storefront_menu_v3('featured-a')::text)=0,'private UUID absent from entire serialized response: '||n)
  from unnest(array['foreign','branch','parent-inactive','inactive','deleted']) n;
reset role;
update menu_items set is_active=false where id=pg_temp.fid('item-1');
set local role anon;
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids',jsonb_build_array(pg_temp.fid('item-2')),'later inactive choice omitted before serialization');
reset role;
update menu_categories set is_active=false where id=pg_temp.fid('category-a');
set local role anon;
select is(public.storefront_menu_v3('featured-a')->'featured_item_ids','[]'::jsonb,'inactive parent removes saved selections from raw DTO');
reset role;
update menu_categories set is_active=true where id=pg_temp.fid('category-a');
update restaurant_storefront_profiles set storefront_branch_id=pg_temp.fid('branch-a2') where restaurant_id=pg_temp.fid('restaurant-a');
set local role anon;
select ok((public.storefront_menu_v3('featured-a')->'featured_item_ids') ? pg_temp.fid('item-branch')::text,'saved branch switch serves only newly visible existing selection');
reset role;
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.fid('restaurant-a');
set local role anon;
select is(public.storefront_menu_v3('featured-a')->>'error','not_found','unpublished profile discloses no selection');
select ok(not(public.storefront_menu_v3('featured-a') ? 'featured_item_ids'),'failure contains no selection metadata');
reset role;
update memberships set deleted_at=now() where id=pg_temp.fid('membership-manager');
set local role authenticated;
select set_config('app.current_app_user_id',pg_temp.fid('user-manager')::text,true);
select throws_ok($$select pg_temp.save('valid',10,pg_temp.patch(jsonb_build_array(upper(pg_temp.fid('item-2')::text),pg_temp.fid('item-1'))))$$,'42501',null,'revocation blocks even exact replay');
reset role;
select * from finish();
rollback;
