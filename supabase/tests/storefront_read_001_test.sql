-- ============================================================================
-- STOREFRONT-READ-001 — pgTAP: the anon-only public storefront read contract
-- (public.storefront_menu), the profile write/read RPCs and the media gate.
--
-- Matrix (packet §6.3 T-S1..T-S5 + the DB half of T-S6):
--   A. contract introspection: one overload, DEFINER, search_path pinned,
--      STABLE, owner postgres, prosrc free of every membership/identity helper,
--      EXECUTE = anon only — authenticated refused at the GRANT layer both by
--      catalog and as the REAL role, and proven after a hosted-shaped re-stamp
--      (grant-then-revoke idiom); anon still has no app USAGE / no table grant.
--   B. the PUBLIC derivative bucket + the three authenticated-only write policies.
--   C. the projection as the REAL role anon: exact key sets per entity, live
--      predicates (inactive / tombstoned / sibling-branch / dead-category rows
--      excluded), sold-out from the branch override, image_url ONLY from a
--      PUBLISHED derivative, negative deltas excluded, max_select 0 served
--      as-is (the UI omits it), tags filtered to the vocabulary, no private key,
--      no scope UUID and no internal field in the payload text.
--   D. uniform not_found for unknown / unpublished / suspended / deleted branch /
--      NULL timezone / non-ILS / inclusive tax / bad grammar; closed and paused
--      tenants stay browsable with their state.
--   E. the CAS write RPC (manager+, denial audited, replay, stale, unknown
--      field, slug grammar + reserved + taken, browse-only flags not patchable,
--      publish preconditions), the CHECK layer, and the manager read.
--   F. the typed payload cap.
--   G. the hours helper at fixed instants (midnight crossing, exception day).
--
-- Fixtures inserted as the BYPASSRLS harness role; anon calls run as the REAL
-- role anon (set local role anon — never a faked JWT); manager calls as
-- authenticated + the identity GUC (no JWT principal => GUC path).
-- Session pinned to UTC. Everything here is synthetic.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(121);

