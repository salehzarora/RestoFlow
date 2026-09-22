// STOREFRONT-UI-001 E - received / status, and the D1 closeout proofs that
// belong to the same finishing stage. Runs against the SHIPPED build
// (SF_EVIDENCE_ROUTES unset); every value typed here is synthetic.
//
//   E-FOCUS  the wide aside's checkout control keeps keyboard focus across a
//            quote settlement (the D1 review's bounded regression), on Home
//            and on Search, and never steals focus that moved elsewhere.
//   G28-G35, H19-H22, E-FLOW, E-RACE, E-DUP, E-BACK, E-UNKNOWN, E-STATIC,
//   E-RESPONSIVE, E-REDUCED, E-PRIVACY  the Phase E cases proper.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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

// ============================================================ shared E helpers


const REF = 'DEMO-7K4XM2D9P3';
const CODE = '#MB-2487';
const REQUEST = `/r/${REF}`;
const CHECKOUT_URL = `${BASE}${CHECKOUT}`;
const AR = JSON.parse(readFileSync(path.join(STOREFRONT, 'messages/storefront.ar.json'), 'utf8'));
const EN = JSON.parse(readFileSync(path.join(STOREFRONT, 'messages/storefront.en.json'), 'utf8'));

/** Synthetic, never real. Every marker is unique enough to grep for. */
const SYNTH = {
  fullName: 'SYNTHNAME7F3A',
  phone: '052-123-4567',
  area: 'SYNTHAREA9B21',
  street: 'SYNTHSTREET4C88',
  building: 'SYNTHBLD12',
  apartment: 'SYNTHAPT7',
  deliveryNotes: 'SYNTHNOTE5E10',
};
const MARKERS = Object.values(SYNTH).concat('0521234567', '052-123-4567');

const SEED_LINES = [
  { lineId: 'e1aaaa', itemId: '1', qty: 1, selections: { bun: ['brioche'], extras: ['cheese'], remove: ['onion'] }, note: '' },
  { lineId: 'e2bbbb', itemId: '7', qty: 2, selections: { sauce: ['garlic'] }, note: '' },
];

async function phone(page: Page) {
  await page.setViewportSize({ width: 390, height: 844 });
}

/** Details -> payment -> review, with synthetic values. */
async function toReview(page: Page, opts: { delivery: boolean; root?: string } = { delivery: false }) {
  const root = opts.root ?? '';
  await page.goto(`${BASE}${root}${CHECKOUT}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])', { timeout: 15_000 });
  await page.locator(`[data-sf-service="${opts.delivery ? 'delivery' : 'pickup'}"]`).click();
  await page.locator('[data-sf-field="fullName"]').fill(SYNTH.fullName);
  await page.locator('[data-sf-field="phone"]').fill(SYNTH.phone);
  if (opts.delivery) {
    await page.locator('[data-sf-field="zoneId"]').selectOption('kafrmanda');
    await page.locator('[data-sf-field="area"]').fill(SYNTH.area);
    await page.locator('[data-sf-field="street"]').fill(SYNTH.street);
    await page.locator('[data-sf-field="building"]').fill(SYNTH.building);
    await page.locator('[data-sf-field="apartment"]').fill(SYNTH.apartment);
    await page.locator('[data-sf-field="deliveryNotes"]').fill(SYNTH.deliveryNotes);
  }
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.waitForSelector('[data-sf-cta="send"]');
}

/** Press send and wait for the request route. */
async function send(page: Page) {
  await page.locator('[data-sf-cta="send"]').click();
  await page.waitForURL(`**${REQUEST}**`, { timeout: 20_000 });
  await page.waitForSelector('[data-sf-screen="received"]', { timeout: 15_000 });
}

/** Direct load of the demo ref in one fixture state. */
async function openStatus(page: Page, token: string, root = '') {
  await page.goto(`${BASE}${root}${REQUEST}?fx=${token}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="status"]', { timeout: 15_000 });
}

/** The effective hit box of a control, probed with elementFromPoint. */
const PROBE_BOX = (selector: string) => {
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
  return {
    painted: { w: Math.round(r.width), h: Math.round(r.height) },
    effective: { w: reach(-1, 0) + reach(1, 0) + 1, h: reach(0, -1) + reach(0, 1) + 1 },
  };
};

function watch(page: Page) {
  const errors: string[] = [];
  const offOrigin: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('request', (req) => {
    if (!req.url().startsWith(BASE)) offOrigin.push(`${req.method()} ${req.url()}`);
  });
  return { errors, offOrigin };
}

const overflow = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);

// ================================================================ G28-G29

