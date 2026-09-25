// STOREFRONT-PUBLISH-001 — recipe `storefront-media-c4` on the vendored jSquash codecs.
//
// Proves: the engine starts only on the pinned wasm and its embedded self-test vector
// (EDGE-4); every golden of test/goldens.mjs (sha-256, size, bytes, ladder trace) with
// its output structure; every hostile vector's typed refusal; the PNG image-data bound
// (EDGE-1: a 256 MiB compressible tail, junk after the stream, truncated streams, the
// Adam7 raw size, ancillary chunks inflating to 1 GiB never reaching the decoder); the
// 8 MiP decode-cap edge; alpha carried exactly (the derivative's alpha plane decoded
// with the vendored WebP decoder equals the pre-encode alpha); the EXIF orientations;
// metadata stripped; and the typed mapping of every codec failure, including which
// failures poison the engine.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createInflate, inflateSync } from 'node:zlib';
import {
  createDeriver, createDeriverFromCodecs, DerivationError, engineSelfTest, outputSize, RECIPE, SELF_TEST,
} from '../lib/recipe.mjs';
import { SourceRejected, sniffSource, webpInfo } from '../lib/sniff.mjs';
import { inflateExact, PIECE, PngRejected, pngRawSize, sanitizePng } from '../lib/pngbound.mjs';
import { applyOrientation } from '../lib/orient.mjs';
import { boxReduce } from '../lib/box.mjs';
import { codecs, deriver, readWasm } from './engine.mjs';
import { chunk, fixture, fixtureSpec, GPS_MARKER, JPEG_FIXTURE_SHA256, PNG_SIGNATURE, withSofSize } from './fixtures.mjs';
import { GOLDENS, REFUSALS, SPIKE_GOLDENS } from './goldens.mjs';

const sha = (b) => createHash('sha256').update(b).digest('hex');
const latin1 = (b) => Buffer.from(b).toString('latin1');

/** Drives the ladder as the handler's caller does: ONE rung per derive() call. */
async function ladder(d, bytes, variant, source, { inspect = false } = {}) {
  const trace = [];
  for (let rung = 0; rung < RECIPE.ladder.length; rung++) {
    const r = await d.derive(bytes, { variant, source, rung, inspect });
    trace.push(`q${r.attempt.quality}:${r.attempt.bytes}${r.status === 'derived' ? '' : '>cap'}`);
    if (r.status === 'derived') return { r, trace: trace.join(' ') };
    assert.equal(r.status, 'ladder_next');
    assert.equal(r.nextRung, rung + 1);
    assert.equal(r.bytes, undefined, 'an over-cap rung returns no bytes');
  }
  throw new Error('the ladder did not end');
}

/** The PNG chunk types, in order. */
function pngChunkTypes(b) {
  const out = []; let o = 8;
  while (o + 8 <= b.length) { const len = Buffer.from(b).readUInt32BE(o); out.push(latin1(b.subarray(o + 4, o + 8))); o += 12 + len; }
  return out;
}
/** The concatenated IDAT data of a PNG. */
function idatOf(b) {
  const parts = []; let o = 8; const B = Buffer.from(b);
  while (o + 8 <= B.length) { const len = B.readUInt32BE(o); if (B.toString('latin1', o + 4, o + 8) === 'IDAT') parts.push(B.subarray(o + 8, o + 8 + len)); o += 12 + len; }
  return Buffer.concat(parts);
}
/** The data of the first chunk of a type. */
function chunkData(b, type) {
  let o = 8; const B = Buffer.from(b);
  while (o + 8 <= B.length) { const len = B.readUInt32BE(o); if (B.toString('latin1', o + 4, o + 8) === type) return B.subarray(o + 8, o + 8 + len); o += 12 + len; }
  return null;
}
/** Bytes a zlib stream inflates to, counted while streaming (never held). */
function inflatedLength(z) {
  return new Promise((resolve, reject) => {
    let n = 0;
    const s = createInflate();
    s.on('data', (c) => { n += c.length; });
    s.on('end', () => resolve(n));
    s.on('error', reject);
    s.end(z);
  });
}

// ------------------------------------------------------------------ engine start
test('R0. the committed JPEG fixtures are the four pinned files, < 300 KB in total', async () => {
  const dir = new URL('./fixtures/', import.meta.url);
  assert.deepEqual((await readdir(dir)).sort(), ['README.md', 'base_420_900x450.jpg', 'base_444_1200x900.jpg', 'gray_prog_1000x750.jpg', 'prog_420_1600x1200.jpg']);
  const readme = await readFile(new URL('README.md', dir), 'utf8');
  let total = 0;
  for (const [name, pinned] of JPEG_FIXTURE_SHA256) {
    const b = await readFile(new URL(name, dir));
    total += b.length;
    assert.equal(sha(b), pinned, name);
    assert.ok(readme.includes(pinned) && readme.includes(name), `README records ${name}`);
  }
  assert.ok(total < 300000, `${total} bytes`);
});

