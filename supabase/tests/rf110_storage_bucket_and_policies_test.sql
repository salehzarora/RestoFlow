-- RF-110 -- menu image storage: bucket config + storage.objects policy/helper structure.
-- (DECISION D-032; API_CONTRACT 4.24; SECURITY T-014.) Catalog/structural assertions
-- only -- no JWT context needed. Proves: the bucket is private with the right MIME
-- types and ~5 MiB limit; the four per-command policies exist on storage.objects,
-- pinned to the menu-images bucket, targeting `authenticated` ONLY (no anon/public/
-- service-role path); the three path-derived helpers exist as SECURITY DEFINER with
-- search_path=''; and -- the load-bearing D-032 guarantee -- the helper bodies do
-- NOT reference the org-GUC helpers (has_scope / has_role_in_scope / current_org_id).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(23);

-- ===== bucket config (5) =====
select ok(exists(select 1 from storage.buckets where id = 'menu-images'),
  'menu-images bucket exists');
select is((select public from storage.buckets where id = 'menu-images'), false,
  'menu-images bucket is private (public = false)');
select is((select file_size_limit from storage.buckets where id = 'menu-images'), 5242880::bigint,
  'menu-images file_size_limit is ~5 MiB');
select is((select allowed_mime_types from storage.buckets where id = 'menu-images'),
  array['image/png', 'image/jpeg', 'image/webp'],
  'menu-images allowed_mime_types = png / jpeg / webp');
select is((select count(*) from storage.buckets where id = 'menu-images' and public)::int, 0,
  'menu-images is never a public bucket');

-- ===== four per-command policies on storage.objects (5) =====
select is((select count(*) from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and policyname like 'menu_images_%')::int, 4,
  'exactly four menu_images_* policies exist on storage.objects');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_select'),
  'SELECT', 'menu_images_select is a SELECT policy');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_insert'),
  'INSERT', 'menu_images_insert is an INSERT policy');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_update'),
  'UPDATE', 'menu_images_update is an UPDATE policy');
select is((select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_delete'),
  'DELETE', 'menu_images_delete is a DELETE policy');

-- ===== role targeting + bucket pin (3) -- no anon / public / service-role path =====
select is((select count(*) from pg_policies
           where schemaname='storage' and tablename='objects'
             and policyname like 'menu_images_%'
             and roles::text[] = array['authenticated'])::int, 4,
  'all four menu_images policies target authenticated ONLY');
select is((select count(*) from pg_policies
           where schemaname='storage' and tablename='objects'
             and policyname like 'menu_images_%'
             and roles::text[] && array['anon', 'public', 'service_role'])::int, 0,
  'no menu_images policy targets anon / public / service_role');
select is((select count(*) from pg_policies
           where schemaname='storage' and tablename='objects'
             and policyname like 'menu_images_%'
             and (coalesce(qual, '') || coalesce(with_check, '')) like '%menu-images%')::int, 4,
  'every menu_images policy is pinned to bucket_id = menu-images');

-- ===== policies wire to the path-derived helpers (3) =====
select ok((select qual from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_select')
            like '%can_read_menu_image%',
  'SELECT policy uses app.can_read_menu_image');
select ok((select with_check from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_insert')
            like '%can_write_menu_image%',
  'INSERT policy uses app.can_write_menu_image');
select ok((select qual from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_delete')
            like '%can_write_menu_image%',
  'DELETE policy uses app.can_write_menu_image');

-- ===== helpers exist as SECURITY DEFINER with search_path='' (4) =====
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='app'
             and p.proname in ('menu_image_scope', 'can_read_menu_image', 'can_write_menu_image')
             and p.prosecdef)::int, 3,
  'all three helpers are SECURITY DEFINER');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='app'
             and p.proname in ('menu_image_scope', 'can_read_menu_image', 'can_write_menu_image')
             and p.proconfig @> array['search_path=""'])::int, 3,
  'all three helpers run with search_path = (empty)');
-- THE D-032 GUARANTEE: path-derived helpers must NOT use the org-GUC helpers, which
-- are unevaluable in the storage context (auth.uid() is set, the org GUC is not).
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='app'
             and p.proname in ('menu_image_scope', 'can_read_menu_image', 'can_write_menu_image')
             and (p.prosrc ilike '%has_role_in_scope%'
               or p.prosrc ilike '%has_scope%'
               or p.prosrc ilike '%current_org_id%'))::int, 0,
  'D-032: helpers do NOT reference has_scope / has_role_in_scope / current_org_id (path-derived)');
-- ...and the write helper DOES verify the menu_item exists in scope.
select ok((select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname='app' and p.proname = 'can_write_menu_image') ilike '%menu_items%',
  'can_write_menu_image verifies the referenced menu_items row exists');

-- ===== grants: authenticated execute; revoked from public (anon proxy) (3) =====
select ok(has_function_privilege('authenticated', 'app.menu_image_scope(text)', 'execute')
       and has_function_privilege('authenticated', 'app.can_read_menu_image(uuid,uuid,uuid)', 'execute')
       and has_function_privilege('authenticated', 'app.can_write_menu_image(uuid,uuid,uuid,uuid)', 'execute'),
  'authenticated can execute all three helpers');
select ok(not has_function_privilege('anon', 'app.can_read_menu_image(uuid,uuid,uuid)', 'execute'),
  'anon (no grant) cannot execute can_read_menu_image -- revoked from public');
select ok(not has_function_privilege('anon', 'app.can_write_menu_image(uuid,uuid,uuid,uuid)', 'execute'),
  'anon (no grant) cannot execute can_write_menu_image -- revoked from public');

select * from finish();
rollback;