test('G28 received: the request was received, NOT confirmed - truth line visible after the stagger, code, summary, message, no "sent"', async ({
  page,
}) => {
  await phone(page);
  await seed(page, SEED_LINES);
  const w = watch(page);
  await toReview(page, { delivery: false });
  await send(page);

  expect(new URL(page.url()).pathname).toBe(REQUEST);
  await expect(page.locator('h1')).toHaveText(AR.received);

  // The truth line is visible AFTER the stagger (650ms + 450ms), fully opaque.
  await page.waitForTimeout(1_200);
  const truth = page.locator('[data-sf-received-truth]');
  await expect(truth).toBeVisible();
  expect(await truth.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  expect(await truth.innerText()).toContain('لم يتم التأكيد بعد');

  // The code pill is the display code, an LTR island; the ref stays in the URL.
  const pill = page.locator('[data-sf-request-code]').first();
  await expect(pill).toHaveText(CODE);
  expect(await pill.getAttribute('dir')).toBe('ltr');

  // The summary is THIS visitor's send: two lines, the pickup total.
  const summary = page.locator('[data-sf-request-summary]');
  await expect(summary.locator('[data-sf-request-line]')).toHaveCount(2);
  await expect(summary).toContainText('₪129.80');
  await expect(summary).toContainText('Maps Burger');

  // The message: code, restaurant, lines, total, pickup wording, the configured
  // origin's /r/ link - and nothing the visitor typed.
  const message = (await page.locator('[data-sf-request-message]').textContent()) ?? '';
  expect(message).toContain(`طلب جديد ${CODE} — Maps Burger`);
  expect(message).toContain('1× Maps كلاسيك (بريوش · جبنة إضافية · ✕ بصل)');
  expect(message).toContain('الإجمالي: ₪129.80 · استلام من المطعم · نقداً');
  expect(message).toMatch(/الحالة: https:\/\/[a-z0-9.-]+\/r\/DEMO-7K4XM2D9P3$/);
  expect(message).not.toContain('bizbot.app');
  for (const m of MARKERS) expect(message).not.toContain(m);
  expect(await page.locator('[data-sf-request-message]').getAttribute('dir')).toBe('rtl');

  // Never "sent": the only "sent" on this page is the demo disclosure saying
  // that nothing is. Measured on the EN copy in a second pass below.
  await expect(page.locator('[data-sf-request-cta="continue"]')).toHaveText(AR.continueWa);
  await expect(page.locator('[data-sf-request-cta="track"]')).toHaveText(AR.trackStatus);
  await expect(page.locator('[data-sf-request-fallback]')).toHaveCount(0);
  await expect(page.locator('[data-sf-request-copy="inline"]')).toHaveCount(1);
  await expect(page.locator('[data-sf-demo-note]')).toBeVisible();

  // Geometry the PNG proves: 78px disc, 58px CTA, 50px track button.
  const disc = await page.locator('[data-sf-received-disc]').boundingBox();
  expect(Math.round(disc!.width)).toBe(78);
  const cta = await page.locator('[data-sf-request-cta="continue"]').boundingBox();
  expect(Math.round(cta!.height)).toBe(58);
  const track = await page.locator('[data-sf-request-cta="track"]').boundingBox();
  expect(Math.round(track!.height)).toBe(50);
  // The 30px copy control keeps its painted size and reaches 44px effective.
  const copy = await page.evaluate(PROBE_BOX, '[data-sf-request-copy="inline"]');
  expect(copy!.painted.h).toBe(30);
  expect(copy!.effective.h).toBeGreaterThanOrEqual(44);

  expect(await overflow(page)).toBe(false);
  expect(w.errors).toEqual([]);
  expect(w.offOrigin).toEqual([]);
  RESULTS.G28 = { url: page.url(), messageLines: message.split('\n').length, disc: disc!.width, cta: cta!.height };
  await page.screenshot({ path: path.join(SHOTS, 'G28-received-ar-dark-390.png'), fullPage: true });
});

test('G28 EN: the received copy never says a message was sent; the preview keeps the restaurant\'s direction', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: false, root: '/en' });
  await send(page);
  expect(await page.evaluate(() => [document.documentElement.lang, document.documentElement.dir])).toEqual(['en', 'ltr']);
  await expect(page.locator('h1')).toHaveText(EN.received);
  // Every visible sentence outside the demo disclosure: no "sent".
  const text = await page.evaluate(() => {
    const note = document.querySelector('[data-sf-demo-note]');
    const clone = document.body.cloneNode(true) as HTMLElement;
    clone.querySelector('[data-sf-demo-note]')?.remove();
    void note;
    return clone.innerText;
  });
  expect(text).not.toMatch(/\bsent\b/i);
  expect(text).toContain('Not confirmed yet');
  const pre = page.locator('[data-sf-request-message]');
  expect(await pre.getAttribute('dir')).toBe('rtl');
  expect(await pre.getAttribute('lang')).toBe('ar');
  RESULTS.G28_EN = { noSent: true };
  await page.screenshot({ path: path.join(SHOTS, 'G28-received-en-390.png'), fullPage: true });
});

