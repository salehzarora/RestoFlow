import { test, expect, type BrowserContext, type Page, type Response, type Locator } from '@playwright/test';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, resolve } from 'node:path';
import { enableFlutterSemantics, waitForFlutterBoot, readAccessibleText } from '../lib/flutter';
import { controlGeometry, visibleGeometry } from './control-geometry.mjs';
import { MAX_REVEAL_WHEELS, nextRevealMove, observeResponse, responseAfterAction } from './control-progress.mjs';
import { isPasswordGrantRequest, authRequestEvidence, authResponseEvidence } from './auth-diagnostics.mjs';
import { LOGICAL_ORIGIN, localMediaTarget, logicalMediaUrl } from './live-transport.mjs';
import { createHash, randomUUID } from 'node:crypto';
import { bannerGeometry, baselineBannerEvidence, replayBaselineBanner, bannerViewportScreenshot, completeResponsiveFixture, responsiveFixtureMismatch } from './banner-responsive';
import { verifyResponsiveBannerSettings, adjustBannerHeightWithKeyboard } from './responsive-banner-settings';
import { dashboardImageHash, dashboardImageBytesMatch, dashboardMediaReady } from './responsive-banner-settings.mjs';
import { BackgroundQuality, backgroundFixture } from './background-quality';
import { companionStatus, classifyCompanion, type CompanionUi } from './companion-observer';
import { fillField, tapButton, tapNav, tapText } from '../lib/dashboard';

