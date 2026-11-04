import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
import { SYNTH_IDS, SYNTH_MEDIA_PATH } from './support/envelope.mjs';
const { decodeStorefrontMenuV5, decodeStorefrontMenuV6 } = await import('../src/source/live/decodeContentV1.ts');
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const row = () => ({ item_id: SYNTH_IDS.burger, w480_url: SYNTH_MEDIA_PATH,
  w960_url: SYNTH_MEDIA_PATH.replace(/a{64}/, 'b'.repeat(64)), width480: 480, height480: 320, width960: 960, height960: 640 });
const menu = () => {
  const raw = syntheticV4Envelope();
  raw.content_v1.appearance = { text_color: null, button_text_color: null, scene_preset: 'reference_dark' };
  raw.product_images_v1 = [row()];
  return raw;
};

test('v6 accepts legacy documents and carries explicit scene; v5 remains strict', () => {
  assert.deepEqual(decodeStorefrontMenuV6(syntheticV4Envelope()), decodeStorefrontMenuV5(syntheticV4Envelope()));
  for (const scene of ['reference_dark', null]) {
    const raw = menu();
    raw.content_v1.appearance.scene_preset = scene;
    const decoded = decodeStorefrontMenuV6(raw);
    assert.equal(decoded.content_v1.appearance.scene_preset, scene);
    assert.equal(adaptStorefront(decoded, ORIGIN).view.tenant.scenePreset, scene);
    assert.throws(() => decodeStorefrontMenuV5(raw), EnvelopeError);
    delete raw.product_images_v1;
    assert.throws(() => decodeStorefrontMenuV5(raw), EnvelopeError);
    delete raw.content_v1.appearance.scene_preset;
    assert.deepEqual(decodeStorefrontMenuV5(raw), decodeStorefrontMenuV6(raw));
  }
  for (const scene of ['', 'dark', 'reference-dark', {}, [], 1, false, undefined]) {
    const raw = menu(); raw.content_v1.appearance.scene_preset = scene;
    assert.throws(() => decodeStorefrontMenuV6(raw), EnvelopeError);
  }
});

test('v6 responsive images stay bounded, strictly shaped and tied to the served product', () => {
  const baseline = menu();
  for (const mutation of [
    raw => { raw.product_images_v1 = null; },
    raw => { raw.product_images_v1 = Array.from({ length: 501 }, row); },
    raw => { raw.product_images_v1.push(row()); },
    raw => { raw.product_images_v1[0].item_id = '00000000-0000-0000-0000-000000000001'; },
    raw => { raw.product_images_v1[0].width480 = 0; },
    raw => { raw.product_images_v1[0].height480 = 481; },
    raw => { raw.product_images_v1[0].width960 = 961; },
    raw => { raw.product_images_v1[0].height960 = 319; },
    raw => { raw.product_images_v1[0].width960 = 2.5; },
    raw => { raw.product_images_v1[0].w480_url = row().w960_url; },
    raw => { raw.product_images_v1[0].w960_url = 'https://example.invalid/private.png'; },
    raw => { raw.product_images_v1[0].source_key = 'private-original'; },
  ]) {
    const raw = structuredClone(baseline); mutation(raw);
    assert.throws(() => decodeStorefrontMenuV6(raw), EnvelopeError);
  }
  const failure = { ok: false, error: 'not_found', entity: 'storefront_menu' };
  assert.deepEqual(decodeStorefrontMenuV6(failure), failure);
  assert.throws(() => decodeStorefrontMenuV6({ ...failure, product_images_v1: [] }), EnvelopeError);
});

test('adapter maps validated variants without touching order data; small sources do not duplicate width descriptors', () => {
  const raw = menu();
  const before = adaptStorefront(decodeStorefrontMenuV6({ ...raw, product_images_v1: [] }), ORIGIN);
  const after = adaptStorefront(decodeStorefrontMenuV6(raw), ORIGIN);
  const item = after.view.items.find(item => item.id === SYNTH_IDS.burger);
  assert.deepEqual(item.imageVariants, [
    { url: `${ORIGIN}${row().w480_url}`, width: 480, height: 320 },
    { url: `${ORIGIN}${row().w960_url}`, width: 960, height: 640 },
  ]);
  assert.deepEqual(after.view.items.map(({ imageVariants, ...item }) => item), before.view.items);
  for (const key of ['groups', 'zones', 'taxRateBp', 'menuVersion']) assert.deepEqual(after[key], before[key]);
  raw.product_images_v1[0] = { ...row(), width480: 120, height480: 80, width960: 120, height960: 80 };
  assert.equal(adaptStorefront(decodeStorefrontMenuV6(raw), ORIGIN).view.items[0].imageVariants.length, 1);
});

test('selecting product presentation preserves the independent Welcome and menu background sources', () => {
  const raw = menu();
  const welcome = SYNTH_MEDIA_PATH.replace(/a{64}/, 'c'.repeat(64));
  const background = SYNTH_MEDIA_PATH.replace(/a{64}/, 'd'.repeat(64));
  raw.restaurant.hero_url = welcome;
  raw.content_v1.hero = { ...raw.content_v1.hero, mode: 'item', item_id: SYNTH_IDS.burger };
  raw.content_v1.appearance.menu_background_url = background;
  const original = adaptStorefront(decodeStorefrontMenuV6(raw), ORIGIN);
  const cutout = SYNTH_MEDIA_PATH.replace(/a{64}/, 'e'.repeat(64));
  raw.items.find(item => item.id === SYNTH_IDS.burger).image_url = cutout;
  raw.product_images_v1[0].w480_url = cutout;
  const selected = adaptStorefront(decodeStorefrontMenuV6(raw), ORIGIN);
  assert.equal(selected.view.items.find(item => item.id === SYNTH_IDS.burger).image, ORIGIN + cutout);
  assert.equal(selected.view.tenant.heroImage, ORIGIN + welcome);
  assert.equal(selected.view.tenant.menuBackgroundImage, ORIGIN + background);
  assert.deepEqual(selected.view.tenant, original.view.tenant);
  assert.deepEqual(selected.view.modules.campaign, original.view.modules.campaign);
});
