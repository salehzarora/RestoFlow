-- ============================================================================
-- KIOSK-001 Phase 2 — pgTAP: the kiosk device security foundation.
--
-- Matrix: device-type contract (kiosk accepted, pos/kds preserved, invalid
-- rejected; redeem allowlist), token proof failure modes (wrong/revoked/
-- expired/foreign/non-kiosk), scope derivation + cross-org/branch/sibling
-- exclusion (R-003), kiosk_menu projection (customer keys ONLY; pos_menu
-- parity), kiosk_tables projection (effective_state only), kiosk_submit_order
-- (actor-null orders, unpaid, audit device actor, validation refusals,
-- idempotency ledger + business replay, the atomic no-hold table gate),
-- POS actor preservation, the staff-PIN privilege boundary, pay-later, POS
-- projection + KDS pull visibility, revocation cutting access, the ACL /
-- constraint surface, and the HARDENING-FIX-073 untrusted-client matrix
-- (forged item/option prices, modifier group rules, self-applied discounts,
-- non-tenant currency, invented tax, forged display names, actorless-order
-- device guard). Fixtures inserted as the BYPASSRLS harness role; device
-- calls run as an ANONYMOUS authenticated principal (GUC '').
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(105);

-- ===== fixture: Org A (Rest A1: branch A1a device-branch, A1b sibling); Org B
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-007100000a00', 'Org A', 'kiosk1-a', 'ILS'),
  ('00000000-0000-0000-0000-007100000b00', 'Org B', 'kiosk1-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a00', 'Rest A1'),
  ('00000000-0000-0000-0000-007100000b10', '00000000-0000-0000-0000-007100000b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-007100000a1b', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', 'Branch A1b'),
  ('00000000-0000-0000-0000-007100000b1a', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', 'Branch B1a');

-- devices: kiosk K1 (live tok), K1's revoked session, kiosk K3 EXPIRED session,
-- kiosk K2 (second kiosk), POS P1 (live tok + PIN sessions), kiosk KB @ Org B.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-007100004001', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'kiosk', 'Kiosk One'),
  ('00000000-0000-0000-0000-007100004002', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'kiosk', 'Kiosk Two'),
  ('00000000-0000-0000-0000-007100004003', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'kiosk', 'Kiosk Expired'),
  ('00000000-0000-0000-0000-007100004004', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'pos',   'Front POS'),
  ('00000000-0000-0000-0000-007100004005', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', '00000000-0000-0000-0000-007100000b1a', 'kiosk', 'OrgB Kiosk');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-007100004011', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004001', 'active'),
  ('00000000-0000-0000-0000-007100004012', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004002', 'active'),
  ('00000000-0000-0000-0000-007100004013', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004003', 'active'),
  ('00000000-0000-0000-0000-007100004014', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004004', 'active'),
  ('00000000-0000-0000-0000-007100004015', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', '00000000-0000-0000-0000-007100000b1a', '00000000-0000-0000-0000-007100004005', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at, expires_at) values
  ('00000000-0000-0000-0000-007100004051', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004001', '00000000-0000-0000-0000-007100004011', app.hash_provisioning_secret('tok-kiosk-a'),       true,  null,  now() + interval '1 day'),
  ('00000000-0000-0000-0000-007100004052', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004001', '00000000-0000-0000-0000-007100004011', app.hash_provisioning_secret('tok-kiosk-revoked'), false, now(), now() + interval '1 day'),
  ('00000000-0000-0000-0000-007100004053', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004003', '00000000-0000-0000-0000-007100004013', app.hash_provisioning_secret('tok-kiosk-expired'), true,  null,  now() - interval '1 minute'),
  ('00000000-0000-0000-0000-007100004054', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004002', '00000000-0000-0000-0000-007100004012', app.hash_provisioning_secret('tok-kiosk-b'),       true,  null,  now() + interval '1 day'),
  ('00000000-0000-0000-0000-007100004055', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004004', '00000000-0000-0000-0000-007100004014', app.hash_provisioning_secret('tok-pos-a'),         true,  null,  now() + interval '1 day'),
  ('00000000-0000-0000-0000-007100004056', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', '00000000-0000-0000-0000-007100000b1a', '00000000-0000-0000-0000-007100004005', '00000000-0000-0000-0000-007100004015', app.hash_provisioning_secret('tok-kiosk-orgb'),    true,  null,  now() + interval '1 day');

-- staff fixtures (POS actor preservation + pay-later + KDS pull): a cashier
-- and a kitchen principal with direct pin_sessions rows (harness shape).
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0071000eea01', 'k1-cashier@example.test'),
  ('00000000-0000-0000-0000-0071000eea02', 'k1-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0071000aba01', '00000000-0000-0000-0000-0071000eea01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'cashier'),
  ('00000000-0000-0000-0000-0071000aba02', '00000000-0000-0000-0000-0071000eea02', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0071000efa01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-0071000eea01', '00000000-0000-0000-0000-0071000aba01'),
  ('00000000-0000-0000-0000-0071000efa02', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-0071000eea02', '00000000-0000-0000-0000-0071000aba02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0071000c5a01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004055', '00000000-0000-0000-0000-0071000efa01', '00000000-0000-0000-0000-0071000aba01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0071000c5a02', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004055', '00000000-0000-0000-0000-0071000efa02', '00000000-0000-0000-0000-0071000aba02', now() + interval '1 hour');

-- menu: category (icon_key) -> items; one branch-availability override; one
-- sibling-branch pin; one inactive; one Org B item; modifiers on the burger
-- (required single 'weight': Classic 0 / Double +1500 with kitchen_meat).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active, icon_key) values
  ('00000000-0000-0000-0000-0071000c1a00', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, 'Burgers', 0, true, 'burger'),
  ('00000000-0000-0000-0000-0071000c1b00', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', null, 'OrgB Cat', 0, true, null);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active, sku, prep_minutes, kitchen_note, attributes, image_path) values
  ('00000000-0000-0000-0000-0071000117a1', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000c1a00', 'Burger', 4000, 'ILS', 0, true, 'SKU-SECRET', 12, 'internal note', '{"prep_components":[{"name":"bun","quantity":1,"unit":"pc"}]}'::jsonb, 'orgA/restA1/global/menu_item/x/y.jpg'),
  ('00000000-0000-0000-0000-0071000117a2', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000c1a00', 'Cola', 1000, 'ILS', 1, true, null, null, null, null, null),
  ('00000000-0000-0000-0000-0071000117a3', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000c1a00', 'PausedItem', 900, 'ILS', 2, true, null, null, null, null, null),
  ('00000000-0000-0000-0000-0071000117a4', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1b', '00000000-0000-0000-0000-0071000c1a00', 'SiblingOnly', 800, 'ILS', 3, true, null, null, null, null, null),
  ('00000000-0000-0000-0000-0071000117a5', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000c1a00', 'DeadItem', 700, 'ILS', 4, false, null, null, null, null, null),
  ('00000000-0000-0000-0000-0071000117b1', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', null, '00000000-0000-0000-0000-0071000c1b00', 'OrgB Item', 5000, 'EUR', 0, true, null, null, null, null, null);
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-0071000117a3', 'unavailable', 'sold_out');
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active) values
  ('00000000-0000-0000-0000-0071000d1a01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000117a1', 'Weight', 'single', 1, 1, true, true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat) values
  ('00000000-0000-0000-0000-0071000d2a01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a01', 'Classic', 0,    0, true, null),
  ('00000000-0000-0000-0000-0071000d2a02', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a01', 'Double',  1500, 1, true, '{"quantity":2,"unit":"pc"}'::jsonb);
-- HARDENING-FIX-073 fixtures: an INACTIVE option inside the live Weight group;
-- a DEAD Burger group carrying a live-flagged option; a quantity-enabled
-- Extras group (multiple, per-option cap 2); and a Salad whose REQUIRED Mix
-- group demands exactly 2 distinct picks.
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('00000000-0000-0000-0000-0071000d2a03', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a01', 'Rare', 0, 2, false);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, allow_quantity, max_quantity) values
  ('00000000-0000-0000-0000-0071000d1a02', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000117a1', 'DeadExtras', 'multiple', 0, null, false, false, false, null),
  ('00000000-0000-0000-0000-0071000d1a03', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000117a1', 'Extras',     'multiple', 0, null, false, true,  true,  2);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('00000000-0000-0000-0000-0071000d2a04', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a02', 'DeadOpt', 0,   0, true),
  ('00000000-0000-0000-0000-0071000d2a05', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a03', 'Sauce',   200, 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('00000000-0000-0000-0000-0071000117a6', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000c1a00', 'Salad', 800, 'ILS', 5, true);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active) values
  ('00000000-0000-0000-0000-0071000d1a04', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000117a6', 'Mix', 'multiple', 2, 2, true, true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('00000000-0000-0000-0000-0071000d2a06', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a04', 'MixA', 0, 0, true),
  ('00000000-0000-0000-0000-0071000d2a07', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a04', 'MixB', 0, 1, true),
  ('00000000-0000-0000-0000-0071000d2a08', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', null, '00000000-0000-0000-0000-0071000d1a04', 'MixC', 0, 2, true);

-- an Org B option (for the ownership refusal)
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, is_active) values
  ('00000000-0000-0000-0000-0071000d1b01', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', null, '00000000-0000-0000-0000-0071000117b1', 'B Mod', 'single', true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
  ('00000000-0000-0000-0000-0071000d2b01', '00000000-0000-0000-0000-007100000b00', '00000000-0000-0000-0000-007100000b10', null, '00000000-0000-0000-0000-0071000d1b01', 'B Opt', 0, 0, true);

-- tables @ A1a: T1 available, T2 manual occupied, T3 reserved, T4 out_of_service,
-- T5 available-manual but occupied via a live staff dine-in order; T6 @ sibling.
insert into table_sections (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-007100051a01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'Hall', 0);
insert into tables (id, organization_id, restaurant_id, branch_id, label, seats, status, is_active, section_id) values
  ('00000000-0000-0000-0000-007100071a01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'T1', 4, 'available',      true, '00000000-0000-0000-0000-007100051a01'),
  ('00000000-0000-0000-0000-007100071a02', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'T2', 2, 'occupied',       true, '00000000-0000-0000-0000-007100051a01'),
  ('00000000-0000-0000-0000-007100071a03', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'T3', 4, 'reserved',       true, '00000000-0000-0000-0000-007100051a01'),
  ('00000000-0000-0000-0000-007100071a04', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'T4', 4, 'out_of_service', true, '00000000-0000-0000-0000-007100051a01'),
  ('00000000-0000-0000-0000-007100071a05', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', 'T5', 6, 'available',      true, '00000000-0000-0000-0000-007100051a01'),
  ('00000000-0000-0000-0000-007100071a06', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1b', 'T6', 4, 'available',      true, null);
-- the live STAFF dine-in order occupying T5 (full actor triple, as today).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, table_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-007100005a01', '00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a', '00000000-0000-0000-0000-007100004004', '00000000-0000-0000-0000-0071000c5a01', '00000000-0000-0000-0000-0071000efa01', '00000000-0000-0000-0000-0071000aba01', '00000000-0000-0000-0000-007100071a05', 'dine_in', 'submitted', 'ILS', 1000, 1000, 'staff-t5-occupier');

create temp table _res (label text primary key, r jsonb);
grant select, insert on _res to authenticated;

-- the CORRECT frozen prep snapshot for (Burger, Double), captured as the
-- harness role (the trusted helper is app-internal; G7 replays it as a client).
create temp table _snap as select app.trusted_modifier_prep_snapshot(
  '00000000-0000-0000-0000-007100000a00',
  '00000000-0000-0000-0000-0071000117a1',
  '00000000-0000-0000-0000-0071000d2a02',
  jsonb_build_array(jsonb_build_object(
    'modifier_option_id', '00000000-0000-0000-0000-0071000d2a02'))) as v;
grant select on _snap to authenticated;

-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '';   -- anonymous authenticated device

-- ---- A. device-type contract + token proof failure modes (1-10) ------------
select is((app.redeem_device_pairing('no-such-code', 'kiosk') ->> 'error'),
  'invalid_code', 'A1: redeem accepts declared type kiosk (fails later on the code, not the type)');
select is((app.redeem_device_pairing('no-such-code', 'tablet') ->> 'error'),
  'invalid_type', 'A2: redeem still refuses an unknown declared type');
select is((app.kiosk_menu(null, 'tok-kiosk-a') ->> 'error'),
  'invalid_session', 'A3: NULL device_id fails closed');
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004001', '   ') ->> 'error'),
  'invalid_session', 'A4: blank token fails closed');
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004001', 'wrong-token') ->> 'error'),
  'invalid_session', 'A5: wrong token fails closed (no scope leak)');
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004001', 'tok-kiosk-revoked') ->> 'error'),
  'invalid_session', 'A6: REVOKED session fails closed');
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004003', 'tok-kiosk-expired') ->> 'error'),
  'invalid_session', 'A7: EXPIRED session fails closed (RF-118)');
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004001', 'tok-kiosk-b') ->> 'error'),
  'invalid_session', 'A8: another device''s token does not open this device');
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004004', 'tok-pos-a') ->> 'error'),
  'invalid_session', 'A9: a NON-KIOSK (pos) device token is refused by the kiosk read family');
select is((app.kiosk_tables('00000000-0000-0000-0000-007100004004', 'tok-pos-a') ->> 'error'),
  'invalid_session', 'A10: the pos token is refused by kiosk_tables too');

-- ---- B. kiosk_menu projection (11-22) --------------------------------------
insert into _res values ('menu',
  public.kiosk_menu('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a'));
select ok((select (r ->> 'ok')::boolean from _res where label = 'menu'),
  'B1: kiosk_menu succeeds on a live kiosk token (via the public wrapper)');
select is((select r ->> 'currency_code' from _res where label = 'menu'), 'ILS',
  'B2: the tenant currency rides the envelope');
select ok((select r -> 'categories' @> '[{"icon_key":"burger"}]' from _res where label = 'menu'),
  'B3: categories carry icon_key');
select ok((select exists (select 1 from jsonb_array_elements(r -> 'items') i
             where i ->> 'id' = '00000000-0000-0000-0000-0071000117a1'
               and (i ->> 'base_price_minor')::bigint = 4000
               and i ? 'image_path' and i ? 'availability') from _res where label = 'menu'),
  'B4: the burger is served with its integer minor price, image reference and availability');
select ok((select not exists (select 1 from jsonb_array_elements(r -> 'items') i
             where i ? 'sku' or i ? 'prep_minutes' or i ? 'kitchen_note' or i ? 'attributes'
                or i ? 'default_station_id') from _res where label = 'menu'),
  'B5: NO staff/kitchen-internal item keys (sku/prep_minutes/kitchen_note/attributes/station)');
select ok((select not (r ? 'sizes') and not (r ? 'variants') from _res where label = 'menu'),
  'B6: legacy sizes/variants are not served to customers');
select ok((select exists (select 1 from jsonb_array_elements(r -> 'items') i
             where i ->> 'id' = '00000000-0000-0000-0000-0071000117a3'
               and i ->> 'availability' = 'unavailable'
               and i ->> 'availability_reason' = 'sold_out') from _res where label = 'menu'),
  'B7: an unavailable item stays visible WITH its structured reason');
select ok((select not exists (select 1 from jsonb_array_elements(r -> 'items') i
             where i ->> 'id' in ('00000000-0000-0000-0000-0071000117a4',
                                  '00000000-0000-0000-0000-0071000117a5',
                                  '00000000-0000-0000-0000-0071000117b1')) from _res where label = 'menu'),
  'B8: sibling-branch, inactive and FOREIGN-ORG items are excluded (R-003)');
select ok((select exists (select 1 from jsonb_array_elements(r -> 'modifiers') m
             where m ->> 'id' = '00000000-0000-0000-0000-0071000d1a01'
               and (m ->> 'is_required')::boolean) from _res where label = 'menu'),
  'B9: modifier groups carry the selection contract');
select ok((select exists (select 1 from jsonb_array_elements(r -> 'modifier_options') o
             where o ->> 'id' = '00000000-0000-0000-0000-0071000d2a02'
               and (o ->> 'price_delta_minor')::bigint = 1500
               and o ? 'kitchen_meat') from _res where label = 'menu'),
  'B10: options carry the signed delta AND kitchen_meat (the 021 frozen-prep contract)');
select ok((select not exists (select 1 from jsonb_array_elements(r -> 'modifier_options') o
             where o ->> 'id' = '00000000-0000-0000-0000-0071000d2b01') from _res where label = 'menu'),
  'B11: a foreign-org option never appears');
-- parity: the kiosk item id set equals the pos_menu (cashier) item id set.
select ok((
  select (select array_agg(i ->> 'id' order by i ->> 'id')
            from jsonb_array_elements((select r from _res where label = 'menu') -> 'items') i)
       = (select array_agg(i ->> 'id' order by i ->> 'id')
            from jsonb_array_elements(
              app.pos_menu('00000000-0000-0000-0000-0071000c5a01',
                           '00000000-0000-0000-0000-007100004004') -> 'items') i)),
  'B12: kiosk_menu serves EXACTLY the pos_menu sellable item set (parity)');

-- ---- C. kiosk_tables projection (23-28) ------------------------------------
insert into _res values ('tables',
  public.kiosk_tables('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a'));
select ok((select (r ->> 'ok')::boolean from _res where label = 'tables'),
  'C1: kiosk_tables succeeds on a live kiosk token');
select is((select t ->> 'effective_state' from _res,
             jsonb_array_elements(r -> 'tables') t
             where label = 'tables' and t ->> 'label' = 'T1'), 'available',
  'C2: an untouched available table reads available');
select ok((select (select t ->> 'effective_state' from jsonb_array_elements(r -> 'tables') t where t ->> 'label' = 'T2') = 'occupied'
              and (select t ->> 'effective_state' from jsonb_array_elements(r -> 'tables') t where t ->> 'label' = 'T3') = 'reserved'
              and (select t ->> 'effective_state' from jsonb_array_elements(r -> 'tables') t where t ->> 'label' = 'T4') = 'out_of_service'
            from _res where label = 'tables'),
  'C3: manual occupied/reserved/out_of_service surface honestly');
select is((select t ->> 'effective_state' from _res,
             jsonb_array_elements(r -> 'tables') t
             where label = 'tables' and t ->> 'label' = 'T5'), 'occupied',
  'C4: DERIVED occupancy (a live staff dine-in order) reads occupied');
select ok((select not exists (select 1 from jsonb_array_elements(r -> 'tables') t
             where t ->> 'label' = 'T6') from _res where label = 'tables'),
  'C5: a sibling-branch table is never served');
select ok((select not exists (select 1 from jsonb_array_elements(r -> 'tables') t
             where t ? 'status' or t ? 'active_order_count' or t ? 'layout_x' or t ? 'group_id')
            from _res where label = 'tables'),
  'C6: no raw manual status / counts / geometry / groups reach the customer');

-- ---- D. kiosk_submit_order: happy takeaway (29-40) -------------------------
insert into _res values ('sub1',
  public.kiosk_submit_order(
    '00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d01', 'kiosk-op-1',
    'takeaway', null, 'ILS', null, 'Sami', '050 123 4567',
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 2,
      'unit_price_minor_snapshot', 1000)),
    2000, 0, 0, 2000));
-- back to the HARNESS role: everything below asserts persisted DB state
-- directly, and RLS + table grants rightly hide those tables from the client
-- role (the RPC calls themselves stay valid from any role — their authority is
-- the token/PIN parameter, never the caller role).
reset role;
select ok((select (r ->> 'ok')::boolean from _res where label = 'sub1'),
  'D1: a valid kiosk takeaway submit succeeds WITHOUT any PIN session');
select is((select r ->> 'order_status' from _res where label = 'sub1'), 'submitted',
  'D2: the order enters the normal submitted state');
select ok((select o.pin_session_id is null and o.opened_by_employee_profile_id is null
              and o.resolved_membership_id is null
            from orders o where o.id = '00000000-0000-0000-0000-0071000a1d01'),
  'D3: the staff actor triple is NULL on a kiosk order (owner decision A)');
select ok((select o.device_id = '00000000-0000-0000-0000-007100004001' and o.shift_id is null
            from orders o where o.id = '00000000-0000-0000-0000-0071000a1d01'),
  'D4: the kiosk device is the recorded device; no shift is attached');
select ok((select o.customer_name = 'Sami' and o.customer_phone = '050 123 4567'
            from orders o where o.id = '00000000-0000-0000-0000-0071000a1d01'),
  'D5: optional customer name/phone are stamped');
select ok((select o.subtotal_minor = 2000 and o.grand_total_minor = 2000 and o.currency_code = 'ILS'
            from orders o where o.id = '00000000-0000-0000-0000-0071000a1d01'),
  'D6: integer minor totals recomputed + persisted');
select is((select count(*)::int from order_items oi
            where oi.order_id = '00000000-0000-0000-0000-0071000a1d01'), 1,
  'D7: the line lands with the order');
select is((select count(*)::int from payments p
            where p.order_id = '00000000-0000-0000-0000-0071000a1d01'), 0,
  'D8: NO payment row — the kiosk order is unpaid (pay-at-cashier)');
select ok((select so.status = 'applied' and so.operation_type = 'kiosk.order.submit'
            from sync_operations so
            where so.device_id = '00000000-0000-0000-0000-007100004001'
              and so.local_operation_id = 'kiosk-op-1'),
  'D9: the transport ledger row is claimed + finalized applied (D-022)');
select ok((select ae.actor_app_user_id is null and ae.actor_employee_profile_id is null
              and ae.device_id = '00000000-0000-0000-0000-007100004001'
              and ae.new_values ->> 'actor_kind' = 'kiosk_device'
            from audit_events ae
            where ae.action = 'kiosk.order.submitted'
              and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0071000a1d01'),
  'D10: the append-only audit row names the kiosk DEVICE as the actor');
select is((select count(*)::int from audit_events ae
            where ae.action = 'kiosk.order.submitted'
              and ae.new_values ->> 'order_id' = '00000000-0000-0000-0000-0071000a1d01'), 1,
  'D11: exactly ONE audit row for the submit');
select ok((select (r ->> 'idempotency_replay')::boolean = false from _res where label = 'sub1'),
  'D12: the first acceptance is not a replay');

-- ---- E. idempotency (41-45) ------------------------------------------------
insert into _res values ('sub1r',
  public.kiosk_submit_order(
    '00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d01', 'kiosk-op-1',
    'takeaway', null, 'ILS', null, 'Sami', '050 123 4567',
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 2,
      'unit_price_minor_snapshot', 1000)),
    2000, 0, 0, 2000));
select ok((select (r ->> 'ok')::boolean and (r ->> 'idempotency_replay')::boolean
            from _res where label = 'sub1r'),
  'E1: the exact replay returns the stored success as a replay');
select is((select r ->> 'order_id' from _res where label = 'sub1r'),
  '00000000-0000-0000-0000-0071000a1d01',
  'E2: the replay names the SAME order');
select is((select count(*)::int from orders o
            where o.device_id = '00000000-0000-0000-0000-007100004001'
              and o.local_operation_id = 'kiosk-op-1'), 1,
  'E3: no duplicate order exists');
-- a DIFFERENT payload under the SAME key must be refused, not applied.
insert into _res values ('sub1x',
  public.kiosk_submit_order(
    '00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d99', 'kiosk-op-1',
    'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1,
      'unit_price_minor_snapshot', 1000)),
    1000, 0, 0, 1000));
select is((select r ->> 'error' from _res where label = 'sub1x'), 'conflict',
  'E4: the reused idempotency key with a different payload is a stable conflict');
select ok(not exists (select 1 from orders o where o.id = '00000000-0000-0000-0000-0071000a1d99'),
  'E5: the conflicting submit created nothing');

-- ---- F. the atomic no-hold table gate (46-53) ------------------------------
create temp table _line as select jsonb_build_array(jsonb_build_object(
  'menu_item_id', '00000000-0000-0000-0000-0071000117a2',
  'menu_item_name_snapshot', 'Cola', 'quantity', 1,
  'unit_price_minor_snapshot', 1000)) as items;
grant select on _line to authenticated;

select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d72', 'kiosk-op-t2', 'dine_in',
    '00000000-0000-0000-0000-007100071a02', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_no_longer_available',
  'F1: a manually OCCUPIED table is refused with the stable kiosk conflict');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d73', 'kiosk-op-t3', 'dine_in',
    '00000000-0000-0000-0000-007100071a03', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_no_longer_available',
  'F2: a RESERVED table is refused (customers never consume reservations)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d74', 'kiosk-op-t4', 'dine_in',
    '00000000-0000-0000-0000-007100071a04', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_not_available',
  'F3: an OUT-OF-SERVICE table is the generic structural refusal (same as POS)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d75', 'kiosk-op-t5', 'dine_in',
    '00000000-0000-0000-0000-007100071a05', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_no_longer_available',
  'F4: DERIVED occupancy (live staff order) is refused under the row lock');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d76', 'kiosk-op-t6', 'dine_in',
    '00000000-0000-0000-0000-007100071a06', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_not_available',
  'F5: a SIBLING-BRANCH table is indistinguishable from unknown (R-003)');
-- kiosk A takes T1; kiosk B then loses T1 with the conflict refusal.
insert into _res values ('dine1',
  public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d02', 'kiosk-op-2', 'dine_in',
    '00000000-0000-0000-0000-007100071a01', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000));
select ok((select (r ->> 'ok')::boolean from _res where label = 'dine1'),
  'F6: kiosk A seats the AVAILABLE table T1');
select ok((select o.table_id = '00000000-0000-0000-0000-007100071a01' and o.order_type = 'dine_in'
            from orders o where o.id = '00000000-0000-0000-0000-0071000a1d02'),
  'F7: the dine-in order carries its table');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004002', 'tok-kiosk-b',
    '00000000-0000-0000-0000-0071000a1d03', 'kiosk-op-3', 'dine_in',
    '00000000-0000-0000-0000-007100071a01', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_no_longer_available',
  'F8: the SECOND kiosk loses the same table with the stable conflict (A wins, B refused)');

-- ---- G. validation refusals (54-59) ----------------------------------------
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1df1', 'kiosk-op-v1', 'takeaway',
    '00000000-0000-0000-0000-007100071a01', 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_not_allowed', 'G1: takeaway with a table is refused (shape rule)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1df2', 'kiosk-op-v2', 'dine_in',
    null, 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'table_required', 'G2: dine-in without a table is refused (shape rule)');
select throws_ok(
  $$select public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
      '00000000-0000-0000-0000-0071000a1df3', 'kiosk-op-v3', 'takeaway', null, 'ILS', null, null, null,
      (select jsonb_build_array(jsonb_build_object(
        'menu_item_id', '00000000-0000-0000-0000-0071000117a2',
        'menu_item_name_snapshot', 'Cola', 'quantity', 1,
        'unit_price_minor_snapshot', 1000))), 999, 0, 0, 999)$$,
  '42501', null, 'G3: a client subtotal that contradicts the snapshots is refused (D-007/D-008)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1df4', 'kiosk-op-v4', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a3',
      'menu_item_name_snapshot', 'PausedItem', 'quantity', 1,
      'unit_price_minor_snapshot', 900)),
    900, 0, 0, 900)) ->> 'error'),
  'item_unavailable', 'G4: an unavailable item is refused at acceptance');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1df5', 'kiosk-op-v5', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1,
      'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2b01',
        'modifier_name_snapshot', 'B Mod', 'option_name_snapshot', 'B Opt',
        'price_minor_snapshot', 0)))),
    4000, 0, 0, 4000)) ->> 'error'),
  'modifier_option_not_in_scope', 'G5: a FOREIGN-ORG modifier option is refused (003D)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1df6', 'kiosk-op-v6', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1,
      'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
        'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double',
        'price_minor_snapshot', 1500,
        'meat_snapshot', jsonb_build_object('quantity', 99, 'unit', 'pc'))))),
    5500, 0, 0, 5500)) ->> 'error'),
  'modifier_prep_snapshot_stale', 'G6: a forged/stale frozen prep snapshot is refused (021)');

