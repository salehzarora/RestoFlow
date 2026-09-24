#!/usr/bin/env node
// Post-build audit of storefront/out - since STOREFRONT-READ-001 the SNAPSHOT
// that scripts/snapshot-server.mjs materialises from a real `next start` (the
// storefront is server-rendered; there is no static export): size budgets,
// forbidden artefacts, the required document set, and emitted lang/dir. Exits
// non-zero on any violation.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { brotliCompressSync } from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BUDGETS, MEDIA_EXTENSIONS, MEDIA_PATH_PREFIX, REQUIRED_HTML, REQUIRED_STATIC, EXPECTED_DOCUMENT } from './budgets.mjs';
import { measure, checkBudgets, cssAcceptance } from './measure-firstload.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'out');

export function walk(dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isSymbolicLink()) found.push({ path: full, symlink: true, size: 0 });
    else if (entry.isDirectory()) found.push(...walk(full));
    else found.push({ path: full, symlink: false, size: statSync(full).size });
  }
  return found;
}

export function auditOutput(outDir = OUT) {
  const problems = [];
  if (!existsSync(outDir)) return { problems: ['out/ does not exist - run npm run build, then node scripts/snapshot-server.mjs'], stats: null };

  const files = walk(outDir);
  const rel = (p) => path.relative(outDir, p).split(path.sep).join('/');
  const total = files.reduce((sum, f) => sum + f.size, 0);

  if (total > BUDGETS.totalOutBytes) problems.push(`out/ is ${total} bytes, budget ${BUDGETS.totalOutBytes}`);

  for (const f of files) {
    if (f.symlink) problems.push(`symlink in output: ${rel(f.path)}`);
    if (f.size > BUDGETS.singleFileBytes) problems.push(`${rel(f.path)} is ${f.size} bytes, budget ${BUDGETS.singleFileBytes}`);
    if (f.path.endsWith('.map')) problems.push(`source map emitted: ${rel(f.path)}`);
    if (MEDIA_EXTENSIONS.includes(path.extname(f.path).toLowerCase())) problems.push(`reference media emitted: ${rel(f.path)}`);
  }

  for (const name of [...REQUIRED_HTML, ...REQUIRED_STATIC]) {
    if (!existsSync(path.join(outDir, name))) problems.push(`missing required output: ${name}`);
  }

  // Emitted lang/dir, as served, before any hydration.
  const documents = {};
  for (const [name, expected] of Object.entries(EXPECTED_DOCUMENT)) {
    const file = path.join(outDir, name);
    if (!existsSync(file)) continue;
    const tag = /<html[^>]*>/.exec(readFileSync(file, 'utf8'));
    const lang = tag ? (/lang="([^"]*)"/.exec(tag[0]) || [])[1] : undefined;
    const dir = tag ? (/dir="([^"]*)"/.exec(tag[0]) || [])[1] : undefined;
    documents[name] = { lang, dir };
    if (lang !== expected.lang) problems.push(`${name} has lang=${lang}, expected ${expected.lang}`);
    if (dir !== expected.dir) problems.push(`${name} has dir=${dir}, expected ${expected.dir}`);
  }

  // 404 is Next's built-in /_not-found: recorded evidence, not an assertion.
  // It must not carry a WRONG language, which is a different claim from having one.
  let notFound = null;
  const notFoundFile = path.join(outDir, '404.html');
  if (existsSync(notFoundFile)) {
    const tag = /<html[^>]*>/.exec(readFileSync(notFoundFile, 'utf8'));
    const lang = tag ? (/lang="([^"]*)"/.exec(tag[0]) || [])[1] : undefined;
    const dir = tag ? (/dir="([^"]*)"/.exec(tag[0]) || [])[1] : undefined;
    notFound = { htmlTag: tag ? tag[0] : null, lang: lang ?? null, dir: dir ?? null };
    if (lang !== undefined && lang !== 'ar' && lang !== 'en' && lang !== 'he') {
      problems.push(`404.html carries an unexpected lang=${lang}`);
    }
  }

  // No emitted document may LOAD an off-origin resource. This asserts loading
  // contexts (src/href/action in HTML, url()/@import in CSS) rather than any
  // string: framework chunks embed documentation URLs such as react.dev/errors
  // inside error-message text, which is not a network request. Those are
  // recorded below as evidence instead of failed as violations.
  //
  // STOREFRONT-READ-001: EXACTLY ONE exception - an <img src> under the public
  // storefront-media path of the Supabase origin (a published derivative, the
  // CSP's img-src). Any other element, attribute or origin is still a violation.
  const offOrigin = (uri) => /^(?:https?:)?\/\//i.test(uri) && !/^https?:\/\/(?:localhost|127\.0\.0\.1)/i.test(uri);
  const allowedImage = (uri) => uri.startsWith(MEDIA_PATH_PREFIX);
  for (const f of files) {
    const ext = path.extname(f.path).toLowerCase();
    if (ext !== '.html' && ext !== '.css') continue;
    const text = readFileSync(f.path, 'utf8');
    if (ext === '.html') {
      const imgSrcs = new Set();
      for (const m of text.matchAll(/<img\b[^>]*\ssrc\s*=\s*"([^"]+)"/gi)) imgSrcs.add(m[1]);
      for (const m of text.matchAll(/(?:src|href|action)\s*=\s*"([^"]+)"/gi)) {
        if (!offOrigin(m[1])) continue;
        if (imgSrcs.has(m[1]) && allowedImage(m[1])) continue;
        problems.push(`${rel(f.path)} loads off-origin resource: ${m[1]}`);
      }
    } else {
      for (const m of text.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/gi)) {
        if (offOrigin(m[1].trim())) problems.push(`${rel(f.path)} loads off-origin resource: ${m[1]}`);
      }
      for (const m of text.matchAll(/@import\s+(?:url\()?["']?([^"')\s]+)/gi)) {
        problems.push(`${rel(f.path)} uses @import: ${m[1]}`);
      }
    }
  }
  // No icon may be referenced while the text-only fallback is in force: a broken
  // or unapproved icon URL must fail rather than 404 quietly in a browser.
  for (const f of files) {
    if (path.extname(f.path).toLowerCase() !== '.html') continue;
    const html = readFileSync(f.path, 'utf8');
    for (const m of html.matchAll(/<link[^>]+rel="[^"]*icon[^"]*"[^>]*>/gi)) {
      problems.push(`${rel(f.path)} references an icon while the text-only fallback applies: ${m[0]}`);
    }
  }
  if (existsSync(path.join(outDir, 'favicon.svg')) || existsSync(path.join(outDir, 'favicon.ico'))) {
    problems.push('a favicon is present although the text-only fallback applies');
  }

  // Evidence, not an assertion: documentation hosts referenced inside chunk text.
  const docHosts = new Set();
  for (const f of files) {
    if (path.extname(f.path).toLowerCase() !== '.js') continue;
    for (const m of readFileSync(f.path, 'utf8').matchAll(/https?:\/\/([a-z0-9.-]{4,})/gi)) docHosts.add(m[1].toLowerCase());
  }

  // First-load client JS on / - sum of <script src> bytes, uncompressed.
  let firstLoadJs = 0;
  let firstLoadJsBrotli = 0;
  const indexFile = path.join(outDir, 'index.html');
  const scripts = [];
  if (existsSync(indexFile)) {
    const html = readFileSync(indexFile, 'utf8');
    for (const m of html.matchAll(/<script[^>]+src="([^"]+)"/g)) {
      const asset = path.join(outDir, m[1].replace(/^\//, ''));
      scripts.push(m[1]);
      if (existsSync(asset)) {
        const bytes = readFileSync(asset);
        firstLoadJs += bytes.length;
        firstLoadJsBrotli += brotliCompressSync(bytes).length;
      }
    }
    if (firstLoadJs > BUDGETS.firstLoadJsBytes) {
      problems.push(`first-load JS on / is ${firstLoadJs} bytes, budget ${BUDGETS.firstLoadJsBytes}`);
    }
  }

  // Per-route CSS and font-preload limits (budgets.mjs), the same measurement
  // measure-firstload.mjs reports; a route over a limit in force fails here
  // too. The raw CSS ceiling in force is the owner-approved exception
  // CSS-UI001-01 on its exact listed routes and the written limit elsewhere
  // (acceptance-exceptions.mjs); the original limit's compliance is carried
  // in `stats.cssAcceptance`, so a retained FAIL stays visible, and the
  // aggregate is marked WITH_APPROVED_EXCEPTIONS whenever the exception is used.
  const perRoute = measure(outDir);
  for (const p of checkBudgets(perRoute)) if (/CSS|font preload|stylesheet|preloaded font|no stylesheet|zero coverage/.test(p)) problems.push(p);
  const acceptance = cssAcceptance(perRoute);
  if (acceptance.status === 'FAIL') for (const row of acceptance.rows) if (row.problem) problems.push(`${row.route}: ${row.problem}`);
  const cssWorst = perRoute.reduce((a, r) => (r.css && r.css.bytes > (a?.css?.bytes ?? -1) ? r : a), null);
  const fontsWorst = perRoute.reduce((a, r) => (r.fontPreloads && r.fontPreloads.count > (a?.fontPreloads?.count ?? -1) ? r : a), null);

  const largest = files.slice().sort((a, b) => b.size - a.size).slice(0, 5)
    .map((f) => ({ file: rel(f.path), bytes: f.size }));

  return {
    problems,
    stats: {
      totalBytes: total, fileCount: files.length, firstLoadJs, firstLoadJsBrotli, scripts, largest,
      cssWorstRoute: cssWorst ? { route: cssWorst.route, bytes: cssWorst.css.bytes, brotli: cssWorst.css.brotli, stylesheets: cssWorst.css.uniqueStylesheets } : null,
      fontPreloadsWorstRoute: fontsWorst ? { route: fontsWorst.route, count: fontsWorst.fontPreloads.count, bytes: fontsWorst.fontPreloads.bytes } : null,
      cssAcceptance: {
        status: acceptance.status, exception: acceptance.exception, routesMeasured: acceptance.routesMeasured,
        originalFailuresRetained: acceptance.originalFailuresRetained, exceptionsApplied: acceptance.exceptionsApplied,
      },
      documents, notFound, documentationHostsInChunks: [...docHosts].sort(),
    },
  };
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('audit-output.mjs')) {
  const { problems, stats } = auditOutput();
  if (stats) console.log(JSON.stringify(stats, null, 2));
  if (problems.length) {
    console.error('\nOUTPUT AUDIT FAILED:');
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  } else if (stats.cssAcceptance.status === 'PASS_WITH_APPROVED_EXCEPTIONS') {
    const a = stats.cssAcceptance;
    console.log(`\nOUTPUT AUDIT PASSED WITH_APPROVED_EXCEPTIONS - ${a.exception.id} applied on ${a.exceptionsApplied.length} route(s); original ${a.exception.originalLimitBytes} B raw CSS limit FAIL retained on ${a.originalFailuresRetained.length} route(s)`);
  } else {
    console.log('\nOUTPUT AUDIT PASSED');
  }
}
