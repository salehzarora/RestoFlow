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

/** Lock direction only after intent is clear, leaving vertical scrolling native. */
export function swipeIntent(dx: number, dy: number): 'horizontal' | 'vertical' | null {
  if (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(dy) * 1.25) return 'horizontal';
  if (Math.abs(dy) > 12 && Math.abs(dy) > Math.abs(dx) * 1.25) return 'vertical';
  return null;
}

/** Mirrors the existing CSS orbit, including its mobile override. */
export function carouselOrbit(viewportWidth: number): number {
  return viewportWidth <= 650 ? viewportWidth * .31 : Math.min(230, Math.max(100, viewportWidth * .3));
}

/** Finger-follow is transient presentation; product selection changes on release. */
export function carouselDragPosition(index: number, active: number, count: number, dx: number, orbit: number, rtl: boolean) {
  let offset = cycleIndex(index - active, 0, count);
  // Two products still have one real neighbour, matching carouselPosition.
  if (count > 1 && offset === count - 1) offset = -1;
  else if (offset > count / 2) offset -= count;
  const axis = rtl ? -orbit : orbit;
  const progress = Math.max(-orbit, Math.min(orbit, dx)) / axis;
  // With two items, orient the one real neighbour on the incoming side once
  // dragging has a direction; no duplicate catalogue/slide node is introduced.
  if (count === 2 && offset !== 0 && progress !== 0) offset = progress > 0 ? -1 : 1;
  const position = offset + progress;
  const distance = Math.abs(position), near = Math.min(1, distance), far = Math.max(0, Math.min(1, distance - 1));
  return {
    x: Math.max(-1, Math.min(1, position)) * axis,
    y: -12 * near - 8 * far,
    scale: 1 - .43 * near - .22 * far,
    opacity: (1 - .15 * near) * (1 - far),
    brightness: 1 - .22 * near,
    visible: distance < 2,
    zIndex: Math.max(0, Math.round(3 - 2 * distance)),
  };
}
