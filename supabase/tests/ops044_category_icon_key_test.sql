-- OPS-044 Phase 2 -- menu_categories.icon_key: storage, three-way write semantics,
-- read exposure on both menu RPCs, and the overload/ACL posture that the arity
-- change had to preserve.
--
-- The load-bearing assertion in this file is the PRESERVE case. menu_upsert_category
-- is a FULL-STATE upsert, so if an omitted p_icon_key were treated as "write NULL",
-- an unrelated rename from any caller that predates this column would silently wipe
-- the owner's chosen icon -- the same hazard OPS-043 Phase 3 hit on the item editor.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(51);

-- ===========================================================================
-- A. SCHEMA
-- ===========================================================================
select has_column('public', 'menu_categories', 'icon_key', 'menu_categories.icon_key exists');
select col_type_is('public', 'menu_categories', 'icon_key', 'text', 'icon_key is text');
select col_is_null('public', 'menu_categories', 'icon_key', 'icon_key is NULLABLE (NULL = no icon chosen)');
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.menu_categories'::regclass
      and contype = 'c' and conname = 'menu_categories_icon_key_format'),
  1, 'the icon_key format CHECK exists');

-- ===========================================================================
-- B. FUNCTION IDENTITY -- exactly ONE overload, old 7-arg signature gone
--    (a leftover overload is what makes PostgREST refuse named-argument calls)
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'menu_upsert_category'),
  1, 'exactly ONE app.menu_upsert_category definition exists');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'menu_upsert_category'),
  1, 'exactly ONE public.menu_upsert_category definition exists');
select is(
  (select pg_get_function_identity_arguments(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'menu_upsert_category'),
  'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_id uuid, p_name text, p_display_order integer, p_is_active boolean, p_icon_key text',
  'app.menu_upsert_category carries p_icon_key LAST so positional 7-arg callers still resolve');
select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'menu_upsert_category'),
  true, 'app.menu_upsert_category is still SECURITY DEFINER');
select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'menu_upsert_category'),
  false, 'public.menu_upsert_category is still SECURITY INVOKER');
select is(
  (select array_to_string(p.proconfig, ',') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'menu_upsert_category'),
  'search_path=""', 'app.menu_upsert_category keeps an empty search_path');

-- ACL posture restored verbatim against the NEW signature
select ok(has_function_privilege('authenticated',
  'app.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean,text)', 'execute'),
  'authenticated may execute app.menu_upsert_category');
select ok(not has_function_privilege('anon',
  'app.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean,text)', 'execute'),
  'anon may NOT execute app.menu_upsert_category');
select ok(not has_function_privilege('service_role',
  'app.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean,text)', 'execute'),
  'service_role may NOT execute app.menu_upsert_category');
select ok(has_function_privilege('authenticated',
  'public.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean,text)', 'execute'),
  'authenticated may execute the public wrapper');
select ok(not has_function_privilege('anon',
  'public.menu_upsert_category(uuid,uuid,uuid,uuid,text,integer,boolean,text)', 'execute'),
  'anon may NOT execute the public wrapper');

-- the read functions were REPLACED, not re-signed
select is(
  (select pg_get_function_identity_arguments(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'list_menu'),
  'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid',
  'app.list_menu signature is unchanged');
select is(
  (select pg_get_function_identity_arguments(p.oid) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'pos_menu'),
  'p_pin_session_id uuid, p_device_id uuid',
  'app.pos_menu signature is unchanged');

-- ===========================================================================
-- C. FIXTURE -- one org, two restaurants (the second proves tenancy)
-- ===========================================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000004400000', 'Icon Org', 'ops044-icons', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000004400010', '00000000-0000-0000-0000-000004400000', 'Rest One'),
  ('00000000-0000-0000-0000-000004400020', '00000000-0000-0000-0000-000004400000', 'Rest Two');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010', 'Branch One'),
  ('00000000-0000-0000-0000-000004400021', '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400020', 'Branch Two');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000044000e1', 'ops044-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000044000f1', '00000000-0000-0000-0000-0000044000e1',
   '00000000-0000-0000-0000-000004400000', null, null, 'org_owner');

-- ===========================================================================
-- D. WRITE SEMANTICS
-- ===========================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';

-- D1. A LEGACY POSITIONAL 7-ARG CALL still resolves through the defaulted 8th
--     parameter. This is the compatibility guarantee for the 29 existing call
--     sites across five pgTAP files.
select is(
  (app.menu_upsert_category(
     '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
     '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c1',
     'Burgers', 1, true) ->> 'action'),
  'created', 'a legacy positional 7-arg call still resolves and creates');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c1'),
  null, 'a 7-arg create leaves icon_key NULL -- no icon inferred from name or order');

