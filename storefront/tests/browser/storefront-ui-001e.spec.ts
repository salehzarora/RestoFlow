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

/**
 * Freeze the page's (installed) clock right after a load and return the fake
 * milliseconds since `t0`. The fixture's late answers and expiry are due
 * 1.5 s after the source mounted, which is after t0: the freeze must land
 * well before that, or the order of events would be real time again - so a
 * slow load fails the test instead of being tolerated.
 */
async function freezeAfterLoad(page: Page, t0: number): Promise<number> {
  const now = await page.evaluate(() => Date.now());
  await page.clock.pauseAt(now + 50);
  const since = now + 50 - t0;
  expect(since, 'the load must finish well before the fixture answers').toBeLessThan(1_200);
  return since;
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

/**
 * The packet's global assertions, recorded for EVERY test by the fixture
 * below and asserted after each: no console or page error, no request that
 * leaves the origin, no failed asset, no CSP violation, and no popup - a
 * `window.open` would otherwise pass "nothing leaves the page" unnoticed.
 */
interface Watch {
  errors: string[];
  offOrigin: string[];
  failed: string[];
  csp: string[];
  popups: number;
}
const WATCHES = new WeakMap<Page, Watch>();

function watch(page: Page): Watch {
  const existing = WATCHES.get(page);
  if (existing) return existing;
  const w: Watch = { errors: [], offOrigin: [], failed: [], csp: [], popups: 0 };
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    (/content security policy/i.test(m.text()) ? w.csp : w.errors).push(m.text());
  });
  page.on('pageerror', (e) => w.errors.push(String(e)));
  page.on('request', (req) => {
    if (!req.url().startsWith(BASE)) w.offOrigin.push(`${req.method()} ${req.url()}`);
  });
  page.on('requestfailed', (req) => {
    // A navigation abandons its in-flight requests; that is not a failed asset.
    if (req.failure()?.errorText === 'net::ERR_ABORTED') return;
    w.failed.push(`${req.url()} ${req.failure()?.errorText ?? ''}`);
  });
  page.on('popup', () => {
    w.popups += 1;
  });
  page.context().on('page', () => {
    w.popups += 1;
  });
  WATCHES.set(page, w);
  return w;
}

test.beforeEach(async ({ page }) => {
  watch(page);
  await page.addInitScript(() => {
    document.addEventListener('securitypolicyviolation', (e) => {
      console.error(`Content Security Policy violation: ${e.violatedDirective} ${e.blockedURI}`);
    });
  });
});

test.afterEach(async ({ page }, info) => {
  const w = WATCHES.get(page);
  if (!w) return;
  // E-UNKNOWN loads a real 404 on purpose; Chromium reports that response as
  // a console error. Nothing else is ever tolerated.
  const errors = w.errors.filter((e) => !(info.title.startsWith('E-UNKNOWN') && /404/.test(e)));
  expect(errors, 'console / page errors').toEqual([]);
  expect(w.offOrigin, 'off-origin requests').toEqual([]);
  expect(w.failed, 'failed requests').toEqual([]);
  expect(w.csp, 'CSP violations').toEqual([]);
  expect(w.popups, 'popups').toBe(0);
});

const overflow = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);

