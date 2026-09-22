import { notFound } from 'next/navigation';
import { StorefrontScreen } from '@/ui/storefront/StorefrontScreen';
import { resolveHome, homeSlugs } from '@/source/home';

// Only fixture slugs exist in UI-001, so an unlisted slug is not a route at all
// and the host serves the Unknown page (app/not-found.tsx). The SHIPPED export
// carries the canonical tenant only; a local evidence build adds the demo
// slugs here as it does for the home and flow routes, so the intro's closed /
// paused / pickupOff / deliveryOff states (H01) have a document to prove them on.
export const dynamicParams = false;

export function generateStaticParams() {
  return homeSlugs().map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return <StorefrontScreen tenant={resolved.view.tenant} locale="he" slug={slug} />;
}
