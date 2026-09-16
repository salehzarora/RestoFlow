// Controls for the CanvasKit release coupling check.
//
//   node --test tools/canvaskit_release_check.test.mjs
//
// Every case builds a DISPOSABLE copy of the relevant source files plus a small
// SYNTHETIC pinned-SDK reference, mutates only that copy, and runs the checker
// as a CLI against it. Nothing in the repository is modified.
//
// These exist because a prior revision of the checker had four demonstrated
// false-pass cases, found in independent review:
//   * every header revision could be replaced wholesale and it still passed;
//   * a published file's header rule could be deleted and 17 rules accepted;
//   * a constant-valued bootstrap revision satisfied the URL-shape regex;
//   * a source-only run printed "All CanvasKit release coupling checks passed"
//     while the only output-backed comparison was skipped.
// Each is a named negative control below.
//
// Set CK_CHECKER to run this suite against a different checker implementation —
// used to record RED against the reviewed version and GREEN against this one.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, readFileSync, cpSync, readdirSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..');
const CHECKER = process.env.CK_CHECKER || path.join(HERE, 'canvaskit_release_check.mjs');

const SOURCE_FILES = [
  'vercel.json',
  'tools/vercel/ignore-build.mjs',
  'tools/vercel_build_web.sh',
  'tools/assemble_web_canvaskit.mjs',
  ...['dashboard', 'pos', 'kds', 'kiosk'].map((a) => `apps/${a}/web/flutter_bootstrap.js`),
];

/** The revision the candidate's header rules actually use. */
function candidateRevision(root = REPO) {
  const cfg = JSON.parse(readFileSync(path.join(root, 'vercel.json'), 'utf8'));
  return /^\/canvaskit\/([0-9a-f]{7,64})\//.exec(cfg.headers[0].source)[1];
}

/**
 * A disposable tree: the real source files, the checker under test, and a
 * SYNTHETIC pinned SDK whose distribution carries the same file NAMES as the
 * real one. Names are all the coupling check reads, so the fixture stays small
 * and hermetic; the real SDK is used by the real run, not by these tests.
 */
function fixture({ withSdk = true, distFiles = null, revision = null } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), 'ck-check-'));
  for (const rel of SOURCE_FILES) {
    mkdirSync(path.join(root, path.dirname(rel)), { recursive: true });
    cpSync(path.join(REPO, rel), path.join(root, rel));
  }
  mkdirSync(path.join(root, 'tools'), { recursive: true });
  cpSync(CHECKER, path.join(root, 'tools/canvaskit_release_check.mjs'));

  const rev = revision ?? candidateRevision();
  const files = distFiles ?? JSON.parse(readFileSync(path.join(REPO, 'vercel.json'), 'utf8'))
    .headers.map((h) => h.source.replace(`/canvaskit/${rev}/`, ''));
  let sdk = null;
  if (withSdk) {
    sdk = path.join(root, 'sdk');
    mkdirSync(path.join(sdk, 'bin/cache'), { recursive: true });
    writeFileSync(path.join(sdk, 'bin/cache/flutter.version.json'), JSON.stringify({ engineRevision: rev, frameworkVersion: '3.44.2' }) + '\n');
    mkdirSync(path.join(sdk, 'bin/internal'), { recursive: true });
    writeFileSync(path.join(sdk, 'bin/internal/engine.version'), rev + '\n');
    for (const f of files) {
      const p = path.join(sdk, 'bin/cache/flutter_web_sdk/canvaskit', ...f.split('/'));
      mkdirSync(path.dirname(p), { recursive: true });
      writeFileSync(p, `synthetic ${f}\n`);
    }
  }
  return { root, sdk, rev };
}

function run(fx, extra = []) {
  const args = [path.join(fx.root, 'tools/canvaskit_release_check.mjs'), ...extra];
  if (fx.sdk && !extra.includes('--sdk')) args.push('--sdk', fx.sdk);
  // Point --output at a path that does not exist so OUTPUT-COUPLING is out of
  // scope here; these controls are about SDK coupling and behaviour.
  if (!extra.includes('--output')) args.push('--output', path.join(fx.root, 'no-such-output'));
  const r = spawnSync(process.execPath, args, { encoding: 'utf8', timeout: 60_000 });
  return { status: r.status, out: `${r.stdout}${r.stderr}` };
}

