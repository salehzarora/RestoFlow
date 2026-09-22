// STOREFRONT-UI-001 D1 targeted proofs, against the SHIPPED build.
//
//   D1-B   the wide aside stepper's EFFECTIVE 44 x 44 hit target
//   D1-C1  progression from the wide aside is blocked while a quote is pending
//
// These measure HIT TESTING and real activation, not computed style. A
// `getComputedStyle(el, '::after')` check would have passed throughout the
// period the overlay was being clipped, which is why the defect survived D.
//
// Every value typed here is synthetic.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_D1_PORT ?? 4415);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_D1_SHOT_DIR ?? path.join(STOREFRONT, 'ui001d1-evidence');
const RESULTS: Record<string, unknown> = {};

const SLUG = 'maps-burger';
const MENU = `/s/${SLUG}/menu`;
const SEARCH = `/s/${SLUG}/search`;
const CHECKOUT = `/s/${SLUG}/checkout`;
const CART_KEY = `sf:v1:cart:${SLUG}`;

const LINES = [
  { lineId: 'd10aaa', itemId: '1', qty: 1, selections: {}, note: '' },
  { lineId: 'd11bbb', itemId: '7', qty: 2, selections: {}, note: '' },
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
  writeFileSync(path.join(SHOTS, 'results-d1.json'), `${JSON.stringify(RESULTS, null, 2)}\n`, 'utf8');
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

/**
 * The effective hit box of a control, probed with elementFromPoint.
 *
 * It walks outward from the centre until the point stops resolving to the
 * control, so the number is what a finger would actually get - not what a
 * stylesheet says.
 */
const PROBE = (selector: string) => {
  const el = document.querySelector(selector) as HTMLElement | null;
  if (!el) return null;
  const r = el.getBoundingClientRect();
  const cx = Math.round(r.left + r.width / 2);
  const cy = Math.round(r.top + r.height / 2);
  const hits = (x: number, y: number) => {
    const found = document.elementFromPoint(x, y);
    return !!found && (found === el || el.contains(found));
  };
  const reach = (dx: number, dy: number) => {
    let n = 0;
    while (n < 60 && hits(cx + dx * (n + 1), cy + dy * (n + 1))) n += 1;
    return n;
  };
  const left = reach(-1, 0);
  const right = reach(1, 0);
  const up = reach(0, -1);
  const down = reach(0, 1);
  return {
    paintedBox: { w: Math.round(r.width), h: Math.round(r.height) },
    effectiveWidth: left + right + 1,
    effectiveHeight: up + down + 1,
    left,
    right,
    up,
    down,
    centreHits: hits(cx, cy),
  };
};

/**
 * What a point resolves to, for the "controls must not steal" check.
 * Serialised into the page, so it must be self-contained.
 */
const AT = ([selector, dx, dy]: [string, number, number]) => {
  const el = document.querySelector(selector) as HTMLElement | null;
  if (!el) return 'missing';
  const r = el.getBoundingClientRect();
  const found = document.elementFromPoint(
    Math.round(r.left + r.width / 2) + dx,
    Math.round(r.top + r.height / 2) + dy,
  );
  if (!found) return 'none';
  const owner = (found as HTMLElement).closest('[data-sf-aside-dec],[data-sf-aside-inc]');
  if (owner) return owner.hasAttribute('data-sf-aside-dec') ? 'DEC' : 'INC';
  return (found as HTMLElement).tagName.toLowerCase();
};

// ============================================================ D1-B hit area

for (const [label, root, dir] of [
  ['AR', '', 'rtl'],
  ['EN', '/en', 'ltr'],
] as const) {
  test(`D1-B ${label} the aside stepper has an EFFECTIVE 44x44 target in both directions`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1280, height: 820 });
    await seed(page);
    await page.goto(`${BASE}${root}${MENU}`, { waitUntil: 'networkidle' });
    await page.waitForSelector('[data-sf-aside-dec]', { timeout: 15_000 });

    expect(await page.evaluate(() => document.documentElement.dir)).toBe(dir);

    const dec = await page.evaluate(PROBE, '[data-sf-aside-dec]');
    const inc = await page.evaluate(PROBE, '[data-sf-aside-inc]');

    // The PAINTED control is UNCHANGED by D1: 36 wide, and 32 tall inside the
    // stepper's 1.5px borders - exactly what the D review recorded as
    // `stepperButton {w:36,h:32}`. Only the hit area moved.
    expect(dec!.paintedBox).toEqual({ w: 36, h: 32 });
    expect(inc!.paintedBox).toEqual({ w: 36, h: 32 });

    // The EFFECTIVE target meets the 44px minimum on both axes.
    expect(dec!.effectiveWidth).toBeGreaterThanOrEqual(44);
    expect(dec!.effectiveHeight).toBeGreaterThanOrEqual(44);
    expect(inc!.effectiveWidth).toBeGreaterThanOrEqual(44);
    expect(inc!.effectiveHeight).toBeGreaterThanOrEqual(44);

    // The stepper itself still paints at its approved height.
    const stepper = await page.locator('[data-sf-stepper="aside"]').first().boundingBox();
    expect(Math.round(stepper!.height)).toBe(34);

    // Neither control steals the other's region, and neither swallows the
    // quantity readout at its centre.
    const probes = {
      decOuter: await page.evaluate(AT, [
        '[data-sf-aside-dec]',
        dir === 'rtl' ? 21 : -21,
        0,
      ] as [string, number, number]),
      incOuter: await page.evaluate(AT, [
        '[data-sf-aside-inc]',
        dir === 'rtl' ? -21 : 21,
        0,
      ] as [string, number, number]),
      decInner: await page.evaluate(AT, [
        '[data-sf-aside-dec]',
        dir === 'rtl' ? -21 : 21,
        0,
      ] as [string, number, number]),
      valueCentre: await page.evaluate(() => {
        const v = document.querySelector('[data-sf-stepper="aside"] span[dir="ltr"]');
        const r = v!.getBoundingClientRect();
        const f = document.elementFromPoint(
          Math.round(r.left + r.width / 2),
          Math.round(r.top + r.height / 2),
        );
        const owner = (f as HTMLElement | null)?.closest(
          '[data-sf-aside-dec],[data-sf-aside-inc]',
        );
        return owner ? 'STOLEN-BY-A-STEPPER-BUTTON' : 'not a control';
      }),
    };
    expect(probes.decOuter, 'the outward extension belongs to DEC').toBe('DEC');
    expect(probes.incOuter, 'the outward extension belongs to INC').toBe('INC');
    expect(probes.decInner, 'DEC must not reach into INC').not.toBe('INC');
    expect(probes.valueCentre).toBe('not a control');

    // No horizontal overflow at wide.
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth > window.innerWidth + 1,
      ),
    ).toBe(false);

    RESULTS[`D1B_${label}`] = { dec, inc, probes, stepperHeight: Math.round(stepper!.height) };
    await page.screenshot({ path: path.join(SHOTS, `D1B-${label}-aside.png`) });
  });
}

