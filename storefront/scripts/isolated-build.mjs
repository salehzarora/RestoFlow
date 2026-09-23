#!/usr/bin/env node
// Isolated-copy build comparison.
//
// Copies ONLY the intended storefront build inputs to a disposable directory
// OUTSIDE the monorepo, installs from the same lockfile with the same Node, and
// compares the two builds with the pure comparator in compare-exports.mjs.
// Proves the build needs no sibling source, owner asset or repository context.
//
// STOREFRONT-READ-001: the storefront is server-rendered, so the artifact
// compared is the CLIENT STATIC tree (.next/static: every chunk, stylesheet,
// font and manifest a browser can load) plus each build's own BUILD_ID, given to
// the comparator through the same index.html marker a served document carries.
// The server bundle embeds absolute build paths and is not byte-comparable
// across directories by design; it is not what this evidence is about.
//
// What is NOT copied: the parent repository, .git, owner folders, credentials,
// node_modules, or any previous build output.
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, rmSync, readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compareInventories, NORMALISATION_DESCRIPTION } from './compare-exports.mjs';

const STOREFRONT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Exactly the tracked build inputs. tests/ and scripts/ are support code the
// build never reads, so a build that succeeds without them is stronger evidence.
const INPUTS = ['package.json', 'package-lock.json', 'next.config.mjs', 'tsconfig.json',
  'app', 'src', 'messages', 'public', '.nvmrc'];

const TEXT = /\.(?:html|js|css|json|txt|svg|map|webmanifest)$/;

function walk(dir, base = dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) found.push(...walk(full, base));
    else found.push(path.relative(base, full).split(path.sep).join('/'));
  }
  return found.sort();
}

/** Read a build's client static tree into the comparator's inventory shape. */
function readBuild(nextDir) {
  const files = new Map();
  const staticDir = path.join(nextDir, 'static');
  for (const rel of walk(staticDir)) {
    const abs = path.join(staticDir, rel);
    const raw = readFileSync(abs);
    files.set(`_next/static/${rel}`, {
      bytes: statSync(abs).size,
      content: TEXT.test(rel) ? raw.toString('utf8') : raw,
    });
  }
  // The build id, in the exact form a served document references it, so the
  // comparator's ONE permitted normalisation (build-ID literals) applies.
  const buildId = readFileSync(path.join(nextDir, 'BUILD_ID'), 'utf8').trim();
  const marker = `<script src="/_next/static/${buildId}/_buildManifest.js"></script>`;
  files.set('index.html', { bytes: Buffer.byteLength(marker), content: marker });
  return files;
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
  for (const forbidden of ['.git', 'node_modules', 'out', '.next', 'tools', 'site', 'apps', 'docs', 'tests', 'scripts']) {
    if (existsSync(path.join(appDir, forbidden))) problems.push(`isolated copy contains ${forbidden}`);
  }

  console.log(`isolated copy at ${appDir}`);
  console.log(`node ${process.version} for BOTH builds (same runtime; differences cannot be blamed on version skew)`);

  execFileSync('npm', ['ci', '--no-audit', '--no-fund'], { cwd: appDir, stdio: 'inherit', shell: process.platform === 'win32' });
  execFileSync('npm', ['run', 'build'], { cwd: appDir, stdio: 'inherit', shell: process.platform === 'win32' });

  const worktreeNext = path.join(STOREFRONT, '.next');
  const isolatedNext = path.join(appDir, '.next');
  if (!existsSync(path.join(worktreeNext, 'BUILD_ID'))) problems.push('worktree .next/ missing - build it first');
  if (!existsSync(path.join(isolatedNext, 'BUILD_ID'))) problems.push('isolated .next/ missing');

  if (!problems.length) {
    const a = readBuild(worktreeNext);
    const b = readBuild(isolatedNext);

    // RAW first: how many files differ byte-for-byte, before any normalisation.
    let rawDiffering = 0;
    for (const [rel, meta] of a) {
      const other = b.get(rel);
      if (!other) continue;
      const left = Buffer.isBuffer(meta.content) ? meta.content : Buffer.from(meta.content);
      const right = Buffer.isBuffer(other.content) ? other.content : Buffer.from(other.content);
      if (!left.equals(right)) rawDiffering++;
    }
    const rawOnlyA = [...a.keys()].filter((k) => !b.has(k)).length;
    const rawOnlyB = [...b.keys()].filter((k) => !a.has(k)).length;

    const result = compareInventories(a, b, { labelA: 'worktree', labelB: 'isolated' });

    console.log(`\nRAW (no normalisation): ${a.size} vs ${b.size} files; ` +
      `${rawDiffering} differing, ${rawOnlyA} only-in-worktree, ${rawOnlyB} only-in-isolated`);
    console.log(`build ids: worktree [${result.stats.buildIdsA.join(', ')}] / isolated [${result.stats.buildIdsB.join(', ')}]`);
    console.log(`\nNORMALISATION APPLIED: ${NORMALISATION_DESCRIPTION}`);
    console.log(`\nAFTER normalisation: ${result.stats.countA} vs ${result.stats.countB} files compared; ` +
      `${result.stats.differing.length} still differing`);
    console.log(`routes: ${result.stats.routes.join(', ')}`);
    problems.push(...result.problems);
  }

  if (problems.length) {
    console.error('\nISOLATED BUILD COMPARISON FAILED:');
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  } else {
    console.log('\nISOLATED BUILD COMPARISON PASSED');
    console.log('Scope of this evidence: the CURRENT storefront builds an identical client');
    console.log('static tree without sibling source or owner assets. It is not a claim about');
    console.log('future features, and it is NOT hosted routing or header verification -');
    console.log('vercel.json behaviour is proven separately, and only against the local');
    console.log('emulation until the hosted gate.');
  }
} finally {
  rmSync(isolated, { recursive: true, force: true });
}
