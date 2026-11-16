// Pure local unit tests. Injected Auth/RPC/Storage replies are NOT Edge E2E proof.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createHandler } from '../lib/handler.mjs';
import { validateWelcomeMp4, WelcomeVideoRejected, WELCOME_VIDEO_LIMITS } from '../lib/welcome-mp4.mjs';
import { validateWelcomeVideoRequest } from '../lib/welcome-video.mjs';

// Existing repository-owned, real H.264 sample. No network/encoder/dependency.
const real = new Uint8Array(await readFile(new URL('../../../../site/public/assets/video/kiosk-attract.mp4', import.meta.url)));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const ORG = '0b5e0000-0000-4000-8000-000000000001', RESTO = '0b5e0000-0000-4000-8000-000000000002';
const REQ = '0b5e0000-0000-4000-8000-000000000003', ID = '0b5e0000-0000-4000-8000-000000000004';
const KEY = `${ORG}/${RESTO}/0b5e0000-0000-4000-8000-000000000005.mp4`, PREFIX = 'a'.repeat(32);
const TOKEN = 'unit.owner.jwt', ANON = 'unit-public-anon', BASE = 'https://temporary-unit.test';
const PRIVATE = 'storefront-welcome-video-originals', PUBLIC = 'storefront-welcome-videos', ENTITY = 'storefront_welcome_video';
const body = (extra = {}) => ({ kind: 'welcome_video_v1', request_id: REQ, organization_id: ORG, restaurant_id: RESTO, source_key: KEY, ...extra });
const json = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });
function post(value = body(), options = {}) {
  return new Request('https://edge.unit.test/storefront-media-publish', {
    method: 'POST', headers: { 'content-type': 'application/json', ...(options.token === null ? {} : { authorization: `Bearer ${options.token ?? TOKEN}` }) },
    body: options.raw ?? JSON.stringify(value),
  });
}
async function run(handle, request = post()) { const response = await handle(request); return { http: response.status, value: await response.json() }; }
function local(options = {}) {
  const state = { calls: [], source: options.source ?? real, publicObjects: new Map(), media: null, engineCalls: 0, retired: 0, uploads: 0 };
  const altered = (phase, value) => options.alter ? options.alter(phase, structuredClone(value)) : value;
  const fetchImpl = async (url, init) => {
    assert.equal(init.headers.authorization, `Bearer ${TOKEN}`); assert.equal(init.headers.apikey, ANON);
    const path = new URL(url).pathname, method = init.method;
    const params = typeof init.body === 'string' ? JSON.parse(init.body) : null;
    state.calls.push({ path, method, params });
    if (options.breakAt === path) throw new TypeError('unit upstream interruption');
    if (path === '/auth/v1/user') return json({ id: ID, role: 'authenticated', aud: 'authenticated', is_anonymous: options.anonymous === true });
    if (path.endsWith('/preflight_storefront_welcome_video_v1')) {
      if (options.canManage === false || params.p_restaurant_id !== RESTO) return json({ ok: false, entity: ENTITY, error: 'permission_denied' });
      return json(altered('preflight', { ok: true, entity: ENTITY, source: { bucket: PRIVATE, key: KEY, bytes: state.source.length, mime_type: 'video/mp4' }, media: state.media }));
    }
    if (path === `/storage/v1/object/authenticated/${PRIVATE}/${KEY}`) {
      if (options.sourceMissing) return json({ statusCode: '404', error: 'Object not found' }, 400);
      if (options.privateBodyInterrupted) return new Response(new ReadableStream({ start(controller) { controller.error(new Error('unit private body interrupted')); } }));
      return new Response(state.source, { headers: { 'content-length': String(state.source.length) } });
    }
    if (path.endsWith('/register_storefront_welcome_video_v1')) {
      assert.equal(params.p_request_id, REQ);
      state.media ??= { id: ID, object_key: `${PREFIX}/${params.p_content_hash}.mp4`, content_hash: params.p_content_hash,
        mime_type: 'video/mp4', width: params.p_width, height: params.p_height, duration_ms: params.p_duration_ms, bytes: params.p_bytes, published: false, url: null };
      return json(altered('register', { ok: true, entity: ENTITY, media: state.media }));
    }
    if (path.startsWith(`/storage/v1/object/authenticated/${PUBLIC}/`)) {
      const key = path.slice(`/storage/v1/object/authenticated/${PUBLIC}/`.length), value = state.publicObjects.get(key);
      if (!value) return json({ statusCode: '404', error: 'Object not found' }, 400);
      if (options.publicBodyInterrupted) return new Response(new ReadableStream({ start(controller) { controller.error(new Error('unit body interrupted')); } }));
      return new Response(value, { headers: { 'content-length': String(value.length) } });
    }
    if (path.startsWith(`/storage/v1/object/${PUBLIC}/`)) {
      state.uploads++; assert.equal(init.headers['x-upsert'], 'false'); assert.equal(init.headers['content-type'], 'video/mp4');
      const key = path.slice(`/storage/v1/object/${PUBLIC}/`.length);
      if (options.conflictRace) { state.publicObjects.set(key, options.conflictRace === 'same' ? new Uint8Array(init.body) : new Uint8Array([1, 2, 3])); return json({ statusCode: '409', error: 'Duplicate' }, 409); }
      state.publicObjects.set(key, options.corruptUpload ? new Uint8Array([1]) : new Uint8Array(init.body)); return json({ Key: key });
    }
    if (path.endsWith('/publish_storefront_welcome_video_v1')) {
      assert.equal(params.p_request_id, REQ); assert.equal(params.p_media_id, ID);
      state.media.published = true; state.media.url = `/storage/v1/object/public/${PUBLIC}/${state.media.object_key}`;
      return json(altered('publish', { ok: true, entity: ENTITY, media: state.media }));
    }
    throw new Error('Unexpected unit route');
  };
  const handle = createHandler({ supabaseUrl: BASE, anonKey: ANON, fetchImpl, engine: async () => { state.engineCalls++; throw new Error('image engine must not initialize'); }, retireWorker: () => { state.retired++; } });
  return { handle, state };
}