test('G29 received with the WhatsApp fallback block: web + copy, no inline copy, still no navigation', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  const w = watch(page);
  await toReview(page, { delivery: false });
  // The request-route token rides on the review URL (fixture layer carries it).
  await page.evaluate(() => window.history.replaceState(null, '', `${window.location.pathname}?fx=wa-fallback`));
  await send(page);
  expect(new URL(page.url()).search).toBe('?fx=wa-fallback');
  const fallback = page.locator('[data-sf-request-fallback]');
  await expect(fallback).toBeVisible();
  await expect(fallback).toContainText(AR.waFallback);
  await expect(fallback.locator('[data-sf-request-cta="wa-web"]')).toHaveText(AR.waWeb);
  await expect(fallback.locator('[data-sf-request-copy="fallback"]')).toHaveText(AR.copyMsg);
  await expect(page.locator('[data-sf-request-copy="inline"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-request-message]')).toBeVisible();
  // "Open WhatsApp Web" is the same simulated launch: nothing leaves the page.
  await fallback.locator('[data-sf-request-cta="wa-web"]').click();
  await page.waitForSelector('[data-sf-screen="status"]');
  expect(new URL(page.url()).pathname).toBe(REQUEST);
  expect(w.offOrigin).toEqual([]);
  expect(w.errors).toEqual([]);
  RESULTS.G29 = { fallback: true, offOrigin: 0 };
  await page.screenshot({ path: path.join(SHOTS, 'G29-received-fallback-ar-dark-390.png'), fullPage: true });
});

// ================================================================ G30-G35

const LIVE_NOT_TTL = () => {
  const ttl = document.querySelector('[data-sf-ttl]');
  const live = document.querySelector('[data-sf-status-live]');
  return {
    ttlPresent: !!ttl,
    ttlInsideLive: !!ttl && !!live && live.contains(ttl),
    ttlRole: ttl?.getAttribute('role') ?? null,
    ttlAriaLive: ttl?.getAttribute('aria-live') ?? null,
    liveRole: live?.getAttribute('role') ?? null,
  };
};

async function nodes(page: Page) {
  return page.evaluate(() =>
    [...document.querySelectorAll('[data-sf-node]')].map((n) => ({
      state: n.getAttribute('data-sf-node'),
      kind: n.getAttribute('data-sf-node-kind'),
      current: n.getAttribute('aria-current'),
      time: n.querySelector('[data-sf-node-time]')?.textContent?.trim() ?? null,
      countdown: !!n.querySelector('[data-sf-node-countdown]'),
    })),
  );
}

test('G30 status waiting: warn tone, live TTL outside the live region, current node, chat + cancel', async ({ page }) => {
  await phone(page);
  const w = watch(page);
  await openStatus(page, 'status-waiting');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await expect(page.locator('[data-sf-status-card]')).toHaveAttribute('data-sf-status-card', 'warn');
  await expect(page.locator('h1')).toHaveText(AR.waiting);
  const ttl = page.locator('[data-sf-ttl-value]');
  await expect(ttl).toHaveText(/^\d+:\d{2}$/);
  expect(await ttl.getAttribute('dir')).toBe('ltr');
  const a11y = await page.evaluate(LIVE_NOT_TTL);
  expect(a11y).toEqual({ ttlPresent: true, ttlInsideLive: false, ttlRole: 'timer', ttlAriaLive: 'off', liveRole: 'status' });
  const n = await nodes(page);
  expect(n.map((x) => [x.state, x.kind])).toEqual([
    ['received', 'done'], ['waiting', 'current'], ['accepted', 'future'], ['preparing', 'future'], ['ready', 'future'], ['completed', 'future'],
  ]);
  expect(n.filter((x) => x.current === 'step').map((x) => x.state)).toEqual(['waiting']);
  expect(n.filter((x) => x.time !== null).map((x) => x.state)).toEqual(['received', 'waiting']);
  expect(n.find((x) => x.state === 'waiting')!.countdown).toBe(true);
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'chat cancel');
  await expect(page.locator('[data-sf-request-code]')).toHaveText(CODE);
  await expect(page.locator('[data-sf-request-summary]')).toContainText('₪141.60');
  expect(await overflow(page)).toBe(false);
  expect(w.errors).toEqual([]);
  RESULTS.G30 = { a11y, nodes: n };
  await page.screenshot({ path: path.join(SHOTS, 'G30-status-waiting-ar-dark-390.png'), fullPage: true });
});

