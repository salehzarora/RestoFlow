import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticEnvelope, SYNTH_IDS, NOT_FOUND_ENVELOPE } from './support/envelope.mjs';
import { defaultContentV1 } from './support/content-envelope.mjs';

const { decodeStorefrontMenu, EnvelopeError } = await import('../src/source/live/decode.ts');
const { decodeStorefrontMenuV2 } = await import('../src/source/live/decodeHomeContent.ts');
const { decodeStorefrontMenuV3 } = await import('../src/source/live/decodeFeaturedItems.ts');
const { adaptStorefront, liveStorefrontSource } = await import('../src/source/live/adapter.ts');
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const HOME = { hero_headline: null, hero_subline: null, announcement_text: null };
const v2 = (over = {}) => ({ ...syntheticEnvelope(over), home_content: { ...HOME } });
const v3 = (ids = [], over = {}) => ({ ...v2(over), featured_item_ids: ids });

test('v3 is a separate strict boundary; legacy and v2 contracts remain unchanged', () => {
  assert.equal(decodeStorefrontMenu(syntheticEnvelope()).ok, true);
  assert.equal(decodeStorefrontMenuV2(v2()).ok, true);
  assert.throws(() => decodeStorefrontMenuV2(v3()), EnvelopeError);
  assert.throws(() => decodeStorefrontMenu(v3()), EnvelopeError);
  assert.throws(() => decodeStorefrontMenuV3(v2()), EnvelopeError);
  assert.deepEqual(decodeStorefrontMenuV3(NOT_FOUND_ENVELOPE), NOT_FOUND_ENVELOPE);
  assert.throws(() => decodeStorefrontMenuV3({ ...NOT_FOUND_ENVELOPE, featured_item_ids: [] }), EnvelopeError);
});

test('empty selection preserves the complete established view and canonical order contract', () => {
  const old = adaptStorefront(decodeStorefrontMenuV2(v2()), ORIGIN);
  const current = adaptStorefront(decodeStorefrontMenuV3(v3()), ORIGIN);
  assert.deepEqual(current, old);
  assert.ok(current.view.items.every(item => !item.featured));
});

test('only served products become featured without copying prices/options/media or ranking', () => {
  const old = adaptStorefront(decodeStorefrontMenuV2(v2()), ORIGIN);
  const current = adaptStorefront(decodeStorefrontMenuV3(v3([SYNTH_IDS.cola, SYNTH_IDS.burger])), ORIGIN);
  assert.deepEqual(current.view.items.map(item => item.id), old.view.items.map(item => item.id));
  assert.deepEqual(current.view.items.map(({ featured, ...item }) => item), old.view.items.map(({ featured, ...item }) => item));
  assert.deepEqual(current.groups, old.groups);
  assert.deepEqual(current.view.tenant, old.view.tenant);
  assert.deepEqual(current.view.categories, old.view.categories);
  assert.deepEqual(current.view.modules, old.view.modules);
  assert.equal(current.view.modules.popular.ready, false);
  assert.equal(current.view.items.find(item => item.id === SYNTH_IDS.cola).featured, true, 'image-less products remain eligible');
});

test('sold-out selection retains the existing sold-out state and may not reopen a product', () => {
  const result = adaptStorefront(decodeStorefrontMenuV3(v3([SYNTH_IDS.soldOut])), ORIGIN);
  const item = result.view.items.find(item => item.id === SYNTH_IDS.soldOut);
  assert.equal(item.featured, true);
  assert.equal(item.soldOut, true);
});

test('nonserved/private IDs are rejected even when valid UUIDs; UI omission is insufficient', () => {
  for (const id of ['11111111-2222-3333-4444-555555555555', SYNTH_IDS.catFood, SYNTH_IDS.weight]) {
    assert.throws(() => decodeStorefrontMenuV3(v3([id])), EnvelopeError);
  }
});

test('wrong types, nested/null/duplicate/alias/injection values cannot cross the boundary', () => {
  const invalid = [null, {}, '', false, 1, [null], [{}], [[]], [true], [1],
    [SYNTH_IDS.burger, SYNTH_IDS.burger], [SYNTH_IDS.burger.toUpperCase()],
    [`${SYNTH_IDS.burger}\n`], [`${SYNTH_IDS.burger}\r`], [` ${SYNTH_IDS.burger}`],
    ['javascript:alert(1)'], ['<img src=x>'], [SYNTH_IDS.burger.replaceAll('-', '')]];
  for (const ids of invalid) assert.throws(() => decodeStorefrontMenuV3(v3(ids)), EnvelopeError);
  assert.throws(() => decodeStorefrontMenuV3({ ...v3(), private_ids: [] }), EnvelopeError);
});

test('maximum twelve is accepted and thirteen fails without truncation', () => {
  const items = Array.from({ length: 13 }, (_, i) => ({ ...syntheticEnvelope().items[1], id: `00000000-0000-0000-0000-${String(i + 1).padStart(12, '0')}` }));
  assert.equal(decodeStorefrontMenuV3(v3(items.slice(0, 12).map(item => item.id), { items })).featured_item_ids.length, 12);
  assert.throws(() => decodeStorefrontMenuV3(v3(items.map(item => item.id), { items })), EnvelopeError);
});

test('independent tenant reads do not share mutable featured state', () => {
  const a = adaptStorefront(decodeStorefrontMenuV3(v3([SYNTH_IDS.burger], { restaurant: { slug: 'sf-synth-a' } })), ORIGIN);
  const b = adaptStorefront(decodeStorefrontMenuV3(v3([], { restaurant: { slug: 'sf-synth-b' } })), ORIGIN);
  assert.equal(a.view.items.find(item => item.id === SYNTH_IDS.burger).featured, true);
  assert.ok(b.view.items.every(item => !item.featured));
});

test('live source requires v4 once, retaining featured selection with no old-reader fallback', async () => {
  const previous = globalThis.fetch;
  const calls = [];
  const source = liveStorefrontSource({ url: ORIGIN, anonKey: 'sb_publishable_SYNTHETIC_not_real_00000' });
  try {
    globalThis.fetch = async (url, init) => { calls.push({ url, init }); return { ok: true, json: async () => ({ ...v3([SYNTH_IDS.burger]), content_v1: defaultContentV1() }) }; };
    const result = await source.getStorefront('sf-synth-a');
    assert.equal(result.view.items.find(item => item.id === SYNTH_IDS.burger).featured, true);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, `${ORIGIN}/rest/v1/rpc/storefront_menu_v4`);
    assert.equal(calls[0].init.body, JSON.stringify({ p_slug: 'sf-synth-a' }));
    globalThis.fetch = async () => { calls.push('legacy'); return { ok: true, json: async () => v2() }; };
    await assert.rejects(source.getStorefront('sf-synth-a'), EnvelopeError);
    assert.equal(calls.length, 2, 'an old backend never triggers a retry to a different authority');
  } finally { globalThis.fetch = previous; }
});
