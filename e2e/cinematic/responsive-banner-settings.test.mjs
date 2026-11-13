import test from 'node:test';
import assert from 'node:assert/strict';
import { responsiveBannerKeys, responsiveBannerFixture, legacyBannerDocument, legacyBannerMenu, responsiveBannerReady,
  dashboardImageHash, dashboardImageBytesMatch, dashboardMediaReady } from './responsive-banner-settings.mjs';
import { controlGeometry, visibleGeometry } from './control-geometry.mjs';
import { createHash } from 'node:crypto';
import { LOCAL_API } from './live-transport.mjs';
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
  const expected = { height: 540, focus: '38% 9%' };
  const current = { height: 540, focus: '38% 9%', resourceMatch: true, layoutResponsive: true, hydrated: true };
  assert.equal(responsiveBannerReady(expected, current), true);
  assert.equal(responsiveBannerReady(expected, { ...current, height: 520 }), false, 'Unchanged image URL does not admit the older saved height');
  assert.equal(responsiveBannerReady(expected, { ...current, focus: '50% 50%' }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, layoutResponsive: false }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, resourceMatch: false }), false);
  assert.equal(responsiveBannerReady(expected, { ...current, hydrated: false }), false);
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