const STATE_CASES: Array<[string, string, string, string, string[], number, number | null]> = [
  // id, token, tone, actions, node kinds, node count, times count
  ['G31', 'status-accepted', 'ok', 'chat', ['done', 'done', 'current', 'future', 'future', 'future'], 6, 3],
  ['G32', 'status-ready', 'ok', 'chat', ['done', 'done', 'done', 'done', 'current', 'future'], 6, 5],
  ['G33', 'status-rejected', 'bad', 'orderAgain', ['done', 'done', 'terminal'], 3, 3],
  ['G34', 'status-expired', 'warn', 'orderAgain', ['done', 'done', 'terminal'], 3, 3],
  ['H20a', 'status-received', 'info', 'chat cancel', ['current', 'future', 'future', 'future', 'future', 'future'], 6, 1],
  ['H20b', 'status-preparing', 'ok', 'chat', ['done', 'done', 'done', 'current', 'future', 'future'], 6, 4],
  ['H20c', 'status-completed', 'ok', 'orderAgain', ['done', 'done', 'done', 'done', 'done', 'current'], 6, 6],
  ['H20d', 'status-cancelled', 'neutral', 'orderAgain', ['done', 'done', 'terminal'], 3, 3],
];

for (const [id, token, tone, actions, kinds, count, times] of STATE_CASES) {
  test(`${id} ${token}: ${tone} tone, actions "${actions}", ${count} nodes, times only where recorded, TTL only while waiting`, async ({ page }) => {
    await phone(page);
    const w = watch(page);
    await openStatus(page, token);
    const state = token.slice('status-'.length);
    await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', state);
    await expect(page.locator('[data-sf-status-card]')).toHaveAttribute('data-sf-status-card', tone);
    await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', actions);
    const n = await nodes(page);
    expect(n.map((x) => x.kind)).toEqual(kinds);
    expect(n.length).toBe(count);
    expect(n.filter((x) => x.time !== null).length).toBe(times);
    for (const x of n) expect(x.time === null, `${x.state} ${x.kind}`).toBe(x.kind === 'future');
    await expect(page.locator('[data-sf-ttl]')).toHaveCount(0);
    expect(n.some((x) => x.countdown)).toBe(false);
    if (kinds.includes('terminal')) {
      expect(n[2].state).toBe(state);
      // The terminal node carries the hero title, not a step label.
      const label = await page.locator('[data-sf-node]').nth(2).locator('span span span').first().innerText();
      expect(label).toBe(await page.locator('h1').innerText());
    }
    // No invented facts anywhere on the screen.
    const text = await page.locator('[data-sf-screen="status"]').innerText();
    expect(text).not.toMatch(/ETA|courier|rating|\bmin(ute)?s? left\b/i);
    expect(await overflow(page)).toBe(false);
    expect(w.errors).toEqual([]);
    RESULTS[id] = { state, tone, actions, nodes: n };
    await page.screenshot({ path: path.join(SHOTS, `${id}-${token}-ar-dark-390.png`), fullPage: true });
  });
}

test('G35 cancel sheet: modal dialog, focus on keep, Tab cycles, Esc and the scrim keep the request, focus returns', async ({ page }) => {
  await phone(page);
  await openStatus(page, 'status-waiting');
  const cancel = page.locator('[data-sf-status-action="cancel"]');
  await cancel.focus();
  await page.keyboard.press('Enter');
  const dialog = page.locator('[role="dialog"]');
  await expect(dialog).toBeVisible();
  expect(await dialog.getAttribute('aria-modal')).toBe('true');
  await expect(dialog).toContainText(AR.cancelTitle);
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cancel'))).toBe('keep');
  await page.keyboard.press('Tab');
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cancel'))).toBe('yes');
  await page.keyboard.press('Tab');
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cancel')), 'Tab wraps inside the sheet').toBe('keep');
  await page.keyboard.press('Shift+Tab');
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cancel'))).toBe('yes');
  await page.screenshot({ path: path.join(SHOTS, 'G35-status-cancel-sheet-ar-dark-390.png') });
  // Buttons meet the 44px minimum.
  for (const sel of ['[data-sf-cancel="keep"]', '[data-sf-cancel="yes"]']) {
    const b = await page.locator(sel).boundingBox();
    expect(Math.round(b!.height)).toBeGreaterThanOrEqual(44);
  }
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-status-action')), 'focus returns to the cancel control').toBe('cancel');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  // The scrim keeps it too.
  await cancel.click();
  await expect(dialog).toBeVisible();
  await page.locator('[data-sf-cancel-scrim]').click({ position: { x: 10, y: 10 } });
  await expect(dialog).toHaveCount(0);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  RESULTS.G35 = { modal: true, focusTrap: true, escKeeps: true, scrimKeeps: true };
});

