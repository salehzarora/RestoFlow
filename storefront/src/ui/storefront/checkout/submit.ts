/**
 * THE FIXTURE REQUEST GATEWAY.
 *
 * This module models the send and returns a typed outcome; it does NOT
 * navigate anywhere and does NOT know what a received screen looks like. The
 * runtime that owns navigation takes the result to `/r/:ref` (Phase E).
 *
 * NO I/O OF ANY KIND. No fetch, no WhatsApp, no queue, no retry timer, no
 * logging. A real gateway would live behind this same signature.
 *
 * IT NEVER RETAINS CUSTOMER FIELDS. The submission is passed in, used to decide
 * an outcome, and dropped. Nothing is stored, echoed into the result, or kept
 * in a module-level variable - which is also why this file holds no state: a
 * server module singleton would leak one visitor's data into another's render.
 */
import type { Quote } from '@/money/quote';
import { DEMO_REQUEST_REF } from '@/source/request-ref';
import type { ServiceState } from '@/source/types';
import type { CheckoutDraft } from './draft';

/** What a send is allowed to carry. Deliberately explicit, never a spread. */
export interface Submission {
  readonly slug: string;
  readonly menuVersion: string;
  /**
   * DEFERRED(IDEM-001). The handoff requires a submit to carry an idempotency
   * key so a retry is the SAME request and the server can answer `duplicate`
   * rather than creating a second one (INTERACTIONS.md:94). The key format and
   * its retention are undefined (OPEN_QUESTIONS.md:46), so this build mints one
   * opaque value per review mount, reuses it across every retry of that
   * attempt, and keeps it in memory only - it is never stored beside the
   * draft, because nothing about this flow may reach web storage.
   *
   * It is derived from nothing the visitor typed: a key is not a place to put
   * a phone number.
   */
  readonly idempotencyKey: string;
  readonly service: CheckoutDraft['service'];
  readonly lines: readonly { readonly itemId: string; readonly qty: number }[];
  readonly subtotalMinor: number;
  readonly feeMinor: number;
  readonly taxMinor: number;
  readonly totalMinor: number;
  readonly zoneId: string;
  /**
   * The contact block. It is passed TRANSIENTLY so a gateway could send it; it
   * is never persisted, never logged and never echoed back in the result.
   */
  readonly contact: {
    readonly fullName: string;
    readonly phone: string;
    readonly area: string;
    readonly street: string;
    readonly building: string;
    readonly apartment: string;
    readonly deliveryNotes: string;
  };
}

/**
 * The typed outcome. Each failure is DISTINCT because each has a different
 * recovery, and collapsing them into one "try again" is what the handoff's
 * separate copy keys exist to prevent.
 */
export type SubmitResult =
  | { readonly kind: 'accepted'; readonly ref: string }
  | { readonly kind: 'duplicate'; readonly ref: string }
  | { readonly kind: 'offline' }
  | { readonly kind: 'server_error' }
  | { readonly kind: 'rate_limited' }
  | { readonly kind: 'cart_changed' }
  /**
   * Ordering was not open at the moment the gateway would have committed the
   * request: the restaurant closed or paused after the send was activated.
   * The screen shows the same closed / paused reason the steps show; nothing
   * was created, so nothing is erased.
   */
  | { readonly kind: 'not_open'; readonly state: 'closed' | 'paused' };

export type RequestGateway = (submission: Submission) => Promise<SubmitResult>;

/** The reference shape the prototype uses, e.g. "MB-2487". */
const REF = /^[A-Z0-9]{1,8}-[A-Z0-9]{1,12}$/;

export function isValidRef(ref: string): boolean {
  return REF.test(ref);
}

/**
 * The fixture gateway. It decides an outcome from demo configuration alone -
 * never from a customer field - so the demo is reproducible and no contact
 * value can change what happens.
 */
