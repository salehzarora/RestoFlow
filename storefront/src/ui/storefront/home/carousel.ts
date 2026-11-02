/** Presentation-only carousel math; product identity and ordering stay in data. */
export function cycleIndex(index: number, step: number, count: number): number {
  return count < 2 ? 0 : ((index + step) % count + count) % count;
}

export function carouselPosition(index: number, active: number, count: number): 'active' | 'previous' | 'next' | 'away' {
  if (index === active) return 'active';
  if (count > 1 && index === cycleIndex(active, -1, count)) return 'previous';
  if (count > 2 && index === cycleIndex(active, 1, count)) return 'next';
  return 'away';
}

export function swipeStep(dx: number, dy: number, rtl: boolean): -1 | 0 | 1 {
  if (Math.abs(dx) < 40 || Math.abs(dx) < Math.abs(dy) * 1.25) return 0;
  return (rtl ? dx > 0 : dx < 0) ? 1 : -1;
}
