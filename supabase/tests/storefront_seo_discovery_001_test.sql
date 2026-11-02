-- BIZBOT-STOREFRONT-SEO-DISCOVERY-001. Real v4, synthetic rollback-only fixture.
-- This guard runs BEFORE extension/fixture writes and rejects sockets/hosted DBs.
do $$declare s inet:=inet_server_addr();c inet:=inet_client_addr();begin
  if not coalesce(((session_user in('postgres','supabase_admin') and current_database() like 'seo_discovery_%'
      and current_setting('bizbot.seo_discovery_ephemeral',true) is not distinct from 'BIZBOT-STOREFRONT-SEO-DISCOVERY-001')
    or(session_user='postgres' and current_database()='postgres'
      and current_setting('bizbot.featured_ci_ephemeral',true) is not distinct from 'BIZBOT-STOREFRONT-FEATURED-ITEMS-001'))
    and s is not null and c is not null and inet_server_port()=5432 and family(s)=4 and family(c)=4
    and(s<<=inet '127.0.0.0/8' or s<<=inet '10.0.0.0/8' or s<<=inet '172.16.0.0/12' or s<<=inet '192.168.0.0/16')
    and(c<<=inet '127.0.0.0/8' or c<<=inet '10.0.0.0/8' or c<<=inet '172.16.0.0/12' or c<<=inet '192.168.0.0/16'),false)
  then raise exception 'SEO_DISCOVERY_DISPOSABLE_LOCAL_DATABASE_REQUIRED';end if;
end;$$;
begin;
set local statement_timeout='60s';
set local lock_timeout='2s';
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
set local timezone='UTC';
select no_plan();
create function pg_temp.sdid(label text) returns uuid language sql immutable as $$select md5('seo-discovery-001-'||label)::uuid;$$;
insert into public.app_users(id,email) values(pg_temp.sdid('actor'),'seo-discovery-owner@example.test');
create function pg_temp.sdtenant(label text,consent boolean default true) returns void language plpgsql as $$begin
  insert into public.organizations(id,name,slug,default_currency) values(pg_temp.sdid(label||'-org'),'Synthetic SEO '||label,'sd-org-'||label,'ILS');
  insert into public.restaurants(id,organization_id,name,timezone) values(pg_temp.sdid(label||'-rest'),pg_temp.sdid(label||'-org'),'Synthetic SEO '||label,'UTC');
  insert into public.branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
    select pg_temp.sdid(label||'-branch'||suffix),pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),'Branch '||suffix,'UTC',false,'exclusive'
      from unnest(array['','-other']) suffix;
  insert into public.restaurant_storefront_profiles(organization_id,restaurant_id,storefront_branch_id,slug,display_name,is_published)
    values(pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),pg_temp.sdid(label||'-branch'),'sd-'||label,'Synthetic SEO '||label,true);
  if consent is not null then
    insert into app.restaurant_storefront_seo_consent_v1(organization_id,restaurant_id,consent_enabled,revision,updated_by_app_user_id)
      values(pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),consent,1,pg_temp.sdid('actor'));
  end if;
end;$$;
create function pg_temp.sdmenu(label text,ncat integer default 1,nitem integer default 1,nmod integer default 1,nopt integer default 1)
returns void language plpgsql as $$begin
  delete from public.modifier_options where restaurant_id=pg_temp.sdid(label||'-rest');
  delete from public.modifiers where restaurant_id=pg_temp.sdid(label||'-rest');
  delete from public.menu_items where restaurant_id=pg_temp.sdid(label||'-rest');
  delete from public.menu_categories where restaurant_id=pg_temp.sdid(label||'-rest');
  insert into public.menu_categories(id,organization_id,restaurant_id,name,display_order)
    select pg_temp.sdid(label||'-cat-'||n),pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),'Category '||n,n from generate_series(1,ncat)n;
  insert into public.menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,display_order)
    select pg_temp.sdid(label||'-item-'||n),pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),pg_temp.sdid(label||'-cat-1'),'Item '||n,1234,'ILS',n from generate_series(1,nitem)n;
  insert into public.modifiers(id,organization_id,restaurant_id,menu_item_id,name,display_order)
    select pg_temp.sdid(label||'-mod-'||n),pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),pg_temp.sdid(label||'-item-1'),'Modifier '||n,n from generate_series(1,nmod)n;
  insert into public.modifier_options(id,organization_id,restaurant_id,modifier_id,name,price_delta_minor,display_order)
    select pg_temp.sdid(label||'-opt-'||n),pg_temp.sdid(label||'-org'),pg_temp.sdid(label||'-rest'),pg_temp.sdid(label||'-mod-1'),'Option '||n,0,n from generate_series(1,nopt)n;