test('R1. createDeriver refuses to start unless every wasm matches its pin, before anything is compiled', async () => {
  const wasm = await readWasm();
  const compile = WebAssembly.compile;
  let compiles = 0;
  WebAssembly.compile = (...a) => { compiles++; return compile(...a); };
  try {
    for (const key of RECIPE.engine.wasmKeys) {
      const tampered = { ...wasm, [key]: Uint8Array.from(wasm[key]) };
      tampered[key][tampered[key].length - 1] ^= 1;
      await assert.rejects(createDeriver(tampered), (e) => e instanceof DerivationError && e.code === 'engine_unavailable' && e.message.includes(key), `${key} tampered`);
      const missing = { ...wasm };
      delete missing[key];
      await assert.rejects(createDeriver(missing), (e) => e instanceof DerivationError && e.code === 'engine_unavailable', `${key} missing`);
    }
    // two valid pinned modules under each other's names
    await assert.rejects(createDeriver({ ...wasm, png: wasm.resize, resize: wasm.png }), (e) => e.code === 'engine_unavailable');
    await assert.rejects(createDeriver(null), (e) => e.code === 'engine_unavailable');
  } finally {
    WebAssembly.compile = compile;
  }
  assert.equal(compiles, 0, 'no wasm was compiled for a refused engine');
});

test('R2. EDGE-4: the embedded vector reproduces its pinned golden; any mismatch poisons the engine as engine_unavailable', async () => {
  const d = await deriver(); // createDeriver() already ran the self-test once
  assert.match(String(createDeriver), /await engineSelfTest\(deriver\);\s*return deriver;/, 'the verified entry point self-tests before it returns');
  const r = await engineSelfTest(d);
  assert.equal(r.sha256, SELF_TEST.sha256);
  assert.deepEqual([r.width, r.height, r.byteLength], [480, 192, 3710]);
  assert.deepEqual(r.chunks, ['VP8X', 'ALPH', 'VP8'], 'the self-test covers the alpha encode');
  assert.deepEqual([r.source.width, r.source.height], [1000, 400], 'k = 2 box pre-reduction, then the resize');
  assert.ok(SELF_TEST.pngBase64.length < 1500, 'a small embedded PNG');
  // a wrong golden
  const other = createDeriverFromCodecs(await codecs());
  await assert.rejects(engineSelfTest(other, '0'.repeat(64)), (e) => e instanceof DerivationError && e.code === 'engine_unavailable');
  assert.equal(other.poisoned, true);
  await assert.rejects(other.derive(await fixture('logo_small_300x150'), { variant: 'w480', source: 'restaurant-logos' }), (e) => e.code === 'engine_unavailable');
  // an engine whose output drifted (a platform change simulated: the encoder answers other bytes)
  const real = await codecs();
  const drifted = createDeriverFromCodecs({ ...real, encodeWebp: (rgba, w, h, opts) => real.encodeWebp(rgba, w, h, { ...opts, quality: opts.quality - 1 }) });
  await assert.rejects(engineSelfTest(drifted), (e) => e.code === 'engine_unavailable');
  assert.equal(drifted.poisoned, true);
  // an engine that fails the vector outright
  const broken = createDeriverFromCodecs({ ...real, decodePng: async () => { throw new Error('boom'); } });
  await assert.rejects(engineSelfTest(broken), (e) => e.code === 'engine_unavailable');
  assert.equal(d.poisoned, false, 'the shared engine is untouched');
});

test('R3. the recipe constants are c4 and frozen', () => {
  assert.equal(RECIPE.id, 'storefront-media-c4');
  assert.ok(Object.isFrozen(RECIPE) && Object.isFrozen(RECIPE.caps) && Object.isFrozen(RECIPE.webp) && Object.isFrozen(RECIPE.engine.files));
  assert.deepEqual({ ...RECIPE.caps }, {
    decodeMaxPixels: 8388608, maxSide: 8192, maxPixels: 8388608, jpegMaxSide: 8192, jpegMaxPixels: 8388608, jpegMaxScans: 16,
    jpegMaxProgressiveCoefficientBytes: 33554432, jpegMaxProgressiveScanWork: 400000000, maxAspect: 8, maxMetadataBytes: 1048576,
    pngMaxRawBytes: 33570816,
    pngMaxChunks: 65536, pngMaxAncillaryChunks: 32, pngMaxIccp: 1, pngMaxCompressedText: 4, webpMaxChunks: 16,
  });
  assert.deepEqual([...RECIPE.ladder], [82, 74, 66, 58, 50]);
  assert.equal(RECIPE.maxOutputBytes, 524288);
  assert.deepEqual({ ...RECIPE.resize }, { filter: 'triangle', method: 0, premultiply: true, linearRGB: false });
  assert.equal(RECIPE.box.minFactor, 2);
  const w = RECIPE.webp;
  assert.deepEqual([w.method, w.exact, w.alpha_quality, w.alpha_compression, w.alpha_filtering, w.lossless, w.use_sharp_yuv, w.thread_level, w.target_size, w.pass],
    [2, 1, 100, 1, 1, 0, 0, 0, 0, 1]);
  assert.deepEqual(RECIPE.engine.packages.map((p) => p.join('@')), ['@jsquash/png@3.1.1', '@jsquash/jpeg@1.6.0', '@jsquash/webp@1.5.0', '@jsquash/resize@2.1.1']);
});

