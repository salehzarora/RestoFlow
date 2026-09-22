// STOREFRONT-UI-001 Phase D evidence, against the REAL exported build.
//
//   G19-G21 / H12-H13   cart populated, empty, notice, blocked
//   G22-G24 / H14-H16   checkout delivery, pickup, zone error, below minimum
//   G25                 payment: cash selected, card an announced dead radio
//   G26-G27 / H17-H18   review, the send spinner, and the four failures
//   G13  / X08-X10      the wide aside on home AND search, and its absence below 900
//   X11  / PG-4         the privacy boundary: where the customer's details are NOT
//   RACE                an older quote may never overwrite a newer one
//
// Everything runs against `npm run build` output served by scripts/serve-out.mjs
// with the COMMITTED vercel.json headers, so the CSP that forbids inline style
// is live for every assertion.
//
// EVERY VALUE TYPED HERE IS SYNTHETIC. No production person, order or credential
// appears in this file or in anything it writes.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_D_PORT ?? 4409);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_D_SHOT_DIR ?? path.join(STOREFRONT, 'ui001d-evidence');
const RESULTS: Record<string, unknown> = {};

const SLUG = 'maps-burger';
const MENU = `/s/${SLUG}/menu`;
const SEARCH = `/s/${SLUG}/search`;
const CART = `/s/${SLUG}/cart`;
const CHECKOUT = `/s/${SLUG}/checkout`;
const PAYMENT = `/s/${SLUG}/payment`;
const REVIEW = `/s/${SLUG}/review`;
const CART_KEY = `sf:v1:cart:${SLUG}`;

/** Synthetic contact details. Every one is a marker we can search sinks for. */
const SYNTH = {
  fullName: 'SYNTHNAME7F3A',
  phone: '052-123-4567',
  area: 'SYNTHAREA9B21',
  street: 'SYNTHSTREET4C88',
  building: 'SYNTHBLD12',
  apartment: 'SYNTHAPT7',
  deliveryNotes: 'SYNTHNOTE5E10',
};
const MARKERS = Object.values(SYNTH).concat('0521234567');

/**
 * The cart behind every canonical cart screenshot: one Maps Classic with
 * brioche and extra cheese, and two crispy fries. 6600 + 4400 = 11000.
 */
const SEED_LINES = [
  { lineId: 'l0aaaa', itemId: '1', qty: 1, selections: { bun: ['brioche'], extras: ['cheese'] }, note: '' },
  { lineId: 'l1bbbb', itemId: '7', qty: 2, selections: {}, note: 'SYNTHKITCHENNOTE' },
];
/** One small line, to fall under the sakhnin minimum of 8000. */
const SMALL_LINES = [{ lineId: 'l0aaaa', itemId: '7', qty: 1, selections: {}, note: '' }];

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
  for (const route of [CART, CHECKOUT, PAYMENT, REVIEW]) {
    const probe = await fetch(`${BASE}${route}`);
    if (!probe.ok) throw new Error(`${route} is missing: ${probe.status}`);
  }
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, 'results.json'), `${JSON.stringify(RESULTS, null, 2)}\n`, 'utf8');
});

/** The phone viewport every canonical screenshot was taken at. */
async function phone(page: Page) {
  await page.setViewportSize({ width: 390, height: 844 });
}

/** The wide viewport the aside is designed for. */
async function wide(page: Page) {
  await page.setViewportSize({ width: 1280, height: 820 });
}

/** Seed a cart as if the visitor had added it on a previous visit. */
async function seedCart(page: Page, lines = SEED_LINES) {
  await page.addInitScript(
    ([key, payload]) => {
      try {
        window.localStorage.setItem(key as string, payload as string);
      } catch {
        /* ignore */
      }
    },
    [CART_KEY, JSON.stringify({ schema: 1, slug: SLUG, menuVersion: 'mb-1', lines })],
  );
}

/** Skip the intro gate so a direct route load lands on the screen itself. */
async function skipIntro(page: Page) {
  await page.addInitScript(
    (key) => {
      try {
        window.sessionStorage.setItem(key as string, '1');
      } catch {
        /* ignore */
      }
    },
    `sf:v1:seen:${SLUG}`,
  );
}

async function box(page: Page, selector: string) {
  const b = await page.locator(selector).first().boundingBox();
  return b === null ? null : { w: Math.round(b.width), h: Math.round(b.height) };
}

