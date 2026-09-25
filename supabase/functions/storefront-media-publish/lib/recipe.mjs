// STOREFRONT-PUBLISH-001 (Q031 remediation): the canonical derivative recipe
// `storefront-media-c4`.
//
// Engine: five focused jSquash WebAssembly codecs, vendored byte-exact and
// unmodified (vendor/jsquash/; provenance, licences and the upgrade rule in
// vendor/README.md and vendor/THIRD_PARTY_NOTICES.txt): PNG decode (png crate),
// JPEG decode (mozjpeg 3.3.1), WebP decode and encode (libwebp 1.1.0, non-SIMD
// build) and resize (resize crate). Host-agnostic ES module: the caller injects
// the pinned wasm bytes and createDeriver() refuses to start unless every one
// matches its sha-256 below. Everything the output bytes depend on is fixed here.
//
// ONE derive() call evaluates ONE ladder rung:
//   exact allowlists (variant / source / rung, Map membership of primitive strings)
//   -> sniff (the whole container; c4 caps: every decode raster <= 8 MiP and
//      <= 8192 px per side, aspect <= 8, the c3 metadata / JPEG scan caps, a
//      4-component JPEG refused) -> PNG only: ancillary chunks stripped and the
//      image data inflated ONCE, bounded by its exact raw size (pngbound.mjs)
//   -> decode (JPEG: ANY libjpeg warning refuses; the decoded size must equal the
//      header's) -> exact integer k x k box pre-reduction when k >= 2 (box.mjs)
//   -> triangle resize, premultiplied alpha, sRGB values (no linearisation), into
//      the W x W box (keep the aspect ratio, never upscale, never crop), in the
//      source orientation -> JPEG EXIF orientation by integer copies (orient.mjs)
//   -> ONE WebP encode (lossy VP8, method 2, `exact`, lossless alpha at
//      alpha_quality 100) -> self-check of the output (dimensions; chunks exactly
//      VP8X,ALPH,VP8 when any alpha < 255, else VP8; no ICCP / EXIF / XMP /
//      animation) -> width, height, bytes and sha-256 read from the ACTUAL output.
//
// Ladder contract (as c3): the rungs are evaluated in order, ONE per call. A call
// for rung r returns the derivative (rung r fits in maxOutputBytes), a typed
// `ladder_next` (it does not fit and a later rung still can), or a typed
// `output_too_large` (the last rung failed, or the lossless ALPH chunk, identical
// at every rung, is already over the cap). The rung order is driven by the
// caller (a convention of the honest client, like the rest of canonicality).
//
// Failure codes are exactly the public sets the handler and the Dashboard know
// (kStorefrontRefusalCodes / kStorefrontPublishFaultCodes): SourceRejected codes
// from the sniff and the PNG bound; decode_warning; corrupt (decoded size differs
// from the header); decode_failed for any NON-trap codec exception (decode,
// resize or encode); self_check_failed; output_too_large; unknown_variant /
// unknown_source / unknown_rung. A WebAssembly trap is engine_unavailable (the
// handler answers a retryable 503 and retires the worker). The PNG and resize
// modules are one instance per worker, and a Rust error thrown out of them does
// not unwind (leaked heap and shadow stack: repeated failures corrupt the
// instance), so ANY exception from them also poisons this deriver: the request
// still gets its typed refusal, and the handler then retires the worker.
//
// EDGE-4: createDeriver() derives one small EMBEDDED vector (SELF_TEST) before
// it returns and compares the sha-256 with its pinned golden; a mismatch (for
// example a platform runtime change that alters the engine's output) poisons the
// engine and fails closed as engine_unavailable instead of minting new hashes.
//
// Enum validation (closes the Option C spike's round-3 BLOCKER): `variant` and
// `source` are untrusted strings, looked up ONLY by exact membership of a Map and
// only when they are primitive strings (test/validation.test.mjs).

import { SourceRejected, sniffSource, webpInfo } from './sniff.mjs';
import { PngRejected, pngRawSize, sanitizePng } from './pngbound.mjs';
import { applyOrientation, jpegExifOrientation } from './orient.mjs';
import { boxReduce } from './box.mjs';
import { loadCodecs } from './codecs.mjs';

