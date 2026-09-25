// Test helper: the pinned engine exactly as the function loads it — the five
// vendored, sha-pinned jSquash wasm files through lib/recipe.mjs createDeriver()
// (hash check, codec load, EDGE-4 self-test) — created once per test process.
import { readFile } from 'node:fs/promises';
import { createDeriver, RECIPE } from '../lib/recipe.mjs';
import { loadCodecs } from '../lib/codecs.mjs';

export const FUNCTION_DIR = new URL('../', import.meta.url);
export const VENDOR_DIR = new URL('vendor/', FUNCTION_DIR);

/** The five wasm files as the function reads them (by the recipe's own paths). */
export async function readWasm() {
  const out = {};
  for (const key of RECIPE.engine.wasmKeys) {
    const pin = RECIPE.engine.files.find((f) => f.key === key);
    out[key] = new Uint8Array(await readFile(new URL(pin.path, FUNCTION_DIR)));
  }
  return out;
}

let deriverPromise = null;
let codecsPromise = null;

/** One verified deriver per process (single-flight, like the function). */
export function deriver() {
  deriverPromise ??= readWasm().then((wasm) => createDeriver(wasm));
  return deriverPromise;
}

/**
 * The raw codecs over the same wasm (fixture WebP encoding, the alpha proof's WebP
 * decode, and separate derivers whose poison flag must not touch the shared one).
 * The PNG / resize wasm-bindgen instance is per process, shared with deriver().
 */
export function codecs() {
  codecsPromise ??= deriver().then(() => readWasm()).then((wasm) => loadCodecs(wasm));
  return codecsPromise;
}
