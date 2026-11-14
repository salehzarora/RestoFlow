import { expect, type Locator, type Page, type Frame, type Request, type Response, type BrowserContext } from '@playwright/test';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { bannerGeometry, bannerViewportScreenshot } from './banner-responsive';
import { responsiveBannerFixture, legacyBannerDocument, legacyBannerMenu, responsiveBannerReady, dashboardImageBytesMatch, classifyMediaReadError, mediaReadErrorDetail, bannerEvidencePhase } from './responsive-banner-settings.mjs';
import { LOGICAL_ORIGIN, localMediaTarget } from './live-transport.mjs';

type Obj = Record<string, any>;
type Dependencies = {
  read: () => Promise<Obj>; readLegacy: () => Promise<Obj>;
  publicRead: (version: 10 | 11) => Promise<Obj>;
  writeDocument: (document: Obj) => Promise<void>;
  reload: () => Promise<Obj>; save: () => Promise<void>;
  upload: (index: number) => Promise<Obj>;
  reveal: (target: Locator) => Promise<void>; tap: (target: Locator) => Promise<void>;
  freshMenu: (width: number) => Promise<{ page: Page; requestedMedia: string[]; check: () => Promise<void>; close: () => Promise<void> }>;
  invariant: () => Promise<void>; captureHeightVideo: (height: number, recordEvidence: (value: Obj) => void) => Promise<Obj>; url: string; artifactDir: string;
  recordPhase?: (phase: string) => void;
  recordRestoredDocument?: (document: Obj) => void;
};
const copy = {
  layout: 'بانر متجاوب مستقل', auto: 'تلقائي حسب نسبة الصورة', custom: 'ارتفاع مخصص',
  mobileHeight: 'ارتفاع صورة الهاتف', desktopHeight: 'ارتفاع صورة الكمبيوتر',
  reset: 'إعادة هذا الارتفاع إلى التلقائي', clear: 'مسح اختيار الكمبيوتر فقط',
};

// Per owned test Page only. A request remains pending until its native browser
// body observation finishes (success OR failure); failures still reach the
// unchanged byte guard. This is not a cache, retry or alternative byte source.
const pageImageEvidence = new WeakMap<Page, Set<Promise<void>>>();
async function withinNavigationDeadline<T>(operation: Promise<T>, deadline: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([operation, new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error('Current document image evidence exceeded the original navigation deadline.')),
        Math.max(1, deadline - Date.now()));
    })]);
  } finally { if (timer !== undefined) clearTimeout(timer); }
}

/** Finish existing resource reads before leaving their document. The quiet wait
 * consumes the caller's original navigation budget; no retry or new request. */
export async function navigateAfterMediaSettles(page: Page, url: string, options: Parameters<Page['goto']>[1]) {
  const budget = options?.timeout ?? 30_000;
  if (!Number.isFinite(budget) || budget <= 0) throw new Error('A finite navigation budget is required.');
  const deadline = Date.now() + budget;
  await page.waitForLoadState('networkidle', { timeout: budget });
  const pending = pageImageEvidence.get(page);
  if (pending) {
    // A viewport change can start picture selection after an earlier networkidle
    // loadstate. Observe that rendering opportunity and decode only the current,
    // already-visible banner; do not preload other images or request another URL.
    await withinNavigationDeadline(page.evaluate(async () => {
      await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
      const image = document.querySelector('[data-sf-menu-banner] img');
      if (image instanceof HTMLImageElement && image.currentSrc) await image.decode();
    }), deadline);
    while (pending.size > 0) await withinNavigationDeadline(Promise.all([...pending]), deadline);
  }
  return page.goto(url, { ...options, timeout: Math.max(1, deadline - Date.now()) });
}

/** Passive diagnostics beside the unchanged isolation guard. Playwright caches
 * each native response-body promise; this neither re-fetches nor substitutes it. */
