// STOREFRONT-UI-001 Phase B1 correction evidence, against the REAL exported
// tree served with the CSP parsed from the committed storefront/vercel.json.
//
// One test per corrected review finding, asserted in the RENDERED DOM rather
// than by a regex over the source that produces it. Several carry an explicit
// negative control, because an assertion that cannot fail proves nothing.
//
// Run against an EVIDENCE build (`SF_EVIDENCE_ROUTES=1 npm run build`): the
// shipped export deliberately emits no demo slug, and the state cases need one.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_B1_PORT ?? 4404);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_B1_SHOT_DIR ?? path.join(STOREFRONT, 'ui001b1-evidence');
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
  // The state cases need the evidence build. Fail loudly rather than skip.
  const probe = await fetch(`${BASE}/s/demo-closed/menu.html`);
  if (!probe.ok) {
    throw new Error(
      'demo routes are absent: rebuild with SF_EVIDENCE_ROUTES=1 before running the B1 suite',
    );
  }
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, 'b1-browser-results.json'), JSON.stringify(RESULTS, null, 2) + '\n');
});

interface Watch {
  consoleErrors: string[];
  cspViolations: string[];
  pageErrors: string[];
  offOrigin: string[];
  failed: string[];
}

function watch(page: Page): Watch {
  const w: Watch = { consoleErrors: [], cspViolations: [], pageErrors: [], offOrigin: [], failed: [] };
  page.on('console', (msg) => {
    if (msg.type() !== 'error') return;
    const t = msg.text();
    (/content security policy/i.test(t) ? w.cspViolations : w.consoleErrors).push(t);
  });
  page.on('pageerror', (e) => w.pageErrors.push(String(e)));
  page.on('request', (r) => {
    if (!r.url().startsWith(BASE) && !r.url().startsWith('data:')) w.offOrigin.push(r.url());
  });
  page.on('requestfailed', (r) => w.failed.push(`${r.url()} ${r.failure()?.errorText ?? ''}`));
  page.on('response', (r) => {
    if (r.status() >= 400) w.failed.push(`${r.url()} HTTP ${r.status()}`);
  });
  return w;
}

async function overflow(page: Page) {
  return page.evaluate(
    () => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1,
  );
}

function assertClean(id: string, w: Watch, over: boolean) {
  expect(w.cspViolations, `${id} CSP violations`).toEqual([]);
  expect(w.pageErrors, `${id} page errors`).toEqual([]);
  expect(w.consoleErrors, `${id} console errors`).toEqual([]);
  expect(w.offOrigin, `${id} off-origin requests`).toEqual([]);
  expect(w.failed, `${id} failed requests`).toEqual([]);
  expect(over, `${id} horizontal overflow`).toBe(false);
}

const rgb = (s: string) => s.replace(/\s/g, '');

// ---------------------------------------------------------------- MAJOR-1

test('B1-M1 the collapsed compact header is out of keyboard and a11y traversal', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const compact = page.locator('[data-sf-compact]');
  const chip = compact.locator('button[data-category]').first();

  await expect(compact).toHaveAttribute('data-sf-compact', 'off');
  expect(await chip.evaluate((el) => getComputedStyle(el).visibility)).toBe('hidden');
  // .focus() on a visibility:hidden element is a no-op: that IS non-focusability.
  await chip.evaluate((el: HTMLElement) => el.focus());
  expect(await chip.evaluate((el) => el === document.activeElement)).toBe(false);
  expect(await page.getByRole('navigation').count(), 'collapsed rail is out of the a11y tree').toBe(1);

  await page.evaluate(() => window.scrollTo(0, 400));
  await page.waitForTimeout(500);
  await expect(compact).toHaveAttribute('data-sf-compact', 'on');
  expect(await chip.evaluate((el) => getComputedStyle(el).visibility)).toBe('visible');
  await chip.evaluate((el: HTMLElement) => el.focus());
  expect(await chip.evaluate((el) => el === document.activeElement)).toBe(true);
  // Both rails are named navigation landmarks once the compact one is exposed.
  expect(await page.getByRole('navigation').count()).toBe(2);

  RESULTS['B1-M1'] = { collapsedNavs: 1, expandedNavs: 2 };
  assertClean('B1-M1', w, await overflow(page));
});

