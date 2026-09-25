// STOREFRONT-PUBLISH-001 — engine poisoning with the REAL codecs (its own test process:
// it deliberately leaves this process's PNG module untrusted).
//
// The PNG decoder is a wasm-bindgen module with ONE instance per worker. A Rust error
// comes out of it as a thrown JS Error WITHOUT unwinding: the Rust heap allocations and
// the shadow-stack frame of the failed call are leaked (measured in the Q031 remediation:
// ~700 failing decodes of a 600 x 300 image grew the instance to 700 MB and then made
// every later decode trap). The recipe therefore treats ANY exception out of that module
// as poisoning the engine: the source keeps its deterministic typed refusal
// (decode_failed), the handler retires the worker, and the worker never derives again.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../lib/handler.mjs';
import { deriver } from './engine.mjs';
import { fixture } from './fixtures.mjs';
import { ANON, TOKEN, URL_BASE, fakeSupabase } from './fake_supabase.mjs';

const ORG = '0b5e0000-0000-4000-8000-000000000001';
const RESTO = '0b5e0000-0000-4000-8000-000000000002';
const LOGO_KEY = `${ORG}/${RESTO}/logo/0b5e0000-0000-4000-8000-0000000000a1.png`;
const body = { request_id: '0b5e0000-0000-4000-8000-0000000000ff', organization_id: ORG, restaurant_id: RESTO, slot: 'logo', variant: 'w480',
  source_bucket: 'restaurant-logos', source_key: LOGO_KEY, rung: 0 };
const post = () => new Request('http://functions.test/storefront-media-publish', {
  method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${TOKEN}` }, body: JSON.stringify(body),
});

test('P1. a PNG decoder exception: the source gets decode_failed (422), the engine is poisoned, the worker retires, later requests never reach the engine', async () => {
  const d = await deriver();
  assert.equal(d.poisoned, false);
  // the good source derives before the failure (control)
  assert.equal((await d.derive(await fixture('logo_opaque_rgb_1200x600'), { variant: 'w480', source: 'restaurant-logos', rung: 0 })).status, 'derived');

  const fake = fakeSupabase({ privateObjects: new Map([[`restaurant-logos/${LOGO_KEY}`, await fixture('bad_png_filter_type')]]) });
  let retired = 0;
  const handle = createHandler({ supabaseUrl: URL_BASE, anonKey: ANON, engine: deriver, fetchImpl: fake.fetchImpl, retireWorker: () => { retired++; } });
  const res = await handle(post());
  assert.equal(res.status, 422);
  assert.deepEqual(await res.json(), { ok: false, status: 'refused', code: 'decode_failed' });
  assert.equal(retired, 1, 'the untrusted engine retires the worker');
  assert.equal(d.poisoned, true);
  assert.equal(fake.media.size, 0, 'nothing was staged');

  // the poisoned engine refuses even a good source
  await assert.rejects(d.derive(await fixture('logo_opaque_rgb_1200x600'), { variant: 'w480', source: 'restaurant-logos', rung: 0 }),
    (e) => e.code === 'engine_unavailable');
  // and the handler answers every later request with a retryable 503 without any upstream call
  const before = fake.calls.length;
  const again = await handle(post());
  assert.equal(again.status, 503);
  assert.deepEqual(await again.json(), { ok: false, status: 'engine_unavailable', retryable: true });
  assert.equal(fake.calls.length, before);
  assert.equal(retired, 2);
});