-- ===== fixtures ==============================================================
-- Org A (ILS): R-A1 published (branch A1a storefront, A1b sibling), R-A2 unpublished,
--              R-A3 no timezone anywhere, R-A4 inclusive tax, R-A5 closed hours,
--              R-A6 paused, R-A7 payload cap, R-A8 deleted branch, R-A9 write-RPC target
-- Org B (ILS): R-B1 published (isolation control)
-- Org C (ILS, SUSPENDED): R-C1 published
-- Org D (EUR): R-D1 published
insert into organizations (id, name, slug, default_currency, status) values
  ('00000000-0000-0000-0000-00ad00000a00', 'SFR Org A', 'sfr1-org-a', 'ILS', 'active'),
  ('00000000-0000-0000-0000-00ad00000b00', 'SFR Org B', 'sfr1-org-b', 'ILS', 'active'),
  ('00000000-0000-0000-0000-00ad00000c00', 'SFR Org C', 'sfr1-org-c', 'ILS', 'suspended'),
  ('00000000-0000-0000-0000-00ad00000d00', 'SFR Org D', 'sfr1-org-d', 'EUR', 'active');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A1', null),
  ('00000000-0000-0000-0000-00ad00000a20', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A2', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000a30', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A3', null),
  ('00000000-0000-0000-0000-00ad00000a40', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A4', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000a50', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A5', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000a60', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A6', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000a70', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A7', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000a80', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A8', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000a90', '00000000-0000-0000-0000-00ad00000a00', 'SFR Rest A9 Name Is Long Enough To Be Truncated At Sixty Chars X', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000b10', '00000000-0000-0000-0000-00ad00000b00', 'SFR Rest B1', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000c10', '00000000-0000-0000-0000-00ad00000c00', 'SFR Rest C1', 'Asia/Jerusalem'),
  ('00000000-0000-0000-0000-00ad00000d10', '00000000-0000-0000-0000-00ad00000d00', 'SFR Rest D1', 'Asia/Jerusalem');
insert into branches (id, organization_id, restaurant_id, name, timezone, tax_enabled, tax_rate_bp, tax_mode, deleted_at) values
  ('00000000-0000-0000-0000-00ad00000a1a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', 'A1a', 'Asia/Jerusalem', true,  1800, 'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a1b', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', 'A1b', 'Asia/Jerusalem', true,  1800, 'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a2a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a20', 'A2a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a3a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a30', 'A3a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a4a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a40', 'A4a', null,             true,  1800, 'inclusive', null),
  ('00000000-0000-0000-0000-00ad00000a5a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a50', 'A5a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a6a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a60', 'A6a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a7a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a70', 'A7a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000a8a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a80', 'A8a', null,             false, 0,    'exclusive', now()),
  ('00000000-0000-0000-0000-00ad00000a9a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 'A9a', null,             true,  1700, 'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000b1a', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b10', 'B1a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000c1a', '00000000-0000-0000-0000-00ad00000c00', '00000000-0000-0000-0000-00ad00000c10', 'C1a', null,             false, 0,    'exclusive', null),
  ('00000000-0000-0000-0000-00ad00000d1a', '00000000-0000-0000-0000-00ad00000d00', '00000000-0000-0000-0000-00ad00000d10', 'D1a', null,             false, 0,    'exclusive', null);

-- principals: owner A (org_owner), manager A (manager over R-A9), cashier A (restaurant-scoped at R-A9:
-- a BRANCH-scoped membership does not cover a restaurant-level write and raises 42501 instead), owner B
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00ad0000ee01', 'sfr1-owner-a@example.test'),
  ('00000000-0000-0000-0000-00ad0000ee02', 'sfr1-manager-a@example.test'),
  ('00000000-0000-0000-0000-00ad0000ee03', 'sfr1-cashier-a@example.test'),
  ('00000000-0000-0000-0000-00ad0000ee04', 'sfr1-cashier-a1@example.test'),
  ('00000000-0000-0000-0000-00ad0000ee0b', 'sfr1-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00ad0000ab01', '00000000-0000-0000-0000-00ad0000ee01', '00000000-0000-0000-0000-00ad00000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00ad0000ab02', '00000000-0000-0000-0000-00ad0000ee02', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', null, 'manager'),
  ('00000000-0000-0000-0000-00ad0000ab03', '00000000-0000-0000-0000-00ad0000ee03', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', null, 'cashier'),
  -- a cashier whose membership COVERS restaurant R-A1 (the media owner): the storage rank floor is what refuses it, not a scope miss
  ('00000000-0000-0000-0000-00ad0000ab04', '00000000-0000-0000-0000-00ad0000ee04', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, 'cashier'),
  ('00000000-0000-0000-0000-00ad0000ab0b', '00000000-0000-0000-0000-00ad0000ee0b', '00000000-0000-0000-0000-00ad00000b00', null, null, 'org_owner');

-- R-A1 menu: Cat1 (global), Cat2 (sibling A1b only), CatDead (inactive, holds an
-- active item); items Burger (tags incl. an off-vocabulary one, private image
-- key, internal fields), Cola (unpublished derivative), PausedItem (sold out
-- at A1a), SiblingOnly (A1b), DeadItem (inactive), DeadCatItem (in CatDead)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active, icon_key) values
  ('00000000-0000-0000-0000-00ad0000c1a1', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, 'Burgers', 0, true, 'burger'),
  ('00000000-0000-0000-0000-00ad0000c1a2', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a1b', 'Sibling Only Cat', 1, true, 'salad'),
  ('00000000-0000-0000-0000-00ad0000c1a3', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, 'Dead Cat', 2, false, null),
  ('00000000-0000-0000-0000-00ad0000c1b1', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b10', null, 'Org B Cat', 0, true, 'pizza'),
  ('00000000-0000-0000-0000-00ad0000c1c1', '00000000-0000-0000-0000-00ad00000c00', '00000000-0000-0000-0000-00ad00000c10', null, 'Org C Cat', 0, true, null),
  ('00000000-0000-0000-0000-00ad0000c1d1', '00000000-0000-0000-0000-00ad00000d00', '00000000-0000-0000-0000-00ad00000d10', null, 'Org D Cat', 0, true, null),
  ('00000000-0000-0000-0000-00ad0000c1a5', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a50', null, 'Closed Cat', 0, true, null),
  ('00000000-0000-0000-0000-00ad0000c1a6', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a60', null, 'Paused Cat', 0, true, null),
  ('00000000-0000-0000-0000-00ad0000c1a7', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a70', null, 'Big Cat', 0, true, null),
  ('00000000-0000-0000-0000-00ad0000c1a9', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', null, 'A9 Cat', 0, true, null);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, description, base_price_minor, currency_code, display_order, is_active, sku, prep_minutes, kitchen_note, attributes, image_path, tags, item_type) values
  ('00000000-0000-0000-0000-00ad00011a01', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000c1a1', 'Burger', 'Beef and bun', 4000, 'ILS', 0, true, 'SKU-SECRET-7', 12, 'internal kitchen note', '{"prep_components":[{"name":"bun","quantity":1,"unit":"pc"}]}'::jsonb, 'privateorg/privaterest/global/menu_item/x/burger.jpg', '["popular","new","internal-x"]'::jsonb, 'food'),
  ('00000000-0000-0000-0000-00ad00011a02', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000c1a1', 'Cola', null, 1000, 'ILS', 1, true, null, null, null, null, 'privateorg/privaterest/global/menu_item/y/cola.jpg', null, 'drink'),
  ('00000000-0000-0000-0000-00ad00011a03', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000c1a1', 'PausedItem', 'sold out today', 900, 'ILS', 2, true, null, null, null, null, null, '["vegetarian"]'::jsonb, null),
  ('00000000-0000-0000-0000-00ad00011a04', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a1b', '00000000-0000-0000-0000-00ad0000c1a1', 'SiblingOnly', null, 800, 'ILS', 3, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011a05', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000c1a1', 'DeadItem', null, 700, 'ILS', 4, false, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011a06', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000c1a3', 'DeadCatItem', null, 600, 'ILS', 5, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011b01', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b10', null, '00000000-0000-0000-0000-00ad0000c1b1', 'OrgB Item', null, 5000, 'ILS', 0, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011c01', '00000000-0000-0000-0000-00ad00000c00', '00000000-0000-0000-0000-00ad00000c10', null, '00000000-0000-0000-0000-00ad0000c1c1', 'OrgC Item', null, 5000, 'ILS', 0, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011d01', '00000000-0000-0000-0000-00ad00000d00', '00000000-0000-0000-0000-00ad00000d10', null, '00000000-0000-0000-0000-00ad0000c1d1', 'OrgD Item', null, 5000, 'EUR', 0, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011a51', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a50', null, '00000000-0000-0000-0000-00ad0000c1a5', 'Closed Item', null, 1200, 'ILS', 0, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011a61', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a60', null, '00000000-0000-0000-0000-00ad0000c1a6', 'Paused Item', null, 1200, 'ILS', 0, true, null, null, null, null, null, null, null),
  ('00000000-0000-0000-0000-00ad00011a91', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', null, '00000000-0000-0000-0000-00ad0000c1a9', 'A9 Item', null, 1500, 'ILS', 0, true, null, null, null, null, null, null, null);
-- payload-cap restaurant: 501 live items
insert into menu_items (organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active)
select '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a70', null, '00000000-0000-0000-0000-00ad0000c1a7', 'Big ' || g, 100, 'ILS', g, true
  from generate_series(1, 501) g;
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a1a', '00000000-0000-0000-0000-00ad00011a03', 'unavailable', 'sold_out'),
  -- a sold-out override at the SIBLING branch must not affect the storefront branch
  ('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a1b', '00000000-0000-0000-0000-00ad00011a01', 'unavailable', 'paused');
-- modifiers on Burger: Weight (single, required), Extras (multiple, max_select 0,
-- allow_quantity), DeadMod (inactive, holds a live option); options incl. a
-- NEGATIVE delta, a TOMBSTONED one and a sibling-branch one
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active, allow_quantity, max_quantity) values
  ('00000000-0000-0000-0000-00ad0000d1a1', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad00011a01', 'Weight',  'single',   1, 1,    true,  true,  false, null),
  ('00000000-0000-0000-0000-00ad0000d1a2', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad00011a01', 'Extras',  'multiple', 0, 0,    false, true,  true,  2),
  ('00000000-0000-0000-0000-00ad0000d1a3', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad00011a01', 'DeadMod', 'multiple', 0, null, false, false, false, null),
  ('00000000-0000-0000-0000-00ad0000d1a4', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a1b', '00000000-0000-0000-0000-00ad00011a01', 'SiblingMod', 'single', 0, null, false, true, false, null);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat, deleted_at) values
  ('00000000-0000-0000-0000-00ad0000d2a1', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a1', 'Classic',    0,    0, true,  '{"quantity":1,"unit":"pc"}'::jsonb, null),
  ('00000000-0000-0000-0000-00ad0000d2a2', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a1', 'Double',     1500, 1, true,  null, null),
  ('00000000-0000-0000-0000-00ad0000d2a3', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a1', 'Negative',   -200, 2, true,  null, null),
  ('00000000-0000-0000-0000-00ad0000d2a4', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a1', 'Tombstoned', 300,  3, true,  null, now()),
  ('00000000-0000-0000-0000-00ad0000d2a5', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a2', 'Cheese',     600,  0, true,  null, null),
  ('00000000-0000-0000-0000-00ad0000d2a6', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a3', 'DeadModOpt', 100,  0, true,  null, null),
  ('00000000-0000-0000-0000-00ad0000d2a7', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', null, '00000000-0000-0000-0000-00ad0000d1a4', 'SiblingOpt', 100,  0, true,  null, null);
-- published derivative for Burger (w480), an UNPUBLISHED one for Cola
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at, unpublished_at) values
  ('00000000-0000-0000-0000-00ad0000f0a1', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', 'menu-images', 'privateorg/privaterest/global/menu_item/x/burger.jpg', 'w480',
   app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000a10') || '/' || repeat('a', 64) || '.webp', repeat('a', 64), 480, 480, 12345, now() - interval '1 day', null),
  ('00000000-0000-0000-0000-00ad0000f0a2', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', 'menu-images', 'privateorg/privaterest/global/menu_item/y/cola.jpg', 'w480',
   app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000a10') || '/' || repeat('b', 64) || '.webp', repeat('b', 64), 480, 480, 12345, now() - interval '2 day', now() - interval '1 day');

-- profiles (direct harness inserts; the RPC path is exercised in section E).
-- "always open": two windows per day, 00:00-12:00 and 11:00-00:00 (crossing midnight).
create temp table _sf_hours as
  select jsonb_build_object('weekly',
    (select jsonb_agg(jsonb_build_object('dow', d, 'open', o, 'close', c))
       from generate_series(0, 6) d cross join (values ('00:00', '12:00'), ('11:00', '00:00')) w(o, c)),
    'exceptions', '[]'::jsonb) as always_open;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, tagline, public_city, public_address, public_phone, primary_color, accent_color, visual_preset, locale_default, card_mode, motion, pickup_enabled, paused_until, opening_hours, logo_media_id, hero_media_id, is_published, version)
select '00000000-0000-0000-0000-00ad00000a10', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a1a', 'sfr1-alpha', 'Alpha <script>alert(1)</script>', 'Tag line', 'Kafr Manda', 'Main St 1', '052-000-0000', '#123027', '#ff8a2a', 'dark', 'ar', 'list', 'full', true, null, always_open, null, null, true, 3 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000a20', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a2a', 'sfr1-unpublished', 'Unpublished', always_open, false, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000a30', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a3a', 'sfr1-notz', 'No Timezone', always_open, true, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000a40', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a4a', 'sfr1-inclusive', 'Inclusive Tax', always_open, true, 1 from _sf_hours;
-- closed: one window three days from "today" in the branch zone -> closed now, next_open within 7 days
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
values ('00000000-0000-0000-0000-00ad00000a50', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a5a', 'sfr1-closed', 'Closed Now',
  jsonb_build_object('weekly', jsonb_build_array(jsonb_build_object('dow', ((extract(dow from (now() at time zone 'Asia/Jerusalem'))::int + 3) % 7), 'open', '10:00', 'close', '11:00')), 'exceptions', '[]'::jsonb), true, 1);
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, paused_until, pause_reason, is_published, version)
select '00000000-0000-0000-0000-00ad00000a60', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a6a', 'sfr1-paused', 'Paused Now', always_open, now() + interval '1 day', 'busy', true, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000a70', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a7a', 'sfr1-big', 'Big Menu', always_open, true, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000a80', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a8a', 'sfr1-delbranch', 'Deleted Branch', always_open, true, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000b10', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b1a', 'sfr1-bravo', 'Bravo', always_open, true, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000c10', '00000000-0000-0000-0000-00ad00000c00', '00000000-0000-0000-0000-00ad00000c1a', 'sfr1-suspended', 'Suspended Org', always_open, true, 1 from _sf_hours;
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, opening_hours, is_published, version)
select '00000000-0000-0000-0000-00ad00000d10', '00000000-0000-0000-0000-00ad00000d00', '00000000-0000-0000-0000-00ad00000d1a', 'sfr1-euro', 'Euro Org', always_open, true, 1 from _sf_hours;

-- results captured as the calling role (temp table readable by every role used here)
create temp table _sf (label text primary key, r jsonb);
grant select, insert on _sf to anon, authenticated;

-- ============================================================================
-- A. contract introspection ............................................. (21)
-- ============================================================================
select is((select count(*)::int from pg_proc where pronamespace = 'public'::regnamespace and proname = 'storefront_menu'), 1,
  'A1. exactly ONE overload of public.storefront_menu exists');
select ok((select prosecdef from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure),
  'A2. public.storefront_menu is SECURITY DEFINER (the enumerated D-037 amendment)');
select ok((select array_length(proconfig, 1) = 1 and proconfig[1] like 'search_path=%' from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure),
  'A3. proconfig pins search_path only (no statement_timeout illusion)');
select is((select provolatile from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure), 's',
  'A4. STABLE — the function cannot write');
select is((select pg_get_userbyid(proowner) from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure), 'postgres',
  'A5. owned by postgres (the migration-running role)');
select ok(
  (select prosrc from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure)
    !~ '(current_app_user_id|current_org_id|current_organization_id|current_setting|has_scope|has_role_in_scope|set_config|auth\.uid|actor_rank_in_scope|request\.jwt)',
  'A6. prosrc references NO membership / identity helper, no set_config, no current_setting / GUC, no auth.uid (slug is the only input)');
select ok(
      not has_function_privilege('authenticated', 'app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'app.storefront_service_window(jsonb, text, timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'app.storefront_media_prefix(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'app.storefront_opening_hours_is_valid(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb)', 'EXECUTE'),
  'A6b. the caller-blind DEFINER helpers (publish_blockers / service_window / media_prefix / hours validator) are EXECUTE-able by no app role');
-- NEGATIVE CONTROL (review C1): the family guard must see PROCEDURES too. A SECURITY DEFINER
-- procedure granted to anon is created inside this transaction, must be reported by the SAME
-- set expressions the migration's final DO block and T-016 use (prokind in ('f','p')), and is
-- dropped again; the sets then equal the enumerated allowlist once more.
create procedure public.zz_read001_probe_proc() language sql security definer set search_path = '' as $$ select 1 $$;
revoke all on procedure public.zz_read001_probe_proc() from public;
grant execute on procedure public.zz_read001_probe_proc() to anon;
select is(
  (select string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public\.', ''))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and has_function_privilege('anon', p.oid, 'EXECUTE')),
  'storefront_menu(text), zz_read001_probe_proc()',
  'A6c. NEGATIVE CONTROL: an anon-executable SECURITY DEFINER PROCEDURE is caught by the widened anon-set guard (prokind f + p)');
select is(
  (select string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public\.', ''))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef),
  'storefront_menu(text), zz_read001_probe_proc()',
  'A6d. NEGATIVE CONTROL: the widened SECURITY DEFINER-set guard reports the procedure too');
drop procedure public.zz_read001_probe_proc();
select is(
  (select string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public\.', ''))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and has_function_privilege('anon', p.oid, 'EXECUTE')),
  'storefront_menu(text)',
  'A6e. ...and once the probe is dropped the anon-executable routine set is exactly the allowlist again');
select ok(has_function_privilege('anon', 'public.storefront_menu(text)', 'EXECUTE'),
  'A7. anon holds EXECUTE on public.storefront_menu(text)');
select ok(not has_function_privilege('authenticated', 'public.storefront_menu(text)', 'EXECUTE'),
  'A8. authenticated does NOT hold EXECUTE (explicit revoke; D-037 point 6)');
select is(
  (select count(*)::int from pg_proc p
     cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public.storefront_menu(text)'::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE'),
  0, 'A9. the PUBLIC pseudo-role holds no EXECUTE on it');
-- hosted-shape simulation: the platform default ACL re-stamps authenticated=X on
-- a fresh CREATE; the migration's explicit revoke must remove it again.
grant execute on function public.storefront_menu(text) to authenticated;
select ok(has_function_privilege('authenticated', 'public.storefront_menu(text)', 'EXECUTE'),
  'A10. simulation: a hosted-style authenticated stamp is reproduced');
revoke all on function public.storefront_menu(text) from authenticated;
select ok(not has_function_privilege('authenticated', 'public.storefront_menu(text)', 'EXECUTE'),
  'A11. the migration statement form removes the stamped authenticated EXECUTE (local/hosted asymmetry covered)');
select ok(not has_schema_privilege('anon', 'app', 'USAGE'),
  'A12. anon still has no USAGE on schema app (T-016 B1 unchanged)');
select ok(
  not has_table_privilege('anon', 'public.restaurant_storefront_profiles', 'SELECT')
  and not has_table_privilege('anon', 'public.storefront_media', 'SELECT'),
  'A13. anon holds no privilege on the two new tables (the function is the boundary)');
select ok(
  not has_table_privilege('authenticated', 'public.restaurant_storefront_profiles', 'SELECT')
  and not has_table_privilege('authenticated', 'public.storefront_media', 'SELECT')
  and not has_table_privilege('authenticated', 'public.restaurant_storefront_profiles', 'INSERT'),
  'A14. authenticated holds no direct privilege on the two new tables (RPC-only, D-011)');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.restaurant_storefront_profiles'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.storefront_media'::regclass),
  'A15. RLS enabled + forced on both new tables');
set local role authenticated;
select throws_ok(
  $$ select public.storefront_menu('sfr1-alpha') $$,
  '42501', 'permission denied for function storefront_menu',
  'A16. the REAL authenticated role is refused at the FUNCTION grant layer');
reset role;
select ok(
  (select prosrc from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure) ~ 'ordering_enabled'', false'
  and (select prosrc from pg_proc where oid = 'public.storefront_menu(text)'::regprocedure) ~ 'delivery_enabled'', false',
  'A17. the served ordering_enabled / delivery_enabled are LITERAL false in the function body (browse-only slice)');

-- ============================================================================
-- B. bucket + write policies ............................................. (22)
-- ============================================================================
select is((select public from storage.buckets where id = 'storefront-media'), true,
  'B1. storefront-media bucket exists and is PUBLIC (derivatives only)');
select is((select file_size_limit from storage.buckets where id = 'storefront-media'), 524288::bigint,
  'B2. storefront-media file_size_limit is 512 KiB');
select is((select allowed_mime_types from storage.buckets where id = 'storefront-media'), array['image/webp'],
  'B3. storefront-media allows image/webp only');
select is((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'storefront_media_%'), 4,
  'B4. exactly four storefront_media_* policies on storage.objects (select/insert/update/delete: the SELECT policy is what makes UPDATE/DELETE reachable; anonymous GET of a public bucket never consults RLS)');
select is((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'storefront_media_%' and roles::text[] = array['authenticated']), 4,
  'B5. all four policies target authenticated ONLY');
select is((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'storefront_media_%'
             and (coalesce(qual, '') || coalesce(with_check, '')) like '%can_write_storefront_object%'), 4,
  'B6. every policy (select/insert/update/delete) goes through app.can_write_storefront_object(name)');
select ok(
  (select prosecdef and array_length(proconfig, 1) = 1 and proconfig[1] like 'search_path=%' from pg_proc where oid = 'app.can_write_storefront_object(text)'::regprocedure)
  and (select prosecdef and array_length(proconfig, 1) = 1 and proconfig[1] like 'search_path=%' from pg_proc where oid = 'app.can_write_storefront_media(uuid, uuid)'::regprocedure),
  'B7. the two gates are SECURITY DEFINER with search_path pinned');
select ok(not has_function_privilege('anon', 'app.can_write_storefront_object(text)', 'EXECUTE')
      and has_function_privilege('authenticated', 'app.can_write_storefront_object(text)', 'EXECUTE'),
  'B8. the object gate is executable by authenticated only');

-- BEHAVIOUR as REAL principals (review C4). Two more registered derivatives: org B's live key 'd' and
-- an org B key 'e' registered but never uploaded; two objects exist in the bucket (A's 'a', B's 'd'),
-- inserted by the harness role which bypasses RLS. Everything rolls back with the transaction.
insert into storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at, unpublished_at) values
  ('00000000-0000-0000-0000-00ad0000f0b1', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b10', 'menu-images', 'orgb/private/x.jpg', 'w480',
   app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000b10') || '/' || repeat('d', 64) || '.webp', repeat('d', 64), 480, 480, 100, now(), null),
  ('00000000-0000-0000-0000-00ad0000f0b2', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b10', 'menu-images', 'orgb/private/y.jpg', 'w480',
   app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000b10') || '/' || repeat('e', 64) || '.webp', repeat('e', 64), 480, 480, 100, now(), null);
insert into storage.objects (bucket_id, name) values
  ('storefront-media', app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000a10') || '/' || repeat('a', 64) || '.webp'),
  ('storefront-media', app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000b10') || '/' || repeat('d', 64) || '.webp');

-- storage.protect_delete() (a statement trigger) refuses every direct DELETE unless the Storage
-- API's own session gate is set; setting it here as the harness lets the RLS DELETE policy - the
-- thing this section proves - be exercised by the REAL roles exactly as the API exercises it.
-- the opaque prefixes, computed ONCE as the harness: the real roles cannot (and must not) call
-- app.storefront_media_prefix themselves
create temp table _sf_keys as
  select app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000a10') as pa,
         app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000b10') as pb;
grant select on _sf_keys to anon, authenticated;
set local storage.allow_delete_query = 'true';
set local role anon;
select is((select count(*)::int from storage.objects where bucket_id = 'storefront-media'), 0,
  'B9. anon lists NO object of the public bucket through storage.objects (a public bucket serves GET by URL; it never enumerates)');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('storefront-media', (select pa from _sf_keys) || '/' || repeat('f', 64) || '.webp') $$,
  '42501', null,
  'B10. anon cannot upload into the bucket');
-- silent no-ops as anon (0 rows visible); the harness role verifies the effect below
update storage.objects set metadata = '{"probe":"anon"}'::jsonb where bucket_id = 'storefront-media';
delete from storage.objects where bucket_id = 'storefront-media';
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'storefront-media' and metadata ? 'probe'), 0,
  'B11. anon updated no object (no probe mark landed)');
select is((select count(*)::int from storage.objects where bucket_id = 'storefront-media'), 2,
  'B12. anon deleted no object (both objects remain)');

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee01';   -- org_owner of Org A (rank 3 over R-A1)
select is((select string_agg(name, ',') from storage.objects where bucket_id = 'storefront-media'),
  (select pa from _sf_keys) || '/' || repeat('a', 64) || '.webp',
  'B13. a manager of Org A sees exactly ITS registered object, never Org B''s (the SELECT policy is tenant-scoped, not bucket-wide)');
update storage.objects set name = (select pa from _sf_keys) || '/' || repeat('b', 64) || '.webp'
 where bucket_id = 'storefront-media' and name = (select pa from _sf_keys) || '/' || repeat('a', 64) || '.webp';
reset role;
select is((select string_agg(name, ',') from storage.objects where bucket_id = 'storefront-media' and name like (select pa from _sf_keys) || '/%'),
  (select pa from _sf_keys) || '/' || repeat('b', 64) || '.webp',
  'B14. ...and may move its object to ANOTHER key registered to its restaurant (UPDATE is reachable through the SELECT policy)');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee01';
select throws_ok(
  $$ update storage.objects set name = (select pa from _sf_keys) || '/' || repeat('9', 64) || '.webp' where bucket_id = 'storefront-media' $$,
  '42501', null,
  'B15. ...but not to an UNREGISTERED key (WITH CHECK)');
delete from storage.objects where bucket_id = 'storefront-media' and name like (select pb from _sf_keys) || '/%';
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('storefront-media', (select pa from _sf_keys) || '/' || repeat('f', 64) || '.webp') $$,
  '42501', null,
  'B17. an Org A manager cannot upload an UNREGISTERED key, even under its own prefix');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('storefront-media', (select pb from _sf_keys) || '/' || repeat('e', 64) || '.webp') $$,
  '42501', null,
  'B18. ...nor a key registered to ANOTHER tenant (cross-tenant key mutation refused)');
delete from storage.objects where bucket_id = 'storefront-media' and name = (select pa from _sf_keys) || '/' || repeat('b', 64) || '.webp';
reset role;
select is((select count(*)::int from storage.objects where bucket_id = 'storefront-media' and name like (select pb from _sf_keys) || '/%'), 1,
  'B16. an Org A manager deletes nothing under Org B''s prefix');
select is((select count(*)::int from storage.objects where bucket_id = 'storefront-media' and name like (select pa from _sf_keys) || '/%'), 0,
  'B19. ...and may retract (DELETE) its own registered derivative');
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee0b';   -- org_owner of Org B
select is((select string_agg(name, ',') from storage.objects where bucket_id = 'storefront-media'),
  (select pb from _sf_keys) || '/' || repeat('d', 64) || '.webp',
  'B20. Org B''s owner sees exactly Org B''s object');
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee04';   -- cashier COVERING R-A1 (rank 1 over the media owner)
select is((select count(*)::int from storage.objects where bucket_id = 'storefront-media'), 0,
  'B21. a cashier whose membership covers the restaurant still sees no object (rank floor, not scope)');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('storefront-media', (select pa from _sf_keys) || '/' || repeat('a', 64) || '.webp') $$,
  '42501', null,
  'B22. ...and cannot upload even a registered key of its own restaurant''s org (rank < manager)');
reset role;

-- ============================================================================
-- C. the projection as the REAL role anon .............................. (24)
-- ============================================================================
set local role anon;
insert into _sf values ('alpha', public.storefront_menu('sfr1-alpha'));
insert into _sf values ('bravo', public.storefront_menu('sfr1-bravo'));
insert into _sf values ('closed', public.storefront_menu('sfr1-closed'));
insert into _sf values ('paused', public.storefront_menu('sfr1-paused'));
insert into _sf values ('big', public.storefront_menu('sfr1-big'));
insert into _sf values ('unknown', public.storefront_menu('sfr1-nope'));
insert into _sf values ('unpublished', public.storefront_menu('sfr1-unpublished'));
insert into _sf values ('suspended', public.storefront_menu('sfr1-suspended'));
insert into _sf values ('delbranch', public.storefront_menu('sfr1-delbranch'));
insert into _sf values ('notz', public.storefront_menu('sfr1-notz'));
insert into _sf values ('euro', public.storefront_menu('sfr1-euro'));
insert into _sf values ('inclusive', public.storefront_menu('sfr1-inclusive'));
insert into _sf values ('grammar1', public.storefront_menu('Bad Slug'));
insert into _sf values ('grammar2', public.storefront_menu('-sfr1'));
insert into _sf values ('grammar3', public.storefront_menu(repeat('a', 64)));
insert into _sf values ('grammar4', public.storefront_menu(''));
insert into _sf values ('grammar5', public.storefront_menu(null));
insert into _sf values ('short', public.storefront_menu('ab'));
reset role;

select is((select r ->> 'ok' from _sf where label = 'alpha'), 'true', 'C1. a published tenant answers ok=true as anon');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r from _sf where label = 'alpha')) k),
  'categories,entity,hours,items,menu_version,modifier_options,modifiers,ok,restaurant,server_ts,service,tax',
  'C2. top-level key set is EXACTLY the contract');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r -> 'restaurant' from _sf where label = 'alpha')) k),
  'accent_color,address,card_mode,city,currency_code,display_name,hero_url,locale_default,logo_url,motion,phone,primary_color,slug,tagline,visual_preset',
  'C3. restaurant key set is EXACTLY the contract (no id, no org, no branch)');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r -> 'hours' from _sf where label = 'alpha')) k),
  'closes,next_open,open_now,opens,timezone',
  'C4. hours key set is EXACTLY the contract');
select is(
  (select r -> 'service' from _sf where label = 'alpha'),
  '{"state":"open","ordering_enabled":false,"pickup_enabled":true,"delivery_enabled":false}'::jsonb,
  'C5. service: open, ordering OFF, pickup on, delivery off');
select is(
  (select r -> 'tax' from _sf where label = 'alpha'),
  '{"enabled":true,"rate_bp":1800,"mode":"exclusive"}'::jsonb,
  'C6. tax served as integer basis points {enabled, rate_bp, mode}');
select is(
  (select string_agg(c ->> 'name', ',' order by (c ->> 'display_order')::int) from jsonb_array_elements((select r -> 'categories' from _sf where label = 'alpha')) c),
  'Burgers',
  'C7. categories: the live global category only (sibling-branch and inactive categories excluded)');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r -> 'categories' -> 0 from _sf where label = 'alpha')) k),
  'display_order,icon_key,id,name',
  'C8. category key set is EXACTLY the contract');
select is(
  (select string_agg(i ->> 'name', ',' order by (i ->> 'display_order')::int) from jsonb_array_elements((select r -> 'items' from _sf where label = 'alpha')) i),
  'Burger,Cola,PausedItem',
  'C9. items: live items of live categories at the storefront branch (SiblingOnly / DeadItem / DeadCatItem excluded)');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r -> 'items' -> 0 from _sf where label = 'alpha')) k),
  'availability,base_price_minor,category_id,description,display_order,id,image_url,name,tags',
  'C10. item key set is EXACTLY the contract');
select is(
  (select string_agg(i ->> 'name' || '=' || (i ->> 'availability'), ',' order by (i ->> 'display_order')::int) from jsonb_array_elements((select r -> 'items' from _sf where label = 'alpha')) i),
  'Burger=available,Cola=available,PausedItem=unavailable',
  'C11. sold-out comes from the STOREFRONT branch override only (the sibling-branch override on Burger is ignored)');
select is(
  (select i ->> 'image_url' from jsonb_array_elements((select r -> 'items' from _sf where label = 'alpha')) i where i ->> 'name' = 'Burger'),
  '/storage/v1/object/public/storefront-media/' || app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000a10') || '/' || repeat('a', 64) || '.webp',
  'C12. image_url is the PUBLIC derivative path (opaque prefix + content hash)');
select ok(
  (select i -> 'image_url' from jsonb_array_elements((select r -> 'items' from _sf where label = 'alpha')) i where i ->> 'name' = 'Cola') = 'null'::jsonb,
  'C13. an UNPUBLISHED derivative yields image_url null (never the private key)');
select ok(
  (select r::text from _sf where label = 'alpha') !~ '(privateorg|privaterest|menu_item/|\.jpg)',
  'C14. no private object key fragment appears anywhere in the payload text');
select ok(
  (select r::text from _sf where label = 'alpha') !~ '(00ad00000a00|00ad00000a10|00ad00000a1a|00ad00000a1b)',
  'C15. no organization / restaurant / branch UUID appears anywhere in the payload text');
select ok(
  (select r::text from _sf where label = 'alpha') !~ '(SKU-SECRET|kitchen_note|internal kitchen|prep_minutes|prep_components|"attributes"|item_type|image_path|kitchen_meat|allow_quantity|max_quantity|default_station|"sku")',
  'C16. no internal field or value (sku / kitchen_note / attributes / prep / item_type / kitchen_meat / quantity rules) appears in the payload text');
select is(
  (select string_agg(m ->> 'name' || ':' || (m ->> 'selection_type') || ':' || coalesce(m ->> 'max_select', 'null'), ',' order by (m ->> 'display_order')::int, m ->> 'name') from jsonb_array_elements((select r -> 'modifiers' from _sf where label = 'alpha')) m),
  'Extras:multiple:0,Weight:single:1',
  'C17. modifiers: live groups only (DeadMod / SiblingMod excluded); max_select 0 served as-is (the UI omits max)');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r -> 'modifiers' -> 0 from _sf where label = 'alpha')) k),
  'display_order,id,is_required,item_id,max_select,min_select,name,selection_type',
  'C18. modifier key set is EXACTLY the contract (no allow_quantity / max_quantity)');