// The ONLY accepted variant names and source buckets, exactly.
const VARIANT_WIDTHS = new Map([['w480', 480], ['w960', 960]]);
// Upper bounds of the EXISTING private upload contracts (storage.buckets rows).
const SOURCE_MAX_BYTES = new Map([['restaurant-logos', 2097152], ['menu-images', 5242880]]);

/** The output box width of an EXACT variant name, or null for anything else. */
export function variantWidth(variant) {
  return typeof variant === 'string' && VARIANT_WIDTHS.has(variant) ? VARIANT_WIDTHS.get(variant) : null;
}

/** The byte cap of an EXACT private source bucket name, or null for anything else. */
export function sourceMaxBytes(source) {
  return typeof source === 'string' && SOURCE_MAX_BYTES.has(source) ? SOURCE_MAX_BYTES.get(source) : null;
}

const pin = (key, pkg, version, tarballPath, path, sha256) => Object.freeze({ key, package: pkg, version, tarballPath, path, sha256 });

// Every vendored file (the ten codec files, byte-identical to the npm tarballs).
// test/license.test.mjs re-hashes all of them (and the notices file) on every run.
const ENGINE_FILES = Object.freeze([
  pin('png', '@jsquash/png', '3.1.1', 'package/codec/pkg/squoosh_png_bg.wasm', 'vendor/jsquash/png/squoosh_png_bg.wasm', '263d6e658808a74b72a1a99c5cc1d619237e70c150db6e41d5d84d3d117ab9be'),
  pin('png.js', '@jsquash/png', '3.1.1', 'package/codec/pkg/squoosh_png.js', 'vendor/jsquash/png/squoosh_png.js', '65ebe1192f970c46263d52a122edf6bd01be81174c6bf1736a16f1e6f0e9b411'),
  pin('jpegDec', '@jsquash/jpeg', '1.6.0', 'package/codec/dec/mozjpeg_dec.wasm', 'vendor/jsquash/jpeg-dec/mozjpeg_dec.wasm', 'a7c4b12169817e779ff4af137981393ae924944e167ad1bd95747c9199162d3e'),
  pin('jpegDec.js', '@jsquash/jpeg', '1.6.0', 'package/codec/dec/mozjpeg_dec.js', 'vendor/jsquash/jpeg-dec/mozjpeg_dec.js', 'a6836b2d03d4fdda64b4aef380e6298d7421c070e7e1e4cf13ec129df7aa0b5e'),
  pin('webpEnc', '@jsquash/webp', '1.5.0', 'package/codec/enc/webp_enc.wasm', 'vendor/jsquash/webp-enc/webp_enc.wasm', 'b6085bb6702f144e9dc6016d58d230b34a84976bf0d080b7390b4b4b137d6ab7'),
  pin('webpEnc.js', '@jsquash/webp', '1.5.0', 'package/codec/enc/webp_enc.js', 'vendor/jsquash/webp-enc/webp_enc.js', '5fd62301662e37785aec38e38807926f72933d4c8b919018a43faf1b1ca760f6'),
  pin('webpDec', '@jsquash/webp', '1.5.0', 'package/codec/dec/webp_dec.wasm', 'vendor/jsquash/webp-dec/webp_dec.wasm', '30fb52fa2a80166d25ba7debf902218904ba1f05ccce9f959f722beff9e2f344'),
  pin('webpDec.js', '@jsquash/webp', '1.5.0', 'package/codec/dec/webp_dec.js', 'vendor/jsquash/webp-dec/webp_dec.js', 'c57971611f4d9ec04e4636ce7bb4a35c031b24cbdb013518f0a017d9f6014370'),
  pin('resize', '@jsquash/resize', '2.1.1', 'package/lib/resize/pkg/squoosh_resize_bg.wasm', 'vendor/jsquash/resize/squoosh_resize_bg.wasm', '5b1f702d502c4d0a70b99f78691bd554d566ba95859e4c57af5435955a1d74a5'),
  pin('resize.js', '@jsquash/resize', '2.1.1', 'package/lib/resize/pkg/squoosh_resize.js', 'vendor/jsquash/resize/squoosh_resize.js', 'e974c442bb6a7f2b57a7c86a879f55a008ffd6fccea5f9ed9fee14900ae56225'),
]);
// The five wasm modules createDeriver() is given (by these keys) and verifies before compiling.
const WASM_KEYS = Object.freeze(['png', 'resize', 'jpegDec', 'webpEnc', 'webpDec']);

