import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
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

// No inherited credentials, Git configuration, proxy settings, or NODE_OPTIONS.
const safeEnv = {};
for (const [key, value] of Object.entries(process.env)) {
  if (/^(path|pathext|systemroot|windir|comspec|temp|tmp)$/i.test(key)) safeEnv[key] = value;
}
Object.assign(safeEnv, {
  GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: emptyGitConfig, GIT_CONFIG_SYSTEM: emptyGitConfig,
  GIT_TERMINAL_PROMPT: '0', GIT_AUTHOR_NAME: 'Filter fixture', GIT_COMMITTER_NAME: 'Filter fixture',
  GIT_AUTHOR_EMAIL: 'filter-fixture@example.invalid', GIT_COMMITTER_EMAIL: 'filter-fixture@example.invalid',
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
  put(repo, '.github/workflows/ci.yml', 'name: fixture\n');
  put(repo, 'tools/vercel/ignore-build.test.mjs', '// fixture suite\n');
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

function invoke(repo, selector, previous, options = {}) {
  const head = runGit(repo, ['rev-parse', 'HEAD']);
  const branch = runGit(repo, ['branch', '--show-current']);
  const env = {
    ...safeEnv, VERCEL_ENV: 'preview', VERCEL_GIT_COMMIT_REF: branch,
    VERCEL_GIT_COMMIT_SHA: head, VERCEL_GIT_PREVIOUS_SHA: previous || '',
    RESTOFLOW_SUPABASE_ANON_KEY: CANARY, RESEND_API_KEY: CANARY, VERCEL_TOKEN: CANARY,
    ...options.env,
  };
  if (options.noGit) {
    for (const key of Object.keys(env)) if (/^path$/i.test(key)) delete env[key];
    env.PATH = join(scratch, 'no-executables');
  }
  const cwd = options.cwd || (selector === 'marketing' ? join(repo, 'site') : repo);
  const result = spawnSync(process.execPath, [join(repo, HELPER), selector], { cwd, env, encoding: 'utf8', timeout: 15_000, windowsHide: true });
  assert.equal(result.error, undefined, 'helper must terminate without process error');
  assert.equal(result.signal, null);
  assert.ok([0, 1].includes(result.status), 'helper must normalize every exit to IGNORE0 or BUILD1');
  assert.ok(!result.stdout.includes(CANARY) && !result.stderr.includes(CANARY), 'synthetic secrets must never be logged');
  assert.equal(result.stderr, '', 'helper must not print raw diagnostics or exception text');
  const lines = result.stdout.trim().split(/\r?\n/);
  assert.equal(lines.length, 1, 'one JSON decision per invocation');
  const output = JSON.parse(lines[0]);
  assert.deepEqual(Object.keys(output).sort(), ['baseline', 'categories', 'decision', 'head', 'reason']);
  assert.equal(output.decision, result.status === 0 ? 'IGNORE' : 'BUILD');
  assert.match(output.reason, /^[a-zA-Z0-9_-]+$/, 'reason must be a bounded code, not error text');
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

function expectPair(repo, base, marketing, product, options) {
  expectDecision(repo, 'marketing', base, marketing, options);
  expectDecision(repo, 'product', base, product, options);
}

function pathCase(name, paths, marketing, product) {
  test(name, () => {
    const { repo, base } = fixture();
    for (const path of paths) {
      if (existsSync(join(repo, path))) appendFileSync(join(repo, path), '\n// test change\n');
      else put(repo, path);
    }
    commit(repo);
    expectPair(repo, base, marketing, product);
  });
}

pathCase('01 marketing source only', ['site/src/main.js'], 'BUILD', 'IGNORE');
pathCase('02 POS runtime source only', ['apps/pos/lib/filter_fixture.dart'], 'IGNORE', 'BUILD');
pathCase('03 reachable Flutter package', ['packages/money/lib/filter_fixture.dart'], 'IGNORE', 'BUILD');
pathCase('04 marketing API and lead production inputs', ['site/api/lead.js', 'site/lib/lead.mjs'], 'BUILD', 'IGNORE');
pathCase('05 root Flutter lockfile', ['pubspec.lock'], 'IGNORE', 'BUILD');
pathCase('07 CI only', ['.github/workflows/ci.yml'], 'IGNORE', 'IGNORE');
pathCase('08 documentation and audit only', ['docs/DEPLOYMENT.md', 'docs/audit/review.md'], 'IGNORE', 'IGNORE');
pathCase('09 marketing tests and README only', ['site/tests/example.test.mjs', 'site/README.md'], 'IGNORE', 'IGNORE');
pathCase('10 product tests only', ['apps/pos/test/example_test.dart', 'packages/money/test/example_test.dart'], 'IGNORE', 'IGNORE');
pathCase('11 shared engine changes', [HELPER], 'BUILD', 'BUILD');
pathCase('12 engine tests and documentation only', ['tools/vercel/ignore-build.test.mjs', 'docs/DEPLOYMENT.md'], 'IGNORE', 'IGNORE');
pathCase('13 mixed marketing and product', ['site/src/main.js', 'apps/kds/lib/filter_fixture.dart'], 'BUILD', 'BUILD');
pathCase('copied marketing assets named README and test files remain production inputs', ['site/public/README.md', 'site/public/test/example.test.js'], 'BUILD', 'IGNORE');
pathCase('declared POS font asset', ['apps/pos/assets/fonts/Rubik-Regular.ttf'], 'IGNORE', 'BUILD');
pathCase('localized runtime source', ['packages/l10n/lib/src/generated/filter_fixture.dart'], 'IGNORE', 'BUILD');
pathCase('native Android and release tooling only', ['apps/pos/android/app/src/main/AndroidManifest.xml', 'tools/android_release/fixture.ps1'], 'IGNORE', 'IGNORE');
pathCase('Admin and currently unused package code', ['apps/admin/lib/filter_fixture.dart', 'packages/feature_reporting/lib/filter_fixture.dart'], 'IGNORE', 'IGNORE');
pathCase('unknown root control config builds conservatively', ['future-build.config.json'], 'BUILD', 'BUILD');
pathCase('checkout-transform attributes are shared deployment control', ['.gitattributes'], 'BUILD', 'BUILD');

test('04 marketing JSON config and package manifest', () => {
  const { repo, base } = fixture();
  const config = JSON.parse(readFileSync(join(repo, 'site/vercel.json'), 'utf8'));
  config.cleanUrls = !config.cleanUrls;
  put(repo, 'site/vercel.json', JSON.stringify(config));
  commit(repo);
  expectPair(repo, base, 'BUILD', 'IGNORE');
});

test('05 root Flutter manifest', () => {
  const { repo, base } = fixture();
  appendFileSync(join(repo, 'pubspec.yaml'), '\n# valid manifest change\n');
  commit(repo);
  expectPair(repo, base, 'IGNORE', 'BUILD');
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
  expectPair(repo, base, 'BUILD', 'IGNORE');
});

test('15 successful baseline spans intervening ignored and failed candidates', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/ignored.md');
  commit(repo);
  expectPair(repo, base, 'IGNORE', 'IGNORE');
  put(repo, 'apps/pos/lib/earlier.dart');
  commit(repo, 'candidate that was not successfully deployed');
  put(repo, 'docs/final.md');
  commit(repo);
  expectPair(repo, base, 'IGNORE', 'BUILD');
});

test('16 deletion of relevant input', () => {
  const { repo, base } = fixture();
  unlinkSync(join(repo, 'apps/pos/lib/filter_fixture.dart'));
  commit(repo);
  expectPair(repo, base, 'IGNORE', 'BUILD');
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
    expectPair(repo, base, 'IGNORE', 'BUILD');
  });
}

test('18 non-ancestor previous SHA builds, including removed former runtime input', () => {
  const { repo, base } = fixture();
  runGit(repo, ['checkout', '--quiet', '-b', 'earlier-deployment']);
  put(repo, 'apps/pos/lib/earlier.dart');
  const nonAncestor = commit(repo);
  runGit(repo, ['checkout', '--quiet', 'main']);
  put(repo, 'docs/rebased.md');
  commit(repo);
  assert.equal(runGit(repo, ['merge-base', nonAncestor, 'HEAD']), base);
  expectPair(repo, nonAncestor, 'BUILD', 'BUILD');
});

test('19 complete feature branch can use local origin/main merge-base fallback', () => {
  const { repo, base } = fixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', base]);
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/site-fixture']);
  put(repo, 'site/src/fallback.js');
  commit(repo);
  expectPair(repo, undefined, 'BUILD', 'IGNORE', { env: { VERCEL_GIT_PULL_REQUEST_ID: '123' } });
});

test('19 missing prior SHA may ignore a docs-only feature branch with proven ancestry', () => {
  const { repo, base } = fixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', base]);
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/docs-fixture']);
  put(repo, 'docs/fallback.md');
  commit(repo);
  expectPair(repo, undefined, 'IGNORE', 'IGNORE', { env: { VERCEL_GIT_PULL_REQUEST_ID: '123' } });
});

test('19 fallback refuses absent or malformed PR context and production/main contexts', () => {
  const { repo, base } = fixture();
  runGit(repo, ['update-ref', 'refs/remotes/origin/main', base]);
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/context-fixture']);
  put(repo, 'docs/fallback.md');
  commit(repo);
  for (const context of [
    { VERCEL_GIT_PULL_REQUEST_ID: '' },
    { VERCEL_GIT_PULL_REQUEST_ID: CANARY },
    { VERCEL_GIT_PULL_REQUEST_ID: '0' },
    { VERCEL_GIT_PULL_REQUEST_ID: '123', VERCEL_ENV: 'production' },
    { VERCEL_GIT_PULL_REQUEST_ID: '123', VERCEL_GIT_COMMIT_REF: 'main' },
  ]) expectPair(repo, undefined, 'BUILD', 'BUILD', { env: context });
});

test('19 no trusted local base ref fails without fetching', () => {
  const { repo } = fixture();
  runGit(repo, ['checkout', '--quiet', '-b', 'feature/no-base']);
  put(repo, 'docs/only.md');
  commit(repo);
  expectPair(repo, undefined, 'BUILD', 'BUILD', { env: { VERCEL_GIT_PULL_REQUEST_ID: '123' } });
});

test('20 missing commit object builds without fetching', () => {
  const { repo } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  expectPair(repo, 'a'.repeat(40), 'BUILD', 'BUILD');
});

test('20 any shallow repository builds even with comparable visible trees', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  put(repo, '.git/shallow', base + '\n');
  assert.equal(runGit(repo, ['rev-parse', '--is-shallow-repository']), 'true');
  expectPair(repo, base, 'BUILD', 'BUILD');
});