-- D2. Create WITH a key.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select is(
  (app.menu_upsert_category(
     '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
     '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
     'Drinks', 2, true, 'drinks') ->> 'action'),
  'created', 'an 8-arg create succeeds');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'drinks', 'the chosen key is stored on create');

-- D3. PRESERVE -- the load-bearing case. An edit that OMITS the argument must
--     not disturb the stored key.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true) $$,
  'a legacy 7-arg EDIT of a category that has an icon succeeds');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'drinks', 'OMITTED p_icon_key PRESERVES the stored key (no silent wipe)');
select is((select name from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'Drinks renamed', 'the rest of the edit still applied');

-- D4. Explicit SQL NULL is the same as omitted: preserve.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, null) $$,
  'an explicit NULL p_icon_key is accepted');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'drinks', 'explicit SQL NULL PRESERVES -- NULL never means "clear"');

-- D5. SET to a different key.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, 'coffee') $$, 'changing the key succeeds');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'coffee', 'a valid non-empty key SETS the stored value');

-- D6. Whitespace is trimmed, consistent with the name convention.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, '  ice_cream  ') $$, 'a padded key is accepted');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'ice_cream', 'the key is trimmed before storage');

-- D7. RESET -- empty string clears to NULL ("no custom icon").
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, '') $$, 'an empty-string key is accepted');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  null, 'the empty string RESETS icon_key to NULL');

-- D8. Whitespace-only resets too (it is empty after trimming).
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, '   ') $$, 'a whitespace-only key is accepted as a reset');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  null, 'a whitespace-only key RESETS to NULL');

-- D9. Malformed keys are refused by the RPC.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select throws_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, 'Bad Key') $$,
  '42501', null, 'a key with spaces/uppercase is refused');
select throws_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, '1burger') $$,
  '42501', null, 'a key starting with a digit is refused');
select throws_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, 'aaaaaaaaaabbbbbbbbbbccccccccccddddddddddx') $$,
  '42501', null, 'a 41-character key is refused (max 40)');
reset role;

-- D10. A key this build has never heard of is ACCEPTED. The DB validates shape,
--      not membership of the app's 49-entry registry -- otherwise a newer
--      Dashboard could not save a newer icon.
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select lives_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Drinks renamed', 2, true, 'some_future_icon_v9') $$,
  'a well-formed key that is not in the current app registry is ACCEPTED');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'some_future_icon_v9', 'forward compatibility: shape is validated, membership is not');

-- D11. The table CHECK is defence in depth -- a direct write cannot bypass it.
select throws_ok($$
  update public.menu_categories set icon_key = 'NOT VALID'
   where id = '00000000-0000-0000-0000-0000044000c2' $$,
  '23514', null, 'the CHECK constraint refuses a malformed key written directly');

-- restore a real key for the read assertions below
update public.menu_categories set icon_key = 'coffee'
 where id = '00000000-0000-0000-0000-0000044000c2';

-- ===========================================================================
-- E. TENANCY -- the icon parameter must not become a cross-scope write
-- ===========================================================================
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000044000e2', 'ops044-outsider@example.test');
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000004401000', 'Other Org', 'ops044-other', 'USD');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000044000f2', '00000000-0000-0000-0000-0000044000e2',
   '00000000-0000-0000-0000-000004401000', null, null, 'org_owner');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e2';
-- app.menu_guard RAISES for a caller with no covering membership (it returns
-- false -- the permission_denied envelope -- only for a covering member whose
-- role is below manager), so the outsider is asserted as a raise.
select throws_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
    '00000000-0000-0000-0000-000004400011', '00000000-0000-0000-0000-0000044000c2',
    'Hijacked', 2, true, 'burger') $$,
  '42501', null, 'an outsider cannot set another org''s category icon');