/** Fill the details step with synthetic values and continue. */
async function fillDetails(page: Page, opts: { delivery: boolean; zone?: string }) {
  await page.locator(`[data-sf-service="${opts.delivery ? 'delivery' : 'pickup'}"]`).click();
  await page.locator('[data-sf-field="fullName"]').fill(SYNTH.fullName);
  await page.locator('[data-sf-field="phone"]').fill(SYNTH.phone);
  if (opts.delivery) {
    await page.locator('[data-sf-field="zoneId"]').selectOption(opts.zone ?? 'kafrmanda');
    await page.locator('[data-sf-field="area"]').fill(SYNTH.area);
    await page.locator('[data-sf-field="street"]').fill(SYNTH.street);
    await page.locator('[data-sf-field="building"]').fill(SYNTH.building);
    await page.locator('[data-sf-field="apartment"]').fill(SYNTH.apartment);
    await page.locator('[data-sf-field="deliveryNotes"]').fill(SYNTH.deliveryNotes);
  }
}

// =========================================================== CART (G19-G21)

test('D-G19 a populated cart renders the approved anatomy and the right money', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CART}`);

  const lines = page.locator('[data-sf-cart-line]');
  await expect(lines).toHaveCount(2);

  // The header count is UNITS, not lines: 1 + 2 = 3.
  await expect(page.locator('[data-sf-count]')).toHaveText(/3/);

  // 64px thumb, 40px stepper, 44px stepper buttons.
  const measured = {
    thumb: await box(page, '[data-sf-cart-line] span:has(> img), [data-sf-cart-line] > span'),
    stepper: await box(page, '[data-sf-stepper="cart"]'),
    stepperButton: await box(page, '[data-sf-dec]'),
    cta: await box(page, '[data-sf-cta="cart-checkout"]'),
  };
  // The STEPPER is 40px tall; its buttons are 44px wide and fill that height.
  expect(measured.stepper?.h).toBe(40);
  expect(measured.stepperButton?.w).toBe(44);
  expect(measured.cta?.h).toBe(56);

  // The modifier summary uses the MIDDLE DOT and marks the removal, and the
  // kitchen note is shown.
  const mods = await lines.first().locator('div').filter({ hasText: '·' }).first().innerText();
  expect(mods).toContain('·');
  expect(mods).not.toContain('•');
  await expect(page.getByText('SYNTHKITCHENNOTE')).toBeVisible();

  // Totals: pickup, so there is NO delivery-fee row and the tax is 18% of the
  // subtotal alone. 110 / 19.80 / 129.80.
  const totals = await page.locator('[data-sf-totals]').innerText();
  expect(totals).toContain('₪110');
  expect(totals).toContain('₪19.80');
  expect(totals).toContain('₪129.80');
  await expect(page.locator('[data-sf-fee-row]')).toHaveCount(0);

  // The sticky footer CTA carries the TOTAL, not the subtotal.
  await expect(page.locator('[data-sf-cta="cart-checkout"]')).toContainText('₪129.80');

  RESULTS.G19 = { measured, totals: totals.replace(/\s+/g, ' ') };
  await page.screenshot({ path: path.join(SHOTS, 'G19-cart-populated.png'), fullPage: true });
});

test('D-G20 an empty cart drops the totals AND the footer, and offers the menu', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await page.goto(`${BASE}${CART}`);

  await expect(page.locator('[data-sf-empty="cart"]')).toBeVisible();
  // Count BEFORE visibility: an empty locator is invisible too, so asserting
  // visibility alone would pass on a selector that matches nothing.
  await expect(page.locator('[data-sf-totals]')).toHaveCount(0);
  await expect(page.locator('[data-sf-cta="cart-checkout"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(0);
  // The header and its count survive - "0 items", from the same string.
  await expect(page.locator('[data-sf-count]')).toHaveText(/0/);

  await page.screenshot({ path: path.join(SHOTS, 'G20-cart-empty.png'), fullPage: true });

  await page.locator('[data-sf-browse]').click();
  await page.waitForURL(`**${MENU}`);
  RESULTS.G20 = { browsesTo: new URL(page.url()).pathname };
});

test('D-G21 a cart notice tells, acknowledges, and changes NOTHING', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CART}?fx=cart-sold-out`);

  const banner = page.locator('[data-sf-banner="cart-soldOut"]');
  await expect(banner).toBeVisible();
  await expect(banner).toHaveAttribute('role', 'alert');
  await expect(banner).toHaveAttribute('data-sf-tone', 'warn');
  const before = await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY);
  const totalsBefore = await page.locator('[data-sf-totals]').innerText();
  // The sold-out line is NOT removed: a notice tells, it never repairs.
  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(2);

  await page.screenshot({ path: path.join(SHOTS, 'G21-cart-sold-out.png'), fullPage: true });

  await banner.locator('[data-sf-banner-action]').click();
  await expect(banner).toHaveCount(0);
  const after = await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY);
  expect(after).toBe(before);
  expect(await page.locator('[data-sf-totals]').innerText()).toBe(totalsBefore);
  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(2);

  // The other two notices render with their own tone and copy.
  const tones: Record<string, string> = {};
  for (const [fx, id] of [['cart-changed', 'cart-changed'], ['cart-price', 'cart-price']]) {
    await page.goto(`${BASE}${CART}?fx=${fx}`);
    const b = page.locator(`[data-sf-banner="${id}"]`);
    await expect(b).toBeVisible();
    tones[fx] = (await b.getAttribute('data-sf-tone')) ?? '';
    // The price notice states the NEW total, not a fabricated one.
    if (fx === 'cart-price') await expect(b).toContainText('₪129.80');
    await page.screenshot({ path: path.join(SHOTS, `H12-${fx}.png`), fullPage: true });
  }
  RESULTS.G21 = { cartUntouched: after === before, tones };
});

