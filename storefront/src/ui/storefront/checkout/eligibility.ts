/**
 * THE ONE SUBMISSION-ELIGIBILITY PREDICATE.
 *
 * Every place that lets a request progress or be sent - the step entry
 * guards, the cart / details / payment / review controls and the send
 * activation itself - asks THIS function, so they cannot disagree about
 * whether ordering is possible right now.
 *
 * Ordering must be EXACTLY 'open'. A closed or paused restaurant, and a
 * readiness that has not resolved (or is a value this build does not know),
 * cannot authorise a step or a send - whichever URL the visitor typed. The
 * cart and the typed draft are never touched by a refusal: the reason is
 * shown, the input stays, and reopening lets the same input proceed.
 *
 * The order of the blockers is the order the visitor can act on them:
 * whether this storefront takes requests AT ALL (STOREFRONT-READ-001: every
 * live tenant is browse-only, so this is the first and standing answer),
 * then readiness (nothing to decide against yet), then the restaurant's
 * state (nothing the visitor can change), then the cart, then the details,
 * then a total that does not yet belong to the current cart.
 */
import type { Quote } from '@/money/quote';
import type { ServiceState } from '@/source/types';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import type { CheckoutDraft } from './draft';
import { validateCheckout } from './validation';

export type OrderingBlocker = 'ordering-off' | 'unresolved' | 'closed' | 'paused';
export type Blocker = OrderingBlocker | 'empty' | 'details' | 'pending';

export type Eligibility =
  | { readonly ok: true }
  | { readonly ok: false; readonly blocker: Blocker };

/**
 * Whether the restaurant's ordering state authorises anything at all.
 * `orderingEnabled` false is the browse-only answer and comes first: no state
 * can authorise a request the storefront does not accept. `null` is "not
 * resolved"; any value other than the three known ones is treated as
 * unresolved too - never as open.
 */
export function orderingBlocker(state: ServiceState | null, orderingEnabled = true): OrderingBlocker | null {
  if (!orderingEnabled) return 'ordering-off';
  if (state === 'open') return null;
  if (state === 'closed' || state === 'paused') return state;
  return 'unresolved';
}

export function submitEligibility(input: {
  /** False for a browse-only storefront: nothing may progress or be sent. */
  readonly orderingEnabled: boolean;
  readonly state: ServiceState | null;
  /** The visitor's own cart has been read and a quote exists for it. */
  readonly ready: boolean;
  /** The quote for the CURRENT cart has not arrived yet. */
  readonly pending: boolean;
  readonly quote: Quote | null;
  readonly draft: CheckoutDraft;
  readonly services: { readonly pickup: boolean; readonly delivery: boolean };
}): Eligibility {
  if (!input.orderingEnabled) return { ok: false, blocker: 'ordering-off' };
  if (!input.ready || input.quote === null) return { ok: false, blocker: 'unresolved' };
  const ordering = orderingBlocker(input.state, input.orderingEnabled);
  if (ordering !== null) return { ok: false, blocker: ordering };
  if (input.quote.lines.length === 0) return { ok: false, blocker: 'empty' };
  if (!validateCheckout(input.draft, input.quote, input.services).ok) return { ok: false, blocker: 'details' };
  if (input.pending) return { ok: false, blocker: 'pending' };
  return { ok: true };
}

/**
 * The localised reason a step shows while ordering is not possible: the two
 * strings the cart and the dock already use for closed / paused
 * (Storefront.dc.html:398, CONTENT_AND_LOCALIZATION.md) and the ONE new family
 * for a browse-only storefront (owner decision D5). Nothing is invented for the
 * unresolved case: a step that cannot decide yet shows its pending frame.
 */
export function orderingReason(
  blocker: OrderingBlocker | null,
  m: StorefrontMessages,
  opensAt: string,
): string | null {
  if (blocker === 'ordering-off') return m.orderingOfflineTitle;
  if (blocker === 'closed') return fill(m.orderingClosed, { t: opensAt });
  if (blocker === 'paused') return m.orderingPaused;
  return null;
}
