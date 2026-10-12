-- ============================================================================
-- STOREFRONT-PUBLISH-001 — REAL two-session concurrency for the media RPCs.
-- ============================================================================
-- Every media mutation locks the restaurants row FOR UPDATE first (then the
-- profile, then media rows), exactly like the profile writer. These scenarios
-- run on GENUINELY SEPARATE database sessions via dblink (the repository's
-- accepted zz_ concurrency harness), each as the REAL role authenticated with
-- the identity GUC:
--
--   H1. two sessions finalize the SAME staged row with DIFFERENT request ids:
--       the loser BLOCKS, then sees the row LIVE (already_published) — one
--       publication, one audit.
--   H2. a finalize that re-points the profile (same-source replacement) races
--       a profile save that expected the OLD version: the save BLOCKS, then
--       gets version_conflict carrying the new version — no lost update, the
--       slot points at the new derivative, never at nothing.
--   H3. cancel of a STAGED row races its finalize: the finalize BLOCKS, then
--       answers not_found; the uploaded object is still there (nothing deletes
--       objects) and nothing was published.
--   H4. two sessions stage the SAME bytes with different request ids: ONE row;
--       the loser gets it back as existing.
--   H5. two sessions finalize two DIFFERENT staged rows of the SAME source: the
--       loser BLOCKS, then replaces the winner (replaced_media_id); exactly ONE
--       LIVE row per (source, variant) remains.
--
-- HARNESS NOTES: dblink sessions cannot see uncommitted fixtures, so this file
-- COMMITS its fixtures (fixed 00b2-prefixed hex ids, upsert-tolerant) and
-- deletes them at the tail (append-only audit_events stay, scoped to this
-- file's own org). Local pgTAP harness only; nothing here can run hosted.
-- ============================================================================
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path to extensions, public, pg_catalog;

-- ===== fixtures (COMMITTED; upsert-tolerant for re-runs) =====================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00b200000a00', 'SFP2 Org', 'sfp2-org', 'ILS')
  on conflict (id) do nothing;
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00b200000a10', '00000000-0000-0000-0000-00b200000a00', 'SFP2 Rest', 'Asia/Jerusalem')
  on conflict (id) do nothing;
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00b200000a1a', '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', 'SFP2 Branch', 'Asia/Jerusalem')
  on conflict (id) do nothing;
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00b20000ee02', 'sfp2-manager@example.test')
  on conflict (id) do nothing;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00b20000ab02', '00000000-0000-0000-0000-00b20000ee02', '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', null, 'manager')
  on conflict (id) do nothing;

-- clean any previous run's residue BEFORE the scenarios (profile first: it references media)
set storage.allow_delete_query = 'true';
delete from restaurant_storefront_profiles where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from storefront_media where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from storage.objects where name like '00000000-0000-0000-0000-00b200000a00/%'
   or name like app.storefront_media_prefix('00000000-0000-0000-0000-00b200000a10') || '/%';
delete from management_request_results where actor_app_user_id = '00000000-0000-0000-0000-00b20000ee02';
reset storage.allow_delete_query;

create temp table t_k as select
  '00000000-0000-0000-0000-00b200000a00/00000000-0000-0000-0000-00b200000a10/logo/00000000-0000-0000-0000-00b20000f101.png'::text as logo_src,
  '00000000-0000-0000-0000-00b200000a00/00000000-0000-0000-0000-00b200000a10/global/menu_item/00000000-0000-0000-0000-00b200011a01/00000000-0000-0000-0000-00b20000f102.jpg'::text as menu_src2,
  '00000000-0000-0000-0000-00b200000a00/00000000-0000-0000-0000-00b200000a10/global/menu_item/00000000-0000-0000-0000-00b200011a02/00000000-0000-0000-0000-00b20000f103.jpg'::text as menu_src3,
  app.storefront_media_prefix('00000000-0000-0000-0000-00b200000a10') as pfx,
  clock_timestamp() as started_at;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_src from t_k;
insert into storage.objects (bucket_id, name) select 'menu-images', menu_src2 from t_k;
insert into storage.objects (bucket_id, name) select 'menu-images', menu_src3 from t_k;
-- M0 LIVE logo (the profile uses it); M1 STAGED replacement of the SAME source; M2 / M3 STAGED heroes
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at)
select v.id::uuid, '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', v.bucket, v.src, v.variant,
       (select pfx from t_k) || '/' || repeat(v.h, 64) || '.webp', repeat(v.h, 64), v.w, v.hh, v.b, v.pub
  from (values
    ('00000000-0000-0000-0000-00b20000f000', 'restaurant-logos', (select logo_src from t_k), 'w480', '0', 480, 240, 1000, now() - interval '1 hour'),
    ('00000000-0000-0000-0000-00b20000f001', 'restaurant-logos', (select logo_src from t_k), 'w480', '1', 480, 240, 1001, null::timestamptz),
    ('00000000-0000-0000-0000-00b20000f002', 'menu-images',      (select menu_src2 from t_k), 'w960', '2', 960, 640, 2002, null),
    ('00000000-0000-0000-0000-00b20000f003', 'menu-images',      (select menu_src3 from t_k), 'w960', '3', 960, 640, 3003, null)
  ) v(id, bucket, src, variant, h, w, hh, b, pub);
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', object_key, jsonb_build_object('mimetype', 'image/webp', 'size', bytes)
  from storefront_media where organization_id = '00000000-0000-0000-0000-00b200000a00';
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, logo_media_id, is_published, version)
values ('00000000-0000-0000-0000-00b200000a10', '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a1a', 'sfp2-race', 'SFP2 Race',
        '00000000-0000-0000-0000-00b20000f000', false, 1);