export function fixtureGateway(
  options: {
    readonly outcome?: SubmitResult['kind'];
    readonly delayMs?: number;
    /**
     * The restaurant's ordering state as the gateway would see it at the
     * moment of commit. A real gateway asks its own server; the fixture asks
     * the runtime's CURRENT reading, so a send activated while open and
     * committed after a close is refused with the reason, and one committed
     * before the close stays accepted - a completed request is never erased
     * retroactively.
     */
    readonly readiness?: () => ServiceState;
  } = {},
): RequestGateway {
  return async (submission) => {
    // The approved mocked delay (DESIGN_HANDOFF.md:130 "a spinner for ~900ms",
    // INTERACTIONS.md:94 "product behaviour with a mocked delay"). A timer is
    // not I/O: nothing is fetched, posted, queued, logged or retained. Tests
    // pass 0 so they assert behaviour rather than wall-clock.
    const wait = options.delayMs ?? 0;
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    const state: ServiceState = options.readiness?.() ?? 'open';
    if (state === 'closed' || state === 'paused') return { kind: 'not_open', state };
    // A reading this build does not know is not "open": nothing is committed.
    if (state !== 'open') return { kind: 'server_error' };
    const kind = options.outcome ?? 'accepted';
    switch (kind) {
      case 'accepted':
        return { kind: 'accepted', ref: refFor(submission) };
      case 'duplicate':
        return { kind: 'duplicate', ref: refFor(submission) };
      default:
        return { kind } as SubmitResult;
    }
  };
}

/**
 * THE ONE FIXTURE REF. Phase D hashed the order's shape into a mock reference;
 * that reference named a document the static export never emitted, so the
 * accepted send could not be taken anywhere. The fixture now answers with the
 * single generated demo ref that every request route pre-renders and that the
 * status fixture serves (FINISH 4.1). Reconciling the two is a fixture
 * allocation, not production ID generation and not an idempotency claim.
 *
 * The submission is still consulted so the signature stays what a real
 * gateway needs - and so the rule below remains testable: NOTHING about the
 * visitor may be recoverable from a reference, and here nothing about the
 * order is either.
 */
function refFor(submission: Submission): string {
  void submission;
  return DEMO_REQUEST_REF;
}

/** Build a submission from validated state. Contact is read, never stored. */
export function buildSubmission(
  slug: string,
  menuVersion: string,
  quote: Quote,
  draft: CheckoutDraft,
  idempotencyKey: string,
): Submission {
  return {
    slug,
    menuVersion,
    idempotencyKey,
    service: draft.service,
    lines: quote.lines.map((l) => ({ itemId: l.item.id, qty: l.qty })),
    subtotalMinor: quote.subtotalMinor,
    feeMinor: quote.feeMinor,
    taxMinor: quote.taxMinor,
    totalMinor: quote.totalMinor,
    zoneId: draft.zoneId,
    contact: {
      fullName: draft.fullName,
      phone: draft.phone,
      area: draft.area,
      street: draft.street,
      building: draft.building,
      apartment: draft.apartment,
      deliveryNotes: draft.deliveryNotes,
    },
  };
}

/**
 * THE COMPLETION OBSERVER. The review screen hands every terminal result to
 * it; the flow runtime, which owns navigation, takes an accepted result to
 * `/r/:ref` and lets a test observe the same call.
 */
export type CompletionObserver = (result: SubmitResult) => void;

/**
 * Mint one attempt key. Not a security token and never sent anywhere in this
 * phase: it only has to be unique among this visitor's own attempts, so a
 * random suffix is enough, and it carries nothing the visitor typed.
 */
export function newIdempotencyKey(): string {
  return `k${Math.random().toString(36).slice(2, 10)}${Math.random().toString(36).slice(2, 10)}`;
}

/** True when the outcome has a destination: the received / status route. */
export function isTerminal(result: SubmitResult): boolean {
  return result.kind === 'accepted' || result.kind === 'duplicate';
}
