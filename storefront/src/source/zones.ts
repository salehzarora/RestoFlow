/**
 * DELIVERY ZONES - fixture layer, transcribed from the approved prototype's
 * `ZONES` (prototype/storefront-data.js).
 *
 * Every figure is an INTEGER number of minor units, like the rest of the money
 * in this app. `fee: null` is NOT "free": it is the OUT-OF-ZONE marker, which
 * the prototype's own validation reads as `!z.fee -> outside` at
 * Storefront.dc.html:765. A zone with no fee cannot be delivered to, and the
 * checkout must say so rather than quoting zero.
 *
 * This is demo/business configuration, not a legal or tariff assertion.
 */
import type { Minor } from './types';

export interface DeliveryZone {
  readonly id: string;
  readonly name: string;
  /** Delivery fee in minor units, or null when the zone is NOT served. */
  readonly feeMinor: Minor | null;
  /** Minimum order subtotal in minor units, or null when not served. */
  readonly minimumMinor: Minor | null;
}

export const DELIVERY_ZONES: readonly DeliveryZone[] = [
  { id: 'kafrmanda', name: 'كفر مندا', feeMinor: 1000, minimumMinor: 4000 },
  { id: 'sakhnin', name: 'سخنين', feeMinor: 2000, minimumMinor: 8000 },
  { id: 'arraba', name: 'عرابة', feeMinor: 2000, minimumMinor: 8000 },
  // Listed so a visitor can pick it and be told the truth, not hidden so the
  // rejection never happens.
  { id: 'nazareth', name: 'الناصرة', feeMinor: null, minimumMinor: null },
];

export function findZone(id: string): DeliveryZone | null {
  return DELIVERY_ZONES.find((z) => z.id === id) ?? null;
}

/** A zone the restaurant actually delivers to. */
export function isServed(zone: DeliveryZone | null): boolean {
  return zone !== null && zone.feeMinor !== null;
}