create temp table t_conn as
  select 'host=' || host(inet_server_addr()) || ' port=' || inet_server_port()
      || ' dbname=' || current_database() || ' user=postgres password=postgres' as cs;

create or replace function pg_temp.drain(conn text) returns text
language plpgsql as $$
declare
  v text;
  r record;
begin
  for i in 1..200 loop
    exit when dblink_is_busy(conn) = 0;
    perform pg_sleep(0.05);
  end loop;
  for r in select * from dblink_get_result(conn) as t(x text) loop
    v := r.x;
  end loop;
  begin
    perform * from dblink_get_result(conn) as t(x text);
  exception when others then null;
  end;
  return v;
end;
$$;

create or replace function pg_temp.fin_sql(p_req text, p_media text) returns text language sql as $$
  select format('select public.finalize_storefront_media(%L, %L, %L, %L)::text', p_req,
    '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', p_media);
$$;

select plan(23);

select dblink_connect('sess_a', (select cs from t_conn));
select dblink_connect('sess_b', (select cs from t_conn));
select dblink_exec('sess_a', 'set role authenticated');
select dblink_exec('sess_b', 'set role authenticated');
select dblink_exec('sess_a', 'set app.current_app_user_id = ''00000000-0000-0000-0000-00b20000ee02''');
select dblink_exec('sess_b', 'set app.current_app_user_id = ''00000000-0000-0000-0000-00b20000ee02''');

-- ============================================================================
-- H1 — the SAME staged row finalized by two sessions (different request ids).
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_h1_a as
  select r::jsonb as res from dblink('sess_a', pg_temp.fin_sql('00000000-0000-0000-0000-00b200c00001', '00000000-0000-0000-0000-00b20000f003')) as t(r text);
select is((select (res ->> 'ok') || ':' || (res ->> 'already_published') from t_h1_a), 'true:false',
  'H1a. session A publishes the staged hero inside its OPEN transaction');
select dblink_send_query('sess_b', pg_temp.fin_sql('00000000-0000-0000-0000-00b200c00002', '00000000-0000-0000-0000-00b20000f003'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1, 'H1b. session B BLOCKS on the restaurant lock while A holds it');
select dblink_exec('sess_a', 'commit');
create temp table t_h1_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select (res ->> 'ok') || ':' || (res ->> 'already_published') from t_h1_b), 'true:true',
  'H1c. session B then sees the row LIVE (already_published), it does not publish twice');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b200000a00'
            and action = 'settings.storefront.media.published' and occurred_at >= (select started_at from t_k)
            and new_values ->> 'id' = '00000000-0000-0000-0000-00b20000f003'), 1,
  'H1d. exactly ONE published audit for the raced row');

