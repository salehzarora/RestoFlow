import test from 'node:test';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import assert from 'node:assert/strict';
import { responsiveBannerKeys, responsiveBannerFixture, legacyBannerDocument, legacyBannerMenu, responsiveBannerReady,
  dashboardImageHash, dashboardImageBytesMatch, dashboardMediaReady, classifyMediaReadError,
  evidenceScalar, bannerDocumentEvidence, bannerComparisonEvidence, bannerAssertionFailure, mediaReadErrorDetail, bannerEvidencePhase } from './responsive-banner-settings.mjs';
import { controlGeometry, visibleGeometry } from './control-geometry.mjs';
import { createHash } from 'node:crypto';
import { LOCAL_API, LOGICAL_ORIGIN } from './live-transport.mjs';
test('restoration materializes exactly six nullable settings without mutating any input or other viewport', () => {
  const input = { appearance: { menu_banner_layout: 'responsive', menu_banner_mobile_height_px: 540,
    menu_banner_media_id: 'phone', menu_background_media_id: 'background', independent: { retained: true } }, hero: { untouched: true } };
  const before = structuredClone(input), result = responsiveBannerFixture(input);
  assert.deepEqual(input, before); assert.equal(responsiveBannerKeys.length, 6);
  assert.deepEqual(result.materializedNullKeys, ['menu_banner_desktop_media_id', 'menu_banner_desktop_height_px', 'menu_banner_desktop_focal_x', 'menu_banner_desktop_focal_y']);
  const mergedPrior = { ...result.document.appearance, menu_banner_desktop_height_px: 420 };
  assert.equal(({ ...mergedPrior, ...input.appearance }).menu_banner_desktop_height_px, 420, 'An omitted key would incorrectly retain the prior fixture choice');
  assert.equal(({ ...mergedPrior, ...result.document.appearance }).menu_banner_desktop_height_px, null, 'Explicit null restores auto/legacy instead');
  assert.equal(result.document.appearance.menu_banner_mobile_height_px, 540);
  assert.deepEqual(result.document.hero, input.hero);
  assert.deepEqual(Object.keys(result.document.appearance).sort(), [...new Set([...Object.keys(input.appearance), ...responsiveBannerKeys])].sort());
  assert.throws(() => responsiveBannerFixture({ appearance: [] }));
});
test('legacy management and public projections remove only the exact admitted extension, preserving unknown-key failures', () => {
  const doc = { appearance: { text_color: '#112233', menu_banner_layout: 'responsive', menu_banner_desktop_media_id: 'published', unknown: true } };
  assert.deepEqual(legacyBannerDocument(doc), { appearance: { text_color: '#112233', unknown: true } });
  const menu = { server_ts: 'original', unrelated: true, content_v1: { appearance: { menu_banner_url: 'phone', menu_banner_desktop_url: 'desktop', menu_banner_width: 960, menu_banner_height: 480, unknown: true } }, menu_banner_desktop_images_v1: { base_url: 'desktop', variants: [] } };
  const copy = structuredClone(menu);
  assert.deepEqual(legacyBannerMenu(menu), { server_ts: 'original', unrelated: true, content_v1: { appearance: { menu_banner_url: 'phone', unknown: true } } });
  assert.deepEqual(menu, copy);
});

test('warm document readiness rejects a same-image stale height, wrong focus or legacy layout', () => {
  const expected = { height: 540, focus: '38% 9%', serviceState: 'open' };
  const current = { height: 540, focus: '38% 9%', resourceMatch: true, layoutResponsive: true, hydrated: true, serviceState: 'open' };
  assert.equal(responsiveBannerReady(expected, current), true);
  assert.equal(responsiveBannerReady(expected, { ...current, height: 520 }), false, 'Unchanged image URL does not admit the older saved height');
  assert.equal(responsiveBannerReady(expected, { ...current, focus: '50% 50%' }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, layoutResponsive: false }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, resourceMatch: false }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, hydrated: false }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, serviceState: 'closed' }), false, 'A cached closing notice must not be compared with an open preview');
  assert.equal(responsiveBannerReady(expected, { ...current, serviceState: undefined }), false);
  assert.equal(responsiveBannerReady({ ...expected, serviceState: '' }, current), false);
  assert.equal(responsiveBannerReady(expected, { ...current, height: NaN }), false);
  assert.equal(responsiveBannerReady(expected, null), false, 'A swallowed geometry error cannot count as ready');
  assert.equal(responsiveBannerReady(expected, { ...current, height: 540.021 }), false, 'The existing strict .02px bound is retained');
});

