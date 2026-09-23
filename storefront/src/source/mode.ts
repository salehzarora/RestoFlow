/**
 * THE SOURCE-MODE RULE (STOREFRONT-READ-001, corrected after independent
 * review): one pure module, imported by the server-only switch
 * (storefront.ts) and by the request-route fixture (request-fixture.ts), so
 * both apply the SAME rule. `process.env` is read INSIDE the functions only,
 * never at module scope, and the name is not a `NEXT_PUBLIC_` one.
 *
 *   STOREFRONT_SOURCE = 'fixture'  -> fixture (local fixture / evidence work)
 *   STOREFRONT_SOURCE = 'live'     -> live (published storefronts, READ-001)
 *   absent or empty, NOT a provider context -> fixture (local developer default)
 *   absent, empty, whitespace-only, misspelled or any other value in a
 *   PROVIDER context -> throw the misconfiguration error (FAIL CLOSED)
 *   any other value outside a provider context -> throw (as before)
 *
 * A PROVIDER context is a Vercel build or runtime: Vercel sets `VERCEL=1`
 * (and `VERCEL_ENV`) for both, so a provider build must state its source
 * explicitly and a public deployment can never quietly serve the demo tenant.
 * NODE_ENV is deliberately NOT consulted: it is `production` for every
 * `next build`, local ones included, and cannot tell preview from production.
 * There is no live -> fixture fallback of any kind on fetch, decode or
 * configuration failure; those throw in src/source/live.
 */
export type SourceMode = 'fixture' | 'live';

/** True inside a Vercel build or runtime (VERCEL=1 / VERCEL_ENV set). */
export function isProviderContext(env: NodeJS.ProcessEnv = process.env): boolean {
  const set = (value: string | undefined) => value !== undefined && value !== '';
  return set(env.VERCEL) || set(env.VERCEL_ENV);
}

export function sourceMode(env: NodeJS.ProcessEnv = process.env): SourceMode {
  const value = env.STOREFRONT_SOURCE;
  if (value === 'fixture') return 'fixture';
  if (value === 'live') return 'live';
  const provider = isProviderContext(env);
  if (!provider && (value === undefined || value === '')) return 'fixture';
  throw new Error(
    `STOREFRONT_SOURCE must be exactly "fixture" or "live"${provider ? ' in a provider (VERCEL) build or runtime' : ''}, got ${JSON.stringify(value)}`,
  );
}

export function isLiveMode(env: NodeJS.ProcessEnv = process.env): boolean {
  return sourceMode(env) === 'live';
}
