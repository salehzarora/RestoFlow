import test from 'node:test';
import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import assert from 'node:assert/strict';
import { responsiveBannerKeys, responsiveBannerFixture, legacyBannerDocument, legacyBannerMenu, legacyWelcomeFixtureDocument, legacyWelcomeFixtureRead, responsiveBannerReady,
  dashboardImageHash, dashboardImageBytesMatch, dashboardMediaReady, classifyMediaReadError,
  evidenceScalar, bannerDocumentEvidence, bannerComparisonEvidence, bannerAssertionFailure, mediaReadErrorDetail, bannerEvidencePhase, menuDocumentNavigation, responsiveSettingsHandoff, assertResponsiveSettingsHandoff, acceptedResponsiveSettingsHandoff } from './responsive-banner-settings.mjs';
import { controlGeometry, visibleGeometry } from './control-geometry.mjs';
import { createHash } from 'node:crypto';
import { LOCAL_API, LOGICAL_ORIGIN } from './live-transport.mjs';

test('document navigation preserves hydration, five-second cadence and the existing deadline', () => {
  const start = 1000;
  assert.deepEqual(menuDocumentNavigation(start, null, false, start), { navigate: true, timeout: 30000, remainingMs: 100000 });
  assert.equal(menuDocumentNavigation(start, start + 100, true, start + 5099).navigate, false);
  assert.equal(menuDocumentNavigation(start, start + 100, false, start + 20000).navigate, false,
    'An incomplete hydration frame must not be discarded, even after the cadence expires');
  assert.equal(menuDocumentNavigation(start, start + 100, true, start + 5100).navigate, true);
  let lastNavigationAt = null, visits = 0;
  for (let now = start; now <= start + 100000; now += 250) {
    const next = menuDocumentNavigation(start, lastNavigationAt, true, now);
    if (next.navigate) { visits++; lastNavigationAt = now; }
  }
  assert.equal(visits, 20);
  assert.deepEqual(menuDocumentNavigation(start, start + 95000, true, start + 100000), { navigate: false, timeout: 1, remainingMs: 0 });
  assert.equal(menuDocumentNavigation(start, null, false, start + 100001).navigate, false);
  assert.deepEqual(menuDocumentNavigation(start, start + 90000, true, start + 99990), { navigate: true, timeout: 10, remainingMs: 10 });
});
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

