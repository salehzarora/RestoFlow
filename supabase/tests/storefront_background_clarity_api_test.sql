-- BIZBOT-STOREFRONT-BACKGROUND-CLARITY-001-API. Rollback-only synthetic scopes.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();

create function pg_temp.id(label text) returns uuid language sql immutable as $$
  select md5('menu-background-clarity-v1-'||label)::uuid;
$$;
create function pg_temp.path(label text) returns text language sql immutable as $$
 select pg_temp.id('o-'||label)||'/'||pg_temp.id('r-'||label)||'/logo/'||pg_temp.id('source-'||label)||'.jpg';
$$;
insert into organizations(id,name,slug,default_currency) select pg_temp.id('o-'||n),n,'background-clarity-'||n,'ILS' from unnest(array['a','b']) n;
insert into restaurants(id,organization_id,name,timezone) select pg_temp.id('r-'||n),pg_temp.id('o-'||n),n,'UTC' from unnest(array['a','b']) n;
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
 select pg_temp.id('b-'||n),pg_temp.id('o-'||n),pg_temp.id('r-'||n),n,'UTC',false,'exclusive' from unnest(array['a','b']) n;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version)
 select pg_temp.id('r-'||n),pg_temp.id('o-'||n),pg_temp.id('b-'||n),'background-clarity-'||n,n,'0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10 from unnest(array['a','b']) n;
insert into app_users(id,email) select pg_temp.id('user-'||n),'bg-'||n||'@example.test' from unnest(array['a','b','branch']) n;
insert into memberships(id,app_user_id,organization_id,restaurant_id,role)
 select pg_temp.id('m-'||n),pg_temp.id('user-'||n),pg_temp.id('o-'||n),pg_temp.id('r-'||n),'manager' from unnest(array['a','b']) n;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
 values(pg_temp.id('mb'),pg_temp.id('user-branch'),pg_temp.id('o-a'),pg_temp.id('r-a'),pg_temp.id('b-a'),'manager');
insert into storage.objects(bucket_id,name) select 'restaurant-logos',pg_temp.path(n) from unnest(array['a','b']) n;
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 select pg_temp.id('base-'||n),pg_temp.id('o-'||n),pg_temp.id('r-'||n),'restaurant-logos',pg_temp.path(n),'w960',
 app.storefront_media_prefix(pg_temp.id('r-'||n))||'/'||repeat(n,64)||'.webp',repeat(n,64),960,720,1000,now() from unnest(array['a','b']) n;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}'
 from storefront_media where id in(pg_temp.id('base-a'),pg_temp.id('base-b'));
insert into app.storefront_content_profiles(organization_id,restaurant_id,storefront_branch_id,appearance)
 select pg_temp.id('o-'||n),pg_temp.id('r-'||n),pg_temp.id('b-'||n),
 jsonb_build_object('text_color',null,'button_text_color',null,'menu_background_media_id',pg_temp.id('base-'||n),'menu_background_dim',15)
 from unnest(array['a','b']) n;

create temp table facts(k text primary key,v jsonb not null);
grant select,insert on facts to authenticated;
create function pg_temp.source(n text) returns jsonb language sql stable as $$
 select public.get_storefront_background_source_v1(pg_temp.id('o-'||n),pg_temp.id('r-'||n),pg_temp.id('b-'||n),pg_temp.id('base-'||n));
$$;
create function pg_temp.stage(label text,snapshot jsonb,width integer default 2560,height integer default 1920,
 bytes integer default 190000,hash text default repeat('c',64),base_hash text default repeat('a',64)) returns jsonb language sql as $$
 select public.stage_storefront_background_variant_v1(pg_temp.id(label),pg_temp.id('o-a'),pg_temp.id('r-a'),pg_temp.id('b-a'),
 pg_temp.id('base-a'),snapshot,base_hash,hash,width,height,bytes);
$$;
create function pg_temp.finalize(label text) returns jsonb language sql as $$
 select public.finalize_storefront_background_variant_v1(pg_temp.id(label),pg_temp.id('o-a'),pg_temp.id('r-a'),
 (select (v->>'variant_id')::uuid from facts where k='stage'));