test('D1-B a real click inside the extension changes the quantity ONCE, in the right direction', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-aside-dec]', { timeout: 15_000 });

  const qty = () => page.locator('[data-sf-stepper="aside"] span[dir="ltr"]').first().innerText();
  const box = async (sel: string) =>
    (await page.locator(sel).first().boundingBox())!;

  expect((await qty()).trim()).toBe('1');

  // Click 5px OUTSIDE the painted increment button, inside the extension only.
  const incBox = await box('[data-sf-aside-inc]');
  const dir = await page.evaluate(() => document.documentElement.dir);
  const outward = dir === 'rtl' ? -1 : 1;
  await page.mouse.click(
    incBox.x + incBox.width / 2 + outward * (incBox.width / 2 + 5),
    incBox.y + incBox.height / 2,
  );
  await page.waitForTimeout(400);
  expect((await qty()).trim(), 'one click, one increment').toBe('2');

  // And 5px ABOVE the painted button - the axis that was clipped.
  await page.mouse.click(incBox.x + incBox.width / 2, incBox.y - 5);
  await page.waitForTimeout(400);
  expect((await qty()).trim(), 'the vertical extension works too').toBe('3');

  // The decrement extension decrements, it does not increment.
  const decBox = await box('[data-sf-aside-dec]');
  await page.mouse.click(decBox.x + decBox.width / 2, decBox.y + decBox.height + 5);
  await page.waitForTimeout(400);
  expect((await qty()).trim()).toBe('2');

  const stored = JSON.parse(
    (await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)) ?? '{}',
  );
  expect(stored.lines[0].qty).toBe(2);
  RESULTS.D1B_clicks = { finalQty: 2, storedQty: stored.lines[0].qty };
});

