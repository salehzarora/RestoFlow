-- BIZBOT-STOREFRONT-FEATURED-ITEMS-001: real independent CI-local SQL sessions.
-- Same-current-server TCP guard as the existing concurrency suites. Synthetic
-- fixture only; no hosted hostname, external client, credentials or retry.
do $$
declare s inet := inet_server_addr(); c inet := inet_client_addr();
begin
  if current_setting('bizbot.featured_ci_ephemeral',true) is distinct from 'BIZBOT-STOREFRONT-FEATURED-ITEMS-001'
    or current_database() <> 'postgres' or session_user <> 'postgres'
    or s is null or c is null or family(s) <> 4 or family(c) <> 4 or inet_server_port() <> 5432
    or not (s <<= inet '127.0.0.0/8' or s <<= inet '10.0.0.0/8' or s <<= inet '172.16.0.0/12' or s <<= inet '192.168.0.0/16')
    or not (c <<= inet '127.0.0.0/8' or c <<= inet '10.0.0.0/8' or c <<= inet '172.16.0.0/12' or c <<= inet '192.168.0.0/16') then
    raise exception 'FEATURED_CI_EPHEMERAL_DATABASE_REQUIRED';
  end if;
end; $$;
set statement_timeout='30s';
set lock_timeout='5s';
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path=extensions,public,pg_catalog;
select no_plan();
insert into organizations(id,name,slug,default_currency) values
  ('0036f001-0000-4000-8000-000000000001','Featured concurrency','featured-concurrency','ILS');