$$;
insert into facts values ('v6',public.storefront_menu_v6('background-clarity-a'));
select ok((select v#>>'{content_v1,appearance,menu_background_url}' is not null from facts where k='v6'),'fixture exposes real eligible selected base');
select is(public.storefront_menu_v7('background-clarity-a'),public.storefront_menu_v6('background-clarity-a'),'eligible existing selection without companion returns exact legacy response');
select is(public.storefront_menu_v7('absent-clarity'),public.storefront_menu_v6('absent-clarity'),'missing slug retains exact legacy response');
select ok((select relrowsecurity from pg_class where oid='app.storefront_background_variants'::regclass),'registry has RLS');
select ok(not has_table_privilege(r,'app.storefront_background_variants','SELECT,INSERT,UPDATE,DELETE'),'registry denies every direct privilege to '||r)
 from unnest(array['anon','authenticated','service_role']) r;
select isnt(app.storefront_background_prefix_v1(pg_temp.id('r-a')),app.storefront_media_prefix(pg_temp.id('r-a')),'background namespace distinct from shared c4 namespace');
select isnt(app.storefront_background_prefix_v1(pg_temp.id('r-a')),app.storefront_background_prefix_v1(pg_temp.id('r-b')),'restaurant namespaces are distinct');
set local role anon;
select is(public.storefront_menu_v7('background-clarity-a')->>'ok','true','anonymous may use v7');
select throws_ok($$select pg_temp.source('a')$$,'42501',null,'anonymous cannot read private source');
reset role;

select set_config('app.current_app_user_id',pg_temp.id('user-branch')::text,true);
set local role authenticated;
select throws_ok($$select pg_temp.source('a')$$,'42501',null,'branch-only role cannot acquire restaurant-wide publication authority');
reset role;
select set_config('app.current_app_user_id',pg_temp.id('user-a')::text,true);
set local role authenticated;
insert into facts values ('source',pg_temp.source('a'));
select is((select v->>'source_key' from facts where k='source'),pg_temp.path('a'),'manager source is exact eligible original key');
select is((select v->>'base_hash' from facts where k='source'),repeat('a',64),'source binds c4 parent bytes');
select throws_ok($$select pg_temp.source('b')$$,'42501',null,'manager cannot acquire foreign source');
select is(public.get_storefront_background_source_v1(pg_temp.id('o-a'),pg_temp.id('r-a'),pg_temp.id('b-a'),pg_temp.id('base-b'))->>'error','not_found','foreign parent id excluded');
select is(public.get_storefront_background_source_v1(pg_temp.id('o-a'),pg_temp.id('r-a'),pg_temp.id('b-b'),pg_temp.id('base-a'))->>'error','not_found','wrong branch excluded');
select is(pg_temp.stage('stale','{}')->>'error','source_stale','stale source generation rejected');
select is(pg_temp.stage('wrong-base',v->'source_snapshot',base_hash=>repeat('1',64))->>'error','source_stale','wrong base hash rejected') from facts where k='source';
select is(pg_temp.stage('invalid',v->'source_snapshot',w,h,b)->>'error','invalid','invalid size/cost/aspect rejected '||w||'x'||h||'/'||b)
 from facts cross join (values(960,720,5000),(2561,1920,5000),(2560,1920,524289),(2500,400,5000),(null,1920,5000)) limits(w,h,b) where k='source';
insert into facts select 'stage',pg_temp.stage('stage',v->'source_snapshot') from facts where k='source';
select is(v->>'state','staged','manager stages new companion') from facts where k='stage';
select is(v->>'variant','bg2560','registered variant fixed') from facts where k='stage';
select is(v->>'recipe','storefront-background-b1','registered recipe fixed') from facts where k='stage';
select is(pg_temp.stage('stage',s.v->'source_snapshot'),r.v,'same stage request replays exact registered output') from facts s,facts r where s.k='source' and r.k='stage';
select is(pg_temp.stage('again',s.v->'source_snapshot'),r.v,'different request for identical source/recipe reuses row') from facts s,facts r where s.k='source' and r.k='stage';
select is(pg_temp.stage('collision',v->'source_snapshot',hash=>repeat('d',64))->>'error','object_conflict','conflicting declaration cannot steal same generation') from facts where k='source';
select is(pg_temp.finalize('finish')->>'error','object_mismatch','missing public object cannot finalize');
select throws_ok($$insert into storage.objects(bucket_id,name) values('storefront-media',repeat('0',32)||'/'||repeat('c',64)||'.webp')$$,
 '42501',null,'unregistered immutable key denied');
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',v->>'object_key','{"mimetype":"image/webp","size":19}' from facts where k='stage';
select is(pg_temp.finalize('finish')->>'error','object_mismatch','wrong actual object size fails closed');
reset role;
update storage.objects set metadata='{"mimetype":"image/jpeg","size":190000}' where bucket_id='storefront-media' and name=(select v->>'object_key' from facts where k='stage');
set local role authenticated;
select is(pg_temp.finalize('finish')->>'error','object_mismatch','wrong actual MIME fails closed');
reset role;
update storage.objects set metadata='{"mimetype":"image/webp","size":190000}' where bucket_id='storefront-media' and name=(select v->>'object_key' from facts where k='stage');
select is(public.storefront_menu_v7('background-clarity-a'),public.storefront_menu_v6('background-clarity-a'),'staging alone is invisible on public menu');
set local role authenticated;
insert into facts values('finish',pg_temp.finalize('finish'));
select is(v->>'state','published','published state returned after storage verification') from facts where k='finish';
select is(pg_temp.finalize('finish'),v,'confirmed final request replays') from facts where k='finish';
select is(pg_temp.finalize('second'),v,'second final request reuses same publication') from facts where k='finish';
with changed as(update storage.objects set metadata='{}' where bucket_id='storefront-media' and name=(select v->>'object_key' from facts where k='stage') returning 1)
 select is(count(*),0::bigint,'registered companion cannot be overwritten') from changed;
-- Storage's normal delete trigger prohibits direct SQL DELETE by design; use its test-only switch
-- here to prove that even when that trigger permits a DELETE, the caller still has no eligible row.
set local storage.allow_delete_query='true';
with removed as(delete from storage.objects where bucket_id='storefront-media' and name=(select v->>'object_key' from facts where k='stage') returning 1)
 select is(count(*),0::bigint,'registered companion cannot be deleted by authenticated manager') from removed;
reset role;
select is((select count(*) from app.storefront_background_variants where restaurant_id=pg_temp.id('r-a')),1::bigint,'duplicate requests create a single variant');
select is((select count(*) from audit_events where restaurant_id=pg_temp.id('r-a') and action='settings.storefront.background.published'),1::bigint,'one published audit');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.id('r-a')),10,'publication preserves profile version');
select is(public.storefront_menu_v6('background-clarity-a'),(select v from facts where k='v6'),'old reader output unchanged after publication');
select is(public.storefront_menu_v7('background-clarity-a')-'menu_background_images_v1',public.storefront_menu_v6('background-clarity-a'),'v7 preserves every legacy field');
select is(public.storefront_menu_v7('background-clarity-a')->'menu_background_images_v1',
 jsonb_build_object('base_url',m#>>'{content_v1,appearance,menu_background_url}','variants',jsonb_build_array(
 jsonb_build_object('url',m#>>'{content_v1,appearance,menu_background_url}','width',960,'height',720),
 jsonb_build_object('url','/storage/v1/object/public/storefront-media/'||(v->>'object_key'),'width',2560,'height',1920))),
 'only public URL and actual dimensions of the eligible pair appear') from facts cross join lateral (select public.storefront_menu_v6('background-clarity-a') m) menu where k='stage';
