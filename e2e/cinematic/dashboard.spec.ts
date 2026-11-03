import { test, expect, type BrowserContext, type Page, type Response, type Locator } from '@playwright/test';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { enableFlutterSemantics, waitForFlutterBoot, readAccessibleText } from '../lib/flutter';
import { controlGeometry } from './control-geometry.mjs';
import { fillField, fillPassword, tapButton, tapNav, tapText, selectDropdown } from '../lib/dashboard';

// This suite drives the shipped Flutter app. It never installs a mocked
// repository, injects a session, calls a privileged client, or writes SQL.
const API = 'http://127.0.0.1:54321';
const DASHBOARD = 'http://127.0.0.1:57026';
const STOREFRONT = 'http://127.0.0.1:3000';
const origins = new Set([API, DASHBOARD, STOREFRONT]);
const L = {
  login: 'تسجيل الدخول', email: 'البريد الإلكتروني', nav: 'الإعدادات',
  upload: 'رفع ونشر خلفية المنيو', save: 'حفظ المحتوى',
  selected: 'نُشرت الخلفية وتم اختيارها. احفظ لتطبيقها على المنيو.',
  saved: 'حُفظ المحتوى وأُعيدت قراءته.',
  unavailable: 'الخدمة غير متاحة؛ لم يُؤكد النجاح.',
  inherit: 'استخدام خلفية البداية', textColor: 'لون النص العام',
  buttonText: 'لون نص الأزرار', fontDefault: 'الخط الافتراضي للتصميم',
  fontAlexandria: 'الإسكندرية', fontRubik: 'روبيك', fontSystem: 'خط الجهاز',
  primary: 'لون الخلفية / اللون الأساسي', accent: 'لون الأزرار / اللون المميز',
  saveProfile: 'حفظ واجهة المتجر',
};
type Obj = Record<string, any>;
type Fixture = {
  apiUrl: string; anonKey: string;
  ownerA: { email: string; password: string; orgId: string; restaurantId: string; branchId: string; slug: string };
  heroMediaId: string; heroUrl: string; receiptLogoKey: string;
  initialInvariants: { logoMediaId: string | null; receiptLogoEnabled: boolean; receiptLogoVersion: number };
};
function fixture(): Fixture {
  const file = process.env.CINEMATIC_FIXTURE_FILE;
  if (process.env.CI !== 'true' || process.env.GITHUB_ACTIONS !== 'true' || process.env.CINEMATIC_EPHEMERAL !== 'BIZBOT-STOREFRONT-CINEMATIC-001B' || !file || !isAbsolute(file)) {
    throw new Error('Requires the authorized ephemeral CI stack and a private absolute fixture path.');
  }
  const f = JSON.parse(readFileSync(file, 'utf8')) as Fixture;
  if (f.apiUrl !== API || !f.anonKey || !f.heroMediaId || !f.receiptLogoKey ||
      !/^cinematic-[a-z0-9-]+$/.test(f.ownerA.slug) ||
      !f.ownerA.email.endsWith('@example.test')) {
    throw new Error('Unexpected fixture identity or endpoint; no acceptance request was sent.');
  }
  localUrl(f.heroUrl);
  return f;
}
function localUrl(value: string): URL {
  const u = new URL(value);
  if (!origins.has(u.origin) || u.username || u.password) throw new Error('Non-ephemeral endpoint rejected.');
  return u;
}
async function guardBrowser(context: BrowserContext): Promise<{ check: () => void; fontsReady: () => Promise<void>; fonts: () => string[] }> {
  let violation = false;
  const fonts = new Set<string>();
  context.on('response', response => {
    const u = new URL(response.url());
    if (u.origin === DASHBOARD && response.status() === 200) {
      if (u.pathname.startsWith('/cinematic-fonts/roboto/')) fonts.add('Roboto');
      if (u.pathname.startsWith('/cinematic-fonts/notosansarabic/')) fonts.add('Noto Sans Arabic');
    }
  });
  await context.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.protocol !== 'http:' || !origins.has(u.origin) || u.username || u.password) {
      violation = true;
      await route.abort('blockedbyclient');
      return;
    }
    await route.continue();
  });
  return {
    check: () => { if (violation) throw new Error('Browser attempted a non-ephemeral request.'); },
    fontsReady: async () => { await expect.poll(() => fonts.has('Roboto') && fonts.has('Noto Sans Arabic'), { message: 'Exact Flutter text fallback fonts load from loopback' }).toBe(true); },
    fonts: () => [...fonts].sort(),
  };
}
async function rpc(f: Fixture, token: string, name: string): Promise<Obj> {
  const response = await fetch(`${API}/rest/v1/rpc/${name}`, {
    method: 'POST', redirect: 'error',
    headers: { apikey: f.anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_organization_id: f.ownerA.orgId, p_restaurant_id: f.ownerA.restaurantId }),
  });
  if (!response.ok) throw new Error(`Owner read ${name} returned HTTP ${response.status}.`);
  const result = await response.json() as Obj;
  expect(result.ok, `Owner read ${name} succeeds`).toBe(true);
  return result;
}
function requestIs(response: Response, suffix: string): boolean {
  const u = new URL(response.url());
  return u.origin === API && u.pathname === suffix && response.request().method() === 'POST';
}
async function targetGeometry(page: Page, target: Locator) {
  if (!(await target.count())) return null;
  return target.first().evaluate(el => {
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    const pointerEvents = getComputedStyle(el).pointerEvents;
    const view = el.closest('flutter-view');
    const engineTags = ['FLT-SEMANTICS', 'FLT-SEMANTICS-CONTAINER', 'FLT-GLASS-PANE', 'FLT-SCENE-HOST', 'FLUTTER-VIEW'];
    const flutterSurfaceHit = hit !== null && view !== null && hit.closest('flutter-view') === view && engineTags.includes(hit.tagName);
    return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height),
      viewportWidth: innerWidth, viewportHeight: innerHeight, centerHit: hit === el || (hit !== null && el.contains(hit)),
      flutterSurfaceHit, hitSurface: hit !== null && engineTags.includes(hit.tagName) ? hit.tagName : 'other',
      disabled: el.getAttribute('aria-disabled') === 'true',
      pointerEvents: ['auto', 'all', 'none'].includes(pointerEvents) ? pointerEvents : 'other',
      hitRelation: hit === null ? 'none' : hit === el ? 'self' : el.contains(hit) ? 'descendant' : hit.contains(el) ? 'ancestor' : 'other' };
  });
}
class ControlRevealError extends Error {
  constructor(readonly samples: { iteration: number; geometry: Awaited<ReturnType<typeof targetGeometry>> }[]) {
    super('Dashboard control did not become visible and pointer-reachable.');
  }
}
async function reveal(page: Page, target: Locator): Promise<void> {
  const viewport = page.viewportSize()!;
  const samples: { iteration: number; geometry: Awaited<ReturnType<typeof targetGeometry>> }[] = [];
  await page.mouse.move(viewport.width / 2, viewport.height / 2);
  if (!(await target.count())) await page.mouse.wheel(0, -30_000);
  for (let i = 0; i < 80; i++) {
    const box = await targetGeometry(page, target);
    if (i % 8 === 0 || i === 79) samples.push({ iteration: i, geometry: box });
    const state = controlGeometry(box, viewport, box?.centerHit ?? false, box?.flutterSurfaceHit ?? false);
    if (state.ready) return;
    // Flutter Settings is a lazy native scrollable. Drive it with genuine
    // wheel input until this control is inside the content viewport and its
    // semantic node or the same Flutter view's input surface is hit-tested.
    await page.mouse.wheel(0, state.deltaY);
    await page.waitForTimeout(100);
  }
  throw new ControlRevealError(samples);
}
async function tapRevealedButton(page: Page, name: string): Promise<void> {
  const target = page.getByRole('button', { name, exact: true });
  await expect(target, 'The actual Flutter control is enabled').toBeEnabled();
  const box = await targetGeometry(page, target);
  expect(controlGeometry(box, page.viewportSize()!, box?.centerHit ?? false, box?.flutterSurfaceHit ?? false).ready,
    'The control is in the viewport with an unobstructed same-view Flutter input surface').toBe(true);
  if (box!.centerHit) return tapButton(page, name);
  // Send an ordinary physical pointer click through the actual Flutter input
  // surface. No force click, DOM event dispatch, or application callback.
  // The chooser/Storage/publisher/save assertions still prove the action.
  await page.mouse.click(box!.x + box!.width / 2, box!.y + box!.height / 2);
}
async function clickButton(page: Page, name: string): Promise<void> {
  await reveal(page, page.getByRole('button', { name, exact: true }));
  await tapRevealedButton(page, name);
}
async function fill(page: Page, name: string, value: string): Promise<void> {
  await reveal(page, page.getByRole('textbox', { name }));
  await fillField(page, name, value);
}
async function semantics(page: Page): Promise<void> {
  await waitForFlutterBoot(page);
  expect(await enableFlutterSemantics(page), 'Real Flutter semantics available').toBe(true);
}
async function textContains(page: Page, text: string): Promise<void> {
  await expect.poll(() => readAccessibleText(page)).toContain(text);
}
async function openEditor(page: Page, reload = false): Promise<void> {
  if (reload) await page.reload({ waitUntil: 'domcontentloaded' });
  await semantics(page);
  await tapNav(page, L.nav);
  await reveal(page, page.getByRole('button', { name: L.upload, exact: true }));
  await expect(page.getByRole('button', { name: L.upload, exact: true })).toBeEnabled();
}
async function saveContent(page: Page): Promise<void> {
  const saved = page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/set_restaurant_storefront_content_v1'));
  await clickButton(page, L.save);
  const response = await saved;
  expect(response.status(), 'Content writer HTTP result').toBe(200);
  expect((await response.json()).ok, 'Content writer accepted actual owner session').toBe(true);
  await textContains(page, L.saved);
}
async function invariants(f: Fixture, token: string): Promise<void> {
  const profile = await rpc(f, token, 'get_restaurant_storefront_profile');
  const logo = await rpc(f, token, 'get_restaurant_receipt_logo');
  expect(profile.profile.hero_media_id, 'Hero pointer unchanged').toBe(f.heroMediaId);
  expect(profile.profile.logo_media_id, 'Published logo pointer unchanged').toBe(f.initialInvariants.logoMediaId);
  expect(logo.receipt_logo_path, 'Receipt logo pointer unchanged').toBe(f.receiptLogoKey);
  expect(logo.receipt_logo_enabled, 'Receipt logo enabled state unchanged').toBe(f.initialInvariants.receiptLogoEnabled);
  expect(logo.receipt_logo_version, 'Receipt logo version unchanged').toBe(f.initialInvariants.receiptLogoVersion);
}
type UploadBoundary = 'reveal' | 'click' | 'filechooser' | 'file-set' | 'private-upload-response' | 'publisher-response' | 'upload-assertion';
type RouteClass = 'private-upload' | 'publisher' | 'auth' | 'private-read' | 'public-media' | 'application' | 'other-local' | 'external';
type Observed<T> = { ok: true; value: T } | { ok: false; error: unknown };
class UploadDiagnostics {
  private readonly started = Date.now();
  control: Awaited<ReturnType<typeof targetGeometry>> = null;
  private readonly events: { ms: number; boundary: string; event: string; status?: number }[] = [];
  private first: { ms: number; boundary: UploadBoundary; errorType: string; error: unknown } | null = null;
  private firstObservedWaitFailure: { ms: number; boundary: UploadBoundary; errorType: string } | null = null;
  private errorType(error: unknown): string {
    const name = error instanceof Error ? error.name : '';
    return ['TimeoutError', 'AssertionError', 'Error'].includes(name) ? name : 'OtherError';
  }
  mark(boundary: string, event: string, status?: number): void {
    // Names are controlled enums at call sites. Never retain URLs, request
    // bodies, headers, object keys, file names or browser exception messages.
    if (this.events.length < 64) this.events.push({ ms: Date.now() - this.started, boundary, event, ...(status === undefined ? {} : { status }) });
  }
  fail(boundary: UploadBoundary, error: unknown): void {
    if (this.first) return;
    this.first = { ms: Date.now() - this.started, boundary, errorType: this.errorType(error), error };
    this.mark(boundary, 'await-failed');
  }
  observe<T>(boundary: UploadBoundary, promise: Promise<T>): Promise<Observed<T>> {
    // Install BOTH handlers immediately, before any other await. A later
    // publisher timeout must not become an unhandled rejection that masks a
    // pending click, chooser or upload. Each result is deliberately settled.
    return promise.then(value => { this.mark(boundary, 'complete'); return { ok: true, value }; },
      error => {
        this.firstObservedWaitFailure ??= { ms: Date.now() - this.started, boundary, errorType: this.errorType(error) };
        this.mark(boundary, 'wait-failed');
        return { ok: false, error };
      });
  }
  async value<T>(boundary: UploadBoundary, promise: Promise<Observed<T>>): Promise<T> {
    const result = await promise;
    if (!result.ok) {
      // A future response waiter may expire while the UI click is still
      // pending. Preserve that observation, but never make it the active
      // operation's error. The first failed awaited boundary remains primary.
      this.fail(boundary, result.error);
      throw this.first?.error ?? result.error;
    }
    return result.value;
  }
  snapshot(): Obj {
    return { events: this.events, controlGeometry: this.control, firstObservedWaitFailure: this.firstObservedWaitFailure, firstFailure: this.first === null ? null : {
      ms: this.first.ms, boundary: this.first.boundary, errorType: this.first.errorType,
    } };
  }
  original(error: unknown): unknown { return this.first?.error ?? error; }
}
function routeClass(url: string): RouteClass {
  const u = new URL(url);
  if (!origins.has(u.origin)) return 'external';
  if (u.origin !== API) return 'application';
  if (u.pathname.startsWith('/storage/v1/object/restaurant-logos/')) return 'private-upload';
  if (u.pathname === '/functions/v1/storefront-media-publish') return 'publisher';
  if (u.pathname.startsWith('/auth/')) return 'auth';
  if (u.pathname.startsWith('/rest/')) return 'private-read';
  if (u.pathname.startsWith('/storage/v1/object/public/')) return 'public-media';
  return 'other-local';
}
async function upload(page: Page, filename: string, diagnostics: UploadDiagnostics, expectedStatus = 200): Promise<Obj> {
  const fixturePath = resolve(__dirname, '../../supabase/functions/storefront-media-publish/test/fixtures', filename);
  const onRequest = (request: import('@playwright/test').Request) => {
    const kind = routeClass(request.url());
    if (request.method() === 'POST' && (kind === 'private-upload' || kind === 'publisher')) diagnostics.mark(kind, 'request');
  };
  const onResponse = (response: Response) => {
    const kind = routeClass(response.url());
    if (response.request().method() === 'POST' && (kind === 'private-upload' || kind === 'publisher')) diagnostics.mark(kind, 'http', response.status());
  };
  const onFailed = (request: import('@playwright/test').Request) => diagnostics.mark(routeClass(request.url()), 'request-failed');
  page.on('request', onRequest);
  page.on('response', onResponse);
  page.on('requestfailed', onFailed);
  try {
    diagnostics.mark('reveal', 'started');
    const target = page.getByRole('button', { name: L.upload, exact: true });
    await diagnostics.value('reveal', diagnostics.observe('reveal', reveal(page, target)));
    diagnostics.control = await targetGeometry(page, target);
    const uploaded = diagnostics.observe('private-upload-response', page.waitForResponse(r => {
      const u = new URL(r.url());
      return u.origin === API && u.pathname.startsWith('/storage/v1/object/restaurant-logos/') && r.request().method() === 'POST';
    }));
    const published = diagnostics.observe('publisher-response', page.waitForResponse(r => requestIs(r, '/functions/v1/storefront-media-publish') && r.status() !== 202, { timeout: 120_000 }));
    const chosen = diagnostics.observe('filechooser', page.waitForEvent('filechooser'));
    diagnostics.mark('click', 'started');
    await diagnostics.value('click', diagnostics.observe('click', tapRevealedButton(page, L.upload)));
    const chooser = await diagnostics.value('filechooser', chosen);
    diagnostics.mark('file-set', 'started');
    await diagnostics.value('file-set', diagnostics.observe('file-set', chooser.setFiles(fixturePath)));
    expect((await diagnostics.value('private-upload-response', uploaded)).ok(), 'Actual private bytes upload').toBe(true);
    const response = await diagnostics.value('publisher-response', published);
    expect(response.status(), 'Actual Edge publication response').toBe(expectedStatus);
    const body = await response.json() as Obj;
    if (expectedStatus === 200) {
      expect(body.ok, 'Actual Edge publisher accepted bytes').toBe(true);
      await textContains(page, L.selected);
    } else {
      expect(body.status, 'Cross-source duplicate is rejected').toBe('object_conflict');
      await textContains(page, L.unavailable);
    }
    return body;
  } catch (error) {
    diagnostics.control = await targetGeometry(page, page.getByRole('button', { name: L.upload, exact: true })).catch(() => null);
    diagnostics.fail('upload-assertion', error);
    throw diagnostics.original(error);
  } finally {
    page.off('request', onRequest);
    page.off('response', onResponse);
    page.off('requestfailed', onFailed);
  }
}
async function editorStatus(page: Page): Promise<string[]> {
  // Only an allowlisted status enum escapes; accessible text stays private.
  const text = await readAccessibleText(page);
  const statuses = [
    ['background-selected', L.selected], ['content-saved', L.saved],
    ['service-unavailable', L.unavailable],
    ['upload-failed', 'تعذّر رفع الصورة.'],
    ['read-unavailable', 'تعذر التحقق من المحتوى.'],
    ['binding-changed', 'تغيّر الاتصال الموثّق'],
    ['publish-uncertain', 'نتيجة النشر غير مؤكدة.'],
  ];
  return statuses.filter(([, value]) => text.includes(value)).map(([key]) => key);
}
async function failureScreenshot(page: Page, path: string): Promise<string> {
  try {
    if (new URL(page.url()).origin !== DASHBOARD || await page.locator('input[type="password"]').count() ||
        !(await page.getByRole('button', { name: L.upload, exact: true }).count())) return 'withheld';
    await page.evaluate(() => {
      const label = document.createElement('div');
      label.textContent = 'ISOLATED CI — SYNTHETIC TEST DATA — FAILED ACCEPTANCE';
      label.setAttribute('data-cinematic-test-label', '');
      Object.assign(label.style, { position: 'fixed', bottom: '0', left: '0', zIndex: '2147483647', background: '#fff', color: '#111', padding: '8px', font: '12px sans-serif' });
      document.body.appendChild(label);
    });
    await page.screenshot({ path, timeout: 5000 });
    return 'captured';
  } catch { return 'unavailable'; }
  finally { await page.locator('[data-cinematic-test-label]').evaluateAll(nodes => nodes.forEach(n => n.remove())).catch(() => {}); }
}
async function readDim(page: Page): Promise<number> {
  const match = (await readAccessibleText(page)).match(/تعتيم الصورة:\s*(\d+)%/);
  if (!match) throw new Error('Image dimming UI value is unavailable.');
  return Number(match[1]);
}
async function setDim(page: Page, target: number): Promise<void> {
  const slider = page.getByRole('slider');
  await reveal(page, slider);
  await expect(slider, 'Exactly one menu dimming slider').toHaveCount(1);
  await slider.focus();
  let current = await readDim(page);
  if (current === target) return;
  // Up/down are Flutter's non-directional increase/decrease shortcuts; unlike
  // left/right their meaning is independent of RTL. divisions=80 gives step=1.
  for (let step = 0; step < 81 && current !== target; step++) {
    await page.keyboard.press(target > current ? 'ArrowUp' : 'ArrowDown');
    await expect.poll(() => readDim(page)).not.toBe(current);
    const next = await readDim(page);
    expect(Math.abs(next - current), 'Slider moves one integer dimming point').toBe(1);
    current = next;
  }
  expect(current, 'Exact dimming value').toBe(target);
}
async function backgroundUrl(f: Fixture, token: string, mediaId: string): Promise<string> {
  const media = await rpc(f, token, 'list_storefront_content_media_v1');
  const rows = media.media ?? media.rows;
  expect(Array.isArray(rows), 'Real content media rows').toBe(true);
  const row = (rows as Obj[]).find(r => r.id === mediaId);
  expect(Boolean(row), 'Selected published media remains listed').toBe(true);
  expect(row!.state).toBe('published');
  const url = `${API}/storage/v1/object/public/storefront-media/${row!.object_key}`;
  localUrl(url);
  const response = await fetch(url, { redirect: 'error' });
  expect(response.status, 'Published bytes stay publicly readable').toBe(200);
  expect(response.headers.get('content-type')).toContain('image/');
  expect((await response.arrayBuffer()).byteLength).toBeGreaterThan(0);
  return url;
}
async function renderMenu(page: Page, f: Fixture, image: string, dim: number | null, colours?: Obj): Promise<void> {
  const route = `${STOREFRONT}/s/${f.ownerA.slug}/menu`;
  localUrl(route);
  // The real application has 60s ISR. Poll normal reloads (no cache/reader
  // overrides) until the newly saved projection is visible, within 100s.
  await expect.poll(async () => {
    await page.goto(route, { waitUntil: 'domcontentloaded' });
    const bg = dim === null
      ? page.locator('main[data-sf-screen="home"] > div[aria-hidden="true"] img').first()
      : page.locator('[data-sf-menu-background="custom"] > img');
    if (!(await bg.count())) return false;
    const root = page.locator('[data-sf-root]');
    const actual = await root.evaluate(el => {
      const s = getComputedStyle(el);
      return { dim: s.getPropertyValue('--menu-image-dim').trim(), tx: s.getPropertyValue('--tx').trim(), onacc: s.getPropertyValue('--onacc').trim(), bg: s.getPropertyValue('--bg').trim(), acc: s.getPropertyValue('--acc').trim(), font: (el as HTMLElement).style.getPropertyValue('--font'), resolvedFont: s.getPropertyValue('--font').trim(), renderedFont: s.fontFamily };
    });
    return await bg.getAttribute('src') === image &&
      (dim === null || Number(actual.dim) === dim / 100) &&
      (!colours || (actual.resolvedFont.length > 0 && actual.renderedFont.replaceAll('\"', '').replaceAll("'", '').replaceAll(' ', '') === actual.resolvedFont.replaceAll('\"', '').replaceAll("'", '').replaceAll(' ', '') && actual.tx === colours.text && actual.onacc === colours.button && actual.bg === colours.primary && actual.acc === colours.accent && actual.font.includes(colours.font)));
  }, { timeout: 100_000, intervals: [1000, 3000, 5000] }).toBe(true);
  await expect(page.locator('[data-sf-root]')).toHaveAttribute('dir', 'rtl');
  if (dim === null) await expect(page.locator('[data-sf-menu-background="custom"]')).toHaveCount(0);
  const bg = page.locator('main[data-sf-screen="home"] > div[aria-hidden="true"] img').first();
  await expect.poll(() => bg.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
}
async function verifyMenuGeometry(page: Page): Promise<void> {
  const sections = page.locator('[data-sf-module="sections"]');
  await expect(sections, 'All four synthetic menu categories remain present').toHaveCount(4);
  const layer = await page.locator('[data-sf-menu-background="custom"]').boundingBox();
  const first = await sections.first().boundingBox();
  const last = await sections.last().boundingBox();
  expect(Boolean(layer && first && last), 'Menu/background geometry is measurable').toBe(true);
  expect(layer!.y).toBeLessThanOrEqual(first!.y);
  expect(layer!.y + layer!.height).toBeGreaterThanOrEqual(last!.y + last!.height);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'No horizontal viewport overflow').toBe(true);
}
async function screenshot(page: Page, path: string): Promise<void> {
  // Load every section and lazy image before a full-page capture.
  for (const section of await page.locator('[data-sf-module="sections"]').all()) await section.scrollIntoViewIfNeeded();
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all(Array.from(document.images, img => img.decode()));
    const label = document.createElement('div');
    label.textContent = 'ISOLATED CI — SYNTHETIC TEST DATA';
    label.setAttribute('data-cinematic-test-label', '');
    Object.assign(label.style, { position: 'fixed', bottom: '0', left: '0', zIndex: '2147483647', background: '#fff', color: '#111', padding: '8px', font: '12px sans-serif' });
    document.body.appendChild(label);
    window.scrollTo(0, 0);
  });
  await page.screenshot({ path, fullPage: true });
  await page.locator('[data-cinematic-test-label]').evaluateAll(nodes => nodes.forEach(n => n.remove()));
}

