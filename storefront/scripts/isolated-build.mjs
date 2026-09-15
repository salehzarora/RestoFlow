#!/usr/bin/env node
// Isolated-copy build comparison.
//
// Copies ONLY the intended storefront build inputs to a disposable directory
// OUTSIDE the monorepo, installs from the same lockfile with the same Node, and
// compares the two exports with the pure comparator in compare-exports.mjs.
// Proves the build needs no sibling source, owner asset or repository context.
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

/** Read an export into the comparator's inventory shape. */
function readExport(outDir) {
  const files = new Map();
  for (const rel of walk(outDir)) {
    const abs = path.join(outDir, rel);
    const raw = readFileSync(abs);
    files.set(rel, {
      bytes: statSync(abs).size,
      content: TEXT.test(rel) ? raw.toString('utf8') : raw,
    });
  }
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

  const worktreeOut = path.join(STOREFRONT, 'out');
  const isolatedOut = path.join(appDir, 'out');
  if (!existsSync(worktreeOut)) problems.push('worktree out/ missing - build it first');
  if (!existsSync(isolatedOut)) problems.push('isolated out/ missing');

  if (!problems.length) {
    const a = readExport(worktreeOut);
    const b = readExport(isolatedOut);

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
    console.log('Scope of this evidence: the CURRENT shell builds identically without sibling');
    console.log('source or owner assets. It is not a claim about future features, and it is');
    console.log('NOT hosted routing or header verification - vercel.json behaviour is proven');
    console.log('separately, and only against the local emulation until the hosted gate.');
  }
} finally {
  rmSync(isolated, { recursive: true, force: true });
}
