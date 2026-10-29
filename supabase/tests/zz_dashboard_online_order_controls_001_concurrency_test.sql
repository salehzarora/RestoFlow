-- Real independent PostgreSQL sessions, explicit disposable fixture only.
-- No hosted URL, credential lookup, HTTP, submission, alert or printer call.
do $$declare server_address inet:=inet_server_addr();client_address inet:=inet_client_addr();begin
  if not coalesce((
    (session_user in('postgres','supabase_admin') and current_database() like 'online_controls_%'
      and current_setting('bizbot.online_controls_ephemeral',true) is not distinct from 'BIZBOT-DASHBOARD-ONLINE-ORDER-CONTROLS-001')
    or (session_user='postgres' and current_database()='postgres'
      and current_setting('bizbot.featured_ci_ephemeral',true) is not distinct from 'BIZBOT-STOREFRONT-FEATURED-ITEMS-001'
      and server_address is not null and client_address is not null and inet_server_port()=5432
      and family(server_address)=4 and family(client_address)=4
      and (server_address<<=inet '127.0.0.0/8' or server_address<<=inet '10.0.0.0/8' or server_address<<=inet '172.16.0.0/12' or server_address<<=inet '192.168.0.0/16')
      and (client_address<<=inet '127.0.0.0/8' or client_address<<=inet '10.0.0.0/8' or client_address<<=inet '172.16.0.0/12' or client_address<<=inet '192.168.0.0/16'))),false) then
    raise exception 'ONLINE_CONTROLS_DISPOSABLE_LOCAL_DATABASE_REQUIRED';
  end if;
end;$$;
set statement_timeout='30s';
set lock_timeout='5s';
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.ocrid(label text) returns uuid language sql immutable as $$select md5('online-controls-race-001-'||label)::uuid;$$;
insert into organizations(id,name,slug,default_currency) values(pg_temp.ocrid('org'),'Online controls race','online-controls-race-001','ILS');
insert into restaurants(id,organization_id,name,timezone) values(pg_temp.ocrid('rest'),pg_temp.ocrid('org'),'Online controls race','UTC');
insert into branches(id,organization_id,restaurant_id,name,timezone) select pg_temp.ocrid('branch-'||b),pg_temp.ocrid('org'),pg_temp.ocrid('rest'),'Online race '||b,'UTC' from unnest(array['a','b']) b;
insert into web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled) select pg_temp.ocrid('org'),pg_temp.ocrid('rest'),pg_temp.ocrid('branch-'||b),true from unnest(array['a','b']) b;
insert into auth.users(id,instance_id,email) select pg_temp.ocrid('auth-'||u),'00000000-0000-0000-0000-000000000000','online-controls-race-'||u||'@example.test' from unnest(array['a','b','owner']) u;
insert into app_users(id,auth_user_id,email) select pg_temp.ocrid('user-'||u),pg_temp.ocrid('auth-'||u),'online-controls-race-'||u||'@example.test' from unnest(array['a','b','owner']) u;
insert into memberships(id,app_user_id,organization_id,restaurant_id,role) select pg_temp.ocrid('member-'||u),pg_temp.ocrid('user-'||u),pg_temp.ocrid('org'),pg_temp.ocrid('rest'),case when u='owner' then 'restaurant_owner' else 'manager' end from unnest(array['a','b','owner']) u;
create function pg_temp.ocrsave(request text,revision bigint,ordering boolean,printing boolean,alerts boolean,branch text default 'a') returns text language sql as $$
  select format('select public.set_online_order_settings_v2(%L,%L,%L,%L,%L::bigint,%L::boolean,%L::boolean,%L::boolean)::text',pg_temp.ocrid('request-'||request),
    pg_temp.ocrid('org'),pg_temp.ocrid('rest'),pg_temp.ocrid('branch-'||branch),revision,ordering,printing,alerts);$$;