/** A theme token as the `rgb(...)` a computed colour reports; runs in the page. */
async function tokenRgb(page: Page, name: string): Promise<string> {
  return page.evaluate((n) => {
    const el = document.querySelector('[data-sf-screen]') as HTMLElement;
    const raw = getComputedStyle(el).getPropertyValue(n).trim();
    const m = raw.match(/^#([0-9a-f]{6})$/i);
    if (!m) return raw;
    const v = parseInt(m[1], 16);
    return `rgb(${(v >> 16) & 255}, ${(v >> 8) & 255}, ${v & 255})`;
  }, name);
}

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
  expect(w.popups, 'no window was opened').toBe(0);
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
  await page.waitForTimeout(1_200);
  // The RENDERED text (innerText of the live document, the disclosure hidden
  // for the read), never a detached clone whose innerText glues words. The
  // claim is the packet's: WhatsApp is opened, never "sent" - so no sentence
  // states a message or request WAS sent, and the approved future-tense
  // preview label ("Message that will be sent", LOCKED string table) is
  // present, pinned rather than tolerated by accident.
  const text = await page.evaluate(() => {
    const note = document.querySelector('[data-sf-demo-note]') as HTMLElement | null;
    if (note) note.hidden = true;
    const t = document.body.innerText;
    if (note) note.hidden = false;
    return t;
  });
  const PAST_SENT = /\b(was|were|been|is|are|got|already|successfully)\s+sent\b/i;
  expect(text).not.toMatch(PAST_SENT);
  expect(text).not.toMatch(/\b(message|request|order)\s+sent\b/i);
  expect(text).toContain(EN.msgPreview);
  expect(EN.msgPreview).toBe('Message that will be sent');
  expect(text).toContain('Not confirmed yet');
  // The detector works: the past-tense sentence it guards against is caught.
  expect('Your message was sent').toMatch(PAST_SENT);
  const pre = page.locator('[data-sf-request-message]');
  expect(await pre.getAttribute('dir')).toBe('rtl');
  expect(await pre.getAttribute('lang')).toBe('ar');
  RESULTS.G28_EN = { noPastTenseSent: true, previewLabel: EN.msgPreview };
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
  // The 36px fallback controls keep their painted size and reach 44px (PX-6).
  await page.waitForTimeout(1_200);
  for (const sel of ['[data-sf-request-cta="wa-web"]', '[data-sf-request-copy="fallback"]']) {
    const box = await page.evaluate(PROBE_BOX, sel);
    expect(box!.painted.h, sel).toBe(36);
    expect(box!.effective.h, sel).toBeGreaterThanOrEqual(44);
  }
  // "Open WhatsApp Web" is the same simulated launch: nothing leaves the
  // page, no window opens, and the visitor STAYS on received (the prototype's
  // href="#", :539) with the copy control still in reach.
  await fallback.locator('[data-sf-request-cta="wa-web"]').click();
  await page.waitForTimeout(300);
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(1);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveCount(0);
  await expect(fallback.locator('[data-sf-request-copy="fallback"]')).toBeVisible();
  expect(new URL(page.url()).pathname).toBe(REQUEST);
  expect(w.offOrigin).toEqual([]);
  expect(w.popups).toBe(0);
  expect(w.errors).toEqual([]);
  RESULTS.G29 = { fallback: true, offOrigin: 0, popups: 0, staysOnReceived: true };
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
  // The body's "{m}" is number-then-unit in a bidi ISOLATE (<bdi>), not an
  // LTR island: forced LTR would read "د 30" in Arabic. The M:SS countdown
  // above is the island CONTENT:221 names; "30 د" is not.
  const minutes = await page.evaluate(() => {
    const body = document.querySelector('[data-sf-status-live] p')!;
    const isolates = [...body.querySelectorAll('bdi')].map((b) => b.textContent);
    return { isolates, ltrIslands: body.querySelectorAll('[dir="ltr"]').length };
  });
  expect(minutes.isolates).toEqual(['Maps Burger', `30 ${AR.min}`]);
  expect(minutes.ltrIslands).toBe(0);
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
  // :571 - the summary's rows sit 15px inside the card (1px border + the
  // container's 14px), padded ONCE, not 29px; and :567 - the cancel control
  // is painted in the danger ink itself, on the page surface.
  const paint = await page.evaluate(() => {
    const summary = document.querySelector('[data-sf-request-summary]') as HTMLElement;
    const row = summary.querySelector('[data-sf-request-line]') as HTMLElement;
    const cancel = document.querySelector('[data-sf-status-action="cancel"]') as HTMLElement;
    return {
      rowInset: Math.round(summary.getBoundingClientRect().right - row.getBoundingClientRect().right),
      cancelColor: getComputedStyle(cancel).color,
    };
  });
  expect(paint.rowInset).toBe(15);
  expect(paint.cancelColor).toBe(await tokenRgb(page, '--bad'));
  expect(await overflow(page)).toBe(false);
  expect(w.errors).toEqual([]);
  RESULTS.G30 = { a11y, nodes: n, paint };
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
    if (tone === 'bad') {
      // The prototype's toneCss (:839): the icon disc and the terminal node
      // paint their glyph in the tone's BED colour on the tone's fill.
      const glyph = await page.evaluate(() => {
        const icon = document.querySelector('[data-sf-status-card] > span') as HTMLElement;
        const dot = document.querySelector('[data-sf-node-kind="terminal"] span span') as HTMLElement;
        return { icon: getComputedStyle(icon).color, dot: getComputedStyle(dot).color, iconBg: getComputedStyle(icon).backgroundColor };
      });
      const badbg = await tokenRgb(page, '--badbg');
      expect(glyph.icon).toBe(badbg);
      expect(glyph.dot).toBe(badbg);
      expect(glyph.iconBg).toBe(await tokenRgb(page, '--bad'));
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
  // The screen behind the sheet is inert: the cancel control that opened it
  // cannot take focus and is hidden from assistive technology.
  const behind = await page.evaluate(() => {
    const cancelCtl = document.querySelector('[data-sf-status-action="cancel"]') as HTMLElement;
    cancelCtl.focus();
    return { inertAncestor: cancelCtl.closest('[inert]') !== null, tookFocus: document.activeElement === cancelCtl };
  });
  expect(behind).toEqual({ inertAncestor: true, tookFocus: false });
  // A click on the sheet's own body moves focus onto the dialog; Tab from
  // there enters the cycle, and Escape still keeps the request.
  await page.locator('[role="dialog"] h2').click();
  expect(await page.evaluate(() => document.activeElement?.getAttribute('role'))).toBe('dialog');
  await page.keyboard.press('Tab');
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cancel')), 'Tab from the sheet body enters at keep').toBe('keep');
  await page.locator('[role="dialog"] h2').click();
  await page.keyboard.press('Shift+Tab');
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-cancel')), 'Shift+Tab from the sheet body enters at yes').toBe('yes');
  await page.locator('[role="dialog"] h2').click();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-status-action')), 'Escape after a click inside still closes and restores').toBe('cancel');
  await cancel.focus();
  await page.keyboard.press('Enter');
  await expect(dialog).toBeVisible();
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
  RESULTS.G35 = { modal: true, focusTrap: true, escKeeps: true, scrimKeeps: true, backgroundInert: true, tabFromSheetBody: true };
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
  // The page's clock is the test's from here: the 1.6 s is pinned exactly,
  // not bracketed by a wall-clock window.
  await page.clock.install();
  await page.clock.pauseAt(Date.now());
  await copy.click();
  await expect(copy).toHaveText(AR.copied);
  // Chromium on Windows hands the text back with CRLF line endings; the
  // comparison is on content, not on the platform's newline.
  const written = (await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, '\n');
  expect(written).toBe(preview);
  for (const m of MARKERS) expect(written).not.toContain(m);
  expect(written).toContain('توصيل — كفر مندا');
  expect(written).not.toContain(SYNTH.street);
  await page.clock.runFor(1_599);
  await expect(copy, 'still "Copied" one millisecond before 1.6 s').toHaveText(AR.copied);
  await page.clock.runFor(1);
  await expect(copy, 'back to "Copy message" at exactly 1.6 s').toHaveText(AR.copyMsg);
  RESULTS.H19 = { copiedForMs: 1_600, clipboardMatchesPreview: true };
});

