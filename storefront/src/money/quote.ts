/**
 * THE QUOTE - the ONE display authority for money on cart, checkout, review
 * and the wide aside.
 *
 * Nothing else may compute tax, a delivery fee or a total. Components read a
 * Quote; they never re-derive one. That is what stops four surfaces drifting
 * apart, and it is why the aside and the cart page can never disagree.
 *
 * THE ARITHMETIC IS THE PROTOTYPE'S, verbatim (Storefront.dc.html:692-696):
 *
 *     subtotal = sum(unit(line) * qty)
 *     fee      = service === 'delivery' && zone && zone.fee ? zone.fee : 0
 *     tax      = round((subtotal + fee) * TAX_RATE)
 *     total    = subtotal + fee + tax
 *
 * Note the tax base: it is (subtotal + FEE), not the subtotal alone. Getting
 * that wrong under-charges tax on every delivery order.
 *
 * PRICES COME FROM THE CURRENT MENU, NEVER FROM STORAGE. A stored cart carries
 * ids and quantities only; every price is resolved here from the fixture, so a
 * tampered or stale payload cannot set its own prices.
 *
 * TAX IS CONFIGURATION, NOT LAW. `TAX_RATE` is a fixture value for this demo
 * tenant. It is passed in rather than imported so no screen can hard-code a
 * rate, and the rendered label must state the configured rate rather than a
 * fixed literal.
 */
import { assertMinor, lineTotalMinor, subtotalMinor } from './pricing';
import { groupsFor } from '@/source/modifier-fixture';
import { isServed, type DeliveryZone } from '@/source/zones';
import type { CartState, MenuItem, Minor } from '@/source/types';

export type Service = 'pickup' | 'delivery';

/** Why a quote cannot yet be ordered. Presentation decides the wording. */
export type QuoteBlocker =
  | 'empty-cart'
  | 'no-zone'
  | 'outside-zone'
  | 'below-minimum';

export interface QuoteLine {
  readonly lineId: string;
  readonly item: MenuItem;
  readonly qty: number;
  readonly unitMinor: Minor;
  readonly lineTotalMinor: Minor;
}

export interface Quote {
  readonly lines: readonly QuoteLine[];
  readonly itemCount: number;
  readonly subtotalMinor: Minor;
  /** 0 for pickup and for any zone that is not served. */
  readonly feeMinor: Minor;
  /** True only when a real delivery fee applies, so 0 is never shown as "free". */
  readonly feeApplies: boolean;
  readonly taxMinor: Minor;
  readonly taxRate: number;
  readonly totalMinor: Minor;
  readonly service: Service;
  readonly zone: DeliveryZone | null;
  /** How far below the zone minimum, in minor units. 0 when not applicable. */
  readonly shortfallMinor: Minor;
  readonly blockers: readonly QuoteBlocker[];
  /** True when nothing blocks progression to the next step. */
  readonly orderable: boolean;
}

export interface QuoteInput {
  readonly cart: CartState;
  readonly items: readonly MenuItem[];
  readonly service: Service;
  readonly zone: DeliveryZone | null;
  readonly taxRate: number;
}

/**
 * A stable key for one set of quote inputs.
 *
 * Used to correlate an async quote result with the state that asked for it, so
 * a slow older result can never overwrite a newer one. It deliberately carries
 * ONLY ids, quantities, selections, service and zone - never a contact or
 * address field, which must not appear in a cache key or a log.
 */
export function quoteKey(input: QuoteInput): string {
  const lines = input.cart.lines
    .map((l) => {
      const sel = Object.keys(l.selections)
        .sort()
        .map((g) => `${g}:${[...l.selections[g]].sort().join('+')}`)
        .join(';');
      return `${l.itemId}x${l.qty}[${sel}]`;
    })
    .join('|');
  return `${input.cart.slug}/${input.cart.menuVersion}/${input.service}/${input.zone?.id ?? '-'}/${input.taxRate}/${lines}`;
}

export function buildQuote(input: QuoteInput): Quote {
  const { cart, items, service, zone, taxRate } = input;

  const lines: QuoteLine[] = [];
  for (const line of cart.lines) {
    const item = items.find((i) => i.id === line.itemId);
    // A line whose item has left the menu is skipped, never priced from stale
    // data and never silently substituted with another product.
    if (item === undefined) continue;
    const groups = groupsFor(item.groupIds);
    const total = lineTotalMinor(item, groups, line.selections, line.qty);
    lines.push({
      lineId: line.lineId,
      item,
      qty: line.qty,
      unitMinor: total / line.qty,
      lineTotalMinor: total,
    });
  }

  const subtotal = subtotalMinor(lines.map((l) => l.lineTotalMinor));
  const served = isServed(zone);
  const feeApplies = service === 'delivery' && served;
  const fee: Minor = feeApplies ? assertMinor(zone!.feeMinor!, 'delivery fee') : 0;

  // The tax base is subtotal PLUS fee - the prototype's rule.
  const tax: Minor = Math.round((subtotal + fee) * taxRate);
  const total: Minor = subtotal + fee + tax;

  const minimum = service === 'delivery' && served ? (zone!.minimumMinor ?? 0) : 0;
  const shortfall: Minor = minimum > subtotal ? minimum - subtotal : 0;

  const blockers: QuoteBlocker[] = [];
  if (lines.length === 0) blockers.push('empty-cart');
  if (service === 'delivery') {
    if (zone === null) blockers.push('no-zone');
    else if (!served) blockers.push('outside-zone');
    else if (shortfall > 0) blockers.push('below-minimum');
  }

  return {
    lines,
    itemCount: lines.reduce((n, l) => n + l.qty, 0),
    subtotalMinor: subtotal,
    feeMinor: fee,
    feeApplies,
    taxMinor: tax,
    taxRate,
    totalMinor: total,
    service,
    zone,
    shortfallMinor: shortfall,
    blockers,
    orderable: blockers.length === 0,
  };
}
