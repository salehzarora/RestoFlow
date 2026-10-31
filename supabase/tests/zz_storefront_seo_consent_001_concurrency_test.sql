-- BIZBOT-STOREFRONT-SEO-CONSENT-001. Real independent sessions, disposable
-- local fixture only. No host port, production URL, credential lookup or HTTP.
do $$declare server_address inet:=inet_server_addr();client_address inet:=inet_client_addr();begin
  if not coalesce((
      (session_user in('postgres','supabase_admin') and current_database() like 'seo_consent_%'
        and current_setting('bizbot.seo_consent_ephemeral',true) is not distinct from 'BIZBOT-STOREFRONT-SEO-CONSENT-001')
      or (session_user='postgres' and current_database()='postgres'
        and current_setting('bizbot.featured_ci_ephemeral',true) is not distinct from 'BIZBOT-STOREFRONT-FEATURED-ITEMS-001'))
    and server_address is not null and client_address is not null and inet_server_port()=5432
    and family(server_address)=4 and family(client_address)=4
    and (server_address<<=inet '127.0.0.0/8' or server_address<<=inet '10.0.0.0/8' or server_address<<=inet '172.16.0.0/12' or server_address<<=inet '192.168.0.0/16')
    and (client_address<<=inet '127.0.0.0/8' or client_address<<=inet '10.0.0.0/8' or client_address<<=inet '172.16.0.0/12' or client_address<<=inet '192.168.0.0/16'),false) then
    raise exception 'SEO_CONSENT_DISPOSABLE_LOCAL_DATABASE_REQUIRED';
  end if;
end;$$;
set statement_timeout='30s';
set lock_timeout='5s';
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.srid(label text) returns uuid language sql immutable as $$select md5('seo-consent-race-001-'||label)::uuid;$$;
insert into organizations(id,name,slug,default_currency) values(pg_temp.srid('org'),'SEO race','seo-consent-race','ILS');
insert into restaurants(id,organization_id,name,timezone) select pg_temp.srid('restaurant-'||r),pg_temp.srid('org'),'SEO race '||r,'UTC' from unnest(array['a','b']) r;
insert into auth.users(id,instance_id,email) select pg_temp.srid('auth-'||u),'00000000-0000-0000-0000-000000000000','seo-race-'||u||'@example.test' from unnest(array['a','b','orgowner']) u;
insert into app_users(id,auth_user_id,email) select pg_temp.srid('user-'||u),pg_temp.srid('auth-'||u),'seo-race-'||u||'@example.test' from unnest(array['a','b','orgowner']) u;
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) select pg_temp.srid('member-'||u),pg_temp.srid('user-'||u),pg_temp.srid('org'),
  case when u='orgowner' then null else pg_temp.srid('restaurant-a') end,case when u='orgowner' then 'org_owner' else 'restaurant_owner' end from unnest(array['a','b','orgowner']) u;
create function pg_temp.srsave(request text,revision bigint,consent boolean,restaurant text default 'a') returns text language sql as $$
  select format('select public.set_storefront_seo_consent_v1(%L,%L,%L,%L::bigint,%L::boolean)::text',pg_temp.srid('request-'||request),pg_temp.srid('org'),pg_temp.srid('restaurant-'||restaurant),revision,consent);$$;
create function pg_temp.srcheck(request text,revision bigint,consent boolean,restaurant text default 'a') returns text language sql as $$
  select replace(pg_temp.srsave(request,revision,consent,restaurant),'public.set_storefront_seo_consent_v1','public.reconcile_storefront_seo_consent_v1');$$;
create function pg_temp.srrevision(restaurant text default 'a') returns bigint language sql stable as $$
  select coalesce((select revision from app.restaurant_storefront_seo_consent_v1 where restaurant_id=pg_temp.srid('restaurant-'||restaurant)),0);$$;
create function pg_temp.srdrain(conn text) returns jsonb language plpgsql as $$declare rec record;v text;begin
  for rec in select * from extensions.dblink_get_result(conn) as t(x text) loop v:=rec.x;end loop;
  perform * from extensions.dblink_get_result(conn) as t(x text);return v::jsonb;end;$$;
create temp table sr_backends(name text primary key,pid integer not null);
create function pg_temp.srwait(conn text) returns boolean language plpgsql as $$declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';begin loop
  perform pg_stat_clear_snapshot();
  if exists(select 1 from pg_stat_activity where pid=(select pid from sr_backends where name=conn) and wait_event_type='Lock') then return true;end if;
  if clock_timestamp()>deadline then return false;end if;perform pg_sleep(0.02);end loop;end;$$;
-- Fixed public credentials belong only to this explicitly marked disposable
-- fixture. Server/client addresses were checked before any connection.
select dblink_connect(c,'host='||host(inet_server_addr())||' port='||inet_server_port()||' dbname='||quote_ident(current_database())
  ||' user=postgres password=postgres connect_timeout=3 application_name=seo_consent_race_'||c) from unnest(array['sr_a','sr_b']) c;
