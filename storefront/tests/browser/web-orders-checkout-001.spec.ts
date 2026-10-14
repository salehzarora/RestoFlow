/** Synthetic-only real Chromium evidence; run through verify-web-orders-checkout.mjs. */
import { test, expect, type BrowserContext, type Page } from '@playwright/test';
import { mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { SYNTH_IDS } from '../support/envelope.mjs';

const BASE = process.env.SF_WEB_ORDER_BASE ?? '';
const RUN = process.env.SF_WEB_ORDER_RUN_DIR ?? '';
const ORIGINAL = process.env.SF_WEB_ORDER_ORIGINAL ?? '';
const APP = process.env.SF_WEB_ORDER_APP_DIR ?? '';
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const EDGE = `${ORIGIN}/functions/v1/web-order-submit`;
const TTL = 86_400_000;
const PHONE = '+972501234567';
const NAME = 'Synthetic Browser Guest';
const ITEM_NOTES = ['First line בלי בצל بدون بصل', 'Second line extra onion'];
const ORDER_NOTE = 'Synthetic pickup note ملاحظة הערה';
const TOTALS = { currency_code: 'ILS', subtotal_minor: 12345, tax_total_minor: 2222, grand_total_minor: 14567 };
type State = 'pending' | 'accepted' | 'rejected' | 'expired';
type RequestBody = { action: 'submit' | 'status'; slug: string; request_id: string; status_token: string; order?: { order_type: string; customer: { name: string; phone: string }; items: { menu_item_id: string; quantity: number; modifiers: { modifier_option_id: string; quantity: number }[]; notes?: string }[]; notes: string } };
type Entry = { body: RequestBody; state: State; expires: string };

function root(locale: string) { return locale === 'ar' ? '' : `/${locale}`; }
function routeFor(locale: string, slug: string, leaf: string) { return `${root(locale)}/s/${slug}/${leaf}`; }

/** No raw capability is emitted to evidence files or user-visible diagnostics. */
async function offlineEdge(context: BrowserContext, page: Page, initial: 'normal' | 'lost-commit' | 'missing' = 'normal') {
  const ledger = new Map<string, Entry>();
  const submissions: RequestBody[] = [];
  const actions: { action: string; slug: string; requestId: string }[] = [];
  const remote: string[] = [];
  const pageErrors: string[] = [];
  let mode = initial;
  let writes = 0;
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await context.route('**/*', async (route) => {
    const request = route.request();
    const url = request.url();
    if (url.startsWith(`${BASE}/`)) { await route.continue(); return; }
    if (url !== EDGE) { remote.push(new URL(url).origin); await route.abort('blockedbyclient'); return; }
    const cors = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store, max-age=0', 'Access-Control-Allow-Origin': BASE, 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'content-type' };
    if (request.method() === 'OPTIONS') { await route.fulfill({ status: 204, headers: cors }); return; }
    expect(request.method()).toBe('POST');
    const headers = request.headers();
    expect(headers.authorization).toBeUndefined(); expect(headers.apikey).toBeUndefined(); expect(headers.cookie).toBeUndefined(); expect(headers.referer).toBeUndefined();
    const body = request.postDataJSON() as RequestBody;
    expect(Object.keys(body).sort()).toEqual((body.action === 'submit' ? ['action', 'slug', 'request_id', 'status_token', 'order'] : ['action', 'slug', 'request_id', 'status_token']).sort());
    expect(/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(body.slug)).toBe(true);
    expect(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(body.request_id)).toBe(true);
    expect(/^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/.test(body.status_token)).toBe(true);
    actions.push({ action: body.action, slug: body.slug, requestId: body.request_id });
    const key = `${body.slug}:${body.request_id}`;
    if (body.action === 'submit') {
      writes++; submissions.push(body);
      if (mode === 'missing' && writes === 1) { await route.abort('failed'); return; }
      if (!ledger.has(key)) ledger.set(key, { body, state: 'pending', expires: new Date(Date.now() + 900_000).toISOString() });
      if (mode === 'lost-commit' && writes === 1) { await route.abort('failed'); return; }
    }
    const entry = ledger.get(key);
    if (!entry || entry.body.status_token !== body.status_token) { await route.fulfill({ status: 404, headers: cors, body: JSON.stringify({ ok: false, error: 'not_found' }) }); return; }
    await route.fulfill({ status: 200, headers: cors, body: JSON.stringify({ ok: true, request_id: body.request_id, status: entry.state, expires_at: entry.expires, totals: TOTALS, replayed: body.action === 'status' || writes > 1 }) });
  });
  return { ledger, submissions, actions, remote, pageErrors, get writes() { return writes; }, setMode(value: typeof mode) { mode = value; }, setState(value: State) { for (const entry of ledger.values()) entry.state = value; } };
}

async function assertPage(page: Page, locale: string) {
  await expect(page.locator('html')).toHaveAttribute('lang', locale);
  await expect(page.locator('html')).toHaveAttribute('dir', locale === 'en' ? 'ltr' : 'rtl');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal document overflow').toBe(true);
}
async function picture(page: Page, filename: string) {
  const dir = path.join(RUN, 'screenshots'); mkdirSync(dir, { recursive: true });
  await page.screenshot({ path: path.join(dir, filename), fullPage: true, animations: 'disabled' });
}
async function addLine(page: Page, note: string, itemQuantity = 1, optionQuantity = 1) {
  await page.locator(`[data-sf-item="${SYNTH_IDS.burger}"]`).first().click();
  const sheet = page.locator('[data-sf-sheet="product"]'); await expect(sheet).toBeVisible();
  await sheet.getByRole('radio', { name: /Synth Classic/ }).click();
  await sheet.getByRole('checkbox', { name: /Synth Cheese/ }).click();
  const option = sheet.locator(`[data-sf-modifier-quantity="${SYNTH_IDS.cheese}"]`);
  for (let quantity = 1; quantity < optionQuantity; quantity++) await option.locator('button').nth(1).click();
  for (let quantity = 1; quantity < itemQuantity; quantity++) await sheet.locator('[data-sf-step="inc"]').click();
  await sheet.locator('textarea').fill(note);
  await sheet.locator('[data-sf-cta="product"]').click();
  await expect(sheet).toHaveCount(0);
}
async function prepare(page: Page, locale: string, slug: string, twoLines = true) {
  const document = await page.goto(routeFor(locale, slug, 'menu'), { waitUntil: 'networkidle' });
  expect(document?.status()).toBe(200);
  expect(document?.headers()['content-security-policy']).toContain(`connect-src 'self' ${ORIGIN};`);
  await assertPage(page, locale);
  await addLine(page, ITEM_NOTES[0], 2, 2);
  if (twoLines) await addLine(page, ITEM_NOTES[1]);
  const dock = page.locator('[data-sf-dock-cta="cart"]');
  if (await dock.isVisible()) {
    await dock.click(); await expect(page.locator('[data-sf-cta="cart-checkout"]')).toBeVisible();
    await page.locator('[data-sf-cta="cart-checkout"]').click();
  } else {
    await expect(page.locator('[data-sf-aside-cta="checkout"]')).toBeVisible();
    await page.locator('[data-sf-aside-cta="checkout"]').click();
  }
  await expect(page.locator('[data-sf-web-order="details"]')).toBeVisible();
  await expect(page.locator('[data-sf-address]')).toHaveCount(0);
  await page.locator('[data-sf-field="fullName"]').fill(NAME);
  await page.locator('[data-sf-field="phone"]').fill('0501234567');
  await expect(page.locator('[data-sf-cta="to-review"]')).toHaveAttribute('aria-disabled', 'true');
  await page.locator('[data-sf-field="phone"]').fill(PHONE);
  await page.locator('[data-sf-field="orderNotes"]').fill(ORDER_NOTE);
  await page.locator('[data-sf-cta="to-review"]').click();
  await expect(page.locator('[data-sf-web-order="review"]')).toBeVisible();
  await expect(page.locator('[data-sf-item-note]')).toHaveText(twoLines ? ITEM_NOTES : [ITEM_NOTES[0]]);
  await expect(page.locator('[data-sf-order-notes]')).toContainText(ORDER_NOTE);
  await expect(page.locator('[data-sf-banner="truth-notice"]')).toBeVisible();
}
function assertPayload(body: RequestBody, twoLines = true) {
  expect(body.order?.order_type).toBe('takeaway');
  expect(body.order?.customer).toEqual({ name: NAME, phone: PHONE });
  expect(body.order?.notes).toBe(ORDER_NOTE);
  expect(body.order?.items.map((item) => ({ id: item.menu_item_id, quantity: item.quantity, notes: item.notes, modifiers: item.modifiers }))).toEqual([
    { id: SYNTH_IDS.burger, quantity: 2, notes: ITEM_NOTES[0], modifiers: [{ modifier_option_id: SYNTH_IDS.classic, quantity: 1 }, { modifier_option_id: SYNTH_IDS.cheese, quantity: 2 }] },
    ...(twoLines ? [{ id: SYNTH_IDS.burger, quantity: 1, notes: ITEM_NOTES[1], modifiers: [{ modifier_option_id: SYNTH_IDS.classic, quantity: 1 }, { modifier_option_id: SYNTH_IDS.cheese, quantity: 1 }] }] : []),
  ]);
  expect(Object.keys(body.order ?? {}).sort()).toEqual(['customer', 'items', 'notes', 'order_type']);
}
async function assertPrivateStorage(page: Page, slug: string) {
  const stored = await page.evaluate((owner) => ({ local: Object.entries(localStorage), session: Object.entries(sessionStorage), cookies: document.cookie, url: location.href, owner }), slug);
  expect(stored.local).toEqual([]); expect(stored.cookies).toBe('');
  const recovery = stored.session.find(([key]) => key === `bizbot:web-order:${slug}`);
  expect(recovery).toBeDefined();
  const value = JSON.parse(recovery![1]);
  expect(Object.keys(value).sort()).toEqual(['slug', 'request_id', 'status_token', 'created_at', 'expires_at'].sort());
  expect(value.slug).toBe(slug); expect(value.expires_at - value.created_at).toBe(TTL);
  expect(stored.url.includes(value.status_token)).toBe(false); expect(stored.url.includes(value.request_id)).toBe(false);
  for (const [, content] of [...stored.local, ...stored.session]) {
    expect(content.includes(NAME)).toBe(false); expect(content.includes(PHONE)).toBe(false); expect(content.includes(ITEM_NOTES[0])).toBe(false); expect(content.includes(ORDER_NOTE)).toBe(false); expect(content.includes(SYNTH_IDS.burger)).toBe(false);
  }
}

test.beforeAll(() => {
  expect(BASE).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);
  expect(RUN && APP && ORIGINAL).toBeTruthy();
  expect(readFileSync(path.join(ORIGINAL, 'src/source/live/ordering.ts'), 'utf8')).toContain('LIVE_ORDERING_RELEASED = false;');
  expect(readFileSync(path.join(APP, 'src/source/live/ordering.ts'), 'utf8')).toContain('LIVE_ORDERING_RELEASED = true;');
});

