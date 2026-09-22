// STOREFRONT-UI-001 G - the final local correction pass, against an EVIDENCE
// build (SF_EVIDENCE_ROUTES=1: the closed / paused demo slugs are needed).
// Every value typed here is synthetic.
//
//   G-ORD    the ordering contract: exactly 'open' authorises a step or a
//            send; closed / paused refuse in place with the localised reason,
//            keep the cart and the typed draft, and admit the same input once
//            ordering reopens; the send checks readiness at ACTIVATION and the
//            fixture gateway at its COMMIT instant; a request accepted before
//            a close is never erased by it.
//   G-H01    the intro's closed / paused / pickupOff / deliveryOff states.
//   G-GLASS  the approved glass is REAL in the built output: a non-none
//            computed backdrop-filter on every consumer, in this engine.
//   G-FONTS  two preloaded subsets per document, the right ones per root, the
//            on-demand subsets fetched when their script appears, and the
//            layout shift the swap causes, measured.
//   G-CHAT   every simulated launch is answered through the demo disclosure's
//            live region; nothing leaves the page.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_G_PORT ?? 4437);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_G_SHOT_DIR ?? path.join(STOREFRONT, 'ui001g-evidence');
const RESULTS: Record<string, unknown> = {};

const OPEN = 'maps-burger';
const CLOSED = 'demo-closed'; // closed AND pickup off
const PAUSED = 'demo-paused'; // paused AND delivery off
const REF = 'DEMO-7K4XM2D9P3';
const REQUEST = `/r/${REF}`;
const AR = JSON.parse(readFileSync(path.join(STOREFRONT, 'messages/storefront.ar.json'), 'utf8'));
const OPENS_AT = '10:00';
const CLOSED_REASON = (AR.orderingClosed as string).replace('{t}', OPENS_AT);
const PAUSED_REASON = AR.orderingPaused as string;

const SYNTH = { fullName: 'SYNTHNAME7F3A', phone: '052-123-4567', area: 'SYNTHAREA9B21', street: 'SYNTHSTREET4C88', building: 'SYNTHBLD12', apartment: 'SYNTHAPT7', deliveryNotes: 'SYNTHNOTE5E10' };
const MARKERS = Object.values(SYNTH).concat('0521234567');
const LINES = [
  { lineId: 'g1aaaa', itemId: '1', qty: 1, selections: { bun: ['brioche'], extras: ['cheese'], remove: ['onion'] }, note: '' },
  { lineId: 'g2bbbb', itemId: '7', qty: 2, selections: { sauce: ['garlic'] }, note: '' },
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
  if (!(await fetch(`${BASE}/s/${CLOSED}/checkout.html`)).ok) {
    throw new Error('the closed / paused demo routes are absent: rebuild with SF_EVIDENCE_ROUTES=1 before this suite');
  }
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, 'results-g.json'), `${JSON.stringify(RESULTS, null, 2)}\n`, 'utf8');
});

// ---------------------------------------------------------------- helpers

interface Watch { errors: string[]; offOrigin: string[]; popups: number; navigations: string[] }
const WATCHES = new WeakMap<Page, Watch>();
function watch(page: Page): Watch {
  const w: Watch = { errors: [], offOrigin: [], popups: 0, navigations: [] };
  page.on('console', (m) => { if (m.type() === 'error') w.errors.push(m.text()); });
  page.on('pageerror', (e) => w.errors.push(String(e)));
  page.on('request', (req) => { if (!req.url().startsWith(BASE)) w.offOrigin.push(`${req.method()} ${req.url()}`); });
  page.on('popup', () => { w.popups += 1; });
  page.context().on('page', () => { w.popups += 1; });
  page.on('framenavigated', (f) => { if (f === page.mainFrame()) w.navigations.push(f.url()); });
  WATCHES.set(page, w);
  return w;
}
test.beforeEach(({ page }) => { watch(page); });
test.afterEach(({ page }, info) => {
  const w = WATCHES.get(page)!;
  // The 404 document is loaded on purpose in one case; Chromium reports that
  // response as a console error. Nothing else is tolerated.
  const errors = w.errors.filter((e) => !(info.title.includes('404 document') && /404/.test(e)));
  expect(errors, 'console / page errors').toEqual([]);
  expect(w.offOrigin, 'off-origin requests').toEqual([]);
  expect(w.popups, 'popups').toBe(0);
});