-- a CORRECT frozen snapshot passes end-to-end (the 021 contract, kiosk side).
insert into _res values ('sub2',
  public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1d04', 'kiosk-op-4', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object(
      'menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1,
      'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
        'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double',
        'price_minor_snapshot', 1500,
        'meat_snapshot', (select v from _snap))))),
    5500, 0, 0, 5500));
select ok((select (r ->> 'ok')::boolean from _res where label = 'sub2'),
  'G7: the matching frozen prep snapshot is accepted (modifier order + meat intact)');
select ok((select oim.price_minor_snapshot = 1500 and oim.meat_snapshot is not null
            from order_item_modifiers oim
            join order_items oi on oi.id = oim.order_item_id
            where oi.order_id = '00000000-0000-0000-0000-0071000a1d04'),
  'G8: the modifier snapshot + validated meat snapshot persist on the line');

-- ---- H. invalid phone (62) -------------------------------------------------
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000a1df7', 'kiosk-op-v7', 'takeaway', null, 'ILS', null,
    null, 'not-a-phone!!',
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'invalid_payload', 'H1: an invalid customer phone is a typed refusal; nothing is created');

-- ---- I. POS actor preservation (63-64) -------------------------------------
insert into _res values ('pos_sub',
  app.submit_order('00000000-0000-0000-0000-0071000c5a01',
    '00000000-0000-0000-0000-0071000a1de1',
    '00000000-0000-0000-0000-007100004004', 'pos-op-1', 'takeaway', null, null, 'ILS', null,
    (select items from _line), 1000, 0, 0, 1000));
