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
 * at phone width.
 *
 * THE WIDE SEAM. At container >= 900px search carries the same persistent cart
 * aside the menu does - the approved inventory lists `PersistentCartAside` for
 * this screen and the prototype's own rule is `showAside = home || search`. It
 * is the SAME component, in the SAME layout, and it is equally NON-FUNCTIONAL:
 * it takes no cart prop, so it cannot show lines, a count, a subtotal, tax or a
 * total, and its checkout CTA is disabled because that route is Phase D.
 *
 * Below 900 the container query hides it, exactly as on the menu. It stays in
 * the document at every width because this is a STATIC export - the same bytes
 * are served to every visitor, so the layout branch cannot be chosen per device
 * on the server, and choosing it in JavaScript would make a layout depend on
 * hydration.
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
import { CartAside } from '../home/CartParts';
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
        {/*
          The SAME wide layout as the menu: `.shell` is the container the 900px
          query measures, so this works inside an embedded preview and not only
          against the viewport.
        */}
        <div className={home.shell}>
          <SearchScreen
            items={items}
            categories={categories}
            m={m}
            menuHref={menuPath(locale, slug)}
          />
          <CartAside m={m} state={tenant.service.state} opensAt={tenant.hours.opens} />
        </div>
      </StorefrontRuntime>
      <span className={home.srOnly} data-slug={slug} />
    </ThemeScope>
  );
}