async function phone(page: Page) { await page.setViewportSize({ width: 390, height: 844 }); }

async function seed(page: Page, slug: string, lines = LINES) {
  await page.addInitScript(
    ([key, payload, seen]) => {
      try {
        window.localStorage.setItem(key as string, payload as string);
        window.sessionStorage.setItem(seen as string, '1');
      } catch { /* ignore */ }
    },
    [`sf:v1:cart:${slug}`, JSON.stringify({ schema: 1, slug, menuVersion: 'mb-1', lines }), `sf:v1:seen:${slug}`],
  );
}

async function fillDetails(page: Page, service: 'pickup' | 'delivery') {
  await page.locator(`[data-sf-service="${service}"]`).click();
  await page.locator('[data-sf-field="fullName"]').fill(SYNTH.fullName);
  await page.locator('[data-sf-field="phone"]').fill(SYNTH.phone);
  if (service === 'delivery') {
    await page.locator('[data-sf-field="zoneId"]').selectOption('kafrmanda');
    await page.locator('[data-sf-field="area"]').fill(SYNTH.area);
    await page.locator('[data-sf-field="street"]').fill(SYNTH.street);
    await page.locator('[data-sf-field="building"]').fill(SYNTH.building);
  }
}

/** Freeze the installed clock right after a load; return fake ms since t0 (must be small). */
async function freezeAfterLoad(page: Page, t0: number): Promise<number> {
  const now = await page.evaluate(() => Date.now());
  await page.clock.pauseAt(now + 50);
  const since = now + 50 - t0;
  expect(since, 'the load must finish well before the fixture flips readiness').toBeLessThan(1_200);
  return since;
}

/** Pointer, Enter, Space and a forced DOM click on a control, in turn. */
async function activateEveryWay(page: Page, selector: string) {
  const el = page.locator(selector);
  await el.click({ force: true });
  await el.focus();
  await page.keyboard.press('Enter');
  await page.keyboard.press('Space');
  await page.evaluate((sel) => (document.querySelector(sel) as HTMLElement).click(), selector);
}

const attempts = (page: Page) => page.locator('[data-sf-screen="review"]').getAttribute('data-sf-send-attempts');
const fieldValues = (page: Page) => page.evaluate(() => Object.fromEntries([...document.querySelectorAll('[data-sf-field]')].map((f) => [f.getAttribute('data-sf-field'), (f as HTMLInputElement).value])));

// ============================================================ G-ORD

test('G-ORD open: the positive control - the whole flow proceeds and exactly one gateway call is made', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  await page.goto(`${BASE}/s/${OPEN}/checkout`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await expect(page.locator('[data-sf-cta="to-payment"]')).toContainText(AR.stepPayment);
  await fillDetails(page, 'pickup');
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await expect(page.locator('[data-sf-cta="to-review"]')).toContainText(AR.reviewCta);
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await expect(page.locator('[data-sf-cta="send"]')).toContainText(AR.sendRequest);
  expect(await attempts(page)).toBe('0');
  await page.locator('[data-sf-cta="send"]').click();
  await page.waitForURL(`**${REQUEST}**`, { timeout: 20_000 });
  await page.waitForSelector('[data-sf-screen="received"]');
  RESULTS.G_ORD_open = { reached: 'received', attempts: 1 };
});

