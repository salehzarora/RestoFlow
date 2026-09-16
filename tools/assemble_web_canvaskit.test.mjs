// Focused controls for the CanvasKit assembly decision.
//
//   node --test tools/assemble_web_canvaskit.test.mjs
//
// These prove the decision FAILS CLOSED and that the accept path is not vacuous.
// Compact and finite; they do not model hostile code. Node standard library only.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync, readdirSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  REVISION_RE, CANVASKIT_DIRS, CANONICAL_DIR, ROLE_DIRS,
  extractBuildConfig, readRevisionFromSource, assertBootstrapTargetsVersioned,
  agreeOnRevision, planAssembly, dirDigest, walkFiles, assertNoEscape, assembleCanvasKit,
} from './assemble_web_canvaskit.mjs';

const REV = '77e2e94772b6eb43759e34ed1ad7da4674e19cab';
const OTHER = '0123456789abcdef0123456789abcdef01234567';

const cfg = (o) => JSON.stringify(o);
const DERIVED = `(function(){var rev=window._flutter.buildConfig.engineRevision;_flutter.loader.load({config:{canvasKitBaseUrl:'/canvaskit/'+rev+'/'},serviceWorkerSettings:{serviceWorkerVersion:"1"}});})();`;
const UNVERSIONED = `_flutter.loader.load({config:{canvasKitBaseUrl:"/canvaskit/"},serviceWorkerSettings:{serviceWorkerVersion:"1"}});`;
const SDK_DEFAULT = `_flutter.loader.load({serviceWorkerSettings:{serviceWorkerVersion:"1"}});`;
const LOADER_NOISE = 'function E(i,e){return i.canvasKitBaseUrl?i.canvasKitBaseUrl:e.engineRevision}\n';
const bootstrap = (config, call) => `${LOADER_NOISE}if(!window._flutter){window._flutter={};}\n_flutter.buildConfig = ${config};\n${call}`;
const OK_CFG = cfg({ engineRevision: REV, builds: [{ compileTarget: 'dart2js', renderer: 'canvaskit' }] });

const FILES = [
  { path: 'canvaskit.js', bytes: 10, sha256: 'a'.repeat(64) },
  { path: 'canvaskit.wasm', bytes: 20, sha256: 'b'.repeat(64) },
  { path: 'chromium/canvaskit.wasm', bytes: 30, sha256: 'c'.repeat(64) },
];
const digests = () => Object.fromEntries(CANVASKIT_DIRS.map((d) => [d, {
  subdir: d, present: true, fileCount: FILES.length,
  totalBytes: FILES.reduce((n, f) => n + f.bytes, 0), digest: 'd'.repeat(64),
  files: FILES.map((f) => ({ ...f })),
}]));
const allAgree = (rev = REV) => ({ dashboard: rev, pos: rev, kds: rev, kiosk: rev });

// ------------------------------------------------------ revision reading --- //

test('the revision comes from the GENERATED build config, parsed not executed', () => {
  const r = readRevisionFromSource(bootstrap(OK_CFG, DERIVED));
  assert.equal(r.revision, REV);
  assert.equal(r.buildConfig.builds[0].renderer, 'canvaskit');
  // A bootstrap that would need evaluating is refused, never run.
  assert.ok(extractBuildConfig('_flutter.buildConfig = computeConfig();').error);
});

test('ABORT: missing, malformed or non-string revisions are refused', () => {
  for (const [c, re] of [
    [cfg({ builds: [] }), /absent/],
    [cfg({ engineRevision: null }), /absent/],
    [cfg({ engineRevision: 7 }), /not a string/],
    [cfg({ engineRevision: '' }), /malformed/],
    [cfg({ engineRevision: '../../etc' }), /malformed/],
    [cfg({ engineRevision: 'a/b' }), /malformed/],
    [cfg({ engineRevision: '3.44.2' }), /malformed/],   // a marketing version is NOT a cache key
    [cfg({ engineRevision: 'zzzz' }), /malformed/],
  ]) {
    const r = readRevisionFromSource(bootstrap(c, DERIVED));
    assert.ok(r.error, `${c} must be refused`);
    assert.match(r.error, re);
    assert.equal(r.revision, undefined);
  }
  assert.ok(readRevisionFromSource('no build config').error);
  assert.ok(readRevisionFromSource('_flutter.buildConfig = {nope};').error);
  assert.ok(readRevisionFromSource('').error);
});