test('B1-M1b the exit transition still plays before the header leaves the tree', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  await page.evaluate(() => window.scrollTo(0, 400));
  await page.waitForTimeout(500);
  const compact = page.locator('[data-sf-compact]');
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.evaluate(
    () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))),
  );
  expect(
    await compact.evaluate((el) => getComputedStyle(el).visibility),
    'visibility must interpolate as visible so the fade-out plays',
  ).toBe('visible');
  await page.waitForTimeout(600);
  expect(await compact.evaluate((el) => getComputedStyle(el).visibility)).toBe('hidden');
});

// ---------------------------------------------------------------- MAJOR-2

test('B1-M2 closed uses the neutral dock surface and paused the warning tone', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });

  await page.goto(`${BASE}/s/demo-closed/menu`, { waitUntil: 'networkidle' });
  const closed = page.locator('[data-sf-notice="closed"]');
  await expect(closed).toBeVisible();
  const closedBg = await closed.evaluate((el) => getComputedStyle(el).backgroundColor);
  // Read the token from the THEMED element: ThemeScope applies tenant tokens to
  // its own root via CSSOM, so documentElement still carries only the neutral
  // pre-hydration fallback from globals.css.
  const tokenAsRgb = (name: string) =>
    closed.evaluate((el, n) => {
      const hex = getComputedStyle(el).getPropertyValue(n).trim();
      const probe = document.createElement('div');
      probe.style.setProperty('color', hex);
      el.appendChild(probe);
      const v = getComputedStyle(probe).color;
      probe.remove();
      return v;
    }, name);
  const sf = await tokenAsRgb('--sf');
  const badbg = await tokenAsRgb('--badbg');
  const asRgb = async (v: string) => v;
  expect(rgb(closedBg), 'closed must be the neutral --sf card').toBe(rgb(await asRgb(sf)));
  expect(rgb(closedBg), 'closed must NOT be the danger bed').not.toBe(rgb(await asRgb(badbg)));

  await page.goto(`${BASE}/s/demo-paused/menu`, { waitUntil: 'networkidle' });
  const paused = page.locator('[data-sf-notice="paused"]');
  await expect(paused).toBeVisible();
  const pausedBg = await paused.evaluate((el) => getComputedStyle(el).backgroundColor);
  const warnbg = await paused.evaluate((el) => {
    const hex = getComputedStyle(el).getPropertyValue('--warnbg').trim();
    const probe = document.createElement('div');
    probe.style.setProperty('color', hex);
    el.appendChild(probe);
    const v = getComputedStyle(probe).color;
    probe.remove();
    return v;
  });
  expect(rgb(pausedBg), 'paused keeps the warning tone').toBe(rgb(warnbg));
  expect(rgb(pausedBg), 'the two states must remain distinguishable').not.toBe(rgb(closedBg));

  RESULTS['B1-M2'] = { closedBg, pausedBg };
  assertClean('B1-M2', w, await overflow(page));
});

// ---------------------------------------------------------------- MAJOR-3

for (const [locale, route, dir] of [
  ['ar', '/s/maps-burger/menu', 'rtl'],
  ['en', '/en/s/maps-burger/menu', 'ltr'],
] as const) {
  test(`B1-M3 promo panes are text-then-photo in ${locale}/${dir}`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    expect(await page.evaluate(() => document.documentElement.dir)).toBe(dir);

    const promo = page.locator('[data-sf-module="promo"]');
    await expect(promo).toBeVisible();
    const band = (await promo.boundingBox())!;
    const media = (await promo.locator('img').first().boundingBox())!;

    // The 42% photo must occupy the inline-END half of the band.
    const mediaCentre = media.x + media.width / 2;
    const bandCentre = band.x + band.width / 2;
    if (dir === 'rtl') {
      expect(mediaCentre, 'RTL: the photo belongs on the LEFT (inline-end)').toBeLessThan(bandCentre);
    } else {
      expect(mediaCentre, 'LTR: the photo belongs on the RIGHT (inline-end)').toBeGreaterThan(bandCentre);
    }
    // ...and it really is the narrower pane, i.e. the 42% track.
    expect(media.width).toBeLessThan(band.width * 0.5);

    RESULTS[`B1-M3-${locale}`] = { band, media };
    assertClean(`B1-M3-${locale}`, w, await overflow(page));
  });
}

