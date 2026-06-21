-- ============================================================================
-- RF-052 — pgTAP: idempotency (AC#1)
-- ============================================================================
-- Submitting the same (device_id, local_operation_id) twice creates exactly ONE
-- order and returns the same order_id (idempotency_replay=true on the second).
-- Replay happens AFTER full validation (RF051-B1), scoped to (org, device,
-- local_operation_id). Fixtures inserted as the BYPASSRLS connection role; the
-- RPC is SECURITY DEFINER (derives actor/scope from the PIN session).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(9);

-- ---- Fixtures: a valid PIN-session chain (cashier on a paired+active device) -
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf052i-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'rf052i@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- ---- first submit: 1 item (qty 2 @ 500) + 1 modifier (100) => line/subtotal 1100
select app.submit_order(
  '00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-00000000a0d1',
  '00000000-0000-0000-0000-00000000da11', 'op-1', 'takeaway', null, null, 'USD', null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Cheese"}]}]'::jsonb,
  1100, 0, 0, 1100, null);

select is((select count(*) from orders)::int, 1,               'first submit created exactly one order');                       -- 1
select is((select count(*) from order_items)::int, 1,          'first submit created exactly one order_item');                  -- 2
select is((select count(*) from order_item_modifiers)::int, 1, 'first submit created exactly one order_item_modifier');         -- 3
select is((select status from orders)::text, 'submitted',      'order persisted at status submitted');                          -- 4
select is((select status from order_items)::text, 'pending',   'order_item persisted at status pending (route_to_kitchen owns queued)'); -- 5

-- ---- second submit: SAME (device_id, local_operation_id) => idempotent replay
select is(
  (app.submit_order(
    '00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-00000000a0d1',
    '00000000-0000-0000-0000-00000000da11', 'op-1', 'takeaway', null, null, 'USD', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Cheese"}]}]'::jsonb,
    1100, 0, 0, 1100, null) ->> 'idempotency_replay')::boolean,
  true, 'second submit with the same (device_id, local_operation_id) is an idempotent replay');                                  -- 6
select is(
  (app.submit_order(
    '00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-00000000a0d1',
    '00000000-0000-0000-0000-00000000da11', 'op-1', 'takeaway', null, null, 'USD', null,
    '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":2,"unit_price_minor_snapshot":500,"menu_item_name_snapshot":"Burger","modifiers":[{"modifier_option_id":"00000000-0000-0000-0000-0000000000f2","price_minor_snapshot":100,"quantity":1,"option_name_snapshot":"Cheese"}]}]'::jsonb,
    1100, 0, 0, 1100, null) ->> 'order_id')::uuid,
  '00000000-0000-0000-0000-00000000a0d1'::uuid, 'replay returns the same order_id');                                            -- 7
select is((select count(*) from orders)::int, 1,      'replay created NO duplicate order');                                     -- 8
select is((select count(*) from order_items)::int, 1, 'replay created NO duplicate order_item');                                -- 9

select * from finish();
rollback;
