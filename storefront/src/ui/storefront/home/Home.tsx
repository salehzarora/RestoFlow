/** Approved design, composed over the existing tenant and order runtime. */
import { dirOf, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { buildCinematicTheme } from '@/theme/buildCinematicTheme';
import { MenuBackdrop } from './MenuBackdrop';
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

const MOTION_CLASS = { calm: '', full: styles.motionFull, lively: `${styles.motionFull} ${styles.motionLively}` } as const;

export function Home({ resolution, locale, slug, hrefFor }: {
  resolution: StorefrontResolution; locale: Locale; slug: string; hrefFor: (target: Locale) => string;
}) {
  const { view, groups, zones, taxRateBp, menuVersion } = resolution;
  const { tenant, modules, categories, items, cardMode } = view;
  const m = storefrontMessages(locale);
  const tokens = buildCinematicTheme(tenant.brand, tenant.scenePreset);
  const background = menuBackground(tenant, tenant.scenePreset);
  return (
    <ThemeScope tokens={tokens} menuImageDim={background.dim} scenePreset={tenant.scenePreset} className={`${shell.root} ${MOTION_CLASS[view.motion]}`} dir={dirOf(locale)}>
      <StorefrontRuntime source={resolution.source} slug={slug} menuVersion={menuVersion} items={items} groups={groups} zones={zones} taxRateBp={taxRateBp} orderingEnabled={tenant.service.orderingEnabled} locale={locale} motion={view.motion} state={tenant.service.state} opensAt={tenant.hours.opens}>
        <main className={styles.page} data-sf-screen="home">
          <MenuBackdrop background={background} />
          <HomeChrome key={slug} tenant={tenant} locale={locale} slug={slug} language={<LanguageMenu locale={locale} hrefFor={hrefFor} />} categories={categories} items={items} cardMode={cardMode}
            announcement={modules.announcement === null || tenant.service.state !== 'open' ? null : modules.announcement.text}
            announcementSegments={modules.announcement?.segments}
            heroTitle={modules.campaign.title} heroSubline={modules.campaign.subline} heroContent={modules.campaign.hero}
            notice={tenant.service.orderingEnabled && tenant.service.state === 'open' ? null : <div className={styles.notices}>{tenant.service.state === 'open' ? null : <StateNotice state={tenant.service.state} tenant={tenant} m={m} />}{tenant.service.state === 'open' && !tenant.service.orderingEnabled ? <OrderingOffNotice m={m} /> : null}</div>}
            empty={items.length === 0 ? <EmptyMenu tenant={tenant} m={m} /> : null}
            cart={<AsideSlot locale={locale} state={tenant.service.state} opensAt={tenant.hours.opens} checkoutHref={checkoutPath(locale, slug)} />}
          />
          {items.length === 0 || modules.promo === null ? null : <PromoBanner promo={modules.promo} m={m} />}
          {items.length === 0 || modules.story === null ? null : <StoryCard story={modules.story} />}
          <SiteFooter tenant={tenant} m={m} sceneImage={background.image} />
          <DockSlot locale={locale} motion={view.motion} state={tenant.service.state} opensAt={tenant.hours.opens} cartHref={cartPath(locale, slug)} />
        </main>
      </StorefrontRuntime>
      <span className={styles.srOnly} data-slug={slug} />
    </ThemeScope>
  );
}
