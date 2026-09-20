import { notFound } from 'next/navigation';
import { StorefrontScreen } from '@/ui/storefront/StorefrontScreen';
import { fixtureSource } from '@/source/fixtures';

// Only fixture slugs exist in UI-001, so an unlisted slug is not a route at all
// and the host serves the Unknown page (app/(root)/not-found.tsx).
export const dynamicParams = false;

export function generateStaticParams() {
  return fixtureSource.staticSlugs().map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const tenant = fixtureSource.getTenant(slug);
  if (tenant === null) notFound();
  return <StorefrontScreen tenant={tenant} locale="he" />;
}
