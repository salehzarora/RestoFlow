// STOREFRONT-UI-001 F - the cross-engine smoke (PACKET 13.2: G02, G04, G17,
// G22, G30 and a shortened X01 on Firefox and WebKit). Run through
// playwright.cross.config.ts against an EVIDENCE build (G04 needs the
// demo-light slug; everything else is on the canonical tenant).
//
// These are SMOKE cases: they re-assert the structural facts each golden PNG
// proves, not every Chromium assertion. Playwright's WebKit is not Safari; a
// real-device iOS pass is launch QA, outside UI-001, and is recorded as such.
// Every value typed here is synthetic.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_F_PORT ?? 4429);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_F_SHOT_DIR ?? path.join(STOREFRONT, 'ui001f-evidence');
const RESULTS: Record<string, unknown> = {};

const SLUG = 'maps-burger';
const MENU = `/s/${SLUG}/menu`;
const CART = `/s/${SLUG}/cart`;
const CHECKOUT = `/s/${SLUG}/checkout`;
const REF = 'DEMO-7K4XM2D9P3';
const REQUEST = `/r/${REF}`;
const CART_KEY = `sf:v1:cart:${SLUG}`;

const LINES = [
  { lineId: 'f1aaaa', itemId: '1', qty: 1, selections: { bun: ['brioche'], extras: ['cheese'], remove: ['onion'] }, note: '' },
  { lineId: 'f2bbbb', itemId: '7', qty: 2, selections: { sauce: ['garlic'] }, note: '' },
];

let server: ChildProcess;

test.beforeAll(async () => {
  mkdirSync(SHOTS, { recursive: true });
  // G04 needs the evidence build. Refuse to pass vacuously on a shipped one.
  if (!existsSync(path.join(STOREFRONT, 'out', 'en', 's', 'demo-light', 'menu.html'))) {
    throw new Error('cross-engine smoke needs an evidence build: SF_EVIDENCE_ROUTES=1 npm run build');
  }
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

/**
 * WebKit and `upgrade-insecure-requests`: the committed CSP carries the
 * directive, and Playwright's WebKit applies it to a plain-http loopback
 * origin too (Chromium and Firefox exempt 127.0.0.1 as potentially
 * trustworthy, per the spec) - every subresource is rewritten to https:// and
 * fails to connect, so nothing hydrates. That is a property of the local
 * server's scheme, not of the storefront: hosted, the document is https and
 * the directive is a no-op. For WebKit ONLY, that ONE directive is removed
 * from the DOCUMENT response here, in the test, leaving the rest of the CSP
 * in force; the results file records that this was done.
 */
/** The last document CSP the WebKit shim served, and the one it was derived from. */
const SHIM: { committed: string | null; adapted: string | null } = { committed: null, adapted: null };

test.beforeEach(async ({ page }, info) => {
  if (info.project.name !== 'webkit') return;
  RESULTS.webkit_document_csp = 'upgrade-insecure-requests removed for loopback http (WebKit applies it to 127.0.0.1); every other directive kept';
  await page.route('**/*', async (route) => {
    if (route.request().resourceType() !== 'document') return route.continue();
    const res = await route.fetch();
    const headers = { ...res.headers() };
    const csp = headers['content-security-policy'];
    if (csp) {
      SHIM.committed = csp;
      headers['content-security-policy'] = csp.replace(/;\s*upgrade-insecure-requests\s*/g, '');
      SHIM.adapted = headers['content-security-policy'];
    }
    await route.fulfill({ response: res, headers });
  });
});

/** Computed backdrop-filter by whichever property this engine supports. */
const GLASS = (selector: string) => {
  const el = document.querySelector(selector) as HTMLElement | null;
  if (!el) return { found: false, value: null as string | null, supported: 'none' };
  const cs = getComputedStyle(el) as CSSStyleDeclaration & { webkitBackdropFilter?: string };
  const supported = CSS.supports('backdrop-filter', 'blur(1px)') ? 'unprefixed' : CSS.supports('-webkit-backdrop-filter', 'blur(1px)') ? 'webkit' : 'none';
  const value = supported === 'unprefixed' ? cs.backdropFilter : supported === 'webkit' ? (cs.webkitBackdropFilter ?? cs.getPropertyValue('-webkit-backdrop-filter')) : null;
  return { found: true, value, supported };
};

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, `results-cross-${process.env.SF_ENGINE ?? 'engine'}.json`), `${JSON.stringify(RESULTS, null, 2)}\n`, 'utf8');
});

