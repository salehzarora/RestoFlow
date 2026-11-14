// BIZBOT-STOREFRONT-CINEMATIC-001B: orchestration for this disposable CI lane.
// Application code/repositories are unchanged; credentials and raw logs never
// enter the public evidence directory. Only the loopback anon key enters builds.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, openSync, closeSync, readdirSync, statSync, existsSync } from 'node:fs';
import { resolve, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { installDashboardFontMirror } from './font-mirror.mjs';
import { requireEphemeralCi } from '../../supabase/tests/support/cinematic_001b_migration_contract.mjs';
import { capturePublisherRuntime } from './publisher-diagnostics.mjs';
import { LOGICAL_ORIGIN } from './live-transport.mjs';
import { measureLiveBudget } from './live-budget.mjs';

const marker = 'BIZBOT-STOREFRONT-CINEMATIC-001B';
const api = 'http://127.0.0.1:54321';
export function localStatus(status) {
  assert.equal(status.API_URL, api, 'Only the disposable loopback gateway is allowed');
  assert.equal(typeof status.ANON_KEY, 'string', 'Local anon key missing');
  const parts = status.ANON_KEY.split('.');
  assert.equal(parts.length, 3, 'Expected the pinned local stack anon JWT');
  const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  assert.equal(claims.role, 'anon', 'A privileged key must never enter an application build');
  return { url: api, anonKey: status.ANON_KEY };
}

// Exactly one owner-authorized, synthetic-only height-control recording. Raw
// Playwright recordings and storage state stay in the private output directory.
export const HEIGHT_VIDEO_FILE = 'responsive-banner-height-adjustment.webm';
export const PUBLISHER_PROBE_TITLE = 'single publisher response - native body diagnostic';
export function acceptanceRunArgs(mode) {
  assert.ok(mode === 'probe' || mode === 'full', 'Unknown acceptance selection');
  // The short probe runs exactly once. The second command still selects every
  // pre-existing case; it excludes only this exact new title, never a stage or
  // an original assertion. Neither command retries a publication or a test.
  return ['--no-install', 'playwright', 'test', '--config', 'cinematic/playwright.config.ts',
    mode === 'probe' ? '--grep' : '--grep-invert', `(?:^|\\s)${PUBLISHER_PROBE_TITLE}$`, '--reporter=json'];
}
export function assertHeightVideoEvidence(name, bytes) {
  assert.equal(name, HEIGHT_VIDEO_FILE);
  assert.ok(bytes.length >= 32 && bytes.length <= 8 * 1024 * 1024, 'Height video has a bounded size');
  assert.equal(bytes.subarray(0, 4).toString('hex'), '1a45dfa3', 'Expected EBML WebM header');
  assert.ok(bytes.subarray(0, 512).includes(Buffer.from('webm')), 'Expected WebM document type');
}

function setup() {
  requireEphemeralCi(process.env); // Reject endpoint/context overrides before even `supabase start`.
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'This runner is CI-only');
  assert.equal(process.env.CI, 'true');
  assert.equal(process.env.CINEMATIC_EPHEMERAL, marker);
  for (const key of ['SUPABASE_ACCESS_TOKEN', 'SUPABASE_DB_PASSWORD', 'SUPABASE_SERVICE_ROLE_KEY', 'VERCEL_TOKEN']) {
    assert.equal(Boolean(process.env[key]), false, `Unexpected hosted credential: ${key}`);
  }
  const root = resolve(process.env.GITHUB_WORKSPACE || '');
  assert.equal(process.cwd(), root, 'Run from the checked-out repository root');
  assert.equal(existsSync(resolve(root, 'supabase/.temp/project-ref')), false, 'Linked projects are forbidden');
  const temp = resolve(process.env.RUNNER_TEMP || '');
  assert.notEqual(temp, root);
  const privateDir = resolve(temp, 'cinematic-private');
  const publicDir = resolve(temp, 'cinematic-public');
  assert.equal(process.env.CINEMATIC_STATUS_FILE, resolve(privateDir, 'status.json'));
  assert.equal(process.env.CINEMATIC_FIXTURE_FILE, resolve(privateDir, 'fixtures.json'));
  assert.equal(process.env.CINEMATIC_ARTIFACT_DIR, publicDir);
  mkdirSync(privateDir, { recursive: true, mode: 0o700 });
  mkdirSync(publicDir, { recursive: true });
  return { root, privateDir, publicDir };
}

function checked(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  assert.equal(result.status, 0, `${command} failed (exit ${result.status}); raw logs remain private`);
  return result.stdout?.trim();
}

async function waitUntil(url, accepts, child) {
  const endpoint = new URL(url);
  assert.equal(endpoint.hostname, '127.0.0.1');
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    if (child && child.exitCode !== null) throw new Error('Local application exited during startup');
    try {
      const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(2000) });
      if (accepts(response)) return;
    } catch { /* Bounded service-readiness polling, never retry an acceptance test. */ }
    await new Promise(r => setTimeout(r, 500));
  }
  throw new Error(`Local service did not become ready on port ${endpoint.port}`);
}