export const RECIPE = Object.freeze({
  id: 'storefront-media-c4',
  engine: Object.freeze({
    packages: Object.freeze([
      Object.freeze(['@jsquash/png', '3.1.1']), Object.freeze(['@jsquash/jpeg', '1.6.0']),
      Object.freeze(['@jsquash/webp', '1.5.0']), Object.freeze(['@jsquash/resize', '2.1.1']),
    ]),
    files: ENGINE_FILES,
    wasmKeys: WASM_KEYS,
  }),
  // Documentation only (frozen [name, value] pairs); lookups go through the Maps above.
  variants: Object.freeze([...VARIANT_WIDTHS].map((p) => Object.freeze(p))),
  sources: Object.freeze([...SOURCE_MAX_BYTES].map((p) => Object.freeze(p))),
  caps: Object.freeze({
    decodeMaxPixels: 8388608, // 8 MiP: the ONE decode raster cap of c4 (measured on the edge runtime, Q031)
    maxSide: 8192, // PNG / WebP
    maxPixels: 8388608, // = decodeMaxPixels (PNG / WebP)
    jpegMaxSide: 8192,
    jpegMaxPixels: 8388608, // = decodeMaxPixels (c4 always decodes a JPEG at full size)
    jpegMaxScans: 16,
    // 32 MiB of 16-bit DCT coefficients: a progressive decode holds the whole coefficient buffer
    // next to the RGBA raster; 32 MiB admits every 4:2:0 progressive JPEG under the 8 MiP cap and
    // a 4:4:4 one up to ~5.3 MiP (memory envelope measured on the edge runtime, 256 MB workers).
    jpegMaxProgressiveCoefficientBytes: 33554432,
    jpegMaxProgressiveScanWork: 400000000, // scans x coefficients
    maxAspect: 8, // mirrors kMaxLogoAspectRatio
    maxMetadataBytes: 1048576, // per chunk (PNG, WebP) / total APPn + COM payload (JPEG)
    // The PNG decoder is one instance per worker (its heap never shrinks): its working set is the
    // inflated image data + the 8-bit RGBA output. 32 MiB + 16 KiB of image data admits every 8-bit
    // RGBA PNG under the 8 MiP cap (4 B/px + the filter bytes, Adam7 included) and a 16-bit RGBA one up
    // to ~4 MiP (checked from the IHDR before any inflate).
    pngMaxRawBytes: 33570816,
    pngMaxChunks: 65536,
    pngMaxAncillaryChunks: 32,
    pngMaxIccp: 1,
    pngMaxCompressedText: 4, // zTXt + iTXt
    webpMaxChunks: 16,
  }),
  // Output geometry: fit inside W x W (the longer side is at most W), keep the aspect
  // ratio, never upscale, never crop; integer arithmetic (outputSize).
  maxOutputHeightFactor: 1,
  // Exact integer k x k box pre-reduction before the resize when k >= 2.
  box: Object.freeze({ minFactor: 2, weighting: 'premultiplied', rounding: 'half-up' }),
  // resize crate: method 0 = triangle; premultiplied alpha; no sRGB -> linear conversion.
  resize: Object.freeze({ filter: 'triangle', method: 0, premultiply: true, linearRGB: false }),
  ladder: Object.freeze([82, 74, 66, 58, 50]),
  maxOutputBytes: 524288,
  // libwebp WebPConfig as the jSquash encoder takes it (quality = the rung's value).
  webp: Object.freeze({
    target_size: 0, target_PSNR: 0, method: 2, sns_strength: 50, filter_strength: 60, filter_sharpness: 0,
    filter_type: 1, partitions: 0, segments: 4, pass: 1, show_compressed: 0, preprocessing: 0, autofilter: 0,
    partition_limit: 0, alpha_compression: 1, alpha_filtering: 1, alpha_quality: 100, lossless: 0, exact: 1,
    image_hint: 0, emulate_jpeg_size: 0, thread_level: 0, low_memory: 0, near_lossless: 100,
    use_delta_palette: 0, use_sharp_yuv: 0,
  }),
});

