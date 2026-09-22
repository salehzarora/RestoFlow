import { notFound } from 'next/navigation';
import { requestRefs, resolveRequest } from '@/source/request-fixture';
import { RequestScreen } from '@/ui/storefront/request/RequestScreen';

export const dynamicParams = false;

/*
 * ONE canonical opaque demo ref ships, in every locale root; the received and
 * status screens are STATES of this one document, not separate routes. Every
 * other scenario is selected after mount from the fixture's closed allowlist,
 * so an evidence build adds no request document. An unlisted ref is not a
 * route at all and the host serves the platform 404.
 */
export function generateStaticParams() {
  return requestRefs().map((ref) => ({ ref }));
}

export default async function Page({ params }: { params: Promise<{ ref: string }> }) {
  const { ref } = await params;
  const resolved = resolveRequest(ref);
  if (resolved === null) notFound();
  return (
    <RequestScreen
      tenant={resolved.tenant}
      locale="he"
      requestRef={resolved.ref}
      slug={resolved.slug}
      contentLocale={resolved.contentLocale}
    />
  );
}
