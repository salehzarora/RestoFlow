// STOREFRONT-PUBLISH-001 — recipe `storefront-media-c4` on the vendored jSquash codecs.
//
// Proves: the engine starts only on the pinned wasm and its embedded self-test vector
// (EDGE-4); every golden of test/goldens.mjs (sha-256, size, bytes, ladder trace) with
// its output structure; every hostile vector's typed refusal; the PNG image-data bound
// (EDGE-1: a 256 MiB compressible tail, junk after the stream, truncated streams, the
// Adam7 raw size, ancillary chunks inflating to 1 GiB never reaching the decoder); the
// 8 MiP decode-cap edge; alpha carried exactly (the derivative's alpha plane decoded
// with the vendored WebP decoder equals the pre-encode alpha); the EXIF orientations;
// metadata stripped; the typed mapping of every codec failure, including which
// failures poison the engine; the fresh per-call codec instances (STOREFRONT-MEDIA-MEMORY-001);
// and the eager release of every owned intermediate raster on each call whose encode returns,
// never the caller's bytes or the output (STOREFRONT-MEDIA-MEMORY-001B).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createInflate, inflateSync } from 'node:zlib';
import {
  createDeriver, createDeriverFromCodecs, DerivationError, engineSelfTest, outputSize, RECIPE, releaseOwned, SELF_TEST,
} from '../lib/recipe.mjs';
import { SourceRejected, sniffSource, webpInfo } from '../lib/sniff.mjs';
import { inflateExact, PIECE, PngRejected, pngRawSize, sanitizePng } from '../lib/pngbound.mjs';
import { applyOrientation } from '../lib/orient.mjs';
import { boxReduce } from '../lib/box.mjs';
import { codecs, deriver, readWasm } from './engine.mjs';
import { loadCodecs } from '../lib/codecs.mjs';
import {
  chunk, fixture, fixtureSpec, GPS_MARKER, JPEG_FIXTURE_SHA256, logoRgba, png, PNG_SIGNATURE, rgbaFromRows, webp, withOrientation,
  withSofSize,
} from './fixtures.mjs';
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
test('R18. codec failures map to the public codes; a trap or an exception out of the PNG or resize module poisons the engine', async () => {
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

// ------------------------------------------------------------------ codec instance lifecycle (STOREFRONT-MEDIA-MEMORY-001, D-041 point 3)
const shaOf = (u8) => sha(Buffer.from(u8.buffer, u8.byteOffset, u8.byteLength));

/**
 * Builds a fresh engine over the pinned wasm — the raw codecs (`make` = loadCodecs) or a verified deriver
 * (`make` = createDeriver) — and records, while `run` executes, every compile, every WebAssembly.Module built
 * from bytes, and every WebAssembly.Instance with the compiled module it came from (keyed png / resize /
 * jpegDec / webpEnc / webpDec) and its own linear memory with its size at creation. The WebAssembly globals
 * are restored afterwards.
 */
async function withInstanceLog(run, make = loadCodecs) {
  const wasm = await readWasm();
  const keyOf = new Map(Object.entries(wasm).map(([k, v]) => [v, k]));
  const { Instance, Module, compile } = WebAssembly;
  const log = { compiles: 0, modulesBuilt: 0, keys: new Map(), instances: [] };
  WebAssembly.compile = async (bytes) => {
    log.compiles++;
    const m = await compile(bytes);
    log.keys.set(m, keyOf.get(bytes) ?? 'unknown');
    return m;
  };
  WebAssembly.Module = new Proxy(Module, { construct(t, a, n) { log.modulesBuilt++; return Reflect.construct(t, a, n); } });
  WebAssembly.Instance = new Proxy(Instance, {
    construct(t, a, n) {
      const instance = Reflect.construct(t, a, n);
      const memory = Object.values(instance.exports).find((v) => v instanceof WebAssembly.Memory) ?? null;
      log.instances.push({ key: log.keys.get(a[0]) ?? 'unknown', module: a[0], instance, memory, bytesAtStart: memory ? memory.buffer.byteLength : null });
      return instance;
    },
  });
  try {
    return await run(await make(wasm), log);
  } finally {
    Object.assign(WebAssembly, { Instance, Module, compile });
  }
}
const of = (log, key) => log.instances.filter((x) => x.key === key);
const size = (x) => x.memory.buffer.byteLength;

test('R21. STOREFRONT-MEDIA-MEMORY-001: every PNG decode runs on a FRESH decoder instance with its own linear memory, from the ONE compiled module; nothing is compiled per call', async () => {
  const src = await fixture('logo_alpha_2000x1000');
  await withInstanceLog(async (c, log) => {
    assert.equal(log.compiles, 5, 'the five modules are compiled once, when the codecs load');
    assert.equal(log.instances.length, 0, 'loading the codecs creates no instance');
    const a = await c.decodePng(src);
    const first = size(of(log, 'png')[0]);
    const b = await c.decodePng(src);
    const png = of(log, 'png');
    assert.equal(png.length, 2, 'one new PNG decoder instance per call');
    assert.equal(log.instances.length, 2, 'a PNG decode instantiates nothing else');
    assert.ok(png[0].instance !== png[1].instance, 'a new instance per call');
    assert.ok(png[0].module === png[1].module, 'both instances come from the one compiled module');
    assert.ok(png[0].memory && png[1].memory && png[0].memory !== png[1].memory, 'each call has its own linear memory');
    assert.ok(first > png[0].bytesAtStart, 'the first decode ran on, and grew, its own instance');
    assert.equal(png[1].bytesAtStart, png[0].bytesAtStart, 'the second instance starts from the initial size, never from the first call\'s grown heap');
    assert.ok(size(png[1]) > png[1].bytesAtStart, 'the second decode ran on its own new instance (it grew)');
    assert.equal(size(png[0]), first, 'the second decode never touched the first instance');
    assert.equal(log.compiles, 5, 'no compile per call');
    assert.equal(log.modulesBuilt, 0, 'no module is built from bytes per call');
    assert.deepEqual([a.width, a.height, shaOf(a.data)], [b.width, b.height, shaOf(b.data)], 'fresh instances decode identical pixels');
  });
});

test('R22. STOREFRONT-MEDIA-MEMORY-001: every resize runs on a FRESH resize instance with its own linear memory, from the ONE compiled module; nothing is compiled per call', async () => {
  const src = await fixture('logo_alpha_2000x1000');
  await withInstanceLog(async (c, log) => {
    const img = await c.decodePng(src);
    const px = new Uint8Array(img.data.buffer, img.data.byteOffset, img.data.length);
    const { method, premultiply, linearRGB } = RECIPE.resize;
    const from = log.instances.length;
    const a = c.resize(px, img.width, img.height, 960, 480, method, premultiply, linearRGB);
    const first = size(log.instances[from]);
    const b = c.resize(px, img.width, img.height, 960, 480, method, premultiply, linearRGB);
    const rs = log.instances.slice(from);
    assert.deepEqual(rs.map((x) => x.key), ['resize', 'resize'], 'one new resize instance per call, and nothing else');
    assert.ok(rs[0].instance !== rs[1].instance, 'a new instance per call');
    assert.ok(rs[0].module === rs[1].module, 'both instances come from the one compiled module');
    assert.ok(rs[0].memory && rs[1].memory && rs[0].memory !== rs[1].memory, 'each call has its own linear memory');
    assert.ok(first > rs[0].bytesAtStart, 'the first resize ran on, and grew, its own instance');
    assert.equal(rs[1].bytesAtStart, rs[0].bytesAtStart, 'the second instance starts from the initial size, never from the first call\'s grown heap');
    assert.ok(size(rs[1]) > rs[1].bytesAtStart, 'the second resize ran on its own new instance (it grew)');
    assert.equal(size(rs[0]), first, 'the second resize never touched the first instance');
    assert.equal(log.compiles, 5, 'no compile per call');
    assert.equal(log.modulesBuilt, 0, 'no module is built from bytes per call');
    assert.equal(a.length, 960 * 480 * 4);
    assert.ok(a.buffer !== rs[0].memory.buffer, 'the output is a copy, never a view of the instance memory');
    assert.equal(shaOf(a), shaOf(b), 'fresh instances resize to identical pixels');
  });
});

test('R23. STOREFRONT-MEDIA-MEMORY-001: the Emscripten codecs keep a fresh instance per call (JPEG decode, WebP decode, WebP encode), each from its one compiled module', async () => {
  const jpeg = await fixture('jpeg_prog_1600x1200');
  const webpSrc = await fixture('webp_lossy_alpha_900x600');
  await withInstanceLog(async (c, log) => {
    const j1 = await c.decodeJpeg(jpeg);
    const j2 = await c.decodeJpeg(jpeg);
    const w1 = await c.decodeWebp(webpSrc);
    const w2 = await c.decodeWebp(webpSrc);
    const opts = { ...RECIPE.webp, quality: RECIPE.ladder[0] };
    const e1 = new Uint8Array(await c.encodeWebp(w1.data, w1.width, w1.height, opts));
    const e2 = new Uint8Array(await c.encodeWebp(w1.data, w1.width, w1.height, opts));
    assert.deepEqual(log.instances.map((x) => x.key), ['jpegDec', 'jpegDec', 'webpDec', 'webpDec', 'webpEnc', 'webpEnc']);
    for (let i = 0; i < 6; i += 2) {
      assert.ok(log.instances[i].instance !== log.instances[i + 1].instance, `${log.instances[i].key}: a new instance per call`);
      assert.ok(log.instances[i].module === log.instances[i + 1].module, `${log.instances[i].key}: one compiled module`);
    }
    assert.equal(log.compiles, 5, 'no compile per call');
    assert.equal(log.modulesBuilt, 0, 'no module is built from bytes per call');
    assert.equal(shaOf(j1.image.data), shaOf(j2.image.data));
    assert.equal(shaOf(w1.data), shaOf(w2.data));
    assert.equal(shaOf(e1), shaOf(e2));
  });
});

test('R24. STOREFRONT-MEDIA-MEMORY-001: a failed PNG decode leaves nothing behind for the next call (a fresh instance decodes identically), and the conservative poison rule is unchanged', async () => {
  const good = await fixture('logo_opaque_rgb_1200x600');
  const bad = await fixture('bad_png_filter_type');
  await withInstanceLog(async (c, log) => {
    const before = await c.decodePng(good);
    await assert.rejects(c.decodePng(bad), (e) => e instanceof Error && !(e instanceof WebAssembly.RuntimeError), 'a Rust error, not a trap');
    const settled = of(log, 'png').map(size);
    const after = await c.decodePng(good);
    const png = of(log, 'png');
    assert.equal(png.length, 3);
    assert.equal(new Set(png.map((x) => x.instance)).size, 3, 'the failed call\'s instance is never reused');
    assert.equal(png[2].bytesAtStart, png[0].bytesAtStart, 'the call after the failure starts from the initial size');
    assert.ok(size(png[2]) > png[2].bytesAtStart, 'the call after the failure ran on its own new instance (it grew)');
    assert.deepEqual(png.slice(0, 2).map(size), settled, 'the call after the failure never touched the earlier instances');
    assert.deepEqual([after.width, after.height, shaOf(after.data)], [before.width, before.height, shaOf(before.data)]);
  });
  // the deriver still treats ANY exception out of the PNG decoder as poisoning (review FN-V1; kept by D-041).
  // A separate deriver, so the shared one of this process stays trusted.
  const d = await createDeriver(await readWasm());
  await assert.rejects(d.derive(bad, { variant: 'w480', source: 'restaurant-logos', rung: 0 }), (e) => e instanceof DerivationError && e.code === 'decode_failed');
  assert.equal(d.poisoned, true);
  await assert.rejects(d.derive(good, { variant: 'w480', source: 'restaurant-logos', rung: 0 }), (e) => e instanceof DerivationError && e.code === 'engine_unavailable');
});

test('R25. STOREFRONT-MEDIA-MEMORY-001: two sequential derives through createDeriver (the function\'s own path, self-test included) each run on their own fresh PNG decoder and resize instances; the five modules are compiled once', async () => {
  const src = await fixture('logo_alpha_2000x1000');
  await withInstanceLog(async (d, log) => {
    assert.equal(log.compiles, 5, 'the engine compiles the five modules once');
    const selfTest = { png: of(log, 'png').length, resize: of(log, 'resize').length };
    assert.deepEqual(selfTest, { png: 1, resize: 1 }, 'the EDGE-4 self-test ran on its own PNG and resize instances');
    // w960: the 2000 x 1000 source is box-reduced to 1000 x 500 and resized to 960 x 480, so both instances must grow
    const a = await d.derive(src, { variant: 'w960', source: 'restaurant-logos', rung: 0 });
    const firstPng = of(log, 'png').map(size);
    const firstRs = of(log, 'resize').map(size);
    const b = await d.derive(src, { variant: 'w960', source: 'restaurant-logos', rung: 0 });
    for (const [key, earlier] of [['png', firstPng], ['resize', firstRs]]) {
      const all = of(log, key);
      assert.equal(all.length, 3, `${key}: the self-test and each derive got their own instance`);
      assert.equal(new Set(all.map((x) => x.instance)).size, 3, `${key}: never reused`);
      assert.equal(new Set(all.map((x) => x.module)).size, 1, `${key}: one compiled module`);
      assert.equal(all[2].bytesAtStart, all[1].bytesAtStart, `${key}: the second derive starts from the initial size`);
      assert.ok(size(all[1]) > all[1].bytesAtStart && size(all[2]) > all[2].bytesAtStart, `${key}: each derive ran on its own instance`);
      assert.deepEqual(all.slice(0, 2).map(size), earlier, `${key}: the second derive never touched an earlier instance`);
    }
    assert.equal(log.compiles, 5, 'no compile per derive');
    assert.equal(log.modulesBuilt, 0, 'no module is built from bytes per derive');
    assert.equal(a.status, 'derived');
    assert.equal(b.sha256, a.sha256, 'both derives produce the same bytes');
    assert.equal(d.poisoned, false);
  }, createDeriver);
});

// ------------------------------------------------------------------ owned-buffer release (STOREFRONT-MEDIA-MEMORY-001B)
const goldenOf = (name, variant) => GOLDENS.find((g) => g[0] === name && g[1] === variant);
const attached = (v) => v.buffer.detached === false;

/**
 * A deriver over `real` codecs that records every raster derive() hands to or gets from a codec (by role:
 * decodeIn, decoded, resizeIn, resized, encodeIn) and, at each codec call, which of the rasters seen so far
 * are already detached, plus the sha-256 of the raster the encoder was given.
 */
function observe(real) {
  const seen = {};
  const at = {};
  const snap = () => Object.fromEntries(Object.entries(seen).map(([k, v]) => [k, v.buffer.detached]));
  const decoder = (fn, image) => async (u8) => {
    seen.decodeIn = u8;
    at.decode = snap();
    const r = await fn(u8);
    seen.decoded = image(r).data;
    return r;
  };
  const d = createDeriverFromCodecs({
    ...real,
    decodePng: decoder(real.decodePng, (r) => r),
    decodeJpeg: decoder(real.decodeJpeg, (r) => r.image),
    decodeWebp: decoder(real.decodeWebp, (r) => r),
    resize: (rgba, ...rest) => {
      seen.resizeIn = rgba;
      at.resize = snap();
      seen.resized = real.resize(rgba, ...rest);
      return seen.resized;
    },
    encodeWebp: async (rgba, ...rest) => {
      seen.encodeIn = rgba;
      at.encode = snap();
      at.encodeSha = shaOf(rgba);
      return real.encodeWebp(rgba, ...rest);
    },
  });
  const reset = () => { for (const o of [seen, at]) for (const k of Object.keys(o)) delete o[k]; };
  return { d, seen, at, reset };
}

// Sources for the release paths that no golden takes (box without resize, rotation without resize, a JPEG box).
// Each pinned hash is the BASE commit c3d530a7's own derivative of the same bytes: the release changes no byte.
const EXTRA_SOURCES = new Map([
  ['png_logo_1920x1080', { bucket: 'restaurant-logos', build: () => png({ width: 1920, height: 1080, channels: 4, rows: logoRgba(1920, 1080) }) }],
  ['png_logo_960x540', { bucket: 'restaurant-logos', build: () => png({ width: 960, height: 540, channels: 4, rows: logoRgba(960, 540) }) }],
  ['webp_photo_1920x1080', { bucket: 'menu-images', build: () => webp(1920, 1080, { alpha: false }) }],
  ['jpeg_logo_900x450_orient_6', { bucket: 'restaurant-logos', build: async () => withOrientation(await fixture('jpeg_logo_900x450'), 6) }],
]);
const BASE_HASHES = new Map([
  ['png_logo_1920x1080 w960', 'd8e3fe08c91e119539e9e8d4570690c6413e13c463e00caf1c29e61dea261af0'],
  ['png_logo_960x540 w480', 'bcef7686ed5cc8f33cabc02694de36d58607132f1e47b258129c32b779d57a21'],
  ['webp_photo_1920x1080 w960', 'ab2730a50a4cdc2ec21d2ac251827518005985f54fe6cb7283b708b46e0bbb96'],
  ['jpeg_logo_900x450_orient_6 w960', '9f83a4a667df3ecb4ea34c15a0781bb97c6140d0da1871173053ed2730d5f4a1'],
  ['jpeg_prog_1600x1200 w480', 'e69a9fff69c652251c4bb8014d80c133fe88172f9b37eedfd9537434923a02b2'],
  ['jpeg_orient_6 w480', '1e3eeda98336fc92ae364bec9440b15483465a8f36a4b7eaa3d50243aa5f8c2a'],
]);
const builtExtra = new Map();
async function releaseSource(name) {
  if (!EXTRA_SOURCES.has(name)) return { bytes: await fixture(name), bucket: fixtureSpec(name).bucket };
  if (!builtExtra.has(name)) builtExtra.set(name, Promise.resolve(EXTRA_SOURCES.get(name).build()).then((b) => new Uint8Array(b)));
  return { bytes: await builtExtra.get(name), bucket: EXTRA_SOURCES.get(name).bucket };
}
const pinnedHash = (name, variant) => BASE_HASHES.get(`${name} ${variant}`) ?? goldenOf(name, variant)[2];

test('R26. STOREFRONT-MEDIA-MEMORY-001B: each owned intermediate is detached after its LAST use and before the next codec call, never earlier, on every release path (box / resize / rotation, alone and combined, and none; PNG, JPEG, WebP); the caller\'s bytes and the output stay attached; the output is pinned', async () => {
  const cases = [
    // [source, variant, box ran, resize ran, the orientation made a new raster]
    ['logo_alpha_2000x1000', 'w480', true, true, false], // PNG: box k = 4, then resize
    ['webp_lossless_alpha_1200x800', 'w480', true, true, false], // WebP: box k = 2, then resize
    ['jpeg_prog_1600x1200', 'w480', true, true, false], // JPEG: box k = 3, then resize
    ['jpeg_orient_6', 'w480', true, true, true], // JPEG: box, resize, then a rotation
    ['png_logo_1920x1080', 'w960', true, false, false], // PNG: box k = 2 lands on the target, no resize
    ['png_logo_960x540', 'w480', true, false, false], // PNG: the same at w480
    ['webp_photo_1920x1080', 'w960', true, false, false], // WebP: box only
    ['logo_opaque_rgb_1200x600', 'w960', false, true, false], // PNG: resize only
    ['jpeg_prog_1600x1200', 'w960', false, true, false], // JPEG: resize, orientation 1
    ['jpeg_orient_6', 'w960', false, true, true], // JPEG: resize, then a rotation
    ['jpeg_logo_900x450_orient_6', 'w960', false, false, true], // JPEG: rotation only (release 4 frees the decoded RGBA)
    ['logo_small_300x150', 'w480', false, false, false], // PNG: neither
    ['webp_lossy_alpha_900x600', 'w960', false, false, false], // WebP: neither
  ];
  const o = observe(await codecs());
  for (const [name, variant, box, resize, rotate] of cases) {
    const label = `${name} ${variant}`;
    o.reset();
    const { bytes, bucket } = await releaseSource(name);
    const before = sha(bytes);
    const type = sniffSource(bytes, { ...RECIPE.caps, maxInputBytes: 5242880 }).type;
    const r = await o.d.derive(bytes, { variant, source: bucket, rung: 0 });
    const { seen, at } = o;
    assert.equal(r.sha256, pinnedHash(name, variant), `${label}: the pinned derivative`);
    // the path really is the one named: the box output, the resize output and the rotated raster are each new arrays
    assert.equal(Boolean(at.resize), resize, `${label}: the resize ${resize ? 'ran' : 'did not run'}`);
    if (resize) {
      assert.equal(seen.resizeIn.buffer !== seen.decoded.buffer, box, `${label}: the box ${box ? 'ran' : 'did not run'}`);
      assert.equal(seen.encodeIn.buffer !== seen.resized.buffer, rotate, `${label}: the orientation ${rotate ? 'made' : 'kept'} the raster`);
    } else {
      assert.equal(seen.encodeIn.buffer !== seen.decoded.buffer, box || rotate, `${label}: the encoder ${box || rotate ? 'got a new raster' : 'got the decoded RGBA'}`);
    }
    // (release 1) the decoder's input: attached while decoded; a PNG's sanitized copy is gone before the next codec call
    assert.equal(at.decode.decodeIn, false, `${label}: the decoder input is attached while decoded`);
    if (type === 'png') {
      assert.ok(seen.decodeIn !== bytes && seen.decodeIn.buffer !== bytes.buffer, `${label}: a PNG is decoded from a sanitized copy`);
      if (resize) assert.equal(at.resize.decodeIn, true, `${label}: the sanitized copy is released before the resize`);
      assert.equal(at.encode.decodeIn, true, `${label}: the sanitized copy is released before the encode`);
    } else {
      assert.equal(seen.decodeIn, bytes, `${label}: a ${type} is decoded from the caller's bytes`);
    }
    // (releases 2 / 3) the decoded RGBA and the resize input
    if (resize) {
      assert.equal(at.resize.resizeIn, false, `${label}: the resize input is attached while resized`);
      assert.equal(at.resize.decoded, box, `${label}: the decoded RGBA is ${box ? 'released after the box, BEFORE the resize' : 'the resize input, still attached'}`);
      assert.equal(at.encode.resizeIn, true, `${label}: the resize input is released before the encode`);
      // (release 4) the resize output: released before the encode only when the orientation copied it
      assert.equal(at.encode.resized, rotate, `${label}: the resize output ${rotate ? 'is released after the orientation' : 'is the encoder input, still attached'}`);
    }
    // releases 2, 3 and 4 between them free the decoded RGBA before the encode on every transforming path
    assert.equal(at.encode.decoded, box || resize || rotate, `${label}: the decoded RGBA ${box || resize || rotate ? 'is released before the encode' : 'is the encoder input, still attached'}`);
    // (release 5) the encoder's input: attached while encoded, released after it
    assert.equal(at.encode.encodeIn, false, `${label}: the encoder input is attached while encoded`);
    for (const [role, v] of Object.entries(seen)) {
      if (v === bytes) continue;
      assert.equal(v.buffer.detached, true, `${label}: ${role} is released by the end of the derive`);
    }
    assert.ok(attached(bytes) && sha(bytes) === before, `${label}: the caller's bytes are attached and unchanged`);
    assert.ok(attached(r.bytes) && sha(r.bytes) === r.sha256, `${label}: the returned bytes are attached and are the reported hash`);
  }
  // inspect: the pre-encode raster the caller asked for is never released, and it is exactly what the encoder got
  for (const [name, variant] of [['logo_alpha_2000x1000', 'w480'], ['jpeg_orient_6', 'w960'], ['logo_small_300x150', 'w480'], ['png_logo_1920x1080', 'w960']]) {
    o.reset();
    const { bytes, bucket } = await releaseSource(name);
    const r = await o.d.derive(bytes, { variant, source: bucket, rung: 0, inspect: true });
    assert.equal(r.sha256, pinnedHash(name, variant), `${name}: inspect does not change the bytes`);
    assert.ok(attached(r.preEncode) && r.preEncode.length === r.width * r.height * 4, `${name}: preEncode is attached and whole`);
    assert.ok(r.preEncode.buffer === o.seen.encodeIn.buffer && shaOf(r.preEncode) === o.at.encodeSha, `${name}: preEncode is the raster the encoder was given`);
    assert.ok(attached(bytes) && attached(r.bytes), `${name}: the caller's bytes and the output stay attached`);
    for (const [role, v] of Object.entries(o.seen)) {
      if (v === bytes || v.buffer === r.preEncode.buffer) continue;
      assert.equal(v.buffer.detached, true, `${name}: ${role} is still released under inspect`);
    }
  }
});

test('R26b. STOREFRONT-MEDIA-MEMORY-001B: a JPEG whose box output lands exactly on the target (no resize), with orientation 1 and with a rotation: the box output (seen through the Uint8Array constructor) is released by release 4 BEFORE the encode when rotated, by release 5 after it otherwise; the output is the base commit\'s', async () => {
  const real = await codecs();
  const W = 1920, H = 1440; // k = 4 at w480: the 480 x 360 box output IS the resize target
  const pixels = rgbaFromRows(W, H, logoRgba(W, H), 4);
  const BASE = new Map([[1, '380bed92e54c01dca7e504d7dc111e379e402035b0bf40dc5977c3e67f6ae62b'], [6, 'e69eeada0cf59e76cba0df31861c73eeeb1e544df5f04e2482644a0e656df7d5']]);
  for (const [o, hash] of BASE) {
    const bytes = withOrientation(withSofSize(await fixture('jpeg_logo_900x450'), W, H), o);
    const before = sha(bytes);
    let decoded = null, box = null, encodeIn = null, atEncode = null, decodedDone = false;
    const made = [];
    // a decoder answering a fresh copy of synthetic 1920 x 1440 pixels (like the real one: a whole JS-owned copy)
    const d = createDeriverFromCodecs({
      ...real,
      decodeJpeg: async () => { decoded = new Uint8ClampedArray(pixels); decodedDone = true; return { image: { width: W, height: H, data: decoded }, warnings: [] }; },
      resize: () => assert.fail('no resize on this path'),
      encodeWebp: async (rgba, ...rest) => {
        encodeIn = rgba;
        box = made[0];
        atEncode = { decoded: decoded.buffer.detached, box: box.buffer.detached, encodeIn: rgba.buffer.detached };
        return real.encodeWebp(rgba, ...rest);
      },
    });
    const Real = globalThis.Uint8Array;
    globalThis.Uint8Array = new Proxy(Real, {
      construct(t, a, n) {
        const v = Reflect.construct(t, a, n);
        if (decodedDone && !encodeIn && v.length === 480 * 360 * 4) made.push(v); // the rasters derive() builds between the decode and the encode
        return v;
      },
    });
    let r;
    try {
      r = await d.derive(bytes, { variant: 'w480', source: 'menu-images', rung: 0 });
    } finally {
      globalThis.Uint8Array = Real;
    }
    assert.equal(r.sha256, hash, `orientation ${o}: the base commit's derivative`);
    assert.equal(made.length, o === 1 ? 1 : 2, `orientation ${o}: the box output${o === 1 ? '' : ' and the rotated copy'} were built`);
    assert.equal(atEncode.decoded, true, `orientation ${o}: the decoded RGBA is released after the box, before the encode`);
    assert.equal(atEncode.encodeIn, false, `orientation ${o}: the encoder input is attached while encoded`);
    if (o === 1) assert.ok(encodeIn.buffer === box.buffer && atEncode.box === false, 'orientation 1: the box output IS the encoder input, attached while encoded');
    else assert.ok(encodeIn.buffer === made[1].buffer && atEncode.box === true, 'orientation 6: release 4 freed the box output BEFORE the encode');
    assert.ok(box.buffer.detached && encodeIn.buffer.detached && decoded.buffer.detached, `orientation ${o}: every owned raster is released by the end`);
    assert.ok(attached(bytes) && sha(bytes) === before && attached(r.bytes), `orientation ${o}: the caller's bytes and the output stay attached`);
  }
});

test('R27. STOREFRONT-MEDIA-MEMORY-001B: EVERY derive call (each golden\'s full ladder walk, both variants and every rung from ONE bytes object per fixture, and each refusal\'s rungs) releases every owned intermediate it created; the caller\'s bytes stay attached and byte-identical, and every returned derivative stays attached and golden after all the later derives', async () => {
  const o = observe(await codecs());
  const d = o.d;
  const sources = new Map();
  const source = async (name) => {
    if (!sources.has(name)) { const bytes = await fixture(name); sources.set(name, { bytes, sha: sha(bytes) }); }
    return sources.get(name);
  };
  const statuses = new Map();
  const count = (k) => statuses.set(k, (statuses.get(k) ?? 0) + 1);
  // one observed call: after it, every raster it handed to or got from a codec is released, except the caller's
  // bytes, the returned output and (documented residual) what a decode_warning holds: it is thrown before release 1
  const call = async (label, bytes, args) => {
    o.reset();
    let r = null, err = null;
    try { r = await d.derive(bytes, args); } catch (e) { err = e; }
    count(err ? `refused:${err.code}` : r.status);
    if (!(err && err.code === 'decode_warning')) {
      for (const [role, v] of Object.entries(o.seen)) {
        if (v.buffer === bytes.buffer || (r && r.bytes && v.buffer === r.bytes.buffer)) continue;
        assert.equal(v.buffer.detached, true, `${label}: ${role} is released after the call (${err ? err.code : r.status})`);
      }
    }
    if (err) throw err;
    return r;
  };
  const outputs = [];
  for (const [name, variant, hash, , , , trace] of GOLDENS) {
    const { bytes } = await source(name);
    const bucket = fixtureSpec(name).bucket;
    const steps = [];
    let r = null;
    for (let rung = 0; rung < RECIPE.ladder.length; rung++) {
      r = await call(`${name} ${variant} rung ${rung}`, bytes, { variant, source: bucket, rung });
      steps.push(`q${r.attempt.quality}:${r.attempt.bytes}${r.status === 'derived' ? '' : '>cap'}`);
      if (r.status === 'derived') break;
    }
    assert.equal(steps.join(' '), trace, `${name} ${variant}: the ladder trace`);
    assert.equal(r.sha256, hash, `${name} ${variant}: the golden`);
    outputs.push([`${name} ${variant}`, r.bytes, hash]);
  }
  for (const [name, variant, code, rung] of REFUSALS) {
    const { bytes } = await source(name);
    const bucket = fixtureSpec(name).bucket;
    for (let k = 0; k < rung; k++) assert.equal((await call(`${name} rung ${k}`, bytes, { variant, source: bucket, rung: k })).status, 'ladder_next', `${name} rung ${k}`);
    await assert.rejects(call(`${name} rung ${rung}`, bytes, { variant, source: bucket, rung }), (e) => e.code === code, `${name}: ${code}`);
  }
  // the observation really covered derivatives, over-cap rungs and refusals after the encode
  assert.ok(statuses.get('derived') === GOLDENS.length && statuses.get('ladder_next') >= 9 && statuses.get('refused:output_too_large') === 2, JSON.stringify([...statuses]));
  for (const [name, { bytes, sha: pinned }] of sources) {
    assert.ok(attached(bytes) && sha(bytes) === pinned, `${name}: the caller's bytes are attached and unchanged after every derive of them`);
  }
  assert.equal(outputs.length, GOLDENS.length);
  for (const [label, bytes, hash] of outputs) assert.ok(attached(bytes) && sha(bytes) === hash, `${label}: the derivative is still attached and golden`);
  assert.equal(d.poisoned, false);
});

test('R28. STOREFRONT-MEDIA-MEMORY-001B: derives keep working after earlier derives released their buffers (w960 then w480 of one source, other codecs in between, a refusal in between, a ladder walk, the first source again)', async () => {
  const d = await deriver();
  const steps = [
    ['logo_alpha_2000x1000', 'w960'], ['logo_alpha_2000x1000', 'w480'], ['jpeg_prog_1600x1200', 'w960'],
    ['bad_png_raw_too_short', 'w480', 'corrupt'], ['webp_lossless_alpha_1200x800', 'w960'], ['webp_lossless_alpha_1200x800', 'w480'],
    ['band_q74', 'w960'], ['bad_jpeg_corrupt_entropy', 'w960', 'decode_warning'], ['jpeg_orient_6', 'w960'],
    ['logo_alpha_2000x1000', 'w480'], ['logo_alpha_2000x1000', 'w960'],
  ];
  for (const [name, variant, code] of steps) {
    const bytes = await fixture(name);
    const bucket = fixtureSpec(name).bucket;
    if (code) {
      await assert.rejects(d.derive(bytes, { variant, source: bucket, rung: 0 }), (e) => e.code === code, `${name}: ${code}`);
      continue;
    }
    const [, , hash, , , , trace] = goldenOf(name, variant);
    const { r, trace: got } = await ladder(d, bytes, variant, bucket);
    assert.deepEqual([r.sha256, got], [hash, trace], `${name} ${variant}`);
  }
  assert.equal(d.poisoned, false, 'no refusal poisoned the engine');
});

test('R29. STOREFRONT-MEDIA-MEMORY-001B: releaseOwned detaches only a view spanning its WHOLE fixed-length ArrayBuffer; a partial view, a resizable buffer, a WebAssembly memory, a SharedArrayBuffer, an empty or already detached buffer, or no view at all is left alone, and it never throws', () => {
  const whole = new Uint8Array(64).fill(7);
  assert.equal(releaseOwned(whole), true);
  assert.ok(whole.buffer.detached && whole.length === 0, 'detached: the bytes are handed back');
  assert.equal(releaseOwned(whole), false, 'an already detached buffer');
  assert.equal(releaseOwned(new Uint8ClampedArray(16)), true, 'a clamped view (the decoders\' ImageData data)');
  const parent = new Uint8Array(64).fill(9);
  for (const [label, view] of [['a middle view', parent.subarray(8, 24)], ['a tail view', parent.subarray(8)], ['a head view', parent.subarray(0, 32)]]) {
    assert.equal(releaseOwned(view), false, label);
  }
  assert.ok(!parent.buffer.detached && parent.every((v) => v === 9), 'the parent of a partial view is untouched');
  const memory = new WebAssembly.Memory({ initial: 1 });
  const all = new Uint8Array(memory.buffer);
  all[0] = 5;
  assert.equal(releaseOwned(all), false, 'a WebAssembly memory is never detached');
  assert.ok(!memory.buffer.detached && memory.buffer.byteLength === 65536 && new Uint8Array(memory.buffer)[0] === 5, 'the memory is intact');
  if (typeof SharedArrayBuffer === 'function') assert.equal(releaseOwned(new Uint8Array(new SharedArrayBuffer(16))), false, 'a SharedArrayBuffer');
  const resizable = new Uint8Array(new ArrayBuffer(16, { maxByteLength: 64 }));
  assert.equal(releaseOwned(resizable), false, 'a resizable buffer');
  assert.ok(!resizable.buffer.detached && resizable.length === 16, 'the resizable buffer is intact');
  assert.equal(releaseOwned(new Uint8Array(0)), false, 'an empty buffer');
  for (const v of [null, undefined, {}, 'text', 7, new ArrayBuffer(8)]) assert.equal(releaseOwned(v), false, `not a view: ${String(v)}`);
});

test('R30. STOREFRONT-MEDIA-MEMORY-001B: the releases never touch a codec instance memory, and the fresh per-call instance lifecycle of STOREFRONT-MEDIA-MEMORY-001 is unchanged (one PNG or JPEG or WebP decoder, one resize, one encoder instance per derive)', async () => {
  await withInstanceLog(async (c, log) => {
    const o = observe(c);
    for (const [name, variant, instances] of [
      ['logo_alpha_2000x1000', 'w960', ['png', 'resize', 'webpEnc']],
      ['jpeg_prog_1600x1200', 'w960', ['jpegDec', 'resize', 'webpEnc']],
      ['webp_lossless_alpha_1200x800', 'w480', ['webpDec', 'resize', 'webpEnc']],
      ['logo_small_300x150', 'w480', ['png', 'webpEnc']],
    ]) {
      o.reset();
      const from = log.instances.length;
      const r = await o.d.derive(await fixture(name), { variant, source: fixtureSpec(name).bucket, rung: 0 });
      assert.equal(r.sha256, goldenOf(name, variant)[2], `${name} ${variant}: the golden`);
      assert.deepEqual(log.instances.slice(from).map((x) => x.key), instances, `${name}: one fresh instance per codec call, nothing else`);
      const memories = log.instances.map((x) => x.memory).filter(Boolean);
      // (a WebAssembly memory's buffer cannot be detached at all; R29 proves releaseOwned refuses one without throwing)
      for (const [role, v] of Object.entries(o.seen)) assert.ok(!memories.some((m) => m.buffer === v.buffer), `${name}: ${role} is never a codec memory`);
    }
    assert.equal(log.compiles, 5, 'no compile per derive');
    assert.equal(log.modulesBuilt, 0);
  });
});

test('R31. STOREFRONT-MEDIA-MEMORY-001B: a buffer the caller owns is never released even when a codec aliases it, a buffer that became the output is never released even when it is the raster\'s own, and a sanitized copy the decoded RGBA views is never released (fake codecs)', async () => {
  const real = await codecs();
  // a decoder whose RGBA shares the caller's buffer: the release points that would reach it (after the resize at
  // w480, after the encode at w960) must leave it alone
  const webp = await fixture('webp_lossy_alpha_900x600');
  for (const variant of ['w960', 'w480']) {
    const shared = new Uint8Array(900 * 600 * 4);
    shared.set(webp, 0);
    const bytes = shared.subarray(0, webp.length);
    const d = createDeriverFromCodecs({ ...real, decodeWebp: async () => ({ width: 900, height: 600, data: new Uint8ClampedArray(shared.buffer) }) });
    const r = await d.derive(bytes, { variant, source: 'menu-images', rung: 0 });
    assert.ok(['derived', 'ladder_next'].includes(r.status), `${variant}: ${r.status}`);
    assert.ok(!shared.buffer.detached && sha(bytes) === sha(webp), `${variant}: the caller's buffer is attached and unchanged`);
  }
  // an encoder that hands back the raster's own buffer as the output: the self-check refuses it, and the buffer
  // that became the output is not released
  let returned = null;
  const d = createDeriverFromCodecs({ ...real, encodeWebp: async (rgba) => { returned = rgba.buffer; return rgba.buffer; } });
  await assert.rejects(d.derive(await fixture('logo_small_300x150'), { variant: 'w480', source: 'restaurant-logos', rung: 0 }), (e) => e.code === 'self_check_failed');
  assert.ok(returned && returned.detached === false, 'the output\'s buffer is never released');
  // a PNG decoder whose RGBA is a view of its input (the sanitized copy): release 1 leaves the shared copy alone
  const tiny = new Uint8Array(png({ width: 2, height: 2, channels: 4, rows: logoRgba(2, 2) }));
  let decodeIn = null;
  const aliasing = createDeriverFromCodecs({ ...real, decodePng: async (u8) => { decodeIn = u8; return { width: 2, height: 2, data: new Uint8ClampedArray(u8.buffer, 0, 16) }; } });
  const r2 = await aliasing.derive(tiny, { variant: 'w480', source: 'restaurant-logos', rung: 0 });
  assert.equal(r2.status, 'derived');
  assert.ok(decodeIn !== tiny && decodeIn.buffer.detached === false, 'the sanitized copy the RGBA views is not released');
  assert.ok(attached(tiny), 'the caller\'s bytes are attached');
});