test('20 Git unavailable produces a sanitized BUILD decision', () => {
  const { repo, base } = fixture();
  expectPair(repo, base, 'BUILD', 'BUILD', { noGit: true });
});

test('21 first production deployment has no trustworthy fallback', () => {
  const { repo } = fixture();
  expectPair(repo, undefined, 'BUILD', 'BUILD', { env: { VERCEL_ENV: 'production' } });
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
    expectPair(repo, previous, 'BUILD', 'BUILD');
  }
});

test('invalid or mismatched advertised HEAD never silently skips', () => {
  const { repo, base } = fixture();
  put(repo, 'docs/only.md');
  commit(repo);
  for (const advertised of [CANARY, base, 'a'.repeat(40)]) {
    expectPair(repo, base, 'BUILD', 'BUILD', { env: { VERCEL_GIT_COMMIT_SHA: advertised } });
  }
});

test('equal previous and HEAD is a complete empty diff', () => {
  const { repo, base } = fixture();
  expectPair(repo, base, 'IGNORE', 'IGNORE');
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
  expectPair(repo, base, 'BUILD', 'IGNORE');
});

test('NUL-safe diff supports newline and tab filenames', { skip: process.platform === 'win32' ? 'Windows filesystem disallows these POSIX filename characters' : false }, () => {
  const { repo, base } = fixture();
  put(repo, 'site/public/a\nREADME.md');
  put(repo, 'site/public/b\ttest.js');
  commit(repo);
  expectPair(repo, base, 'BUILD', 'IGNORE');
});