test('R4. output geometry and the box pre-reduction are exact integer arithmetic', () => {
  assert.deepEqual(outputSize(2000, 1000, 480), { width: 480, height: 240 });
  assert.deepEqual(outputSize(600, 1800, 480), { width: 160, height: 480 }, 'W x W box: the long side is capped');
  assert.deepEqual(outputSize(300, 150, 480), { width: 300, height: 150 }, 'never upscale');
  assert.deepEqual(outputSize(777, 555, 480), { width: 480, height: 343 }, 'round half up');
  assert.deepEqual(outputSize(8192, 1024, 480), { width: 480, height: 60 });
  // premultiplied: a fully transparent pixel never bleeds its colour into the block
  const src = new Uint8Array([255, 0, 0, 255, 0, 0, 255, 0, 255, 0, 0, 255, 0, 0, 255, 0]); // 2 x 2: red opaque | blue transparent
  assert.deepEqual([...boxReduce(src, 2, 2, 2).data], [255, 0, 0, 128]);
  // edge blocks average only what they cover (3 x 1 with k = 2 -> 2 x 1)
  const edge = boxReduce(new Uint8Array([10, 10, 10, 255, 20, 20, 20, 255, 99, 98, 97, 255]), 3, 1, 2);
  assert.deepEqual([edge.width, edge.height, ...edge.data], [2, 1, 15, 15, 15, 255, 99, 98, 97, 255]);
});

// ------------------------------------------------------------------ goldens
for (const [name, variant, hash, width, height, bytes, trace] of GOLDENS) {
  test(`R5. golden ${name} ${variant}`, async () => {
    const d = await deriver();
    const { r, trace: got } = await ladder(d, await fixture(name), variant, fixtureSpec(name).bucket);
    assert.equal(got, trace, 'the ladder trace, one rung per call');
    assert.equal(r.sha256, hash);
    assert.equal(sha(r.bytes), r.sha256, 'the reported hash is the hash of the returned bytes');
    assert.deepEqual([r.width, r.height, r.byteLength, r.bytes.length], [width, height, bytes, bytes]);
    const w = webpInfo(r.bytes);
    assert.deepEqual([w.width, w.height], [width, height], 'the size is read from the actual output');
    assert.deepEqual(w.chunks.map((c) => c.tag.trim()), r.hasAlpha ? ['VP8X', 'ALPH', 'VP8'] : ['VP8']);
    assert.ok(!w.animated && !w.metadataFlags.icc && !w.metadataFlags.exif && !w.metadataFlags.xmp, 'no animation, ICC, EXIF or XMP');
    assert.ok(Math.max(r.width, r.height) <= Number(variant.slice(1)) && r.byteLength <= RECIPE.maxOutputBytes);
  });
}

test('R6. the golden set covers the brief: every PNG / JPEG / WebP shape, all 8 orientations, the three ladder bands', () => {
  const names = new Set(GOLDENS.map((g) => g.slice(0, 2).join(' ')));
  for (const n of ['logo_alpha_2000x1000 w480', 'logo_opaque_rgb_1200x600 w480', 'palette_trns_640x320 w480', 'gray_800x400 w480', 'gray_alpha_800x400 w480',
    'rgba16_800x400 w480', 'adam7_rgba_777x555 w480', 'rgba_all_opaque_800x400 w480', 'logo_small_300x150 w960', 'jpeg_prog_1600x1200 w960',
    'jpeg_base_444_1200x900 w960', 'jpeg_gray_1000x750 w960', 'webp_lossy_alpha_900x600 w960', 'webp_lossless_alpha_1200x800 w960',
    'webp_lossy_opaque_1300x900 w960', 'band_q74 w960', 'band_alpha_q50 w960', 'png_at_cap_4096x2048 w960', 'jpeg_exif_gps w480', 'meta_png_with_ancillary w480']) {
    assert.ok(names.has(n), n);
  }
  for (let o = 1; o <= 8; o++) assert.ok(names.has(`jpeg_orient_${o} w960`), `orientation ${o}`);
  assert.ok(REFUSALS.some((r) => r[0] === 'band_none' && r[2] === 'output_too_large'), 'no rung fits');
  assert.ok(REFUSALS.some((r) => r[0] === 'entropy_webp_lossless' && r[2] === 'output_too_large'), 'the alpha floor');
  assert.equal(SPIKE_GOLDENS.length, 35);
});

test('R7. the same source derives to the same bytes on every call (fresh codec instances included)', async () => {
  const d = await deriver();
  for (const name of ['logo_alpha_2000x1000', 'jpeg_prog_1600x1200', 'webp_lossy_alpha_900x600']) {
    const spec = fixtureSpec(name);
    const a = await d.derive(await fixture(name), { variant: spec.variants[0], source: spec.bucket, rung: 0 });
    const b = await d.derive(await fixture(name), { variant: spec.variants[0], source: spec.bucket, rung: 0 });
    assert.deepEqual(a.bytes, b.bytes, name);
  }
});

// ------------------------------------------------------------------ refusals
for (const [name, variant, code, rung] of REFUSALS) {
  test(`R8. refusal ${name} ${variant} -> ${code}`, async () => {
    const d = await deriver();
    const bytes = await fixture(name);
    const source = fixtureSpec(name).bucket;
    for (let r = 0; r < rung; r++) assert.equal((await d.derive(bytes, { variant, source, rung: r })).status, 'ladder_next', `rung ${r}`);
    await assert.rejects(d.derive(bytes, { variant, source, rung }), (e) => {
      assert.ok(e instanceof SourceRejected || e instanceof DerivationError, `${e && e.name}: ${e && e.message}`);
      assert.equal(e.code, code, e.message);
      assert.ok(!/^(\w+): \1:/.test(e.message), `no doubled prefix: ${e.message}`);
      return true;
    });
    assert.equal(d.poisoned, false, 'a typed refusal of a source never poisons the engine');
  });
}