select is(
  (select string_agg(o ->> 'name' || '=' || (o ->> 'price_delta_minor'), ',' order by o ->> 'name') from jsonb_array_elements((select r -> 'modifier_options' from _sf where label = 'alpha')) o),
  'Cheese=600,Classic=0,Double=1500',
  'C19. options: live options of live groups; NEGATIVE, tombstoned, dead-group and sibling options excluded');
select is(
  (select string_agg(k, ',' order by k) from jsonb_object_keys((select r -> 'modifier_options' -> 0 from _sf where label = 'alpha')) k),
  'display_order,id,modifier_id,name,price_delta_minor',
  'C20. option key set is EXACTLY the contract (no kitchen_meat)');
select is(
  (select i -> 'tags' from jsonb_array_elements((select r -> 'items' from _sf where label = 'alpha')) i where i ->> 'name' = 'Burger'),
  '["popular","new"]'::jsonb,
  'C21. tags are filtered to the client vocabulary (the off-vocabulary tag is dropped) and keep their order');
select ok((select r ->> 'menu_version' from _sf where label = 'alpha') ~ '^3\.[0-9]{9,}$',
  'C22. menu_version = profile version + newest catalog change epoch (opaque, cart-key sized)');
select ok(
  (select (r -> 'hours' ->> 'opens') ~ '^[0-2][0-9]:[0-5][0-9]$' and (r -> 'hours' ->> 'closes') ~ '^[0-2][0-9]:[0-5][0-9]$'
      and (r -> 'hours' ->> 'open_now')::boolean and r -> 'hours' -> 'next_open' = 'null'::jsonb and r -> 'hours' ->> 'timezone' = 'Asia/Jerusalem'
     from _sf where label = 'alpha'),
  'C23. hours: HH:MM strings, open_now true, next_open null while open, the BRANCH timezone');
