// Local delivery evidence, not a Vercel CDN measurement or a real-service save.
// No Playwright routes: routing disables HTTP cache and invalidates this proof.
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { verifyPrepared } from './prepare.mjs';
const web = new URL('../web/product-cutout/', import.meta.url);
const manifest = await verifyPrepared();
const config = JSON.parse(await readFile(new URL('../../../vercel.json', import.meta.url), 'utf8'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const input = await readFile(process.argv[2]);
const paths = new Set([...manifest.sources.map(file => file.file), 'asset-manifest.json',
  ...manifest.files.map(file => `assets/${manifest.revision}/${file.file}`)]);
const requests = [];
let phase = 'initial';
// These are the committed configuration's processor-only patterns. Reject new
// pattern forms until this local measurement adapter is reviewed with them.
const headers = config.headers.map(rule => {
  assert.ok(rule.source.startsWith('/product-cutout/'));
  let source = rule.source;
  if (source.includes(':revision')) {
    assert.equal(source, '/product-cutout/assets/:revision([0-9a-f]{64})/:file');
    source = '/product-cutout/assets/[0-9a-f]{64}/[^/]+';
  } else assert.ok(/^\/product-cutout\/(?:\(\.\*\)(?:\.(?:mjs|wasm|bin|json|txt))?|\(\(\?!assets\/\)\.\*\))$/.test(source));
  return { match: new RegExp(`^${source}$`), headers: rule.headers };
});
const server = createServer(async (req, res) => {
  const path = new URL(req.url, 'http://127.0.0.1').pathname;
  if (path === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end('<title>Local processor cache measurement</title><script src="/product-cutout/bootstrap.js"></script>'); return;
  }
  const relative = path.replace(/^\/product-cutout\//, '');
  if (!paths.has(relative)) { res.writeHead(404, { 'Cache-Control': 'no-store' }).end(); return; }
  try {
    const bytes = await readFile(new URL(relative, web));
    const etag = `"${hash(bytes)}"`;
    res.setHeader('ETag', etag);
    for (const rule of headers) if (rule.match.test(path)) for (const header of rule.headers) res.setHeader(header.key, header.value);
    if (relative.endsWith('.js')) res.setHeader('Content-Type', 'application/javascript');
    const status = req.headers['if-none-match'] === etag ? 304 : 200;
    requests.push({ phase, path, status, bodyBytes: status === 304 ? 0 : bytes.length, cacheControl: res.getHeader('Cache-Control') ?? null, mime: res.getHeader('Content-Type') ?? null });
    if (status === 304) { res.writeHead(304).end(); return; }
    res.setHeader('Content-Length', bytes.length); res.end(bytes);
  } catch { res.writeHead(500).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const profile = await mkdtemp(join(tmpdir(), 'bizbot-cache-profile-'));
const context = await chromium.launchPersistentContext(profile, { channel: 'chrome', headless: true, serviceWorkers: 'block',
  args: ['--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1'] });
try {
  const page = await context.newPage();
  page.on('console', message => { if (message.type() === 'log') console.log(message.text()); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(origin);
  assert.equal(requests.some(request => request.path.includes('/assets/')), false, 'Opening the page fetches no runtime/model assets');
  for (const missing of ['/product-cutout/missing.mjs', `/product-cutout/assets/${manifest.revision}/missing.bin`]) {
    const response = await context.request.get(origin + missing);
    assert.equal(response.status(), 404); assert.doesNotMatch(await response.text(), /<html|<title/i);
  }
  const runs = [];
  for (const run of ['cold', 'warm']) {
    phase = run;
    await page.goto(origin); // Same context/browser cache; no worker survives.
    const result = await page.evaluate(async encoded => {
      const source = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
      const stages = []; const start = performance.now();
      const bridge = await import('/product-cutout/bridge.mjs');
      const output = await bridge.process(source, 'image/jpeg', stage => { stages.push(stage); console.log(stage); });
      const sha256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', output.bytes))].map(byte => byte.toString(16).padStart(2, '0')).join('');
      return { elapsedMs: performance.now() - start, stages, width: output.width, height: output.height,
        bytes: output.bytes.length, sha256, mimeType: output.mimeType, alreadyTransparent: output.alreadyTransparent };
    }, input.toString('base64'));
    const transferred = requests.filter(request => request.phase === run);
    runs.push({ phase: run, ...result, requests: transferred.length,
      modelRequests: transferred.filter(request => /u2net-\d{2}\.bin$/.test(request.path)).length,
      assetBodyBytes: transferred.filter(request => request.path.includes('/assets/')).reduce((sum, request) => sum + request.bodyBytes, 0),
      allBodyBytes: transferred.reduce((sum, request) => sum + request.bodyBytes, 0) });
    console.log(JSON.stringify(runs.at(-1)));
  }
  assert.deepEqual(errors, []);
  assert.equal(runs[0].modelRequests, 11);
  // Cache eviction/refetch is a valid measured outcome, not grounds to change
  // browser cache quotas or claim success from a smaller model/fixture.
  for (const request of requests.filter(request => request.path.includes('/assets/'))) assert.equal(request.cacheControl, 'public, max-age=31536000, immutable');
  assert.equal(runs[0].sha256, runs[1].sha256);
  await writeFile(process.argv[3], JSON.stringify({ kind: 'unrouted-loopback-http-cache', browser: context.browser().version(), profile: 'fresh persistent profile, default cache quota',
    source: { bytes: input.length, sha256: hash(input) }, revision: manifest.revision,
    preparedAssetBytes: manifest.files.reduce((sum, file) => sum + file.bytes, 0),
    transport: 'Actual HTTP response body bytes from local uncompressed server using committed processor headers; excludes protocol overhead. Not production CDN traffic.',
    retention: 'Same fresh browser context only. Storage eviction, other browsers/devices, changed asset revisions and later cold visits can download again.',
    runs, requests }, null, 2) + '\n');
} finally {
  await context.close(); server.close();
  const target = resolve(profile);
  assert.ok(target.startsWith(resolve(tmpdir()) + sep) && target.includes('bizbot-cache-profile-'));
  await rm(target, { recursive: true, force: true });
}
