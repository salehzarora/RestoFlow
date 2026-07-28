-- ============================================================================
-- PRINT-BRANDING-LOGO-001 — pgTAP: restaurant branding column shape +
-- constraints, the restaurant_logo_scope path parser, the private bucket
-- config, storage.objects policy introspection, and SECURITY DEFINER /
-- search_path / grants hygiene. Fixtures seeded by the BYPASSRLS connection.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(44);

-- a minimal live restaurant for constraint + default checks.
insert into organizations (id, name, slug, default_currency) values
  ('b1000000-0000-0000-0000-000000000001', 'Org PBL', 'pbl-schema', 'USD');
insert into restaurants (id, organization_id, name) values
  ('b1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'Rest PBL');

-- ===== column shape =========================================================
select has_column('public', 'restaurants', 'receipt_logo_path', 'restaurants has receipt_logo_path');
select col_type_is('public', 'restaurants', 'receipt_logo_path', 'text', 'receipt_logo_path is text');
select col_is_null('public', 'restaurants', 'receipt_logo_path', 'receipt_logo_path is nullable');

select has_column('public', 'restaurants', 'receipt_logo_enabled', 'restaurants has receipt_logo_enabled');
select col_type_is('public', 'restaurants', 'receipt_logo_enabled', 'boolean', 'receipt_logo_enabled is boolean');
select col_not_null('public', 'restaurants', 'receipt_logo_enabled', 'receipt_logo_enabled is not null');
select col_default_is('public', 'restaurants', 'receipt_logo_enabled', 'false', 'receipt_logo_enabled defaults to false');

select has_column('public', 'restaurants', 'receipt_logo_version', 'restaurants has receipt_logo_version');
select col_type_is('public', 'restaurants', 'receipt_logo_version', 'integer', 'receipt_logo_version is integer');
select col_not_null('public', 'restaurants', 'receipt_logo_version', 'receipt_logo_version is not null');
select col_default_is('public', 'restaurants', 'receipt_logo_version', '0', 'receipt_logo_version defaults to 0');

-- ===== existing rows are backward compatible ================================
select is(
  (select receipt_logo_path from public.restaurants where id = 'b1000000-0000-0000-0000-000000000002'),
  null, 'a freshly inserted restaurant has a NULL logo path');
select is(
  (select receipt_logo_enabled from public.restaurants where id = 'b1000000-0000-0000-0000-000000000002'),
  false, 'a freshly inserted restaurant has logo DISABLED');
select is(
  (select receipt_logo_version from public.restaurants where id = 'b1000000-0000-0000-0000-000000000002'),
  0, 'a freshly inserted restaurant has version 0');

-- ===== constraints ==========================================================
select throws_ok(
  $$ update public.restaurants set receipt_logo_version = -1 where id = 'b1000000-0000-0000-0000-000000000002' $$,
  '23514', null, 'receipt_logo_version < 0 is rejected (check constraint)');
select throws_ok(
  $$ update public.restaurants set receipt_logo_enabled = true where id = 'b1000000-0000-0000-0000-000000000002' $$,
  '23514', null, 'enabling a logo with a NULL path is rejected (enabled requires path)');
select lives_ok(
  $$ update public.restaurants
       set receipt_logo_path = 'b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/logo/b1000000-0000-0000-0000-0000000000f1.png',
           receipt_logo_enabled = true, receipt_logo_version = 1
     where id = 'b1000000-0000-0000-0000-000000000002' $$,
  'enabling with a valid non-null path + positive version is allowed');

-- ===== app.restaurant_logo_scope (strict parser; malformed => no row) =======
select is(
  (select organization_id from app.restaurant_logo_scope(
     'b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/logo/b1000000-0000-0000-0000-0000000000f1.png')),
  'b1000000-0000-0000-0000-000000000001'::uuid, 'valid key parses the organization_id');
select is(
  (select restaurant_id from app.restaurant_logo_scope(
     'b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/logo/b1000000-0000-0000-0000-0000000000f1.png')),
  'b1000000-0000-0000-0000-000000000002'::uuid, 'valid key parses the restaurant_id');
select is(
  (select count(*)::int from app.restaurant_logo_scope('b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/logo/b1000000-0000-0000-0000-0000000000f1.jpg')),
  1, 'a .jpg extension is accepted');
select is(
  (select count(*)::int from app.restaurant_logo_scope('b1000000-0000-0000-0000-000000000001/logo/b1000000-0000-0000-0000-0000000000f1.png')),
  0, 'too few segments => no row (fail closed)');
select is(
  (select count(*)::int from app.restaurant_logo_scope('b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/branding/b1000000-0000-0000-0000-0000000000f1.png')),
  0, 'wrong literal folder (branding != logo) => no row');
select is(
  (select count(*)::int from app.restaurant_logo_scope('not-a-uuid/b1000000-0000-0000-0000-000000000002/logo/b1000000-0000-0000-0000-0000000000f1.png')),
  0, 'a non-uuid organization => no row');
select is(
  (select count(*)::int from app.restaurant_logo_scope('b1000000-0000-0000-0000-000000000001/not-a-uuid/logo/b1000000-0000-0000-0000-0000000000f1.png')),
  0, 'a non-uuid restaurant => no row');
select is(
  (select count(*)::int from app.restaurant_logo_scope('b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/logo/b1000000-0000-0000-0000-0000000000f1.svg')),
  0, 'a disallowed extension (.svg) => no row');
select is(
  (select count(*)::int from app.restaurant_logo_scope('b1000000-0000-0000-0000-000000000001/b1000000-0000-0000-0000-000000000002/logo/not-a-uuid.png')),
  0, 'a non-uuid image id (filename) => no row');
select is(
  (select count(*)::int from app.restaurant_logo_scope(null)),
  0, 'a NULL name => no row (never raises)');

-- ===== bucket configuration =================================================
select is((select public from storage.buckets where id = 'restaurant-logos'), false,
  'the restaurant-logos bucket is PRIVATE');
select is((select file_size_limit from storage.buckets where id = 'restaurant-logos'), 2097152::bigint,
  'the restaurant-logos bucket size limit is 2 MiB');
select is((select allowed_mime_types from storage.buckets where id = 'restaurant-logos'),
  array['image/png', 'image/jpeg', 'image/webp'],
  'the restaurant-logos bucket allows png/jpeg/webp only');

-- ===== storage.objects policy introspection =================================
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='restaurant_logos_select'),
  'SELECT', 'restaurant_logos_select is a SELECT policy');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='restaurant_logos_insert'),
  'INSERT', 'restaurant_logos_insert is an INSERT policy');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='restaurant_logos_update'),
  'UPDATE', 'restaurant_logos_update is an UPDATE policy');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='restaurant_logos_delete'),
  'DELETE', 'restaurant_logos_delete is a DELETE policy');