for (const locale of ['ar', 'he', 'en']) {
  for (const [index, width] of [390, 1024, 1440].entries()) {
    const terminal = (['accepted', 'rejected', 'expired'] as const)[index];
    test(`${locale} ${width}px: quantity + distinct notes → pending → ${terminal} → status reload`, async ({ page, context }) => {
      await page.setViewportSize({ width, height: 900 });
      const edge = await offlineEdge(context, page);
      const slug = `sf-browser-${locale}-${width}`;
      await prepare(page, locale, slug);
      await assertPage(page, locale); await picture(page, `${locale}-${width}-review.png`);
      await page.locator('[data-sf-cta="send"]').click();
      await expect(page.locator('[data-sf-live-status="pending"]')).toBeVisible();
      expect(edge.writes).toBe(1); expect(edge.ledger.size).toBe(1); assertPayload(edge.submissions[0]);
      await expect(page.locator('[data-sf-server-totals]')).toContainText('₪145.67');
      await expect(page.locator('[data-sf-status-action="order-again"]')).toHaveCount(0);
      await assertPrivateStorage(page, slug); await picture(page, `${locale}-${width}-pending.png`);
      edge.setState(terminal);
      await page.locator('[data-sf-status-action="refresh"]').click();
      await expect(page.locator(`[data-sf-live-status="${terminal}"]`)).toBeVisible();
      await page.reload({ waitUntil: 'networkidle' });
      await expect(page.locator(`[data-sf-live-status="${terminal}"]`)).toBeVisible();
      await expect(page).toHaveURL(`${BASE}${routeFor(locale, slug, 'review')}`);
      expect(edge.writes).toBe(1); expect(edge.ledger.size).toBe(1); expect(edge.actions.filter((action) => action.action === 'status').length).toBeLessThan(10);
      await assertPrivateStorage(page, slug); await assertPage(page, locale); await picture(page, `${locale}-${width}-${terminal}-reloaded.png`);
      await page.locator('[data-sf-status-action="order-again"]').click();
      await expect(page).toHaveURL(`${BASE}${routeFor(locale, slug, 'menu')}`);
      expect(await page.evaluate((owner) => sessionStorage.getItem(`bizbot:web-order:${owner}`), slug)).toBeNull();
      expect(edge.remote).toEqual([]); expect(edge.pageErrors).toEqual([]);
    });
  }
}

