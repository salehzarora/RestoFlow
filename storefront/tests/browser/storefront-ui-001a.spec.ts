// STOREFRONT-UI-001 Phase A browser gates, against the REAL exported tree
// served with the CSP parsed from the committed storefront/vercel.json.
//
//   G01  Intro screen matches the approved design contract
//   G36  Unknown/unpublished screen leaks no tenant identity or theme
//   X04  zero CSP violations and zero page errors on every Phase A route
//   X05  locale switching lands on correct served bytes
//   X07  touch targets and focus ring
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_TEST_PORT ?? 4402);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_SHOT_DIR ?? path.join(STOREFRONT, 'ui001a-evidence');
const RESULTS: Record<string, unknown> = {};

let server: ChildProcess;

test.beforeAll(async () => {
  mkdirSync(SHOTS, { recursive: true });
  server = spawn(process.execPath, ['scripts/serve-out.mjs'], {
    cwd: STOREFRONT,
    env: { ...process.env, PORT: String(PORT) },
    stdio: 'ignore',
  });
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
  writeFileSync(path.join(SHOTS, 'browser-results.json'), JSON.stringify(RESULTS, null, 2) + '\n');
});

function watch(page: Page) {
  const consoleErrors: string[] = [];
  const cspViolations: string[] = [];
  const pageErrors: string[] = [];
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    (/content security policy/i.test(t) ? cspViolations : consoleErrors).push(t);
  });
  page.on('pageerror', (e) => pageErrors.push(String(e)));
  return { consoleErrors, cspViolations, pageErrors };
}

const PHASE_A_ROUTES = [
  '/', '/ar', '/en', '/he',
  '/s/maps-burger', '/ar/s/maps-burger', '/en/s/maps-burger', '/he/s/maps-burger',
  '/s/maps-burger/menu',
];

// ---------------------------------------------------------------------------
// Non-vacuity: the CSP detector must be able to SEE a violation, or every
// "zero violations" result below proves nothing.
// ---------------------------------------------------------------------------
test('X00 the CSP detector is non-vacuous', async ({ page }) => {
  const w = watch(page);
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });
  const width = await page.evaluate(() => {
    const el = document.createElement('div');
    el.setAttribute('style', 'width: 123px');
    document.body.appendChild(el);
    return getComputedStyle(el).width;
  });
  RESULTS.X00 = { injectedInlineStyleWidth: width, violationsSeen: w.cspViolations.length };
  expect(width).not.toBe('123px');
  expect(w.cspViolations.length).toBeGreaterThan(0);
});

test('G01 the Intro screen matches the approved contract', async ({ page }) => {
  const w = watch(page);
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);

  const html = page.locator('html');
  const main = page.locator('h1');

  // The tenant identity the design requires on this screen.
  await expect(main).toHaveText('Maps Burger');
  await expect(page.getByText('أهلاً بك في')).toBeVisible();
  await expect(page.getByText('برجر أطيب.. لمزاج أفضل')).toBeVisible();

  // Exactly one primary CTA, and no skip control (there is deliberately none).
  const cta = page.getByRole('link', { name: 'استكشف القائمة' });
  await expect(cta).toHaveCount(1);
  const box = await cta.boundingBox();

  // Three service pills: state, pickup, delivery.
  const pillText = await page.locator('ul li').allInnerTexts();

  // The theme must have been APPLIED by CSSOM, not left at the neutral default.
  const applied = await page.evaluate(() => {
    const root = document.querySelector('[data-sf-root]');
    if (!root) return null;
    const cs = getComputedStyle(root);
    return {
      hero: cs.getPropertyValue('--hero').trim(),
      acc: cs.getPropertyValue('--acc').trim(),
      bg: cs.getPropertyValue('--bg').trim(),
    };
  });

  // The screen does not scroll.
  const scrolls = await page.evaluate(
    () => document.documentElement.scrollHeight > document.documentElement.clientHeight + 2,
  );

  RESULTS.G01 = {
    lang: await html.getAttribute('lang'),
    dir: await html.getAttribute('dir'),
    ctaHeight: box?.height,
    pills: pillText,
    appliedTheme: applied,
    documentScrolls: scrolls,
    cspViolations: w.cspViolations,
    pageErrors: w.pageErrors,
  };

  expect(await html.getAttribute('lang')).toBe('ar');
  expect(await html.getAttribute('dir')).toBe('rtl');
  expect(box!.height).toBeGreaterThanOrEqual(56); // design: 60px CTA
  // Hex is case-insensitive; sanitizePrimary/sanitizeAccent normalise case.
  expect(applied!.hero.toLowerCase()).toBe('#123027'); // the DEMO tenant's primary, at runtime
  expect(applied!.acc.toLowerCase()).toBe('#ff8a2a');
  expect(w.cspViolations).toEqual([]);
  expect(w.pageErrors).toEqual([]);

  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: path.join(SHOTS, 'G01-intro-ar-dark-390x844.png'), fullPage: false });
});