insert into sr_backends select c,pid from unnest(array['sr_a','sr_b']) c cross join lateral dblink(c,'select pg_backend_pid()') as x(pid integer);
select dblink_exec(c,'set statement_timeout=''15s''') from unnest(array['sr_a','sr_b']) c;
select dblink_exec(c,'set lock_timeout=''8s''') from unnest(array['sr_a','sr_b']) c;
select dblink_exec(c,'set role authenticated') from unnest(array['sr_a','sr_b']) c;
select dblink_exec('sr_a',format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-a')));
select dblink_exec('sr_b',format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-b')));
create temp table sr_results(label text primary key,r jsonb);
create temp table sr_versions(label text primary key,revision bigint);

-- Two owners both saw absent state revision 0. The restaurant row serializes
-- creation, so one wins and the other receives a recorded CAS refusal.
select dblink_exec('sr_a','begin');
insert into sr_results select 'first',r::jsonb from dblink('sr_a',pg_temp.srsave('first',0,true)) as t(r text);
select is((select r->>'ok' from sr_results where label='first'),'true','first owner creates explicit consent while holding lock');
select dblink_send_query('sr_b',pg_temp.srsave('second',0,false));
select ok(pg_temp.srwait('sr_b'),'independent second owner waits on absent-row provisioning fence');
select dblink_exec('sr_a','commit');
select is(pg_temp.srdrain('sr_b')->>'error','revision_conflict','stale concurrent owner cannot overwrite winner');
select is((select consent_enabled from app.restaurant_storefront_seo_consent_v1 where restaurant_id=pg_temp.srid('restaurant-a')),true,'winning decision preserved');
select is((select count(*) from app.restaurant_storefront_seo_consent_v1 where restaurant_id=pg_temp.srid('restaurant-a')),1::bigint,'exactly one state row after creation race');

-- Exact duplicate is serialized by actor+UUID before hierarchy locks.
select dblink_exec('sr_b',format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-a')));
insert into sr_versions values('duplicate',pg_temp.srrevision());
select dblink_exec('sr_a','begin');
insert into sr_results select 'duplicate',r::jsonb from dblink('sr_a',pg_temp.srsave('duplicate',pg_temp.srrevision(),false)) as t(r text);
select dblink_send_query('sr_b',pg_temp.srsave('duplicate',(select revision from sr_versions where label='duplicate'),false));
select ok(pg_temp.srwait('sr_b'),'same actor+UUID+intent waits on request lane');
select dblink_exec('sr_a','commit');
select is(pg_temp.srdrain('sr_b')->>'idempotent_replay','true','duplicate returns original receipt');
select is((select count(*) from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.srid('request-duplicate')),1::bigint,'one receipt for concurrent duplicates');
select is((select count(*) from audit_events where new_values->>'client_request_id'=pg_temp.srid('request-duplicate')::text),1::bigint,'one audit for concurrent duplicates');

-- A lost response is recovered by a read-only call waiting for COMMIT.
insert into sr_versions values('uncertain',pg_temp.srrevision());
select dblink_exec('sr_a','begin');
insert into sr_results select 'uncertain',r::jsonb from dblink('sr_a',pg_temp.srsave('uncertain',pg_temp.srrevision(),true)) as t(r text);
select dblink_send_query('sr_b',pg_temp.srcheck('uncertain',(select revision from sr_versions where label='uncertain'),true));
select ok(pg_temp.srwait('sr_b'),'read-only reconciliation waits for in-flight request');
select dblink_exec('sr_a','commit');
insert into sr_results values('recovered',pg_temp.srdrain('sr_b'));
select is((select r->>'mutation_state' from sr_results where label='recovered'),'committed','lost-response commit is recovered');
select is((select count(*) from audit_events where new_values->>'client_request_id'=pg_temp.srid('request-uncertain')::text),1::bigint,'reconciliation creates no audit or second mutation');

-- ROLLBACK removes state, receipt and audit together; recovery never writes.
insert into sr_versions values('rollback',pg_temp.srrevision());
select dblink_exec('sr_a','begin');
insert into sr_results select 'rollback',r::jsonb from dblink('sr_a',pg_temp.srsave('rollback',pg_temp.srrevision(),false)) as t(r text);
select dblink_send_query('sr_b',pg_temp.srcheck('rollback',(select revision from sr_versions where label='rollback'),false));
select ok(pg_temp.srwait('sr_b'),'reconciliation waits for rollback');
select dblink_exec('sr_a','rollback');
select is(pg_temp.srdrain('sr_b')->>'mutation_state','not_recorded','rolled-back intent has no receipt');
select is(pg_temp.srrevision(),(select revision from sr_versions where label='rollback'),'rolled-back consent leaves prior revision');
select is((select consent_enabled from app.restaurant_storefront_seo_consent_v1 where restaurant_id=pg_temp.srid('restaurant-a')),true,'rolled-back revocation leaves previous decision');
select ok(not exists(select 1 from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.srid('request-rollback')),'rollback leaves request identity unused');
select is((select count(*) from audit_events where new_values->>'client_request_id'=pg_temp.srid('request-rollback')::text),0::bigint,'rollback leaves no mutation audit');
select is((select r::jsonb->>'ok' from dblink('sr_b',pg_temp.srsave('rollback',pg_temp.srrevision(),false)) as t(r text)),'true','same-identity explicit retry succeeds after rollback');

-- The request lane also serializes a reused UUID across two restaurants.
select dblink_exec(c,format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-orgowner'))) from unnest(array['sr_a','sr_b']) c;
select dblink_exec('sr_a','begin');
insert into sr_results select 'cross-scope',r::jsonb from dblink('sr_a',pg_temp.srsave('cross-scope',pg_temp.srrevision(),true)) as t(r text);
select dblink_send_query('sr_b',pg_temp.srsave('cross-scope',0,true,'b'));
select ok(pg_temp.srwait('sr_b'),'same UUID on sibling restaurant waits before hierarchy lock');
select dblink_exec('sr_a','commit');
select is(pg_temp.srdrain('sr_b')->>'error','request_conflict','cross-restaurant UUID reuse conflicts');
select is(pg_temp.srrevision('b'),0::bigint,'cross-scope replay cannot provision sibling state');

-- This feature never touches the legacy management request lock lane.
select dblink_exec('sr_a','reset role');
select dblink_exec('sr_a','begin');
select dblink_exec('sr_a',format('insert into public.management_request_results(actor_app_user_id,client_request_id,operation,request_fingerprint,result) values(%L,%L,''synthetic-legacy'',''synthetic'',''{"ok":true}'')',pg_temp.srid('user-orgowner'),pg_temp.srid('request-private-lane')));
select is((select r::jsonb->>'ok' from dblink('sr_b',pg_temp.srsave('private-lane',pg_temp.srrevision(),false)) as t(r text)),'true','private receipt lane does not wait on uncommitted legacy UUID');
select dblink_exec('sr_a','commit');

-- A downgrade while waiting must refuse and audit the locked decision too.
select dblink_exec('sr_b',format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-b')));
insert into sr_versions values('downgrade',pg_temp.srrevision());
select dblink_exec('sr_a','begin');
select dblink_exec('sr_a',format('update public.memberships set role=''manager'' where id=%L',pg_temp.srid('member-b')));
select dblink_send_query('sr_b',pg_temp.srsave('downgrade',pg_temp.srrevision(),true));
select ok(pg_temp.srwait('sr_b'),'initially authorized owner waits for concurrent role downgrade');
select dblink_exec('sr_a','commit');
select is(pg_temp.srdrain('sr_b')->>'error','permission_denied','post-wait manager cannot save restaurant consent');
select is((select count(*) from audit_events where actor_app_user_id=pg_temp.srid('user-b') and action='settings.storefront.seo_consent.denied'),1::bigint,'locked permission denial creates exactly one audit event');
select ok(not exists(select 1 from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.srid('request-downgrade')),'downgrade refusal never consumes receipt identity');
select is(pg_temp.srrevision(),(select revision from sr_versions where label='downgrade'),'downgrade refusal leaves consent unchanged');
select dblink_exec('sr_a',format('update public.memberships set role=''restaurant_owner'' where id=%L',pg_temp.srid('member-b')));

-- Authorization must be fresh after waiting for membership revocation.
select dblink_exec('sr_b',format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-b')));
select dblink_exec('sr_a','begin');
select dblink_exec('sr_a',format('update public.memberships set status=''revoked'' where id=%L',pg_temp.srid('member-b')));
select dblink_send_query('sr_b',pg_temp.srsave('revoked',pg_temp.srrevision(),true));
select ok(pg_temp.srwait('sr_b'),'initially authorized request waits on changing membership');
select dblink_exec('sr_a','commit');
select is(pg_temp.srdrain('sr_b')->>'error','not_found','post-wait revoked owner cannot save');
select ok(not exists(select 1 from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.srid('request-revoked')),'revocation refusal never consumes receipt identity');

-- The parent row is rechecked after a concurrent suspension commits.
select dblink_exec('sr_b',format('set request.jwt.claim.sub=%L',pg_temp.srid('auth-a')));
select dblink_exec('sr_a','begin');
select dblink_exec('sr_a',format('update public.restaurants set status=''suspended'' where id=%L',pg_temp.srid('restaurant-a')));
select dblink_send_query('sr_b',pg_temp.srsave('suspended',pg_temp.srrevision(),true));
select ok(pg_temp.srwait('sr_b'),'initially live scope waits for concurrent restaurant suspension');
select dblink_exec('sr_a','commit');
select is(pg_temp.srdrain('sr_b')->>'error','not_found','post-wait suspended restaurant cannot save');
select ok(not exists(select 1 from app.storefront_seo_consent_requests_v1 where client_request_id=pg_temp.srid('request-suspended')),'suspension refusal never records consent');
select is((select count(*) from memberships where id in(pg_temp.srid('member-a'),pg_temp.srid('member-b'),pg_temp.srid('member-orgowner'))),3::bigint,'all membership history is retained');
select dblink_disconnect('sr_a');
select dblink_disconnect('sr_b');
select * from finish();