insert into restaurants(id,organization_id,name,timezone) values
  ('0036f001-0000-4000-8000-000000000002','0036f001-0000-4000-8000-000000000001','Featured concurrency','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone) values
  ('0036f001-0000-4000-8000-000000000003','0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002','Featured branch','UTC');
insert into app_users(id,email) values('0036f001-0000-4000-8000-000000000004','featured-concurrency@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values
  ('0036f001-0000-4000-8000-000000000005','0036f001-0000-4000-8000-000000000004',
    '0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002','manager');
insert into menu_categories(id,organization_id,restaurant_id,name) values
  ('0036f001-0000-4000-8000-000000000006','0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002','Food');
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
select ('0036f001-0000-4000-8000-'||lpad((10+n)::text,12,'0'))::uuid,
  '0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002',
  '0036f001-0000-4000-8000-000000000006','Product '||n,1234,'ILS' from generate_series(1,2) n;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,version)
values('0036f001-0000-4000-8000-000000000002','0036f001-0000-4000-8000-000000000001',
  '0036f001-0000-4000-8000-000000000003','featured-concurrency','Featured concurrency',1);
create function pg_temp.fsql(n integer,ver integer,item integer) returns text language sql as $$
  select format('select public.set_restaurant_storefront_featured_items(%L,%L,%L,%s,%L::jsonb)::text',
    ('0036f001-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
    '0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002',ver,
    jsonb_build_object('featured_item_ids',jsonb_build_array(('0036f001-0000-4000-8000-'||lpad((10+item)::text,12,'0'))::uuid))); $$;
create function pg_temp.bsql(n integer,ver integer) returns text language sql as $$
  select format('select public.set_restaurant_storefront_profile(%L,%L,%L,%s,%L::jsonb)::text',
    ('0036f001-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
    '0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002',ver,'{"tagline":"Base edit"}'); $$;
create function pg_temp.hsql(n integer,ver integer) returns text language sql as $$
  select format('select public.set_restaurant_storefront_home_content(%L,%L,%L,%s,%L::jsonb)::text',
    ('0036f001-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
    '0036f001-0000-4000-8000-000000000001','0036f001-0000-4000-8000-000000000002',ver,
    '{"hero_headline":"Home edit","hero_subline":null,"announcement_text":null}'); $$;
create function pg_temp.drain(conn text) returns jsonb language plpgsql as $$
declare v text; r record;
begin
  for r in select * from extensions.dblink_get_result(conn) as t(x text) loop v:=r.x; end loop;
  perform * from extensions.dblink_get_result(conn) as t(x text);
  return v::jsonb;
end; $$;
create temp table featured_backend(connection_name text primary key,pid integer not null,app_name text not null);
create function pg_temp.wait_for_lock(conn text) returns boolean language plpgsql as $$
declare deadline timestamptz := clock_timestamp()+interval '4 seconds'; target record;
begin
  select * into strict target from featured_backend where connection_name=conn;
  loop
    perform pg_stat_clear_snapshot();
    if exists(select 1 from pg_stat_activity where pid=target.pid and application_name=target.app_name and wait_event_type='Lock') then return true; end if;
    if clock_timestamp() >= deadline then return false; end if;
    perform pg_sleep(0.02);
  end loop;
end; $$;
select dblink_connect('featured_a','host='||host(inet_server_addr())||' port='||inet_server_port()||' dbname='||current_database()||' user=postgres password=postgres connect_timeout=3 application_name=featured_ci_a');
select dblink_connect('featured_b','host='||host(inet_server_addr())||' port='||inet_server_port()||' dbname='||current_database()||' user=postgres password=postgres connect_timeout=3 application_name=featured_ci_b');
insert into featured_backend select 'featured_a',pid,'featured_ci_a' from dblink('featured_a','select pg_backend_pid()') as t(pid integer);
insert into featured_backend select 'featured_b',pid,'featured_ci_b' from dblink('featured_b','select pg_backend_pid()') as t(pid integer);
select dblink_exec('featured_a','set statement_timeout=''15s''');
select dblink_exec('featured_b','set statement_timeout=''15s''');
select dblink_exec('featured_a','set lock_timeout=''8s''');
select dblink_exec('featured_b','set lock_timeout=''8s''');
select dblink_exec('featured_a','set role authenticated');
select dblink_exec('featured_b','set role authenticated');
select dblink_exec('featured_a','set app.current_app_user_id=''0036f001-0000-4000-8000-000000000004''');
select dblink_exec('featured_b','set app.current_app_user_id=''0036f001-0000-4000-8000-000000000004''');

select dblink_exec('featured_a','begin');
select is((select r::jsonb->>'version' from dblink('featured_a',pg_temp.fsql(1,1,1)) as t(r text)),'2','A feature save holds version2');
select dblink_send_query('featured_b',pg_temp.fsql(2,1,2));
select ok(pg_temp.wait_for_lock('featured_b'),'B feature save waits on shared lock');
select dblink_exec('featured_a','commit');
select is(pg_temp.drain('featured_b')->>'error','version_conflict','one winner and authoritative CAS loser');
select is((select featured_item_ids from restaurant_storefront_profiles where restaurant_id='0036f001-0000-4000-8000-000000000002'),array['0036f001-0000-4000-8000-000000000011']::uuid[],'no lost selection update');

select dblink_exec('featured_a','begin');
select is((select r::jsonb->>'version' from dblink('featured_a',pg_temp.fsql(3,2,2)) as t(r text)),'3','A attempted selection inside rollback transaction');
select dblink_send_query('featured_b',pg_temp.bsql(4,2));
select ok(pg_temp.wait_for_lock('featured_b'),'generic writer waits behind featured');
select dblink_exec('featured_a','rollback');
select is(pg_temp.drain('featured_b')->>'version','3','generic succeeds after rollback');
select ok(not exists(select 1 from management_request_results where client_request_id='0036f001-0000-4000-8000-000000000103'),'rollback consumes no request identity');
select is((select featured_item_ids from restaurant_storefront_profiles where restaurant_id='0036f001-0000-4000-8000-000000000002'),array['0036f001-0000-4000-8000-000000000011']::uuid[],'generic writer preserves selection');

select dblink_exec('featured_a','begin');
select is((select r::jsonb->>'version' from dblink('featured_a',pg_temp.bsql(5,3)) as t(r text)),'4','generic holds next shared version');
select dblink_send_query('featured_b',pg_temp.fsql(6,3,2));
select ok(pg_temp.wait_for_lock('featured_b'),'featured waits behind generic');
select dblink_exec('featured_a','commit');
select is(pg_temp.drain('featured_b')->>'error','version_conflict','featured cannot overwrite committed generic edit');

select dblink_exec('featured_a','begin');
select is((select r::jsonb->>'version' from dblink('featured_a',pg_temp.fsql(7,4,2)) as t(r text)),'5','first exact request holds version5');
select dblink_send_query('featured_b',pg_temp.fsql(7,4,2));
select ok(pg_temp.wait_for_lock('featured_b'),'same identity waits for original outcome');
select dblink_exec('featured_a','commit');
select is(pg_temp.drain('featured_b')->>'idempotent_replay','true','same request replays rather than writes');
select is((select version from restaurant_storefront_profiles where restaurant_id='0036f001-0000-4000-8000-000000000002'),5,'exact replay does not increment version');
select is((select count(*) from audit_events where organization_id='0036f001-0000-4000-8000-000000000001' and action='settings.storefront.updated'),4::bigint,'one audit per committed mutation');

select dblink_exec('featured_a','begin');
select is((select r::jsonb->>'version' from dblink('featured_a',pg_temp.hsql(9,5)) as t(r text)),'6','Home3 holds same profile version');
select dblink_send_query('featured_b',pg_temp.fsql(10,5,1));
select ok(pg_temp.wait_for_lock('featured_b'),'featured waits behind Home3 writer');
select dblink_exec('featured_a','commit');
select is(pg_temp.drain('featured_b')->>'error','version_conflict','featured shares Home3 CAS without overwriting copy');
select is((select hero_headline from restaurant_storefront_profiles where restaurant_id='0036f001-0000-4000-8000-000000000002'),'Home edit','Home3 copy retained');

select dblink_exec('featured_a','reset role');
select dblink_exec('featured_a','begin');
select * from dblink('featured_a',$$select id::text from public.restaurants where id='0036f001-0000-4000-8000-000000000002' for update$$) as t(id text);
select dblink_send_query('featured_b',pg_temp.fsql(8,6,1));
select ok(pg_temp.wait_for_lock('featured_b'),'manager initially waits behind lock');
update memberships set deleted_at=now() where id='0036f001-0000-4000-8000-000000000005';
select dblink_exec('featured_a','commit');
select throws_ok($$select * from extensions.dblink_get_result('featured_b') as t(r text)$$,'42501',null,'revoked waiter cannot mutate or replay');
select * from dblink_get_result('featured_b') as t(r text);
select is((select version from restaurant_storefront_profiles where restaurant_id='0036f001-0000-4000-8000-000000000002'),6,'revocation preserves version');
select ok(not exists(select 1 from management_request_results where client_request_id='0036f001-0000-4000-8000-000000000108'),'revoked request claims no identity');
select dblink_disconnect('featured_a');
select dblink_disconnect('featured_b');

-- Only this committed synthetic fixture is removed; append-only audit remains.
delete from restaurant_storefront_profiles where organization_id='0036f001-0000-4000-8000-000000000001';
delete from management_request_results where actor_app_user_id='0036f001-0000-4000-8000-000000000004';
delete from memberships where organization_id='0036f001-0000-4000-8000-000000000001';
delete from app_users where id='0036f001-0000-4000-8000-000000000004';
delete from menu_items where organization_id='0036f001-0000-4000-8000-000000000001';
delete from menu_categories where organization_id='0036f001-0000-4000-8000-000000000001';
delete from app.pos_order_alert_branch_cursors where branch_id='0036f001-0000-4000-8000-000000000003';
delete from app.online_order_settings where branch_id='0036f001-0000-4000-8000-000000000003';
delete from branches where organization_id='0036f001-0000-4000-8000-000000000001';
delete from restaurants where organization_id='0036f001-0000-4000-8000-000000000001';
delete from organizations where id='0036f001-0000-4000-8000-000000000001';
select * from finish();
