-- ============================================================================
-- STOREFRONT-PUBLISH-001 — pgTAP (T-018): the storefront media publication
-- write path (stage / finalize / cancel / retract / list).
--
-- Matrix:
--   A. contract introspection: 5 public INVOKER wrappers over app DEFINER bodies,
--      search_path pinned, EXECUTE authenticated-only on BOTH layers, anon
--      refused as the REAL role at the GRANT layer (message pinned, so a body
--      refusal cannot pass for it), the anon allowlist and the public DEFINER set
--      still exactly {storefront_menu(text)}, the LIVE-only live-source index.
--   B. stage: exact enumerations (prototype-style names, case variants),
--      item-image refusal, content address, source proof (missing / foreign
--      scope / wrong bucket), authority (rank 1 audited, rank 0 / cross-tenant
--      42501, anonymous 42501), idempotency (replay, key reuse), existing bytes.
--      Every refused stage uses its OWN request id, so a mutant that stops one
--      refusal fails that refusal's named assertion.
--   C. STAGED is absent from the public contract (profile writer refuses it,
--      storefront_menu never serves it).
--   D. finalize: object check (missing / wrong type / wrong size; typed failures
--      NOT claimed), publish, replay, already-published, foreign media.
--   E. same-source replacement: atomic profile re-point (no blank slot), old row
--      retracted, audit reason media_replaced; RETRACTED -> LIVE re-publish.
--   F. retract / cancel: media_in_use, public reference removed, idempotent,
--      STAGED vs RETRACTED rules, no object ever deleted.
--   G. list: manager view, states, in_use, prefix; uniform not_found.
--   H. item images stay out; unpublish -> not_found; audit trail.
--   I. replacement matrix, typed failures not claimed, timestamp edge.
--   J. tenant binding + authority of cancel / retract / finalize (org B and
--      sibling-restaurant media ids -> not_found with the foreign rows untouched
--      and no audit row carrying them; covering cashier -> audited typed
--      permission_denied; sibling manager / foreign owner -> 42501; foreign
--      restaurant named by an org owner / org-wide cashier -> 42501, no audit),
--      cancel of a LIVE row, the finalize object check on a REPLAY and on an
--      already-LIVE row (object deleted / wrong size / restored), and the
--      retract replay re-read (RETRACTED -> LIVE since, or row gone ->
--      stale_request).
--
-- Fixtures inserted as the BYPASSRLS harness role; callers run as the REAL role
-- authenticated + the identity GUC (no JWT principal in pgTAP), anon as the real
-- role anon. Session pinned to UTC. Everything is synthetic and rolls back.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(163);

-- ===== fixtures ==============================================================
insert into organizations (id, name, slug, default_currency, status) values
  ('00000000-0000-0000-0000-00b100000a00', 'SFP Org A', 'sfp1-org-a', 'ILS', 'active'),
  ('00000000-0000-0000-0000-00b100000b00', 'SFP Org B', 'sfp1-org-b', 'ILS', 'active');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b100000a00', 'SFP Rest A1', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00b100000a20', '00000000-0000-0000-0000-00b100000a00', 'SFP Rest A2', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00b100000b10', '00000000-0000-0000-0000-00b100000b00', 'SFP Rest B1', 'Asia/Jerusalem');
insert into branches (id, organization_id, restaurant_id, name, timezone, tax_enabled, tax_rate_bp, tax_mode) values
  ('00000000-0000-0000-0000-00b100000a1a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'A1a', 'Asia/Jerusalem', false, 0, 'exclusive'),
  ('00000000-0000-0000-0000-00b100000a2a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a20', 'A2a', 'Asia/Jerusalem', false, 0, 'exclusive'),
  ('00000000-0000-0000-0000-00b100000b1a', '00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000b10', 'B1a', 'Asia/Jerusalem', false, 0, 'exclusive');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00b10000ee01', 'sfp1-owner-a@example.test'),
  ('00000000-0000-0000-0000-00b10000ee02', 'sfp1-manager-a1@example.test'),
  ('00000000-0000-0000-0000-00b10000ee03', 'sfp1-cashier-a1@example.test'),
  ('00000000-0000-0000-0000-00b10000ee04', 'sfp1-manager-a2@example.test'),
  ('00000000-0000-0000-0000-00b10000ee05', 'sfp1-cashier-orgwide@example.test'),
  ('00000000-0000-0000-0000-00b10000ee0b', 'sfp1-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00b10000ab01', '00000000-0000-0000-0000-00b10000ee01', '00000000-0000-0000-0000-00b100000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00b10000ab02', '00000000-0000-0000-0000-00b10000ee02', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, 'manager'),
  ('00000000-0000-0000-0000-00b10000ab03', '00000000-0000-0000-0000-00b10000ee03', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, 'cashier'),
  ('00000000-0000-0000-0000-00b10000ab04', '00000000-0000-0000-0000-00b10000ee04', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a20', null, 'manager'),
  ('00000000-0000-0000-0000-00b10000ab05', '00000000-0000-0000-0000-00b10000ee05', '00000000-0000-0000-0000-00b100000a00', null, null, 'cashier'),
  ('00000000-0000-0000-0000-00b10000ab0b', '00000000-0000-0000-0000-00b10000ee0b', '00000000-0000-0000-0000-00b100000b00', null, null, 'org_owner');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('00000000-0000-0000-0000-00b10000c1a1', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, 'SFP Cat', 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active, image_path) values
  ('00000000-0000-0000-0000-00b100011a01', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', null, '00000000-0000-0000-0000-00b10000c1a1', 'SFP Item', 1500, 'ILS', 0, true,
   '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/global/menu_item/00000000-0000-0000-0000-00b100011a01/00000000-0000-0000-0000-00b10000f102.jpg');

-- the PRIVATE originals (object rows only; the harness role bypasses the private buckets' RLS)
create temp table _k as select
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/logo/00000000-0000-0000-0000-00b10000f101.png'::text as logo_a1,
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/global/menu_item/00000000-0000-0000-0000-00b100011a01/00000000-0000-0000-0000-00b10000f102.jpg'::text as menu_a1,
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a20/logo/00000000-0000-0000-0000-00b10000f103.png'::text as logo_a2,
  '00000000-0000-0000-0000-00b100000b00/00000000-0000-0000-0000-00b100000b10/logo/00000000-0000-0000-0000-00b10000f1b1.png'::text as logo_b1,
  '00000000-0000-0000-0000-00b100000a00/00000000-0000-0000-0000-00b100000a10/logo/00000000-0000-0000-0000-00b10000f1ff.png'::text as logo_missing,
  app.storefront_media_prefix('00000000-0000-0000-0000-00b100000a10') as pa1,
  app.storefront_media_prefix('00000000-0000-0000-0000-00b100000b10') as pb1;
grant select on _k to anon, authenticated;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_a1 from _k;
insert into storage.objects (bucket_id, name) select 'menu-images', menu_a1 from _k;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_a2 from _k;
insert into storage.objects (bucket_id, name) select 'restaurant-logos', logo_b1 from _k;

-- a published, always-open profile for R-A1 (the public contract under test)
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a1a', 'sfp1-alpha', 'SFP Alpha',
       jsonb_build_object('weekly', (select jsonb_agg(jsonb_build_object('dow', d, 'open', o, 'close', c))
                                       from generate_series(0, 6) d cross join (values ('00:00', '12:00'), ('11:00', '00:00')) w(o, c)),
                          'exceptions', '[]'::jsonb), true, 1;
-- an org B LIVE derivative (cross-tenant target)
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at)
select '00000000-0000-0000-0000-00b10000fb01', '00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000b10', 'restaurant-logos', logo_b1, 'w480',
       pb1 || '/' || repeat('b', 64) || '.webp', repeat('b', 64), 480, 240, 2000, now() - interval '1 hour' from _k;

create temp table _pm (label text primary key, r jsonb);
grant select, insert on _pm to anon, authenticated;

-- ============================================================================
-- A. contract introspection ............................................. (16)
-- ============================================================================
create temp table _fns as select * from (values
  ('stage_storefront_media(uuid,uuid,uuid,text,text,text,text,integer,integer,integer)'),
  ('finalize_storefront_media(uuid,uuid,uuid,uuid)'),
  ('cancel_storefront_media(uuid,uuid,uuid,uuid)'),
  ('retract_storefront_media(uuid,uuid,uuid,uuid)'),
  ('list_storefront_media(uuid,uuid)')) v(sig);
select is((select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('stage_storefront_media', 'finalize_storefront_media', 'cancel_storefront_media', 'retract_storefront_media', 'list_storefront_media')), 5,
  'A1. exactly one public overload of each of the five media RPCs');
select is((select count(*)::int from _fns f join pg_proc p on p.oid = ('public.' || f.sig)::regprocedure
            where not p.prosecdef and p.proconfig = array['search_path=""']), 5,
  'A2. the five public wrappers are SECURITY INVOKER with search_path pinned to empty');
select is((select count(*)::int from _fns f join pg_proc p on p.oid = ('app.' || f.sig)::regprocedure
            where p.prosecdef and p.proconfig = array['search_path=""'] and pg_get_userbyid(p.proowner) = 'postgres'), 5,
  'A3. the five app bodies are SECURITY DEFINER, search_path pinned, owned by postgres');
select is((select count(*)::int from _fns f
            where has_function_privilege('authenticated', ('public.' || f.sig)::regprocedure, 'EXECUTE')
              and has_function_privilege('authenticated', ('app.' || f.sig)::regprocedure, 'EXECUTE')), 5,
  'A4. authenticated holds EXECUTE on BOTH layers (an ungranted DEFINER body behind an INVOKER wrapper would be 42501 for everyone)');
select is((select count(*)::int from _fns f
            where has_function_privilege('anon', ('public.' || f.sig)::regprocedure, 'EXECUTE')
               or has_function_privilege('anon', ('app.' || f.sig)::regprocedure, 'EXECUTE')), 0,
  'A5. anon holds EXECUTE on neither layer');
select is((select count(*)::int from _fns f join pg_proc p on p.oid in (('public.' || f.sig)::regprocedure, ('app.' || f.sig)::regprocedure)
            where exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)), 0,
  'A6. PUBLIC holds EXECUTE on no layer (explicit revoke, never the default grant)');
select is(
  (select string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by 1)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  'storefront_menu(text)',
  'A7. the anon-executable public set is still EXACTLY {storefront_menu(text)} (no new anon RPC)');
select is(
  (select string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by 1)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef),
  'storefront_menu(text)',
  'A8. the public SECURITY DEFINER set is still EXACTLY {storefront_menu(text)}');
