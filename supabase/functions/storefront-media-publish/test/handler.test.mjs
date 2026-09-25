// STOREFRONT-PUBLISH-001 — test group B (function half): the request workflow of
// storefront-media-publish against a test double of Auth / PostgREST / Storage
// (fake_supabase.mjs) and the REAL pinned engine (recipe storefront-media-c4).
//
// Proves: the caller-JWT-only contract (every upstream call carries the caller's
// token and the anon key, nothing else), only a signed-in non-anonymous user
// (SEC-1), duplicate keys refused (SEC-4), validation before any object lookup,
// the authority preflight before any download, typed statuses, the ladder, no
// private bytes or worker state in any response, and RECOVERY: a request killed
// at any boundary (before/after stage, upload, finalize) is retried with the
// same request_id to exactly one row, one object and one publication — never an
// overwrite, never a delete. Every typed status mapping of the handler has a
// case here (TNV-7), and so does each defence-in-depth branch (TNV-4, TNV-8).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createHandler } from '../lib/handler.mjs';
import { DerivationError } from '../lib/recipe.mjs';
import { derivedRequestId } from '../lib/ids.mjs';
import { deriver } from './engine.mjs';
import { fixture } from './fixtures.mjs';
import { ANON, TOKEN, URL_BASE, fakeSupabase } from './fake_supabase.mjs';

const ORG = '0b5e0000-0000-4000-8000-000000000001';
const RESTO = '0b5e0000-0000-4000-8000-000000000002';
const LOGO_KEY = `${ORG}/${RESTO}/logo/0b5e0000-0000-4000-8000-0000000000a1.png`;
const MENU_KEY = `${ORG}/${RESTO}/global/menu_item/0b5e0000-0000-4000-8000-0000000000b1/0b5e0000-0000-4000-8000-0000000000c1.png`;
const REQ = '0b5e0000-0000-4000-8000-0000000000ff';

// The c4 goldens of the two sources these tests publish (test/recipe.test.mjs pins them too).
const LOGO_W480 = { hash: 'fa51ede3e3fe1100cd686d36dfe18036da5be3504e576f2673bbf0194549666e', width: 480, height: 240, bytes: 2526 };
const BAND_Q74_W960 = '6b922ff452ce3eb9947d5f137c76dea1181103d56ee069952a6975fb7d6489f2';

async function setup({ canManage = true, logo = 'logo_opaque_rgb_1200x600', hero = null, engine = deriver, user = null } = {}) {
  const privateObjects = new Map();
  privateObjects.set(`restaurant-logos/${LOGO_KEY}`, await fixture(logo));
  if (hero) privateObjects.set(`menu-images/${MENU_KEY}`, await fixture(hero));
  const fake = fakeSupabase({ canManage, privateObjects, user });
  const retired = { n: 0 };
  const logs = [];
  const handle = createHandler({
    supabaseUrl: URL_BASE, anonKey: ANON, engine, fetchImpl: fake.fetchImpl, upstreamTimeoutMs: 2000,
    retireWorker: () => { retired.n++; }, logError: (m) => logs.push(m),
  });
  return { fake, handle, retired, logs };
}

const body = (over = {}) => ({
  request_id: REQ, organization_id: ORG, restaurant_id: RESTO, slot: 'logo', variant: 'w480',
  source_bucket: 'restaurant-logos', source_key: LOGO_KEY, rung: 0, ...over,
});
function post(b, { token = TOKEN, contentType = 'application/json; charset=utf-8', method = 'POST', raw = null } = {}) {
  const headers = { 'content-type': contentType };
  if (token !== null) headers.authorization = `Bearer ${token}`;
  return new Request('http://functions.test/storefront-media-publish', { method, headers, body: method === 'POST' ? (raw ?? JSON.stringify(b)) : undefined });
}
async function call(handle, req) {
  const res = await handle(req);
  const text = await res.text();
  return { status: res.status, headers: res.headers, json: text ? JSON.parse(text) : null, text };
}

test('F1. transport guards: OPTIONS (CORS), method, media type, body cap, JSON', async () => {
  const { handle, fake } = await setup();
  const pre = await handle(new Request('http://functions.test/x', { method: 'OPTIONS' }));
  assert.equal(pre.status, 204);
  assert.match(pre.headers.get('access-control-allow-headers'), /authorization/);
  assert.equal((await call(handle, post(null, { method: 'GET' }))).json.status, 'method_not_allowed');
  assert.equal((await call(handle, post(body(), { contentType: 'text/plain' }))).status, 415);
  const big = await call(handle, post(null, { raw: JSON.stringify({ ...body(), pad: 'x'.repeat(5000) }) }));
  assert.equal(big.status, 413);
  assert.equal((await call(handle, post(null, { raw: '{not json' }))).json.reason, 'json');
  assert.equal(fake.calls.length, 0, 'none of these reached an upstream service');
});

test('F2. authentication comes first: missing / malformed / rejected tokens are 401 before any other upstream call', async () => {
  const { handle, fake } = await setup();
  assert.equal((await call(handle, post(body(), { token: null }))).status, 401);
  assert.equal((await call(handle, post(body(), { token: 'not-a-jwt' }))).status, 401);
  assert.equal(fake.calls.length, 0);
  const r = await call(handle, post(body(), { token: 'other-header.other-payload.other-signature' }));
  assert.equal(r.status, 401);
  assert.deepEqual(fake.calls.map((c) => c.path), ['/auth/v1/user'], 'only GoTrue was asked');
});