select ok((select (r ->> 'ok')::boolean from _res where label = 'pos_sub'),
  'I1: the existing POS submit_order path still works (signature/behavior untouched)');
select ok((select o.pin_session_id = '00000000-0000-0000-0000-0071000c5a01'
              and o.opened_by_employee_profile_id = '00000000-0000-0000-0000-0071000efa01'
              and o.resolved_membership_id = '00000000-0000-0000-0000-0071000aba01'
            from orders o where o.id = '00000000-0000-0000-0000-0071000a1de1'),
  'I2: a POS order still carries the FULL staff actor triple');

-- ---- J. staff-PIN privilege boundary (65-69) -------------------------------
select throws_ok(
  $$select app.sync_push('00000000-0000-0000-0000-0071000a1d01'::uuid,
      '00000000-0000-0000-0000-007100004001'::uuid, '[]'::jsonb)$$,
  '42501', null,
  'J1: the sync_push mutation funnel refuses a kiosk without a REAL PIN session (a random uuid is not one)');
select throws_ok(
  $$select app.pos_menu('00000000-0000-0000-0000-0071000a1d01'::uuid,
      '00000000-0000-0000-0000-007100004001'::uuid)$$,
  '42501', null,
  'J2: the staff pos_menu read remains PIN-gated for a kiosk');
