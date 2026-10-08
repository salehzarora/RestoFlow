-- ORDER-EDIT-001B — app.pin_session_capabilities (+ its public wrapper): the
-- advisory capabilities.void_order and the top-level branch_features
-- {order_edit_enabled, order_edit_finished_food_manager_only} (API_CONTRACT
-- §4.30b, §4.45.10; DECISION D-043; migration 20261008190000). Pins: the
-- void_order value per role and per cashier permissions shape, its parity with
-- the deny-only resolver AND with the real enforcement (app.void_order through
-- sync_push order.void, app.edit_order's removal gate through order.edit); the
-- branch switches mirroring the session's OWN branch row for every role (FALSE
-- when the branch row is soft-deleted, the probe still ok); the exact success
-- and failure envelopes; and the unchanged volatility / DEFINER / search_path /
-- ACL. Read-only: no audit row.
begin;
set local search_path to extensions, public, pg_catalog;

select plan(41);

-- ===== fixture ==============================================================
-- Org A: branch AB (KDS mode, both switches at their DEFAULT false/false) with
-- a POS (d1) and a KDS (d2); branch AC (both switches ON; soft-deleted later)
-- with a POS (d3). Org B: branch BB (editing ON, finished-food OFF), POS d4.
insert into organizations (id, name, slug, default_currency) values
  ('b1c00000-0000-0000-0000-0000000000a0', 'Org Caps 001B', 'org-caps-001b-a', 'ILS'),
  ('b1c00000-0000-0000-0000-0000000000b0', 'Org Caps 001B B', 'org-caps-001b-b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000a0', 'Rest Caps A'),
  ('b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000b0', 'Rest Caps B');