test('D-H12 decrementing below one removes the line, and says so', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CART}`);

  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(2);
  await page.locator('[data-sf-cart-line]').first().locator('[data-sf-dec]').click();
  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(1);

  // textContent, not innerText: the live region is visually clipped, so
  // innerText renders as empty while the accessibility tree still carries it.
  const announced = (await page.locator('[data-sf-announce]').textContent()) ?? '';
  expect(announced.length).toBeGreaterThan(0);
  const region = page.locator('[data-sf-announce]');
  await expect(region).toHaveAttribute('aria-live', 'polite');

  // It is really gone from storage, not just from the screen.
  const stored = await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY);
  expect(JSON.parse(stored ?? '{}').lines).toHaveLength(1);

  // NEGATIVE CONTROL: decrementing a qty-2 line to 1 must NOT remove it.
  await page.locator('[data-sf-cart-line]').first().locator('[data-sf-dec]').click();
  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(1);
  RESULTS.H12 = { announced, removedAtZero: true, keptAtOne: true };
});

test('D-H12b Edit re-opens the sheet pre-filled and REPLACES the line', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CART}`);

  await page.locator('[data-sf-cart-line]').first().locator('[data-sf-item]').click();
  await expect(page.locator('[data-sf-sheet="product"]')).toBeVisible();
  // The URL names BOTH the item and the line, which is what makes the submit a
  // replacement rather than a second line.
  const url = new URL(page.url());
  expect(url.searchParams.get('item')).toBe('1');
  expect(url.searchParams.get('line')).toBe('l0aaaa');

  await page.screenshot({ path: path.join(SHOTS, 'H12b-edit-prefilled.png'), fullPage: true });

  // Submitting REPLACES the line: the cart still has two, not three.
  await page.locator('[data-sf-cta="product"]').click();
  await expect(page.locator('[data-sf-sheet="product"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-cart-line]')).toHaveCount(2);
  const stored = JSON.parse(
    (await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)) ?? '{}',
  );
  expect(stored.lines).toHaveLength(2);
  expect(stored.lines.map((l: { itemId: string }) => l.itemId)).toEqual(['1', '7']);
  RESULTS.H12b = {
    itemParam: url.searchParams.get('item'),
    lineParam: url.searchParams.get('line'),
    replacedRatherThanAppended: true,
  };
});

// ======================================================= CHECKOUT (G22-G24)

test('D-G22 delivery reveals the address block, the zone pill and the fee', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);

  // Pickup first in the DOM, so it paints on the start side.
  const services = page.locator('[data-sf-service]');
  await expect(services).toHaveCount(2);
  expect(await services.first().getAttribute('data-sf-service')).toBe('pickup');
  const card = await box(page, '[data-sf-service="pickup"]');
  expect(card!.h).toBeGreaterThanOrEqual(92);

  await expect(page.locator('[data-sf-address]')).toHaveCount(0);
  await fillDetails(page, { delivery: true });
  await expect(page.locator('[data-sf-address]')).toBeVisible();

  const pill = page.locator('[data-sf-banner="zone-info"]');
  await expect(pill).toBeVisible();
  await expect(pill).toHaveAttribute('data-sf-tone', 'acc');
  await expect(pill).toContainText('₪10');
  await expect(pill).toContainText('₪40');

  // The CTA carries the TOTAL including the fee and the fee-inclusive tax.
  await expect(page.locator('[data-sf-cta="to-payment"]')).toContainText('₪141.60');
  const cta = await box(page, '[data-sf-cta="to-payment"]');
  expect(cta!.h).toBe(54);

  await page.screenshot({ path: path.join(SHOTS, 'G22-checkout-delivery.png'), fullPage: true });
  RESULTS.G22 = { pillTone: 'acc', ctaHeight: cta!.h };
});

