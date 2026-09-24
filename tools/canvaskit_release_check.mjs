#!/usr/bin/env node
// ============================================================================
// BIZBOT — CanvasKit versioned-release coupling check.
//
// NOT a build input: nothing in the build reads this file, so the deployment
// filter classifies it as unconsumed_tools and it is irrelevant to every
// project. It exists so that couplings which are otherwise only visible on a
// deployment are asserted before one.
//
// WHAT THIS CHECKS, AND IN WHICH CLASS. The classes are reported separately and
// are never substituted for one another:
//
//   SOURCE-SHAPE   properties of the repository's own files, provable from the
//                  repository alone.
//   BEHAVIOUR      what the authored bootstrap template actually DOES, proven by
//                  substituting harmless tokens and running it against a MOCKED
//                  loader with two different synthetic build configs.
//   SDK-COUPLING   agreement between the config and an INDEPENDENT authority -
//                  the installed pinned Flutter SDK's own engine revision and
//                  its own CanvasKit distribution. Never derived from the
//                  vercel.json values being checked.
//   OUTPUT-COUPLING agreement with a genuinely generated build output.
//
// TWO MODES.
//   --mode required    (default) SDK-COUPLING is MANDATORY. If the authoritative
//                      reference is missing the run FAILS as INCOMPLETE. It can
//                      never print a clean pass without having done the coupling
//                      work. This is the mode CI must run.
//   --mode diagnostic  SOURCE-SHAPE and BEHAVIOUR only, for a source-only tree.
//                      Its summary says INCOMPLETE and names what it did not
//                      establish, so it cannot be mistaken for verification.
//
// A prior revision of this file had four false-pass cases, all found in
// independent review and all covered by canvaskit_release_check.test.mjs now:
//   * header revisions could be mutated wholesale and still pass, because only
//     their INTERNAL agreement was checked;
//   * a published file's header rule could be deleted and 17 rules accepted;
//   * the bootstrap check accepted any occurrence of `engineRevision`, including
//     one inside a comment;
//   * a constant-valued revision satisfied the URL-shape regex.
//
// Node standard library only. Reads; never writes, builds or deploys.
// ============================================================================
import { createHash } from 'node:crypto';
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const APPS = ['dashboard', 'pos', 'kds', 'kiosk'];
const TOKENS = ['{{flutter_js}}', '{{flutter_build_config}}', '{{flutter_service_worker_version}}'];
const ENGINE = 'tools/vercel/ignore-build.mjs';
const ASSEMBLER = 'tools/assemble_web_canvaskit.mjs';
const BUILD_SCRIPT = 'tools/vercel_build_web.sh';
const REVISION_RE = /^[0-9a-fA-F]{7,64}$/;

const arg = (n, d) => { const i = process.argv.indexOf(`--${n}`); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d; };
const MODE = arg('mode', 'required');
if (!['required', 'diagnostic'].includes(MODE)) { console.error(`--mode must be required or diagnostic`); process.exit(2); }

const read = (rel) => readFileSync(path.join(REPO, rel), 'utf8');
const lfHash = (text) => createHash('sha256').update(text.replace(/\r\n/g, '\n')).digest('hex');

const results = [];
const check = (cls, name, fn) => {
  try { const detail = fn(); results.push({ cls, name, ok: true, detail: detail ?? '' }); console.log(`PASS  [${cls}] ${name}${detail ? ` — ${detail}` : ''}`); }
  catch (e) { results.push({ cls, name, ok: false, detail: e.message }); console.error(`FAIL  [${cls}] ${name} — ${e.message}`); }
};
const must = (cond, msg) => { if (!cond) throw new Error(msg); };
const listFiles = (root) => {
  const out = [];
  (function walk(d) { for (const e of readdirSync(d, { withFileTypes: true })) { const f = path.join(d, e.name); e.isDirectory() ? walk(f) : out.push(path.relative(root, f).split(path.sep).join('/')); } })(root);
  return out.sort();
};

// ======================================================== SOURCE-SHAPE ====== //

