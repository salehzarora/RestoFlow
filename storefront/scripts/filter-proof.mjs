#!/usr/bin/env node
// Non-vacuous three-project filter proof using the REAL shell in isolated Git
// fixtures.
//
// The point is DIFFERENT snapshots. An equal-tree self-check only ever proves
// `no_changes`; scenarios A-C need a valid shell present in BOTH the baseline
// and the head so the storefront guard passes and the decision comes from
// classification, not from a fail-safe guard failure.
import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { EXPECTATIONS, evaluateCell, evaluateDiff } from './filter-expectations.mjs';

const STOREFRONT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO = path.resolve(STOREFRONT, '..');
const ENGINE = 'tools/vercel/ignore-build.mjs';

const git = (cwd, args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8' }).trim();

function seedFixture() {
  const root = mkdtempSync(path.join(tmpdir(), 'storefront-filter-proof-'));
  git(root, ['init', '--quiet', '--initial-branch=main']);
  git(root, ['config', 'user.email', 'proof@example.invalid']);
  git(root, ['config', 'user.name', 'filter proof']);

  // The real engine, the real product/marketing control files, and the REAL shell.
  const copy = [
    ENGINE, 'vercel.json', 'pubspec.yaml', 'pubspec.lock',
    // Hash-pinned by inspectGraph (BUILD_SCRIPT_HASH). Omitting it makes the
    // product selector fail safe to unsupported_graph, which looks like a
    // decision but proves nothing.
    'tools/vercel_build_web.sh',
    // Consumed by the build tail, pinned by CANVASKIT_ASSEMBLER_HASH, and required
    // to EXIST by inspectGraph. Omitting it fails the product selector closed the
    // same way, so the fixture would prove nothing.
    'tools/assemble_web_canvaskit.mjs',
    'site/vercel.json', 'site/package.json', 'site/scripts/build.mjs',
  ];
  for (const rel of copy) {
    const from = path.join(REPO, rel);
    if (!existsSync(from)) continue;
    mkdirSync(path.join(root, path.dirname(rel)), { recursive: true });
    cpSync(from, path.join(root, rel));
  }
  // EVERY workspace-member manifest. inspectGraph resolves the real Flutter
  // dependency graph, and an incomplete manifest set makes the product selector
  // fail safe to BUILD - which looks like a decision but proves nothing.
  const members = execFileSync('git', ['-C', REPO, 'ls-files', '*pubspec.yaml', 'melos.yaml'], { encoding: 'utf8' })
    .split('\n').map((l) => l.trim()).filter(Boolean);
  for (const rel of members) {
    mkdirSync(path.join(root, path.dirname(rel)), { recursive: true });
    cpSync(path.join(REPO, rel), path.join(root, rel));
  }
  // Each deployed app needs a web entry, and every member a lib/ file, so a
  // change to one is classifiable rather than unknown.
  for (const app of ['apps/dashboard', 'apps/pos', 'apps/kds', 'apps/kiosk']) {
    mkdirSync(path.join(root, app, 'web'), { recursive: true });
    writeFileSync(path.join(root, app, 'web/index.html'), '<!doctype html>fixture\n');
  }
  for (const rel of members) {
    if (!rel.endsWith('pubspec.yaml')) continue;
    const member = path.dirname(rel);
    if (member === '.' || !/^(apps|packages)\//.test(member)) continue;
    mkdirSync(path.join(root, member, 'lib'), { recursive: true });
    writeFileSync(path.join(root, member, 'lib/fixture.dart'), '// fixture\n');
  }
  mkdirSync(path.join(root, 'site/src'), { recursive: true });
  writeFileSync(path.join(root, 'site/src/main.js'), '// fixture\n');
  mkdirSync(path.join(root, 'docs'), { recursive: true });
  writeFileSync(path.join(root, 'docs/NOTE.md'), '# fixture\n');

  // The actual shell: every tracked storefront file, generated output excluded.
  cpSync(STOREFRONT, path.join(root, 'storefront'), {
    recursive: true,
    filter: (src) => {
      const rel = path.relative(STOREFRONT, src).split(path.sep).join('/');
      return !(rel === 'node_modules' || rel.startsWith('node_modules/')
        || rel === 'out' || rel.startsWith('out/')
        || rel === '.next' || rel.startsWith('.next/')
        || rel === 'next-env.d.ts');
    },
  });

  git(root, ['add', '--all']);
  git(root, ['commit', '--quiet', '--no-verify', '-m', 'fixture: real shell in the baseline']);
  return { root, base: git(root, ['rev-parse', 'HEAD']) };
}

function decide(root, selector, baseline) {
  const cwd = selector === 'product' ? root
    : path.join(root, selector === 'marketing' ? 'site' : 'storefront');
  const out = execFileSync(process.execPath, [path.join(root, ENGINE), selector], {
    cwd,
    encoding: 'utf8',
    env: {
      ...process.env,
      VERCEL_ENV: 'preview',
      VERCEL_GIT_COMMIT_REF: 'proof',
      VERCEL_GIT_COMMIT_SHA: git(root, ['rev-parse', 'HEAD']),
      VERCEL_GIT_PREVIOUS_SHA: baseline,
    },
    // exit 1 == BUILD is expected, not an error
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
  return JSON.parse(out);
}

function run(root, selector, baseline) {
  try {
    return decide(root, selector, baseline);
  } catch (error) {
    // The CLI exits 1 for BUILD; stdout still carries the JSON.
    const text = (error.stdout || '').toString().trim();
    if (text) return JSON.parse(text);
    throw error;
  }
}

const SCENARIOS = [
  {
    id: 'A', label: 'product-only change, valid shell in BOTH snapshots',
    mutate: (root) => writeFileSync(path.join(root, 'apps/dashboard/lib/fixture.dart'), '// changed\n'),
  },
  {
    id: 'B', label: 'marketing-only change, valid shell in BOTH snapshots',
    mutate: (root) => writeFileSync(path.join(root, 'site/src/main.js'), '// changed\n'),
  },
  {
    id: 'C', label: 'repository docs-only change, valid shell in BOTH snapshots',
    mutate: (root) => writeFileSync(path.join(root, 'docs/NOTE.md'), '# changed\n'),
  },
  {
    id: 'D1', label: 'storefront application source change',
    mutate: (root) => writeFileSync(path.join(root, 'storefront/src/theme/tokens.ts'),
      'export const TOKENS = { colorText: "#fff" } as const;\n'),
  },
  {
    id: 'D2', label: 'storefront config change (vercel.json)',
    mutate: (root) => {
      const file = path.join(root, 'storefront/vercel.json');
      const config = JSON.parse(readFileSync(file, 'utf8'));
      // A genuinely textual config change: tighten a cache header value.
      config.headers[1].headers[0].value = 'public, max-age=31536000, immutable, stale-while-revalidate=60';
      writeFileSync(file, JSON.stringify(config, null, 2) + '\n');
    },
  },
  {
    id: 'D3', label: 'storefront test change (a support root)',
    mutate: (root) => writeFileSync(path.join(root, 'storefront/tests/locales.test.mjs'),
      "import { test } from 'node:test';\ntest('changed', () => {});\n"),
  },
  {
    id: 'D4', label: 'storefront docs change (a support root)',
    mutate: (root) => writeFileSync(path.join(root, 'storefront/README.md'), '# changed\n'),
  },
];

let failures = 0;
const rows = [];
for (const s of SCENARIOS) {
  const { root, base } = seedFixture();
  try {
    s.mutate(root);
    const status = git(root, ['status', '--porcelain']);
    if (!status) {
      if (s.skipIfUnchanged) { rows.push({ id: s.id, label: s.label, skipped: 'no textual change' }); continue; }
      throw new Error(`${s.id}: mutation produced no change`);
    }
    git(root, ['add', '--all']);
    git(root, ['commit', '--quiet', '--no-verify', '-m', `fixture: ${s.id}`]);

    const head = git(root, ['rev-parse', 'HEAD']);
    // A scenario whose trees are identical exercises no decision at all.
    for (const problem of evaluateDiff({ scenario: s.id, baseline: base, head })) {
      failures++; console.error(`FAIL ${problem}`);
    }

    const got = {};
    for (const selector of ['marketing', 'product', 'storefront']) {
      const result = run(root, selector, base);
      got[selector] = { decision: result.decision, reason: result.reason, categories: result.categories };
      const expected = EXPECTATIONS[s.id]?.[selector];
      if (!expected) {
        failures++;
        console.error(`FAIL ${s.id} ${selector}: no expectation declared`);
        continue;
      }
      // Assert the MECHANISM, not just the outcome: a fail-safe BUILD with an
      // empty category map must never satisfy a cell meant to prove
      // classification against a valid graph.
      for (const problem of evaluateCell({ scenario: s.id, selector, expected, actual: result })) {
        failures++; console.error(`FAIL ${problem}`);
      }
    }
    rows.push({ id: s.id, label: s.label, got });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

for (const r of rows) {
  if (r.skipped) { console.log(`${r.id}  SKIPPED - ${r.skipped}`); continue; }
  const line = ['marketing', 'product', 'storefront']
    .map((s) => `${s}=${r.got[s].decision}/${r.got[s].reason}/${JSON.stringify(r.got[s].categories)}`).join('  ');
  console.log(`${r.id}  ${r.label}\n    ${line}`);
}

if (failures) {
  console.error(`\nFILTER PROOF FAILED: ${failures} wrong decision(s)`);
  process.exitCode = 1;
} else {
  console.log('\nFILTER PROOF PASSED - all scenarios decided as required');
}