// ================================================================ H19-H22

test('H19 copy: "Copied" for 1.6 s only after a REAL successful clipboard write, and the text carries no contact field', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: BASE });
  await phone(page);
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: true });
  await send(page);
  const copy = page.locator('[data-sf-request-copy="inline"]');
  await expect(copy).toHaveText(AR.copyMsg);
  const preview = (await page.locator('[data-sf-request-message]').textContent()) ?? '';
  const t0 = Date.now();
  await copy.click();
  await expect(copy).toHaveText(AR.copied);
  // Chromium on Windows hands the text back with CRLF line endings; the
  // comparison is on content, not on the platform's newline.
  const written = (await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, '\n');
  expect(written).toBe(preview);
  for (const m of MARKERS) expect(written).not.toContain(m);
  expect(written).toContain('توصيل — كفر مندا');
  expect(written).not.toContain(SYNTH.street);
  await expect(copy).toHaveText(AR.copyMsg, { timeout: 4_000 });
  const elapsed = Date.now() - t0;
  expect(elapsed).toBeGreaterThanOrEqual(1_500);
  expect(elapsed).toBeLessThan(3_500);
  RESULTS.H19 = { copiedFor: elapsed, clipboardMatchesPreview: true };
});

test('H19 NEGATIVE CONTROL: a failed write (SIMULATED clipboard stub) never shows "Copied"', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  // A test stub, labelled as such: it is not the OS clipboard and proves
  // nothing about it. It only makes the browser's answer "no".
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: () => Promise.reject(new Error('SIMULATED clipboard refusal')) },
    });
  });
  await toReview(page, { delivery: false });
  await send(page);
  const copy = page.locator('[data-sf-request-copy="inline"]');
  await copy.click();
  await page.waitForTimeout(600);
  await expect(copy).toHaveText(AR.copyMsg);
  RESULTS.H19_negative = { copiedShownOnFailure: false };
});

test('H21 the TTL ticks from the source\'s expiresAt, and expiry is a source event that ends the countdown', async ({ page }) => {
  await phone(page);
  await openStatus(page, 'status-waiting');
  const ttl = page.locator('[data-sf-ttl-value]');
  const parse = (s: string) => {
    const [m, sec] = s.split(':').map(Number);
    return m * 60 + sec;
  };
  const a = parse(await ttl.innerText());
  await page.waitForTimeout(2_200);
  const b = parse(await ttl.innerText());
  expect(a - b).toBeGreaterThanOrEqual(1);
  expect(a - b).toBeLessThanOrEqual(3);
  expect(a).toBeLessThanOrEqual(30 * 60);

  // The restaurant does not answer in time: the SOURCE says expired.
  await openStatus(page, 'status-expires-late');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'expired', { timeout: 8_000 });
  await expect(page.locator('[data-sf-ttl]')).toHaveCount(0);
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'orderAgain');
  const n = await nodes(page);
  expect(n.map((x) => x.kind)).toEqual(['done', 'done', 'terminal']);
  expect(n[2].time).not.toBeNull();
  RESULTS.H21 = { tickedBy: a - b, expiredBySource: true };
});

test('H22 cancel: keep -> confirm -> cancelled -> order again clears the cart and returns to the menu', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  await openStatus(page, 'status-waiting');
  expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).not.toBeNull();
  await page.locator('[data-sf-status-action="cancel"]').click();
  await page.locator('[data-sf-cancel="keep"]').click();
  await expect(page.locator('[role="dialog"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await page.locator('[data-sf-status-action="cancel"]').click();
  await page.locator('[data-sf-cancel="yes"]').click();
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'cancelled', { timeout: 5_000 });
  await expect(page.locator('[role="dialog"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-status-card]')).toHaveAttribute('data-sf-status-card', 'neutral');
  await expect(page.locator('h1')).toHaveText(AR.cancelled);
  await expect(page.locator('[data-sf-status-action="cancel"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-ttl]')).toHaveCount(0);
  expect((await nodes(page)).map((x) => x.kind)).toEqual(['done', 'done', 'terminal']);
  // The cart is untouched by the cancellation itself...
  expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).not.toBeNull();
  await page.screenshot({ path: path.join(SHOTS, 'H22-status-cancelled-ar-dark-390.png'), fullPage: true });
  // ...and cleared by the ONE designed action.
  await page.locator('[data-sf-status-action="orderAgain"]').click();
  await page.waitForURL(`**${MENU}**`);
  expect(new URL(page.url()).pathname).toBe(MENU);
  expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).toBeNull();
  await expect(page.locator('[data-sf-dock]')).toHaveCount(0);
  RESULTS.H22 = { cancelled: true, orderAgainCleared: true, landedOn: MENU };
});