test('F3. validation happens after authentication and BEFORE any object lookup (prototype names included)', async () => {
  const { handle, fake } = await setup();
  for (const [field, value] of [['variant', 'constructor'], ['variant', '__proto__'], ['source_bucket', 'toString'], ['slot', 'valueOf'],
    ['slot', 'prototype'], ['variant', 'W480'], ['source_bucket', 'storefront-media'], ['rung', 5], ['source_key', '../x']]) {
    const r = await call(handle, post(body({ [field]: value })));
    assert.equal(r.status, 400, `${field}=${value}`);
    assert.equal(r.json.status, 'invalid_request');
    assert.equal(r.json.field, field);
  }
  const extra = await call(handle, post(null, { raw: JSON.stringify(body()).replace('{', '{"__proto__":{"slot":"hero"},') }));
  assert.equal(extra.json.field, '__proto__');
  assert.ok(fake.calls.every((c) => c.path === '/auth/v1/user'), 'nothing but authentication ran');
});

test('F4. the authority preflight refuses a non-manager before any download or engine work', async () => {
  let engineCalls = 0;
  const { handle, fake } = await setup({ canManage: false, engine: async () => { engineCalls++; return deriver(); } });
  const r = await call(handle, post(body()));
  assert.equal(r.status, 403);
  assert.equal(r.json.status, 'permission_denied');
  assert.deepEqual(fake.calls.map((c) => c.path), ['/auth/v1/user', '/rest/v1/rpc/list_storefront_media']);
  assert.equal(engineCalls, 0);
});

test('F5. the happy path publishes as the caller: derived keys, x-upsert false, image/webp, no bytes in the response', async () => {
  const { handle, fake } = await setup();
  const r = await call(handle, post(body()));
  assert.equal(r.status, 200, r.text);
  assert.equal(r.json.status, 'published');
  assert.equal(r.json.recipe, 'storefront-media-c4');
  assert.equal(r.json.rung, 0);
  assert.equal(r.json.media.content_hash, LOGO_W480.hash, 'the c4 golden of this source');
  assert.equal(`${r.json.media.width}x${r.json.media.height}`, '480x240');
  assert.equal(r.json.media.bytes, LOGO_W480.bytes);
  assert.deepEqual([r.json.media.variant, r.json.media.source_bucket, r.json.media.source_key, r.json.media.state], ['w480', 'restaurant-logos', LOGO_KEY, 'published'], 'the media block describes the registered row');
  assert.deepEqual(Object.keys(r.json).sort(), ['already_published', 'idempotent_replay', 'media', 'ok', 'profile_version', 'recipe', 'replaced_media_id', 'republished', 'rung', 'source_mismatch', 'status']);
  assert.ok(!/base64|derivative|worker|spent|budget/i.test(r.text), 'no bytes and no isolate state in the response');
  // every upstream call as the caller, nothing privileged
  for (const c of fake.calls) {
    assert.equal(c.headers.authorization, `Bearer ${TOKEN}`, c.path);
    assert.equal(c.headers.apikey, ANON, c.path);
    assert.ok(['GET', 'POST'].includes(c.method.toUpperCase()), `${c.method} ${c.path}`);
  }
  const label = (c) => (!c.path.startsWith('/storage/v1/object/') ? c.path
    : c.path.startsWith('/storage/v1/object/authenticated/storefront-media/') ? 'GET public (read first)'
      : c.path.startsWith('/storage/v1/object/authenticated/') ? 'GET private' : 'POST public');
  assert.deepEqual(fake.calls.map(label),
    ['/auth/v1/user', '/rest/v1/rpc/list_storefront_media', 'GET private', '/rest/v1/rpc/stage_storefront_media', 'GET public (read first)', 'POST public', '/rest/v1/rpc/finalize_storefront_media']);
  const up = fake.calls.find((c) => c.method === 'POST' && c.path.startsWith('/storage/v1/object/storefront-media/'));
  assert.equal(up.headers['x-upsert'], 'false');
  assert.equal(up.headers['content-type'], 'image/webp');
  const stageBody = fake.ledger.get(`stage:${await derivedRequestId(REQ, 'stage')}`);
  assert.ok(stageBody, 'stage used the key derived from the request id');
  assert.ok(fake.ledger.has(`finalize:${await derivedRequestId(REQ, 'finalize')}`), 'finalize used its derived key');
  assert.notEqual(await derivedRequestId(REQ, 'stage'), await derivedRequestId(REQ, 'finalize'));
  const obj = [...fake.objects.values()][0];
  assert.equal(obj.size, r.json.media.bytes);
  assert.equal(fake.sha(obj.bytes), r.json.media.content_hash, 'the uploaded bytes are the content address');
});

test('F6. the ladder: an over-cap rung answers 202 ladder_next; the next rung publishes', async () => {
  const { handle, fake } = await setup({ hero: 'band_q74' });
  const b = body({ slot: 'hero', variant: 'w960', source_bucket: 'menu-images', source_key: MENU_KEY });
  const r0 = await call(handle, post(b));
  assert.equal(r0.status, 202);
  assert.deepEqual(r0.json, { ok: false, status: 'ladder_next', next_rung: 1 });
  assert.equal(fake.media.size, 0, 'nothing staged for an over-cap rung');
  const r1 = await call(handle, post({ ...b, rung: 1 }));
  assert.equal(r1.status, 200, r1.text);
  assert.equal(r1.json.media.content_hash, BAND_Q74_W960);
  assert.equal(r1.json.rung, 1);
});

