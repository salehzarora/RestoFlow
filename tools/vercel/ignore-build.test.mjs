import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { after, test } from 'node:test';

// Always exercise the real sibling helper and manifests from this checkout.
const SOURCE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const HELPER = 'tools/vercel/ignore-build.mjs';
const APP_ROOTS = ['apps/dashboard', 'apps/pos', 'apps/kds', 'apps/kiosk'];
const EXPECTED_RUNTIME_PACKAGES = ['auth_identity', 'core', 'currency', 'data_local', 'data_remote', 'design_system', 'domain', 'feature_admin', 'feature_auth', 'feature_kitchen', 'feature_menu', 'l10n', 'money', 'native_printing', 'printing', 'sync'].map((name) => `packages/${name}`).sort();
const CANARY = 'synthetic-secret-never-log-81ca83a9';
const scratchParent = realpathSync(tmpdir());
const scratch = mkdtempSync(join(scratchParent, 'restoflow-vercel-filter-test-'));
const emptyGitConfig = join(scratch, 'empty-git-config');
writeFileSync(emptyGitConfig, '');
// PLAN §14 canonical text. STOREFRONT_CONFIG_HASH pins this byte-for-byte, so a
// stray edit here turns every storefront case into a fail-safe BUILD. Written
// from INLINE literals because SOURCE_ROOT has no storefront/ at 001A.
const STOREFRONT_NEXT_CONFIG = `/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  images: { unoptimized: true },
  reactStrictMode: true,
  poweredByHeader: false,
  trailingSlash: false,
};

export default nextConfig;
`;

// Hoisted so the Stage 7 cases can derive one-key variants of the approved
// contract instead of restating it, which is how a variant stays a variant.
const json = (value) => JSON.stringify(value, null, 2) + '\n';
const STOREFRONT_TSCONFIG = {
  compilerOptions: { baseUrl: '.', paths: { '@/*': ['./src/*'] } },
  include: ['app', 'src'], exclude: ['tests'],
};
const STOREFRONT_VERCEL = {
  framework: 'nextjs', installCommand: 'npm ci', buildCommand: 'npm run build',
  outputDirectory: 'out',
  ignoreCommand: 'if node ../tools/vercel/ignore-build.mjs storefront; then exit 0; else exit 1; fi',
};

const STOREFRONT_FILES = {
  'storefront/package.json': JSON.stringify({
    name: 'storefront', version: '0.0.0', private: true,
    scripts: { build: 'next build' },
    dependencies: { next: '16.3.5', react: '19.2.0', 'react-dom': '19.2.0' },
  }, null, 2) + '\n',
  'storefront/package-lock.json': JSON.stringify({ name: 'storefront', lockfileVersion: 3, packages: {} }, null, 2) + '\n',
  'storefront/next.config.mjs': STOREFRONT_NEXT_CONFIG,
  'storefront/tsconfig.json': json(STOREFRONT_TSCONFIG),
  'storefront/vercel.json': json(STOREFRONT_VERCEL),
  'storefront/app/page.tsx': "import { hello } from '@/lib/hello';\nexport default function Page() { return hello; }\n",
  'storefront/src/lib/hello.ts': "export const hello = 'fixture';\n",
  'storefront/messages/en.json': '{ "hello": "fixture" }\n',
  'storefront/public/icon.svg': '<svg xmlns="http://www.w3.org/2000/svg"/>\n',
  'storefront/tests/shell.test.mjs': '// fixture suite\n',
};

const fixtureSources = new Map();
const CANONICAL_SOURCE = 'https://github.com/salehzarora/RestoFlow.git';

// No inherited credentials, Git configuration, proxy settings, or NODE_OPTIONS.
const safeEnv = {};
for (const [key, value] of Object.entries(process.env)) {
  if (/^(path|pathext|systemroot|windir|comspec|temp|tmp)$/i.test(key)) safeEnv[key] = value;
}
Object.assign(safeEnv, {
  GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: emptyGitConfig, GIT_CONFIG_SYSTEM: emptyGitConfig,
  GIT_TERMINAL_PROMPT: '0', GIT_AUTHOR_NAME: 'Filter fixture', GIT_COMMITTER_NAME: 'Filter fixture',
  GIT_AUTHOR_EMAIL: 'filter-fixture@example.invalid', GIT_COMMITTER_EMAIL: 'filter-fixture@example.invalid',
  // R2 may fetch baseline objects, but tests can only contact local file remotes.
  GIT_ALLOW_PROTOCOL: 'file',
});

after(() => {
  // Delete only this process's freshly created temporary subtree.
  const actual = realpathSync(scratch);
  assert.equal(dirname(actual), scratchParent);
  assert.ok(actual.startsWith(join(scratchParent, 'restoflow-vercel-filter-test-')));
  rmSync(actual, { recursive: true, force: true });
});

function runGit(repo, args) {
  const result = spawnSync('git', ['-c', 'core.autocrlf=false', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=' + join(scratch, 'no-hooks'), ...args], {
    cwd: repo, env: safeEnv, encoding: 'utf8', timeout: 15_000, windowsHide: true,
  });
  assert.equal(result.error, undefined, 'fixture Git executable must be available');
  assert.equal(result.status, 0, `fixture git ${args[0]} failed: ${result.stderr}`);
  return result.stdout.trim();
}

function put(repo, path, content = 'fixture\n') {
  const target = resolve(repo, path);
  const suffix = relative(repo, target);
  assert.ok(suffix && !isAbsolute(suffix) && suffix !== '..' && !suffix.startsWith('..' + sep));
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, content);
}

function commit(repo, message = 'fixture change') {
  runGit(repo, ['add', '--all']);
  runGit(repo, ['commit', '--quiet', '--no-verify', '-m', message]);
  return runGit(repo, ['rev-parse', 'HEAD']);
}

function workspaceMembers(text) {
  const body = text.split(/^workspace:\s*\r?$/m)[1]?.split(/^\S/m)[0];
  assert.ok(body, 'real workspace must remain an explicit block list');
  const members = [...body.matchAll(/^  - ([A-Za-z0-9_/-]+)\s*\r?$/gm)].map((match) => match[1]);
  assert.equal(new Set(members).size, members.length);
  assert.ok(members.length > 0);
  return members;
}

const rootManifest = readFileSync(join(SOURCE_ROOT, 'pubspec.yaml'), 'utf8');
const MEMBERS = workspaceMembers(rootManifest);
const manifestTexts = new Map(MEMBERS.map((member) => [member, readFileSync(join(SOURCE_ROOT, member, 'pubspec.yaml'), 'utf8')]));

// Independent test oracle: read only the runtime dependency section, resolve
// workspace package names, and compute transitive reachability from build roots.
function runtimeGraph(texts = manifestTexts) {
  const byName = new Map();
  for (const [member, text] of texts) {
    const name = /^name:\s*([A-Za-z0-9_]+)\s*\r?$/m.exec(text)?.[1];
    assert.ok(name, `${member} has an ordinary package name`);
    assert.ok(!byName.has(name), 'workspace package names are unique');
    byName.set(name, member);
  }
  const seen = new Set();
  const pending = [...APP_ROOTS];
  while (pending.length) {
    const member = pending.pop();
    if (seen.has(member)) continue;
    seen.add(member);
    const text = texts.get(member);
    assert.ok(text, `missing manifest in graph oracle: ${member}`);
    const section = text.split(/^dependencies:\s*\r?$/m)[1]?.split(/^\S/m)[0] || '';
    for (const match of section.matchAll(/^  ([A-Za-z0-9_]+):/gm)) {
      const dependency = byName.get(match[1]);
      if (dependency) pending.push(dependency);
    }
  }
  return seen;
}

function fixture(options = {}) {
  const repo = mkdtempSync(join(scratch, 'repo-'));
  runGit(repo, ['init', '--quiet', '--initial-branch=main']);
  put(repo, 'pubspec.yaml', rootManifest);
  const files = ['pubspec.lock', 'vercel.json', 'tools/vercel_build_web.sh', 'site/vercel.json', 'site/package.json', 'site/scripts/build.mjs'];
  for (const path of files) put(repo, path, readFileSync(join(SOURCE_ROOT, path)));
  put(repo, HELPER, readFileSync(join(SOURCE_ROOT, HELPER)));
  for (const [member, text] of manifestTexts) {
    put(repo, `${member}/pubspec.yaml`, text);
    put(repo, `${member}/lib/filter_fixture.dart`, '// fixture\n');
  }
  for (const app of APP_ROOTS) put(repo, `${app}/web/index.html`, '<!doctype html>fixture\n');
  put(repo, 'site/src/main.js', '// site fixture\n');
  put(repo, 'site/public/license.md', 'copied fixture\n');
  put(repo, 'site/api/lead.js', '// fixture\n');
  put(repo, 'site/lib/lead.mjs', '// fixture\n');
  put(repo, 'docs/DEPLOYMENT.md', 'fixture docs\n');
  put(repo, '.github/workflows/ci.yml', 'name: fixture\non:\n  pull_request:\n  push:\n    branches: [main]\n');
  put(repo, 'tools/vercel/ignore-build.test.mjs', '// fixture suite\n');
  for (const [file, text] of Object.entries(STOREFRONT_FILES)) put(repo, file, text);
  if (options.realRuntime) {
    function copyRuntime(relativePath) {
      const source = join(SOURCE_ROOT, relativePath);
      if (!existsSync(source)) return;
      for (const item of readdirSync(source, { withFileTypes: true })) {
        const child = `${relativePath}/${item.name}`;
        if (item.isDirectory()) copyRuntime(child);
        else if (item.isFile()) put(repo, child, readFileSync(join(SOURCE_ROOT, child)));
      }
    }
    for (const member of runtimeGraph()) copyRuntime(`${member}/lib`);
    for (const root of ['site/src', 'site/api', 'site/lib']) copyRuntime(root);
  }
  if (options.seed) options.seed(repo);
  const base = commit(repo, 'initial fixture');
  return { repo, base };
}

// These remotes are created inside this test process's owned scratch tree.
// file:// is deliberate: unlike a local-path clone it honors --depth on Git.
function attachOrigin(repo) {
  const directory = mkdtempSync(join(scratch, 'bare-'));
  const remote = join(directory, 'origin.git');
  runGit(scratch, ['clone', '--quiet', '--bare', '--no-hardlinks', repo, remote]);
  runGit(repo, ['remote', 'add', 'origin', pathToFileURL(remote).href]);
  fixtureSources.set(repo, pathToFileURL(remote).href);
  return remote;
}