for (const [slug, reason, service, word] of [
  [CLOSED, CLOSED_REASON, 'delivery', 'closed'],
  [PAUSED, PAUSED_REASON, 'pickup', 'paused'],
] as const) {
  test(`G-ORD ${word}: a direct checkout visit with a valid cart stays put, states the reason, keeps the draft, and no activation progresses`, async ({ page }) => {
    await phone(page);
    await seed(page, slug);
    const w = WATCHES.get(page)!;
    await page.goto(`${BASE}/s/${slug}/checkout`, { waitUntil: 'networkidle' });
    await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
    // No redirect, no loop: the only navigation is the one the test made.
    await page.waitForTimeout(1_500);
    expect(new URL(page.url()).pathname).toBe(`/s/${slug}/checkout`);
    expect(w.navigations.filter((u) => !u.endsWith(`/s/${slug}/checkout`)), 'no redirect away from checkout').toEqual([]);
    const cta = page.locator('[data-sf-cta="to-payment"]');
    await expect(cta).toContainText(reason);
    await expect(cta).toHaveAttribute('aria-disabled', 'true');
    // The form is still a form: the visitor can type, and the value stays.
    await fillDetails(page, service);
    const before = await fieldValues(page);
    expect(before.fullName).toBe(SYNTH.fullName);
    await activateEveryWay(page, '[data-sf-cta="to-payment"]');
    await page.waitForTimeout(400);
    expect(new URL(page.url()).pathname, 'no activation reaches payment').toBe(`/s/${slug}/checkout`);
    expect(await fieldValues(page), 'the typed draft is untouched by the refusal').toEqual(before);
    expect(await page.evaluate((k) => window.localStorage.getItem(k), `sf:v1:cart:${slug}`), 'the cart is untouched').not.toBeNull();
    // The cart step states the same reason on its own control (H13).
    await page.goto(`${BASE}/s/${slug}/cart`, { waitUntil: 'networkidle' });
    await page.waitForSelector('[data-sf-screen="cart"]:not([data-sf-pending])');
    await expect(page.locator('[data-sf-cta="cart-checkout"]')).toContainText(reason);
    await expect(page.locator('[data-sf-cta="cart-checkout"]')).toHaveAttribute('aria-disabled', 'true');
    RESULTS[`G_ORD_${word}_direct`] = { reason, stayed: true };
    await page.screenshot({ path: path.join(SHOTS, `G-ORD-${word}-checkout-ar-390.png`), fullPage: true });
  });

  test(`G-ORD ${word}: direct payment and review visits land on the first missing step and show the reason there - never a payment or review step`, async ({ page }) => {
    await phone(page);
    await seed(page, slug);
    for (const step of ['payment', 'review']) {
      await page.goto(`${BASE}/s/${slug}/${step}`, { waitUntil: 'networkidle' });
      await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])', { timeout: 15_000 });
      expect(new URL(page.url()).pathname).toBe(`/s/${slug}/checkout`);
      await expect(page.locator('[data-sf-cta="to-payment"]')).toContainText(reason);
    }
    RESULTS[`G_ORD_${word}_deep`] = { landedOn: 'checkout' };
  });
}

test('G-ORD closes-late: open at entry, closed before the send - the send is refused at activation with the reason, zero gateway calls, input intact', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await page.goto(`${BASE}/s/${OPEN}/checkout?fx=closes-late`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await freezeAfterLoad(page, T0);
  await expect(page.locator('[data-sf-cta="to-payment"]')).toContainText(AR.stepPayment);
  await fillDetails(page, 'pickup');
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.waitForSelector('[data-sf-cta="send"]');
  await expect(page.locator('[data-sf-cta="send"]')).toContainText(AR.sendRequest);
  // The restaurant closes now (the fixture's readiness feed, 1.5 s after the
  // review step mounted). The same document, the same draft.
  await page.clock.runFor(1_600);
  await expect(page.locator('[data-sf-cta="send"]')).toContainText(CLOSED_REASON);
  await expect(page.locator('[data-sf-cta="send"]')).toHaveAttribute('aria-disabled', 'true');
  await activateEveryWay(page, '[data-sf-cta="send"]');
  await page.clock.runFor(1_000);
  await page.waitForTimeout(300);
  expect(await attempts(page), 'zero gateway calls').toBe('0');
  await expect(page.locator('[data-sf-cta="send"]')).not.toContainText(AR.sending);
  expect(new URL(page.url()).pathname).toBe(`/s/${OPEN}/review`);
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(0);
  // Back to the details (two history entries): the typed draft survived.
  await page.goBack();
  await page.goBack();
  await page.waitForURL('**/checkout**');
  await page.waitForSelector('[data-sf-field="fullName"]');
  expect((await fieldValues(page)).fullName).toBe(SYNTH.fullName);
  RESULTS.G_ORD_closes_late = { refusedAtActivation: true, attempts: 0, draftKept: true };
  await page.screenshot({ path: path.join(SHOTS, 'G-ORD-closes-late-review-ar-390.png'), fullPage: true });
});