async function main(action) {
  const { root, privateDir, publicDir } = setup();
  if (action === 'prepare') {
    const checkout = checked('git', ['rev-parse', 'HEAD']);
    const tree = checked('git', ['rev-parse', 'HEAD^{tree}']);
    const prHead = process.env.CINEMATIC_PR_HEAD;
    assert.match(prHead || '', /^[a-f0-9]{40}$/);
    checked('git', ['merge-base', '--is-ancestor', prHead, checkout]);
    writeFileSync(resolve(publicDir, 'source.json'), JSON.stringify({ work: marker, prHead,
      prBase: process.env.CINEMATIC_PR_BASE, testedCheckout: checkout, testedTree: tree,
      runId: process.env.GITHUB_RUN_ID, data: 'synthetic isolated CI data',
      flutter: '3.44.2', supabase: '2.107.0' }, null, 2));
    console.log(`PR head ${prHead}; tested merge ${checkout}; tree ${tree}`);
    return;
  }
  if (action === 'sanitize') {
    // Only explicit receipts, PNG screenshots and the one bounded synthetic height video. Never raw server logs, traces,
    // browser storage state, request dumps or the fixture/status files.
    for (const entry of readdirSync(publicDir, { recursive: true })) {
      const path = resolve(publicDir, entry);
      assert.ok(relative(publicDir, path) !== '..' && !relative(publicDir, path).startsWith(`..${sep}`));
      if (statSync(path).isDirectory()) continue;
      assert.ok(entry === HEIGHT_VIDEO_FILE || /^(?:[a-z0-9_-]+\.json|[a-z0-9_-]+\.png)$/i.test(entry), 'Unexpected evidence path');
      if (entry.endsWith('.json')) {
        const text = readFileSync(path, 'utf8');
        JSON.parse(text);
        assert.ok(!/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|"(?:access_token|refresh_token|password|service_role|anonKey|ANON_KEY)"\s*:/i.test(text),
          'Credential-shaped data must not be published');
      } else if (entry === HEIGHT_VIDEO_FILE) {
        assertHeightVideoEvidence(entry, readFileSync(path));
      } else {
        assert.equal(readFileSync(path).subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
      }
    }
    return;
  }
  if (action === 'publisher-diagnostics') {
    try { capturePublisherRuntime(privateDir, publicDir); }
    catch { throw new Error('Publisher diagnostic collection failed; no raw diagnostic exported'); }
    return;
  }
  const status = localStatus(JSON.parse(readFileSync(process.env.CINEMATIC_STATUS_FILE, 'utf8')));
  if (action === 'status') return;
  if (action === 'edge-ready') {
    // Negative JWT control only: this does NOT prove the handler is ready.
    // bootstrap performs a real-session, non-mutating handler readiness probe.
    await waitUntil(`${api}/functions/v1/storefront-media-publish`, r => r.status === 401);
    return;
  }
  assert.ok(!process.env.NODE_OPTIONS, 'Do not inherit an alternate Node preload');
  const liveEnv = { ...process.env, STOREFRONT_SOURCE: 'live', STOREFRONT_SUPABASE_URL: LOGICAL_ORIGIN,
    STOREFRONT_SUPABASE_ANON_KEY: status.anonKey, NEXT_TELEMETRY_DISABLED: '1',
    NODE_OPTIONS: `--import=${pathToFileURL(resolve(root, 'e2e/cinematic/live-transport-preload.mjs')).href}` };
  if (action === 'build') {
    // Build-time model download is pinned and hash-checked. Only Dashboard
    // receives these same-origin lazy assets; the public Storefront does not.
    checked('node', ['prepare.mjs'], { cwd: resolve(root, 'apps/dashboard/cutout'), stdio: 'inherit' });
    checked('npm', ['test'], { cwd: resolve(root, 'apps/dashboard/cutout'), stdio: 'inherit' });
    const defines = resolve(privateDir, 'dashboard-defines.json');
    // Exercise the same optional explicit-action processor compiled for the
    // owner-enabled Production editor; this harness still uses isolated data.
    writeFileSync(defines, JSON.stringify({ RESTOFLOW_DEMO_MODE: 'false', RESTOFLOW_STOREFRONT_EDITOR: 'true',
      SF_PRODUCT_CUTOUT_REVIEW: 'true',
      RESTOFLOW_SUPABASE_URL: status.url, RESTOFLOW_SUPABASE_ANON_KEY: status.anonKey }), { mode: 0o600 });
    checked('flutter', ['build', 'web', '--release', '--no-pub', '--no-web-resources-cdn', `--dart-define-from-file=${defines}`],
      { cwd: resolve(root, 'apps/dashboard'), stdio: 'inherit' });
    checked('node', ['prepare.mjs', '--verify-build', 'true', 'dashboard-only'],
      { cwd: resolve(root, 'apps/dashboard/cutout'), stdio: 'inherit' });
    writeFileSync(resolve(publicDir, 'dashboard-cutout-build.json'),
      readFileSync(resolve(root, 'apps/dashboard/build/web/product-cutout/build-record.json')));
    const fontMirror = installDashboardFontMirror(root);
    writeFileSync(resolve(publicDir, 'dashboard-font-mirror.json'), JSON.stringify(fontMirror, null, 2));
    assert.equal(JSON.parse(readFileSync(resolve(root, 'storefront/package.json'), 'utf8')).scripts.build, 'next build');
    checked('node', ['node_modules/next/dist/bin/next', 'build'], { cwd: resolve(root, 'storefront'), env: liveEnv, stdio: 'inherit' });
    return;
  }
  assert.equal(action, 'acceptance', 'Unknown cinematic CI action');
  const children = [];
  const launch = (command, args, cwd, env, log) => {
    const fd = openSync(resolve(privateDir, log), 'w', 0o600);
    const child = spawn(command, args, { cwd, env, stdio: ['ignore', fd, fd] });
    closeSync(fd); children.push(child); return child;
  };
  try {
    const dashboard = launch('python3', ['-m', 'http.server', '57026', '--bind', '127.0.0.1', '--directory', 'build/web'],
      resolve(root, 'apps/dashboard'), process.env, 'dashboard.log');
    const storefront = launch('node', ['node_modules/next/dist/bin/next', 'start', '--hostname', '127.0.0.1', '--port', '3000'],
      resolve(root, 'storefront'), liveEnv, 'storefront.log');
    await Promise.all([
      waitUntil('http://127.0.0.1:57026/', r => r.ok, dashboard),
      waitUntil('http://127.0.0.1:3000/', r => r.status < 500, storefront),
    ]);
    // Browser call logs can include fill(password). Never publish raw Playwright
    // output. Reduce it to titles/status/one-line errors and redact known fixture
    // values plus JWTs before emitting any diagnostic.
    const fixture = JSON.parse(readFileSync(process.env.CINEMATIC_FIXTURE_FILE, 'utf8'));
    const privateValues = [fixture.anonKey, ...['ownerA', 'ownerB', 'outsider'].map(k => fixture[k]?.password)].filter(Boolean);
    const clean = value => {
      let text = String(value || '').replace(/\x1b\[[0-9;]*m/g, '');
      for (const secret of privateValues) text = text.replaceAll(secret, '[REDACTED]');
      return text.replace(/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, '[REDACTED JWT]').trim().split('\n')[0].slice(0, 400);
    };
    const runCases = mode => {
      const stem = mode === 'probe' ? 'publisher-response-probe' : 'playwright';
      const report = resolve(privateDir, `${stem}.json`);
      const fd = openSync(resolve(privateDir, `${stem}.log`), 'w', 0o600);
      const result = spawnSync('npx', acceptanceRunArgs(mode),
        { cwd: resolve(root, 'e2e'), env: { ...process.env, PLAYWRIGHT_JSON_OUTPUT_NAME: report }, stdio: ['ignore', fd, fd] });
      closeSync(fd);
      const cases = [];
      const collect = suites => { for (const suite of suites || []) {
        for (const spec of suite.specs || []) for (const item of spec.tests || []) {
          cases.push({ title: clean(spec.title), status: item.status,
            results: (item.results || []).map(r => ({ status: r.status, error: clean(r.error?.message) })) });
        }
        collect(suite.suites);
      } };
      const reported = existsSync(report) ? JSON.parse(readFileSync(report, 'utf8')) : {};
      collect(reported.suites);
      const errors = (reported.errors || []).map(error => clean(error.message));
      const outcome = {
        status: result.status === 0 ? 'PASS' : 'FAIL', exitCode: result.status,
        actualServices: true, retries: 0, cases, errors,
      };
      writeFileSync(resolve(publicDir, mode === 'probe' ? 'publisher-response-probe-result.json' : 'browser-result.json'), JSON.stringify(outcome, null, 2));
      for (const item of cases) console.log(`${item.status}: ${item.title}`);
      return outcome;
    };
    const probe = runCases('probe');
    // Stop before the expensive height/readback comparisons if the one-POST
    // reproduction failed. HTTP200 or a later UI message cannot unlock them.
    const full = probe.status === 'PASS' ? runCases('full') : {
      status: 'NOT_RUN', exitCode: null, actualServices: true, retries: 0, cases: [], errors: [],
      reason: 'PUBLISHER_RESPONSE_PROBE_FAILED',
    };
    if (full.status === 'NOT_RUN') writeFileSync(resolve(publicDir, 'browser-result.json'), JSON.stringify(full, null, 2));
    // Run only after the independent UI lifecycle has finished. A size failure
    // cannot prevent Edge acceptance from executing or erase its own receipt.
    const liveBudget = await measureLiveBudget(root, privateDir, publicDir, fixture.ownerA.slug);
    assert.equal(probe.status, 'PASS', 'Single publisher response reproduction failed; no publication/test retry');
    assert.equal(full.status, 'PASS', 'Real Dashboard acceptance failed; no automatic retry');
    assert.equal(liveBudget.status, 'PASS', 'Actual live first-load budget failed; unchanged caps remain a release gate');
  } finally {
    for (const child of children) child.kill('SIGTERM');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main(process.argv[2]).catch(error => { console.error(error.message); process.exitCode = 1; });
}
