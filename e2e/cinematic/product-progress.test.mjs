import test from 'node:test';
import assert from 'node:assert/strict';
import { PUBLISHER_REPLY_LIMITS, captureProductResponse, createProductProgress } from './product-progress.mjs';

// Synthetic deferred promises and plain objects stand in for Playwright's
// response.finished() promise and Request objects; no browser or service runs.
function deferred() {
  let resolve, reject;
  const promise = new Promise((fulfil, fail) => { resolve = fulfil; reject = fail; });
  return { promise, resolve, reject };
}
const settled = () => new Promise(resolve => setImmediate(resolve));
const pendingForever = () => new Promise(() => {});
const emptyPublisherReplies = () => ({
  limits: { replies: PUBLISHER_REPLY_LIMITS.replies, groups: PUBLISHER_REPLY_LIMITS.groups },
  observed: 0, recorded: 0, droppedReplies: 0, groupOverflow: 0, truncated: false,
  counts: { pending: 0, fulfilled: 0, rejected: 0, requestFinished: 0, requestFailed: 0 }, replies: [],
});
function* stringValues(value) {
  if (typeof value === 'string') yield value;
  else if (Array.isArray(value)) for (const item of value) yield* stringValues(item);
  else if (value !== null && typeof value === 'object') for (const item of Object.values(value)) yield* stringValues(item);
}

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
    responses: [], publisherReplies: emptyPublisherReplies(),
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
    publisherReplies: emptyPublisherReplies(),
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
  progress.advance('replacement-selection-proof');
  assert.equal(progress.snapshot().failedStage, 'replacement-selection-proof');
  assert.equal(progress.snapshot().sample, 'burger-highres');
  progress.advance('highres-cutout-render');
  progress.advance('highres-original-render');
  const receipt = progress.snapshot();
  assert.equal(receipt.status, 'FAIL');
  assert.equal(receipt.failedStage, 'highres-original-render');
  assert.equal(receipt.sample, 'burger-highres');
  assert.deepEqual(receipt.completedStages.at(-1), { stage: 'highres-cutout-render', sample: 'burger-highres' });
});

test('publisher replies settle to pending, fulfilled or rejected while the baseline wait keeps its own rejection', async () => {
  const progress = createProductProgress();
  progress.advance('publish-selection', 'platter');
  const replies = [deferred(), deferred(), deferred()];
  const keys = replies.map(() => ({}));
  // The spec's own accounting, composed exactly as product-cutout.spec.ts does.
  const publisherCalls = [];
  const publishedReplies = replies.map((reply, index) => {
    const pushed = reply.promise.then(() => { publisherCalls.push({ variant: 'w480', status: 200 }); });
    progress.observePublisherReply(keys[index], { variant: 'w480', status: 200, groupKey: `publish-${index}`, finished: reply.promise });
    return pushed;
  });
  assert.deepEqual(progress.snapshot().publisherReplies.replies.map(reply => reply.finishedPromise), ['pending', 'pending', 'pending']);
  assert.deepEqual(publisherCalls, []);
  replies[0].resolve(null);
  await settled();
  assert.equal(progress.snapshot().publisherReplies.replies[0].finishedPromise, 'fulfilled');
  assert.equal(progress.snapshot().publisherReplies.replies[0].finishedPromiseStage, 'publish-selection');
  assert.equal(publisherCalls.length, 1, 'accounting still happens at fulfilment, not at observation');
  progress.advance('publication-counts', null);
  const closeReason = new Error('secret-target-closed-reason');
  replies[1].reject(closeReason);
  await assert.rejects(Promise.all(publishedReplies), error => error === closeReason);
  await settled();
  const receipt = progress.snapshot().publisherReplies;
  assert.deepEqual(receipt.replies.map(reply => [reply.finishedPromise, reply.finishedPromiseStage]),
    [['fulfilled', 'publish-selection'], ['rejected', 'publication-counts'], ['pending', null]]);
  assert.deepEqual(receipt.counts, { pending: 1, fulfilled: 1, rejected: 1, requestFinished: 0, requestFailed: 0 });
  assert.equal(publisherCalls.length, 1);
  assert.equal(JSON.stringify(progress.snapshot()).includes('secret-target-closed-reason'), false);
});