test('G-ORD pauses-late: the same refusal with the paused reason', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await page.goto(`${BASE}/s/${OPEN}/payment?fx=pauses-late`, { waitUntil: 'networkidle' });
  // An empty draft lands on checkout first (the prerequisite guard); fill it.
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await freezeAfterLoad(page, T0);
  await fillDetails(page, 'pickup');
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await expect(page.locator('[data-sf-cta="to-review"]')).toContainText(AR.reviewCta);
  await page.clock.runFor(1_600);
  await expect(page.locator('[data-sf-cta="to-review"]')).toContainText(PAUSED_REASON);
  await activateEveryWay(page, '[data-sf-cta="to-review"]');
  await page.waitForTimeout(300);
  expect(new URL(page.url()).pathname).toBe(`/s/${OPEN}/payment`);
  RESULTS.G_ORD_pauses_late = { refused: true };
});

test('G-ORD opens-late: closed at entry, then the restaurant opens - the SAME typed input proceeds through the normal valid flow', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await page.goto(`${BASE}/s/${OPEN}/checkout?fx=opens-late`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await freezeAfterLoad(page, T0);
  const cta = page.locator('[data-sf-cta="to-payment"]');
  await expect(cta).toContainText(CLOSED_REASON);
  await fillDetails(page, 'pickup');
  await activateEveryWay(page, '[data-sf-cta="to-payment"]');
  await page.waitForTimeout(300);
  expect(new URL(page.url()).pathname).toBe(`/s/${OPEN}/checkout`);
  const typed = await fieldValues(page);
  // Reopening: no reload, no retyping.
  await page.clock.runFor(1_600);
  await expect(cta).toContainText(AR.stepPayment);
  await expect(cta).not.toHaveAttribute('aria-disabled', 'true');
  expect(await fieldValues(page)).toEqual(typed);
  await cta.click();
  await page.waitForURL('**/payment**');
  // Every step mount replays the fixture scenario (closed, then open at
  // 1.5 s): a real feed would not, a fixture that flips once per document
  // mount is what makes the proof reproducible on each step.
  await page.clock.runFor(1_600);
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.clock.runFor(1_600);
  await expect(page.locator('[data-sf-cta="send"]')).toContainText(AR.sendRequest);
  await page.locator('[data-sf-cta="send"]').click();
  await page.clock.runFor(900);
  await page.waitForURL(`**${REQUEST}**`, { timeout: 20_000 });
  await page.waitForSelector('[data-sf-screen="received"]');
  RESULTS.G_ORD_opens_late = { reached: 'received' };
});

test('G-ORD commit: a send activated while open but committed after the close is refused by the gateway with the reason - nothing created, input intact', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await page.goto(`${BASE}/s/${OPEN}/checkout?fx=closes-late`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await freezeAfterLoad(page, T0);
  await fillDetails(page, 'pickup');
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.waitForSelector('[data-sf-cta="send"]');
  // 1.0 s into the review mount the restaurant is still open: the send is
  // activated (one gateway call). It commits 0.9 s later - after the 1.5 s
  // close - so the gateway refuses it with the reason.
  await page.clock.runFor(1_000);
  await page.locator('[data-sf-cta="send"]').click();
  await expect(page.locator('[data-sf-cta="send"]')).toContainText(AR.sending);
  expect(await attempts(page)).toBe('1');
  await page.clock.runFor(1_000);
  await expect(page.locator('[data-sf-banner="not_open"]')).toBeVisible();
  await expect(page.locator('[data-sf-banner="not_open"]')).toContainText(CLOSED_REASON);
  await expect(page.locator('[data-sf-cta="send"]')).toContainText(CLOSED_REASON);
  expect(new URL(page.url()).pathname).toBe(`/s/${OPEN}/review`);
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(0);
  expect(await attempts(page), 'no second call').toBe('1');
  expect(await page.evaluate((k) => window.localStorage.getItem(k), `sf:v1:cart:${OPEN}`)).not.toBeNull();
  RESULTS.G_ORD_commit_refused = { attempts: 1, banner: 'not_open' };
  await page.screenshot({ path: path.join(SHOTS, 'G-ORD-commit-refused-ar-390.png'), fullPage: true });
});