test('R8b. a 4-component (CMYK / YCCK) JPEG is refused by the sniff, before any decoder runs', async () => {
  const cmyk = await fixture('bad_jpeg_cmyk');
  assert.throws(() => sniffSource(cmyk, { ...RECIPE.caps, maxInputBytes: 5242880 }),
    (e) => e instanceof SourceRejected && e.code === 'unsupported_format' && e.message === 'unsupported_format: jpeg with 4 components (CMYK/YCCK)');
  const real = await codecs();
  let decodes = 0;
  const d = createDeriverFromCodecs({ ...real, decodeJpeg: async (u8) => { decodes++; return real.decodeJpeg(u8); } });
  await assert.rejects(d.derive(cmyk, { variant: 'w960', source: 'menu-images', rung: 0 }), (e) => e.code === 'unsupported_format');
  assert.equal(decodes, 0);
});

test('R9. the alpha-chunk floor ends the ladder at rung 0; no later rung is tried', async () => {
  const d = await deriver();
  await assert.rejects(d.derive(await fixture('entropy_webp_lossless'), { variant: 'w960', source: 'menu-images', rung: 0 }),
    (e) => e.code === 'output_too_large' && JSON.parse(e.message.slice('output_too_large: '.length)).reason === 'alpha_chunk_exceeds_cap');
  await assert.rejects(d.derive(await fixture('band_none'), { variant: 'w960', source: 'menu-images', rung: 4 }),
    (e) => e.code === 'output_too_large' && JSON.parse(e.message.slice('output_too_large: '.length)).reason === 'every_rung_exceeds_cap');
});

// ------------------------------------------------------------------ EDGE-1: the PNG image-data bound
test('R10. EDGE-1: a 256 MiB compressible IDAT tail passes every pre-decode cap and is refused as corrupt within one chunk of the raw size', async () => {
  const d = await deriver();
  const bytes = await fixture('bomb_idat_tail_256mib');
  assert.ok(bytes.length < 2097152, 'it fits the logo bucket');
  assert.equal(sniffSource(bytes, { ...RECIPE.caps, maxInputBytes: 2097152 }).width, 640, 'the container passes the sniff');
  const expected = pngRawSize(640, 480, 8, 6, 0);
  assert.equal(expected, 1229280);
  const t = performance.now();
  await assert.rejects(d.derive(bytes, { variant: 'w480', source: 'restaurant-logos', rung: 0 }),
    (e) => e instanceof SourceRejected && e.code === 'corrupt' && e.message === `corrupt: png image data inflates beyond the ${expected} B the header implies`);
  const ms = performance.now() - t;
  await assert.rejects(inflateExact([idatOf(bytes)], expected), (e) => {
    assert.ok(e instanceof PngRejected && e.produced > expected && e.produced <= expected + 1048576, `stopped after ${e.produced} B`);
    return true;
  });
  assert.ok(ms < 1500, `refused in ${ms.toFixed(0)} ms`);
  // the inflater is fed in PIECE-byte steps (the edge runtime inflates each written chunk
  // whole before the reader sees it: one 260 KB write of this tail exceeded 256 MB there)
  const Real = globalThis.DecompressionStream;
  let maxWrite = 0, writes = 0;
  globalThis.DecompressionStream = function (format) {
    const inner = new Real(format);
    const tap = new TransformStream({ transform(chunk, c) { writes++; maxWrite = Math.max(maxWrite, chunk.length); c.enqueue(chunk); } });
    tap.readable.pipeTo(inner.writable).catch(() => {});
    return { writable: tap.writable, readable: inner.readable };
  };
  try {
    await assert.rejects(inflateExact([idatOf(bytes)], expected), (e) => e instanceof PngRejected && e.code === 'corrupt');
  } finally {
    globalThis.DecompressionStream = Real;
  }
  assert.ok(writes > 1 && maxWrite <= PIECE && PIECE <= 4096, `${writes} writes of at most ${maxWrite} B`);
});

test('R11. EDGE-1: the zlib wrapper is checked the same on every runtime (junk after the stream, cut trailer, wrong checksum, bad header)', async () => {
  const raw = Buffer.alloc(1001 * 10, 7);
  for (let y = 0; y < 10; y++) raw[y * 1001] = 0;
  const z = (await import('node:zlib')).deflateSync(raw);
  assert.equal(await inflateExact([z], raw.length), raw.length, 'a valid stream');
  assert.equal(await inflateExact([z.subarray(0, 5), z.subarray(5)], raw.length), raw.length, 'split across IDAT chunks');
  const bad = [
    ['junk after the stream', Buffer.concat([z, Buffer.from([1, 2, 3, 4, 5])])],
    ['one junk byte', Buffer.concat([z, Buffer.from([0])])],
    ['trailer cut', z.subarray(0, z.length - 4)],
    ['trailer cut by one byte', z.subarray(0, z.length - 1)],
    ['wrong checksum', Buffer.concat([z.subarray(0, z.length - 1), Buffer.from([z[z.length - 1] ^ 1])])],
    ['deflate data cut', z.subarray(0, Math.floor(z.length / 2))],
    ['preset dictionary flag', Buffer.concat([Buffer.from([0x78, 0xbb]), z.subarray(2)])],
    ['not deflate', Buffer.concat([Buffer.from([0x79, 0x9c - 1]), z.subarray(2)])],
    ['empty', Buffer.alloc(0)],
  ];
  for (const [label, data] of bad) {
    await assert.rejects(inflateExact([data], raw.length), (e) => e instanceof PngRejected && e.code === 'corrupt', label);
  }
  // Documented residual: a second copy of the stream ends with the SAME checksum. Node 24 and the edge
  // runtime refuse any data after the end of the stream; Node 22's inflater ignores it (and the trailer
  // check cannot tell), so there it passes the bound and the PNG decoder decides.
  const probe = new DecompressionStream('deflate');
  const pw = probe.writable.getWriter();
  const fed = pw.write(Buffer.concat([z, Buffer.from([0])])).then(() => pw.close()).catch(() => {});
  const rejectsTrailing = await new Response(probe.readable).arrayBuffer().then(() => false, () => true);
  await fed;
  if (rejectsTrailing) await assert.rejects(inflateExact([Buffer.concat([z, z])], raw.length), (e) => e.code === 'corrupt', 'a second stream');
  else assert.equal(await inflateExact([Buffer.concat([z, z])], raw.length), raw.length, 'Node 22 residual: a second identical stream');
  await assert.rejects(inflateExact([z], raw.length + 1), (e) => e.code === 'corrupt', 'a stream shorter than the raw size');
  await assert.rejects(inflateExact([z], raw.length - 1), (e) => e.code === 'corrupt', 'a stream longer than the raw size');
});

