import { notFound } from 'next/navigation';
import { resolveHome } from '@/source/home';
import { Search } from '@/ui/storefront/search/Search';

export const dynamicParams = false;

export function generateStaticParams() {
  return ['maps-burger'].map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return <Search view={resolved.view} locale="ar" slug={slug} preset={resolved.preset} />;
}