test('H19 fallback: the fallback block\'s copy control writes the same message and reverts at 1.6 s', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: BASE });
  await phone(page);
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: false });
  await page.evaluate(() => window.history.replaceState(null, '', `${window.location.pathname}?fx=wa-fallback`));
  await send(page);
  const copy = page.locator('[data-sf-request-copy="fallback"]');
  await expect(copy).toHaveText(AR.copyMsg);
  const preview = (await page.locator('[data-sf-request-message]').textContent()) ?? '';
  await page.clock.install();
  await page.clock.pauseAt(Date.now());
  await copy.click();
  await expect(copy).toHaveText(AR.copied);
  const written = (await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, '\n');
  expect(written).toBe(preview);
  for (const m of MARKERS) expect(written).not.toContain(m);
  await page.clock.runFor(1_599);
  await expect(copy).toHaveText(AR.copied);
  await page.clock.runFor(1);
  await expect(copy).toHaveText(AR.copyMsg);
  RESULTS.H19_fallback = { copiedForMs: 1_600, clipboardMatchesPreview: true };
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

test('H21 the TTL ticks from the source\'s expiresAt under a FAKE clock, and expiry is a source event that ends the countdown', async ({ page }) => {
  await phone(page);
  // The page's Date and timers are the test's: the fixture ages the demo
  // request 350 s, so the countdown opens at 30:00 - 5:50 = 24:10 exactly.
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await openStatus(page, 'status-waiting');
  await freezeAfterLoad(page, T0);
  const ttl = page.locator('[data-sf-ttl-value]');
  const parse = (s: string) => {
    const [m, sec] = s.split(':').map(Number);
    return m * 60 + sec;
  };
  // 24:10 at mount; at most one whole-second tick may have run before the
  // freeze, never more (the load precondition above).
  const a = parse(await ttl.innerText());
  expect(a).toBeGreaterThanOrEqual(24 * 60 + 9);
  expect(a).toBeLessThanOrEqual(24 * 60 + 10);
  await page.clock.runFor(2_000);
  const b = parse(await ttl.innerText());
  expect(a - b, 'two seconds of clock = two seconds of countdown').toBe(2);
  await page.clock.runFor(58_000);
  expect(parse(await ttl.innerText())).toBe(a - 60);
  // The timeline's own countdown node reads the same value.
  await expect(page.locator('[data-sf-node-countdown]')).toContainText(await ttl.innerText());

  // The restaurant does not answer in time: the SOURCE says expired, at the
  // instant IT set - 1.5 s after the source mounted - and not a tick before.
  await page.clock.install({ time: T0 });
  await openStatus(page, 'status-expires-late');
  const since = await freezeAfterLoad(page, T0);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await page.clock.runFor(1_300 - since);
  await expect(page.locator('[data-sf-screen="status"]'), 'still waiting before the expiry is due').toHaveAttribute('data-sf-status', 'waiting');
  await page.clock.runFor(1_500);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'expired');
  await expect(page.locator('[data-sf-ttl]')).toHaveCount(0);
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'orderAgain');
  const n = await nodes(page);
  expect(n.map((x) => x.kind)).toEqual(['done', 'done', 'terminal']);
  expect(n[2].time).not.toBeNull();
  RESULTS.H21 = { opensAt: a, tickedBy: a - b, expiredBySource: true, fakeClock: true };
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
  // The cancel control is gone with the pending state; focus lands on the
  // status card (the one element every state has), never on body.
  expect(
    await page.evaluate(() => document.activeElement?.getAttribute('data-sf-status-card') ?? document.activeElement?.tagName),
    'focus after the confirm',
  ).toBe('neutral');
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
  // The order of events is the TEST's: the clock is paused before the late
  // answer (1.5 s after load) is due, and advanced past it with the sheet open.
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await openStatus(page, 'status-accepts-late');
  const since = await freezeAfterLoad(page, T0);
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
  await page.clock.runFor(1_300 - since);
  await expect(page.locator('[role="dialog"]'), 'still open before the answer is due').toBeVisible();
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await page.clock.runFor(1_500);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'accepted');
  await expect(page.locator('[role="dialog"]'), 'the sheet closes: there is nothing left to cancel').toHaveCount(0);
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'chat');
  // Focus is handed back: the cancel control is gone, so the card takes it.
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-status-card') ?? 'body')).toBe('ok');
  const states = await page.evaluate(() => (window as unknown as { __states: string[] }).__states);
  expect(states).not.toContain('cancelled');
  expect(states[states.length - 1]).toBe('accepted');
  // After the answer there is nothing to cancel: the control itself is gone.
  await expect(page.locator('[data-sf-status-action="cancel"]')).toHaveCount(0);
  RESULTS.E_RACE = { states, deterministic: true };
});

