-- BIZBOT-STOREFRONT-DESKTOP-BANNER-FIT-001: focused responsive banner contract.
-- Rollback-only synthetic SQL checks. Storage rows prove association/authority,
-- not uploaded bytes, Edge publication, browser decoding or visual quality.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.sid(label text) returns uuid language sql immutable as $$
 select md5('storefront-responsive-banner-001-'||label)::uuid;
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
select has_function('public','storefront_menu_v11',array['text'],'new public version exists');
select has_function('public','get_restaurant_storefront_content_v6',array['uuid','uuid'],'new management version exists');
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.sid('org'),'Site theme A','responsive-banner-001-a','ILS'),
 (pg_temp.sid('foreign-org'),'Site theme B','responsive-banner-001-b','ILS');
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
 values(pg_temp.sid('restaurant'),pg_temp.sid('org'),pg_temp.sid('branch'),'responsive-banner-001-a','Site theme A','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10,'#292929','#ff8000','light');
insert into app_users(id,email) values
 (pg_temp.sid('manager'),'responsive-banner-manager@example.test'),
 (pg_temp.sid('cashier'),'responsive-banner-cashier@example.test'),
 (pg_temp.sid('foreign-manager'),'responsive-banner-foreign@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values
 (pg_temp.sid('manager-member'),pg_temp.sid('manager'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'manager'),
 (pg_temp.sid('cashier-member'),pg_temp.sid('cashier'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'cashier'),
 (pg_temp.sid('foreign-member'),pg_temp.sid('foreign-manager'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-restaurant'),'manager');
insert into storage.objects(bucket_id,name) values('restaurant-logos',
 pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('source')||'.jpg');
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 values(pg_temp.sid('media'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'restaurant-logos',
 pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('source')||'.jpg','w960',
 app.storefront_media_prefix(pg_temp.sid('restaurant'))||'/'||repeat('a',64)||'.webp',repeat('a',64),960,536,1000,now());
insert into storage.objects(bucket_id,name,metadata)
 select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}' from storefront_media where id=pg_temp.sid('media');
create temporary table theme_facts(k text primary key,v jsonb);
grant all on theme_facts to authenticated;
select set_config('app.current_app_user_id',pg_temp.sid('manager')::text,true);

-- Independent desktop base, foreign tenant base and a branch-only base.
insert into storage.objects(bucket_id,name) values
 ('restaurant-logos',pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('desktop-source')||'.jpg'),
 ('restaurant-logos',pg_temp.sid('foreign-org')||'/'||pg_temp.sid('foreign-restaurant')||'/logo/'||pg_temp.sid('foreign-source')||'.jpg'),
 ('menu-images',pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/'||pg_temp.sid('other-branch')||'/menu_item/'||pg_temp.sid('item')||'/'||pg_temp.sid('branch-source')||'.jpg');
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at) values
 (pg_temp.sid('desktop'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'restaurant-logos',
 pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('desktop-source')||'.jpg','w960',app.storefront_media_prefix(pg_temp.sid('restaurant'))||'/'||repeat('b',64)||'.webp',repeat('b',64),960,320,1000,now()),
 (pg_temp.sid('foreign-media'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-restaurant'),'restaurant-logos',
 pg_temp.sid('foreign-org')||'/'||pg_temp.sid('foreign-restaurant')||'/logo/'||pg_temp.sid('foreign-source')||'.jpg','w960',app.storefront_media_prefix(pg_temp.sid('foreign-restaurant'))||'/'||repeat('c',64)||'.webp',repeat('c',64),960,600,1000,now()),
 (pg_temp.sid('branch-media'),pg_temp.sid('org'),pg_temp.sid('restaurant'),'menu-images',
 pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/'||pg_temp.sid('other-branch')||'/menu_item/'||pg_temp.sid('item')||'/'||pg_temp.sid('branch-source')||'.jpg','w960',app.storefront_media_prefix(pg_temp.sid('restaurant'))||'/'||repeat('d',64)||'.webp',repeat('d',64),720,960,1000,now());
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}'
 from storefront_media where id in(pg_temp.sid('desktop'),pg_temp.sid('foreign-media'),pg_temp.sid('branch-media'));
create function pg_temp.responsive_keys() returns text[] language sql immutable as $$
 select array['menu_banner_layout','menu_banner_desktop_media_id','menu_banner_mobile_height_px','menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y']; $$;
create function pg_temp.wire_keys() returns text[] language sql immutable as $$
 select array['menu_banner_layout','menu_banner_desktop_url','menu_banner_mobile_height_px','menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y','menu_banner_width','menu_banner_height','menu_banner_desktop_width','menu_banner_desktop_height']; $$;
create function pg_temp.responsive_document() returns jsonb language sql immutable as $$
 select jsonb_set(pg_temp.theme_document('"dark"'),'{appearance}',(pg_temp.theme_document('"dark"')->'appearance')||jsonb_build_object(
 'menu_banner_media_id',pg_temp.sid('media'),'menu_banner_enabled',true,'menu_intro_visible',false,'menu_banner_focal_x',38,'menu_banner_focal_y',9,
 'menu_banner_layout','responsive','menu_banner_desktop_media_id',pg_temp.sid('desktop'),
 'menu_banner_mobile_height_px',460,'menu_banner_desktop_height_px',400,'menu_banner_desktop_focal_x',23,'menu_banner_desktop_focal_y',74)); $$;
create function pg_temp.read_responsive() returns jsonb language sql stable as $$
 select public.get_restaurant_storefront_content_v6(pg_temp.sid('org'),pg_temp.sid('restaurant')); $$;
create function pg_temp.save_current(label text,k text,v jsonb) returns jsonb language sql volatile as $$
 select pg_temp.theme_save(label,jsonb_set(pg_temp.read_responsive()->'document',array['appearance',k],v),(pg_temp.read_responsive()->>'version')::integer); $$;
create function pg_temp.legacy_management(n integer) returns jsonb language plpgsql stable as $$
 declare r jsonb; begin execute format('select public.get_restaurant_storefront_content_v%s($1,$2)',n)
 into r using pg_temp.sid('org'),pg_temp.sid('restaurant'); return r; end; $$;
create function pg_temp.legacy_public(n integer) returns jsonb language plpgsql stable as $$
 declare r jsonb; begin execute 'select public.storefront_menu'||case when n=1 then '' else '_v'||n end||'($1)'
 into r using 'responsive-banner-001-a'; return r; end; $$;

-- A second published tenant must remain isolated rather than only not-found.
insert into menu_categories(id,organization_id,restaurant_id,name,is_active) values(pg_temp.sid('foreign-category'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-restaurant'),'Foreign category',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active) values(pg_temp.sid('foreign-item'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-restaurant'),pg_temp.sid('foreign-category'),'Foreign item',1000,'ILS',true);
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version)
 values(pg_temp.sid('foreign-restaurant'),pg_temp.sid('foreign-org'),pg_temp.sid('foreign-branch'),'responsive-banner-001-b','Foreign','0521234567','{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10);
-- Validation is strict, independent of UI values. Null remains a real clear.
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.responsive_document(),array['appearance',k],v))->>'field','appearance.'||k,'reject invalid responsive value: '||k||'='||v::text)
 from (values('menu_banner_layout','"other"'::jsonb),('menu_banner_layout','true'::jsonb),('menu_banner_desktop_media_id','"https://private.invalid/original"'::jsonb),
 ('menu_banner_mobile_height_px','319'::jsonb),('menu_banner_mobile_height_px','641'::jsonb),('menu_banner_mobile_height_px','460.5'::jsonb),('menu_banner_mobile_height_px','"460"'::jsonb),
 ('menu_banner_desktop_height_px','239'::jsonb),('menu_banner_desktop_height_px','561'::jsonb),('menu_banner_desktop_height_px','{}'::jsonb),
 ('menu_banner_desktop_focal_x','-1'::jsonb),('menu_banner_desktop_focal_y','101'::jsonb),('menu_banner_desktop_focal_x','23.5'::jsonb),('menu_banner_desktop_focal_y','"74"'::jsonb)) x(k,v);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.responsive_document(),array['appearance',k],'null'))->'error',null::jsonb,'optional null accepted: '||k)
 from unnest(pg_temp.responsive_keys()) x(k);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.responsive_document(),array['appearance',k],to_jsonb(v)))->'error',null::jsonb,'inclusive valid boundary: '||k||'='||v)
 from (values('menu_banner_mobile_height_px',320),('menu_banner_mobile_height_px',640),('menu_banner_desktop_height_px',240),('menu_banner_desktop_height_px',560),('menu_banner_desktop_focal_x',0),('menu_banner_desktop_focal_x',100),('menu_banner_desktop_focal_y',0),('menu_banner_desktop_focal_y',100)) x(k,v);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.responsive_document(),'{appearance,menu_banner_mobile_height_px}','4.6e2'))#>>'{document,appearance,menu_banner_mobile_height_px}','460','integral numeric normalized without truncation');
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.responsive_document(),'{appearance,menu_banner_desktop_media_id}',to_jsonb(upper(pg_temp.sid('desktop')::text)))),
 jsonb_build_object('error','media_invalid','field','appearance.menu_banner_desktop_media_id'),'uppercase desktop UUID remains rejected by the canonical input contract');
