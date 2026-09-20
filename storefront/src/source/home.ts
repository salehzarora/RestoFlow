/**
 * HOME VIEW ASSEMBLY — fixture layer only.
 *
 * Turns the demo tenant plus the demo menu into the `HomeView` the presentation
 * components read. Every `?fx=` scenario lives here and nowhere else (approved
 * decision 14), so when a live adapter replaces this module the scenario switch
 * disappears with it.
 *
 * Nothing here reaches a network, a store, or any production record.
 */
import type {
  Preset,
  CardMode,
  CartLineView,
  CartView,
  HomeModules,
  HomeView,
  MenuItem,
  MotionMode,
  Minor,
  Tenant,
} from './types';
import { CATEGORIES, HOME_MODULES, MENU_ITEMS, TAX_RATE } from './menu-fixture';
import { applyScenarioTenant, findScenario, SCENARIO_SLUGS } from './scenarios';
import { fixtureSource } from './fixtures';

/**
 * A seeded, PRESENTATIONAL cart. It exists so the dock and the wide aside can
 * be rendered and reviewed against the approved screenshots. It is a constant:
 * nothing in Phase B can add to it, change it or persist it.
 */
const SEEDED_LINES: readonly { lineId: string; itemId: string; quantity: number; options: string }[] = [
  { lineId: 'l1', itemId: '1', quantity: 1, options: 'بريوش • جبنة إضافية • ✕ بصل' },
  { lineId: 'l2', itemId: '7', quantity: 2, options: 'مايونيز ثوم' },
];

function buildCart(items: readonly MenuItem[], lines: typeof SEEDED_LINES): CartView {
  const views: CartLineView[] = [];
  let subtotal: Minor = 0;
  for (const line of lines) {
    const item = items.find((i) => i.id === line.itemId);
    if (item === undefined) continue;
    const lineTotal = item.priceMinor * line.quantity;
    subtotal += lineTotal;
    views.push({
      lineId: line.lineId,
      name: item.name,
      image: item.image,
      quantity: line.quantity,
      lineTotalMinor: lineTotal,
      optionSummary: line.options,
    });
  }
  // Integer minor units throughout; rounding happens once, here.
  const tax: Minor = Math.round(subtotal * TAX_RATE);
  return {
    lines: views,
    itemCount: views.reduce((n, l) => n + l.quantity, 0),
    subtotalMinor: subtotal,
    taxMinor: tax,
    totalMinor: subtotal + tax,
    taxRate: TAX_RATE,
  };
}

export interface HomeOptions {
  readonly cardMode?: CardMode;
  readonly motion?: MotionMode;
  readonly modules?: Partial<HomeModules>;
  readonly items?: readonly MenuItem[];
  readonly cart?: readonly (typeof SEEDED_LINES)[number][];
}

export function buildHome(tenant: Tenant, options: HomeOptions = {}): HomeView {
  const items = options.items ?? MENU_ITEMS;
  const modules: HomeModules = { ...HOME_MODULES, ...options.modules };
  // A menu with no items suppresses every optional module, per the design's
  // emptyMenu state: there is nothing for them to decorate.
  const empty = items.length === 0;
  return {
    tenant,
    modules: empty
      ? { ...modules, announcement: null, promo: null, story: null, popular: { enabled: false, ready: false } }
      : modules,
    categories: empty ? [] : CATEGORIES,
    items,
    cardMode: options.cardMode ?? 'list',
    motion: options.motion ?? 'full',
    cart: buildCart(items, options.cart ?? SEEDED_LINES),
  };
}

/** Home-only `?fx=` scenarios. Pure transforms of demo data, fixture-layer only. */
const HOME_SCENARIOS: Readonly<Record<string, HomeOptions>> = {
  grid: { cardMode: 'grid' },
  list: { cardMode: 'list' },
  calm: { motion: 'calm' },
  lively: { motion: 'lively' },
  'modules-off': {
    modules: { announcement: null, promo: null, story: null, popular: { enabled: false, ready: false } },
  },
  'popular-off': { modules: { popular: { enabled: true, ready: false } } },
  'empty-menu': { items: [] },
  'cart-empty': { cart: [] },
};

export function isHomeScenario(name: string): boolean {
  return Object.prototype.hasOwnProperty.call(HOME_SCENARIOS, name);
}

export function homeOptionsFor(names: readonly string[]): HomeOptions {
  let merged: HomeOptions = {};
  for (const name of names) {
    const scenario = HOME_SCENARIOS[name];
    if (scenario === undefined) continue;
    merged = {
      ...merged,
      ...scenario,
      modules: { ...merged.modules, ...scenario.modules },
    };
  }
  return merged;
}

export const HOME_SCENARIO_NAMES: readonly string[] = Object.keys(HOME_SCENARIOS);

/**
 * Resolve a slug straight to everything a route needs to render home.
 *
 * Routes call ONLY this: the scenario machinery stays inside the fixture layer,
 * so no page file imports it and no page file knows demo scenarios exist. When
 * a live adapter replaces this module, the route code is unchanged.
 */
export interface HomeResolution {
  readonly view: HomeView;
  readonly preset: Preset;
}

export function resolveHome(slug: string): HomeResolution | null {
  const scenario = findScenario(slug);
  const base = fixtureSource.getTenant(scenario === null ? slug : 'maps-burger');
  if (base === null) return null;
  const tenant = scenario === null ? base : applyScenarioTenant(base, scenario);
  return {
    view: buildHome(tenant, scenario === null ? {} : scenario.options),
    preset: scenario === null ? 'dark' : scenario.preset,
  };
}

/** Slugs the home route pre-renders under the default locale root. */
export function homeSlugs(): readonly string[] {
  return [...fixtureSource.staticSlugs(), ...SCENARIO_SLUGS];
}