test('a failed browser request is recorded while its finished promise stays pending', async () => {
  const progress = createProductProgress();
  progress.advance('publish-selection', 'drink');
  const request = {};
  progress.observePublisherReply(request, { variant: 'w960', status: 200, groupKey: 'publish-a', finished: pendingForever() });
  progress.advance('selection-readback');
  progress.markPublisherRequestFailed(request);
  await settled();
  const expected = { ordinal: 1, group: 1, variant: 'w960', httpStatus: 200, stage: 'publish-selection', sample: 'drink',
    finishedPromise: 'pending', finishedPromiseStage: null, requestFinished: false, requestFinishedStage: null,
    requestFailed: true, requestFailedStage: 'selection-readback' };
  assert.deepEqual(progress.snapshot().publisherReplies.replies, [expected]);
  // Repeated, unknown or primitive keys change nothing.
  progress.advance('close-product');
  progress.markPublisherRequestFailed(request);
  progress.markPublisherRequestFinished({});
  progress.markPublisherRequestFailed('publish-a');
  progress.markPublisherRequestFinished(undefined);
  assert.deepEqual(progress.snapshot().publisherReplies.replies, [expected]);
  assert.deepEqual(progress.snapshot().publisherReplies.counts,
    { pending: 1, fulfilled: 0, rejected: 0, requestFinished: 0, requestFailed: 1 });
});

test('requestfinished is observed independently of the finished promise', async () => {
  const progress = createProductProgress();
  progress.advance('registration-proof', 'burger');
  const early = { key: {}, reply: deferred() }, late = { key: {}, reply: deferred() };
  progress.observePublisherReply(early.key, { variant: 'w480', status: 200, groupKey: 'publish-early', finished: early.reply.promise });
  progress.observePublisherReply(late.key, { variant: 'w960', status: 202, groupKey: 'publish-late', finished: late.reply.promise });
  const reply = index => progress.snapshot().publisherReplies.replies[index];
  // Browser event first, promise still pending.
  progress.markPublisherRequestFinished(early.key);
  assert.deepEqual([reply(0).requestFinished, reply(0).requestFinishedStage, reply(0).finishedPromise], [true, 'registration-proof', 'pending']);
  early.reply.resolve(null);
  await settled();
  assert.deepEqual([reply(0).requestFinished, reply(0).finishedPromise, reply(0).requestFailed], [true, 'fulfilled', false]);
  // Promise first with no browser event observed is representable as well.
  late.reply.resolve(null);
  await settled();
  assert.deepEqual([reply(1).finishedPromise, reply(1).requestFinished, reply(1).requestFinishedStage, reply(1).requestFailed],
    ['fulfilled', false, null, false]);
  progress.advance('selected-private-read');
  progress.markPublisherRequestFinished(late.key);
  progress.markPublisherRequestFailed(late.key);
  assert.deepEqual([reply(1).requestFinished, reply(1).requestFinishedStage, reply(1).requestFailed, reply(1).requestFailedStage],
    [true, 'selected-private-read', true, 'selected-private-read']);
  assert.deepEqual(progress.snapshot().publisherReplies.counts,
    { pending: 0, fulfilled: 2, rejected: 0, requestFinished: 2, requestFailed: 1 });
});