test('real owner Dashboard → Storage → publisher → save → live menu; replacement, clear and appearance', async ({ page, context }) => {
  const f = fixture();
  const network = await guardBrowser(context);
  const out = resolve(process.env.CINEMATIC_ARTIFACT_DIR ?? 'cinematic-artifacts');
  mkdirSync(out, { recursive: true });
  const stages: string[] = [];
  let stage = 'login';
  const uploadDiagnostics: UploadDiagnostics[] = [];
  const nextUpload = () => { const diagnostics = new UploadDiagnostics(); uploadDiagnostics.push(diagnostics); return diagnostics; };
  try {
    await page.goto(DASHBOARD, { waitUntil: 'domcontentloaded' });
    await semantics(page);
    await network.fontsReady();
    await fillField(page, L.email, f.ownerA.email);
    await fillPassword(page, f.ownerA.password);
    const signedIn = page.waitForResponse(r => requestIs(r, '/auth/v1/token'));
    await tapButton(page, L.login, { which: 'last' });
    const auth = await signedIn;
    expect(auth.status(), 'Actual Dashboard password sign-in succeeds').toBe(200);
    const session = await auth.json();
    expect(session.user.email, 'Signed in as the synthetic owner A').toBe(f.ownerA.email);
    const token: string = session.access_token;
    expect(typeof token, 'Auth issued a user token').toBe('string');
    // Token stays in memory, never in snapshots, report fields, traces or logs.
    stages.push(stage);
    stage = 'open-editor';
    await openEditor(page);
    await invariants(f, token);
    stages.push(stage);

    stage = 'upload-publish-select-save-reload';
    await upload(page, 'base_420_900x450.jpg', nextUpload());
    await saveContent(page);
    const first = (await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance.menu_background_media_id as string;
    expect(first).not.toBe(f.heroMediaId);
    const firstUrl = await backgroundUrl(f, token, first);
    await openEditor(page, true);
    await invariants(f, token);
    const menu = await context.newPage();
    await renderMenu(menu, f, firstUrl, 15);
    stages.push(stage);

    stage = 'profile-colours';
    await fill(page, L.primary, '#211A16');
    await fill(page, L.accent, '#EAB082');
    const profileSaved = page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/set_restaurant_storefront_profile'));
    await clickButton(page, L.saveProfile);
    expect((await (await profileSaved).json()).ok).toBe(true);
    await openEditor(page, true);
    stages.push(stage);

    for (const [dim, fromFont, label, font] of [
      [0, L.fontDefault, L.fontAlexandria, 'alexandria'],
      [15, L.fontAlexandria, L.fontRubik, 'rubik'],
      [80, L.fontRubik, L.fontSystem, 'system'],
    ] as const) {
      stage = `appearance-${dim}`;
      await fill(page, L.textColor, '#FFF1DA');
      await fill(page, L.buttonText, '#20140C');
      await reveal(page, page.getByRole('button', { name: fromFont, exact: false }));
      await selectDropdown(page, fromFont, label);
      await setDim(page, dim);
      await saveContent(page);
      await openEditor(page, true);
      const a = (await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance;
      expect(a.menu_background_dim, 'Explicit dimming survives save and reread').toBe(dim);
      expect(a.text_color).toBe('#fff1da');
      expect(a.button_text_color).toBe('#20140c');
      expect(a.font_family).toBe(font);
      await textContains(page, label);
      expect(await readDim(page)).toBe(dim);
      await renderMenu(menu, f, firstUrl, dim, {
        text: '#fff1da', button: '#20140c', primary: '#211a16', accent: '#eab082',
        font: font === 'alexandria' ? 'SF Alexandria' : font === 'system' ? 'system-ui' : 'sf-font-latin',
      });
      await invariants(f, token);
      stages.push(stage);
    }

    stage = 'replace-background';
    await upload(page, 'base_444_1200x900.jpg', nextUpload());
    await saveContent(page);
    const second = (await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance.menu_background_media_id as string;
    expect(second).not.toBe(first);
    const secondUrl = await backgroundUrl(f, token, second);
    await openEditor(page, true);
    await invariants(f, token);
    await renderMenu(menu, f, secondUrl, 80);
    stages.push(stage);

    stage = 'duplicate-source-rejected';
    await upload(page, 'base_420_900x450.jpg', nextUpload(), 409);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance.menu_background_media_id).toBe(second);
    await invariants(f, token);
    await openEditor(page, true);
    stages.push(stage);

    stage = 'actual-services-screenshots';
    await setDim(page, 15);
    await saveContent(page);
    await renderMenu(menu, f, secondUrl, 15);
    await verifyMenuGeometry(menu);
    await screenshot(menu, resolve(out, 'storefront-desktop-test-data.png'));
    await menu.setViewportSize({ width: 390, height: 844 });
    await verifyMenuGeometry(menu);
    await screenshot(menu, resolve(out, 'storefront-mobile-test-data.png'));
    await reveal(page, page.getByRole('slider'));
    await page.getByRole('slider').scrollIntoViewIfNeeded();
    await screenshot(page, resolve(out, 'dashboard-test-data.png'));
    stages.push(stage);

    stage = 'clear-selection-fallback-media-retained';
    await reveal(page, page.getByRole('button', { name: new RegExp(second.slice(0, 8)) }));
    await page.getByRole('button', { name: new RegExp(second.slice(0, 8)) }).first().click();
    await tapText(page, L.inherit, 'last');
    await saveContent(page);
    await openEditor(page, true);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance.menu_background_media_id).toBeNull();
    await invariants(f, token);
    await backgroundUrl(f, token, first);
    await backgroundUrl(f, token, second);
    await renderMenu(menu, f, f.heroUrl, null);
    stages.push(stage);

    stage = 'clear-shared-hero-media-retained';
    await reveal(page, page.getByRole('button', { name: new RegExp(L.inherit) }));
    await page.getByRole('button', { name: new RegExp(L.inherit) }).first().click();
    await tapText(page, f.heroMediaId.slice(0, 8), 'last');
    await saveContent(page);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance.menu_background_media_id).toBe(f.heroMediaId);
    await invariants(f, token);
    await reveal(page, page.getByRole('button', { name: new RegExp(f.heroMediaId.slice(0, 8)) }));
    await page.getByRole('button', { name: new RegExp(f.heroMediaId.slice(0, 8)) }).first().click();
    await tapText(page, L.inherit, 'last');
    await saveContent(page);
    await openEditor(page, true);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v2')).document.appearance.menu_background_media_id).toBeNull();
    await invariants(f, token);
    await backgroundUrl(f, token, f.heroMediaId);
    await renderMenu(menu, f, f.heroUrl, null);
    stages.push(stage);
    network.check();
    writeFileSync(resolve(out, 'dashboard-result.json'), JSON.stringify({ status: 'PASS', data: 'synthetic ephemeral services', stages, fonts: network.fonts(), uploads: uploadDiagnostics.map(d => d.snapshot()) }, null, 2));
  } catch (error) {
    const statuses = stages.includes('login') ? await editorStatus(page).catch(() => ['unreadable']) : [];
    const failureCapture = stages.includes('login')
      ? await failureScreenshot(page, resolve(out, 'dashboard-failure-test-data.png')) : 'withheld';
    writeFileSync(resolve(out, 'dashboard-result.json'), JSON.stringify({ status: 'FAIL', data: 'synthetic ephemeral services', failedStage: stage, completedStages: stages,
      fonts: network.fonts(), controlReveal: error instanceof ControlRevealError ? error.samples : null,
      uploads: uploadDiagnostics.map(d => d.snapshot()), editorStatuses: statuses, failureScreenshot: failureCapture }, null, 2));
    throw error;
  }
});