select is(
  (select r -> 'restaurant' from _sf where label = 'alpha'),
  '{"slug":"sfr1-alpha","display_name":"Alpha <script>alert(1)</script>","tagline":"Tag line","city":"Kafr Manda","address":"Main St 1","phone":"052-000-0000","primary_color":"#123027","accent_color":"#ff8a2a","logo_url":null,"hero_url":null,"currency_code":"ILS","locale_default":"ar","visual_preset":"dark","card_mode":"list","motion":"full"}'::jsonb,
  'C24. restaurant block is served verbatim as JSON text (a hostile display_name is data, escaped by the renderer, never HTML here)');

-- ============================================================================
-- D. uniform not_found + browsable states .............................. (15)
-- ============================================================================
select is((select r from _sf where label = 'unknown'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D1. unknown slug -> the uniform not_found envelope');
select is((select r from _sf where label = 'unpublished'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D2. unpublished profile -> the SAME envelope (anti-oracle)');
select is((select r from _sf where label = 'suspended'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D3. suspended organization -> the same envelope');
select is((select r from _sf where label = 'delbranch'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D4. tombstoned storefront branch -> the same envelope');
select is((select r from _sf where label = 'notz'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D5. NULL timezone (branch and restaurant) -> the same envelope (never UTC by accident)');
select is((select r from _sf where label = 'euro'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D6. non-ILS currency -> the same envelope (D7 pilot precondition)');
select is((select r from _sf where label = 'inclusive'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D7. inclusive tax -> the same envelope (D7b pilot precondition)');
select ok(
  (select count(*) = 5 and count(distinct r::text) = 1 and min(r::text) = '{"ok": false, "error": "not_found", "entity": "storefront_menu"}'
     from _sf where label like 'grammar%'),
  'D8. every request-grammar refusal (space, leading hyphen, 64 chars, empty, NULL) is the byte-identical envelope');
select is((select r from _sf where label = 'short'), '{"ok":false,"error":"not_found","entity":"storefront_menu"}'::jsonb,
  'D9. a 2-char slug passes the request grammar but can match no row (storage grammar is stricter) -> not_found');
select ok(
  (select count(distinct r::text) = 1 from _sf where label in ('unknown', 'unpublished', 'suspended', 'delbranch', 'notz', 'euro', 'inclusive', 'short')),
  'D10. all eight failure classes are byte-identical (no ordering of checks leaks through)');
select is((select r -> 'service' ->> 'state' from _sf where label = 'closed'), 'closed',
  'D11. a tenant outside its hours is served with state=closed');
select ok(
  (select jsonb_array_length(r -> 'items') = 1 and (r -> 'hours' ->> 'open_now')::boolean = false and r -> 'hours' -> 'next_open' <> 'null'::jsonb
      and (r -> 'hours' ->> 'next_open')::timestamptz > now() and (r -> 'hours' ->> 'next_open')::timestamptz < now() + interval '8 days'
     from _sf where label = 'closed'),
  'D12. ...and stays browsable: items served, open_now false, next_open is the next window within 7 days');
select is((select r -> 'service' ->> 'state' from _sf where label = 'paused'), 'paused',
  'D13. paused_until in the future -> state=paused (takes precedence over open hours)');
select ok((select jsonb_array_length(r -> 'items') = 1 from _sf where label = 'paused'),
  'D14. ...and stays browsable');
select is((select r from _sf where label = 'big'), '{"ok":false,"error":"payload_limit","entity":"storefront_menu"}'::jsonb,
  'D15. 501 live items -> the TYPED payload_limit envelope, never not_found');

-- ============================================================================
-- E. the write RPC, the CHECK layer, the manager read .................. (34)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee02';   -- manager over R-A9
-- a CREATE under a slug that is live on another restaurant is refused before any row exists
-- (a rename of an existing row is refused earlier still, as slug_immutable - E13b)
insert into _sf values ('w_taken', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00006', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 0,
  '{"slug":"sfr1-alpha","storefront_branch_id":"00000000-0000-0000-0000-00ad00000a9a"}'::jsonb));
insert into _sf values ('w_create', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00001', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 0,
  '{"slug":"sfr1-niner","storefront_branch_id":"00000000-0000-0000-0000-00ad00000a9a","tagline":"  padded  "}'::jsonb));
insert into _sf values ('w_replay', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00001', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 0,
  '{"slug":"sfr1-niner","storefront_branch_id":"00000000-0000-0000-0000-00ad00000a9a","tagline":"  padded  "}'::jsonb));
insert into _sf values ('w_stale', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00002', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 0,
  '{"tagline":"stale"}'::jsonb));
insert into _sf values ('w_unknown', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00003', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"tagline":"x","foo":1}'::jsonb));
insert into _sf values ('w_ordering', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00004', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"ordering_enabled":true}'::jsonb));
insert into _sf values ('w_reserved', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00005', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"slug":"admin"}'::jsonb));
insert into _sf values ('w_grammar', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00007', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"slug":"Not-Valid"}'::jsonb));
insert into _sf values ('w_rename', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00021', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"slug":"sfr1-renamed"}'::jsonb));
insert into _sf values ('w_hours_bad', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00008', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"opening_hours":{"weekly":[{"dow":7,"open":"10:00","close":"11:00"}]}}'::jsonb));
insert into _sf values ('w_publish_blocked', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00009', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"is_published":true}'::jsonb));
insert into _sf values ('w_media_bad', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c0000a', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"logo_media_id":"00000000-0000-0000-0000-00ad0000f0a1"}'::jsonb));
insert into _sf values ('w_publish', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c0000b', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 1,
  '{"is_published":true,"opening_hours":{"weekly":[{"dow":0,"open":"09:00","close":"17:00"}],"exceptions":[{"date":"2026-12-25","closed":true}]},"public_phone":"+972520000000","primary_color":"#AABBCC"}'::jsonb));
-- paused_until wire format (review C3): ONE canonical shape - RFC 3339 with an explicit Z/offset - or null
insert into _sf values ('w_pause_word', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00031', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2,
  '{"paused_until":"tomorrow"}'::jsonb));
