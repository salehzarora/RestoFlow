-- BIZBOT-STOREFRONT-CONTENT-CONTRACT-001: CI invalidation regression.
-- Synthetic identities only; all fixtures and injected failures roll back.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.iid(label text) returns uuid language sql immutable as $$
 select md5('storefront-content-invalidation-001-'||label)::uuid;
$$;
create function pg_temp.invalidation_state(label text) returns jsonb language sql volatile as $$
 select jsonb_build_object(
  'profile',(select to_jsonb(p) from public.restaurant_storefront_profiles p where restaurant_id=pg_temp.iid(label)),
  'content',(select coalesce(jsonb_agg(to_jsonb(c) order by c.storefront_branch_id),'[]'::jsonb) from app.storefront_content_profiles c where restaurant_id=pg_temp.iid(label)),
  'categories',(select coalesce(jsonb_agg(to_jsonb(c) order by c.storefront_branch_id,c.category_id),'[]'::jsonb) from app.storefront_category_presentation c where restaurant_id=pg_temp.iid(label)),
  'items',(select coalesce(jsonb_agg(to_jsonb(c) order by c.storefront_branch_id,c.item_id),'[]'::jsonb) from app.storefront_item_presentation c where restaurant_id=pg_temp.iid(label)),
  'audit',(select coalesce(jsonb_agg(to_jsonb(a) order by a.id),'[]'::jsonb) from public.audit_events a where restaurant_id=pg_temp.iid(label)),
  'ledger',(select coalesce(jsonb_agg(to_jsonb(r) order by r.client_request_id),'[]'::jsonb) from public.management_request_results r where actor_app_user_id=pg_temp.iid('manager')));
$$;
insert into organizations(id,name,slug,default_currency)
 values(pg_temp.iid('org'),'Invalidation fixture','content-invalidation-001','ILS');
insert into restaurants(id,organization_id,name,timezone)
 select pg_temp.iid(r),pg_temp.iid('org'),'Invalidation '||r,'UTC' from unnest(array['empty','content']) r;
insert into branches(id,organization_id,restaurant_id,name,timezone)
 select pg_temp.iid(r||'-'||b),pg_temp.iid('org'),pg_temp.iid(r),'Invalidation '||r||' '||b,'UTC'
 from unnest(array['empty','content']) r cross join unnest(array['a','b']) b;
insert into restaurant_storefront_profiles(organization_id,restaurant_id,storefront_branch_id,slug,display_name,hero_headline,is_published,version)
 select pg_temp.iid('org'),pg_temp.iid(r),pg_temp.iid(r||case when r='empty' then '-a' else '-b' end),'content-invalidation-'||r,'Invalidation '||r,'Alpha Beta',true,10
 from unnest(array['empty','content']) r;
insert into app_users(id,email) values(pg_temp.iid('manager'),'content-invalidation-manager@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role)
 values(pg_temp.iid('membership'),pg_temp.iid('manager'),pg_temp.iid('org'),pg_temp.iid('content'),'manager');
insert into menu_categories(id,organization_id,restaurant_id,name,is_active)
 values(pg_temp.iid('category'),pg_temp.iid('org'),pg_temp.iid('content'),'Synthetic category',true);
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
 values(pg_temp.iid('item'),pg_temp.iid('org'),pg_temp.iid('content'),pg_temp.iid('category'),'Synthetic item',1234,'ILS');

-- Only the other restaurant has a sidecar. Its sole row is on a previous branch.
insert into app.storefront_content_profiles(organization_id,restaurant_id,storefront_branch_id,headline_format_text,headline_highlight_start,headline_highlight_end,headline_break_before)
 values(pg_temp.iid('org'),pg_temp.iid('content'),pg_temp.iid('content-a'),'Alpha Beta',0,5,6);
insert into app.storefront_category_presentation(organization_id,restaurant_id,storefront_branch_id,category_id,heading)
 values(pg_temp.iid('org'),pg_temp.iid('content'),pg_temp.iid('content-a'),pg_temp.iid('category'),'Saved heading');
insert into app.storefront_item_presentation(organization_id,restaurant_id,storefront_branch_id,item_id,image_fit)
 values(pg_temp.iid('org'),pg_temp.iid('content'),pg_temp.iid('content-a'),pg_temp.iid('item'),'whole-image');
create temp table invalidation_snapshots(label text primary key,state jsonb not null);
insert into invalidation_snapshots values('other-restaurant',pg_temp.invalidation_state('content'));
select set_config('app.current_app_user_id','',true);
select is(app.current_app_user_id(),null::uuid,'absence fixture has no management actor');
select lives_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('empty-b'),version=version+1 where restaurant_id=pg_temp.iid('empty')$$,'no sidecars: branch change needs no content audit');
select lives_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('empty-a'),version=version+1 where restaurant_id=pg_temp.iid('empty')$$,'no sidecars: return to old branch needs no content audit');
select lives_ok($$update public.restaurant_storefront_profiles set hero_headline='Changed legacy headline',version=version+1 where restaurant_id=pg_temp.iid('empty')$$,'no sidecars: legacy text edit needs no content audit');
select lives_ok($$update public.restaurant_storefront_profiles set deleted_at=now(),version=version+1 where restaurant_id=pg_temp.iid('empty')$$,'no sidecars: soft deletion needs no content audit');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.iid('empty')),14,'legacy changes actually completed without an actor');
select is((select count(*) from app.storefront_content_profiles where restaurant_id=pg_temp.iid('empty')),0::bigint,'legacy changes create no content profile');
select is((select count(*) from app.storefront_category_presentation where restaurant_id=pg_temp.iid('empty')),0::bigint,'legacy changes create no category presentation');
select is((select count(*) from app.storefront_item_presentation where restaurant_id=pg_temp.iid('empty')),0::bigint,'legacy changes create no item presentation');
select is((select count(*) from audit_events where restaurant_id=pg_temp.iid('empty') and action in ('settings.storefront.content.invalidated','settings.storefront.content.format_invalidated')),0::bigint,'legacy changes create no content invalidation audit');
select is(pg_temp.invalidation_state('content'),(select state from invalidation_snapshots where label='other-restaurant'),'another restaurant sidecars and audits remain untouched');

