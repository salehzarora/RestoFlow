#!/usr/bin/env node
/**
 * WEB-ORDERS-CHECKOUT-001: offline release-build browser evidence.
 * Run with Node 24 after `npm ci` and installation of the matching Chromium.
 * A fresh local copy uses the identical tracked server-admission source.
 * Server reads are redirected to a loopback synthetic RPC and every other
 * off-machine Node fetch is denied. The browser spec intercepts the exact Edge
 * endpoint, denies other remote requests, and receives committed CSP headers.
 */
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { createServer, request as httpRequest } from 'node:http';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { syntheticEnvelope, SYNTH_IDS, NOT_FOUND_ENVELOPE } from '../tests/support/envelope.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WORKTREE = path.dirname(ROOT);
const PROJECT = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const RPC = `${PROJECT}/rest/v1/rpc/storefront_menu`;
const SYNTHETIC_KEY = 'sb_publishable_SYNTHETIC_browser_local_only_000000';
const GATE = path.join(ROOT, 'src/source/live/ordering.ts');
const gateSource = readFileSync(GATE, 'utf8');
assert.match(process.version, /^v24\./, 'Use the task Node 24 runtime');
assert.ok(!gateSource.includes('LIVE_ORDERING_RELEASED') && !gateSource.includes('LIVE_PICKUP_ROLLOUT_SLUG'), 'Checkout must follow tenant-scoped server admission without local rollout overrides');
assert.ok(existsSync(path.join(ROOT, 'node_modules/next/dist/bin/next')), 'Run npm ci in this worktree first');

const evidenceRoot = path.join(WORKTREE, 'build/web-orders-checkout-001');
const run = path.join(evidenceRoot, `browser-${Date.now()}-${randomUUID().slice(0, 8)}`);
const app = path.join(run, 'browser-app');
assert.ok(path.resolve(run).startsWith(path.resolve(evidenceRoot) + path.sep));
mkdirSync(app, { recursive: true });
for (const input of ['package.json', 'package-lock.json', 'next.config.mjs', 'tsconfig.json', '.nvmrc', 'app', 'src', 'messages', 'public']) {
  cpSync(path.join(ROOT, input), path.join(app, input), { recursive: true });
}
symlinkSync(path.join(ROOT, 'node_modules'), path.join(app, 'node_modules'), process.platform === 'win32' ? 'junction' : 'dir');
assert.equal(readFileSync(path.join(app, 'src/source/live/ordering.ts'), 'utf8'), gateSource, 'Evidence must exercise identical production admission source');
const committedHeaders = JSON.parse(readFileSync(path.join(ROOT, 'vercel.json'), 'utf8')).headers;
const globalHeaders = Object.fromEntries(committedHeaders.find((rule) => rule.source === '/(.*)').headers.map(({ key, value }) => [key.toLowerCase(), value]));
assert.match(globalHeaders['content-security-policy'], /connect-src 'self' https:\/\/oqmevrndtivqxgyvcmwy\.supabase\.co;/);

const children = new Set();
const servers = [];
const rpcCalls = [];
const summary = { workId: 'BIZBOT-PLATFORM-ONLINE-ORDERS-353', generatedAt: new Date().toISOString(), node: process.version, run, app, productionAdmissionSourceUnchanged: true, trackedGateSha256: createHash('sha256').update(gateSource).digest('hex'), hostedRequests: 0, status: 'running' };
const safeEnv = {};
for (const key of ['PATH', 'Path', 'SystemRoot', 'SYSTEMROOT', 'TEMP', 'TMP', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'COMSPEC', 'PATHEXT']) if (process.env[key]) safeEnv[key] = process.env[key];