select throws_ok(
  $$select app.record_payment('00000000-0000-0000-0000-0071000a1d01'::uuid,
      '00000000-0000-0000-0000-0071000a1d02'::uuid,
      '00000000-0000-0000-0000-007100004001'::uuid, 'kiosk-pay-x', 'cash', 1000, null)$$,
  '42501', null,
  'J3: payments remain PIN-gated (no kiosk payment surface)');
select throws_ok(
  $$select app.create_device(gen_random_uuid(),
      '00000000-0000-0000-0000-007100000a00'::uuid,
      '00000000-0000-0000-0000-007100000a10'::uuid,
      '00000000-0000-0000-0000-007100000a1a'::uuid, 'kiosk', 'rogue')$$,
  '42501', null,
  'J4: device provisioning still requires a JWT management actor (anonymous kiosk refused)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004004', 'tok-pos-a',
    '00000000-0000-0000-0000-0071000a1dc1', 'kiosk-op-x1', 'takeaway', null, 'ILS', null, null, null,
    (select items from _line), 1000, 0, 0, 1000)) ->> 'error'),
  'invalid_session',
  'J5: a NON-KIOSK device token cannot use the kiosk mutation');

-- ---- K. pay-later + projections (70-74) ------------------------------------
-- RF-055: cash needs an OPEN shift + ACTIVE drawer on (branch, device).
select app.open_shift('00000000-0000-0000-0000-0071000c5a01',
                      '00000000-0000-0000-0000-007100057001',
                      '00000000-0000-0000-0000-0071000cd001',
                      '00000000-0000-0000-0000-007100004004', 'k1-shift-1', 0);
