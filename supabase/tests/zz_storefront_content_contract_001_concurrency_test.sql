-- Real independent sessions on the explicitly opted-in disposable CI fixture.
-- No host input, production endpoint, credential lookup or automatic retry.
do $$
declare s inet:=inet_server_addr();c inet:=inet_client_addr();
begin
 -- The existing required CI already marks its disposable PostgreSQL fixture
 -- with the exact Featured flag. Accept that reviewed fixture proof as well
 -- as this task's dedicated local marker, without changing reserved CI code.
 if (current_setting('bizbot.content_ci_ephemeral',true) is distinct from 'BIZBOT-STOREFRONT-CONTENT-CONTRACT-001'
  and current_setting('bizbot.featured_ci_ephemeral',true) is distinct from 'BIZBOT-STOREFRONT-FEATURED-ITEMS-001')
  or current_database()<>'postgres' or session_user<>'postgres' or s is null or c is null
  or family(s)<>4 or family(c)<>4 or inet_server_port()<>5432
  or not(s<<=inet '127.0.0.0/8' or s<<=inet '10.0.0.0/8' or s<<=inet '172.16.0.0/12' or s<<=inet '192.168.0.0/16')
  or not(c<<=inet '127.0.0.0/8' or c<<=inet '10.0.0.0/8' or c<<=inet '172.16.0.0/12' or c<<=inet '192.168.0.0/16') then raise exception 'CONTENT_CI_EPHEMERAL_DATABASE_REQUIRED';end if;
end;$$;
set statement_timeout='30s';
set lock_timeout='5s';
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.ccid(n integer) returns uuid language sql immutable as $$select ('0036cc01-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid;$$;
insert into organizations(id,name,slug,default_currency) values(pg_temp.ccid(1),'Content concurrent','content-concurrent','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.ccid(2),pg_temp.ccid(1),'Content concurrent','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone) values(pg_temp.ccid(3),pg_temp.ccid(1),pg_temp.ccid(2),'Content concurrent','UTC');
insert into app_users(id,email) values(pg_temp.ccid(4),'content-concurrent@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values(pg_temp.ccid(5),pg_temp.ccid(4),pg_temp.ccid(1),pg_temp.ccid(2),'manager');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,version) values(pg_temp.ccid(2),pg_temp.ccid(1),pg_temp.ccid(3),'content-concurrent','Content concurrent',1);
create function pg_temp.csql(n integer,ver integer,headline text default 'Complete content') returns text language sql as $$
 select format('select public.set_restaurant_storefront_content_v1(%L,%L,%L,%s,%L,%L::jsonb)::text',pg_temp.ccid(100+n),pg_temp.ccid(1),pg_temp.ccid(2),ver,pg_temp.ccid(3),
 jsonb_build_object('hero_headline',headline,'hero_subline',null,'announcement_text',null,'hero',jsonb_build_object('mode','editorial','item_id',null,'format',null,'eyebrow',null,'stamp',null,'footnote',null),'announcement_segments',null,'promo',null,'story',null,'category_presentation','[]'::jsonb,'item_presentation','[]'::jsonb));$$;
create function pg_temp.hsql(n integer,ver integer) returns text language sql as $$select format('select public.set_restaurant_storefront_home_content(%L,%L,%L,%s,%L::jsonb)::text',pg_temp.ccid(100+n),pg_temp.ccid(1),pg_temp.ccid(2),ver,'{"hero_headline":"Old Home editor","hero_subline":null,"announcement_text":null}');$$;
create function pg_temp.drain(conn text) returns jsonb language plpgsql as $$declare r record;v text;begin for r in select * from extensions.dblink_get_result(conn) as t(x text) loop v:=r.x;end loop;perform * from extensions.dblink_get_result(conn) as t(x text);return v::jsonb;end;$$;
create temp table content_backends(name text primary key,pid integer not null);
create function pg_temp.wait_lock(conn text) returns boolean language plpgsql as $$declare deadline timestamptz:=clock_timestamp()+interval '4s';begin loop perform pg_stat_clear_snapshot();if exists(select 1 from pg_stat_activity where pid=(select pid from content_backends where name=conn) and wait_event_type='Lock') then return true;end if;if clock_timestamp()>deadline then return false;end if;perform pg_sleep(0.02);end loop;end;$$;
select dblink_connect('content_a','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres connect_timeout=3 application_name=content_ci_a');
select dblink_connect('content_b','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres connect_timeout=3 application_name=content_ci_b');
insert into content_backends select 'content_a',pid from dblink('content_a','select pg_backend_pid()') as x(pid integer);
insert into content_backends select 'content_b',pid from dblink('content_b','select pg_backend_pid()') as x(pid integer);
select dblink_exec(c,'set statement_timeout=''15s''') from unnest(array['content_a','content_b']) c;
select dblink_exec(c,'set lock_timeout=''8s''') from unnest(array['content_a','content_b']) c;
select dblink_exec(c,'set role authenticated') from unnest(array['content_a','content_b']) c;
select dblink_exec(c,'set app.current_app_user_id=''0036cc01-0000-4000-8000-000000000004''') from unnest(array['content_a','content_b']) c;

select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.csql(1,1)) as t(r text)),'2','new content holds shared version');
select dblink_send_query('content_b',pg_temp.csql(2,1,'Losing content'));
select ok(pg_temp.wait_lock('content_b'),'second content waits on same lock');
select dblink_exec('content_a','commit');
select is(pg_temp.drain('content_b')->>'error','version_conflict','one winning content save');
select is((select hero_headline from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2)),'Complete content','losing content did not overwrite');

