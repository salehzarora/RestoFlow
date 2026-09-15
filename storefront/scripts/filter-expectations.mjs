// Expected DECISION MECHANISM for each filter-proof cell, plus a pure evaluator.
//
// Why this exists: at head 67bbd76a the proof only checked `decision`, so a cell
// expecting BUILD would accept `BUILD / unsupported_graph` with `categories: {}`
// - a fail-safe guard failure - even though that scenario exists to prove
// CLASSIFICATION against a valid graph. A fail-safe BUILD is not a decision.
//
// Every expectation below was READ FROM the inspected engine's actual output for
// the deliberately created mutation; none is invented. Each scenario changes
// exactly one file, so each category map has exactly one label with count 1.
// Note that the label is selector-dependent in scenario A: the engine names an
// apps/ change `product_runtime` for the product selector and `product_only`
// for the others.

/** Decision reasons the engine produces from CLASSIFICATION, not from a guard. */
export const CLASSIFICATION_REASONS = { BUILD: 'relevant_changes', IGNORE: 'unaffected_changes' };

/**
 * Evaluate one selector's result against its expectation.
 * @returns {string[]} problems; empty means the cell is correct.
 */
export function evaluateCell({ scenario, selector, expected, actual }) {
  const problems = [];
  const where = `${scenario} ${selector}`;

  if (!actual || typeof actual !== 'object') {
    return [`${where}: no result`];
  }
  if (actual.decision !== expected.decision) {
    problems.push(`${where}: expected ${expected.decision}, got ${actual.decision} (${actual.reason})`);
  }

  // The mechanism, not just the outcome. A guard failure (unsupported_graph,
  // unsupported_build_contract, missing_baseline, ...) must never satisfy a cell
  // that is meant to prove classification.
  const wantReason = expected.reason ?? CLASSIFICATION_REASONS[expected.decision];
  if (actual.reason !== wantReason) {
    problems.push(`${where}: expected reason ${wantReason}, got ${actual.reason}`);
  }

  // An empty category map means the classification loop never ran.
  const categories = actual.categories ?? {};
  if (Object.keys(categories).length === 0) {
    problems.push(`${where}: categories is empty - the classification loop did not run`);
  } else if (expected.categories) {
    const got = JSON.stringify(categories);
    const want = JSON.stringify(expected.categories);
    if (got !== want) problems.push(`${where}: expected categories ${want}, got ${got}`);
  }

  return problems;
}

/** Assert the two compared trees actually differ, or the scenario proves nothing. */
export function evaluateDiff({ scenario, baseline, head }) {
  if (!baseline || !head) return [`${scenario}: missing baseline or head sha`];
  if (baseline === head) return [`${scenario}: baseline and head are identical, so no decision is exercised`];
  return [];
}

const c = (decision, categories) => ({ decision, reason: CLASSIFICATION_REASONS[decision], categories });

/** Per-scenario, per-selector expectations. */
export const EXPECTATIONS = {
  A: {
    marketing: c('IGNORE', { product_only: 1 }),
    product: c('BUILD', { product_runtime: 1 }),
    storefront: c('IGNORE', { product_only: 1 }),
  },
  B: {
    marketing: c('BUILD', { marketing_runtime: 1 }),
    product: c('IGNORE', { marketing_runtime: 1 }),
    storefront: c('IGNORE', { marketing_runtime: 1 }),
  },
  C: {
    marketing: c('IGNORE', { tests_docs: 1 }),
    product: c('IGNORE', { tests_docs: 1 }),
    storefront: c('IGNORE', { tests_docs: 1 }),
  },
  D1: {
    marketing: c('IGNORE', { storefront_runtime: 1 }),
    product: c('IGNORE', { storefront_runtime: 1 }),
    storefront: c('BUILD', { storefront_runtime: 1 }),
  },
  D2: {
    marketing: c('IGNORE', { storefront_runtime: 1 }),
    product: c('IGNORE', { storefront_runtime: 1 }),
    storefront: c('BUILD', { storefront_runtime: 1 }),
  },
  D3: {
    marketing: c('IGNORE', { storefront_local: 1 }),
    product: c('IGNORE', { storefront_local: 1 }),
    storefront: c('BUILD', { storefront_local: 1 }),
  },
  D4: {
    marketing: c('IGNORE', { storefront_local: 1 }),
    product: c('IGNORE', { storefront_local: 1 }),
    storefront: c('BUILD', { storefront_local: 1 }),
  },
};
