// Test helper: the function's block of supabase/config.toml (read, never written).
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const FUNCTION_DIR = new URL('../', import.meta.url);

/** The static files the deploy bundle must carry, exactly and in this order. */
export const STATIC_FILES = Object.freeze([
  './functions/storefront-media-publish/vendor/jsquash/png/squoosh_png_bg.wasm',
  './functions/storefront-media-publish/vendor/jsquash/resize/squoosh_resize_bg.wasm',
  './functions/storefront-media-publish/vendor/jsquash/jpeg-dec/mozjpeg_dec.wasm',
  './functions/storefront-media-publish/vendor/jsquash/webp-enc/webp_enc.wasm',
  './functions/storefront-media-publish/vendor/jsquash/webp-dec/webp_dec.wasm',
  './functions/storefront-media-publish/vendor/THIRD_PARTY_NOTICES.txt',
]);

/** The [functions.storefront-media-publish] block of supabase/config.toml, LF-normalised. */
export async function functionConfigBlock() {
  const toml = (await readFile(new URL('../../config.toml', FUNCTION_DIR), 'utf8')).replace(/\r\n/g, '\n');
  const block = /\n\[functions\.storefront-media-publish\]\n([\s\S]*?)(?=\n\[|$)/.exec(toml);
  assert.ok(block, 'config.toml declares the function');
  return block[1];
}

/** The static_files array of that block (a TOML array of plain double-quoted strings). */
export async function configuredStaticFiles() {
  const m = /^static_files = \[([^\]]*)\]$/m.exec(await functionConfigBlock());
  assert.ok(m, 'static_files is declared');
  const items = [...m[1].matchAll(/"([^"\\]*)"/g)].map((x) => x[1]);
  // nothing but those strings, commas and whitespace inside the brackets
  assert.equal(m[1].replace(/"[^"\\]*"/g, '').replace(/[\s,]/g, ''), '', 'static_files holds plain strings only');
  return items;
}