end;$$;
select pg_temp.sdtenant(x) from unnest(array['a','b','c','d'])x;
select pg_temp.sdmenu(x) from unnest(array['a','b','c','d'])x;
select pg_temp.sdtenant('missing',null);
select pg_temp.sdtenant('off',false);
select pg_temp.sdtenant('empty');
create temp table sd_results(label text primary key,r jsonb);
grant all on sd_results to anon,authenticated,service_role;
create temp table sd_legacy as select p.oid,pg_get_functiondef(p.oid) def,p.proacl,p.proowner,p.proconfig
 from pg_proc p where p.oid in('public.storefront_menu_v4(text)'::regprocedure,
 'public.get_storefront_seo_consent_v1(uuid,uuid)'::regprocedure,
 'public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)'::regprocedure,
 'public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)'::regprocedure,
 'app.storefront_seo_eligibility_when_released_v1(uuid,uuid)'::regprocedure);

-- Exact ACLs include inherited EXECUTE/table/column permissions and PUBLIC.
select ok(relrowsecurity and relforcerowsecurity,'private gate FORCE RLS') from pg_class where oid='app.storefront_seo_release_gate_v1'::regclass;
select is((select count(*) from pg_policy where polrelid='app.storefront_seo_release_gate_v1'::regclass),0::bigint,'gate has no permissive policy');
select is((select count(*) from app.storefront_seo_release_gate_v1),1::bigint,'one private gate row');
select is((select enabled from app.storefront_seo_release_gate_v1),false,'migration does not activate indexing');
select is((select policy_version from app.storefront_seo_release_gate_v1),1,'versioned gate');
select ok((select revision>0 from app.storefront_seo_release_gate_v1),'positive gate revision');
select ok(not has_table_privilege(r,'app.storefront_seo_release_gate_v1','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'),'no private gate privilege: '||r)
 from unnest(array['anon','authenticated','service_role'])r;
select ok(not has_any_column_privilege(r,'app.storefront_seo_release_gate_v1','SELECT,INSERT,UPDATE,REFERENCES'),'no gate column privilege: '||r)
 from unnest(array['anon','authenticated','service_role'])r;
select ok(not exists(select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner)))a
 where c.oid='app.storefront_seo_release_gate_v1'::regclass and a.grantee=0),'PUBLIC has no gate grant');
select ok(has_function_privilege('anon',f,'EXECUTE'),'anon public wrapper: '||f) from unnest(array[
 'public.storefront_seo_page_v1(text)','public.storefront_seo_discovery_v1(text,integer,integer)'])f;
select ok(not has_function_privilege(r,f,'EXECUTE'),'wrapper denied: '||r||' '||f)
 from unnest(array['authenticated','service_role'])r cross join unnest(array[
 'public.storefront_seo_page_v1(text)','public.storefront_seo_discovery_v1(text,integer,integer)'])f;
select ok(not has_function_privilege(r,f,'EXECUTE'),'private helper denied: '||r||' '||f)
 from unnest(array['anon','authenticated','service_role'])r cross join unnest(array[
 'app.storefront_seo_read_v1(text,boolean)','app.storefront_seo_partition_v1(text)'])f;
select ok(not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a where a.grantee=0),'no default PUBLIC execute: '||p.proname)
 from pg_proc p where p.oid in('public.storefront_seo_page_v1(text)'::regprocedure,'public.storefront_seo_discovery_v1(text,integer,integer)'::regprocedure,
 'app.storefront_seo_read_v1(text,boolean)'::regprocedure,'app.storefront_seo_partition_v1(text)'::regprocedure);
select is(p.provolatile::text,'s','read STABLE: '||p.proname) from pg_proc p where p.oid in('public.storefront_seo_page_v1(text)'::regprocedure,
 'public.storefront_seo_discovery_v1(text,integer,integer)'::regprocedure,'app.storefront_seo_read_v1(text,boolean)'::regprocedure);
select ok(p.prosecdef and 'search_path=""'=any(p.proconfig),'definer with empty path: '||p.proname) from pg_proc p where p.oid in(
 'public.storefront_seo_page_v1(text)'::regprocedure,'public.storefront_seo_discovery_v1(text,integer,integer)'::regprocedure,'app.storefront_seo_read_v1(text,boolean)'::regprocedure);
select ok('statement_timeout=2s'=any(p.proconfig) and 'lock_timeout=500ms'=any(p.proconfig),'requested API deadlines: '||p.proname)
 from pg_proc p where p.oid in('public.storefront_seo_page_v1(text)'::regprocedure,'public.storefront_seo_discovery_v1(text,integer,integer)'::regprocedure);
