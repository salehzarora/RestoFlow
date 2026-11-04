-- BIZBOT-STOREFRONT-VISUAL-PARITY-001-MEDIA: rollback-only product publication.
-- Synthetic Storage metadata exercises SQL authorization/identity, not image bytes.
-- Public RPCs run as authenticated/anon; only fixture setup uses the harness role.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();

create function pg_temp.pid(label text) returns uuid language sql immutable as $$
 select md5('visual-parity-product-media-001-'||label)::uuid; $$;
create function pg_temp.pkey(item text,treatment text default 'original') returns text language sql immutable as $$
 select pg_temp.pid(case when item='foreign' then 'foreign-org' else 'org' end)::text||'/'||
 pg_temp.pid(case when item='foreign' then 'foreign-restaurant' else 'restaurant' end)::text||
 '/global/menu_item/'||pg_temp.pid(item)::text||'/'||pg_temp.pid(item||'-'||treatment)::text||'.png'; $$;
create temp table product_results(label text primary key,result jsonb);
grant select,insert,update on product_results to authenticated;
create function pg_temp.pr(label text) returns jsonb language sql stable as $$select result from product_results where label=$1;$$;
create function pg_temp.did(label text) returns uuid language sql stable as $$select (pg_temp.pr(label)->>'derivative_id')::uuid;$$;
create function pg_temp.mid(label text) returns uuid language sql stable as $$select (pg_temp.pr(label)->>'media_id')::uuid;$$;
-- These helpers are SECURITY INVOKER: the public functions see the actual test caller.
create function pg_temp.original(item text) returns jsonb language sql volatile as $$
 select public.get_storefront_product_original_v1(pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid(item));$$;
create function pg_temp.register(label text,item text,treatment text default 'cutout',version bigint default 0) returns jsonb language sql volatile as $$
 select public.register_storefront_product_derivative_v1(pg_temp.pid('register-'||label),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid(item),
 pg_temp.pkey(item),pg_temp.original(item)->'source_snapshot',pg_temp.pkey(item,treatment),treatment,version);$$;
create function pg_temp.source(label text) returns jsonb language sql volatile as $$
 select public.get_storefront_product_source_v1(pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.did(label));$$;
create function pg_temp.stage(request text,registration text,variant text,hash_label text default null) returns jsonb language sql volatile as $$
 select public.stage_storefront_product_media_v1(pg_temp.pid('stage-'||request),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.did(registration),
 pg_temp.pr('source-'||registration)->>'source_key',pg_temp.pr('source-'||registration)->'source_snapshot',variant,
 md5(coalesce(hash_label,request))||md5('tail-'||coalesce(hash_label,request)),case when variant='w480' then 480 else 960 end,240,1000);$$;
create function pg_temp.finalize(request text,stage text) returns jsonb language sql volatile as $$
 select public.finalize_storefront_product_media_v1(pg_temp.pid('finalize-'||request),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.mid(stage));$$;
create function pg_temp.choose(request text,registration text) returns jsonb language sql volatile as $$
 select public.select_storefront_product_derivative_v1(pg_temp.pid('choose-'||request),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.did(registration));$$;

insert into organizations(id,name,slug,default_currency) values
 (pg_temp.pid('org'),'Product test','visual-parity-product-001','ILS'),
 (pg_temp.pid('foreign-org'),'Foreign product test','visual-parity-product-foreign-001','ILS');
