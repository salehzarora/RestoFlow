-- BIZBOT-STOREFRONT-HOME-CONTENT-001: real independent local SQL sessions.
-- Synthetic committed fixtures permit dblink visibility, matching the existing
-- zz_ concurrency harness. No hosted hostname or credential is accepted here.
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path=extensions,public,pg_catalog;
select no_plan();
insert into organizations(id,name,slug,default_currency) values
  ('0036c001-0000-4000-8000-000000000001','Home concurrency','home-content-concurrency','ILS');
insert into restaurants(id,organization_id,name,timezone) values
  ('0036c001-0000-4000-8000-000000000002','0036c001-0000-4000-8000-000000000001','Home concurrency','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone) values
  ('0036c001-0000-4000-8000-000000000003','0036c001-0000-4000-8000-000000000001','0036c001-0000-4000-8000-000000000002','Home branch','UTC');
insert into app_users(id,email) values('0036c001-0000-4000-8000-000000000004','home-concurrency@example.test');
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) values
  ('0036c001-0000-4000-8000-000000000005','0036c001-0000-4000-8000-000000000004',
    '0036c001-0000-4000-8000-000000000001','0036c001-0000-4000-8000-000000000002','manager');
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,version)
values('0036c001-0000-4000-8000-000000000002','0036c001-0000-4000-8000-000000000001',
  '0036c001-0000-4000-8000-000000000003','home-content-concurrency','Home concurrency',1);