select ok(not has_schema_privilege('anon', 'app', 'USAGE'), 'A9. anon still has no USAGE on schema app');
select is((select provolatile::text from pg_proc where oid = 'app.list_storefront_media(uuid,uuid)'::regprocedure), 's',
  'A10. list is STABLE (read-only)');
select ok((select indexdef from pg_indexes where schemaname = 'public' and indexname = 'storefront_media_live_source_idx')
            ~ 'UNIQUE INDEX .* WHERE \(\(published_at IS NOT NULL\) AND \(unpublished_at IS NULL\)\)',
  'A11. the live-source unique index is LIVE-only (published and not retracted)');
select ok(not has_table_privilege('authenticated', 'public.storefront_media', 'SELECT')
      and not has_table_privilege('authenticated', 'public.storefront_media', 'INSERT'),
  'A12. storefront_media is still RPC-only for authenticated (no table grant)');
set local role anon;
-- the grant layer's own message: a body refusal (e.g. "list_storefront_media: authentication required") cannot pass for it
select throws_ok($$ select public.list_storefront_media('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10') $$,
  '42501', 'permission denied for function list_storefront_media', 'A13. the REAL anon role is refused list at the grant layer');
select throws_ok($$ select public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00001', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fb01') $$,
  '42501', 'permission denied for function finalize_storefront_media', 'A14. the REAL anon role is refused finalize at the grant layer');
reset role;
-- authenticated WITHOUT an app user (no GUC, no JWT) is refused inside the body
set local role authenticated;
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c00001', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', 'x', 'w480', repeat('1', 64), 480, 240, 1000) $$,
  '42501', 'stage_storefront_media: authentication required', 'A15. an authenticated session with no resolvable app user is refused inside the body (42501)');
select throws_ok($$ select public.list_storefront_media('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10') $$,
  '42501', 'list_storefront_media: authentication required', 'A16. ...list too');
reset role;

-- ============================================================================
-- B. stage ............................................................... (30)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';   -- manager of R-A1
-- exact enumerations (the Edge Function's prototype-name bug class cannot exist in SQL IN, proven anyway).
-- Each refused stage has its OWN request id (c002xx): a refusal that stopped refusing would claim only
-- its own key, so it fails its named assertion instead of aborting the file on a key-reuse raise.
insert into _pm select 'v_constructor', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00201', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'constructor', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'v_proto', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00202', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), '__proto__', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'v_case', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00203', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'W480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'v_space', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00204', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480 ', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'b_proto', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00205', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'toString', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'b_public', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00206', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'storefront-media', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'b_items', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00207', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'b_hash', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00208', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('G', 64), 480, 240, 1000);
insert into _pm select 'b_dims', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00209', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 481, 240, 1000);
insert into _pm select 'b_bytes', public.stage_storefront_media('00000000-0000-0000-0000-00b100c0020a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 524289);
insert into _pm select 'b_missing', public.stage_storefront_media('00000000-0000-0000-0000-00b100c0020b', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_missing from _k), 'w480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'b_foreign', public.stage_storefront_media('00000000-0000-0000-0000-00b100c0020c', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a2 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'b_wrongbucket', public.stage_storefront_media('00000000-0000-0000-0000-00b100c0020d', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select logo_a1 from _k), 'w960', repeat('1', 64), 960, 480, 1000);
-- the happy path: the receipt logo, w480
insert into _pm select 'stage1', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00003', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'stage1_replay', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00003', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c00003', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('9', 64), 480, 240, 1000) $$,
  '42501', null, 'B1. a request id reused with DIFFERENT input is refused (42501), never silently re-applied');
insert into _pm select 'stage1_again', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00004', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
-- the same bytes claimed from another source: the existing row is returned (content address) and flagged
insert into _pm select 'stage1_other_source', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00005', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('1', 64), 480, 240, 1000);
insert into _pm select 'stage1_mismatch', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00006', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1001);
-- a hero from the menu-item original (w960)
insert into _pm select 'stage_hero', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00007', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('4', 64), 960, 640, 4000);
-- rank 1 covering the restaurant: typed + audited
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee03';   -- cashier of R-A1
insert into _pm select 'cashier_stage', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00008', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('5', 64), 480, 240, 1000);
-- a manager of ANOTHER restaurant of the same org: no covering membership -> 42501
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee04';
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c00009', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('5', 64), 480, 240, 1000) $$,
  '42501', null, 'B2. a manager of a sibling restaurant (no covering membership) is refused with 42501');
-- the owner of ANOTHER tenant: 42501 (cross-tenant)
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee0b';
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c0000a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('5', 64), 480, 240, 1000) $$,
  '42501', null, 'B3. the owner of another tenant is refused with 42501 (no state leak)');
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c0000b', '00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('5', 64), 480, 240, 1000) $$,
  '42501', null, 'B4. ...also when it names its OWN org with the foreign restaurant (restaurant not in org)');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee01';   -- org_owner of org A
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c0000c', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000b10', 'restaurant-logos', 'x', 'bogus', repeat('5', 64), 480, 240, 1000) $$,
  '42501', null, 'B4b. an org owner naming a FOREIGN restaurant is refused with 42501 before input validation (no typed answer)');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee05';   -- ORG-WIDE cashier of org A (rank 1 everywhere)
