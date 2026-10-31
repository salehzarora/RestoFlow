-- BIZBOT-STOREFRONT-SEO-DISCOVERY-001. Independent authenticated TCP sessions.
-- Synthetic fixture only: no HTTP, external endpoint or credential discovery.
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
set statement_timeout='30s';
set lock_timeout='3s';
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path=extensions,public,pg_catalog;
set timezone='UTC';
select no_plan();
create function pg_temp.sdrid(label text) returns uuid language sql immutable as $$select md5('seo-discovery-race-001-'||label)::uuid;$$;
create temp table sdr_gate_before as select * from app.storefront_seo_release_gate_v1;
create temp table sdr_legacy_before as select p.oid,pg_get_functiondef(p.oid)def,p.proacl,p.proowner
 from pg_proc p where p.oid in('public.storefront_menu_v4(text)'::regprocedure,
 'public.get_storefront_seo_consent_v1(uuid,uuid)'::regprocedure,
 'public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)'::regprocedure,
 'public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)'::regprocedure);
create temp table sdr_receipts_before as select to_jsonb(t)row from app.storefront_seo_consent_requests_v1 t;
begin;
insert into public.app_users(id,email) values(pg_temp.sdrid('actor'),'seo-discovery-race@example.test');
insert into public.organizations(id,name,slug,default_currency) values(pg_temp.sdrid('org'),'Synthetic SEO race','sd-race-org','ILS');
insert into public.restaurants(id,organization_id,name,timezone) values(pg_temp.sdrid('rest'),pg_temp.sdrid('org'),'Synthetic SEO race','UTC');
insert into public.branches(id,organization_id,restaurant_id,name,timezone,tax_enabled,tax_mode)
 select pg_temp.sdrid('branch-'||b),pg_temp.sdrid('org'),pg_temp.sdrid('rest'),'Synthetic '||b,'UTC',false,'exclusive' from unnest(array['a','b'])b;
insert into public.menu_categories(id,organization_id,restaurant_id,branch_id,name)
 select pg_temp.sdrid('cat-'||b),pg_temp.sdrid('org'),pg_temp.sdrid('rest'),pg_temp.sdrid('branch-'||b),'Menu branch '||b from unnest(array['a','b'])b;
insert into public.menu_items(id,organization_id,restaurant_id,branch_id,menu_category_id,name,base_price_minor,currency_code)
 select pg_temp.sdrid('item-'||b),pg_temp.sdrid('org'),pg_temp.sdrid('rest'),pg_temp.sdrid('branch-'||b),pg_temp.sdrid('cat-'||b),'Item branch '||b,100,'ILS' from unnest(array['a','b'])b;
insert into public.restaurant_storefront_profiles(organization_id,restaurant_id,storefront_branch_id,slug,display_name,is_published)
 values(pg_temp.sdrid('org'),pg_temp.sdrid('rest'),pg_temp.sdrid('branch-a'),'sd-race','Snapshot A',true);
insert into app.restaurant_storefront_seo_consent_v1(organization_id,restaurant_id,consent_enabled,revision,updated_by_app_user_id)
 values(pg_temp.sdrid('org'),pg_temp.sdrid('rest'),true,1,pg_temp.sdrid('actor'));
update app.storefront_seo_release_gate_v1 set enabled=true,revision=revision+1;
commit;

-- Fixed synthetic credentials only; derive the checked current server/port.
select dblink_connect(c,'host='||host(inet_server_addr())||' port='||inet_server_port()||' dbname='||quote_ident(current_database())
 ||' user=postgres password=postgres connect_timeout=3 application_name=seo_discovery_race_'||c)
 from unnest(array['sdr_writer','sdr_reader','sdr_retained'])c;
select dblink_exec(c,'set statement_timeout=''2s''') from unnest(array['sdr_writer','sdr_reader','sdr_retained'])c;
select dblink_exec(c,'set lock_timeout=''1s''') from unnest(array['sdr_writer','sdr_reader','sdr_retained'])c;
select dblink_exec(c,'set timezone=''UTC''') from unnest(array['sdr_writer','sdr_reader','sdr_retained'])c;
select dblink_exec(c,'set role anon') from unnest(array['sdr_reader','sdr_retained'])c;
create temp table sdr_backends(name text primary key,pid integer not null);
insert into sdr_backends select c,pid from unnest(array['sdr_writer','sdr_reader','sdr_retained'])c
 cross join lateral dblink(c,'select pg_backend_pid()')as x(pid integer);