test('retry grouping maps the application request id to a per-run ordinal and never serializes it', () => {
  const progress = createProductProgress();
  const requestId = 'c0ffee00-1111-4222-8333-444455556666';
  const observations = [
    [requestId, 'w480', 202], [requestId, 'w480', 200], ['d15c0000-2222-4333-8444-555566667777', 'w960', 200],
    [undefined, 'w960', 200], [42, 'w480', 200], ['', 'w480', 200], [requestId, 'w480', 503],
  ];
  for (const [groupKey, variant, status] of observations) {
    progress.observePublisherReply({}, { variant, status, groupKey, finished: pendingForever() });
  }
  const receipt = progress.snapshot().publisherReplies;
  assert.deepEqual(receipt.replies.map(reply => reply.group), [1, 1, 2, null, null, null, 1]);
  assert.deepEqual(receipt.replies.map(reply => reply.ordinal), [1, 2, 3, 4, 5, 6, 7]);
  assert.deepEqual(receipt.replies.map(reply => reply.httpStatus), [202, 200, 200, 200, 200, 200, 503]);
  assert.equal(receipt.groupOverflow, 0);
  const text = JSON.stringify(progress.snapshot());
  assert.equal(text.includes(requestId), false);
  assert.equal(text.includes('d15c0000'), false);
  // Every string in the receipt is a short fixed label: no identifier, digest or free text.
  for (const value of stringValues(progress.snapshot())) {
    assert.ok(value.length <= 32 && /^[A-Za-z0-9_-]+$/.test(value), 'free-form string leaked into the receipt');
  }
});

test('publisher reply facts keep only fixed labels, bounded status and current stage labels', () => {
  const progress = createProductProgress();
  progress.advance('publish-selection', 'fries-cup');
  const last = () => progress.snapshot().publisherReplies.replies.at(-1);
  for (const [variant, expected] of [['w480', 'w480'], ['w960', 'w960'], ['bg2560', 'other'], [undefined, 'other'],
    [{ secret: 'variant' }, 'other'], ['W480', 'other']]) {
    progress.observePublisherReply({}, { variant, status: 200, groupKey: 'publish-v', finished: pendingForever() });
    assert.equal(last().variant, expected);
  }
  for (const [status, expected] of [[200, 200], [202, 202], [503, 503], [99, null], [600, null], [200.5, null],
    ['200', null], [NaN, null], [null, null], [undefined, null]]) {
    progress.observePublisherReply({}, { variant: 'w480', status, groupKey: 'publish-s', finished: pendingForever() });
    assert.equal(last().httpStatus, expected);
  }
  progress.observePublisherReply({}, undefined);
  progress.observePublisherReply({}, null);
  for (const reply of progress.snapshot().publisherReplies.replies.slice(-2)) {
    assert.deepEqual([reply.variant, reply.httpStatus, reply.group, reply.finishedPromise, reply.stage, reply.sample],
      ['other', null, null, 'pending', 'publish-selection', 'fries-cup']);
  }
  const text = JSON.stringify(progress.snapshot());
  assert.equal(text.includes('bg2560'), false);
  assert.equal(text.includes('secret'), false);
  assert.equal(text.includes('W480'), false);
  // After completion no stage is current; labels become null rather than an invented value.
  progress.advance('success-evidence', null);
  progress.complete();
  progress.observePublisherReply({}, { variant: 'w960', status: 200, groupKey: 'publish-late', finished: pendingForever() });
  assert.deepEqual([last().stage, last().sample, last().variant], [null, null, 'w960']);
});

test('reply records and the grouping map are bounded with explicit overflow', () => {
  const { replies: maxReplies, groups: maxGroups } = PUBLISHER_REPLY_LIMITS;
  const progress = createProductProgress();
  for (let index = 0; index < maxReplies + 3; index += 1) {
    progress.observePublisherReply({}, { variant: 'w480', status: 200, groupKey: `publish-${index % 4}`, finished: pendingForever() });
  }
  const receipt = progress.snapshot().publisherReplies;
  assert.deepEqual([receipt.observed, receipt.recorded, receipt.droppedReplies, receipt.groupOverflow, receipt.truncated],
    [maxReplies + 3, maxReplies, 3, 0, true]);
  assert.equal(receipt.replies.length, maxReplies);
  assert.equal(receipt.replies.at(-1).ordinal, maxReplies);
  assert.deepEqual(receipt.limits, { replies: maxReplies, groups: maxGroups });

  const grouped = createProductProgress();
  for (let index = 0; index < maxGroups + 2; index += 1) {
    grouped.observePublisherReply({}, { variant: 'w960', status: 200, groupKey: `publish-${index}`, finished: pendingForever() });
  }
  grouped.observePublisherReply({}, { variant: 'w960', status: 200, groupKey: 'publish-0', finished: pendingForever() });
  const groupedReceipt = grouped.snapshot().publisherReplies;
  assert.deepEqual(groupedReceipt.replies.slice(maxGroups - 1).map(reply => reply.group), [maxGroups, null, null, 1]);
  assert.deepEqual([groupedReceipt.groupOverflow, groupedReceipt.droppedReplies, groupedReceipt.truncated], [2, 0, true]);
  assert.deepEqual(emptyPublisherReplies().truncated, false);
});