insert into branches (id, organization_id, restaurant_id, name) values
  ('b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'Branch Caps AB');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled, order_edit_finished_food_manager_only) values
  ('b1c00000-0000-0000-0000-0000000000ac', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'Branch Caps AC', true, true),
  ('b1c00000-0000-0000-0000-0000000000bb', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'Branch Caps BB', true, false);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b1c00000-0000-0000-0000-0000000000d1', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'pos'),
  ('b1c00000-0000-0000-0000-0000000000d2', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'kds'),
  ('b1c00000-0000-0000-0000-0000000000d3', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'pos'),
  ('b1c00000-0000-0000-0000-0000000000d4', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000bb', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b1c00000-0000-0000-0000-0000000000f1', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-0000000000d1', 'active'),
  ('b1c00000-0000-0000-0000-0000000000f2', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-0000000000d2', 'active'),
  ('b1c00000-0000-0000-0000-0000000000f3', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'b1c00000-0000-0000-0000-0000000000d3', 'active'),
  ('b1c00000-0000-0000-0000-0000000000f4', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000bb', 'b1c00000-0000-0000-0000-0000000000d4', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-0000000000d1', 'b1c00000-0000-0000-0000-0000000000f1'),
  ('b1c00000-0000-0000-0000-00000000005b', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-0000000000d2', 'b1c00000-0000-0000-0000-0000000000f2'),
  ('b1c00000-0000-0000-0000-00000000005c', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'b1c00000-0000-0000-0000-0000000000d3', 'b1c00000-0000-0000-0000-0000000000f3'),
  ('b1c00000-0000-0000-0000-00000000005d', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000bb', 'b1c00000-0000-0000-0000-0000000000d4', 'b1c00000-0000-0000-0000-0000000000f4');
insert into app_users (id, email) values
  ('b1c00000-0000-0000-0000-000000000061', 'caps001b-manager@example.test'),
  ('b1c00000-0000-0000-0000-000000000062', 'caps001b-rest-owner@example.test'),
  ('b1c00000-0000-0000-0000-000000000063', 'caps001b-org-owner@example.test'),
  ('b1c00000-0000-0000-0000-000000000064', 'caps001b-cashier-default@example.test'),
  ('b1c00000-0000-0000-0000-000000000065', 'caps001b-cashier-bool-false@example.test'),
  ('b1c00000-0000-0000-0000-000000000066', 'caps001b-cashier-str-true@example.test'),
  ('b1c00000-0000-0000-0000-000000000067', 'caps001b-cashier-str-false@example.test'),
  ('b1c00000-0000-0000-0000-000000000068', 'caps001b-kitchen@example.test'),
  ('b1c00000-0000-0000-0000-000000000069', 'caps001b-accountant@example.test'),
  ('b1c00000-0000-0000-0000-00000000006a', 'caps001b-cashier-array@example.test'),
  ('b1c00000-0000-0000-0000-00000000006c', 'caps001b-cashier-ac@example.test'),
  ('b1c00000-0000-0000-0000-00000000006d', 'caps001b-cashier-b@example.test');
-- void_order is DENY-ONLY / DEFAULT-ON for a cashier: the key's PRESENCE denies.
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('b1c00000-0000-0000-0000-000000000071', 'b1c00000-0000-0000-0000-000000000061', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000072', 'b1c00000-0000-0000-0000-000000000062', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', null, 'restaurant_owner', '{}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000073', 'b1c00000-0000-0000-0000-000000000063', 'b1c00000-0000-0000-0000-0000000000a0', null, null, 'org_owner', '{}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000074', 'b1c00000-0000-0000-0000-000000000064', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000075', 'b1c00000-0000-0000-0000-000000000065', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'cashier', '{"void_order": false}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000076', 'b1c00000-0000-0000-0000-000000000066', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'cashier', '{"void_order": "true"}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000077', 'b1c00000-0000-0000-0000-000000000067', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'cashier', '{"void_order": "false"}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000078', 'b1c00000-0000-0000-0000-000000000068', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb),
  ('b1c00000-0000-0000-0000-000000000079', 'b1c00000-0000-0000-0000-000000000069', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'accountant', '{}'::jsonb),
  ('b1c00000-0000-0000-0000-00000000007a', 'b1c00000-0000-0000-0000-00000000006a', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'cashier', '[]'::jsonb),
  ('b1c00000-0000-0000-0000-00000000007c', 'b1c00000-0000-0000-0000-00000000006c', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'cashier', '{"void_order": "false"}'::jsonb),
  ('b1c00000-0000-0000-0000-00000000007d', 'b1c00000-0000-0000-0000-00000000006d', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000bb', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('b1c00000-0000-0000-0000-000000000081', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000061', 'b1c00000-0000-0000-0000-000000000071', 'Mia Manager'),
  ('b1c00000-0000-0000-0000-000000000082', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', null, 'b1c00000-0000-0000-0000-000000000062', 'b1c00000-0000-0000-0000-000000000072', 'Rae Owner'),
  ('b1c00000-0000-0000-0000-000000000083', 'b1c00000-0000-0000-0000-0000000000a0', null, null, 'b1c00000-0000-0000-0000-000000000063', 'b1c00000-0000-0000-0000-000000000073', 'Ora Owner'),
  ('b1c00000-0000-0000-0000-000000000084', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000064', 'b1c00000-0000-0000-0000-000000000074', 'Cal Cashier'),
  ('b1c00000-0000-0000-0000-000000000085', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000065', 'b1c00000-0000-0000-0000-000000000075', 'Bo Cashier'),
  ('b1c00000-0000-0000-0000-000000000086', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000066', 'b1c00000-0000-0000-0000-000000000076', 'Tru Cashier'),
  ('b1c00000-0000-0000-0000-000000000087', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000067', 'b1c00000-0000-0000-0000-000000000077', 'Fal Cashier'),
  ('b1c00000-0000-0000-0000-000000000088', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000068', 'b1c00000-0000-0000-0000-000000000078', 'Kit Kitchen'),
  ('b1c00000-0000-0000-0000-000000000089', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-000000000069', 'b1c00000-0000-0000-0000-000000000079', 'Acc Accountant'),
  ('b1c00000-0000-0000-0000-00000000008a', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000006a', 'b1c00000-0000-0000-0000-00000000007a', 'Arr Cashier'),
  ('b1c00000-0000-0000-0000-00000000008c', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'b1c00000-0000-0000-0000-00000000006c', 'b1c00000-0000-0000-0000-00000000007c', 'Ace Cashier'),
  ('b1c00000-0000-0000-0000-00000000008d', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000bb', 'b1c00000-0000-0000-0000-00000000006d', 'b1c00000-0000-0000-0000-00000000007d', 'Bea Cashier');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at, is_active) values
  -- branch AB, POS d1: manager 91, restaurant_owner 92, org_owner 93, cashiers
  -- default 94 / boolean-false 95 / "true" 96 / "false" 97 / non-object 9a,
  -- accountant 99; inactive 9e and expired 9f (the default cashier)
  ('b1c00000-0000-0000-0000-000000000091', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000081', 'b1c00000-0000-0000-0000-000000000071', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000092', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000082', 'b1c00000-0000-0000-0000-000000000072', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000093', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000083', 'b1c00000-0000-0000-0000-000000000073', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000094', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000084', 'b1c00000-0000-0000-0000-000000000074', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000095', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000085', 'b1c00000-0000-0000-0000-000000000075', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000096', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000086', 'b1c00000-0000-0000-0000-000000000076', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000097', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000087', 'b1c00000-0000-0000-0000-000000000077', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-000000000099', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000089', 'b1c00000-0000-0000-0000-000000000079', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-00000000009a', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-00000000008a', 'b1c00000-0000-0000-0000-00000000007a', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-00000000009e', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000084', 'b1c00000-0000-0000-0000-000000000074', now() + interval '1 hour', false),
  ('b1c00000-0000-0000-0000-00000000009f', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005a', 'b1c00000-0000-0000-0000-000000000084', 'b1c00000-0000-0000-0000-000000000074', now() - interval '1 hour', true),
  -- branch AB, KDS d2: kitchen_staff 98
  ('b1c00000-0000-0000-0000-000000000098', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-00000000005b', 'b1c00000-0000-0000-0000-000000000088', 'b1c00000-0000-0000-0000-000000000078', now() + interval '1 hour', true),
  -- branch AC, POS d3: org_owner 9b, "false"-denied cashier 9c
  ('b1c00000-0000-0000-0000-00000000009b', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'b1c00000-0000-0000-0000-00000000005c', 'b1c00000-0000-0000-0000-000000000083', 'b1c00000-0000-0000-0000-000000000073', now() + interval '1 hour', true),
  ('b1c00000-0000-0000-0000-00000000009c', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ac', 'b1c00000-0000-0000-0000-00000000005c', 'b1c00000-0000-0000-0000-00000000008c', 'b1c00000-0000-0000-0000-00000000007c', now() + interval '1 hour', true),
  -- org B branch BB, POS d4: default cashier 9d
  ('b1c00000-0000-0000-0000-00000000009d', 'b1c00000-0000-0000-0000-0000000000b0', 'b1c00000-0000-0000-0000-0000000000b1', 'b1c00000-0000-0000-0000-0000000000bb', 'b1c00000-0000-0000-0000-00000000005d', 'b1c00000-0000-0000-0000-00000000008d', 'b1c00000-0000-0000-0000-00000000007d', now() + interval '1 hour', true);

-- Menu (restaurant-scoped): Fries 1500, Cola 800.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('b1c00000-0000-0000-0000-0000000000c1', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('b1c00000-0000-0000-0000-000000001002', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', null, 'b1c00000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 1),
  ('b1c00000-0000-0000-0000-000000001003', 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1', null, 'b1c00000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 2);

-- the valid fixture sessions: key, pin session, device
create temp table t_sess (k text, pin uuid, dev uuid);
insert into t_sess values
  ('manager',      'b1c00000-0000-0000-0000-000000000091', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('rest_owner',   'b1c00000-0000-0000-0000-000000000092', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('org_owner',    'b1c00000-0000-0000-0000-000000000093', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('cashier',      'b1c00000-0000-0000-0000-000000000094', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('c_bool_false', 'b1c00000-0000-0000-0000-000000000095', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('c_str_true',   'b1c00000-0000-0000-0000-000000000096', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('c_str_false',  'b1c00000-0000-0000-0000-000000000097', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('c_non_object', 'b1c00000-0000-0000-0000-00000000009a', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('kitchen',      'b1c00000-0000-0000-0000-000000000098', 'b1c00000-0000-0000-0000-0000000000d2'),
  ('accountant',   'b1c00000-0000-0000-0000-000000000099', 'b1c00000-0000-0000-0000-0000000000d1'),
  ('ac_org_owner', 'b1c00000-0000-0000-0000-00000000009b', 'b1c00000-0000-0000-0000-0000000000d3'),
  ('ac_c_denied',  'b1c00000-0000-0000-0000-00000000009c', 'b1c00000-0000-0000-0000-0000000000d3'),
  ('b_cashier',    'b1c00000-0000-0000-0000-00000000009d', 'b1c00000-0000-0000-0000-0000000000d4');
-- the sessions of branch AB (every role)
create temp table t_ab (k text);
insert into t_ab values ('manager'), ('rest_owner'), ('org_owner'), ('cashier'), ('c_bool_false'),
  ('c_str_true'), ('c_str_false'), ('c_non_object'), ('kitchen'), ('accountant');

-- one probe of a session by key
create function pg_temp.cap(p_k text) returns jsonb
language sql stable as $$
  select app.pin_session_capabilities(s.pin, s.dev) from t_sess s where s.k = p_k;
$$;
-- the six capabilities computed INDEPENDENTLY from the session's membership row
-- (role grants OR the cashier resolvers: deny-only / grant-only)
create function pg_temp.expected_caps(p_pin uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'apply_discount',           m.role in ('manager', 'restaurant_owner', 'org_owner') or app.cashier_capability_allowed(m.role, m.permissions, 'apply_discount'),
    'apply_full_comp',          m.role in ('manager', 'restaurant_owner', 'org_owner') or app.cashier_capability_granted(m.role, m.permissions, 'apply_full_comp'),
    'manage_menu_availability', m.role in ('manager', 'restaurant_owner', 'org_owner') or app.cashier_capability_allowed(m.role, m.permissions, 'manage_menu_availability'),
    'manage_table_operations',  m.role in ('manager', 'restaurant_owner', 'org_owner') or app.cashier_capability_allowed(m.role, m.permissions, 'manage_table_operations'),
    'open_cash_drawer',         m.role in ('manager', 'restaurant_owner', 'org_owner') or app.cashier_capability_granted(m.role, m.permissions, 'open_cash_drawer'),
    'void_order',               m.role in ('manager', 'restaurant_owner', 'org_owner') or app.cashier_capability_allowed(m.role, m.permissions, 'void_order'))
    from pin_sessions ps
    join memberships m on m.id = ps.resolved_membership_id and m.organization_id = ps.organization_id
   where ps.id = p_pin;
$$;
-- the switches of a branch row, in the branch_features shape
create function pg_temp.bf_row(p_branch uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('order_edit_enabled', b.order_edit_enabled,
                            'order_edit_finished_food_manager_only', b.order_edit_finished_food_manager_only)
    from branches b where b.id = p_branch;
$$;
-- org A branch AB orders (opened by the manager on the POS)
create function pg_temp.mk_order(p_id uuid, p_status text) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status)
  values (p_id, 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1',
    'b1c00000-0000-0000-0000-0000000000ab', 'b1c00000-0000-0000-0000-0000000000d1',
    'b1c00000-0000-0000-0000-000000000091', 'b1c00000-0000-0000-0000-000000000081',
    'b1c00000-0000-0000-0000-000000000071', 'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor)
  values (p_id, 'b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000a1',
    'b1c00000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, 0, p_total);
$$;
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.void through public.sync_push (the org A POS)
create function pg_temp.void_push(p_pin uuid, p_op text, p_order uuid) returns jsonb
language sql as $$
  select public.sync_push(p_pin, 'b1c00000-0000-0000-0000-0000000000d1', jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.void', 'target_entity', 'order',
    'payload', jsonb_build_object('order_id', p_order, 'reason', 'caps parity')))) -> 'results' -> 0;
$$;
-- one order.edit through public.sync_push (the org A POS)
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'b1c00000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;

-- ===== A. signature, volatility, DEFINER, search_path, ACL (unchanged) ======
select ok((select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
                  and p.prorettype = 'jsonb'::regtype
             from pg_proc p where p.oid = 'app.pin_session_capabilities(uuid,uuid)'::regprocedure),
  '01 app.pin_session_capabilities(uuid, uuid) -> jsonb: SECURITY DEFINER, STABLE, search_path pinned to ''''');
select ok(has_function_privilege('authenticated', 'app.pin_session_capabilities(uuid,uuid)', 'EXECUTE')
          and not has_function_privilege('anon', 'app.pin_session_capabilities(uuid,uuid)', 'EXECUTE')
          and not has_function_privilege('public', 'app.pin_session_capabilities(uuid,uuid)', 'EXECUTE'),
  '02 app.pin_session_capabilities: authenticated may execute; anon and PUBLIC may not');
select ok((select not p.prosecdef and p.prorettype = 'jsonb'::regtype
             from pg_proc p where p.oid = 'public.pin_session_capabilities(uuid,uuid)'::regprocedure)
          and has_function_privilege('authenticated', 'public.pin_session_capabilities(uuid,uuid)', 'EXECUTE')
          and not has_function_privilege('anon', 'public.pin_session_capabilities(uuid,uuid)', 'EXECUTE')
          and not has_function_privilege('public', 'public.pin_session_capabilities(uuid,uuid)', 'EXECUTE'),
  '03 public.pin_session_capabilities: SECURITY INVOKER wrapper; authenticated may execute; anon and PUBLIC may not');

-- ===== B. void_order per role / permissions shape (branch AB at default) =====
create temp table t_c1 as select s.k, s.pin, s.dev, pg_temp.cap(s.k) as r from t_sess s;

select ok((select bool_and((c.r ->> 'ok')::boolean and c.r ->> 'entity' = 'pin_session' and c.r ->> 'role' = m.role)
                  and count(*) = 13
             from t_c1 c join pin_sessions ps on ps.id = c.pin
             join memberships m on m.id = ps.resolved_membership_id),
  '04 every valid fixture session (13) probes ok:true, entity pin_session, with its membership''s role');
select ok((select (r -> 'capabilities' -> 'void_order') = 'true'::jsonb from t_c1 where k = 'manager'),
  '05 manager: void_order TRUE (by role)');
select ok((select bool_and((r -> 'capabilities' -> 'void_order') = 'true'::jsonb) and count(*) = 3
             from t_c1 where k in ('rest_owner', 'org_owner', 'ac_org_owner')),
  '06 restaurant_owner and org_owner: void_order TRUE (by role)');
select ok((select (r -> 'capabilities' -> 'void_order') = 'true'::jsonb from t_c1 where k = 'cashier'),
  '07 a default cashier (permissions {}): void_order TRUE (deny-only, DEFAULT ON)');
select ok((select (r -> 'capabilities' -> 'void_order') = 'false'::jsonb from t_c1 where k = 'c_bool_false'),
  '08 a cashier with {"void_order": false} (JSON boolean): void_order FALSE');
select ok((select (r -> 'capabilities' -> 'void_order')
                  = to_jsonb(app.cashier_capability_allowed('cashier', '{"void_order": "true"}'::jsonb, 'void_order'))
                  and (r -> 'capabilities' -> 'void_order') = 'false'::jsonb
             from t_c1 where k = 'c_str_true'),
  '09 a cashier with {"void_order": "true"} (a string): void_order equals the deny-only resolver, which reads ANY present key as a deny (FALSE)');
select ok((select bool_and((r -> 'capabilities' -> 'void_order') = 'false'::jsonb) and count(*) = 2
             from t_c1 where k in ('c_str_false', 'ac_c_denied')),
  '10 a cashier with the canonical deny {"void_order": "false"}: void_order FALSE');
select ok((select (r -> 'capabilities' -> 'void_order') = 'false'::jsonb from t_c1 where k = 'c_non_object'),
  '11 a cashier whose permissions are not a JSON object ([]): void_order FALSE (fail closed)');
select ok((select (r -> 'capabilities' -> 'void_order') = 'false'::jsonb and r ->> 'role' = 'kitchen_staff'
             from t_c1 where k = 'kitchen'),
  '12 kitchen_staff: void_order FALSE');
select ok((select (r -> 'capabilities' -> 'void_order') = 'false'::jsonb and r ->> 'role' = 'accountant'
             from t_c1 where k = 'accountant'),
  '13 accountant: void_order FALSE');
select ok((select bool_and((c.r -> 'capabilities' ->> 'void_order')::boolean
                           = ((m.role in ('manager', 'restaurant_owner', 'org_owner'))
                              or app.cashier_capability_allowed(m.role, m.permissions, 'void_order')))
             from t_c1 c join pin_sessions ps on ps.id = c.pin
             join memberships m on m.id = ps.resolved_membership_id),
  '14 predicate parity: for EVERY fixture membership, void_order = manager+ by role OR app.cashier_capability_allowed(role, permissions, ''void_order'')');
select ok((select bool_and((c.r -> 'capabilities') = pg_temp.expected_caps(c.pin)) from t_c1 c),
  '15 for every fixture session the whole capabilities object equals the six independently computed predicates (the five existing ones unchanged)');

-- ===== C. branch_features: the session's OWN branch row ======================
select ok((select bool_and((c.r -> 'branch_features')
                           = '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb)
                  and bool_and((c.r -> 'branch_features') = pg_temp.bf_row('b1c00000-0000-0000-0000-0000000000ab'))
                  and count(*) = 10
             from t_c1 c join t_ab a on a.k = c.k),
  '16 branch at its defaults: every role (kitchen_staff and accountant included) reads branch_features false / false, the branch row');
select ok((select (r -> 'branch_features') = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": false}'::jsonb
                  and (r -> 'branch_features') = pg_temp.bf_row('b1c00000-0000-0000-0000-0000000000bb')
             from t_c1 where k = 'b_cashier'),
  '17 org B''s session reads ITS OWN branch (true / false) while org A''s branch is false / false');
select ok((select bool_and((r -> 'branch_features') = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": true}'::jsonb)
                  and count(*) = 2
             from t_c1 where k in ('ac_org_owner', 'ac_c_denied')),
  '18 the sibling branch AC (true / true) is reported to ITS sessions only (both roles)');

-- ===== D. the envelope ========================================================
select ok((select bool_and((select array_agg(x order by x) from jsonb_object_keys(r) x)
                           = array['branch_features', 'capabilities', 'entity', 'ok', 'role'])
             from t_c1),
  '19 every success envelope has EXACTLY the keys {branch_features, capabilities, entity, ok, role}');
select ok((select bool_and((select array_agg(x order by x) from jsonb_object_keys(r -> 'capabilities') x)
                           = array['apply_discount', 'apply_full_comp', 'manage_menu_availability',
                                   'manage_table_operations', 'open_cash_drawer', 'void_order'])
             from t_c1),
  '20 capabilities has EXACTLY the six keys (void_order the sixth)');
select ok((select bool_and(jsonb_typeof(r -> 'branch_features') = 'object'
                           and (select array_agg(x order by x) from jsonb_object_keys(r -> 'branch_features') x)
                               = array['order_edit_enabled', 'order_edit_finished_food_manager_only'])
             from t_c1),
  '21 branch_features is a top-level object with EXACTLY {order_edit_enabled, order_edit_finished_food_manager_only}');
select ok((select bool_and(v.t = 'boolean')
             from t_c1 c,
                  lateral (select jsonb_typeof(e.value) as t from jsonb_each(c.r -> 'capabilities') e
                           union all
                           select jsonb_typeof(e.value) from jsonb_each(c.r -> 'branch_features') e) v),
  '22 every capability and every branch_features value is a JSON boolean (never null, never a string)');
select ok((select bool_and(c.r::text !~* '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
                           and position('b1c00000' in c.r::text) = 0
                           and position('permissions' in c.r::text) = 0)
             from t_c1 c),
  '23 no success payload carries any UUID (branch / org / membership / employee / session / device) or the permissions JSON');
select is(app.pin_session_capabilities('b1c00000-0000-0000-0000-00000000009e', 'b1c00000-0000-0000-0000-0000000000d1'),
  '{"ok": false, "error": "invalid_session", "entity": "pin_session"}'::jsonb,
  '24 an INACTIVE session: exactly {ok:false, error:invalid_session, entity:pin_session}');
select is(app.pin_session_capabilities('b1c00000-0000-0000-0000-00000000009f', 'b1c00000-0000-0000-0000-0000000000d1'),
  '{"ok": false, "error": "invalid_session", "entity": "pin_session"}'::jsonb,
  '25 an EXPIRED session: exactly the same envelope');
select is(app.pin_session_capabilities('b1c00000-0000-0000-0000-0000000000ff', 'b1c00000-0000-0000-0000-0000000000d1'),
  '{"ok": false, "error": "invalid_session", "entity": "pin_session"}'::jsonb,
  '26 an UNKNOWN session: exactly the same envelope');
select is(app.pin_session_capabilities('b1c00000-0000-0000-0000-00000000009d', 'b1c00000-0000-0000-0000-0000000000d1'),
  '{"ok": false, "error": "invalid_session", "entity": "pin_session"}'::jsonb,
  '27 a valid org B session named with org A''s device (device mismatch): exactly the same envelope, no branch_features');
select ok((select bool_and(public.pin_session_capabilities(x.pin, x.dev) = app.pin_session_capabilities(x.pin, x.dev))
                  and count(*) = 17
             from (select pin, dev from t_sess
                   union all values
                     ('b1c00000-0000-0000-0000-00000000009e'::uuid, 'b1c00000-0000-0000-0000-0000000000d1'::uuid),
                     ('b1c00000-0000-0000-0000-00000000009f'::uuid, 'b1c00000-0000-0000-0000-0000000000d1'::uuid),
                     ('b1c00000-0000-0000-0000-0000000000ff'::uuid, 'b1c00000-0000-0000-0000-0000000000d1'::uuid),
                     ('b1c00000-0000-0000-0000-00000000009d'::uuid, 'b1c00000-0000-0000-0000-0000000000d1'::uuid)) x),
  '28 public.pin_session_capabilities is a pass-through: byte-identical to app.* for every success and failure probe');

-- ===== E. parity with ENFORCEMENT: app.void_order ============================
-- One unpaid preparing order per attempt (Cola 800).
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a001', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a002', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a003', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a004', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a005', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a006', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a007', 'preparing');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000a008', 'preparing');
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a1001', 'b1c00000-0000-0000-0000-00000000a001', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a2001', 'b1c00000-0000-0000-0000-00000000a002', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a3001', 'b1c00000-0000-0000-0000-00000000a003', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a4001', 'b1c00000-0000-0000-0000-00000000a004', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a5001', 'b1c00000-0000-0000-0000-00000000a005', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a6001', 'b1c00000-0000-0000-0000-00000000a006', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a7001', 'b1c00000-0000-0000-0000-00000000a007', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000a8001', 'b1c00000-0000-0000-0000-00000000a008', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals(id) from orders where id::text like 'b1c00000-0000-0000-0000-00000000a00_';

-- Every attempt is its own statement (the writer), read back later.
create temp table t_void (k text, via text, ord uuid, r jsonb);
insert into t_void select 'c_bool_false', 'push', 'b1c00000-0000-0000-0000-00000000a001',
  pg_temp.void_push('b1c00000-0000-0000-0000-000000000095', 'caps-void-1', 'b1c00000-0000-0000-0000-00000000a001');
insert into t_void select 'c_str_true', 'push', 'b1c00000-0000-0000-0000-00000000a002',
  pg_temp.void_push('b1c00000-0000-0000-0000-000000000096', 'caps-void-2', 'b1c00000-0000-0000-0000-00000000a002');
insert into t_void select 'c_str_false', 'push', 'b1c00000-0000-0000-0000-00000000a003',
  pg_temp.void_push('b1c00000-0000-0000-0000-000000000097', 'caps-void-3', 'b1c00000-0000-0000-0000-00000000a003');
insert into t_void select 'cashier', 'push', 'b1c00000-0000-0000-0000-00000000a004',
  pg_temp.void_push('b1c00000-0000-0000-0000-000000000094', 'caps-void-4', 'b1c00000-0000-0000-0000-00000000a004');
insert into t_void select 'kitchen', 'direct', 'b1c00000-0000-0000-0000-00000000a005',
  app.void_order('b1c00000-0000-0000-0000-000000000098', 'b1c00000-0000-0000-0000-00000000a005',
    'b1c00000-0000-0000-0000-0000000000d2', 'caps-void-5', 'caps parity');
insert into t_void select 'accountant', 'direct', 'b1c00000-0000-0000-0000-00000000a006',
  app.void_order('b1c00000-0000-0000-0000-000000000099', 'b1c00000-0000-0000-0000-00000000a006',
    'b1c00000-0000-0000-0000-0000000000d1', 'caps-void-6', 'caps parity');
insert into t_void select 'c_non_object', 'direct', 'b1c00000-0000-0000-0000-00000000a007',
  app.void_order('b1c00000-0000-0000-0000-00000000009a', 'b1c00000-0000-0000-0000-00000000a007',
    'b1c00000-0000-0000-0000-0000000000d1', 'caps-void-7', 'caps parity');
insert into t_void select 'rest_owner', 'direct', 'b1c00000-0000-0000-0000-00000000a008',
  app.void_order('b1c00000-0000-0000-0000-000000000092', 'b1c00000-0000-0000-0000-00000000a008',
    'b1c00000-0000-0000-0000-0000000000d1', 'caps-void-8', 'caps parity');

select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'permission_denied' from t_void where k = 'c_bool_false')
      and (select status = 'preparing' from orders where id = 'b1c00000-0000-0000-0000-00000000a001'),
  '29 the cashier whose capability says void_order=false ({"void_order": false}): a real order.void through sync_push is refused permission_denied, the order is untouched');
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'permission_denied' from t_void where k = 'c_str_true')
      and (select status = 'preparing' from orders where id = 'b1c00000-0000-0000-0000-00000000a002'),
  '30 the {"void_order": "true"} cashier (capability FALSE): order.void is refused permission_denied too (advisory = enforced)');
select ok((select r ->> 'status' = 'applied' from t_void where k = 'cashier')
      and (select status = 'voided' from orders where id = 'b1c00000-0000-0000-0000-00000000a004'),
  '31 the default cashier (capability TRUE): order.void through sync_push is applied, the order is voided');
select ok((select bool_and(
                    (case when v.via = 'push' then v.r ->> 'status' = 'applied'
                          else coalesce((v.r ->> 'ok')::boolean, false) end)
                    = (c.r -> 'capabilities' ->> 'void_order')::boolean
                    and (case when (c.r -> 'capabilities' ->> 'void_order')::boolean then o.status = 'voided'
                              else o.status = 'preparing' and v.r ->> 'error' = 'permission_denied' end))
                  and count(*) = 8
             from t_void v join t_c1 c on c.k = v.k join orders o on o.id = v.ord),
  '32 for all eight personas (four cashier shapes, kitchen_staff, accountant, restaurant_owner) the void succeeds EXACTLY when the probe said void_order TRUE');

-- ===== F. the setter flips the switches; the probe follows (authenticated) ===
set local role authenticated;
set local app.current_app_user_id = 'b1c00000-0000-0000-0000-000000000063';  -- org_owner
create temp table t_set as select public.set_branch_order_edit_settings(
  'b1c00000-0000-0000-0000-0000000c0001', 'b1c00000-0000-0000-0000-0000000000a0',
  'b1c00000-0000-0000-0000-0000000000a1', 'b1c00000-0000-0000-0000-0000000000ab', true, false) as r;
create temp table t_auth as select
  public.pin_session_capabilities('b1c00000-0000-0000-0000-000000000094', 'b1c00000-0000-0000-0000-0000000000d1') as r;
reset role;

select ok((select (r ->> 'ok')::boolean from t_set)
      and (select (r -> 'branch_features') = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": false}'::jsonb
                  and (r -> 'branch_features') = pg_temp.bf_row('b1c00000-0000-0000-0000-0000000000ab')
                  and (r -> 'capabilities' -> 'void_order') = 'true'::jsonb
             from t_auth),
  '33 after app.set_branch_order_edit_settings(true, false) a probe AS authenticated (public wrapper) reads true / false, the branch row, with void_order');

-- ===== G. parity with ENFORCEMENT: app.edit_order's removal gate ============
-- Two preparing orders: Fries 1500 + Cola 800 = 2300; each removes the Cola.
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000e001', 'preparing');
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000e1001', 'b1c00000-0000-0000-0000-00000000e001', 'b1c00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000e1002', 'b1c00000-0000-0000-0000-00000000e001', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1c00000-0000-0000-0000-00000000e001');
select pg_temp.mk_order('b1c00000-0000-0000-0000-00000000e002', 'preparing');
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000e2001', 'b1c00000-0000-0000-0000-00000000e002', 'b1c00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1c00000-0000-0000-0000-0000000e2002', 'b1c00000-0000-0000-0000-00000000e002', 'b1c00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1c00000-0000-0000-0000-00000000e002');

create temp table t_edit (k text, r jsonb);
insert into t_edit select 'denied', pg_temp.edit('b1c00000-0000-0000-0000-000000000095', 'caps-edit-1', 'b1c00000-0000-0000-0000-00000000e001',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 1500, "tax_total_minor": 0, "grand_total_minor": 1500},
    "changes": [{"op": "remove", "order_item_id": "b1c00000-0000-0000-0000-0000000e1002"}]}'::jsonb);
insert into t_edit select 'default', pg_temp.edit('b1c00000-0000-0000-0000-000000000094', 'caps-edit-2', 'b1c00000-0000-0000-0000-00000000e002',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 1500, "tax_total_minor": 0, "grand_total_minor": 1500},
    "changes": [{"op": "remove", "order_item_id": "b1c00000-0000-0000-0000-0000000e2002"}]}'::jsonb);

select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'permission_denied' and r ->> 'detail' = 'removal_not_permitted'
             from t_edit where k = 'denied')
      and (select edit_count = 0 from orders where id = 'b1c00000-0000-0000-0000-00000000e001')
      and (select (r -> 'capabilities' -> 'void_order') = 'false'::jsonb from t_c1 where k = 'c_bool_false'),
  '34 void_order FALSE => a REMOVING order.edit is refused permission_denied / removal_not_permitted (app.edit_order''s removal gate agrees)');
select ok((select r ->> 'status' = 'applied' from t_edit where k = 'default')
      and (select edit_count = 1 from orders where id = 'b1c00000-0000-0000-0000-00000000e002')
      and (select (r -> 'capabilities' -> 'void_order') = 'true'::jsonb from t_c1 where k = 'cashier'),
  '35 void_order TRUE (default cashier) => the same removing order.edit is applied');

-- ===== H. both switches ON; then only the second one (direct row update) =====
update branches set order_edit_enabled = true, order_edit_finished_food_manager_only = true
 where id = 'b1c00000-0000-0000-0000-0000000000ab';
select ok((select bool_and((pg_temp.cap(a.k) -> 'branch_features')
                           = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": true}'::jsonb)
                  and bool_and((pg_temp.cap(a.k) -> 'branch_features') = pg_temp.bf_row('b1c00000-0000-0000-0000-0000000000ab'))
                  and count(*) = 10
             from t_ab a),
  '36 both switches ON: EVERY role of the branch (kitchen_staff and accountant included) reads true / true, the branch row');
select ok((select bool_and((pg_temp.cap(a.k) - 'branch_features') = (c.r - 'branch_features'))
             from t_ab a join t_c1 c on c.k = a.k),
  '37 flipping the branch switches leaves ok / entity / role / capabilities byte-identical for every role');
update branches set order_edit_enabled = false, order_edit_finished_food_manager_only = true
 where id = 'b1c00000-0000-0000-0000-0000000000ab';
select ok((select bool_and((pg_temp.cap(a.k) -> 'branch_features')
                           = '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": true}'::jsonb)
             from t_ab a),
  '38 false / true is reported as stored: the two keys mirror their own columns independently');

-- ===== I. a soft-deleted session branch reads both switches FALSE ===========
create temp table t_pre as select k, pg_temp.cap(k) as r from t_sess where k in ('ac_org_owner', 'ac_c_denied');
update branches set deleted_at = now() where id = 'b1c00000-0000-0000-0000-0000000000ac';
create temp table t_post as select k, pg_temp.cap(k) as r from t_sess where k in ('ac_org_owner', 'ac_c_denied');
select ok((select bool_and((r -> 'branch_features') = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": true}'::jsonb)
             from t_pre)
      and (select bool_and((r ->> 'ok')::boolean
                           and (r -> 'branch_features') = '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb)
                  and count(*) = 2
             from t_post),
  '39 the session branch soft-deleted (true / true on the row): the probe is still ok:true and reports both switches FALSE');
select ok((select bool_and((p.r - 'branch_features') = (q.r - 'branch_features')) and count(*) = 2
             from t_pre p join t_post q on q.k = p.k)
      and (select (r -> 'capabilities' -> 'void_order') = 'true'::jsonb from t_post where k = 'ac_org_owner')
      and (select (r -> 'capabilities' -> 'void_order') = 'false'::jsonb from t_post where k = 'ac_c_denied'),
  '40 ... and role and every capability are unchanged by the unreadable branch row');

-- ===== J. read-only ===========================================================
create temp table t_audit_before as
  select count(*) as n from audit_events
   where organization_id in ('b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000b0');
create temp table t_probe_again as select k, pg_temp.cap(k) as r from t_sess;
select ok((select count(*) from audit_events
            where organization_id in ('b1c00000-0000-0000-0000-0000000000a0', 'b1c00000-0000-0000-0000-0000000000b0'))
          = (select n from t_audit_before)
      and (select count(*) = 13 from t_probe_again),
  '41 a probe of every fixture session writes no audit row (read-only)');

select * from finish();
rollback;