insert into _sf values ('w_pause_naive', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00032', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2,
  '{"paused_until":"2026-10-01 12:00"}'::jsonb));
insert into _sf values ('w_pause_inf', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00033', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2,
  '{"paused_until":"infinity"}'::jsonb));
insert into _sf values ('w_pause_date', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00034', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2,
  '{"paused_until":"2026-10-01"}'::jsonb));
insert into _sf values ('w_pause_iso', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00035', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2,
  '{"paused_until":"2026-10-01T12:00:00+03:00"}'::jsonb));
-- the stored instant, read back through the manager read BEFORE the pause is cleared
insert into _sf values ('r_after_pause', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90'));
insert into _sf values ('w_pause_clear', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c00036', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 3,
  '{"paused_until":null}'::jsonb));
insert into _sf values ('r_manager', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90'));
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee03';   -- cashier at R-A9
insert into _sf values ('w_cashier', public.set_restaurant_storefront_profile(
  '00000000-0000-0000-0000-00ad00c0000c', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2,
  '{"tagline":"nope"}'::jsonb));
insert into _sf values ('r_cashier', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90'));
set local app.current_app_user_id = '00000000-0000-0000-0000-00ad0000ee0b';   -- owner of Org B
select throws_ok(
  $$ select public.set_restaurant_storefront_profile('00000000-0000-0000-0000-00ad00c0000d', '00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90', 2, '{"tagline":"cross"}'::jsonb) $$,
  '42501', null,
  'E1. cross-tenant write (Org B owner on an Org A restaurant) raises 42501 with no state leak');
insert into _sf values ('r_orgb', public.get_restaurant_storefront_profile('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a90'));
select throws_ok(
  $$ insert into public.restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name)
     values ('00000000-0000-0000-0000-00ad00000b10', '00000000-0000-0000-0000-00ad00000b00', '00000000-0000-0000-0000-00ad00000b1a', 'sfr1-rogue', 'Rogue') $$,
  '42501', null,
  'E2. authenticated direct INSERT into the profile table is denied (RPC-only)');
select throws_ok(
  $$ select count(*) from public.storefront_media $$,
  '42501', null,
  'E3. authenticated direct SELECT on storefront_media is denied (RPC-only)');
reset role;

select ok((select (r ->> 'ok')::boolean and (r ->> 'version')::int = 1 and r ->> 'slug' = 'sfr1-niner' and not (r ->> 'is_published')::boolean from _sf where label = 'w_create'),
  'E4. manager creates the profile (expected_version 0) -> ok, version 1, unpublished');
select is((select display_name from restaurant_storefront_profiles where restaurant_id = '00000000-0000-0000-0000-00ad00000a90'),
  'SFR Rest A9 Name Is Long Enough To Be Truncated At Sixty Cha',
  'E5. display_name defaults to the restaurant name, truncated to 60');
select is((select tagline from restaurant_storefront_profiles where restaurant_id = '00000000-0000-0000-0000-00ad00000a90'), 'padded',
  'E6. text fields are trimmed on write');
select ok((select (r ->> 'idempotent_replay')::boolean and (r ->> 'version')::int = 1 from _sf where label = 'w_replay'),
  'E7. the same (actor, client_request_id, input) replays the stored result (no second version)');
select is((select r ->> 'error' || ':' || (r ->> 'version') from _sf where label = 'w_stale'), 'version_conflict:1',
  'E8. a stale expected_version returns version_conflict carrying the CURRENT version');
select is((select r ->> 'error' || ':' || (r ->> 'reason') || ':' || (r ->> 'field') from _sf where label = 'w_unknown'), 'invalid:unknown_field:foo',
  'E9. an unknown patch field is refused before anything is written');
select is((select r ->> 'error' || ':' || (r ->> 'reason') || ':' || (r ->> 'field') from _sf where label = 'w_ordering'), 'invalid:unknown_field:ordering_enabled',
  'E10. ordering_enabled is NOT patchable in this slice (browse-only)');
select is((select r ->> 'reason' from _sf where label = 'w_reserved'), 'slug_invalid',
  'E11. a reserved word is refused as a slug');
select is((select r ->> 'reason' from _sf where label = 'w_taken'), 'slug_taken',
  'E12. a slug live on another restaurant is refused at creation (slug_taken; no row is created)');
select is((select r ->> 'reason' from _sf where label = 'w_grammar'), 'slug_invalid',
  'E13. upper-case is refused (storage grammar)');
select is((select r ->> 'reason' from _sf where label = 'w_rename'), 'slug_immutable',
  'E13b. a live slug cannot be renamed in this slice (slug_immutable - plan decision D4 / OPEN QUESTION Q-029)');
select is((select r ->> 'reason' from _sf where label = 'w_hours_bad'), 'opening_hours_invalid',
  'E14. dow 7 is refused by the hours validator (typed, not a CHECK violation)');
select is((select r ->> 'reason' || ':' || (r -> 'detail')::text from _sf where label = 'w_publish_blocked'), 'publish_precondition:["hours_missing"]',
  'E15. publishing without hours is refused with the ordered blocker list (slug/branch/tz/ILS/tax/items already satisfied)');
select is((select r ->> 'reason' from _sf where label = 'w_media_bad'), 'logo_media_id_invalid',
  'E16. a media row of ANOTHER restaurant cannot be referenced');
select ok((select (r ->> 'ok')::boolean and (r ->> 'is_published')::boolean and (r ->> 'version')::int = 2 from _sf where label = 'w_publish'),
  'E17. publishing with every precondition met -> ok, is_published true, version 2');
select is((select primary_color || '/' || public_phone from restaurant_storefront_profiles where restaurant_id = '00000000-0000-0000-0000-00ad00000a90'), '#aabbcc/+972520000000',
  'E18. colours are lower-cased; an E.164 phone is accepted');
select is((select r ->> 'error' from _sf where label = 'w_cashier'), 'permission_denied',
  'E19. a cashier is denied (typed, no raise)');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00ad00000a00' and action = 'settings.storefront.update_denied'), 1,
  'E20. the denial is audited once');
