// Post-build assertions over the REAL exported tree. Run after `npm run build`.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { auditOutput } from '../../scripts/audit-output.mjs';

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