test('D-G23 pickup shows contact only, and no address anywhere', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: false });

  await expect(page.locator('[data-sf-address]')).toHaveCount(0);
  for (const field of ['zoneId', 'area', 'street', 'building', 'apartment', 'deliveryNotes']) {
    await expect(page.locator(`[data-sf-field="${field}"]`)).toHaveCount(0);
  }
  await expect(page.locator('[data-sf-cta="to-payment"]')).toContainText('₪129.80');
  await page.screenshot({ path: path.join(SHOTS, 'G23-checkout-pickup.png'), fullPage: true });
  RESULTS.G23 = { addressFieldsWhenPickup: 0 };
});

test('D-G24 an unserved town is a danger pill with one recovery, never a zero fee', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true, zone: 'nazareth' });

  const pill = page.locator('[data-sf-banner="outside-zone"]');
  await expect(pill).toBeVisible();
  await expect(pill).toHaveAttribute('data-sf-tone', 'bad');
  await expect(pill).toHaveAttribute('role', 'alert');
  // Exactly ONE action.
  await expect(pill.locator('[data-sf-banner-action]')).toHaveCount(1);
  // And no fee row and no zero anywhere in the totals the CTA carries.
  const ctaText = await page.locator('[data-sf-cta="to-payment"]').innerText();
  expect(ctaText).toContain('₪129.80');
  expect(ctaText).not.toContain('₪0');

  // A blocked tap dims the CTA but the CTA stays operable, and is never
  // `disabled` - which would take the reason out of the tab order.
  const cta = page.locator('[data-sf-cta="to-payment"]');
  await expect(cta).toHaveAttribute('aria-disabled', 'true');
  expect(await cta.evaluate((el) => (el as HTMLButtonElement).disabled)).toBe(false);
  await cta.click({ force: true });
  await expect(page).toHaveURL(new RegExp(`${CHECKOUT}$`));

  await page.screenshot({ path: path.join(SHOTS, 'G24-checkout-zone-error.png'), fullPage: true });

  // The recovery works, and the zone is DELIBERATELY not cleared.
  await pill.locator('[data-sf-banner-action]').click();
  await expect(page.locator('[data-sf-service="pickup"]')).toHaveAttribute('aria-checked', 'true');
  await expect(page.locator('[data-sf-address]')).toHaveCount(0);
  RESULTS.G24 = { recoversToPickup: true, ctaNativelyDisabled: false };
});

test('D-H15 below the minimum gives the EXACT shortfall and a way to fix it', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page, SMALL_LINES);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true, zone: 'sakhnin' });

  const pill = page.locator('[data-sf-banner="below-minimum"]');
  await expect(pill).toBeVisible();
  await expect(pill).toHaveAttribute('data-sf-tone', 'warn');
  const text = await pill.innerText();
  // subtotal 2200, minimum 8000 -> "add 58 more".
  expect(text).toContain('₪80');
  expect(text).toContain('₪58');

  await page.screenshot({ path: path.join(SHOTS, 'H15-below-minimum.png'), fullPage: true });

  // "add items" leaves for the menu - and the draft must survive the trip,
  // because it lives only in memory.
  await pill.locator('[data-sf-banner-action]').click();
  await page.waitForURL(`**${MENU}`);
  await page.goBack();
  await expect(page.locator('[data-sf-field="fullName"]')).toHaveValue(SYNTH.fullName);
  RESULTS.H15 = { shortfallShown: text.replace(/\s+/g, ' '), draftSurvivedMenuTrip: true };
});

test('D-H14 a blocked tap scrolls to AND focuses the first invalid field', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);

  // Nothing is red before the first blocked tap, even on an empty form.
  await expect(page.locator('[aria-invalid="true"]')).toHaveCount(0);
  const cta = page.locator('[data-sf-cta="to-payment"]');
  await expect(cta).toHaveAttribute('aria-disabled', 'true');

  await cta.click({ force: true });
  await expect(page.locator('[data-sf-field="fullName"]')).toHaveAttribute('aria-invalid', 'true');
  const focused = await page.evaluate(() =>
    document.activeElement?.getAttribute('data-sf-field') ?? document.activeElement?.tagName,
  );
  expect(focused).toBe('fullName');

  // One valid field later, the NEXT one in DOM order takes the focus.
  await page.locator('[data-sf-field="fullName"]').fill(SYNTH.fullName);
  await cta.click({ force: true });
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-field'))).toBe(
    'phone',
  );

  // The phone helper SWAPS to the format mask instead of inventing a sentence.
  await expect(page.locator('[data-sf-phone-help]')).toHaveText('05X-XXX-XXXX');
  await page.screenshot({ path: path.join(SHOTS, 'H14-validation.png'), fullPage: true });
  RESULTS.H14 = { firstFocus: 'fullName', secondFocus: 'phone' };
});

