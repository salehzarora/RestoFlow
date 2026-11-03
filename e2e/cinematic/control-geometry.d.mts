export function controlGeometry(
  rect: { x: number; y: number; width: number; height: number } | null,
  viewport: { width: number; height: number },
  centerHit: boolean,
): { ready: boolean; deltaY: number };