test('F7. typed refusals of the source are 422 and stage nothing', async () => {
  for (const [name, code] of [['bad_gif', 'unsupported_format'], ['bad_apng', 'animated'], ['png_over_cap_header', 'too_many_pixels'], ['bad_empty', 'empty'],
    ['bomb_idat_tail_256mib', 'corrupt'], ['bomb_png_header', 'dimensions_too_large'], ['bad_png_junk_after_zlib', 'corrupt']]) {
    const { handle, fake } = await setup({ logo: name });
    const r = await call(handle, post(body()));
    assert.equal(r.status, 422, name);
    assert.deepEqual(r.json, { ok: false, status: 'refused', code }, name);
    assert.equal(fake.media.size, 0, name);
  }
});

test('F8. an original above its bucket cap is refused while streaming (never buffered whole)', async () => {
  const { handle, fake } = await setup();
  fake.privateObjects.set(`restaurant-logos/${LOGO_KEY}`, new Uint8Array(2097153));
  const r = await call(handle, post(body()));
  assert.deepEqual(r.json, { ok: false, status: 'refused', code: 'input_too_large' });
});

test('F9. a missing / unreadable original is 404 source_not_found', async () => {
  const { handle, fake } = await setup();
  fake.privateObjects.clear();
  const r = await call(handle, post(body()));
  assert.equal(r.status, 404);
  assert.equal(r.json.status, 'source_not_found');
});

// ------------------------------------------------------------------ recovery
async function assertSingleClean(fake) {
  assert.equal(fake.media.size, 1, 'exactly one media row');
  assert.equal(fake.objects.size, 1, 'exactly one object');
  assert.equal(fake.uploads.created, 1, 'the object was created exactly once (never overwritten)');
  assert.ok(fake.calls.every((c) => ['GET', 'POST'].includes(c.method.toUpperCase())), 'only GET / POST: nothing was ever deleted, moved or overwritten');
  const row = [...fake.media.values()][0];
  assert.equal(row.published_at !== null && row.unpublished_at === null, true, 'the row is LIVE');
}

test('F10. killed during STAGE (network failure after the server committed): retry with the same request_id converges', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('stage_storefront_media', 'after_commit');
  const r1 = await call(handle, post(body()));
  assert.equal(r1.status, 503);
  assert.deepEqual(r1.json, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true });
  assert.equal(fake.media.size, 1, 'the stage committed server-side');
  const r2 = await call(handle, post(body()));
  assert.equal(r2.status, 200, r2.text);
  await assertSingleClean(fake);
});

test('F11. killed during UPLOAD (object stored, response lost): retry finds the same bytes and publishes', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('upload', 'after_commit');
  const r1 = await call(handle, post(body()));
  assert.equal(r1.json.uncertain, true);
  assert.equal(fake.objects.size, 1);
  const r2 = await call(handle, post(body()));
  assert.equal(r2.status, 200, r2.text);
  assert.equal(fake.uploads.exists, 0, 'the retry read the existing object first and compared it: the bytes were never re-sent');
  assert.ok(fake.calls.filter((c) => c.path.startsWith('/storage/v1/object/authenticated/storefront-media/')).length >= 2, 'the content address was read back');
  await assertSingleClean(fake);
});

test('F12. killed during FINALIZE after it committed: the retry replays the stored publication', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('finalize_storefront_media', 'after_commit');
  const r1 = await call(handle, post(body()));
  assert.equal(r1.json.status, 'upstream_unavailable');
  const r2 = await call(handle, post(body()));
  assert.equal(r2.status, 200, r2.text);
  assert.equal(r2.json.idempotent_replay, true, 'finalize replayed, it did not publish twice');
  await assertSingleClean(fake);
});

test('F13. killed BEFORE stage (download lost): nothing happened server-side; the retry publishes', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('download', 'network');
  const r1 = await call(handle, post(body()));
  assert.deepEqual(r1.json, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: false });
  assert.equal(fake.media.size, 0);
  assert.equal((await call(handle, post(body()))).status, 200);
  await assertSingleClean(fake);
});

test('F14. an ABANDONED attempt (row cancelled, object left) is recovered by a NEW request without overwriting', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('finalize_storefront_media', 'network');
  await call(handle, post(body()));
  // the Dashboard cancels the stuck STAGED row (cancel deletes the ROW only)
  fake.media.clear();
  const r = await call(handle, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000fe' })));
  assert.equal(r.status, 200, r.text);
  assert.equal(fake.uploads.created, 1);
  assert.equal(fake.uploads.exists, 0, 'the object left in place was found by the read-first check');
  assert.equal(fake.media.size, 1);
});

test('F15. an object at the content address with DIFFERENT bytes is a 409 object_conflict, never overwritten or deleted', async () => {
  const { handle, fake } = await setup();
  const hash = LOGO_W480.hash;
  fake.objects.set(`${'a'.repeat(32)}/${hash}.webp`, { bytes: new Uint8Array([1, 2, 3]), mimetype: 'image/webp', size: 3 });
  const r = await call(handle, post(body()));
  assert.equal(r.status, 409);
  assert.equal(r.json.status, 'object_conflict');
  assert.deepEqual([...fake.objects.values()][0].bytes, new Uint8Array([1, 2, 3]), 'left untouched');
  assert.ok(fake.calls.every((c) => ['GET', 'POST'].includes(c.method.toUpperCase())));
});

test('F16. a request_id reused with different input is 409 restart_required (new request id needed)', async () => {
  const { handle, fake } = await setup();
  const stageKey = await derivedRequestId(REQ, 'stage');
  fake.ledger.set(`stage:${stageKey}`, { fp: 'something else', result: { ok: true } });
  const r = await call(handle, post(body()));
  assert.equal(r.status, 409);
  assert.equal(r.json.status, 'restart_required');
});