insert into restaurants(id,organization_id,name,timezone) values
 (pg_temp.pid('restaurant'),pg_temp.pid('org'),'Product test','UTC'),
 (pg_temp.pid('sibling'),pg_temp.pid('org'),'Sibling test','UTC'),
 (pg_temp.pid('foreign-restaurant'),pg_temp.pid('foreign-org'),'Foreign test','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
 values(pg_temp.pid('branch'),pg_temp.pid('org'),pg_temp.pid('restaurant'),'Product branch','UTC',false,'exclusive');
insert into menu_categories(id,organization_id,restaurant_id,name,is_active) values
 (pg_temp.pid('category'),pg_temp.pid('org'),pg_temp.pid('restaurant'),'Products',true),
 (pg_temp.pid('foreign-category'),pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),'Foreign products',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active,image_path)
 select pg_temp.pid(item),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid('category'),item,1000,'ILS',true,pg_temp.pkey(item)
 from unnest(array['main','other','stage-stale','finalize-stale','selected-stale','race']) item;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active,image_path)
 values(pg_temp.pid('foreign'),pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),pg_temp.pid('foreign-category'),'Foreign',1000,'ILS',true,pg_temp.pkey('foreign'));
insert into storage.objects(bucket_id,name,version,metadata)
 select 'menu-images',pg_temp.pkey(item,treatment),'generation-1','{"mimetype":"image/png","size":4000}'::jsonb
 from unnest(array['main','other','stage-stale','finalize-stale','selected-stale','race','foreign']) item
 cross join unnest(array['original','cutout']) treatment;
insert into storage.objects(bucket_id,name,metadata) values('restaurant-logos',
 pg_temp.pid('org')::text||'/'||pg_temp.pid('restaurant')::text||'/logo/'||pg_temp.pid('receipt')::text||'.png','{"mimetype":"image/png","size":1000}');
update restaurants set receipt_logo_path=pg_temp.pid('org')::text||'/'||pg_temp.pid('restaurant')::text||'/logo/'||pg_temp.pid('receipt')::text||'.png',
 receipt_logo_enabled=true,receipt_logo_version=7 where id=pg_temp.pid('restaurant');
insert into storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
 values(pg_temp.pid('hero'),pg_temp.pid('org'),pg_temp.pid('restaurant'),'menu-images',pg_temp.pkey('main'),'w960',
 app.storefront_media_prefix(pg_temp.pid('restaurant'))||'/'||repeat('a',64)||'.webp',repeat('a',64),960,240,1000,now());
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}'::jsonb
 from storefront_media where id=pg_temp.pid('hero');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version,hero_media_id)
 values(pg_temp.pid('restaurant'),pg_temp.pid('org'),pg_temp.pid('branch'),'visual-parity-product-001','Product test','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}',true,10,pg_temp.pid('hero'));
insert into app_users(id,email) select pg_temp.pid(label),label||'-vp-product@example.test' from unnest(array['manager','cashier','outsider','sibling-manager','foreign-manager']) label;
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values
 (pg_temp.pid('manager-membership'),pg_temp.pid('manager'),pg_temp.pid('org'),pg_temp.pid('restaurant'),'manager'),
 (pg_temp.pid('cashier-membership'),pg_temp.pid('cashier'),pg_temp.pid('org'),pg_temp.pid('restaurant'),'cashier'),
 (pg_temp.pid('sibling-membership'),pg_temp.pid('sibling-manager'),pg_temp.pid('org'),pg_temp.pid('sibling'),'manager'),
 (pg_temp.pid('foreign-membership'),pg_temp.pid('foreign-manager'),pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),'manager');
insert into product_results values('v5-before',public.storefront_menu_v5('visual-parity-product-001')),
 ('receipt-before',(select jsonb_build_array(receipt_logo_path,receipt_logo_enabled,receipt_logo_version) from restaurants where id=pg_temp.pid('restaurant'))),
 ('original-object-before',(select to_jsonb(o) from storage.objects o where bucket_id='menu-images' and name=pg_temp.pkey('main')));