test('the revision pattern rejects anything path-like', () => {
  assert.ok(REVISION_RE.test(REV));
  for (const bad of ['', '/', '..', 'a/b', 'has space', 'g'.repeat(40), '1'.repeat(65), '123456']) {
    assert.ok(!REVISION_RE.test(bad), `${bad} must be rejected`);
  }
});

// ------------------------------------------------- bootstrap target check --- //

test('the bootstrap must DERIVE the path; an unversioned or hardcoded one is refused', () => {
  assert.deepEqual(assertBootstrapTargetsVersioned(bootstrap(OK_CFG, DERIVED)), { ok: true });
  assert.match(assertBootstrapTargetsVersioned(bootstrap(OK_CFG, UNVERSIONED)).error, /UNVERSIONED/);
  assert.ok(assertBootstrapTargetsVersioned(bootstrap(OK_CFG, SDK_DEFAULT)).error);
  assert.ok(assertBootstrapTargetsVersioned(bootstrap(OK_CFG,
    `_flutter.loader.load({config:{canvasKitBaseUrl:"/canvaskit/${REV}/"}});`)).error, 'hardcoded is not derived');
  assert.ok(assertBootstrapTargetsVersioned('no loader call').error);
});

test('NOT VACUOUS: the inlined loader source alone never satisfies the check', () => {
  // The minified loader mentions canvasKitBaseUrl in the ternary that READS it.
  assert.ok(assertBootstrapTargetsVersioned(LOADER_NOISE + bootstrap(OK_CFG, SDK_DEFAULT)).error);
});

test('ABORT: an unsubstituted Flutter template token is rejected', () => {
  const broken = bootstrap(OK_CFG, DERIVED) + '\n// {{flutter_service_worker_version}}';
  assert.match(assertBootstrapTargetsVersioned(broken).error, /unsubstituted/);
});

// ------------------------------------------------------------ agreement --- //

test('ABORT: the apps must agree on exactly one revision', () => {
  assert.equal(agreeOnRevision(allAgree()).revision, REV);
  assert.match(agreeOnRevision({ ...allAgree(), kiosk: OTHER }).error, /disagree/);
  assert.ok(agreeOnRevision({ ...allAgree(), pos: undefined }).error);
  assert.ok(agreeOnRevision({}).error);
});

// ----------------------------------------------------------- the plan ----- //

test('ACCEPT: matching revisions and distributions yield the versioned plan', () => {
  const plan = planAssembly({ revisions: allAgree(), digests: digests() });
  assert.equal(plan.ok, true, plan.problems.join('; '));
  assert.equal(plan.revision, REV);
  assert.equal(plan.versionedPath, `canvaskit/${REV}`);
  assert.deepEqual(plan.removable.sort(), [...CANVASKIT_DIRS].sort());
  assert.equal(plan.savedBytes, 60 * 3);
  assert.ok(!plan.versionedPath.includes('..'));
});

test('ABORT: any revision problem stops the plan before anything is removable', () => {
  for (const revisions of [{ ...allAgree(), kds: OTHER }, { ...allAgree(), pos: 'nope' }, {}]) {
    const plan = planAssembly({ revisions, digests: digests() });
    assert.equal(plan.ok, false);
    assert.deepEqual(plan.removable, []);
    assert.equal(plan.savedBytes, 0);
    assert.equal(plan.versionedPath, null);
  }
});

test('ABORT: the same revision with changed JS or WASM bytes is refused', () => {
  for (const changed of ['canvaskit.js', 'canvaskit.wasm', 'chromium/canvaskit.wasm']) {
    const d = digests();
    d['pos/canvaskit'].digest = 'e'.repeat(64);
    d['pos/canvaskit'].files.find((f) => f.path === changed).sha256 = 'f'.repeat(64);
    const plan = planAssembly({ revisions: allAgree(), digests: d });
    assert.equal(plan.ok, false, `${changed} must abort`);
    assert.deepEqual(plan.removable, []);
    assert.ok(plan.problems.some((p) => p.includes(changed)), plan.problems.join('; '));
  }
  // A length-only difference must also be caught.
  const d2 = digests();
  d2['kds/canvaskit'].digest = 'e'.repeat(64);
  d2['kds/canvaskit'].files[0].bytes = 11;
  assert.ok(planAssembly({ revisions: allAgree(), digests: d2 }).problems.some((p) => p.includes('length differs')));
});

