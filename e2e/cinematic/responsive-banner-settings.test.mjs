import test from 'node:test';
import assert from 'node:assert/strict';
import { responsiveBannerKeys, responsiveBannerFixture, legacyBannerDocument, legacyBannerMenu, responsiveBannerReady } from './responsive-banner-settings.mjs';
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