test('R12. EDGE-1: the raw size is exact for every colour type, bit depth and the Adam7 layout', async () => {
  for (const name of ['palette_trns_640x320', 'gray_800x400', 'gray_alpha_800x400', 'rgba16_800x400', 'adam7_rgba_777x555', 'logo_opaque_rgb_1200x600', 'logo_alpha_2000x1000']) {
    const b = Buffer.from(await fixture(name));
    const ihdr = chunkData(b, 'IHDR');
    const size = pngRawSize(ihdr.readUInt32BE(0), ihdr.readUInt32BE(4), ihdr[8], ihdr[9], ihdr[12]);
    assert.equal(size, inflateSync(idatOf(b)).length, name);
  }
  // Adam7 corner cases: images smaller than the 8 x 8 pattern leave passes empty
  assert.equal(pngRawSize(1, 1, 8, 6, 1), 1 + 4);
  assert.equal(pngRawSize(3, 2, 8, 0, 1), (1 + 1) + (1 + 1) + (1 + 1) + (1 + 3)); // passes 1, 4 (x=2), 6 (x=1), 7 (row 1: 3 px)
  assert.equal(pngRawSize(8, 8, 1, 0, 0), 8 * 2, '1-bit gray rows round up to whole bytes');
});

test('R13. EDGE-1: ancillary chunks inflating to 1 GiB (zTXt / iTXt / iCCP) pass the sniff and never reach the decoder', async () => {
  const d = await deriver();
  const plain = await d.derive(await fixture('plain_700x350'), { variant: 'w480', source: 'restaurant-logos', rung: 0 });
  let checkedInflate = false;
  for (const [name, type] of [['bomb_ztxt_1gib', 'zTXt'], ['bomb_itxt_1gib', 'iTXt'], ['bomb_iccp_1gib', 'iCCP']]) {
    const bytes = await fixture(name);
    const data = chunkData(bytes, type);
    assert.ok(data.length <= RECIPE.caps.maxMetadataBytes, `${type}: ${data.length} B is within the metadata cap, so only the strip protects the decoder`);
    if (!checkedInflate) {
      const z = data.subarray(data.indexOf(0x78)); // the zlib stream after the chunk's text header
      assert.equal(await inflatedLength(z), 1 << 30, 'the compressed payload inflates to exactly 1 GiB');
      checkedInflate = true;
    }
    assert.equal(sniffSource(bytes, { ...RECIPE.caps, maxInputBytes: 2097152 }).type, 'png');
    const kept = await sanitizePng(bytes);
    assert.deepEqual(pngChunkTypes(kept), ['IHDR', 'IDAT', 'IEND'], `${type} is not handed to the decoder`);
    const t = performance.now();
    const r = await d.derive(bytes, { variant: 'w480', source: 'restaurant-logos', rung: 0 });
    assert.equal(r.sha256, plain.sha256, `${type}: the same derivative as without the chunk`);
    assert.ok(performance.now() - t < 1500, `${type}: derived in ${(performance.now() - t).toFixed(0)} ms`);
  }
  // PLTE and tRNS are kept (the pixels depend on them); everything else ancillary goes
  assert.deepEqual(pngChunkTypes(await sanitizePng(await fixture('palette_trns_640x320'))), ['IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND']);
  assert.deepEqual(pngChunkTypes(await fixture('meta_png_with_ancillary')), ['IHDR', 'tEXt', 'eXIf', 'gAMA', 'IDAT', 'IEND']);
  assert.deepEqual(pngChunkTypes(await sanitizePng(await fixture('meta_png_with_ancillary'))), ['IHDR', 'IDAT', 'IEND']);
});