-- Closed ACL and real-role authorization, including a valid but unrelated user.
select ok(not has_table_privilege('authenticated','app.storefront_product_selections','UPDATE'),'selection table has no direct authenticated update grant');
select ok(not has_function_privilege('authenticated','app.storefront_product_current_v1(uuid,uuid,uuid)','EXECUTE'),'generation helper is not a client bypass');
set local role anon;
select throws_ok($$select pg_temp.original('main')$$,'42501',null,'anonymous private original read denied');
reset role;
set local role authenticated;
select set_config('app.current_app_user_id',pg_temp.pid('foreign-manager')::text,true);
insert into product_results values('foreign-original',public.get_storefront_product_original_v1(pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),pg_temp.pid('foreign')));
insert into product_results values('foreign',public.register_storefront_product_derivative_v1(pg_temp.pid('register-foreign'),pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),pg_temp.pid('foreign'),
 pg_temp.pkey('foreign'),pg_temp.pr('foreign-original')->'source_snapshot',pg_temp.pkey('foreign','cutout'),'cutout',0));
insert into product_results values('source-foreign',public.get_storefront_product_source_v1(pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),pg_temp.did('foreign')));
insert into product_results values('foreign480',public.stage_storefront_product_media_v1(pg_temp.pid('foreign480'),pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),pg_temp.did('foreign'),
 pg_temp.pkey('foreign','cutout'),pg_temp.pr('source-foreign')->'source_snapshot','w480',repeat('c',64),480,240,1000));
