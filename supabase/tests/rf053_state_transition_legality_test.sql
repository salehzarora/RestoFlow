-- ============================================================================
-- RF-053 — pgTAP: void state-transition legality + cascade (AC#3, D-024)
-- ============================================================================
-- void_order succeeds from submitted/accepted/preparing/ready/served and is
-- rejected from draft/completed/cancelled/voided; voiding an order cascades its
-- items to voided. Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf053s-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf053s-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- one order per state (connection-role inserts can set any legal status value)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-0000000d5b01', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'o-sub'),
  ('00000000-0000-0000-0000-0000000d5b02', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','accepted','USD',1000,0,0,1000,'o-acc'),
  ('00000000-0000-0000-0000-0000000d5b03', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','preparing','USD',1000,0,0,1000,'o-prep'),
  ('00000000-0000-0000-0000-0000000d5b04', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','ready','USD',1000,0,0,1000,'o-ready'),
  ('00000000-0000-0000-0000-0000000d5b05', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','served','USD',1000,0,0,1000,'o-served'),
  ('00000000-0000-0000-0000-0000000d5b06', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','draft','USD',1000,0,0,1000,'o-draft'),
  ('00000000-0000-0000-0000-0000000d5b07', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','completed','USD',1000,0,0,1000,'o-comp'),
  ('00000000-0000-0000-0000-0000000d5b08', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','cancelled','USD',1000,0,0,1000,'o-canc'),
  ('00000000-0000-0000-0000-0000000d5b09', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','voided','USD',1000,0,0,1000,'o-void');
-- an item on the submitted order (for the cascade assertion)
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor) values
  ('00000000-0000-0000-0000-000000005101', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000d5b01','00000000-0000-0000-0000-0000000000f1','pending',2,'Burger',500,0,1000);

-- legal source states -> void succeeds -------------------------------------- 1-5
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b01','00000000-0000-0000-0000-00000000da11','o-sub','x', null) ->> 'status'), 'voided', 'void from submitted succeeds');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b02','00000000-0000-0000-0000-00000000da11','o-acc','x', null) ->> 'status'), 'voided', 'void from accepted succeeds');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b03','00000000-0000-0000-0000-00000000da11','o-prep','x', null) ->> 'status'), 'voided', 'void from preparing succeeds');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b04','00000000-0000-0000-0000-00000000da11','o-ready','x', null) ->> 'status'), 'voided', 'void from ready succeeds');
select is((app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b05','00000000-0000-0000-0000-00000000da11','o-served','x', null) ->> 'status'), 'voided', 'void from served succeeds');

-- forbidden source states -> rejected --------------------------------------- 6-9
select throws_ok($$ select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b06','00000000-0000-0000-0000-00000000da11','o-draft','x', null) $$, '42501', NULL, 'void from draft rejected');
select throws_ok($$ select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b07','00000000-0000-0000-0000-00000000da11','o-comp','x', null) $$, '42501', NULL, 'void from completed rejected (D-024 terminal)');
select throws_ok($$ select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b08','00000000-0000-0000-0000-00000000da11','o-canc','x', null) $$, '42501', NULL, 'void from cancelled rejected');
select throws_ok($$ select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000d5b09','00000000-0000-0000-0000-00000000da11','o-void','x', null) $$, '42501', NULL, 'void from voided rejected');

-- cascade: voiding the submitted order voided its item ----------------------- 10
select is((select status from order_items where id='00000000-0000-0000-0000-000000005101')::text, 'voided', 'voiding the order cascaded its order_item to voided');

-- the rejected (forbidden-state) orders were NOT mutated ---------------------- 11
select is(
  (select count(*) from orders
     where id in ('00000000-0000-0000-0000-0000000d5b06','00000000-0000-0000-0000-0000000d5b07','00000000-0000-0000-0000-0000000d5b08','00000000-0000-0000-0000-0000000d5b09')
       and status in ('draft','completed','cancelled','voided'))::int,
  4, 'each forbidden-state order retained its original status (the rejected void changed nothing)');

select * from finish();

rollback;
