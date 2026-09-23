// STOREFRONT-READ-001 - the LIVE read path in a real browser, against a real
// `next start` of a LIVE-MODE build (STOREFRONT_SOURCE=live at build time - the
// spec refuses a fixture build). Two sources of truth, one contract:
//
//   STUB   an in-process HTTP server that answers `/rest/v1/rpc/storefront_menu`
//          with the SAME synthetic envelope the unit tests use
//          (tests/support/envelope.mjs). Always runs. Proves the served
//          contract without a database: cache segregation and the ISR header
//          (T-S7), the failure contract (T-S8: not_found -> 404 document,
//          transport failure -> error page, never the fixture), browse-only
//          refusals (T-S9), two tenants x four locale roots with no fixture
//          leakage (T-S10), a hostile display name rendered as text (T-S5),
//          the freshness window (a change is visible after revalidate).
//   REAL   the same assertions against the LOCAL Docker Supabase through the
//          loopback API shim (scripts/local-api-shim.mjs), seeded with the
//          synthetic tenants (scripts/local-storefront-seed.sql). Runs only
//          when STOREFRONT_LOCAL_API_URL and STOREFRONT_LOCAL_ANON_KEY are set;
//          otherwise it is SKIPPED and reported, never silently passed.
//
// Every `next start` on one .next directory SHARES its on-disk ISR cache
// (.next/server/app/<root>/s/<slug>/*.html|.rsc|.meta): a document rendered by
// the STUB server would be served STALE by the REAL block's server (and by the
// next run), so the two blocks use DISJOINT slugs (sf-stub-* vs the seeded
// sf-synth-*) and each block purges the tenant/request cache entries before it
// starts its server. Only cache entries go; the build's [slug] / [ref] output stays.
//
// Everything typed here is synthetic. Nothing leaves the machine.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { createServer, type Server } from 'node:http';
import { existsSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { NOT_FOUND_ENVELOPE, SYNTH_IDS, SYNTH_MEDIA_PATH, syntheticEnvelope } from '../support/envelope.mjs';

const STOREFRONT = path.resolve(process.cwd());
const AR = JSON.parse(readFileSync(path.join(STOREFRONT, 'messages/storefront.ar.json'), 'utf8'));
const EN = JSON.parse(readFileSync(path.join(STOREFRONT, 'messages/storefront.en.json'), 'utf8'));
const HE = JSON.parse(readFileSync(path.join(STOREFRONT, 'messages/storefront.he.json'), 'utf8'));
const FIXTURE_MARKERS = ['maps-burger', 'Maps Burger', 'tenant-maps-burger', AR.demoNotice, EN.demoNotice, 'DEMO-7K4XM2D9P3', '?fx=', 'كفر مندا'];
const SYNTH_KEY = 'sb_publishable_SYNTHETIC_local_only_key_000000';
const ROOTS = [
  { prefix: '', lang: 'ar', dir: 'rtl', m: AR },
  { prefix: '/ar', lang: 'ar', dir: 'rtl', m: AR },
  { prefix: '/en', lang: 'en', dir: 'ltr', m: EN },
  { prefix: '/he', lang: 'he', dir: 'rtl', m: HE },
] as const;

/** Refuse a fixture-mode build: its prerendered `maps-burger` documents would be served from the cache. */
function assertLiveBuild() {
  const manifest = path.join(STOREFRONT, '.next', 'prerender-manifest.json');
  expect(existsSync(manifest), 'run `STOREFRONT_SOURCE=live npm run build` first').toBe(true);
  const routes = Object.keys(JSON.parse(readFileSync(manifest, 'utf8')).routes ?? {});
  expect(routes.filter((r) => r.includes('/s/') || r.includes('/r/')), 'the build must be a LIVE build (no prerendered tenant or request route)').toEqual([]);
}

/** Remove every cached tenant / request document so this block's server renders from ITS source (see the header). */
function purgeIsrCache() {
  const app = path.join(STOREFRONT, '.next', 'server', 'app');
  for (const root of ['', 'ar', 'en', 'he']) {
    for (const segment of ['s', 'r']) {
      const dir = path.join(app, root, segment);
      if (!existsSync(dir)) continue;
      for (const entry of readdirSync(dir)) {
        if (entry.startsWith('[')) continue; // the build output of the dynamic segment, never a cache entry
        rmSync(path.join(dir, entry), { recursive: true, force: true });
      }
    }
  }
}

function startNext(port: number, env: Record<string, string>): ChildProcess {
  const bin = path.join(STOREFRONT, 'node_modules', 'next', 'dist', 'bin', 'next');
  return spawn(process.execPath, [bin, 'start', '-p', String(port), '-H', '127.0.0.1'], {
    cwd: STOREFRONT,
    env: { ...process.env, PORT: String(port), ...env },
    stdio: 'ignore',
  });
}

function stop(child: ChildProcess | undefined) {
  if (!child) return;
  if (process.platform === 'win32') spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
  else child.kill('SIGTERM');
}

async function waitFor(url: string, ms = 60_000) {
  const deadline = Date.now() + ms;
  for (;;) {
    try {
      const res = await fetch(url);
      if (res.status < 500) return;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error(`${url} did not answer within ${ms} ms`);
    await new Promise((r) => setTimeout(r, 250));
  }
}

function watch(page: Page) {
  const pageErrors: string[] = [];
  page.on('pageerror', (e) => pageErrors.push(String(e)));
  return { pageErrors };
}

/** The assertions both sources must satisfy for a published, OPEN, browse-only tenant. */
async function expectBrowseOnlyTenant(page: Page, base: string, slug: string, opts: { name: string; itemNames: string[]; soldOut: string; mediaOrigin: string; foreignItem: string; keyLiteral: string; expectImages: number; taxRateBp: number }) {
  for (const root of ROOTS) {
    const res = await page.goto(`${base}${root.prefix}/s/${slug}/menu`, { waitUntil: 'domcontentloaded' });
    expect(res?.status(), `${root.prefix}/s/${slug}/menu`).toBe(200);
    const html = await page.content();
    expect(await page.getAttribute('html', 'lang')).toBe(root.lang);
    expect(await page.getAttribute('html', 'dir')).toBe(root.dir);
    // the tenant's own data, as TEXT (a hostile name is data, never markup)
    await expect(page.locator('[data-sf-module="hero"]')).toBeVisible();
    expect(html).toContain(opts.name.replace(/</g, '&lt;').replace(/>/g, '&gt;'));
    expect(html).not.toContain('<script>alert(1)</script>');
    for (const item of opts.itemNames) expect(html, `${root.prefix}: ${item}`).toContain(item);
    // a sold-out item is marked, never openable
    const soldOut = page.locator(`[data-sf-item]:has-text("${opts.soldOut}")`).first();
    await expect(soldOut).toHaveAttribute('aria-disabled', 'true');
    // the browse-only notice and NO progression CTA to a send
    await expect(page.locator('[data-sf-notice="ordering-off"]')).toHaveCount(1);
    expect(html).toContain(root.m.orderingOfflineTitle);
    // the tenant's own tax rate reaches the document as serialised menu data (the tax ROW itself only renders on a
    // non-empty cart); the prop is JSON inside the inline RSC flight script, so the quote may be escaped
    const bs = String.fromCharCode(92);
    const rateToken = `taxRateBp${bs}":${opts.taxRateBp},`;
    expect(html.includes(rateToken) || html.includes(`taxRateBp":${opts.taxRateBp},`), `${root.prefix}: serialised tax rate ${opts.taxRateBp}`).toBe(true);
    // cross-tenant: nothing of the OTHER tenant, nothing of the fixture
    expect(html).not.toContain(opts.foreignItem);
    for (const marker of FIXTURE_MARKERS) expect(html, `${root.prefix}: fixture marker ${marker}`).not.toContain(marker);
    // the published derivative is an <img> on the media origin; no private key anywhere
    const srcs = await page.locator('img').evaluateAll((els) => els.map((e) => (e as HTMLImageElement).getAttribute('src') ?? ''));
    const media = srcs.filter((s) => s.startsWith('http'));
    expect(media.length, `${root.prefix}: at least ${opts.expectImages} published derivative rendered as <img>`).toBeGreaterThanOrEqual(opts.expectImages);
    for (const s of media) expect(s.startsWith(`${opts.mediaOrigin}/storage/v1/object/public/storefront-media/`), s).toBe(true);
    expect(html).not.toContain('privateorg');
    expect(html).not.toContain('menu_item/');
    // no credential, no API path in anything the document carries
    expect(html).not.toMatch(/apikey|STOREFRONT_SUPABASE|\/rest\/v1\//);
    expect(html, `${root.prefix}: the configured key value must never reach a document`).not.toContain(opts.keyLiteral);
    expect(html).not.toMatch(/sb_publishable_[A-Za-z0-9_-]{8,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}/);
  }
}

test.describe('STOREFRONT-READ-001 live read against a STUB envelope server', () => {
  const STUB_PORT = Number(process.env.STOREFRONT_STUB_PORT ?? 4710);
  const NEXT_PORT = Number(process.env.STOREFRONT_LIVE_PORT ?? 4711);
  const BASE = `http://127.0.0.1:${NEXT_PORT}`;
  const MEDIA_ORIGIN = `http://127.0.0.1:${STUB_PORT}`;
  let stub: Server;
  let next: ChildProcess;
  let mode: 'ok' | 'not_found' | 'error' | 'timeout' = 'ok';
  let versionTag = 'SYNTH V1';
  const calls: { slug: string; headers: Record<string, string | string[] | undefined> }[] = [];

  const envelopeFor = (slug: string) => {
    if (slug === 'sf-stub-a' || slug === 'sf-stub-fresh') {
      return syntheticEnvelope({ restaurant: { slug }, items: syntheticEnvelope().items.map((i, idx) => (idx === 1 ? { ...i, name: `Synth Cola ${versionTag}` } : i)) });
    }
    if (slug === 'sf-stub-b') {
      return syntheticEnvelope({
        menu_version: '7.1758600001',
        restaurant: { slug: 'sf-stub-b', display_name: 'Synth Bravo', tagline: null, visual_preset: 'light', card_mode: 'grid', motion: 'calm' },
        service: { state: 'paused' },
        tax: { enabled: false, rate_bp: 0, mode: 'exclusive' },
        categories: [{ id: SYNTH_IDS.catFood, name: 'Synth Pizza', display_order: 0, icon_key: 'pizza' }],
        items: [{ id: SYNTH_IDS.burger, category_id: SYNTH_IDS.catFood, name: 'Synth Margherita', description: 'tomato', base_price_minor: 4800, display_order: 0, tags: ['vegetarian'], image_url: null, availability: 'available' }],
        modifiers: [],
        modifier_options: [],
      });
    }
    return NOT_FOUND_ENVELOPE;
  };

  test.beforeAll(async () => {
    assertLiveBuild();
    purgeIsrCache();
    stub = createServer((req, res) => {
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', () => {
        if (req.method !== 'POST' || req.url !== '/rest/v1/rpc/storefront_menu') {
          res.writeHead(404, { 'content-type': 'application/json' });
          res.end('{"message":"not found"}');
          return;
        }
        const slug = String(JSON.parse(body || '{}').p_slug ?? '');
        calls.push({ slug, headers: req.headers });
        if (mode === 'timeout') return; // never answers: the client's 5 s timeout must fire
        if (mode === 'error') {
          res.writeHead(500, { 'content-type': 'application/json' });
          res.end('{"message":"synthetic failure"}');
          return;
        }
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify(mode === 'not_found' ? NOT_FOUND_ENVELOPE : envelopeFor(slug)));
      });
    });
    await new Promise<void>((r) => stub.listen(STUB_PORT, '127.0.0.1', r));
    next = startNext(NEXT_PORT, {
      STOREFRONT_SOURCE: 'live',
      STOREFRONT_SUPABASE_URL: `http://127.0.0.1:${STUB_PORT}`,
      STOREFRONT_SUPABASE_ANON_KEY: SYNTH_KEY,
    });
    await waitFor(`${BASE}/healthz.json`);
  });

  test.afterAll(async () => {
    stop(next);
    await new Promise<void>((r) => stub.close(() => r()));
  });

  test('the server calls the RPC with the anon key over the exact PostgREST shape, once per document, and the browser never does', async ({ page }) => {
    calls.length = 0;
    const requests: string[] = [];
    page.on('request', (r) => requests.push(r.url()));
    const res = await page.goto(`${BASE}/s/sf-stub-a/menu`, { waitUntil: 'networkidle' });
    expect(res?.status()).toBe(200);
    expect(calls.length).toBeGreaterThanOrEqual(1);
    for (const c of calls) {
      expect(c.slug).toBe('sf-stub-a');
      expect(c.headers.apikey).toBe(SYNTH_KEY);
      expect(c.headers.authorization).toBe(`Bearer ${SYNTH_KEY}`);
      expect(c.headers['content-type']).toContain('application/json');
    }
    // the BROWSER made no request to the database origin (connect-src 'self' holds by construction)
    expect(requests.filter((u) => u.startsWith(`http://127.0.0.1:${STUB_PORT}`) && !u.includes('/storage/'))).toEqual([]);
  });

  test('T-S10 / T-S5 / T-S9: two tenants x four locale roots, no fixture leakage, hostile text as text, browse-only', async ({ page }) => {
    mode = 'ok';
    await expectBrowseOnlyTenant(page, BASE, 'sf-stub-a', {
      name: 'Synth Alpha <script>alert(1)</script>',
      itemNames: ['Synth Burger', 'Synth Cola'],
      soldOut: 'Synth Sold Out',
      mediaOrigin: MEDIA_ORIGIN,
      foreignItem: 'Synth Margherita',
      keyLiteral: SYNTH_KEY,
      expectImages: 1,
      taxRateBp: 1800,
    });
    // the second tenant: paused, light, grid, tax OFF -> no tax row at all
    const res = await page.goto(`${BASE}/en/s/sf-stub-b/menu`, { waitUntil: 'domcontentloaded' });
    expect(res?.status()).toBe(200);
    const html = await page.content();
    expect(html).toContain('Synth Margherita');
    expect(html).not.toContain('Synth Burger');
    await expect(page.locator('[data-sf-notice="paused"]')).toHaveCount(1);
    await expect(page.locator('[data-sf-notice="ordering-off"]')).toHaveCount(1);
    for (const marker of FIXTURE_MARKERS) expect(html).not.toContain(marker);
  });

  test('T-S9: the checkout, payment and review URLs bounce to the cart; the send CTA never exists; /r/* is a 404', async ({ page }) => {
    mode = 'ok';
    for (const screen of ['checkout', 'payment', 'review']) {
      await page.goto(`${BASE}/s/sf-stub-a/${screen}`, { waitUntil: 'networkidle' });
      await expect(page).toHaveURL(`${BASE}/s/sf-stub-a/cart`, { timeout: 15_000 });
      await expect(page.locator('[data-sf-cta="send"]')).toHaveCount(0);
    }
    // the cart itself: reachable, states the reason, and its CTA is the reason (aria-disabled), never a link forward
    await page.goto(`${BASE}/s/sf-stub-a/cart`, { waitUntil: 'networkidle' });
    await expect(page.locator('[data-sf-banner="ordering-off"]')).toHaveCount(1);
    await expect(page.locator('[data-sf-cta="send"]')).toHaveCount(0);
    for (const ref of ['DEMO-7K4XM2D9P3', 'SYNTH-1234']) {
      for (const root of ROOTS) {
        const res = await page.goto(`${BASE}${root.prefix}/r/${ref}`, { waitUntil: 'domcontentloaded' });
        expect(res?.status(), `${root.prefix}/r/${ref}`).toBe(404);
      }
    }
  });

  test('T-S7: documents are cached per URL with the 60 s ISR header, carry no cookie, and differ per tenant and per root', async ({ request }) => {
    mode = 'ok';
    const seen = new Map<string, string>();
    for (const slug of ['sf-stub-a', 'sf-stub-b']) {
      for (const root of ROOTS) {
        const res = await request.get(`${BASE}${root.prefix}/s/${slug}/menu`);
        expect(res.status()).toBe(200);
        const h = res.headers();
        expect(h['cache-control'], `${root.prefix}/s/${slug}`).toMatch(/s-maxage=60\b/);
        expect(h['cache-control']).toMatch(/stale-while-revalidate=300\b/);
        expect(h['set-cookie']).toBeUndefined();
        const body = await res.text();
        for (const [other, text] of seen) expect(body, `${root.prefix}/s/${slug} vs ${other}`).not.toBe(text);
        seen.set(`${root.prefix}/s/${slug}`, body);
      }
    }
  });

  test('T-S8: not_found -> the Unknown document (404, no tenant data); a transport failure or timeout -> an error, never the fixture', async ({ page }) => {
    mode = 'not_found';
    const missing = await page.goto(`${BASE}/s/sf-stub-zzz/menu`, { waitUntil: 'domcontentloaded' });
    expect(missing?.status()).toBe(404);
    let html = await page.content();
    expect(html).toContain(AR.unknownTitle);
    expect(html).not.toContain('data-sf-module="hero"');
    for (const marker of FIXTURE_MARKERS) expect(html).not.toContain(marker);

    mode = 'error';
    const failed = await page.goto(`${BASE}/s/sf-stub-err1/menu`, { waitUntil: 'domcontentloaded' });
    expect(failed?.status()).toBe(500);
    html = await page.content();
    expect(html).not.toContain('data-sf-module="hero"');
    for (const marker of FIXTURE_MARKERS) expect(html).not.toContain(marker);

    mode = 'timeout';
    const started = Date.now();
    const timedOut = await page.goto(`${BASE}/s/sf-stub-err2/menu`, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    expect(timedOut?.status()).toBe(500);
    expect(Date.now() - started).toBeGreaterThanOrEqual(4_500);
    html = await page.content();
    expect(html).not.toContain('data-sf-module="hero"');
    mode = 'ok';
  });

  test('T-S7 freshness: a menu change is visible after the 60 s revalidate window (stale-while-revalidate serves the old document once)', async ({ request }) => {
    test.setTimeout(150_000);
    mode = 'ok';
    versionTag = 'SYNTH V1';
    calls.length = 0; // sf-stub-fresh is touched by no other test: the first GET below is a cache MISS
    const first = await request.get(`${BASE}/he/s/sf-stub-fresh/menu`);
    expect(await first.text()).toContain('Synth Cola SYNTH V1');
    versionTag = 'SYNTH V2';
    // inside the window the cached document is served unchanged and the RPC is NOT called again
    expect(await (await request.get(`${BASE}/he/s/sf-stub-fresh/menu`)).text()).toContain('Synth Cola SYNTH V1');
    expect(calls.filter((c) => c.slug === 'sf-stub-fresh').length, 'exactly one render inside the window').toBe(1);
    await new Promise((r) => setTimeout(r, 61_000));
    // first request after the window may still be the stale document (regeneration in the background)
    await request.get(`${BASE}/he/s/sf-stub-fresh/menu`);
    let fresh = '';
    for (let i = 0; i < 20 && !fresh.includes('SYNTH V2'); i++) {
      await new Promise((r) => setTimeout(r, 500));
      fresh = await (await request.get(`${BASE}/he/s/sf-stub-fresh/menu`)).text();
    }
    expect(fresh).toContain('Synth Cola SYNTH V2');
  });
});

test.describe('STOREFRONT-READ-001 live read against the LOCAL database (real RPC)', () => {
  const API = process.env.STOREFRONT_LOCAL_API_URL;
  const KEY = process.env.STOREFRONT_LOCAL_ANON_KEY;
  const NEXT_PORT = Number(process.env.STOREFRONT_LIVE_DB_PORT ?? 4712);
  const BASE = `http://127.0.0.1:${NEXT_PORT}`;
  let next: ChildProcess;

  test.skip(!API || !KEY, 'STOREFRONT_LOCAL_API_URL / STOREFRONT_LOCAL_ANON_KEY not set: the real-database block is SKIPPED (reported, not passed)');

  test.beforeAll(async () => {
    assertLiveBuild();
    purgeIsrCache();
    next = startNext(NEXT_PORT, {
      STOREFRONT_SOURCE: 'live',
      STOREFRONT_SUPABASE_URL: API!,
      STOREFRONT_SUPABASE_ANON_KEY: KEY!,
    });
    await waitFor(`${BASE}/healthz.json`);
  });

  test.afterAll(() => stop(next));

  test('REAL: the seeded synthetic tenants are served by public.storefront_menu through the anon key', async ({ page }) => {
    const { pageErrors } = watch(page);
    await expectBrowseOnlyTenant(page, BASE, 'sf-synth-a', {
      name: 'SYNTH Alpha <script>alert(1)</script>',
      itemNames: ['SYNTH Classic', 'SYNTH Double', 'SYNTH Cola'],
      soldOut: 'SYNTH Sold Out',
      mediaOrigin: API!,
      foreignItem: 'SYNTH Margherita',
      keyLiteral: KEY!,
      expectImages: 1,
      taxRateBp: 1800,
    });
    // the seeded internal fields never reach a document
    const html = await page.content();
    expect(html).not.toMatch(/SYNTH-SKU-SECRET|SYNTH internal note|privateorg/);
    expect(pageErrors).toEqual([]);
  });

  test('REAL: the paused tenant is paused, the unpublished tenant and an unknown slug are the same 404', async ({ page }) => {
    const b = await page.goto(`${BASE}/en/s/sf-synth-b/menu`, { waitUntil: 'domcontentloaded' });
    expect(b?.status()).toBe(200);
    await expect(page.locator('[data-sf-notice="paused"]')).toHaveCount(1);
    const bHtml = await page.content();
    expect(bHtml).toContain('SYNTH Margherita');
    expect(bHtml).toMatch(/taxRateBp\\?":0\b/); // tax OFF for this tenant
    expect(bHtml).not.toMatch(/taxRateBp\\?":1800\b/);
    const c = await page.goto(`${BASE}/s/sf-synth-c/menu`, { waitUntil: 'domcontentloaded' });
    expect(c?.status()).toBe(404);
    const cHtml = await page.content();
    expect(cHtml).not.toContain('SYNTH Hidden');
    expect(cHtml).not.toContain('Charlie');
    const z = await page.goto(`${BASE}/s/sf-synth-zzz/menu`, { waitUntil: 'domcontentloaded' });
    expect(z?.status()).toBe(404);
    expect(await page.content()).toContain(AR.unknownTitle);
  });
});
