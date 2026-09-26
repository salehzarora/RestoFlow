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

test('S8. no fault or kill channel (a lexical guard; code review is the backstop): through any receiver, the function reads three request headers and never the URL, the query or the header map, and Deno.serve takes createHandler directly (STOREFRONT-CANARY-GATE-001); and the PNG decoder and resize module are instantiated per call from the one compiled module, never once per worker (STOREFRONT-MEDIA-MEMORY-001)', async () => {
  // every `.headers` token, whatever its receiver, must be `<receiver>.headers.get('<literal>')` from this list
  const ALLOWED = [
    "lib/caller.mjs:res.headers.get('content-length')",
    "lib/handler.mjs:req.headers.get('authorization')",
    "lib/handler.mjs:req.headers.get('content-length')",
    "lib/handler.mjs:req.headers.get('content-type')",
    // the pinned glue's own streaming-load path, unreachable: the per-call factories return only initSync and decode / resize (L7 pins the text)
    "lib/png_instance.mjs:module.headers.get('Content-Type')",
    "lib/resize_instance.mjs:module.headers.get('Content-Type')",
  ];
  const strip = (s) => s.replace(/'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\.)*`/g, "''");
  const scan = (name, code) => {
    const out = [];
    for (const m of code.matchAll(/\.\s*headers\b/g)) {
      const lit = /^\.headers\.get\('([^'\\]*)'\)/.exec(code.slice(m.index));
      const recv = /([A-Za-z_$][\w$]*)$/.exec(code.slice(0, m.index));
      out.push(lit && recv ? `${name}:${recv[1]}.headers.get('${lit[1]}')` : `${name}:BAD ${code.slice(m.index, m.index + 40)}`);
    }
    for (const m of code.matchAll(/\.\s*url\b/g)) {
      if (code.slice(Math.max(0, m.index - 11), m.index) !== 'import.meta') out.push(`${name}:BAD url ${code.slice(Math.max(0, m.index - 20), m.index + 20)}`);
    }
    for (const m of code.matchAll(/Deno\.serve\(/g)) {
      if (!code.startsWith('Deno.serve(createHandler({', m.index)) out.push(`${name}:BAD a wrapper around the handler`);
    }
    if (/\bsearchParams\b|\[\s*['"`](?:headers|url|searchParams)['"`]\s*\]/.test(code)) out.push(`${name}:BAD the query or a computed member`);
    if (/(?:const|let|var)\s*\{[^}]*\b(?:headers|url)\b|\(\s*\{[^}]*\b(?:headers|url)\b[^}]*\}\s*\)\s*=>/.test(strip(code))) out.push(`${name}:BAD destructuring`);
    return out;
  };
  const found = [];
  let urls = 0;
  for (const { name, text } of await sources()) {
    const code = codeOf(text);
    found.push(...scan(name, code));
    for (const m of code.matchAll(/new URL\(/g)) {
      assert.equal(name, 'index.ts', `${name} builds a URL`);
      assert.ok(code.startsWith("new URL('./vendor/jsquash/", m.index), 'index.ts builds a URL other than a vendored static file');
      urls++;
    }
  }
  assert.deepEqual(found.sort(), [...ALLOWED].sort());
  assert.equal(urls, 5, 'exactly the five static wasm URLs');
  const index = (await sources()).find((s) => s.name === 'index.ts').text;
  assert.equal([...codeOf(index).matchAll(/Deno\.serve\(/g)].length, 1, 'one Deno.serve');
  // self-test: every shape below is caught when it appears in the handler; the allowlisted form is not
  const caught = (src) => scan('lib/handler.mjs', src).some((e) => !ALLOWED.includes(e));
  for (const bad of [
    "new URL(req.url).searchParams.get('f')", "req.headers.has('x-f')", "req.headers['x-f']", 'req.headers.entries()',
    'req.headers.get("x-kill")', 'req.headers.get(`x-kill`)', 'req.headers.get(name)', "request.headers.get('authorization')",
    "request.url.endsWith('/kill')", "const h = req.headers; h.get('x-kill');", "const { headers } = req; headers.get('x-kill');",
    "Deno.serve((request) => (request.headers.get('x-kill') ? kill() : handle(request)));", "req['headers'].get('x-kill')",
  ]) assert.ok(caught(bad), bad);
  assert.ok(!caught("req.headers.get('authorization')"), 'the allowlisted form is not flagged');

  // STOREFRONT-MEDIA-MEMORY-001 (D-041 point 3): the PNG decoder and the resize module are instantiated per
  // call from the one compiled module, never once per worker, and no glue state lives outside the per-call
  // factory. A lexical lock that strips only full-line // comments, so no string literal can hide code from it.
  const lineCode = (text) => text.split(/\r?\n/).filter((l) => !/^\s*\/\//.test(l)).join('\n');
  const PER_CALL = [
    'decodePng: async (u8) => { const png = freshPng(); png.initSync(pngM); return png.decode(u8); },',
    'resize: (rgba, sw, sh, dw, dh, method, premultiply, linear) => { const r = freshResize(); r.initSync(resizeM); return r.resize(rgba, sw, sh, dw, dh, method, premultiply, linear); },',
  ];
  const COMPILE_ONCE = ['const pngM = await WebAssembly.compile(bytes.png);', 'const resizeM = await WebAssembly.compile(bytes.resize);'];
  const IMPORTS = ["import { freshPng } from './png_instance.mjs';", "import { freshResize } from './resize_instance.mjs';"];
  const FACTORIES = [
    ['lib/png_instance.mjs', 'freshPng', 'vendor/jsquash/png/squoosh_png.js', 'initSync, decode'],
    ['lib/resize_instance.mjs', 'freshResize', 'vendor/jsquash/resize/squoosh_resize.js', 'initSync, resize'],
  ];
  // each factory file's whole code, rebuilt from the pinned glue by the rule L7 pins: nothing before, inside or after it may differ
  const expected = new Map();
  for (const [lib, fn, glue, ret] of FACTORIES) {
    const src = (await readFile(new URL(glue, FUNCTION_DIR), 'utf8')).replace(/\r\n/g, '\n');
    const body = src.slice(0, src.indexOf('async function __wbg_init(input) {')).replace(/^export (function|class) /gm, '$1 ');
    expected.set(lib, lineCode(`export function ${fn}() {\nconst __wbg_init = {};\n${body}return { ${ret} };\n}\n`).trim());
  }
  const lifecycle = (files) => {
    const bad = [];
    const count = (s, re) => [...s.matchAll(re)].length;
    for (const { name, text } of files) {
      const code = lineCode(text);
      if (/(?:\bfrom\s*|\bimport\s*\(\s*|\brequire\s*\(\s*)['"`][^'"`]*squoosh_(?:png|resize)\.js['"`]/.test(code)) bad.push(`${name}: loads the per-worker glue module`);
      if (/\bimport\s*\(\s*[^'"`\s]/.test(code)) bad.push(`${name}: a dynamic import with a computed specifier`);
      if (!expected.has(name) && name !== 'lib/codecs.mjs' && /\bfresh(?:Png|Resize)\b/.test(code)) bad.push(`${name}: uses a codec factory outside lib/codecs.mjs`);
    }
    const codecs = files.find((f) => f.name === 'lib/codecs.mjs');
    const flat = codecs ? lineCode(codecs.text).replace(/\s+/g, ' ') : '';
    for (const form of [...PER_CALL, ...COMPILE_ONCE, ...IMPORTS]) if (!flat.includes(form)) bad.push(`lib/codecs.mjs: missing ${form.slice(0, 48)}`);
    for (const [re, n, what] of [
      [/\bfreshPng\b/g, 2, 'freshPng'], [/\bfreshResize\b/g, 2, 'freshResize'], [/\binitSync\b/g, 2, 'initSync'], [/\bpngM\b/g, 2, 'pngM'], [/\bresizeM\b/g, 2, 'resizeM'],
      [/\bdecodePng\s*:/g, 1, 'the decodePng entry'], [/\bresize\s*:/g, 1, 'the resize entry'],
    ]) if (count(flat, re) !== n) bad.push(`lib/codecs.mjs: ${what} x${count(flat, re)} (expected ${n})`);
    for (const [lib] of FACTORIES) {
      const f = files.find((x) => x.name === lib);
      if (!f) bad.push(`${lib}: missing`);
      else if (lineCode(f.text).trim() !== expected.get(lib)) bad.push(`${lib}: differs from the per-call factory rebuilt from the pinned glue`);
    }
    return bad;
  };
  const real = await sources();
  assert.deepEqual(lifecycle(real), [], 'the per-call codec lifecycle holds');
  // self-test: each regression to a per-worker, cached or shared PNG / resize instance or glue state is caught
  const edit = (name, from, to) => real.map((f) => {
    if (f.name !== name) return f;
    assert.ok(f.text.includes(from), `probe anchor present in ${name}: ${from.slice(0, 40)}`);
    return { name, text: f.text.replace(from, to) };
  });
  const [pngForm, resizeForm] = PER_CALL;
  const hoist = (files, i, stmt) => files.map((f) => (f.name === 'lib/codecs.mjs' ? { ...f, text: f.text.replace(COMPILE_ONCE[i], `${COMPILE_ONCE[i]} ${stmt}`) } : f));
  const append = (files, name, tail) => files.map((f) => (f.name === name ? { ...f, text: `${f.text}${tail}` } : f));
  for (const [label, files] of [
    ['a PNG instance hoisted to the worker', hoist(edit('lib/codecs.mjs', pngForm, 'decodePng: async (u8) => png.decode(u8),'), 0, 'const png = freshPng(); png.initSync(pngM);')],
    ['a resize instance hoisted to the worker', hoist(edit('lib/codecs.mjs', resizeForm, 'resize: (rgba, sw, sh, dw, dh, method, premultiply, linear) => r.resize(rgba, sw, sh, dw, dh, method, premultiply, linear),'), 1, 'const r = freshResize(); r.initSync(resizeM);')],
    ['a PNG instance cached across calls', edit('lib/codecs.mjs', 'const png = freshPng();', 'const png = (cachedPng ??= freshPng());')],
    ['a resize instance cached across calls', edit('lib/codecs.mjs', 'const r = freshResize();', 'const r = (cachedResize ??= freshResize());')],
    ['a fresh PNG instance built but the first one reused', edit('lib/codecs.mjs', 'return png.decode(u8);', 'return (usedPng ??= png).decode(u8);')],
    ['a second decodePng entry hidden between comment-like string literals', edit('lib/codecs.mjs', pngForm, `${pngForm} _a: '/*', decodePng: async (u8) => { const png = freshPng(); png.initSync(pngM); return (usedPng ??= png).decode(u8); }, _b: '*/',`)],
    ['the factory aliased behind a memo', edit('lib/codecs.mjs', IMPORTS[0], "import { freshPng as makePng } from './png_instance.mjs'; const freshPng = once(makePng);")],
    ['the per-worker PNG glue imported again', edit('lib/codecs.mjs', IMPORTS[0], `${IMPORTS[0]} import * as pngGlue from '../vendor/jsquash/png/squoosh_png.js';`)],
    ['the per-worker resize glue loaded dynamically', edit('lib/recipe.mjs', "import { loadCodecs } from './codecs.mjs';", "import { loadCodecs } from './codecs.mjs'; const rs = await import('../vendor/jsquash/resize/squoosh_resize.js');")],
    ['the per-worker resize glue loaded through a computed specifier', edit('lib/recipe.mjs', "import { loadCodecs } from './codecs.mjs';", "import { loadCodecs } from './codecs.mjs'; const rs = await import(RECIPE_GLUE);")],
    ['a module-level instance before the PNG factory', edit('lib/png_instance.mjs', 'export function freshPng() {', 'let shared = null;\nexport function freshPng() {')],
    ['the PNG factory memoised after its body (one instance per worker)', append(edit('lib/png_instance.mjs', 'return { initSync, decode };', 'return pngMemo ??= { initSync, decode };'), 'lib/png_instance.mjs', '\nlet pngMemo;\n')],
    ['the resize factory memoised after its body (one instance per worker)', append(edit('lib/resize_instance.mjs', 'return { initSync, resize };', 'return rsMemo ??= { initSync, resize };'), 'lib/resize_instance.mjs', '\nlet rsMemo;\n')],
    ['the PNG glue heap slab moved to module level (shared glue state)', append(edit('lib/png_instance.mjs', 'const heap = new Array(128).fill(undefined);', ''), 'lib/png_instance.mjs', '\nconst heap = new Array(128).fill(undefined);\n')],
    ['a codec factory used outside lib/codecs.mjs', edit('lib/handler.mjs', 'export function createHandler(', "import { freshPng } from './png_instance.mjs';\nexport function createHandler(")],
    ['the PNG module compiled per call', edit('lib/codecs.mjs', 'png.initSync(pngM);', 'png.initSync(new WebAssembly.Module(bytes.png));')],
  ]) assert.ok(lifecycle(files).length > 0, `S8 catches: ${label}`);
});