// ------------------------------------------------------------------ the 8 MiP decode cap
test('R14. the 8 MiP cap edge: 4096 x 2048 (exactly 8,388,608 px) derives; one row more is too_many_pixels before any inflate', async () => {
  const d = await deriver();
  const at = await fixture('png_at_cap_4096x2048');
  const info = sniffSource(at, { ...RECIPE.caps, maxInputBytes: 5242880 });
  assert.equal(info.width * info.height, RECIPE.caps.decodeMaxPixels);
  assert.equal((await d.derive(at, { variant: 'w960', source: 'menu-images', rung: 0 })).status, 'derived');
  const over = await fixture('png_over_cap_4096x2049');
  const t = performance.now();
  await assert.rejects(d.derive(over, { variant: 'w960', source: 'menu-images', rung: 0 }), (e) => e instanceof SourceRejected && e.code === 'too_many_pixels');
  assert.ok(performance.now() - t < 200, 'refused on the header alone');
  for (const name of ['jpeg_over_cap_sof', 'webp_over_cap_header', 'png_over_cap_header']) {
    const spec = fixtureSpec(name);
    await assert.rejects(d.derive(await fixture(name), { variant: spec.variants[0], source: spec.bucket, rung: 0 }), (e) => e.code === 'too_many_pixels', name);
  }
});

// ------------------------------------------------------------------ the memory envelope (reused workers)
test('R14b. the PNG image-data budget (32 MiB, from the IHDR) and the progressive-JPEG coefficient budget (32 MiB) refuse before any inflate / decode', async () => {
  const d = await deriver();
  assert.equal(RECIPE.caps.pngMaxRawBytes, 33570816);
  assert.equal(RECIPE.caps.jpegMaxProgressiveCoefficientBytes, 33554432);
  // 16-bit RGBA, 2049 x 2048: ~4 MiP (under the pixel cap) but 33,572,864 B of image data -> refused on the header
  const ihdr16 = (w, h, interlace) => { const b = Buffer.alloc(13); b.writeUInt32BE(w, 0); b.writeUInt32BE(h, 4); b[8] = 16; b[9] = 6; b[12] = interlace; return b; };
  const header16 = (w, h, interlace = 0) => new Uint8Array(Buffer.concat([PNG_SIGNATURE, chunk('IHDR', ihdr16(w, h, interlace)), chunk('IDAT', Buffer.from([0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01])), chunk('IEND', Buffer.alloc(0))]));
  assert.equal(pngRawSize(2049, 2048, 16, 6, 0), 33572864);
  for (const [w, h, il] of [[2049, 2048, 0], [2049, 2048, 1], [2896, 2896, 0]]) {
    const t = performance.now();
    await assert.rejects(d.derive(header16(w, h, il), { variant: 'w960', source: 'menu-images', rung: 0 }), (e) => e instanceof SourceRejected && e.code === 'too_many_pixels' && /image data/.test(e.message), `${w}x${h} il${il}`);
    assert.ok(performance.now() - t < 200, 'refused on the header alone');
  }
  // 16-bit RGBA 2048 x 2048 (33,556,480 B) is within the budget and reaches the image-data bound
  assert.ok(pngRawSize(2048, 2048, 16, 6, 0) <= RECIPE.caps.pngMaxRawBytes);
  await assert.rejects(d.derive(header16(2048, 2048), { variant: 'w960', source: 'menu-images', rung: 0 }), (e) => e.code === 'corrupt');
  // every 8-bit RGBA PNG at the pixel cap stays admitted (R14), plain and Adam7, any shape up to the side cap
  for (const [w, h] of [[4096, 2048], [2048, 4096], [8192, 1024], [1024, 8192], [2896, 2896]]) for (const il of [0, 1]) assert.ok(pngRawSize(w, h, 8, 6, il) <= RECIPE.caps.pngMaxRawBytes, w + "x" + h + " il" + il);
  // progressive 4:4:4 at 8 MiP needs ~48 MiB of coefficients -> refused; 4:2:0 at 8 MiP (~24 MiB) passes the sniff
  const base = await fixture('jpeg_prog_1600x1200');
  const withComps = (j, w, h, sampling) => { const b = Buffer.from(withSofSize(j, w, h)); let o = 2; while (o < b.length) { const m = b[o + 1]; if (m === 0xc0 || m === 0xc1 || m === 0xc2) break; o += 2 + b.readUInt16BE(o + 2); } assert.equal(b[o + 9], 3); for (let i = 0; i < 3; i++) b[o + 11 + 3 * i] = sampling[i]; return new Uint8Array(b); };
  const p444 = withComps(base, 4096, 2048, [0x11, 0x11, 0x11]);
  assert.throws(() => sniffSource(p444, { ...RECIPE.caps, maxInputBytes: 5242880 }), (e) => e instanceof SourceRejected && e.code === 'too_many_pixels' && /coefficient/.test(e.message));
  const p420 = withComps(base, 4096, 2048, [0x22, 0x11, 0x11]);
  const info = sniffSource(p420, { ...RECIPE.caps, maxInputBytes: 5242880 });
  assert.equal(info.width * info.height, RECIPE.caps.decodeMaxPixels);
});

// ------------------------------------------------------------------ alpha, orientation, metadata
test('R15. alpha is carried EXACTLY: the derivative decoded with the vendored WebP decoder has the pre-encode alpha plane; opaque outputs are opaque', async () => {
  const d = await deriver();
  const c = await codecs();
  let alphaChecked = 0, opaqueChecked = 0;
  for (const [name, variant] of GOLDENS) {
    const { r } = await ladder(d, await fixture(name), variant, fixtureSpec(name).bucket, { inspect: true });
    const back = await c.decodeWebp(r.bytes);
    assert.deepEqual([back.width, back.height], [r.width, r.height], name);
    if (r.hasAlpha) {
      for (let i = 3; i < r.preEncode.length; i += 4) {
        if (back.data[i] !== r.preEncode[i]) assert.fail(`${name} ${variant}: alpha differs at pixel ${i >> 2}: ${back.data[i]} != ${r.preEncode[i]}`);
      }
      assert.ok(r.preEncode.some((v, i) => i % 4 === 3 && v !== 255), `${name}: really has alpha`);
      alphaChecked++;
    } else {
      for (let i = 3; i < back.data.length; i += 4) if (back.data[i] !== 255) assert.fail(`${name} ${variant}: opaque output is not opaque`);
      opaqueChecked++;
    }
  }
  assert.ok(alphaChecked >= 25 && opaqueChecked >= 15, `${alphaChecked} alpha / ${opaqueChecked} opaque derivatives checked`);
});

