/**
 * THE REQUEST ROUTE'S `?fx=` SWITCH - fixture layer only, and deliberately a
 * small module: the flow runtime needs `withRequestScenario` to carry a token
 * from the review URL onto the request route, and importing it from the full
 * status fixture would pull that fixture (snapshots, timers, pricing) into the
 * flow routes' first load, which sits within 1% of its ceiling.
 *
 * A closed allowlist, read only here. `status-<state>` opens the demo ref in
 * that state; the two `-late` tokens make the restaurant answer 1.5 s after
 * load so the cancel race is reproducible; `wa-fallback` renders the
 * "WhatsApp didn't open?" block; `status-missing` makes the source answer that
 * no such request exists.
 */
import { isRequestState, type RequestState } from '@/ui/storefront/request/status';

const STATUS_PREFIX = 'status-';
const LATE_TOKENS = ['status-accepts-late', 'status-expires-late'] as const;
export const WA_FALLBACK = 'wa-fallback';
export const STATUS_MISSING = 'status-missing';
const PARAM = 'fx';

export type RequestScenario =
  | { readonly kind: 'state'; readonly state: RequestState }
  | { readonly kind: 'accepts-late' }
  | { readonly kind: 'expires-late' }
  | { readonly kind: 'fallback' }
  | { readonly kind: 'missing' }
  | null;

export function readRequestScenario(search: string): RequestScenario {
  const value = new URLSearchParams(search).get(PARAM);
  if (value === null) return null;
  if (value === WA_FALLBACK) return { kind: 'fallback' };
  if (value === STATUS_MISSING) return { kind: 'missing' };
  if (value === LATE_TOKENS[0]) return { kind: 'accepts-late' };
  if (value === LATE_TOKENS[1]) return { kind: 'expires-late' };
  if (value.startsWith(STATUS_PREFIX)) {
    const state = value.slice(STATUS_PREFIX.length);
    return isRequestState(state) ? { kind: 'state', state } : null;
  }
  return null;
}

/** Every token this build accepts on the request route, for the evidence index. */
export const REQUEST_SCENARIOS: readonly string[] = [
  ...['received', 'waiting', 'accepted', 'preparing', 'ready', 'completed', 'rejected', 'expired', 'cancelled'].map(
    (s) => `${STATUS_PREFIX}${s}`,
  ),
  ...LATE_TOKENS,
  WA_FALLBACK,
  STATUS_MISSING,
];

/**
 * Carry a REQUEST scenario from the review step's URL onto the request route.
 * The flow's own switch carries only flow tokens; a request token on the
 * review URL selects nothing there and would be dropped by the navigation, so
 * the evidence for the received screen's fallback block could never be
 * reached from a real send. Same closed allowlist: an unrecognised value
 * appends nothing.
 */
export function withRequestScenario(href: string, search: string): string {
  const value = new URLSearchParams(search).get(PARAM);
  if (value === null || !REQUEST_SCENARIOS.includes(value)) return href;
  return `${href}?${PARAM}=${encodeURIComponent(value)}`;
}