test('G-ORD commit: a send committed BEFORE the close stands - the close never erases an accepted request', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await page.goto(`${BASE}/s/${OPEN}/checkout?fx=closes-late`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await freezeAfterLoad(page, T0);
  await fillDetails(page, 'pickup');
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.waitForSelector('[data-sf-cta="send"]');
  await page.locator('[data-sf-cta="send"]').click();
  await page.clock.runFor(900); // commit at +0.9 s, the close is at +1.5 s
  await page.waitForURL(`**${REQUEST}**`, { timeout: 20_000 });
  await page.waitForSelector('[data-sf-screen="received"]');
  await page.clock.runFor(2_000); // the close has passed
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(1);
  await page.locator('[data-sf-request-cta="track"]').click();
  await page.waitForSelector('[data-sf-screen="status"]');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await expect(page.locator('[data-sf-request-summary]')).toContainText('₪129.80');
  RESULTS.G_ORD_commit_stands = { received: true, status: 'waiting' };
});

// ============================================================ G-H01

for (const [slug, stateWord, offKey, tone] of [
  [CLOSED, AR.closed, 'pickupOff', 'toneBad'],
  [PAUSED, AR.paused, 'deliveryOff', 'toneWarn'],
] as const) {
  test(`G-H01 intro ${slug}: the state pill says "${stateWord}" in its tone, the dot does not pulse, and the switched-off service is marked off`, async ({ page }) => {
    await phone(page);
    await page.goto(`${BASE}/s/${slug}`, { waitUntil: 'networkidle' });
    const pills = page.locator('[class*="pills"] > li');
    await expect(pills).toHaveCount(3);
    const state = pills.nth(0);
    await expect(state).toContainText(stateWord);
    expect(await state.getAttribute('class')).toMatch(new RegExp(tone));
    expect(await state.locator('span').first().evaluate((el) => getComputedStyle(el).animationName)).toBe('none');
    const off = page.locator(`[class*="pillOff"]`);
    await expect(off).toHaveCount(1);
    await expect(off).toContainText(AR[offKey]);
    RESULTS[`G_H01_${slug}`] = { state: stateWord, off: AR[offKey] };
    await page.screenshot({ path: path.join(SHOTS, `G-H01-${slug}-intro-ar-390.png`), fullPage: true });
  });
}

