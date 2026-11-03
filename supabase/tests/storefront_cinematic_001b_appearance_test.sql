-- BIZBOT-STOREFRONT-CINEMATIC-001B: synthetic, rollback-only appearance checks.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.aid(label text) returns uuid language sql immutable as $$select md5('storefront-cinematic-001b-'||label)::uuid;$$;
create function pg_temp.appearance_document() returns jsonb language sql immutable as $$
 select jsonb_build_object('hero_headline','Hello','hero_subline',null,'announcement_text',null,
  'hero',jsonb_build_object('mode','editorial','item_id',null,'format',null,'eyebrow',null,'stamp',null,'footnote',null),
  'announcement_segments',null,'promo',null,'story',null,'category_presentation','[]'::jsonb,'item_presentation','[]'::jsonb);
$$;
create function pg_temp.appearance_save(label text,document jsonb,version integer) returns jsonb language sql volatile as $$
 select public.set_restaurant_storefront_content_v1(pg_temp.aid(label),pg_temp.aid('org'),pg_temp.aid('restaurant'),version,pg_temp.aid('branch'),document);
$$;
select ok(not (app.storefront_content_document_shape_v1(pg_temp.appearance_document())->'document') ? 'appearance','legacy shape is unchanged');
select is(app.storefront_content_document_shape_v1(pg_temp.appearance_document()||'{"appearance":{"text_color":"#FfF4E6","button_text_color":null}}')#>'{document,appearance}',
 '{"text_color":"#fff4e6","button_text_color":null}'::jsonb,'HEX normalized with inherited button color');
select is(app.storefront_content_document_shape_v1(pg_temp.appearance_document()||jsonb_build_object('appearance',v))->>'error','presentation_invalid','invalid appearance rejected: '||n)
 from (values
  (1,'null'::jsonb),(2,'{}'::jsonb),(3,'{"text_color":"#ffffff"}'::jsonb),
  (4,'{"text_color":null,"button_text_color":null,"css":"unsafe"}'::jsonb),
  (5,'{"text_color":"#fff","button_text_color":null}'::jsonb),
  (6,'{"text_color":"white","button_text_color":null}'::jsonb),
  (7,'{"text_color":"#gggggg","button_text_color":null}'::jsonb),
  (8,jsonb_build_object('text_color',E'#ffffff\n','button_text_color',null)),
  (9,'{"text_color":123,"button_text_color":null}'::jsonb)) x(n,v);
