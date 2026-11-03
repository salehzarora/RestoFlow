import type { Tenant } from '@/source/types';

/** Read-only presentation choice. The hero source and tenant data stay intact. */
export function menuBackground(tenant: Pick<Tenant, 'heroImage' | 'menuBackgroundImage' | 'menuBackgroundDim'>) {
  if (!tenant.menuBackgroundImage) return { kind: 'legacy' as const, image: tenant.heroImage, dim: null };
  const value = tenant.menuBackgroundDim;
  const dim = typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 80 ? value : 15;
  return { kind: 'custom' as const, image: tenant.menuBackgroundImage, dim };
}