test('publisher reply snapshots are immutable copies', async () => {
  const progress = createProductProgress();
  progress.advance('publish-selection', 'burger');
  const key = {}, reply = deferred();
  progress.observePublisherReply(key, { variant: 'w480', status: 200, groupKey: 'publish-a', finished: reply.promise });
  const before = progress.snapshot();
  const frozen = JSON.stringify(before);
  reply.resolve(null);
  progress.markPublisherRequestFinished(key);
  progress.observePublisherReply({}, { variant: 'w960', status: 200, groupKey: 'publish-b', finished: pendingForever() });
  await settled();
  assert.equal(JSON.stringify(before), frozen, 'later events never alter an earlier receipt');
  before.publisherReplies.replies[0].finishedPromise = 'secret-state';
  before.publisherReplies.replies.push({ variant: 'secret-variant' });
  before.publisherReplies.counts.pending = 99;
  before.publisherReplies.limits.replies = 1;
  const after = progress.snapshot().publisherReplies;
  assert.equal(JSON.stringify(after).includes('secret'), false);
  assert.deepEqual([after.recorded, after.limits.replies, after.counts],
    [2, PUBLISHER_REPLY_LIMITS.replies, { pending: 1, fulfilled: 1, rejected: 0, requestFinished: 1, requestFailed: 0 }]);
});

test('observer inputs never throw and the observer adds no unhandled rejection', async () => {
  const progress = createProductProgress();
  const rejections = [];
  const record = reason => { rejections.push(reason); };
  process.on('unhandledRejection', record);
  try {
    assert.doesNotThrow(() => {
      progress.observePublisherReply(undefined, undefined);
      progress.observePublisherReply(null, { finished: 'not-a-promise' });
      progress.observePublisherReply({}, { finished: { then() { throw new Error('hostile thenable'); } } });
      progress.observePublisherReply({}, { finished: { then(fulfil, fail) { fail(new Error('synchronous rejection')); fulfil(null); fail(new Error('again')); } } });
      progress.markPublisherRequestFinished(null);
      progress.markPublisherRequestFailed(Symbol('request'));
    });
    const observerOnly = Promise.reject(new Error('rejection seen only by the observer'));
    progress.observePublisherReply({}, { variant: 'w480', status: 200, groupKey: 'publish-r', finished: observerOnly });
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.deepEqual(rejections, []);
    assert.deepEqual(progress.snapshot().publisherReplies.replies.map(reply => reply.finishedPromise),
      ['pending', 'pending', 'pending', 'rejected', 'rejected']);
    assert.equal(JSON.stringify(progress.snapshot()).includes('hostile'), false);
  } finally {
    process.off('unhandledRejection', record);
  }
});

test('only the first settlement of a finished promise counts', () => {
  const progress = createProductProgress();
  progress.advance('publish-selection', 'burger');
  // Synchronous thenables settle twice on purpose; a real promise cannot.
  const rejectThenFulfil = { then(fulfil, fail) { fail(new Error('first')); progress.advance('selection-readback'); fulfil(null); } };
  progress.observePublisherReply({}, { variant: 'w480', status: 200, groupKey: 'publish-a', finished: rejectThenFulfil });
  const fulfilThenReject = { then(fulfil, fail) { fulfil(null); fail(new Error('late')); } };
  progress.observePublisherReply({}, { variant: 'w960', status: 200, groupKey: 'publish-b', finished: fulfilThenReject });
  assert.deepEqual(progress.snapshot().publisherReplies.replies.map(reply => [reply.finishedPromise, reply.finishedPromiseStage]),
    [['rejected', 'publish-selection'], ['fulfilled', 'selection-readback']]);
  assert.equal(JSON.stringify(progress.snapshot()).includes('first'), false);
});