const editConfig = (fx, fn) => {
  const p = path.join(fx.root, 'vercel.json');
  const cfg = JSON.parse(readFileSync(p, 'utf8'));
  fn(cfg);
  writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
};
const editTemplates = (fx, fn) => {
  for (const a of ['dashboard', 'pos', 'kds', 'kiosk']) {
    const p = path.join(fx.root, `apps/${a}/web/flutter_bootstrap.js`);
    writeFileSync(p, fn(readFileSync(p, 'utf8')));
  }
};
const cleanup = (fx) => rmSync(fx.root, { recursive: true, force: true });

// ------------------------------------------------------- POSITIVE CONTROL -- //

test('POSITIVE: the unchanged contract passes required mode with an SDK reference', () => {
  const fx = fixture();
  try {
    const r = run(fx);
    assert.equal(r.status, 0, r.out);
    assert.match(r.out, /PASSED/, r.out);
    assert.match(r.out, /\[SDK-COUPLING\].*header revision equals the SDK engine revision/);
    assert.match(r.out, /\[SDK-COUPLING\].*header set equals the SDK CanvasKit distribution exactly/);
    assert.match(r.out, /\[BEHAVIOUR\].*derives the URL from the build config/);
  } finally { cleanup(fx); }
});

// ------------------------------------------------- NEGATIVE: SDK COUPLING -- //

test('NEGATIVE: an unrelated header revision FAILS (reviewed checker passed this)', () => {
  const fx = fixture();
  try {
    const wrong = 'd'.repeat(40);
    editConfig(fx, (cfg) => { for (const h of cfg.headers) h.source = h.source.replace(fx.rev, wrong); });
    const r = run(fx);
    assert.notEqual(r.status, 0, `mutating all 18 header revisions must FAIL\n${r.out}`);
    assert.match(r.out, /header revision equals the SDK engine revision/);
  } finally { cleanup(fx); }
});

test('NEGATIVE: a MISSING header rule for a published file FAILS (reviewed checker accepted 17)', () => {
  const fx = fixture();
  try {
    editConfig(fx, (cfg) => { cfg.headers = cfg.headers.filter((h) => !h.source.endsWith('chromium/canvaskit.wasm')); });
    const r = run(fx);
    assert.notEqual(r.status, 0, `dropping a header rule must FAIL\n${r.out}`);
    assert.match(r.out, /no header rule|header set equals the SDK/);
  } finally { cleanup(fx); }
});

test('NEGATIVE: an EXTRA header rule for a file the SDK does not ship FAILS', () => {
  const fx = fixture();
  try {
    editConfig(fx, (cfg) => cfg.headers.push({ source: `/canvaskit/${fx.rev}/not_in_the_sdk.wasm`, headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }] }));
    const r = run(fx);
    assert.notEqual(r.status, 0, `an unshipped header rule must FAIL\n${r.out}`);
    assert.match(r.out, /does not ship|header set equals the SDK/);
  } finally { cleanup(fx); }
});

test('NEGATIVE: a DUPLICATE header rule FAILS', () => {
  const fx = fixture();
  try {
    editConfig(fx, (cfg) => cfg.headers.push({ ...cfg.headers[0] }));
    const r = run(fx);
    assert.notEqual(r.status, 0, `a duplicate rule must FAIL\n${r.out}`);
    assert.match(r.out, /duplicate header rule/);
  } finally { cleanup(fx); }
});

test('NEGATIVE: a WILDCARD header source FAILS', () => {
  const fx = fixture();
  try {
    editConfig(fx, (cfg) => { cfg.headers = [{ source: `/canvaskit/${fx.rev}/:path*`, headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }] }]; });
    const r = run(fx);
    assert.notEqual(r.status, 0, `a wildcard source must FAIL\n${r.out}`);
    assert.match(r.out, /wildcards are not allowed/);
  } finally { cleanup(fx); }
});

// ---------------------------------------------------- NEGATIVE: BEHAVIOUR -- //

test('NEGATIVE: a CONSTANT-valued bootstrap revision FAILS (reviewed checker passed this)', () => {
  const fx = fixture();
  try {
    editTemplates(fx, (src) => src.replace('var rev = cfg && cfg.engineRevision;', `var rev = '${'d'.repeat(40)}';`));
    const r = run(fx);
    assert.notEqual(r.status, 0, `a hardcoded revision must FAIL\n${r.out}`);
    assert.match(r.out, /did not change with the revision|derives the URL from the build config/);
  } finally { cleanup(fx); }
});

test('NEGATIVE: a template that ignores the config and pins an unversioned path FAILS', () => {
  const fx = fixture();
  try {
    editTemplates(fx, (src) => src.replace(/canvasKitBaseUrl: '\/canvaskit\/' \+ rev \+ '\/'/, "canvasKitBaseUrl: '/canvaskit/'"));
    const r = run(fx);
    assert.notEqual(r.status, 0, `an unversioned path must FAIL\n${r.out}`);
  } finally { cleanup(fx); }
});

