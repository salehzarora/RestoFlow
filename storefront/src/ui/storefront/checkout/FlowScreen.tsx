/**
 * The server half of a Phase D route.
 *
 * It resolves the theme and opens the ThemeScope, then hands the client
 * runtime the tenant scalars AND the menu data the route resolved (items,
 * groups, zones, tax rate, cart key). STOREFRONT-READ-001 moved the menu from
 * a client-side fixture import into these props: a live tenant's menu exists
 * only in the document the server rendered for it, so it travels in the RSC
 * payload by design (packet §7.1 - the per-document cost is measured and
 * reported by the output lane, never folded into the static ceiling).
 *
 * A server component, so none of this file reaches the browser.
 */
import { dirOf, type Locale } from '@/i18n/locales';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import type { MotionMode, ServiceState, StorefrontResolution } from '@/source/types';
import { ThemeScope } from '../ThemeScope';
import shell from '../storefront.module.css';
import type { FlowScreenName } from './FlowRuntime';
import { FlowEntry } from './FlowEntry';
import { orderMessages } from '@/i18n/orders';

export function FlowScreen({
  resolution,
  locale,
  slug,
  screen,
}: {
  resolution: StorefrontResolution;
  locale: Locale;
  slug: string;
  screen: FlowScreenName;
}) {
  const { tenant } = resolution.view;
  const preset: Preset = resolution.preset;
  const motion: MotionMode = resolution.view.motion;
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });
  const state: ServiceState = tenant.service.state;

  return (
    <ThemeScope
      tokens={tokens}
      className={`${shell.root}`}
      dir={dirOf(locale)}
    >
      <FlowEntry
        source={resolution.source}
        orderCopy={resolution.source === 'live' ? orderMessages(locale) : undefined}
        locale={locale}
        slug={slug}
        screen={screen}
        state={state}
        motion={motion}
        items={resolution.view.items}
        groups={resolution.groups}
        zones={resolution.zones}
        taxRateBp={resolution.taxRateBp}
        menuVersion={resolution.menuVersion}
        orderEndpointOrigin={resolution.orderEndpointOrigin}
        tenant={{
          logo: tenant.brand.logo,
          name: tenant.displayName,
          city: tenant.city,
          address: tenant.address,
          publicPhone: tenant.phone,
          opensAt: tenant.hours.opens,
          pickupEnabled: tenant.service.pickupEnabled,
          deliveryEnabled: tenant.service.deliveryEnabled,
          orderingEnabled: tenant.service.orderingEnabled,
        }}
      />
    </ThemeScope>
  );
}
