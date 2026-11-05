// Product endpoint boundary tests with the real c4 decoder/encoder. Database
// authority, generations and atomic selection are independently covered by pgTAP.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../lib/handler.mjs';
import { validateRequest } from '../lib/validate.mjs';
import { deriver } from './engine.mjs';
import { fixture } from './fixtures.mjs';
import { ANON, TOKEN, URL_BASE, fakeSupabase } from './fake_supabase.mjs';

const org = '0b5e0000-0000-4000-8000-000000000001';
const restaurant = '0b5e0000-0000-4000-8000-000000000002';
const derivative = '0b5e0000-0000-4000-8000-000000000003';
const request = '0b5e0000-0000-4000-8000-000000000004';
const source = `${org}/${restaurant}/global/menu_item/${derivative}/${request}.png`;
const snapshot = { storage_object_id: derivative, storage_version: '1', storage_updated_at: '2026-11-04T00:00:00Z' };
const body = (extra = {}) => ({ request_id: request, organization_id: org, restaurant_id: restaurant,
  slot: 'product', variant: 'w480', source_bucket: 'menu-images', source_key: source, rung: 0,
  product_derivative_id: derivative, ...extra });
const json = data => new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json' } });

async function setup({ canManage = true, sourceResult, stageResult, finalizeResult } = {}) {
  const original = await fixture('logo_alpha_2000x1000');
  const fake = fakeSupabase({ canManage, privateObjects: new Map([[`menu-images/${source}`, original]]) });
  const calls = [];
  let engines = 0;
  const handle = createHandler({ supabaseUrl: URL_BASE, anonKey: ANON,
    engine: async () => { engines++; return deriver(); }, retireWorker() {},
    fetchImpl: async (url, init) => {
      const path = new URL(url).pathname;
      const name = path.split('/').at(-1);
      const p = path.startsWith('/rest/v1/rpc/') ? JSON.parse(init.body) : null;
      calls.push({ path, p });
      assert.equal(init.headers.authorization, `Bearer ${TOKEN}`);
      assert.equal(init.headers.apikey, ANON);
      if (name === 'get_storefront_product_source_v1') {
        assert.deepEqual(p, { p_organization_id: org, p_restaurant_id: restaurant, p_derivative_id: derivative });
        return json(sourceResult ?? { ok: true, source_key: source, source_snapshot: snapshot });
      }
      if (name === 'stage_storefront_product_media_v1') {
        assert.equal(p.p_derivative_id, derivative);
        assert.deepEqual(p.p_source_snapshot, snapshot);
        assert.equal(p.p_source_key, source);
        assert.equal('p_source_bucket' in p, false);
        const objectKey = `${'a'.repeat(32)}/${p.p_content_hash}.webp`;
        const row = { id: p.p_variant, object_key: objectKey };
        fake.media.set(row.id, row);
        return json({ ok: true, media_id: row.id, object_key: objectKey, source_bucket: 'menu-images',
          source_key: source, variant: p.p_variant, source_mismatch: false, ...(stageResult ?? {}) });
      }
      if (name === 'finalize_storefront_product_media_v1') {
        const row = fake.media.get(p.p_media_id);
        assert.ok(fake.objects.has(row.object_key), 'publication cannot finalize before upload');
        return json({ ok: true, media_id: row.id, object_key: row.object_key, state: 'published', ...(finalizeResult ?? {}) });
      }
      return fake.fetchImpl(url, init);
    },
  });
  return { fake, calls, engines: () => engines, async run(extra = {}) {
    const response = await handle(new Request('http://function.test/publish', { method: 'POST',
      headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify(body(extra)) }));
    return { status: response.status, ...(await response.json()) };
  } };
}