test('ABORT: a wrong, missing or extra distribution file is refused and named', () => {
  const missing = digests();
  missing['kds/canvaskit'].files.splice(1, 1);
  missing['kds/canvaskit'].digest = 'e'.repeat(64);
  assert.ok(planAssembly({ revisions: allAgree(), digests: missing }).problems.some((p) => p.includes('missing file canvaskit.wasm')));

  const extra = digests();
  extra['kiosk/canvaskit'].files.push({ path: 'rogue.wasm', bytes: 1, sha256: '9'.repeat(64) });
  extra['kiosk/canvaskit'].digest = 'e'.repeat(64);
  assert.ok(planAssembly({ revisions: allAgree(), digests: extra }).problems.some((p) => p.includes('extra file rogue.wasm')));

  for (const dir of CANVASKIT_DIRS) {
    const gone = digests();
    gone[dir] = { subdir: dir, present: false };
    assert.equal(planAssembly({ revisions: allAgree(), digests: gone }).ok, false, `${dir} absent must abort`);
  }
  const empty = digests();
  empty['pos/canvaskit'].files = [];
  assert.ok(planAssembly({ revisions: allAgree(), digests: empty }).problems.some((p) => p.includes('inventoried as empty')));
});

test('ABORT: an occupied revision key is never overwritten, and different bytes are named', () => {
  const d = digests();
  const diff = planAssembly({ revisions: allAgree(), digests: d, existingVersioned: { present: true, digest: 'e'.repeat(64), totalBytes: 60, fileCount: 3, files: FILES } });
  assert.equal(diff.ok, false);
  assert.match(diff.problems.join('; '), /DIFFERENT bytes/);
  const same = planAssembly({ revisions: allAgree(), digests: d, existingVersioned: { present: true, digest: 'd'.repeat(64), totalBytes: 60, fileCount: 3, files: FILES } });
  assert.equal(same.ok, false);
  assert.match(same.problems.join('; '), /already exists/);
});

test('distribution DRIFT is detected, not assumed: the file count is never hard-coded', () => {
  const four = [...FILES, { path: 'newvariant/canvaskit.wasm', bytes: 40, sha256: '7'.repeat(64) }];
  const d = Object.fromEntries(CANVASKIT_DIRS.map((x) => [x, {
    subdir: x, present: true, fileCount: 4, totalBytes: 100, digest: 'z'.repeat(64), files: four.map((f) => ({ ...f })),
  }]));
  const plan = planAssembly({ revisions: allAgree(), digests: d });
  assert.equal(plan.ok, true, 'a future distribution with a new variant must still assemble');
  assert.equal(plan.savedBytes, 100 * 3);
});

// -------------------------------------------------------- filesystem ------ //

