/**
 * FIXTURE SOURCE — demo data only.
 *
 * Everything here is invented demo content from the approved handoff. There is
 * no network call, no credential, no production record and no write path of any
 * kind. When a live adapter lands this whole module is deleted, and with it the
 * `?fx=` scenario switch, which exists ONLY here (approved decision 12).
 *
 * The demo tenant's colours are DATA. They arrive as arguments to the theme
 * derivation and are never written into a component or a stylesheet.
 */
import type { FixtureTenantSource, ServiceState, Tenant } from './types';

const MAPS_BURGER: Tenant = {
  slug: 'maps-burger',
  displayName: 'Maps Burger',
  tagline: 'برجر أطيب.. لمزاج أفضل',
  city: 'كفر مندا',
  address: 'كفر مندا، الشارع الرئيسي',
  phone: '052-000-0000',
  brand: {
    primary: '#123027',
    accent: '#FF8A2A',
    logo: '/tenant-maps-burger-logo.png',
  },
  hours: { opens: '10:00', closes: '23:00', nextOpen: null, nextOpenAt: null, timezone: 'Asia/Jerusalem' },
  service: {
    state: 'open',
    pickupEnabled: true,
    deliveryEnabled: true,
    deliveryFromMinor: 1000,
    orderingEnabled: true,
  },
  heroImage: '/tenant-maps-burger-hero.webp',
  currency: 'ILS',
};

const FIXTURES: readonly Tenant[] = [MAPS_BURGER];

/**
 * `?fx=` scenario overrides. FIXTURE-LAYER ONLY. Each is a pure transform of
 * demo data; none reaches a network, a store, or anything outside this module.
 */
const SCENARIOS: Readonly<Record<string, (t: Tenant) => Tenant>> = {
  open: (t) => withState(t, 'open'),
  closed: (t) => withState(t, 'closed'),
  paused: (t) => withState(t, 'paused'),
  'pickup-only': (t) => ({
    ...t,
    service: { ...t.service, deliveryEnabled: false },
  }),
  'delivery-only': (t) => ({
    ...t,
    service: { ...t.service, pickupEnabled: false },
  }),
  'no-logo': (t) => ({ ...t, brand: { ...t.brand, logo: null } }),
};

function withState(tenant: Tenant, state: ServiceState): Tenant {
  return { ...tenant, service: { ...tenant.service, state } };
}

export function isFixtureScenario(name: string): boolean {
  return Object.prototype.hasOwnProperty.call(SCENARIOS, name);
}

export function applyScenario(tenant: Tenant, name: string | null): Tenant {
  if (name === null) return tenant;
  const transform = SCENARIOS[name];
  return transform ? transform(tenant) : tenant;
}

export const FIXTURE_SCENARIOS: readonly string[] = Object.keys(SCENARIOS);

export const fixtureSource: FixtureTenantSource = {
  kind: 'fixture',
  getTenant(slug: string): Tenant | null {
    return FIXTURES.find((t) => t.slug === slug) ?? null;
  },
  staticSlugs(): readonly string[] {
    return FIXTURES.map((t) => t.slug);
  },
};