test('product request adds one exact identifier; old slots keep their strict shapes and caps', () => {
  for (const variant of ['w480', 'w960']) {
    const result = validateRequest(body({ variant }));
    assert.equal(result.ok, true);
    assert.equal(result.value.productDerivativeId, derivative);
    assert.equal(result.value.sourceMaxBytes, 5 * 1024 * 1024);
  }
  const absent = body(); delete absent.product_derivative_id;
  assert.equal(validateRequest(absent).field, 'product_derivative_id');
  for (const value of ['', null, derivative.toUpperCase(), 'constructor', {}, `${derivative} `]) {
    assert.equal(validateRequest(body({ product_derivative_id: value })).ok, false);
  }
  for (const extra of [{ slot: 'item' }, { source_bucket: 'restaurant-logos' }, { variant: 'w1920' },
    { source_snapshot: snapshot }, { source_key: source.replace(org, derivative) }]) {
    assert.equal(validateRequest(body(extra)).ok, false);
  }
});

test('both product sizes use new source/stage/finalize RPCs, c4 directly from the same private input', async () => {
  const s = await setup();
  for (const [variant, width, height] of [['w480', 480, 240], ['w960', 960, 480]]) {
    const result = await s.run({ variant });
    assert.equal(result.status, 'published');
    assert.equal(result.recipe, 'storefront-media-c4');
    assert.equal(result.media.width, width);
    assert.equal(result.media.height, height);
    assert.ok(result.media.bytes <= 524288);
  }
  assert.equal(s.engines(), 2);
  assert.equal(s.calls.filter(c => c.path === `/storage/v1/object/authenticated/menu-images/${source}`).length, 2);
  assert.ok(!s.calls.some(c => /rpc\/(?:stage_storefront_media|finalize_storefront_media|select_storefront_product)/.test(c.path)),
    'publisher never changes product selection or calls the legacy finalizer');
  assert.ok([...s.fake.objects.values()].every(o => o.upsert === 'false'));
});

test('product manager preflight precedes the generation read, private bytes and engine', async () => {
  const s = await setup({ canManage: false });
  assert.equal((await s.run()).status, 'permission_denied');
  assert.equal(s.calls.length, 2);
  assert.equal(s.engines(), 0);
});

test('unregistered, stale or mismatched candidate cannot reach private download', async () => {
  for (const sourceResult of [{ ok: false, error: 'source_stale' },
    { ok: true, source_key: source.replace(request, derivative), source_snapshot: snapshot },
    { ok: true, source_key: source, source_snapshot: { ...snapshot, injected: true } }]) {
    const s = await setup({ sourceResult });
    assert.notEqual((await s.run()).status, 'published');
    assert.ok(!s.calls.some(c => c.path.startsWith('/storage/')));
    assert.equal(s.engines(), 0);
  }
});

test('changed generation and association at stage prevent public bytes or finalization', async () => {
  for (const stageResult of [{ ok: false, error: 'source_stale' }, { source_key: source.replace(request, derivative) },
    { source_mismatch: true }, { variant: 'w960' }]) {
    const s = await setup({ stageResult });
    assert.notEqual((await s.run()).status, 'published');
    assert.equal(s.fake.objects.size, 0);
    assert.ok(!s.calls.some(c => c.path.endsWith('/finalize_storefront_product_media_v1')));
  }
});

test('finalize stale generation or wrong returned identity never reports publication success', async () => {
  for (const finalizeResult of [{ ok: false, error: 'source_stale' }, { media_id: 'other' },
    { object_key: `${'b'.repeat(32)}/${'c'.repeat(64)}.webp` }, { state: 'staged' }]) {
    const s = await setup({ finalizeResult });
    assert.notEqual((await s.run()).status, 'published');
  }
});

test('a replay reads identical content-addressed bytes instead of overwriting', async () => {
  const s = await setup();
  const a = await s.run();
  const b = await s.run();
  assert.equal(a.status, 'published');
  assert.equal(b.status, 'published');
  assert.equal(a.media.content_hash, b.media.content_hash);
  assert.equal(s.fake.uploads.created, 1);
  assert.equal(s.fake.uploads.exists, 0);
});
