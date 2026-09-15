#!/usr/bin/env node
// Per-route first-load JavaScript measurement, on both approved axes.
//
// Method, stated so it is reproducible and cannot flatter itself:
//  - Per DIRECT-LOAD ROUTE, not summed across the whole export.
//  - UNIQUE external script URLs only: a resource referenced both as <script
//    src> and as a preload/prefetch link counts ONCE.
//  - Speculative route prefetch is reported SEPARATELY and never folded in.
//  - Inline script bytes are reported separately, and the HTML document size is
//    reported too, so moving code into the document cannot hide it.
//  - Brotli models each response body compressed SEPARATELY, never the
//    compression of a concatenation. Quality is the documented default for
//    text, recorded below; it is not tuned until a check passes.
import { readFileSync, existsSync, statSync } from 'node:fs';
import { brotliCompressSync, gzipSync, constants } from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BUDGETS, ROUTES } from './budgets.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'out');

// Documented, fixed setting - recorded in the report, not tuned per run.
const BROTLI_PARAMS = {
  [constants.BROTLI_PARAM_MODE]: constants.BROTLI_MODE_TEXT,
  [constants.BROTLI_PARAM_QUALITY]: 11,
};
const brotli = (buf) => brotliCompressSync(buf, { params: BROTLI_PARAMS }).length;

/** Framework vs authored: authored code lives in our source, framework in node_modules. */
function roleOf(file) {
  const text = readFileSync(file, 'utf8');
  if (/BIZBOT|__BIZBOT_AUTHORED__/.test(text) && !/node_modules/.test(text)) return 'authored+framework';
  return 'framework';
}

export function measure(outDir = OUT) {
  const results = [];
  for (const { route, file } of ROUTES) {
    const htmlPath = path.join(outDir, file);
    if (!existsSync(htmlPath)) continue;
    const html = readFileSync(htmlPath, 'utf8');
    const htmlBytes = Buffer.byteLength(html);

    // External scripts actually executed on initial load.
    const eager = new Set();
    for (const m of html.matchAll(/<script[^>]+src="([^"]+)"/g)) eager.add(m[1]);

    // Preload/modulepreload of the SAME resources must not double count.
    const preloaded = new Set();
    for (const m of html.matchAll(/<link[^>]+rel="(?:preload|modulepreload)"[^>]*href="([^"]+)"/g)) preloaded.add(m[1]);
    // Speculative next-route prefetch, reported separately.
    const prefetch = new Set();
    for (const m of html.matchAll(/<link[^>]+rel="prefetch"[^>]*href="([^"]+)"/g)) {
      if (!eager.has(m[1])) prefetch.add(m[1]);
    }

    const assets = [];
    let raw = 0, br = 0, gz = 0;
    for (const url of [...eager].sort()) {
      const asset = path.join(outDir, url.replace(/^\//, ''));
      if (!existsSync(asset)) { assets.push({ url, missing: true }); continue; }
      const bytes = readFileSync(asset);
      const b = brotli(bytes);
      raw += bytes.length; br += b; gz += gzipSync(bytes, { level: 9 }).length;
      assets.push({
        url, bytes: bytes.length, brotli: b,
        role: roleOf(asset),
        alsoPreloaded: preloaded.has(url),
      });
    }

    // Inline script bytes, reported but never merged into the external total.
    let inlineBytes = 0;
    for (const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)) {
      inlineBytes += Buffer.byteLength(m[1]);
    }

    let prefetchBytes = 0;
    for (const url of prefetch) {
      const asset = path.join(outDir, url.replace(/^\//, ''));
      if (existsSync(asset)) prefetchBytes += statSync(asset).size;
    }

    results.push({
      route, document: file, htmlBytes,
      uniqueExternalScripts: assets.length,
      firstLoadUncompressed: raw,
      firstLoadBrotli: br,
      firstLoadGzip: gz,
      inlineScriptBytes: inlineBytes,
      speculativePrefetchBytes: prefetchBytes,
      speculativePrefetchCount: prefetch.size,
      assets,
    });
  }
  return results;
}

export function checkBudgets(results) {
  const problems = [];
  for (const r of results) {
    if (r.firstLoadUncompressed > BUDGETS.firstLoadJsBytes) {
      problems.push(`${r.route}: first-load JS ${r.firstLoadUncompressed} B > ${BUDGETS.firstLoadJsBytes} B uncompressed`);
    }
    if (r.firstLoadBrotli > BUDGETS.firstLoadJsBrotliBytes) {
      problems.push(`${r.route}: first-load JS ${r.firstLoadBrotli} B brotli > ${BUDGETS.firstLoadJsBrotliBytes} B`);
    }
    for (const a of r.assets) if (a.missing) problems.push(`${r.route}: missing asset ${a.url}`);
  }
  return problems;
}

if (process.argv[1]?.endsWith('measure-firstload.mjs')) {
  const results = measure();
  console.log(JSON.stringify({
    nodeVersion: process.version,
    brotli: { mode: 'BROTLI_MODE_TEXT', quality: 11, perResponse: true },
    note: 'LOCAL COMPRESSION ESTIMATE - modelled per response body, not observed transfer bytes',
    budgets: { uncompressed: BUDGETS.firstLoadJsBytes, brotli: BUDGETS.firstLoadJsBrotliBytes },
    routes: results,
  }, null, 2));
  const problems = checkBudgets(results);
  if (problems.length) {
    console.error('\nFIRST-LOAD BUDGET FAILED:');
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  } else {
    console.log('\nFIRST-LOAD BUDGET PASSED on both axes, per route');
  }
}
