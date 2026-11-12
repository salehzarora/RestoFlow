-- BIZBOT-STOREFRONT-BRAND-HERO-UX-003: focused detail-original contract tests.
-- Rollback-only local test; not an Auth/Storage/Edge publication receipt.
-- Synthetic Storage metadata proves SQL association/authorization, not uploaded
-- bytes, Edge execution, pixel quality or original resolution. No hosted use.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();

create function pg_temp.di(label text) returns uuid language sql immutable as $$
 select md5('ux003-detail-original-focused-'||label)::uuid; $$;
create function pg_temp.dorg(item text) returns uuid language sql immutable as $$
 select pg_temp.di(case when item='foreign' then 'foreign-org' else 'org' end); $$;
create function pg_temp.drest(item text) returns uuid language sql immutable as $$
 select pg_temp.di(case when item='foreign' then 'foreign-rest' else 'rest' end); $$;
create function pg_temp.dkey(item text, treatment text default 'original') returns text language sql immutable as $$
 select pg_temp.dorg(item)::text||'/'||pg_temp.drest(item)::text||'/'||
 case when item='branch-only' then pg_temp.di('other-branch')::text else 'global' end||
 '/menu_item/'||pg_temp.di(item)::text||'/'||pg_temp.di(item||'-'||treatment)::text||'.png'; $$;
create temp table detail_results(label text primary key,result jsonb);
grant select,insert on detail_results to authenticated;
grant select on detail_results to anon;
create function pg_temp.dr(label text) returns jsonb language sql stable as $$
 select result from detail_results where label=$1; $$;
create function pg_temp.dd(label text) returns uuid language sql stable as $$
 select (pg_temp.dr(label)->>'derivative_id')::uuid; $$;
create function pg_temp.dm(label text) returns uuid language sql stable as $$
 select (pg_temp.dr(label)->>'media_id')::uuid; $$;
-- Security invoker helpers: public API calls see the actual current test role.
create function pg_temp.doriginal(item text) returns jsonb language sql volatile as $$
 select public.get_storefront_product_original_v1(pg_temp.dorg(item),pg_temp.drest(item),pg_temp.di(item)); $$;
create function pg_temp.dregister(label text,item text,treatment text,version bigint) returns jsonb language sql volatile as $$
 select public.register_storefront_product_derivative_v1(pg_temp.di('register-'||label),pg_temp.dorg(item),pg_temp.drest(item),pg_temp.di(item),
 pg_temp.dkey(item),pg_temp.doriginal(item)->'source_snapshot',pg_temp.dkey(item,treatment),treatment,version); $$;
create function pg_temp.dstage(label text,item text,registration text,variant text) returns jsonb language sql volatile as $$
 select public.stage_storefront_product_media_v1(pg_temp.di('stage-'||label),pg_temp.dorg(item),pg_temp.drest(item),pg_temp.dd(registration),
 source->>'source_key',source->'source_snapshot',variant,md5(label)||md5('tail-'||label),
 case when variant='w480' then 480 else 960 end,case when variant='w480' then 320 else 640 end,1000)
 from (select public.get_storefront_product_source_v1(pg_temp.dorg(item),pg_temp.drest(item),pg_temp.dd(registration)) source) s; $$;
create function pg_temp.dfinalize(label text,item text,stage text) returns jsonb language sql volatile as $$
 select public.finalize_storefront_product_media_v1(pg_temp.di('finalize-'||label),pg_temp.dorg(item),pg_temp.drest(item),pg_temp.dm(stage)); $$;
create function pg_temp.dchoose(label text,registration text) returns jsonb language sql volatile as $$
 select public.select_storefront_product_derivative_v1(pg_temp.di('choose-'||label),pg_temp.di('org'),pg_temp.di('rest'),pg_temp.dd(registration)); $$;
create function pg_temp.dmenu() returns jsonb language sql stable as $$
 select public.storefront_menu_v10('ux003-detail-original-test'); $$;