test('F17. an engine failure is a retryable 503, retires the worker, and later requests never reach the engine', async () => {
  let engineCalls = 0;
  const { handle, fake, retired } = await setup({ engine: async () => { engineCalls++; throw new Error('wasm trap'); } });
  const r = await call(handle, post(body()));
  assert.deepEqual(r.json, { ok: false, status: 'engine_unavailable', retryable: true });
  assert.equal(retired.n, 1);
  const before = fake.calls.length;
  const r2 = await call(handle, post(body()));
  assert.equal(r2.status, 503);
  assert.equal(fake.calls.length, before, 'a poisoned worker makes no upstream call');
  assert.equal(engineCalls, 1);
});

test('F18. a second publish of the same source + bytes is an idempotent ok (already published), no second object', async () => {
  const { handle, fake } = await setup();
  assert.equal((await call(handle, post(body()))).status, 200);
  const r2 = await call(handle, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000fd' })));
  assert.equal(r2.status, 200);
  assert.equal(r2.json.already_published, true);
  assert.equal(fake.uploads.created, 1);
  assert.equal(fake.uploads.exists, 0, 'the existing object is read and compared first; its bytes are never re-sent or overwritten');
  assert.ok(fake.calls.some((c) => c.path.startsWith('/storage/v1/object/authenticated/storefront-media/')), 'the published object was re-proven');
});

test('F19. error logs never carry request data (keys, tokens, bytes)', async () => {
  const { handle, logs } = await setup({ engine: async () => ({ derive: async () => { throw new TypeError(`boom ${LOGO_KEY} ${TOKEN}`); } }) });
  const r = await call(handle, post(body()));
  assert.equal(r.status, 500);
  assert.equal(r.json.status, 'internal_error');
  assert.ok(logs.length === 1 && !logs[0].includes(LOGO_KEY) && !logs[0].includes(TOKEN), logs[0]);
});

test('F20. the SAME request after its STAGED row was cancelled is 409 restart_required (never a sticky 403); a new request publishes', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('finalize_storefront_media', 'network');
  assert.equal((await call(handle, post(body()))).json.status, 'upstream_unavailable');
  fake.media.clear(); // the Dashboard cancels the stuck STAGED row (the object stays)
  const again = await call(handle, post(body()));
  assert.equal(again.status, 409);
  assert.equal(again.json.status, 'restart_required');
  const fresh = await call(handle, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000fc' })));
  assert.equal(fresh.status, 200, fresh.text);
});

test('F21. an upload refused AFTER a successful stage (the registration vanished) is 409 restart_required', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('upload', { status: 400, body: { statusCode: '403', error: 'Unauthorized', message: 'new row violates row-level security policy' } });
  const r = await call(handle, post(body()));
  assert.equal(r.status, 409);
  assert.equal(r.json.status, 'restart_required');
});

test('F22. the download cap holds while STREAMING: no Content-Length, or a lying one, still stops at the bucket cap', async () => {
  for (const shape of ['no_length', 'lying_length']) {
    const { handle, fake } = await setup();
    fake.privateObjects.set(`restaurant-logos/${LOGO_KEY}`, new Uint8Array(2097153 + 4096));
    fake.downloadShape = shape;
    const r = await call(handle, post(body()));
    assert.deepEqual(r.json, { ok: false, status: 'refused', code: 'input_too_large' }, shape);
    assert.equal(fake.media.size, 0, shape);
  }
  // and a well-formed source streamed without a length still derives the golden
  const { handle, fake } = await setup();
  fake.downloadShape = 'no_length';
  const ok = await call(handle, post(body()));
  assert.equal(ok.json.media.content_hash, LOGO_W480.hash);
});

test('F23. a private download cut mid-body is a retryable 503 with uncertain:false (nothing was staged)', async () => {
  const { handle, fake } = await setup();
  fake.downloadShape = 'cut';
  const r = await call(handle, post(body()));
  assert.deepEqual(r.json, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: false });
  assert.equal(fake.media.size, 0);
});

test('F24. Storage errors are classified by their JSON body (HTTP 400 carries most of them)', async () => {
  const cases = [
    [{ statusCode: '403', error: 'Unauthorized', message: 'invalid signature' }, 401, 'unauthenticated'],
    [{ statusCode: '400', error: 'InvalidJWT', message: 'jwt expired' }, 401, 'unauthenticated'],
    [{ statusCode: '404', error: 'not_found', message: 'Object not found' }, 404, 'source_not_found'],
    [{ statusCode: '403', error: 'AccessDenied', message: 'access denied' }, 403, 'permission_denied'],
  ];
  for (const [bodyJson, status, statusText] of cases) {
    const { handle, fake } = await setup();
    fake.faults.set('download', { status: 400, body: bodyJson });
    const r = await call(handle, post(body()));
    assert.equal(r.status, status, JSON.stringify(bodyJson));
    assert.equal(r.json.status, statusText);
  }
});

test('F25. after "object exists", a failed read-back is an UNKNOWN outcome (503 uncertain), never source_not_found', async () => {
  const { handle, fake } = await setup();
  assert.equal((await call(handle, post(body()))).status, 200);
  // second request: the object exists; its read-back is not visible (e.g. a transient policy / storage failure)
  const origFetch = fake.fetchImpl;
  let downloads = 0;
  const handle2 = createHandler({
    supabaseUrl: URL_BASE, anonKey: ANON, engine: deriver, upstreamTimeoutMs: 2000, retireWorker: () => {},
    fetchImpl: async (url, init) => (String(url).includes('/object/authenticated/storefront-media/') && ++downloads
      ? new Response(JSON.stringify({ statusCode: '404', error: 'not_found', message: 'Object not found' }), { status: 400 })
      : origFetch(url, init)),
  });
  const r = await call(handle2, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000fb' })));
  assert.deepEqual(r.json, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true });
});