// ---------------------------------------------------------------- MAJOR-4

for (const [locale, route, dir] of [
  ['en', '/en/s/maps-burger/menu', 'ltr'],
  ['ar', '/s/maps-burger/menu', 'rtl'],
] as const) {
  test(`B1-M4 hero title, rule and subline share one edge in ${locale}/${dir}`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    expect(await page.evaluate(() => document.documentElement.dir)).toBe(dir);

    // dir="auto" must sit on the inner RUN, never on the block.
    expect(await page.locator('h1[dir="auto"]').count(), 'no block-level dir=auto').toBe(0);
    expect(await page.locator('h1 > span[dir="auto"]').count()).toBe(1);

    // Measure the INK (the inline span). The h1's own box spans the full gutter
    // in every direction and would pass vacuously.
    const hero = page.locator('[data-sf-module="hero"]');
    const titleInk = (await hero.locator('h1 > span').boundingBox())!;
    const subInk = (await hero.locator('p > span[dir="auto"]').first().boundingBox())!;
    const rule = (await hero.locator('h1 + div').boundingBox())!;

    const startEdge = (b: { x: number; width: number }) => (dir === 'rtl' ? b.x + b.width : b.x);
    expect(Math.abs(startEdge(titleInk) - startEdge(rule))).toBeLessThanOrEqual(1.5);
    expect(Math.abs(startEdge(subInk) - startEdge(rule))).toBeLessThanOrEqual(1.5);

    RESULTS[`B1-M4-${locale}`] = { titleInk, subInk, rule };
    assertClean(`B1-M4-${locale}`, w, await overflow(page));
  });
}

// ---------------------------------------------------------------- MAJOR-5

async function samples(page: Page, click: () => Promise<void>, read: () => Promise<number>) {
  await click();
  const t0 = await read();
  await page.waitForTimeout(150);
  return { t0, t150: await read() };
}

const ORB_RAIL = '[data-sf-module="categories"] > div';
const ARROWS = '[data-sf-module="categories"] > button';

test('B1-M5 reduced motion makes programmatic scrolling instant', async ({ browser }) => {
  const ctx = await browser.newContext({
    reducedMotion: 'reduce',
    viewport: { width: 390, height: 844 },
  });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  // (1) goTo -> scrollIntoView on the document scroller.
  const doc = await samples(
    page,
    () => page.locator(`${ORB_RAIL} button[data-category]`).nth(3).click(),
    () => page.evaluate(() => window.scrollY),
  );
  expect(doc.t0, 'it must actually have scrolled').toBeGreaterThan(0);
  expect(doc.t150, 'the document scroll had already settled').toBe(doc.t0);

  // (2) nudge -> scrollBy on the rail. THIS is what proves the CSS override:
  //     with only the JS change the rail would still animate. On a FRESH page,
  //     because the chip click above scrolls the document far away and clicking
  //     the arrow would drag it back, re-firing the spy and re-centring the rail.
  const page2 = await ctx.newPage();
  await page2.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const railLeft = () => page2.locator(ORB_RAIL).evaluate((el) => Math.abs(el.scrollLeft));
  const rail = await samples(page2, () => page2.locator(ARROWS).last().click(), railLeft);
  expect(rail.t0, 'the rail must actually have scrolled').toBeGreaterThan(0);
  expect(rail.t150, 'the rail scroll had already settled').toBe(rail.t0);

  RESULTS['B1-M5'] = { doc, rail };
  await ctx.close();
});

test('B1-M5n NEGATIVE CONTROL: without reduced motion those scrolls animate', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const railLeft = () => page.locator(ORB_RAIL).evaluate((el) => Math.abs(el.scrollLeft));
  const rail = await samples(page, () => page.locator(ARROWS).last().click(), railLeft);
  expect(rail.t150, 'a smooth scroll must still be in flight at 150ms').not.toBe(rail.t0);
  expect(rail.t150, 'and it must end up somewhere').toBeGreaterThan(0);
});

// ---------------------------------------------------------------- MAJOR-6

