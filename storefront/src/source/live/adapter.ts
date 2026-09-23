/**
 * THE LIVE ADAPTER - the decoded envelope becomes the same `HomeView` shape the
 * fixture produces, so no component learns where data came from (types.ts).
 *
 * RULES CARRIED HERE (packet §3):
 *   - icons come from the registry by KEY; tenant text never becomes an SVG path
 *   - image/logo/hero URLs are accepted ONLY as public derivative paths under the
 *     configured origin; anything else becomes null (defence in depth: the RPC
 *     already never serves a private key)
 *   - `signature` = the `popular` tag; `badge` = the `new` tag; `featured` is
 *     always false (no storage); `deal` is never produced
 *   - a category without a live item is not shown; an item whose category is
 *     not served is dropped; a group without a live option is dropped
 *   - `max` is omitted when max_select is NULL or 0 (the sheet would otherwise
 *     refuse every selection); quantity groups are plain multi-select (D10)
 *   - `required` = is_required OR min_select >= 1 (the UI's "at least one")
 *   - the campaign hero falls back to the tagline, else the display name, with
 *     an EMPTY subline the hero omits (D11); every other optional module is off
 *   - ordering is OFF, delivery is OFF, zones are empty: the flow is browse-only
 *
 * Pure: no I/O. `liveSource` is the only thing that calls the client.
 */
import type {
  Category,
  HomeView,
  MenuItem,
  ModifierGroup,
  ModifierOption,
  Preset,
  StorefrontResolution,
  StorefrontSource,
  Tenant,
} from '../types';
import { isValidSlug } from '@/theme/sanitize';
import { fetchStorefrontMenu, liveConfig, type LiveConfig } from './client';
import { decodeStorefrontMenu, type StorefrontMenuOk } from './decode';
import { iconPathFor } from './icons';

const MEDIA_PATH = /^\/storage\/v1\/object\/public\/storefront-media\/[0-9a-f]{32}\/[0-9a-f]{64}\.webp$/;

/** A public derivative path made absolute on the configured origin, else null. */
export function mediaUrl(path: string | null, origin: string): string | null {
  if (path === null || !MEDIA_PATH.test(path)) return null;
  return `${origin}${path}`;
}

export interface AdaptedStorefront extends StorefrontResolution {
  readonly tenant: Tenant;
}

export function adaptStorefront(envelope: StorefrontMenuOk, origin: string): StorefrontResolution {
  const r = envelope.restaurant;
  const tenant: Tenant = {
    slug: r.slug,
    displayName: r.display_name,
    tagline: r.tagline ?? '',
    city: r.city ?? '',
    address: r.address ?? '',
    phone: r.phone ?? '',
    brand: { primary: r.primary_color, accent: r.accent_color, logo: mediaUrl(r.logo_url, origin) },
    hours: { opens: envelope.hours.opens ?? '', closes: envelope.hours.closes ?? '', nextOpen: envelope.hours.next_open },
    service: {
      state: envelope.service.state,
      pickupEnabled: envelope.service.pickup_enabled,
      deliveryEnabled: false,
      deliveryFromMinor: 0,
      orderingEnabled: false,
    },
    heroImage: mediaUrl(r.hero_url, origin),
    currency: 'ILS',
  };

  // groups with at least one live option, in display order
  const optionsByGroup = new Map<string, ModifierOption[]>();
  for (const o of envelope.modifier_options) {
    const bucket = optionsByGroup.get(o.modifier_id) ?? [];
    bucket.push({ id: o.id, name: o.name, priceDeltaMinor: o.price_delta_minor });
    optionsByGroup.set(o.modifier_id, bucket);
  }
  const groupsByItem = new Map<string, string[]>();
  const groups: ModifierGroup[] = [];
  for (const m of envelope.modifiers) {
    const options = optionsByGroup.get(m.id);
    if (options === undefined || options.length === 0) continue;
    const single = m.selection_type === 'single';
    const max = !single && m.max_select !== null && m.max_select > 0 ? m.max_select : undefined;
    groups.push({
      id: m.id,
      name: m.name,
      required: m.is_required || m.min_select >= 1,
      single,
      ...(max === undefined ? {} : { max }),
      options,
    });
    const ids = groupsByItem.get(m.item_id) ?? [];
    ids.push(m.id);
    groupsByItem.set(m.item_id, ids);
  }

  const servedCategoryIds = new Set(envelope.categories.map((c) => c.id));
  const items: MenuItem[] = [];
  for (const i of envelope.items) {
    if (!servedCategoryIds.has(i.category_id)) continue;
    const groupIds = groupsByItem.get(i.id) ?? [];
    items.push({
      id: i.id,
      categoryId: i.category_id,
      name: i.name,
      description: i.description,
      priceMinor: i.base_price_minor,
      image: mediaUrl(i.image_url, origin),
      featured: false,
      signature: i.tags.includes('popular'),
      badge: i.tags.includes('new') ? 'new' : null,
      soldOut: i.availability === 'unavailable',
      hasOptions: groupIds.length > 0,
      groupIds,
    });
  }
  const populated = new Set(items.map((i) => i.categoryId));
  const categories: Category[] = envelope.categories
    .filter((c) => populated.has(c.id))
    .map((c) => ({ id: c.id, name: c.name, image: null, iconPath: iconPathFor(c.icon_key), blurb: null }));

  const taxRateBp = envelope.tax.enabled ? envelope.tax.rate_bp : 0;
  const view: HomeView = {
    tenant,
    modules: {
      announcement: null,
      campaign: { title: r.tagline ?? r.display_name, subline: '' },
      promo: null,
      story: null,
      popular: { enabled: items.some((i) => i.signature && !i.soldOut), ready: false },
    },
    categories,
    items,
    cardMode: r.card_mode,
    motion: r.motion,
    // The presentational cart of the fixture era: nothing on any screen renders
    // it (Home.tsx), and a live document carries no visitor's cart.
    cart: { lines: [], itemCount: 0, subtotalMinor: 0, taxMinor: 0, totalMinor: 0, taxRateBp },
  };
  const preset: Preset = r.visual_preset;
  return { view, preset, groups, zones: [], taxRateBp, menuVersion: envelope.menu_version };
}

/**
 * The live source. `not_found` -> null (the page renders the Unknown document,
 * cached like any document); any other failure envelope or transport error ->
 * throw (never the fixture, never a fabricated menu).
 */
export function liveStorefrontSource(config?: LiveConfig): StorefrontSource {
  return {
    kind: 'live',
    async getStorefront(slug: string): Promise<StorefrontResolution | null> {
      if (!isValidSlug(slug)) return null;
      const cfg = config ?? liveConfig();
      const envelope = decodeStorefrontMenu(await fetchStorefrontMenu(slug, cfg));
      if (!envelope.ok) {
        if (envelope.error === 'not_found') return null;
        throw new Error(`storefront_menu answered ${envelope.error}`);
      }
      if (envelope.restaurant.slug !== slug) throw new Error('storefront_menu answered a different slug');
      return adaptStorefront(envelope, cfg.url);
    },
    staticSlugs(): readonly string[] {
      // Nothing is pre-rendered in live mode: every slug renders on demand and
      // is cached per URL (revalidate = 60).
      return [];
    },
  };
}