insert into _res values ('pay',
  app.record_payment('00000000-0000-0000-0000-0071000c5a01',
    '00000000-0000-0000-0000-0071000a1d02',
    '00000000-0000-0000-0000-007100004004', 'pos-pay-1', 'cash', 1000, null));
select ok((select (r ->> 'ok')::boolean from _res where label = 'pay'),
  'K1: a cashier later records payment on the kiosk order (no actor-null crash)');
select is((select count(*)::int from payments p
            where p.order_id = '00000000-0000-0000-0000-0071000a1d02'
              and p.status = 'completed'), 1,
  'K2: exactly one completed payment lands on the kiosk order');
select ok((select o.status = 'submitted' and o.revision > 1 from orders o
            where o.id = '00000000-0000-0000-0000-0071000a1d02'),
  'K3: payment alone never completes a kds-mode kiosk order (policy unchanged; receipt stamped)');
insert into _res values ('pos_view',
  app.pos_order_snapshots('00000000-0000-0000-0000-0071000c5a01',
                          '00000000-0000-0000-0000-007100004004'));
select ok((select exists (select 1 from jsonb_array_elements(r -> 'orders') o
             where o ->> 'order_id' = '00000000-0000-0000-0000-0071000a1d01')
            from _res where label = 'pos_view'),
  'K4: the kiosk order appears in the POS branch order projection');