check('SOURCE-SHAPE', 'the four bootstrap templates are byte-identical', () => {
  const hashes = new Set(APPS.map((a) => createHash('sha256').update(readFileSync(path.join(REPO, `apps/${a}/web/flutter_bootstrap.js`))).digest('hex')));
  must(hashes.size === 1, `the templates differ (${hashes.size} distinct)`);
  return `sha256 ${[...hashes][0].slice(0, 16)}`;
});

check('SOURCE-SHAPE', 'each Flutter template token appears exactly once', () => {
  // Flutter substitutes {{...}} INSIDE COMMENTS TOO, and the injected build
  // config is multi-line, so a token named in prose becomes live code.
  for (const a of APPS) {
    const src = read(`apps/${a}/web/flutter_bootstrap.js`);
    for (const t of TOKENS) {
      const n = src.split(t).length - 1;
      must(n === 1, `${a}: ${t} appears ${n} times, expected exactly 1`);
    }
  }
  return TOKENS.join(' ');
});

const config = JSON.parse(read('vercel.json'));

check('SOURCE-SHAPE', 'the catch-all rewrite excludes the whole engine namespace', () => {
  const last = config.rewrites?.at(-1);
  must(last && last.destination === '/index.html', 'the final rewrite must still be the SPA fallback');
  const re = new RegExp(`^${last.source}$`);
  for (const p of ['/canvaskit', '/canvaskit/', '/canvaskit/abc/x.wasm']) must(!re.test(p), `${p} must NOT fall into the Dashboard SPA`);
  for (const p of ['/', '/pos', '/pos/', '/kds/deep/link', '/kiosk', '/canvaskit-docs']) must(re.test(p), `${p} must still reach the SPA`);
  return last.source;
});

check('SOURCE-SHAPE', 'header rules are wildcard-free, unique, and name one revision', () => {
  const headers = config.headers ?? [];
  must(headers.length > 0, 'no headers block');
  const revs = new Set();
  const seen = new Set();
  for (const h of headers) {
    const m = /^\/canvaskit\/([0-9a-f]{7,64})\/(.+)$/.exec(h.source);
    must(m, `header source is not a versioned engine file path: ${h.source}`);
    revs.add(m[1]);
    // A wildcard would also match a nonexistent filename under a valid revision
    // and stamp a 404 immutable. Each source must name one concrete file.
    must(!/[*:]/.test(h.source), `${h.source}: wildcards are not allowed`);
    must(!seen.has(h.source), `duplicate header rule: ${h.source}`);
    seen.add(h.source);
    const cc = h.headers?.find((x) => x.key.toLowerCase() === 'cache-control');
    must(cc && /immutable/.test(cc.value), `${h.source}: expected an immutable Cache-Control`);
  }
  must(revs.size === 1, `header sources name ${revs.size} revisions: ${[...revs].join(', ')}`);
  // NOTE: internal agreement only. Agreement with the ACTUAL engine revision is
  // an SDK-COUPLING property and is checked separately below.
  return `${headers.length} unique exact-file rules, internally consistent`;
});

check('SOURCE-SHAPE', 'vercel.json stays inside the deployment engine key allowlist', () => {
  const allow = ['$schema', 'framework', 'installCommand', 'buildCommand', 'outputDirectory', 'ignoreCommand', 'rewrites', 'redirects', 'headers', 'cleanUrls', 'trailingSlash'];
  const bad = Object.keys(config).filter((k) => !allow.includes(k));
  must(bad.length === 0, `disallowed keys: ${bad.join(', ')} (a routes array would fail unsupported_build_contract)`);
  return Object.keys(config).join(', ');
});

check('SOURCE-SHAPE', 'the integrity pins match the current source bytes', () => {
  const engine = read(ENGINE);
  for (const [name, file] of [['BUILD_SCRIPT_HASH', BUILD_SCRIPT], ['CANVASKIT_ASSEMBLER_HASH', ASSEMBLER]]) {
    const m = new RegExp(`const ${name} = '([a-f0-9]{64})';`).exec(engine);
    must(m, `${name} not found in ${ENGINE}`);
    const actual = lfHash(read(file));
    must(m[1] === actual, `${name} is ${m[1].slice(0, 12)} but ${file} hashes to ${actual.slice(0, 12)} - re-pin it in the same commit`);
  }
  return 'both pins current';
});

