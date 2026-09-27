// STOREFRONT-PUBLISH-001 — engine poisoning with the REAL codecs (its own test process:
// it deliberately leaves this process's shared deriver poisoned).
//
// The PNG decoder is a wasm-bindgen module (a fresh instance per call since D-041,
// STOREFRONT-MEDIA-MEMORY-001). A Rust error comes out of it as a thrown JS Error WITHOUT
// unwinding: the Rust heap allocations and the shadow-stack frame of the failed call are
// leaked (measured in the Q031 remediation with the former one-instance-per-worker design:
// ~700 failing decodes of a 600 x 300 image grew the instance to 700 MB and then made every
// later decode trap). The recipe still treats ANY exception out of that module as poisoning
// the engine (kept by D-041), and the STEP that threw decides the answer
// (STOREFRONT-MEDIA-ENGINE-FAILURE-001 / D-042): an exception out of the decode OPERATION
// keeps the source's deterministic typed refusal (decode_failed; P1), a failure to CREATE or
// INITIALISE the call's fresh instance — the source was never read — is the retryable
// 503 engine_unavailable (P2); in both cases the handler retires the worker and the worker
// never derives again.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../lib/handler.mjs';
import { createDeriver } from '../lib/recipe.mjs';
import { deriver, readWasm } from './engine.mjs';
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

test('P2. STOREFRONT-MEDIA-ENGINE-FAILURE-001 (D-042, I): a failure to create the call\'s fresh PNG decoder instance (the REAL initSync path: its WebAssembly.Instance cannot be constructed) answers exactly the contracted 503 engine_unavailable, never a 422, with nothing staged; the engine is poisoned, the worker retires, and the next request is refused before its body is read', async () => {
  // a separate real engine (the shared one is poisoned by P1); built while every instantiation works
  const wasm = await readWasm();
  const keyOf = new Map(Object.entries(wasm).map(([k, v]) => [v, k]));
  const { Instance, compile } = WebAssembly;
  const keys = new Map();
  let armed = false, attempts = 0;
  WebAssembly.compile = async (bytes) => { const m = await compile(bytes); keys.set(m, keyOf.get(bytes) ?? 'unknown'); return m; };
  WebAssembly.Instance = new Proxy(Instance, {
    construct(t, a, n) {
      if (armed && keys.get(a[0]) === 'png') { attempts++; throw new RangeError('WebAssembly.Instance(): Out of memory: Cannot allocate Wasm memory for new instance'); }
      return Reflect.construct(t, a, n);
    },
  });
  try {
    const d = await createDeriver(wasm);
    assert.equal(d.poisoned, false);
    const fake = fakeSupabase({ privateObjects: new Map([[`restaurant-logos/${LOGO_KEY}`, await fixture('logo_opaque_rgb_1200x600')]]) });
    let retired = 0;
    const logs = [];
    const handle = createHandler({ supabaseUrl: URL_BASE, anonKey: ANON, engine: async () => d, fetchImpl: fake.fetchImpl, retireWorker: () => { retired++; }, logError: (m) => logs.push(m) });
    armed = true;
    const res = await handle(post());
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { ok: false, status: 'engine_unavailable', retryable: true }, 'exactly the contract body: no code, no uncertain');
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.equal(res.headers.get('access-control-allow-origin'), '*');
    assert.equal(res.headers.get('access-control-allow-methods'), 'POST, OPTIONS');
    assert.deepEqual(logs, [], 'no new log line (D-042 point 5): the catch-all is never reached');
    assert.equal(attempts, 1, 'the PNG instance construction failed once');
    assert.equal(retired, 1, 'the worker retires');
    assert.equal(d.poisoned, true, 'the engine is poisoned');
    assert.equal(fake.media.size, 0, 'nothing was staged');
    const paths = fake.calls.map((c) => c.path);
    assert.ok(!paths.some((p) => /stage_storefront_media|finalize_storefront_media|\/storage\/v1\/object\/storefront-media/.test(p)), 'no stage, upload or finalize call');
    // the next request on this worker: 503 before its body is read (bodyUsed stays false) and before the media-type
    // guard (a text/plain body would otherwise be 415), without any upstream or engine work
    const before = fake.calls.length;
    const next = new Request('http://functions.test/storefront-media-publish', {
      method: 'POST', headers: { 'content-type': 'text/plain', authorization: `Bearer ${TOKEN}` }, body: JSON.stringify(body),
    });
    const again = await handle(next);
    assert.equal(again.status, 503, 'answered before the 415 media-type guard');
    assert.deepEqual(await again.json(), { ok: false, status: 'engine_unavailable', retryable: true });
    assert.equal(next.bodyUsed, false, 'the body was never read');
    assert.equal(fake.calls.length, before, 'no upstream call');
    assert.equal(attempts, 1, 'the engine was not reached again');
    assert.equal(retired, 2);
    assert.deepEqual(logs, [], 'still no log line');
  } finally {
    Object.assign(WebAssembly, { Instance, compile });
  }
});
