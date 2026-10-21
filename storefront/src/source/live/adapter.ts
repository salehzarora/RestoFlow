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
 *   - min/max count distinct choices; per-option quantities retain their own
 *     published bounds. Impossible required groups remain visible and block.
 *   - old catalog envelopes have quantity selection off until rollout
 *   - approved public Home copy comes from the versioned profile projection;
 *     absent headline keeps the tagline/name fallback and absent optional copy
 *     stays absent. No promo/story/ranking is invented.
 *   - every tenant follows its server-admitted Pickup configuration and
 *     current service state. Delivery stays OFF and zones stay empty.
 *
 * Pure: no I/O. `liveSource` is the only thing that calls the client.
 */
import type {
  Category,
  HomeView,
  MenuItem,
  ModifierGroup,
  ModifierOption,
  NextOpenAt,
  Preset,
  StorefrontResolution,
  StorefrontSource,
  Tenant,
} from '../types';
import { isValidSlug } from '@/theme/sanitize';
import { fetchStorefrontMenu, liveConfig, type LiveConfig } from './client';
import type { StorefrontMenuOk } from './decode';
import { decodeStorefrontMenuV2, type StorefrontMenuV2Ok } from './decodeHomeContent';
import { iconPathFor } from './icons';
import { liveOrderingEnabled, orderEndpointOrigin } from './ordering';

const MEDIA_PATH = /^\/storage\/v1\/object\/public\/storefront-media\/[0-9a-f]{32}\/[0-9a-f]{64}\.webp$/;

/** A public derivative path made absolute on the configured origin, else null. */
export function mediaUrl(path: string | null, origin: string): string | null {
  if (path === null || !MEDIA_PATH.test(path)) return null;
  return `${origin}${path}`;
}

export interface AdaptedStorefront extends StorefrontResolution {
  readonly tenant: Tenant;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;

/**
 * The next opening instant on the restaurant's wall clock (weekday + HH:MM in
 * its own zone), computed here on the server with the platform's time-zone
 * database so the UI never does date arithmetic. Any input the platform cannot
 * express (unparseable instant, unknown zone) yields null: the UI then renders
 * the bounded "closed" copy instead of a fabricated time.
 */
export function nextOpenParts(iso: string | null, timeZone: string): NextOpenAt | null {
  if (iso === null) return null;
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return null;
  try {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(at);
    const part = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
    const weekday = (WEEKDAYS as readonly string[]).indexOf(part('weekday'));
    const hour = part('hour') === '24' ? '00' : part('hour');
    const minute = part('minute');
    if (weekday < 0 || !/^\d{2}$/.test(hour) || !/^\d{2}$/.test(minute)) return null;
    return { weekday, time: `${hour}:${minute}` };
  } catch {
    return null;
  }
}

export function adaptStorefront(envelope: StorefrontMenuOk | StorefrontMenuV2Ok, origin: string): StorefrontResolution {
  const r = envelope.restaurant;
  const home = 'home_content' in envelope ? envelope.home_content : null;
  const tenant: Tenant = {
    slug: r.slug,
    displayName: r.display_name,
    tagline: r.tagline ?? '',
    city: r.city ?? '',
    address: r.address ?? '',
    phone: r.phone ?? '',
    brand: { primary: r.primary_color, accent: r.accent_color, logo: mediaUrl(r.logo_url, origin) },
    hours: {
      opens: envelope.hours.opens ?? '',
      closes: envelope.hours.closes ?? '',
      nextOpen: envelope.hours.next_open,
      nextOpenAt: nextOpenParts(envelope.hours.next_open, envelope.hours.timezone),
      timezone: envelope.hours.timezone,
    },
    service: {
      state: envelope.service.state,
      pickupEnabled: envelope.service.pickup_enabled,
      deliveryEnabled: false,
      deliveryFromMinor: 0,
      orderingEnabled: liveOrderingEnabled(envelope.service),
    },
    heroImage: mediaUrl(r.hero_url, origin),
    currency: 'ILS',
  };

  // Published groups in display order; keep unsatisfied required groups visible.
  const optionsByGroup = new Map<string, ModifierOption[]>();
  for (const o of envelope.modifier_options) {
    const bucket = optionsByGroup.get(o.modifier_id) ?? [];
    bucket.push({ id: o.id, name: o.name, priceDeltaMinor: o.price_delta_minor });
    optionsByGroup.set(o.modifier_id, bucket);
  }
  const groupsByItem = new Map<string, string[]>();
  const groups: ModifierGroup[] = [];
  for (const m of envelope.modifiers) {
    const options = optionsByGroup.get(m.id) ?? [];
    const single = m.selection_type === 'single';
    // Match the authoritative quote: singles require one distinct option,
    // multiples preserve the published minimum and maximum (including zero).
    // A required group cannot disappear and make an invalid cart seem valid.
    const min = single ? 1 : Math.max(m.is_required ? 1 : 0, m.min_select);
    const max = single ? 1 : m.max_select ?? undefined;
    if (options.length === 0 && min === 0) continue;
    groups.push({
      id: m.id,
      name: m.name,
      required: min > 0,
      single,
      min,
      allowQuantity: m.allow_quantity,
      maxQuantity: Math.min(m.max_quantity ?? 20, 20),
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
      announcement: home?.announcement_text == null ? null : { text: home.announcement_text },
      campaign: { title: home?.hero_headline ?? r.tagline ?? r.display_name, subline: home?.hero_subline ?? '' },
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
  return { source: 'live', view, preset, groups, zones: [], taxRateBp, menuVersion: envelope.menu_version, orderEndpointOrigin: orderEndpointOrigin(origin) };
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
      const envelope = decodeStorefrontMenuV2(await fetchStorefrontMenu(slug, cfg));
      if (!envelope.ok) {
        if (envelope.error === 'not_found') return null;
        throw new Error(`storefront_menu answered ${envelope.error}`);
      }
      if (envelope.restaurant.slug !== slug) throw new Error('storefront_menu answered a different slug');
      return adaptStorefront(envelope, cfg.url);
    },
    staticSlugs(): readonly string[] {
      // Nothing is pre-rendered in live mode: all tenants retain per-URL ISR.
      // The server rechecks live branch admission for every new request even
      // if a previously rendered document still displays checkout after OFF.
      return [];
    },
  };
}
