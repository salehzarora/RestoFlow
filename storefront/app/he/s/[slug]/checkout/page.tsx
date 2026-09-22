import { notFound } from 'next/navigation';
import { resolveHome, homeSlugs } from '@/source/home';
import { FlowScreen } from '@/ui/storefront/checkout/FlowScreen';

export const dynamicParams = false;

/*
 * The shipped export carries the canonical tenant and nothing else; a local
 * evidence build (SF_EVIDENCE_ROUTES=1) adds the demo slugs.
 *
 * EVERY demo slug gets the flow routes, not just the ones whose STATE this
 * screen renders. A narrower list looked cheaper and was wrong: the cart dock
 * and the wide aside on a demo MENU page link to that slug's cart and
 * checkout, so omitting them left a live control pointing at a 404 - which the
 * keyframe census caught as a failed request before any human would have.
 */
export function generateStaticParams() {
  return homeSlugs().map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const resolved = resolveHome(slug);
  if (resolved === null) notFound();
  return (
    <FlowScreen
      tenant={resolved.view.tenant}
      locale="he"
      slug={slug}
      screen="checkout"
      preset={resolved.preset}
      motion={resolved.view.motion}
    />
  );
}