insert into _res values ('kds_pull',
  app.sync_pull('00000000-0000-0000-0000-0071000c5a02',
                '00000000-0000-0000-0000-007100004004', array['orders']));
select ok((select r::text like '%0071000a1d01%' from _res where label = 'kds_pull'),
  'K5: the kiosk order flows to the KDS sync_pull feed');

-- ---- N. HARDENING-FIX-073: the kiosk client is UNTRUSTED (75-101) ----------
-- Everything below runs as the harness role (RPC authority is the token
-- parameter, never the caller role; persisted-state asserts need the harness).

-- N-price: forged snapshots are refused with the stable refresh error.
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d01', 'kiosk-hf-01', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1)),
    1, 0, 0, 1)) ->> 'error'), 'menu_price_changed',
  'N1: a forged 1-agora item price (canonical 1000) is menu_price_changed, never a silent recharge');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d02', 'kiosk-hf-02', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 0)),
    0, 0, 0, 0)) ->> 'error'), 'menu_price_changed',
  'N2: a forged FREE item (0 vs canonical 1000) is refused');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d03', 'kiosk-hf-03', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
        'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double',
        'price_minor_snapshot', 1)))),
    4001, 0, 0, 4001)) ->> 'error'), 'menu_price_changed',
  'N3: a forged option delta (1 vs canonical 1500) is refused');