select throws_ok($$ select public.stage_storefront_media('00000000-0000-0000-0000-00b100c0000d', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000b10', 'restaurant-logos', (select logo_b1 from _k), 'w480', repeat('5', 64), 480, 240, 1000) $$,
  '42501', null, 'B4c. an org-wide cashier naming a FOREIGN restaurant gets 42501, not an audited permission_denied');
select throws_ok($$ select public.retract_storefront_media('00000000-0000-0000-0000-00b100c0000e', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b1deadbeef', '00000000-0000-0000-0000-00b10000fb01') $$,
  '42501', null, 'B4d. ...and naming an UNKNOWN restaurant gets 42501 too');
reset role;

select is((select r ->> 'reason' from _pm where label = 'v_constructor'), 'variant_invalid', 'B5. variant "constructor" is refused (variant_invalid)');
select is((select r ->> 'reason' from _pm where label = 'v_proto'), 'variant_invalid', 'B6. variant "__proto__" is refused');
select is((select r ->> 'reason' from _pm where label = 'v_case') || '/' || (select r ->> 'reason' from _pm where label = 'v_space'), 'variant_invalid/variant_invalid',
  'B7. case and whitespace variants of w480 are refused');
select is((select r ->> 'reason' from _pm where label = 'b_proto') || '/' || (select r ->> 'reason' from _pm where label = 'b_public'), 'source_bucket_invalid/source_bucket_invalid',
  'B8. source bucket "toString" and the PUBLIC bucket itself are refused as sources');
select is((select r ->> 'reason' from _pm where label = 'b_items'), 'variant_not_allowed', 'B9. (menu-images, w480) = item images: refused (out of scope)');
select is((select r ->> 'reason' from _pm where label = 'b_hash'), 'content_hash_invalid', 'B10. a non-lower-hex content hash is refused');
select is((select r ->> 'reason' from _pm where label = 'b_dims') || '/' || (select r ->> 'reason' from _pm where label = 'b_bytes'), 'dimensions_invalid/bytes_invalid',
  'B11. a side above the variant box and a size above 512 KiB are refused');
select is((select string_agg(r ->> 'error', '/' order by label) from _pm where label in ('b_missing', 'b_foreign', 'b_wrongbucket')), 'source_not_found/source_not_found/source_not_found',
  'B12. source proof: a missing object, another restaurant''s object and an object in the wrong bucket are all source_not_found');
select is((select count(*)::int from _pm where (label like 'b\_%' or label like 'v\_%') and coalesce((r ->> 'ok')::boolean, false)), 0,
  'B13. no refused stage returned ok');
select is((select (r ->> 'ok') || ':' || (r ->> 'state') || ':' || (r ->> 'existing') || ':' || (r ->> 'idempotent_replay') from _pm where label = 'stage1'), 'true:staged:false:false',
  'B14. a valid stage registers a NEW staged row');
select is((select r ->> 'object_key' from _pm where label = 'stage1'), (select pa1 from _k) || '/' || repeat('1', 64) || '.webp',
  'B15. the object key is the content address <restaurant prefix>/<sha256>.webp');
select is((select (r ->> 'source_bucket') || '|' || (r ->> 'source_key') || '|' || (r ->> 'variant') from _pm where label = 'stage1'),
  'restaurant-logos|' || (select logo_a1 from _k) || '|w480', 'B15b. the envelope carries the registered row''s source identity');
select ok((select (r ->> 'idempotent_replay')::boolean and r ->> 'media_id' = (select r ->> 'media_id' from _pm where label = 'stage1') from _pm where label = 'stage1_replay'),
  'B16. the same request replays the same result (idempotent_replay)');
select is((select (r ->> 'existing') || ':' || (r ->> 'state') || ':' || (r ->> 'source_mismatch') from _pm where label = 'stage1_again'), 'true:staged:false',
  'B17. a new request for the same bytes finds the existing row (one derivative per bytes per restaurant)');
select is((select r ->> 'media_id' from _pm where label = 'stage1_again'), (select r ->> 'media_id' from _pm where label = 'stage1'),
  'B18. ...with the same media id');
select is((select (r ->> 'existing') || ':' || (r ->> 'source_mismatch') from _pm where label = 'stage1_other_source'), 'true:true',
  'B19. the same bytes claimed from another source return the existing row flagged source_mismatch');
select is((select (r ->> 'source_bucket') || '|' || (r ->> 'variant') from _pm where label = 'stage1_other_source'), 'restaurant-logos|w480',
  'B19b. ...describing the EXISTING row (its own source and variant), not the request');
select is((select r ->> 'error' from _pm where label = 'stage1_mismatch'), 'content_mismatch',
  'B20. the same content address with different facts is refused (content_mismatch)');
select is((select count(*)::int from storefront_media where restaurant_id = '00000000-0000-0000-0000-00b100000a10' and published_at is null), 2,
  'B21. exactly two STAGED rows exist (logo + hero), no duplicates');
select is((select r ->> 'error' from _pm where label = 'cashier_stage'), 'permission_denied', 'B22. a cashier covering the restaurant gets a typed permission_denied');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00'
            and action = 'settings.storefront.media.denied' and new_values ->> 'operation' = 'stage'), 1,
  'B23. ...and the denial is audited');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00'
            and action like 'settings.storefront.media.%'
            and restaurant_id not in (select id from restaurants where organization_id = '00000000-0000-0000-0000-00b100000a00')), 0,
  'B23b. no media audit row of org A names a restaurant outside org A (foreign / unknown ids raise before any audit)');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.media.staged'), 2,
  'B24. one staged audit event per NEW row (replays and existing-row stages add none)');

-- ============================================================================
-- C. STAGED is absent from the public contract ............................ (7)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'point_staged', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00010', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 1,
  jsonb_build_object('logo_media_id', (select r ->> 'media_id' from _pm where label = 'stage1')));
reset role;
select is((select r ->> 'reason' from _pm where label = 'point_staged'), 'logo_media_id_invalid',
  'C1. the profile writer refuses to point at a STAGED derivative');
set local role anon;
insert into _pm select 'menu_c', public.storefront_menu('sfp1-alpha');
reset role;
select is((select r -> 'restaurant' ->> 'logo_url' from _pm where label = 'menu_c'), null, 'C2. storefront_menu serves no logo while the derivative is STAGED');
select ok((select r::text from _pm where label = 'menu_c') !~ repeat('1', 64), 'C3. the STAGED content address appears nowhere in the public payload');
select is((select (r ->> 'ok') from _pm where label = 'menu_c'), 'true', 'C4. the published storefront itself is served (control)');
-- bypassing the writer as the harness: a profile pointer at a STAGED row and a STAGED item-slot row
update restaurant_storefront_profiles set logo_media_id = (select (r ->> 'media_id')::uuid from _pm where label = 'stage1')
 where restaurant_id = '00000000-0000-0000-0000-00b100000a10';
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at)
select '00000000-0000-0000-0000-00b10000fc01', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', menu_a1, 'w480', pa1 || '/' || repeat('e', 64) || '.webp', repeat('e', 64), 480, 320, 900, null from _k;
set local role anon;
insert into _pm select 'menu_c_forced', public.storefront_menu('sfp1-alpha');
reset role;
update storefront_media set published_at = now() where id = '00000000-0000-0000-0000-00b10000fc01';
set local role anon;
insert into _pm select 'menu_c_item_live', public.storefront_menu('sfp1-alpha');
reset role;
update restaurant_storefront_profiles set logo_media_id = null where restaurant_id = '00000000-0000-0000-0000-00b100000a10';
delete from storefront_media where id = '00000000-0000-0000-0000-00b10000fc01';
select is((select r -> 'restaurant' ->> 'logo_url' from _pm where label = 'menu_c_forced'), null,
  'C5. even a profile pointer forced onto a STAGED row serves no logo (the read predicate requires LIVE)');
select is((select string_agg(coalesce(e ->> 'image_url', 'null'), ',') from _pm, jsonb_array_elements(r -> 'items') e where label = 'menu_c_forced'), 'null',
  'C6. a STAGED item-slot derivative is not served as the item image');
select is((select string_agg(coalesce(e ->> 'image_url', 'null'), ',') from _pm, jsonb_array_elements(r -> 'items') e where label = 'menu_c_item_live'),
  '/storage/v1/object/public/storefront-media/' || (select pa1 from _k) || '/' || repeat('e', 64) || '.webp',
  'C7. (discriminating control) the same row once LIVE is served, so C5 / C6 are not vacuous');

