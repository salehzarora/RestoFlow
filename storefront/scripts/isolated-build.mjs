#!/usr/bin/env node
// Isolated-copy build comparison.
//
// Copies ONLY the intended storefront build inputs to a disposable directory
// OUTSIDE the monorepo, installs from the same lockfile with the same Node, and
// compares the two exports. Proves the build needs no sibling source, owner
// asset or repository context.
//
// What is NOT copied: the parent repository, .git, owner folders, credentials,
// node_modules, or any previous build output.
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, rmSync, readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const STOREFRONT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Exactly the tracked build inputs. tests/ and scripts/ are support code the
// build never reads, so a build that succeeds without them is stronger evidence.
const INPUTS = ['package.json', 'package-lock.json', 'next.config.mjs', 'tsconfig.json',
  'app', 'src', 'messages', 'public', '.nvmrc'];

// Fields that are legitimately nondeterministic between two builds of identical
// source. Each is listed with WHY; nothing else may be normalised, and whole
// files or chunks are never discarded.
const NORMALISATIONS = [
  { name: 'content-hashed chunk filenames', why: 'Turbopack derives chunk names from content plus a per-build salt, so identical source can still produce different names', pattern: /\/_next\/static\/chunks\/[A-Za-z0-9_.-]+\.(js|css)/g, replacement: '/_next/static/chunks/<CHUNK>.$1' },
  { name: 'RSC cache-busting query', why: 'the _rsc query value is derived from the build id', pattern: /\?_rsc=[A-Za-z0-9_-]+/g, replacement: '?_rsc=<RSC>' },
];

/**
 * A build emits TWO distinct random identifiers, and they are not the same
 * string: the static asset directory (/_next/static/<id>/) and the RSC flight
 * payload build id (the "b" field inside the inline hydration script). Both are
 * read from THIS build's own output and replaced as exact literals, never as a
 * pattern - a pattern of the same shape could mask a real difference. Verified
 * empirically: with both normalised the two builds are byte-identical, which is
 * what proves the build id was the ONLY nondeterministic field.
 */
function buildIdsOf(outDir) {
  const html = readFileSync(path.join(outDir, 'index.html'), 'utf8');
  const ids = new Set();
  const asset = /\/_next\/static\/([A-Za-z0-9_-]{10,})\//.exec(html);
  if (asset) ids.add(asset[1]);
  // Escaped inside the inline script: \"b\":\"<id>\"
  for (const m of html.matchAll(/\\"b\\":\\"([A-Za-z0-9_-]{15,})\\"/g)) ids.add(m[1]);
  // Unescaped form, as it appears in the .txt flight payloads.
  for (const m of html.matchAll(/"b":"([A-Za-z0-9_-]{15,})"/g)) ids.add(m[1]);
  return [...ids];
}

function normaliseWith(text, buildIds) {
  let out = NORMALISATIONS.reduce((acc, n) => acc.replace(n.pattern, n.replacement), text);
  for (const id of buildIds) out = out.split(id).join('<BUILD_ID>');
  return out;
}

const sha = (buf) => createHash('sha256').update(buf).digest('hex');

function walk(dir, base = dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...walk(full, base));
    else found.push(path.relative(base, full).split(path.sep).join('/'));
  }
  return found.sort();
}

function inventory(outDir) {
  const buildId = buildIdsOf(outDir);
  const files = walk(outDir);
  const map = new Map();
  for (const rel of files) {
    const abs = path.join(outDir, rel);
    const raw = readFileSync(abs);
    const isText = /\.(?:html|js|css|json|txt|svg)$/.test(rel);
    map.set(normaliseWith(rel, buildId), {
      bytes: statSync(abs).size,
      digest: isText ? sha(Buffer.from(normaliseWith(raw.toString('utf8'), buildId))) : sha(raw),
      text: isText,
    });
  }
  return { map, buildId };
}

const isolated = mkdtempSync(path.join(tmpdir(), 'storefront-isolated-'));
const appDir = path.join(isolated, 'app-copy');
const problems = [];

try {
  for (const rel of INPUTS) {
    const from = path.join(STOREFRONT, rel);
    if (!existsSync(from)) { problems.push(`missing input ${rel}`); continue; }
    cpSync(from, path.join(appDir, rel), { recursive: true });
  }
  // Nothing from the monorepo may have travelled with it.
  for (const forbidden of ['.git', 'node_modules', 'out', '.next', 'tools', 'site', 'apps', 'docs']) {
    if (existsSync(path.join(appDir, forbidden))) problems.push(`isolated copy contains ${forbidden}`);
  }

  const node = process.version;
  console.log(`isolated copy at ${appDir}`);
  console.log(`node ${node} for BOTH builds (same runtime, so differences cannot be blamed on version skew)`);

  execFileSync('npm', ['ci', '--no-audit', '--no-fund'], { cwd: appDir, stdio: 'inherit', shell: process.platform === 'win32' });
  execFileSync('npm', ['run', 'build'], { cwd: appDir, stdio: 'inherit', shell: process.platform === 'win32' });

  const worktreeOut = path.join(STOREFRONT, 'out');
  const isolatedOut = path.join(appDir, 'out');
  if (!existsSync(worktreeOut)) problems.push('worktree out/ missing - build it first');

  const inventoryA = inventory(worktreeOut);
  const inventoryB = inventory(isolatedOut);
  const a = inventoryA.map;
  const b = inventoryB.map;
  console.log(`build ids: worktree [${inventoryA.buildId.join(', ')}] / isolated [${inventoryB.buildId.join(', ')}]`);

  // Route inventory
  const routesA = [...a.keys()].filter((f) => f.endsWith('.html')).sort();
  const routesB = [...b.keys()].filter((f) => f.endsWith('.html')).sort();
  if (JSON.stringify(routesA) !== JSON.stringify(routesB)) {
    problems.push(`route inventory differs:\n  worktree: ${routesA.join(', ')}\n  isolated: ${routesB.join(', ')}`);
  }

  // Full file inventory
  const onlyA = [...a.keys()].filter((f) => !b.has(f));
  const onlyB = [...b.keys()].filter((f) => !a.has(f));
  for (const f of onlyA) problems.push(`only in worktree build: ${f}`);
  for (const f of onlyB) problems.push(`only in isolated build: ${f}`);

  // Substantive content
  const differing = [];
  for (const [file, meta] of a) {
    const other = b.get(file);
    if (!other) continue;
    if (meta.digest !== other.digest) differing.push({ file, worktree: meta.bytes, isolated: other.bytes });
  }
  for (const d of differing) {
    problems.push(`content differs after normalisation: ${d.file} (${d.worktree} vs ${d.isolated} bytes)`);
  }

  console.log(`\nfiles compared: ${a.size} worktree / ${b.size} isolated`);
  console.log(`routes: ${routesA.join(', ')}`);
  console.log('\nnormalisations applied (each field, and why it is nondeterministic):');
  console.log(`  - build id literals (${inventoryA.buildId.length} per build): the static asset directory and the RSC flight "b" field; only this build's own id strings are replaced, never a pattern`);
  for (const n of NORMALISATIONS) console.log(`  - ${n.name}: ${n.why}`);
  console.log('\nNothing else was normalised; no chunk or document was excluded from the comparison.');

  if (problems.length) {
    console.error('\nISOLATED BUILD COMPARISON FAILED:');
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  } else {
    console.log('\nISOLATED BUILD COMPARISON PASSED - the build needs no sibling source or owner asset');
  }
} finally {
  rmSync(isolated, { recursive: true, force: true });
}
