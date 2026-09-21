/**
 * Cart and product pricing. INTEGER MINOR UNITS ONLY.
 *
 * This module does the arithmetic; `format.ts` does the presentation and is the
 * only place a decimal point appears. Nothing here uses parseFloat, toFixed or
 * any floating operation - every value in and out is an integer number of
 * agorot, and every function throws rather than return a float, because a float
 * that reaches the cart is a money bug that would otherwise surface as a
 * rounding error much later.
 *
 * The rules mirror the approved prototype exactly:
 *   unit  = item.priceMinor + sum(selected option deltas)   (Storefront.dc.html:689)
 *   line  = unit * qty                                      (Storefront.dc.html:810)
 * There is no tax and no fee here: the dock shows a SUBTOTAL, and the
 * authoritative quote arrives with its own phase.
 */
import type { MenuItem, Minor, ModifierGroup, ModifierSelections } from '@/source/types';

/** Hard bounds the design fixes on a line. */
export const MIN_QTY = 1;
export const MAX_QTY = 20;
/** Kitchen note length, per the approved sheet. */
export const MAX_NOTE = 140;

function assertMinor(value: number, what: string): Minor {
  if (!Number.isInteger(value)) {
    throw new TypeError(`${what} must be integer minor units, received ${String(value)}`);
  }
  return value;
}

/** Clamp to the designed range. Non-integers are rejected, never rounded. */
export function clampQty(qty: number): number {
  if (!Number.isInteger(qty)) {
    throw new TypeError(`qty must be an integer, received ${String(qty)}`);
  }
  return Math.min(MAX_QTY, Math.max(MIN_QTY, qty));
}

/**
 * A stored selection clamped to what the GROUP actually allows.
 *
 * The storage parser validates SHAPE - safe ids, no duplicates, sane counts -
 * but it is menu-agnostic and cannot know that `extras` admits at most three
 * options or that `bun` admits exactly one. A hand-edited cart could therefore
 * hold five extras and be priced outside the designed bounds. Clamping here
 * keeps the price, the line summary and the design in agreement.
 */
export function boundedSelection(
  group: ModifierGroup,
  selected: readonly string[],
): readonly string[] {
  const known = selected.filter((id) => group.options.some((o) => o.id === id));
  const unique = [...new Set(known)];
  if (group.single) return unique.slice(0, 1);
  return group.max === undefined ? unique : unique.slice(0, group.max);
}

/**
 * The delta of one group's current selection.
 *
 * Unknown option ids contribute nothing rather than throwing: a stale persisted
 * cart must degrade, not crash.
 *
 * Each option is priced AT MOST ONCE. The approved modifier model has no
 * per-option quantity - an option is selected or it is not - so a repeated id
 * is malformed input, never "two of these". cartStorage.parseLine already
 * REJECTS a payload containing one, so this is defence in depth: it keeps the
 * money correct for any future caller that reaches this function without going
 * through the storage parser.
 */
export function groupDeltaMinor(group: ModifierGroup, selected: readonly string[]): Minor {
  let delta = 0;
  for (const optionId of boundedSelection(group, selected)) {
    const option = group.options.find((o) => o.id === optionId);
    if (option === undefined) continue;
    delta += assertMinor(option.priceDeltaMinor, `option ${option.id} delta`);
  }
  return delta;
}

/** Base price plus every selected delta, for one unit of the item. */
export function unitPriceMinor(
  item: MenuItem,
  groups: readonly ModifierGroup[],
  selections: ModifierSelections,
): Minor {
  let unit = assertMinor(item.priceMinor, `item ${item.id} price`);
  for (const group of groups) {
    unit += groupDeltaMinor(group, selections[group.id] ?? []);
  }
  return unit;
}

/** Unit price times quantity. */
export function lineTotalMinor(
  item: MenuItem,
  groups: readonly ModifierGroup[],
  selections: ModifierSelections,
  qty: number,
): Minor {
  return unitPriceMinor(item, groups, selections) * clampQty(qty);
}

/** Sum of line totals. The dock's subtotal; no tax, no fee. */
export function subtotalMinor(lineTotals: readonly Minor[]): Minor {
  let sum = 0;
  for (const total of lineTotals) sum += assertMinor(total, 'line total');
  return sum;
}
