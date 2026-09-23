/**
 * THE SOURCE SWITCH - the one place that decides fixture vs live.
 *
 * SERVER-ONLY. Route files (server components) call `getStorefront` and
 * `storefrontSlugs`; nothing under src/ui may import this module, and no
 * client module may (tests/sf-source-rules.test.mjs). The mode is read from
 * `STOREFRONT_SOURCE` INSIDE the functions, never at module scope, and the name
 * is deliberately not a `NEXT_PUBLIC_` one, so it can never reach a client
 * bundle (the same rule home.ts applies to SF_EVIDENCE_ROUTES).
 *
 * fixture: the UI-001 tenant and its `?fx=` scenarios, unchanged; the demo
 *   scenario SLUGS stay evidence-build only (SF_EVIDENCE_ROUTES=1). It is the
 *   local developer default ONLY outside a provider context.
 * live: published storefronts through public.storefront_menu; the fixture
 *   tenant, the scenario slugs and the request route do not exist.
 *
 * The rule itself lives in ./mode.ts (fail closed in a provider context): a
 * Vercel build or runtime whose STOREFRONT_SOURCE is absent, empty, whitespace
 * or misspelled throws at build time (generateStaticParams) and at request
 * time - it never quietly serves the demo.
 */
import type { StorefrontResolution, StorefrontSource } from './types';
import { evidenceRoutes, homeSlugs, resolveHome } from './home';
import { MENU_VERSION, TAX_RATE_BP } from './menu-fixture';
import { MODIFIER_GROUPS } from './modifier-fixture';
import { findScenario } from './scenarios';
import { DELIVERY_ZONES } from './zones';
import { liveStorefrontSource } from './live/adapter';
import { isLiveMode, isProviderContext, sourceMode, type SourceMode } from './mode';

export { isLiveMode, isProviderContext, sourceMode };
export type { SourceMode };

/** The fixture wrapped in the async seam; the scenario switch stays inside home.ts. */
export const fixtureStorefrontSource: StorefrontSource = {
  kind: 'fixture',
  async getStorefront(slug: string): Promise<StorefrontResolution | null> {
    // A demo scenario slug is an EVIDENCE route: served only by a local
    // evidence build, as the static export emitted it. Elsewhere it is unknown.
    if (findScenario(slug) !== null && !evidenceRoutes()) return null;
    const resolved = resolveHome(slug);
    if (resolved === null) return null;
    return {
      source: 'fixture',
      view: resolved.view,
      preset: resolved.preset,
      groups: MODIFIER_GROUPS,
      zones: DELIVERY_ZONES,
      taxRateBp: TAX_RATE_BP,
      menuVersion: MENU_VERSION,
    };
  },
  staticSlugs(): readonly string[] {
    return homeSlugs();
  },
};

export function storefrontSource(env: NodeJS.ProcessEnv = process.env): StorefrontSource {
  return isLiveMode(env) ? liveStorefrontSource() : fixtureStorefrontSource;
}

/** What a route renders for a slug, or null for the Unknown document. */
export function getStorefront(slug: string): Promise<StorefrontResolution | null> {
  return storefrontSource().getStorefront(slug);
}

/** The slugs a route pre-renders at build time: the fixture's in fixture mode, none live. */
export function storefrontSlugs(): readonly string[] {
  return storefrontSource().staticSlugs();
}
