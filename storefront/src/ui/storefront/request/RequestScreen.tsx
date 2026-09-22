/**
 * The server half of the `/r/[ref]` route.
 *
 * Resolves the theme for the tenant the ref belongs to, opens the ThemeScope,
 * and hands the client runtime A HANDFUL OF SCALARS: locale, ref, slug, the
 * display code, the content language, the restaurant's name and logo path,
 * the motion mode. Not the menu, not a dictionary, not a request - every one
 * of those would be serialised into this document's RSC payload (the Phase D
 * lesson: 424,033 bytes for sixteen documents), and a request in a static
 * document would be a request nobody owns.
 *
 * A server component, so none of this file reaches the browser.
 */
import { dirOf, type Locale } from '@/i18n/locales';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import type { MotionMode, Tenant } from '@/source/types';
import { ThemeScope } from '../ThemeScope';
import shell from '../storefront.module.css';
import { RequestRuntime } from './RequestRuntime';
import type { ContentLocale } from './message';

export function RequestScreen({
  tenant,
  locale,
  requestRef,
  slug,
  contentLocale,
  preset = 'dark',
  motion = 'full',
  fontClass,
}: {
  tenant: Tenant;
  locale: Locale;
  requestRef: string;
  slug: string;
  contentLocale: ContentLocale;
  preset?: Preset;
  motion?: MotionMode;
  /** The root's font set class (two preloads, one on demand); the page binds it. */
  fontClass: string;
}) {
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });

  return (
    <ThemeScope tokens={tokens} className={`${shell.root} ${fontClass}`} dir={dirOf(locale)}>
      <RequestRuntime
        locale={locale}
        requestRef={requestRef}
        slug={slug}
        contentLocale={contentLocale}
        tenant={{ name: tenant.displayName, logo: tenant.brand.logo }}
        motion={motion}
      />
    </ThemeScope>
  );
}