test('F26. a LIVE row whose object vanished (raw Storage API) is healed by the next publish of the same bytes', async () => {
  const { handle, fake } = await setup();
  assert.equal((await call(handle, post(body()))).status, 200);
  fake.objects.clear(); // a manager removed the public object through the raw Storage API
  const r = await call(handle, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000fa' })));
  assert.equal(r.status, 200, r.text);
  assert.equal(r.json.already_published, true);
  assert.equal(fake.uploads.created, 2, 'the object was re-created under its registered key');
  assert.equal(fake.sha([...fake.objects.values()][0].bytes), r.json.media.content_hash);
});

test('F27. a concurrent request of the same bytes wins the upload race: "exists" -> read back -> compare -> publish, no overwrite', async () => {
  const { fake } = await setup();
  const first = await call(createHandler({ supabaseUrl: URL_BASE, anonKey: ANON, engine: deriver, upstreamTimeoutMs: 2000, retireWorker: () => {}, fetchImpl: fake.fetchImpl }), post(body()));
  assert.equal(first.status, 200);
  fake.media.get(first.json.media.id).published_at = null; // the row is STAGED again for this scenario
  let hidden = true;
  const racing = createHandler({
    supabaseUrl: URL_BASE, anonKey: ANON, engine: deriver, upstreamTimeoutMs: 2000, retireWorker: () => {},
    // the read-first check misses the object (it lands between the read and the upload)
    fetchImpl: async (url, init) => (hidden && String(url).includes('/object/authenticated/storefront-media/') && !(hidden = false)
      ? new Response(JSON.stringify({ statusCode: '404', error: 'not_found', message: 'Object not found' }), { status: 400 })
      : fake.fetchImpl(url, init)),
  });
  const r = await call(racing, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000f9' })));
  assert.equal(r.status, 200, r.text);
  assert.equal(fake.uploads.exists, 1, 'the duplicate upload was detected');
  assert.equal(fake.uploads.created, 1, 'and nothing was overwritten');
});

test('F28. the SAME request replayed after its publication was RETRACTED is 409 restart_required (never a stale 200 published); a new request republishes', async () => {
  const { handle, fake } = await setup();
  fake.faults.set('finalize_storefront_media', 'after_commit'); // finalize committed, the response was lost
  assert.equal((await call(handle, post(body()))).json.status, 'upstream_unavailable');
  const [row] = [...fake.media.values()];
  assert.equal(row.published_at !== null && row.unpublished_at === null, true, 'the lost finalize had published the row');
  row.unpublished_at = 't2'; // another manager retracted it meanwhile
  const stale = await call(handle, post(body()));
  assert.equal(stale.status, 409, stale.text);
  assert.equal(stale.json.status, 'restart_required');
  assert.equal(row.unpublished_at, 't2', 'the stale replay changed nothing');
  const fresh = await call(handle, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000f8' })));
  assert.equal(fresh.status, 200, fresh.text);
  assert.equal(fresh.json.republished, true, 'a new request republishes RETRACTED -> LIVE');
  assert.equal(fake.uploads.created, 1, 'no second object');
});

// ---------------------------------------------------------- review closures
const finalizeCalls = (fake) => fake.calls.filter((c) => c.path === '/rest/v1/rpc/finalize_storefront_media').length;
const stageCalls = (fake) => fake.calls.filter((c) => c.path === '/rest/v1/rpc/stage_storefront_media').length;
const storageCallsToPublic = (fake) => fake.calls.filter((c) => c.path.startsWith('/storage/v1/object/authenticated/storefront-media/') || c.path.startsWith('/storage/v1/object/storefront-media/')).length;
const jsonResponse = (status, b) => new Response(JSON.stringify(b), { status, headers: { 'content-type': 'application/json' } });
const sha = (b) => createHash('sha256').update(b).digest('hex');

test('F15b. TNV-4: a SAME-LENGTH foreign object at the content address is 409 object_conflict, and finalize is never called', async () => {
  const { handle, fake } = await setup();
  const planted = new Uint8Array(LOGO_W480.bytes).fill(7); // exactly the derivative's length, other bytes
  fake.objects.set(`${'a'.repeat(32)}/${LOGO_W480.hash}.webp`, { bytes: planted, mimetype: 'image/webp', size: planted.length });
  const r = await call(handle, post(body()));
  assert.equal(r.status, 409, r.text);
  assert.deepEqual(r.json, { ok: false, status: 'object_conflict' });
  assert.equal(finalizeCalls(fake), 0, 'the size-only proof of finalize was never relied on');
  assert.equal(fake.uploads.created + fake.uploads.exists, 0, 'no upload was attempted');
  assert.deepEqual([...fake.objects.values()][0].bytes, planted, 'left untouched');
  assert.equal([...fake.media.values()][0].published_at, null, 'the row stays STAGED');
});

test('F29. SEC-1: an anonymous session, or any role / audience other than authenticated, is 401 before any RPC, download or engine work', async () => {
  const base = { id: 'user-1', aud: 'authenticated', role: 'authenticated', is_anonymous: false };
  for (const [label, user] of [
    ['anonymous (paired device / kiosk) session', { ...base, is_anonymous: true }],
    ['role anon', { ...base, role: 'anon' }],
    ['role service_role', { ...base, role: 'service_role' }],
    ['audience anon', { ...base, aud: 'anon' }],
    ['no role', { id: 'user-1', aud: 'authenticated', is_anonymous: false }],
    ['no audience', { id: 'user-1', role: 'authenticated', is_anonymous: false }],
    ['audience as an array', { ...base, aud: ['authenticated'] }],
  ]) {
    let engineCalls = 0;
    const { handle, fake } = await setup({ user, engine: async () => { engineCalls++; return deriver(); } });
    const r = await call(handle, post(body()));
    assert.equal(r.status, 401, label);
    assert.deepEqual(r.json, { ok: false, status: 'unauthenticated' }, label);
    assert.deepEqual(fake.calls.map((c) => c.path), ['/auth/v1/user'], `${label}: only GoTrue was asked`);
    assert.equal(engineCalls, 0, label);
  }
  // control: a signed-in user whose GoTrue record has no is_anonymous field is not anonymous
  const { handle } = await setup({ user: { id: 'user-1', aud: 'authenticated', role: 'authenticated' } });
  assert.equal((await call(handle, post(body()))).status, 200);
});

test('F30. SEC-4: a top-level key named twice is 400 invalid_request (duplicate_key) before any upstream call', async () => {
  const { handle, fake } = await setup();
  const good = JSON.stringify(body());
  for (const raw of [
    good.replace('{', '{"slot":"hero",'), // slot twice: JSON.parse would silently keep the last
    good.replace('{', '{"\\u0073lot":"logo",'), // the same key, escaped
    good.replace('{', '{"rung":4,'),
    good.replace(/}$/, `,"request_id":"${REQ}"}`), // even the same value twice is ambiguous input
    good.replace('{', '{"__proto__":1,"__proto__":2,'),
  ]) {
    const r = await call(handle, post(null, { raw }));
    assert.equal(r.status, 400, raw.slice(0, 60));
    assert.deepEqual(r.json, { ok: false, status: 'invalid_request', field: 'body', reason: 'duplicate_key' }, raw.slice(0, 60));
  }
  assert.equal(fake.calls.length, 0, 'refused before authentication');
  // control: the same body without a duplicate proceeds to authentication and publishes
  assert.equal((await call(handle, post(null, { raw: good }))).status, 200);
});

test('F31. TNV-7: every typed upstream answer maps to its exact status and body', async () => {
  const envelope = (error, extra = {}) => ({ status: 200, body: { ok: false, error, entity: 'storefront_media', ...extra } });
  const cases = [
    // GoTrue and the preflight (nothing staged: uncertain false)
    ['getUser 503', '/auth/v1/user', { status: 503, body: {} }, 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: false }],
    ['getUser 200 without a user id', '/auth/v1/user', { status: 200, body: { aud: 'authenticated', role: 'authenticated' } }, 401, { ok: false, status: 'unauthenticated' }],
    ['list 42501', 'list_storefront_media', { status: 403, body: { code: '42501', message: 'permission denied' } }, 403, { ok: false, status: 'permission_denied' }],
    ['list 503', 'list_storefront_media', { status: 503, body: {} }, 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: false }],
    ['list 401', 'list_storefront_media', { status: 401, body: {} }, 401, { ok: false, status: 'unauthenticated' }],
    ['list 400 (rejected)', 'list_storefront_media', { status: 400, body: { code: '22023', message: 'x' } }, 500, { ok: false, status: 'internal_error', retryable: true, uncertain: false }],
    // stage: typed envelopes
    ['stage permission_denied', 'stage_storefront_media', envelope('permission_denied'), 403, { ok: false, status: 'permission_denied' }],
    ['stage source_not_found', 'stage_storefront_media', envelope('source_not_found'), 404, { ok: false, status: 'source_not_found' }],
    ['stage content_mismatch', 'stage_storefront_media', envelope('content_mismatch'), 409, { ok: false, status: 'object_conflict' }],
    ['stage stale_request', 'stage_storefront_media', envelope('stale_request'), 409, { ok: false, status: 'restart_required' }],
    ['stage invalid + reason', 'stage_storefront_media', envelope('invalid', { reason: 'dimensions_invalid' }), 422, { ok: false, status: 'refused', code: 'dimensions_invalid' }],
    ['stage invalid without a reason', 'stage_storefront_media', envelope('invalid'), 422, { ok: false, status: 'refused', code: 'invalid' }],
    ['stage unknown error', 'stage_storefront_media', envelope('surprise'), 500, { ok: false, status: 'internal_error', retryable: true, uncertain: true }],
    // stage: raised errors
    ['stage 42501', 'stage_storefront_media', { status: 403, body: { code: '42501', message: 'permission denied for function' } }, 403, { ok: false, status: 'permission_denied' }],
    ['stage 400 (rejected)', 'stage_storefront_media', { status: 400, body: { code: '22023', message: 'x' } }, 500, { ok: false, status: 'internal_error', retryable: true, uncertain: true }],
    ['stage 503', 'stage_storefront_media', { status: 503, body: {} }, 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true }],
    ['stage 200 non-object envelope', 'stage_storefront_media', { status: 200, body: [] }, 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true }],
    // the read-back of the content address
    ['read-back forbidden', 'read_public', { status: 400, body: { statusCode: '403', error: 'AccessDenied', message: 'access denied' } }, 409, { ok: false, status: 'restart_required' }],
    ['read-back unauthenticated', 'read_public', { status: 400, body: { statusCode: '400', error: 'InvalidJWT', message: 'jwt expired' } }, 401, { ok: false, status: 'unauthenticated' }],
    ['read-back 503', 'read_public', { status: 503, body: {} }, 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true }],
    // the upload
    ['upload 503', 'upload', { status: 503, body: {} }, 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true }],
    ['upload 401', 'upload', { status: 401, body: {} }, 401, { ok: false, status: 'unauthenticated' }],
    ['upload 400 other', 'upload', { status: 400, body: { statusCode: '400', error: 'InvalidKey', message: 'x' } }, 500, { ok: false, status: 'internal_error', retryable: true, uncertain: true }],
    // finalize: typed envelopes and raised errors
    ['finalize permission_denied', 'finalize_storefront_media', envelope('permission_denied'), 403, { ok: false, status: 'permission_denied' }],
    ['finalize not_found', 'finalize_storefront_media', envelope('not_found'), 409, { ok: false, status: 'restart_required' }],
    ['finalize stale_request', 'finalize_storefront_media', envelope('stale_request'), 409, { ok: false, status: 'restart_required' }],
    ['finalize object_mismatch', 'finalize_storefront_media', envelope('object_mismatch'), 409, { ok: false, status: 'object_conflict' }],
    ['finalize object_missing', 'finalize_storefront_media', envelope('object_missing'), 503, { ok: false, status: 'upstream_unavailable', retryable: true, uncertain: true }],
    ['finalize unknown error', 'finalize_storefront_media', envelope('surprise'), 500, { ok: false, status: 'internal_error', retryable: true, uncertain: true }],
    ['finalize 42501', 'finalize_storefront_media', { status: 403, body: { code: '42501', message: 'permission denied' } }, 403, { ok: false, status: 'permission_denied' }],
    ['finalize 42501 key reuse', 'finalize_storefront_media', { status: 403, body: { code: '42501', message: 'management: client_request_id reused with different input' } }, 409, { ok: false, status: 'restart_required' }],
  ];
  for (const [label, step, fault, status, expected] of cases) {
    const { handle, fake } = await setup();
    fake.faults.set(step, fault);
    const r = await call(handle, post(body()));
    assert.equal(r.status, status, `${label}: ${r.text}`);
    assert.deepEqual(r.json, expected, label);
    assert.equal(fake.faults.has(step), false, `${label}: the injected answer was consumed`);
  }
});

