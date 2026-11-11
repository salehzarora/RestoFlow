-- BIZBOT-STOREFRONT-SITE-THEME-001-API. Synthetic, rollback-only contract checks.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.sid(label text) returns uuid language sql immutable as $$
 select md5('storefront-site-theme-001-'||label)::uuid;
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
select has_function('public','storefront_menu_v8',array['text'],'new public version exists');
select has_function('public','get_restaurant_storefront_content_v4',array['uuid','uuid'],'new management version exists');
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.sid('org'),'Site theme A','site-theme-001-a','ILS'),
 (pg_temp.sid('foreign-org'),'Site theme B','site-theme-001-b','ILS');
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
 values(pg_temp.sid('restaurant'),pg_temp.sid('org'),pg_temp.sid('branch'),'site-theme-001-a','Site theme A','0521234567',
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

-- Existing tenants are never initialized or reinterpreted.
select is(public.storefront_menu_v8('site-theme-001-a'),public.storefront_menu_v7('site-theme-001-a'),'absent choice keeps exact public legacy envelope');
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant')),
 public.get_restaurant_storefront_content_v3(pg_temp.sid('org'),pg_temp.sid('restaurant')),'absent choice keeps exact management envelope');
select ok(not exists(select 1 from app.storefront_content_profiles where restaurant_id=pg_temp.sid('restaurant')),'reads do not create an opt-in record');
select is(app.storefront_content_document_shape_v1(pg_temp.theme_document(v))->>'field','appearance.site_theme','strict invalid theme rejected: '||v::text)
 from (values ('"auto"'::jsonb),('"Light"'::jsonb),('"light "'::jsonb),('"false"'::jsonb),('false'::jsonb),('0'::jsonb),('[]'::jsonb),('{}'::jsonb)) x(v);
select is(app.storefront_content_document_shape_v1(pg_temp.theme_document(v))#>'{document,appearance,site_theme}',v,'accepted exact optional enum/null: '||v::text)
 from (values ('"light"'::jsonb),('"dark"'::jsonb),('null'::jsonb)) x(v);
select is(app.storefront_content_document_shape_v1(jsonb_set(pg_temp.theme_document('"light"'),'{appearance,extra}','true'))->>'field',
 'appearance','adding the choice does not relax unknown-key rejection');

set local role authenticated;
insert into theme_facts values('select-result',pg_temp.theme_save('select',pg_temp.theme_document('"light"'),10));
select is(v->>'version','11','explicit site choice increments shared CAS exactly once') from theme_facts where k='select-result';
select is(pg_temp.theme_save('select',pg_temp.theme_document('"light"'),10)->>'idempotent_replay','true','same identity/body replays without another write');
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>>'{document,appearance,site_theme}',
 'light','new reader authoritatively reloads explicit light');
