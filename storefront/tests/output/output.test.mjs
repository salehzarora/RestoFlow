// Post-build assertions over the REAL server-render SNAPSHOT (STOREFRONT-READ-001):
// run `npm run build`, then `node scripts/snapshot-server.mjs`, which fetches every
// canonical route from a real `next start` into out/ (documents, one RSC flight
// payload per document, .next/static, public/, 404.html, SNAPSHOT.json).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { auditOutput, walk } from '../../scripts/audit-output.mjs';
import { checkBudgets, cssAcceptance, cssRawLimitFor, measure } from '../../scripts/measure-firstload.mjs';
import { BUDGETS, MEDIA_PATH_PREFIX } from '../../scripts/budgets.mjs';
import { CSS_RAW_EXCEPTION, PERF_LCP_ACCEPTANCE } from '../../scripts/acceptance-exceptions.mjs';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import {
  renderedModuleOrder,
  checkModuleOrder,
  LOCKED_MODULE_ORDER,
} from '../../scripts/module-order.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const OUT = path.join(ROOT, 'out');

const SNAPSHOT = path.join(OUT, 'SNAPSHOT.json');

test('the snapshot exists', () => {
  assert.ok(existsSync(OUT), 'run npm run build, then node scripts/snapshot-server.mjs, before the output tests');
  assert.ok(existsSync(SNAPSHOT), 'out/ must be a server-render snapshot (SNAPSHOT.json present), not a stale static export');
});

// ------------------------------------------ STOREFRONT-READ-001: served contract
//
// The snapshot records what `next start` actually answered per route. These are
// the LOCAL halves of T-S6 / T-S7: the ISR cache header on every storefront
// document, no cookie on any response, a real 404 for an unknown slug, and no
// database credential, origin or auth-shaped token in anything a browser loads.
const snapshotRecord = () => JSON.parse(readFileSync(SNAPSHOT, 'utf8'));

