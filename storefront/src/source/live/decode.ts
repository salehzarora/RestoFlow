/**
 * THE ENVELOPE DECODER - the storefront's trust boundary for what
 * `public.storefront_menu` answers.
 *
 * STRICT BY DESIGN. Every key set is checked for EQUALITY with the contract
 * (docs/API_CONTRACT.md §4.42): an extra key, a missing key, a wrong type or a
 * non-integer amount REJECTS the whole envelope. A rejected envelope makes the
 * render throw (never a fabricated menu, never the fixture) - the packet's
 * failure contract, T-S8. Money is validated as SAFE INTEGERS (D-007) before
 * any arithmetic can see it.
 *
 * Pure: no I/O, no env, no React. Server-only by use.
 */

export type ServiceStateWire = 'open' | 'closed' | 'paused';

export interface WireRestaurant {
  readonly slug: string;
  readonly display_name: string;
  readonly tagline: string | null;
  readonly city: string | null;
  readonly address: string | null;
  readonly phone: string | null;
  readonly primary_color: string;
  readonly accent_color: string;
  readonly logo_url: string | null;
  readonly hero_url: string | null;
  readonly currency_code: string;
  readonly locale_default: 'ar' | 'he' | 'en';
  readonly visual_preset: 'dark' | 'light';
  readonly card_mode: 'list' | 'grid';
  readonly motion: 'calm' | 'full' | 'lively';
}

export interface WireHours {
  readonly timezone: string;
  readonly opens: string | null;
  readonly closes: string | null;
  readonly open_now: boolean;
  readonly next_open: string | null;
}

export interface WireService {
  readonly state: ServiceStateWire;
  readonly ordering_enabled: boolean;
  readonly pickup_enabled: boolean;
  readonly delivery_enabled: boolean;
}

export interface WireTax {
  readonly enabled: boolean;
  readonly rate_bp: number;
  readonly mode: 'exclusive' | 'inclusive';
}

export interface WireCategory {
  readonly id: string;
  readonly name: string;
  readonly display_order: number;
  readonly icon_key: string | null;
}

export interface WireItem {
  readonly id: string;
  readonly category_id: string;
  readonly name: string;
  readonly description: string;
  readonly base_price_minor: number;
  readonly display_order: number;
  readonly tags: readonly string[];
  readonly image_url: string | null;
  readonly availability: 'available' | 'unavailable';
}

export interface WireModifier {
  readonly id: string;
  readonly item_id: string;
  readonly name: string;
  readonly selection_type: 'single' | 'multiple';
  readonly min_select: number;
  readonly max_select: number | null;
  readonly is_required: boolean;
  readonly display_order: number;
}

export interface WireOption {
  readonly id: string;
  readonly modifier_id: string;
  readonly name: string;
  readonly price_delta_minor: number;
  readonly display_order: number;
}

export interface StorefrontMenuOk {
  readonly ok: true;
  readonly entity: 'storefront_menu';
  readonly menu_version: string;
  readonly server_ts: string;
  readonly restaurant: WireRestaurant;
  readonly hours: WireHours;
  readonly service: WireService;
  readonly tax: WireTax;
  readonly categories: readonly WireCategory[];
  readonly items: readonly WireItem[];
  readonly modifiers: readonly WireModifier[];
  readonly modifier_options: readonly WireOption[];
}

export interface StorefrontMenuFailure {
  readonly ok: false;
  readonly error: string;
  readonly entity: 'storefront_menu';
}

export type StorefrontMenuEnvelope = StorefrontMenuOk | StorefrontMenuFailure;

export class EnvelopeError extends Error {
  constructor(message: string) {
    super(`storefront_menu envelope rejected: ${message}`);
    this.name = 'EnvelopeError';
  }
}