select is((select count(*)::int from audit_events where organization_id = '00000000-0000-0000-0000-00ad00000a00' and action = 'settings.storefront.updated'), 4,
  'E21. the four accepted writes are audited (create + publish + pause + clear); replay / stale / invalid audit nothing');
select ok((select (r ->> 'ok')::boolean and (r ->> 'exists')::boolean and (r -> 'derived' ->> 'publish_ready')::boolean
              and r -> 'derived' ->> 'timezone' = 'Asia/Jerusalem' and r -> 'derived' ->> 'currency_code' = 'ILS'
              and (r -> 'derived' -> 'tax' ->> 'rate_bp')::int = 1700
              and r -> 'derived' ->> 'media_prefix' = app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000a90')
              and (r -> 'profile') ? 'slug' and not ((r -> 'profile') ? 'organization_id')
             from _sf where label = 'r_manager'),
  'E22. the manager read carries the profile (no organization_id), the derived tz/currency/tax, publish readiness and the media prefix');
select is((select r ->> 'error' from _sf where label = 'r_cashier'), 'not_found',
  'E23. below manager the read is not_found (no leak)');
select is((select r ->> 'error' from _sf where label = 'r_orgb'), 'not_found',
  'E24. cross-tenant read is not_found (no leak)');
select throws_ok(
  $$ update public.restaurant_storefront_profiles set ordering_enabled = true where restaurant_id = '00000000-0000-0000-0000-00ad00000a90' $$,
  '23514', null,
  'E25. the browse-only CHECK refuses ordering_enabled=true even for the harness role (layer 4)');