function children(bytes, start = 0, end = bytes.length) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength), rows = [];
  for (let p = start; p < end;) { const size = view.getUint32(p); assert.ok(size >= 8); rows.push({ type: String.fromCharCode(...bytes.subarray(p + 4, p + 8)), start: p, p: p + 8, end: p + size }); p += size; }
  return rows;
}
function find(bytes, path) {
  let start = 0, end = bytes.length, current;
  for (const token of path) { const [type, index = '0'] = token.split('#'); current = children(bytes, start, end).filter(b => b.type === type)[Number(index)]; assert.ok(current, path.join('/')); start = current.p + (type === 'stsd' ? 8 : type === 'avc1' ? 78 : type === 'mp4a' ? 28 : 0); end = current.end; }
  return current;
}
const path = (...tail) => ['moov', 'trak', 'mdia', 'minf', 'stbl', ...tail];
function change(fn) { const bytes = real.slice(), view = new DataView(bytes.buffer); fn(bytes, view); return bytes; }
const mustReject = (bytes, code) => assert.throws(() => validateWelcomeMp4(bytes), error => error instanceof WelcomeVideoRejected && (!code || error.code === code));

function box(type, ...parts) {
  const body = Buffer.concat(parts.map(v => Buffer.from(v))), header = Buffer.alloc(8);
  header.writeUInt32BE(body.length + 8); header.write(type, 4, 'ascii'); return Buffer.concat([header, body]);
}
const word = n => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
const fullBox = (type, ...parts) => box(type, word(0), ...parts);
function addStructuralAac() {
  // Table/configuration fixture only: this test does not assert AAC decode or playback.
  // Video samples/configuration stay the exact repository H.264 bytes.
  const makeTrack = offset => {
    const tk = Buffer.alloc(84); tk.writeUInt32BE(3); tk.writeUInt32BE(2, 12); tk.writeUInt32BE(24, 20); tk.writeUInt16BE(256, 36);
    [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824].forEach((v, i) => tk.writeUInt32BE(v, 40 + i * 4));
    const md = Buffer.alloc(24); md.writeUInt32BE(44100, 12); md.writeUInt32BE(1024, 16); md.writeUInt16BE(0x55c4, 20);
    const hd = Buffer.alloc(24); hd.write('soun', 8, 'ascii');
    const descriptor = (tag, data) => Buffer.concat([Buffer.from([tag, data.length]), data]);
    const configuration = Buffer.alloc(13); configuration[0] = 64; configuration[1] = 21;
    const es = descriptor(3, Buffer.concat([Buffer.from([0, 1, 0]), descriptor(4, Buffer.concat([configuration, descriptor(5, Buffer.from([0x12, 0x10]))])), descriptor(6, Buffer.from([2]))]));
    const entry = Buffer.alloc(28); entry.writeUInt16BE(1, 6); entry.writeUInt16BE(2, 16); entry.writeUInt16BE(16, 18); entry.writeUInt32BE(44100 * 65536, 24);
    const stbl = box('stbl', fullBox('stsd', word(1), box('mp4a', entry, fullBox('esds', es))), fullBox('stts', word(1), word(1), word(1024)), fullBox('stsc', word(1), word(1), word(1), word(1)), fullBox('stsz', word(0), word(1), word(6)), fullBox('stco', word(1), word(offset)));
    const dinf = box('dinf', fullBox('dref', word(1), box('url ', word(1))));
    return box('trak', box('tkhd', tk), box('mdia', box('mdhd', md), box('hdlr', hd), box('minf', fullBox('smhd', word(0)), dinf, stbl)));
  };
  const oldMoov = find(real, ['moov']), oldMdat = find(real, ['mdat']), delta = makeTrack(0).length;
  const moov = box('moov', real.subarray(oldMoov.p, oldMoov.end), makeTrack(oldMdat.end + delta));
  const c = find(moov, path('stco')), v = new DataView(moov.buffer, moov.byteOffset, moov.byteLength);
  for (let i = 0; i < v.getUint32(c.p + 4); i++) v.setUint32(c.p + 8 + i * 4, v.getUint32(c.p + 8 + i * 4) + delta);
  const mvhd = find(moov, ['moov', 'mvhd']); v.setUint32(mvhd.end - 4, 3);
  return new Uint8Array(Buffer.concat(children(real).map(b => b.type === 'moov' ? moov : b.type === 'mdat' ? box('mdat', real.subarray(b.p, b.end), Buffer.from([0x21, 0x10, 0x04, 0x60, 0x8c, 0x1c])) : Buffer.from(real.subarray(b.start, b.end)))));
}