create function pg_temp.sdrread(conn text default 'sdr_reader',slug text default 'sd-race')returns jsonb language plpgsql as $$declare v text;begin
 select r into v from extensions.dblink(conn,format('select public.storefront_seo_page_v1(%L)::text',slug))as t(r text);return v::jsonb;end;$$;
create function pg_temp.sdrlist(conn text default 'sdr_reader',cursor text default null)returns jsonb language plpgsql as $$declare v text;begin
 select r into v from extensions.dblink(conn,format('select public.storefront_seo_discovery_v1(%L,25)::text',cursor))as t(r text);return v::jsonb;end;$$;
create function pg_temp.sdrdrain(conn text)returns jsonb language plpgsql as $$declare rec record;v text;begin
 for rec in select * from extensions.dblink_get_result(conn)as t(r text)loop v:=rec.r;end loop;
 perform * from extensions.dblink_get_result(conn)as t(r text);return v::jsonb;end;$$;
create function pg_temp.sdrwait_gate()returns boolean language plpgsql as $$declare deadline timestamptz:=clock_timestamp()+interval '0.3 seconds';begin loop
 perform pg_stat_clear_snapshot();
 if exists(select 1 from pg_locks where pid=(select pid from sdr_backends where name='sdr_reader')
  and relation='app.storefront_seo_release_gate_v1'::regclass and not granted)then return true;end if;
 if clock_timestamp()>deadline then return false;end if;perform pg_sleep(0.005);end loop;end;$$;