-- ============================================================================
-- H2 — replacement re-point vs a profile save that expected the OLD version.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_h2_a as
  select r::jsonb as res from dblink('sess_a', pg_temp.fin_sql('00000000-0000-0000-0000-00b200c00003', '00000000-0000-0000-0000-00b20000f001')) as t(r text);
select is((select (res ->> 'replaced_media_id') || ':' || (res ->> 'profile_version') from t_h2_a),
  '00000000-0000-0000-0000-00b20000f000:2', 'H2a. session A replaces the LIVE logo and re-points the profile (version 1 -> 2), transaction OPEN');
select dblink_send_query('sess_b', format('select public.set_restaurant_storefront_profile(%L, %L, %L, 1, %L::jsonb)::text',
  '00000000-0000-0000-0000-00b200c00004', '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', '{"display_name":"Stale Edit"}'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1, 'H2b. the stale profile save BLOCKS behind the re-point');
select dblink_exec('sess_a', 'commit');
create temp table t_h2_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select (res ->> 'error') || ':' || (res ->> 'version') from t_h2_b), 'version_conflict:2',
  'H2c. the stale save gets version_conflict carrying the NEW version (no lost update)');
select is((select logo_media_id::text || ':' || display_name || ':' || version from restaurant_storefront_profiles
            where restaurant_id = '00000000-0000-0000-0000-00b200000a10'),
  '00000000-0000-0000-0000-00b20000f001:SFP2 Race:2', 'H2d. the slot points at the new derivative; the stale edit did not land');
select ok((select unpublished_at is not null from storefront_media where id = '00000000-0000-0000-0000-00b20000f000')
      and (select published_at is not null and unpublished_at is null from storefront_media where id = '00000000-0000-0000-0000-00b20000f001'),
  'H2e. the old logo is RETRACTED and the new one LIVE (one LIVE row per source)');

-- ============================================================================
-- H3 — cancel of a STAGED row races its finalize.
-- ============================================================================
select dblink_exec('sess_a', 'begin');
create temp table t_h3_a as
  select r::jsonb as res from dblink('sess_a', format('select public.cancel_storefront_media(%L, %L, %L, %L)::text',
    '00000000-0000-0000-0000-00b200c00005', '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', '00000000-0000-0000-0000-00b20000f002')) as t(r text);
select is((select (res ->> 'ok') || ':' || (res ->> 'state') from t_h3_a), 'true:cancelled', 'H3a. session A cancels the staged row, transaction OPEN');
select dblink_send_query('sess_b', pg_temp.fin_sql('00000000-0000-0000-0000-00b200c00006', '00000000-0000-0000-0000-00b20000f002'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1, 'H3b. the racing finalize BLOCKS');
select dblink_exec('sess_a', 'commit');
create temp table t_h3_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select res ->> 'error' from t_h3_b), 'not_found', 'H3c. after the cancel commits, the finalize answers not_found (nothing published)');
select is((select count(*)::int from storefront_media where id = '00000000-0000-0000-0000-00b20000f002'), 0, 'H3d. the row is gone');
select ok(exists (select 1 from storage.objects where bucket_id = 'storefront-media' and name = (select pfx from t_k) || '/' || repeat('2', 64) || '.webp'),
  'H3e. the uploaded object is still there (no path deletes objects)');

-- ============================================================================
-- H4 — the SAME bytes staged by two sessions (different request ids).
-- ============================================================================
create or replace function pg_temp.stage_sql(p_req text) returns text language sql as $$
  select format('select public.stage_storefront_media(%L, %L, %L, %L, %L, %L, %L, 960, 640, 5005)::text', p_req,
    '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', 'menu-images', (select menu_src2 from t_k), 'w960', repeat('5', 64));
