// Browser verification of the REAL exported out/ tree, served by
// scripts/serve-out.mjs with the headers parsed from the committed
// storefront/vercel.json. This is LOCAL EMULATION of the documented Vercel
// cleanUrls/trailingSlash behaviour, not hosted verification.
//
// This file lives under storefront/tests/, a storefront-local support root the
// deployment filter never scans, so it may use Node APIs and a test runner that
// the application source may not.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import path from 'node:path';

// Playwright transpiles this spec to CJS, so import.meta is unavailable. The
// suite is always invoked from storefront/, which the config's testDir assumes.
const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_TEST_PORT ?? 4399);
const BASE = `http://127.0.0.1:${PORT}`;

let server: ChildProcess;

test.beforeAll(async () => {
  server = spawn(process.execPath, ['scripts/serve-out.mjs'], {
    cwd: STOREFRONT,
    env: { ...process.env, PORT: String(PORT) },
    stdio: 'ignore',
  });
  // Wait for the port to answer rather than sleeping a fixed time.
  const deadline = Date.now() + 20_000;
  for (;;) {
    try {
      const res = await fetch(`${BASE}/healthz.json`);
      if (res.ok) break;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error('serve-out.mjs did not start');
    await new Promise((r) => setTimeout(r, 200));
  }
});

test.afterAll(() => {
  server?.kill();
});

/** Collect console errors, page errors and CSP violations for one page. */
function watch(page: Page) {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  const cspViolations: string[] = [];
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const text = m.text();
    (/content security policy/i.test(text) ? cspViolations : consoleErrors).push(text);
  });
  page.on('pageerror', (e) => pageErrors.push(String(e)));
  return { consoleErrors, pageErrors, cspViolations };
}

const LOCALES = [
  { route: '/', lang: 'ar', dir: 'rtl' },
  { route: '/ar', lang: 'ar', dir: 'rtl' },
  { route: '/en', lang: 'en', dir: 'ltr' },
  { route: '/he', lang: 'he', dir: 'rtl' },
] as const;

test.describe('served headers', () => {
  test('the committed CSP and security headers are actually applied', async ({ request }) => {
    const res = await request.get(`${BASE}/`);
    expect(res.status()).toBe(200);
    const h = res.headers();
    // If this is missing, every CSP assertion below would be vacuous.
    expect(h['content-security-policy'], 'the test server must apply the committed CSP').toBeTruthy();
    expect(h['content-security-policy']).toContain("default-src 'self'");
    expect(h['content-security-policy']).not.toContain("'unsafe-eval'");
    expect(h['x-content-type-options']).toBe('nosniff');
    expect(h['x-frame-options']).toBe('DENY');
    expect(h['referrer-policy']).toBe('strict-origin-when-cross-origin');
    expect(h['x-robots-tag']).toBe('noindex, nofollow');
    expect(h['strict-transport-security']).toContain('max-age=63072000');
  });
});

test.describe('direct load emits the right language before hydration', () => {
  for (const { route, lang, dir } of LOCALES) {
    test(`${route} -> lang=${lang} dir=${dir}`, async ({ page }) => {
      const seen = watch(page);

      // Read the SERVED markup, before any script runs.
      const res = await page.request.get(`${BASE}${route}`);
      expect(res.status()).toBe(200);
      const html = await res.text();
      expect(html).toMatch(new RegExp(`<html lang="${lang}" dir="${dir}"`));

      await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
      await expect(page.locator('html')).toHaveAttribute('lang', lang);
      await expect(page.locator('html')).toHaveAttribute('dir', dir);
      await expect(page.locator('h1')).toBeVisible();

      expect(seen.pageErrors, 'page errors').toEqual([]);
      expect(seen.consoleErrors, 'console errors').toEqual([]);
      expect(seen.cspViolations, 'CSP violations').toEqual([]);
    });
  }
});

test.describe('canonicalisation and not-found', () => {
  test('/ar.html canonicalises to /ar and preserves the query string', async ({ request }) => {
    const res = await request.get(`${BASE}/ar.html?probe=1`, { maxRedirects: 0 });
    expect(res.status()).toBe(308);
    expect(res.headers()['location']).toBe('/ar?probe=1');
  });

  test('/ar/ canonicalises to /ar', async ({ request }) => {
    const res = await request.get(`${BASE}/ar/`, { maxRedirects: 0 });
    expect(res.status()).toBe(308);
    expect(res.headers()['location']).toBe('/ar');
  });

  test('an unknown path returns a real 404, not index.html with 200', async ({ request }) => {
    const res = await request.get(`${BASE}/definitely-not-a-route`);
    expect(res.status()).toBe(404);
    const body = await res.text();
    expect(body).not.toContain('langList'); // not the home document
  });

  test('path traversal cannot escape out/', async ({ request }) => {
    const res = await request.get(`${BASE}/../package.json`);
    expect([400, 404]).toContain(res.status());
  });
});

test.describe('language links', () => {
  test('each locale link navigates and switches the document language', async ({ page }) => {
    for (const { lang, dir } of LOCALES.slice(1)) {
      await page.goto(`${BASE}/`, { waitUntil: 'load' });
      // Crossing root layouts is a full document load, so wait for the
      // navigation rather than assuming client-side routing.
      await Promise.all([
        page.waitForURL(`${BASE}/${lang}`),
        page.locator(`a[hreflang="${lang}"]`).click(),
      ]);
      await expect(page.locator('html')).toHaveAttribute('lang', lang);
      await expect(page.locator('html')).toHaveAttribute('dir', dir);
      await expect(page.locator('h1')).toBeVisible();
    }
  });

  test('keyboard focus reaches every locale link and is visible', async ({ page }) => {
    await page.goto(`${BASE}/en`, { waitUntil: 'networkidle' });
    const links = page.locator('a.langLink');
    await expect(links).toHaveCount(3);
    await page.keyboard.press('Tab');
    const focused = await page.evaluate(() => document.activeElement?.tagName);
    expect(focused).toBe('A');
    const outline = await page.evaluate(() => {
      const el = document.activeElement as HTMLElement | null;
      return el ? getComputedStyle(el).outlineStyle : 'none';
    });
    expect(outline).not.toBe('none');
  });
});

test.describe('viewports', () => {
  for (const width of [375, 390, 430, 1280]) {
    test(`no horizontal overflow at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 844 });
      await page.goto(`${BASE}/`, { waitUntil: 'networkidle' });
      const overflow = await page.evaluate(() =>
        document.documentElement.scrollWidth - document.documentElement.clientWidth);
      expect(overflow, `horizontal overflow at ${width}px`).toBeLessThanOrEqual(0);
      await expect(page.locator('h1')).toBeVisible();
    });
  }
});

test.describe('assets', () => {
  test('every referenced asset resolves', async ({ page }) => {
    const failed: string[] = [];
    page.on('response', (r) => {
      if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`);
    });
    await page.goto(`${BASE}/`, { waitUntil: 'networkidle' });
    expect(failed, 'no broken asset requests').toEqual([]);
  });
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  for (const { route, lang, dir } of LOCALES) {
    test(`${route} is readable and navigable with JS disabled`, async ({ page }) => {
      await page.goto(`${BASE}${route}`);
      await expect(page.locator('html')).toHaveAttribute('lang', lang);
      await expect(page.locator('html')).toHaveAttribute('dir', dir);
      await expect(page.locator('h1')).toBeVisible();
      // Placeholder copy and the locale links are server-rendered, so they work
      // without hydration.
      await expect(page.locator('a.langLink')).toHaveCount(3);
    });
  }
});
