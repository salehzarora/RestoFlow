import type { Locale } from '@/i18n/locales';
import { menuPath } from '@/routes/routes';
import { Home } from '@/ui/storefront/home/Home';
import { CINEMATIC_PREVIEW_SLUG, cinematicPreviewScene } from './access';
import { requireCinematicPreviewResolution } from './pageResolution';

export async function CinematicPreviewMenu({ locale, searchParams }: {
  locale: Locale; searchParams?: Promise<{ scene?: string | string[] }>;
}) {
  const scene = cinematicPreviewScene((await searchParams)?.scene);
  const resolution = requireCinematicPreviewResolution(scene);
  const slug = CINEMATIC_PREVIEW_SLUG;
  return <Home resolution={resolution} locale={locale} slug={slug} hrefFor={target => `${menuPath(target, slug)}?scene=${scene}`} />;
}