select is(app.storefront_content_document_shape_v1(pg_temp.appearance_document()||jsonb_build_object('appearance',
 jsonb_build_object('text_color',null,'button_text_color',null,'font_family',v)))#>'{document,appearance,font_family}',v,'allowed font choice: '||v::text)
 from (values ('"rubik"'::jsonb),('"alexandria"'::jsonb),('"system"'::jsonb),('null'::jsonb)) x(v);
select is(app.storefront_content_document_shape_v1(pg_temp.appearance_document()||jsonb_build_object('appearance',
 jsonb_build_object('text_color',null,'button_text_color',null,'font_family',v)))->>'error','presentation_invalid','invalid font rejected: '||v::text)
 from (values ('"Arial"'::jsonb),('"Alexandria"'::jsonb),('"rubik "'::jsonb),('"url(https://example.invalid)"'::jsonb),('1'::jsonb),('true'::jsonb),('[]'::jsonb),('{}'::jsonb)) x(v);

insert into organizations(id,name,slug,default_currency) values(pg_temp.aid('org'),'Appearance test','appearance-cinematic-001b','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.aid('restaurant'),pg_temp.aid('org'),'Appearance test','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values(pg_temp.aid('branch'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'Appearance test','UTC',false,'exclusive');
-- The existing profile writer rechecks publish preconditions even for a Hero-only patch.
insert into menu_categories(id,organization_id,restaurant_id,name,is_active)
 values(pg_temp.aid('category'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'Appearance category',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active)
 values(pg_temp.aid('item'),pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('category'),'Appearance item',1000,'ILS',true);
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version)
 values(pg_temp.aid('restaurant'),pg_temp.aid('org'),pg_temp.aid('branch'),'appearance-cinematic-001b','Appearance test','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}'::jsonb,true,10);
select is(app.storefront_publish_blockers(pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('branch'),p.slug,p.opening_hours),
 array[]::text[],'published fixture satisfies existing profile writer preconditions')
 from restaurant_storefront_profiles p where p.restaurant_id=pg_temp.aid('restaurant');
insert into app_users(id,email) values(pg_temp.aid('user'),'appearance@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values(pg_temp.aid('membership'),pg_temp.aid('user'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'manager');
select set_config('app.current_app_user_id',pg_temp.aid('user')::text,true);
set local role authenticated;
select is(pg_temp.appearance_save('save',pg_temp.appearance_document()||'{"appearance":{"text_color":"#FFF4E6","button_text_color":"#14120F"}}',10)->>'version','11','appearance saves in existing single version step');
select is(pg_temp.appearance_save('save',pg_temp.appearance_document()||'{"appearance":{"text_color":"#FFF4E6","button_text_color":"#14120F"}}',10)->>'idempotent_replay','true','exact appearance save replays');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>'{document,appearance}',
 '{"text_color":"#fff4e6","button_text_color":"#14120f"}'::jsonb,'private read roundtrips saved colors');
select is(pg_temp.appearance_save('legacy',pg_temp.appearance_document(),11)->>'version','12','legacy content write remains accepted');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,text_color}','#fff4e6','legacy content write preserves appearance');
reset role;
select is(public.storefront_menu_v4('appearance-cinematic-001b')#>>'{content_v1,appearance,text_color}','#fff4e6','public projection carries appearance');
select throws_ok($$update app.storefront_content_profiles set appearance='{"text_color":"red","button_text_color":null}' where restaurant_id=pg_temp.aid('restaurant')$$,'23514',null,'table constraint rejects invalid HEX');
set local role authenticated;
select is(pg_temp.appearance_save('clear',pg_temp.appearance_document()||'{"appearance":{"text_color":null,"button_text_color":null}}',12)->>'version','13','null color overrides explicitly restore defaults');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>'{document,appearance}',
 '{"text_color":null,"button_text_color":null}'::jsonb,'cleared overrides roundtrip');
select is(pg_temp.appearance_save('font',pg_temp.appearance_document()||'{"appearance":{"text_color":null,"button_text_color":null,"font_family":"alexandria"}}',13)->>'version','14','font saves through the existing version step');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,font_family}','alexandria','private read roundtrips the selected font');
select is(pg_temp.appearance_save('old-color-editor',pg_temp.appearance_document()||'{"appearance":{"text_color":"#F0F0F0","button_text_color":null}}',14)->>'version','15','older color-only editor remains accepted');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,font_family}','alexandria','omitted font preserves existing selection');
reset role;
select is(public.storefront_menu_v4('appearance-cinematic-001b')#>>'{content_v1,appearance,font_family}','alexandria','public projection carries selected font');
select throws_ok($$update app.storefront_content_profiles set appearance='{"text_color":null,"button_text_color":null,"font_family":"Arial"}' where restaurant_id=pg_temp.aid('restaurant')$$,'23514',null,'table constraint rejects unlisted font');
set local role authenticated;
select is(pg_temp.appearance_save('clear-font',pg_temp.appearance_document()||'{"appearance":{"text_color":"#f0f0f0","button_text_color":null,"font_family":null}}',15)->>'version','16','explicit null restores the default font');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>'{document,appearance,font_family}','null'::jsonb,'cleared font roundtrips');
reset role;
-- v5: independent menu backdrop uses only existing published w960 media.
create function pg_temp.background_source(label text) returns text language sql immutable as $$
 select pg_temp.aid('org')::text||'/'||pg_temp.aid('restaurant')::text||'/logo/'||pg_temp.aid('original-'||label)::text||'.png';$$;
