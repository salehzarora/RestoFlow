-- ============================================================================
-- RF-052 — pgTAP: integer-minor money enforcement (AC#4)
-- ============================================================================
-- The RPC rejects non-integer, decimal, negative, and non-numeric money values
-- in the payload (D-007; no float money anywhere). A clean integer payload
-- succeeds. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf052m-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf052m@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- ===== fractional unit price is rejected ==================================== 1
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1',
  '00000000-0000-0000-0000-00000000da11','op-frac','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":12.5,"menu_item_name_snapshot":"Item"}]'::jsonb,
  13,0,0,13,null) $$, '42501', NULL,
  'a fractional unit_price_minor_snapshot (12.5) is rejected (no float money)');

-- ===== negative unit price is rejected ====================================== 2
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2',
  '00000000-0000-0000-0000-00000000da11','op-neg','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":-100,"menu_item_name_snapshot":"Item"}]'::jsonb,
  0,0,0,0,null) $$, '42501', NULL,
  'a negative unit_price_minor_snapshot is rejected (money parse, non-negative integer only)');

-- ===== fractional modifier price is rejected ================================ 3
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3',
  '00000000-0000-0000-0000-00000000da11','op-mfrac','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":9.99,"quantity":1,"option_name_snapshot":"X"}]}]'::jsonb,
  1010,0,0,1010,null) $$, '42501', NULL,
  'a fractional modifier price_minor_snapshot (9.99) is rejected');

-- ===== non-numeric money is rejected ======================================== 4
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d4',
  '00000000-0000-0000-0000-00000000da11','op-str','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":"1000","menu_item_name_snapshot":"Item"}]'::jsonb,
  1000,0,0,1000,null) $$, '42501', NULL,
  'a non-numeric (string) money value is rejected');

-- ===== a clean integer-minor payload succeeds (control) ===================== 5
select ok(
  (app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d5',
    '00000000-0000-0000-0000-00000000da11','op-ok','dine_in',null,null,'USD',null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":3,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
    3000,0,0,3000,null) ->> 'order_id') is not null,
  'a clean integer-minor payload submits successfully');

-- ===== an out-of-range quantity yields a clean 42501 (not a raw 22003 cast) == 6
select throws_ok($$ select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d6',
  '00000000-0000-0000-0000-00000000da11','op-bigqty','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":9999999999,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,
  0,0,0,0,null) $$, '42501', NULL,
  'an out-of-range quantity (> int max) is rejected with a clean 42501');

select * from finish();
rollback;