select is(public.storefront_menu_v7('background-clarity-b'),public.storefront_menu_v6('background-clarity-b'),'other tenant receives no companion');
select set_config('app.current_app_user_id',pg_temp.id('user-b')::text,true);
set local role authenticated;
select throws_ok($$select pg_temp.finalize('foreign')$$,'42501',null,'foreign actor cannot finalize');
select throws_ok($$select pg_temp.stage('foreign-stage','{}')$$,'42501',null,'foreign actor cannot stage');
select is((select count(*) from storage.objects where bucket_id='storefront-media' and name=(select v->>'object_key' from facts where k='stage')),0::bigint,
 'foreign authenticated manager has no registered-object metadata SELECT');
reset role;
update app.storefront_content_profiles set appearance=appearance-'menu_background_media_id' where restaurant_id=pg_temp.id('r-a');
select is(public.storefront_menu_v7('background-clarity-a'),public.storefront_menu_v6('background-clarity-a'),'cleared selection immediately suppresses companion');
update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_background_media_id}',to_jsonb(pg_temp.id('base-a'))) where restaurant_id=pg_temp.id('r-a');
-- Finalized objects and their parent are revalidated on every projection.
update storage.objects set metadata='{"mimetype":"image/webp","size":1}' where bucket_id='storefront-media'
 and name=(select v->>'object_key' from facts where k='stage');
select is(public.storefront_menu_v7('background-clarity-a'),public.storefront_menu_v6('background-clarity-a'),'damaged high object suppresses the optional manifest');
update storage.objects set metadata='{"mimetype":"image/webp","size":190000}' where bucket_id='storefront-media'
 and name=(select v->>'object_key' from facts where k='stage');
update storefront_media set unpublished_at=now() where id=pg_temp.id('base-a');
select is(public.storefront_menu_v7('background-clarity-a'),public.storefront_menu_v6('background-clarity-a'),'retracted base suppresses companion');
update storefront_media set unpublished_at=null where id=pg_temp.id('base-a');
select ok(public.storefront_menu_v7('background-clarity-a') ? 'menu_background_images_v1','eligible restored parent and object expose the exact pair again');
update storage.objects set version='generation-2' where bucket_id='restaurant-logos' and name=pg_temp.path('a');
select is(public.storefront_menu_v7('background-clarity-a'),public.storefront_menu_v6('background-clarity-a'),'same-key private overwrite suppresses stale high resource');
select set_config('app.current_app_user_id',pg_temp.id('user-a')::text,true);
set local role authenticated;
select is(pg_temp.finalize('finish')->>'error','source_stale','generation checked before confirmed final replay');
select is(pg_temp.stage('stage',v->'source_snapshot')->>'error','source_stale','generation checked before staged request replay') from facts where k='source';
reset role;
select * from finish();
rollback;