-- ============================================================================
-- D. finalize ............................................................ (15)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'fin_missing', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00011', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
-- the caller uploads the derivative under the REGISTERED key (the storage INSERT policy admits it)
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', r ->> 'object_key', '{"mimetype":"image/png","size":1000}'::jsonb from _pm where label = 'stage1';
insert into _pm select 'fin_type', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00011', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
reset role;
update storage.objects set metadata = '{"mimetype":"image/webp","size":999}'::jsonb
 where bucket_id = 'storefront-media' and name = (select r ->> 'object_key' from _pm where label = 'stage1');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'fin_size', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00011', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
reset role;
update storage.objects set metadata = '{"mimetype":"image/webp","size":1000}'::jsonb
 where bucket_id = 'storefront-media' and name = (select r ->> 'object_key' from _pm where label = 'stage1');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
-- the SAME request id as the failed attempts: typed failures were not claimed, so it now succeeds
insert into _pm select 'fin1', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00011', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'fin1_replay', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00011', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'fin1_again', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00012', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'fin_foreign', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00013', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fb01');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee03';   -- cashier
insert into _pm select 'fin_cashier', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00014', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage_hero'));
reset role;
select is((select r ->> 'error' from _pm where label = 'fin_missing'), 'object_missing', 'D1. finalize before the upload: object_missing');
select is((select r ->> 'error' from _pm where label = 'fin_type'), 'object_mismatch', 'D2. an object that is not image/webp: object_mismatch');
select is((select r ->> 'error' from _pm where label = 'fin_size'), 'object_mismatch', 'D3. an object of another size than staged: object_mismatch');
select is((select (r ->> 'ok') || ':' || (r ->> 'state') || ':' || (r ->> 'already_published') || ':' || (r ->> 'republished') from _pm where label = 'fin1'),
  'true:published:false:false', 'D4. after the proven upload the SAME request id publishes (failures were not claimed)');
select ok((select published_at is not null and unpublished_at is null from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'stage1')),
  'D5. the row is LIVE');
select is((select coalesce(r ->> 'replaced_media_id', 'null') || '|' || coalesce(r ->> 'profile_version', 'null') from _pm where label = 'fin1'), 'null|null',
  'D6. no replacement on a first publish');
select ok((select (r ->> 'idempotent_replay')::boolean from _pm where label = 'fin1_replay'), 'D7. finalize replays');
select is((select (r ->> 'ok') || ':' || (r ->> 'already_published') from _pm where label = 'fin1_again'), 'true:true', 'D8. finalizing a LIVE row again is an idempotent ok');
select is((select r ->> 'error' from _pm where label = 'fin_foreign'), 'not_found', 'D9. another tenant''s media id is not_found');
select is((select r ->> 'error' from _pm where label = 'fin_cashier'), 'permission_denied', 'D10. a cashier cannot finalize');
set local role anon;
insert into _pm select 'menu_d', public.storefront_menu('sfp1-alpha');
reset role;
select ok((select r::text from _pm where label = 'menu_d') !~ repeat('1', 64), 'D11. a LIVE derivative no slot references appears nowhere in the public payload');
select is((select r -> 'restaurant' ->> 'logo_url' from _pm where label = 'menu_d'), null,
  'D12. a LIVE derivative is only served once the profile points at it (finalize does not assign a slot)');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'point_logo', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00015', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 1,
  jsonb_build_object('logo_media_id', (select r ->> 'media_id' from _pm where label = 'stage1')));
reset role;
set local role anon;
insert into _pm select 'menu_d2', public.storefront_menu('sfp1-alpha');
reset role;
select is((select (r ->> 'ok') || ':' || (r ->> 'version') from _pm where label = 'point_logo'), 'true:2', 'D13. the profile writer accepts the LIVE derivative (CAS version 1 -> 2)');
select is((select r -> 'restaurant' ->> 'logo_url' from _pm where label = 'menu_d2'),
  '/storage/v1/object/public/storefront-media/' || (select pa1 from _k) || '/' || repeat('1', 64) || '.webp',
  'D14. storefront_menu now serves the logo at its public content address');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'stage1_replay_live', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00003', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('1', 64), 480, 240, 1000);
reset role;
select is((select (r ->> 'idempotent_replay') || ':' || (r ->> 'state') from _pm where label = 'stage1_replay_live'), 'true:published',
  'D15. a stage replay reports the row''s CURRENT state (published since), not the stored one');

-- ============================================================================
-- E. same-source replacement + RETRACTED -> LIVE ........................ (13)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'stage2', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00020', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('2', 64), 480, 240, 1100);
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', r ->> 'object_key', '{"mimetype":"image/webp","size":1100}'::jsonb from _pm where label = 'stage2';
insert into _pm select 'fin2', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00021', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage2'));
insert into _pm select 'get_e', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
reset role;
set local role anon;
insert into _pm select 'menu_e', public.storefront_menu('sfp1-alpha');
reset role;
select is((select r ->> 'state' from _pm where label = 'stage2'), 'staged', 'E1. a NEW hash for the SAME source stages next to the LIVE row (LIVE-only unique index)');
select is((select r ->> 'replaced_media_id' from _pm where label = 'fin2'), (select r ->> 'media_id' from _pm where label = 'stage1'),
  'E2. finalize reports the replaced LIVE row');
select is((select (r ->> 'profile_version')::int from _pm where label = 'fin2'), 3, 'E3. ...and the re-pointed profile version (2 -> 3)');
select is((select r -> 'profile' ->> 'logo_media_id' from _pm where label = 'get_e'), (select r ->> 'media_id' from _pm where label = 'stage2'),
  'E4. the profile slot moved to the new derivative in the same transaction (no blank slot)');
select is((select (r ->> 'version')::int from _pm where label = 'get_e'), 3, 'E5. the profile version was bumped (concurrent editors get version_conflict)');
select ok((select unpublished_at is not null from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'stage1')),
  'E6. the replaced row is RETRACTED');
select is((select count(*)::int from storefront_media where restaurant_id = '00000000-0000-0000-0000-00b100000a10'
            and source_key = (select logo_a1 from _k) and variant = 'w480' and published_at is not null and unpublished_at is null), 1,
  'E7. exactly one LIVE row per (source, variant)');
select is((select r -> 'restaurant' ->> 'logo_url' from _pm where label = 'menu_e'),
  '/storage/v1/object/public/storefront-media/' || (select pa1 from _k) || '/' || repeat('2', 64) || '.webp',
  'E8. the public logo is the new derivative');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00'
            and action = 'settings.storefront.updated' and reason = 'media_replaced'), 1,
  'E9. the re-point is audited as settings.storefront.updated with reason media_replaced');
-- RETRACTED -> LIVE: re-publish the first derivative
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'fin1_back', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00022', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'get_e2', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
reset role;
select is((select (r ->> 'republished') || ':' || (r ->> 'replaced_media_id') from _pm where label = 'fin1_back'),
  'true:' || (select r ->> 'media_id' from _pm where label = 'stage2'),
  'E10. a RETRACTED derivative can be re-published (RETRACTED -> LIVE), replacing the newer one');
select is((select r -> 'profile' ->> 'logo_media_id' from _pm where label = 'get_e2'), (select r ->> 'media_id' from _pm where label = 'stage1'),
  'E11. ...and the slot moved back atomically');
select ok((select unpublished_at is not null from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'stage2'))
      and (select published_at is not null and unpublished_at is null from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'stage1')),
  'E12. states swapped: first LIVE again, second RETRACTED');
select ok(exists (select 1 from storage.objects where bucket_id = 'storefront-media' and name = (select r ->> 'object_key' from _pm where label = 'stage2')),
  'E13. the retracted derivative''s object was NOT deleted');

-- ============================================================================
-- F. retract / cancel ..................................................... (16)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'ret_inuse', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00030', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'clear_logo', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00031', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 4,
  '{"logo_media_id": null}'::jsonb);
insert into _pm select 'ret1', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00030', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'ret1_replay', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00030', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'ret1_again', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00032', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
insert into _pm select 'point_retracted', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00033', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 5,
  jsonb_build_object('logo_media_id', (select r ->> 'media_id' from _pm where label = 'stage1')));