test('lost response after commit reconciles before reload and never repeats the saved request', async ({ page, context }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const edge = await offlineEdge(context, page, 'lost-commit'); const slug = 'sf-browser-lost-commit';
  await prepare(page, 'en', slug, false);
  await page.locator('[data-sf-cta="send"]').click();
  await expect(page.locator('[data-sf-live-status="pending"]')).toBeVisible();
  expect(edge.actions.slice(0, 2).map((action) => action.action)).toEqual(['submit', 'status']);
  expect(edge.writes).toBe(1); expect(edge.ledger.size).toBe(1); assertPayload(edge.submissions[0], false);
  edge.setState('accepted'); await page.reload({ waitUntil: 'networkidle' });
  await expect(page.locator('[data-sf-live-status="accepted"]')).toBeVisible();
  await expect(page).toHaveURL(`${BASE}${routeFor('en', slug, 'review')}`);
  expect(edge.writes).toBe(1); expect(edge.actions.filter((action) => action.action === 'status').length).toBeLessThan(10);
  expect(edge.pageErrors).toEqual([]);
});
test('not-found reconciliation permits only an explicit exact original retry; reload permits status only', async ({ page, context }) => {
  const edge = await offlineEdge(context, page, 'missing'); const slug = 'sf-browser-missing-retry';
  await prepare(page, 'en', slug, false); await page.locator('[data-sf-cta="send"]').click();
  await expect(page.locator('[data-sf-status-action="retry-original"]')).toBeVisible(); expect(edge.writes).toBe(1);
  await page.locator('[data-sf-status-action="retry-original"]').click();
  await expect(page.locator('[data-sf-live-status="pending"]')).toBeVisible(); expect(edge.writes).toBe(2); expect(edge.ledger.size).toBe(1);
  expect(JSON.stringify(edge.submissions[0]) === JSON.stringify(edge.submissions[1]), 'retry must retain the exact private body').toBe(true);
  await page.reload({ waitUntil: 'networkidle' }); await expect(page.locator('[data-sf-live-status="pending"]')).toBeVisible();
  expect(edge.writes).toBe(2); await expect(page.locator('[data-sf-status-action="retry-original"]')).toHaveCount(0);
});
test('tenant and capability separation prevents cross-tenant or substituted-token status reads', async ({ page, context }) => {
  const edge = await offlineEdge(context, page); const slug = 'sf-browser-owner-a';
  await prepare(page, 'en', slug, false); await page.locator('[data-sf-cta="send"]').click(); await expect(page.locator('[data-sf-live-status="pending"]')).toBeVisible();
  const forged = await page.evaluate(async ({ edgeURL, owner }) => {
    const saved = JSON.parse(sessionStorage.getItem(`bizbot:web-order:${owner}`)!);
    const wrongToken = saved.status_token[0] === 'A' ? `B${saved.status_token.slice(1)}` : `A${saved.status_token.slice(1)}`;
    const results = [];
    for (const [slug, status_token] of [[owner, wrongToken], ['sf-browser-owner-b', saved.status_token]]) {
      const response = await fetch(edgeURL, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', body: JSON.stringify({ action: 'status', slug, request_id: saved.request_id, status_token }) });
      results.push({ status: response.status, error: (await response.json()).error });
    }
    return results;
  }, { edgeURL: EDGE, owner: slug });
  expect(forged).toEqual([{ status: 404, error: 'not_found' }, { status: 404, error: 'not_found' }]);
  const reads = edge.actions.length;
  await page.goto(routeFor('en', 'sf-browser-owner-b', 'review'), { waitUntil: 'networkidle' });
  await expect(page.locator('[data-sf-live-status]')).toHaveCount(0); expect(edge.actions.length).toBe(reads);
  expect(edge.writes).toBe(1); await expect(page.locator('[data-sf-cta="send"]')).toHaveCount(0);
});
test('backend ordering flag OFF stays browse-only even in the isolated release-enabled copy', async ({ page, context }) => {
  const edge = await offlineEdge(context, page);
  await page.goto(routeFor('en', 'sf-browser-profile-off', 'menu'), { waitUntil: 'networkidle' });
  await expect(page.locator('[data-sf-notice="ordering-off"]')).toBeVisible();
  await page.goto(routeFor('en', 'sf-browser-profile-off', 'review'), { waitUntil: 'networkidle' });
  await expect(page).toHaveURL(`${BASE}${routeFor('en', 'sf-browser-profile-off', 'cart')}`);
  await expect(page.locator('[data-sf-cta="send"]')).toHaveCount(0); expect(edge.writes).toBe(0);
});
test('blocked session storage fails closed before any write and CSP blocks unapproved remote connections', async ({ page, context }) => {
  await context.addInitScript(() => {
    const set = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) { if (key.startsWith('bizbot:web-order:')) throw new DOMException('blocked synthetic storage', 'SecurityError'); set.call(this, key, value); };
  });
  const edge = await offlineEdge(context, page); const slug = 'sf-browser-blocked-storage';
  await prepare(page, 'en', slug, false); await page.locator('[data-sf-cta="send"]').click();
  await expect(page.locator('[data-sf-banner="order-failure"]')).toBeVisible(); expect(edge.writes).toBe(0);
  const blocked = await page.evaluate(async () => {
    const violations: string[] = [];
    document.addEventListener('securitypolicyviolation', (event) => violations.push(event.effectiveDirective));
    let failed = false;
    try { await fetch('https://unapproved.invalid/synthetic-verification', { credentials: 'omit' }); } catch { failed = true; }
    await new Promise((resolve) => setTimeout(resolve, 50));
    return { failed, violations };
  });
  expect(blocked.failed).toBe(true); expect(blocked.violations).toContain('connect-src'); expect(edge.remote).toEqual([]);
});
