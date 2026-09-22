// STOREFRONT-UI-001 D1-C2 — neither fulfilment method available.
//
// This is the one D1 case that needs a rendered tenant, because the defect was
// not in a component but in what the shared validation was never asked. No
// existing demo tenant turns BOTH services off, so `demo-no-service` was added
// to the fixture layer - evidence-only, gated behind SF_EVIDENCE_ROUTES, and
// asserted elsewhere never to reach the shipped export.
//
// Run against an EVIDENCE build (`SF_EVIDENCE_ROUTES=1 npm run build`). The
// suite refuses to run rather than pass vacuously if the route is absent.
//
// Every value typed here is synthetic.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_D1E_PORT ?? 4417);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_D1E_SHOT_DIR ?? path.join(STOREFRONT, 'ui001d1-evidence');
const RESULTS: Record<string, unknown> = {};

const NONE = 'demo-no-service';
const PICKUP_OFF = 'demo-closed'; // pickupEnabled: false, delivery still offered
const DELIVERY_OFF = 'demo-paused'; // deliveryEnabled: false, pickup still offered

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
  const probe = await fetch(`${BASE}/s/${NONE}/checkout.html`);
  if (!probe.ok) {
    throw new Error(
      `the ${NONE} fixture route is absent: rebuild with SF_EVIDENCE_ROUTES=1 before this suite`,
    );
  }
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(
    path.join(SHOTS, 'results-d1-evidence.json'),
    `${JSON.stringify(RESULTS, null, 2)}\n`,
    'utf8',
  );
});

async function seed(page: Page, slug: string) {
  await page.setViewportSize({ width: 390, height: 844 });
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
        lines: [{ lineId: 'd1caaa', itemId: '1', qty: 2, selections: {}, note: '' }],
      }),
      `sf:v1:seen:${slug}`,
    ],
  );
}

test('D1-C2 with NEITHER service available, checkout refuses to progress', async ({ page }) => {
  await seed(page, NONE);
  await page.goto(`${BASE}/s/${NONE}/checkout`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-field="fullName"]', { timeout: 15_000 });

  /*
   * Both cards are announced unavailable, and a tap on either CHANGES NOTHING.
   *
   * Note what is NOT asserted: that neither is checked. The draft arrives on
   * pickup before it can know the tenant, and with both services off nothing
   * moves it - so the pickup card reads as chosen AND unavailable at once.
   * That is the shipped behaviour, recorded rather than papered over; the gate
   * is that it cannot be acted on, which the CTA assertions below prove.
   */
  const cards: Record<string, unknown> = {};
  for (const which of ['pickup', 'delivery'] as const) {
    const card = page.locator(`[data-sf-service="${which}"]`);
    await expect(card).toHaveAttribute('aria-disabled', 'true');
    expect(
      await card.evaluate((el) => (el as HTMLButtonElement).disabled),
      'announced, not removed from the tree',
    ).toBe(false);
    const before = await card.getAttribute('aria-checked');
    await card.click({ force: true });
    const after = await card.getAttribute('aria-checked');
    expect(after, `${which}: a tap on an unavailable card must change nothing`).toBe(before);
    cards[which] = { ariaDisabled: true, ariaChecked: after };
  }
  // The service the restaurant cannot give may never BECOME the chosen one.
  expect(await page.locator('[data-sf-service="delivery"]').getAttribute('aria-checked')).toBe(
    'false',
  );

  // Everything else is filled in correctly, so ONLY availability can block.
  await page.locator('[data-sf-field="fullName"]').fill('RVWNAME-ZZ41');
  await page.locator('[data-sf-field="phone"]').fill('054-987-6543');

  const cta = page.locator('[data-sf-cta="to-payment"]');
  await expect(cta).toHaveAttribute('aria-disabled', 'true');
  expect(
    await cta.evaluate((el) => (el as HTMLButtonElement).disabled),
    'never the disabled attribute',
  ).toBe(false);

  // A forced activation cannot bypass it, and it surfaces the approved message.
  await cta.click({ force: true });
  await page.waitForTimeout(500);
  expect(new URL(page.url()).pathname).toBe(`/s/${NONE}/checkout`);
  await expect(page.locator('[data-sf-service-error]')).toHaveCount(1);
  await expect(page.locator('[data-sf-service-error]')).toHaveAttribute('role', 'alert');

  // The visitor's cart and their typed details are untouched by the refusal.
  await expect(page.locator('[data-sf-field="fullName"]')).toHaveValue('RVWNAME-ZZ41');
  const stored = await page.evaluate(
    (k) => window.localStorage.getItem(k),
    `sf:v1:cart:${NONE}`,
  );
  expect(JSON.parse(stored ?? '{}').lines).toHaveLength(1);

  await page.screenshot({ path: path.join(SHOTS, 'D1C2-no-service-checkout.png'), fullPage: true });
  RESULTS.D1C2_checkout = {
    cards,
    ctaAriaDisabled: true,
    ctaNativelyDisabled: false,
    stayedOnCheckout: true,
    serviceErrorShown: true,
    draftPreserved: 'RVWNAME-ZZ41',
  };
});

