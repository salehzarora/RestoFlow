-- BIZBOT-STOREFRONT-VISUAL-PARITY-001-API: synthetic, rollback-only appearance checks.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.aid(label text) returns uuid language sql immutable as $$select md5('storefront-visual-parity-001-'||label)::uuid;$$;
create function pg_temp.appearance_document() returns jsonb language sql immutable as $$
 select jsonb_build_object('hero_headline','Hello','hero_subline',null,'announcement_text',null,
  'hero',jsonb_build_object('mode','editorial','item_id',null,'format',null,'eyebrow',null,'stamp',null,'footnote',null),
  'announcement_segments',null,'promo',null,'story',null,'category_presentation','[]'::jsonb,'item_presentation','[]'::jsonb);
$$;
create function pg_temp.appearance_save(label text,document jsonb,version integer) returns jsonb language sql volatile as $$
 select public.set_restaurant_storefront_content_v1(pg_temp.aid(label),pg_temp.aid('org'),pg_temp.aid('restaurant'),version,pg_temp.aid('branch'),document);
$$;
insert into organizations(id,name,slug,default_currency) values(pg_temp.aid('org'),'Appearance test','appearance-visual-parity-001','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.aid('restaurant'),pg_temp.aid('org'),'Appearance test','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values(pg_temp.aid('branch'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'Appearance test','UTC',false,'exclusive');
-- The existing profile writer rechecks publish preconditions even for a Hero-only patch.
insert into menu_categories(id,organization_id,restaurant_id,name,is_active)
 values(pg_temp.aid('category'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'Appearance category',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active)
 values(pg_temp.aid('item'),pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('category'),'Appearance item',1000,'ILS',true);
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,opening_hours,is_published,version)
 values(pg_temp.aid('restaurant'),pg_temp.aid('org'),pg_temp.aid('branch'),'appearance-visual-parity-001','Appearance test','0521234567',
 '{"weekly":[{"dow":1,"open":"09:00","close":"17:00"}],"exceptions":[]}'::jsonb,true,10);
select is(app.storefront_publish_blockers(pg_temp.aid('org'),pg_temp.aid('restaurant'),pg_temp.aid('branch'),p.slug,p.opening_hours),
 array[]::text[],'published fixture satisfies existing profile writer preconditions')
 from restaurant_storefront_profiles p where p.restaurant_id=pg_temp.aid('restaurant');
insert into app_users(id,email) values(pg_temp.aid('user'),'appearance@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values(pg_temp.aid('membership'),pg_temp.aid('user'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'manager');
select set_config('app.current_app_user_id',pg_temp.aid('user')::text,true);
create function pg_temp.scene_document(scene jsonb) returns jsonb language sql immutable as $$
 select pg_temp.appearance_document()||jsonb_build_object('appearance',jsonb_build_object('text_color',null,'button_text_color',null,'scene_preset',scene));$$;
select is(app.storefront_content_document_shape_v1(pg_temp.scene_document(v))->>'field','appearance.scene_preset','malformed scene rejected: '||v::text)
 from (values ('"dark"'::jsonb),('"reference-dark"'::jsonb),('"reference_dark "'::jsonb),('1'::jsonb),('true'::jsonb),('[]'::jsonb),('{}'::jsonb)) x(v);
select is(app.storefront_content_document_shape_v1(pg_temp.scene_document(v))#>'{document,appearance,scene_preset}',v,'accepted explicit scene: '||v::text)
 from (values ('"reference_dark"'::jsonb),('null'::jsonb)) x(v);

set local role authenticated;
select is(public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant')),
 public.get_restaurant_storefront_content_v2(pg_temp.aid('org'),pg_temp.aid('restaurant')),'no preset preserves exact old private response');
select is(pg_temp.appearance_save('select',pg_temp.scene_document('"reference_dark"'),10)->>'version','11','explicit reference preset saves once');
select is(pg_temp.appearance_save('select',pg_temp.scene_document('"reference_dark"'),10)->>'idempotent_replay','true','exact request safely replays');
select is(public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,scene_preset}',
 'reference_dark','authoritative private reload retains reference preset');
select is(public.get_restaurant_storefront_content_v2(pg_temp.aid('org'),pg_temp.aid('restaurant')),
 public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant')) #- '{document,appearance,scene_preset}','legacy public management wrapper retains strict shape');
select is(app.get_restaurant_storefront_content_v2(pg_temp.aid('org'),pg_temp.aid('restaurant')),
 app.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant')) #- '{document,appearance,scene_preset}','legacy authenticated app helper also retains strict shape');
select is(pg_temp.appearance_save('legacy',public.get_restaurant_storefront_content_v2(pg_temp.aid('org'),pg_temp.aid('restaurant'))->'document',11)->>'version','12','old reader document stays writable');
select is(public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>>'{document,appearance,scene_preset}',
 'reference_dark','old write omits and preserves preset');
reset role;
select ok(exists(select 1 from audit_events where restaurant_id=pg_temp.aid('restaurant') and action='settings.storefront.content.updated'
 and new_values#>>'{appearance,scene_preset}'='reference_dark'),'authoritative audit retains the saved scene');
select is(public.storefront_menu_v6('appearance-visual-parity-001')#>>'{content_v1,appearance,scene_preset}','reference_dark','public v6 exposes selected preset');
select is(public.storefront_menu_v5('appearance-visual-parity-001'),
 (public.storefront_menu_v6('appearance-visual-parity-001')-'product_images_v1') #- '{content_v1,appearance,scene_preset}','no media selection gives exact legacy public projection');
select throws_ok($$update app.storefront_content_profiles set appearance=jsonb_set(appearance,'{scene_preset}','"invalid"') where restaurant_id=pg_temp.aid('restaurant')$$,
 '23514',null,'table constraint rejects unsupported preset');
insert into organizations(id,name,slug,default_currency) values(pg_temp.aid('foreign-org'),'Foreign scene','foreign-scene-001','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.aid('foreign-restaurant'),pg_temp.aid('foreign-org'),'Foreign scene','UTC');
set local role authenticated;
select throws_ok($$select public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('foreign-restaurant'))$$,
 '42501',null,'new private reader rejects cross-tenant ancestry');
select throws_ok($$select public.set_restaurant_storefront_content_v1(pg_temp.aid('foreign-write'),pg_temp.aid('foreign-org'),pg_temp.aid('foreign-restaurant'),1,pg_temp.aid('branch'),pg_temp.scene_document('"reference_dark"'))$$,
 '42501',null,'scene writer retains cross-tenant authority rejection');
select is(pg_temp.appearance_save('clear',pg_temp.scene_document('null'),12)->>'version','13','explicit null restores inherited legacy scene');
select is(public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant'))#>'{document,appearance,scene_preset}',
 'null'::jsonb,'clear authoritatively roundtrips');
reset role;
set local role anon;
select is(public.storefront_menu_v6('appearance-visual-parity-001')->>'ok','true','anonymous public read remains permitted');
select throws_ok($$select public.get_restaurant_storefront_content_v3(pg_temp.aid('org'),pg_temp.aid('restaurant'))$$,
 '42501',null,'anonymous private read remains forbidden');
reset role;
select * from finish();
rollback;