-- A current-branch-only existence check would incorrectly bypass this audit.
select ok(not exists(select 1 from app.storefront_content_profiles where restaurant_id=pg_temp.iid('content') and storefront_branch_id=pg_temp.iid('content-b')),'only a different branch has content');
insert into invalidation_snapshots values('missing-actor-branch',pg_temp.invalidation_state('content'));
select throws_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('content-a'),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'23514',null,'previous-branch sidecar still requires actor-present audit');
select is(pg_temp.invalidation_state('content'),(select state from invalidation_snapshots where label='missing-actor-branch'),'missing actor rolls profile, version, format, every sidecar, audit and ledger back');

select set_config('app.current_app_user_id',pg_temp.iid('manager')::text,true);
select lives_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('content-a'),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'previous-branch sidecar with valid actor invalidates atomically');
select is((select headline_format_text from app.storefront_content_profiles where restaurant_id=pg_temp.iid('content')),null::text,'branch transition clears previous-branch format');
select is((select count(*) from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.invalidated'),1::bigint,'one branch invalidation audit');
select is((select actor_app_user_id from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.invalidated'),pg_temp.iid('manager'),'valid management identity retained in audit');
select is((select new_values->>'reason' from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.invalidated'),'storefront_branch_changed','branch reason retained');

-- The audit injection verifies all preceding effects before raising. A caught
-- error envelope alone would not prove rollback of the underlying mutation.
create function pg_temp.fail_invalidation_audit() returns trigger language plpgsql as $$
begin
 if new.action='settings.storefront.content.invalidated' and new.restaurant_id=pg_temp.iid('content') then
  if (select storefront_branch_id=pg_temp.iid('content-b') from public.restaurant_storefront_profiles where restaurant_id=new.restaurant_id)
   and (select deleted_at is not null and headline_format_text is null from app.storefront_content_profiles where restaurant_id=new.restaurant_id and storefront_branch_id=pg_temp.iid('content-a'))
   and (select deleted_at is not null from app.storefront_category_presentation where restaurant_id=new.restaurant_id)
   and (select deleted_at is not null from app.storefront_item_presentation where restaurant_id=new.restaurant_id) then
   raise exception 'synthetic-invalidation-postwrite-failure';
  end if;
  raise exception 'synthetic-invalidation-not-reached';
 end if;
 return new;
end;$$;
create trigger content_invalidation_test_failure before insert on public.audit_events for each row execute function pg_temp.fail_invalidation_audit();
insert into invalidation_snapshots values('audit-injected',pg_temp.invalidation_state('content'));
select throws_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('content-b'),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'P0001','synthetic-invalidation-postwrite-failure','audit failure occurs after profile and all sidecar invalidation writes');
select is(pg_temp.invalidation_state('content'),(select state from invalidation_snapshots where label='audit-injected'),'failed audit rolls every preceding write back exactly');
drop trigger content_invalidation_test_failure on public.audit_events;

select lives_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('content-b'),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'valid actor commits branch invalidation and audit');
select ok((select deleted_at is not null from app.storefront_content_profiles where restaurant_id=pg_temp.iid('content')),'old content profile tombstoned');
select ok((select deleted_at is not null from app.storefront_category_presentation where restaurant_id=pg_temp.iid('content')),'old category presentation tombstoned');
select ok((select deleted_at is not null from app.storefront_item_presentation where restaurant_id=pg_temp.iid('content')),'old item presentation tombstoned');
select is((select count(*) from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.invalidated'),2::bigint,'successful second transition audits exactly once');

-- A tombstoned previous-branch row is still a sidecar, not the absent state.
select set_config('app.current_app_user_id','',true);
insert into invalidation_snapshots values('tombstone-missing-actor',pg_temp.invalidation_state('content'));
select throws_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('content-a'),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'23514',null,'tombstoned previous-branch settings do not bypass actor audit');
select is(pg_temp.invalidation_state('content'),(select state from invalidation_snapshots where label='tombstone-missing-actor'),'tombstone transition failure is fully rolled back');
select set_config('app.current_app_user_id',pg_temp.iid('manager')::text,true);
select lives_ok($$update public.restaurant_storefront_profiles set storefront_branch_id=pg_temp.iid('content-a'),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'valid actor returns while preserving sidecar tombstones');
select ok((select deleted_at is not null from app.storefront_content_profiles where restaurant_id=pg_temp.iid('content')),'branch return never reactivates content');
select is((select count(*) from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.invalidated'),3::bigint,'return with tombstoned content still audited');

-- Synthetic restoration only, to isolate headline and deletion paths.
update app.storefront_content_profiles set deleted_at=null,headline_format_text='Alpha Beta',headline_highlight_start=0,headline_highlight_end=5,headline_break_before=6 where restaurant_id=pg_temp.iid('content');
update app.storefront_category_presentation set deleted_at=null where restaurant_id=pg_temp.iid('content');
update app.storefront_item_presentation set deleted_at=null where restaurant_id=pg_temp.iid('content');
select set_config('app.current_app_user_id','',true);
insert into invalidation_snapshots values('missing-actor-format',pg_temp.invalidation_state('content'));
select throws_ok($$update public.restaurant_storefront_profiles set hero_headline='Beta Gamma',version=version+1 where restaurant_id=pg_temp.iid('content')$$,'23514',null,'format invalidation cannot bypass actor audit');
select is(pg_temp.invalidation_state('content'),(select state from invalidation_snapshots where label='missing-actor-format'),'missing actor rolls headline and format clearing back');
select set_config('app.current_app_user_id',pg_temp.iid('manager')::text,true);
select lives_ok($$update public.restaurant_storefront_profiles set hero_headline='Beta Gamma',version=version+1 where restaurant_id=pg_temp.iid('content')$$,'valid actor commits headline and format invalidation');
select ok((select headline_format_text is null and headline_highlight_start is null and headline_highlight_end is null and headline_break_before is null from app.storefront_content_profiles where restaurant_id=pg_temp.iid('content')),'all format offsets clear together');
select is((select count(*) from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.format_invalidated' and actor_app_user_id=pg_temp.iid('manager')),1::bigint,'format invalidation retains correct actor exactly once');

select set_config('app.current_app_user_id','',true);
insert into invalidation_snapshots values('missing-actor-delete',pg_temp.invalidation_state('content'));
select throws_ok($$update public.restaurant_storefront_profiles set deleted_at=now(),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'23514',null,'soft deletion with sidecars cannot bypass actor audit');
select is(pg_temp.invalidation_state('content'),(select state from invalidation_snapshots where label='missing-actor-delete'),'failed deletion rolls profile and all sidecars back');
select set_config('app.current_app_user_id',pg_temp.iid('manager')::text,true);
select lives_ok($$update public.restaurant_storefront_profiles set deleted_at=now(),version=version+1 where restaurant_id=pg_temp.iid('content')$$,'valid actor commits deletion and invalidation audit');
select ok((select deleted_at is not null from restaurant_storefront_profiles where restaurant_id=pg_temp.iid('content')),'profile deletion committed');
select ok((select deleted_at is not null from app.storefront_content_profiles where restaurant_id=pg_temp.iid('content')),'deletion invalidates content profile');
select ok((select deleted_at is not null from app.storefront_category_presentation where restaurant_id=pg_temp.iid('content')),'deletion invalidates category presentation');
select ok((select deleted_at is not null from app.storefront_item_presentation where restaurant_id=pg_temp.iid('content')),'deletion invalidates item presentation');
select is((select count(*) from audit_events where restaurant_id=pg_temp.iid('content') and action='settings.storefront.content.invalidated' and new_values->>'reason'='profile_deleted' and actor_app_user_id=pg_temp.iid('manager')),1::bigint,'deletion is audited with its original actor/reason');
select * from finish();
rollback;