$$;
select dblink_exec('sess_a', 'begin');
create temp table t_h4_a as select r::jsonb as res from dblink('sess_a', pg_temp.stage_sql('00000000-0000-0000-0000-00b200c00007')) as t(r text);
select is((select (res ->> 'existing') || ':' || (res ->> 'state') from t_h4_a), 'false:staged', 'H4a. session A registers the bytes, transaction OPEN');
select dblink_send_query('sess_b', pg_temp.stage_sql('00000000-0000-0000-0000-00b200c00008'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1, 'H4b. the second stage BLOCKS');
select dblink_exec('sess_a', 'commit');
create temp table t_h4_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select res ->> 'existing' from t_h4_b), 'true', 'H4c. the loser gets the committed row back as existing');
select is((select b.res ->> 'media_id' from t_h4_b b), (select a.res ->> 'media_id' from t_h4_a a), 'H4d. ...the SAME media id');
select is((select count(*)::int from storefront_media where content_hash = repeat('5', 64)), 1, 'H4e. exactly ONE row for the bytes');

-- ============================================================================
-- H5 — two DIFFERENT staged rows of the SAME source finalized concurrently.
-- ============================================================================
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes)
select '00000000-0000-0000-0000-00b20000f006', '00000000-0000-0000-0000-00b200000a00', '00000000-0000-0000-0000-00b200000a10', 'menu-images', menu_src2, 'w960',
       pfx || '/' || repeat('6', 64) || '.webp', repeat('6', 64), 960, 640, 6006 from t_k;
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', object_key, jsonb_build_object('mimetype', 'image/webp', 'size', bytes)
  from storefront_media where content_hash in (repeat('5', 64), repeat('6', 64)) and organization_id = '00000000-0000-0000-0000-00b200000a00';
create temp table t_h5 as select (select id::text from storefront_media where content_hash = repeat('5', 64)) as m5;
select dblink_exec('sess_a', 'begin');
create temp table t_h5_a as
  select r::jsonb as res from dblink('sess_a', pg_temp.fin_sql('00000000-0000-0000-0000-00b200c00009', (select m5 from t_h5))) as t(r text);
select is((select (res ->> 'ok') || ':' || coalesce(res ->> 'replaced_media_id', 'null') from t_h5_a), 'true:null',
  'H5a. session A publishes the first staged row of the source, transaction OPEN');
select dblink_send_query('sess_b', pg_temp.fin_sql('00000000-0000-0000-0000-00b200c0000a', '00000000-0000-0000-0000-00b20000f006'));
select pg_sleep(0.5);
select is(dblink_is_busy('sess_b'), 1, 'H5b. the finalize of the OTHER staged row of the same source BLOCKS');
select dblink_exec('sess_a', 'commit');
create temp table t_h5_b as select pg_temp.drain('sess_b')::jsonb as res;
select is((select (res ->> 'ok') || ':' || (res ->> 'replaced_media_id') from t_h5_b), 'true:' || (select m5 from t_h5),
  'H5c. after A commits, B publishes by REPLACING the row A just published');
select is((select count(*)::int from storefront_media where organization_id = '00000000-0000-0000-0000-00b200000a00'
            and source_key = (select menu_src2 from t_k) and variant = 'w960' and published_at is not null and unpublished_at is null), 1,
  'H5d. exactly ONE LIVE row for the source remains');

select dblink_disconnect('sess_a');
select dblink_disconnect('sess_b');

-- ===== CLEANUP (committed; audit_events stay — append-only by design) ========
set storage.allow_delete_query = 'true';
delete from restaurant_storefront_profiles where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from storefront_media where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from storage.objects where name like '00000000-0000-0000-0000-00b200000a00/%'
   or name like (select pfx from t_k) || '/%';
reset storage.allow_delete_query;
delete from management_request_results where actor_app_user_id = '00000000-0000-0000-0000-00b20000ee02';
delete from memberships where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from app_users where id = '00000000-0000-0000-0000-00b20000ee02';
delete from branches where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from restaurants where organization_id = '00000000-0000-0000-0000-00b200000a00';
delete from organizations where id = '00000000-0000-0000-0000-00b200000a00';

select * from finish();
