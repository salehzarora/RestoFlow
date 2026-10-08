-- ORDER-EDIT-001B — the money-free order_edits pull entity (API_CONTRACT §4.15,
-- DECISION D-044; migration 20261008190000): app.sync_pull (through the
-- public.sync_pull wrapper) and app.sync_pull_changes. Covers the role
-- allow-list (kitchen_staff in kds mode + every price-capable role), the
-- printer_only kitchen containment (floor only; an explicit request rejects
-- 42501), the KDS-device direct-print graph filter (now five entities) with
-- its cursor-advancing pagination, the kitchen acknowledgement reaching the
-- pull, tenant / sibling-branch isolation, the kitchen money redaction being
-- a no-op on the raw rows, the pager allow-list and the unchanged ACLs.
begin;
set local search_path to extensions, public, pg_catalog;

select plan(42);

-- ===== fixture ==============================================================
-- Org A, one restaurant, two branches (order editing ON on both):
--   K (..ab) kds mode:          POS d1, KDS d2
--   P (..ac) printer_only mode: POS d3, KDS d4
-- PIN sessions:
--   K: cashier (91) / manager (92) / accountant (94) on the POS d1,
--      kitchen_staff (93) on the KDS d2
--   P: cashier (96) / manager (97) on the POS d3,
--      kitchen_staff (98) / manager (99) / cashier (9a) on the KDS d4
insert into organizations (id, name, slug, default_currency) values
  ('b1b00000-0000-0000-0000-0000000000a0', 'Org Edit Pull', 'org-edit-pull-001b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000a0', 'Rest Edit Pull');
