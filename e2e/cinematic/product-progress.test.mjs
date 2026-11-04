import test from 'node:test';
import assert from 'node:assert/strict';
import { createProductProgress } from './product-progress.mjs';

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
    status: 'FAIL', failedStage: 'fixture', sample: null, completedStages: [],
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
