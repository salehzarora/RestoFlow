import test from 'node:test';
import assert from 'node:assert/strict';
import { captureProductResponse, createProductProgress } from './product-progress.mjs';

test('a thrown assertion retains its fixed stage and completed history in finally', () => {
  const progress = createProductProgress();
  let receipt;
  assert.throws(() => {
    try {
      progress.advance('login');
      progress.advance('save-source-result', 'burger');
      throw new Error('private response and assertion values must stay private');
    } finally { receipt = progress.snapshot(); }
  });
  assert.deepEqual(receipt, {
    status: 'FAIL', failedStage: 'save-source-result', sample: 'burger',
    completedStages: [{ stage: 'fixture', sample: null }, { stage: 'login', sample: null }],
    responses: [],
  });
});

test('unknown stages and secret-bearing sample values cannot escape in receipts or errors', () => {
  const progress = createProductProgress();
  const secret = 'credential-token-private-value';
  for (const change of [() => progress.advance(secret), () => progress.advance('login', secret),
    () => progress.advance({ stage: 'login', password: secret }),
    () => progress.advance('login', { sample: 'burger', password: secret })]) {
    assert.throws(change, error => error.message === 'Invalid fixed product progress transition');
  }
  assert.equal(JSON.stringify(progress.snapshot()).includes(secret), false);
  assert.deepEqual(progress.snapshot(), {
    status: 'FAIL', failedStage: 'fixture', sample: null, completedStages: [], responses: [],
  });
});

test('success is explicit and history cannot be altered through a returned receipt', () => {
  const progress = createProductProgress();
  progress.advance('open-product', 'burger');
  progress.advance('open-product', 'fries-cup');
  progress.advance('unchanged-invariants', null);
  const copy = progress.snapshot();
  copy.completedStages[0].stage = 'private-value';
  copy.completedStages.push({ stage: 'private-value', sample: 'private-value' });
  assert.equal(JSON.stringify(progress.snapshot()).includes('private-value'), false);
  progress.complete();
  assert.equal(progress.snapshot().status, 'PASS');
  assert.equal(progress.snapshot().failedStage, null);
  assert.equal(progress.snapshot().sample, null);
  assert.deepEqual(progress.snapshot().completedStages.at(-1), { stage: 'unchanged-invariants', sample: null });
  assert.throws(() => progress.advance('login'));
});

test('RPC facts retain only bounded status, strict boolean and exact source codes', () => {
  const secret = 'secret-body-value';
  for (const code of ['permission_denied', 'source_not_found', '42501', undefined, secret]) {
    const progress = createProductProgress();
    progress.advance('save-source-result', 'burger');
    progress.recordResponse('save-source', 200, { ok: false, error: code, message: secret, id: secret, source_key: secret });
    assert.deepEqual(progress.snapshot().responses, [{ operation: 'save-source', sample: 'burger',
      httpStatus: 200, envelopeOk: false,
      responseCode: code === undefined ? 'missing' : code === secret ? 'unclassified' : code }]);
    assert.equal(JSON.stringify(progress.snapshot()).includes(secret), false);
  }
  const progress = createProductProgress();
  progress.recordResponse('original-read', 403, { code: '42501', message: secret });
  assert.equal(progress.snapshot().responses[0].responseCode, '42501');
  assert.equal(progress.snapshot().responses[0].envelopeOk, null);
});

test('malformed status/body and unknown operation never serialize arbitrary values', () => {
  for (const status of [99, 600, 200.5, '200', NaN, Infinity, null, { secret: 'value' }]) {
    const progress = createProductProgress();
    progress.recordResponse('save-source', status, { ok: 'true', error: { secret: 'value' } });
    assert.deepEqual(progress.snapshot().responses[0], {
      operation: 'save-source', sample: null, httpStatus: null, envelopeOk: null, responseCode: 'unclassified',
    });
  }
  for (const body of [undefined, null, 'secret-body', ['secret-body'], 42, true]) {
    const progress = createProductProgress();
    progress.recordResponse('original-read', 200, body);
    assert.equal(progress.snapshot().responses[0].envelopeOk, null);
    assert.equal(progress.snapshot().responses[0].responseCode, 'unclassified');
    assert.equal(JSON.stringify(progress.snapshot()).includes('secret-body'), false);
  }
  const progress = createProductProgress();
  assert.throws(() => progress.recordResponse('secret-operation', 200, {}),
    error => error.message === 'Invalid fixed product response operation');
  assert.deepEqual(progress.snapshot().responses, []);
});

test('diagnostic JSON parse failure does not mask the original assertion or retain the error', async () => {
  const progress = createProductProgress();
  const original = new Error('original HTTP assertion');
  await captureProductResponse(progress, 'save-source', 503, async () => { throw new Error('secret-parser-input'); });
  assert.deepEqual(progress.snapshot().responses[0], {
    operation: 'save-source', sample: null, httpStatus: 503, envelopeOk: null, responseCode: 'unclassified',
  });
  assert.equal(JSON.stringify(progress.snapshot()).includes('secret-parser-input'), false);
  assert.throws(() => { throw original; }, error => error === original);
});

test('each sample/operation retains its first facts and snapshots cannot mutate them', () => {
  const progress = createProductProgress();
  progress.advance('save-source-result', 'burger');
  progress.recordResponse('save-source', 200, { ok: true });
  progress.recordResponse('save-source', 500, { ok: false });
  progress.snapshot().responses[0].responseCode = 'secret';
  assert.deepEqual(progress.snapshot().responses[0], {
    operation: 'save-source', sample: 'burger', httpStatus: 200, envelopeOk: true, responseCode: 'missing',
  });
  progress.advance('save-source-result', 'drink');
  progress.recordResponse('save-source', 200, { ok: true });
  assert.equal(progress.snapshot().responses.length, 2);
});

test('a high-res rendering failure cannot be mistaken for the preceding successful low-res sample', () => {
  const progress = createProductProgress();
  progress.advance('close-product', 'drink');
  progress.advance('highres-source-metadata', 'burger-highres');
  progress.advance('highres-cutout-render');
  progress.advance('highres-original-render');
  const receipt = progress.snapshot();
  assert.equal(receipt.status, 'FAIL');
  assert.equal(receipt.failedStage, 'highres-original-render');
  assert.equal(receipt.sample, 'burger-highres');
  assert.deepEqual(receipt.completedStages.at(-1), { stage: 'highres-cutout-render', sample: 'burger-highres' });
});
