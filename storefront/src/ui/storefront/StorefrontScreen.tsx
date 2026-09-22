/**
 * Composition root for one tenant's storefront.
 *
 * Order matters: raw tenant input is SANITISED, then the theme is DERIVED from
 * the sanitised values, then the derived tokens are handed to ThemeScope which
 * applies them via CSSOM. No component below this point ever sees a raw tenant
 * colour, and none of them contains a resolved colour of their own.
 */
import { dirOf, type Locale } from '@/i18n/locales';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import type { MotionMode, Tenant } from '@/source/types';
import { storefrontPath } from '@/routes/routes';
import { Intro } from './Intro';
import { IntroGate } from './IntroGate';
import { ThemeScope } from './ThemeScope';
import shell from './storefront.module.css';

export function StorefrontScreen({
  tenant,
  locale,
  slug,
  preset = 'dark',
  motion = 'full',
}: {
  tenant: Tenant;
  locale: Locale;
  /** The ROUTE slug. The menu route writes the session flag with the route slug
      (a scenario slug resolves to the canonical tenant, so tenant.slug is NOT
      the same string there); the intro route must READ it with the same one. */
  slug: string;
  preset?: Preset;
  motion?: MotionMode;
}) {
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });

  return (
    <ThemeScope tokens={tokens} className={`${shell.root}`} dir={dirOf(locale)}>
      <IntroGate slug={slug} homeHref={`${storefrontPath(locale, slug)}/menu`}>
        <Intro tenant={tenant} locale={locale} motion={motion} />
      </IntroGate>
    </ThemeScope>
  );
}