test('F31b. TNV-7: realistic restarts — the row cancelled between stage and finalize, an over-cap object at the address, the misconfigured function', async () => {
  {
    const { handle, fake } = await setup();
    fake.faults.set('finalize_storefront_media', (state) => { state.media.clear(); return null; }); // cancelled meanwhile
    const r = await call(handle, post(body()));
    assert.deepEqual([r.status, r.json], [409, { ok: false, status: 'restart_required' }]);
  }
  {
    const { handle, fake } = await setup();
    const big = new Uint8Array(524289).fill(1);
    fake.objects.set(`${'a'.repeat(32)}/${LOGO_W480.hash}.webp`, { bytes: big, mimetype: 'image/webp', size: big.length });
    const r = await call(handle, post(body()));
    assert.deepEqual([r.status, r.json], [409, { ok: false, status: 'object_conflict' }]);
    assert.equal(finalizeCalls(fake), 0);
  }
  {
    const fake = fakeSupabase({});
    const handle = createHandler({ supabaseUrl: '', anonKey: ANON, engine: deriver, fetchImpl: fake.fetchImpl, retireWorker: () => {} });
    const r = await call(handle, post(body()));
    assert.deepEqual([r.status, r.json], [500, { ok: false, status: 'internal_error', code: 'function_misconfigured', retryable: false, uncertain: false }]);
    assert.equal(fake.calls.length, 0);
  }
});

