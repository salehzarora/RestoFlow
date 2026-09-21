/**
 * CART MODEL — pure functions over CartState. No React, no storage, no DOM.
 *
 * Kept separate from both the persistence layer and the hook so the rules can
 * be tested directly, without a browser and without touching localStorage.
 *
 * Resolution rule: a stored line carries IDS ONLY. Every name, price and image
 * is resolved from the CURRENT menu at render time. A line whose item no longer
 * exists resolves to null and is skipped rather than rendered from stale data.
 */
import { formatMoney } from '@/money/format';
import { boundedSelection } from '@/money/pricing';
import { clampQty, lineTotalMinor, subtotalMinor, unitPriceMinor } from '@/money/pricing';
import { MAX_LINES } from './cartStorage';
import { groupsFor } from '@/source/modifier-fixture';
import type {
  CartLine,
  CartState,
  MenuItem,
  Minor,
  ModifierGroup,
  ModifierSelections,
} from '@/source/types';

/** The approved marker for a removed ingredient (COMPONENT_INVENTORY.md:124). */
const REMOVAL_PREFIX = '\u2715';

export interface ResolvedCartLine {
  readonly line: CartLine;
  readonly item: MenuItem;
  readonly groups: readonly ModifierGroup[];
  readonly unitMinor: Minor;
  readonly totalMinor: Minor;
  /** Selected option names, in group order - display only. */
  readonly optionNames: readonly string[];
}

export interface CartSummary {
  readonly lines: readonly ResolvedCartLine[];
  /** Total number of units, not number of lines. */
  readonly itemCount: number;
  readonly subtotalMinor: Minor;
}

function findItem(items: readonly MenuItem[], id: string): MenuItem | null {
  return items.find((i) => i.id === id) ?? null;
}

export function resolveLine(
  line: CartLine,
  items: readonly MenuItem[],
): ResolvedCartLine | null {
  const item = findItem(items, line.itemId);
  if (item === null) return null;
  const groups = groupsFor(item.groupIds);
  const optionNames: string[] = [];
  for (const group of groups) {
    for (const optionId of boundedSelection(group, line.selections[group.id] ?? [])) {
      const option = group.options.find((o) => o.id === optionId);
      if (option === undefined) continue;
      // A REMOVAL reads as an addition without its marker: "onion" instead of
      // "no onion" is the opposite instruction to a kitchen.
      // COMPONENT_INVENTORY.md:124 prefixes removals with the multiplication
      // sign, and DESIGN_HANDOFF.md:114 repeats it.
      optionNames.push(group.removal === true ? `${REMOVAL_PREFIX} ${option.name}` : option.name);
    }
  }
  return {
    line,
    item,
    groups,
    unitMinor: unitPriceMinor(item, groups, line.selections),
    totalMinor: lineTotalMinor(item, groups, line.selections, line.qty),
    optionNames,
  };
}

export function summarise(state: CartState, items: readonly MenuItem[]): CartSummary {
  const lines: ResolvedCartLine[] = [];
  for (const line of state.lines) {
    const resolved = resolveLine(line, items);
    if (resolved !== null) lines.push(resolved);
  }
  return {
    lines,
    itemCount: lines.reduce((sum, l) => sum + l.line.qty, 0),
    subtotalMinor: subtotalMinor(lines.map((l) => l.totalMinor)),
  };
}

/** The summary string a cart line shows, e.g. "بريوش • جبنة إضافية". */
export function optionSummary(resolved: ResolvedCartLine): string {
  return resolved.optionNames.join(' • ');
}

export { formatMoney };


// ------------------------------------------------------------------ mutations

/**
 * A local line id. Not a security token and never sent anywhere: it only has to
 * be unique within one visitor's cart, so a counter plus a short random suffix
 * is enough, and it stays inside the SAFE_ID shape the storage layer accepts.
 */
export function newLineId(existing: readonly CartLine[]): string {
  const taken = new Set(existing.map((l) => l.lineId));
  for (let n = existing.length; n < existing.length + 1000; n += 1) {
    const candidate = `l${n}${Math.random().toString(36).slice(2, 6)}`;
    if (!taken.has(candidate)) return candidate;
  }
  return `l${Date.now().toString(36)}`;
}

export function addLine(
  state: CartState,
  draft: { itemId: string; qty: number; selections: ModifierSelections; note: string },
): CartState {
  const line: CartLine = {
    lineId: newLineId(state.lines),
    itemId: draft.itemId,
    qty: clampQty(draft.qty),
    selections: draft.selections,
    note: draft.note,
  };
  // Each add is its OWN line. The approved design does not specify merging two
  // identical configurations, and silently coalescing distinct additions would
  // be inventing a behaviour - so it is not done.
  //
  // THE CAP IS ENFORCED HERE, not only in the parser. Past MAX_LINES the
  // storage layer refuses to write, so without this the in-memory cart would
  // keep growing while the stored one silently stayed behind - and the next
  // reload would discard everything the visitor added after the cap.
  if (state.lines.length >= MAX_LINES) return state;
  return { ...state, lines: [...state.lines, line] };
}

export function updateLine(
  state: CartState,
  lineId: string,
  draft: { qty: number; selections: ModifierSelections; note: string },
): CartState {
  let found = false;
  const lines = state.lines.map((l) => {
    if (l.lineId !== lineId) return l;
    found = true;
    return { ...l, qty: clampQty(draft.qty), selections: draft.selections, note: draft.note };
  });
  // An unknown lineId leaves the cart exactly as it was, rather than appending.
  return found ? { ...state, lines } : state;
}

export function removeLine(state: CartState, lineId: string): CartState {
  return { ...state, lines: state.lines.filter((l) => l.lineId !== lineId) };
}

export function findLine(state: CartState, lineId: string): CartLine | null {
  return state.lines.find((l) => l.lineId === lineId) ?? null;
}
