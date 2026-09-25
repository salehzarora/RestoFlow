// STOREFRONT-PUBLISH-001 recipe `storefront-media-c4`: the five pinned jSquash
// WebAssembly codecs (vendor/jsquash/, provenance in vendor/README.md), loaded
// from INJECTED wasm bytes (carried over from the Q031 spike).
//
// No fetch, no URL resolution, no feature detection: the caller (index.ts on the
// edge runtime, test/engine.mjs on Node) reads the pinned .wasm files and
// recipe.mjs verifies their sha-256 before anything is compiled here.
//
//   - PNG decode and resize are wasm-bindgen modules: ONE instance per worker.
//     A Rust error surfaces as a thrown JS Error WITHOUT unwinding (its heap and
//     shadow stack are leaked), so recipe.mjs treats any exception from them as
//     poisoning the worker (the isolate is retired after answering).
//   - The Emscripten codecs (mozjpeg decoder, libwebp decoder and encoder) get a
//     FRESH instance per call, so their heaps (sized by the largest image they
//     saw) are released after every call instead of staying resident, and a
//     failure never leaves shared state behind. The JPEG decoder's warnings
//     (libjpeg "Corrupt JPEG data ...") are captured, never printed.
import * as pngGlue from '../vendor/jsquash/png/squoosh_png.js';
import * as resizeGlue from '../vendor/jsquash/resize/squoosh_resize.js';
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
  pngGlue.initSync(await WebAssembly.compile(bytes.png));
  resizeGlue.initSync(await WebAssembly.compile(bytes.resize));
  const [jpegDecM, webpEncM, webpDecM] = await Promise.all([bytes.jpegDec, bytes.webpEnc, bytes.webpDec].map((b) => WebAssembly.compile(b)));
  return {
    decodePng: async (u8) => pngGlue.decode(u8),
    decodeJpeg: async (u8) => {
      const warnings = [];
      const image = (await instantiate(mozjpegDecFactory, jpegDecM, warnings)).decode(u8, false);
      return { image, warnings };
    },
    decodeWebp: async (u8) => (await instantiate(webpDecFactory, webpDecM)).decode(u8),
    encodeWebp: async (rgba, w, h, opts) => (await instantiate(webpEncFactory, webpEncM)).encode(rgba, w, h, opts),
    resize: (rgba, sw, sh, dw, dh, method, premultiply, linear) => resizeGlue.resize(rgba, sw, sh, dw, dh, method, premultiply, linear),
  };
}