// EDGE-4: the embedded init-time vector. A 1000 x 400 palette PNG with tRNS (three
// alpha levels, edges off the 2 x 2 grid), so the self-test runs the sniff, the PNG
// bound, the PNG decoder, the box pre-reduction (k = 2), the triangle resize and the
// alpha (VP8X,ALPH,VP8) WebP encode. The golden is the same on Node 22, Node 24 and
// edge-runtime v1.74.3 (test/recipe.test.mjs and the parity gate).
export const SELF_TEST = Object.freeze({
  variant: 'w480',
  source: 'restaurant-logos',
  pngBase64: [
    'iVBORw0KGgoAAAANSUhEUgAAA+gAAAGQCAMAAAAKk7pTAAAADFBMVEUAAADoeCAoWsgUoFoQPD6rAAAABHRSTlMA/2DI/UlzUgAAA51JREFUeNrt',
    '1TkOwCAMRUEg9z9yIBInwE3YZvrfWHpyScDxihOA0AGhA0IHhA4IHRA6IHRA6CB0QOiA0AGhA0IHhA4IHRA6CB0QOiB0QOiA0AGhA0IHtgz96cID',
    'C4vpC6EDQgeEDggdEDoIHRA6IHRA6IDQAaEDQgeEDggdhA4IHRA6IHRA6IDQAaEDQgehA0IHhA7cG3oOC++Sxa0LfHRA6CB0QOiA0AGhA0IHhA4I',
    'HRA6CB0QOiB0QOiA0AGhA0IHhA5CB4QOCB0QOiB0QOiA0AGhA0IHoQNCB4QOCB0QOiB0QOiA0EHogNABoQNCB4QOCB0QOiB0EDogdEDogNABoQNC',
    'B4QOCB0QOggdEDogdEDogNABoQNCB4QOQgeEDggdEDogdEDogNABoYPQAaEDQgeEDggdEDogdEDogNBB6IDQAaEDQgeEDggdEDogdBA6IHRA6IDQ',
    'AaEDQgeEDggdhA4IHRA6IHRA6IDQAaGfpXV5XLt9Ucb9sihhQgeEDggdEDoIHRA6IHRA6IDQAaEDQgeEDkIHhA4IHRA6IHRA6IDQAaGD0AGhA0IH',
    'hA4IHRA6IHRA6IDQQeiA0AGhA0IHhA4IHRA6IHQQOiB0QOiA0AGhA0IHhA4IHYQOCB0QOiB0QOiA0AGhA0IHhA5CB4QOCB0QOiB0QOiA0AGhg9AB',
    'oQNCB4QOCB0QOiB0QOggdEDogNABoQNCB4QOCB0QOiB0EDogdEDogNABoQNCB4QOCB2EDggdEDogdEDogNABoQNCB6EDQgeEDggdEDogdEDogNAB',
    'oYPQAaEDQgeEDggdEDogdEDoIHRA6IDQAaEDQgeEDggdEDoIHRA6IHRA6IDQAaEDQgeEDggdhA4IHRA6IHRA6IDQAaEDQgehA0IHhA4IHRA6IHRA',
    '6IDQQeiA0AGhA0IHzg+9hYV36awF+OiA0AGhg9ABoQNCB4QOCB0QOiB0QOggdEDogNABoQNCB4QOCB0QOiB0EDogdEDogNABoQNCB4QOCB2EDggd',
    'EDogdEDogNABoQNCB6EDQgeEDggdEDogdEDogNABoYPQAaEDQgeEDggdEDogdEDoIHRA6IDQAaEDQgeEDggdEDoIHRA6IHRA6IDQAaEDQgeEDgh9',
    'Pbmr47LFWosaJnRA6IDQgbVDf7vwwMJi+kLogNABoQNCB4QOQgeEDggdEDogdEDogNABoQNCB6EDQgeEDggdEDogdEDogNBB6IDQgQ19wT5iTpOy',
    'mAIAAAAASUVORK5CYII=',
  ].join(''),
  sha256: '6058e055d357bb3712536f25a4c147633ab3993366b145ea0a52692aebdc4c5d',
  width: 480,
  height: 192,
});