test('R16. EXIF orientation: the 8 definitions on a labelled raster, and each oriented derivative equals the orientation-1 pixels transformed', async () => {
  const w = 3, h = 2, src = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) src[i * 4] = i;
  const expect = {
    1: [[0, 1, 2], [3, 4, 5]], 2: [[2, 1, 0], [5, 4, 3]], 3: [[5, 4, 3], [2, 1, 0]], 4: [[3, 4, 5], [0, 1, 2]],
    5: [[0, 3], [1, 4], [2, 5]], 6: [[3, 0], [4, 1], [5, 2]], 7: [[5, 2], [4, 1], [3, 0]], 8: [[2, 5], [1, 4], [0, 3]],
  };
  for (let o = 1; o <= 8; o++) {
    const r = applyOrientation(src, w, h, o);
    const rows = [];
    for (let y = 0; y < r.height; y++) { const row = []; for (let x = 0; x < r.width; x++) row.push(r.data[(y * r.width + x) * 4]); rows.push(row); }
    assert.deepEqual(rows, expect[o], `orientation ${o}`);
  }
  const d = await deriver();
  const base = await d.derive(await fixture('jpeg_orient_1'), { variant: 'w960', source: 'menu-images', rung: 0, inspect: true });
  for (let o = 2; o <= 8; o++) {
    const r = await d.derive(await fixture(`jpeg_orient_${o}`), { variant: 'w960', source: 'menu-images', rung: 0, inspect: true });
    assert.equal(r.orientation, o);
    const t = applyOrientation(base.preEncode, base.width, base.height, o);
    assert.deepEqual([t.width, t.height], [r.width, r.height], `orientation ${o} geometry`);
    assert.ok(Buffer.from(t.data).equals(Buffer.from(r.preEncode)), `orientation ${o} pixels`);
  }
  // a PNG eXIf orientation is never applied (it is stripped like every ancillary chunk)
  const meta = await d.derive(await fixture('meta_png_with_ancillary'), { variant: 'w960', source: 'restaurant-logos', rung: 0 });
  assert.deepEqual([meta.orientation, meta.width, meta.height], [1, 700, 350]);
});

test('R17. metadata is stripped: EXIF GPS in a JPEG, tEXt in a PNG, ICCP / EXIF / XMP in a WebP never reach the output', async () => {
  const d = await deriver();
  const cases = [
    ['jpeg_exif_gps', 'jpeg_logo_900x450', 'w480', [GPS_MARKER, 'Exif']],
    ['meta_png_with_ancillary', 'plain_700x350', 'w480', ['private-text', 'Comment', 'MM\0*']],
    ['webp_with_metadata', 'webp_lossy_alpha_900x600', 'w960', [GPS_MARKER, 'RF-PRIVATE-ICC', 'xmpmeta']],
  ];
  for (const [name, plainName, variant, markers] of cases) {
    const src = await fixture(name);
    for (const m of markers) assert.ok(latin1(src).includes(m), `${name} source carries ${JSON.stringify(m)}`);
    const r = await d.derive(src, { variant, source: fixtureSpec(name).bucket, rung: 0 });
    const plain = await d.derive(await fixture(plainName), { variant, source: fixtureSpec(plainName).bucket, rung: 0 });
    assert.equal(r.sha256, plain.sha256, `${name}: identical to the same pixels without metadata`);
    for (const m of [...markers, 'ICCP', 'EXIF', 'XMP ']) assert.ok(!latin1(r.bytes).includes(m), `${name} output has no ${JSON.stringify(m)}`);
  }
});

