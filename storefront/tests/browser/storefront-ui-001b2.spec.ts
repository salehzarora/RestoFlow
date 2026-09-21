// STOREFRONT-UI-001 Phase B2 correction evidence.
//
//   MAJOR-A  popularity truth and item-badge truth coexist on popular cards
//   MAJOR-B  no structural dir="auto" flip survives anywhere on the surface
//   MINOR-5  ranked assertions strengthened
//   MINOR-7  ready=false proven across the full popular set
//
// Run against an EVIDENCE build (`SF_EVIDENCE_ROUTES=1 npm run build`).
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_B2_PORT ?? 4406);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_B2_SHOT_DIR ?? path.join(STOREFRONT, 'ui001b2-evidence');
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
      if ((await fetch(`${BASE}/healthz.json`)).ok) break;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error('serve-out.mjs did not start');
    await new Promise((r) => setTimeout(r, 200));
  }
  const probe = await fetch(`${BASE}/en/s/demo-popular-off/menu.html`);
  if (!probe.ok) {
    throw new Error('rebuild with SF_EVIDENCE_ROUTES=1 before running the B2 suite');
  }
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, 'b2-browser-results.json'), JSON.stringify(RESULTS, null, 2) + '\n');
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

/** Every popular card, with both badge slots resolved. */
async function popularCards(page: Page) {
  return page.evaluate(() => {
    const section = document.querySelector('[data-sf-module="popular"]');
    if (!section) return [];
    const dir = document.documentElement.dir || 'ltr';
    return Array.from(section.querySelectorAll('[class*="cardMediaPopular"]')).map((media) => {
      const pop = media.querySelector('[data-sf-badge="popularity"]');
      const item = media.querySelector('[data-sf-badge="item"]');
      const box = media.getBoundingClientRect();
      const rect = (el: Element | null) => {
        if (!el) return null;
        const b = el.getBoundingClientRect();
        return { x: b.x, y: b.y, w: b.width, h: b.height, right: b.right, bottom: b.bottom };
      };
      const name =
        media.parentElement?.querySelector('[class*="cardName"]')?.textContent?.trim() ?? '';
      return {
        name,
        dir,
        popularity: pop?.textContent?.trim() ?? null,
        item: item?.textContent?.trim() ?? null,
        popularityBox: rect(pop),
        itemBox: rect(item),
        mediaBox: { x: box.x, y: box.y, w: box.width, h: box.height, right: box.right, bottom: box.bottom },
      };
    });
  });
}

const overlaps = (a: { x: number; right: number; y: number; bottom: number }, b: typeof a) =>
  a.x < b.right && b.x < a.right && a.y < b.bottom && b.y < a.bottom;

// ------------------------------------------------------- MAJOR-A · ranked

test('B2-A1 ranked cards carry BOTH the rank truth and the item badge', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const cards = await popularCards(page);
  expect(cards.length, 'the full popular rail').toBe(4);

  // Every card states its rank, in order, as the localized string.
  expect(cards.map((c) => c.popularity)).toEqual([
    '#1 most ordered',
    '#2 most ordered',
    '#3 most ordered',
    '#4 most ordered',
  ]);

  // The three fixture items that carry their own badge STILL show it.
  const withItemBadge = cards.filter((c) => c.item !== null).map((c) => c.item);
  expect(withItemBadge, 'new/deal truth must survive alongside the rank').toEqual([
    'New',
    'New',
    'Deal',
  ]);
  // ...and the one unbadged item shows no item badge, so this is not blanket.
  expect(cards.filter((c) => c.item === null).length).toBe(1);

  RESULTS['B2-A1'] = cards.map((c) => ({ name: c.name, popularity: c.popularity, item: c.item }));
  assertClean('B2-A1', w, await overflow(page));
});

