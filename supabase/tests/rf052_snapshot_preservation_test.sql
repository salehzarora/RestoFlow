-- ============================================================================
-- RF-052 — pgTAP: price-snapshot preservation + total validation (AC#3)
-- ============================================================================
-- The submitted CLIENT snapshots are persisted exactly; the server recomputes
-- totals from those snapshots ONLY (never the live menu) and rejects a tampered
-- client total. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf052s-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf052s@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- submit: 2 x 500 + modifier 100 + a size snapshot; line/subtotal = 1100, grand = 1100
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1',
  '00000000-0000-0000-0000-00000000da11','op-snap','dine_in',null,null,'USD','table note',
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","item_size_snapshot":{"name":"Large","price_delta_minor":0},"modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"modifier_name_snapshot":"Cheese","option_name_snapshot":"Extra"}]}]'::jsonb,
  1100, 0, 0, 1100, null);

-- client snapshots are persisted EXACTLY ------------------------------------- 1-4
select is((select unit_price_minor_snapshot from order_items)::bigint, 500::bigint,  'order_items.unit_price_minor_snapshot persisted exactly (500)');
select is((select menu_item_name_snapshot from order_items)::text, 'Burger',         'order_items.menu_item_name_snapshot persisted exactly');
select is((select price_minor_snapshot from order_item_modifiers)::bigint, 100::bigint, 'order_item_modifiers.price_minor_snapshot persisted exactly (100)');
select is((select option_name_snapshot from order_item_modifiers)::text, 'Extra',     'order_item_modifiers.option_name_snapshot persisted exactly');

-- item_size_snapshot persisted as jsonb -------------------------------------- 5
select is((select item_size_snapshot ->> 'name' from order_items), 'Large', 'order_items.item_size_snapshot persisted as jsonb');

-- totals recomputed from snapshots (never the live menu) --------------------- 6-7
select is((select subtotal_minor from orders)::bigint, 1100::bigint,    'orders.subtotal_minor recomputed from snapshots (2*500 + 100)');
select is((select grand_total_minor from orders)::bigint, 1100::bigint, 'orders.grand_total_minor = subtotal - discount + tax');

-- a tampered client total is rejected ---------------------------------------- 8
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2',
  '00000000-0000-0000-0000-00000000da11','op-tamper','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Extra"}]}]'::jsonb,
  999, 0, 0, 999, null) $$, '42501', NULL,
  'a client subtotal that does not match the snapshot recompute is rejected (anti-tamper)');

-- a CORRECT subtotal but a TAMPERED grand_total is independently rejected ----- 9
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3',
  '00000000-0000-0000-0000-00000000da11','op-grand','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Extra"}]}]'::jsonb,
  1100, 0, 0, 999, null) $$, '42501', NULL,
  'a correct subtotal but a tampered grand_total (1100 vs 999) is rejected (grand_total validation fires independently)');

select * from finish();
rollback;