select is((select roles::text[] from pg_policies where schemaname='storage' and tablename='objects' and policyname='restaurant_logos_select'),
  array['authenticated'], 'restaurant_logos_select targets authenticated only (no anon)');
select ok(
  (select qual from pg_policies where schemaname='storage' and tablename='objects' and policyname='restaurant_logos_device_select')
    like '%device_can_read_restaurant_logo%',
  'the device SELECT policy wires app.device_can_read_restaurant_logo');

-- ===== function security posture ============================================
select is((select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='app' and p.proname='set_restaurant_receipt_logo'), true,
  'app.set_restaurant_receipt_logo is SECURITY DEFINER');
select ok((select proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='app' and p.proname='set_restaurant_receipt_logo') @> array['search_path=""'],
  'app.set_restaurant_receipt_logo runs with search_path = (empty)');
select is((select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname='set_restaurant_receipt_logo'), false,
  'public.set_restaurant_receipt_logo is SECURITY INVOKER (thin wrapper)');
select is((select prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='app' and p.proname='restaurant_logo_scope'), true,
  'app.restaurant_logo_scope is SECURITY DEFINER');
select ok((select proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='app' and p.proname='device_can_read_restaurant_logo') @> array['search_path=""'],
  'app.device_can_read_restaurant_logo runs with search_path = (empty)');

-- ===== grants ===============================================================
select ok(
  has_function_privilege('authenticated', 'app.set_restaurant_receipt_logo(uuid,uuid,uuid,text,boolean,integer)', 'execute')
  and not has_function_privilege('anon', 'app.set_restaurant_receipt_logo(uuid,uuid,uuid,text,boolean,integer)', 'execute'),
  'authenticated (and NOT anon) may execute app.set_restaurant_receipt_logo');
select ok(
  has_function_privilege('authenticated', 'public.set_restaurant_receipt_logo(uuid,uuid,uuid,text,boolean,integer)', 'execute')
  and not has_function_privilege('anon', 'public.set_restaurant_receipt_logo(uuid,uuid,uuid,text,boolean,integer)', 'execute'),
  'authenticated (and NOT anon) may execute public.set_restaurant_receipt_logo');
select ok(
  not has_function_privilege('public', 'app.set_restaurant_receipt_logo(uuid,uuid,uuid,text,boolean,integer)', 'execute'),
  'PUBLIC has NO execute on app.set_restaurant_receipt_logo (revoked)');

select * from finish();
rollback;