-- Minimal independent synthetic restaurant, sibling branch and foreign scope.
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.di('org'),'Detail test','ux003-detail-original-test','ILS'),
 (pg_temp.di('foreign-org'),'Foreign detail test','ux003-detail-original-foreign','ILS');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.di('rest'),pg_temp.di('org'),'Detail test','UTC'),
 (pg_temp.di('foreign-rest'),pg_temp.di('foreign-org'),'Foreign detail test','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values
 (pg_temp.di('branch'),pg_temp.di('org'),pg_temp.di('rest'),'Published branch','UTC',false,'exclusive'),
 (pg_temp.di('other-branch'),pg_temp.di('org'),pg_temp.di('rest'),'Other branch','UTC',false,'exclusive'),
 (pg_temp.di('foreign-branch'),pg_temp.di('foreign-org'),pg_temp.di('foreign-rest'),'Foreign branch','UTC',false,'exclusive');
insert into menu_categories(id,organization_id,restaurant_id,name,is_active) values
 (pg_temp.di('category'),pg_temp.di('org'),pg_temp.di('rest'),'Detail products',true),
 (pg_temp.di('foreign-category'),pg_temp.di('foreign-org'),pg_temp.di('foreign-rest'),'Foreign products',true);
insert into menu_items(id,organization_id,restaurant_id,branch_id,menu_category_id,name,base_price_minor,currency_code,is_active,image_path)
 select pg_temp.di(item),pg_temp.dorg(item),pg_temp.drest(item),
 case when item='branch-only' then pg_temp.di('other-branch') else null::uuid end,
 pg_temp.di(case when item='foreign' then 'foreign-category' else 'category' end),item,1000,'ILS',true,pg_temp.dkey(item)
 from unnest(array['main','branch-only','foreign']) item;
insert into storage.objects(bucket_id,name,version,metadata)
 select 'menu-images',pg_temp.dkey(item,treatment),'generation-1','{"mimetype":"image/png","size":4000}'::jsonb
 from unnest(array['main','branch-only','foreign']) item cross join unnest(array['original','cutout']) treatment;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version)
 values(pg_temp.di('rest'),pg_temp.di('org'),pg_temp.di('branch'),'ux003-detail-original-test','Detail test','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10),
 (pg_temp.di('foreign-rest'),pg_temp.di('foreign-org'),pg_temp.di('foreign-branch'),'ux003-detail-original-foreign','Foreign test','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10);
insert into app_users(id,email) values
 (pg_temp.di('manager'),'manager-ux003-detail@example.test'),
 (pg_temp.di('foreign-manager'),'foreign-ux003-detail@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values
 (pg_temp.di('membership'),pg_temp.di('manager'),pg_temp.di('org'),pg_temp.di('rest'),'manager'),
 (pg_temp.di('foreign-membership'),pg_temp.di('foreign-manager'),pg_temp.di('foreign-org'),pg_temp.di('foreign-rest'),'manager');
insert into detail_results values('original-object-before',(select to_jsonb(o) from storage.objects o where bucket_id='menu-images' and name=pg_temp.dkey('main'))),
 ('profile-before',(select to_jsonb(p) from restaurant_storefront_profiles p where restaurant_id=pg_temp.di('rest')));

-- New helper takes only the pre-admitted item ids (uuid[]; public catalogue cap500).
-- It is private; only the versioned bounded public read is exposed.
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 where p.oid='app.storefront_product_original_images_v1(uuid,uuid,uuid,uuid[])'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),
 'original helper has no PUBLIC execute grant');
select ok(not has_function_privilege(r,'app.storefront_product_original_images_v1(uuid,uuid,uuid,uuid[])','EXECUTE'),
 'original helper is not exposed to '||r) from unnest(array['anon','authenticated','service_role']) r;
select ok(has_function_privilege('anon','public.storefront_menu_v10(text)','EXECUTE') and has_function_privilege('authenticated','public.storefront_menu_v10(text)','EXECUTE'),
 'v10 grants the same public read roles');
select ok(not has_function_privilege('service_role','public.storefront_menu_v10(text)','EXECUTE'), 'v10 adds no service_role execute grant');
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 where p.oid='public.storefront_menu_v10(text)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'), 'v10 has no PUBLIC execute grant');
select ok((select prosecdef and proconfig @> array['search_path=""'] from pg_proc where oid='public.storefront_menu_v10(text)'::regprocedure),
 'v10 is security definer with empty search_path');