test('F32. TNV-8: the handler re-checks the engine result — over-cap, over-box, wrong hash / length / rung or a malformed result is 422 self_check_failed and nothing is staged', async () => {
  const good = await (await deriver()).derive(await fixture('logo_opaque_rgb_1200x600'), { variant: 'w480', source: 'restaurant-logos', rung: 0 });
  const huge = new Uint8Array(524289);
  const variants = [
    ['over the byte cap', { ...good, bytes: huge, byteLength: huge.length, sha256: sha(huge) }],
    ['wider than the box', { ...good, width: 481 }],
    ['taller than the box', { ...good, height: 481 }],
    ['a zero dimension', { ...good, width: 0 }],
    ['a fractional dimension', { ...good, height: 239.5 }],
    ['a wrong content hash', { ...good, sha256: '0'.repeat(64) }],
    ['a byteLength that lies', { ...good, byteLength: good.byteLength - 1 }],
    ['another rung', { ...good, rung: 1 }],
    ['bytes that are not a Uint8Array', { ...good, bytes: Array.from(good.bytes) }],
    ['an unknown status', { ...good, status: 'maybe' }],
  ];
  for (const [label, result] of variants) {
    const { handle, fake } = await setup({ engine: async () => ({ derive: async () => result, poisoned: false }) });
    const r = await call(handle, post(body()));
    assert.deepEqual(r.json, { ok: false, status: 'refused', code: 'self_check_failed' }, label);
    assert.equal(stageCalls(fake), 0, `${label}: nothing staged`);
    assert.equal(storageCallsToPublic(fake), 0, `${label}: nothing uploaded`);
  }
  const { handle } = await setup({ engine: async () => ({ derive: async () => good, poisoned: false }) });
  assert.equal((await call(handle, post(body()))).status, 200, 'control: the untouched result publishes');
});