export function observeLogicalMedia(context: BrowserContext, surfaces: { dashboard: string; storefront: string }) {
  let responses = 0, requestFinished = 0, requestFailed = 0, bodyReads = 0, bodyErrors = 0, filenameMatches = 0, otherPayloads = 0;
  const started = Date.now(), now = () => Date.now() - started;
  let phase = 'baseline', requestSequence = 0, pageSequence = 0, frameSequence = 0;
  const failures: Obj[] = [];
  // Bounded positive evidence for exactly the six viewport transitions whose
  // outgoing-document reads failed in the diagnostic run. All requests still
  // count in the unchanged guard; this sample never selects accepted responses.
  const transitions: Obj[] = [];
  let transition: Obj | null = null;
  const facts = new WeakMap<Request, Obj>(), pages = new WeakMap<Page, Obj>(), frames = new WeakMap<Frame, Obj>();
  const completeEvidence = new WeakMap<Request, () => void>();
  const removers: (() => void)[] = [];
  const frameState = (frame: Frame) => {
    let value = frames.get(frame);
    if (!value) { value = { frameId: `f${++frameSequence}`, observerDocumentEpoch: 0, navigationSequence: 0,
      navigationStartedMs: null, navigationCommittedMs: null, detachedMs: null }; frames.set(frame, value); }
    return value;
  };
  const watchPage = (page: Page) => {
    if (pages.has(page)) return;
    const state: Obj = { pageId: `p${++pageSequence}`, closedMs: null }; pages.set(page, state);
    pageImageEvidence.set(page, new Set());
    const navigated = (frame: Frame) => { const value = frameState(frame); value.observerDocumentEpoch++; value.navigationCommittedMs = now(); };
    const detached = (frame: Frame) => { frameState(frame).detachedMs = now(); };
    const closed = () => { state.closedMs = now(); };
    page.on('framenavigated', navigated); page.on('framedetached', detached); page.on('close', closed);
    removers.push(() => { page.off('framenavigated', navigated); page.off('framedetached', detached); page.off('close', closed);
      pageImageEvidence.delete(page); });
  };
  const location = (request: Request) => {
    try {
      const frame = request.frame(), page = frame.page(); watchPage(page);
      const origin = new URL(page.url()).origin, f = frameState(frame), p = pages.get(page)!;
      return { pageSurface: origin === surfaces.dashboard ? 'dashboard' : origin === surfaces.storefront ? 'storefront' : 'other',
        frameKind: frame.parentFrame() === null ? 'main' : 'child', pageId: p.pageId, frameId: f.frameId,
        observerDocumentEpoch: f.observerDocumentEpoch, navigationSequence: f.navigationSequence,
        navigationStartedMs: f.navigationStartedMs, navigationCommittedMs: f.navigationCommittedMs,
        pageClosedMs: p.closedMs, frameDetachedMs: f.detachedMs };
    } catch { return { pageSurface: 'detached', frameKind: 'detached' }; }
  };
  const admitted = (request: Request) => {
    try { return new URL(request.url()).origin === LOGICAL_ORIGIN && request.resourceType() === 'image'
      && typeof localMediaTarget(request.url(), request.method()) === 'string'; }
    catch { return false; }
  };
  const remember = (value: Obj) => { if (failures.length < 8) failures.push(value); };
  const requested = (request: Request) => {
    if (request.isNavigationRequest()) {
      try { const value = frameState(request.frame()); value.navigationSequence++; value.navigationStartedMs = now();
        const where = location(request);
        if (transition && transition.firstNavigation === null && where.pageSurface === 'storefront' && where.frameKind === 'main')
          transition.firstNavigation = { observedMs: now(), ...where };
      } catch { /* Detached frame: diagnostic only. */ }
    }
    if (admitted(request)) {
      facts.set(request, { requestId: `r${++requestSequence}`, requestMs: now(), phaseAtRequest: phase,
        atRequest: location(request), finishedMs: null, failedMs: null });
      const fact = facts.get(request)!;
      if (transition && transition.firstNavigation === null && transition.requests.length < 4
        && fact.atRequest.pageSurface === 'storefront' && fact.atRequest.frameKind === 'main') transition.requests.push(fact);
      try {
        const pending = pageImageEvidence.get(request.frame().page())!;
        let resolve!: () => void;
        const observation = new Promise<void>(done => { resolve = done; }); pending.add(observation);
        completeEvidence.set(request, () => { pending.delete(observation); resolve(); });
      } catch { /* A detached frame still fails the unchanged guard; no success is fabricated. */ }
    }
  };
  const finished = (request: Request) => { if (admitted(request)) { requestFinished++;
    const value = facts.get(request); if (value) { value.finishedMs = now(); value.atFinish = location(request); } } };
  const failed = (request: Request) => { if (admitted(request)) { requestFailed++;
    const value = facts.get(request) ?? { requestId: 'unobserved' };
    value.failedMs = now(); value.atFailure = location(request);
    remember({ stage: 'native-request', classification: classifyMediaReadError(request.failure()?.errorText), fact: value });
    completeEvidence.get(request)?.(); } };
  const response = (reply: Response) => {
    if (!admitted(reply.request())) return;
    responses++;
    const hash = new URL(reply.url()).pathname.split('/').at(-1)!.slice(0, -5), status = reply.status();
    const fact = facts.get(reply.request()) ?? { requestId: 'unobserved' };
    Object.assign(fact, { responseMs: now(), phaseAtResponse: phase, atResponse: location(reply.request()), bodyReadStartedMs: now() });
    void reply.body().then(bytes => {
      const matches = dashboardImageBytesMatch(hash, status, bytes);
      Object.assign(fact, { bodyReadEndedMs: now(), bodyReadStatus: 'read', bodyMatched: matches,
        bodyBytes: bytes.byteLength, atBodyRead: location(reply.request()) });
      bodyReads++;
      if (matches) filenameMatches++;
      else { otherPayloads++; fact.bodyReadEndedMs = now();
        remember({ stage: 'response-body', classification: 'digest-or-status', httpStatus: status, fact }); }
    }).catch(error => { bodyErrors++; Object.assign(fact, { bodyReadEndedMs: now(), bodyReadStatus: 'unavailable', phaseAtBodyFailure: phase, atBodyFailure: location(reply.request()) });
      remember({ stage: 'response-body', classification: classifyMediaReadError(error), detail: mediaReadErrorDetail(error), httpStatus: status, fact });
    }).finally(() => completeEvidence.get(reply.request())?.());
  };
  context.pages().forEach(watchPage); context.on('page', watchPage); context.on('request', requested);
  context.on('requestfinished', finished); context.on('requestfailed', failed); context.on('response', response);
  return {
    phase: (value: string) => {
      phase = bannerEvidencePhase(value);
      if (/^responsive-desktop-(?:replaced|selected|cleared)-(?:390|1280)$/.test(phase)
        && !transitions.some(sample => sample.phase === phase) && transitions.length < 6) {
        transition = { phase, markedMs: now(), firstNavigation: null, requests: [] }; transitions.push(transition);
      } else if (transition?.phase !== phase) transition = null;
    },
    snapshot: () => ({ responses, requestFinished, requestFailed, bodyReads, bodyErrors, filenameMatches, otherPayloads,
      pendingBodies: responses - bodyReads - bodyErrors, failures: structuredClone(failures),
      responsiveTransitionSamples: structuredClone(transitions),
      scope: 'Passive native public-image diagnostics only; local observer epochs are not CDP loader IDs; original guard remains authoritative' }),
    stop: () => { context.off('page', watchPage); context.off('request', requested); context.off('requestfinished', finished);
      context.off('requestfailed', failed); context.off('response', response); removers.forEach(remove => remove()); },
  };
}