test('recorded 932px phone iframe cannot fit the 1000px capture viewport without changing the guard', () => {
  const frame = { x: 0, y: 96, width: 390, height: 932 }, original = { width: 1440, height: 1000 };
  assert.equal(visibleGeometry(frame, original), false, 'The existing usable vertical range is only 840px');
  const capture = { width: original.width, height: Math.max(original.height, Math.ceil(frame.height) + 192) };
  assert.equal(capture.height, 1124); assert.equal(capture.width, original.width);
  assert.equal(visibleGeometry(frame, capture), true);
  assert.equal(controlGeometry(frame, capture, true).ready, true);
  assert.equal(controlGeometry(frame, capture, false, false).ready, false, 'A blocked input surface is still rejected');
  assert.equal(controlGeometry({ ...frame, y: 95 }, capture, true).ready, false, 'The existing top inset is retained');
});

test('native Dashboard media observation admits only exact public image GETs without credentials', () => {
  const bytes = Buffer.from('synthetic published derivative bytes'), hash = createHash('sha256').update(bytes).digest('hex');
  const url = `${LOCAL_API}/storage/v1/object/public/storefront-media/${'a'.repeat(32)}/${hash}.webp`;
  const request = { url, method: 'GET', resourceType: 'image', headers: { accept: 'image/webp' } };
  assert.equal(dashboardImageHash(request), hash);
  for (const bad of [url.replace(LOCAL_API, 'https://external.test'), url.replace('/public/', '/authenticated/'),
    url.replace('/public/', '/sign/'), url + '?token=secret', url + '#fragment', url.replace('127.0.0.1', 'user:secret@127.0.0.1'),
    url.replace(hash, hash.toUpperCase())]) assert.throws(() => dashboardImageHash({ ...request, url: bad }));
  for (const method of ['POST', 'HEAD', 'DELETE']) assert.throws(() => dashboardImageHash({ ...request, method }));
  assert.throws(() => dashboardImageHash({ ...request, method: undefined }));
  assert.throws(() => dashboardImageHash({ ...request, headers: undefined }));
  assert.throws(() => dashboardImageHash({ ...request, resourceType: 'fetch' }));
  for (const name of ['Authorization', 'apikey', 'Cookie']) for (const value of ['secret', ''])
    assert.throws(() => dashboardImageHash({ ...request, headers: { [name]: value } }));
  assert.equal(dashboardImageBytesMatch(hash, 200, bytes), true);
  for (const status of [201, 304, 404]) assert.equal(dashboardImageBytesMatch(hash, status, bytes), false);
  assert.equal(dashboardImageBytesMatch(hash, 200, Buffer.from('other bytes')), false);
  assert.equal(dashboardImageBytesMatch(hash, 200, new Uint8Array()), false);
});

test('native Dashboard media proof cannot accept missing, failed or only partly verified responses', () => {
  assert.equal(dashboardMediaReady(1, 1, [true]), true);
  for (const values of [[0, 0, []], [1, 0, [false]], [2, 1, [true, false]], [2, 2, [true]], [1, 1, [false]]])
    assert.equal(dashboardMediaReady(...values), false);
});

test('passive public media diagnostics expose fixed classes, never raw exception values', () => {
  assert.equal(classifyMediaReadError(new Error('Protocol error (Network.getResponseBody): No data found for resource with given identifier')), 'body-unavailable');
  assert.equal(classifyMediaReadError(new Error('Target page, context or browser has been closed')), 'context-closed');
  assert.equal(classifyMediaReadError('net::ERR_ABORTED'), 'aborted');
  assert.equal(classifyMediaReadError(new Error('private-value-must-not-escape')), 'unclassified');
  assert.equal(classifyMediaReadError({ message: 'private-value-must-not-escape' }), 'unclassified');
});