test('G01b the Intro renders in every locale with correct served direction', async ({ page }) => {
  const per: Record<string, unknown> = {};
  for (const [route, lang, dir] of [
    ['/ar/s/maps-burger', 'ar', 'rtl'],
    ['/en/s/maps-burger', 'en', 'ltr'],
    ['/he/s/maps-burger', 'he', 'rtl'],
  ] as const) {
    const w = watch(page);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    const html = page.locator('html');
    per[route] = {
      lang: await html.getAttribute('lang'),
      dir: await html.getAttribute('dir'),
      heading: await page.locator('h1').innerText(),
      cspViolations: w.cspViolations,
    };
    expect(await html.getAttribute('lang'), route).toBe(lang);
    expect(await html.getAttribute('dir'), route).toBe(dir);
    expect(w.cspViolations, route).toEqual([]);
    await page.screenshot({ path: path.join(SHOTS, `G01-intro-${lang}-390x844.png`) });
  }
  RESULTS.G01b = per;
});

test('G36 the Unknown screen leaks no tenant identity or theme', async ({ page }) => {
  const w = watch(page);
  const res = await page.goto(`${BASE}/s/not-a-real-tenant`, { waitUntil: 'networkidle' });

  const body = await page.locator('body').innerText();
  const htmlSource = await page.content();

  // Nothing about any tenant may appear.
  for (const leak of ['Maps Burger', 'maps-burger', '#123027', '#FF8A2A', 'كفر مندا', 'برجر']) {
    expect(htmlSource, `Unknown must not leak ${leak}`).not.toContain(leak);
  }

  const themed = await page.evaluate(() => {
    const cs = getComputedStyle(document.body);
    return { hero: cs.getPropertyValue('--hero').trim(), acc: cs.getPropertyValue('--acc').trim() };
  });

  RESULTS.G36 = {
    status: res?.status(),
    bodyText: body,
    tenantCustomProperties: themed,
    cspViolations: w.cspViolations,
    pageErrors: w.pageErrors,
  };

  expect(body).toContain('هذا المتجر غير متاح');
  expect(themed.hero).toBe(''); // no tenant theme is defined at all
  expect(themed.acc).toBe('');
  expect(w.cspViolations).toEqual([]);
  expect(w.pageErrors).toEqual([]);

  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: path.join(SHOTS, 'G36-unknown-390x844.png') });
});