test('NEGATIVE: engineRevision mentioned ONLY in a comment FAILS', () => {
  // The reviewed checker accepted any occurrence of the identifier, including
  // prose. Behaviour, not text, must decide.
  const fx = fixture();
  try {
    editTemplates(fx, (src) => src.replace('var rev = cfg && cfg.engineRevision;', `var rev = '${'e'.repeat(40)}'; // engineRevision is read here`));
    const r = run(fx);
    assert.notEqual(r.status, 0, `a comment mention must not satisfy the check\n${r.out}`);
  } finally { cleanup(fx); }
});

test('NEGATIVE: a template that never calls the loader FAILS', () => {
  const fx = fixture();
  try {
    editTemplates(fx, (src) => src.replace('_flutter.loader.load({', 'void ({'));
    const r = run(fx);
    assert.notEqual(r.status, 0, `no loader call must FAIL\n${r.out}`);
  } finally { cleanup(fx); }
});

// ------------------------------------- NEGATIVE: incomplete authoritative --- //

test('NEGATIVE: required mode WITHOUT an SDK reference fails as INCOMPLETE', () => {
  // The central correction: a run that could not do the coupling work must never
  // report a clean pass. The reviewed checker printed "All ... checks passed".
  const fx = fixture({ withSdk: false });
  try {
    const r = run(fx);
    assert.notEqual(r.status, 0, `required mode without an SDK must FAIL\n${r.out}`);
    assert.match(r.out, /INCOMPLETE|authoritative pinned-SDK reference/);
    assert.doesNotMatch(r.out, /^PASSED/m, `must not claim a pass:\n${r.out}`);
  } finally { cleanup(fx); }
});

test('diagnostic mode is allowed to exit 0 but must label itself INCOMPLETE', () => {
  const fx = fixture({ withSdk: false });
  try {
    const r = run(fx, ['--mode', 'diagnostic']);
    assert.equal(r.status, 0, r.out);
    assert.match(r.out, /INCOMPLETE \(diagnostic mode\)/, r.out);
    assert.match(r.out, /NOT established here/, r.out);
    assert.doesNotMatch(r.out, /^PASSED/m, `diagnostic mode must not read as verification:\n${r.out}`);
  } finally { cleanup(fx); }
});

test('an SDK whose two revision records disagree FAILS', () => {
  const fx = fixture();
  try {
    writeFileSync(path.join(fx.sdk, 'bin/internal/engine.version'), 'f'.repeat(40) + '\n');
    const r = run(fx);
    assert.notEqual(r.status, 0, `an internally inconsistent SDK must FAIL\n${r.out}`);
    assert.match(r.out, /disagrees with flutter\.version\.json/);
  } finally { cleanup(fx); }
});

// --------------------------------------------------- OUTPUT-COUPLING ------- //

test('OUTPUT-COUPLING: a published tree matching the SDK and headers passes', () => {
  const fx = fixture();
  try {
    const out = path.join(fx.root, 'build');
    for (const f of readdirSync(path.join(fx.sdk, 'bin/cache/flutter_web_sdk/canvaskit'), { recursive: true, withFileTypes: true })) {
      if (!f.isFile()) continue;
      const rel = path.relative(path.join(fx.sdk, 'bin/cache/flutter_web_sdk/canvaskit'), path.join(f.parentPath ?? f.path, f.name)).split(path.sep).join('/');
      const p = path.join(out, 'canvaskit', fx.rev, ...rel.split('/'));
      mkdirSync(path.dirname(p), { recursive: true });
      writeFileSync(p, `synthetic ${rel}\n`);
    }
    const r = run(fx, ['--output', out]);
    assert.equal(r.status, 0, r.out);
    assert.match(r.out, /\[OUTPUT-COUPLING\].*published distribution matches/);
  } finally { cleanup(fx); }
});

test('OUTPUT-COUPLING: a published revision directory that is not the SDK revision FAILS', () => {
  const fx = fixture();
  try {
    const out = path.join(fx.root, 'build');
    const p = path.join(out, 'canvaskit', 'b'.repeat(40), 'canvaskit.js');
    mkdirSync(path.dirname(p), { recursive: true });
    writeFileSync(p, 'synthetic\n');
    const r = run(fx, ['--output', out]);
    assert.notEqual(r.status, 0, `a mismatched published revision must FAIL\n${r.out}`);
  } finally { cleanup(fx); }
});
