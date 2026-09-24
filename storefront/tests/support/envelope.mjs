// STOREFRONT-READ-001 - ONE synthetic `storefront_menu` envelope, shaped exactly
// like the RPC's success body (docs/API_CONTRACT.md §4.42), shared by the unit
// tests (decoder / adapter) and the Playwright live spec's stub server so the
// two can never disagree about the wire contract. Every value is synthetic.
export const SYNTH_IDS = Object.freeze({
  catFood: '00000000-0000-0000-0000-00ad0000c1a1',
  catEmpty: '00000000-0000-0000-0000-00ad0000c1a2',
  burger: '00000000-0000-0000-0000-00ad00011a01',
  cola: '00000000-0000-0000-0000-00ad00011a02',
  soldOut: '00000000-0000-0000-0000-00ad00011a03',
  orphan: '00000000-0000-0000-0000-00ad00011a09',
  weight: '00000000-0000-0000-0000-00ad0000d1a1',
  extras: '00000000-0000-0000-0000-00ad0000d1a2',
  emptyGroup: '00000000-0000-0000-0000-00ad0000d1a3',
  classic: '00000000-0000-0000-0000-00ad0000d2a1',
  double: '00000000-0000-0000-0000-00ad0000d2a2',
  cheese: '00000000-0000-0000-0000-00ad0000d2a5',
});

export const SYNTH_MEDIA_PATH =
  '/storage/v1/object/public/storefront-media/0123456789abcdef0123456789abcdef/' + 'a'.repeat(64) + '.webp';

/** A published, open, browse-only tenant with one live category. */
export function syntheticEnvelope(over = {}) {
  const base = {
    ok: true,
    entity: 'storefront_menu',
    menu_version: '3.1758600000',
    server_ts: '2026-09-23T12:00:00+00:00',
    restaurant: {
      slug: 'sf-synth-a',
      display_name: 'Synth Alpha <script>alert(1)</script>',
      tagline: 'SYNTH TAGLINE',
      city: 'Synth City',
      address: 'Synth St 1',
      phone: '052-000-0000',
      primary_color: '#123027',
      accent_color: '#ff8a2a',
      logo_url: null,
      hero_url: null,
      currency_code: 'ILS',
      locale_default: 'ar',
      visual_preset: 'dark',
      card_mode: 'list',
      motion: 'full',
    },
    hours: { timezone: 'Asia/Jerusalem', opens: '00:00', closes: '00:00', open_now: true, next_open: null },
    service: { state: 'open', ordering_enabled: false, pickup_enabled: true, delivery_enabled: false },
    tax: { enabled: true, rate_bp: 1800, mode: 'exclusive' },
    categories: [
      { id: SYNTH_IDS.catFood, name: 'Synth Food', display_order: 0, icon_key: 'burger' },
      { id: SYNTH_IDS.catEmpty, name: 'Synth Empty', display_order: 1, icon_key: 'not-a-registry-key' },
    ],
    items: [
      { id: SYNTH_IDS.burger, category_id: SYNTH_IDS.catFood, name: 'Synth Burger', description: 'Synth beef', base_price_minor: 4000, display_order: 0, tags: ['popular', 'new'], image_url: SYNTH_MEDIA_PATH, availability: 'available' },
      { id: SYNTH_IDS.cola, category_id: SYNTH_IDS.catFood, name: 'Synth Cola', description: '', base_price_minor: 1000, display_order: 1, tags: [], image_url: null, availability: 'available' },
      { id: SYNTH_IDS.soldOut, category_id: SYNTH_IDS.catFood, name: 'Synth Sold Out', description: 'gone', base_price_minor: 900, display_order: 2, tags: ['popular'], image_url: null, availability: 'unavailable' },
      { id: SYNTH_IDS.orphan, category_id: '00000000-0000-0000-0000-00ad0000c1ff', name: 'Synth Orphan', description: '', base_price_minor: 100, display_order: 3, tags: [], image_url: null, availability: 'available' },
    ],
    modifiers: [
      { id: SYNTH_IDS.weight, item_id: SYNTH_IDS.burger, name: 'Synth Weight', selection_type: 'single', min_select: 1, max_select: 1, is_required: true, display_order: 0 },
      { id: SYNTH_IDS.extras, item_id: SYNTH_IDS.burger, name: 'Synth Extras', selection_type: 'multiple', min_select: 0, max_select: 0, is_required: false, display_order: 1 },
      { id: SYNTH_IDS.emptyGroup, item_id: SYNTH_IDS.burger, name: 'Synth Empty Group', selection_type: 'multiple', min_select: 0, max_select: null, is_required: false, display_order: 2 },
    ],
    modifier_options: [
      { id: SYNTH_IDS.classic, modifier_id: SYNTH_IDS.weight, name: 'Synth Classic', price_delta_minor: 0, display_order: 0 },
      { id: SYNTH_IDS.double, modifier_id: SYNTH_IDS.weight, name: 'Synth Double', price_delta_minor: 1500, display_order: 1 },
      { id: SYNTH_IDS.cheese, modifier_id: SYNTH_IDS.extras, name: 'Synth Cheese', price_delta_minor: 600, display_order: 0 },
    ],
  };
  return deepMerge(base, over);
}

export const NOT_FOUND_ENVELOPE = Object.freeze({ ok: false, error: 'not_found', entity: 'storefront_menu' });
export const PAYLOAD_LIMIT_ENVELOPE = Object.freeze({ ok: false, error: 'payload_limit', entity: 'storefront_menu' });

function deepMerge(base, over) {
  if (Array.isArray(over) || typeof over !== 'object' || over === null) return over;
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) {
    out[k] = typeof v === 'object' && v !== null && !Array.isArray(v) && typeof base?.[k] === 'object' && base[k] !== null && !Array.isArray(base[k])
      ? deepMerge(base[k], v)
      : v;
  }
  return out;
}
