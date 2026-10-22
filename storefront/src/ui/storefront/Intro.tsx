/** Derived welcome composition using the approved Home presentation family.
 * IntroGate, route/session decisions and every existing navigation URL stay
 * outside this server component. This is not an Intro reference-parity claim. */
import { type Locale } from '@/i18n/locales';
import { fill, storefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import { searchPath, storefrontPath } from '@/routes/routes';
import type { MotionMode, Tenant } from '@/source/types';
import { LanguageMenu } from './LanguageMenu';
import { BrandLockup, CampaignHero } from './home/HomeParts';
import { hoursLabel } from './home/hoursCopy';
import { DeliveryIcon, SearchIcon, StoreIcon } from './icons';
import styles from './home/home.module.css';

const MOTION_CLASS = {
  calm: '', full: styles.motionFull,
  lively: `${styles.motionFull} ${styles.motionLively}`,
} as const;

export function Intro({ tenant, locale, motion = 'full' }: {
  tenant: Tenant; locale: Locale; motion?: MotionMode;
}) {
  const m = storefrontMessages(locale);
  const { service } = tenant;
  const menuHref = `${storefrontPath(locale, tenant.slug)}/menu`;
  const stateLabel = service.state === 'open' ? m.openNow : service.state === 'closed' ? m.closed : m.paused;
  const stateTone = service.state === 'open' ? styles.stateOpen : service.state === 'closed' ? styles.stateClosed : styles.statePaused;
  return <main className={`${styles.page} ${MOTION_CLASS[motion]}`} data-sf-screen="intro">
    <header className={styles.header}>
      <div className={`${styles.inner} ${styles.headerInner}`}>
        <BrandLockup tenant={tenant} />
        <div className={styles.headerActions}>
          <LanguageMenu locale={locale} hrefFor={target => storefrontPath(target, tenant.slug)} />
          <a className={styles.promoCta} href={searchPath(locale, tenant.slug)} aria-label={m.search}><SearchIcon /></a>
        </div>
      </div>
    </header>
    <CampaignHero tenant={tenant} m={m} eyebrow={m.welcome} title={tenant.displayName} subline={tenant.tagline} ctaHref={menuHref} ctaLabel={m.explore} />
    <div className={styles.serviceWrap} data-sf-intro-service="">
      <div className={styles.service}>
        <div className={`${styles.serviceCell} ${stateTone}`}><span className={styles.stateDot} aria-hidden="true" /><span>{stateLabel}</span></div>
        <div className={`${styles.serviceCell} ${service.pickupEnabled ? '' : styles.serviceOff}`} data-sf-intro-pickup="">
          <span className={styles.serviceIcon} aria-hidden="true"><StoreIcon /></span>
          <span className={styles.serviceLabel}>{service.pickupEnabled ? m.pickup : m.pickupOff}</span>
        </div>
        <div className={`${styles.serviceCell} ${service.deliveryEnabled ? '' : styles.serviceOff}`} data-sf-intro-delivery="">
          <span className={styles.serviceIcon} aria-hidden="true"><DeliveryIcon /></span>
          {service.deliveryEnabled ? <><span className={styles.serviceLabel}>{m.delivery}</span><span aria-hidden="true">·</span><span className={styles.ltr} dir="ltr">{fill(m.fromFee, { f: formatMoney(service.deliveryFromMinor) })}</span></> : <span className={styles.serviceLabel}>{m.deliveryOff}</span>}
        </div>
      </div>
    </div>
    <div className={`${styles.inner} ${styles.footerInner}`}>
      <p className={styles.footerCredit}>{m.poweredBy} <span className={styles.footerBrand}>BIZBOT</span><span className={styles.srOnly}> · {hoursLabel(tenant, m).text}</span></p>
    </div>
  </main>;
}