// ========================================================== PAYMENT (G25)

test('D-G25 payment captures nothing; card is visible, announced and dead', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true });
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL(`**${PAYMENT}`);

  await expect(page.locator('[data-sf-method="cash"]')).toHaveAttribute('aria-checked', 'true');
  const card = page.locator('[data-sf-method="card"]');
  await expect(card).toHaveAttribute('aria-checked', 'false');
  await expect(card).toHaveAttribute('aria-disabled', 'true');
  expect(await card.evaluate((el) => el.tagName)).toBe('DIV');
  // Dashed, which is how the design says "not yet".
  expect(await card.evaluate((el) => getComputedStyle(el).borderStyle)).toContain('dashed');

  // THE STEP CAPTURES NOTHING.
  for (const tag of ['input', 'select', 'textarea']) {
    await expect(page.locator(tag)).toHaveCount(0);
  }
  // The timing line never quotes a fee of zero.
  const timing = await page.locator('[data-sf-banner="cash-timing"]').innerText();
  expect(timing).toContain('₪10');
  expect(timing).not.toContain('₪0 ');

  // Progress: segments one and two filled, the second current.
  const steps = page.locator('[data-sf-steps]');
  await expect(steps).toHaveAttribute('data-sf-steps', '1');

  await page.screenshot({ path: path.join(SHOTS, 'G25-payment.png'), fullPage: true });
  RESULTS.G25 = { cardTag: 'DIV', inputsOnPage: 0, timing: timing.replace(/\s+/g, ' ') };
});

