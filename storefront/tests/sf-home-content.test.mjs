import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticEnvelope, NOT_FOUND_ENVELOPE } from './support/envelope.mjs';

const { decodeStorefrontMenu, EnvelopeError } = await import('../src/source/live/decode.ts');
const { decodeStorefrontMenuV2 } = await import('../src/source/live/decodeHomeContent.ts');
const { adaptStorefront, liveStorefrontSource } = await import('../src/source/live/adapter.ts');
const { storefrontMenuRequest } = await import('../src/source/live/client.ts');
// Production-shaped origin is required by the existing adapter allowlist;
// every fetch in this suite is intercepted locally.
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const EMPTY = { hero_headline: null, hero_subline: null, announcement_text: null };
const envelope = (content = EMPTY, base = {}) => ({ ...syntheticEnvelope(base), home_content: { ...content } });

test('versioned response does not loosen or alter the legacy exact-key decoder', () => {
  const old = syntheticEnvelope();
  assert.equal(decodeStorefrontMenu(old).ok, true);
  assert.throws(() => decodeStorefrontMenu(envelope()), EnvelopeError);
  assert.throws(() => decodeStorefrontMenuV2(old), EnvelopeError);
  assert.deepEqual(decodeStorefrontMenuV2(NOT_FOUND_ENVELOPE), NOT_FOUND_ENVELOPE);
  assert.throws(() => decodeStorefrontMenuV2({ ...NOT_FOUND_ENVELOPE, home_content: EMPTY }), EnvelopeError);
});

test('all-null public Home content keeps the established honest fallback and optional sections absent', () => {
  const legacy = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope()), ORIGIN);
  const current = adaptStorefront(decodeStorefrontMenuV2(envelope()), ORIGIN);
  assert.deepEqual(current, legacy);
  assert.equal(current.view.modules.announcement, null);
  assert.equal(current.view.modules.promo, null);
  assert.equal(current.view.modules.story, null);
  assert.equal(current.view.modules.campaign.subline, '');
});

test('only exact nullable bounded plain-text fields cross the new boundary', () => {
  const invalid = [null, [], {}, { ...EMPTY, extra: 'private' }, { ...EMPTY, hero_headline: 1 },
    { ...EMPTY, hero_subline: false }, { ...EMPTY, announcement_text: {} },
    { ...EMPTY, hero_headline: '' }, { ...EMPTY, hero_headline: 'x'.repeat(121) },
    { ...EMPTY, hero_subline: 'x'.repeat(181) }, { ...EMPTY, announcement_text: 'x'.repeat(241) }];
  const missing = { ...EMPTY }; delete missing.hero_subline; invalid.push(missing);
  for (const value of invalid) assert.throws(() => decodeStorefrontMenuV2({ ...syntheticEnvelope(), home_content: value }), EnvelopeError);
  for (let cp = 0; cp <= 127; cp += 1) {
    if (cp > 31 && cp !== 127) continue;
    for (const key of Object.keys(EMPTY)) assert.throws(() => decodeStorefrontMenuV2(envelope({ ...EMPTY, [key]: `copy${String.fromCharCode(cp)}` })), EnvelopeError);
  }
  for (const [key, cap] of [['hero_headline', 120], ['hero_subline', 180], ['announcement_text', 240]]) {
    const text = '🍔'.repeat(cap);
    assert.equal(decodeStorefrontMenuV2(envelope({ ...EMPTY, [key]: text })).home_content[key], text);
    assert.throws(() => decodeStorefrontMenuV2(envelope({ ...EMPTY, [key]: text + 'x' })), EnvelopeError);
  }
});

test('new text cannot smuggle unknown base fields, private scope or pricing data', () => {
  for (const mutate of [
    e => ({ ...e, organization_id: 'private' }),
    e => ({ ...e, restaurant: { ...e.restaurant, owner_phone: '+000' } }),
    e => ({ ...e, home_content: { ...e.home_content, price: 1 } }),
    e => ({ ...e, items: [{ ...e.items[0], base_price_minor: 0.5 }, ...e.items.slice(1)] }),
  ]) assert.throws(() => decodeStorefrontMenuV2(mutate(envelope())), EnvelopeError);
});

test('merchant copy stays exact in Arabic, Hebrew, English and hostile-looking plain text', () => {
  for (const headline of ['أهلاً بكم', 'ברוכים הבאים', 'Welcome', '<script>alert(1)</script>', '** Stored name **']) {
    const content = { hero_headline: headline, hero_subline: 'Owner-written subtitle', announcement_text: 'Owner-written announcement' };
    const view = adaptStorefront(decodeStorefrontMenuV2(envelope(content)), ORIGIN).view;
    assert.deepEqual(view.modules.campaign, { title: headline, subline: content.hero_subline });
    assert.deepEqual(view.modules.announcement, { text: content.announcement_text });
    assert.equal(view.modules.promo, null);
    assert.equal(view.modules.story, null);
    assert.equal(view.modules.popular.ready, false, 'content editing never invents sales rankings');
  }
});

test('content changes do not change prices, tax, modifiers, media, service or order authority', () => {
  const base = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope()), ORIGIN);
  const changed = adaptStorefront(decodeStorefrontMenuV2(envelope({ hero_headline: 'Headline', hero_subline: 'Subtitle', announcement_text: 'Notice' })), ORIGIN);
  assert.deepEqual(changed.groups, base.groups);
  assert.deepEqual(changed.zones, base.zones);
  assert.equal(changed.taxRateBp, base.taxRateBp);
  assert.equal(changed.menuVersion, base.menuVersion);
  assert.deepEqual(changed.view.tenant, base.view.tenant);
  assert.deepEqual(changed.view.items, base.view.items);
  assert.deepEqual(changed.view.categories, base.view.categories);
  assert.deepEqual(changed.view.cart, base.view.cart);
});

test('independent tenant resolutions never share or persist content', () => {
  const resolve = (slug, title) => adaptStorefront(decodeStorefrontMenuV2(envelope({ ...EMPTY, hero_headline: title }, { restaurant: { slug } })), ORIGIN);
  const a = resolve('sf-synth-a', 'Kitchen A');
  const b = resolve('sf-synth-b', 'Kitchen B');
  assert.equal(a.view.modules.campaign.title, 'Kitchen A');
  assert.equal(b.view.modules.campaign.title, 'Kitchen B');
  assert.equal(resolve('sf-synth-a', null).view.modules.campaign.title, a.view.tenant.tagline);
  assert.equal(a.view.modules.campaign.title, 'Kitchen A');
});

test('one new public read, same scoped body and credentials, no fallback or hidden retry', async () => {
  const config = { url: ORIGIN, anonKey: 'sb_publishable_SYNTHETIC_not_real_00000' };
  const request = storefrontMenuRequest(config, 'sf-synth-a');
  assert.equal(request.url, `${ORIGIN}/rest/v1/rpc/storefront_menu_v3`);
  assert.equal(request.init.body, JSON.stringify({ p_slug: 'sf-synth-a' }));
  assert.equal(request.init.headers.apikey, config.anonKey);
  let calls = 0;
  const old = globalThis.fetch;
  try {
    globalThis.fetch = async () => { calls += 1; return { ok: false, status: 404 }; };
    await assert.rejects(liveStorefrontSource(config).getStorefront('sf-synth-a'), /HTTP 404/);
    assert.equal(calls, 1, 'backend-first deployment is required; errors never switch authority or retry');
  } finally { globalThis.fetch = old; }
});