export async function adjustBannerHeightWithKeyboard(page: Page, reveal: (target: Locator) => Promise<void>, from: number, to: number): Promise<void> {
    const value = page.getByText(`${from} CSS px`, { exact: true });
    await expect(value, 'The visible height value identifies this device control').toHaveCount(1);
    // The native range and its aria-valuetext appear only in keyboard mode /
    // after the first change. Its real semantic owner follows the value label.
    await page.keyboard.press('Shift');
    const initial = value.locator('xpath=ancestor::flt-semantics[1]/following-sibling::flt-semantics[1]').getByRole('slider');
    await expect(initial, 'Exactly the actual intended CSS-height range is selected').toHaveCount(1);
    const id = await initial.evaluate(node => node.closest('[id^="flt-semantic-node-"]')?.id);
    expect(id, 'The genuine Flutter range has a stable DOM identity').toBeTruthy();
    const slider = page.locator(`[id="${id}"]`).getByRole('slider');
    await reveal(slider); await slider.focus(); await expect(slider).toBeFocused();
    const step = Math.sign(to - from);
    expect(Math.abs(to - from)).toBeLessThanOrEqual(40);
    for (let value = from; value !== to;) {
      await page.keyboard.press(step > 0 ? 'ArrowRight' : 'ArrowLeft'); value += step;
      await expect(slider).toHaveAttribute('aria-valuetext', `${value} CSS px`);
      await expect(slider, 'The same input retains focus throughout the drag-equivalent keyboard adjustment').toBeFocused();
    }
}

/** A SwitchListTile box includes title/subtitle. A clipped tile edge may fail
 * the pointer-only whole-rectangle guard while its real keyboard control is
 * visibly reachable. Keep that guard intact; use native focus and Space only
 * on the enabled switch's unobstructed center in the owned Flutter surface. */
export async function enableResponsiveLayoutWithKeyboard(page: Page, layout: Locator, reveal: (target: Locator) => Promise<void>): Promise<Obj> {
  const sample = () => layout.evaluate(el => {
    const r = el.getBoundingClientRect(), x = r.x + r.width / 2, y = r.y + r.height / 2;
    const hit = document.elementFromPoint(x, y), view = el.closest('flutter-view');
    const tags = ['FLT-SEMANTICS', 'FLT-SEMANTICS-CONTAINER', 'FLT-GLASS-PANE', 'FLT-SCENE-HOST', 'FLUTTER-VIEW'];
    return { x: r.x, y: r.y, width: r.width, height: r.height, viewportWidth: innerWidth, viewportHeight: innerHeight,
      centerVisible: x >= 0 && x <= innerWidth && y >= 96 && y <= innerHeight - 64,
      centerHit: hit === el || (hit !== null && el.contains(hit)),
      flutterSurfaceHit: hit !== null && view !== null && hit.closest('flutter-view') === view && tags.includes(hit.tagName),
      role: el.getAttribute('role'), checked: el.getAttribute('aria-checked'),
      disabled: el.getAttribute('aria-disabled') === 'true', focusable: el instanceof HTMLElement && el.tabIndex >= 0 };
  });
  const ready = (g: Obj) => g.width > 0 && g.height > 0 && g.centerVisible && (g.centerHit || g.flutterSurfaceHit) && !g.disabled && g.focusable && g.role === 'switch';
  await expect(layout).toHaveCount(1); await expect(layout).not.toBeChecked();
  const evidence: Obj = { method: 'NATIVE_FOCUS_AND_SPACE', before: await sample() };
  if (!ready(evidence.before)) {
    try { await reveal(layout); evidence.pointerReveal = 'READY'; }
    catch (error) {
      // Only bounded counts/rectangles escape; no rendered text or sessions.
      const samples = (error as { samples?: Obj[] }).samples;
      evidence.pointerReveal = 'WHOLE_TILE_NOT_POINTER_READY';
      evidence.revealTail = Array.isArray(samples) ? samples.slice(-3).map(s => ({ iteration: s.iteration,
        normalMatches: s.normalMatches, hiddenMatches: s.hiddenMatches, direction: s.direction,
        geometry: s.geometry == null ? null : Object.fromEntries(['x','y','width','height','centerHit','flutterSurfaceHit','disabled'].map(k => [k, s.geometry[k]])) })) : [];
    }
  }
  evidence.keyboardGeometry = await sample();
  expect(ready(evidence.keyboardGeometry), 'The genuine enabled switch has a visible center on the owned Flutter input surface').toBe(true);
  await expect(layout).toBeVisible(); await expect(layout).toBeEnabled();
  await layout.focus(); await expect(layout, 'Native focus reaches the actual switch').toBeFocused();
  await page.keyboard.press('Space'); await expect(layout, 'Ordinary Space enables the real responsive setting').toBeChecked();
  evidence.focusedBeforeSpace = true; evidence.checkedAfterSpace = true;
  return evidence;
}

/** Real temporary services and shipped controls. DOM reads below locate genuine
 * Flutter controls; no callback/state/value assignment or response mocking. */