insert into storage.objects(bucket_id,name) select 'restaurant-logos',pg_temp.background_source(label) from unnest(array['hero','menu-a','menu-b','staged']) label;
insert into public.storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 select pg_temp.aid('media-'||label),pg_temp.aid('org'),pg_temp.aid('restaurant'),'restaurant-logos',pg_temp.background_source(source),'w960',app.storefront_media_prefix(pg_temp.aid('restaurant'))||'/'||repeat(ch,64)||'.webp',repeat(ch,64),960,640,1000,
 case when label in ('staged','menu-b-replacement') then null else now() end
 from (values ('hero','hero','1'),('menu-a','menu-a','2'),('menu-b','menu-b','3'),('menu-b-replacement','menu-b','4'),('staged','staged','5')) x(label,source,ch);
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}'::jsonb
 from public.storefront_media where restaurant_id=pg_temp.aid('restaurant');
insert into organizations(id,name,slug,default_currency) values(pg_temp.aid('foreign-org'),'Foreign appearance','appearance-cinematic-foreign','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.aid('foreign-restaurant'),pg_temp.aid('foreign-org'),'Foreign appearance','UTC');
insert into public.storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 values(pg_temp.aid('foreign-media'),pg_temp.aid('foreign-org'),pg_temp.aid('foreign-restaurant'),'restaurant-logos',
 pg_temp.aid('foreign-org')::text||'/'||pg_temp.aid('foreign-restaurant')::text||'/logo/'||pg_temp.aid('foreign-original')::text||'.png',
 'w960',app.storefront_media_prefix(pg_temp.aid('foreign-restaurant'))||'/'||repeat('6',64)||'.webp',repeat('6',64),960,640,1000,now());
create function pg_temp.appearance_version() returns integer language sql stable as $$
 select (public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))->>'version')::integer;$$;
create function pg_temp.background_document(media uuid,dim jsonb) returns jsonb language sql immutable as $$
 select pg_temp.appearance_document()||jsonb_build_object('appearance',jsonb_build_object('text_color','#f0f0f0','button_text_color',null,
  'menu_background_media_id',media,'menu_background_dim',dim));$$;
select is(app.storefront_content_document_shape_v1(pg_temp.background_document(null,'15.0'))#>>'{document,appearance,menu_background_dim}','15','integral numeric dim canonicalizes');
select is(app.storefront_content_document_shape_v1(pg_temp.background_document(null,d))->>'error','presentation_invalid','invalid dim rejected: '||d::text)
 from (values ('-1'::jsonb),('81'::jsonb),('1.5'::jsonb),('"15"'::jsonb),('true'::jsonb),('[]'::jsonb),('{}'::jsonb)) x(d);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.background_document(null,'15'),'{appearance,menu_background_media_id}',to_jsonb('not-uuid'::text)))->>'error','media_invalid','malformed media ID rejected');
set local role authenticated;
select is(public.set_restaurant_storefront_profile(pg_temp.aid('set-original-hero'),pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.appearance_version(),jsonb_build_object('hero_media_id',pg_temp.aid('media-hero')))->>'ok','true','independent Hero seed uses existing profile writer');
select is(pg_temp.appearance_save('menu-select',pg_temp.background_document(pg_temp.aid('media-menu-a'),'15'),pg_temp.appearance_version())->>'ok','true','select menu background through existing writer');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,menu_background_media_id}',pg_temp.aid('media-menu-a')::text,'private read keeps selected ID');
select is(pg_temp.appearance_save('menu-foreign',pg_temp.background_document(pg_temp.aid('foreign-media'),'15'),pg_temp.appearance_version())->>'reason','media_invalid','foreign media refused');
select is(pg_temp.appearance_save('menu-staged',pg_temp.background_document(pg_temp.aid('media-staged'),'15'),pg_temp.appearance_version())->>'reason','media_invalid','unpublished media refused');
select is(public.retract_storefront_media(pg_temp.aid('retract-menu-active'),pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('media-menu-a'))->>'error','media_in_use','existing retract protects menu background reference');
select is((select m->'content_in_use' from jsonb_array_elements(public.list_storefront_content_media_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))->'media') x(m) where m->>'id'=pg_temp.aid('media-menu-a')::text),'[{"kind":"menu_background"}]'::jsonb,'existing editor media list reports usage');
select is(pg_temp.appearance_save('menu-old-editor',pg_temp.appearance_document()||'{"appearance":{"text_color":"#FFFFFF","button_text_color":null}}',pg_temp.appearance_version())->>'ok','true','older color writer remains accepted');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,menu_background_media_id}',pg_temp.aid('media-menu-a')::text,'older writer preserves background');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,menu_background_dim}','15','older writer preserves dim');
reset role;
select is(public.storefront_menu_v4('appearance-cinematic-001b')#>>'{content_v1,appearance,menu_background_url}',
 '/storage/v1/object/public/storefront-media/'||app.storefront_media_prefix(pg_temp.aid('restaurant'))||'/'||repeat('2',64)||'.webp','public projects eligible URL');
