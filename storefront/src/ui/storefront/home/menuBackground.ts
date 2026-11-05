import type { Tenant } from '@/source/types';

/** Read-only presentation choice. The hero source and tenant data stay intact. */
export function menuBackground(tenant: Pick<Tenant, 'heroImage' | 'menuBackgroundImage' | 'menuBackgroundDim' | 'menuBackgroundVariants'>, scenePreset?: 'reference_dark' | null) {
  const value = tenant.menuBackgroundDim;
  const dim = typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 80 ? value : 15;
  // The reference also uses neutral, adjustable dimming when the menu inherits
  // the hero photo. Missing settings preserve the original legacy fallback.
  if (!tenant.menuBackgroundImage) return { kind: 'legacy' as const, image: tenant.heroImage, dim: scenePreset === 'reference_dark' ? dim : null };
  const variants = tenant.menuBackgroundVariants;
  if (variants?.length === 2 && variants[0].url === tenant.menuBackgroundImage) {
    const high = variants[1];
    // Cover paints the greater of the viewport width and height × source aspect.
    // Let the browser choose from actual widths using its own DPR and cache.
    const coverHeight = Math.ceil(100000 * high.width / high.height) / 1000;
    return { kind: 'custom' as const, image: tenant.menuBackgroundImage, dim,
      srcSet: variants.map(v => `${v.url} ${v.width}w`).join(', '),
      sizes: `max(100vw, ${coverHeight}svh)` };
  }
  return { kind: 'custom' as const, image: tenant.menuBackgroundImage, dim };
}
