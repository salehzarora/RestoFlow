/**
 * ROUTE STUB ONLY — the minimum target the Intro CTA needs in order to be a
 * working control rather than a dead link. Phase B replaces this file with the
 * real home/menu module list.
 *
 * It deliberately renders NO invented product copy and reuses no design string
 * that would assert something untrue (the tenant has not "published nothing" —
 * this phase simply has not built the menu yet). It shows the themed shell, the
 * tenant name, and the way back.
 */
import Link from 'next/link';
import { rubik } from '@/fonts/rubik';
import { dirOf, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { buildTheme } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import { storefrontPath } from '@/routes/routes';
import type { Tenant } from '@/source/types';
import { ThemeScope } from './ThemeScope';
import shell from './storefront.module.css';
import styles from './MenuStub.module.css';

export function MenuStub({ tenant, locale }: { tenant: Tenant; locale: Locale }) {
  const m = storefrontMessages(locale);
  const tokens = buildTheme('dark', {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, 'dark'),
  });

  return (
    <ThemeScope tokens={tokens} className={`${shell.root} ${rubik.variable}`} dir={dirOf(locale)}>
      <main className={styles.screen}>
        <h1 className={styles.name} dir="auto">
          {tenant.displayName}
        </h1>
        <Link className={styles.back} href={storefrontPath(locale, tenant.slug)} prefetch={false}>
          {m.back}
        </Link>
      </main>
    </ThemeScope>
  );
}