create function pg_temp.ocrreconcile(request text,revision bigint,ordering boolean,printing boolean,alerts boolean,branch text default 'a') returns text language sql as $$
  select replace(pg_temp.ocrsave(request,revision,ordering,printing,alerts,branch),'public.set_online_order_settings_v2','public.reconcile_online_order_settings_v2');$$;
create function pg_temp.ocrrevision(branch text default 'a') returns bigint language sql stable as $$select revision from app.online_order_settings where branch_id=pg_temp.ocrid('branch-'||branch);$$;
create function pg_temp.ocrdrain(conn text) returns jsonb language plpgsql as $$declare r record;v text;begin
  for r in select * from extensions.dblink_get_result(conn) as t(x text) loop v:=r.x;end loop;
  perform * from extensions.dblink_get_result(conn) as t(x text);return v::jsonb;end;$$;
create temp table ocr_backends(name text primary key,pid integer not null);
create function pg_temp.ocrwait(conn text) returns boolean language plpgsql as $$declare deadline timestamptz:=clock_timestamp()+interval '4 seconds';begin loop
  perform pg_stat_clear_snapshot();
  if exists(select 1 from pg_stat_activity where pid=(select pid from ocr_backends where name=conn) and wait_event_type='Lock') then return true;end if;
  if clock_timestamp()>deadline then return false;end if;perform pg_sleep(0.02);end loop;end;$$;
-- Local fixture administration uses only its Unix socket. Required CI already
-- uses the public, fixed postgres/postgres ephemeral fixture credential for its
-- dblink suites; the same loopback-only contract is used here. This is never a
-- retrieved password or hosted endpoint. All business calls use authenticated.
select dblink_connect('ocr_a',case when session_user='supabase_admin' then 'host=/var/run/postgresql' else 'host=127.0.0.1 port=5432 password=postgres' end
  ||' dbname='||quote_ident(current_database())||' user=postgres application_name=online_controls_race_a');
select dblink_connect('ocr_b',case when session_user='supabase_admin' then 'host=/var/run/postgresql' else 'host=127.0.0.1 port=5432 password=postgres' end
  ||' dbname='||quote_ident(current_database())||' user=postgres application_name=online_controls_race_b');
insert into ocr_backends select 'ocr_a',pid from dblink('ocr_a','select pg_backend_pid()') as x(pid integer);
insert into ocr_backends select 'ocr_b',pid from dblink('ocr_b','select pg_backend_pid()') as x(pid integer);
select dblink_exec(c,'set statement_timeout=''15s''') from unnest(array['ocr_a','ocr_b']) c;
select dblink_exec(c,'set lock_timeout=''8s''') from unnest(array['ocr_a','ocr_b']) c;
select dblink_exec(c,'set role authenticated') from unnest(array['ocr_a','ocr_b']) c;
select dblink_exec('ocr_a',format('set request.jwt.claim.sub=%L',pg_temp.ocrid('auth-a')));
select dblink_exec('ocr_b',format('set request.jwt.claim.sub=%L',pg_temp.ocrid('auth-b')));
create temp table ocr_results(label text primary key,r jsonb);
create temp table ocr_versions(label text primary key,revision bigint);

insert into ocr_versions values('initial',pg_temp.ocrrevision());
select dblink_exec('ocr_a','begin');
insert into ocr_results select 'first',r::jsonb from dblink('ocr_a',pg_temp.ocrsave('first',pg_temp.ocrrevision(),false,true,true)) as t(r text);
select is((select r->>'ok' from ocr_results where label='first'),'true','first manager saves with revision lock held');
select dblink_send_query('ocr_b',pg_temp.ocrsave('second',(select revision from ocr_versions where label='initial'),true,false,true));
select ok(pg_temp.ocrwait('ocr_b'),'second independent manager waits on containment fence');
select dblink_exec('ocr_a','commit');
select is(pg_temp.ocrdrain('ocr_b')->>'error','revision_conflict','second stale manager loses without overwriting first');
select is((select ordering_enabled from app.online_order_settings where branch_id=pg_temp.ocrid('branch-a')),false,'winning intake setting preserved');
select is((select printing_enabled from app.online_order_settings where branch_id=pg_temp.ocrid('branch-a')),true,'losing print change never applied');

