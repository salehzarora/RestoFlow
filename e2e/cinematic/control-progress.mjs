// A scan advances only after observing the preceding physical wheel. A finite
// emergency cap is secondary to stagnation/end detection, never the normal loop.
export const MAX_REVEAL_WHEELS = 80;
export function nextRevealMove(state, { progressed, targetDelta, step }) {
  if (state.wheelSteps >= MAX_REVEAL_WHEELS) return { ...state, stop: true, delta: 0, termination: 'iteration-limit' };
  const stalled = progressed === false ? state.stalled + 1 : 0;
  if (stalled >= 2) {
    if (state.reversed) return { ...state, stalled, stop: true, delta: 0, termination: 'stalled' };
    return { direction: -state.direction, reversed: true, stalled: 0, wheelSteps: state.wheelSteps + 1, stop: false, delta: -state.direction * step, termination: null };
  }
  const delta = targetDelta === null ? state.direction * step : Math.max(-step, Math.min(step, targetDelta));
  return { ...state, direction: Math.sign(delta) || state.direction, stalled, wheelSteps: state.wheelSteps + 1, stop: false, delta, termination: null };
}

// Install both handlers at creation. A later response timeout must never mask
// an earlier reveal/click failure or turn into an unhandled rejection.
export function observeResponse(promise) {
  return promise.then(value => ({ ok: true, value }), error => ({ ok: false, error }));
}
export async function responseAfterAction(observed, action) {
  await action();
  const result = await observed;
  if (!result.ok) throw result.error;
  return result.value;
}