set local role authenticated;
select throws_ok($$select public.storefront_seo_page_v1('sd-a')$$,'42501',null,'authenticated cannot use anonymous wrapper');
reset role;
set local role service_role;
select throws_ok($$select public.storefront_seo_discovery_v1()$$,'42501',null,'service role cannot enumerate');
reset role;
set local role anon;
select throws_ok($$select app.storefront_seo_read_v1('sd-a')$$,'42501',null,'private read helper not exposed');
select throws_ok($$select * from app.storefront_seo_release_gate_v1$$,'42501',null,'private gate not readable');
insert into sd_results values('gate-off-page',public.storefront_seo_page_v1('sd-a')),('gate-off-list',public.storefront_seo_discovery_v1());
reset role;
select is((select r#>>'{seo,eligible}' from sd_results where label='gate-off-page'),'false','gate OFF preserves menu but denies indexing');
select is((select r->'items' from sd_results where label='gate-off-list'),'[]'::jsonb,'known gate OFF returns conclusive empty');
select is((select r->>'ok' from sd_results where label='gate-off-page'),'true','ordinary menu remains public before SEO release');
update app.storefront_seo_release_gate_v1 set enabled=true,revision=revision+1;

-- All positive assertions invoke the actual nested v4 reader, never a mock.
set local role anon;
insert into sd_results values('a',public.storefront_seo_page_v1('sd-a')),('v4-a',public.storefront_menu_v4('sd-a')),
 ('empty',public.storefront_seo_page_v1('sd-empty')),('missing',public.storefront_seo_page_v1('sd-missing')),
 ('off',public.storefront_seo_page_v1('sd-off')),('first',public.storefront_seo_discovery_v1(null,2));
reset role;
select is((select r->'menu' from sd_results where label='a'),(select r from sd_results where label='v4-a'),'wrapper nests exact unchanged actual v4 JSON');
select is((select r#>>'{seo,eligible}' from sd_results where label='a'),'true','gate and explicit consent with real v4 grant eligibility');
select is((select r#>>'{seo,eligible}' from sd_results where label='empty'),'true','empty published menu remains eligible');
select is((select r#>>'{menu,service,state}' from sd_results where label='a'),'closed','default empty-hours closed menu remains a valid real-v4 public page');
select is((select r#>>'{seo,eligible}' from sd_results where label='missing'),'false','missing consent is known OFF');
select is((select r#>>'{seo,eligible}' from sd_results where label='off'),'false','explicit consent OFF');
select is((select array_agg(k order by k) from sd_results,jsonb_object_keys(r)k where label='a'),array['menu','ok','schema','seo'],'page exact public keys');
select is((select array_agg(k order by k) from sd_results,jsonb_object_keys(r->'seo')k where label='a'),array['eligible','evaluated_at','valid_until'],'SEO projection has no reason/revision/actor');
select is((select (r#>>'{seo,valid_until}')::timestamptz-(r#>>'{seo,evaluated_at}')::timestamptz from sd_results where label='a'),interval '10 seconds','page expiry bound to evaluation, not completion');
select is((select array_agg(k order by k) from sd_results,jsonb_object_keys(r)k where label='first'),array['evaluated_at','has_more','items','next_after_slug','ok','schema','valid_until'],'discovery exact public keys');
select is((select r->'items' from sd_results where label='first'),'[{"path":"/s/sd-a/menu"},{"path":"/s/sd-b/menu"}]'::jsonb,'C order over eligible tenant paths');
select is((select r->>'next_after_slug' from sd_results where label='first'),'sd-b','cursor is last returned eligible slug');
select is((select r->>'has_more' from sd_results where label='first'),'true','extra real eligible witness proves more');
select ok((select octet_length(convert_to(r::text,'UTF8'))<=16384 from sd_results where label='first'),'public JSON within 16KiB');
select ok(not exists(select 1 from sd_results,jsonb_array_elements(r->'items')e where label='first' and (select array_agg(k) from jsonb_object_keys(e)k)<>array['path']),'discovery items contain path only');
select ok((select r::text !~ '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' from sd_results where label='first'),'discovery exposes no private UUID');
select is(public.storefront_seo_discovery_v1('sd-b',2)->'items','[{"path":"/s/sd-c/menu"},{"path":"/s/sd-d/menu"}]'::jsonb,'exclusive keyset has no duplicate');
select is(public.storefront_seo_discovery_v1('sd-d',2)->'items','[{"path":"/s/sd-empty/menu"}]'::jsonb,'known excluded slugs omitted without leaked resume key');
select is(public.storefront_seo_discovery_v1('sd-empty',2)->>'has_more','false','conclusive exhausted discovery');
select is(public.storefront_seo_discovery_v1('sd-empty',2)->'next_after_slug','null'::jsonb,'no scan cursor when exhausted');
select is(public.storefront_seo_discovery_v1(null,25)->'items',public.storefront_seo_discovery_v1(null,25)->'items','stable unchanged source order');
select is((public.storefront_seo_discovery_v1(null,25)->>'valid_until')::timestamptz-(public.storefront_seo_discovery_v1(null,25)->>'evaluated_at')::timestamptz,interval '10 seconds','discovery freshness interval exactly ten seconds');

-- All malformed requests have only the versioned generic error envelope.
select is(public.storefront_seo_page_v1(s),' {"ok":false,"schema":1,"error":"not_found"}'::jsonb,'invalid page slug is generic')
 from unnest(array[null::text,'','A','-a','a-','a/b','a?b','a%20b','é',repeat('a',64)])s;
select is(public.storefront_seo_discovery_v1(s,2),'{"ok":false,"schema":1,"error":"invalid_request"}'::jsonb,'invalid cursor never echoed')
 from unnest(array['','A','-a','a-','a/b','é',repeat('a',64)])s;
select is(public.storefront_seo_discovery_v1(null,n),'{"ok":false,"schema":1,"error":"invalid_request"}'::jsonb,'invalid limit') from unnest(array[null::integer,0,-1,26])n;
select is(public.storefront_seo_discovery_v1(null,1,n),'{"ok":false,"schema":1,"error":"invalid_request"}'::jsonb,'invalid partition') from unnest(array[-1,16])n;
select is(public.storefront_seo_page_v1('unknown-tenant'),'{"ok":false,"schema":1,"error":"not_found"}'::jsonb,'unknown and private tenant indistinguishable');
select is(public.storefront_seo_page_v1(repeat('a',63))->>'error','not_found','valid 63-byte unknown slug accepted without echo');
select is(app.storefront_seo_partition_v1('sd-a'),get_byte(sha256(convert_to('sd-a','UTF8')),0)%16,'partition uses canonical public ASCII slug hash');
select ok(app.storefront_seo_partition_v1('Bad') is null,'invalid slug cannot enter private partition index');
select is((select count(*) from generate_series(0,15)p where public.storefront_seo_discovery_v1(null,25,p)->'items' @> '[{"path":"/s/sd-a/menu"}]'::jsonb),1::bigint,'each eligible canonical path belongs to exactly one generic partition');
select ok(not exists(select 1 from generate_series(0,15)p cross join lateral jsonb_array_elements(public.storefront_seo_discovery_v1(null,25,p)->'items')e
 where app.storefront_seo_partition_v1(split_part(e->>'path','/',3))<>p),'partition result cannot cross its declared shard');

-- Publication/ancestry and real reader restrictions; closure/pause are not withdrawal.
update public.restaurant_storefront_profiles set paused_until=now()+interval '1 hour' where restaurant_id=pg_temp.sdid('a-rest');
select is(public.storefront_seo_page_v1('sd-a')#>>'{seo,eligible}','true','temporary pause remains eligible public menu');
update public.restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.sdid('a-rest');
select is(public.storefront_seo_page_v1('sd-a'),'{"ok":false,"schema":1,"error":"not_found"}'::jsonb,'unpublished page unavailable');
select ok(not(public.storefront_seo_discovery_v1(null,25)->'items' @> '[{"path":"/s/sd-a/menu"}]'::jsonb),'unpublished tenant not discoverable');
update public.restaurant_storefront_profiles set is_published=true,deleted_at=now() where restaurant_id=pg_temp.sdid('a-rest');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','deleted public profile unavailable');
update public.restaurant_storefront_profiles set deleted_at=null where restaurant_id=pg_temp.sdid('a-rest');
update public.organizations set status='suspended' where id=pg_temp.sdid('a-org');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','suspended organization unavailable');
update public.organizations set status='active' where id=pg_temp.sdid('a-org');
update public.organizations set deleted_at=now() where id=pg_temp.sdid('a-org');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','deleted organization unavailable');
update public.organizations set deleted_at=null where id=pg_temp.sdid('a-org');
update public.restaurants set status='suspended' where id=pg_temp.sdid('a-rest');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','suspended restaurant unavailable');
update public.restaurants set status='active' where id=pg_temp.sdid('a-rest');
update public.branches set status='suspended' where id=pg_temp.sdid('a-branch');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','suspended selected branch unavailable');
update public.branches set status='active',timezone='Invalid/Timezone' where id=pg_temp.sdid('a-branch');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','actual v4 invalid timezone refusal respected');
update public.restaurants set timezone=null where id=pg_temp.sdid('a-rest');
update public.branches set timezone=null where id=pg_temp.sdid('a-branch');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','missing both branch and restaurant timezone unavailable');
update public.restaurants set timezone='UTC' where id=pg_temp.sdid('a-rest');
update public.branches set timezone='UTC',tax_enabled=true,tax_mode='inclusive' where id=pg_temp.sdid('a-branch');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','actual v4 inclusive-tax refusal respected');
update public.branches set tax_enabled=false,tax_mode='exclusive' where id=pg_temp.sdid('a-branch');
update public.organizations set default_currency='USD' where id=pg_temp.sdid('a-org');
select is(public.storefront_seo_page_v1('sd-a')->>'error','not_found','actual v4 non-ILS refusal respected');
update public.organizations set default_currency='ILS' where id=pg_temp.sdid('a-org');
select is(public.storefront_seo_page_v1('sd-a')#>>'{seo,eligible}','true','normal menu restored without consent rewrite');

-- SEO-only failures preserve the usable menu and return nullable UNKNOWN.
delete from app.storefront_seo_release_gate_v1;
select is(public.storefront_seo_page_v1('sd-a')#>'{seo,eligible}','null'::jsonb,'missing gate is UNKNOWN, not false');
select is(public.storefront_seo_page_v1('sd-a')->>'ok','true','missing gate does not hide real menu');
select is(public.storefront_seo_discovery_v1(),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'missing gate is not conclusive empty');
insert into app.storefront_seo_release_gate_v1 values(true,2,true,1);
select is(public.storefront_seo_page_v1('sd-a')#>'{seo,eligible}','null'::jsonb,'unsupported gate version UNKNOWN');
select is(public.storefront_seo_discovery_v1()->>'error','unavailable','unsupported gate fails discovery closed');
update app.storefront_seo_release_gate_v1 set policy_version=1;
alter table app.restaurant_storefront_seo_consent_v1 rename to seo_discovery_consent_dependency_unavailable;
select is(public.storefront_seo_page_v1('sd-a')#>'{seo,eligible}','null'::jsonb,'unavailable consent dependency is UNKNOWN');
select is(public.storefront_seo_page_v1('sd-a')->>'ok','true','consent-only failure retains actual public menu');
select is(public.storefront_seo_discovery_v1(),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'consent outage never fabricates zero eligible');
alter table app.seo_discovery_consent_dependency_unavailable rename to restaurant_storefront_seo_consent_v1;
alter table app.storefront_seo_release_gate_v1 rename to seo_discovery_gate_dependency_unavailable;
select is(public.storefront_seo_page_v1('sd-a')#>'{seo,eligible}','null'::jsonb,'missing gate dependency UNKNOWN');
select is(public.storefront_seo_discovery_v1()->>'error','unavailable','missing gate dependency fail closed');
alter table app.seo_discovery_gate_dependency_unavailable rename to storefront_seo_release_gate_v1;
alter table public.menu_items rename to seo_discovery_menu_dependency_unavailable;
select is(public.storefront_seo_page_v1('sd-a'),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'menu dependency failure returns no stale/partial menu');
select is(public.storefront_seo_discovery_v1(),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'menu dependency failure returns no partial discovery');
alter table public.seo_discovery_menu_dependency_unavailable rename to menu_items;
alter table public.restaurant_storefront_profiles rename to seo_discovery_publication_dependency_unavailable;
select is(public.storefront_seo_page_v1('sd-a'),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'publication dependency failure cannot hide behind not_found/old menu');
alter table public.seo_discovery_publication_dependency_unavailable rename to restaurant_storefront_profiles;

-- Private bounded count boundary is differential-tested against actual v4.
select pg_temp.sdtenant('caps');
create function pg_temp.sdcap(kind text,n integer) returns void language plpgsql as $$begin
 perform pg_temp.sdmenu('caps',case when kind='categories' then n else 1 end,case when kind='items' then n else 1 end,
  case when kind='modifiers' then n else 1 end,case when kind='options' then n else 1 end);
end;$$;
create function pg_temp.sdcaptest(kind text,n integer,expected boolean) returns setof text language plpgsql as $$declare v jsonb;h jsonb;begin
 perform pg_temp.sdcap(kind,n);
 v:=public.storefront_menu_v4('sd-caps');h:=app.storefront_seo_read_v1('sd-caps',true);
 return next extensions.is(v->>'ok',expected::text,kind||' actual v4 cap at '||n);
 return next extensions.is(h->>'ok',expected::text,kind||' bounded pre-count cap at '||n);
 if expected then return next extensions.is(h->'menu',v,kind||' exact actual v4 at '||n);
 else return next extensions.is(h->>'error','payload_limit',kind||' exclusion before heavy aggregation at '||n);end if;
end;$$;
select t.* from (values('categories',99),('categories',100),('items',499),('items',500),('modifiers',1999),('modifiers',2000),('options',7999),('options',8000))x(k,n)
 cross join lateral pg_temp.sdcaptest(k,n,true)t;
select t.* from (values('categories',101),('items',501),('modifiers',2001),('options',8001))x(k,n)
 cross join lateral pg_temp.sdcaptest(k,n,false)t;
select is(public.storefront_seo_page_v1('sd-caps'),'{"ok":false,"schema":1,"error":"payload_limit"}'::jsonb,'public page preserves typed actual v4 payload error');
select ok(not(public.storefront_seo_discovery_v1(null,25)->'items' @> '[{"path":"/s/sd-caps/menu"}]'::jsonb),'oversized menu omitted from discovery');
-- An over-cap raw relation must not exclude a menu whose reader filters hide it.
update public.modifier_options set price_delta_minor=-1 where restaurant_id=pg_temp.sdid('caps-rest');
select is(public.storefront_menu_v4('sd-caps')->>'ok','true','negative option deltas excluded by actual v4');
select is(app.storefront_seo_read_v1('sd-caps',true)->>'ok','true','pre-count excludes negative option deltas');
select pg_temp.sdcap('options',8001);
update public.modifiers set is_active=false where restaurant_id=pg_temp.sdid('caps-rest');
select is(app.storefront_seo_read_v1('sd-caps',true)->'menu',public.storefront_menu_v4('sd-caps'),'options under inactive modifier do not count');
select pg_temp.sdcap('modifiers',2001);
update public.menu_items set deleted_at=now() where restaurant_id=pg_temp.sdid('caps-rest');
select is(app.storefront_seo_read_v1('sd-caps',true)->'menu',public.storefront_menu_v4('sd-caps'),'modifiers under deleted item do not count');
select pg_temp.sdcap('items',501);
update public.menu_categories set branch_id=pg_temp.sdid('caps-branch-other') where restaurant_id=pg_temp.sdid('caps-rest');
select is(app.storefront_seo_read_v1('sd-caps',true)->'menu',public.storefront_menu_v4('sd-caps'),'items under another selected branch category do not count');
select pg_temp.sdcap('categories',101);
update public.menu_categories set is_active=false where restaurant_id=pg_temp.sdid('caps-rest');
select is(app.storefront_seo_read_v1('sd-caps',true)->'menu',public.storefront_menu_v4('sd-caps'),'inactive categories do not count');
select pg_temp.sdmenu('caps');
insert into public.menu_item_branch_availability(organization_id,restaurant_id,branch_id,menu_item_id,availability,reason)
 values(pg_temp.sdid('caps-org'),pg_temp.sdid('caps-rest'),pg_temp.sdid('caps-branch'),pg_temp.sdid('caps-item-1'),'unavailable','sold_out');
select is(app.storefront_seo_read_v1('sd-caps',true)->'menu',public.storefront_menu_v4('sd-caps'),'sold-out availability remains in real public menu and counts');

-- 64 invalid-public-menu candidates are conclusive; candidate 65 cannot leak.
select pg_temp.sdtenant('budget-'||lpad(n::text,3,'0')) from generate_series(1,65)n;
update public.branches set timezone='Invalid/Timezone' where restaurant_id in(select pg_temp.sdid('budget-'||lpad(n::text,3,'0')||'-rest') from generate_series(1,65)n);
select is(public.storefront_seo_discovery_v1('sd-budget',1),'{"ok":false,"schema":1,"error":"budget_unavailable"}'::jsonb,'65 cheap candidates with no eligible witness fail closed without partial/cursor');
update public.restaurant_storefront_profiles set is_published=false where restaurant_id=pg_temp.sdid('budget-065-rest');
select is(public.storefront_seo_discovery_v1('sd-budget',1)->>'error','budget_unavailable','64 excluded plus later real candidates cannot masquerade as exhausted');
update public.restaurant_storefront_profiles set is_published=false where restaurant_id in(
 select pg_temp.sdid(x||'-rest')from unnest(array['c','d','caps','empty','missing','off'])x);
select is(public.storefront_seo_discovery_v1('sd-budget',1)->'items','[]'::jsonb,'exactly64 rejected and true end returns conclusive empty');
select is(public.storefront_seo_discovery_v1('sd-budget',1)->>'has_more','false','exactly64 true exhaustion is not a budget error');
update public.restaurant_storefront_profiles set is_published=true where slug in('sd-a','sd-b','sd-c','sd-d');
select is(public.storefront_seo_discovery_v1(null,1)->>'next_after_slug','sd-a','small page succeeds before unrelated later scan budget');
select ok(not(public.storefront_seo_discovery_v1(null,1)::text like '%budget-001%'),'ineligible scan key never exposed');

-- Expression indexes must not break the existing authorized profile writer.
-- These are synthetic fixtures, not owner impersonation or hosted mutations.
insert into auth.users(id,instance_id,email) values(pg_temp.sdid('auth-owner'),'00000000-0000-0000-0000-000000000000','seo-discovery-auth@example.test');
update public.app_users set auth_user_id=pg_temp.sdid('auth-owner') where id=pg_temp.sdid('actor');
insert into public.memberships(id,app_user_id,organization_id,restaurant_id,role)
 values(pg_temp.sdid('member-owner'),pg_temp.sdid('actor'),pg_temp.sdid('a-org'),pg_temp.sdid('a-rest'),'restaurant_owner');
select set_config('request.jwt.claim.sub',pg_temp.sdid('auth-owner')::text,true);
set local role authenticated;
select is(public.set_restaurant_storefront_profile(pg_temp.sdid('legacy-unpublish'),pg_temp.sdid('a-org'),pg_temp.sdid('a-rest'),1,'{"is_published":false}') ->>'ok','true','authorized legacy unpublish works despite private expression helper');
select is(public.set_restaurant_storefront_profile(pg_temp.sdid('legacy-profile'),pg_temp.sdid('a-org'),pg_temp.sdid('a-rest'),2,
 '{"display_name":"Owner edited synthetic menu","opening_hours":{"weekly":[{"dow":0,"open":"09:00","close":"17:00"}],"exceptions":[]}}')->>'ok','true','authorized legacy profile edit still works');
select is(public.set_restaurant_storefront_profile(pg_temp.sdid('legacy-publish'),pg_temp.sdid('a-org'),pg_temp.sdid('a-rest'),3,'{"is_published":true}')->>'ok','true','authorized legacy publication still works with both new indexes');
reset role;
select is(public.storefront_seo_page_v1('sd-a')#>>'{menu,restaurant,display_name}','Owner edited synthetic menu','read reflects existing authorized profile writer');

-- Backend calls are read-only across settings, consent, receipts and history.
create temp table sd_protected_before(relation text primary key,payload jsonb);
do $$declare rel text;v jsonb;begin foreach rel in array array[
 'app.storefront_seo_release_gate_v1','app.restaurant_storefront_seo_consent_v1','app.storefront_seo_consent_requests_v1',
 'public.restaurant_storefront_profiles','public.audit_events','public.web_order_channel_settings','public.web_order_requests','public.web_order_decisions',
 'app.online_order_settings','app.online_order_live_requests','app.pos_order_alert_settings','app.pos_order_alert_registrations','app.pos_order_alert_deliveries',
 'public.kitchen_print_dispatches','public.kitchen_print_dispatch_holds','public.kitchen_print_containment_policies']loop
 execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',rel)into v;
 insert into sd_protected_before values(rel,v);end loop;end;$$;
set local role anon;
select public.storefront_seo_page_v1('sd-a')->>'ok';
select public.storefront_seo_discovery_v1(null,1)->>'ok';
reset role;
create function pg_temp.sdunchanged(rel text) returns boolean language plpgsql as $$declare v jsonb;begin
 execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',rel)into v;
 return v=(select payload from sd_protected_before where relation=rel);end;$$;
select ok(pg_temp.sdunchanged(relation),'read preserves exact protected relation: '||relation) from sd_protected_before;
select is((select count(*) from sd_legacy l join pg_proc p on p.oid=l.oid where pg_get_functiondef(l.oid)=l.def and p.proacl is not distinct from l.proacl
 and p.proowner=l.proowner and p.proconfig is not distinct from l.proconfig),(select count(*) from sd_legacy),'v4 and existing consent definitions/ACL/config unchanged');

-- Narrow shared-guard integration controls. Literal full identities, never
-- derived from the catalog being checked. All harmless faults are local and
-- rolled back; no mock is used for a positive menu or eligibility assertion.
create temp table sd_guard_expected(identity text primary key);
insert into sd_guard_expected values ('storefront_menu(text)'),('storefront_menu_v2(text)'),
 ('storefront_menu_v3(text)'),('storefront_menu_v4(text)'),
 ('storefront_seo_page_v1(text)'),('storefront_seo_discovery_v1(text,integer,integer)');
create function pg_temp.sd_guard_surface(kind text) returns text[] language sql stable as $$
 select coalesce(array_agg(regexp_replace(p.oid::regprocedure::text,'^public.','')
   order by regexp_replace(p.oid::regprocedure::text,'^public.','')),array[]::text[])
 from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind in('f','p')
   and ((kind='anon' and has_function_privilege('anon',p.oid,'EXECUTE')) or (kind='definer' and p.prosecdef));
$$;
select is(pg_temp.sd_guard_surface('anon'),(select array_agg(identity order by identity)from sd_guard_expected),'shared guard exact literal anonymous surface baseline');
select is(pg_temp.sd_guard_surface('definer'),(select array_agg(identity order by identity)from sd_guard_expected),'shared guard exact literal definer surface baseline');

create function public.__seo_guard_unexpected_anon_v1() returns integer language sql as $$select 1;$$;
revoke all on function public.__seo_guard_unexpected_anon_v1()from public,anon,authenticated,service_role;
grant execute on function public.__seo_guard_unexpected_anon_v1()to anon;
select isnt(pg_temp.sd_guard_surface('anon'),(select array_agg(identity order by identity)from sd_guard_expected),'unexpected anon-callable identity violates exact set');
select ok('__seo_guard_unexpected_anon_v1()'=any(pg_temp.sd_guard_surface('anon')),'unexpected anonymous culprit is detected by full identity');
drop function public.__seo_guard_unexpected_anon_v1();

create function public.__seo_guard_unexpected_definer_v1() returns integer language sql security definer set search_path='' as $$select 1;$$;
revoke all on function public.__seo_guard_unexpected_definer_v1()from public,anon,authenticated,service_role;
grant execute on function public.__seo_guard_unexpected_definer_v1()to authenticated;
select isnt(pg_temp.sd_guard_surface('definer'),(select array_agg(identity order by identity)from sd_guard_expected),'unapproved public DEFINER violates exact set even without anon grant');
select is(pg_temp.sd_guard_surface('anon'),(select array_agg(identity order by identity)from sd_guard_expected),'definer-only negative control does not rely on anon detection');
drop function public.__seo_guard_unexpected_definer_v1();

create function public.__seo_guard_public_execute_v1() returns integer language sql as $$select 1;$$;
revoke all on function public.__seo_guard_public_execute_v1()from public,anon,authenticated,service_role;
grant execute on function public.__seo_guard_public_execute_v1()to public,authenticated;
select ok(exists(select 1 from pg_proc p,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a
 where p.oid='public.__seo_guard_public_execute_v1()'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC EXECUTE negative control is detected explicitly');
select isnt(pg_temp.sd_guard_surface('anon'),(select array_agg(identity order by identity)from sd_guard_expected),'PUBLIC inheritance also violates effective anonymous set');
drop function public.__seo_guard_public_execute_v1();

create function public.storefront_seo_page_v1(p_slug text,p_unapproved boolean) returns integer language sql as $$select 1;$$;
revoke all on function public.storefront_seo_page_v1(text,boolean)from public,anon,authenticated,service_role;
grant execute on function public.storefront_seo_page_v1(text,boolean)to anon,authenticated;
select isnt(pg_temp.sd_guard_surface('anon'),(select array_agg(identity order by identity)from sd_guard_expected),'same-name unapproved overload is not accepted');
select ok('storefront_seo_page_v1(text)'=any(pg_temp.sd_guard_surface('anon'))
 and 'storefront_seo_page_v1(text,boolean)'=any(pg_temp.sd_guard_surface('anon')),'overload control compares both full signatures, never a name or prefix');
drop function public.storefront_seo_page_v1(text,boolean);

select ok(not exists(select 1 from unnest(array['anon','authenticated','service_role'])r
 where has_function_privilege(r,'app.storefront_seo_read_v1(text,boolean)','EXECUTE')
 or has_function_privilege(r,'app.storefront_seo_partition_v1(text)','EXECUTE')
 or has_table_privilege(r,'app.storefront_seo_release_gate_v1','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
 or has_any_column_privilege(r,'app.storefront_seo_release_gate_v1','SELECT,INSERT,UPDATE,REFERENCES')),'private helpers and gate remain inaccessible after controls');
select ok(pg_temp.sd_guard_surface('anon')=(select array_agg(identity order by identity)from sd_guard_expected)
 and pg_temp.sd_guard_surface('definer')=(select array_agg(identity order by identity)from sd_guard_expected)
 and not exists(select 1 from pg_proc p,lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a
 where p.pronamespace='public'::regnamespace and p.prokind in('f','p')and a.grantee=0 and a.privilege_type='EXECUTE'),'all negative controls removed; exact surface and no PUBLIC EXECUTE restored');
select * from finish();
rollback;
