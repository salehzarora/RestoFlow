-- BIZBOT-STOREFRONT-SITE-THEME-001-API. Synthetic, rollback-only contract checks.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.sid(label text) returns uuid language sql immutable as $$
 select md5('storefront-menu-banner-001-'||label)::uuid;
$$;
create function pg_temp.theme_document(theme jsonb) returns jsonb language sql immutable as $$
 select jsonb_build_object('hero_headline','Theme headline','hero_subline',null,'announcement_text',null,
  'hero',jsonb_build_object('mode','editorial','item_id',null,'format',null,'eyebrow',null,'stamp',null,'footnote',null),
  'announcement_segments',null,'promo',null,'story',null,'category_presentation','[]'::jsonb,'item_presentation','[]'::jsonb,
  'appearance',jsonb_build_object('text_color','#ffffff','button_text_color','#000000','font_family','alexandria',
   'menu_background_media_id',pg_temp.sid('media'),'menu_background_dim',37,'scene_preset','reference_dark','site_theme',theme));
$$;
create function pg_temp.theme_save(label text,document jsonb,version integer,branch uuid default pg_temp.sid('branch'))
returns jsonb language sql volatile as $$
 select public.set_restaurant_storefront_content_v1(pg_temp.sid(label),pg_temp.sid('org'),pg_temp.sid('restaurant'),version,branch,document);
$$;
select has_function('public','storefront_menu_v9',array['text'],'new public version exists');
select has_function('public','get_restaurant_storefront_content_v5',array['uuid','uuid'],'new management version exists');
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.sid('org'),'Site theme A','menu-banner-001-a','ILS'),
 (pg_temp.sid('foreign-org'),'Site theme B','menu-banner-001-b','ILS');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.sid('restaurant'),pg_temp.sid('org'),'Site theme A','UTC'),
 (pg_temp.sid('foreign-restaurant'),pg_temp.sid('foreign-org'),'Site theme B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values
 (pg_temp.sid('branch'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'A','UTC',false,'exclusive'),
 (pg_temp.sid('other-branch'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'A2','UTC',false,'exclusive'),
 (pg_temp.sid('foreign-branch'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-restaurant'),'B','UTC',false,'exclusive');
insert into menu_categories(id,organization_id,restaurant_id,name,is_active)
 values(pg_temp.sid('category'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'Theme category',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active)
 values(pg_temp.sid('item'),pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('category'),'Theme item',1000,'ILS',true);
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,
 opening_hours,is_published,version,primary_color,accent_color,visual_preset)
 values(pg_temp.sid('restaurant'),pg_temp.sid('org'),pg_temp.sid('branch'),'menu-banner-001-a','Site theme A','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10,'#292929','#ff8000','light');
insert into app_users(id,email) values
 (pg_temp.sid('manager'),'site-theme-manager@example.test'),
 (pg_temp.sid('cashier'),'site-theme-cashier@example.test'),
 (pg_temp.sid('foreign-manager'),'site-theme-foreign@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values
 (pg_temp.sid('manager-member'),pg_temp.sid('manager'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'manager'),
 (pg_temp.sid('cashier-member'),pg_temp.sid('cashier'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'cashier'),
 (pg_temp.sid('foreign-member'),pg_temp.sid('foreign-manager'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-restaurant'),'manager');
insert into storage.objects(bucket_id,name) values('restaurant-logos',
 pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('source')||'.jpg');
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 values(pg_temp.sid('media'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'restaurant-logos',
 pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('source')||'.jpg','w960',
 app.storefront_media_prefix(pg_temp.sid('restaurant'))||'/'||repeat('a',64)||'.webp',repeat('a',64),960,720,1000,now());
insert into storage.objects(bucket_id,name,metadata)
 select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}' from storefront_media where id=pg_temp.sid('media');
create temporary table theme_facts(k text primary key,v jsonb);
grant all on theme_facts to authenticated;
select set_config('app.current_app_user_id',pg_temp.sid('manager')::text,true);


create function pg_temp.banner_document() returns jsonb language sql immutable as $$
 select jsonb_set(pg_temp.theme_document('"dark"'),'{appearance}',(pg_temp.theme_document('"dark"')->'appearance')||jsonb_build_object(
 'menu_banner_media_id',pg_temp.sid('media'),'menu_banner_enabled',true,'menu_intro_visible',false,'menu_banner_focal_x',20,'menu_banner_focal_y',75));
$$;
select is(public.storefront_menu_v9('menu-banner-001-a'),public.storefront_menu_v8('menu-banner-001-a'),'absent banner retains exact old public envelope');
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant')),public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant')),'absent banner retains exact old management envelope');
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.banner_document(),array['appearance',k],v))->>'field','appearance.'||k,'strict type/range rejected: '||k||'='||v::text)
 from (values ('menu_banner_enabled','"false"'::jsonb),('menu_intro_visible','0'::jsonb),('menu_banner_focal_x','-1'::jsonb),('menu_banner_focal_y','101'::jsonb),('menu_banner_focal_x','1.5'::jsonb),('menu_banner_focal_y','"50"'::jsonb),('menu_banner_media_id','"https://example.test/original.jpg"'::jsonb)) x(k,v);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.banner_document(),array['appearance',k],'null'))->'error',null::jsonb,'optional null accepted: '||k)
 from unnest(array['menu_banner_media_id','menu_banner_enabled','menu_intro_visible','menu_banner_focal_x','menu_banner_focal_y']) x(k);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.banner_document(),'{appearance,menu_banner_focal_x}','2e1'))#>>'{document,appearance,menu_banner_focal_x}','20','integral exponent normalizes after validation');
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.banner_document(),'{appearance,unknown_banner}','true'))->>'field','appearance','unknown keys still rejected');
set local role authenticated;
insert into theme_facts values('selected',pg_temp.theme_save('banner-select',pg_temp.banner_document(),10));
select is(v->>'version','11','new banner uses existing CAS writer') from theme_facts where k='selected';
select is(pg_temp.theme_save('banner-select',pg_temp.banner_document(),10)->>'idempotent_replay','true','same identity/body replays');
insert into theme_facts values('saved',public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'document');
select is((select v from theme_facts where k='saved'),pg_temp.banner_document(),'management v5 full banner readback');
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance}',
 (select (v->'appearance') - array['menu_banner_media_id','menu_banner_enabled','menu_intro_visible','menu_banner_focal_x','menu_banner_focal_y'] from theme_facts where k='saved'),'strict management v4 strips only new keys');
