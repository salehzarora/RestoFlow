import type { Locale } from '@/i18n/locales';
import { menuPath } from '@/routes/routes';
import { Home } from '@/ui/storefront/home/Home';
import { CINEMATIC_PREVIEW_SLUG } from './access';
import { requireCinematicPreviewResolution } from './pageResolution';

export function CinematicPreviewMenu({ locale }: { locale: Locale }) {
  const resolution = requireCinematicPreviewResolution();
  const slug = CINEMATIC_PREVIEW_SLUG;
  return <Home resolution={resolution} locale={locale} slug={slug} hrefFor={target => menuPath(target, slug)} />;
}