insert into _pm select 'ret_staged', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00034', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage_hero'));
insert into _pm select 'can_retracted', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00035', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage1'));
-- the hero's object was uploaded, then the publish is abandoned: cancel the STAGED row
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', r ->> 'object_key', '{"mimetype":"image/webp","size":4000}'::jsonb from _pm where label = 'stage_hero';
insert into _pm select 'can_hero', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00036', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage_hero'));
insert into _pm select 'can_hero_again', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00037', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage_hero'));
insert into _pm select 'stage_hero_stale', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00007', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('4', 64), 960, 640, 4000);
-- a later publish of the SAME bytes reuses the orphaned object's content address
insert into _pm select 'stage_hero2', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00038', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('4', 64), 960, 640, 4000);
insert into _pm select 'fin_hero2', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00039', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'stage_hero2'));
reset role;
set local role anon;
insert into _pm select 'menu_f', public.storefront_menu('sfp1-alpha');
reset role;
select is((select (r ->> 'error') || ':' || (r -> 'slots' ->> 0) from _pm where label = 'ret_inuse'), 'media_in_use:logo',
  'F1. retracting a derivative the profile uses is refused (media_in_use, slot named)');
select is((select r ->> 'error' from _pm where label = 'ret_inuse') || '|' || (select count(*)::text from management_request_results where client_request_id = '00000000-0000-0000-0000-00b100c00030' and result ->> 'ok' = 'false'),
  'media_in_use|0', 'F2. ...and the refusal was not claimed (the same key later succeeds)');
select is((select (r ->> 'ok') || ':' || (r ->> 'state') || ':' || (r ->> 'already_retracted') from _pm where label = 'ret1'), 'true:retracted:false',
  'F3. after clearing the slot, retract succeeds');
select ok((select (r ->> 'idempotent_replay')::boolean from _pm where label = 'ret1_replay'), 'F4. retract replays');
select is((select (r ->> 'ok') || ':' || (r ->> 'already_retracted') from _pm where label = 'ret1_again'), 'true:true', 'F5. retracting a RETRACTED row is an idempotent ok');
select is((select r ->> 'reason' from _pm where label = 'point_retracted'), 'logo_media_id_invalid', 'F6. the profile writer refuses a RETRACTED derivative');
select is((select r -> 'restaurant' ->> 'logo_url' from _pm where label = 'menu_f'), null, 'F7. the public contract no longer references a logo');
select ok((select r::text from _pm where label = 'menu_f') !~ repeat('1', 64) and (select r::text from _pm where label = 'menu_f') !~ repeat('2', 64),
  'F8. neither retracted content address appears in the public payload');
select is((select r ->> 'error' from _pm where label = 'ret_staged'), 'media_not_published', 'F9. a STAGED row cannot be retracted (cancel it instead)');
select is((select r ->> 'error' from _pm where label = 'can_retracted'), 'media_published', 'F10. a RETRACTED (once public) row cannot be cancelled (a LIVE row: J13)');
select is((select (r ->> 'ok') || ':' || (r ->> 'state') from _pm where label = 'can_hero'), 'true:cancelled', 'F11. a STAGED row is cancelled');
select is((select r ->> 'error' from _pm where label = 'can_hero_again'), 'not_found', 'F12. ...and is gone (a second cancel is not_found)');
select is((select r ->> 'error' from _pm where label = 'stage_hero_stale'), 'stale_request',
  'F12b. replaying the cancelled row''s stage request is stale_request (never a resurrected media id to upload under)');
select ok(exists (select 1 from storage.objects where bucket_id = 'storefront-media' and name = (select r ->> 'object_key' from _pm where label = 'stage_hero')),
  'F13. cancel never deleted the uploaded object');
select is((select (r ->> 'existing') || ':' || (r ->> 'state') from _pm where label = 'stage_hero2'), 'false:staged',
  'F14. the same bytes stage again as a NEW row at the same content address');
select is((select (r ->> 'ok') || ':' || (r ->> 'state') from _pm where label = 'fin_hero2'), 'true:published',
  'F15. ...and publish against the object that was left in place (retry after an abandoned attempt)');

-- ============================================================================
-- G. list ................................................................. (8)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'point_hero', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00040', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 5,
  jsonb_build_object('hero_media_id', (select r ->> 'media_id' from _pm where label = 'stage_hero2')));
insert into _pm select 'list_mgr', public.list_storefront_media('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee03';
insert into _pm select 'list_cashier', public.list_storefront_media('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee0b';
insert into _pm select 'list_foreign', public.list_storefront_media('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
insert into _pm select 'list_foreign_mix', public.list_storefront_media('00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000a10');
reset role;
select is((select (r ->> 'ok') from _pm where label = 'point_hero'), 'true', 'G1. the hero slot is assigned through the profile CAS writer');
select is((select jsonb_array_length(r -> 'media') from _pm where label = 'list_mgr'), 3, 'G2. the manager lists exactly this restaurant''s 3 derivatives');
select is((select string_agg(e ->> 'state', ',' order by e ->> 'content_hash') from _pm, jsonb_array_elements(r -> 'media') e where label = 'list_mgr'),
  'retracted,retracted,published', 'G3. states: logo#1 retracted, logo#2 retracted, hero published');
select is((select e -> 'in_use' from _pm, jsonb_array_elements(r -> 'media') e where label = 'list_mgr' and e ->> 'content_hash' = repeat('4', 64)), '["hero"]'::jsonb,
  'G4. in_use names the slot using the derivative');
select is((select r ->> 'media_prefix' from _pm where label = 'list_mgr'), (select pa1 from _k), 'G5. the listing carries the opaque media prefix');
select is((select r::text from _pm where label = 'list_cashier'), '{"ok": false, "error": "not_found", "entity": "storefront_media"}',
  'G6. below manager: uniform not_found');
select is((select r::text from _pm where label = 'list_foreign'), '{"ok": false, "error": "not_found", "entity": "storefront_media"}',
  'G7. another tenant''s owner: the same uniform not_found (no raise, no leak)');
select is((select r::text from _pm where label = 'list_foreign_mix'), '{"ok": false, "error": "not_found", "entity": "storefront_media"}',
  'G8. an owner naming its own org with a foreign restaurant: not_found');

-- ============================================================================
-- H. item images stay out; hero served; unpublish -> not_found; audit ....... (5)
-- ============================================================================
set local role anon;
insert into _pm select 'menu_h', public.storefront_menu('sfp1-alpha');
reset role;
select is((select r -> 'restaurant' ->> 'hero_url' from _pm where label = 'menu_h'),
  '/storage/v1/object/public/storefront-media/' || (select pa1 from _k) || '/' || repeat('4', 64) || '.webp',
  'H1. the hero derivative is served once assigned');
select is((select string_agg(coalesce(e ->> 'image_url', 'null'), ',') from _pm, jsonb_array_elements(r -> 'items') e where label = 'menu_h'), 'null',
  'H2. item images stay out: a w960 hero published from the item''s own original never becomes the item image');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'unpublish', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00041', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 6,
  '{"is_published": false}'::jsonb);
reset role;
set local role anon;
insert into _pm select 'menu_unpub', public.storefront_menu('sfp1-alpha');
reset role;
select is((select (r ->> 'ok') || ':' || (r ->> 'is_published') from _pm where label = 'unpublish'), 'true:false', 'H3. unpublish through the profile writer');
select is((select r::text from _pm where label = 'menu_unpub'), '{"ok": false, "error": "not_found", "entity": "storefront_menu"}',
  'H4. an unpublished storefront answers the uniform not_found');
select is((select string_agg(action || '=' || n, ',' order by action) from (
             select action, count(*)::text n from audit_events
              where organization_id = '00000000-0000-0000-0000-00b100000a00' and action like 'settings.storefront.media.%'
              group by action) x),
  'settings.storefront.media.cancelled=1,settings.storefront.media.denied=2,settings.storefront.media.published=4,settings.storefront.media.retracted=3,settings.storefront.media.staged=4',
  'H5. the media audit trail: 4 staged, 4 published, 3 retracted (2 by replacement + 1 explicit), 1 cancelled, 2 denied');

-- ============================================================================
-- I. replacement matrix, typed failures not claimed, timestamp edge ........ (18)
-- ============================================================================
-- state here: profile R-A1 version 7 (unpublished), logo null, hero = stage_hero2 (LIVE, menu-images w960)
create or replace function pg_temp.up(p_label text, p_size integer) returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata)
  select 'storefront-media', r ->> 'object_key', jsonb_build_object('mimetype', 'image/webp', 'size', p_size) from _pm where label = p_label;
$$;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
-- I1: a same-source replacement of the HERO moves the hero slot only
insert into _pm select 'i_hero_a', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00050', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('a', 64), 960, 640, 4100);
select pg_temp.up('i_hero_a', 4100);
insert into _pm select 'i_fin_hero_a', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00051', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_hero_a'));
insert into _pm select 'i_get1', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
-- I2: logo AND hero on the same row, then replaced: both move in ONE version bump
insert into _pm select 'i_both', public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00b100c00052', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 8,
  jsonb_build_object('logo_media_id', (select r ->> 'media_id' from _pm where label = 'i_hero_a')));