select is(pg_temp.theme_save('legacy-banner-save',public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'document',11)->>'version','12','old editor still saves');
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'document',(select v from theme_facts where k='saved'),'old editor omission preserves entire new banner and previous values');
select is(pg_temp.theme_save('stale-banner',pg_temp.banner_document(),11)->>'error','version_conflict','stale request cannot replace banner');
select is(pg_temp.theme_save('wrong-banner-branch',pg_temp.banner_document(),12,pg_temp.sid('other-branch'))->>'error','branch_conflict','other branch cannot receive the banner');
select is(pg_temp.theme_save('foreign-banner',jsonb_set(pg_temp.banner_document(),'{appearance,menu_banner_media_id}',to_jsonb(pg_temp.sid('foreign-media')::text)),12)->>'field','appearance.menu_banner_media_id','unavailable/foreign media cannot become selected banner');
reset role;
select is(public.storefront_menu_v9('menu-banner-001-a')#>>'{content_v1,appearance,menu_banner_url}',app.storefront_content_media_url_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('media')),'v9 emits approved public derivative only');
select ok(not(public.storefront_menu_v9('menu-banner-001-a')#>'{content_v1,appearance}' ? 'menu_banner_media_id'),'public read never exposes private media id');
select is(public.storefront_menu_v9('menu-banner-001-a')#>'{content_v1,appearance,menu_banner_enabled}','true'::jsonb,'v9 boolean remains boolean');
select is(public.storefront_menu_v9('menu-banner-001-a')#>'{content_v1,appearance,menu_intro_visible}','false'::jsonb,'independent intro visibility roundtrips');
update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_background_media_id}','null') where restaurant_id=pg_temp.sid('restaurant');
select ok(app.storefront_content_media_in_use_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('media')),'banner is protected as active media reference');
update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_background_media_id}',to_jsonb(pg_temp.sid('media')::text)) where restaurant_id=pg_temp.sid('restaurant');
update storefront_media set unpublished_at=now() where id=pg_temp.sid('media');
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 select pg_temp.sid('media-replacement'),organization_id,restaurant_id,source_bucket,source_key,variant,
 app.storefront_media_prefix(restaurant_id)||'/'||repeat('b',64)||'.webp',repeat('b',64),width,height,bytes,now() from storefront_media where id=pg_temp.sid('media');
insert into storage.objects(bucket_id,name,metadata)
 select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}' from storefront_media where id=pg_temp.sid('media-replacement');
select app.storefront_content_repoint_media_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('media'),pg_temp.sid('media-replacement'));
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>>'{document,appearance,menu_banner_media_id}',pg_temp.sid('media-replacement')::text,'same-source publication replacement preserves selected banner');
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>>'{document,appearance,menu_background_media_id}',pg_temp.sid('media-replacement')::text,'same-source replacement preserves both independent references');
update storefront_media set unpublished_at=now() where id=pg_temp.sid('media-replacement');
update storefront_media set unpublished_at=null where id=pg_temp.sid('media');
select app.storefront_content_repoint_media_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('media-replacement'),pg_temp.sid('media'));