test('D-guard a direct load of payment with no details returns to the details step', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${PAYMENT}`);
  await page.waitForURL(`**${CHECKOUT}`, { timeout: 10_000 });
  // And nothing about a previous visitor is on screen.
  await expect(page.locator('[data-sf-field="fullName"]')).toHaveValue('');
  RESULTS.guardPayment = { redirectedTo: new URL(page.url()).pathname };
});

test('D-guard a direct load of the flow with an EMPTY cart returns to the cart', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await page.waitForURL(`**${CART}`, { timeout: 10_000 });
  RESULTS.guardEmptyCart = { redirectedTo: new URL(page.url()).pathname };
});

// ==================================================== REVIEW (G26/G27, H17)

test('D-G26 review reads the request back, then sends with a spinner', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true });
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL(`**${PAYMENT}`);
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL(`**${REVIEW}`);

  // The summary carries "qty x" and the same totals as every other surface.
  await expect(page.getByText('2×')).toBeVisible();
  const totals = await page.locator('[data-sf-totals]').innerText();
  expect(totals).toContain('₪141.60');
  expect(totals).toContain('₪10');

  // Three read-back blocks, each with a NAMED Edit.
  for (const block of ['receive', 'contact', 'payment']) {
    await expect(page.locator(`[data-sf-block="${block}"]`)).toBeVisible();
    const label = await page.locator(`[data-sf-edit="${block}"]`).getAttribute('aria-label');
    expect(label).toMatch(/·/);
  }
  await expect(page.locator('[data-sf-block="contact"]')).toContainText(SYNTH.fullName);
  await expect(page.locator('[data-sf-block="receive"]')).toContainText(SYNTH.street);

  // The truth notice is always there and carries NO action.
  const truth = page.locator('[data-sf-banner="truth-notice"]');
  await expect(truth).toBeVisible();
  await expect(truth.locator('[data-sf-banner-action]')).toHaveCount(0);

  await page.screenshot({ path: path.join(SHOTS, 'G26-review-ready.png'), fullPage: true });

  // Send: the button becomes the spinner and is genuinely inert while in flight.
  const send = page.locator('[data-sf-cta="send"]');
  const started = Date.now();
  await send.click();
  await expect(send).toBeDisabled();
  await page.screenshot({ path: path.join(SHOTS, 'H17-review-sending.png') });
  await expect(send).toBeEnabled({ timeout: 5_000 });
  const elapsed = Date.now() - started;
  expect(elapsed).toBeGreaterThan(700);

  // D does NOT navigate on success: `/r/:ref` is Phase E.
  expect(new URL(page.url()).pathname).toBe(REVIEW);
  RESULTS.G26 = { sendMs: elapsed, stayedOnReview: true };
});

test('D-G27 each send failure renders ONE recovery and preserves everything', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);

  const seen: Record<string, { tone: string; actions: number }> = {};
  for (const [fx, id, actions] of [
    ['offline', 'offline', 1],
    ['server-error', 'server_error', 1],
    ['rate-limited', 'rate_limited', 1],
    ['duplicate', 'duplicate', 0],
  ] as const) {
    await page.goto(`${BASE}${CHECKOUT}?fx=${fx}`);
    await fillDetails(page, { delivery: true });
    await page.locator('[data-sf-cta="to-payment"]').click();
    await page.waitForURL(`**${PAYMENT}**`);
    await page.locator('[data-sf-cta="to-review"]').click();
    await page.waitForURL(`**${REVIEW}**`);

    const cartBefore = await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY);
    await page.locator('[data-sf-cta="send"]').click();
    const banner = page.locator(`[data-sf-banner="${id}"]`);
    await expect(banner).toBeVisible({ timeout: 5_000 });
    await expect(banner).toHaveAttribute('role', 'alert');
    seen[fx] = {
      tone: (await banner.getAttribute('data-sf-tone')) ?? '',
      actions: await banner.locator('[data-sf-banner-action]').count(),
    };
    expect(seen[fx].actions).toBe(actions);

    // The cart is untouched, the details are untouched, and nothing new is
    // written anywhere.
    expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).toBe(cartBefore);
    await expect(page.locator('[data-sf-block="contact"]')).toContainText(SYNTH.fullName);
    const keys = await page.evaluate(() => Object.keys(window.localStorage));
    expect(keys.sort()).toEqual([CART_KEY]);
    await page.screenshot({ path: path.join(SHOTS, `G27-${fx}.png`), fullPage: true });
  }
  RESULTS.G27 = seen;
});

// ==================================================== WIDE (G13, X08-X10)

test('D-G13 the wide aside is live on home AND search, and the dock is gone', async ({ page }) => {
  await wide(page);
  await skipIntro(page);
  await seedCart(page);

  const perRoute: Record<string, unknown> = {};
  for (const route of [MENU, SEARCH]) {
    await page.goto(`${BASE}${route}`);
    const aside = page.locator('[data-sf-aside="live"]');
    await expect(aside).toHaveCount(1);
    await expect(aside).toBeVisible();
    const b = await box(page, '[data-sf-aside="live"]');
    expect(b!.w).toBe(360);

    // Count the dock BEFORE asserting invisibility: an empty locator is
    // invisible too, which is how a dock gate went vacuous once before.
    const dock = page.locator('[data-sf-dock="live"]');
    expect(await dock.count()).toBeLessThanOrEqual(1);
    if (await dock.count()) await expect(dock).toBeHidden();

    await expect(page.locator('[data-sf-aside-line]')).toHaveCount(2);
    const totals = await page.locator('[data-sf-aside-totals]').innerText();
    expect(totals).toContain('₪110');
    expect(totals).toContain('₪129.80');

    // 34px steppers with 36px buttons - the aside's own size, not the page's.
    const stepper = await box(page, '[data-sf-stepper="aside"]');
    const stepperButton = await box(page, '[data-sf-aside-dec]');
    expect(stepper?.h).toBe(34);
    expect(stepperButton?.w).toBe(36);

    perRoute[route] = {
      asideWidth: b!.w,
      stepper,
      stepperButton,
      totals: totals.replace(/\s+/g, ' '),
    };
    await page.screenshot({
      path: path.join(SHOTS, `G13-wide${route.replace(/\//g, '-')}.png`),
      fullPage: false,
    });
  }

  // The aside CTA goes STRAIGHT to checkout: at wide the cart is already shown.
  await page.locator('[data-sf-aside-cta="checkout"]').click();
  await page.waitForURL(`**${CHECKOUT}`);
  RESULTS.G13 = { perRoute, ctaGoesTo: new URL(page.url()).pathname };
});