const fail = (message: string): never => {
  throw new EnvelopeError(message);
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** The object's own keys must EQUAL `keys` (order-insensitive). */
function exactKeys(value: unknown, keys: readonly string[], where: string): Record<string, unknown> {
  if (!isRecord(value)) return fail(`${where}: not an object`);
  const own = Object.keys(value).sort();
  const want = [...keys].sort();
  if (own.length !== want.length || own.some((k, i) => k !== want[i])) {
    return fail(`${where}: keys [${own.join(',')}] != [${want.join(',')}]`);
  }
  return value;
}

// Caps are counted in CODE POINTS, the unit Postgres `left()` / `length()`
// truncate by on the server; `.length` counts UTF-16 units, so a served text
// at the cap that contains an astral character (an emoji) is one unit longer
// and must still decode. The cheap `.length` test short-circuits the common
// case; only a string over the cap in units is spread into code points.
const str = (v: unknown, where: string, max = 4096): string => {
  if (typeof v !== 'string') return fail(`${where}: not a string`);
  if (v.length > max && [...v].length > max) return fail(`${where}: longer than ${max}`);
  return v;
};
const strOrNull = (v: unknown, where: string, max = 4096): string | null => (v === null ? null : str(v, where, max));
const bool = (v: unknown, where: string): boolean => (typeof v === 'boolean' ? v : fail(`${where}: not a boolean`));
const int = (v: unknown, where: string, min: number, max = Number.MAX_SAFE_INTEGER): number => {
  if (typeof v !== 'number' || !Number.isSafeInteger(v)) return fail(`${where}: not a safe integer`);
  if (v < min || v > max) return fail(`${where}: ${v} outside ${min}..${max}`);
  return v;
};
const oneOf = <T extends string>(v: unknown, allowed: readonly T[], where: string): T => {
  if (typeof v !== 'string' || !(allowed as readonly string[]).includes(v)) return fail(`${where}: not one of ${allowed.join('|')}`);
  return v as T;
};
const list = <T>(v: unknown, where: string, max: number, each: (item: unknown, at: string) => T): readonly T[] => {
  if (!Array.isArray(v)) return fail(`${where}: not an array`);
  if (v.length > max) return fail(`${where}: more than ${max} entries`);
  return v.map((item, i) => each(item, `${where}[${i}]`));
};

const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const id = (v: unknown, where: string): string => {
  const s = str(v, where, 36);
  return ID.test(s) ? s : fail(`${where}: not a uuid`);
};
const HEX = /^#[0-9A-Fa-f]{6}$/;
const HHMM = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const TAGS = ['spicy', 'vegetarian', 'popular', 'new'] as const;

const RESTAURANT_KEYS = ['slug', 'display_name', 'tagline', 'city', 'address', 'phone', 'primary_color', 'accent_color',
  'logo_url', 'hero_url', 'currency_code', 'locale_default', 'visual_preset', 'card_mode', 'motion'] as const;
const HOURS_KEYS = ['timezone', 'opens', 'closes', 'open_now', 'next_open'] as const;
const SERVICE_KEYS = ['state', 'ordering_enabled', 'pickup_enabled', 'delivery_enabled'] as const;
const TAX_KEYS = ['enabled', 'rate_bp', 'mode'] as const;
const CATEGORY_KEYS = ['id', 'name', 'display_order', 'icon_key'] as const;
const ITEM_KEYS = ['id', 'category_id', 'name', 'description', 'base_price_minor', 'display_order', 'tags', 'image_url', 'availability'] as const;
const MODIFIER_KEYS = ['id', 'item_id', 'name', 'selection_type', 'min_select', 'max_select', 'is_required', 'display_order'] as const;
const OPTION_KEYS = ['id', 'modifier_id', 'name', 'price_delta_minor', 'display_order'] as const;
const OK_KEYS = ['ok', 'entity', 'menu_version', 'server_ts', 'restaurant', 'hours', 'service', 'tax',
  'categories', 'items', 'modifiers', 'modifier_options'] as const;
const FAILURE_KEYS = ['ok', 'error', 'entity'] as const;

/** The RPC's own caps, mirrored: anything above them is not a menu we render. */
export const CAPS = Object.freeze({ categories: 100, items: 500, modifiers: 2000, options: 8000 });

/**
 * Decode an unknown JSON value into the typed envelope, or throw
 * `EnvelopeError`. A `{ok:false}` envelope decodes successfully - what to do
 * with it (404 for `not_found`, throw for anything else) is the adapter's rule.
 */
export function decodeStorefrontMenu(raw: unknown): StorefrontMenuEnvelope {
  if (!isRecord(raw)) return fail('not an object');
  if (raw.ok === false) {
    const f = exactKeys(raw, FAILURE_KEYS, 'failure');
    return { ok: false, error: str(f.error, 'failure.error', 64), entity: oneOf(f.entity, ['storefront_menu'], 'failure.entity') };
  }
  const e = exactKeys(raw, OK_KEYS, 'envelope');
  if (e.ok !== true) return fail('ok is not true');
  const r = exactKeys(e.restaurant, RESTAURANT_KEYS, 'restaurant');
  const h = exactKeys(e.hours, HOURS_KEYS, 'hours');
  const s = exactKeys(e.service, SERVICE_KEYS, 'service');
  const t = exactKeys(e.tax, TAX_KEYS, 'tax');

  const restaurant: WireRestaurant = {
    slug: str(r.slug, 'restaurant.slug', 64),
    display_name: str(r.display_name, 'restaurant.display_name', 60),
    tagline: strOrNull(r.tagline, 'restaurant.tagline', 90),
    city: strOrNull(r.city, 'restaurant.city', 60),
    address: strOrNull(r.address, 'restaurant.address', 80),
    phone: strOrNull(r.phone, 'restaurant.phone', 32),
    primary_color: HEX.test(str(r.primary_color, 'restaurant.primary_color', 7)) ? (r.primary_color as string) : fail('restaurant.primary_color: not hex'),
    accent_color: HEX.test(str(r.accent_color, 'restaurant.accent_color', 7)) ? (r.accent_color as string) : fail('restaurant.accent_color: not hex'),
    logo_url: strOrNull(r.logo_url, 'restaurant.logo_url', 256),
    hero_url: strOrNull(r.hero_url, 'restaurant.hero_url', 256),
    currency_code: oneOf(r.currency_code, ['ILS'], 'restaurant.currency_code'),
    locale_default: oneOf(r.locale_default, ['ar', 'he', 'en'], 'restaurant.locale_default'),
    visual_preset: oneOf(r.visual_preset, ['dark', 'light'], 'restaurant.visual_preset'),
    card_mode: oneOf(r.card_mode, ['list', 'grid'], 'restaurant.card_mode'),
    motion: oneOf(r.motion, ['calm', 'full', 'lively'], 'restaurant.motion'),
  };
  const opens = strOrNull(h.opens, 'hours.opens', 5);
  const closes = strOrNull(h.closes, 'hours.closes', 5);
  if (opens !== null && !HHMM.test(opens)) fail('hours.opens: not HH:MM');
  if (closes !== null && !HHMM.test(closes)) fail('hours.closes: not HH:MM');
  const hours: WireHours = {
    timezone: str(h.timezone, 'hours.timezone', 64),
    opens,
    closes,
    open_now: bool(h.open_now, 'hours.open_now'),
    next_open: strOrNull(h.next_open, 'hours.next_open', 64),
  };
  const service: WireService = {
    state: oneOf(s.state, ['open', 'closed', 'paused'], 'service.state'),
    ordering_enabled: bool(s.ordering_enabled, 'service.ordering_enabled'),
    pickup_enabled: bool(s.pickup_enabled, 'service.pickup_enabled'),
    delivery_enabled: bool(s.delivery_enabled, 'service.delivery_enabled'),
  };
  // The browse-only contract is asserted, not assumed: a server that ever
  // answered ordering_enabled=true would not be the contract this build ships.
  if (service.ordering_enabled || service.delivery_enabled) fail('service: ordering/delivery must be off in this slice');
  const tax: WireTax = {
    enabled: bool(t.enabled, 'tax.enabled'),
    rate_bp: int(t.rate_bp, 'tax.rate_bp', 0, 10000),
    mode: oneOf(t.mode, ['exclusive', 'inclusive'], 'tax.mode'),
  };
  if (tax.enabled && tax.mode !== 'exclusive') fail('tax: inclusive mode is not served in this slice');

  const categories = list(e.categories, 'categories', CAPS.categories, (item, at) => {
    const c = exactKeys(item, CATEGORY_KEYS, at);
    return {
      id: id(c.id, `${at}.id`),
      name: str(c.name, `${at}.name`, 80),
      display_order: int(c.display_order, `${at}.display_order`, -2147483648, 2147483647),
      icon_key: strOrNull(c.icon_key, `${at}.icon_key`, 40),
    } satisfies WireCategory;
  });
  const items = list(e.items, 'items', CAPS.items, (item, at) => {
    const i = exactKeys(item, ITEM_KEYS, at);
    return {
      id: id(i.id, `${at}.id`),
      category_id: id(i.category_id, `${at}.category_id`),
      name: str(i.name, `${at}.name`, 120),
      description: str(i.description, `${at}.description`, 600),
      base_price_minor: int(i.base_price_minor, `${at}.base_price_minor`, 0),
      display_order: int(i.display_order, `${at}.display_order`, -2147483648, 2147483647),
      tags: list(i.tags, `${at}.tags`, 8, (tag, tat) => oneOf(tag, TAGS, tat)),
      image_url: strOrNull(i.image_url, `${at}.image_url`, 256),
      availability: oneOf(i.availability, ['available', 'unavailable'], `${at}.availability`),
    } satisfies WireItem;
  });
  const modifiers = list(e.modifiers, 'modifiers', CAPS.modifiers, (item, at) => {
    const m = exactKeys(item, MODIFIER_KEYS, at);
    return {
      id: id(m.id, `${at}.id`),
      item_id: id(m.item_id, `${at}.item_id`),
      name: str(m.name, `${at}.name`, 80),
      selection_type: oneOf(m.selection_type, ['single', 'multiple'], `${at}.selection_type`),
      // The storage domain (public.modifiers CHECKs: min_select >= 0; max_select
      // null or >= 0; int4). Anything a manager can legally store must decode;
      // the min/max RELATION is bounded by the adapter, not refused here.
      min_select: int(m.min_select, `${at}.min_select`, 0, 2147483647),
      max_select: m.max_select === null ? null : int(m.max_select, `${at}.max_select`, 0, 2147483647),
      is_required: bool(m.is_required, `${at}.is_required`),
      display_order: int(m.display_order, `${at}.display_order`, -2147483648, 2147483647),
    } satisfies WireModifier;
  });
  const modifier_options = list(e.modifier_options, 'modifier_options', CAPS.options, (item, at) => {
    const o = exactKeys(item, OPTION_KEYS, at);
    return {
      id: id(o.id, `${at}.id`),
      modifier_id: id(o.modifier_id, `${at}.modifier_id`),
      name: str(o.name, `${at}.name`, 80),
      // The RPC excludes negative deltas; a negative one here is a contract break.
      price_delta_minor: int(o.price_delta_minor, `${at}.price_delta_minor`, 0),
      display_order: int(o.display_order, `${at}.display_order`, -2147483648, 2147483647),
    } satisfies WireOption;
  });

  return {
    ok: true,
    entity: oneOf(e.entity, ['storefront_menu'], 'entity'),
    menu_version: (() => {
      const v = str(e.menu_version, 'menu_version', 64);
      return /^[0-9]+\.[0-9]+$/.test(v) ? v : fail('menu_version: not <version>.<epoch>');
    })(),
    server_ts: str(e.server_ts, 'server_ts', 64),
    restaurant,
    hours,
    service,
    tax,
    categories,
    items,
    modifiers,
    modifier_options,
  };
}