// This suite drives the shipped Flutter app. It never installs a mocked
// repository, calls a privileged client, or writes SQL. Auth acceptance signs in
// through the UI. The separate short video copies only that synthetic CI state
// in memory; it never substitutes for the real sign-in/save acceptance.
const API = 'http://127.0.0.1:54321';
const DASHBOARD = 'http://127.0.0.1:57026';
const STOREFRONT = 'http://127.0.0.1:3000';
const origins = new Set([API, DASHBOARD, STOREFRONT]);
const L = {
  login: 'تسجيل الدخول', email: 'البريد الإلكتروني', nav: 'الإعدادات',
  profileAppearance: 'المظهر', contentAppearance: 'مظهر النصوص',
  backgroundAndScene: 'خلفية المنيو والمشهد', mediaLibrary: 'الصور المنشورة',
  upload: 'رفع ونشر خلفية المنيو', save: 'حفظ المحتوى',
  selected: 'نُشرت الخلفية وتم اختيارها. احفظ لتطبيقها على المنيو.',
  saved: 'حُفظ المحتوى وأُعيدت قراءته.',
  unavailable: 'الخدمة غير متاحة؛ لم يُؤكد النجاح.',
  inherit: 'استخدام خلفية البداية', textColor: 'لون النص العام',
  buttonText: 'لون نص الأزرار', fontDefault: 'الخط الافتراضي للتصميم',
  fontAlexandria: 'الإسكندرية', fontRubik: 'روبيك', fontSystem: 'خط الجهاز',
  primary: 'لون الخلفية / اللون الأساسي', accent: 'لون الأزرار / اللون المميز',
  saveProfile: 'حفظ واجهة المتجر',
  advanced: 'متقدم', apply: 'تطبيق على المسودة', cancel: 'إلغاء',
  saturation: 'التشبع / السطوع', hue: 'درجة اللون',
  scenePreview: 'معاينة مظهر المشهد', sceneReference: 'مرجع داكن محايد', sceneLegacy: 'استخدام مشهد العلامة',
  siteThemeLegacy: 'إبقاء المظهر الحالي (توافق سابق)', siteThemeLight: 'فاتح / أبيض', siteThemeDark: 'داكن',
  bannerTitle: 'بانر المنيو العلوي', bannerUpload: 'رفع بانر جديد', bannerClear: 'مسح اختيار البانر',
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
async function guardBrowser(context: BrowserContext) {
  let violation = false;
  const fonts = new Set<string>();
  const mediaHashes = new Map<unknown, string>();
  const mediaChecks: Promise<boolean>[] = [];
  let mappedMedia = 0, verifiedMediaBytes = 0;
  const directMediaChecks: Promise<boolean>[] = [];
  let directMedia = 0, verifiedDirectMediaBytes = 0;
  context.on('request', request => {
    const u = new URL(request.url());
    if (u.origin !== API || !u.pathname.startsWith('/storage/v1/object/public/storefront-media/') || request.resourceType() !== 'image') return;
    directMedia++;
    // Passive native-response observation only: no fetch, fulfillment, header
    // forwarding or origin admission change. Failed requests remain failures.
    directMediaChecks.push((async () => {
      const hash = dashboardImageHash({ url: request.url(), method: request.method(), resourceType: request.resourceType(), headers: await request.allHeaders() });
      const response = await request.response();
      if (!response || response.url() !== request.url()) return false;
      const equal = dashboardImageBytesMatch(hash, response.status(), await response.body());
      if (equal) verifiedDirectMediaBytes++;
      return equal;
    })().catch(() => false));
  });
  context.on('response', response => {
    const u = new URL(response.url());
    if (u.origin === DASHBOARD && response.status() === 200) {
      if (u.pathname.startsWith('/cinematic-fonts/roboto/')) fonts.add('Roboto');
      if (u.pathname.startsWith('/cinematic-fonts/notosansarabic/')) fonts.add('Noto Sans Arabic');
    }
    const expectedHash = mediaHashes.get(response.request());
    if (expectedHash) mediaChecks.push(response.body().then(bytes => {
      const equal = createHash('sha256').update(bytes).digest('hex') === expectedHash;
      if (equal) verifiedMediaBytes++;
      return equal;
    }).catch(() => false));
  });
  await context.route('**/*', async route => {
    const u = new URL(route.request().url());
    if (u.origin === LOGICAL_ORIGIN) {
      try {
        const request = route.request();
        const target = localMediaTarget(request.url(), request.method());
        const headers = await request.allHeaders();
        if (request.resourceType() !== 'image' || headers.authorization || headers.apikey || headers.cookie) throw new Error('Media credentials rejected');
        // Genuine bytes from the running local Storage service. No browser
        // credential/header is forwarded, no redirect or external fallback.
        const response = await fetch(target, { redirect: 'error', signal: AbortSignal.timeout(15_000) });
        if (response.headers.get('content-encoding') && response.headers.get('content-encoding') !== 'identity') throw new Error('Unexpected media encoding');
        const body = Buffer.from(await response.arrayBuffer());
        mediaHashes.set(request, createHash('sha256').update(body).digest('hex'));
        mappedMedia++;
        const responseHeaders: Record<string, string> = {};
        response.headers.forEach((value, key) => { responseHeaders[key] = value; });
        await route.fulfill({ status: response.status, headers: responseHeaders, body });
      } catch {
        violation = true;
        await route.abort('blockedbyclient');
      }
      return;
    }
    if (u.protocol !== 'http:' || !origins.has(u.origin) || u.username || u.password) {
      violation = true;
      await route.abort('blockedbyclient');
      return;
    }
    if (route.request().method() === 'POST' && u.pathname === '/functions/v1/web-order-submit') {
      violation = true;
      await route.abort('blockedbyclient');
      return;
    }
    await route.continue();
  });
  return {
    check: async () => {
      if (violation) throw new Error('Browser attempted a non-ephemeral request.');
      expect(mappedMedia, 'Live media uses actual local Storage responses').toBeGreaterThan(0);
      expect((await Promise.all(mediaChecks)).every(Boolean), 'Browser receives identical actual Storage bytes').toBe(true);
      expect(verifiedMediaBytes).toBe(mappedMedia);
    },
    media: () => ({ mappedMedia, verifiedMediaBytes }),
    checkDashboardMedia: async (recordEvidence: (value: Obj) => void) => {
      if (violation) throw new Error('Browser attempted a non-ephemeral request.');
      const checks = await Promise.all(directMediaChecks);
      const nativeMedia = { directMedia, verifiedDirectMediaBytes, checkedResponses: checks.length,
        failedResponses: checks.filter(value => !value).length };
      recordEvidence(nativeMedia);
      expect(dashboardMediaReady(directMedia, verifiedDirectMediaBytes, checks),
        'Native Dashboard public images have canonical credential-free requests and exact content-addressed Storage bytes').toBe(true);
      return nativeMedia;
    },
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
async function enterLoginPassword(page: Page, password: string): Promise<void> {
  const input = page.locator('input[type="password"]').first();
  await input.click();
  await expect.poll(() => input.evaluate(el => el.matches(':focus')), {
    message: 'Actual Dashboard password control receives focus',
  }).toBe(true);
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Delete');
  const matches = (expected: string) => input.evaluate((el, value) =>
    el instanceof HTMLInputElement && el.value === value, expected);
  await expect.poll(() => matches(''), {
    message: 'Actual Dashboard password control is cleared by keyboard input',
  }).toBe(true);
  // The preceding real run submitted a value different from the fixture.
  // Confirm each ordinary key's rendered prefix before entering the next one.
  // No refilling, sign-in retry, DOM value assignment or secret-valued assertion.
  let prefix = '';
  for (const character of password) {
    await page.keyboard.type(character);
    prefix += character;
    await expect.poll(() => matches(prefix), {
      message: 'Actual Dashboard password control reflects the entered prefix',
    }).toBe(true);
  }
  await page.keyboard.press('Tab');
  await expect.poll(() => matches(password), {
    message: 'Complete Dashboard password remains correct after blur',
  }).toBe(true);
}
async function targetGeometry(page: Page, target: Locator) {
  // Expansion can replace a semantics node between Playwright calls.
  // Observe presence and geometry in one sample of the current nodes.
  return target.evaluateAll(matches => {
    if (matches.length !== 1) return null;
    const el = matches[0];
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
type RevealPurpose = 'upload' | 'content-save' | 'content-status' | 'background-status' | 'profile-save' | 'field' | 'dimming' | 'other';
type ScrollScope = { x: number; y: number; width: number; height: number; source: 'target' | 'editor-anchor' | 'cached' | 'settings-gutter'; kind: 'clipping-ancestor' | 'flutter-view' | 'settings-viewport' };
type RevealSample = { iteration: number; geometry: Awaited<ReturnType<typeof targetGeometry>>; hiddenGeometry: Awaited<ReturnType<typeof targetGeometry>>; normalMatches: number; hiddenMatches: number; labelEvidence: { exact: number; normalized: number; button: number; hidden: number; textExact: number; textNormalized: number; textButton: number } | null; progressed: boolean | null; visibleNodes: number; surface: ScrollScope; direction: number; reversed: boolean };
type RevealTrace = { purpose: RevealPurpose; result: 'ready' | 'stalled' | 'ambiguous' | 'iteration-limit' | 'disabled'; wheelSteps: number; samples: RevealSample[] };
const revealTraces = new WeakMap<Page, RevealTrace[]>();
const clickTraces = new WeakMap<Page, { modal: boolean; method: 'physical' | 'locator'; geometry: Awaited<ReturnType<typeof targetGeometry>> }[]>();
const scrollScopes = new WeakMap<Page, ScrollScope>();
class ControlRevealError extends Error {
  constructor(readonly purpose: RevealPurpose, readonly samples: RevealSample[]) {
    super('Dashboard control did not become visible and pointer-reachable.');
  }
}
async function scrollScope(page: Page, target: Locator): Promise<ScrollScope> {
  const anchors = [target, page.getByRole('button', { name: L.upload, exact: true }),
    page.getByRole('textbox', { name: L.textColor }), page.getByRole('button', { name: L.saveProfile, exact: true })];
  for (let index = 0; index < anchors.length; index++) {
    const box = await anchors[index].evaluateAll(matches => {
      if (matches.length !== 1) return null;
      const el = matches[0];
      const own = el.getBoundingClientRect();
      if (own.width <= 0 || own.height <= 0 || own.bottom <= 96 || own.top >= innerHeight - 64) return null;
      const view = el.closest('flutter-view');
      if (!view) return null;
      let surface: Element = view;
      let kind: 'clipping-ancestor' | 'flutter-view' = 'flutter-view';
      // Use the actual control's rendered clipping ancestor; no Flutter Key is
      // assumed to become a DOM id and no hidden semantic node is clicked.
      for (let node = el.parentElement; node && node !== view; node = node.parentElement) {
        const r = node.getBoundingClientRect(), style = getComputedStyle(node);
        if (/auto|scroll|hidden|clip/.test(style.overflowY) && r.width > innerWidth / 2 && r.height > 240) {
          surface = node; kind = 'clipping-ancestor'; break;
        }
      }
      const r = surface.getBoundingClientRect(), top = Math.max(96, r.top), bottom = Math.min(innerHeight - 64, r.bottom);
      const left = Math.max(0, r.left), right = Math.min(innerWidth, r.right);
      if (bottom - top < 160 || right - left < 160) return null;
      return { x: Math.round(left + Math.min(24, (right - left) / 10)), y: Math.round((top + bottom) / 2),
        width: Math.round(right - left), height: Math.round(bottom - top), kind };
    });
    if (box) {
      const scope: ScrollScope = { ...box, source: index === 0 ? 'target' : 'editor-anchor' };
      scrollScopes.set(page, scope);
      return scope;
    }
  }
  const cached = scrollScopes.get(page);
  if (cached) return { ...cached, source: 'cached' };
  // Initial navigation can have no materialized editor control yet. Keep the
  // previously observed RTL Settings gutter explicit in the diagnostic record.
  const viewport = page.viewportSize()!;
  return { x: 24, y: Math.round(viewport.height / 2), width: viewport.width,
    height: viewport.height - 160, source: 'settings-gutter', kind: 'settings-viewport' };
}
async function renderedProgress(page: Page, scope: ScrollScope): Promise<{ signature: string; visibleNodes: number }> {
  return page.evaluate(({ x, width }) => {
    const parts: string[] = [];
    for (const el of Array.from(document.querySelectorAll('flt-semantics, [id^="flt-semantic-node-"]'))) {
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0 || r.bottom <= 96 || r.top >= innerHeight - 64 || r.right < x || r.left > x + width) continue;
      // Only transient identity and geometry are compared in memory. Neither
      // labels, values, IDs nor this signature are exported in the artifact.
      parts.push([el.id, Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height),
        Math.round(el.scrollTop), Math.round(el.scrollHeight)].join(':'));
    }
    return { signature: parts.join('|'), visibleNodes: parts.length };
  }, scope);
}
async function settleScroll(page: Page, scope: ScrollScope, requireStable = false): Promise<{ signature: string; visibleNodes: number }> {
  let previous = await renderedProgress(page, scope), stable = 0;
  // Observe several settled rendered samples rather than outrunning Flutter's
  // semantics updates with a fixed series of large wheel movements.
  for (let i = 0; i < 16; i++) {
    await page.waitForTimeout(50);
    const current = await renderedProgress(page, scope);
    stable = current.signature === previous.signature ? stable + 1 : 0;
    previous = current;
    if (stable >= 3) return current;
  }
  if (requireStable) throw new Error('Dashboard control geometry did not settle.');
  return previous;
}
async function reveal(page: Page, target: Locator, purpose: RevealPurpose = 'other', hiddenTarget = target): Promise<void> {
  const viewport = page.viewportSize()!;
  const samples: RevealSample[] = [];
  const trace: RevealTrace = { purpose, result: 'iteration-limit', wheelSteps: 0, samples };
  const traces = revealTraces.get(page) ?? [];
  if (traces.length < 80) traces.push(trace);
  revealTraces.set(page, traces);
  // Content status lives above this long form; Save is at its bottom. Start
  // that observed scan upward while retaining the same progress/end bounds.
  let state = { direction: purpose === 'content-status' ? -1 : 1, reversed: false, stalled: 0, wheelSteps: 0 };
  let progressed: boolean | null = null;
  // Start where the owner actually is and scan nearby controls first. The
  // Settings editor keeps its draft alive while it moves outside the viewport.
  // Keep the original maximum of 80 physical wheels. Actual settling is
  // observed between them; progress/end detection is the normal stop condition.
  for (let i = 0; i <= MAX_REVEAL_WHEELS; i++) {
    const normalMatches = await target.count(), hiddenMatches = await hiddenTarget.count();
    const box = normalMatches === 1 ? await targetGeometry(page, target) : null;
    const hiddenGeometry = normalMatches === 0 && hiddenMatches === 1 ? await targetGeometry(page, hiddenTarget) : null;
    const scope = await scrollScope(page, target);
    const before = await renderedProgress(page, scope);
    const labelEvidence = purpose !== 'content-save' ? null : await page.evaluate(name => {
      const normalize = (value: string) => value.replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').replace(/\s+/g, ' ').trim();
      let exact = 0, normalized = 0, button = 0, hidden = 0, textExact = 0, textNormalized = 0, textButton = 0;
      for (const el of Array.from(document.querySelectorAll('flt-semantics, [id^="flt-semantic-node-"]'))) {
        const label = el.getAttribute('aria-label');
        // Flutter's button name can be text content rather than aria-label.
        // Export only counts, never the surrounding rendered fixture values.
        const text = el.textContent;
        if (text === name) textExact++;
        if (text !== null && normalize(text) === normalize(name)) {
          textNormalized++;
          if (el.getAttribute('role') === 'button') textButton++;
        }
        if (label === name) exact++;
        if (label !== null && normalize(label) === normalize(name)) {
          normalized++;
          if (el.getAttribute('role') === 'button') button++;
          if (el.getAttribute('aria-hidden') === 'true') hidden++;
        }
      }
      return { exact, normalized, button, hidden, textExact, textNormalized, textButton };
    }, L.save);
    const sample: RevealSample = { iteration: i, geometry: box, hiddenGeometry, normalMatches, hiddenMatches, labelEvidence, progressed,
      visibleNodes: before.visibleNodes, surface: scope, direction: state.direction, reversed: state.reversed };
    // Retain every step: only bounded numeric geometry/counts and fixed enums.
    samples.push(sample);
    if (normalMatches > 1) { trace.result = 'ambiguous'; break; }
    const geometry = controlGeometry(box, viewport, box?.centerHit ?? false, box?.flutterSurfaceHit ?? false);
    const statusOnly = purpose === 'content-status' || purpose === 'background-status';
    const readableStatus = statusOnly && visibleGeometry(box, viewport);
    if ((readableStatus || geometry.ready) && await target.isVisible()) {
      if (!statusOnly) {
        // Flutter temporarily disables its native range input after pointer
        // input; observe it re-enable before allowing keyboard interaction.
        try { await expect(target, 'Revealed control settles enabled').toBeEnabled(); }
        catch { trace.result = 'disabled'; break; }
      }
      trace.result = 'ready';
      return;
    }
    // A hidden semantic rectangle may steer ordinary wheel input; only the
    // normal visible, enabled locator can ever satisfy readiness or be clicked.
    const observedBox = box ?? (hiddenGeometry && hiddenGeometry.width > 0 && hiddenGeometry.height > 0 &&
      [hiddenGeometry.x, hiddenGeometry.y, hiddenGeometry.width, hiddenGeometry.height].every(Number.isFinite) ? hiddenGeometry : null);
    const observedDirection = controlGeometry(observedBox, viewport, false).deltaY;
    const move = nextRevealMove(state, { progressed, targetDelta: observedBox === null ? null : observedDirection,
      step: Math.max(80, Math.floor(scope.height * 0.4)) });
    state = move;
    if (move.stop) { trace.result = move.termination!; break; }
    await page.mouse.move(scope.x, scope.y);
    await page.mouse.wheel(0, move.delta);
    trace.wheelSteps++;
    const after = await settleScroll(page, scope);
    progressed = after.signature !== before.signature;
  }
  throw new ControlRevealError(purpose, samples);
}
async function tapRevealedControl(page: Page, target: Locator, modal = false): Promise<void> {
  await expect(target, 'The actual Flutter control is enabled').toBeEnabled();
  const box = await targetGeometry(page, target);
  const viewport = page.viewportSize()!;
  // Modal footer buttons occupy the real viewport's bottom edge; the editor's
  // reserved header/footer insets apply only to controls behind the modal.
  const ready = modal
    ? box !== null && box.width > 0 && box.height > 0 && box.x >= 0 && box.y >= 0 &&
      box.x + box.width <= viewport.width && box.y + box.height <= viewport.height &&
      (box.centerHit || box.flutterSurfaceHit)
    : controlGeometry(box, viewport, box?.centerHit ?? false, box?.flutterSurfaceHit ?? false).ready;
  expect(ready,
    'The control is in the viewport with an unobstructed same-view Flutter input surface').toBe(true);
  // This is pre-click geometry. It determines the physical click coordinates;
  // locator.click can auto-wait/recompute them. No label, value or credential.
  const clicks = clickTraces.get(page) ?? [];
  if (clicks.length < 160) clicks.push({ modal, method: box!.centerHit ? 'locator' : 'physical', geometry: box });
  clickTraces.set(page, clicks);
  if (box!.centerHit) return target.click();
  // Send an ordinary physical pointer click through the actual Flutter input
  // surface. No force click, DOM event dispatch, or application callback.
  // The chooser/Storage/publisher/save assertions still prove the action.
  await page.mouse.click(box!.x + box!.width / 2, box!.y + box!.height / 2);
}
async function tapRevealedButton(page: Page, name: string, modal = false): Promise<void> {
  await tapRevealedControl(page, page.getByRole('button', { name, exact: true }), modal);
}
async function selectRevealedDropdown(page: Page, current: string | RegExp, option: string): Promise<void> {
  await tapRevealedControl(page, page.getByRole('button', { name: current, exact: false }));
  await tapText(page, option, 'last');
}
async function revealButton(page: Page, name: string): Promise<void> {
  await reveal(page, page.getByRole('button', { name, exact: true }), name === L.save ? 'content-save' : name === L.saveProfile ? 'profile-save' : 'other', page.getByRole('button', { name, exact: true, includeHidden: true }));
  await expect(page.getByRole('button', { name, exact: true }), 'Actual revealed control is enabled').toBeEnabled();
}
async function fill(page: Page, name: string, value: string, { blur = false }: { blur?: boolean } = {}): Promise<void> {
  await revealColorAdvanced(page, name);
  const field = page.getByRole('textbox', { name, exact: true });
  await reveal(page, field, 'field', page.getByRole('textbox', { name, exact: true, includeHidden: true }));
  // Ordinary Tab from the preceding field may already have focused this one.
  // There is still only one initial focus action, never a refocus while typing.
  if (!(await field.evaluate(el => el === document.activeElement))) await tapRevealedControl(page, field);
  await expect(field, 'Actual field receives focus before keyboard input').toBeFocused();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Delete');
  await expect(field, 'Actual field is cleared by keyboard input').toHaveValue('');
  await page.keyboard.type(value, { delay: 12 });
  await expect(field, 'Actual field reflects ordinary keyboard input').toHaveValue(value);
  if (blur) {
    await page.keyboard.press('Tab');
    await expect(field, 'Ordinary Tab leaves the edited field').not.toBeFocused();
    await expect(field, 'Complete field value remains after blur').toHaveValue(value);
  }
}
async function revealColorAdvanced(page: Page, name: string): Promise<void> {
  if (![L.primary, L.accent, L.textColor, L.buttonText].includes(name)) return;
  if (await page.getByRole('textbox', { name, exact: true, includeHidden: true }).count()) return;
  const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const advancedName = new RegExp(`${escape(name)}.*${L.advanced}`);
  const advanced = page.getByRole('button', { name: advancedName });
  await reveal(page, advanced, 'field', page.getByRole('button', { name: advancedName, includeHidden: true }));
  // Revealing the control can also restore its already-expanded field after
  // scrolling or a modal transition. Reobserve before toggling it closed.
  if (await page.getByRole('textbox', { name, exact: true, includeHidden: true }).count()) return;
  await tapRevealedControl(page, advanced);
}
async function readColorDraft(page: Page, name: string, expected: string): Promise<string> {
  await revealColorAdvanced(page, name);
  const field = page.getByRole('textbox', { name, exact: true });
  await reveal(page, field, 'field', page.getByRole('textbox', { name, exact: true, includeHidden: true }));
  await tapRevealedControl(page, field);
  await expect(field).toBeFocused();
  // Focus can precede Flutter installing the DOM editing value. The caller
  // supplies the authoritative original or the actual visible picker draft;
  // an empty inherited content color is valid only when explicitly expected.
  await expect(field, 'Focused Flutter control installs the expected draft value')
    .toHaveValue(expected);
  const value = await field.inputValue();
  await page.keyboard.press('Tab');
  return value.toLowerCase();
}
async function useVisualColorPicker(page: Page, name: string, apply: boolean, capture?: string): Promise<string> {
  await revealButton(page, name);
  await tapRevealedButton(page, name);
  // Flutter's incrementable semantics puts the name on the parent surface,
  // and a native range input inside it. Pointer mode disables that input so
  // Flutter, rather than the browser range, handles the actual gesture.
  const svSurface = page.getByLabel(L.saturation, { exact: true });
  const hueSurface = page.getByLabel(L.hue, { exact: true });
  const sv = svSurface.getByRole('slider');
  const hue = hueSurface.getByRole('slider');
  await expect(svSurface, 'The SV surface has its accessible label').toHaveCount(1);
  await expect(hueSurface, 'The hue surface has its accessible label').toHaveCount(1);
  await expect(sv, 'The labeled SV surface exposes one slider').toHaveCount(1);
  await expect(hue, 'The labeled hue surface exposes one slider').toHaveCount(1);
  const swatches = page.getByText(/^#[0-9a-f]{6}$/, { exact: true });
  await expect(swatches, 'The sheet shows current and new HEX swatches').toHaveCount(2);
  const current = await swatches.nth(0).innerText();
  const beforeKeys = await swatches.nth(1).innerText();
  // A modifier enters keyboard mode without changing a draft or focus. Wait
  // for the native controls to be enabled before ordinary Tab traversal.
  await page.keyboard.press('Shift');
  await expect(sv, 'Keyboard mode enables the SV semantics input').toBeEnabled();
  await page.keyboard.press('Tab');
  await expect(sv, 'Tab reaches the SV field').toBeFocused();
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('ArrowRight');
  await expect(swatches.nth(1), 'SV arrow keys change the visible draft').not.toHaveText(beforeKeys);
  await page.keyboard.press('Tab');
  await expect(hue, 'Tab reaches the hue rail').toBeFocused();
  // Flutter initializes aria-valuetext on the first change, not first focus.
  // Exercise both directions so initialization cannot masquerade as a change.
  // RGB-derived initial hue is below 360. Start upward so an inherited white
  // color at hue zero changes instead of clamping and leaving it uninitialized.
  await page.keyboard.press('ArrowUp');
  await expect(hue, 'Hue input reports an angle').toHaveAttribute('aria-valuetext', /^\d+°$/);
  const beforeHueKey = await hue.getAttribute('aria-valuetext');
  await page.keyboard.press('ArrowDown');
  await expect(hue, 'Hue arrow input reports the changed angle').toHaveAttribute('aria-valuetext', /^\d+°$/);
  await expect(hue, 'The opposite hue key changes its actual angle').not.toHaveAttribute('aria-valuetext', beforeHueKey!);
  // Physical pointer input targets each labeled Flutter surface, never the
  // disabled native range. The visible swatch is authoritative in pointer mode.
  const beforePointer = await swatches.nth(1).innerText();
  await tapRevealedControl(page, svSurface);
  await expect(swatches.nth(1), 'SV pointer selection changes the visible draft').not.toHaveText(beforePointer);
  const beforeHuePointer = await swatches.nth(1).innerText();
  await tapRevealedControl(page, hueSurface);
  await expect(swatches.nth(1), 'Hue pointer selection changes the visible draft').not.toHaveText(beforeHuePointer);
  await expect(swatches.nth(0), 'Visual gestures preserve the current swatch').toHaveText(current);
  const previewed = (await swatches.nth(1).innerText()).toLowerCase();
  expect(previewed, 'The visible picker draft is a complete HEX color').toMatch(/^#[0-9a-f]{6}$/);
  if (capture) await screenshot(page, capture);
  await tapRevealedButton(page, apply ? L.apply : L.cancel, true);
  await expect(sv, 'Apply or Cancel closes the visual picker').toHaveCount(0);
  // Flutter removes the modal slider inputs before restoring the editor's
  // semantics. Absence of sliders alone does not mean Advanced is collapsed.
  const returnedField = page.getByRole('textbox', { name, exact: true });
  await expect(returnedField,
    'Returning from the picker restores the still-expanded draft field').toHaveCount(1);
  await settleScroll(page, await scrollScope(page, returnedField), true);
  return previewed;
}
async function saveProfile(page: Page): Promise<void> {
  await revealButton(page, L.saveProfile);
  const saved = observeResponse(page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/set_restaurant_storefront_profile')));
  const response = await responseAfterAction(saved, () => tapRevealedButton(page, L.saveProfile));
  expect(response.status(), 'Profile writer HTTP result').toBe(200);
  expect((await response.json()).ok).toBe(true);
}
async function sceneDialog(page: Page, apply: boolean, legacy = false, capture?: string): Promise<void> {
  await revealButton(page, L.scenePreview);
  await tapRevealedButton(page, L.scenePreview);
  await expect(page.getByRole('button', { name: L.apply, exact: true })).toHaveCount(1);
  if (legacy) {
    // Flutter exposes ChoiceChip as a checkbox, including its selected state.
    const choice = page.getByRole('checkbox', { name: L.sceneLegacy, exact: true });
    const reference = page.getByRole('checkbox', { name: L.sceneReference, exact: true });
    await expect(reference).toBeChecked();
    await expect(choice).not.toBeChecked();
    await tapRevealedControl(page, choice, true);
    await expect(choice, 'The ordinary scene choice selects the brand preset').toBeChecked();
    await expect(reference, 'Scene choices remain mutually exclusive').not.toBeChecked();
  }
  if (capture) await screenshot(page, capture);
  await tapRevealedButton(page, apply ? L.apply : L.cancel, true);
  await expect(page.getByRole('button', { name: L.apply, exact: true })).toHaveCount(0);
}
async function semantics(page: Page): Promise<void> {
  await waitForFlutterBoot(page);
  expect(await enableFlutterSemantics(page), 'Real Flutter semantics available').toBe(true);
}
async function textContains(page: Page, text: string): Promise<void> {
  await expect.poll(() => readAccessibleText(page)).toContain(text);
}
async function revealSavedStatus(page: Page): Promise<void> {
  // Flutter also copies live-region text into an offscreen announcement node.
  // Reveal the real form text instead of accepting that invisible duplicate.
  const status = page.locator('flt-semantics').getByText(L.saved, { exact: true });
  await reveal(page, status, 'content-status');
  await textContains(page, L.saved);
}
type AppearanceGroup = 'profile' | 'content' | 'background' | 'banner';
async function openFoldedGroup(page: Page, group: AppearanceGroup, overviewCapture?: string): Promise<void> {
  const attributes = {
    profile: { title: L.profileAppearance, control: L.primary },
    content: { title: L.contentAppearance, control: L.textColor },
    background: { title: L.backgroundAndScene, control: L.upload },
    banner: { title: L.bannerTitle, control: L.bannerUpload },
  }[group];
  // Flutter exposes a folded ExpansionTile header as a button. After a
  // normal click the expanded group exposes its actual child controls.
  const header = page.getByRole('button', { name: attributes.title, exact: true });
  const control = page.getByRole('button', { name: attributes.control, exact: true });
  await reveal(page, header, 'other', page.getByRole('button', { name: attributes.title, exact: true, includeHidden: true }));
  await expect(control, 'The folded section excludes its control from accessible navigation').toHaveCount(0);
  if (overviewCapture) await screenshot(page, overviewCapture);
  await tapRevealedControl(page, header);
  await reveal(page, control, group === 'background' ? 'upload' : 'field',
    page.getByRole('button', { name: attributes.control, exact: true, includeHidden: true }));
  await expect(control, 'Opening the section exposes its enabled control').toBeEnabled();
  await settleScroll(page, await scrollScope(page, control), true);
}
async function openEditor(page: Page, reload = false, colours?: 'profile' | 'content'): Promise<void> {
  if (reload) await page.reload({ waitUntil: 'domcontentloaded' });
  await semantics(page);
  await tapNav(page, L.nav);
  const overview = reload ? undefined : resolve(process.env.CINEMATIC_ARTIFACT_DIR ?? 'cinematic-artifacts', 'dashboard-settings-folded-test-data.png');
  await openFoldedGroup(page, 'background', overview);
  if (colours) await openFoldedGroup(page, colours);
}
async function captureMediaLibrary(page: Page, mediaId: string, path: string): Promise<void> {
  const header = page.getByRole('button', { name: L.mediaLibrary, exact: true });
  // The full editor merges a published card's dimensions and ID into one
  // text node. The background dropdown does not expose that card label.
  const id = mediaId.slice(0, 8);
  const row = page.getByText(new RegExp(`أبعاد النسخة المنشورة:[\\s\\u2066]*\\d+×\\d+[\\s\\u2069]*بكسل[\\s\\u202a\\u2066]*${id}\\b`));
  await reveal(page, header, 'other', page.getByRole('button', { name: L.mediaLibrary, exact: true, includeHidden: true }));
  await expect(row, 'The folded library excludes the published card').toHaveCount(0);
  await tapRevealedControl(page, header);
  await reveal(page, row, 'content-status');
  await expect(row, 'The gallery displays the published synthetic background').toHaveCount(1);
  await settleScroll(page, await scrollScope(page, row), true);
  await screenshot(page, path);
}
async function saveContent(page: Page): Promise<void> {
  await revealButton(page, L.save);
  const saved = observeResponse(page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/set_restaurant_storefront_content_v1')));
  const response = await responseAfterAction(saved, () => tapRevealedButton(page, L.save));
  expect(response.status(), 'Content writer HTTP result').toBe(200);
  expect((await response.json()).ok, 'Content writer accepted actual owner session').toBe(true);
  await revealSavedStatus(page);
}
async function readCompanionUi(page: Page): Promise<CompanionUi> {
  // The background group was opened during upload. Return to its control without
  // toggling the header, then physically reveal the selected media's live status.
  const upload = page.getByRole('button', {name:L.upload, exact:true});
  await reveal(page, upload, 'upload', page.getByRole('button', {name:L.upload, exact:true, includeHidden:true}));
  const status = companionStatus(page);
  await reveal(page, status, 'background-status');
  return classifyCompanion(await status.innerText());
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
type UploadBoundary = 'reveal' | 'click' | 'filechooser' | 'file-set' | 'private-upload-response' | 'publisher-response' | 'publisher-body' | 'upload-assertion';
type RouteClass = 'private-upload' | 'publisher' | 'auth' | 'private-read' | 'public-media' | 'application' | 'other-local' | 'external';
type Observed<T> = { ok: true; value: T } | { ok: false; error: unknown };
class UploadDiagnostics {
  private readonly started = Date.now();
  control: Awaited<ReturnType<typeof targetGeometry>> = null;
  private readonly events: { ms: number; boundary: string; event: string; status?: number }[] = [];
  private readonly transportFailures: { boundary: RouteClass; code: string }[] = [];
  private readonly publisherResponses: { status: number; corsAllowsDashboard: boolean; jsonContentType: boolean }[] = [];
  private readonly publisherActivity = { requests: 0, finished: 0, failed: 0 };
  private readonly pageLifecycle = { mainFrameNavigations: 0, closes: 0, crashes: 0, corsPolicyMessages: 0 };
  private beforeUiStatuses: string[] = [];
  private bodyFailureObservation: {
    originalAcceptance: 'FAIL_PRESERVED'; reason: 'BODY_TRANSPORT_OR_OBSERVER_NOT_RESOLVED';
    windowMs: number; startedMs: number; endedMs: number | null; termination: string | null;
    beforeUiStatuses: string[];
    samples: { ms: number; uiStatuses: string[]; uploadControl: 'enabled' | 'disabled' | 'unavailable'; terminalMatchesBefore: boolean }[];
  } | null = null;
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
  transportFailure(boundary: RouteClass, errorText: string | undefined): void {
    // Retain only a browser network enum, never its URL/body or raw exception.
    const code = typeof errorText === 'string' && /^net::ERR_[A-Z_0-9]{1,64}$/.test(errorText) ? errorText : 'unclassified';
    if (this.transportFailures.length < 8) this.transportFailures.push({ boundary, code });
  }
  publisherResponse(response: Response): void {
    const headers = response.headers();
    if (this.publisherResponses.length < 8) this.publisherResponses.push({ status: response.status(),
      corsAllowsDashboard: headers['access-control-allow-origin'] === '*' || headers['access-control-allow-origin'] === DASHBOARD,
      jsonContentType: (headers['content-type'] ?? '').split(';')[0].trim() === 'application/json' });
  }
  publisherEvent(event: 'request' | 'request-finished' | 'request-failed'): void {
    if (event === 'request') this.publisherActivity.requests++;
    else if (event === 'request-finished') this.publisherActivity.finished++;
    else this.publisherActivity.failed++;
    this.mark('publisher', event);
  }
  lifecycle(event: 'main-frame-navigation' | 'page-close' | 'page-crash' | 'cors-policy'): void {
    if (event === 'main-frame-navigation') this.pageLifecycle.mainFrameNavigations++;
    else if (event === 'page-close') this.pageLifecycle.closes++;
    else if (event === 'page-crash') this.pageLifecycle.crashes++;
    else this.pageLifecycle.corsPolicyMessages++;
    this.mark('page-lifecycle', event);
  }
  beforeUpload(statuses: string[]): void { this.beforeUiStatuses = [...statuses]; }
  async observeBodyFailure(page: Page, target: Locator): Promise<void> {
    // Diagnostic observation only: never retry, save, decode a substitute body,
    // or convert a UI message into publication acceptance. Disabled can also
    // mean an unsaved draft, so uploadControl is not an assertion of app busy.
    const windowMs = 25_000, began = Date.now();
    const observation = this.bodyFailureObservation = {
      originalAcceptance: 'FAIL_PRESERVED', reason: 'BODY_TRANSPORT_OR_OBSERVER_NOT_RESOLVED',
      windowMs, startedMs: began - this.started, endedMs: null, termination: null,
      beforeUiStatuses: [...this.beforeUiStatuses], samples: [],
    } as NonNullable<UploadDiagnostics['bodyFailureObservation']>;
    const terminal = new Set(['image-published', 'background-selected', 'service-unavailable',
      'upload-failed', 'read-unavailable', 'binding-changed', 'publish-uncertain']);
    const pageLost = () => this.pageLifecycle.mainFrameNavigations > 0 || this.pageLifecycle.closes > 0 || this.pageLifecycle.crashes > 0;
    let active = true, timer: ReturnType<typeof setTimeout> | undefined;
    const expiry = new Promise<string>(done => { timer = setTimeout(() => done('window-expired'), windowMs); });
    const monitor = (async (): Promise<string> => {
      while (active) {
        if (page.isClosed() || pageLost()) return 'page-lifecycle-changed';
        const uiStatuses = await editorStatus(page);
        let uploadControl: 'enabled' | 'disabled' | 'unavailable' = 'unavailable';
        const remaining = windowMs - (Date.now() - began);
        if (remaining <= 0) return 'window-expired';
        try {
          uploadControl = await target.isEnabled({ timeout: Math.min(500, remaining) }) ? 'enabled' : 'disabled';
        } catch { /* Missing/inaccessible control is an enum, never a raw error. */ }
        if (!active) return 'window-expired';
        const terminalStatuses = uiStatuses.filter(status => terminal.has(status));
        const sample = { ms: Date.now() - this.started, uiStatuses, uploadControl,
          terminalMatchesBefore: terminalStatuses.length > 0 && terminalStatuses.every(status => this.beforeUiStatuses.includes(status)) };
        const previous = observation.samples.at(-1);
        if (!previous || previous.uploadControl !== uploadControl || JSON.stringify(previous.uiStatuses) !== JSON.stringify(uiStatuses)) {
          if (observation.samples.length < 16) observation.samples.push(sample);
          else observation.samples[15] = sample; // Keep the last state without unbounded samples.
        }
        // A status left over from an earlier upload is not a new terminal result.
        if (terminalStatuses.some(status => !this.beforeUiStatuses.includes(status))) return 'new-terminal-ui-observed-not-publication-acceptance';
        await new Promise<void>(done => setTimeout(done, Math.min(250, Math.max(1, windowMs - (Date.now() - began)))));
      }
      return 'window-expired';
    })().catch(() => page.isClosed() || pageLost() ? 'page-lifecycle-changed' : 'ui-unreadable');
    try { observation.termination = await Promise.race([monitor, expiry]); }
    finally {
      active = false;
      if (timer !== undefined) clearTimeout(timer);
      observation.endedMs = Date.now() - this.started;
    }
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
    return { events: this.events, transportFailures: this.transportFailures, publisherResponses: this.publisherResponses,
      publisherActivity: this.publisherActivity, pageLifecycle: this.pageLifecycle, bodyFailureObservation: this.bodyFailureObservation,
      controlGeometry: this.control, firstObservedWaitFailure: this.firstObservedWaitFailure, firstFailure: this.first === null ? null : {
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
async function upload(page: Page, filename: string, diagnostics: UploadDiagnostics, expectedStatus = 200, purpose: 'background' | 'banner' | 'desktop-banner' = 'background', synthetic?: Buffer): Promise<Obj> {
  const uploadName = purpose === 'desktop-banner' ? 'رفع صورة للكمبيوتر' : purpose === 'banner' ? L.bannerUpload : L.upload;
  const fixturePath = filename === 'background-2816.jpg' ? backgroundFixture
    : resolve(__dirname, '../../supabase/functions/storefront-media-publish/test/fixtures', filename);
  const onRequest = (request: import('@playwright/test').Request) => {
    const kind = routeClass(request.url());
    if (request.method() === 'POST' && kind === 'publisher') diagnostics.publisherEvent('request');
    else if (request.method() === 'POST' && kind === 'private-upload') diagnostics.mark(kind, 'request');
  };
  const onResponse = (response: Response) => {
    const kind = routeClass(response.url());
    if (response.request().method() === 'POST' && (kind === 'private-upload' || kind === 'publisher')) diagnostics.mark(kind, 'http', response.status());
    if (response.request().method() === 'POST' && kind === 'publisher') diagnostics.publisherResponse(response);
  };
  const onFailed = (request: import('@playwright/test').Request) => {
    const kind = routeClass(request.url());
    if (request.method() === 'POST' && kind === 'publisher') diagnostics.publisherEvent('request-failed');
    else diagnostics.mark(kind, 'request-failed');
    diagnostics.transportFailure(kind, request.failure()?.errorText);
  };
  const onFinished = (request: import('@playwright/test').Request) => {
    if (request.method() === 'POST' && routeClass(request.url()) === 'publisher') diagnostics.publisherEvent('request-finished');
  };
  const onNavigation = (frame: import('@playwright/test').Frame) => { if (frame === page.mainFrame()) diagnostics.lifecycle('main-frame-navigation'); };
  const onClose = () => diagnostics.lifecycle('page-close');
  const onCrash = () => diagnostics.lifecycle('page-crash');
  const onConsole = (message: import('@playwright/test').ConsoleMessage) => {
    // Classify only. Never retain console text, which may include a URL/token.
    if (message.type() === 'error' && /\bCORS policy\b/i.test(message.text())) diagnostics.lifecycle('cors-policy');
  };
  page.on('request', onRequest);
  page.on('response', onResponse);
  page.on('requestfailed', onFailed);
  page.on('requestfinished', onFinished);
  page.on('framenavigated', onNavigation);
  page.on('close', onClose);
  page.on('crash', onCrash);
  page.on('console', onConsole);
  let bodyReadFailed = false;
  try {
    diagnostics.mark('reveal', 'started');
    const target = page.getByRole('button', { name: uploadName, exact: true });
    await diagnostics.value('reveal', diagnostics.observe('reveal', reveal(page, target, 'upload', page.getByRole('button', { name: uploadName, exact: true, includeHidden: true }))));
    diagnostics.control = await targetGeometry(page, target);
    diagnostics.beforeUpload(await editorStatus(page).catch(() => ['unreadable']));
    const uploaded = diagnostics.observe('private-upload-response', page.waitForResponse(r => {
      const u = new URL(r.url());
      return u.origin === API && u.pathname.startsWith('/storage/v1/object/restaurant-logos/') && r.request().method() === 'POST';
    }));
    const published = diagnostics.observe('publisher-response', page.waitForResponse(r => requestIs(r, '/functions/v1/storefront-media-publish')
      && r.request().postDataJSON()?.slot === 'hero' && r.status() !== 202, { timeout: 120_000 }));
    const chosen = diagnostics.observe('filechooser', page.waitForEvent('filechooser'));
    diagnostics.mark('click', 'started');
    await diagnostics.value('click', diagnostics.observe('click', tapRevealedButton(page, uploadName)));
    const chooser = await diagnostics.value('filechooser', chosen);
    diagnostics.mark('file-set', 'started');
    await diagnostics.value('file-set', diagnostics.observe('file-set', chooser.setFiles(synthetic ? { name: filename, mimeType: 'image/png', buffer: synthetic } : fixturePath)));
    expect((await diagnostics.value('private-upload-response', uploaded)).ok(), 'Actual private bytes upload').toBe(true);
    const response = await diagnostics.value('publisher-response', published);
    expect(response.status(), 'Actual Edge publication response').toBe(expectedStatus);
    let body: Obj;
    diagnostics.mark('publisher-body', 'started');
    try { body = await response.json() as Obj; diagnostics.mark('publisher-body', 'complete'); }
    catch (error) {
      bodyReadFailed = true;
      diagnostics.fail('publisher-body', error); // Preserve the first failure BEFORE observing app/lifecycle.
      throw error;
    }
    if (expectedStatus === 200) {
      expect(body.ok, 'Actual Edge publisher accepted bytes').toBe(true);
      await textContains(page, purpose !== 'background' ? 'نُشرت الصورة؛ اخترها واحفظ المحتوى.' : L.selected);
    } else {
      expect(body.status, 'Cross-source duplicate is rejected').toBe('object_conflict');
      await textContains(page, L.unavailable);
    }
    return body;
  } catch (error) {
    diagnostics.fail('upload-assertion', error);
    if (bodyReadFailed) await diagnostics.observeBodyFailure(page, page.getByRole('button', { name: uploadName, exact: true }))
      .catch(() => diagnostics.mark('publisher-body', 'diagnostic-unavailable'));
    diagnostics.control = await targetGeometry(page, page.getByRole('button', { name: uploadName, exact: true })).catch(() => null);
    throw diagnostics.original(error);
  } finally {
    page.off('request', onRequest);
    page.off('response', onResponse);
    page.off('requestfailed', onFailed);
    page.off('requestfinished', onFinished);
    page.off('framenavigated', onNavigation);
    page.off('close', onClose);
    page.off('crash', onCrash);
    page.off('console', onConsole);
  }
}
async function editorStatus(page: Page): Promise<string[]> {
  // Only an allowlisted status enum escapes; accessible text stays private.
  const text = await readAccessibleText(page);
  const statuses = [
    ['background-selected', L.selected], ['content-saved', L.saved],
    ['image-published', 'نُشرت الصورة؛ اخترها واحفظ المحتوى.'],
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
        !(await readAccessibleText(page)).includes('CINEMATIC TEST A')) return 'withheld';
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
  await reveal(page, slider, 'dimming', page.getByRole('slider', { includeHidden: true }));
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
  const media = await rpc(f, token, 'list_storefront_content_media_v2');
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
async function verifyReadCompatibility(f: Fixture, token: string): Promise<void> {
  // Read-only calls use the owner session captured from the actual UI login.
  // All fixture mutations remain the real Dashboard journey above/below.
  const [legacy, previous, current, legacyMedia, currentMedia] = await Promise.all([
    rpc(f, token, 'get_restaurant_storefront_content_v1'),
    rpc(f, token, 'get_restaurant_storefront_content_v2'),
    rpc(f, token, 'get_restaurant_storefront_content_v3'),
    rpc(f, token, 'list_storefront_content_media_v1'),
    rpc(f, token, 'list_storefront_content_media_v2'),
  ]);
  const legacyDocument = structuredClone(current.document);
  delete legacyDocument.appearance;
  expect(legacy.document, 'An old strict reader retains exactly its content document').toEqual(legacyDocument);
  expect(legacy.version).toBe(current.version);
  const previousDocument = structuredClone(current.document);
  if (previousDocument.appearance) delete previousDocument.appearance.scene_preset;
  expect(previous.document, 'Strict v2 omits only the scene extension').toEqual(previousDocument);
  const projectedMedia = structuredClone(currentMedia);
  const rows = projectedMedia.media ?? projectedMedia.rows;
  expect(Array.isArray(rows)).toBe(true);
  for (const row of rows as Obj[]) {
    row.content_in_use = row.content_in_use.filter((use: Obj) => use.kind !== 'menu_background');
  }
  expect(legacyMedia, 'Old media readers omit only the new usage type').toEqual(projectedMedia);
  const publicRead = async (name: string): Promise<Obj> => {
    const response = await fetch(`${API}/rest/v1/rpc/${name}`, {
      method: 'POST', redirect: 'error',
      headers: { apikey: f.anonKey, Authorization: `Bearer ${f.anonKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_slug: f.ownerA.slug }),
    });
    expect(response.status, 'Anonymous versioned public menu read succeeds').toBe(200);
    return response.json() as Promise<Obj>;
  };
  const [oldMenu, newMenu, referenceMenu, responsiveMenu] = await Promise.all([
    publicRead('storefront_menu_v4'), publicRead('storefront_menu_v5'), publicRead('storefront_menu_v6'), publicRead('storefront_menu_v7'),
  ]);
  expect(typeof responsiveMenu.server_ts).toBe('string');
  expect(typeof referenceMenu.server_ts).toBe('string');
  const v7Projection: Obj = { ...responsiveMenu, server_ts: referenceMenu.server_ts };
  if (!referenceMenu.content_v1.appearance?.menu_background_url) {
    expect(Object.hasOwn(v7Projection,'menu_background_images_v1'),'A cleared selection omits the resource manifest').toBe(false);
  }
  delete v7Projection.menu_background_images_v1;
  expect(v7Projection,'All existing public fields remain identical in v7').toEqual(referenceMenu);
  // Separate HTTP snapshots have distinct timestamps; every other old field
  // must remain identical, including prices, modifiers and ordering controls.
  expect(typeof oldMenu.server_ts).toBe('string');
  expect(typeof newMenu.server_ts).toBe('string');
  delete oldMenu.server_ts;
  delete newMenu.server_ts;
  delete referenceMenu.server_ts;
  delete referenceMenu.product_images_v1;
  if (referenceMenu.content_v1.appearance) delete referenceMenu.content_v1.appearance.scene_preset;
  expect(referenceMenu, 'No product selections in this journey: v6 projects exactly to v5').toEqual(newMenu);
  delete newMenu.content_v1.appearance;
  expect(oldMenu, 'Old public readers retain their exact menu projection').toEqual(newMenu);
}
type MenuRenderSample = { ms: number; httpStatus: number | null; roots: number; backgrounds: number; hydrationReady: boolean; imageMatches: boolean; dim: number | null; text: string | null; button: string | null; primary: string | null; accent: string | null; font: 'alexandria' | 'rubik' | 'system' | 'other'; renderedFontMatches: boolean; expectedFontMatches: boolean; coloursMatch: boolean; ready: boolean };
type MenuRenderTrace = { result: 'pending' | 'ready' | 'failed'; navigations: number; samples: MenuRenderSample[] };
const menuRenderTraces = new WeakMap<BrowserContext, MenuRenderTrace[]>();
async function renderMenu(page: Page, f: Fixture, image: string, dim: number | null, colours?: Obj, scene: 'reference_dark' | null = null): Promise<void> {
  const expectedLogicalImage = logicalMediaUrl(image);
  const route = `${STOREFRONT}/s/${f.ownerA.slug}/menu`;
  localUrl(route);
  const trace: MenuRenderTrace = { result: 'pending', navigations: 0, samples: [] };
  const traces = menuRenderTraces.get(page.context()) ?? [];
  traces.push(trace);
  menuRenderTraces.set(page.context(), traces);
  const started = Date.now();
  let hydrated = false, reloadAt = 0, httpStatus: number | null = null;
  try {
    // ThemeScope applies CSSOM tokens in useLayoutEffect. DOMContentLoaded is
    // not hydration: repeatedly reloading at each sample discards that frame.
    // Observe the current page first, then reload a hydrated stale ISR result.
    // The original overall 100s budget and normal 60s ISR remain unchanged.
    await expect.poll(async () => {
      if (trace.navigations === 0 || (hydrated && Date.now() >= reloadAt)) {
        const remaining = Math.max(1, 100_000 - (Date.now() - started));
        const response = await page.goto(route, { waitUntil: 'domcontentloaded', timeout: Math.min(30_000, remaining) });
        httpStatus = response?.status() ?? null;
        trace.navigations++;
        hydrated = false;
        reloadAt = Date.now() + 5000;
      }
      const observation = await page.evaluate(({ expectedImage, expectedDim, expectedColours, expectedScene }) => {
        const roots = document.querySelectorAll<HTMLElement>('[data-sf-root]');
        const backgrounds = document.querySelectorAll<HTMLImageElement>('main[data-sf-screen="home"] [data-sf-menu-primary]');
        const root = roots.length === 1 ? roots[0] : null;
        const style = root ? getComputedStyle(root) : null;
        const value = (name: string) => style?.getPropertyValue(name).trim() ?? '';
        const rawDim = value('--menu-image-dim'), numericDim = rawDim === '' ? null : Number(rawDim);
        const tx = value('--tx'), onacc = value('--onacc'), bg = value('--bg'), acc = value('--acc');
        const font = root?.style.getPropertyValue('--font') ?? '', resolvedFont = value('--font');
        const normalizeFont = (font: string) => font.replaceAll('\"', '').replaceAll("'", '').replaceAll(' ', '');
        const renderedFontMatches = resolvedFont.length > 0 && normalizeFont(style?.fontFamily ?? '') === normalizeFont(resolvedFont);
        const expectedFontMatches = !expectedColours || font.includes(expectedColours.font);
        const coloursMatch = !expectedColours || (tx === expectedColours.text && onacc === expectedColours.button && bg === expectedColours.primary && acc === expectedColours.accent);
        const hydrationReady = Boolean(root?.style.getPropertyValue('--bg') && font);
        const sceneMatches = (root?.getAttribute('data-sf-scene') ?? null) === expectedScene;
        const imageMatches = (expectedDim === null ? backgrounds.length > 0 : backgrounds.length === 1) && backgrounds[0].getAttribute('src') === expectedImage;
        const dimMatches = expectedDim === null || (numericDim !== null && numericDim === expectedDim / 100);
        const colour = (value: string) => /^#[0-9a-f]{6}$/i.test(value) ? value.toLowerCase() : null;
        // Fixed booleans/counts and validated presentation values only. No raw
        // URL, HTML, slug, exception message, session or request data escapes.
        return { roots: Math.min(roots.length, 100), backgrounds: Math.min(backgrounds.length, 100), hydrationReady, imageMatches,
          dim: numericDim !== null && Number.isFinite(numericDim) && numericDim >= 0 && numericDim <= .8 ? numericDim : null,
          text: colour(tx), button: colour(onacc), primary: colour(bg), accent: colour(acc),
          font: font.includes('SF Alexandria') ? 'alexandria' as const : font.includes('sf-font-latin') ? 'rubik' as const : font.includes('system-ui') ? 'system' as const : 'other' as const,
          renderedFontMatches, expectedFontMatches, coloursMatch,
          ready: hydrationReady && sceneMatches && imageMatches && dimMatches && (!expectedColours || (renderedFontMatches && expectedFontMatches && coloursMatch)) };
      }, { expectedImage: expectedLogicalImage, expectedDim: dim, expectedColours: colours ?? null, expectedScene: scene });
      hydrated = observation.hydrationReady;
      const sample = { ms: Date.now() - started, httpStatus, ...observation };
      if (trace.samples.length < 120) trace.samples.push(sample);
      else trace.samples[119] = sample;
      return observation.ready;
    }, { timeout: 100_000, intervals: [100, 250, 500, 1000] }).toBe(true);
    await expect(page.locator('[data-sf-root]')).toHaveAttribute('dir', 'rtl');
    if (dim === null) await expect(page.locator('[data-sf-menu-background="custom"]')).toHaveCount(0);
    const bg = page.locator('main[data-sf-screen="home"] [data-sf-menu-primary]');
    await expect.poll(() => bg.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
    trace.result = 'ready';
  } catch (error) { trace.result = 'failed'; throw error; }
}
type SiteTheme = 'light' | 'dark';
type RetainedMenuAppearance = { primary: string; accent: string; font: string; scene: string | null };
type SiteThemeRenderTrace = {
  mode: SiteTheme; result: 'pending' | 'ready' | 'failed'; navigations: number;
  samples: { ms: number; httpStatus: number | null; hydrated: boolean; modeMatches: boolean; surfacesMatch: boolean; imageMatches: boolean; dimMatches: boolean; brandMatches: boolean; sceneMatches: boolean }[];
};
const siteThemeRenderTraces = new WeakMap<BrowserContext, SiteThemeRenderTrace[]>();
async function renderSiteThemeMenu(page: Page, f: Fixture, mode: SiteTheme, image: string, dim: number, retained: RetainedMenuAppearance): Promise<void> {
  const route = `${STOREFRONT}/s/${f.ownerA.slug}/menu`;
  localUrl(route);
  const expectedImage = logicalMediaUrl(image);
  const trace: SiteThemeRenderTrace = { mode, result: 'pending', navigations: 0, samples: [] };
  const traces = siteThemeRenderTraces.get(page.context()) ?? [];
  traces.push(trace);
  siteThemeRenderTraces.set(page.context(), traces);
  const started = Date.now();
  let hydrated = false, reloadAt = 0, httpStatus: number | null = null;
  try {
    // Keep the existing bounded ISR/hydration behavior. The legacy image check
    // above stays unchanged: explicit Light deliberately has no scene image.
    await expect.poll(async () => {
      if (trace.navigations === 0 || (hydrated && Date.now() >= reloadAt)) {
        const remaining = Math.max(1, 100_000 - (Date.now() - started));
        const response = await page.goto(route, { waitUntil: 'domcontentloaded', timeout: Math.min(30_000, remaining) });
        httpStatus = response?.status() ?? null;
        trace.navigations++;
        hydrated = false;
        reloadAt = Date.now() + 5000;
      }
      const sample = await page.evaluate(({ mode, expectedImage, dim, retained }) => {
        const roots = document.querySelectorAll<HTMLElement>('[data-sf-root]');
        const root = roots.length === 1 ? roots[0] : null;
        const home = root?.querySelector<HTMLElement>('main[data-sf-screen="home"]');
        const style = root ? getComputedStyle(root) : null;
        const value = (name: string) => style?.getPropertyValue(name).trim() ?? '';
        const images = home?.querySelectorAll<HTMLImageElement>('[data-sf-menu-primary]');
        const backgrounds = home?.querySelectorAll('[data-sf-menu-background="custom"]');
        const normalizeFont = (font: string) => font.replaceAll('"', '').replaceAll("'", '').replaceAll(' ', '');
        const bg = value('--bg'), ink = value('--tx');
        const luminance = (hex: string) => {
          if (!/^#[0-9a-f]{6}$/i.test(hex)) return NaN;
          const rgb = [1, 3, 5].map(i => Number.parseInt(hex.slice(i, i + 2), 16) / 255)
            .map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
          return rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722;
        };
        const a = luminance(bg), b = luminance(ink);
        const contrast = (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
        return {
          hydrated: Boolean(home && root?.style.getPropertyValue('--bg') && root.style.getPropertyValue('--font')),
          modeMatches: style?.colorScheme === mode,
          surfacesMatch: contrast >= 4.5 && bg === (mode === 'light' ? '#ffffff' : retained.primary)
            && (mode === 'dark' || Boolean(home && getComputedStyle(home).backgroundColor === 'rgb(255, 255, 255)')),
          imageMatches: mode === 'light' ? images?.length === 0 && backgrounds?.length === 0
            : images?.length === 1 && backgrounds?.length === 1 && images[0].getAttribute('src') === expectedImage
              && images[0].complete && images[0].naturalWidth > 0,
          dimMatches: value('--menu-image-dim') === String(dim / 100),
          brandMatches: value('--acc') === retained.accent && value('--font') === retained.font
            && normalizeFont(style?.fontFamily ?? '') === normalizeFont(retained.font),
          sceneMatches: (root?.getAttribute('data-sf-scene') ?? null) === retained.scene,
        };
      }, { mode, expectedImage, dim, retained });
      hydrated = sample.hydrated;
      const entry = { ms: Date.now() - started, httpStatus, ...sample };
      if (trace.samples.length < 120) trace.samples.push(entry);
      else trace.samples[119] = entry;
      return httpStatus === 200 && Object.values(sample).every(Boolean);
    }, { timeout: 100_000, intervals: [100, 250, 500, 1000] }).toBe(true);
    await expect(page.locator('[data-sf-root]')).toHaveAttribute('dir', 'rtl');
    trace.result = 'ready';
  } catch (error) { trace.result = 'failed'; throw error; }
}
function withoutSiteTheme(document: Obj): Obj {
  const copy = structuredClone(document);
  if (copy.appearance) delete copy.appearance.site_theme;
  return copy;
}
async function publicThemeMenu(f: Fixture, name: 'storefront_menu_v7' | 'storefront_menu_v8'): Promise<Obj> {
  const response = await fetch(`${API}/rest/v1/rpc/${name}`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30_000),
    headers: { apikey: f.anonKey, Authorization: `Bearer ${f.anonKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_slug: f.ownerA.slug }),
  });
  expect(response.status, 'Versioned anonymous theme menu read succeeds').toBe(200);
  const result = await response.json() as Obj;
  expect(result.ok).toBe(true);
  expect(result.restaurant.slug).toBe(f.ownerA.slug);
  return result;
}
async function verifyMenuGeometry(page: Page): Promise<void> {
  const sections = page.locator('[data-sf-module="sections"]');
  await expect(sections, 'All four synthetic menu categories remain present').toHaveCount(4);
  const backdrop = page.locator('[data-sf-menu-background="custom"]');
  const photo = backdrop.locator('[data-sf-menu-primary]');
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
  const layer = await backdrop.boundingBox();
  const first = await sections.first().boundingBox();
  const last = await sections.last().boundingBox();
  expect(Boolean(layer && first && last), 'Menu/background geometry is measurable').toBe(true);
  expect(layer!.y).toBeLessThanOrEqual(first!.y);
  expect(layer!.y + layer!.height).toBeGreaterThanOrEqual(last!.y + last!.height);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'No horizontal viewport overflow').toBe(true);
  await expect(photo).toHaveCSS('position', 'absolute');
  await expect(photo).toHaveCSS('object-fit', 'cover');
  await expect(photo).toHaveCSS('object-position', '50% 0%');
  const viewport = await page.evaluate(() => ({ width: document.documentElement.clientWidth, height: innerHeight }));
  for (const position of ['top', 'last category'] as const) {
    if (position === 'last category') {
      await sections.last().scrollIntoViewIfNeeded();
      await expect(sections.last()).toBeInViewport();
      await expect.poll(() => page.evaluate(() => window.scrollY), 'The long menu actually scrolled').toBeGreaterThan(0);
    }
    const rect = await photo.boundingBox();
    expect(rect, `The lead photograph remains laid out at ${position}`).not.toBeNull();
    const scrollY = await page.evaluate(() => window.scrollY);
    expect(Math.abs(rect!.x), 'Photo stays at the document left edge').toBeLessThanOrEqual(1);
    expect(Math.abs(rect!.y + scrollY), 'Photo stays at the document top').toBeLessThanOrEqual(1);
    expect(Math.abs(rect!.width - viewport.width), 'Photo covers the viewport width').toBeLessThanOrEqual(1);
    expect(Math.abs(rect!.height - viewport.height), 'Photo covers the viewport height').toBeLessThanOrEqual(1);
  }
}
async function verifyReferenceScene(page: Page, dim: number): Promise<void> {
  const result = await page.evaluate(() => {
    const home = document.querySelector('main[data-sf-screen="home"]')!;
    const layer = home.querySelector('div[aria-hidden="true"]')!;
    const image = layer.querySelector('[data-sf-menu-primary]')!;
    const photo = getComputedStyle(image), overlay = getComputedStyle(layer, '::after');
    const header = getComputedStyle(home.querySelector('header')!);
    const category = getComputedStyle(home.querySelector('[data-sf-module="categories"]')!.parentElement!);
    const panel = getComputedStyle(home.querySelector('[data-sf-module="footer"] [data-sf-module="service"] > div')!);
    return { image: { fit: photo.objectFit, filter: photo.filter, position: photo.position, opacity: photo.opacity },
      overlay: { colour: overlay.backgroundColor, opacity: Number(overlay.opacity) },
      header: { colour: header.backgroundColor, blur: header.backdropFilter },
      category: { colour: category.backgroundColor, blur: category.backdropFilter }, footer: panel.backgroundColor,
      fits: document.documentElement.scrollWidth <= innerWidth };
  });
  expect(result.image).toEqual({ fit: 'cover', filter: 'none', position: 'absolute', opacity: '1' });
  expect(result.overlay).toEqual({ colour: 'rgb(0, 0, 0)', opacity: dim / 100 });
  expect(result.header).toEqual({ colour: 'rgba(21, 21, 21, 0.76)', blur: 'none' });
  expect(result.category).toEqual({ colour: 'rgba(0, 0, 0, 0)', blur: 'none' });
  expect(result.footer).toBe('rgba(37, 37, 37, 0.8)');
  expect(result.fits, 'Reference scene fits the viewport').toBe(true);
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

// BIZBOT-STOREFRONT-BANNER-PREVIEW-001: exercise the existing content writer
// through the shipped editor, then require a fresh authenticated server read.
async function verifyBannerFocalPersistence(page: Page, menu: Page, f: Fixture, token: string): Promise<void> {
  const out = process.env.CINEMATIC_ARTIFACT_DIR!;
  const receipt: Obj = { status: 'FAIL', failedStage: 'baseline', data: 'real temporary CI services; owner UI save, no SQL focus write' };
  let stage = 'baseline';
  const read = () => rpc(f, token, 'get_restaurant_storefront_content_v6');
  const previewFrames = page.locator('iframe[title="Storefront banner preview"]');
  const preview = (index: number) => page.frameLocator('iframe[title="Storefront banner preview"]').nth(index);
  const geometry = bannerGeometry;
  const label = (axis: 'x' | 'y') => axis === 'x' ? 'موضع التركيز الأفقي' : 'موضع التركيز الرأسي';
  const focalText = (axis: 'x' | 'y', value: number) => page.getByText(`${label(axis)} — ${value}%`, { exact: true });
  // Discover the real range following its visible axis label, not a fixed
  // Flutter semantic-node ID or a DOM value assignment. Other editor sliders
  // (such as background dimming) are deliberately not selected by index.
  const focalSlider = async (axis: 'x' | 'y', value: number): Promise<Locator> => {
    const text = focalText(axis, value);
    await reveal(page, text, 'content-status');
    const boundary = axis === 'x'
      ? page.getByText(/^موضع التركيز الرأسي — \d+%$/)
      : page.getByText('معاينة قص غير هدّام — هاتف / سطح المكتب', { exact: true });
    await expect(boundary).toHaveCount(1);
    const boundaryElement = await boundary.elementHandle();
    const id = await text.evaluate((el, limit) => {
      const candidates = Array.from(document.querySelectorAll<HTMLElement>('[role="slider"],input[type="range"]'))
        .filter(node => Boolean(el.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING)
          && Boolean(node.compareDocumentPosition(limit!) & Node.DOCUMENT_POSITION_FOLLOWING));
      if (candidates.length !== 1) throw new Error('Axis label must precede exactly one real focal range');
      const node = candidates[0];
      const owner = node?.closest<HTMLElement>('[id^="flt-semantic-node-"]');
      if (!owner?.id) throw new Error('Focal range has no rendered semantic owner');
      return owner.id;
    }, boundaryElement);
    const slider = page.locator(`[id="${id}"]`).getByRole('slider');
    await expect(slider).toHaveCount(1);
    await reveal(page, slider, 'field');
    return slider;
  };
  const setFocal = async (axis: 'x' | 'y', from: number, to: number) => {
    const slider = await focalSlider(axis, from);
    await slider.focus();
    await expect(slider, 'The same ordinary focal input retains keyboard focus').toBeFocused();
    const step = Math.sign(to - from);
    for (let value = from; value !== to;) {
      await page.keyboard.press(step > 0 ? 'ArrowRight' : 'ArrowLeft');
      value += step;
      await expect(focalText(axis, value), 'Observe each actual Flutter draft tick before the next key').toHaveCount(1);
      await expect(slider).toHaveAttribute('aria-valuetext', `${value}%`);
      await expect(slider, 'Never refocus a recreated or unfocused range to hide a draft-input defect').toBeFocused();
    }
  };
  const profileFields = (profile: Obj) => Object.fromEntries([
    'storefront_branch_id', 'display_name', 'tagline', 'public_city', 'public_address', 'public_phone',
    'primary_color', 'accent_color', 'visual_preset', 'locale_default', 'logo_media_id', 'hero_media_id',
    'opening_hours', 'pickup_enabled', 'paused_until', 'pause_reason', 'is_published',
  ].map(key => [key, profile[key]]));
  const withoutFocals = (document: Obj) => {
    const value = structuredClone(document);
    delete value.appearance.menu_banner_focal_x; delete value.appearance.menu_banner_focal_y;
    return value;
  };
  let writes = 0, profileWrites = 0;
  const countWrites = (request: import('@playwright/test').Request) => {
    const u = new URL(request.url());
    if (u.origin === API && request.method() === 'POST' && u.pathname === '/rest/v1/rpc/set_restaurant_storefront_content_v1') writes++;
    if (u.origin === API && request.method() === 'POST' && u.pathname === '/rest/v1/rpc/set_restaurant_storefront_profile') profileWrites++;
  };
  page.on('request', countWrites);
  try {
    const baseline = await read(), profileBefore = (await rpc(f, token, 'get_restaurant_storefront_profile')).profile;
    expect(baseline.restaurant_id).toBe(f.ownerA.restaurantId);
    expect(baseline.storefront_branch_id).toBe(f.ownerA.branchId);
    const before = baseline.document;
    const initialX = before.appearance.menu_banner_focal_x ?? 50, initialY = before.appearance.menu_banner_focal_y ?? 50;
    const phone = preview(0).locator('[data-sf-menu-top]'), desktop = preview(1).locator('[data-sf-menu-top]');
    await expect(previewFrames).toHaveCount(2);
    // The single asynchronous public-state read replaces the initial srcdoc.
    // Wait for that initial document and fonts before taking a baseline. Only
    // this pre-input wait accepts navigation; draft/reuse checks stay strict.
    let initialDocumentNavigations = 0;
    receipt.initialDocumentNavigations = 0;
    const initialGeometry = async (index: number): Promise<Obj> => {
      let observed: Obj | undefined;
      await expect.poll(async () => {
        try {
          const ready = await preview(index).locator('[data-banner-preview-root]').evaluate(el =>
            Boolean((el as HTMLElement).style.getPropertyValue('--font'))
              && Boolean(el.querySelector('[data-sf-order-status] [data-state]'))
              && el.querySelector('[data-sf-order-status] [data-state]')!.getAttribute('data-state') !== 'unknown');
          if (!ready) return false;
          observed = await geometry(preview(index).locator('[data-sf-menu-top]'));
          receipt[index === 0 ? 'initialPhoneGeometry' : 'initialDesktopGeometry'] = observed;
          return observed.position === `${initialX}% ${initialY}%`;
        } catch (error) {
          if (!(error instanceof Error) || !error.message.includes('Execution context was destroyed')) throw error;
          receipt.initialDocumentNavigations = ++initialDocumentNavigations;
          return false;
        }
      }, { timeout: 25000 }).toBe(true);
      return observed!;
    };
    stage = 'baseline-initial-phone';
    const phoneBefore = await initialGeometry(0);
    stage = 'baseline-initial-desktop';
    const desktopBefore = await initialGeometry(1);
    stage = 'baseline-crop-geometry';
    expect(phoneBefore.width, 'Default logical phone preview').toBe(390);
    expect(desktopBefore.viewportWidth, 'Independent logical desktop preview').toBe(1280);
    expect(desktopBefore.width, 'Absent responsive settings preserve the full-width legacy image').toBe(1280);
    expect(phoneBefore.clippedX, 'This real image actually crops horizontally on phone').toBeGreaterThan(1);
    const restoreLegacy = await replayBaselineBanner(desktop);
    try { expect(await geometry(desktop), 'Legacy desktop equals the pinned production CSS replay, not the rejected contain prototype').toEqual(desktopBefore); }
    finally { await restoreLegacy(); }
    const originalPhoto = await preview(0).locator('[data-sf-menu-banner] img').elementHandle();
    expect(originalPhoto).not.toBeNull();
    stage = 'draft-focus-no-autosave';
    await setFocal('x', initialX, 38);
    await expect.poll(async () => (await geometry(phone)).position).toBe(`38% ${initialY}%`);
    await setFocal('y', initialY, 9);
    await expect.poll(async () => (await geometry(desktop)).position).toBe('38% 9%');
    for (const width of [430, 390]) {
      const choice = page.getByRole('checkbox', { name: `${width}px`, exact: true });
      await reveal(page, choice, 'field'); await tapRevealedControl(page, choice);
      await expect(choice, 'Viewport selection is a local preview tool').toBeChecked();
      await expect.poll(async () => (await geometry(phone)).width).toBe(width);
    }
    expect(await originalPhoto!.evaluate(el => el.isConnected && el.ownerDocument.querySelector('[data-sf-menu-banner] img') === el), 'Draft focal moves reuse the same image node/document').toBe(true);
    expect(writes, 'Focal edits never write automatically').toBe(0);
    expect(await read(), 'The actual server still has the entire pre-edit document/version').toEqual(baseline);
    const draftPhone = await geometry(phone), draftDesktop = await geometry(desktop);
    expect(draftPhone.publicPath).toBe(phoneBefore.publicPath);
    expect(draftDesktop.publicPath).toBe(phoneBefore.publicPath);
    // One axis may be complete on a viewport, but its value is still retained
    // for the other viewport. Do not manufacture movement with extra zoom.
    if (draftPhone.clippedY < .01) {
      await reveal(page, previewFrames.nth(0), 'content-status');
      await expect(page.getByText('موضع التركيز الرأسي: الصورة ظاهرة كاملة على هذا المحور', { exact: true }))
        .toHaveCount([draftPhone, draftDesktop].filter(value => value.clippedY < .01).length);
      expect(draftPhone.position).toBe('38% 9%');
    }
    if (draftDesktop.clippedX < .01) {
      await expect(page.getByText('موضع التركيز الأفقي: الصورة ظاهرة كاملة على هذا المحور', { exact: true }))
        .toHaveCount([draftPhone, draftDesktop].filter(value => value.clippedX < .01).length);
      expect(draftDesktop.position).toBe('38% 9%');
    }
    stage = 'save-content-via-ui';
    await saveContent(page);
    expect(writes, 'Only the explicit normal content Save writes once').toBe(1);
    stage = 'reload-real-owner-read';
    const observedRead = observeResponse(page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/get_restaurant_storefront_content_v6')));
    const reloadResponse = await responseAfterAction(observedRead, () => openEditor(page, true));
    expect(reloadResponse.status()).toBe(200);
    const reloadWire = await reloadResponse.json();
    expect(reloadWire.ok).toBe(true);
    expect(reloadWire.restaurant_id).toBe(f.ownerA.restaurantId);
    expect(reloadWire.storefront_branch_id).toBe(f.ownerA.branchId);
    expect(reloadWire.document.appearance.menu_banner_focal_x).toBe(38);
    expect(reloadWire.document.appearance.menu_banner_focal_y).toBe(9);
    await openFoldedGroup(page, 'banner');
    await expect(focalText('x', 38)).toHaveCount(1); await expect(focalText('y', 9)).toHaveCount(1);
    const reread = await read();
    expect(reread.restaurant_id).toBe(f.ownerA.restaurantId); expect(reread.storefront_branch_id).toBe(f.ownerA.branchId);
    expect(reread.version).toBeGreaterThan(baseline.version);
    expect(reread.document.appearance.menu_banner_focal_x).toBe(38);
    expect(reread.document.appearance.menu_banner_focal_y).toBe(9);
    expect(withoutFocals(reread.document), 'All other content/appearance values survive exactly').toEqual(withoutFocals(before));
    expect(profileFields((await rpc(f, token, 'get_restaurant_storefront_profile')).profile), 'Independent profile save was not invoked').toEqual(profileFields(profileBefore));
    expect(profileWrites, 'Content save never invokes the independent profile writer').toBe(0);
    expect(Object.keys(reread.document.appearance).filter(key => /viewport|preview.*width|phone.*width/.test(key))).toEqual([]);
    await invariants(f, token);
    stage = 'matching-saved-phone-preview-and-storefront';
    await expect.poll(async () => (await geometry(phone)).position).toBe('38% 9%');
    const afterPreview = await geometry(phone);
    await menu.setViewportSize({ width: 390, height: 844 });
    await expect.poll(async () => {
      await menu.goto(STOREFRONT + '/ar/s/' + f.ownerA.slug + '/menu', { waitUntil: 'domcontentloaded' });
      const image = menu.locator('[data-sf-menu-banner] img');
      return await image.count() === 1 ? image.evaluate(el => getComputedStyle(el).objectPosition) : '';
    }, { timeout: 100000, intervals: [250, 500, 1000] }).toBe('38% 9%');
    const afterSite = await geometry(menu.locator('[data-sf-menu-top]'));
    for (const key of ['viewportWidth', 'width', 'height', 'naturalWidth', 'naturalHeight', 'publicPath', 'position', 'searchY', 'categoriesY']) {
      expect(afterSite[key], `Saved phone preview and live source match ${key}`).toBe(afterPreview[key]);
    }
    await reveal(page, previewFrames.nth(0), 'content-status');
    await screenshot(page, resolve(out, 'banner-focus-dashboard-saved-test-data.png'));
    await screenshot(menu, resolve(out, 'banner-focus-storefront-saved-test-data.png'));
    receipt.status = 'SAVE_READBACK_PASS'; receipt.failedStage = null;
    Object.assign(receipt, { saved: { x: 38, y: 9 }, phoneBefore, desktopBefore, draftPhone, draftDesktop,
      afterPreview, afterSite, contentWrites: writes, actualUiReloadReadObserved: true,
      allOtherContentPreserved: true, independentProfilePreserved: true, correctRestaurantAndBranch: true,
      viewportToolsNotPersisted: !Object.keys(reread.document.appearance).some(key => /viewport|preview.*width|phone.*width/.test(key)) });
  } finally {
    page.off('request', countWrites);
    if (receipt.status !== 'SAVE_READBACK_PASS') receipt.failedStage = stage;
    writeFileSync(resolve(out, 'banner-focus-persistence-result.json'), JSON.stringify(receipt, null, 2));
  }
}

// BIZBOT-STOREFRONT-DESKTOP-BANNER-FIT-001. This extends the already signed-in
// real banner journey, never the owner's browser/session or a hosted endpoint.
async function verifyBannerResponsive(page: Page, menu: Page, f: Fixture, token: string): Promise<void> {
  const out = process.env.CINEMATIC_ARTIFACT_DIR!, frames = page.locator('iframe[title="Storefront banner preview"]');
  const preview = (index: number) => page.frameLocator('iframe[title="Storefront banner preview"]').nth(index).locator('[data-sf-menu-top]');
  const original = await rpc(f, token, 'get_restaurant_storefront_content_v5');
  const originalProfile = await rpc(f, token, 'get_restaurant_storefront_profile');
  const completedFixture = completeResponsiveFixture(original.document), fixtureBase = completedFixture.document;
  const receipt: Obj = { status: 'FAIL', stage: 'baseline-source', data: 'synthetic isolated CI; actual owner API and renderer; legacy absence/null compatibility against pinned production CSS replay, not a separately built deployment', rows: [], baseline: baselineBannerEvidence(resolve(__dirname, '../..')),
    fixtureRestoration: { materializedNullKeys: completedFixture.materializedNullKeys,
      meaning: 'Explicit null restores legacy semantics for the five mutated optional keys; not original missing-key byte identity.' } };
  const write = async (name: string, body: Obj) => {
    const response = await fetch(`${API}/rest/v1/rpc/${name}`, { method: 'POST', redirect: 'error',
      headers: { apikey: f.anonKey, authorization: 'Bearer ' + token, 'content-type': 'application/json' },
      body: JSON.stringify({ p_organization_id: f.ownerA.orgId, p_restaurant_id: f.ownerA.restaurantId,
        p_client_request_id: randomUUID(), ...body }) });
    expect(response.status).toBe(200); expect((await response.json()).ok).toBe(true);
  };
  const saveDocument = async (document: Obj) => {
    const current = await rpc(f, token, 'get_restaurant_storefront_content_v5');
    await write('set_restaurant_storefront_content_v1', { p_expected_version: current.version,
      p_expected_storefront_branch_id: f.ownerA.branchId, p_document: document });
    const actual = (await rpc(f, token, 'get_restaurant_storefront_content_v5')).document;
    try { expect(actual).toEqual(document); }
    catch (error) {
      if (!Object.hasOwn(receipt, 'firstSaveMismatch')) receipt.firstSaveMismatch = responsiveFixtureMismatch(document, actual);
      throw error;
    }
  };
  const saveProfilePatch = async (patch: Obj) => {
    const current = await rpc(f, token, 'get_restaurant_storefront_profile');
    await write('set_restaurant_storefront_profile', { p_expected_version: current.version, p_patch: patch });
  };
  const hour = Number(new Intl.DateTimeFormat('en-US', { timeZone: originalProfile.derived.timezone, hour: '2-digit', hourCycle: 'h23' }).format(new Date()));
  const time = (h: number) => `${String((h + 24) % 24).padStart(2, '0')}:00`;
  const hours = (open: boolean) => ({ weekly: Array.from({ length: 7 }, (_, dow) =>
    ({ dow, open: time(hour + (open ? -1 : 4)), close: time(hour + (open ? 2 : 5)) })), exceptions: [] });
  const target = { x: 38, y: 9 }, annotation = 'BANNER FIT — بيانات اختبار';
  let expectedPath = '';
  const render = async (width: number, state: string, enabled = true, theme?: string, annotated = false) => {
    await menu.setViewportSize({ width, height: width > 650 ? 900 : 844 });
    await expect.poll(async () => {
      await menu.goto(STOREFRONT + '/ar/s/' + f.ownerA.slug + '/menu', { waitUntil: 'domcontentloaded' });
      return menu.evaluate(marker => ({ state: document.querySelector('[data-sf-order-status] [data-state]')?.getAttribute('data-state'),
        images: document.querySelectorAll('[data-sf-menu-banner] img').length,
        light: getComputedStyle(document.querySelector('[data-sf-root]')!).getPropertyValue('--bg').trim().toLowerCase() === '#ffffff',
        annotated: document.querySelector('[data-sf-module="announce"]')?.textContent?.includes(marker) ?? false }), annotation);
    }, { timeout: 100000, intervals: [250, 500, 1000] }).toEqual({ state, images: enabled ? 1 : 0,
      light: theme === 'light', annotated: annotated && state === 'open' });
    await expect(menu.locator('[data-sf-menu-banner] img')).toHaveCount(enabled ? 1 : 0);
    if (enabled) await expect.poll(() => bannerGeometry(menu.locator('[data-sf-menu-top]')).then(g => g.position)).toBe(`${target.x}% ${target.y}%`);
  };
  try {
    for (const [theme, state] of [['dark', 'open'], ['light', 'closed']] as const) {
      receipt.stage = `${theme}-${state}-owner-api`;
      const document = structuredClone(fixtureBase);
      Object.assign(document.appearance, { site_theme: theme, menu_intro_visible: false, menu_banner_enabled: true,
        menu_banner_focal_x: target.x, menu_banner_focal_y: target.y });
      document.announcement_text = annotation; document.announcement_segments = null;
      await saveDocument(document);
      await saveProfilePatch({ opening_hours: hours(state === 'open'), paused_until: null, pause_reason: null });
      await render(390, state, true, theme, true);
      if (state === 'open') await expect(menu.locator('[data-sf-module="announce"]'), 'The real announcement is present, not dismissed in both comparison views').toContainText(annotation);
      else await expect(menu.locator('[data-sf-module="announce"]'), 'Closed state keeps the existing announcement suppression').toHaveCount(0);
      await expect(menu.locator('[data-sf-notice="closed"]'), 'Closed-state coverage includes the actual notice').toHaveCount(state === 'closed' ? 1 : 0);
      const first = await bannerGeometry(menu.locator('[data-sf-menu-top]'));
      if (expectedPath) expect(first.publicPath).toBe(expectedPath); else expectedPath = first.publicPath;
      await openEditor(page, true); await openFoldedGroup(page, 'banner');
      await expect(frames).toHaveCount(2);
      for (const index of [0, 1]) {
        await expect(frames.nth(index)).toHaveAttribute('sandbox', 'allow-same-origin');
        const policy = await page.frameLocator('iframe[title="Storefront banner preview"]').nth(index).locator('meta[http-equiv="Content-Security-Policy"]').getAttribute('content');
        expect(policy).toContain("script-src 'none'"); expect(policy).toContain("style-src 'self'"); expect(policy).toContain("connect-src 'none'");
        await expect.poll(() => bannerGeometry(preview(index)).then(g => [g.state, g.position, g.publicPath])).toEqual([state, '38% 9%', expectedPath]);
        const announcement = (await bannerGeometry(preview(index))).announcement;
        if (state === 'open') expect(announcement).toContain(annotation);
        else expect(announcement).toBeNull();
      }
      for (const width of [1280, 1920, 390, 360, 430, 650, 651]) {
        receipt.stage = `${theme}-${state}-${width}`;
        await render(width, state, true, theme, true);
        const root = menu.locator('[data-sf-menu-top]'), current = await bannerGeometry(root);
        expect(current.viewportWidth).toBe(width); expect(current.publicPath).toBe(expectedPath);
        expect(current.position).toBe('38% 9%'); expect(current.imageCount).toBe(1);
        expect(current.sceneWidth).toBe(width); expect(current.bannerWidth).toBe(width);
        expect(current.fit, 'No responsive setting preserves the legacy cover renderer').toBe('cover');
        expect(current.imageFilter).toBe('none');
        const capture = `${theme}-${state}-${width}`;
        await bannerViewportScreenshot(menu, resolve(out, `banner-fit-after-${capture}.png`), `CANDIDATE ${capture}`);
        const restore = await replayBaselineBanner(root);
        let before: Obj;
        try {
          before = await bannerGeometry(root);
          await bannerViewportScreenshot(menu, resolve(out, `banner-fit-before-${capture}.png`), `PINNED BASELINE CSS REPLAY ${capture} — NOT MAIN BUILD`);
          expect(before, 'With responsive fields absent/null, every viewport equals the pinned production CSS geometry').toEqual(current);
        } finally { await restore(); }
        expect(await bannerGeometry(root), 'Test-only CSS replay restores the candidate exactly').toEqual(current);
        let matchedPreview: Obj | null = null;
        if ([1280, 390, 360, 430].includes(width)) {
          const index = width === 1280 ? 1 : 0;
          if (!index) {
            const choice = page.getByRole('checkbox', { name: `${width}px`, exact: true });
            await reveal(page, choice, 'field');
            if (!await choice.isChecked()) await tapRevealedControl(page, choice);
          }
          await expect.poll(() => bannerGeometry(preview(index)).then(g => g.viewportWidth)).toBe(width);
          matchedPreview = await bannerGeometry(preview(index));
          for (const key of ['viewportWidth', 'width', 'height', 'naturalWidth', 'naturalHeight', 'fit', 'publicPath', 'position', 'searchY', 'categoriesY', 'state', 'themeBackground'])
            expect(matchedPreview[key], `Actual Dashboard iframe and Storefront match ${key} at ${width}`).toEqual(current[key]);
          await reveal(page, frames.nth(index), 'content-status');
          await frames.nth(index).screenshot({ path: resolve(out, `banner-fit-dashboard-${capture}.png`) });
        }
        receipt.rows.push({ theme, state, width, current, before: before!, matchedPreview, captures: { before: `banner-fit-before-${capture}.png`, after: `banner-fit-after-${capture}.png` } });
      }
    }
    receipt.stage = 'phone-interactions';
    // Use the open case without fake time, response overrides or production data.
    const active = structuredClone(fixtureBase); Object.assign(active.appearance, { site_theme: 'dark', menu_intro_visible: false });
    await saveDocument(active); await saveProfilePatch({ opening_hours: hours(true) }); await render(390, 'open');
    const firstSection = menu.locator('[data-sf-module="sections"]').first();
    const phoneInteractions: Obj = {}; receipt.phoneInteractions = phoneInteractions;
    const independentBefore = await menu.locator('[data-sf-carousel]').evaluateAll(nodes => nodes.slice(1).map(node => node.getAttribute('data-sf-selected')));
    const activeSlide = firstSection.locator('[data-sf-carousel-product][data-position="active"]');
    await expect(firstSection.locator('[data-sf-carousel-product]'), 'Fixture must actually support swipe, never pass with a single item').toHaveCount(2);
    const oldItem = await activeSlide.getAttribute('data-sf-carousel-product');
    const carousel = firstSection.locator('[data-sf-carousel-stage]');
    await carousel.scrollIntoViewIfNeeded();
    const box = await carousel.boundingBox(); expect(box).not.toBeNull();
    const beforeDrag = await activeSlide.boundingBox(); expect(beforeDrag).not.toBeNull();
    await menu.mouse.move(box!.x + box!.width * .75, box!.y + box!.height / 2); await menu.mouse.down();
    await menu.mouse.move(box!.x + box!.width * .25, box!.y + box!.height / 2, { steps: 8 });
    expect(await activeSlide.getAttribute('data-sf-carousel-product'), 'Selection remains stable during the finger-following drag').toBe(oldItem);
    expect(Math.abs((await activeSlide.boundingBox())!.x - beforeDrag!.x), 'Slide visibly follows the pointer before release').toBeGreaterThan(20);
    phoneInteractions.slideFollowsPointerBeforeRelease = true;
    await menu.mouse.up();
    await expect.poll(() => activeSlide.getAttribute('data-sf-carousel-product')).not.toBe(oldItem);
    await expect(menu.locator('dialog[open]'), 'Releasing a swipe never opens product or cart').toHaveCount(0);
    phoneInteractions.swipeSelectsWithoutOpeningDialog = true;
    const arrows = firstSection.getByRole('button', { name: 'المنتج التالي', exact: true });
    const swiped = await activeSlide.getAttribute('data-sf-carousel-product'); await arrows.click();
    await expect.poll(() => activeSlide.getAttribute('data-sf-carousel-product')).not.toBe(swiped);
    phoneInteractions.arrowsChangeSelection = true;
    expect(await menu.locator('[data-sf-carousel]').evaluateAll(nodes => nodes.slice(1).map(node => node.getAttribute('data-sf-selected'))), 'Other category sliders remain independent').toEqual(independentBefore);
    phoneInteractions.otherCategorySlidersIndependent = true;
    await menu.getByRole('searchbox').fill('TEST 1');
    await expect(menu.getByRole('searchbox')).toHaveValue('TEST 1'); await menu.getByRole('searchbox').fill('');
    await expect(menu.getByRole('searchbox')).toHaveValue('');
    phoneInteractions.searchInputAndClear = true;
    const categories = menu.locator('[data-sf-module="categories"] button'); await categories.nth(1).click();
    await expect.poll(() => menu.evaluate(() => window.scrollY)).toBeGreaterThan(0);
    phoneInteractions.verticalCategoryNavigation = true;
    await menu.getByRole('button', { name: /سلتك: 0/ }).click(); await expect(menu.locator('dialog[open]')).toHaveCount(1);
    await menu.keyboard.press('Escape'); await expect(menu.locator('dialog[open]')).toHaveCount(0);
    phoneInteractions.emptyCartOpensAndCloses = true;
    for (const theme of ['light', 'dark']) {
      receipt.stage = `no-banner-${theme}`;
      const document = structuredClone(fixtureBase); Object.assign(document.appearance, { site_theme: theme, menu_banner_enabled: false, menu_intro_visible: false });
      await saveDocument(document);
      for (const width of [390, 1280]) {
        await render(width, 'open', false, theme);
        const top = await menu.locator('[data-sf-menu-top]').boundingBox(); expect(top!.height).toBeLessThan(600);
        await expect(menu.locator('[data-sf-scene-window]')).toHaveCount(0);
        await bannerViewportScreenshot(menu, resolve(out, `banner-fit-absent-${theme}-${width}.png`), `NO BANNER ${theme} ${width}`);
      }
    }
    receipt.status = 'BANNER_RESPONSIVE_PASS'; receipt.stage = null;
  } finally {
    // Restore only this synthetic owner's display settings, by the same CAS APIs.
    const succeeded = receipt.status === 'BANNER_RESPONSIVE_PASS';
    try {
      await saveDocument(fixtureBase);
      await saveProfilePatch({ opening_hours: originalProfile.profile.opening_hours,
        paused_until: originalProfile.profile.paused_until, pause_reason: originalProfile.profile.pause_reason });
      await openEditor(page, true); await openFoldedGroup(page, 'banner');
      receipt.syntheticSettingsRestored = true;
    } catch (error) {
      receipt.syntheticSettingsRestored = false;
      if (succeeded) { receipt.status = 'FAIL'; receipt.stage = 'restore-synthetic-settings'; throw error; }
    } finally {
      writeFileSync(resolve(out, 'banner-responsive-result.json'), JSON.stringify(receipt, null, 2));
    }
  }
}

async function verifyBannerJourney(page: Page, menu: Page, f: Fixture, token: string, diagnostics: () => UploadDiagnostics): Promise<void> {
  const out = process.env.CINEMATIC_ARTIFACT_DIR!;
  let stage = 'baseline';
  const receipt: Obj = { status: 'FAIL', failedStage: stage, data: 'actual isolated Dashboard/Auth/Storage/Edge; no mocked publication', publications: [] };
  const read = async () => (await rpc(f, token, 'get_restaurant_storefront_content_v6')).document;
  const publicMenu = async () => {
    const response = await fetch(API + '/rest/v1/rpc/storefront_menu_v11', { method: 'POST', redirect: 'error',
      headers: { apikey: f.anonKey, authorization: 'Bearer ' + f.anonKey, 'content-type': 'application/json' }, body: JSON.stringify({ p_slug: f.ownerA.slug }) });
    expect(response.status).toBe(200); const value = await response.json(); expect(value.ok).toBe(true); return value;
  };
  const baseline = await read();
  const unchanged = async () => {
    expect((await read()).appearance.menu_background_media_id).toBe(baseline.appearance.menu_background_media_id);
    await invariants(f, token);
  };
  try {
    for (const [index, geometry] of [[900, 450], [1000, 750]].entries()) {
      const file = `ux003-banner-${index}.png`;
      // Procedural test pixels through the existing fixture generator. Unique
      // sources avoid collisions with independent Hero/product security inputs.
      const chosen = readFileSync(resolve(dirname(process.env.CINEMATIC_FIXTURE_FILE!), file));
      stage = index === 0 ? 'upload-save-first-banner' : 'replace-save-banner';
      await openEditor(page, true); await openFoldedGroup(page, 'banner');
      const publication = await upload(page, file, diagnostics(), 200, 'banner', chosen);
      expect(publication.recipe).toBe('storefront-media-c4'); expect(publication.media.variant).toBe('w960');
      await saveContent(page); await openEditor(page, true); await openFoldedGroup(page, 'banner');
      const document = await read();
      expect(document.appearance.menu_banner_media_id).toBe(publication.media.id);
      expect(document.appearance.menu_banner_enabled).toBe(true); await unchanged();
      stage = 'verify-retained-private-source';
      const sourceResponse = await fetch(API + '/rest/v1/rpc/get_storefront_background_source_v1', { method: 'POST', redirect: 'error',
        headers: { apikey: f.anonKey, authorization: 'Bearer ' + token, 'content-type': 'application/json' },
        body: JSON.stringify({ p_organization_id: f.ownerA.orgId, p_restaurant_id: f.ownerA.restaurantId, p_branch_id: f.ownerA.branchId, p_base_media_id: publication.media.id }) });
      expect(sourceResponse.status).toBe(200); const source = await sourceResponse.json(); expect(source.ok).toBe(true);
      expect(source.source_bucket).toBe('restaurant-logos');
      expect(source.source_key.startsWith(f.ownerA.orgId + '/' + f.ownerA.restaurantId + '/logo/')).toBe(true);
      const privateReply = await fetch(API + '/storage/v1/object/authenticated/restaurant-logos/' + source.source_key.split('/').map(encodeURIComponent).join('/'),
        { redirect: 'error', headers: { apikey: f.anonKey, authorization: 'Bearer ' + token } });
      expect(privateReply.status).toBe(200);
      const original = Buffer.from(await privateReply.arrayBuffer());
      const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
      expect(hash(original), 'Dashboard retains the exact private source bytes').toBe(hash(chosen));
      stage = 'public-banner-read-and-render';
      const current = await publicMenu(), path = current.content_v1.appearance.menu_banner_url;
      expect(path).toMatch(/^\/storage\/v1\/object\/public\/storefront-media\/[a-f0-9]{32}\/[a-f0-9]{64}\.webp$/);
      const actual = await fetch(API + path, { redirect: 'error' }); expect(actual.status).toBe(200);
      const bytes = Buffer.from(await actual.arrayBuffer()); expect(bytes.length).toBe(publication.media.bytes);
      const dimensions = await menu.evaluate(async data => {
        const image = await createImageBitmap(new Blob([Uint8Array.from(atob(data), c => c.charCodeAt(0))]));
        const result = { width: image.width, height: image.height }; image.close(); return result;
      }, bytes.toString('base64'));
      expect(dimensions).toEqual({ width: publication.media.width, height: publication.media.height });
      expect(Math.max(dimensions.width, dimensions.height)).toBeLessThanOrEqual(960);
      await expect.poll(async () => {
        await menu.goto(STOREFRONT + '/ar/s/' + f.ownerA.slug + '/menu', { waitUntil: 'domcontentloaded' });
        const image = menu.locator('[data-sf-menu-banner] img');
        return await image.count() === 1 && (await image.getAttribute('src'))?.endsWith(path);
      }, { timeout: 100000, intervals: [250, 500, 1000] }).toBe(true);
      if (index === 0) {
        stage = 'banner-focal-persistence';
        await verifyBannerFocalPersistence(page, menu, f, token);
        stage = 'banner-responsive';
        await verifyBannerResponsive(page, menu, f, token);
        // The responsive case ends on a no-banner document. Restoring the
        // synthetic server settings does not refresh this already loaded tab.
        stage = 'restored-banner-public-read-and-render';
        expect((await publicMenu()).content_v1.appearance.menu_banner_url).toBe(path);
        await expect.poll(async () => {
          await menu.goto(STOREFRONT + '/ar/s/' + f.ownerA.slug + '/menu', { waitUntil: 'domcontentloaded' });
          const restored = menu.locator('[data-sf-menu-banner] img');
          return await restored.count() === 1 ? {
            sameResource: (await restored.getAttribute('src'))?.endsWith(path),
            position: await restored.evaluate(img => getComputedStyle(img).objectPosition),
          } : null;
        }, { timeout: 100000, intervals: [250, 500, 1000] }).toEqual({ sameResource: true, position: '38% 9%' });
        receipt.responsiveReturn = { freshPublicRead: true, freshDocumentRead: true, samePublicPath: path, position: '38% 9%' };
        stage = 'independent-responsive-settings-ui-save-readback';
        await verifyResponsiveBannerSettings(page, menu, {
          read: () => rpc(f, token, 'get_restaurant_storefront_content_v6'),
          readLegacy: () => rpc(f, token, 'get_restaurant_storefront_content_v5'),
          publicRead: async version => {
            const response = await fetch(API + '/rest/v1/rpc/storefront_menu_v' + version, { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30_000),
              headers: { apikey: f.anonKey, authorization: 'Bearer ' + f.anonKey, 'content-type': 'application/json' }, body: JSON.stringify({ p_slug: f.ownerA.slug }) });
            expect(response.status).toBe(200); const value = await response.json(); expect(value.ok).toBe(true); return value;
          },
          writeDocument: async document => {
            const current = await rpc(f, token, 'get_restaurant_storefront_content_v6');
            const response = await fetch(API + '/rest/v1/rpc/set_restaurant_storefront_content_v1', { method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30_000),
              headers: { apikey: f.anonKey, authorization: 'Bearer ' + token, 'content-type': 'application/json' },
              body: JSON.stringify({ p_organization_id: f.ownerA.orgId, p_restaurant_id: f.ownerA.restaurantId, p_client_request_id: randomUUID(),
                p_expected_version: current.version, p_expected_storefront_branch_id: f.ownerA.branchId, p_document: document }) });
            expect(response.status).toBe(200); const result = await response.json(); expect(result.ok).toBe(true); expect(result.version).toBe(current.version + 1);
          },
          reload: async () => {
            const observed = observeResponse(page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/get_restaurant_storefront_content_v6')));
            const response = await responseAfterAction(observed, () => openEditor(page, true));
            expect(response.status()).toBe(200); const readback = await response.json(); expect(readback.ok).toBe(true);
            await openFoldedGroup(page, 'banner'); return readback;
          },
          save: () => saveContent(page),
          upload: index => {
            const file = `responsive-banner-${index}.png`;
            return upload(page, file, diagnostics(), 200, 'desktop-banner', readFileSync(resolve(dirname(process.env.CINEMATIC_FIXTURE_FILE!), file)));
          },
          reveal: target => reveal(page, target, 'field'), tap: target => tapRevealedControl(page, target),
          freshMenu: async width => {
            const browser = page.context().browser(); expect(browser).not.toBeNull();
            const context = await browser!.newContext({ viewport: { width, height: width > 650 ? 900 : 844 }, locale: 'ar', serviceWorkers: 'block' });
            const network = await guardBrowser(context), surface = await context.newPage(), requestedMedia: string[] = [];
            surface.on('request', request => { const url = new URL(request.url());
              if (request.resourceType() === 'image' && url.origin === LOGICAL_ORIGIN) requestedMedia.push(url.pathname); });
            return { page: surface, requestedMedia, check: network.check, close: () => context.close() };
          },
          captureHeightVideo: async (height, recordEvidence) => {
            const videoEvidence: Obj = { status: 'NOT_RUN', failedSubstage: 'read_saved_height', captures: [],
              errorType: null, controlRevealPurpose: null, controlRevealTail: [] };
            recordEvidence(videoEvidence);
            const before = await rpc(f, token, 'get_restaurant_storefront_content_v6');
            expect(before.document.appearance.menu_banner_mobile_height_px).toBe(height);
            const browser = page.context().browser(); expect(browser).not.toBeNull();
            // Auxiliary recording only: this state belongs to the real synthetic
            // owner UI test above, remains in memory, and is never an artifact.
            videoEvidence.failedSubstage = 'create_recording_context';
            const recording = await browser!.newContext({ storageState: await page.context().storageState(),
              viewport: { width: 1440, height: 1000 }, locale: 'ar', serviceWorkers: 'block',
              recordVideo: { dir: resolve(process.env.RUNNER_TEMP!, 'cinematic-private/height-video'), size: { width: 1080, height: 750 } } });
            const videoNetwork = await guardBrowser(recording), videoPage = await recording.newPage();
            const clip = videoPage.video(); expect(clip).not.toBeNull();
            let contentWrites = 0, loginEntries = 0, accepted = false;
            const started = Date.now();
            videoPage.on('request', request => {
              if (request.method() === 'POST' && new URL(request.url()).pathname === '/rest/v1/rpc/set_restaurant_storefront_content_v1') contentWrites++;
              if (isPasswordGrantRequest(request.url(), request.method(), API)) loginEntries++;
            });
            try {
              videoEvidence.failedSubstage = 'open_editor';
              await videoPage.goto(DASHBOARD, { waitUntil: 'domcontentloaded' }); await semantics(videoPage); await videoNetwork.fontsReady();
              await openEditor(videoPage); await openFoldedGroup(videoPage, 'banner');
              expect(await videoPage.locator('input[type="password"]').count()).toBe(0);
              await expect.poll(() => readAccessibleText(videoPage)).toContain('CINEMATIC TEST A');
              const frame = videoPage.frameLocator('iframe[title="Storefront banner preview"]').nth(0).locator('[data-sf-menu-top]');
              videoEvidence.failedSubstage = 'verify_saved_preview';
              const state = (await publicMenu()).service.state;
              await expect.poll(() => bannerGeometry(frame).then(g => [g.state, g.height]).catch(() => null)).toEqual([state, height]);
              const originalNode = await frame.locator('[data-sf-menu-banner] img').elementHandle(); expect(originalNode).not.toBeNull();
              const revealRange = (target: Locator) => reveal(videoPage, target, 'field');
              const iframe = videoPage.locator('iframe[title="Storefront banner preview"]').nth(0);
              const capturePreview = async (label: 'high' | 'restored') => {
                const originalViewport = videoPage.viewportSize(); expect(originalViewport).not.toBeNull();
                const frameBox = await iframe.boundingBox(); expect(frameBox).not.toBeNull();
                const captureViewport = { width: originalViewport!.width,
                  height: Math.max(originalViewport!.height, Math.ceil(frameBox!.height) + 192) };
                expect(captureViewport.height, 'The controlled synthetic preview has a bounded capture height').toBeLessThanOrEqual(2400);
                try {
                  await videoPage.setViewportSize(captureViewport);
                  await reveal(videoPage, iframe, 'content-status');
                  const logicalPreviewWidth = await frame.evaluate(el => el.ownerDocument.documentElement.clientWidth);
                  expect(logicalPreviewWidth, 'Capture resizing preserves the real 390px preview document').toBe(390);
                  await iframe.screenshot({ path: resolve(out, `responsive-height-video-${label}.png`) });
                  videoEvidence.captures.push({ label, viewport: captureViewport, frameHeight: frameBox!.height,
                    logicalPreviewWidth, zoom: 100 });
                } finally { await videoPage.setViewportSize(originalViewport!); }
              };
              videoEvidence.failedSubstage = 'height_up_keys';
              await adjustBannerHeightWithKeyboard(videoPage, revealRange, height, height + 20);
              await expect.poll(() => bannerGeometry(frame).then(g => g.height)).toBe(height + 20);
              videoEvidence.failedSubstage = 'capture_high_preview'; await capturePreview('high');
              videoEvidence.failedSubstage = 'height_down_keys';
              await adjustBannerHeightWithKeyboard(videoPage, revealRange, height + 20, height);
              await expect.poll(() => bannerGeometry(frame).then(g => g.height)).toBe(height);
              videoEvidence.failedSubstage = 'capture_restored_preview'; await capturePreview('restored');
              videoEvidence.failedSubstage = 'verify_invariants';
              expect(await originalNode!.evaluate(el => el.isConnected), 'Recording uses actual live preview updates, not source replacement').toBe(true);
              expect(contentWrites).toBe(0); expect(loginEntries).toBe(0);
              expect(await rpc(f, token, 'get_restaurant_storefront_content_v6')).toEqual(before);
              videoEvidence.nativeMedia = await videoNetwork.checkDashboardMedia(value => { videoEvidence.nativeMedia = value; }); accepted = true;
            } catch (error) {
              videoEvidence.errorType = error instanceof ControlRevealError ? 'ControlRevealError'
                : error instanceof Error && ['Error', 'TypeError', 'TimeoutError', 'AssertionError'].includes(error.name) ? error.name : 'unclassified';
              if (error instanceof ControlRevealError) {
                videoEvidence.controlRevealPurpose = error.purpose;
                videoEvidence.controlRevealTail = error.samples.slice(-3).map(sample => ({ iteration: sample.iteration,
                  normalMatches: sample.normalMatches, hiddenMatches: sample.hiddenMatches,
                  geometry: sample.geometry == null ? null : Object.fromEntries(
                    ['x', 'y', 'width', 'height', 'viewportWidth', 'viewportHeight', 'centerHit', 'flutterSurfaceHit', 'disabled'].map(key => [key, sample.geometry![key as keyof typeof sample.geometry]])) }));
              }
              throw error;
            } finally { await recording.close(); }
            expect(accepted).toBe(true);
            videoEvidence.failedSubstage = 'finalize_recording';
            const file = 'responsive-banner-height-adjustment.webm';
            await clip!.saveAs(resolve(out, file));
            const bytes = readFileSync(resolve(out, file));
            return { status: 'SYNTHETIC_HEIGHT_ADJUSTMENT_VIDEO_RECORDED', file, bytes: bytes.length,
              sha256: createHash('sha256').update(bytes).digest('hex'), durationWindowMs: Date.now() - started,
              includesLocalEditorBoot: true, values: [height, height + 20, height], contentWrites: 0, loginEntries: 0,
              syntheticStateInMemoryOnly: true, noOwnerBrowserSession: true, captures: videoEvidence.captures, nativeMedia: videoEvidence.nativeMedia };
          },
          invariant: unchanged, url: STOREFRONT + '/ar/s/' + f.ownerA.slug + '/menu', artifactDir: out,
        });
        receipt.independentResponsiveSettingsAcceptance = 'RESPONSIVE_BANNER_SETTINGS_SAVE_READBACK_PASS';
      }
      const image = menu.locator('[data-sf-menu-banner] img');
      await expect.poll(() => image.evaluate(img => (img as HTMLImageElement).complete && (img as HTMLImageElement).naturalWidth > 0)).toBe(true);
      await screenshot(menu, resolve(out, `banner-${index ? 'replacement' : 'first'}-test-data.png`));
      receipt.publications.push({ publicPath: path, originalBytes: original.length, originalSha256: hash(original), publishedBytes: bytes.length, publishedSha256: hash(bytes), ...dimensions });
    }
    stage = 'clear-banner-only';
    await revealButton(page, L.bannerClear); await tapRevealedButton(page, L.bannerClear); await saveContent(page);
    await openEditor(page, true); expect((await read()).appearance.menu_banner_media_id).toBeNull(); await unchanged();
    await expect.poll(async () => {
      await menu.goto(STOREFRONT + '/ar/s/' + f.ownerA.slug + '/menu', { waitUntil: 'domcontentloaded' });
      return await menu.locator('[data-sf-menu-top]').count() === 1 && await menu.locator('[data-sf-menu-banner]').count() === 0;
    }, { timeout: 100000, intervals: [250, 500, 1000] }).toBe(true);
    receipt.status = 'BANNER_UPLOAD_E2E_PASS'; receipt.failedStage = null;
    receipt.backgroundAndWelcomePreserved = true;
  } finally {
    if (receipt.status !== 'BANNER_UPLOAD_E2E_PASS') receipt.failedStage = stage;
    writeFileSync(resolve(out, 'banner-upload-result.json'), JSON.stringify(receipt, null, 2));
  }
}

test('real owner Dashboard → Storage → publisher → save → live menu; replacement, clear and appearance', async ({ page, context }) => {
  // Leave both final clear checks their full render windows after the earlier
  // saves, reloads and scene checks in this serial browser journey.
  test.setTimeout(20 * 60_000);
  const f = fixture();
  const network = await guardBrowser(context);
  const out = resolve(process.env.CINEMATIC_ARTIFACT_DIR ?? 'cinematic-artifacts');
  mkdirSync(out, { recursive: true });
  const quality = new BackgroundQuality(out);
  quality.observe(page);
  const stages: string[] = [];
  let stage = 'login';
  const loginEvidence: {
    fieldsBeforeSubmit: { emailMatchesFixture: boolean; passwordMatchesFixture: boolean } | null;
    request: ReturnType<typeof authRequestEvidence> | null;
    response: ReturnType<typeof authResponseEvidence> | null;
  } = { fieldsBeforeSubmit: null, request: null, response: null };
  const uploadDiagnostics: UploadDiagnostics[] = [];
  const nextUpload = () => { const diagnostics = new UploadDiagnostics(); uploadDiagnostics.push(diagnostics); return diagnostics; };
  let draftWrites = 0, profileWrites = 0;
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.origin === API && request.method() === 'POST' &&
        ['/rest/v1/rpc/set_restaurant_storefront_profile', '/rest/v1/rpc/set_restaurant_storefront_content_v1'].includes(url.pathname)) draftWrites++;
    if (url.origin === API && request.method() === 'POST' && url.pathname === '/rest/v1/rpc/set_restaurant_storefront_profile') profileWrites++;
  });
  try {
    await page.goto(DASHBOARD, { waitUntil: 'domcontentloaded' });
    await semantics(page);
    await network.fontsReady();
    await fillField(page, L.email, f.ownerA.email);
    stage = 'login-password-entry';
    await enterLoginPassword(page, f.ownerA.password);
    stage = 'login-pre-submit';
    // Check only equality booleans before sending the one Auth request.
    // An incomplete entry fails here without attempting a bad sign-in.
    loginEvidence.fieldsBeforeSubmit = {
      emailMatchesFixture: await page.getByRole('textbox', { name: L.email }).evaluateAll((nodes, expected) =>
        nodes[0] instanceof HTMLInputElement && nodes[0].value === expected, f.ownerA.email),
      passwordMatchesFixture: await page.locator('input[type="password"]').evaluateAll((nodes, expected) =>
        nodes[0] instanceof HTMLInputElement && nodes[0].value === expected, f.ownerA.password),
    };
    expect(loginEvidence.fieldsBeforeSubmit.emailMatchesFixture,
      'Actual Dashboard email matches the intended fixture before submission').toBe(true);
    expect(loginEvidence.fieldsBeforeSubmit.passwordMatchesFixture,
      'Actual Dashboard password matches the intended fixture before submission').toBe(true);
    stage = 'login';
    const loginStarted = performance.now();
    const signedIn = observeResponse(page.waitForResponse(r => isPasswordGrantRequest(r.url(), r.request().method(), API)));
    const auth = await responseAfterAction(signedIn, () => tapButton(page, L.login, { which: 'last' }));
    const loginDuration = performance.now() - loginStarted;
    loginEvidence.request = authRequestEvidence(auth.url(), auth.request().postData(), f.ownerA);
    // Parse only for fixed classifications before the status assertion. The
    // full body remains transient/private; the existing session path follows.
    const authData: unknown = await auth.json().catch(() => null);
    loginEvidence.response = authResponseEvidence({ status: auth.status(),
      contentType: auth.headers()['content-type'], data: authData }, loginDuration);
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
    await verifyReadCompatibility(f, token);
    stages.push(stage);

    stage = 'upload-publish-select-save-reload';
    const firstPublish = await upload(page, 'background-2816.jpg', nextUpload());
    expect([firstPublish.recipe, firstPublish.media.width, firstPublish.media.height, firstPublish.media.bytes, firstPublish.media.content_hash],
      'The real base publisher identifies its c4 output').toEqual(['storefront-media-c4', 960, 720, 111406, '211a00daf75bb8f868cec1c95aaa1e4c5e7d1d9aba8b46e6867d2753a8ff2ed3']);
    stages.push('first-upload-published-selected');
    stage = 'save-first-background';
    await saveContent(page);
    stages.push(stage);
    stage = 'read-first-background';
    const first = (await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.menu_background_media_id as string;
    expect(first).not.toBe(f.heroMediaId);
    expect(first).toBe(firstPublish.media.id);
    stage = 'verify-first-background-companion';
    await quality.verifyPublication(first, () => readCompanionUi(page), async () => {
      const retry = 'إعادة محاولة التحضير نفسه';
      await reveal(page, page.getByRole('button', {name:retry, exact:true}), 'other', page.getByRole('button', {name:retry, exact:true, includeHidden:true}));
      await expect(page.getByRole('button', {name:retry, exact:true}), 'Only a genuine uncertain state allows a retry').toBeEnabled();
      await tapRevealedButton(page, retry);
    });
    await quality.privateOriginal(f, token, first);
    const pair = await quality.readManifest(f);
    const firstUrl = await backgroundUrl(f, token, first);
    await verifyReadCompatibility(f, token);
    stage = 'reload-first-background';
    await openEditor(page, true);
    await screenshot(page, resolve(out, 'dashboard-menu-background-test-data.png'));
    await captureMediaLibrary(page, first, resolve(out, 'dashboard-media-library-test-data.png'));
    await invariants(f, token);
    const menu = await context.newPage();
    await renderMenu(menu, f, firstUrl, 15);
    stages.push(stage);

    stage = 'site-theme-baseline';
    const themeBaseline = await rpc(f, token, 'get_restaurant_storefront_content_v5');
    const profileBaseline = (await rpc(f, token, 'get_restaurant_storefront_profile')).profile;
    const retainedMenu = await menu.locator('[data-sf-root]').evaluate(root => {
      const style = getComputedStyle(root);
      return { primary: style.getPropertyValue('--bg').trim(), accent: style.getPropertyValue('--acc').trim(),
        font: style.getPropertyValue('--font').trim(), scene: root.getAttribute('data-sf-scene') };
    });
    expect(themeBaseline.document.appearance.site_theme ?? null, 'Synthetic fixture starts with legacy appearance').toBeNull();
    let themeVersion: number = themeBaseline.version;
    let selectedTheme: string = L.siteThemeLegacy;
    await openFoldedGroup(page, 'content');
    for (const [mode, label] of [['light', L.siteThemeLight], ['dark', L.siteThemeDark], [null, L.siteThemeLegacy]] as const) {
      stage = mode === null ? 'site-theme-restore-legacy' : `site-theme-${mode}-save-reload`;
      const writesBefore = draftWrites, profileWritesBefore = profileWrites;
      const dropdown = page.getByRole('button', { name: selectedTheme, exact: false });
      await reveal(page, dropdown, 'field', page.getByRole('button', { name: selectedTheme, exact: false, includeHidden: true }));
      await expect(dropdown, 'One actual site appearance dropdown is available').toHaveCount(1);
      await selectRevealedDropdown(page, selectedTheme, label);
      selectedTheme = label;
      expect(draftWrites, 'Choosing site appearance changes only the unsaved draft').toBe(writesBefore);
      const pending = await rpc(f, token, 'get_restaurant_storefront_content_v5');
      expect(pending.version, 'A dropdown selection does not advance server CAS').toBe(themeVersion);
      if (mode === 'light') expect(pending.document).toEqual(themeBaseline.document);
      else expect(pending.document.appearance.site_theme).toBe(mode === 'dark' ? 'light' : 'dark');
      const saved = observeResponse(page.waitForResponse(r => requestIs(r, '/rest/v1/rpc/set_restaurant_storefront_content_v1')));
      const writer = await responseAfterAction(saved, () => saveContent(page));
      const submitted = writer.request().postDataJSON();
      expect(submitted.p_expected_version, 'The UI writer uses the current CAS version').toBe(themeVersion);
      expect(submitted.p_expected_storefront_branch_id, 'The UI writer retains the selected branch').toBe(f.ownerA.branchId);
      expect(submitted.p_document.appearance.site_theme).toBe(mode);
      expect(withoutSiteTheme(submitted.p_document), 'Theme selection preserves every other draft field').toEqual(withoutSiteTheme(themeBaseline.document));
      expect(draftWrites, 'One content Save issues exactly one write').toBe(writesBefore + 1);
      expect(profileWrites, 'Site appearance never saves the independent profile').toBe(profileWritesBefore);
      await openEditor(page, true, 'content');
      const reloaded = page.getByRole('button', { name: label, exact: false });
      await reveal(page, reloaded, 'field', page.getByRole('button', { name: label, exact: false, includeHidden: true }));
      await expect(reloaded, 'The actual reloaded Dashboard retains its saved appearance').toHaveCount(1);
      const readback = await rpc(f, token, 'get_restaurant_storefront_content_v5');
      expect(readback.restaurant_id).toBe(f.ownerA.restaurantId);
      expect(readback.storefront_branch_id).toBe(f.ownerA.branchId);
      expect(readback.version).toBe(++themeVersion);
      expect(readback.document.appearance.site_theme).toBe(mode);
      expect(withoutSiteTheme(readback.document), 'Background, dimming, scene, font, custom colours and content are retained').toEqual(withoutSiteTheme(themeBaseline.document));
      const profileAfter = (await rpc(f, token, 'get_restaurant_storefront_profile')).profile;
      expect(profileAfter.version, 'Content and profile share the same CAS version').toBe(themeVersion);
      // The existing profile row trigger updates metadata on a content save.
      // All actual settings remain equal; only version/updated_at may advance.
      expect({ ...profileAfter, version: profileBaseline.version, updated_at: profileBaseline.updated_at },
        'Content theme Save preserves the independent profile settings').toEqual(profileBaseline);
      const [v8, v7] = await Promise.all([publicThemeMenu(f, 'storefront_menu_v8'), publicThemeMenu(f, 'storefront_menu_v7')]);
      expect(v8.content_v1.appearance.site_theme).toBe(mode);
      const v8Projection = structuredClone(v8);
      delete v8Projection.content_v1.appearance.site_theme;
      v8Projection.server_ts = v7.server_ts;
      expect(v8Projection, 'V8 extends V7 only by the explicit site-theme field').toEqual(v7);
      await verifyReadCompatibility(f, token);
      await invariants(f, token);
      if (mode !== null) {
        await renderSiteThemeMenu(menu, f, mode, firstUrl, 15, retainedMenu);
        await screenshot(menu, resolve(out, `storefront-site-theme-${mode}-test-data.png`));
        await screenshot(page, resolve(out, `dashboard-site-theme-${mode}-test-data.png`));
      }
      stages.push(stage);
    }
    // Restore the historical layout/state before the unchanged picker and scene
    // acceptance phases. Restoring legacy is a real UI save, never an API write.
    await openEditor(page, true);
    await renderMenu(menu, f, firstUrl, 15);

    // Both profile and content pickers use the actual sheet, draft, writer and
    // reread path. Preview and Cancel never issue a persistence request.
    for (const [scope, roles] of [
      ['profile', [[L.primary, 'primary_color'], [L.accent, 'accent_color']]],
      ['content', [[L.textColor, 'text_color'], [L.buttonText, 'button_text_color']]],
    ] as const) {
      stage = `visual-picker-${scope}`;
      await openFoldedGroup(page, scope);
      await screenshot(page, resolve(out, `dashboard-${scope}-appearance-test-data.png`));
      const chosen = new Map<string, string>();
      const writesBefore = draftWrites;
      const before = await rpc(f, token, scope === 'profile' ? 'get_restaurant_storefront_profile' : 'get_restaurant_storefront_content_v3');
      for (const [name, key] of roles) {
        stage = `visual-picker-${scope}-${key}-original`;
        const authoritativeOriginal = scope === 'profile'
          ? before.profile[key] : (before.document.appearance?.[key] ?? '');
        expect(authoritativeOriginal, 'The initial draft has a valid authoritative color or explicit inheritance')
          .toMatch(scope === 'profile' ? /^#[0-9a-f]{6}$/ : /^(?:#[0-9a-f]{6})?$/);
        const original = await readColorDraft(page, name, authoritativeOriginal);
        stage = `visual-picker-${scope}-${key}-cancel`;
        await useVisualColorPicker(page, name, false);
        stage = `visual-picker-${scope}-${key}-cancel-readback`;
        expect(await readColorDraft(page, name, original), 'Cancel preserves the actual draft field').toBe(original);
        stage = `visual-picker-${scope}-${key}-apply`;
        const previewed = await useVisualColorPicker(page, name, true, resolve(out, `picker-${key}-test-data.png`));
        stage = `visual-picker-${scope}-${key}-apply-readback`;
        const selected = await readColorDraft(page, name, previewed);
        expect(selected, 'Visual selection produces a complete color without HEX entry').toMatch(/^#[0-9a-f]{6}$/);
        expect(selected, 'Apply changes the actual draft').not.toBe(original);
        chosen.set(key, selected);
      }
      expect(draftWrites, 'Picker preview, Cancel and Apply do not persist').toBe(writesBefore);
      const pending = await rpc(f, token, scope === 'profile' ? 'get_restaurant_storefront_profile' : 'get_restaurant_storefront_content_v3');
      expect(scope === 'profile' ? pending.profile : pending.document, 'Authoritative data stays unchanged before Save')
        .toEqual(scope === 'profile' ? before.profile : before.document);
      stage = `visual-picker-${scope}-save-reload`;
      if (scope === 'profile') await saveProfile(page); else await saveContent(page);
      const persisted = await rpc(f, token, scope === 'profile' ? 'get_restaurant_storefront_profile' : 'get_restaurant_storefront_content_v3');
      await openEditor(page, true, scope);
      for (const [name, key] of roles) {
        expect((scope === 'profile' ? persisted.profile : persisted.document.appearance)[key]).toBe(chosen.get(key));
        expect(await readColorDraft(page, name, chosen.get(key)!), 'Authoritative save survives Dashboard reload').toBe(chosen.get(key));
      }
      stages.push(stage);
    }

    stage = 'profile-colours';
    await openFoldedGroup(page, 'profile');
    await fill(page, L.primary, '#211A16', { blur: true });
    await fill(page, L.accent, '#EAB082', { blur: true });
    await saveProfile(page);
    const savedProfile = await rpc(f, token, 'get_restaurant_storefront_profile');
    expect(savedProfile.profile.primary_color, 'Authoritative saved primary HEX').toBe('#211a16');
    expect(savedProfile.profile.accent_color, 'Authoritative saved accent HEX').toBe('#eab082');
    await openEditor(page, true, 'profile');
    for (const [name, value] of [[L.primary, '#211a16'], [L.accent, '#eab082']]) {
      await revealColorAdvanced(page, name);
      const field = page.getByRole('textbox', { name, exact: true });
      await reveal(page, field, 'field', page.getByRole('textbox', { name, exact: true, includeHidden: true }));
      // Flutter initializes an unfocused semantic input's DOM value lazily.
      // Acquire ordinary focus once to read it; this does not edit the value.
      if (!(await field.evaluate(el => el === document.activeElement))) await tapRevealedControl(page, field);
      await expect(field, 'Reloaded field receives ordinary focus before reading').toBeFocused();
      await expect(field, 'Reloaded Dashboard retains the complete saved HEX').toHaveValue(value);
      await page.keyboard.press('Tab');
      await expect(field, 'Ordinary Tab leaves the reloaded field').not.toBeFocused();
      await expect(field, 'Complete saved HEX remains after blur').toHaveValue(value);
    }
    stages.push(stage);

    await openFoldedGroup(page, 'content');
    for (const [dim, fromFont, label, font] of [
      [0, L.fontDefault, L.fontAlexandria, 'alexandria'],
      [15, L.fontAlexandria, L.fontRubik, 'rubik'],
      [80, L.fontRubik, L.fontSystem, 'system'],
    ] as const) {
      stage = `appearance-${dim}`;
      await fill(page, L.textColor, '#FFF1DA');
      await fill(page, L.buttonText, '#20140C');
      await reveal(page, page.getByRole('button', { name: fromFont, exact: false }), 'other', page.getByRole('button', { name: fromFont, exact: false, includeHidden: true }));
      await selectRevealedDropdown(page, fromFont, label);
      await setDim(page, dim);
      await saveContent(page);
      await openEditor(page, true, 'content');
      const a = (await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance;
      expect(a.menu_background_dim, 'Explicit dimming survives save and reread').toBe(dim);
      expect(a.text_color).toBe('#fff1da');
      expect(a.button_text_color).toBe('#20140c');
      expect(a.font_family).toBe(font);
      await reveal(page, page.getByRole('button', { name: label, exact: false }), 'other', page.getByRole('button', { name: label, exact: false, includeHidden: true }));
      await textContains(page, label);
      await reveal(page, page.getByRole('slider'), 'dimming', page.getByRole('slider', { includeHidden: true }));
      expect(await readDim(page)).toBe(dim);
      await renderMenu(menu, f, firstUrl, dim, {
        text: '#fff1da', button: '#20140c', primary: '#211a16', accent: '#eab082',
        font: font === 'alexandria' ? 'SF Alexandria' : font === 'system' ? 'system-ui' : 'sf-font-latin',
      });
      await invariants(f, token);
      stages.push(stage);
    }

    stage = 'scene-bright-brand-before';
    await openFoldedGroup(page, 'profile');
    await fill(page, L.primary, '#00FF00', { blur: true });
    await fill(page, L.accent, '#FF00FF', { blur: true });
    await saveProfile(page);
    await setDim(page, 15);
    await saveContent(page);
    const referenceColours = { text: '#fff1da', button: '#20140c', primary: '#151515', accent: '#ff00ff', font: 'system-ui' };
    const legacyColours = { ...referenceColours, primary: '#00ff00' };
    await renderMenu(menu, f, firstUrl, 15, legacyColours);
    await screenshot(menu, resolve(out, 'scene-same-source-legacy-desktop-test-data.png'));
    await menu.setViewportSize({ width: 390, height: 844 });
    await screenshot(menu, resolve(out, 'scene-same-source-legacy-mobile-test-data.png'));
    await menu.setViewportSize({ width: 1440, height: 1000 });
    await quality.captureScene(context.browser()!, menu.url(), pair, 'legacy', guardBrowser);
    stages.push(stage);

    stage = 'scene-cancel-apply-save-reload';
    const sceneBefore = await rpc(f, token, 'get_restaurant_storefront_content_v3');
    const sceneWrites = draftWrites;
    await sceneDialog(page, false);
    expect(draftWrites, 'Cancelling scene preview does not persist').toBe(sceneWrites);
    const contentSave = page.getByRole('button', { name: L.save, exact: true });
    // Read this disabled control as status; the action reveal path correctly
    // requires enabled controls and must not be weakened for this assertion.
    await reveal(page, contentSave, 'content-status', page.getByRole('button', { name: L.save, exact: true, includeHidden: true }));
    expect(await contentSave.isEnabled(), 'Scene Cancel leaves the clean draft unchanged').toBe(false);
    const cancelled = await rpc(f, token, 'get_restaurant_storefront_content_v3');
    expect(cancelled.document, 'Scene Cancel retains the complete prior draft').toEqual(sceneBefore.document);
    await sceneDialog(page, true, false, resolve(out, 'scene-preview-test-data.png'));
    expect(draftWrites, 'Scene Apply only changes the draft').toBe(sceneWrites);
    const applied = await rpc(f, token, 'get_restaurant_storefront_content_v3');
    expect(applied.document, 'Scene Apply waits for content Save').toEqual(sceneBefore.document);
    await saveContent(page);
    await openEditor(page, true);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.scene_preset).toBe('reference_dark');
    await verifyReadCompatibility(f, token);
    const unchangedBrand = (await rpc(f, token, 'get_restaurant_storefront_profile')).profile;
    expect(unchangedBrand.primary_color).toBe('#00ff00');
    expect(unchangedBrand.accent_color).toBe('#ff00ff');
    stages.push(stage);

    for (const dim of [0, 15, 80]) {
      stage = `scene-reference-${dim}`;
      await setDim(page, dim);
      await saveContent(page);
      await openEditor(page, true);
      const appearance = (await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance;
      expect(appearance.scene_preset).toBe('reference_dark');
      expect(appearance.menu_background_dim).toBe(dim);
      expect(appearance.menu_background_media_id).toBe(first);
      await renderMenu(menu, f, firstUrl, dim, referenceColours, 'reference_dark');
      await verifyReferenceScene(menu, dim);
      if (dim === 15) {
        await verifyMenuGeometry(menu);
        await screenshot(menu, resolve(out, 'scene-same-source-reference-desktop-test-data.png'));
        await menu.setViewportSize({ width: 390, height: 844 });
        await verifyReferenceScene(menu, dim);
        await verifyMenuGeometry(menu);
        await screenshot(menu, resolve(out, 'scene-same-source-reference-mobile-test-data.png'));
        await quality.captureScene(context.browser()!, menu.url(), pair, 'reference_dark', guardBrowser);
        await menu.setViewportSize({ width: 1440, height: 1000 });
      }
      await invariants(f, token);
      stages.push(stage);
    }
    // A fresh tab has its own unvisited Intro session. Inspect real served
    // Welcome imagery, without changing local/session storage or the route.
    stage = 'independent-welcome';
    const welcome = await context.newPage();
    await welcome.goto(`${STOREFRONT}/s/${f.ownerA.slug}`, { waitUntil: 'domcontentloaded' });
    await expect(welcome.locator('[data-sf-screen="intro"] [data-sf-hero-mode="editorial"]')).toHaveCount(1);
    await expect(welcome.locator('[data-sf-screen="intro"] [data-sf-module="hero"] img')).toHaveAttribute('src', logicalMediaUrl(f.heroUrl));
    await welcome.close();
    await sceneDialog(page, true, true);
    await saveContent(page);
    await openEditor(page, true);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.scene_preset).toBeNull();
    await renderMenu(menu, f, firstUrl, 80, legacyColours);
    stages.push(stage);

    stage = 'replace-background';
    await upload(page, 'base_444_1200x900.jpg', nextUpload());
    await saveContent(page);
    const second = (await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.menu_background_media_id as string;
    expect(second).not.toBe(first);
    const secondUrl = await backgroundUrl(f, token, second);
    await verifyReadCompatibility(f, token);
    await openEditor(page, true);
    await invariants(f, token);
    await renderMenu(menu, f, secondUrl, 80);
    stages.push(stage);

    stage = 'duplicate-source-rejected';
    await upload(page, 'background-2816.jpg', nextUpload(), 409);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.menu_background_media_id).toBe(second);
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
    await reveal(page, page.getByRole('slider'), 'dimming', page.getByRole('slider', { includeHidden: true }));
    await page.getByRole('slider').scrollIntoViewIfNeeded();
    await screenshot(page, resolve(out, 'dashboard-test-data.png'));
    stages.push(stage);

    stage = 'clear-selection-fallback-media-retained';
    await reveal(page, page.getByRole('button', { name: new RegExp(second.slice(0, 8)) }), 'other', page.getByRole('button', { name: new RegExp(second.slice(0, 8)), includeHidden: true }));
    await selectRevealedDropdown(page, new RegExp(second.slice(0, 8)), L.inherit);
    await saveContent(page);
    await openEditor(page, true);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.menu_background_media_id).toBeNull();
    await verifyReadCompatibility(f, token);
    await invariants(f, token);
    await backgroundUrl(f, token, first);
    await backgroundUrl(f, token, second);
    await renderMenu(menu, f, f.heroUrl, null);
    stages.push(stage);

    stage = 'clear-shared-hero-media-retained';
    await reveal(page, page.getByRole('button', { name: new RegExp(L.inherit) }), 'other', page.getByRole('button', { name: new RegExp(L.inherit), includeHidden: true }));
    await selectRevealedDropdown(page, new RegExp(L.inherit), f.heroMediaId.slice(0, 8));
    await saveContent(page);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.menu_background_media_id).toBe(f.heroMediaId);
    await invariants(f, token);
    await reveal(page, page.getByRole('button', { name: new RegExp(f.heroMediaId.slice(0, 8)) }), 'other', page.getByRole('button', { name: new RegExp(f.heroMediaId.slice(0, 8)), includeHidden: true }));
    await selectRevealedDropdown(page, new RegExp(f.heroMediaId.slice(0, 8)), L.inherit);
    await saveContent(page);
    await openEditor(page, true);
    expect((await rpc(f, token, 'get_restaurant_storefront_content_v3')).document.appearance.menu_background_media_id).toBeNull();
    await invariants(f, token);
    await backgroundUrl(f, token, f.heroMediaId);
    await renderMenu(menu, f, f.heroUrl, null);
    stages.push(stage);
    await quality.privateOriginal(f, token, first);
    quality.complete();
    await network.check();
    writeFileSync(resolve(out, 'dashboard-result.json'), JSON.stringify({ status: 'PASS', data: 'synthetic ephemeral services', stages, login: loginEvidence, fonts: network.fonts(), mediaTransport: network.media(), controlReveals: revealTraces.get(page) ?? [], controlClicks: clickTraces.get(page) ?? [], menuRenders: menuRenderTraces.get(context) ?? [], siteThemeRenders: siteThemeRenderTraces.get(context) ?? [], uploads: uploadDiagnostics.map(d => d.snapshot()) }, null, 2));
  } catch (error) {
    const statuses = stages.includes('login') ? await editorStatus(page).catch(() => ['unreadable']) : [];
    const failureCapture = stages.includes('login')
      ? await failureScreenshot(page, resolve(out, 'dashboard-failure-test-data.png')) : 'withheld';
    writeFileSync(resolve(out, 'dashboard-result.json'), JSON.stringify({ status: 'FAIL', data: 'synthetic ephemeral services', failedStage: stage, completedStages: stages,
      login: loginEvidence, fonts: network.fonts(), mediaTransport: network.media(), controlRevealPurpose: error instanceof ControlRevealError ? error.purpose : null,
      controlReveal: error instanceof ControlRevealError ? error.samples : null,
      controlReveals: revealTraces.get(page) ?? [], controlClicks: clickTraces.get(page) ?? [], menuRenders: menuRenderTraces.get(context) ?? [], siteThemeRenders: siteThemeRenderTraces.get(context) ?? [], uploads: uploadDiagnostics.map(d => d.snapshot()), editorStatuses: statuses, failureScreenshot: failureCapture }, null, 2));
    throw error;
  }
});

// Independent evidence in the same real-service stack. A failed legacy
// background-companion assertion remains a failure, but cannot skip this
// banner lifecycle. It signs in through the real UI again; no session injection.
test('independent banner → actual Edge → save/reload → replace/clear preserves other media', async ({ page, context }) => {
  // The added independent device heights/media include fourteen live readbacks.
  // Use the same finite case budget as the other full Dashboard journey.
  test.setTimeout(20 * 60_000);
  const f = fixture(), network = await guardBrowser(context);
  const uploads: UploadDiagnostics[] = [];
  let signedIn = false, passed = false;
  try {
    await page.goto(DASHBOARD, { waitUntil: 'domcontentloaded' }); await semantics(page); await network.fontsReady();
    await fillField(page, L.email, f.ownerA.email); await enterLoginPassword(page, f.ownerA.password);
    expect(await page.getByRole('textbox', { name: L.email }).inputValue()).toBe(f.ownerA.email);
    expect(await page.locator('input[type="password"]').inputValue()).toBe(f.ownerA.password);
    const observed = observeResponse(page.waitForResponse(r => isPasswordGrantRequest(r.url(), r.request().method(), API)));
    const auth = await responseAfterAction(observed, () => tapButton(page, L.login, { which: 'last' }));
    expect(auth.status()).toBe(200); const session = await auth.json();
    expect(session.user.email).toBe(f.ownerA.email); expect(typeof session.access_token).toBe('string');
    signedIn = true;
    await openEditor(page);
    const menu = await context.newPage();
    await verifyBannerJourney(page, menu, f, session.access_token, () => {
      const value = new UploadDiagnostics(); uploads.push(value); return value;
    });
    await network.check(); passed = true;
  } finally {
    if (signedIn && !passed) await failureScreenshot(page, resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'banner-dashboard-failure-test-data.png'));
    writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'banner-browser-result.json'), JSON.stringify({
      status: passed ? 'PASS' : 'FAIL', realUiSignIn: signedIn, uploads: uploads.map(item => item.snapshot()),
      fonts: network.fonts(), mediaTransport: network.media(),
    }, null, 2));
  }
});