// Both Phase A/B surfaces: the menu route consumes 4 keyframes, the INTRO
// route consumes the other 8 (B1 review MINOR-3 - proving only the menu route
// left the bulk of the co-location fix unexercised).
// INTRO FIRST, deliberately: loading the menu writes sf:v1:seen:<slug>, and the
// intro route then correctly skips itself - so the menu-first order silently
// measured the menu twice and never exercised the 8 Intro keyframes.
// The lively route is the ONLY place sfFloat is reachable: it is gated on
// `.motionLively`, a preset no canonical route uses. Evidence routes cost the
// shipped export nothing, so the 13th keyframe gets real coverage rather than
// a documented gap.
const ANIMATED_ROUTES = ['/s/maps-burger', '/s/maps-burger/menu', '/s/demo-lively/menu'];

test('B1-M6 every consumed animation resolves to a real keyframe', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  const union = { defined: new Set<string>(), used: new Set<string>(), unresolved: [] as string[] };

  for (const route of ANIMATED_ROUTES) {
  await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
  // The language disclosure animates only while open.
  const disclosure = page.locator('details').first();
  if (await disclosure.count()) {
    await disclosure.locator('summary').click().catch(() => undefined);
    await page.waitForTimeout(300);
  }

  const report = await page.evaluate(() => {
    const defined = new Set<string>();
    for (const sheet of Array.from(document.styleSheets)) {
      let rules: CSSRuleList;
      try {
        rules = sheet.cssRules;
      } catch {
        continue;
      }
      const visit = (list: CSSRuleList) => {
        for (const rule of Array.from(list)) {
          if (rule instanceof CSSKeyframesRule) defined.add(rule.name);
          const nested = (rule as CSSGroupingRule).cssRules;
          if (nested) visit(nested);
        }
      };
      visit(rules);
    }
    const used = new Set<string>();
    for (const el of Array.from(document.querySelectorAll('*'))) {
      for (const pseudo of [null, '::before', '::after']) {
        const name = getComputedStyle(el, pseudo).animationName;
        if (name && name !== 'none') for (const n of name.split(',')) used.add(n.trim());
      }
    }
    return {
      defined: [...defined].sort(),
      used: [...used].sort(),
      unresolved: [...used].filter((n) => !defined.has(n)).sort(),
    };
  });

  expect(report.used.length, `${route} must animate something at all`).toBeGreaterThan(0);
  expect(report.unresolved, `${route}: every animation-name needs a matching @keyframes`).toEqual([]);
  for (const d of report.defined) union.defined.add(d);
  for (const u of report.used) union.used.add(u);
  union.unresolved.push(...report.unresolved);
  }

  // ALL 13 consumed Phase A/B animations, across both surfaces.
  expect(union.unresolved, 'no unresolved animation anywhere').toEqual([]);
  expect(union.used.size, 'every consumed keyframe across Phase A + Phase B').toBe(13);
  expect([...union.used].every((u) => union.defined.has(u))).toBe(true);
  // The Intro's own set must genuinely be among them.
  const intro = [...union.used].filter((u) => u.includes('Intro-module'));
  expect(intro.length, 'the Intro keyframes must be exercised, not just the home ones').toBe(8);

  RESULTS['B1-M6'] = {
    defined: [...union.defined].sort(),
    used: [...union.used].sort(),
    unresolved: union.unresolved,
  };
  assertClean('B1-M6', w, await overflow(page));
});

test('B1-M6n NEGATIVE CONTROL: an undefined keyframe name is detectable', async ({ page }) => {
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  // Applied through CSSOM on a throwaway element - the same mechanism ThemeScope
  // uses, and permitted by style-src 'self'. Nothing in the page is mutated.
  const unresolved = await page.evaluate(() => {
    const probe = document.createElement('div');
    probe.style.setProperty('animation-name', 'sfDefinitelyNotDefined');
    document.body.appendChild(probe);
    const name = getComputedStyle(probe).animationName;
    const defined = new Set<string>();
    for (const sheet of Array.from(document.styleSheets)) {
      try {
        for (const rule of Array.from(sheet.cssRules)) {
          if (rule instanceof CSSKeyframesRule) defined.add(rule.name);
        }
      } catch {
        /* cross-origin */
      }
    }
    probe.remove();
    return name !== 'none' && !defined.has(name);
  });
  expect(unresolved, 'the detector must be able to see an unresolved name').toBe(true);
});

