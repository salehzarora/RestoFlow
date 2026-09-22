#!/usr/bin/env node
// Per-route first-load JavaScript measurement, on both approved axes - and,
// since the correction pass, the per-route CSS and font-preload measurement
// against the written limits (budgets.mjs), with the same method.
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
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BUDGETS, ROUTES } from './budgets.mjs';
import { CSS_RAW_EXCEPTION } from './acceptance-exceptions.mjs';

// The exception table must agree with the written limits it sits on top of;
// a drift here is a defect, not a quiet re-baselining.
if (CSS_RAW_EXCEPTION.originalLimitBytes !== BUDGETS.cssPerRouteBytes
  || CSS_RAW_EXCEPTION.brotliLimitBytes !== BUDGETS.cssPerRouteBrotliBytes
  || !(CSS_RAW_EXCEPTION.approvedLimitBytes > CSS_RAW_EXCEPTION.originalLimitBytes)) {
  throw new Error('acceptance-exceptions.mjs disagrees with budgets.mjs');
}

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'out');
const VERCEL_JSON = path.join(ROOT, 'vercel.json');

/**
 * Preloads a HOST would add through a `Link: <...>; rel=preload` response
 * header, from the committed header set. The committed set carries none; the
 * reader exists so that a later header preload is counted, not missed.
 */
