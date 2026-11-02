import { notFound } from 'next/navigation';
import type { Locale } from '@/i18n/locales';
import { menuPath } from '@/routes/routes';
import { StorefrontScreen } from '@/ui/storefront/StorefrontScreen';
import { Home } from '@/ui/storefront/home/Home';
import { Search } from '@/ui/storefront/search/Search';
import { FlowScreen } from '@/ui/storefront/checkout/FlowScreen';
import { CINEMATIC_PREVIEW_SLUG, cinematicPreviewScreen } from './access';
import { cinematicPreviewResolution } from './resolution';

export type CinematicPreviewParams = Promise<{ screen?: string[] }>;

/** Existing components and actions; only the preview data/profile are substituted. */
export async function CinematicPreviewPage({ locale, params }: { locale: Locale; params: CinematicPreviewParams }) {
  const screen = cinematicPreviewScreen((await params).screen);
  const resolution = cinematicPreviewResolution();
  if (screen === null || resolution === null) notFound();
  const slug = CINEMATIC_PREVIEW_SLUG;
  if (screen === 'intro') return <StorefrontScreen
    tenant={resolution.view.tenant} campaign={resolution.view.modules.campaign}
    locale={locale} slug={slug} preset={resolution.preset} motion={resolution.view.motion}
  />;
  if (screen === 'menu') return <Home resolution={resolution} locale={locale} slug={slug} hrefFor={target => menuPath(target, slug)} />;
  if (screen === 'search') return <Search resolution={resolution} locale={locale} slug={slug} />;
  return <FlowScreen resolution={resolution} locale={locale} slug={slug} screen="cart" />;
}