// ---------------------------------------------------------------- MAJOR-7

for (const [id, route, width] of [
  ['ar-360', '/s/maps-burger/menu', 360],
  ['he-360', '/he/s/maps-burger/menu', 360],
  ['paused-360', '/s/demo-paused/menu', 360],
] as const) {
  test(`B1-M7 the service strip wraps instead of clipping (${id})`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width, height: 780 });
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);

    const metrics = await page.evaluate(() => {
      const out = {
        clipped: 0,
        count: 0,
        stateRowHeight: 0,
        lineHeight: 0,
        whiteSpace: '',
      };
      for (const el of Array.from(document.querySelectorAll('[class*="serviceMeta"]'))) {
        out.count += 1;
        if (el.scrollWidth > el.clientWidth + 1) out.clipped += 1;
      }
      const row = document.querySelector('[class*="stateRow"]') as HTMLElement | null;
      if (row) {
        out.stateRowHeight = row.getBoundingClientRect().height;
        // Line height from the element that actually lays the text out.
        const meta = row.closest('[class*="serviceMeta"]') as HTMLElement | null;
        const cs = getComputedStyle(meta ?? row);
        const lh = parseFloat(cs.lineHeight);
        out.lineHeight = Number.isFinite(lh) ? lh : parseFloat(cs.fontSize) * 1.25;
        out.whiteSpace = cs.whiteSpace;
      }
      return out;
    });

    expect(metrics.count, 'all three service cells must be present').toBe(3);
    expect(metrics.clipped, 'no service cell may clip its text').toBe(0);
    // B1 review MINOR-4: assert the WRAP, not merely the absence of clipping.
    // A cell that shrank its type, or truncated silently, would also report
    // clipped === 0. The status must occupy more than one line box at 360.
    expect(
      metrics.stateRowHeight,
      'the status must WRAP to at least two lines at 360, not shrink or truncate',
    ).toBeGreaterThan(metrics.lineHeight * 1.5);
    // ...and it must not have been achieved by suppressing wrapping.
    expect(metrics.whiteSpace, 'wrapping must stay enabled').not.toBe('nowrap');

    RESULTS[`B1-M7-${id}`] = metrics;
    assertClean(`B1-M7-${id}`, w, await overflow(page));
  });
}

// ---------------------------------------------------------------- MAJOR-8

test('B1-M8 the rendered DOM carries the locked module order, unnested', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const observed = await page.evaluate(() => {
    const seen: string[] = [];
    for (const el of Array.from(document.querySelectorAll('[data-sf-module]'))) {
      const name = el.getAttribute('data-sf-module')!;
      if (seen[seen.length - 1] !== name) seen.push(name);
    }
    return seen;
  });

  const LOCKED = [
    'announce', 'compact', 'hero', 'service', 'notice',
    'categories', 'promo', 'popular', 'sections', 'story', 'footer',
  ];
  expect(observed.length, 'modules must actually render').toBeGreaterThan(5);
  expect(observed).toEqual(LOCKED.filter((n) => observed.includes(n)));

  // No module may be nested inside another - document order alone would not
  // catch a module that had been moved INSIDE its neighbour.
  const nested = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-sf-module]'))
      .filter((el) => el.parentElement?.closest('[data-sf-module]'))
      .map((el) => el.getAttribute('data-sf-module')),
  );
  expect(nested, 'no module may be nested inside another').toEqual([]);

  RESULTS['B1-M8'] = { observed };
  assertClean('B1-M8', w, await overflow(page));
});

// ---------------------------------------------------------------- MAJOR-9

test('B1-M9 POPULAR_READY=true shows a localized rank, not a bare #n', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const popular = page.locator('[data-sf-module="popular"]');
  await expect(popular).toBeVisible();
  await expect(popular.getByRole('heading')).toHaveText('Most ordered');
  const badges = popular.locator('[data-sf-badge="popularity"]');
  const texts = await badges.allInnerTexts();
  expect(texts.length, 'the ranked rail must carry badges').toBeGreaterThan(0);
  expect(texts[0]).toBe('#1 most ordered');
  expect(texts.some((t) => t.trim() === '#1'), 'a bare #n is the defect').toBe(false);
  // The rank must be readable, not aria-hidden.
  expect(await badges.first().evaluate((el) => el.getAttribute('aria-hidden'))).toBeNull();

  RESULTS['B1-M9-ready'] = { texts };
  assertClean('B1-M9-ready', w, await overflow(page));
});

