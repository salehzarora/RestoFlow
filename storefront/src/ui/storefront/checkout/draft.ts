/**
 * THE CHECKOUT DRAFT SHAPE.
 *
 * Separated from the provider so the shape can be imported by anything -
 * validation, the submit contract, a test - without dragging React in. The
 * provider that OWNS an instance of it lives in CheckoutDraftProvider.tsx, and
 * that file is where the memory-only rule is stated and enforced.
 *
 * MEMORY ONLY. None of these fields may ever be written to web storage, a
 * cookie, a URL, history state, a log or an analytics call.
 */
export type Service = 'pickup' | 'delivery';

export interface CheckoutDraft {
  readonly service: Service;
  readonly fullName: string;
  readonly phone: string;
  readonly zoneId: string;
  readonly area: string;
  readonly street: string;
  readonly building: string;
  readonly apartment: string;
  readonly deliveryNotes: string;
}

export const EMPTY_DRAFT: CheckoutDraft = {
  service: 'pickup',
  fullName: '',
  phone: '',
  zoneId: '',
  area: '',
  street: '',
  building: '',
  apartment: '',
  deliveryNotes: '',
};
