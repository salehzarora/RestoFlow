-- ============================================================================
-- RF-064 — pgTAP: public.sync_pull is a SAFE, narrow wrapper over app.sync_pull
-- ============================================================================
-- public.sync_pull exists, returns jsonb, is SECURITY INVOKER, search_path-locked,
-- callable by `authenticated` but NOT by public/anon. Behaviourally it delegates
-- verbatim to app.sync_pull (the source of truth): same result for a valid PIN
-- session, the same 42501 on a revoked device and an expired PIN, and the same
-- kitchen money redaction (RF-057/RF-059/RF-061 are unchanged — preserved through
-- the wrapper). Finally, NO other sensitive app RPC was given a public sibling.
-- Fixtures inserted as the BYPASSRLS connection role (RF-057/RF-059 pattern); the
-- sync_pull calls run as the connection role (the owner has EXECUTE on app.sync_pull).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(21);

-- ===== fixture (cashier + kitchen on active devices; a revoked device; an =====
-- ===== expired PIN) — based on the RF-059 redaction fixture ===================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf064w-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kds'),
  ('00000000-0000-0000-0000-00000000da13', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'); -- to be revoked
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', 'active'),
  ('00000000-0000-0000-0000-00000000fa13', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da13', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12'),
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da13', '00000000-0000-0000-0000-00000000fa13');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf064w-cashier@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf064w-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),  -- cashier (valid)
  ('00000000-0000-0000-0000-00000000c504', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000ef004', '00000000-0000-0000-0000-00000000ab04', now() + interval '1 hour'),  -- kitchen (valid)
  ('00000000-0000-0000-0000-00000000c5d3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),  -- on the device to revoke (PIN itself valid)
  ('00000000-0000-0000-0000-00000000c5e1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() - interval '1 hour');  -- EXPIRED (past the window)

-- a live active dining table in the same org/restaurant/branch as the PIN session
-- (RESTAURANT-OPERATIONS-V1-001: dine_in submits now REQUIRE a valid table)
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF064-T1', true);

-- a sellable menu category + item for the submitted line (RESTAURANT-OPERATIONS-V1-001:
-- submit_order now requires every payload menu_item_id to be a proven-sellable menu item)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item', 1000, 'USD', 1);

-- a real order WITH a modifier (order_item_modifiers carries price_minor_snapshot)
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-sub','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","option_name_snapshot":"Extra Cheese","price_minor_snapshot":100,"quantity":1}]}]'::jsonb,
  1100,0,0,1100,null);

-- revoke device da13 (direct state change as the owner — RF-061 already tests the
-- revoke RPC; here we only need a revoked-device STATE to prove wrapper parity).
update device_pairings set status='revoked', revoked_at=now() where id='00000000-0000-0000-0000-00000000fa13';
update device_sessions set is_active=false, revoked_at=now() where id='00000000-0000-0000-0000-0000000005a3';

-- ===== (1-7) introspection: existence / type / invoker / search_path / grants =
select has_function('public', 'sync_pull', 'public.sync_pull exists');
select is(
  (select format_type(prorettype, null) from pg_proc where proname='sync_pull' and pronamespace='public'::regnamespace and pronargs=5),
  'jsonb', 'public.sync_pull returns jsonb');
select is(
  (select prosecdef from pg_proc where proname='sync_pull' and pronamespace='public'::regnamespace and pronargs=5),
  false, 'public.sync_pull is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='sync_pull' and p.pronamespace='public'::regnamespace and p.pronargs=5
       and cfg like 'search_path=%')),
  'public.sync_pull has a locked search_path');
select ok(
  not has_function_privilege('public', 'public.sync_pull(uuid, uuid, text[], jsonb, integer)', 'execute'),
  'PUBLIC may NOT execute public.sync_pull (revoked)');
select ok(
  not has_function_privilege('anon', 'public.sync_pull(uuid, uuid, text[], jsonb, integer)', 'execute'),
  'anon may NOT execute public.sync_pull');
select ok(
  has_function_privilege('authenticated', 'public.sync_pull(uuid, uuid, text[], jsonb, integer)', 'execute'),
  'authenticated MAY execute public.sync_pull');

-- ===== (8) equivalence: wrapper result == app.sync_pull result ================
select is(
  public.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders','order_items','order_item_modifiers'],'{}'::jsonb,500),
  app.sync_pull('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000da11',array['orders','order_items','order_item_modifiers'],'{}'::jsonb,500),
  'public.sync_pull delegates verbatim — identical jsonb to app.sync_pull for a valid PIN session');

-- ===== (9) revoked device through the wrapper still raises 42501 ==============
select throws_ok(
  $$ select public.sync_pull('00000000-0000-0000-0000-00000000c5d3','00000000-0000-0000-0000-00000000da13',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'revoked device through public.sync_pull raises 42501 (same as app.sync_pull)');

-- ===== (10) expired PIN through the wrapper still raises 42501 ================
select throws_ok(
  $$ select public.sync_pull('00000000-0000-0000-0000-00000000c5e1','00000000-0000-0000-0000-00000000da11',null,'{}'::jsonb,500) $$,
  '42501', NULL, 'expired PIN through public.sync_pull raises 42501 (same as app.sync_pull)');

-- ===== (11-13) kitchen money redaction preserved through the wrapper ==========
select is(
  (select count(*) from jsonb_array_elements(public.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') as r
   cross join lateral jsonb_object_keys(r) as keys(key) where keys.key ~ '(^|_)minor($|_)')::int,
  0, 'kitchen orders via wrapper: NO key matches the money token (^|_)minor($|_)');
select is(
  (select count(*) from jsonb_array_elements(public.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['order_items'],'{}'::jsonb,500) -> 'changes' -> 'order_items' -> 'rows') as r
   cross join lateral jsonb_object_keys(r) as keys(key) where keys.key ~ '(^|_)minor($|_)')::int,
  0, 'kitchen order_items via wrapper: NO money token key (catches unit_price_minor_snapshot)');
select ok(
  (select bool_and(not (r ? 'receipt_number') and not (r ? 'receipt_provisional_id')) from jsonb_array_elements(public.sync_pull('00000000-0000-0000-0000-00000000c504','00000000-0000-0000-0000-00000000da12',array['orders'],'{}'::jsonb,500) -> 'changes' -> 'orders' -> 'rows') r),
  'kitchen orders via wrapper: receipt_number / receipt_provisional_id still redacted');

-- ===== (14-21) guard: NO other sensitive app RPC has a public sibling =========
select hasnt_function('public', 'submit_order',                  'no public.submit_order wrapper exists (only sync_pull is exposed)');
select hasnt_function('public', 'record_payment',                'no public.record_payment wrapper exists');
select hasnt_function('public', 'void_order',                    'no public.void_order wrapper exists');
select hasnt_function('public', 'apply_discount',                'no public.apply_discount wrapper exists');
select hasnt_function('public', 'open_shift',                    'no public.open_shift wrapper exists (sync_push is now intentionally wrapped under RF-126; open_shift stays dispatcher-only)');
select hasnt_function('public', 'revoke_device',                 'no public.revoke_device wrapper exists');
select hasnt_function('public', 'revoke_employee',               'no public.revoke_employee wrapper exists');
select hasnt_function('public', 'platform_admin_list_organizations', 'no public.platform_admin_list_organizations wrapper exists');

select * from finish();
rollback;