test('B1-M9 POPULAR_READY=false makes no rank claim and says kitchen pick', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/demo-popular-off/menu`, { waitUntil: 'networkidle' });

  const popular = page.locator('[data-sf-module="popular"]');
  await expect(popular).toBeVisible();
  await expect(popular.getByRole('heading')).toHaveText('Chosen by the kitchen');
  const texts = await popular.locator('[data-sf-badge="popularity"]').allInnerTexts();
  expect(texts.length, 'the unranked rail still carries a badge').toBeGreaterThan(0);
  for (const t of texts) expect(t).toBe('Kitchen pick');
  // The item-truth slot is asserted in the B2 suite; here just prove the two
  // slots are distinct so this assertion cannot be satisfied by either alone.
  expect(await popular.locator('[data-sf-badge="item"]').count()).toBeGreaterThan(0);

  const body = await popular.innerText();
  expect(body, 'no rank number may appear').not.toMatch(/#\d/);
  expect(body, 'no "most ordered" claim may appear').not.toContain('Most ordered');
  expect(body, 'no 30-day window claim may appear').not.toContain('last 30 days');

  RESULTS['B1-M9-unready'] = { texts };
  assertClean('B1-M9-unready', w, await overflow(page));
});

// ------------------------------------------------------- session UI state

test('B1-S1 the intro is shown once per tab, per slug', async ({ browser }) => {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();

  // First visit: the intro renders.
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  expect(page.url()).toContain('/s/maps-burger');

  // The CTA is the only way forward, and reaching home records the flag.
  await page.getByRole('link').filter({ hasText: /.+/ }).last().click();
  await page.waitForURL('**/s/maps-burger/menu');
  await expect(page.locator('[data-sf-module="hero"]')).toBeVisible();

  const keys = await page.evaluate(() => Object.keys(sessionStorage));
  expect(keys).toContain('sf:v1:seen:maps-burger');

  // A HARD navigation back to the intro route skips straight to home.
  await page.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });
  await page.waitForURL('**/s/maps-burger/menu', { timeout: 10_000 });

  // A fresh context is a fresh session: the intro is shown again.
  const ctx2 = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page2 = await ctx2.newPage();
  await page2.goto(`${BASE}/s/maps-burger`, { waitUntil: 'networkidle' });
  await page2.waitForTimeout(500);
  expect(page2.url(), 'a new session must see the intro again').toContain('/s/maps-burger');
  expect(page2.url()).not.toContain('/menu');

  RESULTS['B1-S1'] = { keys };
  await ctx.close();
  await ctx2.close();
});

test('B1-S2 announcement dismissal lasts the session and is per slug', async ({ browser }) => {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();

  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const strip = page.locator('[data-sf-module="announce"]');
  await expect(strip).toBeVisible();
  await strip.getByRole('button').click();
  await expect(strip).toHaveCount(0);

  // It stays dismissed across a reload, in the same tab.
  await page.reload({ waitUntil: 'networkidle' });
  await expect(page.locator('[data-sf-module="announce"]')).toHaveCount(0);

  // A DIFFERENT slug is independent.
  await page.goto(`${BASE}/s/demo-grid/menu`, { waitUntil: 'networkidle' });
  await expect(page.locator('[data-sf-module="announce"]')).toBeVisible();

  // Nothing outside the two approved keys was written, in either store.
  const stored = await page.evaluate(() => ({
    session: Object.keys(sessionStorage),
    local: Object.keys(localStorage),
  }));
  expect(stored.local, 'no long-lived storage may be used').toEqual([]);
  for (const k of stored.session) {
    expect(k, `unexpected session key: ${k}`).toMatch(
      /^sf:v1:(seen|announcement-dismissed):[a-z0-9-]+$/,
    );
  }
  // And the values carry no payload beyond the flag itself.
  const values = await page.evaluate(() =>
    Object.keys(sessionStorage).map((k) => sessionStorage.getItem(k)),
  );
  for (const v of values) expect(v).toBe('1');

  RESULTS['B1-S2'] = stored;
  await ctx.close();
});

// ------------------------------------------------------------- minors

test('B1-D7 rail arrows expose disabled semantics at the ends', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const start = page.locator(ARROWS).first();
  const end = page.locator(ARROWS).last();
  // The rail begins at its inline start: the start arrow can do nothing.
  await expect(start).toBeDisabled();
  await expect(end).toBeEnabled();

  // Scroll it to the far end; the roles reverse.
  await page.locator(ORB_RAIL).evaluate((el) => {
    // CSSOM-View "negative" model: in RTL the valid range is -max..0, so seeking
    // to +max would clamp straight back to the start and prove nothing.
    const max = el.scrollWidth - el.clientWidth;
    el.scrollLeft = getComputedStyle(el).direction === 'rtl' ? -max : max;
  });
  await page.waitForTimeout(250);
  await expect(start).toBeEnabled();
  await expect(end).toBeDisabled();

  RESULTS['B1-D7'] = { ok: true };
  assertClean('B1-D7', w, await overflow(page));
});

test('B1-D1 the closed strip says when it opens, not the full range', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/demo-closed/menu`, { waitUntil: 'networkidle' });
  const strip = page.locator('[data-sf-module="service"]');
  const text = await strip.innerText();
  expect(text).toContain('opens 10:00');
  expect(text, 'the full range belongs to the open and paused states').not.toContain('10:00–23:00');
});

