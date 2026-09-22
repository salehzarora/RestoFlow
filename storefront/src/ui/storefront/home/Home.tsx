/**
 * Home / menu — screen 2 of the approved handoff.
 *
 * THE MODULE ORDER IS FIXED in UI-001 and is expressed here, once, in source
 * order: announce -> hero -> service -> categories -> promo -> popular ->
 * sections -> story -> footer. Visibility is a per-restaurant toggle; ordering
 * is not data and there is no dashboard reorder in this release.
 *
 * A server component. The only client JavaScript is `HomeChrome`, which owns
 * the compact header, the scroll-spy and the announcement dismissal.
 */
import { dirOf, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
import { cartPath, checkoutPath, searchPath } from '@/routes/routes';
import { MENU_VERSION } from '@/source/menu-fixture';
import type { HomeView } from '@/source/types';
import { LanguageMenu } from '../LanguageMenu';
import { ThemeScope } from '../ThemeScope';
import { MenuIcon, SearchIcon } from '../icons';
import shell from '../storefront.module.css';
import {
  BrandLockup,
  CampaignHero,
  EmptyMenu,
  PromoBanner,
  ServiceStatusStrip,
  SiteFooter,
  StateNotice,
  StoryCard,
} from './HomeParts';
import { MenuSection, PopularSection } from './MenuParts';
import { AsideSlot, DockSlot } from '../cart/CartRuntime';
import { HomeChrome } from './HomeChrome';
import { StorefrontRuntime } from '../StorefrontRuntime';
import styles from './home.module.css';

const MOTION_CLASS = {
  calm: '',
  full: styles.motionFull,
  lively: `${styles.motionFull} ${styles.motionLively}`,
} as const;

export function Home({
  view,
  locale,
  slug,
  preset = 'dark',
  hrefFor,
}: {
  view: HomeView;
  locale: Locale;
  slug: string;
  preset?: Preset;
  hrefFor: (target: Locale) => string;
}) {
  const m = storefrontMessages(locale);
  // `view.cart` is DELIBERATELY not destructured: the fixture cart is test and
  // evidence data only, and nothing on this screen may render it.
  const { tenant, modules, categories, items, cardMode } = view;
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });
  const empty = items.length === 0;
  const searchHref = searchPath(locale, slug);
  const cartHref = cartPath(locale, slug);
  const checkoutHref = checkoutPath(locale, slug);
  const firstCategoryId = categories[0] === undefined ? '' : `sf-cat-${categories[0].id}`;

  // The hero's own header row: menu button on the start side, the brand lockup
  // centred, search + language on the end side. Fixed 84px side groups keep the
  // lockup optically centred whatever the name's length.
  const heroHeader = (
    <div className={styles.heroRow}>
      <div className={styles.heroSide}>
        {/* With no menu section there is nothing to jump to. The control stays
            in the approved three-column row (COMPONENT_INVENTORY.md:22) but is
            inert rather than an anchor to "#", the same honesty the search
            button and the promo CTA already use. The prototype's own menu
            button does nothing under emptyMenu (Storefront.dc.html:119 + :716). */}
        {firstCategoryId === '' ? (
          <button className={styles.iconBtn} type="button" aria-label={m.menuLabel} disabled>
            <MenuIcon />
          </button>
        ) : (
          <a className={styles.iconBtn} href={`#${firstCategoryId}`} aria-label={m.menuLabel}>
            <MenuIcon />
          </a>
        )}
      </div>
      <BrandLockup tenant={tenant} />
      <div className={`${styles.heroSide} ${styles.heroSideEnd}`}>
        <a className={styles.iconBtn} href={searchHref} aria-label={m.search}>
          <SearchIcon />
        </a>
        <LanguageMenu locale={locale} hrefFor={hrefFor} variant="circle" />
      </div>
    </div>
  );

  return (
    <ThemeScope
      tokens={tokens}
      className={`${shell.root} ${MOTION_CLASS[view.motion]}`}
      dir={dirOf(locale)}
    >
      {/*
        The cart scope wraps the WHOLE shell so the dock slot can stay inside
        <main> and keep its sticky positioning.

        THE STATIC DOCUMENT CARRIES NO CART. Every route here is a static
        document: the bytes are identical for every visitor, so any cart in them
        is a cart nobody owns. A first visit has an EMPTY cart, and an empty
        cart renders no dock at all - so the prerendered document contains no
        dock, no count, no line and no money. Only a validated cart read from
        this visitor's own storage, after hydration, can put one there.
      */}
      <StorefrontRuntime
        slug={slug}
        menuVersion={MENU_VERSION}
        items={items}
        locale={locale}
        motion={view.motion}
        state={tenant.service.state}
        opensAt={tenant.hours.opens}
      >
        <div className={styles.shell}>
          <main className={styles.page}>
            {/*
              FIXED ORDER. HomeChrome renders, in this order: the announcement,
              the compact header, the hero, the service strip, the closed/paused
              notice and the category rail.
            */}
            <HomeChrome
              tenant={tenant}
              locale={locale}
              categories={categories}
              slug={slug}
              announcement={
                // The announcement is auto-suppressed while closed or paused.
                modules.announcement === null || tenant.service.state !== 'open'
                  ? null
                  : modules.announcement.text
              }
              searchLabel={m.search}
              searchHref={searchHref}
              hero={
                <CampaignHero
                  tenant={tenant}
                  m={m}
                  title={modules.campaign.title}
                  subline={modules.campaign.subline}
                >
                  {heroHeader}
                </CampaignHero>
              }
              service={<ServiceStatusStrip tenant={tenant} m={m} />}
              notice={
                tenant.service.state === 'open' ? null : (
                  <StateNotice state={tenant.service.state} tenant={tenant} m={m} />
                )
              }
            />

            {empty ? (
              <EmptyMenu tenant={tenant} m={m} />
            ) : (
              <>
                {modules.promo === null ? null : <PromoBanner promo={modules.promo} m={m} />}

                {modules.popular.enabled ? (
                  <PopularSection
                    items={items}
                    m={m}
                    ready={modules.popular.ready}
                    menuId={firstCategoryId}
                  />
                ) : null}

                {categories.map((category) => (
                  <MenuSection
                    key={category.id}
                    category={category}
                    items={items.filter((item) => item.categoryId === category.id)}
                    cardMode={cardMode}
                    m={m}
                  />
                ))}

                {modules.story === null ? null : <StoryCard story={modules.story} />}
              </>
            )}

            <SiteFooter tenant={tenant} m={m} />

            {/* Renders NOTHING until this visitor's own cart has been read,
                so the static document and the first client render agree and
                neither contains a cart. */}
            <DockSlot
              locale={locale}
              motion={view.motion}
              state={tenant.service.state}
              opensAt={tenant.hours.opens}
              cartHref={cartHref}
            />
          </main>

          {/*
            THE WIDE CART, FUNCTIONAL FROM PHASE D.
            Its FRAME is prerendered so 360px of layout does not appear after
            hydration, but it carries no lines, no count, no subtotal, no tax
            and no total until this visitor's own cart has been read - so the
            static document still contains no cart at all. At wide there is no
            dock, and this CTA goes straight to checkout.
          */}
          <AsideSlot
            locale={locale}
            state={tenant.service.state}
            opensAt={tenant.hours.opens}
            checkoutHref={checkoutHref}
          />
        </div>
      </StorefrontRuntime>
      <span className={styles.srOnly} data-slug={slug} />
    </ThemeScope>
  );
}
