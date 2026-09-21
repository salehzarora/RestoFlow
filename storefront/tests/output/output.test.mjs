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