select is(public.storefront_menu_v8('menu-banner-001-a'),public.storefront_menu_v9('menu-banner-001-a')
 #-'{content_v1,appearance,menu_banner_url}' #-'{content_v1,appearance,menu_banner_enabled}' #-'{content_v1,appearance,menu_intro_visible}' #-'{content_v1,appearance,menu_banner_focal_x}' #-'{content_v1,appearance,menu_banner_focal_y}','v8 exact old projection');
select ok(not(public.storefront_menu_v7('menu-banner-001-a')#>'{content_v1,appearance}' ? 'menu_banner_media_id'),'v7 has no banner id');
select ok(not(public.storefront_menu_v6('menu-banner-001-a')#>'{content_v1,appearance}' ? 'menu_banner_enabled'),'v6 has no banner controls');
select ok(not(public.storefront_menu_v5('menu-banner-001-a')#>'{content_v1,appearance}' ? 'menu_intro_visible'),'v5 has no intro controls');
select ok(exists(select 1 from audit_events where restaurant_id=pg_temp.sid('restaurant') and action='settings.storefront.content.updated' and new_values#>>'{appearance,menu_banner_media_id}'=pg_temp.sid('media')::text),'audit captures full banner document');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_banner_enabled}','"false"') where restaurant_id=pg_temp.sid('restaurant')$$,'23514',null,'constraint rejects string booleans independently');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_banner_focal_x}','101') where restaurant_id=pg_temp.sid('restaurant')$$,'23514',null,'constraint rejects out-of-range focal point');
-- No production mutation; retire synthetic media only inside this rolled-back test.
update storefront_media set unpublished_at=now() where id=pg_temp.sid('media');
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance,menu_banner_media_id}','null'::jsonb,'unavailable banner sanitized on management read');
select ok(exists(select 1 from jsonb_array_elements(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'warnings') w where w->>'field'='appearance.menu_banner_media_id'),'new reader warns about unavailable banner');
select ok(not exists(select 1 from jsonb_array_elements(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'warnings') w where w->>'field'='appearance.menu_banner_media_id'),'old reader does not receive unknown warning path');
select is(public.storefront_menu_v9('menu-banner-001-a')#>'{content_v1,appearance,menu_banner_url}','null'::jsonb,'unavailable derivative omitted safely');
update storefront_media set unpublished_at=null where id=pg_temp.sid('media');
set local role authenticated;
select is(pg_temp.theme_save('clear-banner',jsonb_set(pg_temp.banner_document(),'{appearance,menu_banner_media_id}','null'),12)->>'version','13','explicit clear uses ordinary CAS');
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance,menu_banner_media_id}','null'::jsonb,'clear roundtrips');
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>>'{document,appearance,menu_background_media_id}',pg_temp.sid('media')::text,'clearing banner preserves independent background');
reset role;
select set_config('app.current_app_user_id',pg_temp.sid('cashier')::text,true);
set local role authenticated;
select is(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))->>'error','not_found','cashier read remains denied');
select is(pg_temp.theme_save('cashier-banner',pg_temp.banner_document(),13)->>'error','permission_denied','cashier write remains denied');
reset role;
select set_config('app.current_app_user_id',pg_temp.sid('foreign-manager')::text,true);
set local role authenticated;
select throws_ok($$select public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))$$,'42501',null,'foreign manager cannot read banner');
select throws_ok($$select public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('foreign-restaurant'))$$,'42501',null,'mismatched ancestry denied');
select throws_ok($$select pg_temp.theme_save('foreign-banner-save',pg_temp.banner_document(),13)$$,'42501',null,'foreign manager cannot write banner');
reset role;
set local role anon;
select is(public.storefront_menu_v9('menu-banner-001-a')->>'ok','true','public published read works');
select throws_ok($$select public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))$$,'42501',null,'anonymous management read denied');
select is(public.storefront_menu_v9('missing-banner'),public.storefront_menu_v8('missing-banner'),'missing tenant exact failure');
reset role;
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.sid('restaurant');
set local role anon;
select is(public.storefront_menu_v9('menu-banner-001-a')->>'error','not_found','v9 honors unpublished admission');
reset role;
select is((select prosecdef from pg_proc where oid='public.get_restaurant_storefront_content_v5(uuid,uuid)'::regprocedure),false,'public management wrapper remains invoker');
select is((select proconfig from pg_proc where oid='public.storefront_menu_v9(text)'::regprocedure),array['search_path=""'],'v9 empty search_path');
select ok(has_function_privilege('authenticated','public.get_restaurant_storefront_content_v5(uuid,uuid)','execute') and not has_function_privilege('anon','public.get_restaurant_storefront_content_v5(uuid,uuid)','execute'),'management ACL exact auth admission');
select ok(has_function_privilege('anon','public.storefront_menu_v9(text)','execute') and has_function_privilege('authenticated','public.storefront_menu_v9(text)','execute') and not has_function_privilege('service_role','public.storefront_menu_v9(text)','execute'),'v9 no additional direct service-role authority');
select * from finish();
rollback;