async function seed(page: Page) {
  await page.addInitScript(
    ([key, payload, seen]) => {
      try {
        window.localStorage.setItem(key as string, payload as string);
        window.sessionStorage.setItem(seen as string, '1');
      } catch {
        /* ignore */
      }
    },
    [CART_KEY, JSON.stringify({ schema: 1, slug: SLUG, menuVersion: 'mb-1', lines: LINES }), `sf:v1:seen:${SLUG}`],
  );
}

function watch(page: Page) {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text());
  });
  return errors;
}

const overflow = (page: Page) =>
  page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);

/** Tab until the focused element matches, or give up after `max` presses. */
async function tabTo(page: Page, selector: string, max = 60): Promise<boolean> {
  for (let i = 0; i < max; i += 1) {
    await page.keyboard.press('Tab');
    const hit = await page.evaluate((sel) => {
      const el = document.activeElement;
      return !!el && el.matches(sel);
    }, selector);
    if (hit) return true;
  }
  return false;
}

test('G02 home AR dark 390: locked module order, hero, strip and dock geometry', async ({ page }, info) => {
  const errors = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await seed(page);
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  expect(await page.evaluate(() => [document.documentElement.lang, document.documentElement.dir])).toEqual(['ar', 'rtl']);
  const order = await page.evaluate(() =>
    [...document.querySelectorAll('[data-sf-module]')].map((el) => el.getAttribute('data-sf-module')),
  );
  const collapsed = order.filter((m, i) => m !== order[i - 1]);
  const locked = ['announce', 'compact', 'hero', 'service', 'notice', 'categories', 'promo', 'popular', 'sections', 'story', 'footer'];
  expect(locked.filter((m) => collapsed.includes(m))).toEqual(collapsed);
  for (const must of ['hero', 'service', 'categories', 'sections', 'footer']) expect(collapsed).toContain(must);
  const hero = await page.locator('[data-sf-module="hero"]').boundingBox();
  expect(Math.round(hero!.height)).toBe(298);
  const dock = page.locator('[data-sf-dock="live"]');
  await expect(dock).toHaveCount(1);
  const dockBox = await dock.boundingBox();
  expect(Math.round(dockBox!.height)).toBe(60);
  // The approved glass is REAL on this engine too: a non-none computed
  // backdrop-filter on the hero control, the service strip and the dock,
  // through whichever property the engine supports (recorded per engine).
  const glass: Record<string, unknown> = {};
  for (const [id, selector, expected] of [
    ['heroIconButton', '[data-sf-module="hero"] [class*="iconBtn"]', 'blur(10px)'],
    ['serviceStrip', '[data-sf-module="service"] [class*="service"]', 'blur(14px)'],
    ['dock', '[data-sf-dock="live"]', 'blur(14px)'],
  ] as const) {
    const probe = await page.evaluate(GLASS, selector);
    expect(probe.found, `${id} exists`).toBe(true);
    expect(probe.supported, `${id}: ${info.project.name} supports backdrop-filter`).not.toBe('none');
    expect(probe.value, `${id}: computed backdrop-filter on ${info.project.name}`).toBe(expected);
    glass[id] = probe;
  }
  expect(await overflow(page)).toBe(false);
  expect(errors).toEqual([]);
  RESULTS[`G02_${info.project.name}`] = { order: collapsed, hero: hero!.height, dock: dockBox!.height, glass };
  await page.screenshot({ path: path.join(SHOTS, `G02-${info.project.name}.png`) });
});