create temp table sdr_results(label text primary key,r jsonb);
insert into sdr_results values('initial',pg_temp.sdrread());
select is((select r#>>'{seo,eligible}' from sdr_results where label='initial'),'true','actual real-v4 fixture eligible before withdrawal');
select is((select r#>>'{menu,categories,0,name}' from sdr_results where label='initial'),'Menu branch a','initial selected-branch menu is real v4');

-- Ordinary MVCC reads do not require mutation locks or wait on row writers.
select dblink_exec('sdr_writer','begin');
select dblink_exec('sdr_writer',format('update app.restaurant_storefront_seo_consent_v1 set consent_enabled=false,revision=revision+1 where restaurant_id=%L',pg_temp.sdrid('rest')));
select is(pg_temp.sdrread()#>>'{seo,eligible}','true','uncommitted withdrawal may use previous committed snapshot');
select dblink_exec('sdr_writer','commit');
select is(pg_temp.sdrread()#>>'{seo,eligible}','false','first new statement after withdrawal COMMIT denies eligibility');
select ok(not(pg_temp.sdrlist()->'items' @> '[{"path":"/s/sd-race/menu"}]'::jsonb),'new discovery statement excludes committed consent withdrawal');
select dblink_exec('sdr_writer',format('update app.restaurant_storefront_seo_consent_v1 set consent_enabled=true,revision=revision+1 where restaurant_id=%L',pg_temp.sdrid('rest')));
select is(pg_temp.sdrread()#>>'{seo,eligible}','true','new statement reflects explicit re-enable, no cached OFF');

-- Hold only the SEO gate relation. The actual v4 read finishes before the
-- helper waits here. Commit a simultaneous branch/menu+consent change while it
-- waits. The in-flight STABLE statement must remain ONE old snapshot.
select dblink_exec('sdr_writer','begin');
select dblink_exec('sdr_writer','lock table app.storefront_seo_release_gate_v1 in access exclusive mode');
select dblink_send_query('sdr_reader','select public.storefront_seo_page_v1(''sd-race'')::text');
select ok(pg_temp.sdrwait_gate(),'in-flight real read reaches controlled gate lock after statement snapshot acquisition');
select dblink_exec('sdr_writer',format('update app.restaurant_storefront_seo_consent_v1 set consent_enabled=false,revision=revision+1 where restaurant_id=%L',pg_temp.sdrid('rest')));
select dblink_exec('sdr_writer',format('update public.restaurant_storefront_profiles set storefront_branch_id=%L,display_name=''Snapshot B'' where restaurant_id=%L',pg_temp.sdrid('branch-b'),pg_temp.sdrid('rest')));
select dblink_exec('sdr_writer','commit');
insert into sdr_results values('in-flight',pg_temp.sdrdrain('sdr_reader')),('after-commit',pg_temp.sdrread());
select is((select r#>>'{seo,eligible}' from sdr_results where label='in-flight'),'true','in-flight eligibility remains original statement snapshot');
select is((select r#>>'{menu,restaurant,display_name}' from sdr_results where label='in-flight'),'Snapshot A','in-flight menu cannot mix new public profile with old consent');
select is((select r#>>'{menu,categories,0,name}' from sdr_results where label='in-flight'),'Menu branch a','in-flight menu preserves original selected branch');
select is((select r#>>'{seo,eligible}' from sdr_results where label='after-commit'),'false','subsequent statement sees committed consent withdrawal');
select is((select r#>>'{menu,restaurant,display_name}' from sdr_results where label='after-commit'),'Snapshot B','subsequent statement sees committed profile');
select is((select r#>>'{menu,categories,0,name}' from sdr_results where label='after-commit'),'Menu branch b','subsequent statement uses actual new selected branch');
select is((select (r#>>'{seo,valid_until}')::timestamptz-(r#>>'{seo,evaluated_at}')::timestamptz from sdr_results where label='in-flight'),interval '10 seconds','waiting does not renew in-flight freshness timestamp');

-- No retained transaction snapshot may be advertised as freshly evaluated.
select dblink_exec('sdr_retained','begin isolation level repeatable read');
select is(pg_temp.sdrread('sdr_retained'),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'retained REPEATABLE READ page fails closed');
select is(pg_temp.sdrlist('sdr_retained'),'{"ok":false,"schema":1,"error":"unavailable"}'::jsonb,'retained REPEATABLE READ discovery fails closed');
select dblink_exec('sdr_retained','rollback');
select dblink_exec('sdr_retained','begin isolation level serializable');
select is(pg_temp.sdrread('sdr_retained')->>'error','unavailable','SERIALIZABLE page cannot label retained snapshot fresh');
select is(pg_temp.sdrlist('sdr_retained')->>'error','unavailable','SERIALIZABLE discovery cannot label retained snapshot fresh');
select dblink_exec('sdr_retained','rollback');
select dblink_exec('sdr_retained','begin isolation level repeatable read');
select dblink_exec('sdr_retained','reset role');
select is((select r::jsonb from dblink('sdr_retained','select app.storefront_seo_read_v1(''sd-race'')::text')as t(r text)),
 '{"ok":false,"error":"unavailable"}'::jsonb,'private helper also refuses retained snapshot');
select dblink_exec('sdr_retained','rollback');
select dblink_exec('sdr_retained','set role anon');

-- statement_timestamp must advance inside a long READ COMMITTED transaction;
-- transaction_timestamp/now() is intentionally not a fresh authorization clock.
select dblink_exec('sdr_reader','begin isolation level read committed');
insert into sdr_results values('clock-a',pg_temp.sdrread());
select pg_sleep(0.03);
insert into sdr_results values('clock-b',pg_temp.sdrread());
select ok((select (r#>>'{seo,evaluated_at}')::timestamptz from sdr_results where label='clock-b')>
 (select (r#>>'{seo,evaluated_at}')::timestamptz from sdr_results where label='clock-a'),'evaluation clock is current statement, not transaction start');
select dblink_exec('sdr_reader','commit');

select dblink_exec('sdr_writer',format('update app.restaurant_storefront_seo_consent_v1 set consent_enabled=true,revision=revision+1 where restaurant_id=%L',pg_temp.sdrid('rest')));
select dblink_exec('sdr_writer',format('update public.restaurant_storefront_profiles set is_published=false where restaurant_id=%L',pg_temp.sdrid('rest')));
select is(pg_temp.sdrread(),'{"ok":false,"schema":1,"error":"not_found"}'::jsonb,'new statement after unpublish COMMIT cannot expose page');
select ok(not(pg_temp.sdrlist()->'items' @> '[{"path":"/s/sd-race/menu"}]'::jsonb),'new discovery after unpublish excludes path');
select dblink_exec('sdr_writer',format('update public.restaurant_storefront_profiles set is_published=true where restaurant_id=%L',pg_temp.sdrid('rest')));
select dblink_exec('sdr_writer',format('update public.organizations set status=''suspended'' where id=%L',pg_temp.sdrid('org')));
select is(pg_temp.sdrread()->>'error','not_found','committed ancestor suspension withdraws ordinary page too');
select ok(not(pg_temp.sdrlist()->'items' @> '[{"path":"/s/sd-race/menu"}]'::jsonb),'committed suspended ancestry excluded from discovery');
select dblink_exec('sdr_writer',format('update public.organizations set status=''active'' where id=%L',pg_temp.sdrid('org')));
select dblink_exec('sdr_writer',format('update public.restaurant_storefront_profiles set slug=''sd-race-renamed'' where restaurant_id=%L',pg_temp.sdrid('rest')));
select is(pg_temp.sdrread()->>'error','not_found','old key not authorized after committed synthetic rename');
select is(pg_temp.sdrread('sdr_reader','sd-race-renamed')#>>'{seo,eligible}','true','renamed public path checked under current state');
select ok(pg_temp.sdrlist('sdr_reader','sd-race')->'items' @> '[{"path":"/s/sd-race-renamed/menu"}]'::jsonb,'C-keyset reflects new eligible key beyond cursor');
select dblink_exec('sdr_writer','update app.storefront_seo_release_gate_v1 set enabled=false,revision=revision+1');
select is(pg_temp.sdrlist()->'items','[]'::jsonb,'new statement after global release withdrawal returns conclusive empty');
select is(pg_temp.sdrread('sdr_reader','sd-race-renamed')#>>'{seo,eligible}','false','release gate withdrawal denies only indexing');
select is(pg_temp.sdrread('sdr_reader','sd-race-renamed')->>'ok','true','global SEO release withdrawal does not hide valid ordinary menu');

select dblink_disconnect(c) from unnest(array['sdr_writer','sdr_reader','sdr_retained'])c;
select is((select count(*) from sdr_legacy_before b join pg_proc p on p.oid=b.oid where pg_get_functiondef(b.oid)=b.def
 and p.proacl is not distinct from b.proacl and p.proowner=b.proowner),(select count(*) from sdr_legacy_before),'concurrency leaves v4/consent function definitions and ACL unchanged');
select is((select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),'[]'::jsonb)from app.storefront_seo_consent_requests_v1 t),
 (select coalesce(jsonb_agg(row order by row::text),'[]'::jsonb)from sdr_receipts_before),'read races create no consent receipts or replay');
-- Restore only this synthetic fixture's seeded rows and the exact prior gate.
begin;
delete from app.restaurant_storefront_seo_consent_v1 where restaurant_id=pg_temp.sdrid('rest');
delete from public.restaurant_storefront_profiles where restaurant_id=pg_temp.sdrid('rest');
delete from public.menu_items where restaurant_id=pg_temp.sdrid('rest');
delete from public.menu_categories where restaurant_id=pg_temp.sdrid('rest');
delete from public.web_order_channel_settings where restaurant_id=pg_temp.sdrid('rest');
delete from app.pos_order_alert_branch_cursors where branch_id in(pg_temp.sdrid('branch-a'),pg_temp.sdrid('branch-b'));
delete from app.online_order_settings where branch_id in(pg_temp.sdrid('branch-a'),pg_temp.sdrid('branch-b'));
delete from public.branches where restaurant_id=pg_temp.sdrid('rest');
delete from public.restaurants where id=pg_temp.sdrid('rest');
delete from public.organizations where id=pg_temp.sdrid('org');
delete from public.app_users where id=pg_temp.sdrid('actor');
update app.storefront_seo_release_gate_v1 g set policy_version=b.policy_version,enabled=b.enabled,revision=b.revision from sdr_gate_before b where g.singleton=b.singleton;
commit;
select is((select to_jsonb(g)from app.storefront_seo_release_gate_v1 g),(select to_jsonb(b)from sdr_gate_before b),'private gate restored to exact pre-test state');
select * from finish();
