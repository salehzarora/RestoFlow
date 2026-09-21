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
 * Every state now gets a route. While these were SHIPPED documents each cost
 * roughly 170 KB of a hard 4 MiB ceiling, so `popular: ready=false` and
 * `motion: lively` were proven by unit assertions instead. Gating them behind
 * SF_EVIDENCE_ROUTES made evidence routes free, so both are now proven in a
 * real rendered document - which is what finally exercises `sfFloat`, the one
 * keyframe reachable only under the lively preset.
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
    slug: 'demo-lively',
    proves: 'H04 lively motion - the popular-card float, the only lively-only effect',
    preset: 'dark',
    options: trimmed({ motion: 'lively' as MotionMode }),
  },
  {
    slug: 'demo-popular-off',
    proves: 'H05 POPULAR_READY=false - kitchen picks, no rank claim, badges kept',
    preset: 'dark',
    // Deliberately NOT trimmed: the unranked state must be proven across the
    // FULL canonical popular set, including the items that carry their own
    // new/deal badge, so badge coexistence is visible in both ready states.
    // Evidence-build only, so the full menu costs the shipped export nothing.
    options: { modules: { popular: { enabled: true, ready: false } } },
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