test('invalid UTF-8 path bytes fail safely', { skip: process.platform === 'win32' ? 'POSIX raw filename byte case' : false }, () => {
  const { repo, base } = fixture();
  const filename = Buffer.concat([Buffer.from(join(repo, 'site/public/') + '/'), Buffer.from([0xff]), Buffer.from('.txt')]);
  writeFileSync(filename, 'fixture');
  commit(repo);
  expectPair(repo, base, 'BUILD', 'BUILD');
});

test('declared Flutter asset directories override docs and test exclusions', () => {
  const text = manifestTexts.get('apps/kiosk');
  assert.match(text, /assets\/fixtures\//);
  const { repo, base } = fixture();
  put(repo, 'apps/kiosk/assets/fixtures/README.md');
  put(repo, 'apps/kiosk/assets/fixtures/test/data.json');
  commit(repo);
  expectPair(repo, base, 'IGNORE', 'BUILD');
});

test('new declared test-directory asset takes priority after its manifest baseline', () => {
  const { repo, base } = fixture({ seed(repo) {
    const manifest = manifestTexts.get('apps/pos').replace(/^flutter:\s*\r?$/m, 'flutter:\n  assets:\n    - test/deploy_assets/');
    put(repo, 'apps/pos/pubspec.yaml', manifest);
    put(repo, 'apps/pos/test/deploy_assets/README.md');
  } });
  appendFileSync(join(repo, 'apps/pos/test/deploy_assets/README.md'), 'changed\n');
  commit(repo);
  expectPair(repo, base, 'IGNORE', 'BUILD');
});

test('declared shared marketing asset affects both projects', () => {
  const { repo, base } = fixture({ seed(repo) {
    const manifest = manifestTexts.get('apps/pos').replace(/^flutter:\s*\r?$/m, 'flutter:\n  assets:\n    - ../../site/public/license.md');
    put(repo, 'apps/pos/pubspec.yaml', manifest);
  } });
  appendFileSync(join(repo, 'site/public/license.md'), 'changed\n');
  commit(repo);
  expectPair(repo, base, 'BUILD', 'BUILD');
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
  expectPair(repo, base, 'IGNORE', 'IGNORE');
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
