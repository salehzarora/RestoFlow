import { cache } from 'react';
import type { Metadata } from 'next';
import { getStorefront } from '@/source/storefront';
import type { StorefrontResolution } from '@/source/types';
import { menuPath } from '@/routes/routes';
import { absoluteUrl } from '@/routes/origin';
import { isValidSlug } from '@/theme/sanitize';

/** One request-scoped read shared by the menu document and its metadata.
 * No persistent cache: existing publication, error and ISR semantics remain
 * owned by getStorefront and the route. Primitive slug keys isolate tenants.
 */
export const getMenuResolution = cache((slug: string) =>
  isValidSlug(slug) ? getStorefront(slug) : Promise.resolve(null),
);

function publicText(value: unknown, limit: number): string | null {
  if (typeof value !== 'string') return null;
  const text = value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/gu, ' ').trim();
  return text ? Array.from(text).slice(0, limit).join('') : null;
}

/** Metadata is derived only from the same published resolution as the page.
 * The presentation model carries shared merchant strings, not evidence of
 * independent language variants. Until a versioned contract supplies that
 * evidence, all menu locales reference the existing Arabic canonical and
 * intentionally advertise no hreflang (including no invented x-default).
 * This is metadata preparation only; every indexing barrier remains active.
 */
export function menuMetadata(slug: string, resolved: StorefrontResolution): Metadata {
  if (!isValidSlug(slug)) {
    throw new Error('Storefront metadata scope mismatch');
  }
  if (resolved.view.tenant.slug !== slug) {
    // Existing local evidence scenarios intentionally reuse a fixture tenant.
    // They have no public identity/canonical; leave their inherited shell
    // metadata intact. Live responses must still match the requested tenant.
    if (resolved.source === 'fixture') return { robots: { index: false, follow: false } };
    throw new Error('Storefront metadata scope mismatch');
  }
  const tenant = resolved.view.tenant;
  const name = publicText(tenant.displayName, 160) ?? 'BIZBOT';
  return {
    title: name,
    description: publicText(tenant.tagline, 320) ?? name,
    alternates: { canonical: absoluteUrl(menuPath('ar', slug)) },
    robots: { index: false, follow: false },
  };
}