reset role;
select is((select icon_key from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'coffee', 'the refused call left the icon untouched');
select is((select name from public.menu_categories where id = '00000000-0000-0000-0000-0000044000c2'),
  'Drinks renamed', 'the refused call left the name untouched');

-- moving a row to a sibling restaurant via the icon-carrying call is still refused
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0000044000e1';
select throws_ok($$
  select app.menu_upsert_category(
    '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400020',
    '00000000-0000-0000-0000-000004400021', '00000000-0000-0000-0000-0000044000c2',
    'Moved', 2, true, 'burger') $$,
  '42501', null, 'restaurant/branch stay immutable on an icon-carrying update');
reset role;

-- ===========================================================================
-- F. READ EXPOSURE
-- ===========================================================================
-- F1. app.list_menu carries the key, and a NULL stays JSON null.
select is(
  (select (c ->> 'icon_key')
     from jsonb_array_elements(
       app.list_menu('00000000-0000-0000-0000-000004400000',
                     '00000000-0000-0000-0000-000004400010',
                     '00000000-0000-0000-0000-000004400011') -> 'categories') c
    where c ->> 'id' = '00000000-0000-0000-0000-0000044000c2'),
  'coffee', 'list_menu exposes the chosen icon_key');
select is(
  (select jsonb_typeof(c -> 'icon_key')
     from jsonb_array_elements(
       app.list_menu('00000000-0000-0000-0000-000004400000',
                     '00000000-0000-0000-0000-000004400010',
                     '00000000-0000-0000-0000-000004400011') -> 'categories') c
    where c ->> 'id' = '00000000-0000-0000-0000-0000044000c1'),
  'null', 'list_menu renders an unset icon_key as JSON null, not a default key');
select is(
  (select count(*)::int
     from jsonb_array_elements(
       app.list_menu('00000000-0000-0000-0000-000004400000',
                     '00000000-0000-0000-0000-000004400010',
                     '00000000-0000-0000-0000-000004400011') -> 'categories') c),
  2, 'list_menu still returns both categories -- no row dropped by the new key');

-- F2. app.pos_menu carries it too. pos_menu resolves its scope from a PIN
--     session, so build the device + session the same way the POS does.
-- the RF-109 chain pos_menu resolves through: device -> pairing -> session,
-- then a PIN session bound to an employee profile + its membership.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0000044000d1', '00000000-0000-0000-0000-000004400000',
   '00000000-0000-0000-0000-000004400010', '00000000-0000-0000-0000-000004400011', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0000044000d4', '00000000-0000-0000-0000-000004400000',
   '00000000-0000-0000-0000-000004400010', '00000000-0000-0000-0000-000004400011',
   '00000000-0000-0000-0000-0000044000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000044000d5', '00000000-0000-0000-0000-000004400000',
   '00000000-0000-0000-0000-000004400010', '00000000-0000-0000-0000-000004400011',
   '00000000-0000-0000-0000-0000044000d1', '00000000-0000-0000-0000-0000044000d4');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000044000e3', 'ops044-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000044000f3', '00000000-0000-0000-0000-0000044000e3',
   '00000000-0000-0000-0000-000004400000', '00000000-0000-0000-0000-000004400010',
   '00000000-0000-0000-0000-000004400011', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000044000d2', '00000000-0000-0000-0000-000004400000',
   '00000000-0000-0000-0000-000004400010', '00000000-0000-0000-0000-000004400011',
   '00000000-0000-0000-0000-0000044000e3', '00000000-0000-0000-0000-0000044000f3');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000044000d3', '00000000-0000-0000-0000-000004400000',
   '00000000-0000-0000-0000-000004400010', '00000000-0000-0000-0000-000004400011',
   '00000000-0000-0000-0000-0000044000d5', '00000000-0000-0000-0000-0000044000d2',
   '00000000-0000-0000-0000-0000044000f3', now() + interval '1 hour');

select is(
  (select (c ->> 'icon_key')
     from jsonb_array_elements(
       app.pos_menu('00000000-0000-0000-0000-0000044000d3',
                    '00000000-0000-0000-0000-0000044000d1') -> 'categories') c
    where c ->> 'id' = '00000000-0000-0000-0000-0000044000c2'),
  'coffee', 'pos_menu exposes the chosen icon_key');
select is(
  (select jsonb_typeof(c -> 'icon_key')
     from jsonb_array_elements(
       app.pos_menu('00000000-0000-0000-0000-0000044000d3',
                    '00000000-0000-0000-0000-0000044000d1') -> 'categories') c
    where c ->> 'id' = '00000000-0000-0000-0000-0000044000c1'),
  'null', 'pos_menu renders an unset icon_key as JSON null -- NO server-side fallback');
select is(
  (select array_agg(c ->> 'id' order by ord)
     from jsonb_array_elements(
       app.pos_menu('00000000-0000-0000-0000-0000044000d3',
                    '00000000-0000-0000-0000-0000044000d1') -> 'categories')
       with ordinality as t(c, ord)),
  array['00000000-0000-0000-0000-0000044000c1', '00000000-0000-0000-0000-0000044000c2'],
  'pos_menu category ORDER is unchanged (display_order, name)');
select ok(
  (app.pos_menu('00000000-0000-0000-0000-0000044000d3',
                '00000000-0000-0000-0000-0000044000d1')) ?& array[
    'ok', 'categories', 'items', 'sizes', 'variants', 'modifiers',
    'modifier_options', 'currency_code', 'server_ts'],
  'the pos_menu envelope keys are unchanged -- icon_key is purely additive');

select * from finish();
rollback;
