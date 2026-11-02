/** Welcome composition; tenant colours are validated by the cinematic theme. */
import { dirOf, type Locale } from '@/i18n/locales';
import type { Preset } from '@/theme/buildTheme';
import { buildCinematicTheme } from '@/theme/buildCinematicTheme';
import type { CampaignModule, MotionMode, Tenant } from '@/source/types';
import { storefrontPath } from '@/routes/routes';
import { Intro } from './Intro';
import { IntroGate } from './IntroGate';
import { ThemeScope } from './ThemeScope';
import shell from './storefront.module.css';

export function StorefrontScreen({
  tenant,
  locale,
  slug,
  campaign,
  motion = 'full',
}: {
  tenant: Tenant;
  locale: Locale;
  /** The ROUTE slug. The menu route writes the session flag with the route slug
      (a scenario slug resolves to the canonical tenant, so tenant.slug is NOT
      the same string there); the intro route must READ it with the same one. */
  slug: string;
  preset?: Preset;
  campaign?: CampaignModule;
  motion?: MotionMode;
}) {
  const tokens = buildCinematicTheme(tenant.brand);

  return (
    <ThemeScope tokens={tokens} className={`${shell.root}`} dir={dirOf(locale)}>
      <IntroGate slug={slug} homeHref={`${storefrontPath(locale, slug)}/menu`}>
        <Intro tenant={tenant} locale={locale} campaign={campaign} motion={motion} />
      </IntroGate>
    </ThemeScope>
  );
}
