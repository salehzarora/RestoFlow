-- RF-109 Stage 2 -- menu RPC contract: public wrappers + app implementation shape (D-031 §4.23).
-- public.menu_* exist (SECURITY INVOKER), app.menu_* exist (SECURITY DEFINER), wrappers delegate,
-- granted to authenticated only (never anon). app schema stays unexposed (only public.* reachable).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(34);

-- ---- public wrappers exist (7) ----
select has_function('public', 'menu_upsert_category',        'public.menu_upsert_category wrapper exists');
select has_function('public', 'menu_upsert_item',            'public.menu_upsert_item wrapper exists');
select has_function('public', 'menu_upsert_size',            'public.menu_upsert_size wrapper exists');
select has_function('public', 'menu_upsert_variant',         'public.menu_upsert_variant wrapper exists');
select has_function('public', 'menu_upsert_modifier',        'public.menu_upsert_modifier wrapper exists');
select has_function('public', 'menu_upsert_modifier_option', 'public.menu_upsert_modifier_option wrapper exists');
select has_function('public', 'menu_soft_delete',            'public.menu_soft_delete wrapper exists');

-- ---- app implementation functions exist (7) ----
select has_function('app', 'menu_upsert_category',        'app.menu_upsert_category exists');
select has_function('app', 'menu_upsert_item',            'app.menu_upsert_item exists');
select has_function('app', 'menu_upsert_size',            'app.menu_upsert_size exists');
select has_function('app', 'menu_upsert_variant',         'app.menu_upsert_variant exists');
select has_function('app', 'menu_upsert_modifier',        'app.menu_upsert_modifier exists');
select has_function('app', 'menu_upsert_modifier_option', 'app.menu_upsert_modifier_option exists');
select has_function('app', 'menu_soft_delete',            'app.menu_soft_delete exists');

-- ---- app.* are SECURITY DEFINER (7) ----
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_category'), true, 'app.menu_upsert_category is SECURITY DEFINER');
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_item'), true, 'app.menu_upsert_item is SECURITY DEFINER');
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_size'), true, 'app.menu_upsert_size is SECURITY DEFINER');
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_variant'), true, 'app.menu_upsert_variant is SECURITY DEFINER');
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_modifier'), true, 'app.menu_upsert_modifier is SECURITY DEFINER');
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_modifier_option'), true, 'app.menu_upsert_modifier_option is SECURITY DEFINER');
select is((select bool_and(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_soft_delete'), true, 'app.menu_soft_delete is SECURITY DEFINER');

-- ---- public.* are SECURITY INVOKER (7) ----
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_category'), false, 'public.menu_upsert_category is SECURITY INVOKER');
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_item'), false, 'public.menu_upsert_item is SECURITY INVOKER');
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_size'), false, 'public.menu_upsert_size is SECURITY INVOKER');
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_variant'), false, 'public.menu_upsert_variant is SECURITY INVOKER');
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_modifier'), false, 'public.menu_upsert_modifier is SECURITY INVOKER');
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_modifier_option'), false, 'public.menu_upsert_modifier_option is SECURITY INVOKER');
select is((select bool_or(p.prosecdef) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_soft_delete'), false, 'public.menu_soft_delete is SECURITY INVOKER');

-- ---- grants: authenticated yes, anon no (2) ----
select ok(has_function_privilege('authenticated',
  'public.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean)', 'execute'),
  'authenticated may execute public.menu_upsert_category');
select ok(not has_function_privilege('anon',
  'public.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean)', 'execute'),
  'anon may NOT execute public.menu_upsert_category');

-- ---- delegation: public wrapper -> app function actually writes (4) ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf109rpc-c-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'rf109rpc-c-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000000000e1';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select is(
  (public.menu_upsert_category('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000c001', 'Drinks', 0, true) ->> 'ok')::boolean,
  true, 'public.menu_upsert_category delegates to app and returns ok');
select is(
  (select count(*) from menu_categories where id = '00000000-0000-0000-0000-00000000c001')::int,
  1, 'the category row was written through the wrapper -> app delegation');
select is(
  (public.menu_upsert_item('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001', 'Cola', null, 1500, 'USD', null, 0, true) ->> 'action'),
  'created', 'public.menu_upsert_item delegates and reports created');
select is(
  (select base_price_minor from menu_items where id = '00000000-0000-0000-0000-00000000d001'),
  1500::bigint, 'the item row was written with integer-minor price');

reset role;
select * from finish();
rollback;