test('E-RACE a cancel that lands FIRST is final: the restaurant answering later never overwrites a terminal state', async ({ page }) => {
  await phone(page);
  const T0 = new Date('2026-09-22T10:00:00.000Z').getTime();
  await page.clock.install({ time: T0 });
  await openStatus(page, 'status-accepts-late');
  await freezeAfterLoad(page, T0);
  await page.locator('[data-sf-status-action="cancel"]').click();
  // Confirm: the cancel round trip (300 ms) completes before the
  // restaurant's answer (1.5 s after mount), so the request is cancelled...
  await page.locator('[data-sf-cancel="yes"]').click();
  await expect(page.locator('[data-sf-cancel="yes"]')).toHaveAttribute('aria-disabled', 'true');
  await page.clock.runFor(300);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'cancelled');
  await expect(page.locator('[role="dialog"]')).toHaveCount(0);
  // ...and the late acceptance is refused by the source: a terminal state is
  // never overwritten. (The opposite order - answered first, cancel refused -
  // is pinned deterministically in tests/sf-request.test.mjs.)
  await page.clock.runFor(2_000);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'cancelled');
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'orderAgain');
  RESULTS.E_RACE_confirm = { finalState: 'cancelled', lateAnswerIgnored: true, deterministic: true };
});

// ============================================================== the flow