select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.csql(3,2,'Rollback')) as t(r text)),'3','uncommitted content holds next version');
select dblink_send_query('content_b',pg_temp.hsql(4,2));
select ok(pg_temp.wait_lock('content_b'),'old Home writer waits behind new content');
select dblink_exec('content_a','rollback');
select is(pg_temp.drain('content_b')->>'version','3','old writer succeeds after whole content rollback');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.ccid(103)),'rolled-back identity remains unconsumed');

select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.hsql(5,3)) as t(r text)),'4','old Home owns next revision');
select dblink_send_query('content_b',pg_temp.csql(6,3));
select ok(pg_temp.wait_lock('content_b'),'content waits behind old writer');
select dblink_exec('content_a','commit');
select is(pg_temp.drain('content_b')->>'error','version_conflict','new writer cannot lose old Home update');

select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.csql(7,4)) as t(r text)),'5','first duplicate request writes once');
select dblink_send_query('content_b',pg_temp.csql(7,4));
select ok(pg_temp.wait_lock('content_b'),'exact duplicate waits for original');
select dblink_exec('content_a','commit');
select is(pg_temp.drain('content_b')->>'idempotent_replay','true','duplicate is stored replay');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2)),5,'duplicate does not increment twice');

-- Lock timeout is an exception with no invented successful/failed outcome.
-- The synthetic lock holder uses the fixture administrator only to hold a row
-- lock; the waiting mutation retains the real authenticated RPC path.
select dblink_exec('content_a','reset role');
select dblink_exec('content_a','begin');
select * from dblink('content_a',$$select id::text from public.restaurants where id='0036cc01-0000-4000-8000-000000000002' for update$$) as x(id text);
select dblink_exec('content_b','set lock_timeout=''80ms''');
select throws_ok(format('select * from extensions.dblink(%L,%L) as t(r text)','content_b',pg_temp.csql(8,5)),'55P03',null,'lock timeout remains explicit');
select dblink_exec('content_a','rollback');
select dblink_exec('content_a','set role authenticated');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.ccid(108)),'timed-out request claims no identity');
select dblink_exec('content_b','set lock_timeout=''8s''');

-- A committed result whose acknowledgement is discarded is reconciled using
-- BOTH history identity and state. No second mutation/request is submitted.
select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.csql(9,5,'Reconciled commit')) as t(r text)),'6','controlled commit candidate');
select dblink_exec('content_a','commit');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2)),6,'independent state read resolves committed outcome');
select is((select count(*) from management_request_results where client_request_id=pg_temp.ccid(109)),1::bigint,'independent identity read resolves committed outcome');

-- Media and content share restaurant/profile locks: a valid replacement cannot
-- leave content pointed to the just-retracted object or increment twice.
insert into storage.objects(bucket_id,name) values('restaurant-logos',pg_temp.ccid(1)::text||'/'||pg_temp.ccid(2)::text||'/logo/'||pg_temp.ccid(200)::text||'.png');
insert into public.storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,published_at)
select pg_temp.ccid(200+n),pg_temp.ccid(1),pg_temp.ccid(2),'restaurant-logos',pg_temp.ccid(1)::text||'/'||pg_temp.ccid(2)::text||'/logo/'||pg_temp.ccid(200)::text||'.png','w960',app.storefront_media_prefix(pg_temp.ccid(2))||'/'||repeat(ch,64)||'.webp',repeat(ch,64),960,640,1000,case when n=1 then now() end from (values(1,'c'),(2,'d')) x(n,ch);
insert into storage.objects(bucket_id,name,metadata) select 'storefront-media',object_key,'{"mimetype":"image/webp","size":1000}'::jsonb from storefront_media where id in(pg_temp.ccid(201),pg_temp.ccid(202));
create function pg_temp.msql(n integer,ver integer) returns text language sql as $$select format('select public.set_restaurant_storefront_content_v1(%L,%L,%L,%s,%L,%L::jsonb)::text',pg_temp.ccid(100+n),pg_temp.ccid(1),pg_temp.ccid(2),ver,pg_temp.ccid(3),jsonb_build_object('hero_headline','Media race','hero_subline',null,'announcement_text',null,'hero',jsonb_build_object('mode','editorial','item_id',null,'format',null,'eyebrow',null,'stamp',null,'footnote',null),'announcement_segments',null,'promo',null,'story',jsonb_build_object('kicker','Story','title','Race','body','Synthetic','editorial_media_id',pg_temp.ccid(201),'facts','[]'::jsonb),'category_presentation','[]'::jsonb,'item_presentation','[]'::jsonb));$$;
select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.msql(11,6)) as t(r text)),'7','content reference holds next shared revision');
select dblink_send_query('content_b',format('select public.finalize_storefront_media(%L,%L,%L,%L)::text',pg_temp.ccid(112),pg_temp.ccid(1),pg_temp.ccid(2),pg_temp.ccid(202)));
select ok(pg_temp.wait_lock('content_b'),'media publisher waits behind content write');
select dblink_exec('content_a','commit');
select is(pg_temp.drain('content_b')->>'profile_version','8','media replacement increments shared version once');
select is((select story_media_id from app.storefront_content_profiles where restaurant_id=pg_temp.ccid(2) and storefront_branch_id=pg_temp.ccid(3)),pg_temp.ccid(202),'waited replacement repoints new committed content reference');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2)),8,'no duplicate media/content version increment');