select throws_ok(
  $$ update public.restaurant_storefront_profiles set slug = 'Kiosk' where restaurant_id = '00000000-0000-0000-0000-00ad00000a90' $$,
  '23514', null,
  'E26. the storage-grammar CHECK refuses upper-case at the table (layer 4)');
select throws_ok(
  $$ insert into public.storefront_media (organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes)
     values ('00000000-0000-0000-0000-00ad00000a00', '00000000-0000-0000-0000-00ad00000a10', 'menu-images', 'k', 'w480', app.storefront_media_prefix('00000000-0000-0000-0000-00ad00000b10') || '/' || repeat('c', 64) || '.webp', repeat('c', 64), 1, 1, 1) $$,
  '23514', null,
  'E27. a derivative cannot be registered under ANOTHER restaurant''s opaque prefix (key-shape CHECK)');
select is((select r ->> 'reason' from _sf where label = 'w_pause_word'), 'paused_until_invalid',
  'E28. paused_until: a relative word (tomorrow) is refused');
select is((select r ->> 'reason' from _sf where label = 'w_pause_naive'), 'paused_until_invalid',
  'E29. paused_until: an offset-less timestamp (session-zone dependent) is refused');
select is((select r ->> 'reason' from _sf where label = 'w_pause_inf'), 'paused_until_invalid',
  'E30. paused_until: infinity is refused');
