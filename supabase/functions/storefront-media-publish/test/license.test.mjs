// STOREFRONT-PUBLISH-001 — licence and provenance pins of the vendored codecs
// (closes review findings LIC-1, LIC-2, LIC-4, LIC-5, LIC-6 on the c4 engine).
//
// Proves on every run: every vendored file (the ten jSquash codec files AND the
// third-party notices) is byte-exact to its pinned sha-256; the vendor directory holds
// nothing else; the notices and the provenance README name every file's hash and carry
// the required IJG statement; the deploy bundle ships exactly the five .wasm files and
// the notices (config.toml static_files); and no path or file anywhere under the
// function belongs to the previous, LGPL-linked engine.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { RECIPE } from '../lib/recipe.mjs';
import { configuredStaticFiles, STATIC_FILES } from './config.mjs';

const FUNCTION_DIR = new URL('../', import.meta.url);
const sha = (b) => createHash('sha256').update(b).digest('hex');

// Pinned HERE, independently of lib/recipe.mjs (a single edit cannot move both).
const PINS = Object.freeze(new Map([
  ['vendor/jsquash/png/squoosh_png_bg.wasm', '263d6e658808a74b72a1a99c5cc1d619237e70c150db6e41d5d84d3d117ab9be'],
  ['vendor/jsquash/png/squoosh_png.js', '65ebe1192f970c46263d52a122edf6bd01be81174c6bf1736a16f1e6f0e9b411'],
  ['vendor/jsquash/jpeg-dec/mozjpeg_dec.wasm', 'a7c4b12169817e779ff4af137981393ae924944e167ad1bd95747c9199162d3e'],
  ['vendor/jsquash/jpeg-dec/mozjpeg_dec.js', 'a6836b2d03d4fdda64b4aef380e6298d7421c070e7e1e4cf13ec129df7aa0b5e'],
  ['vendor/jsquash/webp-enc/webp_enc.wasm', 'b6085bb6702f144e9dc6016d58d230b34a84976bf0d080b7390b4b4b137d6ab7'],
  ['vendor/jsquash/webp-enc/webp_enc.js', '5fd62301662e37785aec38e38807926f72933d4c8b919018a43faf1b1ca760f6'],
  ['vendor/jsquash/webp-dec/webp_dec.wasm', '30fb52fa2a80166d25ba7debf902218904ba1f05ccce9f959f722beff9e2f344'],
  ['vendor/jsquash/webp-dec/webp_dec.js', 'c57971611f4d9ec04e4636ce7bb4a35c031b24cbdb013518f0a017d9f6014370'],
  ['vendor/jsquash/resize/squoosh_resize_bg.wasm', '5b1f702d502c4d0a70b99f78691bd554d566ba95859e4c57af5435955a1d74a5'],
  ['vendor/jsquash/resize/squoosh_resize.js', 'e974c442bb6a7f2b57a7c86a879f55a008ffd6fccea5f9ed9fee14900ae56225'],
  ['vendor/THIRD_PARTY_NOTICES.txt', 'aca02b5e7f056fc00e9defe6784456d1852fcf7d81c2c0bf2c41dcd640411af5'],
]));
const IJG = 'This software is based in part on the work of the Independent JPEG Group.';

async function walk(dirUrl, prefix = '') {
  const out = [];
  for (const e of await readdir(dirUrl, { withFileTypes: true })) {
    const rel = `${prefix}${e.name}`;
    if (e.isDirectory()) out.push(`${rel}/`, ...(await walk(new URL(`${e.name}/`, dirUrl), `${rel}/`)));
    else out.push(rel);
  }
  return out;
}

test('L1. every vendored file (ten codec files + THIRD_PARTY_NOTICES.txt) is byte-exact to its pinned sha-256', async () => {
  for (const [path, pinned] of PINS) {
    assert.equal(sha(await readFile(new URL(path, FUNCTION_DIR))), pinned, path);
  }
  // the recipe's own pins agree with these, file for file
  assert.equal(RECIPE.engine.files.length, 10);
  for (const f of RECIPE.engine.files) assert.equal(f.sha256, PINS.get(f.path), `RECIPE pin of ${f.path}`);
});

test('L2. the vendor directory holds exactly the pinned files and the provenance README (no stray codec, licence or glue)', async () => {
  const files = (await walk(new URL('vendor/', FUNCTION_DIR))).filter((p) => !p.endsWith('/')).map((p) => `vendor/${p}`).sort();
  assert.deepEqual(files, [...PINS.keys(), 'vendor/README.md'].sort());
});

