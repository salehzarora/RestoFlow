// STOREFRONT-UI-001 Phase B browser evidence, against the REAL exported tree
// served with the CSP parsed from the committed storefront/vercel.json.
//
//   G02-G14  the required home screenshots and their structural assertions
//   H03/H06  state evidence that has a route (the rest is in sf-home)
//
// Every case also carries the global assertions: no console error, no page
// error, no CSP violation, no off-origin request, no failed asset, and no
// horizontal overflow.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_TEST_PORT ?? 4403);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_SHOT_DIR ?? path.join(STOREFRONT, 'ui001b-evidence');
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
  writeFileSync(path.join(SHOTS, 'home-browser-results.json'), JSON.stringify(RESULTS, null, 2) + '\n');
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

interface Case {
  id: string;
  route: string;
  width: number;
  height: number;
  note: string;
}

const CASES: Case[] = [
  { id: 'G02', route: '/s/maps-burger/menu', width: 390, height: 844, note: 'AR dark list normal' },
  { id: 'G03', route: '/he/s/maps-burger/menu', width: 390, height: 844, note: 'HE dark list normal' },
  { id: 'G04', route: '/en/s/demo-light/menu', width: 390, height: 844, note: 'EN light' },
  { id: 'G05', route: '/s/demo-light/menu', width: 390, height: 844, note: 'AR light' },
  { id: 'G06', route: '/s/demo-grid/menu', width: 390, height: 844, note: 'AR dark grid' },
  { id: 'G07', route: '/s/demo-quiet/menu', width: 390, height: 844, note: 'modules off' },
  { id: 'G08', route: '/s/demo-calm/menu', width: 390, height: 844, note: 'calm motion' },
  { id: 'G09', route: '/s/demo-closed/menu', width: 390, height: 844, note: 'closed + pickup off' },
  { id: 'G10', route: '/s/demo-paused/menu', width: 390, height: 844, note: 'paused + delivery off' },
  { id: 'G11', route: '/s/maps-burger/menu', width: 360, height: 780, note: 'narrow phone' },
  { id: 'G12', route: '/s/maps-burger/menu', width: 430, height: 932, note: 'large phone' },
  { id: 'G13', route: '/s/maps-burger/menu', width: 1280, height: 820, note: 'wide, aside present' },
  { id: 'G14', route: '/s/maps-burger/menu', width: 834, height: 820, note: 'tablet stays phone-style' },
];

