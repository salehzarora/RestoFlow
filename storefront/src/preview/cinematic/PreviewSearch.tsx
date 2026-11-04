import type { Locale } from '@/i18n/locales';
import { Search } from '@/ui/storefront/search/Search';
import { CINEMATIC_PREVIEW_SLUG } from './access';
import { requireCinematicPreviewResolution } from './pageResolution';

export function CinematicPreviewSearch({ locale }: { locale: Locale }) {
  const resolution = requireCinematicPreviewResolution();
  return <Search resolution={resolution} locale={locale} slug={CINEMATIC_PREVIEW_SLUG} />;
}