create function pg_temp.hsql(n integer,ver integer,head text) returns text language sql as $$
  select format('select public.set_restaurant_storefront_home_content(%L,%L,%L,%s,%L::jsonb)::text',
    ('0036c001-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
    '0036c001-0000-4000-8000-000000000001','0036c001-0000-4000-8000-000000000002',ver,
    jsonb_build_object('hero_headline',head,'hero_subline',null,'announcement_text',null)); $$;
create function pg_temp.bsql(n integer,ver integer) returns text language sql as $$
  select format('select public.set_restaurant_storefront_profile(%L,%L,%L,%s,%L::jsonb)::text',
    ('0036c001-0000-4000-8000-'||lpad((100+n)::text,12,'0'))::uuid,
    '0036c001-0000-4000-8000-000000000001','0036c001-0000-4000-8000-000000000002',ver,'{"tagline":"Base edit"}'); $$;
create function pg_temp.drain(conn text) returns jsonb language plpgsql as $$
declare v text; r record;
begin
  for r in select * from extensions.dblink_get_result(conn) as t(x text) loop v:=r.x; end loop;
  perform * from extensions.dblink_get_result(conn) as t(x text);
  return v::jsonb;
end; $$;
select dblink_connect('home_a','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres password=postgres');
select dblink_connect('home_b','host=127.0.0.1 port='||current_setting('port')||' dbname='||current_database()||' user=postgres password=postgres');
select dblink_exec('home_a','set role authenticated');
select dblink_exec('home_b','set role authenticated');
select dblink_exec('home_a','set app.current_app_user_id=''0036c001-0000-4000-8000-000000000004''');
select dblink_exec('home_b','set app.current_app_user_id=''0036c001-0000-4000-8000-000000000004''');

-- One winner under shared expected version; the loser waits then conflicts.
select dblink_exec('home_a','begin');
select is((select r::jsonb->>'version' from dblink('home_a',pg_temp.hsql(1,1,'Winner')) as t(r text)),'2','A content save holds transaction at version 2');
select dblink_send_query('home_b',pg_temp.hsql(2,1,'Loser'));
select pg_sleep(0.2);
select is(dblink_is_busy('home_b'),1,'B content save waits on the same restaurant lock');
select dblink_exec('home_a','commit');
select is(pg_temp.drain('home_b')->>'error','version_conflict','B sees authoritative CAS conflict');
select is((select hero_headline from restaurant_storefront_profiles where restaurant_id='0036c001-0000-4000-8000-000000000002'),'Winner','no lost update');

-- A failed transaction releases the lock, version, request and audit together.
select dblink_exec('home_a','begin');
select is((select r::jsonb->>'version' from dblink('home_a',pg_temp.hsql(3,2,'Rolled back')) as t(r text)),'3','A attempted version 3 inside transaction');
select dblink_send_query('home_b',pg_temp.bsql(4,2));
select pg_sleep(0.2);
select is(dblink_is_busy('home_b'),1,'old generic writer waits behind content writer');
select dblink_exec('home_a','rollback');
select is(pg_temp.drain('home_b')->>'version','3','old writer succeeds after content rollback');
select ok(not exists(select 1 from management_request_results where client_request_id='0036c001-0000-4000-8000-000000000103'),'rolled-back request identity not consumed');
select is((select hero_headline from restaurant_storefront_profiles where restaurant_id='0036c001-0000-4000-8000-000000000002'),'Winner','old generic writer preserved content');

-- Opposite ordering: content waits for a base edit, then sees new CAS version.
select dblink_exec('home_a','begin');
select is((select r::jsonb->>'version' from dblink('home_a',pg_temp.bsql(5,3)) as t(r text)),'4','base writer holds new shared version');
select dblink_send_query('home_b',pg_temp.hsql(6,3,'Stale content'));
select pg_sleep(0.2);
select is(dblink_is_busy('home_b'),1,'content writer waits behind generic writer');
select dblink_exec('home_a','commit');
select is(pg_temp.drain('home_b')->>'error','version_conflict','content cannot overwrite committed base edit');

-- Concurrent exact replay has one mutation and one audit, not two version bumps.
select dblink_exec('home_a','begin');
select is((select r::jsonb->>'version' from dblink('home_a',pg_temp.hsql(7,4,'Same request')) as t(r text)),'5','first request holds version 5');
select dblink_send_query('home_b',pg_temp.hsql(7,4,'Same request'));
select pg_sleep(0.2);
select is(dblink_is_busy('home_b'),1,'identical replay waits for original outcome');
select dblink_exec('home_a','commit');
select is(pg_temp.drain('home_b')->>'idempotent_replay','true','same identity replays original result');
select is((select version from restaurant_storefront_profiles where restaurant_id='0036c001-0000-4000-8000-000000000002'),5,'exact replay did not increment version');
select is((select count(*) from audit_events where organization_id='0036c001-0000-4000-8000-000000000001' and action='settings.storefront.updated'),4::bigint,'only four committed mutations audited');

-- Authority revoked while waiting must be checked again BEFORE replay/write.
select dblink_exec('home_a','reset role');
select dblink_exec('home_a','begin');
select * from dblink('home_a',$$select id::text from public.restaurants where id='0036c001-0000-4000-8000-000000000002' for update$$) as t(id text);
select dblink_send_query('home_b',pg_temp.hsql(8,5,'Revoked waiter'));
select pg_sleep(0.2);
select is(dblink_is_busy('home_b'),1,'manager request initially waits behind existing lock');
update memberships set deleted_at=now() where id='0036c001-0000-4000-8000-000000000005';
select dblink_exec('home_a','commit');
select throws_ok($$select * from extensions.dblink_get_result('home_b') as t(r text)$$,'42501',null,'revoked waiting manager is denied before mutation');
select * from dblink_get_result('home_b') as t(r text);
select is((select version from restaurant_storefront_profiles where restaurant_id='0036c001-0000-4000-8000-000000000002'),5,'revocation prevented write');
select ok(not exists(select 1 from management_request_results where client_request_id='0036c001-0000-4000-8000-000000000108'),'revoked request claims no identity');
select dblink_disconnect('home_a');
select dblink_disconnect('home_b');

-- Cleanup only this committed synthetic fixture. Append-only audit remains.
delete from restaurant_storefront_profiles where organization_id='0036c001-0000-4000-8000-000000000001';
delete from management_request_results where actor_app_user_id='0036c001-0000-4000-8000-000000000004';
delete from memberships where organization_id='0036c001-0000-4000-8000-000000000001';
delete from app_users where id='0036c001-0000-4000-8000-000000000004';
delete from app.pos_order_alert_branch_cursors where branch_id='0036c001-0000-4000-8000-000000000003';
delete from app.online_order_settings where branch_id='0036c001-0000-4000-8000-000000000003';
delete from branches where organization_id='0036c001-0000-4000-8000-000000000001';
delete from restaurants where organization_id='0036c001-0000-4000-8000-000000000001';
delete from organizations where id='0036c001-0000-4000-8000-000000000001';
select * from finish();
