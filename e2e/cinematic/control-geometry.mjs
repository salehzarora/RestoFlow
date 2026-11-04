// Flutter scrollables render their own viewport; DOM attachment alone does not
// prove a semantic control can receive a real pointer event.
export function visibleGeometry(rect, viewport) {
  const top = 96;
  const bottom = viewport.height - 64;
  return rect !== null && rect.width > 0 && rect.height > 0 &&
    rect.x >= 0 && rect.x + rect.width <= viewport.width &&
    rect.y >= top && rect.y + rect.height <= bottom;
}
export function controlGeometry(rect, viewport, centerHit, flutterSurfaceHit = false) {
  const top = 96;
  const bottom = viewport.height - 64;
  const ready = visibleGeometry(rect, viewport) && (centerHit || flutterSurfaceHit);
  const delta = rect === null ? 600 : rect.y + rect.height / 2 - (top + bottom) / 2;
  return { ready, deltaY: Math.max(-600, Math.min(600, Math.abs(delta) < 80 ? 80 : delta)) };
}