insert into _pm select 'i_hero_b', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00053', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('b', 64), 960, 640, 4200);
select pg_temp.up('i_hero_b', 4200);
insert into _pm select 'i_fin_hero_b', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00054', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_hero_b'));
insert into _pm select 'i_get2', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
-- I3: a replacement of an UNASSIGNED LIVE row re-points nothing
insert into _pm select 'i_logo_c', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00055', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('c', 64), 480, 240, 1200);
select pg_temp.up('i_logo_c', 1200);
insert into _pm select 'i_fin_logo_c', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00056', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_logo_c'));
insert into _pm select 'i_logo_d', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00057', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w480', repeat('d', 64), 480, 240, 1300);
select pg_temp.up('i_logo_d', 1300);
insert into _pm select 'i_fin_logo_d', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00058', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_logo_d'));
insert into _pm select 'i_get3', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10');
-- I4: retract refused while STAGED, then the SAME key succeeds once LIVE (the refusal was not claimed)
insert into _pm select 'i_w960', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00059', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w960', repeat('f', 64), 960, 480, 3000);
insert into _pm select 'i_ret_staged', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00060', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_w960'));
select pg_temp.up('i_w960', 3000);
insert into _pm select 'i_fin_w960', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00061', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_w960'));
insert into _pm select 'i_ret_live', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00060', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_w960'));
-- I5: content_mismatch is not claimed: after the conflicting STAGED row is cancelled the SAME key succeeds
insert into _pm select 'i_m', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00062', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w960', repeat('9', 64), 960, 480, 5000);
insert into _pm select 'i_mismatch', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00063', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w960', repeat('9', 64), 960, 480, 5001);
insert into _pm select 'i_cancel_m', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00064', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_m'));
insert into _pm select 'i_mismatch_retry', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00063', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'restaurant-logos', (select logo_a1 from _k), 'w960', repeat('9', 64), 960, 480, 5001);
reset role;
-- I6: a LIVE row whose published_at lies AHEAD of now() (what a lock wait can produce) is replaced
--     and a new row retracted without violating unpublish_after_publish
update storefront_media set unpublished_at = greatest(now(), published_at)
 where organization_id = '00000000-0000-0000-0000-00b100000a00' and source_key = (select menu_a1 from _k) and variant = 'w960' and published_at is not null and unpublished_at is null;
update restaurant_storefront_profiles set hero_media_id = null, logo_media_id = null where restaurant_id = '00000000-0000-0000-0000-00b100000a10';
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at)
select '00000000-0000-0000-0000-00b10000fd01', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', menu_a1, 'w960', pa1 || '/' || repeat('6', 64) || '.webp', repeat('6', 64), 960, 640, 100, now() + interval '1 minute' from _k;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'i_new7', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00065', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('7', 64), 960, 640, 4700);
select pg_temp.up('i_new7', 4700);
insert into _pm select 'i_fin_new7', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00066', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_new7'));
insert into _pm select 'i_ret_new7', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00067', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_new7'));
-- I7: the finalize request of i_new7 replayed AFTER the row was retracted: the stored answer is stale
insert into _pm select 'i_fin_new7_replay', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00066', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'i_new7'));
reset role;
select is((select (r ->> 'replaced_media_id') || ':' || (r ->> 'profile_version') from _pm where label = 'i_fin_hero_a'),
  (select r ->> 'media_id' from _pm where label = 'stage_hero2') || ':8', 'I1. replacing the HERO derivative reports the replaced row and the re-pointed version 8');
select is((select coalesce(r -> 'profile' ->> 'hero_media_id', 'null') || '|' || coalesce(r -> 'profile' ->> 'logo_media_id', 'null') from _pm where label = 'i_get1'),
  (select r ->> 'media_id' from _pm where label = 'i_hero_a') || '|null', 'I2. the hero slot moved; the (empty) logo slot was untouched');
select is((select (r ->> 'profile_version')::int from _pm where label = 'i_fin_hero_b'), 10, 'I3. both slots on the replaced row: ONE version bump (9 -> 10)');
select is((select (r -> 'profile' ->> 'hero_media_id') || '|' || (r -> 'profile' ->> 'logo_media_id') from _pm where label = 'i_get2'),
  (select r ->> 'media_id' from _pm where label = 'i_hero_b') || '|' || (select r ->> 'media_id' from _pm where label = 'i_hero_b'),
  'I4. ...both logo and hero moved to the new derivative in that one transaction');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.updated' and reason = 'media_replaced'), 4,
  'I5. ...with exactly one media_replaced profile audit per re-pointing finalize (2 in E + I1 + I2)');
select is((select coalesce(r ->> 'profile_version', 'null') || '|' || (r ->> 'replaced_media_id') from _pm where label = 'i_fin_logo_d'),
  'null|' || (select r ->> 'media_id' from _pm where label = 'i_logo_c'), 'I6. replacing an UNASSIGNED LIVE row retracts it and re-points nothing (profile_version null)');
select is((select (r ->> 'version')::int from _pm where label = 'i_get3'), 10, 'I7. ...the profile version is unchanged');
select is((select r ->> 'error' from _pm where label = 'i_ret_staged'), 'media_not_published', 'I8. retracting a STAGED row is refused');
select is((select (r ->> 'ok') || ':' || (r ->> 'idempotent_replay') || ':' || (r ->> 'already_retracted') from _pm where label = 'i_ret_live'), 'true:false:false',
  'I9. ...and that refusal was not claimed: the SAME key retracts the row once it is LIVE');
select is((select r ->> 'error' from _pm where label = 'i_mismatch'), 'content_mismatch', 'I10. a content address with other facts is refused');
select is((select (r ->> 'ok') || ':' || (r ->> 'existing') || ':' || (r ->> 'idempotent_replay') from _pm where label = 'i_mismatch_retry'), 'true:false:false',
  'I11. ...not claimed: after the conflicting row is cancelled the SAME key registers the bytes');
select is((select (r ->> 'replaced_media_id') from _pm where label = 'i_fin_new7'), '00000000-0000-0000-0000-00b10000fd01',
  'I12. a LIVE row published AHEAD of now() is replaced without violating unpublish_after_publish');
select ok((select unpublished_at = published_at from storefront_media where id = '00000000-0000-0000-0000-00b10000fd01'),
  'I13. ...its unpublished_at is clamped to its published_at');
select is((select (r ->> 'ok') || ':' || (r ->> 'state') from _pm where label = 'i_ret_new7'), 'true:retracted', 'I14. retracting the new row succeeds too');
select ok((select unpublished_at >= published_at from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'i_new7')),
  'I15. ...and keeps unpublished_at >= published_at');
select is((select r ->> 'error' from _pm where label = 'i_fin_new7_replay'), 'stale_request',
  'I17. a finalize replay re-reads its row: retracted since -> stale_request, never the stored "published"');
select ok((select unpublished_at is not null from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'i_new7'))
          and (select count(*) from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.media.published'
                 and new_values ->> 'id' = (select r ->> 'media_id' from _pm where label = 'i_new7')) = 1,
  'I18. ...and the stale replay changed nothing (the row stays RETRACTED, still one publish audit)');
select is((select coalesce(max(n), 0) from (select count(*)::int n from storefront_media where organization_id = '00000000-0000-0000-0000-00b100000a00' and restaurant_id = '00000000-0000-0000-0000-00b100000a10'
            and published_at is not null and unpublished_at is null group by source_bucket, source_key, variant) x), 1,
  'I16. every (source, variant) still has at most ONE LIVE row after the whole matrix');