test('banner evidence distinguishes omission, explicit null, booleans and numbers without exporting private strings', () => {
  const result = bannerDocumentEvidence({ appearance: { menu_banner_media_id: null, menu_banner_enabled: false,
    menu_banner_focal_x: 0, menu_banner_focal_y: 100, menu_banner_layout: 'responsive',
    text_color: '#FFFFFF', not_an_allowed_field: 'private-content' }, story: { editorial_media_id: 'private-id' } });
  assert.deepEqual(result.appearance.menu_banner_media_id, { present: true, type: 'null', value: null });
  assert.deepEqual(result.appearance.menu_banner_desktop_media_id, { present: false, type: 'undefined' });
  assert.deepEqual(result.appearance.menu_banner_enabled, { present: true, type: 'boolean', value: false });
  assert.deepEqual(result.appearance.menu_banner_focal_x, { present: true, type: 'number', value: 0 });
  assert.equal(result.appearance.menu_banner_focal_y.value, 100);
  assert.equal(result.appearance.menu_banner_layout.value, 'responsive');
  assert.equal(result.appearance.text_color.value, '#FFFFFF');
  assert.equal(result.media['story.editorial_media_id'].sha256, createHash('sha256').update('private-id').digest('hex'));
  assert.deepEqual(result.media['promo.editorial_media_id'], { present: false, type: 'undefined' });
  const serialized = JSON.stringify(result);
  assert.equal(serialized.includes('private-content'), false); assert.equal(serialized.includes('private-id'), false);
  assert.equal(Object.hasOwn(result.appearance, 'not_an_allowed_field'), false);
  assert.equal(evidenceScalar('a-private-session').sha256, createHash('sha256').update('a-private-session').digest('hex'));
});

test('failed assertion evidence preserves false versus true and only owned source coordinates', () => {
  const failure = Object.assign(new Error('never export this message'), { matcherResult: { name: 'toBe', actual: false, expected: true } });
  failure.stack = 'private stack https://private.invalid\n at helper (C:/private/dashboard.spec.ts:407:4)\n at clear (C:/private/dashboard.spec.ts:1880:9)';
  const result = bannerAssertionFailure(failure);
  assert.equal(result.matcher, 'toBe');
  assert.deepEqual(result.actual, { present: true, type: 'boolean', value: false });
  assert.deepEqual(result.expected, { present: true, type: 'boolean', value: true });
  assert.deepEqual(result.sourceFrames, [{ file: 'dashboard.spec.ts', line: 407, column: 4 }, { file: 'dashboard.spec.ts', line: 1880, column: 9 }]);
  assert.equal(JSON.stringify(result).includes('private'), false);
  assert.equal(bannerComparisonEvidence('strict nullable pointer', 'appearance.menu_banner_media_id', null, undefined).equal, false);
  assert.equal(bannerComparisonEvidence('zero stays zero', 'appearance.menu_banner_focal_x', 0, 0).equal, true);
});

test('media evidence uses fixed phases and error details without exporting arbitrary input', () => {
  assert.equal(bannerEvidencePhase('clear-storefront'), 'clear-storefront');
  assert.equal(bannerEvidencePhase('responsive-desktop-cleared-390'), 'responsive-desktop-cleared-390');
  for (const value of ['private-value', 'responsive-desktop-cleared-392', 'responsive-unknown-390', { secret: 'hidden' }])
    assert.equal(bannerEvidencePhase(value), 'unclassified');
  assert.equal(mediaReadErrorDetail(new Error('No data found for resource with given identifier')), 'no-data');
  assert.equal(mediaReadErrorDetail(new Error('No resource with given identifier found')), 'no-resource');
  assert.equal(mediaReadErrorDetail(new Error('Protocol error Network.getResponseBody')), 'get-body-error');
  assert.equal(mediaReadErrorDetail(new Error('unexported private exception')), 'unclassified');
});