test('B2-A2 ready=false keeps kitchen-pick AND every item badge, with no rank', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/demo-popular-off/menu`, { waitUntil: 'networkidle' });

  const cards = await popularCards(page);
  // MINOR-7: the full canonical popular set, not a single trimmed card.
  expect(cards.length, 'ready=false must be proven across the full rail').toBe(4);

  for (const c of cards) expect(c.popularity).toBe('Kitchen pick');
  expect(cards.filter((c) => c.item !== null).map((c) => c.item)).toEqual(['New', 'New', 'Deal']);

  const section = await page.locator('[data-sf-module="popular"]').innerText();
  await expect(page.locator('[data-sf-module="popular"]').getByRole('heading')).toHaveText(
    'Chosen by the kitchen',
  );
  expect(section, 'no rank number anywhere').not.toMatch(/#\d/);
  expect(section, 'no most-ordered claim').not.toContain('Most ordered');
  expect(section, 'no 30-day window claim').not.toContain('last 30 days');

  RESULTS['B2-A2'] = cards.map((c) => ({ name: c.name, popularity: c.popularity, item: c.item }));
  assertClean('B2-A2', w, await overflow(page));
});

// ------------------------------------- MAJOR-A · logical placement + overlap

for (const [locale, route, dir] of [
  ['en', '/en/s/maps-burger/menu', 'ltr'],
  ['ar', '/s/maps-burger/menu', 'rtl'],
] as const) {
  test(`B2-A3 badge slots are logical and never overlap (${locale}/${dir})`, async ({ page }) => {
    const w = watch(page);
    for (const width of [360, 390, 430, 834, 1280]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);

      const cards = await popularCards(page);
      expect(cards.length, `${width}px rail`).toBe(4);

      for (const c of cards) {
        expect(c.popularityBox, `${width}px: popularity badge present`).not.toBeNull();
        const pop = c.popularityBox!;
        // Popularity truth hugs the INLINE-START edge of the media.
        const startGap = dir === 'rtl' ? c.mediaBox.right - pop.right : pop.x - c.mediaBox.x;
        expect(startGap, `${width}px ${dir}: popularity badge is inline-start`).toBeLessThan(16);

        if (c.itemBox) {
          // Item truth hugs the INLINE-END edge.
          const endGap = dir === 'rtl' ? c.itemBox.x - c.mediaBox.x : c.mediaBox.right - c.itemBox.right;
          expect(endGap, `${width}px ${dir}: item badge is inline-end`).toBeLessThan(16);
          // And the two must never collide.
          expect(
            overlaps(pop, c.itemBox),
            `${width}px ${dir}: the two badges overlap on "${c.name}"`,
          ).toBe(false);
          // Both stay inside the media box.
          expect(c.itemBox.right).toBeLessThanOrEqual(c.mediaBox.right + 1);
          expect(c.itemBox.bottom).toBeLessThanOrEqual(c.mediaBox.bottom + 1);
        }
      }
    }
    RESULTS[`B2-A3-${locale}`] = 'no overlap at 360/390/430/834/1280';
    assertClean(`B2-A3-${locale}`, w, await overflow(page));
  });
}

test('B2-A4 category sections keep the unchanged single-badge behaviour', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const sections = await page.evaluate(() => {
    const out: { badges: string[]; popularitySlots: number } = { badges: [], popularitySlots: 0 };
    for (const s of Array.from(document.querySelectorAll('[data-sf-module="sections"]'))) {
      for (const b of Array.from(s.querySelectorAll('[data-sf-badge]'))) {
        out.badges.push(b.textContent?.trim() ?? '');
        if (b.getAttribute('data-sf-badge') === 'popularity') out.popularitySlots += 1;
      }
    }
    return out;
  });

  // Category cards carry only their own item truth - no rank leaks into them.
  expect(sections.popularitySlots, 'no popularity badge outside the rail').toBe(0);
  expect(sections.badges.sort()).toEqual(['Deal', 'New', 'New', 'Sold out'].sort());
});

// ------------------------------------------------------------- MAJOR-B

/**
 * The structural-bidi measurement, as a test.
 *
 * An element is UNSAFE when it resolves to the opposite direction from the page
 * AND is a block-level box AND its ink hugs the page's END edge while there is
 * slack at the START edge - i.e. it has flipped away from its neighbours. An
 * INLINE run is safe by construction: its parent decides the ink edge.
 */
async function flippedBlocks(page: Page) {
  return page.evaluate(() => {
    const pageDir = document.documentElement.dir || 'ltr';
    const num = (v: string) => parseFloat(v) || 0;
    const bad: { tag: string; cls: string; text: string; startGap: number; endGap: number }[] = [];
    for (const el of Array.from(document.querySelectorAll('[dir="auto"]'))) {
      const cs = getComputedStyle(el);
      const parent = el.parentElement;
      if (!parent) continue;
      if (cs.display === 'inline') continue; // the approved isolation run
      if (cs.direction === pageDir) continue;

      const pcs = getComputedStyle(parent);
      const pb = parent.getBoundingClientRect();
      const cLeft = pb.x + num(pcs.borderLeftWidth) + num(pcs.paddingLeft);
      const cRight = pb.right - num(pcs.borderRightWidth) - num(pcs.paddingRight);
      if (cRight - cLeft <= 0) continue;

      // Shrink-wrapped boxes are positioned by their PARENT (a flex row, a
      // centred container), so their direction cannot move their ink. Only a
      // box that fills the inline axis resolves text-align against its own
      // direction - that is the defect this detects.
      const own = el.getBoundingClientRect();
      if (own.width < cRight - cLeft - 2) continue;

      const r = document.createRange();
      r.selectNodeContents(el);
      const ink = r.getBoundingClientRect();
      if (ink.width <= 0) continue;

      const startGap = Math.round(pageDir === 'rtl' ? cRight - ink.right : ink.x - cLeft);
      const endGap = Math.round(pageDir === 'rtl' ? ink.x - cLeft : cRight - ink.right);
      if (Math.abs(startGap - endGap) <= 4) continue; // no slack to move into
      if (startGap <= 2) continue; // still hugging the page start - fine

      bad.push({
        tag: el.tagName.toLowerCase(),
        cls: (el.getAttribute('class') ?? '').replace(/[A-Za-z]+-module__[A-Za-z0-9-]+__/g, ''),
        text: (el.textContent ?? '').trim().slice(0, 30),
        startGap,
        endGap,
      });
    }
    return bad;
  });
}

// The critical case: an ENGLISH page carrying Arabic tenant content. That is the
// designed MVP shape (CONTENT_AND_LOCALIZATION.md:3), and it is where a
// block-level dir="auto" visibly detaches text from its own structure.
for (const [id, route] of [
  ['en-home', '/en/s/maps-burger/menu'],
  ['en-closed', '/en/s/demo-closed/menu'],
  ['en-empty', '/en/s/maps-burger/menu'],
  ['ar-home', '/s/maps-burger/menu'],
  ['he-home', '/he/s/maps-burger/menu'],
  ['en-intro', '/en/s/maps-burger'],
] as const) {
  test(`B2-B1 no structural bidi flip on ${id}`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);

    const bad = await flippedBlocks(page);
    expect(
      bad.map((b) => `${b.tag}.${b.cls} "${b.text}" startGap=${b.startGap}`),
      'a block-level dir="auto" has flipped away from its neighbours',
    ).toEqual([]);

    RESULTS[`B2-B1-${id}`] = { flipped: bad.length };
    assertClean(`B2-B1-${id}`, w, await overflow(page));
  });
}

test('B2-B2 NEGATIVE CONTROL: the flip detector can see a flipped block', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  // Reintroduce the defect on a throwaway element, via CSSOM only - the page's
  // own markup is untouched and nothing is written to disk.
  await page.evaluate(() => {
    const host = document.querySelector('[data-sf-module="story"]') as HTMLElement | null;
    if (!host) throw new Error('no story module to probe');
    const probe = document.createElement('p');
    probe.setAttribute('dir', 'auto');
    probe.textContent = 'قصتنا';
    probe.style.setProperty('display', 'block');
    probe.style.setProperty('text-align', 'start');
    host.appendChild(probe);
  });

  const bad = await flippedBlocks(page);
  expect(bad.length, 'the detector MUST see a block-level flip').toBeGreaterThan(0);

  await page.evaluate(() => {
    const host = document.querySelector('[data-sf-module="story"]');
    host?.lastElementChild?.remove();
  });
  expect(await flippedBlocks(page), 'and the real page is clean once removed').toEqual([]);
});

test('B2-B3 the structural alignments the flip used to break', async ({ page }) => {
  const w = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}/en/s/maps-burger/menu`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);

  const aligned = await page.evaluate(() => {
    const inkX = (el: Element | null) => {
      if (!el) return null;
      const r = document.createRange();
      r.selectNodeContents(el);
      const b = r.getBoundingClientRect();
      return b.width > 0 ? b.x : null;
    };
    const section = document.querySelector('[data-sf-module="sections"]')!;
    const bar = section.querySelector('[class*="sectionBar"]')!.getBoundingClientRect();
    const heading = inkX(section.querySelector('[class*="sectionTitle"]'));

    const card = section.querySelector('[class*="cardBody"]')!;
    const name = inkX(card.querySelector('[class*="cardName"]'));
    const foot = card.querySelector('[class*="cardFoot"]')!.getBoundingClientRect();

    const story = document.querySelector('[data-sf-module="story"]')!;
    const storyTitle = inkX(story.querySelector('[class*="storyTitle"]'));
    const pill = story.querySelector('[class*="fact"]')!.getBoundingClientRect();

    const footer = document.querySelector('[data-sf-module="footer"]')!;
    const rows = Array.from(footer.querySelectorAll('[class*="footerRow"]'));
    return {
      headingVsBar: heading === null ? null : Math.round(heading - bar.x),
      nameVsFoot: name === null ? null : Math.round(name - foot.x),
      storyVsPill: storyTitle === null ? null : Math.round(storyTitle - pill.x),
      footerRowXs: rows.map((r) => Math.round(r.getBoundingClientRect().x)),
    };
  });

  // Each of these was hundreds of pixels adrift before B2.
  // The bar is a 5px tile and .sectionHead has a gap, so the heading starts a
  // short, fixed distance after it. Before B2 this was 288px - the heading had
  // detached to the far side of the page.
  expect(aligned.headingVsBar!, 'heading must follow its accent bar').toBeGreaterThan(0);
  expect(aligned.headingVsBar!, 'heading must sit WITH its accent bar').toBeLessThanOrEqual(28);
  expect(Math.abs(aligned.nameVsFoot!), 'card name must sit over its price row').toBeLessThanOrEqual(4);
  expect(Math.abs(aligned.storyVsPill!), 'story copy must sit over its fact pills').toBeLessThanOrEqual(4);
  expect(new Set(aligned.footerRowXs).size, 'all footer rows share one start edge').toBe(1);

  RESULTS['B2-B3'] = aligned;
  assertClean('B2-B3', w, await overflow(page));
});