export class DerivationError extends Error {
  constructor(code, detail) {
    super(`${code}${detail ? `: ${detail}` : ''}`);
    this.code = code;
  }
}

const hex = (buf) => Array.from(new Uint8Array(buf), (x) => x.toString(16).padStart(2, '0')).join('');
export async function sha256Hex(bytes) {
  return hex(await crypto.subtle.digest('SHA-256', bytes));
}

/** Canonical output size: integer arithmetic only (round half up of src * num / den). */
export function outputSize(srcW, srcH, target, heightFactor = RECIPE.maxOutputHeightFactor) {
  let num = 1, den = 1;
  if (target * den < num * srcW) { num = target; den = srcW; }
  if (heightFactor * target * den < num * srcH) { num = heightFactor * target; den = srcH; }
  const r = (x) => Math.floor((2 * x * num + den) / (2 * den));
  return { width: Math.max(1, r(srcW)), height: Math.max(1, r(srcH)) };
}

const isTrap = (e) => e instanceof WebAssembly.RuntimeError;
const detailOf = (e) => String(e && e.message ? e.message : e).slice(0, 160);

/**
 * The deriver over already-loaded codecs (createDeriver() is the verified entry point;
 * tests inject fakes here to reach the defensive branches).
 * Returns { derive, poison, poisoned }.
 */