-- ============================================================================
-- J. tenant binding + authority of cancel / retract / finalize, cancel of a
--    LIVE row, the object check on replays / already-LIVE rows, and the
--    retract replay re-read ................................................ (35)
-- ============================================================================
-- state here: the R-A1 profile slots are empty (I6); R-A1 has no LIVE row for
-- (restaurant-logos, logo_a1, w960) nor for (menu-images, menu_a1, w960).
-- Fixtures (harness): org B STAGED fb02 (next to its LIVE fb01), restaurant A2 LIVE fa21 + STAGED fa22,
-- and the R-A1 targets fa11 (STAGED) and fa12 (LIVE, no slot uses it, its object present).
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at)
select v.id::uuid, v.org::uuid, v.rest::uuid, 'restaurant-logos', v.src, v.variant,
       app.storefront_media_prefix(v.rest::uuid) || '/' || v.h || '.webp', v.h, 480, 240, 1000, v.pub
  from _k cross join lateral (values
    ('00000000-0000-0000-0000-00b10000fb02', '00000000-0000-0000-0000-00b100000b00', '00000000-0000-0000-0000-00b100000b10', _k.logo_b1, 'w480', repeat('03', 32), null::timestamptz),
    ('00000000-0000-0000-0000-00b10000fa21', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a20', _k.logo_a2, 'w480', repeat('04', 32), now() - interval '1 hour'),
    ('00000000-0000-0000-0000-00b10000fa22', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a20', _k.logo_a2, 'w480', repeat('05', 32), null),
    ('00000000-0000-0000-0000-00b10000fa11', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', _k.logo_a1, 'w960', repeat('08', 32), null),
    ('00000000-0000-0000-0000-00b10000fa12', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', _k.logo_a1, 'w960', repeat('0c', 32), now() - interval '1 hour')
  ) v(id, org, rest, src, variant, h, pub);
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', object_key, jsonb_build_object('mimetype', 'image/webp', 'size', bytes)
  from storefront_media where id = '00000000-0000-0000-0000-00b10000fa12';
create temp table _snap as
  select sm.id, to_jsonb(sm) as j from storefront_media sm
   where sm.id in ('00000000-0000-0000-0000-00b10000fb01', '00000000-0000-0000-0000-00b10000fb02', '00000000-0000-0000-0000-00b10000fa21',
                   '00000000-0000-0000-0000-00b10000fa22', '00000000-0000-0000-0000-00b10000fa11', '00000000-0000-0000-0000-00b10000fa12');
-- how many of the given rows are byte-for-byte what they were at the snapshot (a deleted row does not count)
create or replace function pg_temp.unchanged(p_ids uuid[]) returns integer language sql as $$
  select count(*)::int from storefront_media sm join _snap s on s.id = sm.id where sm.id = any(p_ids) and to_jsonb(sm) = s.j;
$$;
-- the typed error of a recorded call; the whole envelope when it carries none (a mutant's ok shows up in the diagnostics)
create or replace function pg_temp.err(p_label text) returns text language sql as $$
  select coalesce((select coalesce(r ->> 'error', r::text) from _pm where label = p_label), '<no call>');
$$;

-- J1-J4 (TNV-1): a manager of R-A1 names ITS OWN org + restaurant with a FOREIGN media id
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';   -- manager of R-A1
insert into _pm select 'j_can_orgb', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00101', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fb02');
insert into _pm select 'j_can_a2', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00102', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa22');
insert into _pm select 'j_ret_orgb', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00103', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fb01');
insert into _pm select 'j_ret_a2', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00104', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa21');
reset role;
select is(pg_temp.err('j_can_orgb') || '/' || pg_temp.err('j_can_a2'), 'not_found/not_found',
  'J1. cancel naming (org A, R-A1) with an org B / a restaurant A2 STAGED media id: not_found (the row select is bound to the caller''s org + restaurant)');
select is(pg_temp.err('j_ret_orgb') || '/' || pg_temp.err('j_ret_a2'), 'not_found/not_found',
  'J2. retract naming (org A, R-A1) with an org B / a restaurant A2 LIVE media id: not_found');
select is(pg_temp.unchanged(array['00000000-0000-0000-0000-00b10000fb01', '00000000-0000-0000-0000-00b10000fb02',
                                  '00000000-0000-0000-0000-00b10000fa21', '00000000-0000-0000-0000-00b10000fa22']::uuid[]), 4,
  'J3. the four foreign rows are untouched (both STAGED rows still present, both LIVE rows still LIVE)');
select is((select count(*)::int from audit_events
            where (old_values ->> 'id') in ('00000000-0000-0000-0000-00b10000fb01', '00000000-0000-0000-0000-00b10000fb02', '00000000-0000-0000-0000-00b10000fa21', '00000000-0000-0000-0000-00b10000fa22')
               or (new_values ->> 'id') in ('00000000-0000-0000-0000-00b10000fb01', '00000000-0000-0000-0000-00b10000fb02', '00000000-0000-0000-0000-00b10000fa21', '00000000-0000-0000-0000-00b10000fa22')), 0,
  'J4. no audit row (of any tenant) carries a foreign row''s data');

-- J5-J12 (TNV-2): who may cancel / retract R-A1's own rows
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee03';   -- cashier covering R-A1 (rank 1)
insert into _pm select 'j_can_cashier', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00105', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa11');
insert into _pm select 'j_ret_cashier', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00106', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee04';   -- manager of the SIBLING restaurant A2 (rank 0 over R-A1)
select throws_ok($$ select public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00107', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa11') $$,
  '42501', 'cancel_storefront_media: caller has no active membership covering the restaurant',
  'J5. a manager of a sibling restaurant cannot cancel an R-A1 row (42501, no typed answer)');
select throws_ok($$ select public.retract_storefront_media('00000000-0000-0000-0000-00b100c00108', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12') $$,
  '42501', 'retract_storefront_media: caller has no active membership covering the restaurant',
  'J6. ...nor retract one');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee0b';   -- owner of org B (rank 0 over org A)
select throws_ok($$ select public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00109', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa11') $$,
  '42501', 'cancel_storefront_media: caller has no active membership covering the restaurant',
  'J7. the owner of another tenant cannot cancel an R-A1 row (42501)');
select throws_ok($$ select public.retract_storefront_media('00000000-0000-0000-0000-00b100c0010a', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12') $$,
  '42501', 'retract_storefront_media: caller has no active membership covering the restaurant',
  'J8. ...nor retract one');
reset role;
select is(pg_temp.err('j_can_cashier'), 'permission_denied', 'J9. a cashier covering R-A1 cannot cancel (typed permission_denied)');
select is(pg_temp.err('j_ret_cashier'), 'permission_denied', 'J10. ...nor retract');
select is((select string_agg(op || '=' || n, ',' order by op) from (
             select new_values ->> 'operation' as op, count(*)::text as n from audit_events
              where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.media.denied'
                and new_values ->> 'operation' in ('cancel', 'retract')
              group by 1) x),
  'cancel=1,retract=1', 'J11. ...and each of the two denials is audited');
select is(pg_temp.unchanged(array['00000000-0000-0000-0000-00b10000fa11', '00000000-0000-0000-0000-00b10000fa12']::uuid[]), 2,
  'J12. after every refused cancel / retract, the STAGED row is still present and the LIVE row still LIVE');

-- J13-J14 (TNV-6): a LIVE row (no slot uses it) cannot be cancelled either
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_can_live', public.cancel_storefront_media('00000000-0000-0000-0000-00b100c0010b', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12');
reset role;
select is(pg_temp.err('j_can_live'), 'media_published', 'J13. cancelling an unassigned LIVE row is refused (media_published)');
select is(pg_temp.unchanged(array['00000000-0000-0000-0000-00b10000fa12']::uuid[]), 1, 'J14. ...and the LIVE row is unchanged (its publication record is kept)');