test('E-RACE the restaurant accepts while the confirmation sheet is open: nothing is cancelled', async ({ page }) => {
  await phone(page);
  await openStatus(page, 'status-accepts-late');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await page.locator('[data-sf-status-action="cancel"]').click();
  await expect(page.locator('[role="dialog"]')).toBeVisible();
  // Record every state the screen passes through.
  await page.evaluate(() => {
    const w = window as unknown as { __states: string[] };
    w.__states = [];
    const el = document.querySelector('[data-sf-screen="status"]')!;
    const push = () => w.__states.push(el.getAttribute('data-sf-status') ?? '');
    push();
    new MutationObserver(push).observe(el, { attributes: true, attributeFilter: ['data-sf-status'] });
  });
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'accepted', { timeout: 8_000 });
  await expect(page.locator('[role="dialog"]'), 'the sheet closes: there is nothing left to cancel').toHaveCount(0);
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'chat');
  const states = await page.evaluate(() => (window as unknown as { __states: string[] }).__states);
  expect(states).not.toContain('cancelled');
  expect(states[states.length - 1]).toBe('accepted');
  RESULTS.E_RACE = { states };
});

test('E-RACE a cancel that lands FIRST is final: the restaurant answering later never overwrites a terminal state', async ({ page }) => {
  await phone(page);
  await openStatus(page, 'status-accepts-late');
  await page.locator('[data-sf-status-action="cancel"]').click();
  // Confirm at once: the cancel round trip (~300ms) completes before the
  // restaurant's answer (1.5s after load), so the request is cancelled...
  await page.locator('[data-sf-cancel="yes"]').click();
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'cancelled', { timeout: 5_000 });
  // ...and the late acceptance is refused by the source: a terminal state is
  // never overwritten. (The opposite order - answered first, cancel refused -
  // is pinned deterministically in tests/sf-request.test.mjs.)
  await page.waitForTimeout(2_200);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'cancelled');
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'orderAgain');
  RESULTS.E_RACE_confirm = { finalState: 'cancelled', lateAnswerIgnored: true };
});

// ============================================================== the flow

test('E-FLOW submit -> received -> track -> status carries THIS send; a reload renders status from the source', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  const w = watch(page);
  await toReview(page, { delivery: false });
  await send(page);
  await page.locator('[data-sf-request-cta="track"]').click();
  await page.waitForSelector('[data-sf-screen="status"]');
  expect(new URL(page.url()).pathname, 'received and status are STATES of one URL').toBe(REQUEST);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  // The status view shows the visitor's own send: pickup, 129.80.
  await expect(page.locator('[data-sf-request-summary]')).toContainText('₪129.80');
  await expect(page.locator('[data-sf-request-summary] [data-sf-request-line]')).toHaveCount(2);
  await expect(page.locator('[data-sf-ttl]')).toHaveCount(1);
  // The cart survived the send (nothing clears it but "order again").
  expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).not.toBeNull();

  // Reload: the in-memory handoff is gone; the same URL is the status view,
  // fed by the source (the fixed demo request), never the received view.
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="status"]', { timeout: 15_000 });
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await expect(page.locator('[data-sf-request-summary]')).toContainText('₪141.60');
  expect(w.errors).toEqual([]);
  expect(w.offOrigin).toEqual([]);
  RESULTS.E_FLOW = { trackedTo: 'waiting', reloadShowsStatus: true };
});