test('G04 home EN light 390: ltr chrome, light tokens, Arabic tenant text intact', async ({ page }, info) => {
  const errors = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript((seen) => {
    try {
      window.sessionStorage.setItem(seen as string, '1');
    } catch {
      /* ignore */
    }
  }, 'sf:v1:seen:demo-light');
  await page.goto(`${BASE}/en/s/demo-light/menu`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  expect(await page.evaluate(() => [document.documentElement.lang, document.documentElement.dir])).toEqual(['en', 'ltr']);
  const bg = await page.evaluate(() => {
    const root = document.querySelector('[data-sf-root]') as HTMLElement;
    return root.style.getPropertyValue('--bg').trim().toLowerCase();
  });
  expect(bg).toBe('#f4f6f5');
  // The tenant's Arabic hero copy renders as an isolated run inside LTR
  // chrome (the h1 is the tagline, the lockup carries the name).
  const h1 = await page.locator('h1').first().innerText();
  expect(/[؀-ۿ]/.test(h1)).toBe(true);
  expect(await page.evaluate(() => document.querySelector('h1 span')?.getAttribute('dir'))).toBe('auto');
  await expect(page.locator('body')).toContainText('Maps Burger');
  expect(await overflow(page)).toBe(false);
  expect(errors).toEqual([]);
  RESULTS[`G04_${info.project.name}`] = { bg };
  await page.screenshot({ path: path.join(SHOTS, `G04-${info.project.name}.png`) });
});

test('G17 product sheet: opens by deep link, the total is live, a required group blocks the CTA', async ({ page }, info) => {
  const errors = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript((seen) => {
    try {
      window.sessionStorage.setItem(seen as string, '1');
    } catch {
      /* ignore */
    }
  }, `sf:v1:seen:${SLUG}`);
  await page.goto(`${BASE}${MENU}?item=1`, { waitUntil: 'networkidle' });
  const sheet = page.locator('[data-sf-sheet="product"]');
  await expect(sheet).toBeVisible();
  const price = page.locator('[data-sf-cta="product"] span[dir="ltr"]');
  await expect(price).toHaveText('₪55');
  await sheet.locator('[data-sf-group="bun"] [role="radio"]').nth(1).click();
  await expect(price).toHaveText('₪60');
  await sheet.locator('[data-sf-group="extras"] [role="checkbox"]').first().click();
  await expect(price).toHaveText('₪66');
  expect(await overflow(page)).toBe(false);
  expect(errors).toEqual([]);
  RESULTS[`G17_${info.project.name}`] = { total: '₪66' };
  await page.screenshot({ path: path.join(SHOTS, `G17-${info.project.name}.png`) });
});

test('G22 checkout delivery: the address block appears, the zone pill states the fee, the CTA carries ₪141.60', async ({ page }, info) => {
  const errors = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await seed(page);
  await page.goto(`${BASE}${CHECKOUT}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');
  await expect(page.locator('[data-sf-address]')).toHaveCount(0);
  await page.locator('[data-sf-service="delivery"]').click();
  await expect(page.locator('[data-sf-address]')).toBeVisible();
  await page.locator('[data-sf-field="zoneId"]').selectOption('kafrmanda');
  await expect(page.locator('[data-sf-banner="zone-info"]')).toBeVisible();
  await expect(page.locator('[data-sf-cta="to-payment"]')).toContainText('₪141.60');
  expect(await overflow(page)).toBe(false);
  expect(errors).toEqual([]);
  RESULTS[`G22_${info.project.name}`] = { total: '₪141.60' };
  await page.screenshot({ path: path.join(SHOTS, `G22-${info.project.name}.png`), fullPage: true });
});

test('G30 status waiting: tone, TTL outside the live region, current node, chat + cancel', async ({ page }, info) => {
  const errors = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${BASE}${REQUEST}?fx=status-waiting`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-screen="status"]');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  await expect(page.locator('[data-sf-status-card]')).toHaveAttribute('data-sf-status-card', 'warn');
  await expect(page.locator('[data-sf-ttl-value]')).toHaveText(/^\d+:\d{2}$/);
  const a11y = await page.evaluate(() => {
    const ttl = document.querySelector('[data-sf-ttl]')!;
    const live = document.querySelector('[data-sf-status-live]')!;
    return { inside: live.contains(ttl), role: ttl.getAttribute('role'), current: document.querySelectorAll('[aria-current="step"]').length };
  });
  expect(a11y).toEqual({ inside: false, role: 'timer', current: 1 });
  await expect(page.locator('[data-sf-node]')).toHaveCount(6);
  await expect(page.locator('[data-sf-status-actions]')).toHaveAttribute('data-sf-status-actions', 'chat cancel');
  // The countdown ticks on this engine too.
  const a = await page.locator('[data-sf-ttl-value]').innerText();
  await page.waitForTimeout(1_600);
  const b = await page.locator('[data-sf-ttl-value]').innerText();
  expect(a).not.toBe(b);
  expect(await overflow(page)).toBe(false);
  expect(errors).toEqual([]);
  RESULTS[`G30_${info.project.name}`] = { a11y, ticked: a !== b };
  await page.screenshot({ path: path.join(SHOTS, `G30-${info.project.name}.png`), fullPage: true });
});

test('X01 (shortened) keyboard-only, AR 390: cart -> checkout -> payment -> review -> send -> received -> status', async ({ page }, info) => {
  const errors = watch(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await seed(page);
  await page.goto(`${BASE}${CART}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('[data-sf-cart-line]');

  expect(await tabTo(page, '[data-sf-cta="cart-checkout"]')).toBe(true);
  await page.keyboard.press('Enter');
  await page.waitForURL(`**${CHECKOUT}**`);
  await page.waitForSelector('[data-sf-screen="checkout"]:not([data-sf-pending])');

  expect(await tabTo(page, '[data-sf-service="pickup"]')).toBe(true);
  await page.keyboard.press('Space');
  expect(await tabTo(page, '[data-sf-field="fullName"]')).toBe(true);
  await page.keyboard.type('SYNTHKEYS01');
  expect(await tabTo(page, '[data-sf-field="phone"]')).toBe(true);
  await page.keyboard.type('052-123-4567');
  expect(await tabTo(page, '[data-sf-cta="to-payment"]')).toBe(true);
  await page.keyboard.press('Enter');
  await page.waitForURL('**/payment**');

  expect(await tabTo(page, '[data-sf-cta="to-review"]')).toBe(true);
  await page.keyboard.press('Enter');
  await page.waitForURL('**/review**');

  expect(await tabTo(page, '[data-sf-cta="send"]')).toBe(true);
  await page.keyboard.press('Enter');
  await page.waitForURL(`**${REQUEST}**`, { timeout: 20_000 });
  await page.waitForSelector('[data-sf-screen="received"]');
  await expect(page.locator('h1')).toBeVisible();

  expect(await tabTo(page, '[data-sf-request-cta="track"]')).toBe(true);
  await page.keyboard.press('Enter');
  await page.waitForSelector('[data-sf-screen="status"]');
  await expect(page.locator('[data-sf-screen="status"]')).toHaveAttribute('data-sf-status', 'waiting');
  // The activated control is gone with the received view: focus is on the
  // status card on this engine too, not on body.
  expect(await page.evaluate(() => document.activeElement?.getAttribute('data-sf-status-card') ?? 'body')).toBe('warn');
  // The sent details reached no store.
  const keys = await page.evaluate(() => [Object.keys(window.localStorage), Object.keys(window.sessionStorage)]);
  expect(keys[0]).toEqual([CART_KEY]);
  expect(await page.evaluate(() => JSON.stringify(window.localStorage) + JSON.stringify(window.sessionStorage))).not.toContain('SYNTHKEYS01');
  expect(await overflow(page)).toBe(false);
  expect(errors).toEqual([]);
  RESULTS[`X01_${info.project.name}`] = { reached: 'status' };
  await page.screenshot({ path: path.join(SHOTS, `X01-${info.project.name}.png`), fullPage: true });
});

test('CSP the served policy is enforced on this engine: an inline <style> and a style attribute are both blocked, and the WebKit shim differs from the committed policy by exactly one directive', async ({ page }, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => {
    (window as unknown as { __csp: string[] }).__csp = [];
    document.addEventListener('securitypolicyviolation', (e) => {
      (window as unknown as { __csp: string[] }).__csp.push(`${e.violatedDirective}:${e.blockedURI}`);
    });
  });
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'networkidle' });
  // The committed policy, read directly (this request never passes the page's route shim).
  const direct = await page.request.get(`${BASE}${MENU}`);
  const committed = direct.headers()['content-security-policy'] ?? '';
  expect(committed).toContain("style-src 'self'");
  expect(committed).toContain('upgrade-insecure-requests');
  if (info.project.name === 'webkit') {
    expect(SHIM.committed).toBe(committed);
    const stripped = committed.replace(/;\s*upgrade-insecure-requests\s*/g, '');
    expect(SHIM.adapted).toBe(stripped);
    expect(committed.split(';').length - stripped.split(';').length, 'exactly one directive removed').toBe(1);
  }
  // NEGATIVE CONTROL: inline style is refused under style-src 'self' on the
  // policy this engine actually received - so the shim (WebKit) or the
  // committed header (Firefox) is in force, not a permissive fallback.
  const probe = await page.evaluate(() => {
    const style = document.createElement('style');
    style.textContent = '.sf-csp-probe{color:rgb(1, 2, 3)}';
    document.head.appendChild(style);
    const p = document.createElement('p');
    p.className = 'sf-csp-probe';
    p.setAttribute('style', 'color:rgb(4, 5, 6)');
    p.textContent = 'probe';
    document.body.appendChild(p);
    const color = getComputedStyle(p).color;
    p.remove();
    style.remove();
    return { color };
  });
  expect(probe.color).not.toBe('rgb(1, 2, 3)');
  expect(probe.color).not.toBe('rgb(4, 5, 6)');
  // The violation report is dispatched on a later task.
  await page.waitForTimeout(250);
  const violations = await page.evaluate(() => (window as unknown as { __csp: string[] }).__csp);
  expect(violations.length, 'the engine reported the refusal').toBeGreaterThanOrEqual(1);
  expect(violations.every((v) => v.startsWith('style-src'))).toBe(true);
  RESULTS[`CSP_${info.project.name}`] = { committedDirectives: committed.split(';').length, shim: info.project.name === 'webkit' ? SHIM : null, inlineRefused: true, violations };
});