check('SOURCE-SHAPE', 'the build script still invokes the pinned assembler', () => {
  must(read(BUILD_SCRIPT).includes(`node ${ASSEMBLER} apps/dashboard/build/web`), 'the build tail no longer calls the assembler');
  return `${BUILD_SCRIPT} -> ${ASSEMBLER}`;
});

// =========================================================== BEHAVIOUR ====== //

/**
 * Run the AUTHORED template with harmless substitutions against a MOCKED loader,
 * and report the canvasKitBaseUrl it actually passes.
 *
 * This is deliberately narrow. It does NOT execute the real generated or
 * minified Flutter loader, and it does NOT eval a generated build config to
 * discover a revision: the build config here is a synthetic object this function
 * constructs, which is the whole point - the template must read OUR value.
 */
export function evaluateTemplate(templateSrc, syntheticRevision) {
  const src = templateSrc
    .replace('{{flutter_js}}', '/* mocked loader supplied by the harness */')
    .replace('{{flutter_build_config}}', `window._flutter = window._flutter || {}; window._flutter.buildConfig = ${JSON.stringify({ engineRevision: syntheticRevision, builds: [] })};`)
    .replace('{{flutter_service_worker_version}}', '"synthetic-sw-version"');
  must(!/\{\{[a-z_]+\}\}/.test(src), 'an unsubstituted template token remained');

  const sandbox = {};
  sandbox.window = sandbox;          // browser-ish: window === the global object
  sandbox.globalThis = sandbox;
  const captured = [];
  sandbox.__capture = (o) => { captured.push(o); };
  vm.createContext(sandbox);
  // Seed the mock BEFORE the template runs. The template's own build-config line
  // uses `window._flutter || {}`, so it preserves this loader.
  vm.runInContext('var _flutter = { loader: { load: function (o) { __capture(o); } } }; window._flutter = _flutter;', ctxOf(sandbox));
  let threw = null;
  try { vm.runInContext(src, ctxOf(sandbox), { timeout: 2000 }); }
  catch (e) { threw = String(e.message ?? e); }
  return { calls: captured, threw, url: captured[0]?.config?.canvasKitBaseUrl ?? null, serviceWorkerSettings: captured[0]?.serviceWorkerSettings ?? null };
}
// vm.createContext returns the contextified object itself; keep one accessor so
// the two runInContext calls provably share a single context.
function ctxOf(sandbox) { return sandbox; }

const TEMPLATE = read('apps/dashboard/web/flutter_bootstrap.js');
const SYNTH_A = 'a'.repeat(40);
const SYNTH_B = '0123456789abcdef0123456789abcdef01234567';

check('BEHAVIOUR', 'the template derives the URL from the build config it is GIVEN', () => {
  const a = evaluateTemplate(TEMPLATE, SYNTH_A);
  const b = evaluateTemplate(TEMPLATE, SYNTH_B);
  must(!a.threw && !b.threw, `the template threw on a valid revision: ${a.threw ?? b.threw}`);
  must(a.calls.length === 1 && b.calls.length === 1, 'the loader must be called exactly once');
  must(a.url === `/canvaskit/${SYNTH_A}/`, `expected /canvaskit/${SYNTH_A}/, got ${a.url}`);
  must(b.url === `/canvaskit/${SYNTH_B}/`, `expected /canvaskit/${SYNTH_B}/, got ${b.url}`);
  // Two DIFFERENT inputs must give two DIFFERENT outputs. A constant-valued
  // revision passes a shape regex but fails here.
  must(a.url !== b.url, 'the URL did not change with the revision - it is not derived');
  must(a.serviceWorkerSettings && 'serviceWorkerVersion' in a.serviceWorkerSettings, 'serviceWorkerSettings must be preserved');
  return `${SYNTH_A.slice(0, 8)}… -> ${a.url}   |   ${SYNTH_B.slice(0, 8)}… -> ${b.url}`;
});

