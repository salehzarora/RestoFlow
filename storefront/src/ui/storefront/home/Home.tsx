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
import { rubik } from '@/fonts/rubik';
import { buildTheme, type Preset } from '@/theme/buildTheme';
import { sanitizeAccent, sanitizePrimary } from '@/theme/sanitize';
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
import { CartAside, CartDock } from './CartParts';
import { HomeChrome } from './HomeChrome';
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
  const { tenant, modules, categories, items, cardMode, cart } = view;
  const tokens = buildTheme(preset, {
    primary: sanitizePrimary(tenant.brand.primary),
    accent: sanitizeAccent(tenant.brand.accent, preset),
  });
  const empty = items.length === 0;
  const firstCategoryId = categories[0] === undefined ? '' : `sf-cat-${categories[0].id}`;

  // The hero's own header row: menu button on the start side, the brand lockup
  // centred, search + language on the end side. Fixed 84px side groups keep the
  // lockup optically centred whatever the name's length.
  const heroHeader = (
    <div className={styles.heroRow}>
      <div className={styles.heroSide}>
        <a className={styles.iconBtn} href={`#${firstCategoryId}`} aria-label={m.menuLabel}>
          <MenuIcon />
        </a>
      </div>
      <BrandLockup tenant={tenant} />
      <div className={`${styles.heroSide} ${styles.heroSideEnd}`}>
        <button className={styles.iconBtn} type="button" aria-label={m.search} disabled>
          <SearchIcon />
        </button>
        <LanguageMenu locale={locale} hrefFor={hrefFor} variant="circle" />
      </div>
    </div>
  );

  return (
    <ThemeScope
      tokens={tokens}
      className={`${shell.root} ${rubik.variable} ${MOTION_CLASS[view.motion]}`}
      dir={dirOf(locale)}
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
            m={m}
            categories={categories}
            announcement={
              // The announcement is auto-suppressed while closed or paused.
              modules.announcement === null || tenant.service.state !== 'open'
                ? null
                : modules.announcement.text
            }
            searchLabel={m.search}
            hero={
              <CampaignHero
                tenant={tenant}
                m={m}
                title={modules.campaign.title}
                subline={modules.campaign.subline}
                showMotif={view.motion !== 'calm'}
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

          <CartDock cart={cart} m={m} state={tenant.service.state} opensAt={tenant.hours.opens} />
        </main>

        <CartAside cart={cart} m={m} state={tenant.service.state} opensAt={tenant.hours.opens} />
      </div>
      <span className={styles.srOnly} data-slug={slug} />
    </ThemeScope>
  );
}