test('E-FLOW submit -> received -> track -> status carries THIS send; a reload renders status from the source', async ({ page }) => {
  await phone(page);
  await seed(page, SEED_LINES);
  const w = watch(page);
  await toReview(page, { delivery: false });
  await send(page);
  await page.locator('[data-sf-request-cta="track"]').focus();
  await page.keyboard.press('Enter');
  await page.waitForSelector('[data-sf-screen="status"]');
  expect(new URL(page.url()).pathname, 'received and status are STATES of one URL').toBe(REQUEST);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  // The control that was activated is gone with the received view; focus
  // moved to the status card, so a keyboard visitor is not dropped on body.
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-status-card') ?? 'body'), 'focus after the switch').toBe('warn');
  // The visitor's own send opened seconds ago: no recorded instant lies in
  // the future of the wall clock (the "waiting" record is held at the clock).
  const clockNow = await page.evaluate(() => {
    const d = new Date();
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  });
  for (const x of await nodes(page)) {
    if (x.time !== null) expect(x.time <= clockNow || (x.time.startsWith('23') && clockNow.startsWith('00')), `${x.state} at ${x.time} vs now ${clockNow}`).toBe(true);
  }
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
  // Forward again: received was shown ONCE. The same document, the same
  // handoff - the request route now renders status, not the received view.
  await page.goForward();
  await page.waitForSelector('[data-sf-screen="status"]', { timeout: 15_000 });
  expect(new URL(page.url()).pathname).toBe(REQUEST);
  await expect(page.locator('[data-sf-screen="received"]')).toHaveCount(0);
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  // And it is still THIS send's summary (the handoff survived the soft
  // navigations): pickup 129.80, not the fixed demo request.
  await expect(page.locator('[data-sf-request-summary]')).toContainText('₪129.80');
  RESULTS.E_BACK = { landedOn: pathname, forwardShows: 'status' };
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
  // Where the content fits, the document is EXACTLY the viewport: the demo
  // disclosure sits inside the 100dvh column, not on top of a second one.
  await page.setViewportSize({ width: 1280, height: 1500 });
  await openStatus(page, 'status-waiting');
  await page.waitForTimeout(400);
  const tall = await page.evaluate(() => ({ scroll: document.documentElement.scrollHeight, inner: window.innerHeight }));
  expect(tall.scroll, `document ${tall.scroll} vs viewport ${tall.inner}`).toBe(tall.inner);
  out.tall = tall;
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
      new Promise<{ truthOpacity: string; truthVisible: boolean; ringAnimation: string; sheenDisplay: string; framesWaited: number }>((resolve) => {
        requestAnimationFrame(() =>
          requestAnimationFrame(() => {
            const truth = document.querySelector('[data-sf-received-truth]') as HTMLElement;
            const ring = document.querySelector('[data-sf-received-disc]')!.parentElement!.querySelector('span') as HTMLElement;
            const sheen = document.querySelector('[data-sf-request-cta="continue"] > span:first-child') as HTMLElement;
            resolve({
              truthOpacity: getComputedStyle(truth).opacity,
              truthVisible: truth.getBoundingClientRect().height > 0,
              ringAnimation: getComputedStyle(ring).animationName,
              sheenDisplay: getComputedStyle(sheen).display,
              framesWaited: 2,
            });
          }),
        );
      }),
  );
  expect(probe.truthOpacity).toBe('1');
  expect(probe.truthVisible).toBe(true);
  expect(probe.ringAnimation).toBe('none');
  // A stopped sheen would be a stripe painted across the CTA: it is not shown.
  expect(probe.sheenDisplay).toBe('none');
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
  await seed(page, SEED_LINES);
  await toReview(page, { delivery: false });
  await send(page);
  // The shipped tenant is `full`. Calm is what the same markup does WITHOUT
  // the motionFull class - so the class is removed in place and the computed
  // styles are read: the decorations stop, the entrance keeps running.
  const probe = await page.evaluate(() => {
    const screen = document.querySelector('[data-sf-screen="received"]') as HTMLElement;
    const motionClass = [...screen.classList].find((c) => /motionFull/.test(c)) ?? null;
    const ring = document.querySelector('[data-sf-received-disc]')!.parentElement!.querySelector('span') as HTMLElement;
    const cta = document.querySelector('[data-sf-request-cta="continue"]') as HTMLElement;
    const sheen = cta.querySelector(':scope > span:first-child') as HTMLElement;
    const halo = cta.parentElement!.querySelector(':scope > span:first-child') as HTMLElement;
    const truth = document.querySelector('[data-sf-received-truth]') as HTMLElement;
    const read = () => ({
      ring: getComputedStyle(ring).animationName,
      halo: getComputedStyle(halo).animationName,
      sheen: getComputedStyle(sheen).animationName,
      sheenDisplay: getComputedStyle(sheen).display,
      truth: getComputedStyle(truth).animationName,
    });
    const full = read();
    if (motionClass) screen.classList.remove(motionClass);
    const calm = read();
    if (motionClass) screen.classList.add(motionClass);
    return { motionClass: motionClass !== null, full, calm };
  });
  expect(probe.motionClass).toBe(true);
  // Full: the decorations run and so does the entrance.
  expect(probe.full.ring).not.toBe('none');
  expect(probe.full.halo).not.toBe('none');
  expect(probe.full.sheen).not.toBe('none');
  expect(probe.full.truth).not.toBe('none');
  // Calm: the decorations stop and the sheen is not painted; the entrance stays.
  expect(probe.calm.ring).toBe('none');
  expect(probe.calm.halo).toBe('none');
  expect(probe.calm.sheen).toBe('none');
  expect(probe.calm.sheenDisplay).toBe('none');
  expect(probe.calm.truth).toBe(probe.full.truth);
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
    // Every TRANSIENT write is recorded too - a value written and removed
    // again before the final sweep would otherwise never be seen: storage
    // setItem, history pushState / replaceState and the cookie setter.
    const writes: string[] = [];
    (window as unknown as { __writes: string[] }).__writes = writes;
    const setItem = Storage.prototype.setItem;
    Storage.prototype.setItem = function (this: Storage, k: string, v: string) {
      writes.push(`setItem ${k}=${v}`);
      return setItem.call(this, k, v);
    };
    for (const fn of ['pushState', 'replaceState'] as const) {
      const orig = History.prototype[fn];
      History.prototype[fn] = function (this: History, state: unknown, title: string, url?: string | URL | null) {
        writes.push(`${fn} ${JSON.stringify(state)} ${String(url ?? '')}`);
        return orig.call(this, state, title, url);
      };
    }
    const cookie = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie');
    if (cookie?.set) {
      Object.defineProperty(document, 'cookie', {
        configurable: true,
        get() { return cookie.get!.call(document); },
        set(v: string) { writes.push(`cookie ${v}`); cookie.set!.call(document, v); },
      });
    }
  });
  await toReview(page, { delivery: true });
  await send(page);
  await page.waitForTimeout(1_200);
  // The received view itself, before it is left: the DOM that carries the
  // visitor's own summary and message must carry none of the markers.
  const receivedDom = await page.evaluate(() => document.documentElement.outerHTML);
  expect(receivedDom).toContain('data-sf-screen="received"');
  await page.locator('[data-sf-request-copy="inline"]').click();
  await page.locator('[data-sf-request-cta="track"]').click();
  await page.waitForSelector('[data-sf-screen="status"]');
  await page.waitForTimeout(400);

  const sinks = await page.evaluate(() => ({
    receivedDom: '',
    writes: (window as unknown as { __writes: string[] }).__writes.join('\n'),
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
  sinks.receivedDom = receivedDom;
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
  // The transient recorder is live (it saw the flow's own writes) and every
  // storage write it saw is the cart or the seen flag; no cookie was set.
  const writeLines = sinks.writes.split('\n').filter(Boolean);
  expect(writeLines.length).toBeGreaterThan(0);
  expect(writeLines.filter((l) => l.startsWith('cookie '))).toEqual([]);
  for (const line of writeLines) {
    if (line.startsWith('setItem ')) expect(line).toMatch(/^setItem sf:v1:(cart|seen):maps-burger=/);
  }
  expect(w.offOrigin).toEqual([]);
  expect(w.errors).toEqual([]);
  expect(w.popups).toBe(0);
  // The detector works: a planted marker in a scratch string is found.
  const planted = `x ${SYNTH.street} y`;
  expect(MARKERS.some((m) => planted.includes(m))).toBe(true);
  RESULTS.E_PRIVACY = { leaks, localKeys: sinks.localKeys, sessionKeys: sinks.sessionKeys, clipWrites: sinks.clip.split('\n').length, transientWrites: writeLines.length, offOrigin: w.offOrigin.length };
});
