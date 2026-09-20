/**
 * Composition root for one tenant's storefront.
 *
 * Order matters: raw tenant input is SANITISED, then the theme is DERIVED from
 * the sanitised values, then the derived tokens are handed to ThemeScope which
 * applies them via CSSOM. No component below this point ever sees a raw tenant
 * colour, and none of them contains a resolved colour of their own.
 */
import { rubik } from '@/fonts/rubik';
import { dirOf, type Locale } from '@/i18n/locales';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import type { Tenant } from '@/source/types';
import { Intro } from './Intro';
import { ThemeScope } from './ThemeScope';
import shell from './storefront.module.css';

export function StorefrontScreen({
  tenant,
  locale,
  preset = 'dark',
}: {
  tenant: Tenant;
  locale: Locale;
  preset?: Preset;
}) {
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });

  return (
    <ThemeScope tokens={tokens} className={`${shell.root} ${rubik.variable}`} dir={dirOf(locale)}>
      <Intro tenant={tenant} locale={locale} />
    </ThemeScope>
  );
}