// ------------------------------------------------------------- MINOR-6

test('B2-M6 the cart dock shows the running subtotal, not the total', async ({ page }) => {
  // 1280 so the cart ASIDE renders too: it lists Subtotal / Tax / Total, which
  // lets the dock be cross-checked against the page's own numbers rather than
  // against a literal a future fixture change would silently invalidate.
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(`${BASE}/en/s/maps-burger/menu`, { waitUntil: 'networkidle' });

  const money = await page.evaluate(() => {
    const dock = document.querySelector('[class*="dockTotal"]')?.textContent?.trim() ?? '';
    const rows: Record<string, string> = {};
    for (const r of Array.from(document.querySelectorAll('[class*="totalRow"]'))) {
      const spans = r.querySelectorAll('span');
      if (spans.length >= 2) rows[spans[0].textContent!.trim()] = spans[1].textContent!.trim();
    }
    return { dock, rows };
  });

  expect(money.rows.Subtotal, 'the aside must state a subtotal').toBeTruthy();
  expect(money.rows.Total, 'the aside must state a total').toBeTruthy();
  // The seeded cart is taxed, so subtotal and total genuinely differ - this
  // assertion can fail if the wrong field is rendered.
  expect(money.rows.Subtotal).not.toBe(money.rows.Total);
  expect(money.dock, 'the dock carries the SUBTOTAL').toBe(money.rows.Subtotal);
  expect(money.dock, 'the dock must not carry the total').not.toBe(money.rows.Total);

  RESULTS['B2-M6'] = money;
});

