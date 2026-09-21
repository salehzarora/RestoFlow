/**
 * MENU SEARCH — fixture layer, pure function, no network.
 *
 * The approved behaviour (DESIGN_HANDOFF search section, and the prototype's
 * own filter): a case-insensitive SUBSTRING match over the item's name and
 * description. There is deliberately NO relevance ranking and no fuzzy
 * matching - results keep menu order, because inventing a ranking would be
 * inventing a product behaviour the design does not specify.
 *
 * An EMPTY query is not "no results": it shows the first few items so the
 * screen is never a blank box.
 */
import type { MenuItem } from './types';

/** How many items an empty query shows. */
export const EMPTY_QUERY_COUNT = 6;

/**
 * Normalise for comparison. Arabic and Hebrew have no case, so toLowerCase is a
 * no-op there and matters only for the Latin names in the menu ("Maps كلاسيك").
 */
function fold(value: string): string {
  return value.toLowerCase();
}

export function searchItems(
  items: readonly MenuItem[],
  query: string,
): readonly MenuItem[] {
  const trimmed = query.trim();
  if (trimmed.length === 0) return items.slice(0, EMPTY_QUERY_COUNT);
  const needle = fold(trimmed);
  return items.filter((item) => fold(`${item.name} ${item.description}`).includes(needle));
}
