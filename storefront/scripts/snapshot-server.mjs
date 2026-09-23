#!/usr/bin/env node
// STOREFRONT-READ-001 - the server-render SNAPSHOT lane.
//
// The storefront is no longer a static export (owner decisions D2 / D13):
// `next build` produces a server build and no `out/` tree. Every output gate
// (scripts/audit-output.mjs, scripts/measure-firstload.mjs, tests/output,
// scripts/serve-out.mjs and the Playwright suites) reads a directory of
// documents plus static assets, so this lane MATERIALISES one: it starts the
// real `next start`, fetches every canonical route exactly as a browser's first
// request would, and writes the responses to `out/` in the shape the export
// used to have (`<route>.html`, one RSC flight payload as `<route>.txt`,
// `_next/static/**`, `public/**`, `404.html`).
//
// What it records that a static export could not: the SERVED response headers
// per document (Cache-Control is the ISR contract: s-maxage=60 with a
// stale-while-revalidate window from expireTime), the per-document byte size,
// and the server bundle size, in `out/SNAPSHOT.json` - reported separately from
// the client static budget, never folded into it (packet §7.1).
//
// Local emulation only: `next start` applies none of the committed vercel.json
// headers (serve-out.mjs adds them on top of the snapshot), and the CDN in
// front of the deployment may rewrite the browser-facing Cache-Control. Hosted
// behaviour is verified at the hosted gate, not here.
import { spawn } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ROUTES } from './budgets.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const NEXT_DIR = path.join(ROOT, '.next');
const OUT = path.join(ROOT, 'out');
const PORT = Number(process.env.STOREFRONT_SNAPSHOT_PORT ?? 4600);
const BASE = `http://127.0.0.1:${PORT}`;
// A slug no source resolves: the 404 document the host would serve.
const UNKNOWN_ROUTE = '/s/no-such-storefront-9f3a';

function dirBytes(dir) {
  if (!existsSync(dir)) return 0;
  let total = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    total += entry.isDirectory() ? dirBytes(full) : statSync(full).size;
  }
  return total;
}