-- Same actor+UUID+intent replay waits for the original COMMIT. Reconciliation
-- also waits and reads the original receipt without submitting another write.
select dblink_exec('ocr_b',format('set request.jwt.claim.sub=%L',pg_temp.ocrid('auth-a')));
insert into ocr_versions values('duplicate',pg_temp.ocrrevision());
select dblink_exec('ocr_a','begin');
insert into ocr_results select 'duplicate',r::jsonb from dblink('ocr_a',pg_temp.ocrsave('duplicate',pg_temp.ocrrevision(),false,true,false)) as t(r text);
select dblink_send_query('ocr_b',pg_temp.ocrsave('duplicate',(select revision from ocr_versions where label='duplicate'),false,true,false));
select ok(pg_temp.ocrwait('ocr_b'),'exact duplicate waits for same actor/request lane');
select dblink_exec('ocr_a','commit');
select is(pg_temp.ocrdrain('ocr_b')->>'idempotent_replay','true','exact duplicate replays one confirmed intent');
select is((select count(*) from app.online_order_settings_requests_v2 where client_request_id=pg_temp.ocrid('request-duplicate')),1::bigint,'one receipt for duplicate calls');

insert into ocr_versions values('uncertain',pg_temp.ocrrevision());
select dblink_exec('ocr_a','begin');
insert into ocr_results select 'uncertain',r::jsonb from dblink('ocr_a',pg_temp.ocrsave('uncertain',pg_temp.ocrrevision(),true,true,false)) as t(r text);
select dblink_send_query('ocr_b',pg_temp.ocrreconcile('uncertain',(select revision from ocr_versions where label='uncertain'),true,true,false));
select ok(pg_temp.ocrwait('ocr_b'),'read-only uncertain-response reconciliation waits for active transaction');
select dblink_exec('ocr_a','commit');
insert into ocr_results values('reconciled',pg_temp.ocrdrain('ocr_b'));
select is((select r->>'mutation_state' from ocr_results where label='reconciled'),'committed','lost-response commit independently reconciles');
select is((select count(*) from audit_events where new_values->>'client_request_id'=pg_temp.ocrid('request-uncertain')::text),1::bigint,'reconciliation produced no second audit/change');

-- A rolled-back intent is not committed, and its same-identity explicit retry
-- can succeed. This is controlled local reproduction, never a blind retry.
insert into ocr_versions values('rollback',pg_temp.ocrrevision());
select dblink_exec('ocr_a','begin');
insert into ocr_results select 'rollback',r::jsonb from dblink('ocr_a',pg_temp.ocrsave('rollback',pg_temp.ocrrevision(),true,false,false)) as t(r text);
select dblink_send_query('ocr_b',pg_temp.ocrreconcile('rollback',(select revision from ocr_versions where label='rollback'),true,false,false));
select ok(pg_temp.ocrwait('ocr_b'),'read-only reconciliation waits for rollback too');
select dblink_exec('ocr_a','rollback');
select is(pg_temp.ocrdrain('ocr_b')->>'mutation_state','not_recorded','rolled-back receipt and state are not committed');
select ok(not exists(select 1 from app.online_order_settings_requests_v2 where client_request_id=pg_temp.ocrid('request-rollback')),'rolled-back request identity is unconsumed');

-- Legacy setter and v2 share the existing containment -> hierarchy lock order.
select dblink_exec('ocr_a','begin');
insert into ocr_versions values('legacy',pg_temp.ocrrevision());
select is((select r::jsonb->>'ok' from dblink('ocr_a',format('select public.set_online_order_settings(%L,%L,%L,true,true,true)::text',pg_temp.ocrid('org'),pg_temp.ocrid('rest'),pg_temp.ocrid('branch-a'))) as t(r text)),'true','legacy writer runs unchanged');
select dblink_send_query('ocr_b',pg_temp.ocrsave('after-legacy',(select revision from ocr_versions where label='legacy'),false,true,true));
select ok(pg_temp.ocrwait('ocr_b'),'v2 waits behind unchanged legacy writer');
select dblink_exec('ocr_a','commit');
select is(pg_temp.ocrdrain('ocr_b')->>'error','revision_conflict','legacy commit is protected from stale v2 overwrite');

