#!/usr/bin/env node
// ============================================================================
// BIZBOT — CanvasKit engine assembly for the combined web output.
//
// PRODUCTION BUILD INPUT. tools/vercel_build_web.sh delegates its assembly tail
// to this helper, and tools/vercel/ignore-build.mjs pins it by CRLF-normalised
// SHA-256 as CANVASKIT_ASSEMBLER_HASH and classifies it as a product build
// input. Changing, moving or deleting this file changes the product build, and
// the deployment filter is written so that it can never become a false IGNORE.
//
// WHY IT EXISTS
// Each of the four apps is built separately and each `flutter build web` emits
// its own complete copy of the CanvasKit engine. Assembling them under one
// output therefore ships four byte-identical 38,475,613-byte distributions. The
// authored web/flutter_bootstrap.js templates point every role at ONE shared,
// engine-revision-addressed directory instead:
//
//     /canvaskit/<engineRevision>/<relative distribution file>
//
// The revision comes from the SDK's own generated build config, so the path
// changes when the engine changes: a browser can never pair cached bytes from
// one engine with a main.dart.js from another.
//
// SAFETY CONTRACT, in order. Any failure aborts BEFORE anything is removed.
//   1. Read engineRevision from all four generated bootstraps, by regex plus
//      JSON.parse. NEVER eval - a generated bootstrap is a large minified file
//      and executing it to learn one field would be unnecessary and unsafe.
//   2. Require the four revisions to be present, well formed and identical, and
//      each bootstrap to derive its URL from the build config rather than
//      hardcoding a path.
//   3. Require the four distributions to be equal on relative path set, byte
//      length and SHA-256. Distribution DRIFT is detected, not assumed away:
//      the file count is read from the build, never hard-coded.
//   4. Stage one copy, verify it, then remove all four originals and place it at
//      the versioned path. Retain ZERO unversioned copies.
//   5. Re-verify: the placed copy matches the proven bytes, every other file is
//      untouched, canvaskit/ holds exactly the one revision directory, and no
//      symlink exists anywhere in the output.
//
// Real files only - no symlink, junction, hardlink, "latest" alias, redirect or
// external CDN. Writes only inside the given output directory.
//
// IMPORTING THIS MODULE HAS NO SIDE EFFECTS. The exported functions are pure
// decision logic; the filesystem work runs only via main(), which is invoked
// only when this file is executed directly. Node standard library only: no
// dependency, no package.json, no lockfile, no node_modules.
// ============================================================================
import { createHash } from 'node:crypto';
import {
  cpSync, rmSync, mkdirSync, existsSync, readFileSync, readdirSync, lstatSync, realpathSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

/** Where each app's build output is assembled into the combined output. */
export const ROLE_DIRS = ['pos', 'kds', 'kiosk'];
/** The four CanvasKit copies the four builds produce, relative to the output root. */
export const CANONICAL_DIR = 'canvaskit';
export const CANVASKIT_DIRS = [CANONICAL_DIR, ...ROLE_DIRS.map((r) => `${r}/canvaskit`)];

/**
 * A revision is a cache key AND a path segment. Anything that is not a plain hex
 * token is refused, which also makes "/", "..", "" and whitespace impossible, so
 * the value can never escape the intended directory.
 */
export const REVISION_RE = /^[0-9a-fA-F]{7,64}$/;

// ---------------------------------------------------------------- pure ----- //

/** sha256 of a Buffer or string, hex. */
export const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

/**
 * Pull `_flutter.buildConfig = {...};` out of a generated bootstrap and parse it.
 * Deterministic and non-executing: a bounded regex plus JSON.parse.
 */
export function extractBuildConfig(source) {
  if (typeof source !== 'string' || !source) return { error: 'empty bootstrap source' };
  const m = source.match(/_flutter\.buildConfig\s*=\s*(\{[\s\S]*?\});/);
  if (!m) return { error: 'no _flutter.buildConfig assignment found' };
  try { return { buildConfig: JSON.parse(m[1]) }; }
  catch (e) { return { error: `buildConfig is not valid JSON: ${e.message}` }; }
}

/** The engine revision of the build that produced this bootstrap, or an error. */
export function readRevisionFromSource(source) {
  const { buildConfig, error } = extractBuildConfig(source);
  if (error) return { error };
  const rev = buildConfig?.engineRevision;
  if (rev === undefined || rev === null) return { error: 'engineRevision is absent' };
  if (typeof rev !== 'string') return { error: `engineRevision is ${typeof rev}, not a string` };
  if (!REVISION_RE.test(rev)) return { error: `engineRevision "${rev}" is malformed` };
  return { revision: rev, buildConfig };
}

/**
 * The emitted bootstrap must DERIVE its base URL from the build config.
 *
 * Checked on the FINAL loader call only: the inlined loader source itself
 * mentions canvasKitBaseUrl in the ternary that reads the option, and the derived
 * form legitimately contains the literal '/canvaskit/' as its first term - so a
 * bare literal counts only when it TERMINATES the value.
 */
export function assertBootstrapTargetsVersioned(source) {
  const at = source.lastIndexOf('_flutter.loader.load(');
  if (at < 0) return { error: 'no _flutter.loader.load( call found' };
  const call = source.slice(at);
  if (!/config\s*:\s*\{[^}]*canvasKitBaseUrl/.test(call)) return { error: 'canvasKitBaseUrl is not inside the load() config object' };
  if (/\{\{\s*flutter_/.test(source)) return { error: 'an unsubstituted {{flutter_*}} token survived into the output' };
  const derived = /canvasKitBaseUrl\s*:\s*['"]\/canvaskit\/['"]\s*\+\s*[A-Za-z_$][\w$]*\s*\+\s*['"]\/['"]/.test(call);
  if (derived) return { ok: true };
  if (/canvasKitBaseUrl\s*:\s*["']\/canvaskit\/["']\s*[,}]/.test(call)) return { error: 'pins the UNVERSIONED /canvaskit/ path' };
  return { error: 'canvasKitBaseUrl is not derived from the build-config revision' };
}

/** All apps must agree on one revision. */
export function agreeOnRevision(perApp) {
  const entries = Object.entries(perApp ?? {});
  if (entries.length === 0) return { error: 'no revisions supplied' };
  for (const [app, r] of entries) {
    if (typeof r !== 'string' || !REVISION_RE.test(r)) return { error: `${app}: revision "${r}" is missing or malformed` };
  }
  const distinct = [...new Set(entries.map(([, r]) => r))];
  if (distinct.length !== 1) return { error: `apps disagree on the engine revision: ${JSON.stringify(perApp)}` };
  return { revision: distinct[0] };
}

/**
 * Decide whether one distribution may be published at canvaskit/<revision>/ and
 * all four originals removed. Pure: decides, never deletes.
 */
export function planAssembly({ revisions, digests, canonical = CANONICAL_DIR, existingVersioned = null } = {}) {
  const problems = [];
  const no = (why) => { problems.push(why); return { ok: false, revision: null, versionedPath: null, removable: [], problems, savedBytes: 0, digest: null }; };

  const agreed = agreeOnRevision(revisions);
  if (agreed.error) return no(agreed.error);
  const revision = agreed.revision;

  if (!digests || typeof digests !== 'object') return no('no digests supplied');
  if (!CANVASKIT_DIRS.includes(canonical)) return no(`canonical ${canonical} is not a known CanvasKit directory`);
  for (const dir of CANVASKIT_DIRS) {
    const d = digests[dir];
    if (!d) return no(`no inventory for ${dir}`);
    if (!d.present) return no(`missing CanvasKit directory: ${dir}`);
    if (!d.digest) return no(`no digest computed for ${dir}`);
    if (!Array.isArray(d.files) || d.files.length === 0) return no(`${dir} inventoried as empty`);
  }

  const ref = digests[canonical];
  for (const dir of CANVASKIT_DIRS.filter((d) => d !== canonical)) {
    const d = digests[dir];
    if (d.digest === ref.digest) continue;
    const refByPath = new Map(ref.files.map((f) => [f.path, f]));
    const gotByPath = new Map(d.files.map((f) => [f.path, f]));
    for (const p of refByPath.keys()) if (!gotByPath.has(p)) problems.push(`${dir}: missing file ${p}`);
    for (const p of gotByPath.keys()) if (!refByPath.has(p)) problems.push(`${dir}: extra file ${p}`);
    for (const [p, a] of refByPath) {
      const b = gotByPath.get(p);
      if (!b) continue;
      if (a.sha256 !== b.sha256) problems.push(`${dir}: content differs for ${p}`);
      else if (a.bytes !== b.bytes) problems.push(`${dir}: length differs for ${p}`);
    }
    if (!problems.length) problems.push(`${dir}: digest mismatch`);
  }
  if (problems.length) return { ok: false, revision: null, versionedPath: null, removable: [], problems, savedBytes: 0, digest: null };

  // A revision key is immutable by construction. Anything already occupying it
  // breaks that premise; different bytes are named explicitly.
  if (existingVersioned && existingVersioned.present) {
    if (existingVersioned.digest !== ref.digest) {
      return no(`canvaskit/${revision}/ already holds DIFFERENT bytes (${existingVersioned.digest.slice(0, 12)} vs ${ref.digest.slice(0, 12)}) - refusing to overwrite a revision key`);
    }
    return no(`canvaskit/${revision}/ already exists - refusing to write over a revision key`);
  }

  const removable = [...CANVASKIT_DIRS];
  const savedBytes = removable.reduce((n, d) => n + digests[d].totalBytes, 0) - ref.totalBytes;
  return { ok: true, revision, versionedPath: `${CANONICAL_DIR}/${revision}`, removable, problems: [], savedBytes, digest: ref.digest };
}

// ------------------------------------------------------------ filesystem --- //

/** Every regular file under `root`, sorted POSIX-relative. Throws on any link. */
export function walkFiles(root, base = root) {
  const found = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`symlink found, refusing to continue: ${path.relative(base, full)}`);
    if (entry.isDirectory()) found.push(...walkFiles(full, base));
    else if (entry.isFile()) found.push(path.relative(base, full).split(path.sep).join('/'));
    else throw new Error(`not a regular file: ${path.relative(base, full)}`);
  }
  return found.sort();
}

/** One manifest row: relative path, exact bytes, sha256. */
export function fileEntry(root, rel) {
  const abs = path.join(root, ...rel.split('/'));
  const st = lstatSync(abs);
  if (st.isSymbolicLink()) throw new Error(`symlink: ${rel}`);
  const raw = readFileSync(abs);
  if (st.size !== raw.length) throw new Error(`size race on ${rel}: ${st.size} vs ${raw.length}`);
  return { path: rel, bytes: raw.length, sha256: sha256(raw) };
}

/**
 * Digest of one subtree: sha256 over "path\0sha256\0bytes\n" lines. Parent-path
 * independent, so canvaskit/ and pos/canvaskit/ compare directly, and sensitive
 * to both content and length.
 */
export function dirDigest(root, subdir) {
  const abs = path.join(root, ...subdir.split('/'));
  if (!existsSync(abs)) return { subdir, present: false };
  const files = walkFiles(abs).map((rel) => fileEntry(abs, rel));
  return {
    subdir, present: true,
    fileCount: files.length,
    totalBytes: files.reduce((n, f) => n + f.bytes, 0),
    digest: sha256(files.map((f) => `${f.path}\0${f.sha256}\0${f.bytes}\n`).join('')),
    files,
  };
}

/** Refuse any target that is not a plain directory strictly inside `root`. */
export function assertNoEscape(root, relTarget) {
  const rootReal = realpathSync(root);
  const abs = path.resolve(rootReal, ...relTarget.split('/'));
  const rel = path.relative(rootReal, abs);
  if (rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) throw new Error(`escape refused: ${relTarget} resolves outside ${root}`);
  if (!existsSync(abs)) throw new Error(`target does not exist: ${relTarget}`);
  const st = lstatSync(abs);
  if (st.isSymbolicLink()) throw new Error(`refusing to follow a symlink: ${relTarget}`);
  if (!st.isDirectory()) throw new Error(`not a directory: ${relTarget}`);
  const realRel = path.relative(rootReal, realpathSync(abs));
  if (realRel.startsWith('..') || path.isAbsolute(realRel)) throw new Error(`escape refused after realpath: ${relTarget}`);
  return abs;
}

export const asMB = (bytes) => (bytes / 1e6).toFixed(3);
export const asMiB = (bytes) => (bytes / 1048576).toFixed(3);

// ------------------------------------------------------------------ main --- //

/**
 * Assemble the shared engine in `outputDir`, which must already contain the four
 * app outputs. Returns a summary; throws with a precise reason on any failure.
 */
export function assembleCanvasKit(outputDir, { log = console.log } = {}) {
  const out = path.resolve(outputDir);
  if (!existsSync(out)) throw new Error(`output directory does not exist: ${out}`);
  const bootstraps = [
    { role: 'dashboard', rel: 'flutter_bootstrap.js' },
    ...ROLE_DIRS.map((r) => ({ role: r, rel: `${r}/flutter_bootstrap.js` })),
  ];

  // 1 + 2. revisions, read from the generated bootstraps
  const revisions = {};
  for (const b of bootstraps) {
    const abs = path.join(out, ...b.rel.split('/'));
    if (!existsSync(abs)) throw new Error(`${b.role}: missing ${b.rel}`);
    const source = readFileSync(abs, 'utf8');
    const r = readRevisionFromSource(source);
    if (r.error) throw new Error(`${b.role}: ${r.error}`);
    const t = assertBootstrapTargetsVersioned(source);
    if (t.error) throw new Error(`${b.role}: ${t.error}`);
    revisions[b.role] = r.revision;
    log(`  ${b.role.padEnd(10)} engineRevision ${r.revision}`);
  }

  // 3. the four distributions must be provably identical
  const digests = {};
  for (const d of CANVASKIT_DIRS) {
    digests[d] = dirDigest(out, d);
    const x = digests[d];
    log(`  ${d.padEnd(16)} ${x.present ? `${x.fileCount} files ${x.totalBytes} bytes digest ${x.digest.slice(0, 16)}` : 'MISSING'}`);
  }

  const before = walkFiles(out).map((rel) => fileEntry(out, rel));
  const plan = planAssembly({
    revisions, digests,
    existingVersioned: dirDigest(out, `${CANONICAL_DIR}/${Object.values(revisions)[0] ?? 'none'}`),
  });
  if (!plan.ok) throw new Error(`assembly refused: ${plan.problems.join('; ')}`);
  const { revision, versionedPath, digest } = plan;
  log(`  -> all agree: ${revision}`);
  log(`  proof passed: every distribution shares digest ${digest.slice(0, 16)}`);

  // 4. stage outside canvaskit/, verify, then remove the originals and place it.
  const staging = path.join(out, `.canvaskit-staging-${revision}`);
  rmSync(staging, { recursive: true, force: true });
  cpSync(path.join(out, CANONICAL_DIR), staging, { recursive: true, dereference: false, verbatimSymlinks: true });
  const staged = dirDigest(out, path.basename(staging));
  if (!staged.present || staged.digest !== digest) { rmSync(staging, { recursive: true, force: true }); throw new Error('staged copy does not match the proven distribution'); }

  const removed = [];
  for (const rel of plan.removable) { rmSync(assertNoEscape(out, rel), { recursive: true, force: false }); removed.push(rel); }
  mkdirSync(path.join(out, CANONICAL_DIR), { recursive: true });
  cpSync(staging, path.join(out, ...versionedPath.split('/')), { recursive: true, dereference: false, verbatimSymlinks: true });
  rmSync(staging, { recursive: true, force: true });
  log(`  removed ${removed.length} unversioned directories: ${removed.join(', ')}`);
  log(`  published one distribution at /${versionedPath}/`);

  // 5. re-verify
  const placed = dirDigest(out, versionedPath);
  if (!placed.present) throw new Error('the versioned directory was not created');
  if (placed.digest !== digest) throw new Error(`published copy digest ${placed.digest.slice(0, 16)} != proven ${digest.slice(0, 16)}`);

  const after = walkFiles(out).map((rel) => fileEntry(out, rel));
  const beforeByPath = new Map(before.map((f) => [f.path, f]));
  const afterByPath = new Map(after.map((f) => [f.path, f]));
  const wasOriginal = (p) => CANVASKIT_DIRS.some((d) => p === d || p.startsWith(`${d}/`));
  const isVersioned = (p) => p === versionedPath || p.startsWith(`${versionedPath}/`);
  const problems = [];
  for (const [p, f] of beforeByPath) {
    const still = afterByPath.get(p);
    if (!still && !wasOriginal(p)) problems.push(`unexpectedly removed: ${p}`);
    if (still && wasOriginal(p) && !isVersioned(p)) problems.push(`should have been removed: ${p}`);
    if (still && !wasOriginal(p) && (still.sha256 !== f.sha256 || still.bytes !== f.bytes)) problems.push(`surviving file changed: ${p}`);
  }
  for (const p of afterByPath.keys()) if (!beforeByPath.has(p) && !isVersioned(p)) problems.push(`appeared unexpectedly: ${p}`);
  for (const d of CANVASKIT_DIRS.filter((x) => x !== CANONICAL_DIR)) {
    if (existsSync(path.join(out, ...d.split('/')))) problems.push(`unversioned copy still present: ${d}`);
  }
  const under = readdirSync(path.join(out, CANONICAL_DIR));
  if (under.length !== 1 || under[0] !== revision) problems.push(`canvaskit/ must contain exactly the revision directory, found: ${under.join(', ')}`);
  if (existsSync(path.join(out, CANONICAL_DIR, revision, CANONICAL_DIR))) problems.push('the versioned directory is nested inside itself');
  if (problems.length) throw new Error(`post-assembly verification failed:\n  - ${problems.join('\n  - ')}`);

  const totalBefore = before.reduce((n, f) => n + f.bytes, 0);
  const totalAfter = after.reduce((n, f) => n + f.bytes, 0);
  return {
    revision, versionedPath: `/${versionedPath}/`, digest,
    distributionFileCount: placed.fileCount, distributionBytes: placed.totalBytes,
    removed,
    fileCountBefore: before.length, fileCountAfter: after.length,
    bytesBefore: totalBefore, bytesAfter: totalAfter, savedBytes: totalBefore - totalAfter,
    files: after.map((f) => f.path),
  };
}

function main(argv) {
  const out = argv[2];
  if (!out) { console.error('usage: node tools/assemble_web_canvaskit.mjs <combined-output-dir>'); return 2; }
  console.log('=== CanvasKit engine assembly ===');
  try {
    const r = assembleCanvasKit(out);
    console.log(`  engine     : ${r.revision}`);
    console.log(`  published  : ${r.versionedPath} (${r.distributionFileCount} files, ${r.distributionBytes} bytes)`);
    console.log(`  output     : ${r.fileCountBefore} -> ${r.fileCountAfter} files, ${r.bytesBefore} -> ${r.bytesAfter} bytes`);
    console.log(`  saved      : ${r.savedBytes} bytes (${asMB(r.savedBytes)} MB / ${asMiB(r.savedBytes)} MiB)`);
    return 0;
  } catch (e) {
    console.error(`\nCANVASKIT ASSEMBLY FAILED - the output was not published:\n  ${e.message}`);
    return 1;
  }
}

// Executed directly? Do the work. Imported? Do nothing at all.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exit(main(process.argv));
}
