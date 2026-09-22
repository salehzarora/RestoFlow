// STOREFRONT-UI-001 E - received / status, and the D1 closeout proofs that
// belong to the same finishing stage. Runs against the SHIPPED build
// (SF_EVIDENCE_ROUTES unset); every value typed here is synthetic.
//
//   E-FOCUS  the wide aside's checkout control keeps keyboard focus across a
//            quote settlement (the D1 review's bounded regression), on Home
//            and on Search, and never steals focus that moved elsewhere.
//   G28-G35, H19-H22, E-FLOW, E-PRIVACY  the Phase E cases proper.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_E_PORT ?? 4425);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_E_SHOT_DIR ?? path.join(STOREFRONT, 'ui001e-evidence');
const RESULTS: Record<string, unknown> = {};

const SLUG = 'maps-burger';
const MENU = `/s/${SLUG}/menu`;
const SEARCH = `/s/${SLUG}/search`;
const CHECKOUT = `/s/${SLUG}/checkout`;
const CART_KEY = `sf:v1:cart:${SLUG}`;

const LINES = [
  { lineId: 'e10aaa', itemId: '1', qty: 1, selections: {}, note: '' },
  { lineId: 'e11bbb', itemId: '7', qty: 2, selections: {}, note: '' },
];

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
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, 'results-e.json'), `${JSON.stringify(RESULTS, null, 2)}\n`, 'utf8');
});

async function seed(page: Page, lines = LINES) {
  await page.addInitScript(
    ([key, payload, seen]) => {
      try {
        window.localStorage.setItem(key as string, payload as string);
        window.sessionStorage.setItem(seen as string, '1');
      } catch {
        /* ignore */
      }
    },
    [
      CART_KEY,
      JSON.stringify({ schema: 1, slug: SLUG, menuVersion: 'mb-1', lines }),
      `sf:v1:seen:${SLUG}`,
    ],
  );
}

/** The data-sf-aside-cta value of the focused element, or the tag if unmarked. */
const FOCUSED = () => {
  const el = document.activeElement as HTMLElement | null;
  if (!el) return 'none';
  return el.getAttribute('data-sf-aside-cta') ?? el.tagName.toLowerCase();
};

// ============================================================ E-FOCUS

for (const [surface, route] of [
  ['Home', MENU],
  ['Search', SEARCH],
] as const) {
  test(`E-FOCUS ${surface}: focus placed on the pending checkout control survives settlement, and activation becomes valid only then`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 820 });
    await seed(page);
    // The race source makes the pending window long enough to act in.
    await page.goto(`${BASE}${route}?fx=quote-race`, { waitUntil: 'networkidle' });
    await page.waitForSelector('[data-sf-aside-totals]', { timeout: 15_000 });
    await expect(page.locator('[data-sf-aside-cta="checkout"]')).toHaveCount(1);

    // Tag the document so a full load (which would also drop the memory-only
    // draft) is distinguishable from the soft navigation the control performs.
    await page.evaluate(() => document.documentElement.setAttribute('data-sf-tag', 'kept'));

    // Change the cart -> the quote goes pending -> the control refuses.
    await page.locator('[data-sf-aside-inc]').first().click();
    await page.waitForTimeout(60);
    const pending = page.locator('[data-sf-aside-cta="pending"]');
    await expect(pending).toHaveCount(1);
    await expect(pending).toHaveAttribute('aria-disabled', 'true');
    expect(await pending.evaluate((el) => (el as HTMLButtonElement).disabled)).toBe(false);

    // A keyboard visitor reaches the refusing control and presses it: inert.
    await pending.focus();
    expect(await page.evaluate(FOCUSED)).toBe('pending');
    await page.keyboard.press('Enter');
    await page.keyboard.press('Space');
    await page.waitForTimeout(200);
    expect(new URL(page.url()).pathname, 'pending keyboard activation is inert').toBe(route);
    expect(await page.evaluate(FOCUSED), 'and focus is not moved by the refusal').toBe('pending');

    // The matching total lands. The SAME node is now the live control, and it
    // is still the focused element - nothing restored it, nothing had to.
    await expect(page.locator('[data-sf-aside-cta="checkout"]')).toHaveCount(1, { timeout: 10_000 });
    expect(await page.evaluate(FOCUSED), 'focus survives settlement').toBe('checkout');
    expect(
      await page.evaluate(() => document.activeElement === document.body),
      'focus did NOT fall to body',
    ).toBe(false);

    // Now the same key that was inert a moment ago navigates - softly.
    await page.keyboard.press('Enter');
    await page.waitForURL(`**${CHECKOUT}**`);
    expect(new URL(page.url()).pathname).toBe(CHECKOUT);
    expect(
      await page.evaluate(() => document.documentElement.getAttribute('data-sf-tag')),
      'a soft navigation keeps the document',
    ).toBe('kept');

    RESULTS[`EFOCUS_${surface}`] = { survived: true, landedOn: CHECKOUT, soft: true };
  });
}

test('E-FOCUS settlement never steals focus that the visitor moved elsewhere', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  await page.goto(`${BASE}${SEARCH}?fx=quote-race`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-aside-totals]', { timeout: 15_000 });

  await page.locator('[data-sf-aside-inc]').first().click();
  await page.waitForTimeout(60);
  await expect(page.locator('[data-sf-aside-cta="pending"]')).toHaveCount(1);

  // The visitor goes to the search field while the quote is pending.
  const field = page.locator('input[type="search"], input').first();
  await field.focus();
  expect(await page.evaluate(() => document.activeElement?.tagName)).toBe('INPUT');

  await expect(page.locator('[data-sf-aside-cta="checkout"]')).toHaveCount(1, { timeout: 10_000 });
  await page.waitForTimeout(150);
  expect(await page.evaluate(() => document.activeElement?.tagName), 'focus stays where the visitor put it').toBe(
    'INPUT',
  );
  RESULTS.EFOCUS_noSteal = { stayedOn: 'INPUT' };
});

test('E-FOCUS the hidden narrow aside exposes no focusable checkout control', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await seed(page);
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-dock]', { timeout: 15_000 });

  const probe = await page.evaluate(() => {
    const aside = document.querySelector('[data-sf-aside="live"]') as HTMLElement | null;
    if (!aside) return { present: false };
    const r = aside.getBoundingClientRect();
    const controls = [...aside.querySelectorAll('button, a, input, [tabindex]')] as HTMLElement[];
    const focusable = controls.filter((c) => {
      c.focus();
      return document.activeElement === c;
    });
    return {
      present: true,
      box: { w: Math.round(r.width), h: Math.round(r.height) },
      display: getComputedStyle(aside).display,
      controls: controls.length,
      focusable: focusable.length,
      landmarkExposed: getComputedStyle(aside).display !== 'none',
    };
  });
  expect(probe.present).toBe(true);
  expect(probe.display).toBe('none');
  expect(probe.focusable).toBe(0);
  expect(probe.landmarkExposed).toBe(false);
  RESULTS.EFOCUS_narrow = probe;
});