// ------------------------------------------------------------------ typed failure mapping (fake codecs)
test('R18. codec failures map to the public codes; a trap or an exception out of a one-per-worker module poisons the engine', async () => {
  const real = await codecs();
  const png = await fixture('logo_alpha_2000x1000');
  const jpeg = await fixture('jpeg_logo_900x450');
  const webp = await fixture('webp_lossy_alpha_900x600');
  const trap = () => { throw new WebAssembly.RuntimeError('unreachable'); };
  const boom = () => { throw new Error('codec said no'); };
  const cases = [
    // [label, codec overrides, source, expected code, poisoned?]
    ['PNG decoder throws (wasm-bindgen: no unwind)', { decodePng: boom }, png, 'decode_failed', true],
    ['PNG decoder traps', { decodePng: trap }, png, 'engine_unavailable', true],
    ['JPEG decoder throws (fresh instance)', { decodeJpeg: boom }, jpeg, 'decode_failed', false],
    ['JPEG decoder traps', { decodeJpeg: trap }, jpeg, 'engine_unavailable', true],
    ['JPEG decoder warns', { decodeJpeg: async (u8) => ({ ...(await real.decodeJpeg(u8)), warnings: ['Corrupt JPEG data: 1 extraneous bytes'] }) }, jpeg, 'decode_warning', false],
    ['WebP decoder throws (fresh instance)', { decodeWebp: boom }, webp, 'decode_failed', false],
    ['WebP decoder traps', { decodeWebp: trap }, webp, 'engine_unavailable', true],
    ['decoder returns nothing', { decodePng: async () => null }, png, 'decode_failed', false],
    ['decoded size differs from the header', { decodePng: async (u8) => { const i = await real.decodePng(u8); return { width: i.width - 1, height: i.height, data: i.data }; } }, png, 'corrupt', false],
    ['resize throws (wasm-bindgen)', { resize: boom }, png, 'decode_failed', true],
    ['resize traps', { resize: trap }, png, 'engine_unavailable', true],
    ['resize returns the wrong size', { resize: () => new Uint8Array(4) }, png, 'self_check_failed', false],
    ['encoder throws (fresh instance)', { encodeWebp: boom }, png, 'decode_failed', false],
    ['encoder traps', { encodeWebp: trap }, png, 'engine_unavailable', true],
    ['encoder returns garbage', { encodeWebp: async () => new Uint8Array([1, 2, 3]) }, png, 'self_check_failed', false],
  ];
  for (const [label, overrides, src, code, poisoned] of cases) {
    const d = createDeriverFromCodecs({ ...real, ...overrides });
    await assert.rejects(d.derive(src, { variant: 'w480', source: 'menu-images', rung: 0 }), (e) => e.code === code, label);
    assert.equal(d.poisoned, poisoned, `${label}: poisoned`);
    if (poisoned) await assert.rejects(d.derive(await fixture('logo_small_300x150'), { variant: 'w480', source: 'menu-images', rung: 0 }), (e) => e.code === 'engine_unavailable', `${label}: later calls refused`);
  }
});

test('R19. the output self-check refuses any WebP that is not exactly the canonical structure', async () => {
  const real = await codecs();
  const alpha = await fixture('logo_alpha_2000x1000'); // derives VP8X,ALPH,VP8
  const opaque = await fixture('logo_opaque_rgb_1200x600'); // derives VP8
  const good = { alpha: (await (await deriver()).derive(alpha, { variant: 'w480', source: 'restaurant-logos', rung: 0 })).bytes,
    opaque: (await (await deriver()).derive(opaque, { variant: 'w480', source: 'restaurant-logos', rung: 0 })).bytes,
    small: (await (await deriver()).derive(await fixture('logo_small_300x150'), { variant: 'w480', source: 'restaurant-logos', rung: 0 })).bytes };
  const riff = (chunks) => {
    const body = Buffer.concat(chunks.map(([t, d]) => { const h = Buffer.alloc(8); h.write(t, 0, 'latin1'); h.writeUInt32LE(d.length, 4); return Buffer.concat([h, d, d.length & 1 ? Buffer.alloc(1) : Buffer.alloc(0)]); }));
    const head = Buffer.alloc(12); head.write('RIFF', 0, 'latin1'); head.writeUInt32LE(4 + body.length, 4); head.write('WEBP', 8, 'latin1');
    return new Uint8Array(Buffer.concat([head, body]));
  };
  const chunksOf = (b) => { const out = []; let o = 12; const B = Buffer.from(b); while (o + 8 <= B.length) { const s = B.readUInt32LE(o + 4); out.push([B.toString('latin1', o, o + 4), B.subarray(o + 8, o + 8 + s)]); o += 8 + s + (s & 1); } return out; };
  const [vp8x, alph, vp8] = chunksOf(good.alpha);
  const withFlag = (f) => { const x = Buffer.from(vp8x[1]); x[0] |= f; return ['VP8X', x]; };
  const cases = [
    ['alpha source, EXIF chunk added', alpha, riff([withFlag(0x08), alph, vp8, ['EXIF', Buffer.from('MM\0*')]])],
    ['alpha source, ICC flag set', alpha, riff([withFlag(0x20), ['ICCP', Buffer.from('icc!')], alph, vp8])],
    ['alpha source, XMP chunk added', alpha, riff([withFlag(0x04), alph, vp8, ['XMP ', Buffer.from('<x/>')]])],
    ['alpha source, animation flag', alpha, riff([withFlag(0x02), alph, vp8])],
    ['alpha source, ALPH missing', alpha, riff([vp8x, vp8])],
    ['alpha source, simple VP8 only', alpha, riff([vp8])],
    ['opaque source, alpha output', opaque, good.alpha],
    ['wrong dimensions', alpha, good.small],
  ];
  for (const [label, src, out] of cases) {
    const d = createDeriverFromCodecs({ ...real, encodeWebp: async () => out });
    await assert.rejects(d.derive(src, { variant: 'w480', source: 'restaurant-logos', rung: 0 }), (e) => e.code === 'self_check_failed', label);
  }
  // control: the untouched bytes pass the same self-check
  const ok = createDeriverFromCodecs({ ...real, encodeWebp: async () => good.alpha });
  assert.equal((await ok.derive(alpha, { variant: 'w480', source: 'restaurant-logos', rung: 0 })).status, 'derived');
});

test('R20. a PNG refusal from the image-data bound keeps its code and passes only the detail (no doubled prefix)', async () => {
  const d = await deriver();
  await assert.rejects(d.derive(await fixture('bad_png_raw_too_short'), { variant: 'w480', source: 'restaurant-logos', rung: 0 }),
    (e) => e instanceof SourceRejected && e.code === 'corrupt' && /^corrupt: png image data inflates to \d+ of 320200 B$/.test(e.message));
});
