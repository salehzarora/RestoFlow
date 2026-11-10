/**
 * THE LIVE READ CLIENT - server-only, no SDK.
 *
 * WHAT IT DOES. POSTs `{p_slug}` to `<origin>/rest/v1/rpc/storefront_menu_v8`
 * with the PUBLISHABLE anon key from SERVER environment (never `NEXT_PUBLIC_`),
 * with one shared 5 s deadline, and decodes the response for the requested RPC.
 * During a staggered rollout, an explicitly missing v8 permits v7, then only an
 * explicitly missing v7 permits v6. All reads share the original deadline.
 * Each is the same request a direct PostgREST caller could make
 * with the same key, so the site adds caching only and no authority.
 *
 * WHY THE GLOBAL `fetch` AND NOT A SUPABASE CLIENT. The deployment filter and
 * tests/contract.test.mjs allow exactly three runtime dependencies (react,
 * react-dom, next); a client library would also carry auth/session machinery
 * this read must never have. `fetch` is a platform global on Node 24.
 *
 * SERVER-ONLY, ENFORCED THREE WAYS: (1) the runtime guard below throws if a
 * `window` exists; (2) tests/sf-source-rules.test.mjs allows `fetch(` in THIS
 * file only and forbids any client module from importing it; (3)
 * tests/output/output.test.mjs scans every emitted client chunk for the env
 * names, `rest/v1`, `apikey` and JWT shapes.
 *
 * MISCONFIGURATION NEVER FALLS BACK. A missing origin or key throws; the
 * fixture is never a substitute for a live tenant (packet §4.3 failure contract).
 */

import { decodeStorefrontMenuV6, decodeStorefrontMenuV7, decodeStorefrontMenuV8, type StorefrontMenuV8Envelope } from './decodeContentV1';

const TIMEOUT_MS = 5000;

export interface LiveConfig {
  readonly url: string;
  readonly anonKey: string;
}

/** Read and validate the two server-only variables. Throws when unusable. */
export function liveConfig(env: NodeJS.ProcessEnv = process.env): LiveConfig {
  const url = (env.STOREFRONT_SUPABASE_URL ?? '').trim();
  const anonKey = (env.STOREFRONT_SUPABASE_ANON_KEY ?? '').trim();
  if (!/^https?:\/\/[A-Za-z0-9.-]+(?::[0-9]{1,5})?$/.test(url)) {
    throw new Error('STOREFRONT_SUPABASE_URL must be an origin (https://<project-ref>.supabase.co) with no path');
  }
  if (anonKey.length < 20 || /\s/.test(anonKey)) {
    throw new Error('STOREFRONT_SUPABASE_ANON_KEY is missing or malformed');
  }
  return { url, anonKey };
}

/** The exact request the read makes, exposed so a test can assert its shape. */
export function storefrontMenuRequest(config: LiveConfig, slug: string): { readonly url: string; readonly init: RequestInit } {
  return {
    url: `${config.url}/rest/v1/rpc/storefront_menu_v8`,
    init: {
      method: 'POST',
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${config.anonKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ p_slug: slug }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    },
  };
}

/** Only an exact missing requested RPC permits its legacy read. */
async function missingMenu(response: Response, version: 7 | 8): Promise<boolean> {
  if (response.status !== 404) return false;
  try {
    const body = await response.json();
    return (body?.code === 'PGRST202' &&
      body.message === `Could not find the function public.storefront_menu_v${version}(p_slug) in the schema cache`) ||
      (body?.code === '42883' && body.message === `function public.storefront_menu_v${version}(text) does not exist`);
  } catch {
    return false;
  }
}

/**
 * Fetch and decode the envelope. Throws on a transport failure, unavailable read or
 * non-JSON body - the page then throws too, which is the designed outcome:
 * ISR keeps the last good document for a cached URL and a never-cached URL
 * gets the framework error page, never a fabricated menu.
 */
export async function fetchStorefrontMenu(slug: string, config?: LiveConfig): Promise<StorefrontMenuV8Envelope> {
  if (typeof window !== 'undefined') {
    throw new Error('storefront live client is server-only');
  }
  const cfg = config ?? liveConfig();
  const { url, init } = storefrontMenuRequest(cfg, slug);
  const response = await fetch(url, init);
  if (response.ok) return decodeStorefrontMenuV8(await response.json());
  if (await missingMenu(response, 8)) {
    // All reads share the original deadline, slug and publishable credentials.
    const v7 = await fetch(`${cfg.url}/rest/v1/rpc/storefront_menu_v7`, init);
    if (v7.ok) return decodeStorefrontMenuV7(await v7.json());
    if (await missingMenu(v7, 7)) {
      const v6 = await fetch(`${cfg.url}/rest/v1/rpc/storefront_menu_v6`, init);
      if (v6.ok) return decodeStorefrontMenuV6(await v6.json());
      throw new Error(`storefront_menu: HTTP ${v6.status}`);
    }
    throw new Error(`storefront_menu: HTTP ${v7.status}`);
  }
  throw new Error(`storefront_menu: HTTP ${response.status}`);
}