select ok((select proconfig @> array['search_path=""'] from pg_proc where oid='app.storefront_product_original_images_v1(uuid,uuid,uuid,uuid[])'::regprocedure),
 'private original helper has empty search_path');
set local role anon;
select throws_ok($$select app.storefront_product_original_images_v1(pg_temp.di('org'),pg_temp.di('rest'),pg_temp.di('branch'),array[pg_temp.di('main')])$$,'42501',null,'anonymous cannot bypass the public catalogue with the helper');
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'no original publication yields an empty manifest');
reset role;

-- Establish a real normal-role selected cutout pair at selection revision one.
set local role authenticated;
select set_config('app.current_app_user_id',pg_temp.di('manager')::text,true);
select throws_ok($$select pg_temp.dregister('foreign-denied','foreign','original',0)$$,'42501',null,'own manager cannot register a foreign original');
insert into detail_results values('cutout',pg_temp.dregister('cutout','main','cutout',0));
insert into detail_results values('cut480',pg_temp.dstage('cut480','main','cutout','w480')),('cut960',pg_temp.dstage('cut960','main','cutout','w960'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id in(pg_temp.dm('cut480'),pg_temp.dm('cut960'));
set local role authenticated;
select is(pg_temp.dfinalize('cut480','main','cut480')->>'ok','true','cutout low rung finalizes as normal manager');
select is(pg_temp.dfinalize('cut960','main','cut960')->>'ok','true','cutout high rung finalizes as normal manager');
select is(pg_temp.dchoose('cutout','cutout')->>'selection_version','1','cutout remains the explicitly selected presentation');
reset role;
insert into detail_results values
 ('v5-before',public.storefront_menu_v5('ux003-detail-original-test')),
 ('v6-before',public.storefront_menu_v6('ux003-detail-original-test')),
 ('v7-before',public.storefront_menu_v7('ux003-detail-original-test')),
 ('v8-before',public.storefront_menu_v8('ux003-detail-original-test')),
 ('v9-before',public.storefront_menu_v9('ux003-detail-original-test')),
 ('selection-before',(select to_jsonb(s) from app.storefront_product_selections s where item_id=pg_temp.di('main')));

-- Publish original w960 ONLY. There is deliberately no choose/select call here.
set local role authenticated;
insert into detail_results values('detail',pg_temp.dregister('detail','main','original',1)),
 ('branch-detail',pg_temp.dregister('branch-detail','branch-only','original',0));
insert into detail_results values('detail960',pg_temp.dstage('detail960','main','detail','w960')),
 ('branch960',pg_temp.dstage('branch960','branch-only','branch-detail','w960'));
select set_config('app.current_app_user_id',pg_temp.di('foreign-manager')::text,true);
insert into detail_results values('foreign-detail',pg_temp.dregister('foreign-detail','foreign','original',0));
insert into detail_results values('foreign960',pg_temp.dstage('foreign960','foreign','foreign-detail','w960'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id in(pg_temp.dm('detail960'),pg_temp.dm('branch960'),pg_temp.dm('foreign960'));
set local role authenticated;
select is(pg_temp.dfinalize('foreign960','foreign','foreign960')->>'ok','true','foreign original is independently authorized and actually publishable');
select set_config('app.current_app_user_id',pg_temp.di('manager')::text,true);
select is(pg_temp.dfinalize('detail960','main','detail960')->>'ok','true','original960-only finalizes without selecting it');
select is(pg_temp.dfinalize('branch960','branch-only','branch960')->>'ok','true','other-branch original is independently publishable');
select is(pg_temp.doriginal('main')->>'selected_derivative_id',pg_temp.dd('cutout')::text,'detail publication preserves selected cutout id');
select is(pg_temp.doriginal('main')->>'selection_version','1','detail publication does not advance selection revision');
reset role;
select is((select count(*)::integer from storefront_media where product_derivative_id=pg_temp.dd('detail') and variant='w480'),0,'detail requires no unused original w480 row');
select is((select to_jsonb(s) from app.storefront_product_selections s where item_id=pg_temp.di('main')),pg_temp.dr('selection-before'),'saved selection is exactly unchanged');
select is(public.storefront_menu_v5('ux003-detail-original-test'),pg_temp.dr('v5-before'),'v5 response remains exact');
select is(public.storefront_menu_v6('ux003-detail-original-test'),pg_temp.dr('v6-before'),'v6 response remains exact');
select is(public.storefront_menu_v7('ux003-detail-original-test'),pg_temp.dr('v7-before'),'v7 response remains exact');
select is(public.storefront_menu_v8('ux003-detail-original-test'),pg_temp.dr('v8-before'),'v8 response remains exact');
select is(public.storefront_menu_v9('ux003-detail-original-test'),pg_temp.dr('v9-before'),'v9 response remains exact');
set local role anon;
select is(pg_temp.dmenu()-'product_original_images_v1',public.storefront_menu_v9('ux003-detail-original-test'),'v10 adds only its independent manifest');
select is(pg_temp.dmenu()->'product_original_images_v1',jsonb_build_array(jsonb_build_object('item_id',pg_temp.di('main'),
 'url','/storage/v1/object/public/storefront-media/'||(pg_temp.dr('detail960')->>'object_key'),'width',960,'height',640)),
 'v10 exposes the exact bounded current original row, not a private path or selected cutout');
select is(pg_temp.dmenu()->'product_images_v1',pg_temp.dr('v9-before')->'product_images_v1','selected responsive cutout pair remains unchanged');
select is(jsonb_array_length(public.storefront_menu_v10('ux003-detail-original-foreign')->'product_original_images_v1'),1,'foreign published profile exposes only its own original');
reset role;
select is(jsonb_array_length(app.storefront_product_original_images_v1(pg_temp.di('org'),pg_temp.di('rest'),pg_temp.di('other-branch'),array[pg_temp.di('main'),pg_temp.di('branch-only')])),2,
 'private helper positive control: global main and own branch-scoped original are eligible in that branch');
select is(app.storefront_product_original_images_v1(pg_temp.di('org'),pg_temp.di('rest'),pg_temp.di('other-branch'),array[]::uuid[]),'[]'::jsonb,
 'empty served-id list excludes otherwise eligible original publications');
select is(jsonb_array_length(app.storefront_product_original_images_v1(pg_temp.di('org'),pg_temp.di('rest'),pg_temp.di('other-branch'),array[pg_temp.di('branch-only')])),1,
 'served-id list excludes eligible main while retaining only its named branch peer');
select is((select to_jsonb(o) from storage.objects o where bucket_id='menu-images' and name=pg_temp.dkey('main')),pg_temp.dr('original-object-before'),'private original storage metadata is unchanged');
select is((select image_path from menu_items where id=pg_temp.di('main')),pg_temp.dkey('main'),'catalogue original path is unchanged');
select is((select to_jsonb(p) from restaurant_storefront_profiles p where restaurant_id=pg_temp.di('rest')),pg_temp.dr('profile-before'),'profile/background/branding pointers are unchanged');

-- Newest VALID publication wins once per item; a retired newest row falls back
-- to the earlier valid same-generation original, not to any cutout.
set local role authenticated;
insert into detail_results values('new-detail',pg_temp.dregister('new-detail','main','original',1));
insert into detail_results values('new-detail960',pg_temp.dstage('new-detail960','main','new-detail','w960'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id=pg_temp.dm('new-detail960');
set local role authenticated;
select is(pg_temp.dfinalize('new-detail960','main','new-detail960')->>'ok','true','second original publication completes normally');
reset role;
-- Clock is not changed: fixture-only publication ordering is explicit because
-- transaction now() is constant. These rows are synthetic metadata only.
update storefront_media set published_at=now()+interval '1 second' where id=pg_temp.dm('new-detail960');
set local role anon;
select is(jsonb_array_length(pg_temp.dmenu()->'product_original_images_v1'),1,'one original row per served item despite two valid registrations');
select is(pg_temp.dmenu()#>>'{product_original_images_v1,0,url}','/storage/v1/object/public/storefront-media/'||(pg_temp.dr('new-detail960')->>'object_key'),'newest valid original publication is deterministic');
reset role;
update storefront_media set unpublished_at=published_at where id=pg_temp.dm('new-detail960');
set local role anon;
select is(pg_temp.dmenu()#>>'{product_original_images_v1,0,url}','/storage/v1/object/public/storefront-media/'||(pg_temp.dr('detail960')->>'object_key'),'unpublished newest is excluded before deterministic selection');
reset role;
update storefront_media set unpublished_at=null where id=pg_temp.dm('new-detail960');
-- Keep only the newest valid fixture for the isolated negative cases below.
update storefront_media set unpublished_at=published_at where id=pg_temp.dm('detail960');

-- A new explicit cutout choice advances selection, not the original generation.
set local role authenticated;
insert into detail_results values('cutout-v2',pg_temp.dregister('cutout-v2','main','cutout',1));
insert into detail_results values('cut2-480',pg_temp.dstage('cut2-480','main','cutout-v2','w480')),('cut2-960',pg_temp.dstage('cut2-960','main','cutout-v2','w960'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id in(pg_temp.dm('cut2-480'),pg_temp.dm('cut2-960'));
set local role authenticated;
select is(pg_temp.dfinalize('cut2-480','main','cut2-480')->>'ok','true','new cutout low rung finalizes');
select is(pg_temp.dfinalize('cut2-960','main','cut2-960')->>'ok','true','new cutout high rung finalizes');
select is(pg_temp.dchoose('cutout-v2','cutout-v2')->>'selection_version','2','new explicit cutout advances revision');
reset role;
set local role anon;
select is(pg_temp.dmenu()#>>'{product_original_images_v1,0,url}','/storage/v1/object/public/storefront-media/'||(pg_temp.dr('new-detail960')->>'object_key'),'selection revision change does not invalidate current original generation');
reset role;

-- Each failure is isolated, queried as anon, then restored as fixture admin.
update menu_items set is_active=false where id=pg_temp.di('main');
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'inactive item cannot be introduced by media');
reset role;
update menu_items set is_active=true where id=pg_temp.di('main');
update menu_categories set is_active=false where id=pg_temp.di('category');
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'inactive category excludes original and branch peer');
reset role;
update menu_categories set is_active=true where id=pg_temp.di('category');
update storage.objects set metadata=jsonb_set(metadata,'{mimetype}','"image/png"') where bucket_id='storefront-media' and name=pg_temp.dr('new-detail960')->>'object_key';
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'wrong public MIME suppresses original');
reset role;
update storage.objects set metadata=jsonb_set(metadata,'{mimetype}','"image/webp"') where bucket_id='storefront-media' and name=pg_temp.dr('new-detail960')->>'object_key';
update storage.objects set metadata=jsonb_set(metadata,'{size}','999') where bucket_id='storefront-media' and name=pg_temp.dr('new-detail960')->>'object_key';
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'wrong public byte size suppresses original');
reset role;
update storage.objects set metadata=jsonb_set(metadata,'{size}','1000') where bucket_id='storefront-media' and name=pg_temp.dr('new-detail960')->>'object_key';
update storage.objects set name=name||'.missing' where bucket_id='storefront-media' and name=pg_temp.dr('new-detail960')->>'object_key';
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'missing exact immutable public object suppresses original');
reset role;
update storage.objects set name=pg_temp.dr('new-detail960')->>'object_key' where bucket_id='storefront-media' and name=(pg_temp.dr('new-detail960')->>'object_key')||'.missing';
update storefront_media set unpublished_at=published_at where id=pg_temp.dm('new-detail960');
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'unpublished original is not exposed');
reset role;
update storefront_media set unpublished_at=null where id=pg_temp.dm('new-detail960');
update storage.objects set version='generation-2',updated_at=updated_at+interval '1 second' where bucket_id='menu-images' and name=pg_temp.dkey('main');
set local role anon;
select is(pg_temp.dmenu()->'product_original_images_v1','[]'::jsonb,'overwritten private original generation invalidates the public detail');
reset role;
select is((select derivative_id from app.storefront_product_selections where item_id=pg_temp.di('main')),pg_temp.dd('cutout-v2'),'public suppression never rewrites the current cutout selection');
select is((select version from app.storefront_product_selections where item_id=pg_temp.di('main')),2::bigint,'negative reads do not advance selection revision');

select * from finish();
rollback;