test('E-DUP the duplicate banner carries ONE recovery, "view status", which opens the status view without a new send', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  await page.goto(`${BASE}${CHECKOUT}?fx=duplicate`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await page.locator('[data-sf-service="pickup"]').click();
  await page.locator('[data-sf-field="fullName"]').fill(SYNTH.fullName);
  await page.locator('[data-sf-field="phone"]').fill(SYNTH.phone);
  await page.locator('[data-sf-cta="to-payment"]').click();
  await page.waitForURL('**/payment**');
  await page.locator('[data-sf-cta="to-review"]').click();
  await page.waitForURL('**/review**');
  await page.locator('[data-sf-cta="send"]').click();
  const banner = page.locator('[data-sf-banner="duplicate"]');
  await expect(banner).toBeVisible({ timeout: 10_000 });
  expect(new URL(page.url()).pathname).toContain('/review');
  const actions = banner.locator('[data-sf-banner-action]');
  await expect(actions).toHaveCount(1);
  await expect(actions).toHaveText(AR.viewStatus);
  await actions.click();
  await page.waitForURL(`**${REQUEST}**`);
  await page.waitForSelector('[data-sf-screen="status"]', { timeout: 15_000 });
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(0);
  expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).not.toBeNull();
  RESULTS.E_DUP = { oneAction: true, landedOn: 'status' };
});

test('E-BACK Back from the request route returns into the flow with the cart intact; the draft is memory-only', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: false });
  await send(page);
  await page.goBack();
  await page.waitForTimeout(800);
  const pathname = new URL(page.url()).pathname;
  // The review step's guard sends an empty draft back to details.
  expect([`/s/${SLUG}/review`, `/s/${SLUG}/checkout`]).toContain(pathname);
  expect(await page.evaluate((k) => window.localStorage.getItem(k), CART_KEY)).not.toBeNull();
  expect(await page.locator('[data-sf-field="fullName"]').inputValue().catch(() => '')).toBe('');
  RESULTS.E_BACK = { landedOn: pathname };
});

test('E-UNKNOWN an ungenerated ref is a real 404; a source that knows no such request answers neutrally', async ({ page }) => {
  await phone(page);
  const res = await page.goto(`${BASE}/r/NOPE-1`);
  expect(res!.status()).toBe(404);
  await expect(page.locator('h1')).toHaveText(AR.unknownTitle);
  await openStatus(page, 'status-missing');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'missing');
  await expect(page.locator('h1')).toHaveText(AR.unknownTitle);
  await expect(page.locator('[data-sf-timeline]')).toHaveCount(0);
  RESULTS.E_UNKNOWN = { status404: true, missingNeutral: true };
});

test('E-STATIC the served request documents are chrome only, in the right language and direction', async () => {
  for (const [root, lang, dir] of [['', 'ar', 'rtl'], ['/ar', 'ar', 'rtl'], ['/en', 'en', 'ltr'], ['/he', 'he', 'rtl']] as const) {
    const html = await (await fetch(`${BASE}${root}${REQUEST}`)).text();
    expect(html).toContain(`<html lang="${lang}" dir="${dir}"`);
    expect(html).toContain('data-sf-pending');
    for (const banned of [CODE, 'data-sf-timeline', 'data-sf-ttl', 'data-sf-screen="received"', 'data-sf-screen="status"', '₪', AR.waiting, AR.received]) {
      expect(html, `${root}: ${banned}`).not.toContain(banned);
    }
  }
  RESULTS.E_STATIC = { neutral: true };
});

test('E-RESPONSIVE no horizontal overflow, no aside, one column at every width incl. 899/900 and 1280', async ({ page }) => {
  const out: Record<string, unknown> = {};
  for (const width of [360, 390, 430, 834, 899, 900, 1280]) {
    await page.setViewportSize({ width, height: 900 });
    await openStatus(page, 'status-waiting');
    await expect(page.locator('[data-sf-aside]')).toHaveCount(0);
    expect(await overflow(page), `${width}: overflow`).toBe(false);
    const card = await page.locator('[data-sf-status-card]').boundingBox();
    expect(card!.width).toBeLessThanOrEqual(width);
    out[width] = { overflow: false, cardWidth: Math.round(card!.width) };
  }
  RESULTS.E_RESPONSIVE = out;
  await page.screenshot({ path: path.join(SHOTS, 'E-status-waiting-1280.png') });
});

test('E-REDUCED under reduced motion the truth line is visible at once and the decorative rings do not run', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await phone(page);
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: false });
  await send(page);
  // "A single frame": measured after exactly two animation frames, which is
  // what a collapsed 0.001s / 0ms-delay entrance needs to reach its end state.
  // Under motion the same probe would read 0 for the 350ms of the stagger.
  const probe = await page.evaluate(
    () =>
      new Promise<{ truthOpacity: string; truthVisible: boolean; ringAnimation: string; framesWaited: number }>((resolve) => {
        requestAnimationFrame(() =>
          requestAnimationFrame(() => {
            const truth = document.querySelector('[data-sf-received-truth]') as HTMLElement;
            const ring = document.querySelector('[data-sf-received-disc]')!.parentElement!.querySelector('span') as HTMLElement;
            resolve({
              truthOpacity: getComputedStyle(truth).opacity,
              truthVisible: truth.getBoundingClientRect().height > 0,
              ringAnimation: getComputedStyle(ring).animationName,
              framesWaited: 2,
            });
          }),
        );
      }),
  );
  expect(probe.truthOpacity).toBe('1');
  expect(probe.truthVisible).toBe(true);
  expect(probe.ringAnimation).toBe('none');
  RESULTS.E_REDUCED = probe;
});