-- A real containment writer commits while v2 waits. The post-wait read must
-- observe its revision, even when the three configured values are unchanged.
select dblink_exec('ocr_a','reset role');
select dblink_exec('ocr_a','begin');
select dblink_exec('ocr_a',format('insert into public.kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,mode,reason,operator_reference) values(%L,%L,%L,''blocked'',''Synthetic online-controls race'',''ONLINE-CONTROLS-001-LOCAL'')',pg_temp.ocrid('org'),pg_temp.ocrid('rest'),pg_temp.ocrid('branch-a')));
insert into ocr_versions values('containment',pg_temp.ocrrevision());
select dblink_send_query('ocr_b',pg_temp.ocrsave('containment',(select revision from ocr_versions where label='containment'),true,true,true));
select ok(pg_temp.ocrwait('ocr_b'),'v2 waits for containment writer before hierarchy/settings');
select dblink_exec('ocr_a','commit');
insert into ocr_results values('containment',pg_temp.ocrdrain('ocr_b'));
select is((select r->>'ok' from ocr_results where label='containment'),'true','post-wait v2 succeeds after real containment transition');
select is((select r->>'containment_revision' from ocr_results where label='containment'),(select max(revision)::text from kitchen_print_containment_policies where branch_id=pg_temp.ocrid('branch-a')),'post-wait fresh containment revision retained');
select is((select r->>'no_change' from ocr_results where label='containment'),'false','flag no-op after containment change is a generation transition');

-- Authorization is rechecked after waiting on a membership row.
select dblink_exec('ocr_b',format('set request.jwt.claim.sub=%L',pg_temp.ocrid('auth-b')));
select dblink_exec('ocr_a','begin');
select dblink_exec('ocr_a',format('update public.memberships set deleted_at=clock_timestamp() where id=%L',pg_temp.ocrid('member-b')));
select dblink_send_query('ocr_b',pg_temp.ocrsave('revoked',pg_temp.ocrrevision(),false,true,true));
select ok(pg_temp.ocrwait('ocr_b'),'authorized initial read waits for covering membership change');
select dblink_exec('ocr_a','commit');
select is(pg_temp.ocrdrain('ocr_b')->>'error','not_found','post-lock revoked membership cannot save');
select ok(not exists(select 1 from app.online_order_settings_requests_v2 where client_request_id=pg_temp.ocrid('request-revoked')),'authorization refusal never claims a receipt');

-- A legacy management UUID occupies only the legacy ledger. The new API's
-- private receipt lane cannot wait on that legacy ledger while holding the
-- hierarchy SHARE lock (the prior reviewed deadlock pattern).
select dblink_exec('ocr_b',format('set request.jwt.claim.sub=%L',pg_temp.ocrid('auth-owner')));
select dblink_exec('ocr_a','begin');
select dblink_exec('ocr_a',format('insert into public.management_request_results(actor_app_user_id,client_request_id,operation,request_fingerprint,result) values(%L,%L,''synthetic-legacy-operation'',''synthetic'',''{"ok":true}'')',pg_temp.ocrid('user-owner'),pg_temp.ocrid('request-private-lane')));
select is((select r::jsonb->>'ok' from dblink('ocr_b',pg_temp.ocrsave('private-lane',pg_temp.ocrrevision(),true,true,false)) as t(r text)),'true','private receipt does not wait on uncommitted same-UUID legacy ledger');
select dblink_exec('ocr_a','commit');
select is((select count(*) from app.online_order_settings_requests_v2 where client_request_id=pg_temp.ocrid('request-private-lane')),1::bigint,'feature receipt remains scoped in its own ledger');
select dblink_disconnect('ocr_a');
select dblink_disconnect('ocr_b');
select * from finish();