insert into branches (id, organization_id, restaurant_id, name, kitchen_workflow_mode, order_edit_enabled) values
  ('b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'Branch Pull KDS', 'kds', true),
  ('b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'Branch Pull Paper', 'printer_only', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b1b00000-0000-0000-0000-0000000000d1', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'pos'),
  ('b1b00000-0000-0000-0000-0000000000d2', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'kds'),
  ('b1b00000-0000-0000-0000-0000000000d3', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'pos'),
  ('b1b00000-0000-0000-0000-0000000000d4', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b1b00000-0000-0000-0000-0000000000f1', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-0000000000d1', 'active'),
  ('b1b00000-0000-0000-0000-0000000000f2', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-0000000000d2', 'active'),
  ('b1b00000-0000-0000-0000-0000000000f3', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-0000000000d3', 'active'),
  ('b1b00000-0000-0000-0000-0000000000f4', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-0000000000d4', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b1b00000-0000-0000-0000-000000000051', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-0000000000d1', 'b1b00000-0000-0000-0000-0000000000f1'),
  ('b1b00000-0000-0000-0000-000000000052', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-0000000000d2', 'b1b00000-0000-0000-0000-0000000000f2'),
  ('b1b00000-0000-0000-0000-000000000053', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-0000000000d3', 'b1b00000-0000-0000-0000-0000000000f3'),
  ('b1b00000-0000-0000-0000-000000000054', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-0000000000d4', 'b1b00000-0000-0000-0000-0000000000f4');
insert into app_users (id, email) values
  ('b1b00000-0000-0000-0000-000000000061', 'pull-k-cashier@example.test'),
  ('b1b00000-0000-0000-0000-000000000062', 'pull-k-manager@example.test'),
  ('b1b00000-0000-0000-0000-000000000063', 'pull-k-kitchen@example.test'),
  ('b1b00000-0000-0000-0000-000000000064', 'pull-k-accountant@example.test'),
  ('b1b00000-0000-0000-0000-000000000065', 'pull-p-cashier@example.test'),
  ('b1b00000-0000-0000-0000-000000000066', 'pull-p-manager@example.test'),
  ('b1b00000-0000-0000-0000-000000000067', 'pull-p-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('b1b00000-0000-0000-0000-000000000071', 'b1b00000-0000-0000-0000-000000000061', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('b1b00000-0000-0000-0000-000000000072', 'b1b00000-0000-0000-0000-000000000062', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('b1b00000-0000-0000-0000-000000000073', 'b1b00000-0000-0000-0000-000000000063', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb),
  ('b1b00000-0000-0000-0000-000000000074', 'b1b00000-0000-0000-0000-000000000064', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'accountant', '{}'::jsonb),
  ('b1b00000-0000-0000-0000-000000000075', 'b1b00000-0000-0000-0000-000000000065', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'cashier', '{}'::jsonb),
  ('b1b00000-0000-0000-0000-000000000076', 'b1b00000-0000-0000-0000-000000000066', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'manager', '{}'::jsonb),
  ('b1b00000-0000-0000-0000-000000000077', 'b1b00000-0000-0000-0000-000000000067', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'kitchen_staff', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('b1b00000-0000-0000-0000-000000000081', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000061', 'b1b00000-0000-0000-0000-000000000071', 'Kay Cashier'),
  ('b1b00000-0000-0000-0000-000000000082', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000062', 'b1b00000-0000-0000-0000-000000000072', 'Kim Manager'),
  ('b1b00000-0000-0000-0000-000000000083', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000063', 'b1b00000-0000-0000-0000-000000000073', 'Kit Kitchen'),
  ('b1b00000-0000-0000-0000-000000000084', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000064', 'b1b00000-0000-0000-0000-000000000074', 'Ari Accountant'),
  ('b1b00000-0000-0000-0000-000000000085', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000065', 'b1b00000-0000-0000-0000-000000000075', 'Pia Cashier'),
  ('b1b00000-0000-0000-0000-000000000086', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000066', 'b1b00000-0000-0000-0000-000000000076', 'Pat Manager'),
  ('b1b00000-0000-0000-0000-000000000087', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000067', 'b1b00000-0000-0000-0000-000000000077', 'Pip Kitchen');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  -- K POS: cashier (91), manager (92), accountant (94); K KDS: kitchen_staff (93)
  ('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000051', 'b1b00000-0000-0000-0000-000000000081', 'b1b00000-0000-0000-0000-000000000071', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-000000000092', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000051', 'b1b00000-0000-0000-0000-000000000082', 'b1b00000-0000-0000-0000-000000000072', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-000000000093', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000052', 'b1b00000-0000-0000-0000-000000000083', 'b1b00000-0000-0000-0000-000000000073', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-000000000094', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000000051', 'b1b00000-0000-0000-0000-000000000084', 'b1b00000-0000-0000-0000-000000000074', now() + interval '1 hour'),
  -- P POS: cashier (96), manager (97); P KDS: kitchen_staff (98), manager (99), cashier (9a)
  ('b1b00000-0000-0000-0000-000000000096', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000053', 'b1b00000-0000-0000-0000-000000000085', 'b1b00000-0000-0000-0000-000000000075', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-000000000097', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000053', 'b1b00000-0000-0000-0000-000000000086', 'b1b00000-0000-0000-0000-000000000076', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-000000000098', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000054', 'b1b00000-0000-0000-0000-000000000087', 'b1b00000-0000-0000-0000-000000000077', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-000000000099', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000054', 'b1b00000-0000-0000-0000-000000000086', 'b1b00000-0000-0000-0000-000000000076', now() + interval '1 hour'),
  ('b1b00000-0000-0000-0000-00000000009a', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000000054', 'b1b00000-0000-0000-0000-000000000085', 'b1b00000-0000-0000-0000-000000000075', now() + interval '1 hour');

-- Menu (restaurant-scoped, shared by both branches): Fries 1500, Cola 800.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('b1b00000-0000-0000-0000-0000000000c1', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('b1b00000-0000-0000-0000-000000001001', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', null, 'b1b00000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 1),
  ('b1b00000-0000-0000-0000-000000001002', 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', null, 'b1b00000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 2);

-- Org B: a second tenant with its own KDS-mode branch (editing ON), POS,
-- cashier PIN, menu and one preparing order (Cola x1 800).
insert into organizations (id, name, slug, default_currency) values
  ('b1b00000-0000-0000-0000-0000000000b0', 'Org Edit Pull B', 'org-edit-pull-001b-b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000b0', 'Rest Edit Pull B');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled) values
  ('b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'Branch Edit Pull B', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b1b00000-0000-0000-0000-0000000000bd', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000bb', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b1b00000-0000-0000-0000-0000000000bf', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-0000000000bd', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b1b00000-0000-0000-0000-0000000000b5', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-0000000000bd', 'b1b00000-0000-0000-0000-0000000000bf');
insert into app_users (id, email) values
  ('b1b00000-0000-0000-0000-0000000000b6', 'pull-b-cashier@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('b1b00000-0000-0000-0000-0000000000b7', 'b1b00000-0000-0000-0000-0000000000b6', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000bb', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('b1b00000-0000-0000-0000-0000000000b8', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-0000000000b6', 'b1b00000-0000-0000-0000-0000000000b7', 'Bo Cashier');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('b1b00000-0000-0000-0000-0000000000b9', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', 'b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-0000000000b5', 'b1b00000-0000-0000-0000-0000000000b8', 'b1b00000-0000-0000-0000-0000000000b7', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('b1b00000-0000-0000-0000-0000000000bc', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', null, 'Drinks', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('b1b00000-0000-0000-0000-00000000b003', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1', null, 'b1b00000-0000-0000-0000-0000000000bc', 'Cola', 800, 'ILS', 1);
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
  subtotal_minor, grand_total_minor, local_operation_id, status) values
  ('b1b00000-0000-0000-0000-00000000b0b1', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1',
   'b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-0000000000bd', 'b1b00000-0000-0000-0000-0000000000b9',
   'b1b00000-0000-0000-0000-0000000000b8', 'b1b00000-0000-0000-0000-0000000000b7', 'dine_in', 'ILS', 800, 800,
   'submit-pull-org-b-1', 'preparing');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor) values
  ('b1b00000-0000-0000-0000-0000000b1001', 'b1b00000-0000-0000-0000-0000000000b0', 'b1b00000-0000-0000-0000-0000000000b1',
   'b1b00000-0000-0000-0000-0000000000bb', 'b1b00000-0000-0000-0000-00000000b0b1', 'b1b00000-0000-0000-0000-00000000b003',
   1, 'Cola', 800, 0, 800);

-- Org A builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire). The opening actor is the cashier
-- of the order's branch on that branch's POS.
create function pg_temp.mk_order(p_id uuid, p_branch uuid, p_status text, p_dispatch text default 'kds') returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at, dispatch_mode)
  values (p_id, 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1', p_branch,
    case when p_branch = 'b1b00000-0000-0000-0000-0000000000ab'
         then 'b1b00000-0000-0000-0000-0000000000d1'::uuid else 'b1b00000-0000-0000-0000-0000000000d3'::uuid end,
    case when p_branch = 'b1b00000-0000-0000-0000-0000000000ab'
         then 'b1b00000-0000-0000-0000-000000000091'::uuid else 'b1b00000-0000-0000-0000-000000000096'::uuid end,
    case when p_branch = 'b1b00000-0000-0000-0000-0000000000ab'
         then 'b1b00000-0000-0000-0000-000000000081'::uuid else 'b1b00000-0000-0000-0000-000000000085'::uuid end,
    case when p_branch = 'b1b00000-0000-0000-0000-0000000000ab'
         then 'b1b00000-0000-0000-0000-000000000071'::uuid else 'b1b00000-0000-0000-0000-000000000075'::uuid end,
    'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end, p_dispatch);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_branch uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor)
  values (p_id, 'b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000a1',
    p_branch, p_order, p_menu, p_qty, p_name, p_unit, 0, p_total);
$$;
-- re-roll an order's stored totals from its live lines (tax off, no discount)
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push; returns the op's result
create function pg_temp.edit(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_payload jsonb) returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- one order.edit_ack through public.sync_push; the payload is {order_id} || p_extra
create function pg_temp.ack(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_extra jsonb) returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit_ack', 'target_entity', 'order',
    'target_id', p_order, 'payload', jsonb_build_object('order_id', p_order) || p_extra))) -> 'results' -> 0;
$$;
-- the id of edit N of an order
create function pg_temp.eid(p_order uuid, p_n int) returns uuid
language sql stable as $$
  select id from order_edits where order_id = p_order and edit_number = p_n;
$$;
-- the ids of a pulled rows array, uuid-ordered, comma-joined ('' when empty)
create function pg_temp.ids(p_rows jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(r ->> 'id', ',' order by (r ->> 'id')::uuid), '')
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r;
$$;
-- the ids of the stored order_edits rows of one org + branch, same format
create function pg_temp.branch_edit_ids(p_org uuid, p_branch uuid) returns text
language sql stable as $$
  select coalesce(string_agg(e.id::text, ',' order by e.id), '')
    from order_edits e where e.organization_id = p_org and e.branch_id = p_branch;
$$;
-- the sorted entity keys of a pull's changes object
create function pg_temp.keys(p_res jsonb) returns text
language sql immutable as $$
  select coalesce(string_agg(k, ',' order by k collate "C"), '')
    from jsonb_object_keys(p_res -> 'changes') k;
$$;
-- TRUE when every pulled row equals its stored to_jsonb(order_edits) row byte-for-byte
create function pg_temp.raw_rows(p_rows jsonb) returns boolean
language sql stable as $$
  select coalesce(bool_and(r = (select to_jsonb(e) from order_edits e where e.id = (r ->> 'id')::uuid)), false)
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r;
$$;

-- Orders (org A):
--   K1 (a001, branch K) preparing: Fries x1 1500, Cola x1 800 = 2300
--   K2 (a002, branch K) preparing: Fries x1 1500, Cola x1 800 = 2300
--   P1 (c001, branch P) served, dispatch_mode direct_print: Fries x1, Cola x1 = 2300
--   P2 (c002, branch P) submitted (kds dispatch): Fries x1 = 1500
select pg_temp.mk_order('b1b00000-0000-0000-0000-00000000a001', 'b1b00000-0000-0000-0000-0000000000ab', 'preparing');
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000a1001', 'b1b00000-0000-0000-0000-00000000a001', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000001001', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000a1002', 'b1b00000-0000-0000-0000-00000000a001', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000001002', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1b00000-0000-0000-0000-00000000a001');

select pg_temp.mk_order('b1b00000-0000-0000-0000-00000000a002', 'b1b00000-0000-0000-0000-0000000000ab', 'preparing');
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000a2001', 'b1b00000-0000-0000-0000-00000000a002', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000001001', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000a2002', 'b1b00000-0000-0000-0000-00000000a002', 'b1b00000-0000-0000-0000-0000000000ab', 'b1b00000-0000-0000-0000-000000001002', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1b00000-0000-0000-0000-00000000a002');

select pg_temp.mk_order('b1b00000-0000-0000-0000-00000000c001', 'b1b00000-0000-0000-0000-0000000000ac', 'served', 'direct_print');
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000c1001', 'b1b00000-0000-0000-0000-00000000c001', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000001001', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000c1002', 'b1b00000-0000-0000-0000-00000000c001', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000001002', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1b00000-0000-0000-0000-00000000c001');

select pg_temp.mk_order('b1b00000-0000-0000-0000-00000000c002', 'b1b00000-0000-0000-0000-0000000000ac', 'submitted');
select pg_temp.mk_item('b1b00000-0000-0000-0000-0000000c2001', 'b1b00000-0000-0000-0000-00000000c002', 'b1b00000-0000-0000-0000-0000000000ac', 'b1b00000-0000-0000-0000-000000001001', 'Fries', 1, 1500, 1500);
select pg_temp.settle_totals('b1b00000-0000-0000-0000-00000000c002');

-- The first fixture edits, through public.sync_push (order.edit). P2's edit
-- is made LATER (section E), after the single-row pagination probe.
create temp table t_edits (k text, r jsonb);
-- K1 edit 1: Cola 1 -> 2 (a +1 delta in place on the In-kitchen unit: confirmation required)
insert into t_edits select 'k1', pg_temp.edit('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000d1',
  'k1-e1', 'b1b00000-0000-0000-0000-00000000a001',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "b1b00000-0000-0000-0000-0000000a1002", "quantity": 2}]}'::jsonb);
-- K2 edit 1: remove Cola, reason 'other' + free text (confirmation required)
insert into t_edits select 'k2', pg_temp.edit('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000d1',
  'k2-e1', 'b1b00000-0000-0000-0000-00000000a002',
  '{"reason_code": "other", "reason_text": "Guest allergy",
    "expected": {"subtotal_minor": 1500, "tax_total_minor": 0, "grand_total_minor": 1500},
    "changes": [{"op": "remove", "order_item_id": "b1b00000-0000-0000-0000-0000000a2002"}]}'::jsonb);
-- P1 edit 1 (direct_print order, printer_only branch => PAPER channel): Cola 1 -> 2
insert into t_edits select 'p1', pg_temp.edit('b1b00000-0000-0000-0000-000000000096', 'b1b00000-0000-0000-0000-0000000000d3',
  'p1-e1', 'b1b00000-0000-0000-0000-00000000c001',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "b1b00000-0000-0000-0000-0000000c1002", "quantity": 2}]}'::jsonb);
-- org B's own edit on its own order (its own POS + cashier)
insert into t_edits select 'b1', pg_temp.edit('b1b00000-0000-0000-0000-0000000000b9', 'b1b00000-0000-0000-0000-0000000000bd',
  'b-e1', 'b1b00000-0000-0000-0000-00000000b0b1',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 0, "grand_total_minor": 1600},
    "changes": [{"op": "set_quantity", "order_item_id": "b1b00000-0000-0000-0000-0000000b1001", "quantity": 2}]}'::jsonb);

select is((select string_agg(k || '=' || coalesce(r ->> 'status', 'null'), ',' order by k) from t_edits),
  'b1=applied,k1=applied,k2=applied,p1=applied',
  '01 every fixture edit is applied through sync_push (order.edit)');
select is((select string_agg(e.order_id::text || ':' || e.edit_number || ':' || e.kitchen_channel || ':' || e.kitchen_ack_required,
                             ',' order by e.order_id)
             from order_edits e where e.organization_id = 'b1b00000-0000-0000-0000-0000000000a0'),
  'b1b00000-0000-0000-0000-00000000a001:1:kds:true,b1b00000-0000-0000-0000-00000000a002:1:kds:true,'
  || 'b1b00000-0000-0000-0000-00000000c001:1:paper:false',
  '02 fixture: K1 / K2 edits are KDS-channel with a required confirmation; the direct_print P1 edit is paper');

-- ===== A. kitchen_staff on the KDS of the kds-mode branch K ===================
create temp table t_kk as select public.sync_pull('b1b00000-0000-0000-0000-000000000093', 'b1b00000-0000-0000-0000-0000000000d2') as res;
create temp table t_kk_x as select public.sync_pull('b1b00000-0000-0000-0000-000000000093', 'b1b00000-0000-0000-0000-0000000000d2',
  array['order_edits']) as res;
create temp table t_kk_old as select public.sync_pull('b1b00000-0000-0000-0000-000000000093', 'b1b00000-0000-0000-0000-0000000000d2',
  array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'tables']) as res;

select is((select pg_temp.keys(res) from t_kk),
  'order_edits,order_item_modifiers,order_items,order_service_rounds,orders,tables',
  '03 kitchen_staff (kds mode) default pull: the five order entities incl. order_edits + the floor; no money / menu entity');
select is((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows') from t_kk),
  pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab'),
  '04 kitchen_staff default pull: order_edits carries exactly branch K''s edit rows (K1, K2)');
select ok((select count(*) = 2 from t_kk, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows'))
      and (select bool_and(
                    (select array_agg(k order by k collate "C") from jsonb_object_keys(r) k)
                    = (select array_agg(a.attname::text order by a.attname::text collate "C")
                         from pg_attribute a
                        where a.attrelid = 'public.order_edits'::regclass and a.attnum > 0 and not a.attisdropped))
             from t_kk, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows') r),
  '05 each order_edits row is the RAW row: its keys are exactly the order_edits columns (to_jsonb)');
select ok((select pg_temp.raw_rows(res -> 'changes' -> 'order_edits' -> 'rows') from t_kk),
  '06 the kitchen money redaction leaves every order_edits row byte-equal to to_jsonb(order_edits)');
select ok((select r ->> 'order_id' = 'b1b00000-0000-0000-0000-00000000a002'
                  and (r ->> 'edit_number')::int = 1
                  and r ->> 'kitchen_channel' = 'kds'
                  and (r ->> 'kitchen_ack_required')::boolean
                  and r -> 'kitchen_ack_at' = 'null'::jsonb
                  and r -> 'kitchen_ack_by_employee_profile_id' = 'null'::jsonb
                  and r ->> 'reason_code' = 'other'
                  and r ->> 'reason_text' = 'Guest allergy'
                  and r -> 'deleted_at' = 'null'::jsonb
                  and r ->> 'branch_id' = 'b1b00000-0000-0000-0000-0000000000ab'
             from t_kk, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows') r
            where r ->> 'id' = pg_temp.eid('b1b00000-0000-0000-0000-00000000a002', 1)::text),
  '07 the K2 edit row carries order_id, edit_number, kitchen_channel, kitchen_ack_required, a null ack and the reason');
select ok((select pg_temp.keys(res) = 'order_edits'
                  and pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                      = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
                  and res -> 'operation_statuses' -> 'rows' = '[]'::jsonb
             from t_kk_x),
  '08 kitchen_staff explicit [order_edits]: allowed, only that entity, the same branch K rows');
select ok((select pg_temp.keys(res) = 'order_item_modifiers,order_items,order_service_rounds,orders,tables'
                  and not (res -> 'changes' ? 'order_edits')
                  and jsonb_array_length(res -> 'changes' -> 'orders' -> 'rows') = 2
             from t_kk_old),
  '09 an old KDS entity list (no order_edits) is served unchanged and carries NO order_edits key');

-- ===== B. price-capable roles on the POS of branch K ==========================
create temp table t_kc as select public.sync_pull('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000d1') as res;
create temp table t_km as select public.sync_pull('b1b00000-0000-0000-0000-000000000092', 'b1b00000-0000-0000-0000-0000000000d1') as res;
create temp table t_ka as select public.sync_pull('b1b00000-0000-0000-0000-000000000094', 'b1b00000-0000-0000-0000-0000000000d1') as res;
create temp table t_ka_x as select public.sync_pull('b1b00000-0000-0000-0000-000000000094', 'b1b00000-0000-0000-0000-0000000000d1',
  array['order_edits']) as res;
create temp table t_kc_x as select public.sync_pull('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000d1',
  array['order_edits', 'orders']) as res;

select is((select pg_temp.keys(res) from t_kc),
  'cash_drawer_sessions,item_sizes,item_variants,menu_categories,menu_items,modifier_options,modifiers,'
  || 'order_edits,order_item_modifiers,order_items,order_service_rounds,orders,payments,shifts,tables',
  '10 cashier (POS) default pull: the business set now includes order_edits, + menu + floor');
select ok((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                  = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
                  and pg_temp.raw_rows(res -> 'changes' -> 'order_edits' -> 'rows')
             from t_kc),
  '11 cashier default pull: order_edits = branch K''s raw edit rows');
select ok((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                  = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
                  and pg_temp.raw_rows(res -> 'changes' -> 'order_edits' -> 'rows')
             from t_km),
  '12 manager default pull: order_edits = branch K''s raw edit rows');
select ok((select (res -> 'changes' ? 'order_edits')
                  and pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                      = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
             from t_ka)
      and (select pg_temp.keys(res) = 'order_edits'
                  and pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                      = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
             from t_ka_x),
  '13 accountant: order_edits in the default pull, and an explicit [order_edits] request is allowed');
select ok((select pg_temp.keys(res) = 'order_edits,orders'
                  and pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                      = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
             from t_kc_x),
  '14 cashier explicit [order_edits, orders]: allowed, exactly those two entities');

-- ===== C. kitchen_staff on a printer_only branch: floor only ==================
create temp table t_pk as select public.sync_pull('b1b00000-0000-0000-0000-000000000098', 'b1b00000-0000-0000-0000-0000000000d4') as res;
select ok((select pg_temp.keys(res) = 'tables'
                  and not (res -> 'changes' ? 'order_edits')
                  and res -> 'operation_statuses' = '{"rows": [], "has_more": false, "next_cursor": null}'::jsonb
             from t_pk),
  '15 kitchen_staff on a printer_only branch: default pull is the floor only (no order_edits key, no op feed)');
select throws_ok($$select public.sync_pull('b1b00000-0000-0000-0000-000000000098', 'b1b00000-0000-0000-0000-0000000000d4',
                    array['order_edits'])$$,
  '42501', 'sync_pull: entity order_edits is not permitted for role kitchen_staff',
  '16 kitchen_staff on a printer_only branch: an explicit [order_edits] request rejects 42501');
select throws_ok($$select public.sync_pull('b1b00000-0000-0000-0000-000000000098', 'b1b00000-0000-0000-0000-0000000000d4',
                    array['tables', 'order_edits'])$$,
  '42501', 'sync_pull: entity order_edits is not permitted for role kitchen_staff',
  '17 ... even alongside a permitted entity (fail closed, never a silently truncated feed)');

-- ===== D. the KDS-DEVICE direct-print filter (branch P) =======================
-- Only the direct_print P1 edit exists on branch P at this point.
create temp table t_pm_kds as select public.sync_pull('b1b00000-0000-0000-0000-000000000099', 'b1b00000-0000-0000-0000-0000000000d4') as res;
create temp table t_pc_kds as select public.sync_pull('b1b00000-0000-0000-0000-00000000009a', 'b1b00000-0000-0000-0000-0000000000d4',
  array['order_edits']) as res;
create temp table t_pm_pos as select public.sync_pull('b1b00000-0000-0000-0000-000000000097', 'b1b00000-0000-0000-0000-0000000000d3',
  array['order_edits']) as res;
create temp table t_pc_pos as select public.sync_pull('b1b00000-0000-0000-0000-000000000096', 'b1b00000-0000-0000-0000-0000000000d3') as res;
create temp table t_pg as select public.sync_pull('b1b00000-0000-0000-0000-000000000099', 'b1b00000-0000-0000-0000-0000000000d4',
  array['order_edits'], '{}'::jsonb, 1) as res;

select ok((select (res -> 'changes' ? 'order_edits')
                  and res -> 'changes' -> 'order_edits' -> 'rows' = '[]'::jsonb
                  and pg_temp.ids(res -> 'changes' -> 'orders' -> 'rows') = 'b1b00000-0000-0000-0000-00000000c002'
             from t_pm_kds),
  '18 a manager PIN on the KDS device: the direct_print order''s edit is NOT served (the order neither; P2 is)');
-- The order id is absent from the WHOLE serialized pull. The filtered edit's
-- own id is absent from every served row; it legitimately survives only as the
-- order_edits next_cursor key (the KITCHEN-PRINT-DUAL-001C cursor-advance
-- design, pinned by 23).
select ok((select res::text not like '%b1b00000-0000-0000-0000-00000000c001%'
                  and not exists (select 1 from jsonb_each(res -> 'changes') e, jsonb_array_elements(e.value -> 'rows') r
                                   where r::text like '%' || pg_temp.eid('b1b00000-0000-0000-0000-00000000c001', 1)::text || '%')
             from t_pm_kds),
  '19 the manager''s KDS pull never mentions the direct_print order id, and no served row carries its edit id');
select ok((select pg_temp.keys(res) = 'order_edits'
                  and res -> 'changes' -> 'order_edits' -> 'rows' = '[]'::jsonb
                  and res::text not like '%b1b00000-0000-0000-0000-00000000c001%'
             from t_pc_kds),
  '20 a cashier PIN on the KDS device, explicit [order_edits]: the direct_print edit is NOT served');
select ok((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                  = pg_temp.eid('b1b00000-0000-0000-0000-00000000c001', 1)::text
                  and pg_temp.raw_rows(res -> 'changes' -> 'order_edits' -> 'rows')
             from t_pm_pos),
  '21 the same manager on the POS device DOES receive the direct_print order''s (paper) edit row');
select ok((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                  = pg_temp.eid('b1b00000-0000-0000-0000-00000000c001', 1)::text
                  and exists (select 1 from jsonb_array_elements(res -> 'changes' -> 'orders' -> 'rows') o
                               where o ->> 'id' = 'b1b00000-0000-0000-0000-00000000c001')
             from t_pc_pos),
  '22 the cashier on the POS device receives the edit row and the direct_print order itself');
select ok((select res -> 'changes' -> 'order_edits' -> 'rows' = '[]'::jsonb
                  and res -> 'changes' -> 'order_edits' -> 'next_cursor' is not null
                  and res -> 'changes' -> 'order_edits' -> 'next_cursor' <> 'null'::jsonb
                  and res -> 'changes' -> 'order_edits' ->> 'has_more' = 'false'
                  and res -> 'changes' -> 'order_edits' -> 'next_cursor' ->> 'id'
                      = pg_temp.eid('b1b00000-0000-0000-0000-00000000c001', 1)::text
                  and (res -> 'changes' -> 'order_edits' -> 'next_cursor' ->> 'updated_at')::timestamptz
                      = (select e.updated_at from order_edits e
                          where e.id = pg_temp.eid('b1b00000-0000-0000-0000-00000000c001', 1))
             from t_pg),
  '23 p_limit 1 where the only row is filtered: rows [] but next_cursor ADVANCES past it (the filtered edit''s key)');

-- P2's edit: a kds-dispatch order on the printer_only branch (paper channel).
insert into t_edits select 'p2', pg_temp.edit('b1b00000-0000-0000-0000-000000000096', 'b1b00000-0000-0000-0000-0000000000d3',
  'p2-e1', 'b1b00000-0000-0000-0000-00000000c002',
  '{"expected": {"subtotal_minor": 2300, "tax_total_minor": 0, "grand_total_minor": 2300},
    "changes": [{"op": "add", "item": {"menu_item_id": "b1b00000-0000-0000-0000-000000001002", "quantity": 1,
      "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola"}}]}'::jsonb);
create temp table t_pm_kds2 as select public.sync_pull('b1b00000-0000-0000-0000-000000000099', 'b1b00000-0000-0000-0000-0000000000d4',
  array['order_edits']) as res;
create temp table t_pm_pos2 as select public.sync_pull('b1b00000-0000-0000-0000-000000000097', 'b1b00000-0000-0000-0000-0000000000d3',
  array['order_edits']) as res;
select ok((select r ->> 'status' = 'applied' from t_edits where k = 'p2')
      and (select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows')
                  = pg_temp.eid('b1b00000-0000-0000-0000-00000000c002', 1)::text
                  and res::text not like '%b1b00000-0000-0000-0000-00000000c001%'
             from t_pm_kds2),
  '24 the filter is selective: the KDS manager now receives the kds-dispatch P2 edit, still never the direct_print P1 edit');
select is((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows') from t_pm_pos2),
  pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ac'),
  '25 the POS manager receives both branch P edits (non-KDS callers are untouched)');

-- ===== E. the kitchen acknowledgement reaches the pull =======================
create temp table t_ack as select pg_temp.ack('b1b00000-0000-0000-0000-000000000093', 'b1b00000-0000-0000-0000-0000000000d2',
  'k1-ack', 'b1b00000-0000-0000-0000-00000000a001', '{"up_to_edit_number": 1}'::jsonb) as r;
create temp table t_kk2 as select public.sync_pull('b1b00000-0000-0000-0000-000000000093', 'b1b00000-0000-0000-0000-0000000000d2',
  array['order_edits']) as res;
create temp table t_kc2 as select public.sync_pull('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000d1',
  array['order_edits']) as res;

select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack),
  '26 order.edit_ack (kitchen_staff, KDS) on K1 edit 1 is applied: acknowledged_count 1');
select ok((select r -> 'kitchen_ack_at' = 'null'::jsonb
             from t_kk, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows') r
            where r ->> 'id' = pg_temp.eid('b1b00000-0000-0000-0000-00000000a001', 1)::text)
      and (select r ->> 'kitchen_ack_at' is not null
                  and (r ->> 'kitchen_ack_at')::timestamptz = now()
                  and r ->> 'kitchen_ack_by_employee_profile_id' = 'b1b00000-0000-0000-0000-000000000083'
                  and r ->> 'kitchen_ack_device_id' = 'b1b00000-0000-0000-0000-0000000000d2'
             from t_kk2, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows') r
            where r ->> 'id' = pg_temp.eid('b1b00000-0000-0000-0000-00000000a001', 1)::text),
  '27 a fresh kitchen pull shows the K1 edit stamped (kitchen_ack_at, ack employee, ack device); the earlier pull did not');
select ok((select r -> 'kitchen_ack_at' = 'null'::jsonb and r -> 'kitchen_ack_by_employee_profile_id' = 'null'::jsonb
             from t_kk2, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows') r
            where r ->> 'id' = pg_temp.eid('b1b00000-0000-0000-0000-00000000a002', 1)::text)
      and (select pg_temp.raw_rows(res -> 'changes' -> 'order_edits' -> 'rows') from t_kk2),
  '28 the un-acknowledged K2 edit is still pending, and the post-ack kitchen rows are still byte-equal raw rows');
select ok((select r ->> 'kitchen_ack_at' is not null
                  and r ->> 'kitchen_ack_by_employee_profile_id' = 'b1b00000-0000-0000-0000-000000000083'
             from t_kc2, jsonb_array_elements(res -> 'changes' -> 'order_edits' -> 'rows') r
            where r ->> 'id' = pg_temp.eid('b1b00000-0000-0000-0000-00000000a001', 1)::text),
  '29 the POS cashier''s pull sees the acknowledgement too (it writes no orders row)');

-- ===== F. isolation ==========================================================
create temp table t_b as select public.sync_pull('b1b00000-0000-0000-0000-0000000000b9', 'b1b00000-0000-0000-0000-0000000000bd',
  array['order_edits']) as res;
create temp table t_all_a as
  select 'kk' as k, res from t_kk union all select 'kk_x', res from t_kk_x union all select 'kk2', res from t_kk2
  union all select 'kc', res from t_kc union all select 'kc_x', res from t_kc_x union all select 'kc2', res from t_kc2
  union all select 'km', res from t_km union all select 'ka', res from t_ka union all select 'ka_x', res from t_ka_x
  union all select 'pk', res from t_pk union all select 'pm_kds', res from t_pm_kds union all select 'pc_kds', res from t_pc_kds
  union all select 'pm_pos', res from t_pm_pos union all select 'pc_pos', res from t_pc_pos union all select 'pg', res from t_pg
  union all select 'pm_kds2', res from t_pm_kds2 union all select 'pm_pos2', res from t_pm_pos2;

select ok((select count(*) = 17 from t_all_a)
      and not exists (select 1 from t_all_a
                       where res::text like '%' || pg_temp.eid('b1b00000-0000-0000-0000-00000000b0b1', 1)::text || '%'
                          or res::text like '%b1b00000-0000-0000-0000-00000000b0b1%'),
  '30 the second organization''s edit (and order) never appears in any org A pull');
select ok(not exists (select 1 from t_all_a
                       where k in ('kk', 'kk_x', 'kk2', 'kc', 'kc_x', 'kc2', 'km', 'ka', 'ka_x')
                         and (res::text like '%' || pg_temp.eid('b1b00000-0000-0000-0000-00000000c001', 1)::text || '%'
                              or res::text like '%' || pg_temp.eid('b1b00000-0000-0000-0000-00000000c002', 1)::text || '%')),
  '31 the sibling branch P''s edits never appear in a branch K pull (strict branch scope)');
select ok(not exists (select 1 from t_all_a
                       where k in ('pk', 'pm_kds', 'pc_kds', 'pm_pos', 'pc_pos', 'pg', 'pm_kds2', 'pm_pos2')
                         and (res::text like '%' || pg_temp.eid('b1b00000-0000-0000-0000-00000000a001', 1)::text || '%'
                              or res::text like '%' || pg_temp.eid('b1b00000-0000-0000-0000-00000000a002', 1)::text || '%')),
  '32 the sibling branch K''s edits never appear in a branch P pull');
select is((select pg_temp.ids(res -> 'changes' -> 'order_edits' -> 'rows') from t_b),
  pg_temp.eid('b1b00000-0000-0000-0000-00000000b0b1', 1)::text,
  '33 the second organization''s own pull carries exactly its own edit');

-- ===== G. app.sync_pull_changes + entity validation ==========================
create temp table t_pc_k as select app.sync_pull_changes('order_edits', 'b1b00000-0000-0000-0000-0000000000a0',
  'b1b00000-0000-0000-0000-0000000000ab', null, null, 10) as res;
create temp table t_pc_k1 as select app.sync_pull_changes('order_edits', 'b1b00000-0000-0000-0000-0000000000a0',
  'b1b00000-0000-0000-0000-0000000000ab', null, null, 1) as res;
create temp table t_pc_p as select app.sync_pull_changes('order_edits', 'b1b00000-0000-0000-0000-0000000000a0',
  'b1b00000-0000-0000-0000-0000000000ac', null, null, 10) as res;
create temp table t_pc_x as select app.sync_pull_changes('order_edits', 'b1b00000-0000-0000-0000-0000000000b0',
  'b1b00000-0000-0000-0000-0000000000ab', null, null, 10) as res;

select ok((select pg_temp.ids(res -> 'rows')
                  = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ab')
                  and pg_temp.raw_rows(res -> 'rows')
                  and res ->> 'has_more' = 'false'
                  and res -> 'next_cursor' <> 'null'::jsonb
             from t_pc_k),
  '34 app.sync_pull_changes(order_edits, org, branch K) called directly pages the branch''s raw edit rows');
select ok((select jsonb_array_length(res -> 'rows') = 1 and res ->> 'has_more' = 'true'
                  and res -> 'next_cursor' ->> 'id' = res -> 'rows' -> 0 ->> 'id'
             from t_pc_k1),
  '35 the pager''s limit + lookahead: limit 1 over two rows -> one row, has_more, cursor at that row');
select ok((select pg_temp.ids(res -> 'rows')
                  = pg_temp.branch_edit_ids('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000ac')
                  and res::text like '%b1b00000-0000-0000-0000-00000000c001%'
             from t_pc_p)
      and (select res -> 'rows' = '[]'::jsonb and res -> 'next_cursor' = 'null'::jsonb from t_pc_x),
  '36 the pager is strict-branch + org (no dispatch awareness: the KDS filter lives in sync_pull); a foreign org pairs to nothing');
select throws_ok($$select app.sync_pull_changes('order_editz', 'b1b00000-0000-0000-0000-0000000000a0',
                    'b1b00000-0000-0000-0000-0000000000ab', null, null, 10)$$,
  '42501', 'sync_pull_changes: order_editz is not a pull-allowed entity',
  '37 app.sync_pull_changes still rejects an unknown table name 42501');
select throws_ok($$select public.sync_pull('b1b00000-0000-0000-0000-000000000091', 'b1b00000-0000-0000-0000-0000000000d1',
                    array['order_edit'])$$,
  '42501', 'sync_pull: unknown entity order_edit',
  '38 sync_pull still rejects an unknown entity name (order_edit, singular) 42501');

-- ===== H. ACLs and function attributes unchanged ==============================
select ok(has_function_privilege('authenticated', 'app.sync_pull(uuid, uuid, text[], jsonb, integer)', 'EXECUTE')
      and not has_function_privilege('anon', 'app.sync_pull(uuid, uuid, text[], jsonb, integer)', 'EXECUTE')
      and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                       where p.oid = 'app.sync_pull(uuid, uuid, text[], jsonb, integer)'::regprocedure
                         and a.grantee = 0),
  '39 app.sync_pull: EXECUTE for authenticated, not anon, no PUBLIC grant');
select ok(not has_function_privilege('authenticated', 'app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer)', 'EXECUTE')
      and not has_function_privilege('anon', 'app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer)', 'EXECUTE')
      and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                       where p.oid = 'app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer)'::regprocedure
                         and a.grantee = 0),
  '40 app.sync_pull_changes: NOT executable by authenticated / anon, no PUBLIC grant');
select ok((select bool_and(p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""'])
             from pg_proc p
            where p.oid in ('app.sync_pull(uuid, uuid, text[], jsonb, integer)'::regprocedure,
                            'app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer)'::regprocedure)),
  '41 both re-emits are still SECURITY DEFINER, VOLATILE, search_path=''''');
select ok(not exists (select 1 from audit_events
                       where organization_id in ('b1b00000-0000-0000-0000-0000000000a0', 'b1b00000-0000-0000-0000-0000000000b0')
                         and action not in ('order.edited', 'order.edit_acknowledged', 'kitchen.dispatch_created')),
  '42 the pulls wrote no audit event (only the edits, the ack and the paper dispatches audit)');

select * from finish();
rollback;
