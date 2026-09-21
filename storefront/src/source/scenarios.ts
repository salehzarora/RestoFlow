/**
 * DEMO SCENARIO SLUGS — fixture layer only.
 *
 * Each slug renders the home surface in one approved presentation state so it
 * can be screenshotted from the real built output rather than from a mocked
 * DOM. They are ordinary static routes - so no client-side `?fx=` reader is
 * needed and the default route stays fully server-rendered - but they are
 * EVIDENCE-BUILD ONLY: `homeSlugs()` emits them solely when a local build sets
 * SF_EVIDENCE_ROUTES=1. The SHIPPED export carries `maps-burger` and nothing
 * else, and tests/output/output.test.mjs fails if a demo slug creeps back in.
 *
 * Scenario slugs deliberately carry a TRIMMED menu (the first category,
 * five items): the states they prove are STRUCTURAL, and repeating the full
 * 20-item menu in every scenario costs more build time than the evidence is
 * worth. The canonical `maps-burger` route keeps the full menu.
 *
 * NOT every state gets a route. Each scenario document costs roughly 170 KB of
 * the 4 MiB output budget, and the budget is a hard ceiling this phase may not
 * raise. So the slugs below cover the states that REQUIRE a screenshot, while
 * `popular: ready=false` and `motion: lively` - which the packet classifies as
 * unscreenshotted state evidence - are proven by tests/sf-home.test.mjs against
 * the real `buildHome` output and the real stylesheet instead.
 *
 * This entire module disappears with the fixtures when a live adapter lands.
 */
import type { CardMode, MotionMode, Preset, ServiceState, Tenant } from './types';
import type { HomeOptions } from './home';
import { CATEGORIES, MENU_ITEMS } from './menu-fixture';

const TRIMMED_CATEGORIES = CATEGORIES.slice(0, 1).map((c) => c.id);
const TRIMMED = MENU_ITEMS.filter((i) => TRIMMED_CATEGORIES.includes(i.categoryId));

export interface Scenario {
  readonly slug: string;
  /** What this scenario exists to evidence. */
  readonly proves: string;
  readonly preset: Preset;
  readonly service?: Partial<{
    state: ServiceState;
    pickupEnabled: boolean;
    deliveryEnabled: boolean;
  }>;
  readonly options: HomeOptions;
}

const trimmed = (extra: HomeOptions = {}): HomeOptions => ({ items: TRIMMED, ...extra });

export const SCENARIOS: readonly Scenario[] = [
  {
    slug: 'demo-grid',
    proves: 'G06 grid card mode',
    preset: 'dark',
    options: trimmed({ cardMode: 'grid' as CardMode }),
  },
  {
    slug: 'demo-quiet',
    proves: 'G07 every optional module off',
    preset: 'dark',
    options: trimmed({
      modules: { announcement: null, promo: null, story: null, popular: { enabled: false, ready: false } },
    }),
  },
  {
    slug: 'demo-calm',
    proves: 'G08 calm motion - no sheen or Ken Burns; the motif stays, undrawn',
    preset: 'dark',
    options: trimmed({ motion: 'calm' as MotionMode }),
  },
  {
    slug: 'demo-closed',
    proves: 'G09 closed, and H03 pickup unavailable',
    preset: 'dark',
    service: { state: 'closed', pickupEnabled: false },
    options: trimmed(),
  },
  {
    slug: 'demo-paused',
    proves: 'G10 paused, and H03 delivery unavailable',
    preset: 'dark',
    service: { state: 'paused', deliveryEnabled: false },
    options: trimmed(),
  },
  {
    slug: 'demo-empty',
    proves: 'H02 emptyMenu',
    preset: 'dark',
    options: { items: [] },
  },
  {
    slug: 'demo-popular-off',
    proves: 'H05 POPULAR_READY=false - kitchen picks, no rank claim',
    preset: 'dark',
    options: trimmed({ modules: { popular: { enabled: true, ready: false } } }),
  },
  {
    slug: 'demo-light',
    proves: 'G04/G05 light preset, and H06 light x grid',
    preset: 'light',
    options: trimmed({ cardMode: 'grid' as CardMode }),
  },
];

export function findScenario(slug: string): Scenario | null {
  return SCENARIOS.find((s) => s.slug === slug) ?? null;
}

/** Apply a scenario's service overrides to the demo tenant. */
export function applyScenarioTenant(tenant: Tenant, scenario: Scenario): Tenant {
  if (scenario.service === undefined) return tenant;
  return { ...tenant, service: { ...tenant.service, ...scenario.service } };
}

export const SCENARIO_SLUGS: readonly string[] = SCENARIOS.map((s) => s.slug);