select is(app.storefront_content_document_shape_v1(pg_temp.responsive_document())#>>'{document,appearance,menu_banner_desktop_media_id}',pg_temp.sid('desktop')::text,'canonical lowercase desktop UUID roundtrips for reference bookkeeping');
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.responsive_document(),'{appearance,menu_banner_zoom}','2'))->>'field','appearance','unknown future field remains rejected');
set local role authenticated;
insert into theme_facts values('selected',pg_temp.theme_save('responsive-select',pg_temp.responsive_document(),10));
select is(v->>'version','11','responsive settings use existing CAS writer once') from theme_facts where k='selected';
select is(pg_temp.theme_save('responsive-select',pg_temp.responsive_document(),10)->>'idempotent_replay','true','exact request replays without extending version');
insert into theme_facts values('saved',pg_temp.read_responsive()->'document');
select is(pg_temp.read_responsive()->'document',pg_temp.responsive_document(),'new management reader re-reads all six fields');
select ok(not coalesce((pg_temp.legacy_management(n)#>'{document,appearance}' ?| pg_temp.responsive_keys()),false),'old management v'||n||' has no unknown keys') from generate_series(1,5) n;
select is(pg_temp.theme_save('old-editor-save',public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'document',11)->>'version','12','old editor still saves through ordinary writer');
select is(pg_temp.read_responsive()->'document',(select v from theme_facts where k='saved'),'old omission preserves all optional settings and old fields');
select is(pg_temp.theme_save('stale-responsive',pg_temp.responsive_document(),11)->>'error','version_conflict','stale version cannot replace settings');
select is(pg_temp.theme_save('wrong-branch',pg_temp.responsive_document(),12,pg_temp.sid('other-branch'))->>'error','branch_conflict','branch conflict remains strict');
select is(pg_temp.theme_save('foreign-image',jsonb_set(pg_temp.responsive_document(),'{appearance,menu_banner_desktop_media_id}',to_jsonb(pg_temp.sid('foreign-media')::text)),12)->>'field','appearance.menu_banner_desktop_media_id','foreign tenant published derivative rejected');
select is(pg_temp.theme_save('other-branch-image',jsonb_set(pg_temp.responsive_document(),'{appearance,menu_banner_desktop_media_id}',to_jsonb(pg_temp.sid('branch-media')::text)),12)->>'field','appearance.menu_banner_desktop_media_id','other branch original scope rejected');
select is(pg_temp.save_current('phone-height','menu_banner_mobile_height_px','500')->>'ok','true','phone height updates independently');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_desktop_height_px}','400','phone change preserves desktop height');
select is(pg_temp.save_current('desktop-height','menu_banner_desktop_height_px','480')->>'ok','true','desktop height updates independently');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_mobile_height_px}','500','desktop change preserves phone height');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_focal_x}','38','desktop change preserves phone focal X');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_focal_y}','9','desktop change preserves phone focal Y');
select is(pg_temp.save_current('auto-phone','menu_banner_mobile_height_px','null')->>'ok','true','null phone height selects auto without affecting desktop');
select is(pg_temp.read_responsive()#>'{document,appearance,menu_banner_mobile_height_px}','null'::jsonb,'null phone height read back');
select is(pg_temp.save_current('legacy-layout','menu_banner_layout','null')->>'ok','true','explicit legacy layout accepted');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_desktop_media_id}',pg_temp.sid('desktop')::text,'layout clear retains independent desktop choice');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_desktop_height_px}','480','layout clear retains desktop height');
select is(public.retract_storefront_media(pg_temp.sid('retract-selected'),pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('desktop'))->>'error','media_in_use','retained desktop choice protects media even in legacy layout');
reset role;
select ok(app.storefront_content_media_in_use_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop')),'desktop reference is tracked independently of layout');
select ok(not coalesce((pg_temp.legacy_public(n)#>'{content_v1,appearance}' ?| (pg_temp.responsive_keys()||pg_temp.wire_keys())),false),'public reader v'||n||' retains old key surface') from generate_series(1,10) n;
select is(jsonb_set(public.storefront_menu_v11('responsive-banner-001-a')-'menu_banner_desktop_images_v1','{content_v1,appearance}',(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance}')-pg_temp.wire_keys()),public.storefront_menu_v10('responsive-banner-001-a'),'v11 adds only its explicit presentation surface to exact v10 envelope');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>>'{content_v1,appearance,menu_banner_url}',app.storefront_content_media_url_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('media')),'phone URL remains exact selected eligible base');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>>'{content_v1,appearance,menu_banner_desktop_url}',app.storefront_content_media_url_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop')),'desktop URL is its independently eligible public base');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_width}','960'::jsonb,'phone width paired to phone URL');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_height}','536'::jsonb,'phone height paired to phone URL');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_desktop_width}','960'::jsonb,'desktop width paired to desktop URL');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_desktop_height}','320'::jsonb,'desktop height paired to desktop URL');
select ok(not(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance}' ? 'menu_banner_desktop_media_id'),'public output never leaks desktop identifier');
select ok(not(public.storefront_menu_v11('responsive-banner-001-a') ? 'menu_banner_desktop_images_v1'),'old base without companion is valid base-only fallback');
select is(public.storefront_menu_v11('responsive-banner-001-b')->>'ok','true','foreign tenant fixture is itself a published valid catalogue');
select ok(not (coalesce(public.storefront_menu_v11('responsive-banner-001-b')#>'{content_v1,appearance}','{}'::jsonb) ? 'menu_banner_desktop_url'),'foreign catalogue cannot inherit A desktop URL');
select ok(not(public.storefront_menu_v11('responsive-banner-001-b') ? 'menu_banner_desktop_images_v1'),'foreign catalogue cannot inherit A high companion');
-- Synthetic companion: use existing eligible association and generation, not a new variant.
insert into app.storefront_background_variants(organization_id,restaurant_id,branch_id,base_media_id,base_hash,source_snapshot,content_hash,object_key,width,height,bytes,published_at)
 select pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop'),base_hash,source_snapshot,repeat('e',64),app.storefront_background_prefix_v1(pg_temp.sid('restaurant'))||'/'||repeat('e',64)||'.webp',1920,640,2000,now()
 from app.storefront_background_context_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop'));
insert into storage.objects(bucket_id,name,metadata) values('storefront-media',app.storefront_background_prefix_v1(pg_temp.sid('restaurant'))||'/'||repeat('e',64)||'.webp','{"mimetype":"image/webp","size":2000}');
select is(public.storefront_menu_v11('responsive-banner-001-a')->'menu_banner_desktop_images_v1',jsonb_build_object('base_url',app.storefront_content_media_url_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop')),'variants',jsonb_build_array(
 jsonb_build_object('url',app.storefront_content_media_url_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop')),'width',960,'height',320),
 jsonb_build_object('url','/storage/v1/object/public/storefront-media/'||app.storefront_background_prefix_v1(pg_temp.sid('restaurant'))||'/'||repeat('e',64)||'.webp','width',1920,'height',640))),'desktop manifest uses exact existing v7 public shape and same selected base');
select ok(not(public.storefront_menu_v10('responsive-banner-001-a') ? 'menu_banner_desktop_images_v1'),'old reader never receives new top-level manifest');
update storage.objects set version='responsive-generation-2' where bucket_id='restaurant-logos' and name=pg_temp.sid('org')||'/'||pg_temp.sid('restaurant')||'/logo/'||pg_temp.sid('desktop-source')||'.jpg';
select ok(not(public.storefront_menu_v11('responsive-banner-001-a') ? 'menu_banner_desktop_images_v1'),'private-source generation change suppresses stale high companion');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>>'{content_v1,appearance,menu_banner_desktop_url}',app.storefront_content_media_url_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop')),'stale companion does not discard eligible base fallback');
-- Unpublishing/metadata failure affects only the independent desktop selection.
update storefront_media set unpublished_at=now() where id=pg_temp.sid('desktop');
select is(pg_temp.read_responsive()#>'{document,appearance,menu_banner_desktop_media_id}','null'::jsonb,'unpublished desktop sanitized on new management read');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.read_responsive()->'warnings') w where w->>'field'='appearance.menu_banner_desktop_media_id'),'new warning is scoped to new reader');
select ok(not exists(select 1 from jsonb_array_elements(public.get_restaurant_storefront_content_v5(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'warnings') w where w->>'field'='appearance.menu_banner_desktop_media_id'),'old reader warning shape unchanged');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_desktop_url}','null'::jsonb,'unpublished desktop public URL cleared');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_desktop_width}','null'::jsonb,'unpublished desktop dimensions cleared with URL');
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_width}','960'::jsonb,'desktop unpublish leaves phone reference unchanged');
update storefront_media set unpublished_at=null where id=pg_temp.sid('desktop');
update storage.objects set metadata='{"mimetype":"image/jpeg","size":1000}' where bucket_id='storefront-media' and name=(select object_key from storefront_media where id=pg_temp.sid('desktop'));
select is(public.storefront_menu_v11('responsive-banner-001-a')#>'{content_v1,appearance,menu_banner_desktop_url}','null'::jsonb,'invalid public MIME cannot supply desktop image');
update storage.objects set metadata='{"mimetype":"image/webp","size":1000}' where bucket_id='storefront-media' and name=(select object_key from storefront_media where id=pg_temp.sid('desktop'));
-- Same-source replacement repoints only the matching desktop reference.
-- Match the existing publisher: retract old before publishing the same-source
-- successor, preserving the one-live-row source/variant invariant.
update storefront_media set unpublished_at=greatest(now(),published_at) where id=pg_temp.sid('desktop');
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 select pg_temp.sid('desktop-replacement'),organization_id,restaurant_id,source_bucket,source_key,variant,app.storefront_media_prefix(restaurant_id)||'/'||repeat('f',64)||'.webp',repeat('f',64),width,height,bytes,now() from storefront_media where id=pg_temp.sid('desktop');
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}' from storefront_media where id=pg_temp.sid('desktop-replacement');
select throws_ok($$select app.storefront_content_repoint_media_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop'),pg_temp.sid('media'))$$,'23514',null,'different original cannot repoint desktop');
select app.storefront_content_repoint_media_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'),pg_temp.sid('branch'),pg_temp.sid('desktop'),pg_temp.sid('desktop-replacement'));
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_desktop_media_id}',pg_temp.sid('desktop-replacement')::text,'same-source republish follows desktop selection');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_media_id}',pg_temp.sid('media')::text,'desktop repoint preserves phone image');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_background_media_id}',pg_temp.sid('media')::text,'desktop repoint preserves menu background');
select ok(not(public.storefront_menu_v11('responsive-banner-001-a') ? 'menu_banner_desktop_images_v1'),'replacement base cannot inherit previous companion association');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_banner_mobile_height_px}','319') where restaurant_id=pg_temp.sid('restaurant')$$,'23514',null,'database independently rejects bad height');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_banner_layout}','"other"') where restaurant_id=pg_temp.sid('restaurant')$$,'23514',null,'database independently rejects unknown layout');
select ok(exists(select 1 from audit_events where restaurant_id=pg_temp.sid('restaurant') and action='settings.storefront.content.updated' and new_values#>>'{appearance,menu_banner_layout}'='responsive'),'ordinary content audit includes responsive presentation');
set local role authenticated;
select is(pg_temp.save_current('clear-desktop','menu_banner_desktop_media_id','null')->>'ok','true','explicit null clears only desktop selection through ordinary save');
select is(pg_temp.read_responsive()#>'{document,appearance,menu_banner_desktop_media_id}','null'::jsonb,'explicit clear survives server re-read');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_banner_media_id}',pg_temp.sid('media')::text,'desktop clear preserves phone selection');
select is(pg_temp.read_responsive()#>>'{document,appearance,menu_background_media_id}',pg_temp.sid('media')::text,'desktop clear preserves background selection');
reset role;
-- Remaining explicit nulls persist without resetting phone or other fields.
select set_config('app.current_app_user_id',pg_temp.sid('manager')::text,true);
set local role authenticated;
select is(pg_temp.save_current('null-'||k,k,'null')->>'ok','true','explicit null saves optional field: '||k)
 from unnest(array['menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y']) x(k);
select is(pg_temp.read_responsive()#>array['document','appearance',k],'null'::jsonb,'explicit null read back: '||k)
 from unnest(array['menu_banner_desktop_height_px','menu_banner_desktop_focal_x','menu_banner_desktop_focal_y']) x(k);
reset role;
-- Authority is not expanded by a new reader version.
update memberships set role='cashier' where id=pg_temp.sid('manager-member');
set local role authenticated;
select is(pg_temp.read_responsive()->>'error','not_found','revoked management rank immediately denies new reader');
select is(pg_temp.theme_save('demoted',pg_temp.responsive_document(),0)->>'error','permission_denied','revoked rank cannot save via shared writer');
reset role;
update memberships set role='manager' where id=pg_temp.sid('manager-member');
select set_config('app.current_app_user_id',pg_temp.sid('cashier')::text,true);
set local role authenticated;
select is(pg_temp.read_responsive()->>'error','not_found','cashier cannot read new management contract');
select is(pg_temp.theme_save('cashier',pg_temp.responsive_document(),0)->>'error','permission_denied','cashier cannot use shared writer');
reset role;
select set_config('app.current_app_user_id',pg_temp.sid('foreign-manager')::text,true);
set local role authenticated;
select throws_ok($$select pg_temp.read_responsive()$$,'42501',null,'foreign manager cannot read new scoped settings');
select throws_ok($$select public.get_restaurant_storefront_content_v6(pg_temp.sid('org'),pg_temp.sid('foreign-restaurant'))$$,'42501',null,'ancestry mismatch denied before authority');
select throws_ok($$select pg_temp.theme_save('foreign',pg_temp.responsive_document(),0)$$,'42501',null,'foreign manager cannot save responsive settings');
reset role;
set local role anon;
select is(public.storefront_menu_v11('responsive-banner-001-a')->>'ok','true','anonymous published catalogue remains available');
select throws_ok($$select pg_temp.read_responsive()$$,'42501',null,'anonymous cannot read new management contract');
select is(public.storefront_menu_v11('missing-responsive'),public.storefront_menu_v10('missing-responsive'),'missing slug retains exact old failure');
reset role;
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.sid('restaurant');
select is(public.storefront_menu_v11('responsive-banner-001-a'),public.storefront_menu_v10('responsive-banner-001-a'),'unpublished catalogue retains exact old failure');
select is((select prosecdef from pg_proc where oid='public.get_restaurant_storefront_content_v6(uuid,uuid)'::regprocedure),false,'management public wrapper remains invoker');
select is((select prosecdef from pg_proc where oid='app.get_restaurant_storefront_content_v6(uuid,uuid)'::regprocedure),true,'management authority remains in scoped definer');
select is((select proconfig from pg_proc where oid='public.storefront_menu_v11(text)'::regprocedure),array['search_path=""'],'new public reader has empty search_path');
select is((select pg_get_userbyid(proowner) from pg_proc where oid='public.storefront_menu_v11(text)'::regprocedure),'postgres','new reader owner is explicit postgres');
select ok(has_function_privilege('authenticated','public.get_restaurant_storefront_content_v6(uuid,uuid)','execute') and not has_function_privilege('anon','public.get_restaurant_storefront_content_v6(uuid,uuid)','execute') and not has_function_privilege('service_role','public.get_restaurant_storefront_content_v6(uuid,uuid)','execute'),'new management ACL authenticated only');
select ok(has_function_privilege('anon','public.storefront_menu_v11(text)','execute') and has_function_privilege('authenticated','public.storefront_menu_v11(text)','execute') and not has_function_privilege('service_role','public.storefront_menu_v11(text)','execute'),'new public ACL anon/auth only');
select * from finish();
rollback;