test('D1-C2 a direct load of payment or review cannot bypass the same guard', async ({ page }) => {
  await seed(page, NONE);
  const landed: Record<string, string> = {};
  for (const step of ['payment', 'review'] as const) {
    await page.goto(`${BASE}/s/${NONE}/${step}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1_200);
    landed[step] = new URL(page.url()).pathname;
  }
  expect(landed.payment).toBe(`/s/${NONE}/checkout`);
  expect(landed.review).toBe(`/s/${NONE}/checkout`);

  // The cart survived the redirect - a guard must not clear it to pass.
  const stored = await page.evaluate(
    (k) => window.localStorage.getItem(k),
    `sf:v1:cart:${NONE}`,
  );
  expect(JSON.parse(stored ?? '{}').lines).toHaveLength(1);
  RESULTS.D1C2_directRoutes = landed;
});

test('D1-C2 with ONE service available the step moves to it, in either direction', async ({
  page,
}) => {
  // The complement of the rule: a single unavailable service is not a dead end,
  // it is a switch - and the prototype models only one of the two directions.
  const per: Record<string, unknown> = {};
  for (const [slug, off, on] of [
    [PICKUP_OFF, 'pickup', 'delivery'],
    [DELIVERY_OFF, 'delivery', 'pickup'],
  ] as const) {
    await seed(page, slug);
    await page.goto(`${BASE}/s/${slug}/checkout`, { waitUntil: 'networkidle' });
    await page.waitForSelector('[data-sf-field="fullName"]', { timeout: 15_000 });

    // The available one is selected without the visitor doing anything.
    await expect(page.locator(`[data-sf-service="${on}"]`)).toHaveAttribute(
      'aria-checked',
      'true',
    );
    await expect(page.locator(`[data-sf-service="${off}"]`)).toHaveAttribute(
      'aria-checked',
      'false',
    );

    // And with the rest filled in, progression is NOT blocked by availability.
    await page.locator('[data-sf-field="fullName"]').fill('RVWNAME-ZZ41');
    await page.locator('[data-sf-field="phone"]').fill('054-987-6543');
    if (on === 'delivery') {
      await page.locator('[data-sf-field="zoneId"]').selectOption('kafrmanda');
      await page.locator('[data-sf-field="street"]').fill('RVWSTREET-KK9');
      await page.locator('[data-sf-field="building"]').fill('3');
    }
    const cta = page.locator('[data-sf-cta="to-payment"]');
    // Retries: choosing a zone re-quotes, and the CTA is blocked while pending.
    await expect(cta, `${slug}: one available service must not block`).not.toHaveAttribute(
      'aria-disabled',
      'true',
    );
    await expect(page.locator('[data-sf-service-error]')).toHaveCount(0);
    per[slug] = {
      off,
      autoSelected: on,
      ctaAriaDisabled: await cta.getAttribute('aria-disabled'),
    };

    await page.screenshot({
      path: path.join(SHOTS, `D1C2-${slug}-one-service.png`),
      fullPage: true,
    });
  }
  RESULTS.D1C2_oneAvailable = per;
});