test('welcome MP4: real repository H.264 bytes produce measured metadata, not caller claims', () => {
  assert.equal(real.length, 660459);
  assert.deepEqual(validateWelcomeMp4(real), { width: 540, height: 864, durationMs: 12042, byteLength: 660459, mimeType: 'video/mp4', audioTracks: 0 });
  assert.equal(Object.isFrozen(validateWelcomeMp4(real)), true);
});
test('welcome MP4: truncated containers, invalid box lengths, size-zero containers and extra moov fail', () => {
  for (const n of [0, 1, 7, 31, 100, real.length - 1]) mustReject(real.subarray(0, n));
  mustReject(change((b, v) => v.setUint32(0, b.length + 1)));
  mustReject(change((b, v) => v.setUint32(find(b, ['moov']).start, 0)));
  const moov = find(real, ['moov']); mustReject(new Uint8Array([...real, ...real.subarray(moov.start, moov.end)]));
});
test('welcome MP4: input, duration and actual sample dimension limits are enforced', () => {
  mustReject(new Uint8Array(WELCOME_VIDEO_LIMITS.bytes + 1), 'input_too_large');
  mustReject(change((b, v) => { const m = find(b, ['moov', 'mvhd']); v.setUint32(m.p + 16, v.getUint32(m.p + 12) * 31); }), 'duration_too_long');
  mustReject(change((b, v) => { const d = find(b, path('stsd', 'avc1')); v.setUint16(d.p + 24, 1921); }), 'dimensions_exceeded');
});
test('welcome MP4: an AVC label cannot hide a different codec, SPS mismatch or invalid AVC config', () => {
  mustReject(change((b) => { const d = find(b, path('stsd', 'avc1')); b.set(new TextEncoder().encode('hvc1'), d.start + 4); }), 'unsupported_video_codec');
  mustReject(change((b) => { const c = find(b, path('stsd', 'avc1', 'avcC')); b[c.p] = 2; }));
  mustReject(change((b) => { const c = find(b, path('stsd', 'avc1', 'avcC')); b[c.p + 4] = 254; }), 'unsupported_video_codec');
  mustReject(change((b) => { const c = find(b, path('stsd', 'avc1', 'avcC')); b[c.p + 3] = 1; }));
});
test('welcome MP4: external media references, transforms and fragmented movie are refused', () => {
  mustReject(change((b, v) => { const d = find(b, ['moov', 'trak', 'mdia', 'minf', 'dinf', 'dref']); v.setUint32(d.p + 16, 0); }), 'unsupported_video_layout');
  mustReject(change((b, v) => v.setUint32(find(b, ['moov', 'trak', 'tkhd']).p + 40, 131072)), 'unsupported_video_layout');
  mustReject(new Uint8Array([...real, 0, 0, 0, 8, 109, 111, 111, 102]), 'unsupported_video_layout');
});
test('welcome MP4: sample table pointers, sample sizes and actual NAL framing must be valid', () => {
  mustReject(change((b, v) => v.setUint32(find(b, path('stco')).p + 8, b.length - 1)));
  mustReject(change((b, v) => v.setUint32(find(b, path('stsz')).p + 12, 0)));
  mustReject(change((b, v) => { const c = find(b, path('stco')), first = v.getUint32(c.p + 8); v.setUint32(first, 0); }));
  mustReject(change((b, v) => { const c = find(b, path('stco')), first = v.getUint32(c.p + 8); b[first + 4] |= 128; }));
});
test('welcome MP4: real sample duration cannot be hidden by a short movie-header claim', () => {
  mustReject(change((b, v) => { const t = find(b, path('stts')); v.setUint32(t.p + 12, 0xffffffff); }), 'duration_too_long');
});
test('welcome MP4: one optional AAC-LC configuration is bounded; this is structural evidence, not an AAC decode claim', () => {
  const withAudio = addStructuralAac();
  assert.equal(validateWelcomeMp4(withAudio).audioTracks, 1);
  const wrongCodec = withAudio.slice(), codec = find(wrongCodec, ['moov', 'trak#1', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a']);
  wrongCodec.set(new TextEncoder().encode('Opus'), codec.start + 4); mustReject(wrongCodec, 'unsupported_audio_codec');
  const wrongProfile = withAudio.slice(), esds = find(wrongProfile, ['moov', 'trak#1', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a', 'esds']);
  wrongProfile[esds.end - 5] = 0xf8; mustReject(wrongProfile, 'unsupported_audio_codec');
  const wrongChannels = withAudio.slice(), sample = find(wrongChannels, ['moov', 'trak#1', 'mdia', 'minf', 'stbl', 'stsd', 'mp4a']);
  new DataView(wrongChannels.buffer).setUint16(sample.p + 16, 3); mustReject(wrongChannels, 'unsupported_audio_codec');
});
test('welcome MP4: more than one audio track or duplicate track identity cannot pass', () => {
  const withAudio = addStructuralAac(), moov = find(withAudio, ['moov']), audio = find(withAudio, ['moov', 'trak#1']);
  const three = Buffer.concat(children(withAudio).map(b => b.type === 'moov' ? box('moov', withAudio.subarray(moov.p, moov.end), withAudio.subarray(audio.start, audio.end)) : Buffer.from(withAudio.subarray(b.start, b.end))));
  mustReject(three, 'unsupported_video_layout');
  const duplicate = withAudio.slice(), tkhd = find(duplicate, ['moov', 'trak#1', 'tkhd']); new DataView(duplicate.buffer).setUint32(tkhd.p + 12, 1); mustReject(duplicate);
});

test('welcome request: exactly five keys, strict UUIDs and same organization/restaurant path', () => {
  assert.equal(validateWelcomeVideoRequest(body()).ok, true);
  for (const value of [null, [], {}, body({ organization_id: ORG.toUpperCase() }), body({ kind: 'welcome_video_v2' }), body({ source_key: KEY.replace(RESTO, ID) }), body({ source_key: KEY.replace('.mp4', '.MP4') }), body({ url: 'https://outside.test/file.mp4' })]) assert.equal(validateWelcomeVideoRequest(value).ok, false);
});
test('welcome transport/auth: duplicate keys and unsigned/anonymous users never reach video authority or media', async () => {
  const { handle, state } = local();
  assert.equal((await run(handle, post(body(), { token: null }))).http, 401);
  assert.equal((await run(handle, post(body(), { raw: JSON.stringify(body()).replace('{', '{"kind":"welcome_video_v1",') }))).http, 400);
  assert.equal(state.calls.length, 0);
  const anonymous = local({ anonymous: true }); assert.equal((await run(anonymous.handle)).http, 401);
  assert.deepEqual(anonymous.state.calls.map(c => c.path), ['/auth/v1/user']);
});
test('welcome authority: manager check precedes private download; path scope never grants authority', async () => {
  const denied = local({ canManage: false }); assert.equal((await run(denied.handle)).http, 403);
  assert.equal(denied.state.calls.length, 2); assert.equal(denied.state.engineCalls, 0);
  const other = local(); const target = ID;
  assert.equal((await run(other.handle, post(body({ restaurant_id: target, source_key: KEY.replace(RESTO, target) })))).http, 403);
  const invalid = local(); assert.equal((await run(invalid.handle, post(body({ source_key: KEY.replace(ORG, ID) })))).http, 400);
  assert.equal(invalid.state.calls.length, 1);
});
test('welcome publication: actual validated bytes pass caller-only stage/copy/readback/finalize with exact scoped response', async () => {
  const { handle, state } = local(); const r = await run(handle);
  assert.equal(r.http, 200); assert.equal(r.value.status, 'published');
  assert.deepEqual(Object.keys(r.value).sort(), ['kind', 'media', 'ok', 'organization_id', 'request_id', 'restaurant_id', 'status']);
  assert.equal(r.value.organization_id, ORG); assert.equal(r.value.restaurant_id, RESTO); assert.equal(r.value.request_id, REQ);
  assert.deepEqual(r.value.media, { id: ID, object_key: `${PREFIX}/${hash(real)}.mp4`, content_hash: hash(real), mime_type: 'video/mp4', width: 540, height: 864, duration_ms: 12042, bytes: 660459, published: true, url: `/storage/v1/object/public/${PUBLIC}/${PREFIX}/${hash(real)}.mp4` });
  assert.equal(state.engineCalls, 0); assert.equal(state.retired, 0); assert.equal(state.uploads, 1);
  assert.deepEqual(state.publicObjects.get(state.media.object_key), real);
  assert.equal(state.calls.filter(c => c.path.endsWith('/publish_storefront_welcome_video_v1')).length, 1);
  assert.equal(JSON.stringify(r.value).includes(KEY), false, 'private source key stays out of the response');
});
test('welcome replay: one original request id converges without a duplicate Storage upload', async () => {
  const { handle, state } = local(); assert.equal((await run(handle)).http, 200); const first = state.media.id;
  assert.equal((await run(handle)).http, 200); assert.equal(state.media.id, first); assert.equal(state.uploads, 1);
  assert.ok(state.calls.filter(c => c.params?.p_request_id).every(c => c.params.p_request_id === REQ));
});
test('welcome invalid/truncated bytes never reach register, public copy or image engine', async () => {
  for (const source of [new Uint8Array(40), real.subarray(0, real.length - 1)]) {
    const { handle, state } = local({ source }); const r = await run(handle); assert.equal(r.http, 422); assert.equal(r.value.status, 'refused');
    assert.equal(state.calls.some(c => c.path.endsWith('/register_storefront_welcome_video_v1')), false); assert.equal(state.uploads, 0); assert.equal(state.engineCalls, 0);
  }
});
test('welcome source metadata must name this immutable private key, MIME and exact actual byte length', async () => {
  for (const alter of [v => { v.source.bucket = PUBLIC; }, v => { v.source.key = KEY.replace(RESTO, ID); }, v => { v.source.mime_type = 'image/webp'; }, v => { v.source.bytes--; }]) {
    const { handle, state } = local({ alter: (phase, v) => { if (phase === 'preflight') alter(v); return v; } });
    assert.ok([422, 500].includes((await run(handle)).http)); assert.equal(state.uploads, 0); assert.equal(state.media, null);
  }
});
test('welcome staged/publication metadata cannot substitute another hash, dimension, id or URL', async () => {
  for (const phase of ['register', 'publish']) for (const edit of [v => { v.media.content_hash = 'b'.repeat(64); }, v => { v.media.width++; }, v => { v.media.extra = true; }, v => { v.media.url = 'https://outside.test/file.mp4'; }]) {
    const { handle } = local({ alter: (where, v) => { if (where === phase) edit(v); return v; } });
    const r = await run(handle); assert.equal(r.http, 500); assert.equal(r.value.uncertain, true);
  }
});
test('welcome public collision: equal raced bytes pass; wrong bytes and corrupt writes never finalize', async () => {
  const equal = local({ conflictRace: 'same' }); assert.equal((await run(equal.handle)).http, 200);
  for (const options of [{ conflictRace: 'different' }, { corruptUpload: true }]) {
    const { handle, state } = local(options); const r = await run(handle); assert.equal(r.http, 409); assert.equal(r.value.status, 'object_conflict');
    assert.equal(state.calls.some(c => c.path.endsWith('/publish_storefront_welcome_video_v1')), false); assert.equal(state.uploads, 1);
  }
});
test('welcome actual public-body read failure stays uncertain and never counts as original bytes', async () => {
  const { handle, state } = local({ publicBodyInterrupted: true }); const r = await run(handle);
  assert.equal(r.http, 503); assert.equal(r.value.uncertain, true);
  assert.equal(state.calls.some(c => c.path.endsWith('/publish_storefront_welcome_video_v1')), false); assert.equal(state.uploads, 1);
});
test('welcome missing/interrupted original and an actual oversized body stop before registration', async () => {
  for (const [options, http, code] of [[{ sourceMissing: true }, 404, null], [{ privateBodyInterrupted: true }, 503, null], [{ source: new Uint8Array(WELCOME_VIDEO_LIMITS.bytes + 1), alter: (phase, v) => { if (phase === 'preflight') v.source.bytes = WELCOME_VIDEO_LIMITS.bytes; return v; } }, 422, 'input_too_large']]) {
    const { handle, state } = local(options), r = await run(handle); assert.equal(r.http, http);
    if (code) assert.equal(r.value.code, code);
    if (http === 503) assert.equal(r.value.uncertain, false);
    assert.equal(state.calls.some(c => c.path.endsWith('/register_storefront_welcome_video_v1')), false); assert.equal(state.uploads, 0);
  }
});
test('welcome a lost public POST is not repeated and publication is not inferred', async () => {
  const route = `/storage/v1/object/${PUBLIC}/${PREFIX}/${hash(real)}.mp4`, { handle, state } = local({ breakAt: route }), r = await run(handle);
  assert.equal(r.http, 503); assert.equal(r.value.uncertain, true); assert.equal(state.calls.filter(c => c.path === route).length, 1);
  assert.equal(state.calls.some(c => c.path.endsWith('/publish_storefront_welcome_video_v1')), false);
});
test('welcome finalization cannot swap the registered id or claim an unpublished row as success', async () => {
  for (const edit of [v => { v.media.id = REQ; }, v => { v.media.published = false; v.media.url = null; }]) {
    const { handle } = local({ alter: (phase, v) => { if (phase === 'publish') edit(v); return v; } }), r = await run(handle);
    assert.equal(r.http, 500); assert.equal(r.value.uncertain, true);
  }
});
test('welcome upstream loss before stage is known, while stage/upload/finalize loss stays uncertain without retry', async () => {
  for (const [suffix, uncertain] of [['preflight_storefront_welcome_video_v1', false], ['register_storefront_welcome_video_v1', true], ['publish_storefront_welcome_video_v1', true]]) {
    const route = '/rest/v1/rpc/' + suffix, { handle, state } = local({ breakAt: route }), r = await run(handle);
    assert.equal(r.http, 503); assert.equal(r.value.uncertain, uncertain); assert.equal(state.calls.filter(c => c.path === route).length, 1);
  }
});
test('welcome typed database refusals remain bounded; unknown/extra envelope fields never pass', async () => {
  const expected = { permission_denied: 403, invalid: 400, not_found: 404, source_unavailable: 422, request_mismatch: 409, object_unavailable: 503, future_error: 500 };
  for (const [error, http] of Object.entries(expected)) {
    const { handle } = local({ alter: (phase, v) => phase === 'preflight' ? { ok: false, entity: ENTITY, error, ...(error === 'invalid' ? { field: 'source_key' } : {}) } : v });
    assert.equal((await run(handle)).http, http);
  }
  const extra = local({ alter: (phase, v) => { if (phase === 'preflight') v.extra = true; return v; } }); assert.equal((await run(extra.handle)).http, 500);
});
test('welcome unknown kind and mixed legacy image/video fields remain refused by the unchanged image validator', async () => {
  for (const request of [body({ kind: 'welcome_video_v2' }), body({ kind: 'constructor' }), body({ slot: 'hero' }), body({ source_bucket: PRIVATE })]) {
    const { handle, state } = local(); assert.equal((await run(handle, post(request))).http, 400); assert.equal(state.calls.length, 1); assert.equal(state.engineCalls, 0);
  }
});
