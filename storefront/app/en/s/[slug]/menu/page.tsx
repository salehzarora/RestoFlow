import { notFound } from 'next/navigation';
import { resolveHome, homeSlugs } from '@/source/home';
import { storefrontPath } from '@/routes/routes';
import { Home } from '@/ui/storefront/home/Home';

export const dynamicParams = false;

export function generateStaticParams() {
  // Evidence-build only (SF_EVIDENCE_ROUTES=1); the shipped export emits just
  // the canonical tenant. These carry the English-copy browser cases.
  return homeSlugs(['demo-light', 'demo-closed', 'demo-popular-off']).map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return (
    <Home
      view={resolved.view}
      locale="en"
      slug={slug}
      preset={resolved.preset}
      hrefFor={(target) => `${storefrontPath(target, slug)}/menu`}
    />
  );
}