test('D-X09 the aside steppers are live and agree with the cart page', async ({ page }) => {
  await wide(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${MENU}`);

  await page.locator('[data-sf-aside-line]').first().locator('[data-sf-aside-inc]').click();
  await expect(page.locator('[data-sf-aside-totals]')).toContainText('₪176');
  // The stored cart really moved, and the kitchen note on the OTHER line
  // survived the write.
  const stored = JSON.parse(
    (await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)) ?? '{}',
  );
  expect(stored.lines[0].qty).toBe(2);
  expect(stored.lines[1].note).toBe('SYNTHKITCHENNOTE');

  // Decrementing to zero removes the line here too.
  await page.locator('[data-sf-aside-line]').first().locator('[data-sf-aside-dec]').click();
  await page.locator('[data-sf-aside-line]').first().locator('[data-sf-aside-dec]').click();
  await expect(page.locator('[data-sf-aside-line]')).toHaveCount(1);
  RESULTS.X09 = { stepperWrites: true, notePreserved: true };
});

test('D-X10 the aside shows the delivery fee once a zone is chosen', async ({ page }) => {
  // The prototype's aside omits the fee row while taxing subtotal+fee, so at
  // wide it can print 110 + 21.60 = 141.60. This is the deviation that fixes it.
  await wide(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true });
  // Back to the menu WITHOUT a reload, so the in-memory draft survives.
  await page.locator('[data-sf-back]').click();
  await page.waitForURL(`**${CART}`);
  await page.goto(`${BASE}${MENU}`);

  // A hard navigation drops the draft by design, so re-enter through the flow.
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true });
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL(`**${PAYMENT}`);
  await page.locator('[data-sf-back]').click();
  await page.waitForURL(`**${CHECKOUT}`);
  await page.locator('[data-sf-back]').click();
  await page.waitForURL(`**${CART}`);
  await page.locator('[data-sf-back]').click();
  await page.waitForURL(`**${MENU}`);

  const fee = page.locator('[data-sf-aside-fee]');
  await expect(fee).toHaveCount(1);
  const totals = await page.locator('[data-sf-aside-totals]').innerText();
  expect(totals).toContain('₪10');
  expect(totals).toContain('₪21.60');
  expect(totals).toContain('₪141.60');
  await page.screenshot({ path: path.join(SHOTS, 'X10-aside-with-fee.png') });
  RESULTS.X10 = { totals: totals.replace(/\s+/g, ' ') };
});

test('D-X08 below 900 there is a dock and no VISIBLE aside', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${MENU}`);

  const aside = page.locator('[data-sf-aside="live"]');
  // DOM count, VISIBILITY and LAYOUT recorded separately: the aside is
  // CSS-hidden below 900, which is not the same as absent.
  const domCount = await aside.count();
  const visible = domCount ? await aside.first().isVisible() : false;
  const display = domCount
    ? await aside.first().evaluate((el) => getComputedStyle(el).display)
    : 'absent';
  expect(visible).toBe(false);
  expect(display).toBe('none');

  const dock = page.locator('[data-sf-dock="live"]');
  await expect(dock).toHaveCount(1);
  await expect(dock).toBeVisible();
  await page.locator('[data-sf-dock-cta="cart"]').click();
  await page.waitForURL(`**${CART}`);
  RESULTS.X08 = { asideDomCount: domCount, asideVisible: visible, asideDisplay: display };
});

// ============================================================ PRIVACY (X11)

test('D-X11 the customer details reach NO sink, and die on reload', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page);

  const offOrigin: string[] = [];
  const carrying: string[] = [];
  page.on('request', (req) => {
    const url = req.url();
    if (!url.startsWith(BASE)) offOrigin.push(`${req.method()} ${url}`);
    const body = req.postData() ?? '';
    if (MARKERS.some((mk) => url.includes(mk) || body.includes(mk))) {
      carrying.push(`${req.method()} ${url}`);
    }
  });

  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true });
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL(`**${PAYMENT}`);
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL(`**${REVIEW}`);
  await page.locator('[data-sf-cta="send"]').click();
  await expect(page.locator('[data-sf-cta="send"]')).toBeEnabled({ timeout: 5_000 });

  const leaks = await page.evaluate(async (markers) => {
    const found: Record<string, boolean> = {};
    const hay = (text: string) => markers.some((mk: string) => text.includes(mk));
    const read = (fn: () => string) => {
      try {
        return fn();
      } catch {
        return '';
      }
    };
    found.localStorage = hay(read(() => JSON.stringify(window.localStorage)));
    found.sessionStorage = hay(read(() => JSON.stringify(window.sessionStorage)));
    found.cookie = hay(read(() => document.cookie));
    found.url = hay(window.location.href);
    found.hash = hay(window.location.hash);
    found.historyState = hay(read(() => JSON.stringify(window.history.state ?? null)));
    found.windowName = hay(window.name ?? '');
    found.title = hay(document.title);
    let idb = '';
    try {
      const dbs = (await (indexedDB as unknown as { databases?: () => Promise<unknown[]> })
        .databases?.()) ?? [];
      idb = JSON.stringify(dbs);
    } catch {
      idb = '';
    }
    found.idb = hay(idb) || idb !== '[]';
    return found;
  }, MARKERS);

  for (const [sink, leaked] of Object.entries(leaks)) {
    expect(leaked, `the draft reached ${sink}`).toBe(false);
  }
  expect(offOrigin).toEqual([]);
  expect(carrying).toEqual([]);

  // NEGATIVE CONTROL: the detector really does find a marker when one is there.
  const detects = await page.evaluate((markers) => {
    try {
      window.sessionStorage.setItem('sf-probe', markers[0]);
      const hit = JSON.stringify(window.sessionStorage).includes(markers[0]);
      window.sessionStorage.removeItem('sf-probe');
      return hit;
    } catch {
      return false;
    }
  }, MARKERS);
  expect(detects).toBe(true);

  // A reload kills the draft and keeps the cart. That IS the contract.
  await page.reload();
  const cartStillThere = await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY);
  expect(cartStillThere).not.toBeNull();
  await page.waitForURL(`**${CART}`, { timeout: 10_000 }).catch(() => undefined);
  await page.goto(`${BASE}${CHECKOUT}`);
  await expect(page.locator('[data-sf-field="fullName"]')).toHaveValue('');

  RESULTS.X11 = { leaks, offOrigin, carrying, detectorWorks: detects, cartSurvivedReload: true };
});