export function createDeriverFromCodecs(codecs, recipe = RECIPE) {
  let poisoned = false;
  const poison = () => { poisoned = true; };

  /** A codec exception: a trap is engine_unavailable; anything else the given typed code. */
  const codecFailure = (e, { taints }) => {
    if (e instanceof DerivationError || e instanceof SourceRejected) return e;
    if (isTrap(e)) { poisoned = true; return new DerivationError('engine_unavailable', detailOf(e)); }
    if (taints) poisoned = true; // a one-per-worker wasm-bindgen instance threw: its state is not trusted
    return new DerivationError('decode_failed', detailOf(e));
  };

  /**
   * Evaluates ONE ladder rung for (source bytes, variant, source bucket).
   * Returns { status: 'derived', bytes, sha256, byteLength, width, height, rung, ... }
   *       | { status: 'ladder_next', nextRung, attempt }
   * or throws SourceRejected / DerivationError (typed).
   * `inspect: true` (tests only) also returns the pre-encode RGBA raster.
   */
  async function derive(bytes, { variant, source, rung = 0, inspect = false } = {}) {
    const t0 = performance.now();
    // Exact allowlists (Map membership of a primitive string); validated before any byte is read.
    const target = variantWidth(variant);
    if (target === null) throw new DerivationError('unknown_variant');
    const maxInputBytes = sourceMaxBytes(source);
    if (maxInputBytes === null) throw new DerivationError('unknown_source');
    if (!Number.isInteger(rung) || rung < 0 || rung >= recipe.ladder.length) throw new DerivationError('unknown_rung');
    if (poisoned) throw new DerivationError('engine_unavailable', 'engine state not trusted on this worker');

    const info = sniffSource(bytes, { ...recipe.caps, maxInputBytes });
    let decodeInput = bytes;
    if (info.type === 'png') {
      const raw = pngRawSize(info.width, info.height, info.bitDepth, info.colorType, info.interlace);
      if (raw > recipe.caps.pngMaxRawBytes) throw new SourceRejected('too_many_pixels', `png image data ${raw} B > ${recipe.caps.pngMaxRawBytes} B`);
      try {
        decodeInput = await sanitizePng(bytes);
      } catch (e) {
        if (e instanceof PngRejected) throw new SourceRejected(e.code, e.detail);
        throw e;
      }
    }
    const orientation = info.type === 'jpeg' ? jpegExifOrientation(bytes) : 1;
    const tSniff = performance.now();

    let decoded;
    try {
      if (info.type === 'jpeg') {
        const j = await codecs.decodeJpeg(decodeInput);
        if (j.warnings.length) throw new DerivationError('decode_warning', j.warnings.join(' | ').slice(0, 160));
        decoded = j.image;
      } else if (info.type === 'png') {
        decoded = await codecs.decodePng(decodeInput);
      } else {
        decoded = await codecs.decodeWebp(decodeInput);
      }
    } catch (e) {
      throw codecFailure(e, { taints: info.type === 'png' });
    }
    if (!decoded || !decoded.data) throw new DerivationError('decode_failed', 'the decoder returned no image');
    if (decoded.width !== info.width || decoded.height !== info.height || decoded.data.length !== info.width * info.height * 4) {
      throw new DerivationError('corrupt', `decoded ${decoded.width}x${decoded.height}, expected ${info.width}x${info.height}`);
    }
    const tDecode = performance.now();

    // Canonical geometry from the SOURCE header + EXIF orientation only.
    const swap = orientation >= 5;
    const out = outputSize(swap ? info.height : info.width, swap ? info.width : info.height, target, recipe.maxOutputHeightFactor);
    const rw = swap ? out.height : out.width, rh = swap ? out.width : out.height; // resize in the SOURCE orientation
    let px = new Uint8Array(decoded.data.buffer, decoded.data.byteOffset, decoded.data.length);
    let pw = info.width, ph = info.height;
    const k = Math.floor(Math.min(pw / rw, ph / rh));
    if (k >= recipe.box.minFactor) { const r = boxReduce(px, pw, ph, k); px = r.data; pw = r.width; ph = r.height; }
    const tBox = performance.now();
    if (rw !== pw || rh !== ph) {
      try {
        px = codecs.resize(px, pw, ph, rw, rh, recipe.resize.method, recipe.resize.premultiply, recipe.resize.linearRGB);
      } catch (e) {
        throw codecFailure(e, { taints: true });
      }
      if (!px || px.length !== rw * rh * 4) throw new DerivationError('self_check_failed', 'resize geometry');
    }
    const tResize = performance.now();
    if (px.byteOffset % 4) px = px.slice();
    const oriented = applyOrientation(px, rw, rh, orientation);
    if (oriented.width !== out.width || oriented.height !== out.height) throw new DerivationError('self_check_failed', 'orientation geometry');
    let transparent = false;
    for (let i = 3; i < oriented.data.length; i += 4) if (oriented.data[i] !== 255) { transparent = true; break; }
    const tOrient = performance.now();

    const quality = recipe.ladder[rung];
    let outBytes;
    try {
      const rgba = new Uint8ClampedArray(oriented.data.buffer, oriented.data.byteOffset, oriented.data.length);
      outBytes = new Uint8Array(await codecs.encodeWebp(rgba, out.width, out.height, { ...recipe.webp, quality }));
    } catch (e) {
      throw codecFailure(e, { taints: false });
    }
    const tEncode = performance.now();

    // Self-check: a still WebP of exactly the expected size, alpha iff expected, no metadata.
    let w;
    try { w = webpInfo(outBytes); } catch (e) { throw new DerivationError('self_check_failed', detailOf(e)); }
    const tags = w.chunks.map((c) => c.tag.trim()).join(',');
    if (w.width !== out.width || w.height !== out.height) throw new DerivationError('self_check_failed', 'dimensions');
    if (tags !== (transparent ? 'VP8X,ALPH,VP8' : 'VP8')) throw new DerivationError('self_check_failed', `chunks ${tags}`);
    if (w.animated || w.metadataFlags.icc || w.metadataFlags.exif || w.metadataFlags.xmp || transparent !== w.alphaFlag) {
      throw new DerivationError('self_check_failed', 'flags');
    }
    const ms = {
      sniff: +(tSniff - t0).toFixed(1), decode: +(tDecode - tSniff).toFixed(1), box: +(tBox - tDecode).toFixed(1),
      resize: +(tResize - tBox).toFixed(1), orient: +(tOrient - tResize).toFixed(1), encode: +(tEncode - tOrient).toFixed(1),
    };
    const attempt = { rung, quality, bytes: outBytes.length };
    if (outBytes.length > recipe.maxOutputBytes) {
      // Exact lower bound for every later rung: the ALPH chunk is identical at every
      // rung (alpha_quality 100, lossless), so RIFF(12) + VP8X(18) + ALPH + VP8 header(8)
      // + a minimal 10-byte VP8 frame is a floor on every rung's size.
      const alph = w.chunks.find((c) => c.tag === 'ALPH');
      const floor = alph ? 12 + 18 + 8 + alph.size + (alph.size & 1) + 8 + 10 : 0;
      if (floor > recipe.maxOutputBytes) throw new DerivationError('output_too_large', JSON.stringify({ ...attempt, reason: 'alpha_chunk_exceeds_cap', alphBytes: alph.size, floor }));
      if (rung === recipe.ladder.length - 1) throw new DerivationError('output_too_large', JSON.stringify({ ...attempt, reason: 'every_rung_exceeds_cap' }));
      return { status: 'ladder_next', nextRung: rung + 1, attempt: { ...attempt, alphBytes: alph ? alph.size : 0, floor }, ms: { ...ms, total: +(performance.now() - t0).toFixed(1) } };
    }
    return {
      status: 'derived',
      rung,
      quality,
      bytes: outBytes,
      byteLength: outBytes.length,
      sha256: await sha256Hex(outBytes),
      width: w.width,
      height: w.height,
      hasAlpha: transparent,
      chunks: tags.split(','),
      orientation,
      source: { type: info.type, width: info.width, height: info.height, ...(info.type === 'jpeg' ? { components: info.components, progressive: info.progressive, scans: info.scans } : {}) },
      attempt,
      ms: { ...ms, total: +(performance.now() - t0).toFixed(1) },
      ...(inspect ? { preEncode: oriented.data } : {}),
    };
  }

  return {
    derive,
    /** Marks the engine as untrusted: every later derive() is refused as engine_unavailable. */
    poison,
    get poisoned() { return poisoned; },
  };
}

