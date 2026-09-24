/**
 * PURE LOOKUPS over data a route handed down - the replacement for the two
 * fixture-bound helpers (modifier-fixture.groupsFor, zones.findZone) at every
 * import site the packet names (§4.5). No fixture import, no I/O: whichever
 * source produced the groups and the zones, the same functions resolve them.
 */
import type { DeliveryZone, ModifierGroup } from './types';

/** The groups an item offers, in the ITEM's display order, skipping any unknown id. */
export function groupsFor(
  groupIds: readonly string[],
  groups: readonly ModifierGroup[],
): readonly ModifierGroup[] {
  const out: ModifierGroup[] = [];
  for (const id of groupIds) {
    const group = groups.find((g) => g.id === id);
    if (group !== undefined) out.push(group);
  }
  return out;
}

/** The zone with this id, or null. An empty zone list (live mode) never matches. */
export function zoneFor(id: string, zones: readonly DeliveryZone[]): DeliveryZone | null {
  return zones.find((z) => z.id === id) ?? null;
}
