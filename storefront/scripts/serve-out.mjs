#!/usr/bin/env node
// Localhost static server for the REAL exported out/ tree.
//
// It applies the header set parsed from the COMMITTED storefront/vercel.json, so
// a browser check can never accidentally run without the CSP it is meant to
// test. cleanUrls/trailingSlash handling here is LOCAL EMULATION of the
// documented Vercel behaviour - it is not hosted verification, which happens
// only after the separate project-creation gate.
import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'out');
const CONFIG = JSON.parse(readFileSync(path.join(ROOT, 'vercel.json'), 'utf8'));

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.webmanifest': 'application/manifest+json',
};

// Vercel `source` patterns are path regexes; only the two committed shapes are
// emulated, deliberately and explicitly.
function headersFor(pathname) {
  const applied = {};
  for (const rule of CONFIG.headers ?? []) {
    let match = false;
    if (rule.source === '/(.*)') match = true;
    else if (rule.source === '/_next/static/(.*)') match = pathname.startsWith('/_next/static/');
    if (match) for (const h of rule.headers) applied[h.key] = h.value;
  }
  return applied;
}

/** Resolve a URL path to a file inside out/, or null. Never escapes out/. */
function resolveFile(pathname) {
  const decoded = decodeURIComponent(pathname);
  if (decoded.includes('\0')) return null;
  const candidate = path.resolve(OUT, '.' + decoded);
  if (candidate !== OUT && !candidate.startsWith(OUT + path.sep)) return null; // traversal
  if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  return null;
}

export function createStaticServer() {
  return createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    let pathname = url.pathname;
    const search = url.search;

    const send = (status, body, extra = {}) => {
      const headers = { ...headersFor(pathname), ...extra };
      res.writeHead(status, headers);
      res.end(req.method === 'HEAD' ? undefined : body);
    };
    const redirect = (to) => {
      // 308 preserves method AND the query string.
      send(308, '', { Location: to + search, 'Content-Type': 'text/plain; charset=utf-8' });
    };

    if (req.method !== 'GET' && req.method !== 'HEAD') return send(405, 'Method Not Allowed');

    // trailingSlash: false -> /ar/ canonicalises to /ar
    if (CONFIG.trailingSlash === false && pathname.length > 1 && pathname.endsWith('/')) {
      return redirect(pathname.replace(/\/+$/, ''));
    }
    // cleanUrls: true -> /ar.html canonicalises to /ar, and /ar serves ar.html
    if (CONFIG.cleanUrls === true && pathname.endsWith('.html')) {
      const clean = pathname.slice(0, -'.html'.length);
      return redirect(clean === '/index' ? '/' : clean);
    }

    let file = resolveFile(pathname === '/' ? '/index.html' : pathname);
    if (!file && CONFIG.cleanUrls === true && !path.extname(pathname)) {
      file = resolveFile(pathname + '.html');
    }

    if (!file) {
      // A genuine 404 status, never index.html with 200.
      const notFound = path.join(OUT, '404.html');
      const body = existsSync(notFound) ? readFileSync(notFound) : 'Not Found';
      return send(404, body, { 'Content-Type': TYPES['.html'] });
    }

    const type = TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream';
    return send(200, readFileSync(file), { 'Content-Type': type });
  });
}

export function startStaticServer(port = 0) {
  return new Promise((resolve) => {
    const server = createStaticServer();
    // Localhost only.
    server.listen(port, '127.0.0.1', () => resolve({ server, port: server.address().port }));
  });
}

if (process.argv[1]?.endsWith('serve-out.mjs')) {
  const port = Number(process.env.PORT ?? 4321);
  startStaticServer(port).then(({ port: actual }) => {
    console.log(`serving ${OUT} on http://127.0.0.1:${actual} with committed vercel.json headers`);
  });
}