async function waitFor(url, ms) {
  const deadline = Date.now() + ms;
  for (;;) {
    try {
      const res = await fetch(url);
      if (res.status < 500) return;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error(`next start did not answer at ${url} within ${ms} ms`);
    await new Promise((r) => setTimeout(r, 250));
  }
}

function startServer() {
  const bin = path.join(ROOT, 'node_modules', 'next', 'dist', 'bin', 'next');
  const child = spawn(process.execPath, [bin, 'start', '-p', String(PORT), '-H', '127.0.0.1'], {
    cwd: ROOT,
    env: { ...process.env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const log = [];
  child.stdout.on('data', (d) => log.push(String(d)));
  child.stderr.on('data', (d) => log.push(String(d)));
  return { child, log };
}

function stopServer(child) {
  if (process.platform === 'win32') {
    // `next start` forks the real server; kill the whole tree.
    spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
  } else {
    child.kill('SIGTERM');
  }
}

/**
 * Fetch one URL as a first visit; never follow a redirect silently. The one
 * documented exception is the RSC flight request: the server answers a first
 * `RSC: 1` request with a 307 to the same path plus its `?_rsc=` cache-busting
 * query, so that single hop is followed with the same headers and recorded.
 */
async function get(pathname, headers = {}) {
  let res = await fetch(`${BASE}${pathname}`, { headers, redirect: 'manual' });
  if (headers.RSC === '1' && res.status === 307 && res.headers.get('location')?.startsWith(`${pathname}?_rsc`)) {
    res = await fetch(`${BASE}${res.headers.get('location')}`, { headers, redirect: 'manual' });
  }
  const body = Buffer.from(await res.arrayBuffer());
  const picked = {};
  for (const name of ['cache-control', 'content-type', 'set-cookie', 'x-nextjs-cache', 'x-nextjs-prerender', 'vary', 'location']) {
    const value = res.headers.get(name);
    if (value !== null) picked[name] = value;
  }
  return { status: res.status, headers: picked, body };
}

export async function snapshot() {
  if (!existsSync(path.join(NEXT_DIR, 'BUILD_ID'))) {
    throw new Error('.next/BUILD_ID is missing - run `npm run build` first');
  }
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });

  // 1. static assets exactly as the server serves them, and the public files
  cpSync(path.join(NEXT_DIR, 'static'), path.join(OUT, '_next', 'static'), { recursive: true });
  for (const name of readdirSync(path.join(ROOT, 'public'))) {
    cpSync(path.join(ROOT, 'public', name), path.join(OUT, name), { recursive: true });
  }

  const { child, log } = startServer();
  const documents = [];
  const problems = [];
  try {
    await waitFor(`${BASE}/healthz.json`, 60_000);

    // 2. every canonical route: the document and its RSC flight payload
    for (const { route, file } of ROUTES) {
      const doc = await get(route);
      if (doc.status !== 200) problems.push(`${route}: HTTP ${doc.status} (expected 200)`);
      const target = path.join(OUT, file);
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, doc.body);
      const flight = await get(route, { RSC: '1' });
      if (flight.status !== 200 || !/text\/x-component/.test(flight.headers['content-type'] ?? '')) {
        problems.push(`${route}: RSC flight HTTP ${flight.status} ${flight.headers['content-type'] ?? ''} (expected 200 text/x-component)`);
      }
      writeFileSync(target.replace(/\.html$/, '.txt'), flight.body);
      documents.push({
        route,
        file,
        status: doc.status,
        bytes: doc.body.length,
        flightStatus: flight.status,
        flightBytes: flight.body.length,
        headers: doc.headers,
      });
    }

    // 3. the 404 document, from a slug no source resolves
    const missing = await get(UNKNOWN_ROUTE);
    if (missing.status !== 404) problems.push(`${UNKNOWN_ROUTE}: HTTP ${missing.status} (expected 404)`);
    writeFileSync(path.join(OUT, '404.html'), missing.body);
    documents.push({ route: UNKNOWN_ROUTE, file: '404.html', status: missing.status, bytes: missing.body.length, flightBytes: 0, headers: missing.headers });
  } finally {
    stopServer(child);
  }

  const record = {
    generatedAt: new Date().toISOString(),
    nodeVersion: process.version,
    source: process.env.STOREFRONT_SOURCE ?? 'fixture',
    buildId: existsSync(path.join(NEXT_DIR, 'BUILD_ID')) ? readFileSync(path.join(NEXT_DIR, 'BUILD_ID'), 'utf8').trim() : null,
    port: PORT,
    clientStaticBytes: dirBytes(path.join(NEXT_DIR, 'static')),
    // The server artifact: Vercel-managed, reported in its own row, never a
    // static-ceiling figure.
    serverBundleBytes: dirBytes(path.join(NEXT_DIR, 'server')),
    documents,
    problems,
    note: 'LOCAL next start snapshot; vercel.json headers are NOT applied here (serve-out.mjs adds them); the hosted CDN may rewrite Cache-Control.',
  };
  writeFileSync(path.join(OUT, 'SNAPSHOT.json'), JSON.stringify(record, null, 2) + '\n');
  if (problems.length) {
    console.error(log.join(''));
  }
  return record;
}

if (process.argv[1]?.endsWith('snapshot-server.mjs')) {
  snapshot().then((record) => {
    const worst = record.documents.reduce((a, d) => (d.bytes > (a?.bytes ?? -1) ? d : a), null);
    console.log(`snapshot: ${record.documents.length} documents -> out/; client static ${record.clientStaticBytes} B; server bundle ${record.serverBundleBytes} B; largest document ${worst?.route} ${worst?.bytes} B`);
    for (const d of record.documents) {
      console.log(`  ${String(d.status).padEnd(3)} ${d.route.padEnd(32)} ${String(d.bytes).padStart(8)} B  rsc ${String(d.flightBytes).padStart(7)} B  ${d.headers['cache-control'] ?? '(no cache-control)'}`);
    }
    if (record.problems.length) {
      console.error('\nSNAPSHOT PROBLEMS:');
      for (const p of record.problems) console.error('  - ' + p);
      process.exitCode = 1;
    }
  }).catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