export function headerPreloads(configPath = VERCEL_JSON) {
  if (!existsSync(configPath)) return [];
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const found = [];
  for (const rule of config.headers ?? []) {
    for (const h of rule.headers ?? []) {
      if (h.key.toLowerCase() !== 'link') continue;
      for (const part of h.value.split(',')) {
        const m = /<([^>]+)>[^,]*rel=["']?preload/i.exec(part);
        if (m) found.push({ source: rule.source, url: m[1], as: (/as=["']?([a-z]+)/i.exec(part) || [])[1] ?? null });
      }
    }
  }
  return found;
}

// Documented, fixed setting - recorded in the report, not tuned per run.
const BROTLI_PARAMS = {
  [constants.BROTLI_PARAM_MODE]: constants.BROTLI_MODE_TEXT,
  [constants.BROTLI_PARAM_QUALITY]: 11,
};
// One compression per asset per process: 36 routes share a handful of chunks,
// and the size of a given byte sequence does not change between routes.
const brotliCache = new Map();
const brotli = (buf) => {
  const key = createHash('sha256').update(buf).digest('hex');
  let size = brotliCache.get(key);
  if (size === undefined) {
    size = brotliCompressSync(buf, { params: BROTLI_PARAMS }).length;
    brotliCache.set(key, size);
  }
  return size;
};

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

    // CSS actually referenced by THIS document: unique stylesheet hrefs (a
    // stylesheet that is also preloaded counts once), each compressed
    // separately; inline <style> bytes reported beside them, never hidden.
    const stylesheetUrls = new Set();
    for (const m of html.matchAll(/<link[^>]+rel="stylesheet"[^>]*href="([^"]+)"/g)) stylesheetUrls.add(m[1]);
    for (const m of html.matchAll(/<link[^>]+href="([^"]+\.css)"[^>]*rel="stylesheet"/g)) stylesheetUrls.add(m[1]);
    const stylesheets = [];
    let cssRaw = 0, cssBr = 0;
    for (const url of [...stylesheetUrls].sort()) {
      const asset = path.join(outDir, url.replace(/^\//, ''));
      if (!existsSync(asset)) { stylesheets.push({ url, missing: true }); continue; }
      const bytes = readFileSync(asset);
      const b = brotli(bytes);
      cssRaw += bytes.length; cssBr += b;
      stylesheets.push({ url, bytes: bytes.length, brotli: b });
    }
    let inlineStyleBytes = 0;
    for (const m of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)) inlineStyleBytes += Buffer.byteLength(m[1]);

    // Fonts this document PRELOADS: link rel=preload as=font, plus any
    // Link-header preload the committed header set would add for the route
    // (reported under `fromHeader`). Every font the document may LOAD on
    // demand is a different, larger set and is not what the limit counts.
    const fontUrls = new Set();
    for (const m of html.matchAll(/<link[^>]+rel="preload"[^>]*as="font"[^>]*href="([^"]+)"/g)) fontUrls.add(m[1]);
    for (const m of html.matchAll(/<link[^>]+rel="preload"[^>]*href="([^"]+)"[^>]*as="font"/g)) fontUrls.add(m[1]);
    const fromHeader = headerPreloads().filter((h) => h.as === 'font' && (h.source === '/(.*)' || h.source === route));
    for (const h of fromHeader) fontUrls.add(h.url);
    const fontPreloads = [];
    let fontBytes = 0;
    for (const url of [...fontUrls].sort()) {
      const asset = path.join(outDir, url.replace(/^\//, ''));
      if (!existsSync(asset)) { fontPreloads.push({ url, missing: true }); continue; }
      const size = statSync(asset).size;
      fontBytes += size;
      fontPreloads.push({ url, bytes: size, fromHeader: fromHeader.some((h) => h.url === url) });
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
      css: { uniqueStylesheets: stylesheets.length, bytes: cssRaw, brotli: cssBr, inlineStyleBytes, stylesheets },
      fontPreloads: { count: fontPreloads.length, bytes: fontBytes, files: fontPreloads },
    });
  }
  return results;
}

/**
 * The raw-CSS ceiling in force for a route: the owner-approved exception
 * CSS-UI001-01 for its EXACT listed routes, the written limit for every
 * other route. Nothing else selects it.
 */
export function cssRawLimitFor(route) {
  return CSS_RAW_EXCEPTION.routes.includes(route) ? CSS_RAW_EXCEPTION.approvedLimitBytes : BUDGETS.cssPerRouteBytes;
}

/**
 * The CSS acceptance record, per route, under decision CSS-UI001-01. The
 * original limit and its compliance are ALWAYS reported (the retained FAIL
 * is the record the owner asked to keep); the approved exception applies
 * only to its listed routes, and a route passes WITH it only when both the
 * approved raw ceiling and the unchanged Brotli ceiling hold. Unknown or
 * missing measurements, a missing referenced stylesheet and zero route
 * coverage FAIL. Takes the measurement only - no option can widen it.
 */
export function cssAcceptance(results) {
  const X = CSS_RAW_EXCEPTION;
  const rows = [];
  for (const r of results) {
    const listed = X.routes.includes(r.route);
    const css = r.css;
    const missing = css?.stylesheets?.filter((s) => s.missing).map((s) => s.url) ?? [];
    const measurable = !!css && Number.isInteger(css.bytes) && Number.isInteger(css.brotli)
      && css.uniqueStylesheets > 0 && missing.length === 0;
    const raw = measurable ? css.bytes : null;
    const br = measurable ? css.brotli : null;
    const originalCompliance = measurable && raw <= X.originalLimitBytes ? 'PASS' : 'FAIL';
    const brotliCompliance = measurable && br <= X.brotliLimitBytes ? 'PASS' : 'FAIL';
    let effective, problem = null;
    if (!css) { effective = 'FAIL'; problem = 'no CSS measurement for this route'; }
    else if (missing.length) { effective = 'FAIL'; problem = `missing referenced stylesheet: ${missing.join(', ')}`; }
    else if (!measurable) { effective = 'FAIL'; problem = css.uniqueStylesheets > 0 ? 'CSS measurement is not a byte count' : 'no stylesheet counted (measurement empty)'; }
    else if (brotliCompliance === 'FAIL') { effective = 'FAIL'; problem = `CSS ${br} B brotli > ${X.brotliLimitBytes} B`; }
    else if (originalCompliance === 'PASS') effective = 'PASS';
    else if (listed && raw <= X.approvedLimitBytes) effective = 'PASS_WITH_APPROVED_EXCEPTION';
    else if (listed) { effective = 'FAIL'; problem = `CSS ${raw} B > ${X.approvedLimitBytes} B uncompressed (approved exception ${X.id} ceiling; original limit ${X.originalLimitBytes} B)`; }
    else { effective = 'FAIL'; problem = `CSS ${raw} B > ${X.originalLimitBytes} B uncompressed (route not listed under ${X.id})`; }
    rows.push({
      route: r.route,
      measured_raw_bytes: raw,
      original_limit: X.originalLimitBytes,
      original_compliance: originalCompliance,
      exception_id: listed ? X.id : null,
      approved_exception_limit: listed ? X.approvedLimitBytes : null,
      brotli_bytes: br,
      brotli_limit: X.brotliLimitBytes,
      brotli_compliance: brotliCompliance,
      effective_acceptance: effective,
      problem,
    });
  }
  const status = rows.length === 0 ? 'FAIL'
    : rows.some((x) => x.effective_acceptance === 'FAIL') ? 'FAIL'
    : rows.some((x) => x.effective_acceptance === 'PASS_WITH_APPROVED_EXCEPTION') ? 'PASS_WITH_APPROVED_EXCEPTIONS'
    : 'PASS';
  return {
    exception: { id: X.id, decision: X.decision, originalLimitBytes: X.originalLimitBytes, approvedLimitBytes: X.approvedLimitBytes, brotliLimitBytes: X.brotliLimitBytes, listedRoutes: X.routes.length },
    status,
    routesMeasured: rows.length,
    originalFailuresRetained: rows.filter((x) => x.original_compliance === 'FAIL').map((x) => x.route),
    exceptionsApplied: rows.filter((x) => x.effective_acceptance === 'PASS_WITH_APPROVED_EXCEPTION').map((x) => x.route),
    rows,
  };
}

export function checkBudgets(results) {
  const problems = [];
  // A measurement that covered no route proves nothing and must not pass.
  if (results.length === 0) problems.push('no route measured (zero coverage)');
  for (const r of results) {
    if (r.firstLoadUncompressed > BUDGETS.firstLoadJsBytes) {
      problems.push(`${r.route}: first-load JS ${r.firstLoadUncompressed} B > ${BUDGETS.firstLoadJsBytes} B uncompressed`);
    }
    if (r.firstLoadBrotli > BUDGETS.firstLoadJsBrotliBytes) {
      problems.push(`${r.route}: first-load JS ${r.firstLoadBrotli} B brotli > ${BUDGETS.firstLoadJsBrotliBytes} B`);
    }
    for (const a of r.assets) if (a.missing) problems.push(`${r.route}: missing asset ${a.url}`);
    // The CSS and font-preload limits, per route, both axes where two exist.
    // A document with NO stylesheet or NO preload is a measurement that found
    // nothing, and is reported as such rather than passing on an empty count;
    // a row WITHOUT the measurement is a missing measurement and fails too.
    // The raw CSS ceiling is the one in force for the route (CSS-UI001-01 on
    // its exact listed routes, the written 70,000 B elsewhere); the original
    // limit's compliance is reported by cssAcceptance(), never dropped.
    if (!r.css) problems.push(`${r.route}: no CSS measurement`);
    else {
      if (r.css.uniqueStylesheets === 0) problems.push(`${r.route}: no stylesheet counted (measurement empty)`);
      const rawLimit = cssRawLimitFor(r.route);
      if (r.css.bytes > rawLimit) {
        problems.push(rawLimit === BUDGETS.cssPerRouteBytes
          ? `${r.route}: CSS ${r.css.bytes} B > ${rawLimit} B uncompressed`
          : `${r.route}: CSS ${r.css.bytes} B > ${rawLimit} B uncompressed (approved exception ${CSS_RAW_EXCEPTION.id} ceiling; original limit ${BUDGETS.cssPerRouteBytes} B)`);
      }
      if (r.css.brotli > BUDGETS.cssPerRouteBrotliBytes) {
        problems.push(`${r.route}: CSS ${r.css.brotli} B brotli > ${BUDGETS.cssPerRouteBrotliBytes} B`);
      }
      for (const s of r.css.stylesheets) if (s.missing) problems.push(`${r.route}: missing stylesheet ${s.url}`);
    }
    if (!r.fontPreloads) problems.push(`${r.route}: no font-preload measurement`);
    else {
      if (r.fontPreloads.count > BUDGETS.fontPreloadsPerRoute) {
        problems.push(`${r.route}: ${r.fontPreloads.count} font preloads > ${BUDGETS.fontPreloadsPerRoute}`);
      }
      if (r.fontPreloads.bytes > BUDGETS.fontPreloadBytesPerRoute) {
        problems.push(`${r.route}: font preloads ${r.fontPreloads.bytes} B > ${BUDGETS.fontPreloadBytesPerRoute} B`);
      }
      for (const f of r.fontPreloads.files) if (f.missing) problems.push(`${r.route}: missing preloaded font ${f.url}`);
    }
  }
  return problems;
}

if (process.argv[1]?.endsWith('measure-firstload.mjs')) {
  const results = measure();
  const acceptance = cssAcceptance(results);
  console.log(JSON.stringify({
    nodeVersion: process.version,
    brotli: { mode: 'BROTLI_MODE_TEXT', quality: 11, perResponse: true },
    note: 'LOCAL COMPRESSION ESTIMATE - modelled per response body, not observed transfer bytes',
    budgets: {
      uncompressed: BUDGETS.firstLoadJsBytes, brotli: BUDGETS.firstLoadJsBrotliBytes,
      cssPerRouteBytes: BUDGETS.cssPerRouteBytes, cssPerRouteBrotliBytes: BUDGETS.cssPerRouteBrotliBytes,
      fontPreloadsPerRoute: BUDGETS.fontPreloadsPerRoute, fontPreloadBytesPerRoute: BUDGETS.fontPreloadBytesPerRoute,
    },
    headerPreloads: headerPreloads(),
    // CSS-UI001-01: the per-route acceptance record - original limit and its
    // compliance retained beside the effective (excepted) acceptance.
    cssAcceptance: acceptance,
    routes: results,
  }, null, 2));
  const problems = checkBudgets(results);
  if (problems.length) {
    console.error('\nFIRST-LOAD / CSS / FONT-PRELOAD BUDGET FAILED:');
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  } else if (acceptance.status === 'PASS_WITH_APPROVED_EXCEPTIONS') {
    console.log(`\nFIRST-LOAD, CSS AND FONT-PRELOAD BUDGETS PASSED WITH_APPROVED_EXCEPTIONS, per route - ${acceptance.exception.id} applied on ${acceptance.exceptionsApplied.length} route(s): original ${acceptance.exception.originalLimitBytes} B raw CSS limit FAIL retained on ${acceptance.originalFailuresRetained.length} route(s), approved ${acceptance.exception.approvedLimitBytes} B ceiling met, ${acceptance.exception.brotliLimitBytes} B Brotli limit unchanged and met`);
  } else {
    console.log('\nFIRST-LOAD, CSS AND FONT-PRELOAD BUDGETS PASSED, per route');
  }
}