test('G-H01 intro open: the positive control - the dot pulses and no service is off', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}/s/${OPEN}`, { waitUntil: 'networkidle' });
  const state = page.locator('[class*="pills"] > li').nth(0);
  await expect(state).toContainText(AR.openNow);
  expect(await state.locator('span').first().evaluate((el) => getComputedStyle(el).animationName)).not.toBe('none');
  await expect(page.locator('[class*="pillOff"]')).toHaveCount(0);
});

// ============================================================ G-GLASS

/** Computed backdrop-filter of an element, by whichever property this engine supports. */
const GLASS = (selector: string) => {
  const el = document.querySelector(selector) as HTMLElement | null;
  if (!el) return { found: false, value: null, supported: null };
  const cs = getComputedStyle(el) as CSSStyleDeclaration & { webkitBackdropFilter?: string };
  const supported = CSS.supports('backdrop-filter', 'blur(1px)') ? 'unprefixed' : CSS.supports('-webkit-backdrop-filter', 'blur(1px)') ? 'webkit' : 'none';
  const value = supported === 'unprefixed' ? cs.backdropFilter : supported === 'webkit' ? (cs.webkitBackdropFilter ?? cs.getPropertyValue('-webkit-backdrop-filter')) : null;
  return { found: true, value, supported };
};

const GLASS_CONSUMERS: Array<[string, string, string, string]> = [
  // id, route, selector, expected blur. The intro first: a menu visit marks
  // the intro as seen for the tab, after which the intro route goes home.
  ['intro glass button', `/s/${OPEN}`, '[class*="glassBtn"]', 'blur(10px)'],
  ['intro pill', `/s/${OPEN}`, '[class*="pills"] > li', 'blur(10px)'],
  ['language control', `/s/${OPEN}`, 'details[class*="wrap"] > summary', 'blur(10px)'],
  ['language menu panel', `/s/${OPEN}`, 'details[class*="wrap"] > ul', 'blur(14px)'],
  ['hero icon button', `/s/${OPEN}/menu`, '[data-sf-module="hero"] [class*="iconBtn"]', 'blur(10px)'],
  ['service strip', `/s/${OPEN}/menu`, '[data-sf-module="service"] [class*="service"]', 'blur(14px)'],
  ['compact header', `/s/${OPEN}/menu`, '[data-sf-compact]', 'blur(14px)'],
  ['badge', `/s/${OPEN}/menu`, '[data-sf-badge]', 'blur(8px)'],
  ['cart dock', `/s/${OPEN}/menu`, '[data-sf-dock="live"]', 'blur(14px)'],
];

test('G-GLASS every approved glass consumer has a REAL non-none computed backdrop-filter in the built output', async ({ page }) => {
  await phone(page);
  // The cart only (the dock needs a line); the intro must still be unseen.
  await page.addInitScript(([key, payload]) => { try { window.localStorage.setItem(key as string, payload as string); } catch { /* ignore */ } }, [`sf:v1:cart:${OPEN}`, JSON.stringify({ schema: 1, slug: OPEN, menuVersion: 'mb-1', lines: LINES })]);
  const out: Record<string, unknown> = {};
  for (const [id, route, selector, expected] of GLASS_CONSUMERS) {
    if (!page.url().endsWith(route)) {
      await page.goto(`${BASE}${route}`, { waitUntil: 'networkidle' });
      await page.evaluate(() => document.fonts.ready);
      if (route.endsWith('/menu')) await page.waitForSelector('[data-sf-dock="live"]', { timeout: 15_000 });
    }
    const probe = await page.evaluate(GLASS, selector);
    expect(probe.found, `${id}: ${selector} exists`).toBe(true);
    expect(probe.supported, `${id}: this engine supports backdrop-filter`).not.toBe('none');
    expect(probe.value, `${id}: computed backdrop-filter`).toBe(expected);
    out[id] = probe;
  }
  // The declarations themselves, in the served stylesheet, unprefixed AND prefixed.
  const css = await page.evaluate(async () => {
    const hrefs = [...document.querySelectorAll('link[rel="stylesheet"]')].map((l) => (l as HTMLLinkElement).href);
    const texts = await Promise.all(hrefs.map((h) => fetch(h).then((r) => r.text())));
    const all = texts.join('\n');
    return { unprefixed: (all.match(/(?<![-\w])backdrop-filter:blur\(/g) || []).length, webkit: (all.match(/-webkit-backdrop-filter:blur\(/g) || []).length };
  });
  expect(css.unprefixed).toBeGreaterThanOrEqual(5);
  expect(css.webkit).toBe(css.unprefixed);
  RESULTS.G_GLASS = { consumers: out, declarations: css, engine: 'chromium' };
  await page.goto(`${BASE}/s/${OPEN}/menu`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-dock="live"]');
  await page.evaluate(() => window.scrollTo(0, 420));
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(SHOTS, 'G-GLASS-home-compact-dock-ar-390.png') });
});

test('G-GLASS the geometry the glass sits on is unchanged: hero 298, dock 60, service strip and compact header sizes', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  await page.goto(`${BASE}/s/${OPEN}/menu`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-dock="live"]');
  const hero = await page.locator('[data-sf-module="hero"]').boundingBox();
  const dock = await page.locator('[data-sf-dock="live"]').boundingBox();
  const service = await page.locator('[data-sf-module="service"] [class*="service"]').first().boundingBox();
  expect(Math.round(hero!.height)).toBe(298);
  expect(Math.round(dock!.height)).toBe(60);
  expect(Math.round(service!.height)).toBeGreaterThanOrEqual(46);
  expect(await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1)).toBe(false);
  RESULTS.G_GLASS_geometry = { hero: hero!.height, dock: dock!.height, service: service!.height };
});

// ============================================================ G-FONTS

const FONT_STATE = () => {
  const faces = [...document.fonts].map((f) => ({ family: f.family.replace(/"/g, ''), status: f.status }));
  const preloads = [...document.querySelectorAll('link[rel="preload"][as="font"]')].map((l) => (l as HTMLLinkElement).href.replace(/.*rubik_/, '').replace(/_var.*/, ''));
  return { faces, preloads };
};

for (const [root, lang, expectPreload, expectLoaded] of [
  ['', 'ar', ['arabic', 'latin'], ['rubikArabic', 'rubikLatin', 'rubikHebrewLazy']],
  ['/en', 'en', ['arabic', 'latin'], ['rubikArabic', 'rubikLatin', 'rubikHebrewLazy']],
  ['/he', 'he', ['hebrew', 'latin'], ['rubikHebrew', 'rubikLatin', 'rubikArabicLazy']],
] as const) {
  test(`G-FONTS ${lang}: two preloaded subsets, the on-demand subset fetched when its script appears, Rubik renders every script, and the swap shift is measured`, async ({ page }) => {
    await phone(page);
    await seed(page, OPEN);
    await page.addInitScript(() => {
      const w = window as unknown as { __cls: number; __clsAfterFonts: number; __fontsReadyAt: number };
      w.__cls = 0; w.__clsAfterFonts = 0; w.__fontsReadyAt = -1;
      new PerformanceObserver((list) => {
        for (const e of list.getEntries() as PerformanceEntry[]) {
          const s = e as PerformanceEntry & { value: number; hadRecentInput: boolean };
          if (s.hadRecentInput) continue;
          w.__cls += s.value;
          if (w.__fontsReadyAt >= 0 && e.startTime >= w.__fontsReadyAt - 50) w.__clsAfterFonts += s.value;
        }
      }).observe({ type: 'layout-shift', buffered: true });
      document.fonts.ready.then(() => { w.__fontsReadyAt = performance.now(); });
    });
    await page.goto(`${BASE}${root}/s/${OPEN}/menu`, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(800);
    const state = await page.evaluate(FONT_STATE);
    expect(state.preloads.sort()).toEqual([...expectPreload]);
    const loaded = state.faces.filter((f) => f.status === 'loaded').map((f) => f.family).sort();
    for (const fam of expectLoaded) expect(loaded, `${fam} is loaded (the on-demand one because its characters are on the page)`).toContain(fam);
    // Nothing that this root did not declare is loaded, and no 404 face is.
    expect(loaded.filter((f) => /404/.test(f))).toEqual([]);
    // Rubik actually renders the scripts on the page: the tenant name (Latin), a
    // price (digits + ₪) and the interface / tenant text of the page's script.
    const rendered = await page.evaluate(() => ({
      latin: document.fonts.check('700 16px rubikLatin', 'Maps Burger 129'),
      shekel: document.fonts.check('700 16px rubikHebrew', '₪') || document.fonts.check('700 16px rubikHebrewLazy', '₪'),
      arabic: document.fonts.check('700 16px rubikArabic', 'كلاسيك') || document.fonts.check('700 16px rubikArabicLazy', 'كلاسيك'),
      hebrew: document.fonts.check('700 16px rubikHebrew', 'תפריט') || document.fonts.check('700 16px rubikHebrewLazy', 'תפריט'),
    }));
    expect(rendered.latin && rendered.shekel && rendered.arabic).toBe(true);
    if (lang === 'he') expect(rendered.hebrew).toBe(true);
    const shift = await page.evaluate(() => {
      const w = window as unknown as { __cls: number; __clsAfterFonts: number };
      return { cls: Number(w.__cls.toFixed(4)), afterFonts: Number(w.__clsAfterFonts.toFixed(4)) };
    });
    expect(shift.cls, 'total layout shift stays under the hard limit').toBeLessThanOrEqual(0.1);
    expect(shift.afterFonts, 'the font-swap shift target').toBeLessThanOrEqual(0.02);
    RESULTS[`G_FONTS_${lang}`] = { preloads: state.preloads, loaded, rendered, shift };
    await page.screenshot({ path: path.join(SHOTS, `G-FONTS-${lang}-home-390.png`) });
  });
}

test('G-FONTS the request document (EN root) and the 404 document: two preloads, and none, respectively; Rubik still declared on both', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}/en${REQUEST}?fx=status-waiting`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="status"]');
  const req = await page.evaluate(FONT_STATE);
  expect(req.preloads.sort()).toEqual(['arabic', 'latin']);
  const res = await page.goto(`${BASE}/r/NOPE-404`);
  expect(res!.status()).toBe(404);
  await page.evaluate(() => document.fonts.ready);
  const nf = await page.evaluate(FONT_STATE);
  expect(nf.preloads).toEqual([]);
  expect(nf.faces.map((f) => f.family).sort()).toEqual(expect.arrayContaining(['rubikLatin', 'rubikArabic404', 'rubikHebrew404']));
  expect(await page.evaluate(() => document.fonts.check('700 16px rubikArabic404', 'غير'))).toBe(true);
  RESULTS.G_FONTS_request_404 = { request: req.preloads, notFound: nf.preloads };
});