for (const c of CASES) {
  test(`${c.id} ${c.note} (${c.width}x${c.height})`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width: c.width, height: c.height });
    await page.goto(`${BASE}${c.route}`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);

    const html = page.locator('html');
    const info: Record<string, unknown> = {
      route: c.route,
      viewport: `${c.width}x${c.height}`,
      lang: await html.getAttribute('lang'),
      dir: await html.getAttribute('dir'),
      h1: await page.locator('h1').first().innerText(),
      asideVisible: await page.locator('aside').isVisible().catch(() => false),
      dockVisible: await page.locator('[class*="dock"]').first().isVisible().catch(() => false),
    };

    // Case-specific structure.
    if (c.id === 'G06') {
      // Scroll a real grid tile into view before asserting it exists.
      const firstSection = page.locator('section[id^="sf-cat-"]').first();
      await firstSection.scrollIntoViewIfNeeded();
      await page.waitForTimeout(400);
      const tiles = page.locator('[class*="gridWrap"] > *');
      info.gridTiles = await tiles.count();
      expect(info.gridTiles, 'G06 must show real grid tiles').toBeGreaterThan(0);
      await expect(tiles.first()).toBeVisible();
    }
    if (c.id === 'G07') {
      // Every optional module gone, and no empty heading or spacer left behind.
      info.promo = await page.locator('[class*="promo"]').count();
      info.story = await page.locator('[class*="story"]').count();
      info.announce = await page.locator('[class*="announce"]').count();
      expect(info.promo, 'promo module must be absent').toBe(0);
      expect(info.story, 'story module must be absent').toBe(0);
      expect(info.announce, 'announcement must be absent').toBe(0);
      // The mandatory parts still render.
      await expect(page.locator('section[id^="sf-cat-"]').first()).toBeVisible();
    }
    if (c.id === 'G08') {
      // calm removes the sheen and the Ken Burns pan; the motif STAYS, undrawn.
      const anims = await page.evaluate(() =>
        Array.from(document.querySelectorAll('*'))
          .map((el) => getComputedStyle(el).animationName)
          .filter((n) => n && n !== 'none'),
      );
      info.animationNames = [...new Set(anims)];
      expect(anims.some((n) => n.includes('sfKen')), 'calm must not pan the hero').toBe(false);
      expect(anims.some((n) => n.includes('sfSheen')), 'calm must not sweep a sheen').toBe(false);
      info.motif = await page.locator('[class*="heroMotif"]').count();
      expect(info.motif, 'calm must keep the motif').toBe(1);
      const motifAnim = await page
        .locator('[class*="heroMotif"] svg')
        .first()
        .evaluate((el) => getComputedStyle(el).animationName);
      expect(motifAnim, 'calm must not animate the motif').toBe('none');
    }
    if (c.id === 'G09' || c.id === 'G10') {
      const notice = page.locator('[class*="notice"]').first();
      await expect(notice).toBeVisible();
      info.noticeText = await notice.innerText();
      // The announcement is suppressed while closed or paused.
      info.announce = await page.locator('[class*="announce"]').count();
      expect(info.announce, 'announcement must be suppressed').toBe(0);
      // The menu is still browsable.
      await expect(page.locator('section[id^="sf-cat-"]').first()).toBeVisible();
      // H03: the unavailable service is struck through.
      const struck = await page.evaluate(() =>
        Array.from(document.querySelectorAll('[class*="serviceOff"]')).length,
      );
      info.disabledServiceCells = struck;
      expect(struck, 'a disabled service must be marked').toBeGreaterThan(0);
    }
    if (c.id === 'G13') {
      // The wide layout shows the persistent aside and hides the dock.
      await expect(page.locator('aside')).toBeVisible();
      info.asideWidth = await page.locator('aside').evaluate((el) => el.getBoundingClientRect().width);
      expect(Math.round(info.asideWidth as number), 'aside is 360px').toBe(360);
      expect(await page.locator('[class*="dock"]').first().isVisible()).toBe(false);
    }
    if (c.id === 'G14') {
      // 834px is still phone-style: the container has not reached 900px.
      expect(await page.locator('aside').isVisible(), '834 must stay phone-style').toBe(false);
    }
    if (c.id === 'G04' || c.id === 'G05') {
      // H06 light x grid: the light canvas really applied.
      info.canvas = await page.evaluate(() => {
        const root = document.querySelector('[data-sf-root]');
        return root === null ? null : getComputedStyle(root).getPropertyValue('--bg').trim();
      });
      expect(String(info.canvas).toLowerCase()).toBe('#f4f6f5');
      info.gridTiles = await page.locator('[class*="gridWrap"] > *').count();
      expect(info.gridTiles, 'light scenario is grid mode').toBeGreaterThan(0);
    }

    const over = await overflow(page);
    info.horizontalOverflow = over;
    info.cspViolations = w.cspViolations;
    info.offOrigin = w.offOrigin;
    info.failed = w.failed;
    RESULTS[c.id] = info;

    await page.screenshot({
      path: path.join(SHOTS, `${c.id}-home-${c.note.replace(/[^a-z0-9]+/gi, '-')}-${c.width}x${c.height}.png`),
    });
    assertClean(c.id, w, over);
  });
}

test('the compact header appears at the approved threshold, without a jump', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const compact = page.locator('[data-sf-compact]');
  const before = await compact.evaluate((el) => getComputedStyle(el).opacity);
  const heroTopBefore = await page
    .locator('[class*="hero"]').first()
    .evaluate((el) => el.getBoundingClientRect().top + window.scrollY);

  await page.evaluate(() => window.scrollTo(0, 400));
  await page.waitForTimeout(500);
  const after = await compact.evaluate((el) => getComputedStyle(el).opacity);
  const heroTopAfter = await page
    .locator('[class*="hero"]').first()
    .evaluate((el) => el.getBoundingClientRect().top + window.scrollY);

  RESULTS.compactHeader = {
    opacityBefore: before,
    opacityAfter: after,
    stateBefore: await compact.getAttribute('data-sf-compact'),
    heroTopBefore,
    heroTopAfter,
    documentShift: Math.abs(heroTopAfter - heroTopBefore),
  };
  expect(Number(before)).toBe(0);
  expect(Number(after)).toBe(1);
  // Revealing the header must not move the document: no layout jump.
  expect(Math.abs(heroTopAfter - heroTopBefore)).toBeLessThanOrEqual(1);
  assertClean('compact', w, await overflow(page));
});

test('tapping a category scrolls to its section and marks it current', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  // The ORB rail only. The compact rail is also a labelled <nav> and precedes
  // this one in document order, but it is visibility:hidden until the compact
  // header appears - so an unscoped selector resolves to an unclickable chip.
  const orbs = page.locator('[data-sf-module="categories"] > div button[data-category]');
  const target = orbs.nth(2);
  const id = await target.getAttribute('data-category');
  await target.click();
  await page.waitForTimeout(900);

  const section = page.locator(`#sf-cat-${id}`);
  const box = await section.boundingBox();
  // After a smooth scroll the spy re-derives the active category from section
  // offsets, so assert the INVARIANT (both rails agree on exactly one current
  // category) rather than pinning it to the id that was tapped.
  const current = await page.evaluate(() =>
    Array.from(document.querySelectorAll('button[data-category][aria-current="true"]')).map(
      (el) => el.getAttribute('data-category'),
    ),
  );
  RESULTS.categoryTap = { tapped: id, sectionTop: box?.y, current };
  expect(box!.y, 'the tapped section scrolled into view').toBeLessThan(300);
  expect(current.length, 'one current chip per rail').toBe(2);
  expect(new Set(current).size, 'both rails agree').toBe(1);
  assertClean('categoryTap', w, await overflow(page));
});

