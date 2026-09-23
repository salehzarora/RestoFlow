import type { ReactNode } from 'react';
import { rubikPreloadHebrew } from '@/fonts/rubik-preload-hebrew';
import { CheckoutDraftProvider } from '@/ui/storefront/checkout/CheckoutDraftProvider';

/**
 * Shared segment layout for one tenant's storefront.
 *
 * WHY IT EXISTS: the checkout draft is APPLICATION MEMORY ONLY. It must survive
 * Checkout -> Payment -> Review -> Back without touching any storage, so the
 * provider has to stay mounted across those navigations. A layout at this
 * segment is what the App Router keeps alive during a soft navigation between
 * its child routes; a full-document navigation would correctly destroy it.
 *
 * The provider is keyed by the CANONICAL slug, so one tenant's draft can never
 * be observed by another.
 *
 * It also binds THIS root's font set (two preloaded subsets, one on demand -
 * src/fonts/README.md) on a wrapper element: bound any higher, in the root
 * layout, the pinned toolchain links every root's set into every document.
 */
export default async function SlugLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  return (
    <CheckoutDraftProvider slug={slug}>
      <div className={rubikPreloadHebrew.className} data-sf-fonts="">{children}</div>
    </CheckoutDraftProvider>
  );
}