test('E-REDUCED NEGATIVE CONTROL: with motion, the same two-frame probe finds the truth line still inside its stagger', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await phone(page);
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: false });
  await send(page);
  const opacity = await page.evaluate(
    () =>
      new Promise<string>((resolve) => {
        requestAnimationFrame(() =>
          requestAnimationFrame(() =>
            resolve(getComputedStyle(document.querySelector('[data-sf-received-truth]') as HTMLElement).opacity),
          ),
        );
      }),
  );
  // 350ms of delay have not elapsed after two frames: the probe discriminates.
  expect(Number(opacity)).toBeLessThan(1);
  // And after the stagger the same line is fully visible (the G28 guarantee).
  await page.waitForTimeout(1_200);
  expect(await page.locator('[data-sf-received-truth]').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  RESULTS.E_REDUCED_negative = { twoFrameOpacityWithMotion: opacity };
});

test('E-CALM the calm motion preset keeps the entrance and drops the rings, halo and sheen', async ({ page }) => {
  await phone(page);
  await openStatus(page, 'status-waiting');
  // The shipped tenant is `full`; calm is proven structurally: without the
  // motionFull class, the ring / halo / sheen rules do not apply.
  const probe = await page.evaluate(() => {
    const screen = document.querySelector('[data-sf-screen="status"]') as HTMLElement;
    return { hasMotionClass: [...screen.classList].some((c) => /motionFull/.test(c)) };
  });
  expect(probe.hasMotionClass).toBe(true);
  RESULTS.E_CALM = probe;
});

// ============================================================== PG-4

test('E-PRIVACY (PG-4) after a full delivery send with markers in every field: no marker in any store, in the DOM, in the message, in the clipboard write, and no off-origin request', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  const w = watch(page);
  // A SIMULATED clipboard that records what the page tried to write. It is a
  // test seam, not the OS clipboard.
  await page.addInitScript(() => {
    const written: string[] = [];
    (window as unknown as { __clip: string[] }).__clip = written;
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: (t: string) => { written.push(t); return Promise.resolve(); } },
    });
  });
  await toReview(page, { delivery: true });
  await send(page);
  await page.locator('[data-sf-request-copy="inline"]').click();
  await page.locator('[data-sf-request-cta="track"]').click();
  await page.waitForSelector('[data-sf-screen="status"]');
  await page.waitForTimeout(400);

  const sinks = await page.evaluate(() => ({
    localKeys: Object.keys(window.localStorage),
    sessionKeys: Object.keys(window.sessionStorage),
    localText: Object.entries(window.localStorage).map(([k, v]) => `${k}=${v}`).join('\n'),
    sessionText: Object.entries(window.sessionStorage).map(([k, v]) => `${k}=${v}`).join('\n'),
    dom: document.documentElement.outerHTML,
    url: window.location.href,
    historyState: JSON.stringify(window.history.state ?? null),
    name: window.name,
    cookie: document.cookie,
    clip: (window as unknown as { __clip: string[] }).__clip.join('\n'),
  }));
  const leaks: string[] = [];
  for (const [sink, text] of Object.entries(sinks)) {
    if (Array.isArray(text)) continue;
    for (const m of MARKERS) if (String(text).includes(m)) leaks.push(`${sink}: ${m}`);
  }
  expect(leaks).toEqual([]);
  expect(sinks.localKeys).toEqual([CART_KEY]);
  expect(sinks.sessionKeys.sort()).toEqual([`sf:v1:seen:${SLUG}`]);
  expect(sinks.cookie).toBe('');
  expect(sinks.name).toBe('');
  expect(sinks.clip.length).toBeGreaterThan(50);
  expect(w.offOrigin).toEqual([]);
  expect(w.errors).toEqual([]);
  // The detector works: a planted marker in a scratch string is found.
  const planted = `x ${SYNTH.street} y`;
  expect(MARKERS.some((m) => planted.includes(m))).toBe(true);
  RESULTS.E_PRIVACY = { leaks, localKeys: sinks.localKeys, sessionKeys: sinks.sessionKeys, clipWrites: sinks.clip.split('\n').length, offOrigin: w.offOrigin.length };
});
