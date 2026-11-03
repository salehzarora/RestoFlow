-- BIZBOT-STOREFRONT-CINEMATIC-001B: migration readiness + unchanged read authority.
-- Real installed SQL helpers/roles; synthetic rollback-only principals/claims.
-- This is not a GoTrue login, Storage upload, or HTTP isolation test.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.rid(label text) returns uuid language sql immutable as $$
 select md5('cinematic-readiness-001b-'||label)::uuid;
$$;

select has_function('public','get_restaurant_storefront_content_v2',array['uuid','uuid'],'appearance migration installs the readiness reader');
select ok(not p.prosecdef and p.provolatile='s' and p.proconfig=array['search_path=""'],
 'readiness wrapper is stable, invoker and has an empty search path')
 from pg_proc p where p.oid='public.get_restaurant_storefront_content_v2(uuid,uuid)'::regprocedure;
select ok(has_function_privilege('authenticated','public.get_restaurant_storefront_content_v2(uuid,uuid)','execute'),'authenticated can invoke readiness');
select ok(not has_function_privilege(role,'public.get_restaurant_storefront_content_v2(uuid,uuid)','execute'),'no readiness grant for '||role)
 from unnest(array['anon','service_role']) role;
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 where p.oid='public.get_restaurant_storefront_content_v2(uuid,uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),
 'PUBLIC has no execute privilege');

insert into auth.users(id,email) select pg_temp.rid('auth-'||label),'cinematic-readiness-'||label||'@example.test'
 from unnest(array['owner-a','owner-b','cashier-a','unlinked']) label;
insert into app_users(id,email,auth_user_id) select pg_temp.rid('user-'||label),'cinematic-readiness-'||label||'@example.test',pg_temp.rid('auth-'||label)
 from unnest(array['owner-a','owner-b','cashier-a']) label;
insert into organizations(id,name,slug,default_currency) select pg_temp.rid('org-'||label),'Synthetic readiness '||label,'cinematic-readiness-'||label,'ILS'
 from unnest(array['a','b']) label;
insert into restaurants(id,organization_id,name,timezone) select pg_temp.rid('restaurant-'||label),pg_temp.rid('org-'||label),'Synthetic readiness '||label,'UTC'
 from unnest(array['a','b']) label;
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
 select pg_temp.rid('branch-'||label),pg_temp.rid('org-'||label),pg_temp.rid('restaurant-'||label),'Synthetic branch '||label,'UTC',false,'exclusive'
 from unnest(array['a','b']) label;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,version)
 select pg_temp.rid('restaurant-'||label),pg_temp.rid('org-'||label),pg_temp.rid('branch-'||label),'cinematic-readiness-'||label,'Synthetic readiness '||label,1
 from unnest(array['a','b']) label;
insert into memberships(app_user_id,organization_id,role) values
 (pg_temp.rid('user-owner-a'),pg_temp.rid('org-a'),'org_owner'),
 (pg_temp.rid('user-owner-b'),pg_temp.rid('org-b'),'org_owner');
insert into memberships(app_user_id,organization_id,restaurant_id,role) values
 (pg_temp.rid('user-cashier-a'),pg_temp.rid('org-a'),pg_temp.rid('restaurant-a'),'cashier');

-- No GUC-identity shortcut: resolve through auth.uid and app_users.auth_user_id.
set local app.current_app_user_id='';
select set_config('request.jwt.claim.sub',pg_temp.rid('auth-owner-a')::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.rid('auth-owner-a'),'aal','aal2')::text,true);
set local role authenticated;
select is(app.current_app_user_id(),pg_temp.rid('user-owner-a'),'installed principal helper resolves the synthetic JWT claim');
select is(public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a')),
 public.get_restaurant_storefront_content_v1(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a')),'v2 preserves the complete existing envelope');
select is(public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a'))->>'ok','true','owner reads untouched legacy profile on ready backend');
select ok(not (public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a'))->'document') ? 'appearance','readiness does not require appearance to have been saved');
select throws_ok($$select public.get_restaurant_storefront_content_v2(pg_temp.rid('org-b'),pg_temp.rid('restaurant-b'))$$,'42501',null,'owner A cannot read restaurant B');
select throws_ok($$select public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-b'))$$,'42501',null,'mismatched organization and restaurant denied');
reset role;

select set_config('request.jwt.claim.sub',pg_temp.rid('auth-owner-b')::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.rid('auth-owner-b'),'aal','aal2')::text,true);
set local role authenticated;
select is(public.get_restaurant_storefront_content_v2(pg_temp.rid('org-b'),pg_temp.rid('restaurant-b'))->>'ok','true','owner B reads only its own profile');
select throws_ok($$select public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a'))$$,'42501',null,'owner B cannot read restaurant A');
reset role;

select set_config('request.jwt.claim.sub',pg_temp.rid('auth-cashier-a')::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.rid('auth-cashier-a'),'aal','aal2')::text,true);
set local role authenticated;
select is(public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a'))->>'error','not_found','cashier cannot read editor content');
reset role;
select set_config('request.jwt.claim.sub',pg_temp.rid('auth-unlinked')::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.rid('auth-unlinked'),'aal','aal2')::text,true);
set local role authenticated;
select throws_ok($$select public.get_restaurant_storefront_content_v2(pg_temp.rid('org-a'),pg_temp.rid('restaurant-a'))$$,'42501',null,'unlinked principal denied by existing helper');
reset role;
set local role anon;
select throws_ok($$select public.get_restaurant_storefront_content_v2(null,null)$$,'42501',null,'anonymous denied at wrapper ACL');
reset role;
set local role service_role;
select throws_ok($$select public.get_restaurant_storefront_content_v2(null,null)$$,'42501',null,'service role has no wrapper grant');
reset role;
select * from finish();
rollback;