test('D1-B NEGATIVE CONTROL: re-introducing the clip makes the same check fail', async ({
  page,
}) => {
  // The defect was a clipped overlay. Re-apply the clip through CSSOM - on a
  // throwaway page, never in the source - and the measurement must collapse.
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-aside-dec]', { timeout: 15_000 });

  const before = await page.evaluate(PROBE, '[data-sf-aside-dec]');
  expect(before!.effectiveHeight).toBeGreaterThanOrEqual(44);

  await page.evaluate(() => {
    const stepper = document.querySelector('[data-sf-stepper="aside"]') as HTMLElement;
    stepper.style.setProperty('overflow', 'hidden');
  });
  const after = await page.evaluate(PROBE, '[data-sf-aside-dec]');

  expect(after!.effectiveHeight, 'the clip must collapse the target').toBeLessThan(44);
  expect(after!.paintedBox, 'and must not move a painted pixel').toEqual(before!.paintedBox);
  RESULTS.D1B_negativeControl = { before, after };
});

// ====================================================== D1-C1 pending gating

test('D1-C1 the wide aside refuses progression while its quote is pending', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  // The race source makes a SMALLER cart resolve more slowly, so the pending
  // window is long enough to act in and an older result lands last.
  await page.goto(`${BASE}${MENU}?fx=quote-race`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-aside-totals]', { timeout: 15_000 });

  const live = page.locator('[data-sf-aside-cta="checkout"]');
  const blocked = page.locator('[data-sf-aside-cta="pending"]');
  await expect(live, 'it starts live').toHaveCount(1);

  await page.locator('[data-sf-aside-inc]').first().click();
  await page.waitForTimeout(80);

  // It is now a refusing control, not a link.
  await expect(blocked).toHaveCount(1);
  await expect(live).toHaveCount(0);
  await expect(blocked).toHaveAttribute('aria-disabled', 'true');
  expect(await blocked.evaluate((el) => el.tagName)).toBe('BUTTON');
  expect(
    await blocked.evaluate((el) => (el as HTMLButtonElement).disabled),
    'never the disabled attribute - the reason must stay reachable',
  ).toBe(false);

  // POINTER activation does not progress. `force` is required because
  // Playwright treats aria-disabled as not-actionable and would wait forever -
  // but a real visitor CAN press this control, which is exactly why it must
  // refuse rather than be `disabled`.
  await blocked.click({ force: true });
  await page.waitForTimeout(250);
  expect(new URL(page.url()).pathname).toBe(MENU);

  // KEYBOARD activation does not progress either.
  await blocked.focus();
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-aside-cta'))).toBe(
    'pending',
  );
  await page.keyboard.press('Enter');
  await page.keyboard.press('Space');
  await page.waitForTimeout(250);
  expect(new URL(page.url()).pathname).toBe(MENU);

  // The page stayed mounted and the cart is intact throughout.
  await expect(page.locator('[data-sf-aside-line]')).toHaveCount(2);

  // Once the matching result lands, progression works again.
  await expect(live).toHaveCount(1, { timeout: 10_000 });
  const totals = await page.locator('[data-sf-aside-totals]').innerText();
  await live.click();
  await page.waitForURL(`**${CHECKOUT}**`);

  RESULTS.D1C1 = {
    blockedWhilePending: true,
    totalsAfterResolve: totals.replace(/\s+/g, ' '),
    landedOn: new URL(page.url()).pathname,
  };
});