test('L3. the notices name every vendored file with its sha-256 and carry the IJG statement; the README records the provenance', async () => {
  const notices = await readFile(new URL('vendor/THIRD_PARTY_NOTICES.txt', FUNCTION_DIR), 'utf8');
  const readme = await readFile(new URL('vendor/README.md', FUNCTION_DIR), 'utf8');
  for (const [path, pinned] of PINS) {
    if (path.endsWith('THIRD_PARTY_NOTICES.txt')) continue;
    const short = path.slice('vendor/jsquash/'.length);
    assert.match(notices, new RegExp(`${short.replace(/[.]/g, '\\.')}\\s+${pinned}`), `notices list ${short}`);
    assert.ok(readme.includes(pinned), `README records ${path}`);
  }
  assert.ok(readme.includes(PINS.get('vendor/THIRD_PARTY_NOTICES.txt')), 'README records the notices hash');
  assert.ok(notices.includes(IJG), 'notices carry the IJG statement');
  assert.ok(readme.includes(IJG), 'README carries the IJG statement');
  for (const s of ['@jsquash/png@3.1.1', '@jsquash/jpeg@1.6.0', '@jsquash/webp@1.5.0', '@jsquash/resize@2.1.1',
    'sha512-C10pc+0H6j0h8fENOfnGOvkXCmvpSQTDGlfGd0sHphZhPSGTyLjIrHba0FaZZdsKqA/wlmhYicUHb92vfZphaw==',
    'sha512-zwN46Awh1VM6gXlIcALwb5WzqK5H2e6+Awcs1QP8AvS8ohsK/sbE4esvmH4jhlhW7+CgiUUww66vg0aTnlSIMA==',
    'sha512-KggLoj2MnRSfIqTeKe1EmbljTX2vuV7mh79k89PCL1pyqiDULcPM1L47twxXt0hkb68F70bXiL31MxsuoZtKFw==',
    'sha512-0R5UL1ZLHUT+carjVikcE1QfA+kfNQ2YamYyGVRmhfh4zttU5EY3bQBGxPIPtY2xIAw1P4Kgyxm2xrceRw1r2w==',
    'b7fa9ac9ec02f224847ad23d19d115f9e296a368', '1f62015f53e28bd18b2d7c8a3ca3326577efc445', '8bcd212da8c2be7c9c223e8f222eb3d9574a713b', 'da47a2be3b302beb5a5ae164a2ab7aa21a041d90',
    'd2e245ea9e959a5a79e1db0ed2085206947e98f2', 'f154ccc091cbc22141cdfd531e5ad1fdc5bc53c7', 'unmodified', 'Upgrade rule']) {
    assert.ok(readme.includes(s), `README records ${s}`);
  }
  // each jSquash gitHead is the one the notices header names for that package
  for (const g of ['b7fa9ac9ec02f224847ad23d19d115f9e296a368', '1f62015f53e28bd18b2d7c8a3ca3326577efc445', '8bcd212da8c2be7c9c223e8f222eb3d9574a713b', 'da47a2be3b302beb5a5ae164a2ab7aa21a041d90']) {
    assert.ok(notices.includes(g), `notices name gitHead ${g}`);
  }
});

test('L4. the deploy bundle ships exactly the five codec .wasm files and the notices (config.toml static_files)', async () => {
  assert.deepEqual(await configuredStaticFiles(), STATIC_FILES);
  for (const f of STATIC_FILES) {
    const path = f.slice('./functions/storefront-media-publish/'.length);
    assert.ok(PINS.has(path), `${path} is a pinned file`);
  }
});

test('L5. vendored bytes are never normalised by git (.gitattributes: vendor/** -text, .wasm binary, fixtures binary)', async () => {
  const attrs = (await readFile(new URL('.gitattributes', FUNCTION_DIR), 'utf8')).split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  assert.ok(attrs.includes('vendor/** -text'));
  assert.ok(attrs.includes('vendor/**/*.wasm binary'));
  assert.ok(attrs.includes('test/fixtures/*.jpg binary'));
});

test('L6. nothing under the function belongs to the previous engine: no path and no file names it', async () => {
  const banned = ['ma', 'gick'].join(''); // spelled in two parts so this file passes its own check
  const paths = await walk(FUNCTION_DIR);
  assert.ok(paths.length > 20, 'the walk sees the function tree');
  for (const p of paths) assert.ok(!p.toLowerCase().includes(banned), `path ${p}`);
  for (const p of paths.filter((x) => !x.endsWith('/'))) {
    const text = (await readFile(new URL(p, FUNCTION_DIR))).toString('latin1').toLowerCase();
    assert.ok(!text.includes(banned), `file ${p}`);
  }
});
