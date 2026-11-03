import type { Locale } from '@/i18n/locales';
import { FlowScreen } from '@/ui/storefront/checkout/FlowScreen';
import { CINEMATIC_PREVIEW_SLUG } from './access';
import { requireCinematicPreviewResolution } from './pageResolution';

export function CinematicPreviewCart({ locale }: { locale: Locale }) {
  const resolution = requireCinematicPreviewResolution();
  return <FlowScreen resolution={resolution} locale={locale} slug={CINEMATIC_PREVIEW_SLUG} screen="cart" />;
}