// =============================================================== THE RACE

test('D-RACE an older quote never overwrites a newer one', async ({ page }) => {
  await phone(page);
  await skipIntro(page);
  await seedCart(page, SMALL_LINES);
  // Under this seam a SMALLER cart resolves more slowly, so the first request
  // is guaranteed to land after the second.
  await page.goto(`${BASE}${CART}?fx=quote-race`);

  await expect(page.locator('[data-sf-totals]')).toBeVisible({ timeout: 10_000 });
  const inc = page.locator('[data-sf-cart-line]').first().locator('[data-sf-inc]');
  await inc.click();
  await inc.click();
  // qty 3 -> subtotal 6600, tax 1188, total 7788.
  await expect(page.locator('[data-sf-totals]')).toContainText('₪77.88', { timeout: 10_000 });

  // Wait out every slower in-flight request; the stale one must be discarded.
  await page.waitForTimeout(2_500);
  const totals = await page.locator('[data-sf-totals]').innerText();
  expect(totals).toContain('₪77.88');
  expect(totals).not.toContain('₪25.96');
  expect(await page.locator('[data-sf-cart-line]').first().locator('[data-sf-inc]').count()).toBe(1);
  RESULTS.RACE = { finalTotals: totals.replace(/\s+/g, ' ') };
});

// ====================================================== NETWORK HYGIENE

test('D-NET no flow route makes a request that fails', async ({ page }) => {
  /*
   * Phase D introduced the storefront's first `next/link`, and with it Next's
   * viewport prefetch. On a static export that prefetch asks for a PER-SEGMENT
   * RSC payload whose path it spells with dots, while `output: 'export'` writes
   * the same payload as nested directories - so nothing serves it and every
   * prefetch is a 404. It is invisible to a visitor and invisible to every
   * assertion about rendering, which is exactly why it needs its own gate.
   */
  await phone(page);
  await skipIntro(page);
  await seedCart(page);

  const failed: string[] = [];
  page.on('response', (r) => {
    if (r.status() >= 400) failed.push(`${r.status()} ${new URL(r.url()).pathname}`);
  });

  for (const route of [MENU, SEARCH, CART, CHECKOUT]) {
    await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
  }
  // Wide too: that is where the aside's checkout link renders.
  await wide(page);
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);

  expect(failed).toEqual([]);

  // NEGATIVE CONTROL: the watcher really does see a 404 when there is one.
  const probe = await page.evaluate(async (base) => {
    const res = await fetch(`${base}/s/maps-burger/definitely-not-a-route.txt`);
    return res.status;
  }, BASE);
  expect(probe).toBe(404);
  expect(failed.length, 'the watcher must have caught the deliberate one').toBe(1);

  RESULTS.NET = { failedBeforeProbe: [], watcherWorks: true };
});

test('D-NAV a soft navigation still preserves the draft with prefetch off', async ({ page }) => {
  // Turning the prefetch off must not turn a soft navigation into a hard one:
  // a full document load would destroy a draft that lives only in memory.
  await phone(page);
  await skipIntro(page);
  await seedCart(page);
  await page.goto(`${BASE}${CHECKOUT}`);
  await fillDetails(page, { delivery: true });

  // Tag the document. A hard navigation replaces it and the tag is gone.
  await page.evaluate(() => {
    (window as unknown as { __sfSameDocument?: boolean }).__sfSameDocument = true;
  });

  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL(`**${PAYMENT}`);
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL(`**${REVIEW}`);

  const sameDocument = await page.evaluate(
    () => (window as unknown as { __sfSameDocument?: boolean }).__sfSameDocument === true,
  );
  expect(sameDocument, 'the step navigation must stay in ONE document').toBe(true);
  await expect(page.locator('[data-sf-block="contact"]')).toContainText(SYNTH.fullName);
  RESULTS.NAV = { sameDocument };
});