-- N-rules: the CURRENT group contract is server-enforced.
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d04', 'kiosk-hf-04', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000)),
    4000, 0, 0, 4000)) ->> 'error'), 'modifier_selection_invalid',
  'N4: omitting the REQUIRED Weight group is refused even with a consistent subtotal');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d05', 'kiosk-hf-05', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a01',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Classic', 'price_minor_snapshot', 0),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double', 'price_minor_snapshot', 1500)))),
    5500, 0, 0, 5500)) ->> 'error'), 'modifier_selection_invalid',
  'N5: two distinct options in a SINGLE group are refused');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d06', 'kiosk-hf-06', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double', 'price_minor_snapshot', 1500),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double', 'price_minor_snapshot', 1500)))),
    7000, 0, 0, 7000)) ->> 'error'), 'modifier_selection_invalid',
  'N6: DUPLICATE rows of one option are summed and cannot bypass the single-selection cap');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d0a', 'kiosk-hf-07', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2a03',
        'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Rare', 'price_minor_snapshot', 0)))),
    4000, 0, 0, 4000)) ->> 'error'), 'modifier_selection_invalid',
  'N7: an INACTIVE option is refused (ownership alone is not liveness)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d0b', 'kiosk-hf-08', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double', 'price_minor_snapshot', 1500),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a04',
          'modifier_name_snapshot', 'DeadExtras', 'option_name_snapshot', 'DeadOpt', 'price_minor_snapshot', 0)))),
    5500, 0, 0, 5500)) ->> 'error'), 'modifier_selection_invalid',
  'N8: an option inside a DEAD group is refused (and a dead group is never demanded)');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d0c', 'kiosk-hf-09', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double', 'price_minor_snapshot', 1500,
          'meat_snapshot', (select v from _snap)),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a05',
          'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Sauce', 'price_minor_snapshot', 200,
          'quantity', 3)))),
    6100, 0, 0, 6100)) ->> 'error'), 'modifier_selection_invalid',
  'N9: quantity 3 over the per-option cap of 2 is refused');
insert into _res values ('hf_qty',
  public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d0d', 'kiosk-hf-10', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'Burger', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
          'modifier_name_snapshot', 'Weight', 'option_name_snapshot', 'Double', 'price_minor_snapshot', 1500,
          'meat_snapshot', (select v from _snap)),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a05',
          'modifier_name_snapshot', 'Extras', 'option_name_snapshot', 'Sauce', 'price_minor_snapshot', 200,
          'quantity', 2)))),
    5900, 0, 0, 5900));
select ok((select (r ->> 'ok')::boolean from _res where label = 'hf_qty'),
  'N10: an in-cap quantity 2 with canonical prices is accepted');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d0e', 'kiosk-hf-11', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a6',
      'menu_item_name_snapshot', 'Salad', 'quantity', 1, 'unit_price_minor_snapshot', 800,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2a06',
        'modifier_name_snapshot', 'Mix', 'option_name_snapshot', 'MixA', 'price_minor_snapshot', 0)))),
    800, 0, 0, 800)) ->> 'error'), 'modifier_selection_invalid',
  'N11: one pick under min_select=2 is refused');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d0f', 'kiosk-hf-12', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a6',
      'menu_item_name_snapshot', 'Salad', 'quantity', 1, 'unit_price_minor_snapshot', 800,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a06',
          'modifier_name_snapshot', 'Mix', 'option_name_snapshot', 'MixA', 'price_minor_snapshot', 0),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a07',
          'modifier_name_snapshot', 'Mix', 'option_name_snapshot', 'MixB', 'price_minor_snapshot', 0),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a08',
          'modifier_name_snapshot', 'Mix', 'option_name_snapshot', 'MixC', 'price_minor_snapshot', 0)))),
    800, 0, 0, 800)) ->> 'error'), 'modifier_selection_invalid',
  'N12: three picks over max_select=2 are refused');
select ok((((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d10', 'kiosk-hf-13', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a6',
      'menu_item_name_snapshot', 'Salad', 'quantity', 1, 'unit_price_minor_snapshot', 800,
      'modifiers', jsonb_build_array(
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a06',
          'modifier_name_snapshot', 'Mix', 'option_name_snapshot', 'MixA', 'price_minor_snapshot', 0),
        jsonb_build_object('modifier_option_id', '00000000-0000-0000-0000-0071000d2a07',
          'modifier_name_snapshot', 'Mix', 'option_name_snapshot', 'MixB', 'price_minor_snapshot', 0)))),
    800, 0, 0, 800)) ->> 'ok')::boolean),
  'N13: exactly 2 picks satisfy the min=max=2 contract');

-- N-discount: V1 kiosk has no customer discount authority.
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d11', 'kiosk-hf-14', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 4, 'unit_price_minor_snapshot', 1000)),
    4000, 3999, 0, 1)) ->> 'error'), 'discount_not_allowed',
  'N14: a self-applied 3999 discount (pay 1 agora) is refused');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d12', 'kiosk-hf-15', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1000,
      'line_discount_minor', 100)),
    900, 0, 0, 900)) ->> 'error'), 'discount_not_allowed',
  'N15: a nonzero LINE discount is refused too');

-- N-currency: the tenant currency is the only legal currency.
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d13', 'kiosk-hf-16', 'takeaway', null, 'USD', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1000)),
    1000, 0, 0, 1000)) ->> 'error'), 'currency_mismatch',
  'N16: USD on an ILS tenant is refused despite passing the ISO regex');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d14', 'kiosk-hf-17', 'takeaway', null, 'EUR', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1000)),
    1000, 0, 0, 1000)) ->> 'error'), 'currency_mismatch',
  'N17: EUR is refused the same way');

-- N-tax: the RF-117 branch setting is the only tax authority.
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d15', 'kiosk-hf-18', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1000)),
    1000, 0, 170, 1170)) ->> 'error'), 'tax_mismatch',
  'N18: a customer-invented tax on a tax-DISABLED branch is refused');
update branches set tax_enabled = true, tax_rate_bp = 1700
  where id = '00000000-0000-0000-0000-007100000a1a';
insert into _res values ('hf_tax',
  public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d16', 'kiosk-hf-19', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1000)),
    1000, 0, 170, 1170));