test('request correlation uses object identity only and keeps the first record of a repeated request object', () => {
  const progress = createProductProgress();
  progress.advance('registration-proof', 'platter');
  // Equal primitive keys are never correlation keys.
  progress.observePublisherReply('request-a', { variant: 'w480', status: 200, groupKey: 'publish-a', finished: pendingForever() });
  progress.markPublisherRequestFinished('request-a');
  progress.observePublisherReply(undefined, { variant: 'w480', status: 200, groupKey: 'publish-b', finished: pendingForever() });
  progress.markPublisherRequestFailed(undefined);
  // The same request object observed twice keeps its first record.
  const request = {};
  progress.observePublisherReply(request, { variant: 'w960', status: 202, groupKey: 'publish-c', finished: pendingForever() });
  progress.observePublisherReply(request, { variant: 'w960', status: 200, groupKey: 'publish-c', finished: pendingForever() });
  progress.markPublisherRequestFinished(request);
  const receipt = progress.snapshot().publisherReplies;
  assert.deepEqual(receipt.replies.map(reply => [reply.requestFinished, reply.requestFailed]),
    [[false, false], [false, false], [true, false], [false, false]]);
  assert.deepEqual([receipt.counts.requestFinished, receipt.counts.requestFailed], [1, 0]);
});

test('dropped replies never consume a group slot', () => {
  const { replies: maxReplies, groups: maxGroups } = PUBLISHER_REPLY_LIMITS;
  const progress = createProductProgress();
  // Fill every reply slot using exactly the available group slots, then offer dropped replies with new ids.
  for (let index = 0; index < maxReplies; index += 1) {
    progress.observePublisherReply({}, { variant: 'w480', status: 200, groupKey: `publish-${index % maxGroups}`, finished: pendingForever() });
  }
  assert.equal(progress.snapshot().publisherReplies.groupOverflow, 0);
  for (let index = 0; index < 3; index += 1) {
    progress.observePublisherReply({}, { variant: 'w480', status: 200, groupKey: `dropped-${index}`, finished: pendingForever() });
  }
  const receipt = progress.snapshot().publisherReplies;
  assert.deepEqual([receipt.observed, receipt.recorded, receipt.droppedReplies, receipt.groupOverflow, receipt.truncated],
    [maxReplies + 3, maxReplies, 3, 0, true]);
});

test('observer state is settled by the time the awaiting continuation runs, without an extra tick', async () => {
  const progress = createProductProgress();
  progress.advance('publish-selection', 'drink');
  const good = deferred(), stuck = deferred();
  // The spec's composition: the pushed chain is registered before the observer.
  const chains = [good, stuck].map((reply, index) => {
    const pushed = reply.promise.then(() => {});
    progress.observePublisherReply({}, { variant: 'w480', status: 200, groupKey: `publish-${index}`, finished: reply.promise });
    return pushed;
  });
  good.resolve(null);
  await chains[0];
  assert.equal(progress.snapshot().publisherReplies.replies[0].finishedPromise, 'fulfilled');
  progress.advance('publication-counts', null);
  const closeReason = new Error('page closed');
  let receipt;
  try {
    stuck.reject(closeReason);
    await Promise.all(chains);
    assert.fail('the wait must reject');
  } catch (error) {
    assert.equal(error, closeReason);
  } finally {
    receipt = progress.snapshot();
  }
  assert.deepEqual([receipt.publisherReplies.replies[1].finishedPromise, receipt.publisherReplies.replies[1].finishedPromiseStage],
    ['rejected', 'publication-counts']);
  assert.deepEqual(receipt.publisherReplies.counts, { pending: 0, fulfilled: 1, rejected: 1, requestFinished: 0, requestFailed: 0 });
});
