#!/usr/bin/env node
// Local preview: builds ./dist, serves it with the same clean-URL semantics
// Vercel applies (/en → /en/index.html) and mounts the /api/lead function in
// process so the form can be exercised end to end without deploying.
//   node scripts/dev.mjs [port]          (default 8787)
// Never used in production — Vercel serves dist/ and api/ itself.

import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { build } from './build.mjs';
import { createHandler } from '../lib/lead.mjs';

const port = Number(process.argv[2] || process.env.PORT || 8787);
const { dist } = build({ quiet: true });
const lead = createHandler();

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.ico': 'image/x-icon',
  '.mp4': 'video/mp4', '.woff2': 'font/woff2', '.xml': 'application/xml', '.txt': 'text/plain; charset=utf-8', '.webmanifest': 'application/manifest+json',
};

function wrap(res) {
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(o)); return res; };
  return res;
}

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/api/lead') {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    req.body = raw;
    return lead(req, wrap(res));
  }
  let p = normalize(decodeURIComponent(url.pathname)).replace(/^(\.\.[/\\])+/, '');
  let file = join(dist, p);
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  else if (!existsSync(file) && existsSync(file + '.html')) file += '.html';
  else if (!existsSync(file) && existsSync(join(dist, p, 'index.html'))) file = join(dist, p, 'index.html');
  if (!existsSync(file) || statSync(file).isDirectory()) {
    res.statusCode = 404;
    res.end('not found');
    return;
  }
  res.setHeader('Content-Type', TYPES[extname(file)] || 'application/octet-stream');
  res.end(readFileSync(file));
}).listen(port, () => console.log(`bizbot-site preview → http://localhost:${port}/  (en: /en, he: /he)`));