select ok(not (public.storefront_menu_v4('appearance-cinematic-001b')#>'{content_v1,appearance}') ? 'menu_background_media_id','public never exposes private media ID field');
select is((select hero_media_id from public.restaurant_storefront_profiles where restaurant_id=pg_temp.aid('restaurant')),pg_temp.aid('media-hero'),'menu selection never changes Hero');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{menu_background_dim}','81') where restaurant_id=pg_temp.aid('restaurant')$$,'23514',null,'table constraint rejects invalid dim');
set local role authenticated;
select is(pg_temp.appearance_save('menu-replace',pg_temp.background_document(pg_temp.aid('media-menu-b'),'60'),pg_temp.appearance_version())->>'ok','true','replace menu background and dim');
select is(public.retract_storefront_media(pg_temp.aid('retract-menu-previous'),pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('media-menu-a'))->>'ok','true','old unselected background may be retracted');
select is(public.finalize_storefront_media(pg_temp.aid('finalize-menu-replacement'),pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('media-menu-b-replacement'))->>'ok','true','existing same-source finalize repoints background');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,menu_background_media_id}',pg_temp.aid('media-menu-b-replacement')::text,'republished derivative pointer roundtrips');
reset role;
select is((select hero_media_id from public.restaurant_storefront_profiles where restaurant_id=pg_temp.aid('restaurant')),pg_temp.aid('media-hero'),'replacement and republication preserve Hero');
-- Move only this rollback-only fixture's metadata so the registered key is absent.
-- Do not disable Storage's delete guard or delete object metadata directly.
with moved as (
 update storage.objects set name=app.storefront_media_prefix(pg_temp.aid('restaurant'))||'/'||repeat('7',64)||'.webp'
 where bucket_id='storefront-media' and name=app.storefront_media_prefix(pg_temp.aid('restaurant'))||'/'||repeat('4',64)||'.webp'
 returning 1
) select is((select count(*)::integer from moved),1,'missing-object fixture moves exactly its synthetic replacement object');
select is(public.storefront_menu_v4('appearance-cinematic-001b')#>'{content_v1,appearance,menu_background_url}','null'::jsonb,'unavailable public object projects null');
select ok((public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))->'warnings') @> '[{"field":"appearance.menu_background_media_id","reason":"media_unavailable"}]'::jsonb,'private read warns on unavailable object');
select is((select appearance->>'menu_background_media_id' from app.storefront_content_profiles
 where restaurant_id=pg_temp.aid('restaurant') and storefront_branch_id=pg_temp.aid('branch') and deleted_at is null),
 pg_temp.aid('media-menu-b-replacement')::text,'unavailable public object does not mutate the saved background ID');
set local role authenticated;
select is(pg_temp.appearance_save('menu-clear',pg_temp.background_document(null,'null'),pg_temp.appearance_version())->>'ok','true','explicit null clears background and dim');
select is(public.get_restaurant_storefront_content_v1(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>'{document,appearance,menu_background_media_id}','null'::jsonb,'clear readback is explicit null');
reset role;
select is(public.storefront_menu_v4('appearance-cinematic-001b')#>'{content_v1,appearance,menu_background_dim}','null'::jsonb,'dim clear roundtrips');
select is((select hero_media_id from public.restaurant_storefront_profiles where restaurant_id=pg_temp.aid('restaurant')),pg_temp.aid('media-hero'),'clearing menu background preserves Hero fallback');

select * from finish();
rollback;
