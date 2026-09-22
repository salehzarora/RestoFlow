/**
 * The server half of a Phase D route.
 *
 * It resolves the theme and opens the ThemeScope, then hands the client
 * runtime a HANDFUL OF SCALARS. It deliberately does NOT pass the menu, the
 * categories or the dictionaries: every one of those would be serialised into
 * this document's RSC payload, and with sixteen Phase D documents that is the
 * difference between 424,033 bytes and 11,702. The client imports them
 * directly instead, into one shared chunk.
 *
 * A server component, so none of this file reaches the browser.
 */
import { rubik } from '@/fonts/rubik';
import { dirOf, type Locale } from '@/i18n/locales';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import type { MotionMode, ServiceState, Tenant } from '@/source/types';
import { ThemeScope } from '../ThemeScope';
import shell from '../storefront.module.css';
import { FlowRuntime, type FlowScreenName } from './FlowRuntime';

export function FlowScreen({
  tenant,
  locale,
  slug,
  screen,
  preset = 'dark',
  motion,
}: {
  tenant: Tenant;
  locale: Locale;
  slug: string;
  screen: FlowScreenName;
  preset?: Preset;
  motion: MotionMode;
}) {
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });
  const state: ServiceState = tenant.service.state;

  return (
    <ThemeScope
      tokens={tokens}
      className={`${shell.root} ${rubik.variable}`}
      dir={dirOf(locale)}
    >
      <FlowRuntime
        locale={locale}
        slug={slug}
        screen={screen}
        state={state}
        motion={motion}
        tenant={{
          name: tenant.displayName,
          city: tenant.city,
          address: tenant.address,
          opensAt: tenant.hours.opens,
          pickupEnabled: tenant.service.pickupEnabled,
          deliveryEnabled: tenant.service.deliveryEnabled,
        }}
      />
    </ThemeScope>
  );
}
