import type { ReactNode } from 'react';
import { notFound } from 'next/navigation';
import { CheckoutEntry } from '@/ui/storefront/checkout/CheckoutEntry';
import { CINEMATIC_PREVIEW_SLUG, cinematicPreviewAllowed } from './access';

/** Separate namespace: preview cart storage/provider can never belong to Maps' real slug. */
export function CinematicPreviewLayout({ children, fontClassName }: { children: ReactNode; fontClassName: string }) {
  if (!cinematicPreviewAllowed()) notFound();
  return <CheckoutEntry source="fixture" slug={CINEMATIC_PREVIEW_SLUG}>
    <div className={fontClassName} data-sf-fonts="">{children}</div>
  </CheckoutEntry>;
}
