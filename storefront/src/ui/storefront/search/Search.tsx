/**
 * Composition root for the search route.
 *
 * A server component, mirroring StorefrontScreen: raw tenant input is
 * sanitised, the theme is derived from the sanitised values, and only the
 * derived tokens reach ThemeScope. The screen itself is a client component
 * because the query is component state - which is what the execution packet
 * decides and what the prototype does; no query-URL behaviour is designed.
 *
 * `StorefrontRuntime` is mounted here WITHOUT a dock slot: search opens the
 * SAME product sheet as the menu (DESIGN_HANDOFF.md:90) but shows no cart dock
 * and no wide seam.
 */
import { rubik } from '@/fonts/rubik';
import { dirOf, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { menuPath } from '@/routes/routes';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import { MENU_VERSION } from '@/source/menu-fixture';
import type { HomeView } from '@/source/types';
import { StorefrontRuntime } from '../StorefrontRuntime';
import { ThemeScope } from '../ThemeScope';
import shell from '../storefront.module.css';
import home from '../home/home.module.css';
import { SearchScreen } from './SearchScreen';

export function Search({
  view,
  locale,
  slug,
  preset = 'dark',
}: {
  view: HomeView;
  locale: Locale;
  slug: string;
  preset?: Preset;
}) {
  const m = storefrontMessages(locale);
  const { tenant, categories, items } = view;
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });

  return (
    <ThemeScope
      tokens={tokens}
      className={`${shell.root} ${rubik.variable}`}
      dir={dirOf(locale)}
    >
      {/* No dock slot here: the approved dock condition is menu-only
          (prototype Storefront.dc.html:865 `showCartBar: isMenu && ...`), and
          neither canonical search screenshot shows one. */}
      <StorefrontRuntime
        slug={slug}
        menuVersion={MENU_VERSION}
        items={items}
        m={m}
        motion={view.motion}
        state={tenant.service.state}
        opensAt={tenant.hours.opens}
      >
        <SearchScreen
          items={items}
          categories={categories}
          m={m}
          menuHref={menuPath(locale, slug)}
        />
      </StorefrontRuntime>
      <span className={home.srOnly} data-slug={slug} />
    </ThemeScope>
  );
}
