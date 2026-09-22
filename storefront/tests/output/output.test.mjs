// Post-build assertions over the REAL exported tree. Run after `npm run build`.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { auditOutput, walk } from '../../scripts/audit-output.mjs';
import {
  renderedModuleOrder,
  checkModuleOrder,
  LOCKED_MODULE_ORDER,
} from '../../scripts/module-order.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const OUT = path.join(ROOT, 'out');

test('the export exists', () => {
  assert.ok(existsSync(OUT), 'run npm run build before the output tests');
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
// The SHIPPED export carries the canonical tenant slug and nothing else. Demo
// scenario documents cost 1,306,346 bytes of a 4 MiB ceiling that may not be
// raised, so they are emitted only by a local SF_EVIDENCE_ROUTES=1 build.
// Adding one back to any generateStaticParams turns this list RED.
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
  // Four RSC payloads per document (the route's .txt, _full, _tree and the
  // page segment): an exact count, so a payload the export adds later cannot
  // slip out of the sweep.
  assert.equal(payloads.length, docs.length * 4, 'every RSC payload of the request route is in scope');
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
