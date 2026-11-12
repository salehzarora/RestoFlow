import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
import { SYNTH_IDS, SYNTH_MEDIA_PATH } from './support/envelope.mjs';
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const decoders = await import('../src/source/live/decodeContentV1.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { fetchStorefrontMenu } = await import('../src/source/live/client.ts');
const origin = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const config = { url: origin, anonKey: 'SYNTHETIC_NOT_A_REAL_KEY' };
const field = 'product_original_images_v1';
const originalPath = SYNTH_MEDIA_PATH.replace('a'.repeat(64), 'b'.repeat(64));
const row = () => ({ item_id: SYNTH_IDS.burger, url: originalPath, width: 960, height: 640 });
const menu = (rows = [row()]) => ({ ...syntheticV4Envelope(), [field]: rows });
const missing = v => ({ code: 'PGRST202', message: `Could not find the function public.storefront_menu_v${v}(p_slug) in the schema cache` });

test('v10 absence is exact v9; the separate detail reference does not replace selected product media or money', () => {
  const base = syntheticV4Envelope(), raw = menu(), snapshot = structuredClone(raw);
  assert.deepEqual(decoders.decodeStorefrontMenuV10(base), decoders.decodeStorefrontMenuV9(base));
  const before = adaptStorefront(decoders.decodeStorefrontMenuV9(base), origin);
  const after = adaptStorefront(decoders.decodeStorefrontMenuV10(raw), origin);
  assert.deepEqual(raw, snapshot);
  assert.deepEqual(after.view.tenant, before.view.tenant);
  assert.deepEqual(after.view.categories, before.view.categories);
  const item = after.view.items.find(i => i.id === SYNTH_IDS.burger);
  const { detailImage, ...unchanged } = item;
  assert.deepEqual(unchanged, before.view.items.find(i => i.id === item.id));
  assert.equal(item.image, origin + SYNTH_MEDIA_PATH);
  assert.deepEqual(detailImage, { url: origin + originalPath, width: 960, height: 640 });
  assert.ok(after.view.items.filter(i => i.id !== item.id).every(i => !Object.hasOwn(i, 'detailImage')));
  assert.deepEqual(adaptStorefront(decoders.decodeStorefrontMenuV10(menu([])), origin), before);
  assert.doesNotThrow(() => decoders.decodeStorefrontMenuV10(menu([{ ...row(), url: SYNTH_MEDIA_PATH }])));
});

test('new original-image projection remains unavailable to strict v5-v9 readers', () => {
  for (const v of [5, 6, 7, 8, 9]) assert.throws(() => decoders['decodeStorefrontMenuV' + v](menu()), EnvelopeError, `v${v}`);
  const failure = { ok: false, entity: 'storefront_menu', error: 'not_found' };
  assert.deepEqual(decoders.decodeStorefrontMenuV10(failure), failure);
  assert.throws(() => decoders.decodeStorefrontMenuV10({ ...failure, [field]: [] }), EnvelopeError);
});

test('detail manifest rejects private/signed/unknown URLs, dimensions, duplicates and unserved identities', () => {
  const invalid = [
    { url: null }, { url: undefined }, { url: '' }, { url: origin + originalPath },
    { url: originalPath.replace('/public/', '/sign/') }, { url: '/storage/v1/object/menu-images/private.png' },
    { url: originalPath + '?token=private' }, { url: originalPath + '\n' },
    { width: 0 }, { height: 961 }, { width: 960.5 }, { height: '640' }, { width: Infinity },
    { item_id: SYNTH_IDS.orphan }, { item_id: '11111111-1111-4111-8111-111111111111' },
    { original_key: 'private' }, { source_generation: 'private' },
  ];
  for (const change of invalid) assert.throws(() => decoders.decodeStorefrontMenuV10(menu([{ ...row(), ...change }])), EnvelopeError, JSON.stringify(change));
  for (const rows of [null, undefined, {}, [row(), row()], Array.from({ length: 501 }, row)]) {
    assert.throws(() => decoders.decodeStorefrontMenuV10({ ...syntheticV4Envelope(), [field]: rows }), EnvelopeError);
  }
  for (const key of ['item_id', 'url', 'width', 'height']) {
    const value = row(); delete value[key];
    assert.throws(() => decoders.decodeStorefrontMenuV10(menu([value])), EnvelopeError);
  }
});

test('only exact missing v10 falls back to strict v9 with one body, public authority and shared deadline', async () => {
  const old = globalThis.fetch, calls = [];
  const responses = (...queue) => {
    calls.length = 0;
    globalThis.fetch = async (url, init) => {
      calls.push({ url, init }); assert.ok(queue.length, 'no unplanned request');
      const [status, body] = queue.shift(); return new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });
    };
  };
  try {
    responses([200, menu()]);
    assert.deepEqual((await fetchStorefrontMenu('sf-synth-a', config))[field], [row()]);
    assert.equal(calls.length, 1); assert.equal(calls[0].url, origin + '/rest/v1/rpc/storefront_menu_v10');
    for (const error of [missing(10), { code: '42883', message: 'function public.storefront_menu_v10(text) does not exist' }]) {
      responses([404, error], [200, syntheticV4Envelope()]);
      assert.deepEqual(await fetchStorefrontMenu('sf-synth-a', config), decoders.decodeStorefrontMenuV9(syntheticV4Envelope()));
      assert.deepEqual(calls.map(c => c.url), [10, 9].map(v => origin + '/rest/v1/rpc/storefront_menu_v' + v));
      assert.equal(calls[0].init, calls[1].init);
      assert.equal(calls[0].init.body, JSON.stringify({ p_slug: 'sf-synth-a' }));
      assert.equal(calls[0].init.headers.apikey, config.anonKey);
      assert.equal(calls[0].init.signal, calls[1].init.signal);
      assert.equal(calls[0].init.signal.aborted, false);
    }
    for (const [status, value] of [[404, missing(9)], [403, missing(10)], [500, missing(10)], [404, { ...missing(10), code: '42501' }], [404, '<html>missing</html>'], [200, menu([{ ...row(), width: 0 }])]]) {
      responses([status, value]); await assert.rejects(() => fetchStorefrontMenu('sf-synth-a', config)); assert.equal(calls.length, 1);
    }
    responses([404, missing(10)], [200, menu()]);
    await assert.rejects(() => fetchStorefrontMenu('sf-synth-a', config), EnvelopeError, 'v9 never silently accepts the v10-only field');
    assert.equal(calls.length, 2);
  } finally { globalThis.fetch = old; }
});
