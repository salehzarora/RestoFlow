import type { Tenant } from '@/source/types';

/** Read-only presentation choice. The hero source and tenant data stay intact. */
export function menuBackground(tenant: Pick<Tenant, 'heroImage' | 'menuBackgroundImage' | 'menuBackgroundDim'>, scenePreset?: 'reference_dark' | null) {
  const value = tenant.menuBackgroundDim;
  const dim = typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 80 ? value : 15;
  // The reference also uses neutral, adjustable dimming when the menu inherits
  // the hero photo. Missing settings preserve the original legacy fallback.
  if (!tenant.menuBackgroundImage) return { kind: 'legacy' as const, image: tenant.heroImage, dim: scenePreset === 'reference_dark' ? dim : null };
  return { kind: 'custom' as const, image: tenant.menuBackgroundImage, dim };
}