select ok((select (r ->> 'ok')::boolean from _res where label = 'hf_tax'),
  'N19: the canonical 17% exclusive tax (170 on 1000) is accepted');
select ok((select o.tax_total_minor = 170 and o.grand_total_minor = 1170 from orders o
            where o.id = '00000000-0000-0000-0000-0071000b0d16'),
  'N20: the authoritative tax + grand persist');
select is(((public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d17', 'kiosk-hf-20', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'Cola', 'quantity', 1, 'unit_price_minor_snapshot', 1000)),
    1000, 0, 0, 1000)) ->> 'error'), 'tax_mismatch',
  'N21: omitting the tax on a tax-ENABLED branch is refused (stale cart => refresh)');
update branches set tax_enabled = false, tax_rate_bp = 0
  where id = '00000000-0000-0000-0000-007100000a1a';

-- N-snapshots: persisted names are CANONICAL, never client strings.
insert into _res values ('hf_name1',
  public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d18', 'kiosk-hf-21', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a2',
      'menu_item_name_snapshot', 'HACKED ITEM', 'quantity', 1, 'unit_price_minor_snapshot', 1000)),
    1000, 0, 0, 1000));
select ok((select (r ->> 'ok')::boolean from _res where label = 'hf_name1'),
  'N22: a fake display name does not block a valid order (names carry no authority)');
select is((select oi.menu_item_name_snapshot from order_items oi
            where oi.order_id = '00000000-0000-0000-0000-0071000b0d18'), 'Cola',
  'N23: the persisted item snapshot is the CANONICAL DB name, not the client string');
insert into _res values ('hf_name2',
  public.kiosk_submit_order('00000000-0000-0000-0000-007100004001', 'tok-kiosk-a',
    '00000000-0000-0000-0000-0071000b0d19', 'kiosk-hf-22', 'takeaway', null, 'ILS', null, null, null,
    jsonb_build_array(jsonb_build_object('menu_item_id', '00000000-0000-0000-0000-0071000117a1',
      'menu_item_name_snapshot', 'FAKE BURGER', 'quantity', 1, 'unit_price_minor_snapshot', 4000,
      'modifiers', jsonb_build_array(jsonb_build_object(
        'modifier_option_id', '00000000-0000-0000-0000-0071000d2a02',
        'modifier_name_snapshot', 'FAKE GROUP', 'option_name_snapshot', 'FAKE OPT',
        'price_minor_snapshot', 1500,
        'meat_snapshot', (select v from _snap))))),
    5500, 0, 0, 5500));
select ok((select (r ->> 'ok')::boolean from _res where label = 'hf_name2'),
  'N24: fake group/option labels do not block a valid order');
select ok((select oi.menu_item_name_snapshot = 'Burger'
              and oim.modifier_name_snapshot = 'Weight'
              and oim.option_name_snapshot = 'Double'
              and oim.price_minor_snapshot = 1500
            from order_items oi
            join order_item_modifiers oim on oim.order_item_id = oi.id
            where oi.order_id = '00000000-0000-0000-0000-0071000b0d19'),
  'N25: the persisted receipt/kitchen snapshots are the canonical Weight/Double rows');

-- N-actor: defense-in-depth — an actorless row must belong to a KIOSK device.
select throws_ok(
  $$insert into orders (id, organization_id, restaurant_id, branch_id, device_id,
      order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id)
    values (gen_random_uuid(), '00000000-0000-0000-0000-007100000a00',
      '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a',
      '00000000-0000-0000-0000-007100004004',
      'takeaway', 'submitted', 'ILS', 0, 0, 'direct-pos-null-actor')$$,
  '23514', null,
  'N26: an actorless order on a POS device is refused even by a privileged direct write');
select lives_ok(
  $$insert into orders (id, organization_id, restaurant_id, branch_id, device_id,
      order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id)
    values ('00000000-0000-0000-0000-0071000b0df1', '00000000-0000-0000-0000-007100000a00',
      '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a',
      '00000000-0000-0000-0000-007100004001',
      'takeaway', 'submitted', 'ILS', 0, 0, 'direct-hf-1')$$,
  'N27: an actorless order on a KIOSK device passes the guard');

-- ---- L. revocation cuts access at use time (102) ----------------------------
reset role;
update device_sessions set is_active = false, revoked_at = now()
  where id = '00000000-0000-0000-0000-007100004054';
set local role authenticated;
set local app.current_app_user_id = '';
select is((app.kiosk_menu('00000000-0000-0000-0000-007100004002', 'tok-kiosk-b') ->> 'error'),
  'invalid_session', 'L1: revoking the session cuts every kiosk RPC immediately');

-- ---- M. constraints + ACL surface (103-105) --------------------------------
reset role;
select throws_ok(
  $$insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label)
    values (gen_random_uuid(), '00000000-0000-0000-0000-007100000a00',
            '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a',
            'tablet', 'nope')$$,
  '23514', null, 'M1: the devices CHECK still refuses unknown types');
select throws_ok(
  $$insert into orders (id, organization_id, restaurant_id, branch_id, device_id,
      pin_session_id, opened_by_employee_profile_id, resolved_membership_id,
      order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id)
    values (gen_random_uuid(), '00000000-0000-0000-0000-007100000a00',
      '00000000-0000-0000-0000-007100000a10', '00000000-0000-0000-0000-007100000a1a',
      '00000000-0000-0000-0000-007100004001',
      '00000000-0000-0000-0000-0071000c5a01', null, null,
      'takeaway', 'submitted', 'ILS', 0, 0, 'partial-actor')$$,
  '23514', null, 'M2: a PARTIAL staff actor triple is rejected (all-or-none boundary)');
select throws_ok(
  $$insert into audit_events (organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id, action, new_values)
    values ('00000000-0000-0000-0000-007100000a00', '00000000-0000-0000-0000-007100000a10',
            '00000000-0000-0000-0000-007100000a1a', null, null, null, 'kiosk.something', '{}'::jsonb)$$,
  '23514', null, 'M3: an audit row with NO actor of any kind (human or device) is still impossible');

select * from finish();
rollback;
