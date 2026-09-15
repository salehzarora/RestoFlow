// Controls for the export comparator.
//
// These exist because the comparator at head 67bbd76a contained a real
// false-equality defect: a blanket rule rewrote every
// /_next/static/chunks/<name>.js reference to one <CHUNK>.js placeholder, so
// two exports whose documents load DIFFERENT scripts compared equal. Case C is
// that exact counterexample and is RED against the old rule.
//
// Small synthetic fixtures only: importing the comparator runs no install, no
// build and no directory cleanup.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compareInventories, normaliseWith, buildIdsFrom } from '../scripts/compare-exports.mjs';

/** An export inventory: path -> { bytes, content }. */
const inv = (entries) => new Map(Object.entries(entries).map(([p, content]) => [
  p, { bytes: Buffer.byteLength(content), content },
]));

// Two chunk names of EQUAL LENGTH, so no size difference can accidentally
// distinguish them - the reference itself is the only signal.
const CHUNK_A = '11111111.js';
const CHUNK_B = '22222222.js';

const page = (chunk) =>
  `<!doctype html><html lang="ar" dir="rtl"><body><h1>BIZBOT</h1>` +
  `<script src="/_next/static/chunks/${chunk}"></script></body></html>`;

const baseFiles = (chunk) => ({
  'index.html': page(chunk),
  // BOTH chunks exist in BOTH inventories with identical bytes; only the
  // document's choice of which to load differs.
  '_next/static/chunks/11111111.js': 'console.log("behaviour one");',
  '_next/static/chunks/22222222.js': 'console.log("behaviour two");',
});

test('A. identical inventories pass', () => {
  const result = compareInventories(inv(baseFiles(CHUNK_A)), inv(baseFiles(CHUNK_A)));
  assert.equal(result.ok, true, result.problems.join('\n'));
  assert.equal(result.stats.countA, 3);
});

test('B. only the documented build-ID metadata differs -> pass', () => {
  const withId = (id) => ({
    'index.html': `<!doctype html><html lang="ar"><script src="/_next/static/${id}/main.js"></script>` +
      `<script>self.__next_f.push([1,"{\\"b\\":\\"${id}\\"}"])</script></html>`,
    [`_next/static/${id}/main.js`]: 'console.log("same");',
  });
  const result = compareInventories(inv(withId('AAAAAAAAAAAAAAAAAAAAA')), inv(withId('BBBBBBBBBBBBBBBBBBBBB')));
  assert.equal(result.ok, true, result.problems.join('\n'));
  assert.equal(result.stats.buildIdsA.length >= 1, true);
});

test('C. same files and bytes but a changed HTML script reference -> FAIL', () => {
  // THE COUNTEREXAMPLE. No build id differs anywhere. Every file is present in
  // both inventories with identical bytes. The only change is which script the
  // page loads - a behavioural difference the comparator must not absorb.
  const result = compareInventories(inv(baseFiles(CHUNK_A)), inv(baseFiles(CHUNK_B)));
  assert.equal(result.ok, false, 'a changed script reference must be reported');
  assert.ok(result.problems.some((p) => p.startsWith('content differs: index.html')),
    `expected index.html to differ, got:\n${result.problems.join('\n')}`);
});

test('D. a changed stylesheet reference -> FAIL', () => {
  const sheet = (name) => ({
    'index.html': `<!doctype html><html lang="ar"><link rel="stylesheet" href="/_next/static/chunks/${name}"></html>`,
    '_next/static/chunks/aaaaaaaa.css': '.a{color:red}',
    '_next/static/chunks/bbbbbbbb.css': '.b{color:blue}',
  });
  const result = compareInventories(inv(sheet('aaaaaaaa.css')), inv(sheet('bbbbbbbb.css')));
  assert.equal(result.ok, false, 'a changed stylesheet reference must be reported');
});

test('E. changed JS content, changed locale text, and missing/extra assets all FAIL', () => {
  const a = baseFiles(CHUNK_A);

  const changedJs = { ...a, '_next/static/chunks/11111111.js': 'console.log("tampered");' };
  assert.equal(compareInventories(inv(a), inv(changedJs)).ok, false, 'changed JS content');

  const changedText = { ...a, 'index.html': page(CHUNK_A).replace('BIZBOT', 'ALTERED') };
  assert.equal(compareInventories(inv(a), inv(changedText)).ok, false, 'changed locale text');

  const missing = { ...a };
  delete missing['_next/static/chunks/22222222.js'];
  const missingResult = compareInventories(inv(a), inv(missing));
  assert.equal(missingResult.ok, false, 'missing asset');
  assert.ok(missingResult.problems.some((p) => p.startsWith('only in A:')));

  const extra = { ...a, '_next/static/chunks/33333333.js': 'console.log("extra");' };
  const extraResult = compareInventories(inv(a), inv(extra));
  assert.equal(extraResult.ok, false, 'extra asset');
  assert.ok(extraResult.problems.some((p) => p.startsWith('only in B:')));
});

test('F. a changed _rsc query is reported, not absorbed', () => {
  const rsc = (value) => ({
    'index.html': `<!doctype html><html lang="ar"><a href="/ar?_rsc=${value}">ar</a></html>`,
  });
  const result = compareInventories(inv(rsc('aaaa1111')), inv(rsc('bbbb2222')));
  assert.equal(result.ok, false, 'no approved normalisation exists for _rsc values');
});

test('G. a normalisation-key collision fails instead of overwriting', () => {
  // Two distinct files whose paths differ only by the build id would normalise
  // to one key. The second must not silently replace the first.
  const id = 'CCCCCCCCCCCCCCCCCCCCC';
  const colliding = new Map([
    ['index.html', { bytes: 10, content: `<script src="/_next/static/${id}/x.js"></script>` }],
    [`_next/static/${id}/a.js`, { bytes: 3, content: 'one' }],
    ['_next/static/<BUILD_ID>/a.js', { bytes: 3, content: 'two' }],
  ]);
  const result = compareInventories(colliding, colliding);
  assert.equal(result.ok, false, 'a key collision must fail');
  assert.ok(result.problems.some((p) => p.includes('normalise to the same key')));
});

test('G2. a missing or empty inventory fails rather than passing vacuously', () => {
  assert.equal(compareInventories(new Map(), new Map()).ok, false, 'empty inventories');
  const noIndex = new Map([['ar.html', { bytes: 4, content: 'page' }]]);
  const result = compareInventories(noIndex, noIndex);
  assert.equal(result.ok, false, 'index.html missing means build IDs are unknown');
});

test('the normaliser replaces literals only, never a pattern', () => {
  const text = '/_next/static/ID123456789/a.js and /_next/static/chunks/other.js';
  const out = normaliseWith(text, ['ID123456789']);
  assert.ok(out.includes('<BUILD_ID>'), 'the known literal is replaced');
  assert.ok(out.includes('chunks/other.js'), 'an unrelated chunk name survives untouched');
});

test('buildIdsFrom reads only ids the export itself declares', () => {
  const html = '<script src="/_next/static/ZZZZZZZZZZZZ/m.js"></script>' +
    '<script>self.__next_f.push([1,"{\\"b\\":\\"QQQQQQQQQQQQQQQQ\\"}"])</script>';
  const ids = buildIdsFrom(html);
  assert.ok(ids.includes('ZZZZZZZZZZZZ'));
  assert.ok(ids.includes('QQQQQQQQQQQQQQQQ'));
  assert.deepEqual(buildIdsFrom(undefined), []);
});
