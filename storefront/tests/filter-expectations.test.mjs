// Controls for the filter-proof evaluator.
//
// At head 67bbd76a the proof checked only `decision`, so a cell expecting BUILD
// would accept a fail-safe guard failure - `BUILD / unsupported_graph` with
// `categories: {}` - even though that scenario exists to prove CLASSIFICATION
// against a valid graph. The negative control below is exactly that case.
//
// Pure evaluator, small literals: importing it starts no git fixture, no build
// and no engine run.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { evaluateCell, evaluateDiff, EXPECTATIONS, CLASSIFICATION_REASONS } from '../scripts/filter-expectations.mjs';

const cell = (scenario, selector, actual) =>
  evaluateCell({ scenario, selector, expected: EXPECTATIONS[scenario][selector], actual });

test('NEGATIVE CONTROL: a fail-safe BUILD cannot satisfy a BUILD cell', () => {
  // The exact substitution the review called out.
  const problems = cell('D1', 'storefront', {
    decision: 'BUILD', reason: 'unsupported_graph', categories: {},
  });
  assert.notDeepEqual(problems, [], 'a guard failure must be rejected');
  assert.ok(problems.some((p) => p.includes('expected reason relevant_changes')),
    `expected a reason complaint, got:\n${problems.join('\n')}`);
  assert.ok(problems.some((p) => p.includes('categories is empty')),
    'an empty category map must be called out on its own');
});

test('NEGATIVE CONTROL: other guard failures are rejected too', () => {
  for (const reason of ['unsupported_build_contract', 'missing_baseline', 'invalid_cwd', 'helper_error']) {
    const problems = cell('D3', 'storefront', { decision: 'BUILD', reason, categories: {} });
    assert.notDeepEqual(problems, [], `${reason} must be rejected`);
  }
});

test('POSITIVE CONTROL: the real classification results pass', () => {
  assert.deepEqual(cell('D1', 'storefront', {
    decision: 'BUILD', reason: 'relevant_changes', categories: { storefront_runtime: 1 },
  }), []);
  assert.deepEqual(cell('D1', 'product', {
    decision: 'IGNORE', reason: 'unaffected_changes', categories: { storefront_runtime: 1 },
  }), []);
  assert.deepEqual(cell('A', 'product', {
    decision: 'BUILD', reason: 'relevant_changes', categories: { product_runtime: 1 },
  }), []);
  assert.deepEqual(cell('B', 'marketing', {
    decision: 'BUILD', reason: 'relevant_changes', categories: { marketing_runtime: 1 },
  }), []);
});

test('an IGNORE cell demands unaffected_changes, not no_changes', () => {
  // no_changes means the trees were identical, which proves nothing about
  // classification of a real diff.
  const problems = cell('C', 'product', { decision: 'IGNORE', reason: 'no_changes', categories: {} });
  assert.notDeepEqual(problems, []);
});

test('a wrong category label or count is rejected', () => {
  assert.notDeepEqual(cell('D3', 'storefront', {
    decision: 'BUILD', reason: 'relevant_changes', categories: { storefront_runtime: 1 },
  }), [], 'wrong label');
  assert.notDeepEqual(cell('D3', 'storefront', {
    decision: 'BUILD', reason: 'relevant_changes', categories: { storefront_local: 2 },
  }), [], 'wrong count');
});

test('a missing result fails rather than passing vacuously', () => {
  assert.notDeepEqual(cell('D1', 'storefront', undefined), []);
  assert.notDeepEqual(cell('D1', 'storefront', null), []);
});

test('identical baseline and head exercise no decision', () => {
  assert.notDeepEqual(evaluateDiff({ scenario: 'A', baseline: 'abc', head: 'abc' }), []);
  assert.notDeepEqual(evaluateDiff({ scenario: 'A', baseline: undefined, head: 'abc' }), []);
  assert.deepEqual(evaluateDiff({ scenario: 'A', baseline: 'abc', head: 'def' }), []);
});

test('every scenario declares all three selectors', () => {
  for (const [scenario, bySelector] of Object.entries(EXPECTATIONS)) {
    for (const selector of ['marketing', 'product', 'storefront']) {
      const e = bySelector[selector];
      assert.ok(e, `${scenario} is missing ${selector}`);
      assert.ok(['BUILD', 'IGNORE'].includes(e.decision), `${scenario}.${selector} decision`);
      // Expectations must describe classification, never a guard reason.
      assert.equal(e.reason, CLASSIFICATION_REASONS[e.decision], `${scenario}.${selector} reason`);
      assert.ok(e.categories && Object.keys(e.categories).length > 0, `${scenario}.${selector} categories`);
    }
  }
});
