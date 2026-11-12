/** Approved design, composed over the existing tenant and order runtime. */
import { dirOf, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { buildSiteTheme, siteThemeClass } from '@/theme/buildSiteTheme';
import { MenuBackdrop } from './MenuBackdrop';
import { buildMenuBrand } from '@/theme/buildMenuBrand';
import { menuBackground } from './menuBackground';
import { cartPath, checkoutPath } from '@/routes/routes';
import type { StorefrontResolution } from '@/source/types';
import { ThemeScope } from '../ThemeScope';
import { LanguageMenu } from '../LanguageMenu';
import { EmptyMenu, OrderingOffNotice, PromoBanner, SiteFooter, StateNotice, StoryCard } from './HomeParts';
import { AsideSlot, DockSlot } from '../cart/CartRuntime';
import { HomeChrome } from './HomeChrome';
import { StorefrontRuntime } from '../StorefrontRuntime';
import shell from '../storefront.module.css';
import styles from './home.module.css';
import appearance from '../siteAppearance.module.css';

const MOTION_CLASS = { calm: '', full: styles.motionFull, lively: `${styles.motionFull} ${styles.motionLively}` } as const;

export function Home({ resolution, locale, slug, hrefFor }: {
  resolution: StorefrontResolution; locale: Locale; slug: string; hrefFor: (target: Locale) => string;
}) {
  const { view, groups, zones, taxRateBp, menuVersion } = resolution;
  const { tenant, modules, categories, items, cardMode } = view;
  const m = storefrontMessages(locale);
  const tokens = buildMenuBrand(tenant, buildSiteTheme(tenant));
  const background = menuBackground(tenant, tenant.scenePreset);
  return (
    <ThemeScope tokens={tokens} menuImageDim={background.dim} scenePreset={tenant.scenePreset} className={`${shell.root} ${appearance[siteThemeClass(tenant.siteTheme)]} ${MOTION_CLASS[view.motion]}`} dir={dirOf(locale)}>
      <StorefrontRuntime m={m} source={resolution.source} slug={slug} menuVersion={menuVersion} items={items} groups={groups} zones={zones} taxRateBp={taxRateBp} orderingEnabled={tenant.service.orderingEnabled} locale={locale} motion={view.motion} state={tenant.service.state} opensAt={tenant.hours.opens}>
        <main className={styles.page} data-sf-screen="home">
          {tenant.siteTheme === 'light' ? null : <MenuBackdrop background={background} sectionCount={categories.length} itemCount={items.length} />}
          <HomeChrome key={slug} m={m} tenant={tenant} locale={locale} slug={slug} language={<LanguageMenu locale={locale} hrefFor={hrefFor} />} categories={categories} items={items} cardMode={cardMode}
            announcement={modules.announcement === null || tenant.service.state !== 'open' ? null : modules.announcement.text}
            announcementSegments={modules.announcement?.segments}
            heroTitle={modules.campaign.title} heroSubline={modules.campaign.subline} heroContent={modules.campaign.hero}
            notice={tenant.service.orderingEnabled && tenant.service.state === 'open' ? null : <div className={styles.notices}>{tenant.service.state === 'open' ? null : <StateNotice state={tenant.service.state} tenant={tenant} m={m} />}{tenant.service.state === 'open' && !tenant.service.orderingEnabled ? <OrderingOffNotice m={m} /> : null}</div>}
            empty={items.length === 0 ? <EmptyMenu tenant={tenant} m={m} /> : null}
            cart={<AsideSlot m={m} state={tenant.service.state} opensAt={tenant.hours.opens} checkoutHref={checkoutPath(locale, slug)} />}
          />
          {items.length === 0 || modules.promo === null ? null : <PromoBanner promo={modules.promo} m={m} />}
          {items.length === 0 || modules.story === null ? null : <StoryCard story={modules.story} />}
          <SiteFooter tenant={tenant} m={m} sceneImage={tenant.siteTheme === 'light' ? null : background.image} />
          <DockSlot m={m} motion={view.motion} state={tenant.service.state} opensAt={tenant.hours.opens} cartHref={cartPath(locale, slug)} />
        </main>
      </StorefrontRuntime>
      <span className={styles.srOnly} data-slug={slug} />
    </ThemeScope>
  );
}