function cloneOrigin(remote, { branch = 'feature/r2', depth = 1 } = {}) {
  const parent = mkdtempSync(join(scratch, 'clone-'));
  const repo = join(parent, 'checkout');
  const args = ['clone', '--quiet', '--no-tags', '--single-branch', '--branch', branch];
  if (depth !== null) args.push(`--depth=${depth}`);
  runGit(parent, [...args, pathToFileURL(remote).href, repo]);
  fixtureSources.set(repo, pathToFileURL(remote).href);
  return repo;
}

// Acquisition tests inject owned file URLs through the imported code API only.
// The actual CLI has no source option and always uses the canonical public URL.
function shallowFixture({ changes = [['docs/r2.md']], depth = 1 } = {}) {
  const { repo: source, base } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'feature/r2']);
  for (const paths of changes) {
    for (const path of paths) {
      if (existsSync(join(source, path))) appendFileSync(join(source, path), '\n// R2 change\n');
      else put(source, path, '// R2 fixture change\n');
    }
    commit(source);
  }
  const remote = attachOrigin(source);
  const repo = cloneOrigin(remote, { depth });
  assert.equal(runGit(repo, ['rev-parse', '--is-shallow-repository']), 'true');
  return { repo, source, remote, base };
}

function commitAvailable(repo, sha) {
  const probe = spawnSync('git', ['-C', repo, 'cat-file', '-e', `${sha}^{commit}`], {
    env: safeEnv, encoding: 'utf8', timeout: 15_000, windowsHide: true,
  });
  assert.equal(probe.error, undefined);
  return probe.status === 0;
}

function traceOptions() {
  const path = join(mkdtempSync(join(scratch, 'trace-')), 'git.log');
  return { path, env: { GIT_TRACE: path.replace(/\\/g, '/') } };
}

function fetchCommands(trace) {
  if (!existsSync(trace.path)) return [];
  return readFileSync(trace.path, 'utf8').split(/\r?\n/)
    .filter((line) => line.includes('built-in: git ') && /\sfetch\s/.test(line))
    .map((line) => line.slice(line.indexOf(' fetch ') + 1));
}

function assertExactFetch(trace, spec, source) {
  const commands = fetchCommands(trace);
  assert.equal(commands.length, 1, 'exactly one acquisition fetch');
  const prefix = 'fetch --no-tags --depth=1 --no-recurse-submodules --no-auto-maintenance --no-write-commit-graph --no-prune --no-prune-tags --refmap= ';
  assert.ok(commands[0].startsWith(prefix) && commands[0].endsWith(' ' + spec));
  const actual = commands[0].slice(prefix.length, -spec.length - 1);
  if (source) assert.equal(actual, source);
  else assert.ok([...fixtureSources.values()].includes(actual), 'only a code-injected owned bare repository');
}

function assertBaseline(output, baseline, source, fetched) {
  assert.equal(output.baseline, baseline);
  assert.equal(output.baselineSource, source);
  assert.equal(output.fetched, fetched);
}

function worktreeSnapshot(repo) {
  const status = runGit(repo, ['status', '--porcelain=v1', '--untracked-files=all']);
  return {
    head: runGit(repo, ['rev-parse', 'HEAD']),
    symbolicHead: readFileSync(join(repo, '.git/HEAD'), 'utf8'),
    refs: runGit(repo, ['for-each-ref', '--format=%(refname) %(objectname)']),
    status,
    index: readFileSync(join(repo, '.git/index')).toString('base64'),
    dirty: readFileSync(join(repo, 'docs/DEPLOYMENT.md'), 'utf8'),
    untracked: readFileSync(join(repo, 'docs/untracked-r2.md'), 'utf8'),
  };
}

function invoke(repo, selector, previous, options = {}) {
  const head = runGit(repo, ['rev-parse', 'HEAD']);
  const branch = runGit(repo, ['branch', '--show-current']);
  const env = {
    ...safeEnv, VERCEL_ENV: 'preview', VERCEL_GIT_COMMIT_REF: branch,
    VERCEL_GIT_COMMIT_SHA: head, VERCEL_GIT_PREVIOUS_SHA: previous || '',
    RESTOFLOW_SUPABASE_ANON_KEY: CANARY, RESEND_API_KEY: CANARY, VERCEL_TOKEN: CANARY,
    ...options.env,
  };
  for (const name of options.absentEnv || []) delete env[name];
  if (options.noGit) {
    for (const key of Object.keys(env)) if (/^path$/i.test(key)) delete env[key];
    env.PATH = join(scratch, 'no-executables');
  }
  const cwd = options.cwd || (selector === 'product' ? repo
    : join(repo, selector === 'marketing' ? 'site' : 'storefront'));
  const helperFile = join(repo, HELPER);
  const repositoryUrl = options.productionCli ? undefined : fixtureSources.get(repo);
  // Source injection is a literal JS dependency in this child, never env or a
  // production CLI argument. All other paths continue to exercise the CLI.
  const args = repositoryUrl === undefined ? [helperFile, selector] : ['--input-type=module', '-e',
    'import { decide } from ' + JSON.stringify(pathToFileURL(helperFile).href) + ';' +
    'const result = decide(' + JSON.stringify({ selector, helperFile }) + ',' + JSON.stringify({ repositoryUrl }) + ');' +
    'process.stdout.write(JSON.stringify(result) + "\\n"); process.exitCode = result.decision === "IGNORE" ? 0 : 1;'];
  const result = spawnSync(process.execPath, args, { cwd, env, encoding: 'utf8', timeout: 35_000, windowsHide: true });
  assert.equal(result.error, undefined, 'helper must terminate without process error');
  assert.equal(result.signal, null);
  assert.ok([0, 1].includes(result.status), 'helper must normalize every exit to IGNORE0 or BUILD1');
  assert.ok(!result.stdout.includes(CANARY) && !result.stderr.includes(CANARY), 'synthetic secrets must never be logged');
  assert.equal(result.stderr, '', 'helper must not print raw diagnostics or exception text');
  const lines = result.stdout.trim().split(/\r?\n/);
  assert.equal(lines.length, 1, 'one JSON decision per invocation');
  const output = JSON.parse(lines[0]);
  assert.deepEqual(Object.keys(output).sort(), ['baseline', 'baselineSource', 'categories', 'decision', 'fetched', 'head', 'reason']);
  assert.equal(output.decision, result.status === 0 ? 'IGNORE' : 'BUILD');
  assert.match(output.reason, /^[a-zA-Z0-9_-]+$/, 'reason must be a bounded code, not error text');
  assert.ok([null, 'previous_success', 'production_main'].includes(output.baselineSource));
  assert.equal(typeof output.fetched, 'boolean');
  for (const key of ['baseline', 'head']) assert.ok(output[key] === null || /^[0-9a-f]{40}$/i.test(output[key]));
  assert.equal(typeof output.categories, 'object');
  assert.ok(output.categories && !Array.isArray(output.categories));
  for (const [category, count] of Object.entries(output.categories)) {
    assert.match(category, /^[a-zA-Z0-9_-]+$/, 'categories must not contain raw paths');
    assert.ok(Number.isInteger(count) && count >= 0);
  }
  return { ...result, output, head };
}

function expectDecision(repo, selector, base, expected, options) {
  const result = invoke(repo, selector, base, options);
  assert.equal(result.output.decision, expected, `${selector}: ${result.stdout}`);
  return result.output;
}

// Every call site states all THREE expectations explicitly: a default would
// make the storefront column vacuous exactly where it matters most.
function expectAll(repo, base, marketing, product, storefront, options) {
  expectDecision(repo, 'marketing', base, marketing, options);
  expectDecision(repo, 'product', base, product, options);
  expectDecision(repo, 'storefront', base, storefront, options);
}

// A guard violation present in BOTH compared trees, with docs/ as the only
// changed path. The classifier's own answer there is IGNORE, so a BUILD can
// only have come from inspectStorefront. Asserting the guard REASON is what
// separates a real guard proof from a case that merely touched a runtime file
// and collected relevant_changes.
function guardOnly(mutate, label) {
  const { repo, base } = fixture({ seed: mutate });
  put(repo, 'docs/guard-probe.md', `# ${label}\n`);
  commit(repo);
  const { output, stdout } = invoke(repo, 'storefront', base);
  assert.equal(output.decision, 'BUILD', `guard-only ${label}: ${stdout}`);
  assert.ok(['unsupported_build_contract', 'unsupported_graph'].includes(output.reason),
    `guard-only ${label}: expected a guard reason, got ${output.reason}`);
  expectDecision(repo, 'marketing', base, 'IGNORE');
  return output;
}

function pathCase(name, paths, marketing, product, storefront) {
  test(name, () => {
    const { repo, base } = fixture();
    for (const path of paths) {
      if (existsSync(join(repo, path))) appendFileSync(join(repo, path), '\n// test change\n');
      else put(repo, path);
    }
    commit(repo);
    expectAll(repo, base, marketing, product, storefront);
  });
}