select is(pg_temp.pr('foreign480')->>'ok','true','foreign fixture is a real independently authorized staged derivative');
select set_config('app.current_app_user_id',pg_temp.pid('cashier')::text,true);
select throws_ok($$select pg_temp.original('main')$$,'42501',null,'cashier cannot access product processing');
select set_config('app.current_app_user_id',pg_temp.pid('outsider')::text,true);
select throws_ok($$select pg_temp.register('outsider','main')$$,'42501',null,'unrelated authenticated user cannot register');
select set_config('app.current_app_user_id',pg_temp.pid('sibling-manager')::text,true);
select throws_ok($$select pg_temp.original('main')$$,'42501',null,'sibling restaurant manager cannot access product source');
select set_config('app.current_app_user_id',pg_temp.pid('manager')::text,true);
select throws_ok($$select public.get_storefront_product_original_v1(pg_temp.pid('foreign-org'),pg_temp.pid('foreign-restaurant'),pg_temp.pid('foreign'))$$,'42501',null,'foreign scope rejected before item lookup');
select is(pg_temp.original('foreign')->>'error','source_not_found','foreign item cannot be read through authorized scope');
select is(pg_temp.source('foreign')->>'error','source_stale','real foreign derivative cannot be read through authorized scope');
select is(pg_temp.stage('foreign-through-own','foreign','w480')->>'error','source_stale','real foreign derivative cannot be staged through authorized scope');
select is(pg_temp.finalize('foreign-through-own','foreign480')->>'error','not_found','real foreign media cannot be finalized through authorized scope');
select is(pg_temp.choose('foreign-through-own','foreign')->>'error','source_stale','real foreign derivative cannot be selected through authorized scope');
insert into product_results values('original',pg_temp.original('main'));
select is(pg_temp.pr('original')->>'selection_version','0','unselected original begins at version zero');
select is(pg_temp.pr('original')->>'source_key',pg_temp.pkey('main'),'authorized original read retains private upload key');
select is(pg_temp.pr('original')->'selected_derivative_id','null'::jsonb,'no derivative selected initially');
select is(public.register_storefront_product_derivative_v1(pg_temp.pid('foreign-candidate'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid('main'),pg_temp.pkey('main'),pg_temp.pr('original')->'source_snapshot',pg_temp.pkey('foreign','cutout'),'cutout',0)->>'error','source_not_found','candidate ownership excludes foreign tenant');
select is(public.register_storefront_product_derivative_v1(pg_temp.pid('other-candidate'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid('main'),pg_temp.pkey('main'),pg_temp.pr('original')->'source_snapshot',pg_temp.pkey('other','cutout'),'cutout',0)->>'error','source_not_found','candidate ownership excludes another item in same restaurant');
select is(public.register_storefront_product_derivative_v1(pg_temp.pid('other-original'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid('other'),pg_temp.pkey('main'),pg_temp.pr('original')->'source_snapshot',pg_temp.pkey('other','cutout'),'cutout',0)->>'error','source_stale','original snapshot cannot be rebound to another item');
select is(public.register_storefront_product_derivative_v1(pg_temp.pid('same-cutout'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid('main'),pg_temp.pkey('main'),pg_temp.pr('original')->'source_snapshot',pg_temp.pkey('main'),'cutout',0)->>'error','invalid','cutout cannot overwrite the original key');

-- Register two independent choices against the same selection version.
insert into product_results values('main',pg_temp.register('main','main')),('rival',pg_temp.register('rival','main'));
select is(pg_temp.pr('main')->>'ok','true','cutout registration succeeds');
select isnt(pg_temp.did('main'),pg_temp.did('rival'),'logical choices have independent associations');
select is(pg_temp.register('main','main')->>'idempotent_replay','true','identical register request replays');
select throws_ok($$select pg_temp.register('main','other')$$,'42501',null,'register idempotency key rejects changed item');
insert into product_results values('source-main',pg_temp.source('main')),('source-rival',pg_temp.source('rival'));
select is(pg_temp.pr('source-main')->>'source_key',pg_temp.pkey('main','cutout'),'processing source is the separate candidate');
select is(public.get_storefront_product_source_v1(pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.pid('missing'))->>'error','source_stale','unknown derivative returns no source');
select is(pg_temp.choose('main','main')->>'error','media_unavailable','selection rejects a registration with no published variants');
insert into product_results values('main480',pg_temp.stage('main480','main','w480')),('main960',pg_temp.stage('main960','main','w960'));
select is(pg_temp.pr('main480')->>'state','staged','small derivative is staged');
select is(pg_temp.pr('main960')->>'state','staged','large derivative is staged');
select is(pg_temp.stage('main480','main','w480')->>'media_id',pg_temp.mid('main480')::text,'stage retry preserves the association');
select throws_ok($$select pg_temp.stage('main480','main','w960')$$,'42501',null,'stage idempotency key rejects changed variant');
select is(pg_temp.finalize('main480','main480')->>'error','object_mismatch','missing uploaded output cannot finalize');
select is(public.finalize_storefront_media(pg_temp.pid('old-finalize'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.mid('main480'))->>'error','product_operation_required','legacy finalize refuses a product marker');
select is(public.stage_storefront_product_media_v1(pg_temp.pid('oversize'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.did('main'),pg_temp.pkey('main','cutout'),pg_temp.pr('source-main')->'source_snapshot','w480',repeat('b',64),481,240,1000)->>'error','invalid','existing width cap is retained');
select is(public.stage_storefront_product_media_v1(pg_temp.pid('overbudget'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.did('main'),pg_temp.pkey('main','cutout'),pg_temp.pr('source-main')->'source_snapshot','w480',repeat('b',64),480,240,524289)->>'error','invalid','existing output budget is retained');
select is(public.stage_storefront_product_media_v1(pg_temp.pid('source-substitution'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.did('main'),pg_temp.pkey('other','cutout'),pg_temp.pr('source-main')->'source_snapshot','w480',repeat('b',64),480,240,1000)->>'error','source_stale','stage cannot substitute another candidate key');
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id in(pg_temp.mid('main480'),pg_temp.mid('main960'));
set local role authenticated;
select is(pg_temp.finalize('main480','main480')->>'ok','true','retry after uploading small bytes finalizes once');
select is(pg_temp.choose('main','main')->>'error','media_unavailable','one published rung cannot be selected');
select is(pg_temp.original('main')->>'selection_version','0','failed partial selection has no version side effect');
select is(pg_temp.finalize('main960','main960')->>'ok','true','second rung finalizes');
select is(pg_temp.finalize('main960','main960')->>'idempotent_replay','true','finalize replay remains idempotent');
select is(pg_temp.stage('main960','main','w960')->>'state','published','stage replay rereads current published state');
-- Both competing registrations have a complete pair at expected version zero.
-- Sharing immutable bytes does not merge their publication associations.
insert into product_results values('rival480',pg_temp.stage('rival480','rival','w480','main480')),
 ('rival960',pg_temp.stage('rival960','rival','w960','main960'));
select isnt(pg_temp.mid('rival480'),pg_temp.mid('main480'),'same content address has separate product association per choice');
select is(pg_temp.pr('rival480')->>'object_key',pg_temp.pr('main480')->>'object_key','identical bytes keep identical content address');
select is(pg_temp.finalize('rival480','rival480')->>'ok','true','competing small rung publishes independently');
select is(pg_temp.finalize('rival960','rival960')->>'ok','true','competing large rung publishes independently');
reset role;
update storage.objects set metadata=jsonb_set(metadata,'{size}','999') where bucket_id='storefront-media' and name=pg_temp.pr('main960')->>'object_key';
set local role authenticated;
select is(pg_temp.choose('main','main')->>'error','media_unavailable','published metadata alone cannot select a pair whose high output mismatches');
select is(pg_temp.finalize('main960','main960')->>'error','object_mismatch','finalize replay verifies output metadata before returning cached success');
reset role;
update storage.objects set metadata=jsonb_set(metadata,'{size}','1000') where bucket_id='storefront-media' and name=pg_temp.pr('main960')->>'object_key';
set local role authenticated;
select is(pg_temp.choose('main','main')->>'selection_version','1','complete pair becomes one atomic selection');
select is(pg_temp.choose('main','main')->>'idempotent_replay','true','same selection request safely replays');
select is(pg_temp.original('main')->>'selected_derivative_id',pg_temp.did('main')::text,'authoritative original read names current selection');
select is(pg_temp.choose('rival','rival')->>'error','selection_stale','competing choice at original version cannot replace selected pair');
select is(pg_temp.register('new-stale','main')->>'error','selection_stale','new registration requires current selection version');
select is(public.retract_storefront_media(pg_temp.pid('retract-selected'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.mid('main480'))->>'error','media_in_use','selected low rung is protected from generic retraction');
select is(public.retract_storefront_media(pg_temp.pid('retract-selected-high'),pg_temp.pid('org'),pg_temp.pid('restaurant'),pg_temp.mid('main960'))->>'error','media_in_use','selected high rung is protected from generic retraction');
select is(public.set_restaurant_storefront_profile(pg_temp.pid('rebind-hero'),pg_temp.pid('org'),pg_temp.pid('restaurant'),10,jsonb_build_object('hero_media_id',pg_temp.mid('main960')))->>'reason','hero_media_id_invalid','product media cannot become Hero');
select is(public.set_restaurant_storefront_profile(pg_temp.pid('rebind-logo'),pg_temp.pid('org'),pg_temp.pid('restaurant'),10,jsonb_build_object('logo_media_id',pg_temp.mid('main480')))->>'reason','logo_media_id_invalid','product media cannot become profile logo');
reset role;
select is(public.storefront_menu_v5('visual-parity-product-001'),pg_temp.pr('v5-before'),'selection leaves exact old v5 payload unchanged');
select is(jsonb_array_length(public.storefront_menu_v6('visual-parity-product-001')->'product_images_v1'),1,'v6 projects one selected product pair');
select is(public.storefront_menu_v6('visual-parity-product-001')#>>'{product_images_v1,0,w960_url}',
 '/storage/v1/object/public/storefront-media/'||(pg_temp.pr('main960')->>'object_key'),'v6 exposes selected large variant');
select is((select i->>'image_url' from jsonb_array_elements(public.storefront_menu_v6('visual-parity-product-001')->'items') i where i->>'id'=pg_temp.pid('main')::text),
 '/storage/v1/object/public/storefront-media/'||(pg_temp.pr('main480')->>'object_key'),'v6 item uses selected small variant');
select is((select image_path from menu_items where id=pg_temp.pid('main')),pg_temp.pkey('main'),'cutout selection never changes catalogue original image_path');
select is((select to_jsonb(o) from storage.objects o where bucket_id='menu-images' and name=pg_temp.pkey('main')),pg_temp.pr('original-object-before'),'original private storage metadata remains byte-for-byte unchanged');
select is((select hero_media_id from restaurant_storefront_profiles where restaurant_id=pg_temp.pid('restaurant')),pg_temp.pid('hero'),'product finalize/select never repoints Hero');
select is((select jsonb_build_array(receipt_logo_path,receipt_logo_enabled,receipt_logo_version) from restaurants where id=pg_temp.pid('restaurant')),pg_temp.pr('receipt-before'),'product lifecycle preserves receipt branding');
update storage.objects set metadata=jsonb_set(metadata,'{mimetype}','"image/png"') where bucket_id='storefront-media' and name=pg_temp.pr('main480')->>'object_key';
select is(public.storefront_menu_v6('visual-parity-product-001')->'product_images_v1','[]'::jsonb,'public reader suppresses the whole selected pair when one output is unavailable');
select is((select derivative_id from app.storefront_product_selections where item_id=pg_temp.pid('main')),pg_temp.did('main'),'read-only suppression does not change selection');
update storage.objects set metadata=jsonb_set(metadata,'{mimetype}','"image/webp"') where bucket_id='storefront-media' and name=pg_temp.pr('main480')->>'object_key';
set local role authenticated;
insert into product_results values('selected-replacement',pg_temp.stage('selected-replacement','main','w480'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id=pg_temp.mid('selected-replacement');
set local role authenticated;
select is(pg_temp.finalize('selected-replacement','selected-replacement')->>'error','stale_request','finalize cannot replace one rung beneath an already selected pair');
reset role;
select is((select count(*)::integer from storefront_media where product_derivative_id=pg_temp.did('main') and published_at is not null and unpublished_at is null),2,'failed replacement leaves exactly the original two live rungs');

-- Legacy publication may share bytes but may never reuse/rebind product rows.
set local role authenticated;
insert into product_results values('legacy960',public.stage_storefront_media(pg_temp.pid('legacy960'),pg_temp.pid('org'),pg_temp.pid('restaurant'),
 'menu-images',pg_temp.pkey('main','cutout'),'w960',md5('main960')||md5('tail-main960'),960,240,1000));
select is(pg_temp.pr('legacy960')->>'ok','true','old stage still accepts its supported editorial publication');
select isnt(pg_temp.mid('legacy960'),pg_temp.mid('main960'),'old stage excludes product association from dedup');
reset role;
select is((select product_derivative_id from storefront_media where id=pg_temp.mid('legacy960')),null::uuid,'legacy row is not silently marked as product');
select is((select product_derivative_id from storefront_media where id=pg_temp.mid('main960')),pg_temp.did('main'),'product association survives legacy dedup request');

-- Choose Original explicitly using its own two variants; same original source
-- as Hero must not cause generic same-source rebinds.
set local role authenticated;
insert into product_results values('restore',pg_temp.register('restore','main','original',1));
insert into product_results values('source-restore',pg_temp.source('restore'));
insert into product_results values('restore480',pg_temp.stage('restore480','restore','w480')),('restore960',pg_temp.stage('restore960','restore','w960'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id in(pg_temp.mid('restore480'),pg_temp.mid('restore960'));
set local role authenticated;
select is(pg_temp.finalize('restore480','restore480')->>'ok','true','original small variant finalizes separately');
select is(pg_temp.finalize('restore960','restore960')->>'ok','true','original large variant finalizes separately');
select is(pg_temp.choose('restore','restore')->>'selection_version','2','Original is an explicit next selection');
select is(pg_temp.choose('main','main')->>'error','stale_request','replaying superseded selection cannot restore old cutout');
select is(pg_temp.original('main')->>'selected_derivative_id',pg_temp.did('restore')::text,'readback identifies restored original treatment');
reset role;
select is((select hero_media_id from restaurant_storefront_profiles where restaurant_id=pg_temp.pid('restaurant')),pg_temp.pid('hero'),'same-source product Original publication still preserves Hero');
select ok((select unpublished_at is null from storefront_media where id=pg_temp.pid('hero')),'same-source Hero media remains published');

-- Changing source generations invalidates before stage, before finalize, and
-- after selection, including previously successful request IDs.
set local role authenticated;
insert into product_results select item,pg_temp.register(item,item) from unnest(array['stage-stale','finalize-stale','selected-stale']) item;
insert into product_results select 'source-'||item,pg_temp.source(item) from unnest(array['stage-stale','finalize-stale','selected-stale']) item;
insert into product_results values('stale-stage-replay',pg_temp.stage('stale-stage-replay','stage-stale','w480')),
 ('stale-finalize',pg_temp.stage('stale-finalize','finalize-stale','w480')),
 ('selected480',pg_temp.stage('selected480','selected-stale','w480')),
 ('selected960',pg_temp.stage('selected960','selected-stale','w960'));
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,jsonb_build_object('mimetype','image/webp','size',bytes)
 from storefront_media where id in(pg_temp.mid('stale-finalize'),pg_temp.mid('selected480'),pg_temp.mid('selected960'));
set local role authenticated;
select is(pg_temp.finalize('selected480','selected480')->>'ok','true','fresh selected-stale fixture low rung publishes');
select is(pg_temp.finalize('selected960','selected960')->>'ok','true','fresh selected-stale fixture high rung publishes');
select is(pg_temp.choose('selected','selected-stale')->>'ok','true','fresh selected-stale fixture is visible');
reset role;
update storage.objects set version='generation-2',updated_at=updated_at+interval '1 second' where bucket_id='menu-images'
 and name in(pg_temp.pkey('stage-stale','cutout'),pg_temp.pkey('finalize-stale'),pg_temp.pkey('selected-stale','cutout'));
set local role authenticated;
select is(pg_temp.source('stage-stale')->>'error','source_stale','candidate overwrite invalidates private source read');
select is(pg_temp.register('stage-stale','stage-stale')->>'error','source_stale','register retry cannot return stale candidate generation');
select is(pg_temp.stage('stale-stage-new','stage-stale','w960')->>'error','source_stale','candidate overwrite rejected before a new stage');
select is(pg_temp.stage('stale-stage-replay','stage-stale','w480')->>'error','source_stale','candidate overwrite rejected on successful stage replay');
select is(pg_temp.finalize('stale-finalize','stale-finalize')->>'error','source_stale','original generation change rejected before finalize');
select is(pg_temp.finalize('selected960','selected960')->>'error','source_stale','successful finalize retry rechecks selected candidate generation');
select is(pg_temp.choose('selected','selected-stale')->>'error','source_stale','selection replay rechecks source generation');
reset role;
select ok(not exists(select 1 from jsonb_array_elements(public.storefront_menu_v6('visual-parity-product-001')->'product_images_v1') i
 where i->>'item_id'=pg_temp.pid('selected-stale')::text),'public read hides a stale selected generation');
select is((select derivative_id from app.storefront_product_selections where item_id=pg_temp.pid('selected-stale')),pg_temp.did('selected-stale'),'stale public suppression does not mutate authoritative saved selection');
select ok((select published_at is null from storefront_media where id=pg_temp.mid('stale-finalize')),'failed finalize leaves original staged state intact');
select is((select count(*)::integer from app.storefront_product_derivatives where organization_id=pg_temp.pid('foreign-org')),1,'foreign derivative association unchanged by cross-tenant attacks');
select is((select count(*)::integer from app.storefront_product_selections where organization_id=pg_temp.pid('foreign-org')),0,'cross-tenant attempts never select foreign media');
select is((select image_path from menu_items where id=pg_temp.pid('main')),pg_temp.pkey('main'),'all tests preserve original catalogue pointer');
select * from finish();
rollback;