test('every storefront document was served with the 60 s ISR cache header and no cookie; an unknown slug is a real 404', () => {
  const record = snapshotRecord();
  assert.deepEqual(record.problems, [], record.problems.join('\n'));
  // The 28 tenant documents (7 screens x 4 locale roots) carry the ISR contract
  // (revalidate = 60, expireTime = 360 -> stale-while-revalidate=300); the four
  // request documents are fixture-only static routes (dynamicParams = false).
  const tenantDocs = record.documents.filter((d) => /\/s\//.test(d.route) && d.file !== '404.html');
  assert.equal(tenantDocs.length, 28, 'every tenant document is in the snapshot');
  for (const d of tenantDocs) {
    assert.equal(d.status, 200, d.route);
    assert.match(d.headers['cache-control'] ?? '', /s-maxage=60\b/, `${d.route}: ${d.headers['cache-control']}`);
    assert.match(d.headers['cache-control'] ?? '', /stale-while-revalidate=300\b/, `${d.route}: ${d.headers['cache-control']}`);
    assert.equal(d.flightStatus, 200, `${d.route}: its RSC flight payload was served`);
    assert.ok(d.flightBytes > 0, `${d.route}: the flight payload is not empty`);
  }
  const requestDocs = record.documents.filter((d) => /\/r\//.test(d.route));
  assert.equal(requestDocs.length, 4, 'the fixture request document exists in every locale root (fixture mode)');
  for (const d of requestDocs) assert.equal(d.status, 200, d.route);
  for (const d of record.documents) assert.equal(d.headers['set-cookie'], undefined, `${d.route} set a cookie`);
  const missing = record.documents.find((d) => d.file === '404.html');
  assert.ok(missing, 'the unknown-slug fetch is recorded');
  assert.equal(missing.status, 404, 'an unknown slug is a real 404, never a 200 with the Unknown copy');
  // The server artifact is REPORTED, in its own row - never folded into the static ceiling.
  assert.ok(Number.isInteger(record.serverBundleBytes) && record.serverBundleBytes > 0, 'the server bundle size is recorded');
  console.log(`server bundle ${record.serverBundleBytes} B (reported, not budgeted); client static ${record.clientStaticBytes} B`);
});

test('the largest served document is reported against the PROPOSED per-document ceiling (not enforced until approved)', () => {
  const record = snapshotRecord();
  const worst = record.documents.filter((d) => d.status === 200).reduce((a, d) => (d.bytes > a.bytes ? d : a));
  console.log(`largest document ${worst.route}: ${worst.bytes} B decoded (proposal ${BUDGETS.documentBytesProposal} B - ${worst.bytes <= BUDGETS.documentBytesProposal ? 'within' : 'OVER'})`);
  assert.ok(Number.isInteger(worst.bytes) && worst.bytes > 0);
});

/** What a browser must never receive from this site: the read path is server-only. */
const CREDENTIAL_SHAPES = [
  ['apikey', /\bapikey\b/i],
  ['the server env names', /STOREFRONT_SUPABASE_/],
  ['a PostgREST path', /\/rest\/v1\//],
  ['an auth path', /\/auth\/v1\//],
  ['a JWT shape', /eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}/],
  ['a publishable key shape', /sb_publishable_[A-Za-z0-9_-]{10,}/],
  ['anonymous sign-in', /signInAnonymously/],
  ['a supabase client', /createClient\(/],
];

test('no emitted client chunk, document or flight payload carries a database credential, API path or auth-shaped token', () => {
  const scripts = outFiles()
    .filter((f) => f.endsWith('.js'))
    .map((f) => ({ file: path.relative(OUT, f).replace(/\\/g, '/'), text: readFileSync(f, 'utf8') }));
  assert.ok(scripts.length > 10, 'the snapshot ships client scripts');
  const all = [...emittedText(), ...scripts];
  for (const { file, text } of all) {
    for (const [label, shape] of CREDENTIAL_SHAPES) {
      assert.ok(!shape.test(text), `${file}: carries ${label}`);
    }
    // The ONLY permitted appearance of the database origin is a published
    // derivative <img src> under the public storefront-media path.
    for (const m of text.matchAll(/https?:\/\/[a-z0-9-]+\.supabase\.co[^"'\s<>)]*/gi)) {
      assert.ok(m[0].startsWith(MEDIA_PATH_PREFIX), `${file}: the database origin appears outside the public media path: ${m[0].slice(0, 80)}`);
    }
  }
});

test('NEGATIVE CONTROL: the credential scan catches each shape it names', () => {
  const planted = [
    'x = { apikey: "k" }', 'process.env.STOREFRONT_SUPABASE_URL', 'fetch("/rest/v1/rpc/storefront_menu")', '"/auth/v1/token"',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0', 'sb_publishable_abcdefghijklmnop', 'auth.signInAnonymously()', 'createClient(url, key)',
  ];
  for (const [i, sample] of planted.entries()) {
    assert.ok(CREDENTIAL_SHAPES.some(([, shape]) => shape.test(sample)), `shape ${i} MISSED: ${sample}`);
  }
  // and the boundary case it must NOT flag: the plural word is not the header name
  assert.ok(!CREDENTIAL_SHAPES.some(([, shape]) => shape.test('const key = "apikeys are not this";')), 'the scan must not flag the plural "apikeys"');
});

test('the output audit reports no problems', () => {
  const { problems } = auditOutput(OUT);
  assert.deepEqual(problems, [], problems.join('\n'));
});

test('every promised document is emitted with the right lang and dir', () => {
  const { stats } = auditOutput(OUT);
  assert.deepEqual(stats.documents['index.html'], { lang: 'ar', dir: 'rtl' });
  assert.deepEqual(stats.documents['ar.html'], { lang: 'ar', dir: 'rtl' });
  assert.deepEqual(stats.documents['en.html'], { lang: 'en', dir: 'ltr' });
  assert.deepEqual(stats.documents['he.html'], { lang: 'he', dir: 'rtl' });
});

test('404 exists and does not carry a wrong language', () => {
  const { stats } = auditOutput(OUT);
  assert.ok(existsSync(path.join(OUT, '404.html')));
  // Recorded evidence, not an assertion about which language it should be:
  // what matters is that it did not inherit an INCORRECT one.
  assert.ok(stats.notFound.lang === null || ['ar', 'en', 'he'].includes(stats.notFound.lang));
});

// ---------------------------------------------------------------------------
// The SNAPSHOT carries the canonical fixture tenant and nothing else (fixture
// mode; a live tenant is never snapshotted here). Demo scenario slugs resolve
// only in a local SF_EVIDENCE_ROUTES=1 build, exactly as the static export
// emitted them; a live tenant slug does not exist in fixture mode. Adding a demo
// slug to any generateStaticParams turns this list RED.
const SHIPPED_SLUGS = ['maps-burger'];

// walk() yields { path, symlink, size } records, not strings.
const outFiles = () => walk(OUT).map((e) => e.path.replace(/\\/g, '/'));
const menuDocuments = () => outFiles().filter((f) => f.endsWith('/menu.html'));

test('the shipped export emits exactly the allowlisted storefront slugs', () => {
  const slugs = new Set();
  for (const f of outFiles()) {
    const m = f.match(/\/s\/([^/]+)(?:\/|\.)/);
    if (m) slugs.add(m[1]);
  }
  assert.deepEqual([...slugs].sort(), [...SHIPPED_SLUGS].sort());
  // Stated separately so the failure message names the offender.
  const demo = [...slugs].filter((s) => s.startsWith('demo-'));
  assert.deepEqual(demo, [], `demo slugs must not ship: ${demo.join(', ')}`);
});

test('every emitted menu document renders the locked module order', () => {
  const docs = menuDocuments();
  // Coverage assertion first: a scan that silently matched zero documents would
  // otherwise "pass" - the exact failure mode of the Phase A dictionary guard.
  assert.equal(docs.length, 4, `expected 4 shipped menu documents, found ${docs.length}`);
  for (const f of docs) {
    const observed = renderedModuleOrder(readFileSync(f, 'utf8'));
    const problems = checkModuleOrder(observed, {
      mandatory: ['compact', 'hero', 'service', 'categories', 'sections', 'footer'],
    });
    assert.deepEqual(problems, [], `${f}: ${problems.join('; ')}`);
  }
});

test('NEGATIVE CONTROL: the rendered module-order check catches a reordered document', () => {
  const docs = menuDocuments();
  assert.ok(docs.length > 0);
  const html = readFileSync(docs[0], 'utf8');
  const observed = renderedModuleOrder(html);
  assert.ok(observed.length >= 3, 'need at least three modules to reorder');

  // Swap two modules in the OBSERVED order; the committed export is untouched.
  const swapped = [...observed];
  [swapped[0], swapped[1]] = [swapped[1], swapped[0]];
  assert.ok(
    checkModuleOrder(swapped).length > 0,
    'a swapped module order MUST be caught',
  );
  // An unknown module must also be caught.
  assert.ok(checkModuleOrder([...observed, 'checkout']).length > 0);
  // An empty document must be caught rather than passing vacuously.
  assert.ok(checkModuleOrder([]).length > 0);
  // ...and the real order still passes, so this control discriminates.
  assert.deepEqual(checkModuleOrder(observed), []);
});

test('every module named in the locked order actually renders somewhere', () => {
  // Guards against an anchor being deleted from markup: the source-order test
  // would still pass with a module gone if nothing checked the export.
  const seen = new Set();
  for (const f of menuDocuments()) {
    for (const name of renderedModuleOrder(readFileSync(f, 'utf8'))) seen.add(name);
  }
  // announce/promo/popular/story are module toggles and notice is state-driven;
  // on the canonical shipped documents all of them are on except notice.
  for (const name of LOCKED_MODULE_ORDER.filter((n) => n !== 'notice')) {
    assert.ok(seen.has(name), `module "${name}" renders on no shipped document`);
  }
});

// ------------------------------------------- shipped bytes carry NO visitor cart
//
// A static export serves IDENTICAL bytes to everyone, so any cart inside them is
// a cart nobody owns. A no-JS visitor and a crawler see exactly these bytes.
//
// The fixture cart (home.ts SEEDED_LINES) is item 1 x1 plus item 7 x2, which
// renders as "3 items", a 9900 subtotal and an 18% tax - so those are the exact
// strings a leak would produce.

/** Markers that can only come from a FABRICATED cart, never from a real one. */
const FAKE_CART_MARKERS = [
  '₪99',       // seeded subtotal
  '₪17.82',    // 18% tax on the seeded subtotal
  '₪116.82',   // seeded total
  'dockCount',      // the dock's count badge
  'dockTotal',      // the dock's money slot
  'dockThumb',      // a line thumbnail in the dock
  'asideLine',      // a line row in the wide aside
  'totalRow',       // the aside's subtotal/tax/total block
  'data-sf-dock',   // the live dock itself
];

/** Every emitted document and RSC payload, as text. */
const emittedText = () =>
  outFiles()
    .filter((f) => f.endsWith('.html') || f.endsWith('.txt'))
    .map((f) => ({ file: path.relative(OUT, f).replace(/\\/g, '/'), text: readFileSync(f, 'utf8') }));

/** The rule as a pure function, so the negative control can run the SAME logic. */
function fakeCartOffences(docs) {
  const found = [];
  for (const { file, text } of docs) {
    for (const marker of FAKE_CART_MARKERS) {
      if (text.includes(marker)) found.push(`${file}: ${marker}`);
    }
  }
  return found;
}

test('no shipped document or RSC payload contains a fabricated cart', () => {
  const docs = emittedText();
  assert.ok(docs.length > 0, 'expected emitted documents');
  assert.deepEqual(fakeCartOffences(docs), []);
});

test('NEGATIVE CONTROL: the fabricated-cart detector fails on a document that has one', () => {
  // Without this the test above would also pass on an export that emits nothing
  // at all, or if every marker were renamed.
  const docs = emittedText();
  for (const marker of FAKE_CART_MARKERS) {
    const planted = [...docs, { file: 'scratch/planted.html', text: `<p>${marker}</p>` }];
    const caught = fakeCartOffences(planted);
    assert.deepEqual(caught, [`scratch/planted.html: ${marker}`],
      `the detector MISSED a planted ${marker}`);
  }
});

test('the wide aside is live in the browser but carries NO cart in the bytes', () => {
  /*
   * Phase D makes the aside functional, and this gate does NOT relax because
   * of it - it gets sharper.
   *
   * A static document is byte-identical for every visitor, so any cart in it
   * is a cart nobody owns. That is exactly the defect the Phase C review found
   * when a seeded fixture cart reached sixteen shipped documents. The live
   * aside therefore prerenders its FRAME and its head only, and the lines,
   * steppers and totals appear only after this visitor's own cart has been
   * read from their own device.
   *
   * The frame must still be there: returning nothing until hydration would
   * reflow 360px of layout the moment the cart arrives.
   *
   * BOTH surfaces carry it: the menu and, since C2, search.
   */
  const withAside = emittedText().filter((d) => /(^|\/)(menu|search)\.html$/.test(d.file));
  assert.equal(withAside.length, 8,
    'expected one menu AND one search document per locale root');
  for (const { file, text } of withAside) {
    assert.ok(text.includes('data-sf-aside="live"'), `${file}: the wide aside is missing`);
    // Scoped to the <aside> ELEMENT: the document also carries an RSC payload
    // full of legitimate MENU prices, which are not cart state.
    const start = text.indexOf('<aside');
    const seam = text.slice(start, text.indexOf('</aside>', start));
    assert.ok(start !== -1 && seam.length > 0, `${file}: no aside element`);
    assert.ok(!seam.includes('asideStepper'), `${file}: the bytes must expose no stepper`);
    assert.ok(!seam.includes('asideLine'), `${file}: the bytes must carry no cart line`);
    assert.ok(!seam.includes('totalRow'), `${file}: the bytes must carry no totals`);
    assert.ok(!/₪\d/.test(seam), `${file}: the bytes must carry no money`);
    // And the frame IS there, with its head, so the column does not appear
    // from nowhere after hydration.
    assert.ok(seam.includes('sf-aside-title'), `${file}: the aside head is missing`);
  }
});

test('the four flow documents contain no cart, no draft and no money', () => {
  /*
   * The same rule, applied where it matters most. `/cart` is the one route
   * whose entire purpose is to show a cart - which is precisely why its static
   * bytes must contain none: every visitor is served the same file.
   *
   * The draft check is the privacy half: a checkout document that shipped a
   * name, a phone or an address would be shipping one visitor's details to
   * every other.
   */
  const flow = emittedText().filter((d) =>
    /(^|\/)(cart|checkout|payment|review)\.html$/.test(d.file),
  );
  assert.equal(flow.length, 16, 'expected four flow documents per locale root');
  for (const { file, text } of flow) {
    assert.ok(text.includes('data-sf-pending'), `${file}: must ship the pre-hydration frame only`);
    for (const banned of ['data-sf-cart-line', 'data-sf-totals', 'data-sf-aside-line']) {
      assert.ok(!text.includes(banned), `${file}: prerendered ${banned}`);
    }
    assert.ok(!/₪\d/.test(text), `${file}: the document must carry no money`);
    // No input may arrive with a value: a prefilled contact field in a static
    // document is someone else's data.
    assert.ok(!/<input[^>]*\svalue="[^"]/.test(text), `${file}: an input ships a value`);
    assert.ok(!/<textarea[^>]*>[^<]/.test(text), `${file}: a textarea ships content`);
  }
});

// ------------------------------------------ the request documents are NEUTRAL
//
// Phase E. `/r/<ref>` is one document per locale root that renders EITHER the
// received view (this visitor just sent a request) OR the status view (the
// source answered after mount). Both are decided after hydration, so the
// served bytes carry the chrome only: no request state, no timeline, no TTL,
// no line, no amount, no code, no personal field - nothing that could belong
// to one visitor and be served to every other.
const SHIPPED_REF = 'DEMO-7K4XM2D9P3';

test('the shipped export emits exactly one request ref, in every locale root', () => {
  const refs = new Set();
  for (const f of outFiles()) {
    const m = f.match(/\/r\/([^/]+)(?:\/|\.)/);
    if (m) refs.add(m[1]);
  }
  assert.deepEqual([...refs], [SHIPPED_REF]);
  const docs = emittedText().filter((d) => /(^|\/)r\/[^/]+\.html$/.test(d.file));
  assert.equal(docs.length, 4, 'expected one request document per locale root');
});

test('the four request documents carry no request, no status, no TTL, no money and no code', () => {
  const docs = emittedText().filter((d) => /(^|\/)r\/[^/]+\.html$/.test(d.file));
  assert.equal(docs.length, 4);
  const payloads = emittedText().filter((d) => /(^|\/)r\/[^/]+(\/|\.txt$)/.test(d.file));
  // ONE RSC flight payload per document in the server-render snapshot (the
  // static export used to write four per route): an exact count, so a payload
  // the lane adds later cannot slip out of the sweep.
  assert.equal(payloads.length, docs.length, 'every RSC payload of the request route is in scope');
  for (const { file, text } of [...docs, ...payloads]) {
    if (file.endsWith('.html')) {
      assert.ok(text.includes('data-sf-pending'), `${file}: must ship the pre-hydration frame only`);
    }
    for (const banned of [
      'data-sf-screen="received"', 'data-sf-screen="status"', 'data-sf-status=', 'data-sf-timeline', 'data-sf-ttl',
      'data-sf-request-line', 'data-sf-request-code', 'data-sf-request-message', 'data-sf-cancel-sheet',
      'data-sf-demo-note', '#MB-2487', 'aria-current="step"', 'role="timer"',
    ]) {
      assert.ok(!text.includes(banned), `${file}: prerendered ${banned}`);
    }
    assert.ok(!/\u20AA\d/.test(text), `${file}: the document must carry no money`);
    // The opaque ref may appear (it is the URL); the display code may not.
    assert.ok(!text.includes('MB-2487'), `${file}: the display code is not a prerendered fact`);
  }
});

test('no emitted document, payload OR script carries a real WhatsApp destination or the dead status literal', () => {
  // The JS chunks are where a deep link would actually live; they are swept
  // with the documents and payloads, not exempted from the rule.
  const scripts = outFiles()
    .filter((f) => f.endsWith('.js'))
    .map((f) => ({ file: path.relative(OUT, f).replace(/\\/g, '/'), text: readFileSync(f, 'utf8') }));
  assert.ok(scripts.length > 10, 'the export ships scripts');
  for (const { file, text } of [...emittedText(), ...scripts]) {
    for (const banned of ['wa.me', 'whatsapp://', 'api.whatsapp.com', 'bizbot.app']) {
      assert.ok(!text.includes(banned), `${file}: ${banned}`);
    }
  }
});

// ------------------------------------------------------ CSS / font preloads
//
// The two asset classes the plan named limits for without a validator
// (finishing mandate 7; correction pass 4). Measured per DIRECT-LOAD ROUTE by
// the same method as the JS budget: unique stylesheets the document actually
// references, each compressed separately; the fonts the document PRELOADS.
// The limits are the written ones (scripts/budgets.mjs); a route over one
// FAILS here, it is not warned about. The raw and compressed axes are
// separate tests so a report can name which one a route missed.
//
// CSS-UI001-01 (owner-approved, 2026-09-23; scripts/acceptance-exceptions.mjs):
// the ORIGINAL 70,000 B raw limit stays recorded and its compliance is still
// reported per route - a retained FAIL is a record, not a pass. On the EXACT
// thirty-two listed storefront routes the effective raw ceiling is 100,000 B
// (a new owner-chosen limit for this decision, not measured x 1.2); the
// 14,000 B Brotli limit is unchanged and must pass as well. Every other
// route keeps the 70,000 B target. The aggregate is visibly marked
// WITH_APPROVED_EXCEPTIONS whenever the exception is used.

const CSS_FONT = (p) => /CSS|font preload|stylesheet|preloaded font|no stylesheet/.test(p);
// Measured once per run; the tests below read the same rows.
let MEASURED = null;
const measured = () => (MEASURED ??= measure(OUT));

test('CSS / font measurement covers every direct-load route and is never empty', () => {
  const rows = measured();
  assert.equal(rows.length, 36, 'every canonical direct-load route is measured');
  for (const r of rows) {
    assert.ok(r.css.uniqueStylesheets >= 1, `${r.route}: at least one stylesheet counted`);
    assert.ok(r.css.bytes > 0 && r.css.brotli > 0, `${r.route}: nonzero CSS bytes on both axes`);
    assert.equal(r.css.inlineStyleBytes, 0, `${r.route}: no inline <style> under style-src 'self'`);
    for (const s of r.css.stylesheets) assert.ok(!s.missing, `${r.route}: ${s.url} exists`);
    for (const f of r.fontPreloads.files) assert.ok(!f.missing, `${r.route}: ${f.url} exists`);
  }
  // Every storefront document (not the four locale-root placeholders)
  // preloads its script subsets: an empty preload count would be a broken
  // font binding, not a saving.
  for (const r of rows.filter((x) => /\/s\/|\/r\//.test(x.route))) {
    assert.equal(r.fontPreloads.count, 2, `${r.route}: two preloaded subsets, ${r.fontPreloads.files.map((f) => f.url).join(', ')}`);
  }
});

test('font preloads per route: at most 2 files and at most 120,000 B (the written limit)', () => {
  const problems = checkBudgets(measured()).filter((p) => /font preload|preloaded font/.test(p));
  assert.deepEqual(problems, []);
});

test('the preloaded subsets are the right ones per root: Latin everywhere, Arabic on ar / en / root, Hebrew on he (src/fonts/README.md)', () => {
  for (const r of measured().filter((x) => /\/s\/|\/r\//.test(x.route))) {
    const names = r.fontPreloads.files.map((f) => f.url.replace(/.*rubik_/, '').replace(/_var.*/, '')).sort();
    const expected = r.route.startsWith('/he/') ? ['hebrew', 'latin'] : ['arabic', 'latin'];
    assert.deepEqual(names, expected, r.route);
  }
});

test('CSS per route: at most 14,000 B Brotli (the written limit)', () => {
  const problems = checkBudgets(measured()).filter((p) => /CSS .* brotli/.test(p));
  assert.deepEqual(problems, []);
});

test('CSS per route raw (CSS-UI001-01): the original 70,000 B limit is recorded with its compliance; the approved 100,000 B ceiling applies to exactly the listed routes; Brotli 14,000 B unchanged; the aggregate is marked WITH_APPROVED_EXCEPTIONS', () => {
  const rows = measured();
  const problems = checkBudgets(rows).filter((p) => /CSS .* uncompressed/.test(p));
  assert.deepEqual(problems, [], 'no route is over the raw ceiling in force for it');
  const acc = cssAcceptance(rows);
  assert.equal(acc.routesMeasured, 36);
  const over = [];
  for (const row of acc.rows) {
    assert.equal(row.original_limit, BUDGETS.cssPerRouteBytes, `${row.route}: the original limit is still the written one`);
    assert.equal(row.brotli_limit, BUDGETS.cssPerRouteBrotliBytes, `${row.route}: the Brotli limit is unchanged`);
    assert.equal(row.brotli_compliance, 'PASS', `${row.route}: Brotli ${row.brotli_bytes} B`);
    assert.notEqual(row.effective_acceptance, 'FAIL', `${row.route}: ${row.problem}`);
    if (row.measured_raw_bytes > BUDGETS.cssPerRouteBytes) {
      over.push(row.route);
      // The retained record: the original limit is FAILED, and the route
      // passes only WITH the named exception, under its ceiling.
      assert.equal(row.original_compliance, 'FAIL', row.route);
      assert.equal(row.exception_id, CSS_RAW_EXCEPTION.id, `${row.route} must be a listed route`);
      assert.equal(row.approved_exception_limit, CSS_RAW_EXCEPTION.approvedLimitBytes);
      assert.equal(row.effective_acceptance, 'PASS_WITH_APPROVED_EXCEPTION', row.route);
      assert.ok(row.measured_raw_bytes <= CSS_RAW_EXCEPTION.approvedLimitBytes, `${row.route}: ${row.measured_raw_bytes} B`);
    } else {
      assert.equal(row.original_compliance, 'PASS', row.route);
      assert.equal(row.effective_acceptance, 'PASS', row.route);
    }
    if (!CSS_RAW_EXCEPTION.routes.includes(row.route)) {
      assert.equal(cssRawLimitFor(row.route), BUDGETS.cssPerRouteBytes, `${row.route}: unlisted, the written limit applies`);
      assert.ok(row.measured_raw_bytes <= BUDGETS.cssPerRouteBytes, `${row.route}: unlisted route within 70,000 B`);
    }
  }
  // The exception list is bound to the measurement, not inferred from a
  // failure count: it names exactly the canonical routes measured over the
  // original limit - neither a route that does not need it (narrow the list
  // when a route drops under 70,000 B; the exception is temporary) nor one
  // that is not a measured canonical route. The locale-root placeholders are
  // not listed.
  assert.deepEqual([...CSS_RAW_EXCEPTION.routes].sort(), over.sort(),
    'CSS-UI001-01 lists exactly the routes measured over the original limit');
  for (const r of ['/', '/ar', '/en', '/he']) assert.ok(!CSS_RAW_EXCEPTION.routes.includes(r), `${r} is not excepted`);
  const expectedStatus = over.length ? 'PASS_WITH_APPROVED_EXCEPTIONS' : 'PASS';
  assert.equal(acc.status, expectedStatus);
  assert.deepEqual(acc.originalFailuresRetained.sort(), over.sort());
  // The audit carries the same aggregate, visibly.
  const { stats } = auditOutput(OUT);
  assert.equal(stats.cssAcceptance.status, expectedStatus);
  assert.deepEqual(stats.cssAcceptance.originalFailuresRetained.sort(), over.sort());
  console.log(`${CSS_RAW_EXCEPTION.id}: original ${BUDGETS.cssPerRouteBytes} B raw limit FAIL retained on ${over.length} route(s); effective ${acc.status}`);
});

test('NEGATIVE CONTROLS (CSS-UI001-01): the real evaluator FAILS a listed route at 100,001 B raw, a listed route over 14,000 B Brotli, an unlisted route at 70,001 B raw, a missing measurement, a missing stylesheet and zero coverage; exactly 100,000 B passes only WITH the exception and only on a listed route', () => {
  const listed = measured().find((r) => r.route === '/s/maps-burger/menu');
  const unlisted = measured().find((r) => r.route === '/');
  assert.ok(CSS_RAW_EXCEPTION.routes.includes(listed.route) && !CSS_RAW_EXCEPTION.routes.includes(unlisted.route));
  const clone = (r) => JSON.parse(JSON.stringify(r));
  const judge = (row) => ({ problems: checkBudgets([row]).filter(CSS_FONT).join('\n'), acc: cssAcceptance([row]) });

  // named (listed) route at 100,001 raw -> FAIL
  const a = clone(listed); a.css.bytes = CSS_RAW_EXCEPTION.approvedLimitBytes + 1; a.css.brotli = 1;
  let j = judge(a);
  assert.match(j.problems, /CSS 100001 B > 100000 B uncompressed \(approved exception CSS-UI001-01 ceiling; original limit 70000 B\)/);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL'); assert.equal(j.acc.status, 'FAIL');
  assert.equal(j.acc.rows[0].original_compliance, 'FAIL');

  // named (listed) route over 14,000 Brotli -> FAIL, whatever the raw figure
  const b = clone(listed); b.css.bytes = 80000; b.css.brotli = BUDGETS.cssPerRouteBrotliBytes + 1;
  j = judge(b);
  assert.match(j.problems, /CSS 14001 B brotli > 14000 B/);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL'); assert.equal(j.acc.rows[0].brotli_compliance, 'FAIL');

  // unlisted route over 70,000 raw -> FAIL under the ORIGINAL limit, no exception id
  const c = clone(unlisted); c.css.bytes = BUDGETS.cssPerRouteBytes + 1; c.css.brotli = 1;
  j = judge(c);
  assert.match(j.problems, /CSS 70001 B > 70000 B uncompressed/);
  assert.doesNotMatch(j.problems, /approved exception/);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL'); assert.equal(j.acc.rows[0].exception_id, null);
  assert.match(j.acc.rows[0].problem, /route not listed under CSS-UI001-01/);

  // an unlisted route at exactly 100,000 is still a FAIL: the exception does not travel
  const g = clone(unlisted); g.css.bytes = CSS_RAW_EXCEPTION.approvedLimitBytes; g.css.brotli = 1;
  j = judge(g);
  assert.match(j.problems, /CSS 100000 B > 70000 B uncompressed/);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL');

  // missing measurement -> FAIL (no catch-and-ignore)
  const d = clone(listed); delete d.css;
  j = judge(d);
  assert.match(j.problems, /no CSS measurement/);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL'); assert.match(j.acc.rows[0].problem, /no CSS measurement/);
  const d2 = clone(listed); d2.css.bytes = 'unknown';
  j = judge(d2);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL');

  // missing referenced stylesheet -> FAIL
  const e = clone(listed); e.css.stylesheets[0] = { url: e.css.stylesheets[0].url, missing: true };
  j = judge(e);
  assert.match(j.problems, /missing stylesheet/);
  assert.equal(j.acc.rows[0].effective_acceptance, 'FAIL'); assert.match(j.acc.rows[0].problem, /missing referenced stylesheet/);

  // zero route coverage -> FAIL
  assert.match(checkBudgets([]).join('\n'), /no route measured \(zero coverage\)/);
  assert.equal(cssAcceptance([]).status, 'FAIL');

  // a listed route at exactly 100,000 raw and 14,000 Brotli passes, and only WITH the exception
  const f = clone(listed); f.css.bytes = CSS_RAW_EXCEPTION.approvedLimitBytes; f.css.brotli = BUDGETS.cssPerRouteBrotliBytes;
  j = judge(f);
  assert.equal(j.problems, '');
  assert.equal(j.acc.rows[0].original_compliance, 'FAIL');
  assert.equal(j.acc.rows[0].effective_acceptance, 'PASS_WITH_APPROVED_EXCEPTION');
  assert.equal(j.acc.status, 'PASS_WITH_APPROVED_EXCEPTIONS');
  // a listed route under the original limit passes PLAINLY - the exception is not credited when unused
  const h = clone(listed); h.css.bytes = BUDGETS.cssPerRouteBytes; h.css.brotli = 1;
  j = judge(h);
  assert.equal(j.acc.rows[0].effective_acceptance, 'PASS'); assert.equal(j.acc.status, 'PASS');

  // Nothing outside this table can select or widen the exception: the table
  // is frozen, the evaluators take the measurement only, and neither module
  // reads the environment.
  assert.ok(Object.isFrozen(CSS_RAW_EXCEPTION) && Object.isFrozen(CSS_RAW_EXCEPTION.routes));
  assert.throws(() => { CSS_RAW_EXCEPTION.routes.push('/'); }, TypeError);
  assert.throws(() => { CSS_RAW_EXCEPTION.approvedLimitBytes = 1e9; }, TypeError);
  assert.equal(checkBudgets.length, 1); assert.equal(cssAcceptance.length, 1); assert.equal(cssRawLimitFor.length, 1);
  for (const f of ['scripts/acceptance-exceptions.mjs', 'scripts/measure-firstload.mjs', 'scripts/audit-output.mjs']) {
    assert.doesNotMatch(readFileSync(path.join(ROOT, f), 'utf8'), /process\.env/, `${f} reads no environment variable`);
  }
});

test('PERF-UI001-01 is recorded as written: LCP target 2,500 ms unchanged, the compressed local lab decides, the uncompressed lane is retained as a diagnostic, the other lab limits and the hosted gate unchanged', () => {
  assert.equal(PERF_LCP_ACCEPTANCE.id, 'PERF-UI001-01');
  assert.equal(PERF_LCP_ACCEPTANCE.lcpTargetMs, 2500);
  assert.match(PERF_LCP_ACCEPTANCE.acceptanceTransport, /compressed local lab/);
  assert.match(PERF_LCP_ACCEPTANCE.diagnosticTransport, /uncompressed local lab .* retained as a diagnostic record/);
  assert.deepEqual(PERF_LCP_ACCEPTANCE.unchanged, { longTaskOver50Ms: 300, cls: 0.05, clsHard: 0.1, fontSwapShift: 0.02 });
  assert.match(PERF_LCP_ACCEPTANCE.hosted, /UNVERIFIED/);
  assert.ok(Object.isFrozen(PERF_LCP_ACCEPTANCE) && Object.isFrozen(PERF_LCP_ACCEPTANCE.unchanged));
  // The CSS exception's own record, likewise as written.
  assert.equal(CSS_RAW_EXCEPTION.originalLimitBytes, 70000);
  assert.equal(CSS_RAW_EXCEPTION.approvedLimitBytes, 100000);
  assert.equal(CSS_RAW_EXCEPTION.brotliLimitBytes, 14000);
  assert.equal(CSS_RAW_EXCEPTION.routes.length, 32);
  assert.equal(new Set(CSS_RAW_EXCEPTION.routes).size, 32, 'no duplicate route');
});

test('NEGATIVE CONTROLS: an oversized stylesheet, a third preload and an oversized preload set each FAIL the same check', () => {
  // Built from a real measurement so the shape is the validator's own; only
  // the offending figure is changed, one at a time.
  const real = measured().find((r) => r.route === '/s/maps-burger/menu');
  const clone = () => JSON.parse(JSON.stringify(real));
  const within = clone();
  within.css.bytes = BUDGETS.cssPerRouteBytes; within.css.brotli = BUDGETS.cssPerRouteBrotliBytes;
  within.fontPreloads.count = BUDGETS.fontPreloadsPerRoute; within.fontPreloads.bytes = BUDGETS.fontPreloadBytesPerRoute;
  within.fontPreloads.files = within.fontPreloads.files.slice(0, 2);
  assert.deepEqual(checkBudgets([within]).filter(CSS_FONT), [], 'exactly at every limit passes');

  // 70,001 B raw on an UNLISTED route fails the written limit; on this
  // listed route the same figure fails the ORIGINAL limit in the acceptance
  // record while the approved ceiling admits it (CSS-UI001-01).
  const bigRaw = clone(); bigRaw.route = '/'; bigRaw.css.bytes = BUDGETS.cssPerRouteBytes + 1; bigRaw.css.brotli = 1;
  assert.match(checkBudgets([bigRaw]).filter(CSS_FONT).join('\n'), /CSS 70001 B > 70000 B uncompressed/);
  const bigRawListed = clone(); bigRawListed.css.bytes = BUDGETS.cssPerRouteBytes + 1; bigRawListed.css.brotli = 1;
  assert.deepEqual(checkBudgets([bigRawListed]).filter(CSS_FONT), []);
  assert.equal(cssAcceptance([bigRawListed]).rows[0].original_compliance, 'FAIL');
  assert.equal(cssAcceptance([bigRawListed]).rows[0].effective_acceptance, 'PASS_WITH_APPROVED_EXCEPTION');
  const bigBr = clone(); bigBr.css.bytes = 1; bigBr.css.brotli = BUDGETS.cssPerRouteBrotliBytes + 1;
  assert.match(checkBudgets([bigBr]).filter(CSS_FONT).join('\n'), /CSS 14001 B brotli > 14000 B/);
  const three = clone(); three.css.bytes = 1; three.css.brotli = 1; three.fontPreloads.count = 3; three.fontPreloads.bytes = 1;
  assert.match(checkBudgets([three]).filter(CSS_FONT).join('\n'), /3 font preloads > 2/);
  const heavy = clone(); heavy.css.bytes = 1; heavy.css.brotli = 1; heavy.fontPreloads.count = 2; heavy.fontPreloads.bytes = BUDGETS.fontPreloadBytesPerRoute + 1;
  assert.match(checkBudgets([heavy]).filter(CSS_FONT).join('\n'), /font preloads 120001 B > 120000 B/);
  const empty = clone(); empty.css.bytes = 0; empty.css.brotli = 0; empty.css.uniqueStylesheets = 0;
  assert.match(checkBudgets([empty]).filter(CSS_FONT).join('\n'), /no stylesheet counted/);
});

test('NEGATIVE CONTROL: the measurement itself counts a planted third preload and an 80,000 B stylesheet', () => {
  // A scratch out/ with one document (the "/" route) that links a real
  // oversized stylesheet and three font preloads; measure() must COUNT them,
  // not only the checker judge them.
  const dir = mkdtempSync(path.join(tmpdir(), 'sf-css-fixture-'));
  try {
    mkdirSync(path.join(dir, 'css'), { recursive: true });
    mkdirSync(path.join(dir, 'f'), { recursive: true });
    writeFileSync(path.join(dir, 'css', 'big.css'), `.a{color:red}`.repeat(6154).slice(0, 80000));
    for (const n of ['a', 'b', 'c']) writeFileSync(path.join(dir, 'f', `${n}.woff2`), Buffer.alloc(50000, n.charCodeAt(0)));
    writeFileSync(path.join(dir, 'index.html'), [
      '<html lang="ar" dir="rtl"><head>',
      '<link rel="preload" href="/f/a.woff2" as="font" crossorigin="" type="font/woff2"/>',
      '<link rel="preload" href="/f/b.woff2" as="font" crossorigin="" type="font/woff2"/>',
      '<link rel="preload" href="/f/c.woff2" as="font" crossorigin="" type="font/woff2"/>',
      '<link rel="stylesheet" href="/css/big.css" data-precedence="next"/>',
      '<link rel="stylesheet" href="/css/big.css" data-precedence="next"/>',
      '</head><body></body></html>',
    ].join(''));
    const rows = measure(dir);
    assert.equal(rows.length, 1);
    const r = rows[0];
    assert.equal(r.css.uniqueStylesheets, 1, 'the twice-linked stylesheet counts once');
    assert.equal(r.css.bytes, 80000);
    assert.equal(r.fontPreloads.count, 3);
    assert.equal(r.fontPreloads.bytes, 150000);
    const problems = checkBudgets(rows).filter(CSS_FONT).join('\n');
    assert.match(problems, /CSS 80000 B > 70000 B uncompressed/);
    assert.match(problems, /3 font preloads > 2/);
    assert.match(problems, /font preloads 150000 B > 120000 B/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