test('V7 fixture projects only its exact two welcome keys to V6, retaining unknown-field and old-banner checks', () => {
  const document = { hero_headline: 'unchanged', appearance: { text_color: null, button_text_color: null,
    welcome_media_type: null, welcome_video_media_id: null, menu_banner_layout: 'responsive', unknown: true } };
  const input = { ok: true, version: 4, storefront_branch_id: 'same', document }, before = structuredClone(input);
  const projected = legacyWelcomeFixtureRead(input);
  assert.deepEqual(projected, { ...input, document: { hero_headline: 'unchanged', appearance: {
    text_color: null, button_text_color: null, menu_banner_layout: 'responsive', unknown: true } } });
  assert.deepEqual(input, before);
  assert.deepEqual(legacyBannerDocument(projected.document).appearance, { text_color: null, button_text_color: null, unknown: true });
  assert.notDeepEqual(projected.document, { ...projected.document, appearance: { ...projected.document.appearance, unknown: false } });
  for (const appearance of [null, [], {}, { welcome_media_type: null }, { welcome_video_media_id: null }])
    assert.throws(() => legacyWelcomeFixtureDocument({ appearance }));
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
  assert.equal(bannerEvidencePhase('initialize-independent-content-baseline'), 'initialize-independent-content-baseline');
  assert.equal(bannerEvidencePhase('responsive-desktop-cleared-390'), 'responsive-desktop-cleared-390');
  for (const value of ['private-value', 'initialize-independent-content-baseline-unknown', 'responsive-desktop-cleared-392', 'responsive-unknown-390', { secret: 'hidden' }])
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

test('UNIT_ONLY: settings handoff admits only the current source, synthetic owner and fresh cleared document; no Auth state', () => {
  const source = { runId: '44168481188', runAttempt: '1', prHead: 'a'.repeat(40), prBase: 'b'.repeat(40), testedCheckout: 'c'.repeat(40), testedTree: 'd'.repeat(40) };
  const owner = { orgId: '11111111-1111-1111-1111-111111111111', restaurantId: '22222222-2222-2222-2222-222222222222',
    branchId: '33333333-3333-3333-3333-333333333333', slug: 'cinematic-settings', password: 'never-copy-secret' };
  const phone = { mediaId: '44444444-4444-4444-4444-444444444444', publicPath: `/storage/v1/object/public/storefront-media/${'2'.repeat(32)}/${'5'.repeat(64)}.webp`, width: 900, height: 450 };
  const readback = { ok: true, restaurant_id: owner.restaurantId, storefront_branch_id: owner.branchId, version: 7,
    document: { hero_headline: 'not-exported-content', appearance: { menu_banner_media_id: null, menu_banner_layout: null } } };
  const originals = structuredClone({ source, owner, phone, readback });
  const handoff = responsiveSettingsHandoff(source, owner, phone, readback);
  assert.doesNotThrow(() => assertResponsiveSettingsHandoff(handoff, source, owner, readback));
  assert(!JSON.stringify(handoff).includes('never-copy-secret'));
  assert(!JSON.stringify(handoff).includes('not-exported-content'));
  assert.deepEqual({ source, owner, phone, readback }, originals);
  for (const missing of [undefined, null, {}, { source }]) assert.throws(() => assertResponsiveSettingsHandoff(missing, source, owner, readback));
  for (const key of ['runId', 'runAttempt', 'prHead', 'prBase', 'testedCheckout', 'testedTree']) {
    const changed = { ...source, [key]: key === 'runId' ? '44168481189' : key === 'runAttempt' ? '2' : 'e'.repeat(40) };
    assert.throws(() => assertResponsiveSettingsHandoff(handoff, changed, owner, readback));
  }
  for (const key of ['orgId', 'restaurantId', 'branchId', 'slug']) {
    const changed = { ...owner, [key]: key === 'slug' ? 'cinematic-other' : '66666666-6666-6666-6666-666666666666' };
    assert.throws(() => assertResponsiveSettingsHandoff(handoff, source, changed, readback));
  }
  assert.throws(() => assertResponsiveSettingsHandoff(handoff, source, owner, { ...readback, version: 8 }));
  const stale = structuredClone(readback); stale.document.hero_headline = 'changed';
  assert.throws(() => assertResponsiveSettingsHandoff(handoff, source, owner, stale));
  const selected = structuredClone(readback); selected.document.appearance.menu_banner_media_id = phone.mediaId;
  assert.throws(() => responsiveSettingsHandoff(source, owner, phone, selected));
  const tampered = structuredClone(handoff); tampered.phone.mediaId = '77777777-7777-7777-7777-777777777777';
  assert.throws(() => assertResponsiveSettingsHandoff(tampered, source, owner, readback));
  assert.throws(() => responsiveSettingsHandoff(source, owner, { ...phone, publicPath: '/storage/v1/object/authenticated/private' }, readback));
  assert.throws(() => responsiveSettingsHandoff(source, owner, { ...phone, width: 1920 }, readback));
  for (const runAttempt of [undefined, null, '', '0', 1, '-1', '1.5'])
    assert.throws(() => responsiveSettingsHandoff({ ...source, runAttempt }, owner, phone, readback));
  const proof = { primarySucceeded: true, byteGuardStatus: 'PASS', mappedMedia: 4, verifiedMediaBytes: 4 };
  assert.equal(acceptedResponsiveSettingsHandoff(handoff, proof), handoff);
  for (const changed of [{ primarySucceeded: false }, { byteGuardStatus: 'NOT_RUN' }, { byteGuardStatus: 'RUNNING' },
    { byteGuardStatus: 'FAIL' }, { mappedMedia: 0, verifiedMediaBytes: 0 }, { verifiedMediaBytes: 3 }, { mappedMedia: NaN }])
    assert.equal(acceptedResponsiveSettingsHandoff(handoff, { ...proof, ...changed }), null,
      'A failed/incomplete/zero-resource producer cannot publish the private handoff');
  assert.equal(acceptedResponsiveSettingsHandoff(null, proof), null);
});

test('UNIT_ONLY: original settings assertion is persisted before blocked restoration and remains the thrown error', async () => {
  const source = readFileSync(new URL('./responsive-banner-settings.ts', import.meta.url), 'utf8');
  const start = source.indexOf('export async function verifyResponsiveBannerSettings(');
  assert(start >= 0);
  const code = ts.transpileModule(source.slice(start).replace('export async function', 'async function'),
    { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  const original = new Error('original bounded assertion');
  original.matcherResult = { name: 'toBe', expected: true, actual: false };
  original.stack = 'Error: original bounded assertion\n at verifyResponsiveBannerSettings (responsive-banner-settings.ts:600:10)';
  const writes = new Map(), cleanupEntered = bannerDeferred(), cleanup = bannerDeferred();
  const run = runInNewContext(code + '\nverifyResponsiveBannerSettings', { Error, Date, Math, JSON,
    responsiveBannerFixture, bannerAssertionFailure, copy: { layout: 'existing-layout' },
    resolve: (directory, file) => `${directory}/${file}`,
    writeFileSync: (file, body) => writes.set(file, JSON.parse(body)),
    enableResponsiveLayoutWithKeyboard: async () => { throw original; },
  });
  const page = { on() {}, off() {}, locator: () => ({}), getByRole: () => ({}) };
  const operation = run(page, {}, { read: async () => ({ document: { appearance: { menu_banner_media_id: null } } }),
    artifactDir: '/unit', writeDocument: () => { cleanupEntered.resolve(); return cleanup.promise; } });
  await cleanupEntered.promise;
  const pending = writes.get('/unit/responsive-banner-settings-result.json');
  assert.equal(pending.status, 'FAIL'); assert.equal(pending.originalFailure.matcher, 'toBe');
  assert.deepEqual(pending.originalFailure.expected, { present: true, type: 'boolean', value: true });
  assert.deepEqual(pending.originalFailure.actual, { present: true, type: 'boolean', value: false });
  assert.equal(pending.originalFailure.sourceLine, 600);
  assert.equal(writes.get('/unit/responsive-banner-settings-progress.json').originalFailure.sourceLine, 600);
  cleanup.reject(new Error('later cleanup failure'));
  await assert.rejects(operation, error => error === original, 'Cleanup failure cannot replace the original assertion');
});

test('UNIT_ONLY: actual producer keeps the scalar candidate private until its native byte guard completes', async () => {
  const sourceText = readFileSync(new URL('./dashboard.spec.ts', import.meta.url), 'utf8');
  const start = sourceText.indexOf("test('independent banner → actual Edge → save/reload → replace/clear preserves other media'");
  const end = sourceText.indexOf('// Split from the base banner journey', start);
  assert(start >= 0 && end > start);
  const code = ts.transpileModule(sourceText.slice(start, end),
    { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
  for (const failGuard of [false, true]) {
    const gate = bannerDeferred(), entered = bannerDeferred(), original = new Error('real guard failure remains primary');
    const source = { runId: '44168481188', runAttempt: '1', prHead: 'a'.repeat(40), prBase: 'b'.repeat(40), testedCheckout: 'c'.repeat(40), testedTree: 'd'.repeat(40) };
    const owner = { orgId: '11111111-1111-1111-1111-111111111111', restaurantId: '22222222-2222-2222-2222-222222222222',
      branchId: '33333333-3333-3333-3333-333333333333', slug: 'cinematic-settings', email: 'owner@unit.invalid', password: 'unit-only' };
    const phone = { mediaId: '44444444-4444-4444-4444-444444444444', publicPath: `/storage/v1/object/public/storefront-media/${'2'.repeat(32)}/${'5'.repeat(64)}.webp`, width: 900, height: 450 };
    const readback = { ok: true, restaurant_id: owner.restaurantId, storefront_branch_id: owner.branchId, version: 7,
      document: { appearance: { menu_banner_media_id: null, menu_banner_layout: null } } };
    let callback; const register = (_title, value) => { callback = value; }; register.setTimeout = () => {};
    const auth = { status: () => 200, json: async () => ({ user: { email: owner.email }, access_token: 'unit-only-session' }) };
    const network = { fontsReady: async () => {}, fonts: () => [], media: () => ({ mappedMedia: 4, verifiedMediaBytes: 4 }),
      check: () => { entered.resolve(); return gate.promise; } };
    const page = { goto: async () => {}, getByRole: () => ({ inputValue: async () => owner.email }),
      locator: () => ({ inputValue: async () => owner.password }), waitForResponse: async () => auth };
    const getter = runInNewContext('let responsiveSettingsCaseHandoff = null;\n' + code + '\n() => responsiveSettingsCaseHandoff', {
      test: register, Date, Error, process: { env: { CINEMATIC_ARTIFACT_DIR: '/unit' } },
      fixture: () => ({ ownerA: owner }), guardBrowser: async () => network,
      observeLogicalMedia: () => ({ phase() {}, snapshot: () => ({}), stop() {} }),
      semantics: async () => {}, fillField: async () => {}, enterLoginPassword: async () => {}, tapButton: async () => {}, openEditor: async () => {},
      observeResponse: value => value, responseAfterAction: async (value, action) => { await action(); return value; },
      isPasswordGrantRequest: () => true, verifyBannerJourney: async () => phone, rpc: async () => readback,
      responsiveSettingsSource: () => source, responsiveSettingsHandoff, acceptedResponsiveSettingsHandoff,
      bannerEvidencePhase, bannerAssertionFailure, failureScreenshot: async () => 'not-captured',
      writeFileSync() {}, resolve: (directory, file) => `${directory}/${file}`,
      expect: value => ({ toBe: expected => assert.equal(value, expected) }),
      L: { email: 'email', login: 'login' }, DASHBOARD: 'http://127.0.0.1:57026', API: 'http://127.0.0.1:54321', STOREFRONT: 'http://127.0.0.1:3000',
    });
    const operation = callback({ page, context: { newPage: async () => ({}) } }, { timeout: 1200000 });
    await entered.promise;
    assert.equal(getter(), null, 'The actual producer has finished its UI/readback but must not publish before native byte evidence');
    if (failGuard) {
      gate.reject(original); await assert.rejects(operation, error => error === original);
      assert.equal(getter(), null, 'A real guard rejection leaves no private handoff for another case');
    } else {
      gate.resolve(); await operation;
      assert.equal(getter().phone.mediaId, phone.mediaId); assert.equal(getter().source.runAttempt, '1');
    }
  }
});
function bannerNavigationUnit(lateSelection = false) {
  const frameReady = bannerDeferred(), decoded = bannerDeferred(), body = bannerDeferred();
  const bytes = Buffer.from('Synthetic already-issued public image observation'), hash = createHash('sha256').update(bytes).digest('hex');
  const imageUrl = `${LOGICAL_ORIGIN}/storage/v1/object/public/storefront-media/${'7'.repeat(32)}/${hash}.webp`;
  const calls = { wait: [], goto: [], evaluate: 0, animationFrame: 0, query: 0, decode: 0, body: 0, imageRequests: 0 };
  class ImageMock extends EventEmitter {
    currentSrc = lateSelection ? imageUrl.replace(hash, '0'.repeat(64)) : imageUrl;
    srcset = '';
    closest() { return lateSelection ? { querySelectorAll: () => [{ media: '(min-width:651px)', srcset: imageUrl + ' 1280w' }] } : null; }
    getAttribute(name) { assert.equal(name, 'src'); return this.currentSrc; }
    addEventListener(name, callback) { this.on(name, callback); }
    removeEventListener(name, callback) { this.off(name, callback); }
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
        HTMLImageElement: ImageMock, URL, matchMedia: () => ({ matches: true }),
        document: { baseURI: 'http://127.0.0.1:3000/unit-menu', querySelector: selector => { assert.equal(selector, '[data-sf-menu-banner] img'); calls.query++; return image; } },
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
  return { page, context, request, response, observer, calls, frameReady, decoded, body, bytes, select: () => { image.currentSrc = imageUrl; image.emit('load'); } };
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
    assert.deepEqual(u.calls.wait, []);
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
    assert.deepEqual(u.calls.wait, []); assert.equal(u.calls.goto.length, 0); assert.equal(u.calls.body, 1); assert.equal(u.calls.imageRequests, 1);
    assert.equal(u.observer.snapshot().pendingBodies, 1);
    u.body.resolve(u.bytes); await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'Completion after the failed original call never triggers another navigation');
  } finally { u.observer.stop(); }
});

test('UNIT_ONLY: a viewport desktop request arriving after old-image decode cannot overlap goto', async () => {
  const u = bannerNavigationUnit(true), budget = 220;
  try {
    u.observer.phase('responsive-desktop-selected-1280');
    u.frameReady.resolve(); u.decoded.resolve();
    const started = Date.now();
    const navigation = realBannerNavigation.navigateAfterMediaSettles(u.page, 'http://127.0.0.1:3000/unit-target', { timeout: budget, waitUntil: 'domcontentloaded' });
    await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'Old currentSrc decode cannot admit navigation before active desktop source selection');
    assert.equal(u.calls.decode, 0, 'No old-image decode is substituted for selected desktop load');
    u.context.emit('request', u.request); u.context.emit('response', u.response); u.context.emit('requestfinished', u.request);
    u.select(); await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'Selected resource load/finished cannot replace its pending native body');
    u.body.resolve(u.bytes); await navigation;
    const snapshot = u.observer.snapshot(), sample = snapshot.responsiveTransitionSamples[0];
    assert.equal(snapshot.filenameMatches, 1); assert.equal(snapshot.bodyErrors, 0);
    assert.equal(u.calls.imageRequests, 1); assert.equal(u.calls.body, 1); assert.equal(u.calls.goto.length, 1);
    assert(sample.requests[0].bodyReadEndedMs <= sample.firstNavigation.observedMs);
    assert(u.calls.goto[0].timeout > 0 && u.calls.goto[0].timeout <= budget - (u.calls.goto[0].at - started) + 5);
    assert.deepEqual(u.calls.wait, [], 'No page-global networkidle is used by the helper');
  } finally { u.observer.stop(); }
});

test('UNIT_ONLY: a cancelled selected request remains a native failure without a response or body substitute', async () => {
  const u = bannerNavigationUnit(true);
  try {
    u.frameReady.resolve(); u.decoded.resolve();
    const navigation = realBannerNavigation.navigateAfterMediaSettles(u.page, 'http://127.0.0.1:3000/unit-target', { timeout: 220, waitUntil: 'domcontentloaded' });
    await bannerUnitTick(); assert.equal(u.calls.goto.length, 0);
    u.request.failure = () => ({ errorText: 'net::ERR_ABORTED' });
    u.context.emit('request', u.request); u.context.emit('requestfailed', u.request); u.select();
    await navigation;
    const snapshot = u.observer.snapshot();
    assert.deepEqual([snapshot.responses, snapshot.requestFailed, snapshot.bodyReads, snapshot.filenameMatches], [0, 1, 0, 0]);
    assert.equal(snapshot.failures[0].classification, 'aborted');
    assert.deepEqual([u.calls.imageRequests, u.calls.body], [1, 0], 'Cancellation is retained, never retried or accepted as bytes');
  } finally { u.observer.stop(); }
});

test('UNIT_ONLY: late selected request still unfinished at the original deadline never navigates', async () => {
  const u = bannerNavigationUnit(true), budget = 60;
  try {
    u.frameReady.resolve(); u.decoded.resolve();
    const navigation = realBannerNavigation.navigateAfterMediaSettles(u.page, 'http://127.0.0.1:3000/unit-target', { timeout: budget, waitUntil: 'domcontentloaded' });
    await bannerUnitTick();
    u.context.emit('request', u.request); u.context.emit('response', u.response); u.select();
    await assert.rejects(navigation, /original navigation deadline/);
    assert.equal(u.calls.goto.length, 0); assert.equal(u.observer.snapshot().pendingBodies, 1);
    u.body.resolve(u.bytes); await bannerUnitTick();
    assert.equal(u.calls.goto.length, 0, 'Completion after timeout never restarts navigation');
  } finally { u.observer.stop(); }
});
