// BIZBOT-STOREFRONT-CINEMATIC-001B: orchestration for this disposable CI lane.
// Application code/repositories are unchanged; credentials and raw logs never
// enter the public evidence directory. Only the loopback anon key enters builds.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
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
export const CLEAR_TRACE_TITLE = 'warm saved banner → one clear → ordinary menu read/render trace';
export function acceptanceRunArgs(mode) {
  assert.ok(mode === 'probe' || mode === 'trace' || mode === 'full', 'Unknown acceptance selection');
  // The short probe runs exactly once. The second command still selects every
  // pre-existing case; it excludes only this exact new title, never a stage or
  // an original assertion. Neither command retries a publication or a test.
  return ['--no-install', 'playwright', 'test', '--config', 'cinematic/playwright.config.ts',
    mode === 'full' ? '--grep-invert' : '--grep', mode === 'full'
      ? `(?:^|\\s)(?:${PUBLISHER_PROBE_TITLE}|${CLEAR_TRACE_TITLE})$`
      : `(?:^|\\s)${mode === 'probe' ? PUBLISHER_PROBE_TITLE : CLEAR_TRACE_TITLE}$`, '--reporter=json'];
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

// Public evidence projection only. The reviewed SQL/ACL producer and the
// generic credential predicate below remain unchanged.
export const WELCOME_GRANT_IDENTITIES = Object.freeze([
  'app.get_restaurant_storefront_content_v7(uuid,uuid)',
  'app.list_storefront_welcome_videos_v1(uuid,uuid)',
  'app.preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid)',
  'app.publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid)',
  'app.register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer)',
  'get_restaurant_storefront_content_v7(uuid,uuid)',
  'list_storefront_welcome_videos_v1(uuid,uuid)',
  'preflight_storefront_welcome_video_v1(uuid,uuid,text,uuid)',
  'publish_storefront_welcome_video_v1(uuid,uuid,uuid,uuid)',
  'register_storefront_welcome_video_v1(uuid,uuid,text,uuid,text,integer,integer,integer,integer)',
  'storefront_menu_v12(text)',
]);
const sha256 = text => createHash('sha256').update(text).digest('hex');
const evidenceFailure = reason => { const error = new Error(reason); error.evidenceReason = reason; throw error; };
export function assertPublicEvidenceJson(text) {
  JSON.parse(text);
  assert.ok(!/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|"(?:access_token|refresh_token|password|service_role|anonKey|ANON_KEY)"\s*:/i.test(text),
    'Credential-shaped data must not be published');
}
function sourceMatches(source, current) {
  return /^[0-9a-f]{40}$/.test(source?.testedCheckout ?? '') && /^[0-9a-f]{40}$/.test(source?.testedTree ?? '') &&
    source.testedCheckout === current?.checkout && source.testedTree === current?.tree;
}
export function projectMigrationGrantReceipt(entry, text, source, current) {
  if (entry !== 'migration-atomicity.json') evidenceFailure('ROLE_AUDIT_PROJECTION_INVALID');
  if (!sourceMatches(source, current)) evidenceFailure('SOURCE_IDENTITY_MISMATCH');
  const data = JSON.parse(text);
  if (!data || typeof data !== 'object' || Array.isArray(data)) evidenceFailure('ROLE_AUDIT_PROJECTION_INVALID');
  // An earlier failed migration phase has no new role-audit structure. Preserve
  // that original failure byte-for-byte; the unchanged generic guard still runs.
  if (!Object.hasOwn(data, 'welcome_video_release')) return { text, manifest: null };
  if (data.tested_commit !== source.testedCheckout || data.tested_tree !== source.testedTree)
    evidenceFailure('SOURCE_IDENTITY_MISMATCH');
  const release = data.welcome_video_release;
  const rows = release?.grants;
  if (!release || typeof release !== 'object' || Array.isArray(release) || !['PASS','FAIL'].includes(data.status) || !['PASS','FAIL'].includes(release.status) || !Array.isArray(rows) || rows.length !== 11)
    evidenceFailure('ROLE_AUDIT_PROJECTION_INVALID');
  const keys = ['anon','authenticated','definer','identity','owner','public_execute','search_path','service_role'];
  for (let index = 0; index < rows.length; index++) {
    const row = rows[index];
    if (!row || typeof row !== 'object' || Array.isArray(row) || JSON.stringify(Object.keys(row).sort()) !== JSON.stringify(keys) ||
        row.identity !== WELCOME_GRANT_IDENTITIES[index] || typeof row.owner !== 'string' ||
        !(row.search_path === null || Array.isArray(row.search_path) && row.search_path.every(value => typeof value === 'string')) ||
        ['anon','authenticated','definer','public_execute','service_role'].some(key => typeof row[key] !== 'boolean'))
      evidenceFailure('ROLE_AUDIT_PROJECTION_INVALID');
  }
  // Replace only the eleven literal property-name tokens in the original text.
  // Never reserialize other fields: duplicate password keys, token strings,
  // whitespace and every failure value remain visible to the original guard.
  const tokens = [...text.matchAll(/"service_role"(?=\s*:)/g)];
  if (tokens.length !== 11) evidenceFailure('ROLE_AUDIT_PROJECTION_INVALID');
  const projected = text.replace(/"service_role"(?=\s*:)/g, '"serviceRoleExecute"');
  const expected = structuredClone(data);
  expected.welcome_video_release.grants = rows.map(({ service_role, ...other }) => ({ ...other, serviceRoleExecute: service_role }));
  try { assert.deepEqual(JSON.parse(projected), expected); }
  catch { evidenceFailure('ROLE_AUDIT_PROJECTION_INVALID'); }
  return { text: projected, manifest: {
    status: 'DERIVED_PUBLIC_EVIDENCE', projection: 'WELCOME_VIDEO_GRANT_ROLE_KEY_V1', sourceFile: entry,
    sourceSha256: sha256(text), projectedSha256: sha256(projected), rawOriginalRetainedPrivately: true,
    testedCommit: source.testedCheckout, testedTree: source.testedTree, producerStatus: data.status,
    renamedFields: rows.map((row, index) => ({ identity: row.identity,
      sourcePath: `$.welcome_video_release.grants[${index}].service_role`,
      publicPath: `$.welcome_video_release.grants[${index}].serviceRoleExecute`, value: row.service_role })),
  } };
}
const diagnosticFiles = new Set(['source.json','migration-atomicity.json','migration-atomicity-public-projection.json',
  'publisher-response-probe.json','publisher-response-probe-result.json','browser-result.json','welcome-browser-result.json']);
export function evidenceSanitizeDiagnostic(entry, error) {
  const reasons = new Set(['ROLE_AUDIT_PROJECTION_INVALID','SOURCE_IDENTITY_MISMATCH']);
  const reason = reasons.has(error?.evidenceReason) ? error.evidenceReason : error instanceof SyntaxError ? 'JSON_INVALID' :
    error?.message === 'Credential-shaped data must not be published' ? 'CREDENTIAL_PATTERN_REJECTED' : 'EVIDENCE_SANITIZE_FAILED';
  return { file: diagnosticFiles.has(entry) ? entry : null, reason };
}
export function caseCollectionSummary(mode, result, report, reportPresent) {
  const codes = new Set(['ENOENT','EACCES','EPERM','ETIMEDOUT','ENOBUFS','E2BIG']);
  const signals = new Set(['SIGTERM','SIGKILL','SIGABRT','SIGINT','SIGSEGV']);
  return { mode: ['probe','full','trace'].includes(mode) ? mode : 'unclassified', exitCode: Number.isInteger(result?.status) ? result.status : null,
    signal: signals.has(result?.signal) ? result.signal : result?.signal ? 'OTHER' : null,
    spawnError: result?.error ? { name: ['Error','TypeError','RangeError'].includes(result.error.name) ? result.error.name : 'OTHER',
      code: codes.has(result.error.code) ? result.error.code : 'OTHER' } : null,
    reportPresent: reportPresent === true, globalErrorCount: Array.isArray(report?.errors) ? report.errors.length : 0,
    globalErrors: (Array.isArray(report?.errors) ? report.errors : []).slice(0, 3).map(error => ({
      messageSha256: sha256(String(error?.message ?? '')), classification: ['Error','TypeError','SyntaxError','ReferenceError'].includes(error?.name) ? error.name : 'unclassified',
      sourceFrame: String(error?.stack ?? '').match(/(?:^|[\s(/])(?:e2e\/)?(cinematic\/[a-z0-9_-]+(?:\.spec)?\.(?:ts|mjs):[0-9]+:[0-9]+)(?=[)\s]|$)/m)?.[1] ?? null,
    })),
  };
}
export function probeDiagnosticScalars(value) {
  const phases = new Set(['dashboard-load','owner-login','open-banner-editor','legacy-authenticated-pre-read',
    'ui-upload-original-publisher-response','published-resource-preview','legacy-authenticated-post-read','native-dashboard-image-byte-guard','complete']);
  const readErrors = new Set(['no-data','no-resource','get-body-error','context-closed','aborted','unclassified']);
  return { status: ['PASS','FAIL','NOT_RUN'].includes(value?.status) ? value.status : 'unclassified',
    phase: phases.has(value?.phase) ? value.phase : 'unclassified',
    uiPublicationCalls: [0,1].includes(value?.uiPublicationCalls) ? value.uiPublicationCalls : null,
    contentSaveCalls: value?.contentSaveCalls === 0 ? 0 : null,
    matcher: typeof value?.failure?.matcher === 'string' && /^to[A-Za-z]{1,40}$/.test(value.failure.matcher) ? value.failure.matcher : 'unclassified',
    sourceLine: Number.isInteger(value?.failure?.sourceLine) && value.failure.sourceLine > 0 ? value.failure.sourceLine : null,
    readErrorDetail: readErrors.has(value?.readErrorDetail) ? value.readErrorDetail : 'unclassified' };
}

export function budgetChildProcessStates(dashboard, storefront) {
  const signals = new Set(['SIGTERM','SIGKILL','SIGABRT','SIGINT','SIGSEGV','SIGILL','SIGBUS','SIGHUP','SIGQUIT']);
  return [['dashboard',dashboard],['storefront',storefront]].filter(([, child]) => child !== null && typeof child === 'object').map(([label, child]) => ({
    label, exitCode: Number.isInteger(child.exitCode) ? child.exitCode : null,
    signal: child.signalCode === null || child.signalCode === undefined ? null : signals.has(child.signalCode) ? child.signalCode : 'OTHER',
    killed: child.killed === true,
  }));
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
    let entry = 'source.json';
    try {
      const source = JSON.parse(readFileSync(resolve(publicDir, entry), 'utf8'));
      const current = { checkout: checked('git', ['rev-parse','HEAD']), tree: checked('git', ['rev-parse','HEAD^{tree}']) };
      if (!sourceMatches(source, current)) evidenceFailure('SOURCE_IDENTITY_MISMATCH');
      for (entry of readdirSync(publicDir, { recursive: true })) {
        const path = resolve(publicDir, entry);
        assert.ok(relative(publicDir, path) !== '..' && !relative(publicDir, path).startsWith(`..${sep}`));
        if (statSync(path).isDirectory()) continue;
        assert.ok(entry === HEIGHT_VIDEO_FILE || /^(?:[a-z0-9_-]+\.json|[a-z0-9_-]+\.png)$/i.test(entry), 'Unexpected evidence path');
        if (entry.endsWith('.json')) {
          let text = readFileSync(path, 'utf8');
          if (entry === 'migration-atomicity.json') {
            const raw = resolve(privateDir, 'migration-atomicity.raw.json');
            if (existsSync(raw)) assert.equal(readFileSync(raw,'utf8'),text,'Raw migration receipt identity changed');
            else writeFileSync(raw,text,{mode:0o600,flag:'wx'});
            const projection = projectMigrationGrantReceipt(entry,text,source,current);
            text = projection.text;
            if (projection.manifest) {
              assertPublicEvidenceJson(text);
              const manifest = JSON.stringify(projection.manifest,null,2)+'\n';
              assertPublicEvidenceJson(manifest);
              writeFileSync(path,text);
              writeFileSync(resolve(publicDir,'migration-atomicity-public-projection.json'),manifest);
            }
          }
          assertPublicEvidenceJson(text);
        } else if (entry === HEIGHT_VIDEO_FILE) {
          assertHeightVideoEvidence(entry, readFileSync(path));
        } else {
          assert.equal(readFileSync(path).subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
        }
      }
    } catch (error) {
      const diagnostic = evidenceSanitizeDiagnostic(entry,error);
      console.error('CINEMATIC_EVIDENCE_REJECTED '+JSON.stringify(diagnostic));
      throw new Error(`Evidence sanitization failed: ${diagnostic.reason}`);
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
      const stem = mode === 'probe' ? 'publisher-response-probe' : mode === 'trace' ? 'warm-clear-trace' : 'playwright';
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
      const reportPresent = existsSync(report);
      const reported = reportPresent ? JSON.parse(readFileSync(report, 'utf8')) : {};
      collect(reported.suites);
      const errors = (reported.errors || []).map(error => clean(error.message));
      const collection = { ...caseCollectionSummary(mode,result,reported,reportPresent), cases: cases.length };
      console.log('CINEMATIC_CASE_COLLECTION '+JSON.stringify(collection));
      if (mode === 'probe') {
        const probeReceipt = resolve(publicDir,'publisher-response-probe.json');
        if (existsSync(probeReceipt)) {
          try { console.log('CINEMATIC_PROBE_DIAGNOSTIC '+JSON.stringify(probeDiagnosticScalars(JSON.parse(readFileSync(probeReceipt,'utf8'))))); }
          catch { console.log('CINEMATIC_PROBE_DIAGNOSTIC '+JSON.stringify({ status:'RECEIPT_UNREADABLE' })); }
        } else console.log('CINEMATIC_PROBE_DIAGNOSTIC '+JSON.stringify({ status:'RECEIPT_ABSENT' }));
      }
      const outcome = {
        status: result.status === 0 ? 'PASS' : 'FAIL', exitCode: result.status, collection,
        actualServices: true, retries: 0, cases, errors,
      };
      writeFileSync(resolve(publicDir, mode === 'probe' ? 'publisher-response-probe-result.json' : mode === 'trace' ? 'warm-clear-trace-result.json' : 'browser-result.json'), JSON.stringify(outcome, null, 2));
      for (const item of cases) console.log(`${item.status}: ${item.title}`);
      return outcome;
    };
    // The short warm-clear diagnosis is retained as a separate exact selection.
    // Normal final acceptance retains the three complete journeys plus welcome; its
    // independent banner case now captures the same clear read/render chain.
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
    let liveBudget;
    try { liveBudget = await measureLiveBudget(root, privateDir, publicDir, fixture.ownerA.slug); }
    catch (error) {
      // Observe only these already launched children, before the existing
      // finally sends SIGTERM. No health fetch, wait, retry or connection change.
      try {
        const childProcesses = budgetChildProcessStates(dashboard, storefront);
        const receiptPath = resolve(publicDir, 'live-firstload-budget.json');
        if (existsSync(receiptPath)) {
          const receipt = JSON.parse(readFileSync(receiptPath, 'utf8'));
          writeFileSync(receiptPath, JSON.stringify({ ...receipt, childProcesses }, null, 2));
        } else writeFileSync(resolve(publicDir, 'live-budget-child-state.json'), JSON.stringify({ childProcesses }, null, 2));
      } catch { /* Retain the same original measurement failure even if evidence I/O fails. */ }
      throw error;
    }
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
