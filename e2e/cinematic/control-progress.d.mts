export const MAX_REVEAL_WHEELS: 80;
export type RevealProgress = { direction: number; reversed: boolean; stalled: number; wheelSteps: number };
export function nextRevealMove(
  state: RevealProgress,
  observation: { progressed: boolean | null; targetDelta: number | null; step: number },
): RevealProgress & { stop: boolean; delta: number; termination: 'iteration-limit' | 'stalled' | null };
export type ObservedResponse<T> = { ok: true; value: T } | { ok: false; error: unknown };
export function observeResponse<T>(promise: Promise<T>): Promise<ObservedResponse<T>>;
export function responseAfterAction<T>(observed: Promise<ObservedResponse<T>>, action: () => Promise<unknown>): Promise<T>;