select is((select r ->> 'reason' from _sf where label = 'w_pause_date'), 'paused_until_invalid',
  'E31. paused_until: a bare date is refused');
select ok((select (r ->> 'ok')::boolean and (r ->> 'version')::int = 3 from _sf where label = 'w_pause_iso')
          and (select (r -> 'profile' ->> 'paused_until')::timestamptz = '2026-10-01T09:00:00Z'::timestamptz from _sf where label = 'r_after_pause'),
  'E32. paused_until: an RFC 3339 instant with an explicit offset is accepted and stored as that instant (deterministic across session zones)');
select ok((select (r ->> 'ok')::boolean and (r ->> 'version')::int = 4 from _sf where label = 'w_pause_clear')
          and (select paused_until is null from restaurant_storefront_profiles where restaurant_id = '00000000-0000-0000-0000-00ad00000a90'),
  'E33. paused_until: null clears the pause');

-- ============================================================================
-- F. the newly published tenant is served by the public read ............. (2)
-- ============================================================================
set local role anon;
insert into _sf values ('niner', public.storefront_menu('sfr1-niner'));
reset role;
select ok((select (r ->> 'ok')::boolean and r -> 'tax' = '{"enabled":true,"rate_bp":1700,"mode":"exclusive"}'::jsonb and jsonb_array_length(r -> 'items') = 1 from _sf where label = 'niner'),
  'F1. the profile published through the RPC is served to anon with the branch tax rate');
select ok((select case when (r -> 'hours' ->> 'open_now')::boolean
                       then (r -> 'hours' ->> 'opens') = '09:00' and (r -> 'hours' ->> 'closes') = '17:00'
                       else (r -> 'hours' ->> 'next_open') is not null
                            and extract(dow from ((r -> 'hours' ->> 'next_open')::timestamptz at time zone (r -> 'hours' ->> 'timezone'))) = 0
                            and to_char(((r -> 'hours' ->> 'next_open')::timestamptz at time zone (r -> 'hours' ->> 'timezone')), 'HH24:MI') = '09:00'
                            and ((r -> 'hours' ->> 'opens') is null or (r -> 'hours' ->> 'opens') = '09:00')
                  end
           from _sf where label = 'niner'),
  'F2. the served window is the profile''s own: open now => 09:00-17:00; else next_open is a Sunday 09:00 local and opens/closes describe TODAY only (null on another day)');

-- ============================================================================
-- G. the hours helper at fixed instants ................................... (3)
-- ============================================================================
-- Asia/Jerusalem, Wednesday 2026-09-23 23:30 local = 20:30Z; a window 18:00 -> 02:00 on dow 3
select is(
  (select opens || '-' || closes || ':' || open_now::text from app.storefront_service_window(
     '{"weekly":[{"dow":3,"open":"18:00","close":"02:00"}]}'::jsonb, 'Asia/Jerusalem', '2026-09-23T20:30:00Z'::timestamptz)),
  '18:00-02:00:true',
  'G1. a midnight-crossing window is OPEN at 23:30 local');
select is(
  (select opens || '-' || closes || ':' || open_now::text from app.storefront_service_window(
     '{"weekly":[{"dow":3,"open":"18:00","close":"02:00"}]}'::jsonb, 'Asia/Jerusalem', '2026-09-23T22:30:00Z'::timestamptz)),
  '18:00-02:00:true',
  'G2. ...and still OPEN at 01:30 local the next calendar day (the wrap is honoured)');
select ok(
  (select not open_now and opens is null and closes is null and next_open = '2026-09-30T15:00:00Z'::timestamptz from app.storefront_service_window(
     '{"weekly":[{"dow":3,"open":"18:00","close":"02:00"}],"exceptions":[{"date":"2026-09-23","closed":true}]}'::jsonb, 'Asia/Jerusalem', '2026-09-23T20:30:00Z'::timestamptz)),
  'G3. an exception closes the day: opens/closes are null (no window starts today) and next_open rolls to the following week''s window (18:00 local = 15:00Z)');

select * from finish();
rollback;