test('no output escape: traversal, non-directory and symlink targets are refused', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'ck-escape-'));
  try {
    mkdirSync(path.join(root, 'canvaskit'), { recursive: true });
    writeFileSync(path.join(root, 'canvaskit', 'f.txt'), 'x');
    assert.equal(assertNoEscape(root, 'canvaskit'), path.join(root, 'canvaskit'));
    assert.throws(() => assertNoEscape(root, '..'), /escape refused/);
    assert.throws(() => assertNoEscape(root, ''), /escape refused/);
    assert.throws(() => assertNoEscape(root, 'nope'), /does not exist/);
    assert.throws(() => assertNoEscape(root, 'canvaskit/f.txt'), /not a directory/);
    const outside = mkdtempSync(path.join(tmpdir(), 'ck-outside-'));
    let linked = false;
    try { symlinkSync(outside, path.join(root, 'link'), 'junction'); linked = true; } catch { /* needs privilege */ }
    if (linked) assert.throws(() => assertNoEscape(root, 'link'), /symlink|escape refused/);
    rmSync(outside, { recursive: true, force: true });
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('the walker refuses to describe a symlink as a file', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'ck-walk-'));
  try {
    writeFileSync(path.join(root, 'real.txt'), 'x');
    assert.deepEqual(walkFiles(root), ['real.txt']);
    let linked = false;
    try { symlinkSync(path.join(root, 'real.txt'), path.join(root, 'link.txt'), 'file'); linked = true; } catch { /* needs privilege */ }
    if (linked) assert.throws(() => walkFiles(root), /symlink/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('dirDigest is parent-independent and one-byte sensitive', () => {
  const root = mkdtempSync(path.join(tmpdir(), 'ck-dig-'));
  try {
    for (const sub of ['canvaskit', 'pos/canvaskit']) {
      mkdirSync(path.join(root, ...sub.split('/'), 'chromium'), { recursive: true });
      writeFileSync(path.join(root, ...sub.split('/'), 'canvaskit.wasm'), 'WASM');
      writeFileSync(path.join(root, ...sub.split('/'), 'chromium', 'canvaskit.wasm'), 'CHROM');
    }
    assert.equal(dirDigest(root, 'canvaskit').digest, dirDigest(root, 'pos/canvaskit').digest);
    writeFileSync(path.join(root, 'pos', 'canvaskit', 'chromium', 'canvaskit.wasm'), 'CHROMX');
    assert.notEqual(dirDigest(root, 'pos/canvaskit').digest, dirDigest(root, 'canvaskit').digest);
    assert.equal(dirDigest(root, 'nope').present, false);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

// ------------------------------------------------- end-to-end, small tree --- //

/** A miniature combined output: four bootstraps and four identical distributions. */
function fixture({ revs = allAgree(), bytes = {}, call = DERIVED } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), 'ck-e2e-'));
  const place = (dir, rel, content) => {
    const abs = path.join(root, ...dir.split('/').filter(Boolean), ...rel.split('/'));
    mkdirSync(path.dirname(abs), { recursive: true });
    writeFileSync(abs, content);
  };
  for (const [role, dir] of [['dashboard', ''], ['pos', 'pos'], ['kds', 'kds'], ['kiosk', 'kiosk']]) {
    place(dir, 'flutter_bootstrap.js', bootstrap(cfg({ engineRevision: revs[role], builds: [] }), call));
    place(dir, 'main.dart.js', `// ${role}`);
    const ck = dir ? `${dir}/canvaskit` : 'canvaskit';
    place(ck, 'canvaskit.js', bytes[role]?.js ?? 'ENGINE-JS');
    place(ck, 'canvaskit.wasm', bytes[role]?.wasm ?? 'ENGINE-WASM');
    place(ck, 'chromium/canvaskit.wasm', 'CHROMIUM-WASM');
  }
  return root;
}

test('END TO END: one distribution is published and no unversioned copy survives', () => {
  const root = fixture();
  try {
    const before = walkFiles(root).length;
    const r = assembleCanvasKit(root, { log: () => {} });
    assert.equal(r.revision, REV);
    assert.equal(r.versionedPath, `/canvaskit/${REV}/`);
    assert.equal(r.distributionFileCount, 3);
    for (const d of ROLE_DIRS) assert.ok(!existsSync(path.join(root, d, 'canvaskit')), `${d}/canvaskit must be gone`);
    assert.deepEqual(readdirSync(path.join(root, 'canvaskit')), [REV]);
    assert.ok(!existsSync(path.join(root, 'canvaskit', REV, 'canvaskit')), 'must not nest inside itself');
    assert.equal(r.fileCountAfter, before - 9);
    assert.ok(r.savedBytes > 0);
    // Every role's own files survive untouched.
    for (const d of ROLE_DIRS) assert.ok(existsSync(path.join(root, d, 'main.dart.js')));
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('END TO END: a mismatched distribution aborts and DELETES NOTHING', () => {
  const root = fixture({ bytes: { kiosk: { wasm: 'DIFFERENT-ENGINE-WASM' } } });
  try {
    const before = walkFiles(root);
    assert.throws(() => assembleCanvasKit(root, { log: () => {} }), /assembly refused/);
    assert.deepEqual(walkFiles(root), before, 'the tree must be untouched after a refusal');
    for (const d of CANVASKIT_DIRS) assert.ok(existsSync(path.join(root, ...d.split('/'))), `${d} must survive`);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('END TO END: disagreeing revisions abort and DELETE NOTHING', () => {
  const root = fixture({ revs: { ...allAgree(), kds: OTHER } });
  try {
    const before = walkFiles(root);
    assert.throws(() => assembleCanvasKit(root, { log: () => {} }), /disagree/);
    assert.deepEqual(walkFiles(root), before);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('END TO END: an unversioned bootstrap aborts before any removal', () => {
  const root = fixture({ call: UNVERSIONED });
  try {
    const before = walkFiles(root);
    assert.throws(() => assembleCanvasKit(root, { log: () => {} }), /UNVERSIONED/);
    assert.deepEqual(walkFiles(root), before);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('END TO END: re-running on an already-assembled tree refuses, it does not nest', () => {
  const root = fixture();
  try {
    assembleCanvasKit(root, { log: () => {} });
    const after = walkFiles(root);
    assert.throws(() => assembleCanvasKit(root, { log: () => {} }), /missing CanvasKit directory|already exists/);
    assert.deepEqual(walkFiles(root), after, 'a repeat run must leave the tree exactly as it was');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('END TO END: a missing output root fails without touching anything', () => {
  assert.throws(() => assembleCanvasKit(path.join(tmpdir(), 'ck-does-not-exist-' + REV), { log: () => {} }), /does not exist/);
});