// ------------------------------------------------------------ screenshots

const SHOT_CASES = [
  { id: 'B2-01-popular-ranked-badges-en', route: '/en/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B2-02-popular-kitchen-badges-en', route: '/en/s/demo-popular-off/menu', w: 390, h: 844 },
  { id: 'B2-03-popular-ranked-badges-ar', route: '/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B2-04-bidi-sections-en', route: '/en/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B2-05-bidi-ar-home', route: '/s/maps-burger/menu', w: 390, h: 844 },
  { id: 'B2-06-360-narrow', route: '/en/s/maps-burger/menu', w: 360, h: 780 },
];

for (const c of SHOT_CASES) {
  test(`SHOT ${c.id}`, async ({ page }) => {
    const w = watch(page);
    await page.setViewportSize({ width: c.w, height: c.h });
    await page.goto(`${BASE}${c.route}`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    if (c.id.includes('popular') || c.id.includes('sections')) {
      await page.evaluate(() => {
        const sel = document.querySelector('[data-sf-module="popular"]')
          ?? document.querySelector('[data-sf-module="sections"]');
        sel?.scrollIntoView({ block: 'start', behavior: 'auto' });
      });
      await page.waitForTimeout(400);
    }
    await page.screenshot({ path: path.join(SHOTS, `${c.id}-${c.w}x${c.h}.png`) });
    assertClean(c.id, w, await overflow(page));
  });
}
