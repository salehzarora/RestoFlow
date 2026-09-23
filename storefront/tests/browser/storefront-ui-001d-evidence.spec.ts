// STOREFRONT-UI-001 Phase D evidence that needs a DEMO ROUTE.
//
//   H13  the cart CTA while ordering is closed or paused
//   H16  the details step with one service switched off
//   H18  the light preset and the calm motion preset, across all four screens
//
// Run against an EVIDENCE build (`SF_EVIDENCE_ROUTES=1 npm run build`). The
// shipped export carries the canonical tenant only, so these routes do not
// exist in it - and the suite refuses to run rather than pass vacuously.
//
// EVERY VALUE TYPED HERE IS SYNTHETIC.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_DE_PORT ?? 4411);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_DE_SHOT_DIR ?? path.join(STOREFRONT, 'ui001d-evidence');
const RESULTS: Record<string, unknown> = {};

/** demo-closed is closed AND has pickup off; demo-paused is paused AND has delivery off. */
const CLOSED = 'demo-closed';
const PAUSED = 'demo-paused';
const LIGHT = 'demo-light';
const CALM = 'demo-calm';

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
  const probe = await fetch(`${BASE}/s/${CLOSED}/cart.html`);
  if (!probe.ok) {
    throw new Error(
      'the Phase D demo routes are absent: rebuild with SF_EVIDENCE_ROUTES=1 before this suite',
    );
  }
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(
    path.join(SHOTS, 'results-evidence.json'),
    `${JSON.stringify(RESULTS, null, 2)}\n`,
    'utf8',
  );
});

async function phone(page: Page) {
  await page.setViewportSize({ width: 390, height: 844 });
}

/**
 * Seed a cart for a demo slug. The demo tenants carry a TRIMMED menu (the
 * first category only), so the seed uses an item that survives the trim.
 */
async function seedCart(page: Page, slug: string) {
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
      `sf:v1:cart:${slug}`,
      JSON.stringify({
        schema: 1,
        slug,
        menuVersion: 'mb-1',
        lines: [{ lineId: 'l0aaaa', itemId: '1', qty: 2, selections: {}, note: '' }],
      }),
      `sf:v1:seen:${slug}`,
    ],
  );
}

test('D-H13 a blocked cart CTA states the reason, keeps the total, and stays reachable', async ({ page }) => {
  await phone(page);
  const states: Record<string, unknown> = {};
  for (const slug of [CLOSED, PAUSED]) {
    await seedCart(page, slug);
    await page.goto(`${BASE}/s/${slug}/cart`);

    const cta = page.locator('[data-sf-cta="cart-checkout"]');
    await expect(cta).toBeVisible();
    const label = (await cta.textContent()) ?? '';

    // NEVER the `disabled` attribute: that removes the control from the tab
    // order and takes the REASON with it, for exactly the visitors who cannot
    // see the dimmed fill.
    expect(await cta.evaluate((el) => (el as HTMLButtonElement).disabled)).toBe(false);
    await expect(cta).toHaveAttribute('aria-disabled', 'true');
    await cta.focus();
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cta'))).toBe(
      'cart-checkout',
    );

    // The label is the reason, and the TOTAL keeps rendering beside it.
    expect(label).toMatch(/₪\s*\d/);
    // Activating it goes nowhere: the reason is the answer.
    await cta.click({ force: true });
    await page.waitForTimeout(300);
    expect(new URL(page.url()).pathname).toBe(`/s/${slug}/cart`);

    // And the lines, the steppers and the totals stay fully interactive:
    // "the cart is preserved" while closed or paused.
    await expect(page.locator('[data-sf-cart-line]')).toHaveCount(1);
    await page.locator('[data-sf-inc]').click();
    await expect(page.locator('[data-sf-cart-line] [data-sf-stepper="cart"]')).toContainText('3');

    states[slug] = { label: label.replace(/\s+/g, ' '), nativelyDisabled: false };
    await page.screenshot({ path: path.join(SHOTS, `H13-${slug}-cart.png`), fullPage: true });
  }
  RESULTS.H13 = states;
});

