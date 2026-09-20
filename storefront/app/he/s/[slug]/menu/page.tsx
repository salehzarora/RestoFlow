import { notFound } from 'next/navigation';
import { fixtureSource } from '@/source/fixtures';
import { MenuStub } from '@/ui/storefront/MenuStub';

export const dynamicParams = false;

export function generateStaticParams() {
  return fixtureSource.staticSlugs().map((slug) => ({ slug }));
}

export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const tenant = fixtureSource.getTenant(slug);
  if (tenant === null) notFound();
  return <MenuStub tenant={tenant} locale="he" />;
}
