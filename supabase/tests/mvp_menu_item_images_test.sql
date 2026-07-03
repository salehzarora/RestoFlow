-- ============================================================================
-- MVP (menu/media sprint) — pgTAP: menu item images end to end.
-- Covers: menu_items.image_path schema + blank CHECK; menu_upsert_item 13-arg
-- roundtrip (set / legacy-12-arg-clears / blank-normalizes / re-set) with a
-- SINGLE overload (PostgREST-unambiguous) + grants; list_menu + pos_menu expose
-- image_path; kitchen_staff pos_menu OMITS the key (T-014, the T-003 omit
-- pattern); redeem_device_pairing still works and now records
-- device_sessions.auth_user_id; and the NEW storage.objects device SELECT
-- policy matrix (own-org POS CAN read, KDS CANNOT, other-org POS CANNOT,
-- revoked session CANNOT, unbound principal CANNOT). RISK R-003 — the device
-- policy is PENDING the standing human RLS/security sign-off.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(43);

-- ===== fixtures (BYPASSRLS connection role) =================================
insert into organizations (id, name, slug, default_currency) values
  ('77000000-0000-0000-0000-0000000000a0', 'Org A', 'mvpimg-a', 'USD'),
  ('77000000-0000-0000-0000-0000000000b0', 'Org B', 'mvpimg-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('77000000-0000-0000-0000-0000000000b1', '77000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('77000000-0000-0000-0000-00000000a1b0', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('77000000-0000-0000-0000-00000000b1a0', '77000000-0000-0000-0000-0000000000b0', '77000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('77000000-0000-0000-0000-00000000ee01', 'mvpimg-owner@example.test'),
  ('77000000-0000-0000-0000-00000000ee02', 'mvpimg-cashier@example.test'),
  ('77000000-0000-0000-0000-00000000ee03', 'mvpimg-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('77000000-0000-0000-0000-00000000ab01', '77000000-0000-0000-0000-00000000ee01', '77000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('77000000-0000-0000-0000-00000000ab02', '77000000-0000-0000-0000-00000000ee02', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', 'cashier'),
  ('77000000-0000-0000-0000-00000000ab03', '77000000-0000-0000-0000-00000000ee03', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('77000000-0000-0000-0000-0000000ef002', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000ee02', '77000000-0000-0000-0000-00000000ab02'),
  ('77000000-0000-0000-0000-0000000ef003', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000ee03', '77000000-0000-0000-0000-00000000ab03');

-- devices: POS + KDS + a revoked-session POS in org A (branch A1a); a POS to be
-- redeemed (posX); a POS in org B.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('77000000-0000-0000-0000-00000000d001', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', 'pos'),
  ('77000000-0000-0000-0000-00000000d002', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', 'kds'),
  ('77000000-0000-0000-0000-00000000d003', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', 'pos'),
  ('77000000-0000-0000-0000-00000000d004', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', 'pos'),
  ('77000000-0000-0000-0000-00000000d00b', '77000000-0000-0000-0000-0000000000b0', '77000000-0000-0000-0000-0000000000b1', '77000000-0000-0000-0000-00000000b1a0', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('77000000-0000-0000-0000-00000000fa01', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d001', 'active'),
  ('77000000-0000-0000-0000-00000000fa02', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d002', 'active'),
  ('77000000-0000-0000-0000-00000000fa03', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d003', 'active'),
  ('77000000-0000-0000-0000-00000000fb0b', '77000000-0000-0000-0000-0000000000b0', '77000000-0000-0000-0000-0000000000b1', '77000000-0000-0000-0000-00000000b1a0', '77000000-0000-0000-0000-00000000d00b', 'active');
-- a redeemable code for posX (hash-only, RF-161 shape).
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, enrollment_code_hash, code_expires_at) values
  ('77000000-0000-0000-0000-00000000fa04', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d004', 'code_issued', app.hash_provisioning_secret('mvpimg-code-1'), now() + interval '1 hour');

-- device sessions BOUND to anonymous auth principals (the new binding column):
-- P1 = live POS (org A), K1 = live KDS (org A), P2 = live POS (org B),
-- R1 = REVOKED POS session (org A).
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, auth_user_id, is_active, revoked_at) values
  ('77000000-0000-0000-0000-000000005a01', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d001', '77000000-0000-0000-0000-00000000fa01', '77000000-0000-0000-0000-00000000a801', true,  null),
  ('77000000-0000-0000-0000-000000005a02', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d002', '77000000-0000-0000-0000-00000000fa02', '77000000-0000-0000-0000-00000000a802', true,  null),
  ('77000000-0000-0000-0000-000000005a03', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-00000000d003', '77000000-0000-0000-0000-00000000fa03', '77000000-0000-0000-0000-00000000a804', false, now()),
  ('77000000-0000-0000-0000-000000005b0b', '77000000-0000-0000-0000-0000000000b0', '77000000-0000-0000-0000-0000000000b1', '77000000-0000-0000-0000-00000000b1a0', '77000000-0000-0000-0000-00000000d00b', '77000000-0000-0000-0000-00000000fb0b', '77000000-0000-0000-0000-00000000a803', true,  null);

-- PIN sessions for the pos_menu reads (cashier on the POS, kitchen on the KDS).
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('77000000-0000-0000-0000-00000000c501', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-000000005a01', '77000000-0000-0000-0000-0000000ef002', '77000000-0000-0000-0000-00000000ab02', now() + interval '1 hour'),
  ('77000000-0000-0000-0000-00000000c503', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', '77000000-0000-0000-0000-00000000a1a0', '77000000-0000-0000-0000-000000005a02', '77000000-0000-0000-0000-0000000ef003', '77000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- menu: one restaurant-wide category; item2 seeded WITHOUT an image (item1 is
-- created through the RPC below).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('77000000-0000-0000-0000-00000000ca01', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', null, 'Cat A');
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('77000000-0000-0000-0000-00000000e002', '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', null, '77000000-0000-0000-0000-00000000ca01', 'No Pic Cola', 1500, 'USD');

-- storage objects for the device policy matrix (BYPASSRLS seed).
insert into storage.objects (bucket_id, name) values
  ('menu-images', '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/77000000-0000-0000-0000-00000000a1a0/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0001.png'), -- objA_branch (A1a)
  ('menu-images', '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/global/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0002.png'),                                  -- objA_global
  ('menu-images', '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/77000000-0000-0000-0000-00000000a1b0/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0003.png'), -- objA_sibling (A1b)
  ('menu-images', '77000000-0000-0000-0000-0000000000b0/77000000-0000-0000-0000-0000000000b1/77000000-0000-0000-0000-00000000b1a0/menu_item/77000000-0000-0000-0000-00000000e00b/77000000-0000-0000-0000-0000000f0004.png'); -- objB

-- ===== (1-4) schema: menu_items.image_path ===================================
select has_column('public', 'menu_items', 'image_path', 'menu_items.image_path exists');
select col_is_null('public', 'menu_items', 'image_path', 'menu_items.image_path is nullable (no image = null)');
select col_type_is('public', 'menu_items', 'image_path', 'text', 'menu_items.image_path is text');
select throws_ok(
  $$ insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, image_path)
     values ('77000000-0000-0000-0000-0000000000a0','77000000-0000-0000-0000-0000000000a1',null,'77000000-0000-0000-0000-00000000ca01','Blank Pic', 100, 'USD', '   ') $$,
  '23514', NULL, 'menu_items.image_path rejects a blank (whitespace-only) value (check_violation)');

-- ===== (5-6) schema: device_sessions.auth_user_id ============================
select has_column('public', 'device_sessions', 'auth_user_id', 'device_sessions.auth_user_id exists (storage-policy binding)');
select col_is_null('public', 'device_sessions', 'auth_user_id', 'device_sessions.auth_user_id is nullable (legacy/GUC sessions have none)');

-- ===== (7-10) menu_upsert_item: ONE overload + grants ========================
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'app' and p.proname = 'menu_upsert_item'), 1,
  'exactly ONE app.menu_upsert_item exists (no overload — PostgREST-unambiguous)');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'menu_upsert_item'), 1,
  'exactly ONE public.menu_upsert_item wrapper exists');
select ok(
  has_function_privilege('authenticated', 'public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text)', 'execute'),
  'authenticated MAY execute the 13-arg public.menu_upsert_item');
select ok(
  not has_function_privilege('anon', 'public.menu_upsert_item(uuid, uuid, uuid, uuid, uuid, text, text, bigint, text, uuid, integer, boolean, text)', 'execute'),
  'anon may NOT execute the 13-arg public.menu_upsert_item');

-- ===== (11-17) image_path roundtrip through menu_upsert_item =================
set local role authenticated;
set local app.current_app_user_id = '77000000-0000-0000-0000-00000000ee01';  -- org_owner
select is(
  (app.menu_upsert_item('77000000-0000-0000-0000-0000000000a0','77000000-0000-0000-0000-0000000000a1',null,'77000000-0000-0000-0000-00000000e001','77000000-0000-0000-0000-00000000ca01','Pic Burger',null,5000,'USD',null,0,true,
     '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/77000000-0000-0000-0000-00000000a1a0/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0001.png') ->> 'action'),
  'created', 'creating an item with p_image_path succeeds');
reset role;
select is(
  (select image_path from menu_items where id = '77000000-0000-0000-0000-00000000e001'),
  '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/77000000-0000-0000-0000-00000000a1a0/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0001.png',
  'the created row stores the passed image_path');
set local role authenticated;
set local app.current_app_user_id = '77000000-0000-0000-0000-00000000ee01';
select is(
  (app.menu_upsert_item('77000000-0000-0000-0000-0000000000a0','77000000-0000-0000-0000-0000000000a1',null,'77000000-0000-0000-0000-00000000e001','77000000-0000-0000-0000-00000000ca01','Pic Burger',null,5000,'USD',null,0,true) ->> 'action'),
  'updated', 'the legacy 12-arg positional call still binds (p_image_path defaults to null)');
reset role;
select is(
  (select image_path from menu_items where id = '77000000-0000-0000-0000-00000000e001'),
  null::text, 'omitting p_image_path (null) CLEARS the stored image (the editor sends full state)');
set local role authenticated;
set local app.current_app_user_id = '77000000-0000-0000-0000-00000000ee01';
select is(
  (app.menu_upsert_item('77000000-0000-0000-0000-0000000000a0','77000000-0000-0000-0000-0000000000a1',null,'77000000-0000-0000-0000-00000000e001','77000000-0000-0000-0000-00000000ca01','Pic Burger',null,5000,'USD',null,0,true,'   ') ->> 'ok')::boolean,
  true, 'a blank p_image_path normalizes to clear (never a crash, never a blank row)');
select is(
  (app.menu_upsert_item('77000000-0000-0000-0000-0000000000a0','77000000-0000-0000-0000-0000000000a1',null,'77000000-0000-0000-0000-00000000e001','77000000-0000-0000-0000-00000000ca01','Pic Burger',null,5000,'USD',null,0,true,
     '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/global/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0002.png') ->> 'action'),
  'updated', 'updating with a new p_image_path succeeds (replace)');
reset role;
select is(
  (select image_path from menu_items where id = '77000000-0000-0000-0000-00000000e001'),
  '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/global/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0002.png',
  'the replaced image_path is stored');

-- ===== (18-20) list_menu exposes image_path ==================================
set local role authenticated;
set local app.current_app_user_id = '77000000-0000-0000-0000-00000000ee01';
create temp table t_list as select app.list_menu(
  '77000000-0000-0000-0000-0000000000a0', '77000000-0000-0000-0000-0000000000a1', null) as res;
reset role;
select is(
  (select e->>'image_path' from t_list, jsonb_array_elements(res->'items') e
    where e->>'id' = '77000000-0000-0000-0000-00000000e001'),
  '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/global/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0002.png',
  'list_menu item rows expose image_path');
select ok(
  (select (e ? 'image_path') and (e->>'image_path') is null from t_list, jsonb_array_elements(res->'items') e
    where e->>'id' = '77000000-0000-0000-0000-00000000e002'),
  'an item WITHOUT an image carries the image_path key with null (uniform parse)');
select ok(
  (select bool_and(e ? 'image_path') from t_list, jsonb_array_elements(res->'items') e),
  'every list_menu item row carries the image_path key');

-- ===== (21-24) pos_menu: cashier gets image_path; kitchen key is OMITTED =====
select is(
  (select it->>'image_path'
     from jsonb_array_elements(app.pos_menu('77000000-0000-0000-0000-00000000c501', '77000000-0000-0000-0000-00000000d001') -> 'items') it
    where it->>'name' = 'Pic Burger'),
  '77000000-0000-0000-0000-0000000000a0/77000000-0000-0000-0000-0000000000a1/global/menu_item/77000000-0000-0000-0000-00000000e001/77000000-0000-0000-0000-0000000f0002.png',
  'the cashier pos_menu item carries image_path');
select ok(
  (select (it ? 'image_path')
     from jsonb_array_elements(app.pos_menu('77000000-0000-0000-0000-00000000c501', '77000000-0000-0000-0000-00000000d001') -> 'items') it
    where it->>'name' = 'No Pic Cola'),
  'a cashier item without an image still carries the image_path key (null)');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(app.pos_menu('77000000-0000-0000-0000-00000000c503', '77000000-0000-0000-0000-00000000d002') -> 'items') it
    cross join lateral jsonb_object_keys(it) k
    where k = 'image_path'),
  'NO kitchen_staff pos_menu item carries the image_path key (omitted, not nulled — T-014)');
select is(
  (select count(*)::int from jsonb_array_elements(app.pos_menu('77000000-0000-0000-0000-00000000c503', '77000000-0000-0000-0000-00000000d002') -> 'items') it),
  2, 'the kitchen session still receives both items (menu usable, image-free)');

-- ===== (25-28) redeem still works and records auth_user_id ===================
create temp table t_redeem (r jsonb);
grant select, insert on t_redeem to authenticated;
set local role authenticated;
set local app.current_app_user_id = '';
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a805"}';
insert into t_redeem select app.redeem_device_pairing('mvpimg-code-1', 'pos');
select is((select (r->>'ok')::boolean from t_redeem), true,
  'redeem_device_pairing still succeeds after the DROP+recreate');
select isnt((select r->>'session_token' from t_redeem), null,
  'redeem still returns the one-time session token');
reset role;
select is(
  (select auth_user_id from device_sessions where id = (select (r->>'device_session_id')::uuid from t_redeem)),
  '77000000-0000-0000-0000-00000000a805'::uuid,
  'the minted device session records auth_user_id = auth.uid() (the storage-policy binding)');
set local role authenticated;
set local app.current_app_user_id = '';
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a805"}';
select is(
  (app.restore_device_session('77000000-0000-0000-0000-00000000d004', (select r->>'session_token' from t_redeem)) ->> 'device_session_id'),
  (select r->>'device_session_id' from t_redeem),
  'restore_device_session still restores the redeemed session (behavior preserved)');
reset role;

-- ===== (29-34) device storage policy — structure =============================
select is(
  (select cmd from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_device_select'),
  'SELECT', 'menu_images_device_select exists and is a SELECT policy');
select is(
  (select roles::text[] from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_device_select'),
  array['authenticated'], 'the device policy targets authenticated ONLY (no anon/public/service_role)');
select ok(
  (select qual from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_device_select')
    like '%menu-images%'
  and (select qual from pg_policies where schemaname='storage' and tablename='objects' and policyname='menu_images_device_select')
    like '%device_can_read_menu_image%',
  'the device policy is pinned to the menu-images bucket and wires app.device_can_read_menu_image');
select ok(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='app' and p.proname='device_can_read_menu_image'),
  'app.device_can_read_menu_image is SECURITY DEFINER');
select ok(
  (select p.proconfig @> array['search_path=""'] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='app' and p.proname='device_can_read_menu_image'),
  'app.device_can_read_menu_image runs with search_path = (empty)');
select ok(
  has_function_privilege('authenticated', 'app.device_can_read_menu_image(text)', 'execute')
  and not has_function_privilege('anon', 'app.device_can_read_menu_image(text)', 'execute'),
  'authenticated (and NOT anon) may execute the device read helper');

-- ===== (35-43) device storage policy — behavior matrix =======================
set local role authenticated;
set local app.current_app_user_id = '';           -- identity comes from the JWT only
set local app.current_organization_id = '';       -- the org GUC is ABSENT (storage context)

-- P1: the live, bound POS device session of org A / branch A1a.
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a801"}';
select is((select count(*)::int from storage.objects where name like '%77000000-0000-0000-0000-0000000f0001.png'), 1,
  'a live POS device session CAN read its own-branch menu image');
select is((select count(*)::int from storage.objects where name like '%77000000-0000-0000-0000-0000000f0002.png'), 1,
  'a live POS device session CAN read a restaurant-scoped (global) menu image');
select is((select count(*)::int from storage.objects where name like '%77000000-0000-0000-0000-0000000f0003.png'), 0,
  'a POS device session CANNOT read a sibling-branch image');
select is((select count(*)::int from storage.objects where name like '%77000000-0000-0000-0000-0000000f0004.png'), 0,
  'a POS device session CANNOT read another organization''s image (R-003)');

-- K1: the live, bound KDS device session (kitchen surface — EXCLUDED, T-014).
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a802"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  'a KDS device session sees ZERO menu images (device_type=pos only — T-014)');

-- P2: the live POS device session of ORG B.
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a803"}';
select is((select count(*)::int from storage.objects where name like '%77000000-0000-0000-0000-0000000f0001.png'), 0,
  'an OTHER-org POS device session sees ZERO org A images (cross-org)');
select is((select count(*)::int from storage.objects where name like '%77000000-0000-0000-0000-0000000f0004.png'), 1,
  'the org B POS device session CAN read its own org''s image (control)');

-- R1: a REVOKED (bound) POS device session.
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a804"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  'a revoked device session sees ZERO menu images (liveness gate)');

-- N1: an authenticated principal with NO device-session binding (the legacy /
-- pre-column shape: auth_user_id is null everywhere for it).
set local request.jwt.claims = '{"sub":"77000000-0000-0000-0000-00000000a806"}';
select is((select count(*)::int from storage.objects where bucket_id = 'menu-images'), 0,
  'an unbound anonymous principal (legacy session shape) sees ZERO menu images');

reset role;
select * from finish();
rollback;