export async function verifyResponsiveBannerSettings(page: Page, menu: Page, d: Dependencies): Promise<void> {
  const baseline = await d.read(), completed = responsiveBannerFixture(baseline.document);
  const original = completed.document;
  const phoneId = original.appearance.menu_banner_media_id;
  const receipt: Obj = { status: 'FAIL', stage: 'baseline', data: 'Actual temporary CI services; synthetic owner and image bytes; no production writes or response mocking', rows: [],
    restoration: { materializedNullKeys: completed.materializedNullKeys,
      meaning: 'Semantic legacy restoration with explicit null; not missing-key byte identity.' },
    video: { status: 'NOT_RUN' }, uiWriteCount: 0 };
  let writes = 0, videoFailure: { error: unknown } | null = null;
  const count = (request: Request) => {
    const u = new URL(request.url());
    if (u.origin === 'http://127.0.0.1:54321' && u.pathname === '/rest/v1/rpc/set_restaurant_storefront_content_v1'
      && request.method() === 'POST') writes++;
  };
  page.on('request', count);
  const frames = page.locator('iframe[title="Storefront banner preview"]');
  const preview = (index: number) => page.frameLocator('iframe[title="Storefront banner preview"]').nth(index).locator('[data-sf-menu-top]');
  const button = (name: string | RegExp) => page.getByRole('button', { name, exact: typeof name === 'string' });
  const click = async (target: Locator) => { await d.reveal(target); await d.tap(target); };
  const expectPhone = (document: Obj) => {
    expect(document.appearance.menu_banner_media_id, 'Desktop operations preserve the selected phone image').toBe(phoneId);
    expect(document.appearance.menu_banner_focal_x).toBe(original.appearance.menu_banner_focal_x);
    expect(document.appearance.menu_banner_focal_y).toBe(original.appearance.menu_banner_focal_y);
    expect(legacyBannerDocument(document), 'All settings outside the six new responsive fields remain exact').toEqual(legacyBannerDocument(original));
  };
  const recordControl = async (stage: string, target: Locator) => {
    receipt.stage = stage;
    receipt.control = { matches: await target.count(), samples: await target.evaluateAll(nodes => nodes.slice(0, 2).map(el => {
      const r = el.getBoundingClientRect(), hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
      return { role: el.getAttribute('role'), tabIndex: (el as HTMLElement).tabIndex, checked: el.getAttribute('aria-checked'),
        disabled: el.getAttribute('aria-disabled') === 'true', x: r.x, y: r.y, width: r.width, height: r.height,
        centerHit: hit === el || (hit !== null && el.contains(hit)) };
    })) };
  };
  const editDevice = async (phone: boolean) => {
    const stage = receipt.stage;
    const choice = page.getByRole('checkbox', { name: phone ? 'الهاتف' : 'الكمبيوتر', exact: true });
    await recordControl(`${stage}-${phone ? 'phone' : 'desktop'}-choice-reveal`, choice);
    // Flutter may omit offscreen semantics after the preview capture. The
    // existing bounded physical-wheel scan must reveal the real control first.
    try { await d.reveal(choice); }
    catch (error) {
      const samples = (error as { samples?: Obj[] }).samples;
      receipt.control.revealTail = Array.isArray(samples) ? samples.slice(-3).map(s => ({ iteration: s.iteration,
        normalMatches: s.normalMatches, hiddenMatches: s.hiddenMatches, direction: s.direction, reversed: s.reversed,
        geometry: s.geometry == null ? null : Object.fromEntries(['x','y','width','height','centerHit','flutterSurfaceHit','disabled'].map(k => [k, s.geometry[k]])) })) : [];
      throw error;
    }
    await recordControl(`${stage}-${phone ? 'phone' : 'desktop'}-choice-ready`, choice);
    await expect(choice).toHaveCount(1);
    if (!await choice.isChecked()) {
      await recordControl(`${stage}-${phone ? 'phone' : 'desktop'}-choice-tap`, choice); await d.tap(choice);
    }
    await expect(choice).toBeChecked();
    receipt.stage = stage;
  };
  const customMode = async (phone: boolean) => {
    const stage = receipt.stage;
    await editDevice(phone);
    // Flutter exposes the popup choice as an accessible menuitem, with an
    // aria-label and no Text node. Keep the real pointer guards and click path.
    const field = button(new RegExp(phone ? copy.mobileHeight : copy.desktopHeight));
    await recordControl(`${stage}-dropdown-reveal`, field); await expect(field).toHaveCount(1); await d.reveal(field);
    await recordControl(`${stage}-dropdown-tap`, field); await d.tap(field);
    const option = page.getByRole('menuitem', { name: copy.custom, exact: true });
    await recordControl(`${stage}-option-reveal`, option); await expect(option).toHaveCount(1); await d.reveal(option);
    await recordControl(`${stage}-option-tap`, option); await d.tap(option);
    receipt.stage = `${stage}-selected-value`;
    await expect(field).toContainText(copy.custom);
    await expect(page.getByText(`${phone ? 520 : 400} CSS px`, { exact: true })).toHaveCount(1);
    receipt.stage = stage;
  };
  const changeHeight = (from: number, to: number) => adjustBannerHeightWithKeyboard(page, d.reveal, from, to);
  const noAutosave = async (before: Obj, expectedWrites: number) => {
    expect(writes, 'Draft controls and media publication never save content automatically').toBe(expectedWrites);
    expect(await d.read(), 'Fresh real owner read retains pre-draft document and CAS version').toEqual(before);
  };
  const saveReload = async (expected: Obj) => {
    const before = writes; await d.save(); expect(writes).toBe(before + 1);
    const wire = await d.reload(), actual = await d.read();
    expect(wire, 'Actual Dashboard reload response equals an independent authenticated v6 read').toEqual(actual);
    expect(actual.restaurant_id).toBe(baseline.restaurant_id);
    expect(actual.storefront_branch_id).toBe(baseline.storefront_branch_id);
    expect(actual.version).toBeGreaterThan(baseline.version);
    for (const [key, value] of Object.entries(expected)) expect(actual.document.appearance[key], key).toEqual(value);
    expectPhone(actual.document); await d.invariant();
    // Wait for the one asynchronous public-state snapshot before retaining
    // image handles. Initial srcdoc replacement is not a slider regression.
    const state = (await d.publicRead(11)).service.state;
    for (const index of [0, 1]) await expect.poll(() => bannerGeometry(preview(index)).then(g => g.state).catch(() => null)).toBe(state);
    return actual;
  };
  const compare = async (label: string) => {
    const latest = await d.publicRead(11), appearance = latest.content_v1.appearance;
    const current = (await d.read()).document;
    expect(appearance.menu_banner_layout).toBe(current.appearance.menu_banner_layout);
    expect(appearance.menu_banner_mobile_height_px).toBe(current.appearance.menu_banner_mobile_height_px);
    expect(appearance.menu_banner_desktop_height_px).toBe(current.appearance.menu_banner_desktop_height_px);
    await expect(frames).toHaveCount(2);
    for (const [index, width] of [[0, 390], [1, 1280]]) {
      d.recordPhase?.(`responsive-${label}-${width}`);
      await expect(frames.nth(index)).toHaveAttribute('sandbox', 'allow-same-origin');
      const frame = page.frameLocator('iframe[title="Storefront banner preview"]').nth(index);
      const policy = await frame.locator('meta[http-equiv="Content-Security-Policy"]').getAttribute('content');
      expect(policy).toContain("script-src 'none'"); expect(policy).toContain("connect-src 'none'"); expect(policy).toContain("style-src 'self'");
      const base = index ? appearance.menu_banner_desktop_url ?? appearance.menu_banner_url : appearance.menu_banner_url;
      const allowed = new Set([base, ...(index ? latest.menu_banner_desktop_images_v1?.variants?.map((v: Obj) => v.url) ?? [] : [])]);
      const focus = index ? `${appearance.menu_banner_desktop_focal_x ?? 50}% ${appearance.menu_banner_desktop_focal_y ?? 50}%`
        : `${appearance.menu_banner_focal_x ?? 50}% ${appearance.menu_banner_focal_y ?? 50}%`;
      const custom = index ? current.appearance.menu_banner_desktop_height_px : current.appearance.menu_banner_mobile_height_px;
      const iw = index && appearance.menu_banner_desktop_url ? appearance.menu_banner_desktop_width : appearance.menu_banner_width;
      const ih = index && appearance.menu_banner_desktop_url ? appearance.menu_banner_desktop_height : appearance.menu_banner_height;
      const expectedHeight = custom ?? Math.max(index ? 240 : 320, Math.min(index ? 480 : 640, width * ih / iw));
      const safeHeight = (value: unknown) => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 10000 ? value : null;
      const safeFocus = (value: unknown) => {
        const points = typeof value === 'string' ? /^(\d+(?:\.\d+)?)% (\d+(?:\.\d+)?)%$/.exec(value) : null;
        return points && points.slice(1).every(p => Number(p) >= 0 && Number(p) <= 100) ? points.slice(1).map(Number) : null;
      };
      const measure = async (root: Locator, phase: 'warm_navigation' | 'fresh_context' | 'preview_resource') => {
        let required: Obj = { rootCount: await root.count(), selectorRead: false, currentImageCount: null,
          layoutResponsive: false, hydrated: false, themeRoot: false, state: false, search: false, categories: false };
        try {
          required = { ...required, ...await root.evaluate(el => {
            const doc = el.ownerDocument, host = doc.querySelector('[data-sf-menu-banner]'), theme = doc.querySelector<HTMLElement>('[data-sf-root],[data-banner-preview-root]');
            return { selectorRead: true, currentImageCount: doc.querySelectorAll('[data-sf-menu-banner] img').length,
              layoutResponsive: host?.getAttribute('data-sf-banner-layout') === 'responsive',
              hydrated: Boolean(theme?.style.getPropertyValue('--bg') && theme.style.getPropertyValue('--font')), themeRoot: !!theme,
              state: !!doc.querySelector('[data-sf-order-status] [data-state]'),
              search: !!doc.querySelector('[role="search"]'), categories: !!doc.querySelector('[data-sf-module="categories"]') };
          }) };
          const geometry = await bannerGeometry(root);
          const actual = { height: geometry.height, focus: geometry.position, resourceMatch: allowed.has(geometry.publicPath), layoutResponsive: required.layoutResponsive, hydrated: required.hydrated, serviceState: geometry.state };
          receipt.readinessObservation = { phase, width, expectedHeight: safeHeight(expectedHeight), actualHeight: safeHeight(geometry.height),
            expectedFocus: safeFocus(focus), actualFocus: safeFocus(geometry.position), resourceMatch: actual.resourceMatch,
            expectedServiceState: ['open','closed'].includes(latest.service.state) ? latest.service.state : 'unclassified',
            actualServiceState: ['open','closed'].includes(geometry.state) ? geometry.state : 'unclassified',
            ...required, errorType: null };
          return { geometry, actual };
        } catch (error) {
          receipt.readinessObservation = { phase, width, expectedHeight: safeHeight(expectedHeight), actualHeight: null,
            expectedFocus: safeFocus(focus), actualFocus: null, resourceMatch: false, ...required,
            errorType: error instanceof Error && ['Error', 'TypeError', 'TimeoutError'].includes(error.name) ? error.name : 'unclassified' };
          return null;
        }
      };
      await menu.waitForLoadState('networkidle', { timeout: 30000 }); await menu.setViewportSize({ width, height: index ? 900 : 844 });
      const warmStarted = Date.now(); let hydrated = false, reloadAt = 0, navigations = 0;
      await expect.poll(async () => {
        // Reuse renderMenu's existing bounded ISR/hydration pattern: do not
        // discard a pending hydration frame by navigating at every sample.
        if (navigations === 0 || (hydrated && Date.now() >= reloadAt)) {
          const remaining = Math.max(1, 100000 - (Date.now() - warmStarted));
          await navigateAfterMediaSettles(menu, d.url, { waitUntil: 'domcontentloaded', timeout: Math.min(30000, remaining) });
          navigations++; hydrated = false; reloadAt = Date.now() + 5000;
        }
        const measured = await measure(menu.locator('[data-sf-menu-top]'), 'warm_navigation');
        hydrated = receipt.readinessObservation?.hydrated === true;
        receipt.readinessObservation.navigations = navigations;
        return responsiveBannerReady({ height: expectedHeight, focus, serviceState: latest.service.state }, measured?.actual);
      }, { timeout: 100000, intervals: [250, 500, 1000] }).toBe(true);
      // Warm the actual app until it serves this newly saved version, then
      // use a fresh, session-free context to prove native picture selection.
      const sample = await d.freshMenu(width), surface = sample.page;
      try {
      await navigateAfterMediaSettles(surface, d.url, { waitUntil: 'domcontentloaded' });
      const source = surface.locator('[data-sf-menu-banner] img'); await expect(source).toHaveCount(1);
      await source.evaluate(async img => { await (img as HTMLImageElement).decode(); });
      await expect.poll(async () => {
        const measured = await measure(surface.locator('[data-sf-menu-top]'), 'fresh_context');
        return measured ? { heightMatches: Math.abs(measured.geometry.height - expectedHeight) < .02, focus: measured.geometry.position,
          resourceMatches: measured.actual.resourceMatch, serviceState: measured.geometry.state } : null;
      },
        { message: 'Fresh application hydrates the saved height/focal/resource and same public service state before measurement' })
        .toEqual({ heightMatches: true, focus, resourceMatches: true, serviceState: latest.service.state });
      await expect.poll(async () => {
        const geometry = (await measure(preview(index), 'preview_resource'))?.geometry;
        return geometry ? { publicPath: geometry.publicPath, serviceState: geometry.state } : null;
      }).toEqual({ publicPath: base, serviceState: latest.service.state });
      const comparisonKeys = ['viewportWidth', 'width', 'height', 'position', 'searchY', 'categoriesY', 'state', 'themeBackground'];
      const scrollEvidence = (root: Locator) => root.evaluate(el => ({ x: el.ownerDocument.defaultView!.scrollX,
        y: el.ownerDocument.defaultView!.scrollY, viewportHeight: el.ownerDocument.documentElement.clientHeight,
        documentHeight: el.ownerDocument.documentElement.scrollHeight, fontsLoaded: el.ownerDocument.fonts.status === 'loaded' }));
      const beforeSite = await bannerGeometry(surface.locator('[data-sf-menu-top]')), beforeDraft = await bannerGeometry(preview(index));
      receipt.beforeCaptureComparison = { label, width,
        site: Object.fromEntries(comparisonKeys.map(key => [key, beforeSite[key]])),
        preview: Object.fromEntries(comparisonKeys.map(key => [key, beforeDraft[key]])),
        siteScroll: await scrollEvidence(surface.locator('[data-sf-menu-top]')), previewScroll: await scrollEvidence(preview(index)) };
      receipt.comparisonPhase = 'capture-same-inputs-before-equality';
      await bannerViewportScreenshot(surface, resolve(d.artifactDir, `responsive-settings-${label}-${width}.png`), `RESPONSIVE SETTINGS ${label} ${width}`);
      // A truthful custom-height phone preview can exceed the interactive
      // 1000px Dashboard viewport. Enlarge only this read-only capture surface;
      // keep the logical preview width, image height, zoom and input guard.
      const dashboardViewport = page.viewportSize(); expect(dashboardViewport).not.toBeNull();
      const frameBox = await frames.nth(index).boundingBox(); expect(frameBox).not.toBeNull();
      const captureViewport = { width: dashboardViewport!.width,
        height: Math.max(dashboardViewport!.height, Math.ceil(frameBox!.height) + 192) };
      expect(captureViewport.height, 'The controlled synthetic preview has a bounded capture height').toBeLessThanOrEqual(2400);
      try {
        await page.setViewportSize(captureViewport);
        await d.reveal(frames.nth(index));
        await frames.nth(index).screenshot({ path: resolve(d.artifactDir, `responsive-settings-dashboard-${label}-${width}.png`) });
      } finally { await page.setViewportSize(dashboardViewport!); }
      const site = await bannerGeometry(surface.locator('[data-sf-menu-top]')), draft = await bannerGeometry(preview(index));
      expect(allowed.has(site.publicPath), 'Fresh Storefront uses exactly an admitted resource for this device').toBe(true);
      const candidates = new Set([appearance.menu_banner_url, appearance.menu_banner_desktop_url,
        ...(latest.menu_banner_desktop_images_v1?.variants?.map((v: Obj) => v.url) ?? [])]);
      const requested = [...new Set(sample.requestedMedia.filter(path => candidates.has(path)))];
      expect(requested, 'A fresh native picture loads one chosen banner resource, never both device images').toEqual([site.publicPath]);
      expect(site.fit).toBe('cover'); expect(draft.fit).toBe('cover');
      expect(site.position).toBe(focus); expect(draft.position).toBe(focus);

      expect(Math.abs(site.height - expectedHeight), 'The image alone uses its saved CSS height or bounded natural ratio').toBeLessThan(.02);
      receipt.comparisonPhase = 'strict-equality';
      receipt.lastComparison = { label, width, expectedServiceState: latest.service.state,
        site: Object.fromEntries(comparisonKeys.map(key => [key, site[key]])),
        preview: Object.fromEntries(comparisonKeys.map(key => [key, draft[key]])),
        differingFields: comparisonKeys.filter(key => !isDeepStrictEqual(draft[key], site[key])),
        announcementEqual: site.announcement === draft.announcement,
        siteScroll: await scrollEvidence(surface.locator('[data-sf-menu-top]')), previewScroll: await scrollEvidence(preview(index)),
        imagesCapturedBeforeEquality: true };
      for (const key of comparisonKeys)
        expect(draft[key], `Real Dashboard preview and actual Storefront match ${key} at ${width}`).toEqual(site[key]);
      expect(site.bannerWidth).toBe(width); expect(site.borderWidth).toBe('0px'); expect(site.borderRadius).toBe('0px');
      expect(site.maxControlOverlapArea, 'Real identity/status/announcement/search do not cover the visible photo').toBeLessThan(.1);
      expect(site.imageCount).toBe(1); expect(site.naturalWidth).toBeGreaterThan(0); expect(site.naturalHeight).toBeGreaterThan(0);
      receipt.rows.push({ label, width, basePublicPath: base, actualResource: site.publicPath, iframeResource: draft.publicPath,
        resourceRelationship: site.publicPath === draft.publicPath ? 'SAME_PUBLISHED_RESOURCE' : 'DECLARED_SAME_SOURCE_COMPANION',
        imageHeight: site.height, viewportGeometryMatches: true, state: site.state, focus, natural: [site.naturalWidth, site.naturalHeight], requestedBannerResources: requested,
        dashboardCaptureViewport: captureViewport, zoom: 100 });
      await surface.waitForLoadState('networkidle', { timeout: 30000 });
      await sample.check();
      receipt.comparisonPhase = 'complete';
      } finally { await sample.close(); }
    }
  };
  try {
    receipt.stage = 'enable-responsive-layout-native-keyboard';
    const layout = page.getByRole('switch', { name: new RegExp(copy.layout) });
    receipt.layoutSwitch = await enableResponsiveLayoutWithKeyboard(page, layout, d.reveal);
    receipt.stage = 'phone-custom-height-mode'; await customMode(true);
    receipt.stage = 'desktop-custom-height-mode'; await customMode(false);
    receipt.stage = 'initial-responsive-draft-no-autosave'; await noAutosave(baseline, 0);
    receipt.stage = 'save-responsive-layout-and-initial-heights';
    await saveReload({ menu_banner_layout: 'responsive', menu_banner_mobile_height_px: 520, menu_banner_desktop_height_px: 400 });
    receipt.stage = 'mobile-height-draft-save-and-readback';
    let before = await d.read(), countBefore = writes;
    await editDevice(true);
    const originalPhoneNode = await preview(0).locator('[data-sf-menu-banner] img').elementHandle(); expect(originalPhoneNode).not.toBeNull();
    await changeHeight(520, 540); await noAutosave(before, countBefore);
    expect(await originalPhoneNode!.evaluate(el => el.isConnected), 'Height ticks retain the real preview image node/document').toBe(true);
    await saveReload({ menu_banner_mobile_height_px: 540, menu_banner_desktop_height_px: 400 }); await compare('phone-height');
    receipt.stage = 'short-synthetic-dashboard-height-video';
    try { receipt.video = await d.captureHeightVideo(540, value => { receipt.video = value; }); }
    catch (error) { videoFailure = { error }; receipt.auxiliaryFailureStage = receipt.stage; }
    receipt.stage = 'desktop-height-draft-save-and-readback';
    before = await d.read(); countBefore = writes;
    await editDevice(false); await changeHeight(400, 420); await noAutosave(before, countBefore);
    await saveReload({ menu_banner_mobile_height_px: 540, menu_banner_desktop_height_px: 420 }); await compare('desktop-height');
    receipt.stage = 'phone-height-reset-only';
    await editDevice(true); await expect(button(copy.reset)).toHaveCount(1); await click(button(copy.reset));
    await saveReload({ menu_banner_mobile_height_px: null, menu_banner_desktop_height_px: 420 }); await compare('phone-auto');
    receipt.stage = 'desktop-null-fallback';
    expect((await d.read()).document.appearance.menu_banner_desktop_media_id ?? null).toBeNull();
    const publications: Obj[] = [];
    for (const index of [0, 1]) {
      receipt.stage = `desktop-${index ? 'replace' : 'upload'}-actual-edge`;
      before = await d.read(); countBefore = writes;
      await editDevice(false);
      const result = await d.upload(index); publications.push(result);
      expect(result.ok).toBe(true); expect(result.recipe).toBe('storefront-media-c4'); expect(result.media.variant).toBe('w960');
      await noAutosave(before, countBefore);
      await saveReload({ menu_banner_desktop_media_id: result.media.id, menu_banner_mobile_height_px: null, menu_banner_desktop_height_px: 420 });
      await compare(index ? 'desktop-replaced' : 'desktop-uploaded');
    }
    expect(publications[0].media.id).not.toBe(publications[1].media.id);
    receipt.stage = 'select-previous-desktop-from-library';
    const label = (p: Obj) => `${p.media.width}×${p.media.height} · ${p.media.id.slice(0, 8)}`;
    await editDevice(false);
    await click(button(new RegExp(label(publications[1]).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))));
    await click(page.getByRole('menuitem', { name: label(publications[0]), exact: true }));
    await saveReload({ menu_banner_desktop_media_id: publications[0].media.id }); await compare('desktop-selected');
    receipt.stage = 'legacy-v5-v10-reader-and-writer-compatibility';
    const active = await d.read(), legacy = await d.readLegacy();
    expect(legacy.document).toEqual(legacyBannerDocument(active.document));
    await d.writeDocument(legacy.document);
    expect((await d.read()).document, 'An actual old writer omitting the new fields preserves every chosen responsive setting').toEqual(active.document);
    const [v11, v10] = await Promise.all([d.publicRead(11), d.publicRead(10)]);
    const projection = legacyBannerMenu(v11); projection.server_ts = v10.server_ts;
    expect(projection, 'Strict V10 response stays exactly equal to the old projection').toEqual(v10);
    receipt.oldClientOmissionPreservesNewSettings = true; receipt.legacyV5V10ProjectionsUnchanged = true;
    receipt.stage = 'clear-desktop-only-and-return-to-fallback';
    await d.reload(); await editDevice(false); await click(button(copy.clear));
    await saveReload({ menu_banner_desktop_media_id: null, menu_banner_desktop_height_px: 420 }); await compare('desktop-cleared');
    receipt.primaryLifecycleCompleted = true;
    receipt.phoneImageAndFocusPreserved = true; receipt.otherContentAndMediaPreserved = true;
    if (videoFailure) { receipt.stage = receipt.auxiliaryFailureStage; throw videoFailure.error; }
    receipt.status = 'RESPONSIVE_BANNER_SETTINGS_SAVE_READBACK_PASS'; receipt.stage = null;
  } catch (error) {
    receipt.error = error instanceof Error ? error.message.split('\n')[0] : 'acceptance failed'; throw error;
  } finally {
    page.off('request', count); receipt.uiWriteCount = writes;
    const succeeded = receipt.status === 'RESPONSIVE_BANNER_SETTINGS_SAVE_READBACK_PASS';
    try {
      receipt.restoration.stage = 'write-original-owner-document';
      await d.writeDocument(original);
      receipt.restoration.stage = 'v6-document-exact';
      const restored = (await d.read()).document;
      d.recordRestoredDocument?.(restored);
      // Only schema-key names and equality flags leave this synthetic cleanup;
      // no document values, media identifiers, sessions or raw response bodies.
      const differingKeys = (expected: Obj, actual: Obj) => {
        if (!expected || !actual || typeof expected !== 'object' || typeof actual !== 'object' || Array.isArray(expected) || Array.isArray(actual)) return ['invalid-object-shape'];
        return [...new Set([...Object.keys(expected), ...Object.keys(actual)])]
          .filter(key => !isDeepStrictEqual(expected[key], actual[key]) || Object.hasOwn(expected, key) !== Object.hasOwn(actual, key))
          .slice(0, 32).map(key => /^[a-z_]{1,64}$/.test(key) ? key : 'unclassified-key');
      };
      receipt.restoration.v6 = { equal: isDeepStrictEqual(restored, original),
        differingKeys: differingKeys(original, restored),
        differingAppearanceKeys: differingKeys(original.appearance, restored.appearance) };
      expect(restored).toEqual(original);
      receipt.restoration.stage = 'v5-legacy-projection-exact';
      const restoredLegacy = (await d.readLegacy()).document, expectedLegacy = legacyBannerDocument(original);
      receipt.restoration.v5 = { equal: isDeepStrictEqual(restoredLegacy, expectedLegacy),
        differingKeys: differingKeys(expectedLegacy, restoredLegacy),
        differingAppearanceKeys: differingKeys(expectedLegacy.appearance, restoredLegacy.appearance) };
      expect(restoredLegacy, 'Restored legacy V5 projection remains exact').toEqual(expectedLegacy);
      receipt.restoration.stage = 'reload-real-editor';
      await d.reload();
      receipt.restoration.stage = 'public-v11-layout-null';
      expect((await d.publicRead(11)).content_v1.appearance.menu_banner_layout).toBeNull();
      receipt.restoration.publicLayoutNull = true;
      receipt.restoration.stage = 'storefront-restored-legacy-document';
      await menu.waitForLoadState('networkidle', { timeout: 30000 }); await menu.setViewportSize({ width: 390, height: 844 });
      await expect.poll(async () => {
        const response = await navigateAfterMediaSettles(menu, d.url, { waitUntil: 'domcontentloaded' });
        const observation = { restoredLegacy: await menu.locator('[data-sf-banner-layout="responsive"]').count() === 0,
          imageCount: await menu.locator('[data-sf-menu-banner] img').count() };
        const cache = response?.headers()['x-nextjs-cache'];
        receipt.restoration.lastStorefront = { ...observation,
          cache: ['HIT', 'STALE', 'MISS', 'REVALIDATED'].includes(cache ?? '') ? cache : 'unclassified' };
        return observation;
      }, { timeout: 100000, intervals: [250, 500, 1000] }).toEqual({ restoredLegacy: true, imageCount: 1 });
      receipt.syntheticSettingsRestored = true;
      receipt.restoration.stage = 'complete';
    } catch (error) {
      receipt.syntheticSettingsRestored = false;
      receipt.restoration.failedAt = receipt.restoration.stage;
      receipt.restoration.errorType = error instanceof Error && ['Error','TypeError','TimeoutError','AssertionError'].includes(error.name) ? error.name : 'unclassified';
      if (succeeded) { receipt.status = 'FAIL'; receipt.stage = 'restore-synthetic-settings'; throw error; }
    } finally { writeFileSync(resolve(d.artifactDir, 'responsive-banner-settings-result.json'), JSON.stringify(receipt, null, 2)); }
  }
}
