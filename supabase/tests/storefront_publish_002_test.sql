-- STOREFRONT-PUBLISH-002: current item association, generation races and replay safety.
-- Synthetic fixtures only; every mutation rolls back.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';
set local storage.allow_delete_query = 'true';

select no_plan();

-- ===== fixtures ==============================================================
insert into organizations (id, name, slug, default_currency, status) values
  ('00000000-0000-0000-0000-00b100000a00', 'SFP Org A', 'sfp1-org-a', 'ILS', 'active'),
  ('00000000-0000-0000-0000-00b100000b00', 'SFP Org B', 'sfp1-org-b', 'ILS', 'active');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b100000a00', 'SFP Rest A1', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00b100000a20', '00000000-0000-0000-0000-00b100000a00', 'SFP Rest A2', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00b100000b10', '00000000-0000-0000-0000-00b100000b00', 'SFP Rest B1', 'Asia/Jerusalem');
insert into branches (id, organization_id, restaurant_id, name, timezone, tax_enabled, tax_rate_bp, tax_mode) values
  ('00000000-0000-0000-0000-00b100000a1a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'A1a', 'Asia/Jerusalem', false, 0, 'exclusive'),
  ('00000000-0000-0000-0000-00b100000a2a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a20', 'A2a', 'Asia/Jerusalem', false, 0, 'exclusive'),
  ('00000000-0000-0000-0000-00b100000b1a', '00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000b10', 'B1a', 'Asia/Jerusalem', false, 0, 'exclusive');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00b10000ee01', 'sfp1-owner-a@example.test'),
  ('00000000-0000-0000-0000-00b10000ee02', 'sfp1-manager-a1@example.test'),
  ('00000000-0000-0000-0000-00b10000ee03', 'sfp1-cashier-a1@example.test'),
  ('00000000-0000-0000-0000-00b10000ee04', 'sfp1-manager-a2@example.test'),
  ('00000000-0000-0000-0000-00b10000ee05', 'sfp1-cashier-orgwide@example.test'),
  ('00000000-0000-0000-0000-00b10000ee0b', 'sfp1-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00b10000ab01', '00000000-0000-0000-0000-00b10000ee01', '00000000-0000-0000-0000-00b100000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00b10000ab02', '00000000-0000-0000-0000-00b10000ee02', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, 'manager'),
  ('00000000-0000-0000-0000-00b10000ab03', '00000000-0000-0000-0000-00b10000ee03', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, 'cashier'),
  ('00000000-0000-0000-0000-00b10000ab04', '00000000-0000-0000-0000-00b10000ee04', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a20', null, 'manager'),
  ('00000000-0000-0000-0000-00b10000ab05', '00000000-0000-0000-0000-00b10000ee05', '00000000-0000-0000-0000-00b100000a00', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00b10000ab0b', '00000000-0000-0000-0000-00b10000ee0b', '00000000-0000-0000-0000-00b100000b00', null, null, 'org_owner');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('00000000-0000-0000-0000-00b10000c1a1', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, 'SFP Cat', 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active, image_path) values
  ('00000000-0000-0000-0000-00b100011a01', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, '00000000-0000-0000-0000-00b10000c1a1', 'SFP Item', 1500, 'ILS', 0, true,
   '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/global/menu_item/00000000-0000-0000-0000-00b100011a01/00000000-0000-0000-0000-00b10000f102.jpg');

-- the PRIVATE originals (object rows only; the harness role bypasses the private buckets' RLS)
create temp table _k as select
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/logo/00000000-0000-0000-0000-00b10000f101.png'::text as logo_a1,
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/global/menu_item/00000000-0000-0000-0000-00b100011a01/00000000-0000-0000-0000-00b10000f102.jpg'::text as menu_a1,
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a20/logo/00000000-0000-0000-0000-00b10000f103.png'::text as logo_a2,
  '00000000-0000-0000-0000-00b100000b00/00000000-0000-0000-0000-00b100000b10/logo/00000000-0000-0000-0000-00b10000f1b1.png'::text as logo_b1,
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/logo/00000000-0000-0000-0000-00b10000f1ff.png'::text as logo_missing,
  app.storefront_media_prefix('00000000-0000-0000-0000-00b100000a10') as pa1,
  app.storefront_media_prefix('00000000-0000-0000-0000-00b100000b10') as pb1;
grant select on _k to anon, authenticated;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_a1 from _k;
insert into storage.objects (bucket_id, name) select 'menu-images', menu_a1 from _k;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_a2 from _k;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_b1 from _k;

-- a published, always-open profile for R-A1 (the public contract under test)
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a1a', 'sfp1-alpha', 'SFP Alpha',
       jsonb_build_object('weekly', (select jsonb_agg(jsonb_build_object('dow', d, 'open', o, 'close', c))
                                       from generate_series(0, 6) d cross join (values ('00:00', '12:00'), ('11:00', '00:00')) w(o, c)),
                          'exceptions', '[]'::jsonb), true, 1;
-- an org B LIVE derivative (cross-tenant target)
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at)
select '00000000-0000-0000-0000-00b10000fb01', '00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000b10', 'restaurant-logos', logo_b1, 'w480',
       pb1 || '/' || repeat('b', 64) || '.webp', repeat('b', 64), 480, 240, 2000, now() - interval '1 hour' from _k;

create temp table _pm (label text primary key, r jsonb);
grant select, insert on _pm to anon, authenticated;


insert into menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code, is_active, image_path)
select '00000000-0000-0000-0000-00b100011a02', organization_id, restaurant_id, menu_category_id, 'SFP Item Two', 2000, 'ILS', true,
       replace(image_path, '00b100011a01/', '00b100011a02/')
 from menu_items where id='00000000-0000-0000-0000-00b100011a01';
insert into storage.objects(bucket_id,name,version)
select 'menu-images',image_path,'item-two-v1' from menu_items where id='00000000-0000-0000-0000-00b100011a02';
-- Test-only convenience wrappers execute the real public RPC as the real caller.
create function pg_temp.item_source(p_key text) returns jsonb language sql as $$
 select public.get_storefront_item_source('00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10',p_key);
$$;
create function pg_temp.item_stage(p_request integer,p_key text,p_snapshot jsonb) returns jsonb language sql as $$
 select public.stage_storefront_media(md5('sfp2-stage-'||p_request)::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10','menu-images',p_key,'w480',repeat('1',64),480,240,1000,p_snapshot);
$$;
create function pg_temp.item_finalize(p_request integer,p_id uuid) returns jsonb language sql as $$
 select public.finalize_storefront_media(md5('sfp2-finalize-'||p_request)::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10',p_id);
$$;

select ok(not has_function_privilege('anon','public.get_storefront_item_source(uuid,uuid,text)','EXECUTE') and not has_function_privilege('anon','app.get_storefront_item_source(uuid,uuid,text)','EXECUTE'), 'preflight is not anonymous on either layer');

select ok(not has_function_privilege('authenticated','app.storefront_item_source_snapshot(uuid,uuid,text)','EXECUTE'), 'internal helper is not an authenticated bypass');

select ok((select not prosecdef and proconfig=array['search_path=""'] from pg_proc where oid='public.get_storefront_item_source(uuid,uuid,text)'::regprocedure), 'preflight public wrapper pins invoker search_path');

select ok((select prosecdef and proconfig=array['search_path=""'] and pg_get_userbyid(proowner)='postgres' from pg_proc where oid='app.get_storefront_item_source(uuid,uuid,text)'::regprocedure), 'preflight app body pins definer owner/search_path');

select is((select count(*)::int from pg_proc where pronamespace='public'::regnamespace and proname='stage_storefront_media'), 1, 'one stage overload avoids PostgREST ambiguity');

select is((select pronargdefaults from pg_proc where oid='public.stage_storefront_media(uuid,uuid,uuid,text,text,text,text,integer,integer,integer,jsonb)'::regprocedure), 1::smallint, 'legacy ten-argument calls retain default snapshot');

reset role;
set local role anon;

select throws_ok($$ select public.get_storefront_item_source('00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10','x') $$,'42501','permission denied for function get_storefront_item_source','real anon denied at grant layer');

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

set local app.current_app_user_id='00000000-0000-0000-0000-00b10000ee03';

select is(pg_temp.item_source((select menu_a1 from _k))->>'error', 'permission_denied', 'cashier cannot acquire source token');

set local app.current_app_user_id='00000000-0000-0000-0000-00b10000ee04';

select throws_ok($$select pg_temp.item_source((select menu_a1 from _k))$$,'42501',null,'sibling restaurant manager cannot acquire token');

set local app.current_app_user_id='00000000-0000-0000-0000-00b10000ee0b';

select throws_ok($$select pg_temp.item_source((select menu_a1 from _k))$$,'42501',null,'foreign owner cannot acquire token');

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

insert into _pm select 'source1', pg_temp.item_source((select menu_a1 from _k));

insert into _pm select 'source2', pg_temp.item_source(replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'));

select is((select r->> 'ok' from _pm where label='source1'), 'true', 'manager acquires current source token');

select is((select count(*)::int from jsonb_object_keys((select r->'source_snapshot' from _pm where label='source1'))), 3, 'snapshot has exactly three generation fields');

select is(pg_temp.item_stage(1, (select menu_a1 from _k), null)->>'reason', 'source_snapshot_required', 'item cannot omit pre-download token');

select is(pg_temp.item_stage(2, (select menu_a1 from _k), '{}')->>'error', 'source_stale', 'invented token cannot bind item');

insert into _pm select 'item1', pg_temp.item_stage(3, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1'));

insert into _pm select 'item2', pg_temp.item_stage(4, replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'), (select r->'source_snapshot' from _pm where label='source2'));

insert into _pm select 'logo', public.stage_storefront_media(md5('sfp2-logo')::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10','restaurant-logos',(select logo_a1 from _k),'w480',repeat('1',64),480,240,1000);

select is((select count(distinct r->>'media_id')::int from _pm where label in ('item1','item2','logo')), 3, 'shared bytes retain separate item and profile associations');

select is((select count(distinct r->>'object_key')::int from _pm where label in ('item1','item2','logo')), 1, 'identical bytes retain one public content address');

select ok((select bool_and(r->>'source_mismatch'='false') from _pm where label in ('item1','item2','logo')), 'associations are never rebound');

select is((select r->> 'source_key' from _pm where label='item2'), replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'), 'second item receives exact requested association');

select is(pg_temp.item_stage(5, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1'))->>'media_id', (select r->> 'media_id' from _pm where label='item1'), 'same source/generation deduplicates');

select is(pg_temp.item_finalize(1, ((select r->> 'media_id' from _pm where label='item1'))::uuid)->>'error', 'object_missing', 'cannot finalize without derivative');

reset role;
set local role anon;

select ok((select bool_and(x->>'image_url' is null) from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x), 'staged items remain image-less');

reset role;
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',r->>'object_key','{"mimetype":"image/webp","size":1000}' from _pm where label='item1';

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

insert into _pm select 'final_item1', pg_temp.item_finalize(1, ((select r->> 'media_id' from _pm where label='item1'))::uuid);

insert into _pm select 'final_item2', pg_temp.item_finalize(2, ((select r->> 'media_id' from _pm where label='item2'))::uuid);

insert into _pm select 'final_logo', pg_temp.item_finalize(3, ((select r->> 'media_id' from _pm where label='logo'))::uuid);

select ok((select bool_and(r->>'ok'='true') from _pm where label in ('final_item1','final_item2','final_logo')), 'all shared-byte associations finalize independently');

select is(pg_temp.item_finalize(1, ((select r->> 'media_id' from _pm where label='item1'))::uuid)->>'idempotent_replay', 'true', 'unchanged finalize replay succeeds');

select is(pg_temp.item_stage(3, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1'))->>'state', 'published', 'stage replay revalidates and returns current state');

select is(public.set_restaurant_storefront_profile(md5('sfp2-logo-item-denied')::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10',1,jsonb_build_object('logo_media_id',(select r->> 'media_id' from _pm where label='item1')))->>'reason', 'logo_media_id_invalid', 'item cannot become profile logo');

select is(public.set_restaurant_storefront_profile(md5('sfp2-hero-item-denied')::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10',1,jsonb_build_object('hero_media_id',(select r->> 'media_id' from _pm where label='item1')))->>'reason', 'hero_media_id_invalid', 'item cannot become profile hero');

select is(public.set_restaurant_storefront_profile(md5('sfp2-logo-selected')::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10',1,jsonb_build_object('logo_media_id',(select r->> 'media_id' from _pm where label='logo')))->>'ok', 'true', 'legacy logo remains selectable');

insert into _pm select 'legacy_hero', public.stage_storefront_media(md5('sfp2-legacy-hero')::uuid,'00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10','menu-images',(select menu_a1 from _k),'w960',repeat('1',64),480,240,1000);

select is((select r->> 'media_id' from _pm where label='legacy_hero'), (select r->> 'media_id' from _pm where label='logo'), 'legacy cross-source dedup still returns legacy row');

select is((select r->> 'source_mismatch' from _pm where label='legacy_hero'), 'true', 'legacy source mismatch flag unchanged');

reset role;
set local role anon;

insert into _pm select 'public_live', public.storefront_menu('sfp1-alpha');

select is((select count(*)::int from jsonb_array_elements((select r->'items' from _pm where label='public_live')) x where x->>'image_url' is not null), 2, 'both items serve shared derivative');

select ok((select r::text not like '%'||(select menu_a1 from _k)||'%' and r::text not like '%source_snapshot%' from _pm where label='public_live'), 'public payload exposes no private source or snapshot');

reset role;
-- A corrupt borrowed path must not attach item one's derivative to item two.
update menu_items set image_path=(select menu_a1 from _k) where id='00000000-0000-0000-0000-00b100011a02';
set local role anon;
select is((select x->>'image_url' from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x where x->>'name'='SFP Item Two'),null,'reader verifies parsed item ID, not merely a borrowed current path');
reset role;
update menu_items set image_path=replace((select menu_a1 from _k),'00b100011a01/','00b100011a02/') where id='00000000-0000-0000-0000-00b100011a02';
-- Simulate Storage overwrite after preflight/publication using synthetic metadata.
update storage.objects set version='item-one-v2',updated_at=updated_at+interval '1 second' where bucket_id='menu-images' and name=(select menu_a1 from _k);

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_stage(3, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1'))->>'error', 'source_stale', 'stage replay refuses changed generation');

select is(pg_temp.item_stage(6, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1'))->>'error', 'source_stale', 'preflight/download before stage refuses changed generation');

select is(pg_temp.item_finalize(1, ((select r->> 'media_id' from _pm where label='item1'))::uuid)->>'error', 'source_stale', 'finalize replay refuses changed generation');

select is(pg_temp.item_finalize(4, ((select r->> 'media_id' from _pm where label='item1'))::uuid)->>'error', 'source_stale', 'already-live finalize refuses changed generation');

insert into _pm select 'source1_v2', pg_temp.item_source((select menu_a1 from _k));

select throws_ok($$select pg_temp.item_stage(3, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1_v2'))$$,'42501',null,'changed snapshot cannot reuse claimed request ID');

insert into _pm select 'item1_v2', pg_temp.item_stage(7, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1_v2'));

select ok((select r->> 'media_id' from _pm where label='item1_v2') <> (select r->> 'media_id' from _pm where label='item1'), 'fresh generation gets distinct association for identical bytes');

reset role;
set local role anon;

select is((select x->>'image_url' from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x where x->>'name'='SFP Item'), null, 'reader hides stale original immediately');

select ok((select x->>'image_url' from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x where x->>'name'='SFP Item Two') is not null, 'other shared-byte item remains visible');

select ok(public.storefront_menu('sfp1-alpha')->'restaurant'->>'logo_url' is not null, 'shared logo unaffected');

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_finalize(5, ((select r->> 'media_id' from _pm where label='item1_v2'))::uuid)->>'ok', 'true', 'fresh generation republishes same bytes safely');

reset role;

select ok((select unpublished_at is not null from storefront_media where id=((select r->> 'media_id' from _pm where label='item1'))::uuid), 'old association retracted without rebinding');

select is((select item_source_snapshot from storefront_media where id=((select r->> 'media_id' from _pm where label='item1'))::uuid), (select r->'source_snapshot' from _pm where label='source1'), 'old generation remains recorded');

delete from storage.objects where bucket_id='menu-images' and name=(select menu_a1 from _k);

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_source((select menu_a1 from _k))->>'error', 'source_not_found', 'getter refuses missing original');

select is(pg_temp.item_stage(7, (select menu_a1 from _k), (select r->'source_snapshot' from _pm where label='source1_v2'))->>'error', 'source_not_found', 'stage replay refuses missing original');

select is(pg_temp.item_finalize(5, ((select r->> 'media_id' from _pm where label='item1_v2'))::uuid)->>'error', 'source_not_found', 'finalize replay refuses missing original');

reset role;
set local role anon;

select is((select x->>'image_url' from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x where x->>'name'='SFP Item'), null, 'reader hides deleted original');

reset role;
insert into storage.objects(bucket_id,name,version) select 'menu-images',menu_a1,'recreated' from _k;

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_finalize(5, ((select r->> 'media_id' from _pm where label='item1_v2'))::uuid)->>'error', 'source_stale', 'delete/recreate at same key cannot revive old association');

reset role;
update menu_items set image_path=null where id='00000000-0000-0000-0000-00b100011a02';

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_source(replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'))->>'error', 'source_not_found', 'leftover original no longer current fails closed');

select is(pg_temp.item_finalize(2, ((select r->> 'media_id' from _pm where label='item2'))::uuid)->>'error', 'source_not_found', 'finalize replay checks current image_path');

reset role;
update menu_items set image_path=replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'),deleted_at=now() where id='00000000-0000-0000-0000-00b100011a02';

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_source(replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'))->>'error', 'source_not_found', 'deleted item cannot acquire source token');

reset role;
update menu_items set deleted_at=null,is_active=false where id='00000000-0000-0000-0000-00b100011a02';

reset role;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';

select is(pg_temp.item_source(replace((select menu_a1 from _k), '00b100011a01/', '00b100011a02/'))->>'error', 'source_not_found', 'inactive item cannot acquire source token');

reset role;
update menu_items set is_active=true where id='00000000-0000-0000-0000-00b100011a02';
update storage.objects set metadata='{"mimetype":"image/png","size":1000}' where bucket_id='storefront-media' and name=(select r->> 'object_key' from _pm where label='item2');

reset role;
set local role anon;

select is((select x->>'image_url' from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x where x->>'name'='SFP Item Two'), null, 'reader hides corrupt derivative metadata');

reset role;
delete from storage.objects where bucket_id='storefront-media' and name=(select r->> 'object_key' from _pm where label='item2');

reset role;
set local role anon;

select is((select x->>'image_url' from jsonb_array_elements(public.storefront_menu('sfp1-alpha')->'items') x where x->>'name'='SFP Item Two'), null, 'reader hides missing derivative');

reset role;
-- More item history than the legacy list budget must not hide current profile media.
insert into storefront_media (organization_id,restaurant_id,source_bucket,source_key,variant,
  object_key,content_hash,width,height,bytes,item_source_snapshot,created_at)
select '00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10',
 'menu-images',menu_a1,'w480',pa1||'/'||md5('history-'||n)||md5('history-'||n)||'.webp',
 md5('history-'||n)||md5('history-'||n),480,240,1000,
 (select r->'source_snapshot' from _pm where label='source1'),now()+n*interval '1 second'
 from _k cross join generate_series(1,201) n;
set local role authenticated;
insert into _pm select 'profile_list',public.list_storefront_media('00000000-0000-0000-0000-00b100000a00','00000000-0000-0000-0000-00b100000a10');
select is((select jsonb_array_length(r->'media') from _pm where label='profile_list'),1,'201 newer item associations cannot consume profile-media list budget');
select is((select r->'media'->0->>'id' from _pm where label='profile_list'),(select r->>'media_id' from _pm where label='logo'),'existing logo remains in manager list');
select is((select r->'media'->0->'in_use' from _pm where label='profile_list'),'["logo"]'::jsonb,'profile list keeps exact legacy in_use contract');
reset role;
select * from finish();
rollback;