-- Terminate ONLY the exact synthetic backend registered by this suite. A lost
-- session before COMMIT rolls the transaction/claim back; never reconnect to
-- resubmit that request identity automatically.
create function pg_temp.wait_backend_gone(conn text) returns boolean language plpgsql as $$declare deadline timestamptz:=clock_timestamp()+interval '4s';begin loop perform pg_stat_clear_snapshot();if not exists(select 1 from pg_stat_activity where pid=(select pid from content_backends where name=conn)) then return true;end if;if clock_timestamp()>deadline then return false;end if;perform pg_sleep(0.02);end loop;end;$$;
select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.csql(13,8,'Interrupted before commit')) as t(r text)),'9','interrupted session held uncommitted mutation');
select ok((select pg_terminate_backend(a.pid) from pg_stat_activity a join content_backends b on b.pid=a.pid where b.name='content_a' and a.application_name='content_ci_a' and a.datname=current_database() and a.usename='postgres'),'only registered synthetic backend terminated');
select ok(pg_temp.wait_backend_gone('content_a'),'interrupted backend is gone before reconciliation');
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2)),8,'interrupted uncommitted content rolled back');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.ccid(113)),'interrupted transaction leaves no claim');
select dblink_disconnect('content_a');
select dblink_connect('content_a','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres connect_timeout=3 application_name=content_ci_a');
update content_backends set pid=(select pid from dblink('content_a','select pg_backend_pid()') as x(pid integer)) where name='content_a';
select dblink_exec('content_a','set statement_timeout=''15s''');
select dblink_exec('content_a','set lock_timeout=''8s''');
select dblink_exec('content_a','set role authenticated');
select dblink_exec('content_a','set app.current_app_user_id=''0036cc01-0000-4000-8000-000000000004''');

-- Send COMMIT and deliberately discard its response. Either outcome is
-- permitted, but it MUST reconcile atomically and no write is retried.
select dblink_exec('content_a','begin');
select is((select r::jsonb->>'version' from dblink('content_a',pg_temp.csql(14,8,'Uncertain commit')) as t(r text)),'9','uncertain commit candidate completed mutation');
select is(dblink_send_query('content_a','commit'),1,'COMMIT was sent asynchronously');
select dblink_disconnect('content_a');
select ok(pg_temp.wait_backend_gone('content_a'),'discarded-ack backend closed before independent read');
select ok((select (p.version=8 and not exists(select 1 from management_request_results where client_request_id=pg_temp.ccid(114))) or (p.version=9 and exists(select 1 from management_request_results where client_request_id=pg_temp.ccid(114))) from restaurant_storefront_profiles p where p.restaurant_id=pg_temp.ccid(2)),'ambiguous COMMIT reconciles coherent state and identity; no retry');
create temp table reconciled_content_version as select version from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2);
select dblink_connect('content_a','host='||host(inet_server_addr())||' port=5432 dbname=postgres user=postgres password=postgres connect_timeout=3 application_name=content_ci_a');
update content_backends set pid=(select pid from dblink('content_a','select pg_backend_pid()') as x(pid integer)) where name='content_a';

-- Waiting actor revocation must be refreshed after lock acquisition, before
-- any new write OR stored replay disclosure.
select dblink_exec('content_a','reset role');
select dblink_exec('content_a','begin');
select * from dblink('content_a',$$select id::text from public.restaurants where id='0036cc01-0000-4000-8000-000000000002' for update$$) as x(id text);
select dblink_send_query('content_b',pg_temp.csql(10,(select version from reconciled_content_version)));
select ok(pg_temp.wait_lock('content_b'),'authorized actor initially waits');
update memberships set deleted_at=now() where id=pg_temp.ccid(5);
select dblink_exec('content_a','commit');
select throws_ok($$select * from extensions.dblink_get_result('content_b') as t(r text)$$,'42501',null,'revoked waiter denied after lock wait');
select * from dblink_get_result('content_b') as t(r text);
select is((select version from restaurant_storefront_profiles where restaurant_id=pg_temp.ccid(2)),(select version from reconciled_content_version),'revoked waiter preserved version');
select ok(not exists(select 1 from management_request_results where client_request_id=pg_temp.ccid(110)),'revoked actor claims no identity');
select dblink_disconnect('content_a');
select dblink_disconnect('content_b');

-- No cleanup of append-only audit or operational evidence. This entire
-- namespaced synthetic fixture is disposed with the reviewed container.
select * from finish();
