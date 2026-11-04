import test from 'node:test';
import assert from 'node:assert/strict';
import { MAX_REVEAL_WHEELS, nextRevealMove, observeResponse, responseAfterAction } from './control-progress.mjs';
const initial = { direction: 1, reversed: false, stalled: 0, wheelSteps: 0 };
test('search preserves current position and advances less than half its viewport', () => {
  const result = nextRevealMove(initial, { progressed: null, targetDelta: null, step: 360 });
  assert.equal(result.delta, 360);
  assert.equal(result.reversed, false);
});
test('rendered progress clears a transient no-motion sample', () => {
  const result = nextRevealMove({ ...initial, stalled: 1 }, { progressed: true, targetDelta: null, step: 360 });
  assert.equal(result.stalled, 0);
  assert.equal(result.stop, false);
});
test('two settled no-motion steps reverse only once then stop at the other end', () => {
  let state = initial;
  for (let i = 0; i < 2; i++) state = nextRevealMove(state, { progressed: false, targetDelta: null, step: 360 });
  assert.equal(state.reversed, true); assert.equal(state.delta, -360); assert.equal(state.stop, false);
  for (let i = 0; i < 2; i++) state = nextRevealMove(state, { progressed: false, targetDelta: null, step: 360 });
  assert.equal(state.stop, true); assert.equal(state.delta, 0);
});
test('an observed above-viewport target chooses its actual direction with bounded movement', () => {
  const result = nextRevealMove(initial, { progressed: true, targetDelta: -1200, step: 360 });
  assert.equal(result.delta, -360);
});
test('earlier physical-click failure remains primary after a response rejects', async () => {
  const first = new Error('control failure'), later = new Error('response timeout');
  const observed = observeResponse(Promise.reject(later));
  await assert.rejects(responseAfterAction(observed, async () => { await Promise.resolve(); throw first; }), error => error === first);
  assert.deepEqual(await observed, { ok: false, error: later });
});
test('response failure is raised when the actual physical action succeeds', async () => {
  const failure = new Error('response timeout');
  await assert.rejects(responseAfterAction(observeResponse(Promise.reject(failure)), async () => {}), error => error === failure);
});
test('successful action returns the actual observed response', async () => {
  const response = { status: 200 };
  assert.equal(await responseAfterAction(observeResponse(Promise.resolve(response)), async () => {}), response);
});

test('continuous progress still stops after the original 80 physical-wheel input budget', () => {
  let state = initial;
  for (let i = 0; i < MAX_REVEAL_WHEELS; i++) {
    state = nextRevealMove(state, { progressed: true, targetDelta: null, step: 360 });
    assert.equal(state.stop, false);
    assert.equal(state.wheelSteps, i + 1);
  }
  const stopped = nextRevealMove(state, { progressed: true, targetDelta: null, step: 360 });
  assert.equal(stopped.stop, true);
  assert.equal(stopped.termination, 'iteration-limit');
  assert.equal(stopped.wheelSteps, 80);
  assert.equal(stopped.delta, 0);
});
test('stagnation is reported distinctly from exhausting the input budget', () => {
  const stopped = nextRevealMove({ ...initial, reversed: true, stalled: 1, wheelSteps: 3 },
    { progressed: false, targetDelta: null, step: 360 });
  assert.equal(stopped.stop, true);
  assert.equal(stopped.termination, 'stalled');
  assert.equal(stopped.wheelSteps, 3);
});
