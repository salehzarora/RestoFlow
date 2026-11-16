-- BIZBOT-STOREFRONT-WELCOME-VIDEO-CONTRACT-001.
-- Synthetic rollback-only association/authority tests. storage.objects rows are
-- not real MP4 uploads and never constitute Edge/video playback acceptance.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.vid(label text) returns uuid language sql immutable as $$ select md5('welcome-video-001-'||label)::uuid; $$;
create function pg_temp.source_key(label text,foreign_tenant boolean default false) returns text language sql immutable as $$
 select pg_temp.vid(case when foreign_tenant then 'foreign-org' else 'org' end)||'/'||pg_temp.vid(case when foreign_tenant then 'foreign-restaurant' else 'restaurant' end)||'/'||pg_temp.vid(label)||'.mp4'; $$;
create function pg_temp.save(label text,d jsonb,expected integer,branch uuid default pg_temp.vid('branch')) returns jsonb language sql volatile as $$
 select public.set_restaurant_storefront_content_v1(pg_temp.vid(label),pg_temp.vid('org'),pg_temp.vid('restaurant'),expected,branch,d); $$;
insert into organizations(id,name,slug,default_currency) values
 (pg_temp.vid('org'),'Welcome A','welcome-video-001-a','ILS'),(pg_temp.vid('foreign-org'),'Welcome B','welcome-video-001-b','ILS');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.vid('restaurant'),pg_temp.vid('org'),'Welcome A','UTC'),(pg_temp.vid('foreign-restaurant'),pg_temp.vid('foreign-org'),'Welcome B','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values
 (pg_temp.vid('branch'),pg_temp.vid('org'),pg_temp.vid('restaurant'),'A','UTC',false,'exclusive'),
 (pg_temp.vid('branch2'),pg_temp.vid('org'),pg_temp.vid('restaurant'),'A2','UTC',false,'exclusive'),
 (pg_temp.vid('foreign-branch'),pg_temp.vid('foreign-org'),pg_temp.vid('foreign-restaurant'),'B','UTC',false,'exclusive');
insert into menu_categories(id,organization_id,restaurant_id,name,is_active) values(pg_temp.vid('category'),pg_temp.vid('org'),pg_temp.vid('restaurant'),'Food',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active)
 values(pg_temp.vid('item'),pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.vid('category'),'Food',1000,'ILS',true);
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version)
 values(pg_temp.vid('restaurant'),pg_temp.vid('org'),pg_temp.vid('branch'),'welcome-video-001-a','Welcome A','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10);
insert into app_users(id,email) values
 (pg_temp.vid('manager'),'welcome-video-manager@example.test'),(pg_temp.vid('cashier'),'welcome-video-cashier@example.test'),
 (pg_temp.vid('foreign-manager'),'welcome-video-foreign@example.test'),(pg_temp.vid('branch-manager'),'welcome-video-branch@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role) values
 (pg_temp.vid('manager-member'),pg_temp.vid('manager'),pg_temp.vid('org'),pg_temp.vid('restaurant'),null,'manager'),
 (pg_temp.vid('cashier-member'),pg_temp.vid('cashier'),pg_temp.vid('org'),pg_temp.vid('restaurant'),null,'cashier'),
 (pg_temp.vid('foreign-member'),pg_temp.vid('foreign-manager'),pg_temp.vid('foreign-org'),pg_temp.vid('foreign-restaurant'),null,'manager'),
 (pg_temp.vid('branch-member'),pg_temp.vid('branch-manager'),pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.vid('branch'),'manager');
create temporary table video_facts(k text primary key,v jsonb);
grant all on video_facts to authenticated;
insert into storage.objects(bucket_id,name,metadata) values('storefront-welcome-video-originals',pg_temp.source_key('foreign-source',true),'{"mimetype":"video/mp4","size":100}');

select ok((select relrowsecurity and relforcerowsecurity from pg_class where oid='app.storefront_welcome_video_media'::regclass),'registry has forced RLS');
select ok(not has_table_privilege('authenticated','app.storefront_welcome_video_media','select'),'no direct registry read grant');
select ok(not has_table_privilege('authenticated','app.storefront_welcome_video_media','insert'),'no direct registry insert grant');
select is((select public from storage.buckets where id='storefront-welcome-video-originals'),false,'original bucket stays private');
select is((select public from storage.buckets where id='storefront-welcome-videos'),true,'bounded explicit publication bucket is public');
select is((select file_size_limit from storage.buckets where id='storefront-welcome-videos'),20971520::bigint,'public upload byte bound');
select is((select allowed_mime_types from storage.buckets where id='storefront-welcome-videos'),array['video/mp4']::text[],'MP4-only bucket');
select ok(not has_function_privilege('anon','public.get_restaurant_storefront_content_v7(uuid,uuid)','execute'),'anonymous management denied');
select ok(not has_function_privilege('service_role','public.get_restaurant_storefront_content_v7(uuid,uuid)','execute'),'no service-role management grant');
select ok(has_function_privilege('anon','public.storefront_menu_v12(text)','execute'),'anonymous published-reader grant');
select ok(not has_function_privilege('service_role','public.storefront_menu_v12(text)','execute'),'no added service-role public grant');
select ok((select not prosecdef and proowner='postgres'::regrole and proconfig=array['search_path=""'] from pg_proc where oid='public.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer)'::regprocedure),'registration wrapper fixed owner/path and INVOKER');
select ok((select prosecdef and proowner='postgres'::regrole and proconfig=array['search_path=""'] from pg_proc where oid='app.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer)'::regprocedure),'registration body fixed owner/path and DEFINER');

select set_config('app.current_app_user_id',pg_temp.vid('manager')::text,true);
set local role authenticated;
-- Exercise the actual legacy management response before any content row exists.
insert into video_facts values('legacy-empty-v6-document',public.get_restaurant_storefront_content_v6(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document');
select ok(not ((public.get_restaurant_storefront_content_v6(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document') ? 'appearance'),'fixture really begins with legacy absent appearance');
select is(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>'{document,appearance}',
 jsonb_build_object('text_color',null,'button_text_color',null,'welcome_media_type',null,'welcome_video_media_id',null),'actual v7 materializes all four nullable appearance keys for a legacy document');
select is(public.get_restaurant_storefront_content_v6(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document',(select v from video_facts where k='legacy-empty-v6-document'),'v7 read does not materialize or change old v6 state');
select lives_ok(format('insert into storage.objects(bucket_id,name,metadata) values(%L,%L,%L::jsonb)','storefront-welcome-video-originals',pg_temp.source_key('source'),'{"mimetype":"video/mp4","size":100}'),'same-scope manager can insert immutable original');
select throws_ok(format('insert into storage.objects(bucket_id,name,metadata) values(%L,%L,%L::jsonb)','storefront-welcome-video-originals',pg_temp.source_key('foreign-insert',true),'{"mimetype":"video/mp4","size":100}'),'42501',null,'foreign original insert rejected');
select is((select count(*)::integer from storage.objects where bucket_id='storefront-welcome-video-originals' and name=pg_temp.source_key('foreign-source',true)),0,'foreign original not visible');
select is((public.preflight_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'))->>'ok'),'true','actual same-scope preflight');
select is(public.preflight_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('absent'),pg_temp.vid('request'))->>'error','source_unavailable','missing own original is explicit');
select is(public.preflight_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('foreign-source',true),pg_temp.vid('request'))->>'field','source_key','foreign key rejected before reading object');
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('a',64),1921,1080,30000,100)->>'field','width','1921 width refused');
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('a',64),1920,1081,30000,100)->>'field','height','1081 height refused');
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('a',64),1920,1080,30001,100)->>'field','duration_ms','30001ms refused');
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('a',64),1920,1080,30000,101)->>'field','bytes','actual source metadata byte mismatch refused');
insert into video_facts values('registered',public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('a',64),1920,1080,30000,100));
select is(v->>'ok','true','inclusive video bounds register') from video_facts where k='registered';
select is(v#>>'{media,published}','false','stage is not published') from video_facts where k='registered';
select is(v#>'{media,url}','null'::jsonb,'stage has no public URL') from video_facts where k='registered';
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('a',64),1920,1080,30000,100),(select v from video_facts where k='registered'),'exact registration replay returns same registry identity');
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('request'),repeat('b',64),1920,1080,30000,100)->>'error','request_mismatch','same identity with changed hash refused');
select is(jsonb_array_length(public.list_storefront_welcome_videos_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'media'),0,'staged row not offered as published selection');
select is(public.publish_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),(select (v#>>'{media,id}')::uuid from video_facts where k='registered'),pg_temp.vid('request'))->>'error','object_unavailable','finalize without actual public Storage object refused');
select lives_ok(format('insert into storage.objects(bucket_id,name,metadata) values(%L,%L,%L::jsonb)','storefront-welcome-videos',(select v#>>'{media,object_key}' from video_facts where k='registered'),'{"mimetype":"video/mp4","size":100}'),'registry-authorized same-scope public object insert');
insert into video_facts values('published',public.publish_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),(select (v#>>'{media,id}')::uuid from video_facts where k='registered'),pg_temp.vid('request')));
select is(v#>>'{media,published}','true','finalized actual object association') from video_facts where k='published';
select matches(v#>>'{media,url}','^/storage/v1/object/public/storefront-welcome-videos/[0-9a-f]{32}/[0-9a-f]{64}\.mp4$','published canonical MP4 URL') from video_facts where k='published';
select is(public.publish_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),(select (v#>>'{media,id}')::uuid from video_facts where k='registered'),pg_temp.vid('request')),(select v from video_facts where k='published'),'exact finalize replay');
select is(public.publish_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),(select (v#>>'{media,id}')::uuid from video_facts where k='registered'),pg_temp.vid('wrong-request'))->>'error','request_mismatch','wrong finalize identity refused');
select is(jsonb_array_length(public.list_storefront_welcome_videos_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'media'),1,'published list contains one validated association');
select is((select count(*)::integer from jsonb_object_keys(public.list_storefront_welcome_videos_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>'{media,0}')),10,'owner media row exact ten-key shape');
insert into video_facts values('old-document',public.get_restaurant_storefront_content_v6(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document');
insert into video_facts values('new-document',jsonb_set((public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document'),'{appearance}',(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>'{document,appearance}')||jsonb_build_object('welcome_media_type','video','welcome_video_media_id',(select v#>>'{media,id}' from video_facts where k='published'))));
insert into video_facts values('expected-legacy-document',jsonb_set((select v from video_facts where k='new-document'),'{appearance}',((select v from video_facts where k='new-document')->'appearance')-array['welcome_media_type','welcome_video_media_id']));
select is(pg_temp.save('select-video',(select v from video_facts where k='new-document'),10)->>'version','11','video selection uses ordinary content CAS');
select is(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>>'{document,appearance,welcome_media_type}','video','v7 re-reads mode');
select is(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>>'{document,appearance,welcome_video_media_id}',(select v#>>'{media,id}' from video_facts where k='published'),'v7 re-reads selected id');
select is(public.get_restaurant_storefront_content_v6(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document',(select v from video_facts where k='expected-legacy-document'),'v6 exact legacy projection after storing welcome fields');
select is(public.get_restaurant_storefront_content_v5(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document',(select v from video_facts where k='expected-legacy-document'),'v5 exact legacy projection after storing welcome fields');
select ok(not coalesce(public.storefront_menu_v11('welcome-video-001-a')#>'{content_v1,appearance}' ?| array['welcome_media_type','welcome_video_media_id'],false),'old public v11 appearance has neither private welcome setting');
select is(public.storefront_menu_v12('welcome-video-001-a')#>>'{restaurant,welcome_media_type}','video','public explicit opt-in mode');
select is((select count(*)::integer from jsonb_object_keys(public.storefront_menu_v12('welcome-video-001-a')#>'{restaurant,welcome_video}')),6,'public selected video exact six-key shape');
select ok(position(pg_temp.source_key('source') in public.storefront_menu_v12('welcome-video-001-a')::text)=0,'public response never exposes private source key');
select is((public.storefront_menu_v12('welcome-video-001-a')#-'{restaurant,welcome_media_type}'#-'{restaurant,welcome_video}')-'server_ts',public.storefront_menu_v11('welcome-video-001-a')-'server_ts','v12 stripping two public fields equals v11 exactly');
select is(pg_temp.save('old-omission',(select v from video_facts where k='old-document'),11)->>'version','12','old client still saves');
select is(public.get_restaurant_storefront_content_v6(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document',(select v from video_facts where k='expected-legacy-document'),'old v6 projection remains exact after an old-writer omission save');
select is(public.get_restaurant_storefront_content_v5(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document',(select v from video_facts where k='expected-legacy-document'),'old v5 projection remains exact after an old-writer omission save');
select is(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>>'{document,appearance,welcome_media_type}','video','old omission preserves mode');
select is(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))#>>'{document,appearance,welcome_video_media_id}',(select v#>>'{media,id}' from video_facts where k='published'),'old omission preserves selected video');
select is(pg_temp.save('stale',(select v from video_facts where k='new-document'),11)->>'error','version_conflict','stale client cannot overwrite selection');
select is(pg_temp.save('clear-selection',jsonb_set((public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document'),'{appearance,welcome_video_media_id}','null'),12)->>'version','13','explicit null independently clears selection');
select is(public.storefront_menu_v12('welcome-video-001-a')#>'{restaurant,welcome_video}','null'::jsonb,'missing selection uses image fallback instead of invalid public video');
select is(public.storefront_menu_v12('welcome-video-001-a')#>>'{restaurant,welcome_media_type}','video','clearing selection does not silently change owner mode');
select is(pg_temp.save('clear-mode',jsonb_set((public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document'),'{appearance,welcome_media_type}','null'),13)->>'version','14','explicit null mode restores legacy choice');
select is(public.storefront_menu_v12('welcome-video-001-a')#>'{restaurant,welcome_media_type}','null'::jsonb,'public legacy mode is JSON null');
reset role;
select is(app.storefront_content_document_shape_v1(jsonb_set((select v from video_facts where k='new-document'),'{appearance,welcome_media_type}','"unknown"'))->>'field','appearance.welcome_media_type','unknown future mode rejected');
select is(app.storefront_content_document_shape_v1(jsonb_set((select v from video_facts where k='new-document'),'{appearance,welcome_video_media_id}','"bad"'))->>'field','appearance.welcome_video_media_id','bad media identity rejected');

-- Actual table CHECKs, with an otherwise valid stored appearance object.
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{welcome_media_type}','"future"') where organization_id=pg_temp.vid('org') and restaurant_id=pg_temp.vid('restaurant') and storefront_branch_id=pg_temp.vid('branch')$$,'23514',null,'table CHECK rejects unknown mode, not only the document helper');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{welcome_video_media_id}','"bad-uuid"') where organization_id=pg_temp.vid('org') and restaurant_id=pg_temp.vid('restaurant') and storefront_branch_id=pg_temp.vid('branch')$$,'23514',null,'table CHECK rejects invalid video UUID, not only the document helper');
select is(app.storefront_content_document_shape_v1(jsonb_set((select v from video_facts where k='new-document'),'{appearance}',bad)),
 jsonb_build_object('error','presentation_invalid','field','appearance'),'legacy non-object appearance keeps exact original error for '||bad::text)
 from unnest(array['null'::jsonb,'[]'::jsonb,'"text"'::jsonb,'3'::jsonb,'true'::jsonb]) x(bad);
select is((select count(*)::integer from app.storefront_welcome_video_media where organization_id=pg_temp.vid('org') and request_id=pg_temp.vid('request')),1,'replay creates no extra registry row');
select is((select count(*)::integer from audit_events where restaurant_id=pg_temp.vid('restaurant') and action='settings.storefront.welcome_video.registered'),1,'registration audit appended once');
select is((select count(*)::integer from audit_events where restaurant_id=pg_temp.vid('restaurant') and action='settings.storefront.welcome_video.published'),1,'publication audit appended once');
select ok(exists(select 1 from audit_events where restaurant_id=pg_temp.vid('restaurant') and action='settings.storefront.content.updated' and new_values#>>'{appearance,welcome_media_type}'='video'),'ordinary content audit includes video choice');

-- A real published foreign registry row and a real staged same-tenant row remain unselectable.
insert into app.storefront_welcome_video_media(id,organization_id,restaurant_id,request_id,created_by,source_key,content_hash,object_key,width,height,duration_ms,bytes,published_at)
 values(pg_temp.vid('foreign-video'),pg_temp.vid('foreign-org'),pg_temp.vid('foreign-restaurant'),pg_temp.vid('foreign-request'),pg_temp.vid('foreign-manager'),pg_temp.source_key('foreign-source',true),repeat('f',64),app.storefront_media_prefix(pg_temp.vid('foreign-restaurant'))||'/'||repeat('f',64)||'.mp4',320,240,1000,100,now());
insert into storage.objects(bucket_id,name,metadata) values('storefront-welcome-videos',app.storefront_media_prefix(pg_temp.vid('foreign-restaurant'))||'/'||repeat('f',64)||'.mp4','{"mimetype":"video/mp4","size":100}');
set local role authenticated;
select is(pg_temp.save('foreign-selection',jsonb_set((public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document'),'{appearance,welcome_video_media_id}',to_jsonb(pg_temp.vid('foreign-video')::text)),14)->>'field','appearance.welcome_video_media_id','published foreign video cannot be selected');
insert into video_facts values('staged-second',public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('second-request'),repeat('b',64),320,240,1000,100));
select is(pg_temp.save('staged-selection',jsonb_set((public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))->'document'),'{appearance,welcome_video_media_id}',(select v#>'{media,id}' from video_facts where k='staged-second')),14)->>'field','appearance.welcome_video_media_id','staged own video cannot be selected');
select is(public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))->>'version','14','invalid selections do not increment content version');
select is(pg_temp.save('wrong-branch',(select v from video_facts where k='old-document'),14,pg_temp.vid('branch2'))->>'error','branch_conflict','new media fields cannot bypass selected branch CAS');
reset role;

-- Wrong actor checks target the same valid source and ids, not easier missing data.
select set_config('app.current_app_user_id',pg_temp.vid('cashier')::text,true);
set local role authenticated;
select is(public.preflight_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('cashier-request'))->>'error','permission_denied','cashier preflight denied');
select is(public.register_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('cashier-request'),repeat('a',64),1920,1080,30000,100)->>'error','permission_denied','cashier registration denied');
select is(public.publish_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),(select (v#>>'{media,id}')::uuid from video_facts where k='registered'),pg_temp.vid('request'))->>'error','permission_denied','cashier publication denied');
select is(public.list_storefront_welcome_videos_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'))->>'error','permission_denied','cashier list denied');
reset role;
select set_config('app.current_app_user_id',pg_temp.vid('foreign-manager')::text,true);
set local role authenticated;
select is(public.preflight_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('foreign-attempt'))->>'error','permission_denied','other tenant cannot preflight real own-tenant source');
select is(public.list_storefront_welcome_videos_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'))->>'error','permission_denied','other tenant cannot list videos');
select throws_ok($$select public.get_restaurant_storefront_content_v7(pg_temp.vid('org'),pg_temp.vid('restaurant'))$$,'42501',null,'v7 retains cross-tenant refusal');
reset role;
select set_config('app.current_app_user_id',pg_temp.vid('branch-manager')::text,true);
set local role authenticated;
select is(public.preflight_storefront_welcome_video_v1(pg_temp.vid('org'),pg_temp.vid('restaurant'),pg_temp.source_key('source'),pg_temp.vid('branch-attempt'))->>'error','permission_denied','branch-only actor cannot use restaurant-level media authority');
reset role;
select * from finish();
rollback;
