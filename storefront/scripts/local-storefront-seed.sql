-- ============================================================================
-- STOREFRONT-READ-001 - LOCAL-ONLY synthetic tenants for the live-mode browser
-- smoke (tests/browser/storefront-read-001.spec.ts) and manual local runs.
--
-- Runs against the LOCAL Docker Supabase only (scripts/seed-local.mjs refuses
-- any non-loopback database URL). ONE statement (a DO block) because the CLI's
-- `db query -f` sends the file as a single prepared statement. Idempotent:
-- every row is keyed by a fixed synthetic UUID under the
-- 00000000-0000-0000-0000-00ad1... prefix and upserted. Nothing here is a real
-- restaurant, person or image; the media row points at an object that is never
-- uploaded (the derivative URL 404s locally, which the DOM-level assertions
-- tolerate by design).
--
-- Tenants:
--   sf-synth-a   published, ALWAYS open (two windows a day that cover 24 h),
--                tax 18% exclusive, a hostile display_name, one published
--                derivative on the first item, one sold-out item, groups
--   sf-synth-b   published, PAUSED (paused_until far in the future), tax off
--   sf-synth-c   NOT published (must 404 exactly like an unknown slug)
-- ============================================================================
do $seed$
declare
  v_hours jsonb;
begin
  insert into public.organizations (id, name, slug, default_currency, status) values
    ('00000000-0000-0000-0000-00ad10000a00', 'SYNTH Org A (local)', 'sf-synth-org-a', 'ILS', 'active'),
    ('00000000-0000-0000-0000-00ad10000b00', 'SYNTH Org B (local)', 'sf-synth-org-b', 'ILS', 'active')
  on conflict (id) do update set name = excluded.name, default_currency = excluded.default_currency, status = excluded.status, deleted_at = null;

  insert into public.restaurants (id, organization_id, name, timezone) values
    ('00000000-0000-0000-0000-00ad10000a10', '00000000-0000-0000-0000-00ad10000a00', 'SYNTH Rest A1', 'Asia/Jerusalem'),
    ('00000000-0000-0000-0000-00ad10000a20', '00000000-0000-0000-0000-00ad10000a00', 'SYNTH Rest A2', 'Asia/Jerusalem'),
    ('00000000-0000-0000-0000-00ad10000b10', '00000000-0000-0000-0000-00ad10000b00', 'SYNTH Rest B1', 'Asia/Jerusalem')
  on conflict (id) do update set name = excluded.name, timezone = excluded.timezone, status = 'active', deleted_at = null;

  insert into public.branches (id, organization_id, restaurant_id, name, timezone, tax_enabled, tax_rate_bp, tax_mode) values
    ('00000000-0000-0000-0000-00ad10000a1a', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', 'SYNTH A1a', 'Asia/Jerusalem', true, 1800, 'exclusive'),
    ('00000000-0000-0000-0000-00ad10000a2a', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a20', 'SYNTH A2a', 'Asia/Jerusalem', false, 0, 'exclusive'),
    ('00000000-0000-0000-0000-00ad10000b1a', '00000000-0000-0000-0000-00ad10000b00', '00000000-0000-0000-0000-00ad10000b10', 'SYNTH B1a', 'Asia/Jerusalem', false, 0, 'exclusive')
  on conflict (id) do update set name = excluded.name, timezone = excluded.timezone, tax_enabled = excluded.tax_enabled, tax_rate_bp = excluded.tax_rate_bp, tax_mode = excluded.tax_mode, status = 'active', deleted_at = null;

  insert into public.menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active, icon_key) values
    ('00000000-0000-0000-0000-00ad1000c1a1', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, 'SYNTH Burgers', 0, true, 'burger'),
    ('00000000-0000-0000-0000-00ad1000c1a2', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, 'SYNTH Drinks', 1, true, 'drinks'),
    ('00000000-0000-0000-0000-00ad1000c1b1', '00000000-0000-0000-0000-00ad10000b00', '00000000-0000-0000-0000-00ad10000b10', null, 'SYNTH Pizza', 0, true, 'pizza'),
    ('00000000-0000-0000-0000-00ad1000c1a3', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a20', null, 'SYNTH Hidden', 0, true, null)
  on conflict (id) do update set name = excluded.name, display_order = excluded.display_order, is_active = excluded.is_active, icon_key = excluded.icon_key, deleted_at = null;

  insert into public.menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, description, base_price_minor, currency_code, display_order, is_active, image_path, tags, sku, kitchen_note) values
    ('00000000-0000-0000-0000-00ad10011a01', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000c1a1', 'SYNTH Classic', 'SYNTH 180 g beef, cheddar, lettuce', 5500, 'ILS', 0, true, 'privateorg/privaterest/global/menu_item/a01/classic.jpg', '["popular","new"]'::jsonb, 'SYNTH-SKU-SECRET', 'SYNTH internal note'),
    ('00000000-0000-0000-0000-00ad10011a02', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000c1a1', 'SYNTH Double', 'SYNTH two patties', 7500, 'ILS', 1, true, null, '["popular"]'::jsonb, null, null),
    ('00000000-0000-0000-0000-00ad10011a03', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000c1a1', 'SYNTH Sold Out', 'SYNTH gone today', 6500, 'ILS', 2, true, null, null, null, null),
    ('00000000-0000-0000-0000-00ad10011a04', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000c1a2', 'SYNTH Cola', null, 1200, 'ILS', 0, true, null, null, null, null),
    ('00000000-0000-0000-0000-00ad10011b01', '00000000-0000-0000-0000-00ad10000b00', '00000000-0000-0000-0000-00ad10000b10', null, '00000000-0000-0000-0000-00ad1000c1b1', 'SYNTH Margherita', 'SYNTH tomato and basil', 4800, 'ILS', 0, true, null, '["vegetarian"]'::jsonb, null, null),
    ('00000000-0000-0000-0000-00ad10011a31', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a20', null, '00000000-0000-0000-0000-00ad1000c1a3', 'SYNTH Hidden Item', null, 100, 'ILS', 0, true, null, null, null, null)
  on conflict (id) do update set name = excluded.name, description = excluded.description, base_price_minor = excluded.base_price_minor, display_order = excluded.display_order, is_active = excluded.is_active, image_path = excluded.image_path, tags = excluded.tags, sku = excluded.sku, kitchen_note = excluded.kitchen_note, deleted_at = null;

  insert into public.menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
    ('00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', '00000000-0000-0000-0000-00ad10000a1a', '00000000-0000-0000-0000-00ad10011a03', 'unavailable', 'sold_out')
  on conflict (organization_id, branch_id, menu_item_id) do update set availability = excluded.availability, reason = excluded.reason;

  insert into public.modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, min_select, max_select, is_required, is_active) values
    ('00000000-0000-0000-0000-00ad1000d1a1', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad10011a01', 'SYNTH Bun', 'single', 1, 1, true, true),
    ('00000000-0000-0000-0000-00ad1000d1a2', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad10011a01', 'SYNTH Extras', 'multiple', 0, 3, false, true)
  on conflict (id) do update set name = excluded.name, selection_type = excluded.selection_type, min_select = excluded.min_select, max_select = excluded.max_select, is_required = excluded.is_required, is_active = excluded.is_active, deleted_at = null;

  insert into public.modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active) values
    ('00000000-0000-0000-0000-00ad1000d2a1', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000d1a1', 'SYNTH Classic bun', 0, 0, true),
    ('00000000-0000-0000-0000-00ad1000d2a2', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000d1a1', 'SYNTH Brioche', 500, 1, true),
    ('00000000-0000-0000-0000-00ad1000d2a3', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000d1a2', 'SYNTH Cheese', 600, 0, true),
    ('00000000-0000-0000-0000-00ad1000d2a4', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', null, '00000000-0000-0000-0000-00ad1000d1a2', 'SYNTH Egg', 500, 1, true)
  on conflict (id) do update set name = excluded.name, price_delta_minor = excluded.price_delta_minor, display_order = excluded.display_order, is_active = excluded.is_active, deleted_at = null;

  -- a published derivative for the first item (no object is uploaded locally)
  insert into public.storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant, object_key, content_hash, width, height, bytes, published_at, unpublished_at) values
    ('00000000-0000-0000-0000-00ad1000f0a1', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a10', 'menu-images', 'privateorg/privaterest/global/menu_item/a01/classic.jpg', 'w480',
     app.storefront_media_prefix('00000000-0000-0000-0000-00ad10000a10') || '/' || repeat('c', 64) || '.webp', repeat('c', 64), 480, 480, 20480, now(), null)
  on conflict (id) do update set published_at = excluded.published_at, unpublished_at = null;

  -- "always open": two windows a day, 00:00-12:00 and 11:00-00:00 (crossing midnight)
  select jsonb_build_object('weekly',
      (select jsonb_agg(jsonb_build_object('dow', d, 'open', o, 'close', c))
         from generate_series(0, 6) d cross join (values ('00:00', '12:00'), ('11:00', '00:00')) w(o, c)),
      'exceptions', '[]'::jsonb)
    into v_hours;

  insert into public.restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name, tagline, public_city, public_address, public_phone, primary_color, accent_color, visual_preset, locale_default, card_mode, motion, pickup_enabled, paused_until, pause_reason, opening_hours, logo_media_id, hero_media_id, is_published, version) values
    ('00000000-0000-0000-0000-00ad10000a10', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a1a', 'sf-synth-a', 'SYNTH Alpha <script>alert(1)</script>', 'SYNTH tagline for alpha', 'SYNTH City', 'SYNTH Main St 1', '052-000-0001', '#123027', '#ff8a2a', 'dark', 'ar', 'list', 'full', true, null, null, v_hours, null, null, true, 1),
    ('00000000-0000-0000-0000-00ad10000b10', '00000000-0000-0000-0000-00ad10000b00', '00000000-0000-0000-0000-00ad10000b1a', 'sf-synth-b', 'SYNTH Bravo', null, 'SYNTH Town', 'SYNTH Side St 2', '+972520000002', '#2a1240', '#3dd1a0', 'light', 'en', 'grid', 'calm', true, now() + interval '365 days', 'SYNTH paused', v_hours, null, null, true, 1),
    ('00000000-0000-0000-0000-00ad10000a20', '00000000-0000-0000-0000-00ad10000a00', '00000000-0000-0000-0000-00ad10000a2a', 'sf-synth-c', 'SYNTH Charlie (unpublished)', null, null, null, null, '#13322a', '#e07b2c', 'dark', 'ar', 'list', 'full', true, null, null, v_hours, null, null, false, 1)
  on conflict (restaurant_id) do update set
    storefront_branch_id = excluded.storefront_branch_id, slug = excluded.slug, display_name = excluded.display_name, tagline = excluded.tagline,
    public_city = excluded.public_city, public_address = excluded.public_address, public_phone = excluded.public_phone,
    primary_color = excluded.primary_color, accent_color = excluded.accent_color, visual_preset = excluded.visual_preset,
    locale_default = excluded.locale_default, card_mode = excluded.card_mode, motion = excluded.motion, pickup_enabled = excluded.pickup_enabled,
    paused_until = excluded.paused_until, pause_reason = excluded.pause_reason, opening_hours = excluded.opening_hours,
    logo_media_id = excluded.logo_media_id, hero_media_id = excluded.hero_media_id, is_published = excluded.is_published, deleted_at = null;
end
$seed$;