test('F33. TNV-8: a trap during derive is a retryable 503 that retires the worker; a POISONED typed refusal keeps its 422 and retires too', async () => {
  {
    let derives = 0;
    const { handle, fake, retired } = await setup({ engine: async () => ({ derive: async () => { derives++; throw new DerivationError('engine_unavailable', 'trap'); }, poisoned: true }) });
    const r = await call(handle, post(body()));
    assert.deepEqual(r.json, { ok: false, status: 'engine_unavailable', retryable: true });
    assert.equal(retired.n, 1, 'retireWorker was called');
    const before = fake.calls.length;
    const r2 = await call(handle, post(body()));
    assert.deepEqual([r2.status, r2.json], [503, { ok: false, status: 'engine_unavailable', retryable: true }]);
    assert.equal(fake.calls.length, before, 'a poisoned worker makes no upstream call');
    assert.equal(derives, 1);
  }
  {
    const { handle, fake, retired } = await setup({ engine: async () => ({ derive: async () => { throw new DerivationError('decode_failed', 'png'); }, poisoned: true }) });
    const r = await call(handle, post(body()));
    assert.deepEqual(r.json, { ok: false, status: 'refused', code: 'decode_failed' }, 'the source still gets its typed refusal');
    assert.equal(retired.n, 1, 'and the untrusted engine retires the worker');
    const before = fake.calls.length;
    assert.equal((await call(handle, post(body()))).status, 503);
    assert.equal(fake.calls.length, before);
  }
  {
    const { handle, retired } = await setup({ engine: async () => ({ derive: async () => { throw new DerivationError('decode_failed', 'jpeg'); }, poisoned: false }) });
    assert.deepEqual((await call(handle, post(body()))).json, { ok: false, status: 'refused', code: 'decode_failed' });
    assert.equal(retired.n, 0, 'control: a refusal from a trusted engine does not retire the worker');
  }
});

test('F34. TNV-8: a JWT-shaped bearer longer than 8192 characters is 401 with no upstream call; 8192 is still a candidate', async () => {
  const { handle, fake } = await setup();
  const over = `${'a'.repeat(4000)}.${'b'.repeat(4000)}.${'c'.repeat(191)}`; // 8193
  assert.equal(over.length, 8193);
  const r = await call(handle, post(body(), { token: over }));
  assert.deepEqual([r.status, r.json], [401, { ok: false, status: 'unauthenticated' }]);
  assert.equal(fake.calls.length, 0);
  const at = `${'a'.repeat(4000)}.${'b'.repeat(4000)}.${'c'.repeat(190)}`; // 8192
  assert.equal(at.length, 8192);
  assert.equal((await call(handle, post(body(), { token: at }))).status, 401);
  assert.deepEqual(fake.calls.map((c) => c.path), ['/auth/v1/user'], 'the 8192-character token reached GoTrue (which refused it)');
});

test('F35. TNV-8: a stage answer whose object_key is not exactly <32 hex>/<this sha-256>.webp is 500 (uncertain); nothing is uploaded or finalized', async () => {
  const h = LOGO_W480.hash, p = 'a'.repeat(32);
  for (const key of [`../${p}/${h}.webp`, `${p}/../${h}.webp`, `${p}/./${h}.webp`, `${p}//${h}.webp`, `${'a'.repeat(31)}/${h}.webp`, `${'A'.repeat(32)}/${h}.webp`,
    `${p}/${'0'.repeat(64)}.webp`, `x/${p}/${h}.webp`, `${p}/${h}.webp/`, `${p}/${h}.png`, 42, null]) {
    const { handle, fake } = await setup();
    fake.faults.set('stage_storefront_media', (state, init) => {
      const q = JSON.parse(init.body);
      return jsonResponse(200, { ok: true, idempotent_replay: false, entity: 'storefront_media', media_id: 'm-x', object_key: key, state: 'staged', existing: false,
        source_bucket: q.p_source_bucket, source_key: q.p_source_key, variant: q.p_variant, source_mismatch: false });
    });
    const r = await call(handle, post(body()));
    assert.deepEqual([r.status, r.json], [500, { ok: false, status: 'internal_error', retryable: true, uncertain: true }], String(key));
    assert.equal(storageCallsToPublic(fake), 0, `${key}: no read-back and no upload`);
    assert.equal(finalizeCalls(fake), 0, String(key));
  }
});

test('F36. TNV-8: identical bytes already registered for ANOTHER source pass through as source_mismatch with the existing row', async () => {
  const LOGO_KEY_2 = `${ORG}/${RESTO}/logo/0b5e0000-0000-4000-8000-0000000000a2.png`;
  const { handle, fake } = await setup();
  fake.privateObjects.set(`restaurant-logos/${LOGO_KEY_2}`, await fixture('logo_opaque_rgb_1200x600'));
  assert.equal((await call(handle, post(body()))).status, 200);
  const r = await call(handle, post(body({ request_id: '0b5e0000-0000-4000-8000-0000000000f7', source_key: LOGO_KEY_2 })));
  assert.equal(r.status, 200, r.text);
  assert.equal(r.json.source_mismatch, true);
  assert.equal(r.json.media.source_key, LOGO_KEY, 'media describes the EXISTING row (identical bytes), not the requested source');
  assert.equal(r.json.already_published, true);
  assert.equal(fake.media.size, 1);
  assert.equal(fake.uploads.created, 1);
});

test('F37. TNV-8: the download cap is measured in bytes PULLED — a 64 MiB original without a length stops within two chunks past the 2 MiB cap', async () => {
  const { handle, fake } = await setup();
  fake.privateObjects.set(`restaurant-logos/${LOGO_KEY}`, new Uint8Array(64 * 1048576));
  fake.downloadShape = 'counted';
  const r = await call(handle, post(body()));
  assert.deepEqual(r.json, { ok: false, status: 'refused', code: 'input_too_large' });
  assert.ok(fake.pulled > 2097152 && fake.pulled <= 2097152 + 2 * 65536, `pulled ${fake.pulled} bytes of a 64 MiB object`);
  assert.equal(stageCalls(fake), 0);
  // control: a well-formed source pulled in 64 KiB chunks derives the golden, read exactly once
  const ok = await setup();
  ok.fake.downloadShape = 'counted';
  const res = await call(ok.handle, post(body()));
  assert.equal(res.json.media.content_hash, LOGO_W480.hash);
  assert.equal(ok.fake.pulled, (await fixture('logo_opaque_rgb_1200x600')).length);
});
