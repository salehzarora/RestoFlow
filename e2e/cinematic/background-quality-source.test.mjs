import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { runInThisContext } from 'node:vm';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
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
function actualBindingUnit(options = {}) {
  const code = readFileSync(new URL('./dashboard.spec.ts', import.meta.url), 'utf8');
  const block = code.slice(code.indexOf('function traditionalBackgroundBinding('), code.indexOf('const authoritativeHash ='));
  assert(block.startsWith('function traditionalBackgroundBinding('));
  const js = ts.transpileModule(block, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
  const source = { prHead: binding.prHead, prBase: binding.prBase, testedCheckout: binding.testedCheckout,
    testedTree: binding.testedTree, runId: binding.runId, ...options.source };
  const env = { GITHUB_SHA: binding.testedCheckout, GITHUB_RUN_ID: binding.runId, GITHUB_RUN_ATTEMPT: binding.runAttempt, ...options.env };
  const calls = [], metadata = {
    'rev-parse HEAD': options.head ?? binding.testedCheckout,
    'rev-parse HEAD^{tree}': options.tree ?? binding.testedTree,
    'show -s --format=%P HEAD': (options.parents ?? [binding.prBase, binding.prHead]).join(' '),
  };
  const git = (command, args, settings) => {
    assert.equal(command, 'git'); assert.equal(settings.encoding, 'utf8');
    const key = args.join(' '); assert(Object.hasOwn(metadata, key), 'Only the existing exact Git metadata reads are allowed');
    calls.push(key); return metadata[key] + '\n';
  };
  const read = (path, encoding) => { assert.equal(path, resolve('unit-public', 'source.json')); assert.equal(encoding, 'utf8'); return JSON.stringify(source); };
  const expect = createRequire(import.meta.url)('@playwright/test').expect;
  const actual = runInThisContext('(function(readFileSync,resolve,execFileSync,expect,process){' + js + '\nreturn traditionalBackgroundBinding;})')(
    read, resolve, git, expect, { env });
  const ownerA = { orgId: binding.orgId, restaurantId: binding.restaurantId, branchId: binding.branchId, slug: binding.slug, ...options.tenant };
  return { run: () => actual({ ownerA }, 'unit-public'), calls, env };
}
test('UNIT_ONLY: the actual binding helper proves the event merge, tree and exact ordered parents without step-local PR variables', () => {
  const u = actualBindingUnit();
  assert.equal(Object.hasOwn(u.env, 'CINEMATIC_PR_HEAD'), false); assert.equal(Object.hasOwn(u.env, 'CINEMATIC_PR_BASE'), false);
  assert.deepEqual(u.run(), binding);
  assert.deepEqual(u.calls, ['rev-parse HEAD','rev-parse HEAD^{tree}','show -s --format=%P HEAD']);
});
test('UNIT_ONLY: the actual binding helper rejects wrong source, event checkout, tree, run and synthetic merge ancestry', () => {
  for (const source of [{ prHead: '9'.repeat(40) }, { prBase: '9'.repeat(40) }, { testedCheckout: '9'.repeat(40) },
    { testedTree: '9'.repeat(40) }, { runId: '999' }]) assert.throws(() => actualBindingUnit({ source }).run());
  for (const options of [{ head: '9'.repeat(40) }, { tree: '9'.repeat(40) }, { parents: [binding.prHead, binding.prBase] },
    { parents: [binding.prHead] }, { parents: [binding.prBase,binding.prHead,'9'.repeat(40)] },
    { env: { GITHUB_SHA: '9'.repeat(40) } }, { env: { GITHUB_SHA: undefined } },
    { env: { GITHUB_RUN_ID: undefined } }, { env: { GITHUB_RUN_ATTEMPT: undefined } }, { env: { GITHUB_RUN_ATTEMPT: '0' } }]) {
    assert.throws(() => actualBindingUnit(options).run());
  }
  const { validateBackgroundHandoff } = qualityHandoffUnit();
  assert.throws(() => validateBackgroundHandoff(handoffFixture(), actualBindingUnit({ env: { GITHUB_RUN_ATTEMPT: '2' } }).run()), 'A different actual attempt cannot consume the same handoff');
  assert.throws(() => validateBackgroundHandoff(handoffFixture(), actualBindingUnit({ tenant: { branchId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' } }).run()), 'A different current tenant branch cannot consume the handoff');
});
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