-- J15-J22 (TNV-3): finalize rank 0, and the finalize / cancel restaurant-in-org pre-checks
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee04';   -- sibling manager
select throws_ok($$ select public.finalize_storefront_media('00000000-0000-0000-0000-00b100c0010c', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa11') $$,
  '42501', 'finalize_storefront_media: caller has no active membership covering the restaurant',
  'J15. a manager of a sibling restaurant cannot finalize an R-A1 row (42501, not an audited typed denial)');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee0b';   -- owner of org B
select throws_ok($$ select public.finalize_storefront_media('00000000-0000-0000-0000-00b100c0010d', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa11') $$,
  '42501', 'finalize_storefront_media: caller has no active membership covering the restaurant',
  'J16. ...nor can the owner of another tenant');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee01';   -- org_owner of org A naming a FOREIGN restaurant
select throws_ok($$ select public.finalize_storefront_media('00000000-0000-0000-0000-00b100c0010e', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000b10', '00000000-0000-0000-0000-00b10000fb02') $$,
  '42501', 'finalize_storefront_media: restaurant not found in organization or soft-deleted',
  'J17. an org owner naming a FOREIGN restaurant with its own org cannot finalize (42501)');
select throws_ok($$ select public.cancel_storefront_media('00000000-0000-0000-0000-00b100c0010f', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000b10', '00000000-0000-0000-0000-00b10000fb02') $$,
  '42501', 'cancel_storefront_media: restaurant not found in organization or soft-deleted',
  'J18. ...nor cancel');
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee05';   -- ORG-WIDE cashier of org A (rank 1 everywhere in org A)
select throws_ok($$ select public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00110', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000b10', '00000000-0000-0000-0000-00b10000fb02') $$,
  '42501', 'finalize_storefront_media: restaurant not found in organization or soft-deleted',
  'J19. an org-wide cashier naming a FOREIGN restaurant gets 42501 on finalize, not an audited permission_denied');
select throws_ok($$ select public.cancel_storefront_media('00000000-0000-0000-0000-00b100c00111', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000b10', '00000000-0000-0000-0000-00b10000fb02') $$,
  '42501', 'cancel_storefront_media: restaurant not found in organization or soft-deleted',
  'J20. ...and on cancel');
reset role;
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00'
            and action like 'settings.storefront.media.%'
            and restaurant_id not in (select id from restaurants where organization_id = '00000000-0000-0000-0000-00b100000a00')), 0,
  'J21. still no media audit row of org A names a restaurant outside org A');
select is((select string_agg(op || '=' || n, ',' order by op) from (
             select new_values ->> 'operation' as op, count(*)::text as n from audit_events
              where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.media.denied'
              group by 1) x),
  'cancel=1,finalize=1,retract=1,stage=1', 'J22. the only denial audits are the four rank-1 refusals (B22, D10, J9, J10): no 42501 above wrote one');

-- J23-J30 (DB-3 / TNV-5): the object check also runs on a REPLAY and on an already-LIVE row
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_stage_obj', public.stage_storefront_media('00000000-0000-0000-0000-00b100c00112', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', 'menu-images', (select menu_a1 from _k), 'w960', repeat('0d', 32), 960, 640, 2500);
select pg_temp.up('j_stage_obj', 2500);
insert into _pm select 'j_fin_obj', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00113', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
reset role;
-- the object vanishes (what a manager's raw Storage DELETE of a registered key does; a harness delete here)
set local storage.allow_delete_query = 'true';
delete from storage.objects where bucket_id = 'storefront-media' and name = (select r ->> 'object_key' from _pm where label = 'j_stage_obj');
reset storage.allow_delete_query;
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_fin_obj_replay_gone', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00113', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
insert into _pm select 'j_fin_obj_new_gone', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00114', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
reset role;
-- it comes back with the WRONG size
insert into storage.objects (bucket_id, name, metadata)
select 'storefront-media', r ->> 'object_key', '{"mimetype":"image/webp","size":2499}'::jsonb from _pm where label = 'j_stage_obj';
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_fin_obj_replay_size', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00113', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
insert into _pm select 'j_fin_obj_new_size', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00114', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
reset role;
-- restored
update storage.objects set metadata = '{"mimetype":"image/webp","size":2500}'::jsonb
 where bucket_id = 'storefront-media' and name = (select r ->> 'object_key' from _pm where label = 'j_stage_obj');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_fin_obj_replay_ok', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00113', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
insert into _pm select 'j_fin_obj_new_ok', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00114', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
reset role;
select is((select (r ->> 'ok') || ':' || (r ->> 'state') || ':' || (r ->> 'already_published') from _pm where label = 'j_fin_obj'), 'true:published:false',
  'J23. (control) a fresh stage + upload + finalize publishes');
select is(pg_temp.err('j_fin_obj_replay_gone'), 'object_missing',
  'J24. the object gone: a REPLAY of that finalize is object_missing, never the stored "published"');
select is(pg_temp.err('j_fin_obj_new_gone'), 'object_missing',
  'J25. ...and a NEW request on the LIVE row is object_missing, never already_published');
select is(pg_temp.err('j_fin_obj_replay_size'), 'object_mismatch', 'J26. back with the wrong size: the replay is object_mismatch');
select is(pg_temp.err('j_fin_obj_new_size'), 'object_mismatch', 'J27. ...and so is the new request');
select is((select (r ->> 'ok') || ':' || (r ->> 'idempotent_replay') || ':' || (r ->> 'state') from _pm where label = 'j_fin_obj_replay_ok'), 'true:true:published',
  'J28. restored: the replay answers its stored success again (idempotent_replay)');
select is((select (r ->> 'ok') || ':' || (r ->> 'idempotent_replay') || ':' || (r ->> 'already_published') from _pm where label = 'j_fin_obj_new_ok'), 'true:false:true',
  'J29. ...and the new request is a first (unreplayed) already_published: none of its failures was claimed');
select ok((select published_at is not null and unpublished_at is null from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'))
          and (select count(*) from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.media.published'
                 and new_values ->> 'id' = (select r ->> 'media_id' from _pm where label = 'j_stage_obj')) = 1,
  'J30. the row stayed LIVE throughout, with exactly one publish audit');

-- J31-J35 (DB-4): a retract REPLAY re-reads its row
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_ret_fa12', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00121', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12');
insert into _pm select 'j_fin_fa12_back', public.finalize_storefront_media('00000000-0000-0000-0000-00b100c00122', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12');
insert into _pm select 'j_ret_fa12_replay', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00121', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', '00000000-0000-0000-0000-00b10000fa12');
insert into _pm select 'j_ret_obj', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00123', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
reset role;
-- the retracted row vanishes (unreachable through the RPCs -- cancel refuses published rows -- so a harness delete)
delete from storefront_media where id = (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00b10000ee02';
insert into _pm select 'j_ret_obj_replay', public.retract_storefront_media('00000000-0000-0000-0000-00b100c00123', '00000000-0000-0000-0000-00b100000a00', '00000000-0000-0000-0000-00b100000a10', (select (r ->> 'media_id')::uuid from _pm where label = 'j_stage_obj'));
reset role;
select is((select (r ->> 'ok') || ':' || (r ->> 'state') || ':' || (r ->> 'already_retracted') from _pm where label = 'j_ret_fa12'), 'true:retracted:false',
  'J31. (control) the LIVE row is retracted');
select is((select (r ->> 'ok') || ':' || (r ->> 'republished') from _pm where label = 'j_fin_fa12_back'), 'true:true',
  'J32. ...then re-published (RETRACTED -> LIVE) by a later finalize');
select is(pg_temp.err('j_ret_fa12_replay'), 'stale_request',
  'J33. a replay of the retract after RETRACTED -> LIVE is stale_request, never the stored "retracted"');
select ok((select published_at is not null and unpublished_at is null from storefront_media where id = '00000000-0000-0000-0000-00b10000fa12')
          and (select count(*) from audit_events where organization_id = '00000000-0000-0000-0000-00b100000a00' and action = 'settings.storefront.media.retracted'
                 and new_values ->> 'id' = '00000000-0000-0000-0000-00b10000fa12') = 1,
  'J34. ...and it changed nothing: the row stays LIVE, still one retract audit');
select is((select r ->> 'ok' from _pm where label = 'j_ret_obj') || '|' || pg_temp.err('j_ret_obj_replay'), 'true|stale_request',
  'J35. a replay of a retract whose row is gone since is stale_request too');

select * from finish();
rollback;
