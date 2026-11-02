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

insert into organizations(id,name,slug,default_currency) values(pg_temp.aid('org'),'Appearance test','appearance-cinematic-001b','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.aid('restaurant'),pg_temp.aid('org'),'Appearance test','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode) values(pg_temp.aid('branch'),pg_temp.aid('org'),pg_temp.aid('restaurant'),'Appearance test','UTC',false,'exclusive');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,public_phone,is_published,version)
 values(pg_temp.aid('restaurant'),pg_temp.aid('org'),pg_temp.aid('branch'),'appearance-cinematic-001b','Appearance test','0521234567',true,10);
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
reset role;
select * from finish();
rollback;
