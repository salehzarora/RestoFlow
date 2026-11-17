import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { runInThisContext } from 'node:vm';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
import { deriver } from '../../supabase/functions/storefront-media-publish/test/engine.mjs';

function qualityHandoffUnit() {
  const source = readFileSync(new URL('./background-quality.ts', import.meta.url), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, esModuleInterop: true } }).outputText;
  const localRequire = createRequire(import.meta.url), module = { exports: {} }, records = [];
  const unitRequire = name => name === './companion-observer' ? { CompanionObserver: class { evidence() { return { scope: 'UNIT_ONLY_NO_BROWSER' }; } } }
    : name === 'node:fs' ? { readFileSync, writeFileSync: (_path, text) => records.push(JSON.parse(text)) } : localRequire(name);
  runInThisContext('(function(exports,require,module,__filename,__dirname){' + code + '\n})')(
    module.exports, unitRequire, module, fileURLToPath(new URL('./background-quality.ts', import.meta.url)), fileURLToPath(new URL('.', import.meta.url)));
  return { ...module.exports, records };
}
const binding = { prHead: '1'.repeat(40), prBase: '2'.repeat(40), testedCheckout: '3'.repeat(40), testedTree: '4'.repeat(40),
  runId: '123', runAttempt: '1', orgId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  restaurantId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', branchId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', slug: 'cinematic-a-unit' };
function handoffFixture() {
  const base = { width: 960, height: 720, bytes: 111406, sha256: '211a00daf75bb8f868cec1c95aaa1e4c5e7d1d9aba8b46e6867d2753a8ff2ed3' };
  const high = { width: 2560, height: 1920, bytes: 459258, sha256: 'c0120cc575b08c4227d3c060ac78af28ee4ec7085ec4fd85f510778933fcd85f' };
  const path = '/storage/v1/object/public/storefront-media/' + 'a'.repeat(32) + '/' + base.sha256 + '.webp';
  return { schema: 'background-quality-handoff-v1', status: 'FIRST_CASE_NATIVE_BYTE_GUARD_PASS', binding: structuredClone(binding),
    firstMediaId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', firstPublicUrl: 'http://127.0.0.1:54321' + path,
    pair: { baseUrl: 'https://oqmevrndtivqxgyvcmwy.supabase.co' + path, highUrl: 'https://oqmevrndtivqxgyvcmwy.supabase.co' + path.replace(base.sha256, high.sha256) },
    contentVersion: 7, profileVersion: 7, contentSha256: '5'.repeat(64), profileSha256: '6'.repeat(64), byteGuard: { status: 'PASS', mappedMedia: 2, verifiedMediaBytes: 2 },
    quality: { baseMediaId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', companionPublished: true, explicitRetry: false,
      originalReads: [{ bytes: 1463022, sha256: '3e6b8197d0f1e17da8a86b5f0db95330394e11bc30c34b16ca0a076959346d54' }],
      publishedReads: [base, high], publisherResult: { recipe: 'storefront-background-b1', variant: 'bg2560', rung: 0, ...high }, views: [] } };
}
test('UNIT_ONLY: the same-source/run/tenant scalar handoff imports publication facts without accepting any scene or continuation byte proof', () => {
  const u = qualityHandoffUnit(), input = handoffFixture(), checked = u.validateBackgroundHandoff(input, binding);
  assert.deepEqual(checked, input); assert.notEqual(checked, input);
  assert.doesNotThrow(() => u.validateBackgroundHandoff(input, binding, { contentVersion: 7, profileVersion: 7 }));
  assert.throws(() => u.validateBackgroundHandoff(input, binding, { contentVersion: 8, profileVersion: 7 }), 'CAS-only content changes fail even with identical hashes');
  assert.throws(() => u.validateBackgroundHandoff(input, binding, { contentVersion: 7, profileVersion: 8 }), 'Profile envelope version is independently bound');
  const quality = new u.BackgroundQuality('unit-no-write');
  quality.resume(checked, binding);
  assert.equal(quality.views.length, 0, 'All eight scene captures remain unexecuted in the continuation');
  assert.equal(u.records.at(-1).originalVerifiedReads.length, 1, 'Only the producer original read is imported');
  assert.equal(u.records.at(-1).priorCaseProof.byteGuard.verifiedMediaBytes, 2);
  assert.throws(() => quality.complete(), 'The unchanged final original/scene completeness assertions still fail before continuation');
  assert.throws(() => quality.resume(checked, binding), 'A second import cannot duplicate old evidence to fill the final counts');
});
test('UNIT_ONLY: absent, stale, cross-run/source/tenant/branch or unverified background handoffs fail closed', () => {
  const { validateBackgroundHandoff: validate } = qualityHandoffUnit();
  for (const key of Object.keys(binding)) {
    const wrong = structuredClone(binding); wrong[key] = key === 'slug' ? 'cinematic-other-unit'
      : ['runId','runAttempt'].includes(key) ? '9' : key.endsWith('Id') ? 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' : '9'.repeat(40);
    assert.throws(() => validate(handoffFixture(), wrong), key);
  }
  for (const bad of [null, {}, { status: 'NOT_READY' }, { status: 'PRODUCER_FAILED' }]) assert.throws(() => validate(bad, binding));
  for (const mutate of [v => { v.byteGuard.status = 'FAIL'; }, v => { v.byteGuard.mappedMedia = 0; v.byteGuard.verifiedMediaBytes = 0; },
    v => { v.byteGuard.verifiedMediaBytes--; }, v => { v.quality.views = [{ source: 'not-a-current-scene-read' }]; },
    v => { v.quality.originalReads.push(v.quality.originalReads[0]); }, v => { v.quality.companionPublished = false; },
    v => { v.quality.body = Buffer.from('not-an-original-response'); }, v => { v.session = 'never-export'; },
    v => { v.firstPublicUrl = 'https://private.example/secret'; }, v => { v.pair.highUrl = v.pair.baseUrl; }]) {
    const bad = handoffFixture(); mutate(bad); assert.throws(() => validate(bad, binding));
  }
  for (const version of [undefined, null, -1, 1.5, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    for (const key of ['contentVersion','profileVersion']) { const bad = handoffFixture(); bad[key] = version; assert.throws(() => validate(bad, binding)); }
  }
});

test('the Dashboard background fixture fits the private bucket and reproduces both real publication goldens', async () => {
  const bytes = await readFile(new URL('./fixtures/background-quality/background-2816.jpg', import.meta.url));
  assert.equal(bytes.length, 1463022);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), '3e6b8197d0f1e17da8a86b5f0db95330394e11bc30c34b16ca0a076959346d54');
  const engine = await deriver();
  const base = await engine.derive(bytes, { variant:'w960', source:'restaurant-logos', rung:0 });
  const high = await engine.deriveBackground(bytes, { source:'restaurant-logos', rung:0 });
  assert.deepEqual([base.source.width, base.source.height, high.source.width, high.source.height], [2816,2112,2816,2112]);
  assert.deepEqual([base.status, base.width, base.height, base.byteLength, base.sha256],
    ['derived',960,720,111406,'211a00daf75bb8f868cec1c95aaa1e4c5e7d1d9aba8b46e6867d2753a8ff2ed3']);
  assert.deepEqual([high.status, high.width, high.height, high.byteLength, high.sha256],
    ['derived',2560,1920,459258,'c0120cc575b08c4227d3c060ac78af28ee4ec7085ec4fd85f510778933fcd85f']);
});
