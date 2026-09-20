import { notFound } from 'next/navigation';
import { resolveHome } from '@/source/home';
import { storefrontPath } from '@/routes/routes';
import { Home } from '@/ui/storefront/home/Home';

export const dynamicParams = false;

export function generateStaticParams() {
  return ['maps-burger'].map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return (
    <Home
      view={resolved.view}
      locale="ar"
      slug={slug}
      preset={resolved.preset}
      hrefFor={(target) => `${storefrontPath(target, slug)}/menu`}
    />
  );
}