select is(public.get_restaurant_storefront_content_v3(pg_temp.sid('org'),pg_temp.sid('restaurant')),
 public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant')) #- '{document,appearance,site_theme}','old public management v3 exact projection');
select is(app.get_restaurant_storefront_content_v3(pg_temp.sid('org'),pg_temp.sid('restaurant')),
 app.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant')) #- '{document,appearance,site_theme}','old authenticated app v3 exact projection');
select ok(not(public.get_restaurant_storefront_content_v2(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance}' ? 'site_theme'),
 'old management v2 omits new key');
select ok(not(public.get_restaurant_storefront_content_v1(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'document' ? 'appearance'),
 'old management v1 shape stays unchanged');
insert into theme_facts values('appearance',public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance}');
select is(pg_temp.theme_save('legacy-save',public.get_restaurant_storefront_content_v3(pg_temp.sid('org'),pg_temp.sid('restaurant'))->'document',11)->>'version',
 '12','old editor full document remains writable');
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>>'{document,appearance,site_theme}',
 'light','old editor omission preserves saved site choice');
select is(pg_temp.theme_save('stale',pg_temp.theme_document('"dark"'),11)->>'error','version_conflict','stale choice cannot replace current site choice');
select is(pg_temp.theme_save('wrong-branch',pg_temp.theme_document('"dark"'),12,pg_temp.sid('other-branch'))->>'error',
 'branch_conflict','a different real branch cannot inherit or receive the choice');
select is(pg_temp.theme_save('dark',pg_temp.theme_document('"dark"'),12)->>'version','13','explicit dark saves independently');
select is((public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance}') - 'site_theme',
 (select v-'site_theme' from theme_facts where k='appearance'),'light to dark preserves text/button/font/media/dim/scene exactly');
reset role;
select is(public.storefront_menu_v8('site-theme-001-a')#>>'{content_v1,appearance,site_theme}','dark','v8 alone exposes current choice');
select is(public.storefront_menu_v7('site-theme-001-a'),public.storefront_menu_v8('site-theme-001-a') #- '{content_v1,appearance,site_theme}',
 'v7 strict shape preserves its full existing catalogue/media/scene contract');
select ok(not(public.storefront_menu_v6('site-theme-001-a')#>'{content_v1,appearance}' ? 'site_theme'),'v6 strips choice');
select ok(not(public.storefront_menu_v5('site-theme-001-a')#>'{content_v1,appearance}' ? 'site_theme'),'v5 strips choice');
select ok(not(public.storefront_menu_v4('site-theme-001-a')->'content_v1' ? 'appearance'),'v4 keeps appearance absent');
select is(public.storefront_menu_v8('site-theme-001-a')#>>'{restaurant,visual_preset}','light','legacy preset is never overwritten by dark opt-in');
select is(public.storefront_menu_v8('site-theme-001-a')#>>'{restaurant,primary_color}','#292929','profile brand primary is unchanged');
select is(public.storefront_menu_v8('site-theme-001-a')#>>'{restaurant,accent_color}','#ff8000','profile accent is unchanged');
set local role authenticated;
select is(pg_temp.theme_save('clear',pg_temp.theme_document('null'),13)->>'version','14','explicit null resets opt-in through the same writer');
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance,site_theme}',
 'null'::jsonb,'explicit null roundtrips, distinct from an omitted old editor key');
select is(pg_temp.theme_save('without-appearance',pg_temp.theme_document('null')-'appearance',14)->>'version','15','oldest editor can save without appearance');
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))#>'{document,appearance}',
 (select jsonb_set(v,'{site_theme}','null') from theme_facts where k='appearance'),'omitting appearance preserves every saved optional key');
reset role;
select ok(exists(select 1 from audit_events where restaurant_id=pg_temp.sid('restaurant') and action='settings.storefront.content.updated'
 and old_values#>>'{appearance,site_theme}'='light' and new_values#>>'{appearance,site_theme}'='dark'),'audit stores full before/after choice despite old strict reader projection');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{site_theme}','true') where restaurant_id=pg_temp.sid('restaurant')$$,
 '23514',null,'table constraint independently rejects malformed theme');
select ok(not exists(select 1 from app.storefront_content_profiles where storefront_branch_id in(pg_temp.sid('other-branch'),pg_temp.sid('foreign-branch'))),
 'no other branch or tenant receives an opt-in');

select set_config('app.current_app_user_id',pg_temp.sid('cashier')::text,true);
set local role authenticated;
select is(public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))->>'error','not_found','lower rank cannot use management read');
select is(pg_temp.theme_save('cashier-denied',pg_temp.theme_document('"dark"'),15)->>'error','permission_denied','new choice grants no additional write authority');
reset role;
select set_config('app.current_app_user_id',pg_temp.sid('foreign-manager')::text,true);
set local role authenticated;
select throws_ok($$select public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))$$,'42501',null,'foreign manager cannot read this tenant');
select throws_ok($$select public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('foreign-restaurant'))$$,'42501',null,'new reader rejects mismatched ancestry');
select throws_ok($$select pg_temp.theme_save('foreign-denied',pg_temp.theme_document('"dark"'),15)$$,'42501',null,'foreign manager cannot save this tenant');
reset role;
set local role anon;
select is(public.storefront_menu_v8('site-theme-001-a')->>'ok','true','anonymous published public read remains supported');
select is(public.storefront_menu_v8('missing-theme-001'),public.storefront_menu_v7('missing-theme-001'),'missing tenant preserves exact failure envelope');
select throws_ok($$select public.get_restaurant_storefront_content_v4(pg_temp.sid('org'),pg_temp.sid('restaurant'))$$,'42501',null,'anonymous management read denied');
reset role;
update restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.sid('restaurant');
set local role anon;
select is(public.storefront_menu_v8('site-theme-001-a')->>'error','not_found','new public read never bypasses unpublished admission');
reset role;
select * from finish();
rollback;