// UNIT_ONLY: EventEmitter/VM fixtures exercise the exact owned TypeScript
// navigation/observer implementation. No browser, network, Auth or Edge exists.
const bannerNavigationSource = readFileSync(new URL('./responsive-banner-settings.ts', import.meta.url), 'utf8');
const bannerNavigationStart = bannerNavigationSource.indexOf('const pageImageEvidence =');
const bannerNavigationEnd = bannerNavigationSource.indexOf('export async function adjustBannerHeightWithKeyboard(');
assert(bannerNavigationStart >= 0 && bannerNavigationEnd > bannerNavigationStart, 'Extract only the current navigation/observer block');
const bannerNavigationFragment = bannerNavigationSource.slice(bannerNavigationStart, bannerNavigationEnd);
const bannerNavigationModule = `import { dashboardImageBytesMatch, classifyMediaReadError, mediaReadErrorDetail, bannerEvidencePhase } from ${JSON.stringify(new URL('./responsive-banner-settings.mjs', import.meta.url).href)};
import { LOGICAL_ORIGIN, localMediaTarget } from ${JSON.stringify(new URL('./live-transport.mjs', import.meta.url).href)};
` + ts.transpileModule(bannerNavigationFragment, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const realBannerNavigation = await import(`data:text/javascript;base64,${Buffer.from(bannerNavigationModule).toString('base64')}`);
function bannerDeferred() {
  let resolve, reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
}
const bannerUnitTick = () => new Promise(resolve => setImmediate(resolve));
function bannerNavigationUnit() {
  const frameReady = bannerDeferred(), decoded = bannerDeferred(), body = bannerDeferred();
  const bytes = Buffer.from('Synthetic already-issued public image observation'), hash = createHash('sha256').update(bytes).digest('hex');
  const imageUrl = `${LOGICAL_ORIGIN}/storage/v1/object/public/storefront-media/${'7'.repeat(32)}/${hash}.webp`;
  const calls = { wait: [], goto: [], evaluate: 0, animationFrame: 0, query: 0, decode: 0, body: 0, imageRequests: 0 };
  class ImageMock {
    currentSrc = imageUrl;
    decode() { calls.decode++; return decoded.promise; }
  }
  const image = new ImageMock();
  class PageMock extends EventEmitter {
    url() { return 'http://127.0.0.1:3000/unit-menu'; }
    waitForLoadState(state, options) { calls.wait.push({ state, ...options }); return Promise.resolve(); }
    evaluate(callback) {
      calls.evaluate++;
      // Execute the real evaluate callback with an in-memory DOM boundary,
      // rather than resolving a substitute implementation of its frame/decode.
      return runInNewContext(`(${callback.toString()})()`, {
        requestAnimationFrame: callback => { calls.animationFrame++; frameReady.promise.then(() => callback(0)); return 1; },
        HTMLImageElement: ImageMock,
        document: { querySelector: selector => { assert.equal(selector, '[data-sf-menu-banner] img'); calls.query++; return image; } },
      });
    }
    goto(url, options) {
      calls.goto.push({ url, ...options, at: Date.now() });
      context.emit('request', { url: () => url, method: () => 'GET', resourceType: () => 'document', frame: () => frame, isNavigationRequest: () => true });
      return Promise.resolve({ status: () => 200 });
    }
  }
  const page = new PageMock(), frame = { page: () => page, parentFrame: () => null };
  class ContextMock extends EventEmitter { pages() { return [page]; } }
  const context = new ContextMock();
  context.on('request', request => { if (request.resourceType() === 'image') calls.imageRequests++; });
  const request = { url: () => imageUrl, method: () => 'GET', resourceType: () => 'image', frame: () => frame, isNavigationRequest: () => false, failure: () => null };
  const response = { url: () => imageUrl, request: () => request, status: () => 200, body: () => { calls.body++; return body.promise; } };
  const observer = realBannerNavigation.observeLogicalMedia(context, { dashboard: 'http://127.0.0.1:57026', storefront: 'http://127.0.0.1:3000' });
  return { page, context, request, response, observer, calls, frameReady, decoded, body, bytes };
}

test('UNIT_ONLY: already-fired networkidle waits for request-before-response, current decode and native evidence once within the original budget', async () => {
  const u = bannerNavigationUnit(), budget = 220;
  try {
    u.observer.phase('responsive-desktop-replaced-390'); u.context.emit('request', u.request);
    const started = Date.now(), navigation = realBannerNavigation.navigateAfterMediaSettles(u.page, 'http://127.0.0.1:3000/unit-target', { timeout: budget, waitUntil: 'domcontentloaded' });
    await bannerUnitTick(); assert.equal(u.calls.goto.length, 0); assert.equal(u.calls.animationFrame, 1);
    u.frameReady.resolve(); await bannerUnitTick(); assert.equal(u.calls.decode, 1);
    u.decoded.resolve(); await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'A request observed before its response must remain pending even after the current image decodes');
    u.context.emit('response', u.response); u.context.emit('requestfinished', u.request); await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'Native requestfinished alone does not replace the pending native body observation');
    u.body.resolve(u.bytes); await navigation;
    const snapshot = u.observer.snapshot();
    assert.deepEqual(u.calls.wait, [{ state: 'networkidle', timeout: budget }]);
    assert.equal(u.calls.goto.length, 1); assert.equal(u.calls.goto[0].waitUntil, 'domcontentloaded');
    const spent = u.calls.goto[0].at - started, remaining = u.calls.goto[0].timeout;
    assert(remaining > 0 && remaining <= budget && remaining <= budget - spent + 5, 'goto receives only the original remaining deadline');
    assert.deepEqual([u.calls.evaluate, u.calls.animationFrame, u.calls.query, u.calls.decode, u.calls.body, u.calls.imageRequests], [1, 1, 1, 1, 1, 1]);
    assert.deepEqual([snapshot.requestFinished, snapshot.bodyReads, snapshot.filenameMatches, snapshot.bodyErrors, snapshot.pendingBodies], [1, 1, 1, 0, 0]);
    const transition = snapshot.responsiveTransitionSamples[0], fact = transition.requests[0];
    assert.equal(transition.phase, 'responsive-desktop-replaced-390'); assert.equal(transition.requests.length, 1);
    assert.deepEqual([fact.bodyReadStatus, fact.bodyMatched, fact.bodyBytes], ['read', true, u.bytes.length]);
    assert(fact.bodyReadEndedMs <= transition.firstNavigation.observedMs, 'Actual native evidence is read before the first navigation event');
  } finally { u.observer.stop(); }
});