// ============================================================ G-CHAT

test('G-CHAT every simulated launch is answered by the demo disclosure (role=status) and nothing leaves the page or touches the message', async ({ page }) => {
  await phone(page);
  await seed(page, OPEN);
  const w = WATCHES.get(page)!;
  await page.goto(`${BASE}/s/${OPEN}/checkout`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await fillDetails(page, 'delivery');
  await page.locator('[data-sf-field="deliveryNotes"]').fill(SYNTH.deliveryNotes);
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.evaluate(() => window.history.replaceState(null, '', `${window.location.pathname}?fx=wa-fallback`));
  await page.locator('[data-sf-cta="send"]').click();
  await page.waitForURL(`**${REQUEST}**`, { timeout: 20_000 });
  await page.waitForSelector('[data-sf-screen="received"]');
  const note = page.locator('[data-sf-demo-note]');
  await expect(note).toHaveAttribute('role', 'status');
  await expect(note).toHaveAttribute('aria-live', 'polite');
  await expect(note).toHaveAttribute('data-sf-demo-note-fired', '0');
  await expect(note).toHaveText(AR.demoNotice);
  const messageBefore = await page.locator('[data-sf-request-message]').textContent();
  // The fallback launch: answered, and the visitor stays on received.
  await page.locator('[data-sf-request-cta="wa-web"]').click();
  await expect(note).toHaveAttribute('data-sf-demo-note-fired', '1');
  await expect(note).toHaveText(AR.demoNotice);
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(1);
  expect(await page.locator('[data-sf-request-message]').textContent()).toBe(messageBefore);
  for (const m of MARKERS) expect(messageBefore ?? '').not.toContain(m);
  // The main launch: answered, then the status view.
  await page.locator('[data-sf-request-cta="continue"]').click();
  await expect(note).toHaveAttribute('data-sf-demo-note-fired', '2');
  await page.waitForSelector('[data-sf-screen="status"]');
  // The status view's chat: answered again; the same one sentence, re-issued.
  await page.locator('[data-sf-status-action="chat"]').click();
  await expect(note).toHaveAttribute('data-sf-demo-note-fired', '3');
  await expect(note).toHaveText(AR.demoNotice);
  expect(await note.evaluate((el) => getComputedStyle(el.firstElementChild as Element).animationName)).not.toBe('none');
  // The sentence never claims a launch: it is the approved disclosure, verbatim.
  expect(AR.demoNotice).toContain('لا يتم');
  expect(w.popups).toBe(0);
  expect(w.offOrigin).toEqual([]);
  expect(new URL(page.url()).pathname).toBe(REQUEST);
  RESULTS.G_CHAT = { fired: 3, popups: 0, offOrigin: 0, staysOnReceivedAfterWaWeb: true };
  await page.screenshot({ path: path.join(SHOTS, 'G-CHAT-status-after-chat-ar-390.png'), fullPage: true });
});

test('G-CHAT under reduced motion the answer is one frame and still counted', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await phone(page);
  await page.goto(`${BASE}${REQUEST}?fx=status-waiting`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="status"]');
  await page.locator('[data-sf-status-action="chat"]').click();
  await expect(page.locator('[data-sf-demo-note]')).toHaveAttribute('data-sf-demo-note-fired', '1');
  const dur = await page.locator('[data-sf-demo-note] > span').evaluate((el) => getComputedStyle(el).animationDuration);
  expect(parseFloat(dur), `one frame, reported as ${dur}`).toBeLessThanOrEqual(0.05);
});
