import { notFound } from 'next/navigation';
import { getStorefront, storefrontSlugs } from '@/source/storefront';
import { FlowScreen } from '@/ui/storefront/checkout/FlowScreen';

/*
 * STOREFRONT-READ-001 route contract (owner decisions D2 / D13):
 *   - a SERVER-RENDERED document, cached per URL for 60 s and served stale for
 *     up to 300 s more while it regenerates (revalidate + expireTime in
 *     next.config.mjs) - not a static export;
 *   - dynamicParams = true: any slug renders on demand; an unknown, unpublished
 *     or suspended one resolves to null and becomes the Unknown document;
 *   - generateStaticParams pre-renders the fixture tenant in fixture mode and
 *     nothing in live mode (the same literals cannot differ per mode);
 *   - a transport failure THROWS (the framework error page; a cached URL keeps
 *     its last good document) - never the fixture, never a fabricated menu.
 */
export const dynamicParams = true;
export const revalidate = 60;

export function generateStaticParams() {
  return storefrontSlugs().map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = await getStorefront(slug);
  if (resolved === null) notFound();
  return <FlowScreen resolution={resolved} locale="ar" slug={slug} screen="cart" />;
}
