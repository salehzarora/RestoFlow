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
  "highres-source-metadata",
  "highres-cutout-render",
  "highres-original-render",
  "save-source",
  "save-source-status",
  "save-source-result",
  "save-source-identifiers",
  "original-read-status",
  "original-read-result",
  "original-source-key",
  "original-selection-default",
  "replacement-selection-proof",
  "private-original-status",
  "private-original-bytes",
  "original-only-no-processing",
  "explicit-prepare",
  "candidate-session-reuse",
  "existing-close",
  "existing-reopen",
  "existing-prepare",
  "existing-verify",
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
const samples = new Set(['burger', 'fries-cup', 'platter', 'drink', 'burger-highres']);
const operations = new Set(['save-source', 'original-read']);
// Exact literals from menu_upsert_item and get_storefront_product_original_v1.
const responseCodes = new Set(['permission_denied', 'source_not_found', '42501']);
// Publisher-reply lifecycle diagnostic. Each observed product publisher reply
// keeps bounded facts only: per-run ordinals, a fixed variant label, a bounded
// HTTP status, the fixed stage/sample labels current at each observation, the
// finished() promise state and the independent browser request flags. Request
// objects and the application request id stay in memory and are never written.
// Reading rule: Playwright resolves finished() only on requestfinished and
// rejects it only when the page closes, so in a timed-out run the reply that
// never finished reads finishedPromise 'rejected' at 'publication-counts' with
// requestFinished false; 'pending' appears only when another failure ends the
// test while replies are still in flight.
// Bounds: fourteen logical publishes (7 x w480 + 7 x w960), each at most five
// ladder rungs x two attempts under one request id, give 140 replies; 192
// leaves room for restart_required re-publishes. Overflow is always reported.
export const PUBLISHER_REPLY_LIMITS = Object.freeze({ replies: 192, groups: 32 });
const publisherVariants = new Set(['w480', 'w960']);
const boundedStatus = status => Number.isInteger(status) && status >= 100 && status <= 599 ? status : null;
const identityKey = key => (typeof key === 'object' && key !== null) || typeof key === 'function';

function responseFacts(status, body) {
  const record = body !== null && typeof body === 'object' && !Array.isArray(body);
  const code = record ? body.error ?? body.code : undefined;
  return {
    httpStatus: boundedStatus(status),
    envelopeOk: record && typeof body.ok === 'boolean' ? body.ok : null,
    responseCode: !record ? 'unclassified' : code === undefined || code === null ? 'missing'
      : responseCodes.has(code) ? code : 'unclassified',
  };
}

export async function captureProductResponse(progress, operation, status, readBody) {
  let body;
  try { body = await readBody(); } catch { /* Never retain a parser error or change the original assertion. */ }
  progress.recordResponse(operation, status, body);
}

export function createProductProgress() {
  let current = { stage: 'fixture', sample: null };
  const completed = [];
  const responses = new Map();
  let passed = false;
  // Publisher reply state: bounded records, request identity and request-id
  // grouping. Dropped replies and unassignable groups are counted explicitly.
  const replies = [];
  const repliesByRequest = new Map();
  const groupsByRequestId = new Map();
  let observedReplies = 0, groupOverflow = 0;
  const stageNow = () => current?.stage ?? null;
  const groupOrdinal = requestId => {
    if (typeof requestId !== 'string' || requestId === '') return null;
    const known = groupsByRequestId.get(requestId);
    if (known !== undefined) return known;
    if (groupsByRequestId.size >= PUBLISHER_REPLY_LIMITS.groups) { groupOverflow += 1; return null; }
    const ordinal = groupsByRequestId.size + 1;
    groupsByRequestId.set(requestId, ordinal);
    return ordinal;
  };
  // Only the first settlement counts; handlers assign fixed values and never throw.
  const settle = (record, state) => {
    if (record.finishedPromise !== 'pending') return;
    record.finishedPromise = state;
    record.finishedPromiseStage = stageNow();
  };
  const markRequest = (requestKey, flag, stageField) => {
    const record = identityKey(requestKey) ? repliesByRequest.get(requestKey) : undefined;
    if (!record || record[flag]) return;
    record[flag] = true;
    record[stageField] = stageNow();
  };
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
    recordResponse(operation, status, body) {
      if (!operations.has(operation)) throw new Error('Invalid fixed product response operation');
      const sample = current?.sample ?? null;
      const key = `${sample}:${operation}`;
      // Keep the first observation for each fixed sample/operation pair.
      if (!responses.has(key)) responses.set(key, { operation, sample, ...responseFacts(status, body) });
    },
    // Never throws: every input is reduced to a fixed label, a bounded integer
    // or a boolean before it is retained. The caller's finished() promise is
    // only observed; its own chain, accounting and rejection path are untouched.
    observePublisherReply(requestKey, facts) {
      observedReplies += 1;
      if (replies.length >= PUBLISHER_REPLY_LIMITS.replies) return;
      const input = facts !== null && typeof facts === 'object' ? facts : {};
      const record = {
        ordinal: observedReplies,
        group: groupOrdinal(input.groupKey),
        variant: publisherVariants.has(input.variant) ? input.variant : 'other',
        httpStatus: boundedStatus(input.status),
        stage: stageNow(),
        sample: current?.sample ?? null,
        finishedPromise: 'pending',
        finishedPromiseStage: null,
        requestFinished: false,
        requestFinishedStage: null,
        requestFailed: false,
        requestFailedStage: null,
      };
      replies.push(record);
      if (identityKey(requestKey) && !repliesByRequest.has(requestKey)) repliesByRequest.set(requestKey, record);
      const finished = input.finished;
      if (identityKey(finished) && typeof finished.then === 'function') {
        try {
          finished.then(() => settle(record, 'fulfilled'), () => settle(record, 'rejected'));
        } catch { /* A hostile thenable must not break the browser event handler. */ }
      }
    },
    markPublisherRequestFinished(requestKey) { markRequest(requestKey, 'requestFinished', 'requestFinishedStage'); },
    markPublisherRequestFailed(requestKey) { markRequest(requestKey, 'requestFailed', 'requestFailedStage'); },
    snapshot() {
      const counts = { pending: 0, fulfilled: 0, rejected: 0, requestFinished: 0, requestFailed: 0 };
      for (const record of replies) {
        counts[record.finishedPromise] += 1;
        if (record.requestFinished) counts.requestFinished += 1;
        if (record.requestFailed) counts.requestFailed += 1;
      }
      return {
        status: passed ? 'PASS' : 'FAIL',
        failedStage: current?.stage ?? null,
        sample: current?.sample ?? null,
        completedStages: completed.map(entry => ({ ...entry })),
        responses: [...responses.values()].map(entry => ({ ...entry })),
        publisherReplies: {
          limits: { ...PUBLISHER_REPLY_LIMITS },
          observed: observedReplies,
          recorded: replies.length,
          droppedReplies: observedReplies - replies.length,
          groupOverflow,
          truncated: observedReplies > replies.length || groupOverflow > 0,
          counts,
          replies: replies.map(record => ({ ...record })),
        },
      };
    },
  };
}