check('BEHAVIOUR', 'the template REFUSES a missing or malformed revision', () => {
  for (const bad of [undefined, null, '', '3.44.2', '../../etc', 'a/b', 'zz', 12345]) {
    const r = evaluateTemplate(TEMPLATE, bad);
    must(r.threw, `a revision of ${JSON.stringify(bad)} was accepted instead of throwing`);
    must(r.calls.length === 0, `the loader was still called with ${JSON.stringify(bad)}`);
  }
  return 'throws rather than falling back to an unversioned path or the CDN';
});

check('BEHAVIOUR', 'all four templates behave identically', () => {
  const urls = APPS.map((a) => evaluateTemplate(read(`apps/${a}/web/flutter_bootstrap.js`), SYNTH_A).url);
  must(new Set(urls).size === 1 && urls[0] === `/canvaskit/${SYNTH_A}/`, `roles disagree: ${JSON.stringify(urls)}`);
  return urls[0];
});

// ======================================================== SDK-COUPLING ====== //

/** Locate the pinned SDK: explicit flag, then env, then the repo-local clone. */
function resolveSdk() {
  const candidates = [arg('sdk', null), process.env.FLUTTER_ROOT, path.join(REPO, 'flutter')].filter(Boolean);
  for (const c of candidates) {
    const versionFile = path.join(c, 'bin/cache/flutter.version.json');
    const dist = path.join(c, 'bin/cache/flutter_web_sdk/canvaskit');
    if (existsSync(versionFile) && existsSync(dist)) return { root: c, versionFile, dist };
  }
  return { root: null, tried: candidates };
}

const sdk = resolveSdk();
let sdkRevision = null;
let sdkFiles = null;

if (sdk.root) {
  check('SDK-COUPLING', 'the pinned SDK supplies an independent engine revision', () => {
    const v = JSON.parse(readFileSync(sdk.versionFile, 'utf8'));
    must(typeof v.engineRevision === 'string' && REVISION_RE.test(v.engineRevision), `flutter.version.json engineRevision is ${JSON.stringify(v.engineRevision)}`);
    sdkRevision = v.engineRevision;
    // Cross-check against the SDK's second, independent record of the same fact.
    const pinFile = path.join(sdk.root, 'bin/internal/engine.version');
    if (existsSync(pinFile)) {
      const pinned = readFileSync(pinFile, 'utf8').trim();
      must(pinned === sdkRevision, `bin/internal/engine.version (${pinned.slice(0, 12)}) disagrees with flutter.version.json (${sdkRevision.slice(0, 12)})`);
    }
    return `${sdkRevision} (framework ${v.frameworkVersion}) from ${path.relative(REPO, sdk.versionFile).split(path.sep).join('/') || sdk.versionFile}`;
  });

  check('SDK-COUPLING', 'the header revision equals the SDK engine revision', () => {
    must(sdkRevision, 'no SDK revision was established');
    const bad = (config.headers ?? []).filter((h) => !h.source.startsWith(`/canvaskit/${sdkRevision}/`));
    must(bad.length === 0, `${bad.length} header rule(s) do not use the SDK revision ${sdkRevision.slice(0, 12)} — e.g. ${bad[0]?.source}`);
    return `all ${config.headers.length} rules use ${sdkRevision.slice(0, 16)}…`;
  });

  check('SDK-COUPLING', 'the header set equals the SDK CanvasKit distribution exactly', () => {
    must(sdkRevision, 'no SDK revision was established');
    sdkFiles = listFiles(sdk.dist);
    must(sdkFiles.length > 0, 'the SDK CanvasKit distribution is empty');
    const declared = (config.headers ?? []).map((h) => h.source.replace(`/canvaskit/${sdkRevision}/`, '')).sort();
    const missing = sdkFiles.filter((f) => !declared.includes(f));
    const extra = declared.filter((f) => !sdkFiles.includes(f));
    must(missing.length === 0, `SDK ships ${missing.length} file(s) with no header rule: ${missing.slice(0, 4).join(', ')}`);
    must(extra.length === 0, `header rules name ${extra.length} file(s) the SDK does not ship: ${extra.slice(0, 4).join(', ')}`);
    return `${sdkFiles.length} files, one-to-one`;
  });
} else if (MODE === 'required') {
  results.push({ cls: 'SDK-COUPLING', name: 'an authoritative pinned-SDK reference is available', ok: false, detail: `not found; tried: ${sdk.tried.join(', ')}` });
  console.error(`FAIL  [SDK-COUPLING] an authoritative pinned-SDK reference is available — not found; tried: ${sdk.tried.join(', ')}`);
} else {
  console.log('SKIP  [SDK-COUPLING] no pinned SDK supplied — diagnostic mode does not establish coupling');
}