const base64Bytes = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

/**
 * EDGE-4: derives the embedded vector and compares it with the pinned golden. On any
 * failure or mismatch the deriver is poisoned and DerivationError('engine_unavailable') is thrown.
 */
export async function engineSelfTest(deriver, golden = SELF_TEST.sha256) {
  let r = null;
  try {
    r = await deriver.derive(base64Bytes(SELF_TEST.pngBase64), { variant: SELF_TEST.variant, source: SELF_TEST.source, rung: 0 });
  } catch (e) {
    deriver.poison();
    throw new DerivationError('engine_unavailable', `self-test failed: ${e && e.code ? e.code : 'error'}`);
  }
  if (r.status !== 'derived' || r.sha256 !== golden || r.width !== SELF_TEST.width || r.height !== SELF_TEST.height) {
    deriver.poison();
    throw new DerivationError('engine_unavailable', 'self-test output differs from the pinned golden');
  }
  return r;
}

/**
 * The verified engine: every wasm must match its pinned sha-256 BEFORE anything is
 * compiled; then the codecs load, and the embedded vector must reproduce its golden.
 * @param {{ png: Uint8Array, resize: Uint8Array, jpegDec: Uint8Array, webpEnc: Uint8Array, webpDec: Uint8Array }} wasm
 */
export async function createDeriver(wasm) {
  for (const key of WASM_KEYS) {
    const bytes = wasm && Object.prototype.hasOwnProperty.call(wasm, key) ? wasm[key] : null;
    if (!(bytes instanceof Uint8Array)) throw new DerivationError('engine_unavailable', `engine wasm ${key} missing`);
    const expected = ENGINE_FILES.find((f) => f.key === key).sha256;
    const actual = await sha256Hex(bytes);
    if (actual !== expected) throw new DerivationError('engine_unavailable', `engine wasm ${key} sha-256 ${actual} is not the pinned ${expected}`);
  }
  const codecs = await loadCodecs({ png: wasm.png, resize: wasm.resize, jpegDec: wasm.jpegDec, webpEnc: wasm.webpEnc, webpDec: wasm.webpDec });
  const deriver = createDeriverFromCodecs(codecs);
  await engineSelfTest(deriver);
  return deriver;
}