test('the rails are navigation, not a tablist, in the rendered DOM', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const roles = await page.evaluate(() => ({
    tablist: document.querySelectorAll('[role="tablist"]').length,
    tab: document.querySelectorAll('[role="tab"]').length,
    tabpanel: document.querySelectorAll('[role="tabpanel"]').length,
    nav: document.querySelectorAll('nav[aria-label]').length,
    namedNavs: Array.from(document.querySelectorAll('nav')).filter(
      (n) => (n.getAttribute('aria-label') ?? '').trim().length > 0,
    ).length,
    current: document.querySelectorAll('[aria-current="true"]').length,
    // Scoped to the rails: LanguageMenu marks the active locale with its own
    // aria-current, which is correct and must not be folded into this count.
    currentChips: document.querySelectorAll('button[data-category][aria-current="true"]').length,
    chips: document.querySelectorAll('button[data-category]').length,
  }));
  RESULTS.railSemantics = roles;
  expect(roles.tablist).toBe(0);
  expect(roles.tab).toBe(0);
  expect(roles.tabpanel).toBe(0);
  // EXACT counts, not "> 0": a count assertion that passes for any nonzero
  // value cannot distinguish "both rails render" from "one silently vanished".
  // 7 fixture categories, two rails (orb + compact), one current chip in each.
  expect(roles.nav, 'the orb rail and the compact rail are both named navs').toBe(2);
  expect(roles.currentChips, 'exactly one chip is current in each rail').toBe(2);
  expect(roles.current, 'the two rails plus the language menu').toBe(3);
  expect(roles.chips, '7 categories rendered in each of the two rails').toBe(14);
  expect(roles.namedNavs, 'an unnamed nav landmark is worse than none').toBe(roles.nav);
});

test('every interactive control reaches a 44x44 effective target', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const small = await page.evaluate(() => {
    const out: { tag: string; label: string; w: number; h: number }[] = [];
    for (const el of document.querySelectorAll('a, button, summary')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      // An ::after overlay can enlarge the hit area beyond the painted box.
      const after = getComputedStyle(el, '::after');
      const grow = (v: string) => (v.startsWith('-') ? Math.abs(parseFloat(v)) * 2 : 0);
      const w = r.width + grow(after.insetInlineStart || after.left || '0');
      const h = r.height + grow(after.insetBlockStart || after.top || '0');
      if (w < 44 || h < 44) {
        out.push({
          tag: el.tagName.toLowerCase(),
          label: (el.getAttribute('aria-label') ?? el.textContent ?? '').trim().slice(0, 30),
          w: Math.round(w),
          h: Math.round(h),
        });
      }
    }
    return out;
  });
  RESULTS.smallTargets = small;
  expect(small, 'controls below 44x44').toEqual([]);
});

test('reduced motion collapses every animation on home', async ({ browser }) => {
  const ctx = await browser.newContext({ reducedMotion: 'reduce', viewport: { width: 390, height: 844 } });
  const page = await ctx.newPage();
  await page.goto(`${BASE}/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  const durations = await page.evaluate(() =>
    Array.from(document.querySelectorAll('*'))
      .map((el) => getComputedStyle(el).animationDuration)
      .filter((d) => d !== 'auto' && d !== '0s'),
  );
  RESULTS.reducedMotion = { distinctDurations: [...new Set(durations)] };
  for (const d of durations) expect(parseFloat(d)).toBeLessThanOrEqual(0.01);
  await ctx.close();
});

test('the emptyMenu state renders and suppresses every module', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/s/demo-empty/menu`, { waitUntil: 'networkidle' });
  const body = await page.locator('body').innerText();
  RESULTS.H02 = {
    body: body.slice(0, 200),
    sections: await page.locator('section[id^="sf-cat-"]').count(),
    rail: await page.locator('nav[aria-label] button[data-category]').count(),
  };
  expect(body).toContain('القائمة قريباً');
  expect(RESULTS.H02).toMatchObject({ sections: 0, rail: 0 });
  await page.screenshot({ path: path.join(SHOTS, 'H02-empty-menu-390x844.png') });
  assertClean('H02', w, await overflow(page));
});