// ===================================================== OUTPUT-COUPLING ====== //

const outArg = arg('output', path.join(REPO, 'apps/dashboard/build/web'));
const OUT = path.join(outArg, 'canvaskit');
if (existsSync(OUT)) {
  check('OUTPUT-COUPLING', 'the published distribution matches the headers and the SDK', () => {
    const revs = readdirSync(OUT);
    must(revs.length === 1, `expected one revision directory, found: ${revs.join(', ') || 'none'}`);
    const rev = revs[0];
    if (sdkRevision) must(rev === sdkRevision, `published revision ${rev.slice(0, 12)} != SDK ${sdkRevision.slice(0, 12)}`);
    const shipped = listFiles(path.join(OUT, rev));
    const declared = (config.headers ?? []).map((h) => h.source.replace(`/canvaskit/${rev}/`, '')).sort();
    const missing = shipped.filter((f) => !declared.includes(f));
    const extra = declared.filter((f) => !shipped.includes(f));
    must(missing.length === 0, `published but unheadered: ${missing.join(', ')}`);
    must(extra.length === 0, `headered but not published: ${extra.join(', ')}`);
    if (sdkFiles) must(JSON.stringify(shipped) === JSON.stringify(sdkFiles), 'the published distribution differs from the SDK distribution');
    return `${shipped.length} published files at revision ${rev}`;
  });
} else {
  console.log(`SKIP  [OUTPUT-COUPLING] no build output at ${outArg} — this run establishes nothing about generated output`);
}

// ============================================================= summary ====== //

const byClass = {};
for (const r of results) { (byClass[r.cls] ??= { pass: 0, fail: 0 }); byClass[r.cls][r.ok ? 'pass' : 'fail']++; }
const failed = results.filter((r) => !r.ok);
const sdkDone = results.some((r) => r.cls === 'SDK-COUPLING' && r.ok);
const outputDone = results.some((r) => r.cls === 'OUTPUT-COUPLING' && r.ok);

console.log('\n--- what this run established ---');
for (const [cls, c] of Object.entries(byClass)) console.log(`  ${cls.padEnd(16)} ${c.pass} passed, ${c.fail} failed`);
if (!sdkDone) console.log('  SDK-COUPLING     NOT ESTABLISHED');
if (!outputDone) console.log('  OUTPUT-COUPLING  NOT ESTABLISHED (no generated output was inspected)');

if (failed.length) {
  console.error(`\nFAILED — ${failed.length} check(s): ${failed.map((f) => f.name).join('; ')}`);
  process.exit(1);
}
if (MODE === 'required' && !sdkDone) {
  console.error('\nINCOMPLETE — required mode did not establish SDK coupling. This is NOT a pass.');
  process.exit(1);
}
if (MODE === 'diagnostic') {
  console.log('\nINCOMPLETE (diagnostic mode) — source-shape and behaviour only.');
  console.log(`  NOT established here: SDK coupling${outputDone ? '' : ', output coupling'}. Do not read this as release verification.`);
  process.exit(0);
}
console.log(`\nPASSED — source shape, template behaviour and SDK coupling verified${outputDone ? ', plus generated output' : ' (no generated output was present to inspect)'}.`);
