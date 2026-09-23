'use client';

/**
 * THE QUOTE SOURCE AND ITS RACE CONTRACT.
 *
 * A quote is modelled as ASYNC even though the fixture resolves immediately.
 * That is deliberate: it is the seam a real pricing service would occupy, and
 * modelling it synchronously now would hide the one bug that matters here -
 * an older, slower result landing after a newer one and quietly restoring a
 * stale total while the visitor is looking at a different cart.
 *
 * THE RULE: every request is correlated to the EXACT inputs that produced it,
 * via `quoteKey`. A result whose key is not the current key is DISCARDED, not
 * merged. While the current key has no result, `pending` is true and callers
 * must keep progression blocked rather than ordering against a stale price.
 *
 * The key carries ids, quantities, selections, service and zone only. It never
 * carries a name, phone or address: a quote key can end up in a cache or a log,
 * and customer fields must not.
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { buildQuote, quoteKey, type Quote, type QuoteInput } from './quote';

/** The injectable seam. A real implementation would be a network call. */
export type QuoteSource = (input: QuoteInput) => Promise<Quote>;

/** The fixture source: pure local arithmetic, resolved on a microtask. */
export const fixtureQuoteSource: QuoteSource = async (input) => buildQuote(input);

export interface QuoteState {
  /**
   * The last result that MATCHED THE INPUTS THAT ASKED FOR IT, or null before
   * the first one has arrived.
   *
   * It is deliberately NOT cleared when the inputs move on. Clearing it would
   * make every quantity change blank the totals for at least one frame - and
   * because a screen that has no quote has nothing to draw, it would unmount
   * and remount the whole screen, losing scroll position, focus and any
   * announcement the visitor had not heard yet. That is a worse failure than a
   * total that is one frame behind, and it is a failure this build actually
   * shipped until a removal announcement came back empty.
   *
   * `pending` is what callers must gate PROGRESSION on: a stale total may be
   * displayed, but nothing may be ordered against it.
   */
  readonly quote: Quote | null;
  /** True while the CURRENT inputs have no matching result yet. */
  readonly pending: boolean;
  /** The key the current result belongs to, for assertions and debugging. */
  readonly key: string;
}

export function useQuote(input: QuoteInput, source: QuoteSource = fixtureQuoteSource): QuoteState {
  const key = quoteKey(input);
  const [state, setState] = useState<{ quote: Quote | null; key: string }>({
    quote: null,
    key: '',
  });

  // The key the newest request was issued for. A completion is only accepted
  // when it still matches, so an out-of-order resolution cannot win.
  const currentKey = useRef(key);
  currentKey.current = key;

  // Inputs are read through a ref so the effect depends on the KEY alone: the
  // object identity changes on every render, the key does not.
  const latestInput = useRef(input);
  latestInput.current = input;

  useEffect(() => {
    let cancelled = false;
    const issuedFor = key;
    void (async () => {
      try {
        const result = await source(latestInput.current);
        // Two guards, deliberately both: `cancelled` covers unmount and a
        // superseded effect, `currentKey` covers a resolution that arrives
        // after the inputs moved on within the same effect generation.
        if (cancelled || currentKey.current !== issuedFor) return;
        setState({ quote: result, key: issuedFor });
      } catch {
        // A failed quote leaves the previous one in place and stays pending,
        // so nothing is ordered against a price we could not compute.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [key, source]);

  return { quote: state.quote, pending: state.key !== key, key };
}

/**
 * A test seam: a source that resolves after a caller-controlled delay, so a
 * race can be reproduced deterministically instead of by timing luck.
 */
export function delayedQuoteSource(delayFor: (input: QuoteInput) => number): QuoteSource {
  return async (input) => {
    const ms = delayFor(input);
    if (ms > 0) await new Promise((r) => setTimeout(r, ms));
    return buildQuote(input);
  };
}

/**
 * THE DEMO RACE SOURCE - one definition, shared by every surface that reads a
 * quote, so the cart page and the wide aside can be driven into the same
 * pending state by the same switch.
 *
 * It makes a SMALLER cart resolve MORE slowly, so an older request is guaranteed
 * to land after a newer one. That is the only failure mode an async quote really
 * has, and it cannot be reproduced by timing luck. It changes nothing but WHEN a
 * result arrives: the arithmetic, the inputs and the rendered figures are the
 * fixture's own.
 *
 * Selected only by the fixture layer's closed scenario allowlist. Production
 * passes nothing and gets `fixtureQuoteSource`.
 */
export const raceQuoteSource: QuoteSource = delayedQuoteSource((input) => {
  const units = input.cart.lines.reduce((n, l) => n + l.qty, 0);
  return Math.max(120, 1600 - units * 120);
});

/** Stable identity so passing the default does not retrigger the effect. */
export const useFixtureQuote = (input: QuoteInput): QuoteState =>
  useQuote(input, fixtureQuoteSource);

export const buildQuoteNow = buildQuote;
export { quoteKey };

/** Callers that need to force a refresh (e.g. after a menu change notice). */
export function useQuoteRefresher(): () => void {
  const [, bump] = useState(0);
  return useCallback(() => bump((n) => n + 1), []);
}
