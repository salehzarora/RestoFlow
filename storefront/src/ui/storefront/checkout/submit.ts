/**
 * THE FIXTURE REQUEST GATEWAY - and the D/E boundary.
 *
 * Phase D owns everything up to and including the typed RESULT of a send.
 * Phase E owns the received/status screen at `/r/:code`. This module therefore
 * models the send and returns a typed outcome; it does NOT navigate anywhere
 * and does NOT know what a received screen looks like.
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
  | { readonly kind: 'cart_changed' };

export type RequestGateway = (submission: Submission) => Promise<SubmitResult>;

/** The reference shape the prototype uses, e.g. "MB-2487". */
const REF = /^[A-Z0-9]{1,8}-[A-Z0-9]{1,12}$/;

export function isValidRef(ref: string): boolean {
  return REF.test(ref);
}

/**
 * The fixture gateway. It decides an outcome from the SUBMISSION SHAPE alone -
 * never from a customer field - so the demo is reproducible and no contact
 * value can change what happens.
 */
export function fixtureGateway(
  options: { readonly outcome?: SubmitResult['kind']; readonly delayMs?: number } = {},
): RequestGateway {
  return async (submission) => {
    // The approved mocked delay (DESIGN_HANDOFF.md:130 "a spinner for ~900ms",
    // INTERACTIONS.md:94 "product behaviour with a mocked delay"). A timer is
    // not I/O: nothing is fetched, posted, queued, logged or retained. Tests
    // pass 0 so they assert behaviour rather than wall-clock.
    const wait = options.delayMs ?? 0;
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
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
 * A deterministic reference derived from order SHAPE only - never from a name,
 * phone or address, which must not be recoverable from a reference.
 */
function refFor(submission: Submission): string {
  let hash = 0;
  const shape = `${submission.slug}|${submission.totalMinor}|${submission.lines
    .map((l) => `${l.itemId}x${l.qty}`)
    .join(',')}`;
  for (let i = 0; i < shape.length; i += 1) {
    hash = (hash * 31 + shape.charCodeAt(i)) >>> 0;
  }
  const code = hash.toString(36).toUpperCase().slice(0, 4).padStart(4, '0');
  return `MB-${code}`;
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
 * THE D/E HANDOFF SEAM.
 *
 * On acceptance Phase E will take the visitor to `/r/:ref`. That route does not
 * exist yet, so D must not navigate to it - an enabled control whose only
 * outcome is a 404 would be worse than an honest block. Instead the completion
 * is handed to an injected observer, which D's tests assert against and E will
 * replace with the real navigation.
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

/** True when the outcome is one E will own a destination for. */
export function isTerminal(result: SubmitResult): boolean {
  return result.kind === 'accepted' || result.kind === 'duplicate';
}
