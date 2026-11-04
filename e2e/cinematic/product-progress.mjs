// Test-only progress receipt: fixed labels only, including on failure. No raw
// error, request, response, credential, byte hash, URL or fixture value enters it.
const stages = new Set([
  "fixture",
  "route-setup",
  "login",
  "baseline-invariants",
  "initial-model-count",
  "open-product",
  "choose-source",
  "save-source",
  "save-source-status",
  "save-source-result",
  "save-source-identifiers",
  "original-read-status",
  "original-read-result",
  "original-source-key",
  "original-selection-default",
  "private-original-status",
  "private-original-bytes",
  "cancel-await-model-download",
  "cancel-worker",
  "cancel-no-automatic-publication",
  "cancel-original-bytes",
  "fault-start-worker",
  "fault-observed",
  "fault-no-automatic-publication",
  "fault-original-bytes",
  "retry-worker",
  "worker-ready",
  "alpha-bypass-review",
  "model-chunk-count",
  "cutout-choice-enabled",
  "prepublication-no-register",
  "light-review-capture",
  "dark-review-capture",
  "publish-selection",
  "selection-readback",
  "original-after-publication",
  "registration-proof",
  "selected-private-read",
  "live-menu-readback",
  "published-image-fetch",
  "published-image-alpha",
  "restore-original-selection",
  "restore-original-readback",
  "close-product",
  "publication-counts",
  "unchanged-invariants",
  "transport-boundary",
  "success-evidence"
]);
const samples = new Set(['burger', 'fries-cup', 'platter', 'drink']);

export function createProductProgress() {
  let current = { stage: 'fixture', sample: null };
  const completed = [];
  let passed = false;
  return {
    advance(stage, sample = current?.sample ?? null) {
      if (passed || !stages.has(stage) || (sample !== null && !samples.has(sample))) {
        throw new Error('Invalid fixed product progress transition');
      }
      completed.push(current);
      current = { stage, sample };
    },
    complete() {
      if (passed) throw new Error('Product progress already completed');
      completed.push(current);
      current = null;
      passed = true;
    },
    snapshot() {
      return {
        status: passed ? 'PASS' : 'FAIL',
        failedStage: current?.stage ?? null,
        sample: current?.sample ?? null,
        completedStages: completed.map(entry => ({ ...entry })),
      };
    },
  };
}
