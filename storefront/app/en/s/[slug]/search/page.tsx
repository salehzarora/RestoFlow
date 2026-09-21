import { notFound } from 'next/navigation';
import { resolveHome, homeSlugs } from '@/source/home';
import { Search } from '@/ui/storefront/search/Search';

export const dynamicParams = false;

export function generateStaticParams() {
  // MUST match the en MENU route's slug set exactly. Every menu document
  // renders a search button, so a slug whose menu is exported but whose search
  // is not gives that build a control that 404s.
  return homeSlugs(['demo-light', 'demo-closed', 'demo-popular-off']).map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return <Search view={resolved.view} locale="en" slug={slug} preset={resolved.preset} />;
}