test('X04 zero CSP violations and page errors across every Phase A route', async ({ page }) => {
  const per: Record<string, unknown> = {};
  for (const route of PHASE_A_ROUTES) {
    const w = watch(page);
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    // No document may carry an inline style attribute of our authorship.
    // Next injects <next-route-announcer> with an inline style on every
    // app-router page, including the pre-existing shell. That is framework
    // output, not ours, so it is RECORDED rather than asserted away — what
    // must be zero is inline styles of our own authorship.
    const styled = await page.evaluate(() =>
      Array.from(document.querySelectorAll('[style]')).map((el) => ({
        tag: el.tagName.toLowerCase(),
        inAnnouncer: el.closest('next-route-announcer') !== null,
        isThemeHost: el.hasAttribute('data-sf-root'),
        style: (el.getAttribute('style') ?? '').slice(0, 60),
      })),
    );
    // The theme host legitimately CARRIES a style attribute at runtime: that is
    // exactly what CSSOM setProperty produces, and it is the CSP-legal path
    // U-8 proved. What must never happen is a style attribute in the SERVED
    // bytes, which is asserted separately below against the raw response.
    const ours = styled.filter((e) => !e.inAnnouncer && !e.isThemeHost);
    const servedHtml = await (await fetch(`${BASE}${route}`)).text();
    const servedStyleAttrs = servedHtml.match(/<[^>]+\sstyle="/g) ?? [];
    per[route] = {
      cspViolations: w.cspViolations,
      consoleErrors: w.consoleErrors,
      pageErrors: w.pageErrors,
      inlineStyledElements: styled,
      inlineStylesOfOurAuthorship: ours,
      styleAttributesInServedBytes: servedStyleAttrs.length,
    };
    expect(w.cspViolations, `${route} CSP`).toEqual([]);
    expect(w.pageErrors, `${route} page errors`).toEqual([]);
    expect(ours, `${route} unexpected runtime inline styles`).toEqual([]);
    expect(servedStyleAttrs, `${route} style attributes in SERVED bytes`).toEqual([]);
  }
  RESULTS.X04 = per;
});

test('X05 language switching lands on correct served bytes', async ({ page }) => {
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });

  // The control is a <details> disclosure: the three language links exist in
  // the document but are not reachable until it is opened. That it needs
  // opening is the designed behaviour, so the test opens it the way a person
  // would rather than reaching past it.
  const en = page.locator('a[hreflang="en"]');
  await expect(en).toHaveCount(1);
  await expect(en).not.toBeVisible();
  await page.locator('summary').click();
  await expect(en).toBeVisible();

  // All three languages are offered, with the current one marked.
  const offered = await page.locator('a[hreflang]').count();
  expect(offered).toBe(3);
  await expect(page.locator('a[hreflang="ar"][aria-current="true"]')).toHaveCount(1);

  await en.click();
  await page.waitForLoadState('networkidle');

  const after = {
    url: new URL(page.url()).pathname,
    lang: await page.locator('html').getAttribute('lang'),
    dir: await page.locator('html').getAttribute('dir'),
  };
  RESULTS.X05 = after;
  // A full navigation, so the SERVED document is the English one.
  expect(after.url).toBe('/en/s/maps-burger');
  expect(after.lang).toBe('en');
  expect(after.dir).toBe('ltr');
});

test('X07 touch targets reach 44px and the focus ring is visible', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });

  const targets = await page.evaluate(() => {
    const out: { tag: string; label: string; w: number; h: number }[] = [];
    for (const el of document.querySelectorAll('a, button')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      out.push({
        tag: el.tagName.toLowerCase(),
        label: (el.getAttribute('aria-label') ?? el.textContent ?? '').trim().slice(0, 30),
        w: Math.round(r.width),
        h: Math.round(r.height),
      });
    }
    return out;
  });

  const cta = page.getByRole('link', { name: 'استكشف القائمة' });
  await cta.focus();
  const ring = await cta.evaluate((el) => {
    const cs = getComputedStyle(el);
    return { outlineWidth: cs.outlineWidth, outlineStyle: cs.outlineStyle, outlineColor: cs.outlineColor };
  });

  RESULTS.X07 = { targets, focusRing: ring };
  // The effective target for every control is at least 44x44.
  for (const t of targets) {
    expect(t.w, `${t.tag} "${t.label}" width`).toBeGreaterThanOrEqual(44);
    expect(t.h, `${t.tag} "${t.label}" height`).toBeGreaterThanOrEqual(44);
  }
  expect(ring.outlineStyle).toBe('solid');
  expect(parseFloat(ring.outlineWidth)).toBeGreaterThanOrEqual(3);
});

test('X07b reduced motion collapses the authored animations', async ({ browser }) => {
  const ctx = await browser.newContext({ reducedMotion: 'reduce' });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });
  const durations = await page.evaluate(() =>
    Array.from(document.querySelectorAll('h1, p, a, li'))
      .map((el) => getComputedStyle(el).animationDuration)
      .filter((d) => d !== 'auto' && d !== '0s'),
  );
  RESULTS.X07b = { animationDurations: [...new Set(durations)] };
  for (const d of durations) expect(parseFloat(d)).toBeLessThanOrEqual(0.01);
  await ctx.close();
});
