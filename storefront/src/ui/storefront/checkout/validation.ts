/**
 * CHECKOUT VALIDATION - transcribed from the approved prototype's `validate()`
 * (Storefront.dc.html:763-766), which is the only place these rules exist.
 *
 *   !service            -> service
 *   !name.trim()        -> name
 *   phone fails regex   -> phone
 *   delivery:
 *     no zone           -> city
 *     zone has no fee   -> outside      (NOT "free delivery")
 *     subtotal < min    -> belowMin
 *     !street.trim()    -> street
 *     !building.trim()  -> building
 *
 * `area`, `apartment` and `deliveryNotes` are NOT required - the handoff lists
 * them as fields, and the prototype never validates them. Do not invent a
 * requirement the design does not state.
 *
 * NOTHING HERE CALLS ANYTHING. No API, no geocoder, no phone-number service, no
 * analytics. Validation is a pure function of the draft and the quote, so a
 * keystroke can never become a network request carrying a phone number.
 */
import type { Quote } from '@/money/quote';
import type { CheckoutDraft } from './draft';

/**
 * The prototype's phone shape: a local number beginning 0, then 1-2 digits, an
 * optional separator, 3 digits, an optional separator and 4 digits.
 * Anchored at both ends, with a bounded body, so it cannot backtrack badly.
 */
const PHONE = /^0\d{1,2}[- ]?\d{3}[- ]?\d{4}$/;

/** Field-level problems, in the DOM order the fields appear in. */
export type CheckoutField =
  | 'service'
  | 'fullName'
  | 'phone'
  | 'zoneId'
  | 'street'
  | 'building';

/** A whole-form problem that is not attached to one input. */
export type CheckoutBlocker = 'outside-zone' | 'below-minimum' | 'service-unavailable';

/**
 * What the restaurant currently offers.
 *
 * REQUIRED, with no default. A default of "both available" is precisely the
 * assumption that let a checkout validate against a service the restaurant had
 * switched off: the draft starts on pickup before it knows the tenant, and
 * nothing downstream asked. You cannot validate a checkout without knowing what
 * can actually be ordered, so the caller must say.
 */
export interface ServiceAvailability {
  readonly pickup: boolean;
  readonly delivery: boolean;
}

export function isServiceAvailable(
  service: CheckoutDraft['service'],
  available: ServiceAvailability,
): boolean {
  return service === 'pickup' ? available.pickup : available.delivery;
}

export interface CheckoutValidation {
  readonly invalid: readonly CheckoutField[];
  readonly blockers: readonly CheckoutBlocker[];
  /** The first invalid field in DOM order, for focus + scroll. */
  readonly firstInvalid: CheckoutField | null;
  readonly ok: boolean;
}

/** DOM order, so "first invalid" means first ON SCREEN, not first declared. */
const FIELD_ORDER: readonly CheckoutField[] = [
  'service',
  'fullName',
  'phone',
  'zoneId',
  'street',
  'building',
];

export function validateCheckout(
  draft: CheckoutDraft,
  quote: Quote,
  available: ServiceAvailability,
): CheckoutValidation {
  const invalid = new Set<CheckoutField>();
  const blockers: CheckoutBlocker[] = [];

  if (draft.service !== 'pickup' && draft.service !== 'delivery') invalid.add('service');

  /*
   * A SERVICE THE RESTAURANT HAS SWITCHED OFF CANNOT BE ORDERED.
   *
   * This is a BLOCKER, not a field error: the visitor has not typed anything
   * wrong, and with both services off there is no answer they could give. The
   * details step reuses the approved service message for it, and the step
   * guards read the same result, so a direct load of /payment or /review cannot
   * walk past it either.
   *
   * When exactly one service is off, the step moves the draft to the other one
   * before this can fire; this is what remains when NEITHER is available.
   */
  if (!isServiceAvailable(draft.service, available)) blockers.push('service-unavailable');
  if (draft.fullName.trim() === '') invalid.add('fullName');
  if (!PHONE.test(draft.phone.trim())) invalid.add('phone');

  if (draft.service === 'delivery') {
    if (quote.blockers.includes('no-zone')) invalid.add('zoneId');
    // Outside-zone and below-minimum are QUOTE facts, not field errors: the
    // chosen town is a real answer, it just cannot be delivered to.
    if (quote.blockers.includes('outside-zone')) blockers.push('outside-zone');
    if (quote.blockers.includes('below-minimum')) blockers.push('below-minimum');
    if (draft.street.trim() === '') invalid.add('street');
    if (draft.building.trim() === '') invalid.add('building');
  }

  const ordered = FIELD_ORDER.filter((f) => invalid.has(f));
  return {
    invalid: ordered,
    blockers,
    firstInvalid: ordered[0] ?? null,
    ok: ordered.length === 0 && blockers.length === 0,
  };
}

/** Bounds, so a paste cannot create an unbounded draft field. */
export const FIELD_LIMITS: Readonly<Record<keyof CheckoutDraft, number>> = {
  service: 16,
  fullName: 60,
  phone: 20,
  zoneId: 32,
  area: 60,
  street: 80,
  building: 16,
  apartment: 16,
  deliveryNotes: 140,
};