test('UNIT_ONLY: a native body-unavailable result remains a byte-evidence failure without a retry or substitute success', async () => {
  const u = bannerNavigationUnit();
  try {
    u.context.emit('request', u.request); u.frameReady.resolve(); u.decoded.resolve();
    const navigation = realBannerNavigation.navigateAfterMediaSettles(u.page, 'http://127.0.0.1:3000/unit-target', { timeout: 220, waitUntil: 'domcontentloaded' });
    u.context.emit('response', u.response); await bannerUnitTick();
    u.body.reject(new Error('Protocol error Network.getResponseBody: No resource with given identifier found'));
    await navigation;
    const snapshot = u.observer.snapshot();
    assert.deepEqual([snapshot.responses, snapshot.bodyReads, snapshot.filenameMatches, snapshot.bodyErrors, snapshot.pendingBodies], [1, 0, 0, 1, 0]);
    assert.equal(snapshot.failures.length, 1); assert.equal(snapshot.failures[0].classification, 'body-unavailable'); assert.equal(snapshot.failures[0].detail, 'no-resource');
    assert.equal(snapshot.failures[0].fact.requestId, 'r1');
    assert.deepEqual([u.calls.body, u.calls.imageRequests, u.calls.goto.length], [1, 1, 1], 'Observing a failure neither repeats the request nor changes it into accepted image evidence');
    u.context.emit('requestfinished', u.request);
    assert.notEqual(u.observer.snapshot().failures[0].fact.finishedMs, null, 'A late finish is still joined to the retained failure');
    assert.equal(u.observer.snapshot().bodyErrors, 1);
  } finally { u.observer.stop(); }
});

test('UNIT_ONLY: unresolved native evidence times out at the supplied navigation budget without goto or a late-completion retry', async () => {
  const u = bannerNavigationUnit(), budget = 60;
  try {
    u.context.emit('request', u.request); u.context.emit('response', u.response); u.frameReady.resolve(); u.decoded.resolve();
    const started = Date.now();
    await assert.rejects(realBannerNavigation.navigateAfterMediaSettles(u.page, 'http://127.0.0.1:3000/unit-target', { timeout: budget, waitUntil: 'domcontentloaded' }), /original navigation deadline/);
    const elapsed = Date.now() - started;
    assert(elapsed >= budget - 5 && elapsed <= budget + 150, 'Configured budget is unchanged; finite driver scheduling overhead is bounded');
    assert.deepEqual(u.calls.wait, [{ state: 'networkidle', timeout: budget }]); assert.equal(u.calls.goto.length, 0); assert.equal(u.calls.body, 1); assert.equal(u.calls.imageRequests, 1);
    assert.equal(u.observer.snapshot().pendingBodies, 1);
    u.body.resolve(u.bytes); await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'Completion after the failed original call never triggers another navigation');
  } finally { u.observer.stop(); }
});