test('D1-C1 an older aside result never overwrites a newer one', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  await page.goto(`${BASE}${MENU}?fx=quote-race`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-aside-totals]', { timeout: 15_000 });

  // Two increments in quick succession: under this source the SECOND request is
  // faster, so the first one is guaranteed to land last.
  const inc = page.locator('[data-sf-aside-inc]').first();
  await inc.click();
  await inc.click();

  await expect(page.locator('[data-sf-aside-cta="checkout"]')).toHaveCount(1, { timeout: 10_000 });
  const settled = await page.locator('[data-sf-aside-totals]').innerText();
  // Wait out every slower in-flight request.
  await page.waitForTimeout(2_500);
  const after = await page.locator('[data-sf-aside-totals]').innerText();

  expect(after, 'a late result must not change a settled total').toBe(settled);
  // 3 x 5500 + 2 x 2200 = 20900 -> tax 3762 -> total 24662.
  expect(after).toContain('₪209');
  expect(after).toContain('₪246.62');
  RESULTS.D1C1_race = { settled: settled.replace(/\s+/g, ' ') };
});

test('D1-C1 the head count and the body never contradict each other', async ({ page }) => {
  // Before D1 the count came from the summary and the empty sentence from the
  // quote, so every wide load had a frame reading "3 items" and "your cart is
  // empty" at once. Observed from the first paint.
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  await page.addInitScript(() => {
    (window as unknown as { __f: unknown[] }).__f = [];
    const snap = () => {
      const c = document.querySelector('[data-sf-aside-count]');
      if (!c) return;
      (window as unknown as { __f: unknown[] }).__f.push({
        count: (c.textContent || '').trim(),
        empty: !!document.querySelector('[data-sf-aside-empty]'),
        lines: document.querySelectorAll('[data-sf-aside-line]').length,
      });
    };
    const start = () => {
      snap();
      new MutationObserver(snap).observe(document.documentElement, {
        subtree: true,
        childList: true,
        characterData: true,
      });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
    else start();
  });
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1_200);

  const frames = (await page.evaluate(
    () => (window as unknown as { __f: { count: string; empty: boolean; lines: number }[] }).__f,
  )) as { count: string; empty: boolean; lines: number }[];

  expect(frames.length).toBeGreaterThan(0);
  const contradictory = frames.filter((f) => f.empty && /[1-9]/.test(f.count));
  expect(contradictory, 'no frame may claim items and emptiness at once').toEqual([]);
  RESULTS.D1C1_frames = { frames: frames.length, contradictory: contradictory.length };
});

test('D1-C1 Search gets the same gate, and narrow stays non-interactive', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 820 });
  await seed(page);
  await page.goto(`${BASE}${SEARCH}?fx=quote-race`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-aside-totals]', { timeout: 15_000 });
  await page.locator('[data-sf-aside-inc]').first().click();
  await page.waitForTimeout(80);
  await expect(page.locator('[data-sf-aside-cta="pending"]')).toHaveCount(1);
  await expect(page.locator('[data-sf-aside-cta="checkout"]')).toHaveCount(1, { timeout: 10_000 });

  // Below 900 the aside keeps its DOM node but must reach no one.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  const narrow = await page.evaluate(() => {
    const aside = document.querySelector('[data-sf-aside="live"]') as HTMLElement;
    const controls = aside.querySelectorAll('a[href],button,select,input,textarea');
    const focusable: string[] = [];
    for (const c of Array.from(controls)) {
      (c as HTMLElement).focus();
      if (document.activeElement === c) focusable.push(c.tagName);
    }
    const r = aside.getBoundingClientRect();
    return {
      display: getComputedStyle(aside).display,
      box: { w: Math.round(r.width), h: Math.round(r.height) },
      controlCount: controls.length,
      focusable,
      dock: document.querySelectorAll('[data-sf-dock="live"]').length,
    };
  });
  expect(narrow.display).toBe('none');
  expect(narrow.box).toEqual({ w: 0, h: 0 });
  expect(narrow.focusable, 'nothing in a hidden aside may take focus').toEqual([]);
  expect(narrow.dock).toBe(1);
  RESULTS.D1C1_searchAndNarrow = narrow;
});