pathCase('01 marketing source only', ['site/src/main.js'], 'BUILD', 'IGNORE', 'IGNORE');
pathCase('02 POS runtime source only', ['apps/pos/lib/filter_fixture.dart'], 'IGNORE', 'BUILD', 'IGNORE');
pathCase('03 reachable Flutter package', ['packages/money/lib/filter_fixture.dart'], 'IGNORE', 'BUILD', 'IGNORE');
pathCase('04 marketing API and lead production inputs', ['site/api/lead.js', 'site/lib/lead.mjs'], 'BUILD', 'IGNORE', 'IGNORE');
pathCase('05 root Flutter lockfile', ['pubspec.lock'], 'IGNORE', 'BUILD', 'IGNORE');
pathCase('07 CI only', ['.github/workflows/ci.yml'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('08 documentation and audit only', ['docs/DEPLOYMENT.md', 'docs/audit/review.md'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('09 marketing tests and README only', ['site/tests/example.test.mjs', 'site/README.md'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('10 product tests only', ['apps/pos/test/example_test.dart', 'packages/money/test/example_test.dart'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('11 shared engine changes', [HELPER], 'BUILD', 'BUILD', 'BUILD');
pathCase('12 engine tests and documentation only', ['tools/vercel/ignore-build.test.mjs', 'docs/DEPLOYMENT.md'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('13 mixed marketing and product', ['site/src/main.js', 'apps/kds/lib/filter_fixture.dart'], 'BUILD', 'BUILD', 'IGNORE');
pathCase('copied marketing assets named README and test files remain production inputs', ['site/public/README.md', 'site/public/test/example.test.js'], 'BUILD', 'IGNORE', 'IGNORE');
pathCase('declared POS font asset', ['apps/pos/assets/fonts/Rubik-Regular.ttf'], 'IGNORE', 'BUILD', 'IGNORE');
pathCase('localized runtime source', ['packages/l10n/lib/src/generated/filter_fixture.dart'], 'IGNORE', 'BUILD', 'IGNORE');
pathCase('native Android and release tooling only', ['apps/pos/android/app/src/main/AndroidManifest.xml', 'tools/android_release/fixture.ps1'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('Admin and currently unused package code', ['apps/admin/lib/filter_fixture.dart', 'packages/feature_reporting/lib/filter_fixture.dart'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('unknown root control config builds conservatively', ['future-build.config.json'], 'BUILD', 'BUILD', 'BUILD');
pathCase('checkout-transform attributes are shared deployment control', ['.gitattributes'], 'BUILD', 'BUILD', 'BUILD');

test('04 marketing JSON config and package manifest', () => {
  const { repo, base } = fixture();
  const config = JSON.parse(readFileSync(join(repo, 'site/vercel.json'), 'utf8'));
  config.cleanUrls = !config.cleanUrls;
  put(repo, 'site/vercel.json', JSON.stringify(config));
  commit(repo);
  expectAll(repo, base, 'BUILD', 'IGNORE', 'IGNORE');
});

test('05 root Flutter manifest', () => {
  const { repo, base } = fixture();
  appendFileSync(join(repo, 'pubspec.yaml'), '\n# valid manifest change\n');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

test('06 every current workspace manifest affects resolution', () => {
  const { repo, base: initial } = fixture();
  for (const member of MEMBERS) {
    const base = runGit(repo, ['rev-parse', 'HEAD']);
    appendFileSync(join(repo, member, 'pubspec.yaml'), '\n# valid manifest change\n');
    commit(repo);
    expectDecision(repo, 'product', base, 'BUILD');
  }
  expectDecision(repo, 'marketing', initial, 'IGNORE');
});

test('14 earlier relevant commit survives docs-only final commit', () => {
  const { repo, base } = fixture();
  put(repo, 'site/src/earlier.js');
  commit(repo, 'earlier marketing change');
  put(repo, 'docs/final.md');
  commit(repo, 'final docs change');
  expectAll(repo, base, 'BUILD', 'IGNORE', 'IGNORE');
});

test('15 successful baseline spans intervening ignored and failed candidates', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/ignored.md');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'IGNORE');
  put(repo, 'apps/pos/lib/earlier.dart');
  commit(repo, 'candidate that was not successfully deployed');
  put(repo, 'docs/final.md');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

test('16 deletion of relevant input', () => {
  const { repo, base } = fixture();
  unlinkSync(join(repo, 'apps/pos/lib/filter_fixture.dart'));
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

for (const [label, from, to] of [
  ['runtime to docs', 'apps/pos/lib/filter_fixture.dart', 'docs/moved.dart'],
  ['docs to runtime', 'docs/DEPLOYMENT.md', 'apps/pos/lib/moved.md'],
]) {
  test(`17 rename ${label} checks both paths`, () => {
    const { repo, base } = fixture();
    mkdirSync(dirname(join(repo, to)), { recursive: true });
    renameSync(join(repo, from), join(repo, to));
    commit(repo);
    expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
  });
}

test('18 non-ancestor previous SHA compares both trees, including removed former runtime input', () => {
  const { repo, base } = fixture();
  runGit(repo, ['checkout', '--quiet', '-b', 'earlier-deployment']);
  put(repo, 'apps/pos/lib/earlier.dart');
  const nonAncestor = commit(repo);
  runGit(repo, ['checkout', '--quiet', 'main']);
  put(repo, 'docs/rebased.md');
  commit(repo);
  assert.equal(runGit(repo, ['merge-base', nonAncestor, 'HEAD']), base);
  expectAll(repo, nonAncestor, 'IGNORE', 'BUILD', 'IGNORE');
});

test('19 complete feature branch uses the exact local origin/main tree', () => {
  const { repo, base } = fixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', base]);
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/site-fixture']);
  put(repo, 'site/src/fallback.js');
  commit(repo);
  attachOrigin(repo);
  expectAll(repo, undefined, 'BUILD', 'IGNORE', 'IGNORE', { env: { VERCEL_GIT_PULL_REQUEST_ID: '123' } });
});

test('19 missing prior SHA may ignore a docs-only preview against exact origin/main', () => {
  const { repo, base } = fixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', base]);
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/docs-fixture']);
  put(repo, 'docs/fallback.md');
  commit(repo);
  attachOrigin(repo);
  expectAll(repo, undefined, 'IGNORE', 'IGNORE', 'IGNORE', { env: { VERCEL_GIT_PULL_REQUEST_ID: '123' } });
});

test('19 first-preview fallback does not depend on PR metadata and rejects non-preview contexts', () => {
  const { repo, base } = fixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', base]);
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/context-fixture']);
  put(repo, 'docs/fallback.md');
  commit(repo);
  attachOrigin(repo);
  for (const context of [
    { VERCEL_GIT_PULL_REQUEST_ID: '' },
    { VERCEL_GIT_PULL_REQUEST_ID: CANARY },
    { VERCEL_GIT_PULL_REQUEST_ID: '0' },
  ]) expectAll(repo, undefined, 'IGNORE', 'IGNORE', 'IGNORE', { env: context });
  for (const environment of ['production', 'development', '']) {
    expectAll(repo, undefined, 'BUILD', 'BUILD', 'BUILD', { env: { VERCEL_ENV: environment } });
  }
});

test('19 unavailable origin/main fails safely with no configured origin', () => {
  const { repo } = fixture();
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/no-base']);
  put(repo, 'docs/only.md');
  commit(repo);
  expectAll(repo, undefined, 'BUILD', 'BUILD', 'BUILD', { env: { VERCEL_GIT_PULL_REQUEST_ID: '123' } });
});

test('20 missing previous commit in complete history builds safely', () => {
  const { repo } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  expectAll(repo, 'a'.repeat(40), 'BUILD', 'BUILD', 'BUILD');
});

test('20 shallow repository can compare already available exact endpoint trees', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  put(repo, '.git/shallow', base + '\n');
  assert.equal(runGit(repo, ['rev-parse', '--is-shallow-repository']), 'true');
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'IGNORE');
});

test('20 Git unavailable produces a sanitized BUILD decision', () => {
  const { repo, base } = fixture();
  expectAll(repo, base, 'BUILD', 'BUILD', 'BUILD', { noGit: true });
});

test('21 first production deployment has no trustworthy fallback', () => {
  const { repo } = fixture();
  expectAll(repo, undefined, 'BUILD', 'BUILD', 'BUILD', { env: { VERCEL_ENV: 'production' } });
});

test('22 marketing executes correctly from site Root Directory', () => {
  const { repo, base } = fixture();
  put(repo, 'site/src/changed.js');
  commit(repo);
  expectDecision(repo, 'marketing', base, 'BUILD', { cwd: join(repo, 'site') });
  expectDecision(repo, 'product', base, 'IGNORE', { cwd: repo });
});

test('invalid selector or unexpected cwd produces BUILD', () => {
  const { repo, base } = fixture();
  expectDecision(repo, CANARY, base, 'BUILD');
  expectDecision(repo, 'product', base, 'BUILD', { cwd: join(repo, 'site') });
  expectDecision(repo, 'marketing', base, 'BUILD', { cwd: join(repo, 'apps/pos') });
});

const shellPath = process.platform === 'win32'
  ? ['C:/Program Files/Git/bin/bash.exe', 'C:/Program Files/Git/usr/bin/bash.exe'].find(existsSync)
  : '/bin/sh';

test('source wrappers normalize missing helper and missing Node to BUILD1', { skip: !shellPath ? 'Git Bash unavailable; exercised on Linux CI' : false }, () => {
  const { repo, base } = fixture();
  const commands = [
    { path: 'vercel.json', cwd: repo },
    { path: 'site/vercel.json', cwd: join(repo, 'site') },
    { path: 'storefront/vercel.json', cwd: join(repo, 'storefront') },
  ].map(({ path, cwd }) => ({ cwd, command: JSON.parse(readFileSync(join(repo, path), 'utf8')).ignoreCommand }));
  for (const { command } of commands) assert.match(command, /^if node .+; then exit 0; else exit 1; fi$/);
  for (const { command, cwd } of commands) {
    const valid = spawnSync(shellPath, ['-c', command], {
      cwd, env: { ...safeEnv, VERCEL_GIT_PREVIOUS_SHA: base, VERCEL_GIT_COMMIT_SHA: base },
      encoding: 'utf8', windowsHide: true, timeout: 15_000,
    });
    assert.equal(valid.error, undefined);
    assert.equal(valid.status, 0, 'real IGNORE must survive the source shell wrapper');
    assert.equal(JSON.parse(valid.stdout).decision, 'IGNORE');
  }
  renameSync(join(repo, HELPER), join(repo, HELPER + '.unavailable'));
  for (const { command, cwd } of commands) {
    const missingHelper = spawnSync(shellPath, ['-c', command], { cwd, env: safeEnv, encoding: 'utf8', windowsHide: true, timeout: 15_000 });
    assert.equal(missingHelper.error, undefined);
    assert.equal(missingHelper.status, 1);
    const emptyPath = { ...safeEnv };
    for (const key of Object.keys(emptyPath)) if (/^path$/i.test(key)) delete emptyPath[key];
    emptyPath.PATH = '/no-executables';
    const missingNode = spawnSync(shellPath, ['-c', command], { cwd, env: emptyPath, encoding: 'utf8', windowsHide: true, timeout: 15_000 });
    assert.equal(missingNode.error, undefined);
    assert.equal(missingNode.status, 1);
  }
});

test('invalid previous SHA forms are never accepted or echoed', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  for (const previous of [CANARY, ` ${base}`, `${base}\n`, 'HEAD^', `${base}^{tree}`, '--help']) {
    expectAll(repo, previous, 'BUILD', 'BUILD', 'BUILD');
  }
});

test('invalid or mismatched advertised HEAD never silently skips', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  for (const advertised of [CANARY, base, 'a'.repeat(40)]) {
    expectAll(repo, base, 'BUILD', 'BUILD', 'BUILD', { env: { VERCEL_GIT_COMMIT_SHA: advertised } });
  }
});

test('equal previous and HEAD is a complete empty diff', () => {
  const { repo, base } = fixture();
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'IGNORE');
});

test('missing or malformed workspace manifest never silently omits dependencies', () => {
  for (const mutation of ['delete', 'malformed']) {
    const { repo, base } = fixture();
    if (mutation === 'delete') unlinkSync(join(repo, 'packages/money/pubspec.yaml'));
    else put(repo, 'packages/money/pubspec.yaml', `name: restoflow_money\ndependencies: {${CANARY}\n`);
    commit(repo);
    expectDecision(repo, 'product', base, 'BUILD');
  }
});

test('malformed baseline graph also fails safely', () => {
  const { repo } = fixture({ seed(repo) { put(repo, 'packages/money/pubspec.yaml', 'name: restoflow_money\ndependencies: [not supported]\n'); } });
  const base = runGit(repo, ['rev-parse', 'HEAD']);
  put(repo, 'packages/money/pubspec.yaml', manifestTexts.get('packages/money'));
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('persistent malformed graph blocks an otherwise docs-only ignore', () => {
  const { repo, base } = fixture({ seed(repo) { put(repo, 'packages/core/pubspec.yaml', `name: restoflow_core\ndependencies: {${CANARY}\n`); } });
  put(repo, 'docs/only.md');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('workspace dependency name/path mismatch cannot be treated as unrelated', () => {
  const { repo, base } = fixture({ seed(repo) {
    const text = manifestTexts.get('apps/pos').replace('path: ../../packages/money', 'path: ../../packages/feature_reporting');
    put(repo, 'apps/pos/pubspec.yaml', text);
  } });
  put(repo, 'docs/only.md');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('CRLF manifests and whitespace filenames preserve classification', () => {
  const { repo, base } = fixture({ seed(repo) {
    for (const member of MEMBERS) put(repo, `${member}/pubspec.yaml`, manifestTexts.get(member).replace(/\r?\n/g, '\r\n'));
  } });
  put(repo, 'site/public/a space README.md');
  commit(repo);
  expectAll(repo, base, 'BUILD', 'IGNORE', 'IGNORE');
});

test('NUL-safe diff supports newline and tab filenames', { skip: process.platform === 'win32' ? 'Windows filesystem disallows these POSIX filename characters' : false }, () => {
  const { repo, base } = fixture();
  put(repo, 'site/public/a\nREADME.md');
  put(repo, 'site/public/b\ttest.js');
  commit(repo);
  expectAll(repo, base, 'BUILD', 'IGNORE', 'IGNORE');
});

test('invalid UTF-8 path bytes fail safely', { skip: process.platform === 'win32' ? 'POSIX raw filename byte case' : false }, () => {
  const { repo, base } = fixture();
  const filename = Buffer.concat([Buffer.from(join(repo, 'site/public/') + '/'), Buffer.from([0xff]), Buffer.from('.txt')]);
  writeFileSync(filename, 'fixture');
  commit(repo);
  expectAll(repo, base, 'BUILD', 'BUILD', 'BUILD');
});

test('declared Flutter asset directories override docs and test exclusions', () => {
  const text = manifestTexts.get('apps/kiosk');
  assert.match(text, /assets\/fixtures\//);
  const { repo, base } = fixture();
  put(repo, 'apps/kiosk/assets/fixtures/README.md');
  put(repo, 'apps/kiosk/assets/fixtures/test/data.json');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

test('new declared test-directory asset takes priority after its manifest baseline', () => {
  const { repo, base } = fixture({ seed(repo) {
    const manifest = manifestTexts.get('apps/pos').replace(/^flutter:\s*\r?$/m, 'flutter:\n  assets:\n    - test/deploy_assets/');
    put(repo, 'apps/pos/pubspec.yaml', manifest);
    put(repo, 'apps/pos/test/deploy_assets/README.md');
  } });
  appendFileSync(join(repo, 'apps/pos/test/deploy_assets/README.md'), 'changed\n');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

test('declared shared marketing asset affects both projects', () => {
  const { repo, base } = fixture({ seed(repo) {
    const manifest = manifestTexts.get('apps/pos').replace(/^flutter:\s*\r?$/m, 'flutter:\n  assets:\n    - ../../site/public/license.md');
    put(repo, 'apps/pos/pubspec.yaml', manifest);
  } });
  appendFileSync(join(repo, 'site/public/license.md'), 'changed\n');
  commit(repo);
  expectAll(repo, base, 'BUILD', 'BUILD', 'IGNORE');
});

test('23 actual build roots and full runtime graph remain covered', () => {
  const script = readFileSync(join(SOURCE_ROOT, 'tools/vercel_build_web.sh'), 'utf8');
  const actualApps = [...script.matchAll(/^\(cd (apps\/[A-Za-z0-9_-]+) &&.* build web /gm)].map((match) => match[1]);
  assert.deepEqual(actualApps.sort(), [...APP_ROOTS].sort(), 'new deployed app requires filter/test review');
  const closure = runtimeGraph();
  assert.deepEqual([...closure].filter((path) => path.startsWith('packages/')).sort(), EXPECTED_RUNTIME_PACKAGES, 'new runtime dependency requires explicit graph review');
  const { repo, base: initial } = fixture();
  for (const member of MEMBERS) {
    const base = runGit(repo, ['rev-parse', 'HEAD']);
    appendFileSync(join(repo, member, 'lib/filter_fixture.dart'), '// changed\n');
    commit(repo);
    expectDecision(repo, 'product', base, closure.has(member) ? 'BUILD' : 'IGNORE');
  }
  expectDecision(repo, 'marketing', initial, 'IGNORE');
});

test('23 actual production imports participate in graph validation', () => {
  const { repo, base } = fixture({ realRuntime: true });
  put(repo, 'docs/only.md');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'IGNORE');
});

test('23 undeclared workspace import cannot hide behind an ignored package', () => {
  const { repo, base } = fixture({ seed(repo) {
    put(repo, 'apps/pos/lib/filter_fixture.dart', "import 'package:restoflow_feature_reporting/filter_fixture.dart';\n");
  } });
  appendFileSync(join(repo, 'packages/feature_reporting/lib/filter_fixture.dart'), '// undeclared input\n');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

for (const [name, directive] of [
  ['import', "import '../test/hidden.dart';"],
  ['multiline import', "import\n  '../test/hidden.dart';"],
  ['second import on one line', "import 'filter_fixture.dart'; import '../test/hidden.dart';"],
  ['comment-separated import', "import/* comment */'../test/hidden.dart';"],
  ['encoded relative import', "import '%2e%2e/test/hidden.dart';"],
  ['conditional import', "import 'filter_fixture.dart' if (dart.library.io) '../test/hidden.dart';"],
  ['export', "export '../test/hidden.dart';"],
  ['part', "part '../test/hidden.dart';"],
]) {
  test(`persistent Dart ${name} escaping lib fails before test-only ignore`, () => {
    const { repo, base } = fixture({ seed(repo) {
      put(repo, 'apps/pos/lib/escape.dart', directive + '\n');
      put(repo, 'apps/pos/test/hidden.dart', '// baseline\n');
    } });
    appendFileSync(join(repo, 'apps/pos/test/hidden.dart'), '// later source change\n');
    commit(repo);
    expectDecision(repo, 'product', base, 'BUILD');
  });
}

for (const [name, directive] of [
  ['multiline import', "import { x } from\n'../tests/helper.mjs';"],
  ['side-effect import newline', "import\n'../tests/helper.mjs';"],
  ['comment-separated import', "import { x } from/* comment */'../tests/helper.mjs';"],
  ['encoded relative import', "import { x } from '%2e%2e/tests/helper.mjs';"],
  ['dynamic import', "const loaded = import('../tests/helper.mjs');"],
]) {
  test(`persistent marketing ${name} escaping source fails before test-only ignore`, () => {
    const { repo, base } = fixture({ seed(repo) {
      put(repo, 'site/src/escape.mjs', directive + '\n');
      put(repo, 'site/tests/helper.mjs', 'export const x = 1;\n');
    } });
    appendFileSync(join(repo, 'site/tests/helper.mjs'), '// later source change\n');
    commit(repo);
    expectDecision(repo, 'marketing', base, 'BUILD');
  });
}

for (const overridePath of ['pubspec_overrides.yaml', 'apps/pos/pubspec_overrides.yaml']) {
  test(`persistent ${overridePath} cannot create unwatched product inputs`, () => {
    const { repo, base } = fixture({ seed(repo) { put(repo, overridePath, 'dependency_overrides:\n  restoflow_money:\n    path: packages/feature_reporting\n'); } });
    put(repo, 'docs/only.md');
    commit(repo);
    expectDecision(repo, 'product', base, 'BUILD');
  });
}

test('persistent marketing includeFiles outside the input contract fails safely', () => {
  const { repo, base } = fixture({ seed(repo) {
    const config = JSON.parse(readFileSync(join(repo, 'site/vercel.json'), 'utf8'));
    config.functions = { 'api/lead.js': { includeFiles: 'docs/**' } };
    put(repo, 'site/vercel.json', JSON.stringify(config));
    put(repo, 'site/docs/included.md');
  } });
  appendFileSync(join(repo, 'site/docs/included.md'), 'changed\n');
  commit(repo);
  expectDecision(repo, 'marketing', base, 'BUILD');
});

test('persistent custom product builds cannot make tools silently irrelevant', () => {
  const { repo, base } = fixture({ seed(repo) {
    const config = JSON.parse(readFileSync(join(repo, 'vercel.json'), 'utf8'));
    config.builds = [{ src: 'tools/runtime-input.js', use: '@vercel/node' }];
    put(repo, 'vercel.json', JSON.stringify(config));
    put(repo, 'tools/runtime-input.js');
  } });
  appendFileSync(join(repo, 'tools/runtime-input.js'), '// changed\n');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('persistent automatic root API cannot make documentation a hidden runtime input', () => {
  const { repo, base } = fixture({ seed(repo) {
    put(repo, 'api/review.js', "import { value } from '../docs/runtime.mjs';\nexport default () => value;\n");
    put(repo, 'docs/runtime.mjs', 'export const value = 1;\n');
  } });
  put(repo, 'docs/runtime.mjs', 'export const value = 2;\n');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('persistent automatic site middleware cannot hide a docs-only runtime change', () => {
  const { repo, base } = fixture({ seed(repo) {
    put(repo, 'site/middleware.js', "import { value } from './docs/runtime.mjs';\nexport default () => value;\n");
    put(repo, 'site/docs/runtime.mjs', 'export const value = 1;\n');
  } });
  put(repo, 'site/docs/runtime.mjs', 'export const value = 2;\n');
  commit(repo);
  expectDecision(repo, 'marketing', base, 'BUILD');
});

test('persistent Flutter generation cannot make test-directory ARB inputs invisible', () => {
  const { repo, base } = fixture({ seed(repo) {
    const manifest = manifestTexts.get('packages/l10n').replace('generate: false', 'generate: true');
    put(repo, 'packages/l10n/pubspec.yaml', manifest);
    put(repo, 'packages/l10n/l10n.yaml', 'arb-dir: test/l10n\n');
    put(repo, 'packages/l10n/test/l10n/app_en.arb', '{"message":"baseline"}\n');
  } });
  put(repo, 'packages/l10n/test/l10n/app_en.arb', '{"message":"changed"}\n');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('23 new transitive dependency cannot hide a later source-only change', () => {
  const { repo, base } = fixture();
  let core = manifestTexts.get('packages/core');
  const edge = '  restoflow_feature_reporting:\n    path: ../feature_reporting\n';
  core = /^dependencies:/m.test(core) ? core.replace(/^dependencies:\s*\r?$/m, 'dependencies:\n' + edge) : core + '\ndependencies:\n' + edge;
  put(repo, 'packages/core/pubspec.yaml', core);
  const deployedGraph = commit(repo, 'new graph already deployed');
  expectDecision(repo, 'product', base, 'BUILD');
  appendFileSync(join(repo, 'packages/feature_reporting/lib/filter_fixture.dart'), '// new reachable runtime\n');
  commit(repo);
  expectDecision(repo, 'product', deployedGraph, 'BUILD');
});

test('23 removed runtime edge is visible from the baseline tree', () => {
  const { repo, base } = fixture();
  for (const [member, text] of manifestTexts) {
    put(repo, `${member}/pubspec.yaml`, text.replace(/^  restoflow_money:\r?\n    path: [^\r\n]+\r?\n/gm, ''));
  }
  appendFileSync(join(repo, 'packages/money/lib/filter_fixture.dart'), '// removal affects old graph\n');
  commit(repo);
  expectDecision(repo, 'product', base, 'BUILD');
});

test('R2-01 shallow checkout uses an already available previous-success tree without fetching', () => {
  const { repo, base } = shallowFixture({ depth: 2 });
  assert.equal(commitAvailable(repo, base), true);
  const trace = traceOptions();
  for (const selector of ['marketing', 'product']) {
    const output = expectDecision(repo, selector, base, 'IGNORE', { env: trace.env });
    assertBaseline(output, base, 'previous_success', false);
  }
  assert.deepEqual(fetchCommands(trace), []);
});

test('R2-02 shallow checkout fetches only the exact missing previous-success SHA', () => {
  const { repo, base } = shallowFixture();
  assert.equal(commitAvailable(repo, base), false);
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', base, 'IGNORE', { env: trace.env });
  assertBaseline(output, base, 'previous_success', true);
  assert.equal(commitAvailable(repo, base), true);
  assertExactFetch(trace, base);
  assert.equal(runGit(repo, ['rev-parse', '--is-shallow-repository']), 'true');
});

test('R2-03 failed exact previous-success fetch returns BUILD without another baseline', () => {
  const { repo, base } = shallowFixture();
  fixtureSources.set(repo, pathToFileURL(join(scratch, 'missing-source.git')).href);
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', base, 'BUILD', { env: trace.env });
  assert.equal(output.fetched, true, 'attempted failed fetch is still disclosed');
  assert.equal(output.baseline, null);
  assert.equal(commitAvailable(repo, base), false);
  assertExactFetch(trace, base);
});

test('R2-04 invalid previous SHA is rejected before fetching or consulting main', () => {
  const { repo, base } = shallowFixture();
  const trace = traceOptions();
  for (const previous of [CANARY, `${base}\n`, ` ${base}`, `${base}^{commit}`, '--all', 'a'.repeat(39)]) {
    const output = expectDecision(repo, 'product', previous, 'BUILD', { env: trace.env });
    assert.equal(output.fetched, false);
  }
  runGit(repo, ['tag', '--annotate', 'invalid-object-type', '--message', 'fixture annotated tag', 'HEAD']);
  const tagObject = runGit(repo, ['rev-parse', 'refs/tags/invalid-object-type']);
  assert.equal(runGit(repo, ['cat-file', '-t', tagObject]), 'tag');
  const wrongType = expectDecision(repo, 'product', tagObject, 'BUILD', { env: trace.env });
  assert.equal(wrongType.fetched, false, 'known local tag object is invalid, not a missing baseline');
  assert.deepEqual(fetchCommands(trace), []);
});

test('R2-05 non-ancestor previous success compares exact trees even after a shallow fetch', () => {
  const { repo: source, base: common } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'previous-success']);
  put(source, 'docs/previous.md');
  const base = commit(source);
  runGit(source, ['checkout', '--quiet', 'main']);
  runGit(source, ['checkout', '--quiet', '-b', 'feature/r2']);
  put(source, 'docs/rebased.md');
  commit(source);
  assert.equal(runGit(source, ['merge-base', base, 'HEAD']), common);
  const remote = attachOrigin(source);
  const repo = cloneOrigin(remote);
  assert.equal(commitAvailable(repo, base), false);
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', base, 'IGNORE', { env: trace.env });
  assertBaseline(output, base, 'previous_success', true);
  assertExactFetch(trace, base);
  expectDecision(repo, 'marketing', base, 'IGNORE');
});

test('R2-06 first shallow preview fetches the exact main tree with no PR-ID requirement', () => {
  const { repo, base } = shallowFixture({ changes: [['site/src/r2.js']] });
  assert.ok(!runGit(repo, ['for-each-ref', '--format=%(refname)']).includes('refs/remotes/origin/main'));
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', undefined, 'IGNORE', { env: trace.env });
  assertBaseline(output, base, 'production_main', true);
  assertExactFetch(trace, 'refs/heads/main');
  const site = expectDecision(repo, 'marketing', undefined, 'BUILD');
  assertBaseline(site, base, 'production_main', true);
});

test('R2-07 unavailable main or unsupported production-branch contract returns BUILD', () => {
  const { repo, remote } = shallowFixture();
  runGit(scratch, ['--git-dir=' + remote, 'update-ref', '-d', 'refs/heads/main']);
  const trace = traceOptions();
  const missing = expectDecision(repo, 'product', undefined, 'BUILD', { env: trace.env });
  assert.equal(missing.fetched, true);
  assert.equal(missing.baseline, null);
  assertExactFetch(trace, 'refs/heads/main');

  const guarded = shallowFixture();
  put(guarded.repo, '.github/workflows/ci.yml', 'name: changed\non:\n  push:\n    branches: [release]\n');
  commit(guarded.repo);
  const guardTrace = traceOptions();
  expectAll(guarded.repo, undefined, 'BUILD', 'BUILD', 'BUILD', { env: guardTrace.env });
  assert.deepEqual(fetchCommands(guardTrace), [], 'source must establish main before network acquisition');

  const detached = shallowFixture();
  runGit(detached.repo, ['checkout', '--quiet', '--detach']);
  const refTrace = traceOptions();
  for (const ref of ['feature/r2\n', 'main\n', 'foo//bar', 'foo.lock']) {
    const output = expectDecision(detached.repo, 'product', undefined, 'BUILD', {
      env: { ...refTrace.env, VERCEL_GIT_COMMIT_REF: ref },
    });
    assert.equal(output.fetched, false, 'invalid detached feature context must fail before fetch');
  }
  assert.deepEqual(fetchCommands(refTrace), []);
});

test('R2-08 production without a previous success always BUILDs without a fetch', () => {
  const { repo } = shallowFixture();
  const trace = traceOptions();
  for (const selector of ['marketing', 'product']) {
    const output = expectDecision(repo, selector, undefined, 'BUILD', { env: { ...trace.env, VERCEL_ENV: 'production' } });
    assert.equal(output.fetched, false);
    assert.equal(output.baseline, null);
  }
  assert.deepEqual(fetchCommands(trace), []);
});

test('R2-09 docs-only existing shallow branch ignores both projects', () => {
  const { repo, base } = shallowFixture({ changes: [['docs/DEPLOYMENT.md', 'docs/audit/r2.md']] });
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'IGNORE');
});

test('R2-10 marketing-only existing shallow branch builds only marketing', () => {
  const { repo, base } = shallowFixture({ changes: [['site/src/r2.js', 'site/public/r2.md']] });
  expectAll(repo, base, 'BUILD', 'IGNORE', 'IGNORE');
});

test('R2-11 product-only existing shallow branch builds only product', () => {
  const { repo, base } = shallowFixture({ changes: [['apps/pos/lib/r2.dart', 'packages/money/lib/r2.dart']] });
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

test('R2-12 multi-commit shallow branch includes earlier runtime changes in the tree delta', () => {
  const { repo, base } = shallowFixture({ changes: [['apps/kds/lib/earlier.dart'], ['docs/middle.md'], ['docs/final.md']] });
  expectAll(repo, base, 'IGNORE', 'BUILD', 'IGNORE');
});

test('R2-13 ignored candidates never replace the supplied previous-success baseline', () => {
  const { repo: source, base } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'feature/r2']);
  put(source, 'site/src/not-yet-successful.js');
  commit(source);
  put(source, 'docs/ignored-one.md');
  const intervening = commit(source);
  put(source, 'docs/ignored-two.md');
  commit(source);
  const remote = attachOrigin(source);
  const repo = cloneOrigin(remote);
  const output = expectDecision(repo, 'marketing', base, 'BUILD');
  assertBaseline(output, base, 'previous_success', true);
  assert.notEqual(output.baseline, intervening);
  expectDecision(repo, 'product', base, 'IGNORE');
});

test('R2-14 exact previous and main fetches preserve all refs, HEAD, index and worktree files', () => {
  const { repo, base } = shallowFixture();
  appendFileSync(join(repo, 'docs/DEPLOYMENT.md'), 'uncommitted local edit\n');
  put(repo, 'docs/untracked-r2.md', CANARY + '\n');
  const before = worktreeSnapshot(repo);
  const previous = expectDecision(repo, 'product', base, 'IGNORE');
  assertBaseline(previous, base, 'previous_success', true);
  assert.deepEqual(worktreeSnapshot(repo), before);
  const main = expectDecision(repo, 'marketing', undefined, 'IGNORE');
  assertBaseline(main, base, 'production_main', true);
  assert.deepEqual(worktreeSnapshot(repo), before);
});

test('R2-15 failed source and credential-bearing checkout origin are redacted', () => {
  const { repo, base } = shallowFixture();
  runGit(repo, ['remote', 'set-url', 'origin', `https://fixture-user:${CANARY}@example.invalid/repo.git`]);
  fixtureSources.set(repo, pathToFileURL(join(scratch, CANARY + '-missing.git')).href);
  // The missing owned file source fails; the checkout origin is irrelevant.
  const output = expectDecision(repo, 'product', base, 'BUILD');
  assert.equal(output.fetched, true);
  assert.equal(output.baseline, null);
  assert.ok(!JSON.stringify(output).includes('example.invalid'));
  assert.ok(!JSON.stringify(output).includes('fixture-user'));
});

test('R2-16 first preview behind main refreshes stale origin/main and sees runtime removals', () => {
  const { repo: source, base } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'feature/r2']);
  put(source, 'docs/preview.md');
  commit(source);
  runGit(source, ['checkout', '--quiet', 'main']);
  put(source, 'apps/pos/lib/newer-main.dart');
  const currentMain = commit(source);
  const remote = attachOrigin(source);
  const repo = cloneOrigin(remote);
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', runGit(repo, ['rev-parse', 'HEAD'])]);
  const stale = runGit(repo, ['rev-parse', 'refs/remotes/origin/main']);
  assert.notEqual(stale, currentMain);
  assert.notEqual(base, currentMain);
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', undefined, 'BUILD', { env: trace.env });
  assertBaseline(output, currentMain, 'production_main', true);
  assertExactFetch(trace, 'refs/heads/main');
  assert.equal(runGit(repo, ['rev-parse', 'refs/remotes/origin/main']), stale, 'refresh must not move remote-tracking refs');
  expectDecision(repo, 'marketing', undefined, 'IGNORE');
});

test('R2-17 shallow root and site working directories both fetch the correct baseline', () => {
  const { repo, remote, base } = shallowFixture({ changes: [['site/src/cwd.js']] });
  const siteRepo = cloneOrigin(remote);
  const product = expectDecision(repo, 'product', base, 'IGNORE', { cwd: repo });
  assertBaseline(product, base, 'previous_success', true);
  const marketing = expectDecision(siteRepo, 'marketing', base, 'BUILD', { cwd: join(siteRepo, 'site') });
  assertBaseline(marketing, base, 'previous_success', true);
});

test('R3-21 failed PR #277 replay: missing ref, detached shallow docs-only first Preview', () => {
  const { repo, base } = shallowFixture({ changes: [['docs/DEPLOYMENT.md']] });
  runGit(repo, ['checkout', '--quiet', '--detach']);
  assert.equal(runGit(repo, ['branch', '--show-current']), '');
  for (const selector of ['marketing', 'product']) {
    const trace = traceOptions();
    const output = expectDecision(repo, selector, undefined, 'IGNORE', {
      absentEnv: ['VERCEL_GIT_COMMIT_REF', 'VERCEL_GIT_PREVIOUS_SHA'], env: trace.env,
    });
    assert.equal(output.reason, 'unaffected_changes');
    assertBaseline(output, base, 'production_main', true);
    assertExactFetch(trace, 'refs/heads/main');
  }
});

test('R3-01 missing optional ref uses main even when HEAD is attached', () => {
  const { repo, base } = shallowFixture();
  const output = expectDecision(repo, 'product', undefined, 'IGNORE', { absentEnv: ['VERCEL_GIT_COMMIT_REF'] });
  assertBaseline(output, base, 'production_main', true);
});

test('R3-02 detached HEAD with empty optional ref uses main', () => {
  const { repo, base } = shallowFixture();
  runGit(repo, ['checkout', '--quiet', '--detach']);
  const output = expectDecision(repo, 'product', undefined, 'IGNORE');
  assertBaseline(output, base, 'production_main', true);
});

test('R3-03 valid optional ref does not require a matching local symbolic branch', () => {
  const { repo, base } = shallowFixture();
  const options = { env: { VERCEL_GIT_COMMIT_REF: 'verify/vercel-first-preview-docs-only' } };
  assertBaseline(expectDecision(repo, 'product', undefined, 'IGNORE', options), base, 'production_main', true);
  runGit(repo, ['checkout', '--quiet', '--detach']);
  assertBaseline(expectDecision(repo, 'marketing', undefined, 'IGNORE', options), base, 'production_main', true);
});

test('R3-04 matching or absent optional exposed SHA allows verified HEAD', () => {
  const { repo, base } = shallowFixture();
  assertBaseline(expectDecision(repo, 'product', undefined, 'IGNORE'), base, 'production_main', true);
  assertBaseline(expectDecision(repo, 'marketing', undefined, 'IGNORE', {
    absentEnv: ['VERCEL_GIT_COMMIT_SHA', 'VERCEL_GIT_COMMIT_REF'],
  }), base, 'production_main', true);
});

test('R3-05 mismatched or malformed exposed SHA BUILDs before fetch', () => {
  const { repo, base } = shallowFixture();
  const trace = traceOptions();
  for (const sha of [base, CANARY, '--all', `${base}\n`]) {
    const output = expectDecision(repo, 'product', undefined, 'BUILD', { env: { ...trace.env, VERCEL_GIT_COMMIT_SHA: sha } });
    assert.equal(output.reason, 'head_mismatch');
    assert.equal(output.fetched, false);
  }
  assert.deepEqual(fetchCommands(trace), []);
});

test('R3-06 malformed or contradictory optional refs BUILD without choosing fetch targets', () => {
  const { repo } = shallowFixture();
  const trace = traceOptions();
  for (const ref of ['main', 'HEAD', '--all', '../main', 'foo//bar', 'foo.lock', 'x\n', 'x\r', 'x@{1}', 'x y']) {
    const output = expectDecision(repo, 'product', undefined, 'BUILD', { env: { ...trace.env, VERCEL_GIT_COMMIT_REF: ref } });
    assert.equal(output.reason, 'untrusted_feature_ref');
    assert.equal(output.fetched, false);
  }
  assert.deepEqual(fetchCommands(trace), []);
});

for (const [id, name, paths, site, product] of [
  ['12', 'docs-only', ['docs/DEPLOYMENT.md'], 'IGNORE', 'IGNORE'],
  ['13', 'marketing-only', ['site/src/r3.js'], 'BUILD', 'IGNORE'],
  ['14', 'product-only', ['apps/pos/lib/r3.dart'], 'IGNORE', 'BUILD'],
  ['15', 'mixed', ['site/src/r3.js', 'apps/pos/lib/r3.dart'], 'BUILD', 'BUILD'],
]) {
  test(`R3-${id} first Preview ${name} uses direct main-to-HEAD trees without ref env`, () => {
    const { repo, base } = shallowFixture({ changes: [paths] });
    for (const [selector, expected] of [['marketing', site], ['product', product]]) {
      const output = expectDecision(repo, selector, undefined, expected, { absentEnv: ['VERCEL_GIT_COMMIT_REF'] });
      assertBaseline(output, base, 'production_main', true);
      assert.equal(output.reason, expected === 'IGNORE' ? 'unaffected_changes' : 'relevant_changes');
    }
  });
}

test('R3-16 failed main acquisition BUILDs without using a stale local ref', () => {
  const { repo, remote } = shallowFixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  runGit(scratch, ['--git-dir=' + remote, 'update-ref', '-d', 'refs/heads/main']);
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', undefined, 'BUILD', { env: trace.env, absentEnv: ['VERCEL_GIT_COMMIT_REF'] });
  assert.equal(output.reason, 'baseline_fetch_failed');
  assertBaseline(output, null, 'production_main', true);
  assertExactFetch(trace, 'refs/heads/main');
});

test('R3-17 detached Preview behind main sees runtime changes absent from HEAD', () => {
  const { repo: source } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'feature/r2']);
  put(source, 'docs/r3-behind.md');
  commit(source);
  runGit(source, ['checkout', '--quiet', 'main']);
  put(source, 'apps/pos/lib/main-only.dart');
  put(source, 'site/src/main-only.js');
  const base = commit(source);
  const remote = attachOrigin(source);
  const repo = cloneOrigin(remote);
  runGit(repo, ['checkout', '--quiet', '--detach']);
  for (const selector of ['marketing', 'product']) {
    assertBaseline(expectDecision(repo, selector, undefined, 'BUILD', { absentEnv: ['VERCEL_GIT_COMMIT_REF'] }), base, 'production_main', true);
  }
});

test('R3-18 previous success stays authoritative regardless of optional first-Preview metadata', () => {
  const { repo, base } = shallowFixture();
  runGit(repo, ['checkout', '--quiet', '--detach']);
  const output = expectDecision(repo, 'product', base, 'IGNORE', { env: { VERCEL_GIT_COMMIT_REF: '--invalid', VERCEL_ENV: 'production' } });
  assertBaseline(output, base, 'previous_success', true);
  runGit(repo, ['remote', 'set-url', 'origin', 'https://example.invalid/wrong.git']);
  assertBaseline(expectDecision(repo, 'marketing', base, 'IGNORE'), base, 'previous_success', false);
});

test('R3-19 first Production without ref or previous success always BUILDs', () => {
  const { repo } = shallowFixture();
  runGit(repo, ['checkout', '--quiet', '--detach']);
  for (const selector of ['marketing', 'product']) {
    const output = expectDecision(repo, selector, undefined, 'BUILD', {
      env: { VERCEL_ENV: 'production' }, absentEnv: ['VERCEL_GIT_COMMIT_REF', 'VERCEL_GIT_PREVIOUS_SHA'],
    });
    assert.equal(output.reason, 'missing_baseline');
    assertBaseline(output, null, null, false);
  }
});


for (const [id, origin] of [
  ['01', null],
  ['02', 'https://vercel-internal.invalid/clone/project-token'],
  ['03', 'https://github.com/another-owner/another-repo.git'],
]) {
  test('R4-' + id + ' first Preview docs ignores both independently of checkout origin', () => {
    const { repo, base } = shallowFixture();
    if (origin === null) runGit(repo, ['remote', 'remove', 'origin']);
    else runGit(repo, ['remote', 'set-url', 'origin', origin]);
    for (const selector of ['marketing', 'product']) {
      const trace = traceOptions();
      const output = expectDecision(repo, selector, undefined, 'IGNORE', { env: trace.env });
      assertBaseline(output, base, 'production_main', true);
      assert.equal(output.reason, 'unaffected_changes');
      assertExactFetch(trace, 'refs/heads/main', fixtureSources.get(repo));
      const log = readFileSync(trace.path, 'utf8');
      assert.ok(!/remote get-url|remote\.origin\.url/.test(log), 'no origin reads');
    }
  });
}

test('R4-04 non-shallow missing previous success also acquires the exact object', () => {
  const { repo: source } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'previous']);
  put(source, 'docs/previous.md');
  const base = commit(source);
  runGit(source, ['checkout', '--quiet', 'main']);
  const { repo } = fixture();
  const remote = attachOrigin(source);
  fixtureSources.set(repo, pathToFileURL(remote).href);
  assert.equal(commitAvailable(repo, base), false);
  assert.equal(runGit(repo, ['rev-parse', '--is-shallow-repository']), 'false');
  const trace = traceOptions();
  assertBaseline(expectDecision(repo, 'product', base, 'IGNORE', { env: trace.env }), base, 'previous_success', true);
  assertExactFetch(trace, base);
});

test('R4-19 first Preview runtime deletion and rename stay relevant', () => {
  const { repo: source } = fixture();
  runGit(source, ['checkout', '--quiet', '-b', 'feature/r2']);
  unlinkSync(join(source, 'site/api/lead.js'));
  renameSync(join(source, 'apps/pos/lib/filter_fixture.dart'), join(source, 'docs/moved.dart'));
  commit(source);
  const repo = cloneOrigin(attachOrigin(source));
  expectAll(repo, undefined, 'BUILD', 'BUILD', 'IGNORE');
});

test('R4-20 Git stderr and credential-bearing origin never escape on failed fetch', () => {
  const { repo } = shallowFixture();
  const origin = 'https://fixture-user:' + CANARY + '@internal.invalid/wrong.git';
  runGit(repo, ['remote', 'set-url', 'origin', origin]);
  // Git itself emits the canary from this missing local URL to its captured
  // stderr. No network or substitute Git executable is involved.
  const missing = pathToFileURL(join(scratch, CANARY + '-stderr.git')).href;
  fixtureSources.set(repo, missing);
  const raw = spawnSync('git', ['-C', repo, 'fetch', missing, 'refs/heads/main'], { env: safeEnv, encoding: 'utf8', windowsHide: true });
  assert.notEqual(raw.status, 0);
  assert.ok(raw.stderr.includes(CANARY));
  const result = invoke(repo, 'product');
  assert.equal(result.output.reason, 'baseline_fetch_failed');
  assert.ok(!result.stdout.includes('internal.invalid') && !result.stdout.includes('fixture-user'));
});

test('R4-21 PR #277 replay: detached first Preview, missing ref, docs-only', () => {
  const { repo, base } = shallowFixture();
  runGit(repo, ['checkout', '--quiet', '--detach']);
  runGit(repo, ['remote', 'remove', 'origin']);
  for (const selector of ['marketing', 'product']) {
    assertBaseline(expectDecision(repo, selector, undefined, 'IGNORE', {
      absentEnv: ['VERCEL_GIT_COMMIT_REF', 'VERCEL_GIT_PREVIOUS_SHA'],
    }), base, 'production_main', true);
  }
});

test('R4-22 R3 internal-origin blocker replay reaches shared-engine classification', () => {
  const { repo, base } = shallowFixture({ changes: [[HELPER]] });
  runGit(repo, ['checkout', '--quiet', '--detach']);
  runGit(repo, ['remote', 'set-url', 'origin', 'https://internal.invalid/' + CANARY]);
  for (const selector of ['marketing', 'product']) {
    const output = expectDecision(repo, selector, undefined, 'BUILD', { absentEnv: ['VERCEL_GIT_COMMIT_REF'] });
    assert.equal(output.reason, 'relevant_changes');
    assert.equal(output.categories.shared_engine, 1);
    assertBaseline(output, base, 'production_main', true);
  }
});

test('R4-23 canonical URL constant changes build both projects', () => {
  const { repo, base } = fixture();
  const text = readFileSync(join(repo, HELPER), 'utf8');
  assert.ok(text.includes("const TRUSTED_REPOSITORY_URL = '" + CANONICAL_SOURCE + "';"));
  put(repo, HELPER, text.replace(CANONICAL_SOURCE, 'https://github.com/reviewed/source-change.git'));
  commit(repo);
  for (const selector of ['marketing', 'product']) {
    const output = expectDecision(repo, selector, base, 'BUILD');
    assert.equal(output.categories.shared_engine, 1);
  }
});

test('R4 CLI ignores env source overrides and fetches only the canonical URL', () => {
  const { repo } = shallowFixture();
  runGit(repo, ['remote', 'remove', 'origin']);
  const trace = traceOptions();
  const output = expectDecision(repo, 'product', undefined, 'BUILD', { productionCli: true, env: {
    ...trace.env, TRUSTED_REPOSITORY_URL: fixtureSources.get(repo),
    VERCEL_GIT_REPO_URL: fixtureSources.get(repo), VERCEL_GIT_REPO_SLUG: CANARY,
  } });
  // HTTPS is forbidden by the fixture protocol allowlist, so this cannot
  // contact GitHub; a source override would incorrectly make it IGNORE.
  assert.equal(output.reason, 'baseline_fetch_failed');
  assertExactFetch(trace, 'refs/heads/main', CANONICAL_SOURCE);
});

test('R4 canonical URL cannot be redirected by checkout or environment Git rewrites', () => {
  const { repo } = shallowFixture();
  for (const mode of ['local', 'environment']) {
    const trace = traceOptions();
    const key = 'url.' + fixtureSources.get(repo) + '.insteadOf';
    const env = { ...trace.env };
    if (mode === 'local') runGit(repo, ['config', key, CANONICAL_SOURCE]);
    else Object.assign(env, { GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: key, GIT_CONFIG_VALUE_0: CANONICAL_SOURCE });
    const output = expectDecision(repo, 'product', undefined, 'BUILD', { productionCli: true, env });
    assert.equal(output.reason, 'baseline_source_rewritten');
    assert.equal(output.fetched, false);
    assert.deepEqual(fetchCommands(trace), []);
    if (mode === 'local') runGit(repo, ['config', '--unset-all', key]);
  }
});


// ---------------------------------------------------------------------------
// STOREFRONT-INFRA-001A — three-way filter. The storefront project does not
// exist yet; these cases are the contract it will be created against.
// ---------------------------------------------------------------------------

test('24 storefront executes correctly from storefront Root Directory', () => {
  const { repo, base } = fixture();
  put(repo, 'storefront/app/changed.tsx', 'export default function C() { return null; }\n');
  commit(repo);
  expectDecision(repo, 'storefront', base, 'BUILD', { cwd: join(repo, 'storefront') });
  // The repo root is the product Root Directory, so the storefront selector
  // there is invalid_cwd -> BUILD, never a silent IGNORE.
  expectDecision(repo, 'storefront', base, 'BUILD', { cwd: repo });
  expectDecision(repo, 'product', base, 'IGNORE', { cwd: repo });
});

pathCase('24 storefront runtime source only', ['storefront/app/page.tsx'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront aliased src module only', ['storefront/src/lib/hello.ts'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront messages only', ['storefront/messages/en.json'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront public asset only', ['storefront/public/icon.svg'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront lockfile only', ['storefront/package-lock.json'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront deployment config only', ['storefront/vercel.json'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront node pin only', ['storefront/.nvmrc'], 'IGNORE', 'IGNORE', 'BUILD');
pathCase('24 storefront tests and docs only ignore everywhere', ['storefront/tests/shell.test.mjs', 'storefront/README.md', 'storefront/.gitignore'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('24 storefront audit script only ignores everywhere', ['storefront/scripts/audit-output.mjs'], 'IGNORE', 'IGNORE', 'IGNORE');
pathCase('24 unknown storefront input builds the storefront only', ['storefront/whatever.cfg'], 'IGNORE', 'IGNORE', 'BUILD');

test('24 supabase-only changes ignore all three projects', () => {
  const { repo, base } = fixture();
  put(repo, 'supabase/migrations/20260101000000_fixture.sql', '-- fixture\n');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'IGNORE');
});

test('24 ci.yml step-only edits ignore all three on both baseline paths', () => {
  const previousSuccess = fixture();
  put(previousSuccess.repo, '.github/workflows/ci.yml', 'name: changed\non:\n  pull_request:\n  push:\n    branches: [main]\n');
  commit(previousSuccess.repo);
  expectAll(previousSuccess.repo, previousSuccess.base, 'IGNORE', 'IGNORE', 'IGNORE');
});

test('24 storefront guard failures all fail safe to BUILD', () => {
  // Each mutation is a separate fixture so one failure cannot mask another.
  const cases = [
    ['request-time entrypoint', (repo) => put(repo, 'storefront/middleware.ts', 'export function middleware() {}\n')],
    ['checkout override', (repo) => put(repo, 'storefront/.vercelignore', 'out\n')],
    ['changed next.config', (repo) => put(repo, 'storefront/next.config.mjs', STOREFRONT_NEXT_CONFIG.replace('export', 'standalone'))],
    ['missing lockfile', (repo) => unlinkSync(join(repo, 'storefront/package-lock.json'))],
    ['floating dependency range', (repo) => put(repo, 'storefront/package.json', JSON.stringify({ name: 'storefront', private: true, scripts: { build: 'next build' }, dependencies: { next: '^16.3.5' } }, null, 2) + '\n')],
    ['unlisted runtime dependency', (repo) => put(repo, 'storefront/package.json', JSON.stringify({ name: 'storefront', private: true, scripts: { build: 'next build' }, dependencies: { next: '16.3.5', lodash: '4.17.21' } }, null, 2) + '\n')],
    ['escaping relative import', (repo) => put(repo, 'storefront/app/page.tsx', "import x from '../../site/src/main.js';\nexport default function P() { return x; }\n")],
    ['disallowed bare import', (repo) => put(repo, 'storefront/app/page.tsx', "import x from 'lodash';\nexport default function P() { return x; }\n")],
    ['dynamic import', (repo) => put(repo, 'storefront/app/page.tsx', "export default async function P() { return import('./other'); }\n")],
    // Pre-fix this passed inspection outright: safeRelative normalises
    // storefront + ../site/src to site/src, which is not an escape, so only the
    // alias pin catches an alias aimed at another project.
    ['tsconfig alias escaping the root', (repo) => put(repo, 'storefront/tsconfig.json', json({ ...STOREFRONT_TSCONFIG, compilerOptions: { baseUrl: '.', paths: { '@/*': ['../site/src/*'] } } }))],
    // storefront/styles is a runtime root that an app module may import, so its
    // OWN imports have to be scanned as well, or it is an unchecked bridge from
    // the build graph into storefront/tests.
    ['a runtime root bridging into tests', (repo) => {
      put(repo, 'storefront/styles/theme.ts', "export { fixture } from '../tests/fixtures/data';\n");
      put(repo, 'storefront/app/page.tsx', "import { fixture } from '../styles/theme';\nexport default function P() { return fixture; }\n");
    }],
    ['oversized public asset', (repo) => put(repo, 'storefront/public/big.png', 'x'.repeat(300 * 1024))],
    ['video in public', (repo) => put(repo, 'storefront/public/clip.mp4', 'fixture\n')],
  ];
  for (const [label, mutate] of cases) {
    const { repo, base } = fixture();
    mutate(repo);
    commit(repo);
    // The storefront fails safe; the other two are unaffected by storefront/.
    expectDecision(repo, 'storefront', base, 'BUILD', { message: label });
    expectDecision(repo, 'marketing', base, 'IGNORE', { message: label });
    // Every file mutated above is itself a storefront runtime input, so the
    // classifier alone already answers BUILD and the assertions above would hold
    // with inspectStorefront deleted. Re-run each case where only the guard can
    // produce the BUILD.
    guardOnly(mutate, label);
  }
});

// STAGE 7 BLOCKER. Reported sequence: a tsconfig change puts storefront/tests
// into TypeScript's build graph and correctly BUILDs on its own commit, then a
// LATER tests-only .ts change is classified storefront_tests_docs and IGNOREd
// while `next build` still type-checks it. Pre-fix, every shape below passed
// inspection and returned IGNORE at step 3: a false IGNORE. The contract is now
// enforced, so the unsafe configuration cannot be silently ignored.
test('24 REGRESSION a tests-widening tsconfig cannot produce a tests-only IGNORE', () => {
  const unsafe = [
    // TypeScript's own default when include is omitted, written out.
    ['default **/* include', { ...STOREFRONT_TSCONFIG, include: ['**/*.ts', '**/*.tsx'] }],
    ['include omitted entirely', { compilerOptions: STOREFRONT_TSCONFIG.compilerOptions, exclude: ['tests'] }],
    ['whole Root Directory included', { ...STOREFRONT_TSCONFIG, include: ['.'] }],
    ['tests named in include', { ...STOREFRONT_TSCONFIG, include: ['app', 'src', 'tests'] }],
    ['a tests subdirectory included', { ...STOREFRONT_TSCONFIG, include: ['app', 'src', 'tests/unit'] }],
    // exclude is the only thing the fixture relied on, and it only subtracts.
    ['tests exclusion removed from a broad include', { ...STOREFRONT_TSCONFIG, include: ['.'], exclude: [] }],
    // files[] adds to the program independently of include.
    ['files[] naming a test setup', { ...STOREFRONT_TSCONFIG, files: ['tests/setup.ts'] }],
    // extends can inherit an include this parser never sees.
    ['include inherited through extends', { extends: './tests/tsconfig.base.json', include: ['app', 'src'] }],
    ['project references', { ...STOREFRONT_TSCONFIG, references: [{ path: './tests' }] }],
    // Ambient declarations enter the program without any import.
    ['typeRoots inside tests', { ...STOREFRONT_TSCONFIG, compilerOptions: { baseUrl: '.', typeRoots: ['./tests/types'] } }],
    ['types inside tests', { ...STOREFRONT_TSCONFIG, compilerOptions: { baseUrl: '.', types: ['./tests/globals'] } }],
    ['rootDirs reaching tests', { ...STOREFRONT_TSCONFIG, compilerOptions: { baseUrl: '.', rootDirs: ['./src', './tests'] } }],
    // The alias step 8 resolves as storefront/src, aimed at tests instead.
    ['alias remapped into tests', { ...STOREFRONT_TSCONFIG, compilerOptions: { baseUrl: '.', paths: { '@/*': ['./tests/*'] } } }],
  ];
  for (const [label, tsconfig] of unsafe) {
    const { repo } = fixture();
    // 1-2. The widening is committed. tsconfig.json is a storefront runtime
    //      input, so that commit BUILDs on its own, as the report describes.
    put(repo, 'storefront/tsconfig.json', json(tsconfig));
    const widened = commit(repo);
    // 3. A later commit changes ONLY a TypeScript file under storefront/tests.
    put(repo, 'storefront/tests/shell.spec.ts', 'export const probe = 1;\n');
    commit(repo);
    // 4. Classification alone says IGNORE here; inspection must override it.
    const result = expectDecision(repo, 'storefront', widened, 'BUILD');
    assert.ok(['unsupported_build_contract', 'unsupported_graph'].includes(result.reason),
      `${label}: expected the unsafe tsconfig to fail inspection, got ${result.reason}`);
    // The unsafe storefront contract must not leak into the other two projects.
    expectDecision(repo, 'marketing', widened, 'IGNORE');
    expectDecision(repo, 'product', widened, 'IGNORE');
  }
});

// The other half of the blocker, and the reason the fix is a proof rather than
// "BUILD on anything tsconfig-shaped": under a contract that provably excludes
// them, ignored storefront paths must still be ignored. Without this case,
// classifying storefront/tests as BUILD would also satisfy the regression above.
test('24 safe tsconfig shapes still ignore a tests-only TypeScript change', () => {
  const safe = [
    ['bare directories', ['app', 'src']],
    ['explicitly relative directories', ['./app', './src']],
    ['trailing globs under a safe root', ['app/**/*.tsx', 'src/**/*.ts']],
    // What `next build` writes back into tsconfig.json; both are generated,
    // neither overlaps an ignored root.
    ['next generated entries', ['next-env.d.ts', '.next/types/**/*.ts', 'app', 'src']],
  ];
  for (const [label, include] of safe) {
    const { repo } = fixture();
    put(repo, 'storefront/tsconfig.json', json({ ...STOREFRONT_TSCONFIG, include }));
    // A marker keeps the configuring commit non-empty: the first shape is
    // byte-identical to the fixture, and an empty commit aborts git.
    put(repo, 'docs/tsconfig-case.md', `# ${label}
`);
    const configured = commit(repo);
    put(repo, 'storefront/tests/shell.spec.ts', 'export const probe = 1;\n');
    put(repo, 'storefront/docs/notes.md', '# fixture\n');
    commit(repo);
    expectAll(repo, configured, 'IGNORE', 'IGNORE', 'IGNORE', { message: label });
  }
});

// Stage 7 hardening 1: allowed keys were not checked for approved VALUES. A
// foreign ignoreCommand means the project is filtered by something other than
// this engine; `exit 0` would make it never build at all.
test('24 storefront deployment values are pinned, not merely allowed', () => {
  const { outputDirectory, ignoreCommand, ...withoutBoth } = STOREFRONT_VERCEL;
  const cases = [
    ['a different outputDirectory', { ...STOREFRONT_VERCEL, outputDirectory: 'dist' }],
    ['outputDirectory omitted', { ...withoutBoth, ignoreCommand }],
    ['an always-ignore ignoreCommand', { ...STOREFRONT_VERCEL, ignoreCommand: 'exit 0' }],
    ['the marketing selector', { ...STOREFRONT_VERCEL, ignoreCommand: ignoreCommand.replace('storefront', 'marketing') }],
    ['a different engine path', { ...STOREFRONT_VERCEL, ignoreCommand: ignoreCommand.replace('../tools', '../other') }],
    ['ignoreCommand omitted', { ...withoutBoth, outputDirectory }],
  ];
  for (const [label, config] of cases) {
    guardOnly((repo) => put(repo, 'storefront/vercel.json', json(config)), label);
  }
});

// Stage 7 hardening 2: the runtime pin. No approved Node value exists to
// validate at 001A, so the Vercel project's Node.js Version setting stays
// authoritative (DEPLOYMENT.md §15) and the engine only bounds the shape. What
// matters for correctness is that neither file is ever read to decide relevance:
// both are storefront_runtime, so any edit BUILDs whatever it says.
test('24 the storefront Node pin is shape-bounded and never trusted for relevance', () => {
  const manifest = JSON.parse(STOREFRONT_FILES['storefront/package.json']);
  for (const [label, engines] of [
    ['a non-string node value', { node: 22 }],
    ['an unrecognised engine key', { node: '22.x', npm: '10.x' }],
    ['an array instead of an object', ['22.x']],
  ]) {
    guardOnly((repo) => put(repo, 'storefront/package.json', json({ ...manifest, engines })), label);
  }
  // A well-formed pin passes, and changing either file BUILDs the storefront
  // alone by classification — the value itself is never interpreted.
  const { repo, base } = fixture({ seed: (target) => put(target, 'storefront/package.json', json({ ...manifest, engines: { node: '22.x' } })) });
  put(repo, 'storefront/.nvmrc', '22\n');
  commit(repo);
  expectAll(repo, base, 'IGNORE', 'IGNORE', 'BUILD');
});

test('24 a baseline without storefront fails the storefront safe', () => {
  // The very first storefront Preview evaluated against a pre-001B main. It
  // cannot happen in the Option B sequence; pinned here rather than discovered
  // hosted.
  const { repo } = fixture();
  for (const file of Object.keys(STOREFRONT_FILES)) unlinkSync(join(repo, file));
  const withoutStorefront = commit(repo);
  for (const [file, text] of Object.entries(STOREFRONT_FILES)) put(repo, file, text);
  commit(repo);
  const result = expectDecision(repo, 'storefront', withoutStorefront, 'BUILD');
  assert.equal(result.reason, 'unsupported_build_contract');
});

test('24 same-tree storefront self-check ignores', () => {
  const { repo } = fixture();
  const head = runGit(repo, ['rev-parse', 'HEAD']);
  const result = expectDecision(repo, 'storefront', head, 'IGNORE');
  assert.equal(result.reason, 'no_changes');
});

test('24 misspelled storefront selector is an invalid selector', () => {
  const { repo, base } = fixture();
  expectDecision(repo, 'storefrnt', base, 'BUILD');
});
