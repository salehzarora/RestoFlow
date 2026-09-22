/**
 * DEMO SCENARIOS FOR THE PHASE D FLOW - fixture layer only.
 *
 * Two things in Phase D have no honest trigger yet and must still be
 * reviewable:
 *
 *   1. The three cart notices. Which lines changed is a server answer that
 *      does not exist (OPEN_QUESTIONS.md:42-43, marker SNAP-001), so the notice
 *      is INJECTED and the cart screen only renders it. A screen must never
 *      invent a reason to tell a visitor their order changed.
 *   2. The four send failures. The gateway is a fixture; which outcome it
 *      returns is demo configuration, not a decision a component makes.
 *
 * A third entry exists purely to make a RACE reproducible: it slows a smaller
 * cart's quote so an older request always resolves after a newer one.
 *
 * WHY THIS MODULE EXISTS AT ALL. `tests/sf-source-rules.test.mjs` forbids the
 * scenario switch from appearing outside the fixture layer, and that rule is
 * right: the whole switch must disappear with the fixtures when a live adapter
 * lands. So the machinery lives HERE and the screens import a typed answer,
 * rather than the rule being widened to let a component parse demo tokens.
 *
 * Everything here is PRESENTATIONAL. Nothing in this file mutates a cart,
 * changes a price, writes to storage or reaches a network.
 */

/** The three designed cart notices (Storefront.dc.html:849). */
export type FlowNoticeKind = 'changed' | 'price' | 'soldOut';

/** The four designed send failures, plus the two accepted outcomes. */
export type FlowSendOutcome =
  | 'accepted'
  | 'duplicate'
  | 'offline'
  | 'server_error'
  | 'rate_limited'
  | 'cart_changed';

const NOTICES: Readonly<Record<string, FlowNoticeKind>> = {
  'cart-changed': 'changed',
  'cart-price': 'price',
  'cart-sold-out': 'soldOut',
};

const SENDS: Readonly<Record<string, FlowSendOutcome>> = {
  offline: 'offline',
  'server-error': 'server_error',
  'rate-limited': 'rate_limited',
  duplicate: 'duplicate',
};

const RACE = 'quote-race';

/** The one query parameter this switch reads: `?fx=<token>`. */
const PARAM = 'fx';

/**
 * The scenario token in a URL, or ''.
 *
 * An ALLOWLIST, never free text: an unrecognised value selects nothing, so no
 * URL can put arbitrary state on a screen.
 */
export function readFlowScenario(search: string): string {
  const value = new URLSearchParams(search).get(PARAM);
  if (value === null) return '';
  return value in NOTICES || value in SENDS || value === RACE ? value : '';
}

/**
 * Carry a scenario across a step navigation.
 *
 * Without it a demo state chosen on one step vanishes on the next, which makes
 * the send failures unreachable by URL and the evidence unreproducible.
 */
export function withFlowScenario(href: string, scenario: string): string {
  if (scenario === '') return href;
  return `${href}?${PARAM}=${encodeURIComponent(scenario)}`;
}

export function noticeFor(scenario: string): FlowNoticeKind | null {
  return NOTICES[scenario] ?? null;
}

export function sendOutcomeFor(scenario: string): FlowSendOutcome | undefined {
  return SENDS[scenario];
}

export function isQuoteRace(scenario: string): boolean {
  return scenario === RACE;
}

/** Every token this build accepts, for the evidence index and for tests. */
export const FLOW_SCENARIOS: readonly string[] = [
  ...Object.keys(NOTICES),
  ...Object.keys(SENDS),
  RACE,
];
