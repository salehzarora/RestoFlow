// STOREFRONT-PUBLISH-001 — static guard of the function's source and configuration:
// no privileged credential path, no environment beyond the two public settings
// (every Deno.env token counted and every code use of the Deno global allowlisted,
// review TNV-9), no remote or floating imports, no delete / overwrite path, JWT
// verification on, and the deploy bundle's static files are exactly the five pinned
// codec .wasm files plus the third-party notices.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { FUNCTION_DIR, VENDOR_DIR } from './engine.mjs';
import { RECIPE } from '../lib/recipe.mjs';
import { configuredStaticFiles, functionConfigBlock, STATIC_FILES } from './config.mjs';

async function sources() {
  const files = [new URL('index.ts', FUNCTION_DIR)];
  for (const f of await readdir(new URL('lib/', FUNCTION_DIR))) files.push(new URL(`lib/${f}`, FUNCTION_DIR));
  return Promise.all(files.map(async (u) => ({ name: u.href.slice(FUNCTION_DIR.href.length), text: await readFile(u, 'utf8') })));
}
const GLUE = RECIPE.engine.files.filter((f) => f.path.endsWith('.js')).map((f) => f.path);

test('S1. no privileged credential, secret or storage key is referenced anywhere in the function source', async () => {
  const forbidden = [
    /service_role/i, /SERVICE_ROLE/, /SUPABASE_SERVICE/, /SECRET_KEY/, /SUPABASE_SECRET/, /sb_secret_/, /SUPABASE_DB_URL/,
    /\bS3_[A-Z]/, /\bAWS_[A-Z]/, /\bprocess\.env\b/, /\bpostgres(ql)?:\/\//i,
  ];
  for (const { name, text } of await sources()) {
    for (const re of forbidden) assert.ok(!re.test(text), `${name} matches ${re}`);
  }
});

