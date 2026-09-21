import { notFound } from 'next/navigation';
import { resolveHome, homeSlugs } from '@/source/home';
import { Search } from '@/ui/storefront/search/Search';

export const dynamicParams = false;

export function generateStaticParams() {
  return homeSlugs().map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return <Search view={resolved.view} locale="ar" slug={slug} preset={resolved.preset} />;
}