const listen = (server) => new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', () => { servers.push(server); resolve(server.address().port); });
});
async function sparePort() {
  const server = createServer();
  const port = await new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
  await new Promise((resolve) => server.close(resolve));
  return port;
}
function launch(args, cwd, env, logFile) {
  const child = spawn(process.execPath, args, { cwd, env: { ...safeEnv, ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  children.add(child);
  let log = '';
  for (const stream of [child.stdout, child.stderr]) stream.on('data', (chunk) => { log += String(chunk); writeFileSync(logFile, log); });
  child.once('close', () => children.delete(child));
  return child;
}
const completion = (child) => new Promise((resolve, reject) => {
  child.once('error', reject);
  child.once('close', (code, signal) => code === 0 ? resolve() : reject(new Error(`Local command failed (${code ?? signal}); inspect evidence logs`)));
});
async function waitFor(url, child) {
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error('Local Next server exited before readiness');
    try { if ((await fetch(url)).status === 200) return; } catch { /* local startup */ }
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error('Local Next server readiness timed out');
}
async function stop(child) {
  if (child.exitCode !== null) return;
  if (process.platform === 'win32') {
    await new Promise((resolve) => spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' }).once('close', resolve));
  } else child.kill('SIGTERM');
}

try {
  const stub = createServer((req, res) => {
    let body = ''; let bytes = 0;
    req.on('data', (chunk) => { bytes += chunk.length; if (bytes <= 2048) body += chunk; else req.destroy(); });
    req.on('end', () => {
      let input;
      try { input = JSON.parse(body); } catch { res.writeHead(400).end(); return; }
      if (req.method !== 'POST' || req.url !== '/rest/v1/rpc/storefront_menu' || Object.keys(input).join(',') !== 'p_slug' || req.headers.apikey !== SYNTHETIC_KEY || req.headers.authorization !== `Bearer ${SYNTHETIC_KEY}`) { res.writeHead(400).end(); return; }
      const slug = input.p_slug;
      rpcCalls.push(slug);
      if (typeof slug !== 'string' || !/^sf-browser-[a-z0-9-]+$/.test(slug)) { res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(NOT_FOUND_ENVELOPE)); return; }
      const envelope = syntheticEnvelope({ restaurant: { slug, display_name: 'Synthetic Pickup Kitchen', tagline: 'Offline checkout verification', motion: 'calm' }, service: { ordering_enabled: !slug.endsWith('-off'), pickup_enabled: true, delivery_enabled: false } });
      envelope.items = envelope.items.map((item) => ({ ...item, image_url: null }));
      envelope.modifiers = envelope.modifiers.map((group) => group.id === SYNTH_IDS.extras ? { ...group, allow_quantity: true, max_quantity: 20, max_select: null } : group);
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(envelope));
    });
  });
  const stubPort = await listen(stub);
  const nextPort = await sparePort();
  const preload = path.join(run, 'local-only-fetch.mjs');
  writeFileSync(preload, `// Generated offline-only process boundary. No real service is contacted.\nconst originalFetch = globalThis.fetch;\nglobalThis.fetch = (input, init) => {\n const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;\n if (url === ${JSON.stringify(RPC)}) return originalFetch(${JSON.stringify(`http://127.0.0.1:${stubPort}/rest/v1/rpc/storefront_menu`)}, init);\n const parsed = new URL(url);\n if (parsed.protocol === 'http:' && parsed.hostname === '127.0.0.1') return originalFetch(input, init);\n throw new Error('offline_verification_remote_fetch_blocked');\n};\n`);
  const env = { NODE_ENV: 'production', NEXT_TELEMETRY_DISABLED: '1', STOREFRONT_SOURCE: 'live', STOREFRONT_SUPABASE_URL: PROJECT, STOREFRONT_SUPABASE_ANON_KEY: SYNTHETIC_KEY, NODE_OPTIONS: `--import=${pathToFileURL(preload).href}` };
  console.log(`Offline browser evidence: ${run}`);
  console.log('Building an isolated LIVE-mode copy with identical tenant-scoped admission source.');
  await completion(launch([path.join(app, 'node_modules/next/dist/bin/next'), 'build', '--webpack'], app, env, path.join(run, 'build.log')));
  assert.equal(readFileSync(GATE, 'utf8'), gateSource, 'Tracked admission source changed during evidence build');
  const manifest = JSON.parse(readFileSync(path.join(app, '.next/prerender-manifest.json'), 'utf8'));
  assert.deepEqual(Object.keys(manifest.routes).filter((route) => /\/(?:s|r)\//.test(route)), [], 'Live build must not prerender fixture tenants');
  const next = launch([path.join(app, 'node_modules/next/dist/bin/next'), 'start', '-p', String(nextPort), '-H', '127.0.0.1'], app, env, path.join(run, 'next.log'));
  await waitFor(`http://127.0.0.1:${nextPort}/healthz.json`, next);

  // Native loopback proxy applies exactly the committed Vercel response headers.
  const proxy = createServer((req, res) => {
    const upstream = httpRequest({ hostname: '127.0.0.1', port: nextPort, path: req.url, method: req.method, headers: req.headers }, (incoming) => {
      const headers = { ...incoming.headers, ...globalHeaders };
      if (req.url?.startsWith('/_next/static/')) Object.assign(headers, Object.fromEntries(committedHeaders.find((rule) => rule.source === '/_next/static/(.*)').headers.map(({ key, value }) => [key.toLowerCase(), value])));
      res.writeHead(incoming.statusCode ?? 502, headers); incoming.pipe(res);
    });
    upstream.once('error', () => { if (!res.headersSent) res.writeHead(502); res.end(); });
    req.pipe(upstream);
  });
  const proxyPort = await listen(proxy);
  const baseURL = `http://127.0.0.1:${proxyPort}`;
  const config = path.join(run, 'playwright.config.mjs');
  // Traces capture POST bodies and storage evaluations, including capabilities.
  // Screenshots/results prove the flow without recording those private bodies.
  writeFileSync(config, `import { defineConfig } from ${JSON.stringify(pathToFileURL(path.join(ROOT, 'node_modules/@playwright/test/index.mjs')).href)};\nexport default defineConfig({ testDir: ${JSON.stringify(path.join(ROOT, 'tests/browser'))}, testMatch: 'web-orders-checkout-001.spec.ts', workers: 1, fullyParallel: false, retries: 0, timeout: 60000, expect: { timeout: 12000 }, outputDir: ${JSON.stringify(path.join(run, 'test-results'))}, reporter: [['list'], ['json', { outputFile: ${JSON.stringify(path.join(run, 'results.json'))} }], ['html', { outputFolder: ${JSON.stringify(path.join(run, 'report'))}, open: 'never' }]], use: { baseURL: ${JSON.stringify(baseURL)}, headless: true, serviceWorkers: 'block', trace: 'off', screenshot: 'only-on-failure', video: 'off' }, projects: [{name:'chromium',use:{browserName:'chromium'}}] });\n`);
  console.log('Running Chromium against loopback with the committed CSP.');
  await completion(launch([path.join(ROOT, 'node_modules/@playwright/test/cli.js'), 'test', '--config', config], ROOT, { ...safeEnv, SF_WEB_ORDER_BASE: baseURL, SF_WEB_ORDER_RUN_DIR: run, SF_WEB_ORDER_ORIGINAL: ROOT, SF_WEB_ORDER_APP_DIR: app, NEXT_TELEMETRY_DISABLED: '1', NODE_OPTIONS: env.NODE_OPTIONS }, path.join(run, 'browser.log')));
  const results = JSON.parse(readFileSync(path.join(run, 'results.json'), 'utf8'));
  summary.stats = results.stats;
  summary.rpcReadCount = rpcCalls.length;
  summary.syntheticTenants = [...new Set(rpcCalls)].sort();
  summary.status = 'passed';
  console.log(`Chromium passed: ${results.stats.expected} checks; evidence ${run}`);
} catch (error) {
  summary.status = 'failed'; summary.failure = String(error.message);
  console.error(`Offline browser verification failed. Evidence: ${run}`);
  process.exitCode = 1;
} finally {
  assert.equal(readFileSync(GATE, 'utf8'), gateSource, 'Tracked admission source must remain unchanged');
  writeFileSync(path.join(run, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
  for (const child of children) await stop(child);
  for (const server of servers.reverse()) { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
}