// Every syntactic route to Deno.env: dot, optional chaining or bracket access on Deno.
const ENV_TOKEN = /\bDeno\s*(?:\?\.\s*|\.\s*)env\b|\bDeno\s*(?:\?\.\s*)?\[/g;
// Every CODE use of the Deno global: member access, or Deno as a value (aliasing,
// destructuring, an argument, globalThis.Deno, globalThis['Deno']). Prose in comments is not a use.
const DENO_USE = /\bDeno\s*(?:\?\.|\.|\[)|[=({,:]\s*Deno\b|\.\s*Deno\b|\[\s*['"`]Deno['"`]\s*\]/g;
// Source without its full-line // comments and /* */ blocks (prose may name the runtime).
const codeOf = (text) => text.split(/\r?\n/).filter((l) => !/^\s*\/\//.test(l)).join('\n').replace(/\/\*[\s\S]*?\*\//g, '');
const ALLOWED_DENO_USE = [
  /^Deno\.env\.get\('SUPABASE_URL'\)/, /^Deno\.env\.get\('SUPABASE_ANON_KEY'\)/,
  /^Deno\.readFile\(new URL\('\.\/vendor\/jsquash\//, /^Deno\.serve\(/,
];

test('S2. exactly two environment reads (SUPABASE_URL, SUPABASE_ANON_KEY); EVERY Deno.env token and every code use of Deno is allowlisted', async () => {
  const all = await sources();
  const envTokens = [];
  const uses = [];
  for (const { name, text } of all) {
    for (const m of text.matchAll(ENV_TOKEN)) envTokens.push(`${name}@${m.index}`);
    const code = codeOf(text);
    for (const m of code.matchAll(DENO_USE)) { const at = m.index + m[0].indexOf('Deno'); uses.push({ name, rest: code.slice(at, at + 60) }); }
    assert.ok(!/\btoObject\b/.test(text), `${name} dumps the environment`);
  }
  assert.equal(envTokens.length, 2, `Deno.env appears exactly twice (found at ${envTokens.join(', ')})`);
  const reads = [];
  for (const { name, text } of all) for (const m of text.matchAll(/Deno\.env\.get\(([^)]*)\)/g)) reads.push(`${name}:${m[1]}`);
  assert.deepEqual(reads.sort(), ["index.ts:'SUPABASE_ANON_KEY'", "index.ts:'SUPABASE_URL'"]);
  assert.ok(uses.length >= 8, 'the scan sees the known uses');
  for (const { name, rest } of uses) {
    assert.equal(name, 'index.ts', `lib/ stays host-agnostic, but ${name} uses Deno: ${JSON.stringify(rest)}`);
    assert.ok(ALLOWED_DENO_USE.some((re) => re.test(rest)), `index.ts uses Deno as ${JSON.stringify(rest)}`);
  }
});

test('S2b. the Deno-use scan itself catches aliases, destructuring and bracket access (self-test of the guard)', () => {
  const caught = (src) => [...src.matchAll(DENO_USE)].some((m) => !ALLOWED_DENO_USE.some((re) => re.test(src.slice(m.index + m[0].indexOf('Deno')))))
    || [...src.matchAll(ENV_TOKEN)].length > 0;
  for (const bad of ['const e = Deno.env; e.get("X");', 'const { env } = Deno;', "Deno['env'].get('X')", 'Deno?.env?.get("X")',
    'const d = globalThis.Deno;', "globalThis['Deno'].env", 'f(Deno)', 'Deno.readFile("/etc/passwd")', 'Deno.env.toObject()']) {
    assert.ok(caught(bad), bad);
  }
  assert.ok(!caught('// runs on the Deno edge runtime and on Node'), 'prose is not a use');
});

test('S3. every import is relative (vendored, pinned): no npm:, jsr:, http(s): or bare specifiers; the vendored glue imports nothing', async () => {
  for (const { name, text } of await sources()) {
    for (const m of text.matchAll(/\b(?:import|export)\b[^'"]*?\bfrom\s+['"]([^'"]+)['"]|\bimport\(\s*['"]([^'"]+)['"]\s*\)/g)) {
      const spec = m[1] ?? m[2];
      assert.ok(spec.startsWith('./') || spec.startsWith('../'), `${name} imports ${spec}`);
    }
    assert.ok(!/https?:\/\//.test(text), `${name} carries a hard-coded URL`);
  }
  assert.equal(GLUE.length, 5);
  for (const path of GLUE) {
    const glue = await readFile(new URL(path, FUNCTION_DIR), 'utf8');
    assert.ok(!/Deno\.env|process\.env/.test(glue), `${path} reads no environment`);
    assert.ok(!/^\s*import\s|\bfrom\s*['"]|\bimport\(\s*['"]|\brequire\(/m.test(glue), `${path} imports nothing`);
  }
});

test('S4. no delete, move, copy or overwrite path: an ALLOWLIST of upstream methods and storage routes', async () => {
  for (const { name, text } of await sources()) {
    // every HTTP method literal is exactly GET or POST (case-insensitive allowlist, not a denylist)
    for (const m of text.matchAll(/\bmethod\s*:\s*['"]([A-Za-z]+)['"]/g)) {
      assert.ok(['GET', 'POST'].includes(m[1].toUpperCase()) && m[1] === m[1].toUpperCase(), `${name} uses method ${m[1]}`);
    }
    assert.ok(!/['"](?:DELETE|PUT|PATCH)['"]/i.test(text), `${name} names a mutating method`);
    assert.ok(!/\.remove\(|\/object\/move|\/object\/copy|\/object\/sign|\/object\/upload\/sign/i.test(text), `${name} reaches a remove / move / copy / signing route`);
    // x-upsert appears only as the literal 'false'
    for (const m of text.matchAll(/['"]x-upsert['"]\s*:\s*([^,}\n]+)/gi)) assert.equal(m[1].trim(), "'false'", `${name} x-upsert ${m[1]}`);
    assert.ok(!/cancel_storefront_media|retract_storefront_media/.test(text), `${name} cancels or retracts on its own`);
  }
  const caller = (await sources()).find((s) => s.name === 'lib/caller.mjs').text;
  assert.match(caller, /'x-upsert': 'false'/);
  // the only storage routes: GET /object/authenticated/<bucket>/<key> and POST /object/<bucket>/<key>
  const routes = [...caller.matchAll(/\/storage\/v1\/object\/([a-z]*)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(routes)].sort(), ['', 'authenticated']);
});

test('S5. the deployment config keeps JWT verification ON and ships EXACTLY the five codec wasm files and the notices as static files', async () => {
  const block = await functionConfigBlock();
  assert.match(block, /^enabled = true$/m);
  assert.match(block, /^verify_jwt = true$/m);
  assert.deepEqual(await configuredStaticFiles(), STATIC_FILES);
  // the list is the recipe's wasm set (same files, in the engine's key order) + the notices
  const wasm = RECIPE.engine.wasmKeys.map((k) => `./functions/storefront-media-publish/${RECIPE.engine.files.find((f) => f.key === k).path}`);
  assert.deepEqual(STATIC_FILES.slice(0, 5), wasm);
  assert.equal(STATIC_FILES[5], './functions/storefront-media-publish/vendor/THIRD_PARTY_NOTICES.txt');
});

test('S6. responses never echo private bytes or isolate state (no base64 / worker / raster fields in the handler output)', async () => {
  const handler = (await sources()).find((s) => s.name === 'lib/handler.mjs').text;
  assert.ok(!/toBase64|btoa\(|derivativeBase64/.test(handler));
  assert.ok(!/worker\s*:|spentMs|budget|preEncode|inspect/.test(handler));
});

test('S7. index.ts reads exactly the five static wasm files (by URL relative to itself) and builds the engine only through createDeriver', async () => {
  const index = (await sources()).find((s) => s.name === 'index.ts').text;
  const reads = [...index.matchAll(/Deno\.readFile\(new URL\('\.\/([^']+)', import\.meta\.url\)\)/g)].map((m) => `./functions/storefront-media-publish/${m[1]}`);
  assert.deepEqual(reads, STATIC_FILES.slice(0, 5));
  assert.equal([...index.matchAll(/Deno\.readFile\(/g)].length, 5, 'no other file is read');
  assert.match(index, /createDeriver\(\{ png, resize, jpegDec, webpEnc, webpDec \}\)/);
  assert.ok(!/createDeriverFromCodecs|loadCodecs/.test(index), 'the unverified test entry points are never used by the function');
  // the ImageData polyfill is defined in exactly one place
  const assignsImageData = /\.ImageData\s*=(?!=)|\[\s*['"`]ImageData['"`]\s*\]\s*=(?!=)|defineProperty\([^)]*ImageData/;
  const polyfills = (await sources()).filter((s) => assignsImageData.test(s.text)).map((s) => s.name);
  assert.deepEqual(polyfills, ['lib/codecs.mjs']);
  await readFile(new URL('THIRD_PARTY_NOTICES.txt', VENDOR_DIR)); // the notices exist where the bundle ships them
});
