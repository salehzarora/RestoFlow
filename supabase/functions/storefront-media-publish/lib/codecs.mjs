// STOREFRONT-PUBLISH-001 recipe `storefront-media-c4`: the five pinned jSquash
// WebAssembly codecs (vendor/jsquash/, provenance in vendor/README.md), loaded
// from INJECTED wasm bytes (carried over from the Q031 spike).
//
// No fetch, no URL resolution, no feature detection: the caller (index.ts on the
// edge runtime, test/engine.mjs on Node) reads the pinned .wasm files and
// recipe.mjs verifies their sha-256 before anything is compiled here.
//
//   - PNG decode and resize are wasm-bindgen modules: a FRESH instance per call
//     (lib/png_instance.mjs and lib/resize_instance.mjs wrap the pinned glue's own
//     text as a per-call factory; STOREFRONT-CANARY-GATE-001 / D-041), so no decoder
//     heap outlives its request. A Rust error surfaces as a thrown JS Error WITHOUT
//     unwinding, and recipe.mjs still treats any exception from them as poisoning
//     the worker (the isolate is retired after answering; unchanged). Creating that
//     instance (the factory and initSync of the compiled module) never reads the
//     source, so a failure there is marked CodecInitError (STOREFRONT-MEDIA-ENGINE-
//     FAILURE-001 / D-042) and recipe.mjs answers it engine_unavailable; the decode
//     and resize OPERATIONS are never wrapped, so their exceptions keep their meaning.
//   - The Emscripten codecs (mozjpeg decoder, libwebp decoder and encoder) get a
//     FRESH instance per call, so their heaps (sized by the largest image they
//     saw) are released after every call instead of staying resident, and a
//     failure never leaves shared state behind. The JPEG decoder's warnings
//     (libjpeg "Corrupt JPEG data ...") are captured, never printed.
import { freshPng } from './png_instance.mjs';
import { freshResize } from './resize_instance.mjs';
import mozjpegDecFactory from '../vendor/jsquash/jpeg-dec/mozjpeg_dec.js';
import webpEncFactory from '../vendor/jsquash/webp-enc/webp_enc.js';
import webpDecFactory from '../vendor/jsquash/webp-dec/webp_dec.js';

// The decoders return ImageData; neither Node nor every edge runtime defines it.
// This is the ONLY place the polyfill is defined.
if (typeof globalThis.ImageData !== 'function') {
  globalThis.ImageData = class ImageData {
    constructor(data, width, height) { this.data = data; this.width = width; this.height = height; }
  };
}

/**
 * STOREFRONT-MEDIA-ENGINE-FAILURE-001 (D-042): the call's fresh PNG decoder or resize instance could not be
 * created or initialised — the per-call factory, or the initialisation of the instance from the cached
 * compiled module, threw (for example an instance whose memory cannot be allocated). These steps never read
 * the source, so this is an engine / runtime availability failure, never a verdict on the image: recipe.mjs
 * maps it to engine_unavailable and poisons the deriver. `codec` is 'png' | 'resize'; `cause` is the original
 * exception (never returned to a caller).
 */
export class CodecInitError extends Error {
  constructor(codec, cause) {
    super(`${codec} instance not created: ${String(cause && cause.message ? cause.message : cause).slice(0, 120)}`);
    this.name = 'CodecInitError';
    this.codec = codec;
    this.cause = cause;
  }
}

function instantiate(factory, module, messages = null) {
  return factory({
    print: (t) => { if (messages) messages.push(String(t).slice(0, 200)); },
    printErr: (t) => { if (messages) messages.push(String(t).slice(0, 200)); },
    noInitialRun: true,
    instantiateWasm(imports, callback) {
      const instance = new WebAssembly.Instance(module, imports);
      callback(instance);
      return instance.exports;
    },
    locateFile: (path) => path, // computed eagerly by the glue; never fetched (instantiateWasm is supplied)
  });
}

/** bytes: { png, resize, jpegDec, webpEnc, webpDec } (Uint8Array each, already sha-verified). */
export async function loadCodecs(bytes) {
  const pngM = await WebAssembly.compile(bytes.png);
  const resizeM = await WebAssembly.compile(bytes.resize);
  const [jpegDecM, webpEncM, webpDecM] = await Promise.all([bytes.jpegDec, bytes.webpEnc, bytes.webpDec].map((b) => WebAssembly.compile(b)));
  return {
    // D-042: the try covers EXACTLY the creation steps (factory + initSync); the decode / resize call stays outside it
    decodePng: async (u8) => { let png; try { png = freshPng(); png.initSync(pngM); } catch (e) { throw new CodecInitError('png', e); } return png.decode(u8); },
    decodeJpeg: async (u8) => {
      const warnings = [];
      const image = (await instantiate(mozjpegDecFactory, jpegDecM, warnings)).decode(u8, false);
      return { image, warnings };
    },
    decodeWebp: async (u8) => (await instantiate(webpDecFactory, webpDecM)).decode(u8),
    encodeWebp: async (rgba, w, h, opts) => (await instantiate(webpEncFactory, webpEncM)).encode(rgba, w, h, opts),
    resize: (rgba, sw, sh, dw, dh, method, premultiply, linear) => { let r; try { r = freshResize(); r.initSync(resizeM); } catch (e) { throw new CodecInitError('resize', e); } return r.resize(rgba, sw, sh, dw, dh, method, premultiply, linear); },
  };
}