test('B1-D4 the empty menu offers no anchor to nowhere', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/demo-empty/menu`, { waitUntil: 'networkidle' });
  expect(await page.locator('a[href="#"]').count(), 'href="#" is never acceptable').toBe(0);
  const menuButton = page.locator('[data-sf-module="hero"] button').first();
  await expect(menuButton).toBeDisabled();
  assertClean('B1-D4', w, await overflow(page));
});

test('B1-D2 calm keeps the motif but does not animate it', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/demo-calm/menu`, { waitUntil: 'networkidle' });
  const motif = page.locator('[class*="heroMotif"]');
  await expect(motif).toHaveCount(1);
  const anim = await motif.evaluate((el) => getComputedStyle(el).animationName);
  expect(anim).toBe('none');
  // ...and the full preset genuinely does animate, so this discriminates.
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const heroImg = page.locator('[data-sf-module="hero"] img').first();
  expect(await heroImg.evaluate((el) => getComputedStyle(el).animationName)).not.toBe('none');
  assertClean('B1-D2', w, await overflow(page));
});

// ------------------------------------------------------------ screenshots

const SHOT_CASES = [
  { id: 'B1-01-closed-neutral', route: '/s/demo-closed/menu', w: 390, h: 844 },
  { id: 'B1-02-paused-warning', route: '/s/demo-paused/menu', w: 390, h: 844 },
  { id: 'B1-03-promo-hero-ar', route: '/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B1-04-promo-hero-en', route: '/en/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B1-05-service-360-ar', route: '/s/maps-burger/menu', w: 360, h: 780 },
  { id: 'B1-06-service-360-he', route: '/he/s/maps-burger/menu', w: 360, h: 780 },
  { id: 'B1-07-popular-ranked-en', route: '/en/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B1-08-popular-kitchen-pick', route: '/en/s/demo-popular-off/menu', w: 390, h: 844 },
  { id: 'B1-09-calm-keeps-motif', route: '/s/demo-calm/menu', w: 390, h: 844 },
  { id: 'B1-10-empty-menu', route: '/s/demo-empty/menu', w: 390, h: 844 },
  { id: 'B1-11-intro', route: '/s/maps-burger', w: 390, h: 844 },
  { id: 'B1-12-wide', route: '/s/maps-burger/menu', w: 1280, h: 820 },
];

for (const c of SHOT_CASES) {
  test(`SHOT ${c.id}`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width: c.w, height: c.h });
    await page.goto(`${BASE}${c.route}`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(SHOTS, `${c.id}-${c.w}x${c.h}.png`), fullPage: false });
    assertClean(c.id, w, await overflow(page));
  });
}

test('SHOT B1-13-compact-header-expanded', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  await page.evaluate(() => window.scrollTo(0, 600));
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(SHOTS, 'B1-13-compact-header-expanded-390x844.png') });
});
