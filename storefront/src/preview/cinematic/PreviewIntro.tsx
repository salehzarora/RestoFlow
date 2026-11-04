import type { Locale } from '@/i18n/locales';
import { StorefrontScreen } from '@/ui/storefront/StorefrontScreen';
import { CINEMATIC_PREVIEW_SLUG } from './access';
import { requireCinematicPreviewResolution } from './pageResolution';

export function CinematicPreviewIntro({ locale }: { locale: Locale }) {
  const resolution = requireCinematicPreviewResolution();
  return <StorefrontScreen
    tenant={resolution.view.tenant} campaign={resolution.view.modules.campaign}
    locale={locale} slug={CINEMATIC_PREVIEW_SLUG} preset={resolution.preset} motion={resolution.view.motion}
  />;
}