test('D-H16 a service the restaurant switched off is dimmed, announced and unselectable', async ({ page }) => {
  await phone(page);
  const states: Record<string, unknown> = {};
  // demo-closed has pickupEnabled: false; demo-paused has deliveryEnabled: false.
  for (const [slug, off, on] of [
    [CLOSED, 'pickup', 'delivery'],
    [PAUSED, 'delivery', 'pickup'],
  ] as const) {
    await seedCart(page, slug);
    await page.goto(`${BASE}/s/${slug}/checkout`);

    const dead = page.locator(`[data-sf-service="${off}"]`);
    await expect(dead).toBeVisible();
    await expect(dead).toHaveAttribute('aria-disabled', 'true');
    // Announced, not removed: `disabled` would hide "unavailable now" from the
    // visitors who most need it.
    expect(await dead.evaluate((el) => (el as HTMLButtonElement).disabled)).toBe(false);
    const opacity = await dead.evaluate((el) => getComputedStyle(el).opacity);
    expect(Number(opacity)).toBeLessThanOrEqual(0.55);
    // NO strike-through: that belongs to the home service strip, not here.
    const decoration = await dead.evaluate((el) => getComputedStyle(el).textDecorationLine);
    expect(decoration).not.toContain('line-through');

    // Clicking it changes nothing.
    const checkedBefore = await page.locator(`[data-sf-service="${on}"]`).getAttribute('aria-checked');
    await dead.click({ force: true });
    expect(await dead.getAttribute('aria-checked')).toBe('false');
    expect(await page.locator(`[data-sf-service="${on}"]`).getAttribute('aria-checked')).toBe(
      checkedBefore,
    );

    states[slug] = { off, opacity, strikeThrough: false };
    await page.screenshot({ path: path.join(SHOTS, `H16-${slug}-checkout.png`), fullPage: true });
  }
  RESULTS.H16 = states;
});

test('D-H18 the light preset and calm motion render every flow screen', async ({ page }) => {
  await phone(page);
  const shots: string[] = [];
  for (const slug of [LIGHT, CALM]) {
    await seedCart(page, slug);
    for (const screen of ['cart', 'checkout'] as const) {
      await page.goto(`${BASE}/s/${slug}/${screen}`);
      await expect(page.locator(`[data-sf-screen="${screen}"]`)).toBeVisible();
      // The frame really rendered, not just the skeleton.
      await expect(page.locator('[data-sf-pending]')).toHaveCount(0);
      const name = `H18-${slug}-${screen}.png`;
      await page.screenshot({ path: path.join(SHOTS, name), fullPage: true });
      shots.push(name);
    }
  }

  // Calm means NO animation anywhere on the flow: no sheen on the CTA, no
  // rise on the line cards.
  await seedCart(page, CALM);
  await page.goto(`${BASE}/s/${CALM}/cart`);
  const animated = await page.evaluate(() =>
    Array.from(document.querySelectorAll('*')).filter((el) => {
      const name = getComputedStyle(el).animationName;
      return name !== 'none' && name !== '';
    }).length,
  );
  expect(animated, 'calm motion must animate nothing on the cart').toBe(0);

  // NEGATIVE CONTROL: the default preset DOES animate, so the check above is
  // measuring motion rather than measuring nothing.
  await seedCart(page, LIGHT);
  await page.goto(`${BASE}/s/${LIGHT}/cart`);
  const animatedDefault = await page.evaluate(() =>
    Array.from(document.querySelectorAll('*')).filter((el) => {
      const name = getComputedStyle(el).animationName;
      return name !== 'none' && name !== '';
    }).length,
  );
  expect(animatedDefault, 'the default preset must animate something').toBeGreaterThan(0);

  RESULTS.H18 = { shots, calmAnimations: animated, defaultAnimations: animatedDefault };
});
