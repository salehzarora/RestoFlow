/**
 * Home modules that render from data alone — no interactivity of their own.
 * All are SERVER components; only the chrome that needs scroll is a client one.
 */
import { type Locale } from '@/i18n/locales';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { PromoModule, ServiceState, StoryModule, Tenant } from '@/source/types';
import { AlertIcon, ChevronIcon, ClockIcon, DeliveryIcon, MapMotif, StoreIcon } from '../icons';
import styles from './home.module.css';

/** Price, always an LTR island with tabular figures even inside RTL copy. */
export function Price({ minor, from }: { minor: number; from?: string }) {
  return (
    <span className={styles.price}>
      {from === undefined ? null : <span className={styles.priceFrom}>{from}</span>}
      <span className={styles.ltr} dir="ltr">
        {formatMoney(minor)}
      </span>
    </span>
  );
}

export function CampaignHero({
  tenant,
  m,
  title,
  subline,
  showMotif,
  children,
}: {
  tenant: Tenant;
  m: StorefrontMessages;
  title: string;
  subline: string;
  showMotif: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className={styles.hero}>
      <div className={styles.heroMedia}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={styles.heroImg}
          src={tenant.heroImage}
          alt=""
          width={1600}
          height={1067}
          decoding="async"
          fetchPriority="high"
        />
      </div>
      <div className={styles.heroShade} />
      {showMotif ? <div className={styles.heroMotif}>{<MapMotif />}</div> : null}
      {children}
      <div className={styles.heroCopy}>
        <h1 className={styles.heroTitle} dir="auto">
          {title}
        </h1>
        <div className={styles.heroRule} />
        <p className={styles.heroSub} dir="auto">
          {subline}
        </p>
      </div>
      <span className={styles.srOnly}>{fill(m.hours, {})}</span>
    </div>
  );
}

export function BrandLockup({ tenant, small = false }: { tenant: Tenant; small?: boolean }) {
  return (
    <div className={styles.lockup}>
      {tenant.brand.logo === null ? null : (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img
          className={small ? styles.compactLogo : styles.brandLogo}
          src={tenant.brand.logo}
          alt=""
          width={84}
          height={84}
          decoding="async"
        />
      )}
      <span className={styles.lockupText}>
        <span className={styles.brandName} dir="auto">
          {tenant.displayName}
        </span>
        <span className={styles.brandCity} dir="auto">
          {tenant.city}
        </span>
      </span>
    </div>
  );
}

const STATE_CLASS: Readonly<Record<ServiceState, string>> = {
  open: styles.stateOpen,
  closed: styles.stateClosed,
  paused: styles.statePaused,
};

export function ServiceStatusStrip({ tenant, m }: { tenant: Tenant; m: StorefrontMessages }) {
  const { service, hours } = tenant;
  const stateWord =
    service.state === 'open' ? m.openNow : service.state === 'closed' ? m.closed : m.paused;

  // Cell order is delivery -> pickup -> hours, which puts the hours cell at the
  // END of the strip: the left in RTL, exactly as the handoff specifies, and
  // the right in LTR. The strip mirrors with the reading direction like the
  // rest of the row content.
  return (
    <div className={styles.serviceWrap}>
      <div className={styles.service}>
        <div className={`${styles.serviceCell} ${service.deliveryEnabled ? '' : styles.serviceOff}`}>
          <span className={styles.serviceIcon} aria-hidden="true">
            <DeliveryIcon />
          </span>
          <span className={styles.serviceText}>
            <span className={styles.serviceLabel}>{m.delivery}</span>
            <span className={styles.serviceMeta}>
              {service.deliveryEnabled ? (
                <span className={styles.ltr} dir="ltr">
                  {fill(m.fromFee, { f: formatMoney(service.deliveryFromMinor) })}
                </span>
              ) : (
                m.unavailableNow
              )}
            </span>
          </span>
        </div>

        <div className={`${styles.serviceCell} ${service.pickupEnabled ? '' : styles.serviceOff}`}>
          <span className={styles.serviceIcon} aria-hidden="true">
            <StoreIcon />
          </span>
          <span className={styles.serviceText}>
            <span className={styles.serviceLabel}>{m.pickupShort}</span>
            <span className={styles.serviceMeta} dir="auto">
              {service.pickupEnabled ? tenant.city : m.unavailableNow}
            </span>
          </span>
        </div>

        <div className={styles.serviceCell}>
          <span className={styles.serviceText}>
            <span className={`${styles.serviceLabel} ${styles.ltr}`} dir="ltr">
              {hours.opens}–{hours.closes}
            </span>
            <span className={`${styles.serviceMeta} ${STATE_CLASS[service.state]}`}>
              <span className={styles.stateRow}>
                <span className={styles.stateDot} aria-hidden="true" />
                {stateWord}
              </span>
            </span>
          </span>
          <span className={`${styles.serviceIcon} ${styles.serviceClock}`} aria-hidden="true">
            <ClockIcon />
          </span>
        </div>
      </div>
    </div>
  );
}

/** Closed / paused notice, shown under the hero. The menu stays browsable. */
export function StateNotice({
  state,
  tenant,
  m,
}: {
  state: Exclude<ServiceState, 'open'>;
  tenant: Tenant;
  m: StorefrontMessages;
}) {
  const closed = state === 'closed';
  return (
    <div
      className={`${styles.notice} ${closed ? styles.noticeClosed : styles.noticePaused}`}
      role="status"
    >
      <span className={styles.noticeIcon} aria-hidden="true">
        <AlertIcon />
      </span>
      <span>
        <span className={styles.noticeTitle}>{closed ? m.closedTitle : m.pausedTitle}</span>
        <span className={styles.noticeBody} dir="auto">
          {closed
            ? fill(m.closedBody, { t: tenant.hours.opens })
            : fill(m.pausedBody, { r: tenant.displayName })}
        </span>
      </span>
    </div>
  );
}

export function PromoBanner({ promo, m }: { promo: PromoModule; m: StorefrontMessages }) {
  return (
    <div className={styles.promo}>
      <div className={styles.promoMediaWrap}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={styles.promoImg}
          src={promo.image}
          alt=""
          width={780}
          height={495}
          loading="lazy"
          decoding="async"
        />
        <span className={`${styles.promoPrice} ${styles.ltr}`} dir="ltr">
          {formatMoney(promo.priceMinor)}
        </span>
      </div>
      <div className={styles.promoBody}>
        <p className={styles.promoKicker}>{promo.kicker}</p>
        <p className={styles.promoTitle} dir="auto">
          {promo.title}
        </p>
        <p className={styles.promoText} dir="auto">
          {promo.body}
        </p>
        {/* The sheet this opens is a later phase; the affordance is present but
            inert rather than linking to a route that does not exist yet. */}
        <button className={styles.promoCta} type="button" disabled>
          {m.orderNow}
          <ChevronIcon />
        </button>
      </div>
    </div>
  );
}

export function StoryCard({ story }: { story: StoryModule }) {
  return (
    <section className={styles.story} aria-labelledby="sf-story-title">
      <div className={styles.storyMedia}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={styles.storyImg}
          src={story.image}
          alt=""
          width={720}
          height={480}
          loading="lazy"
          decoding="async"
        />
        <div className={styles.storyFade} />
      </div>
      <div className={styles.storyBody}>
        <p className={styles.storyKicker} dir="auto">
          {story.kicker}
        </p>
        <h2 className={styles.storyTitle} id="sf-story-title" dir="auto">
          {story.title}
        </h2>
        <p className={styles.storyText} dir="auto">
          {story.body}
        </p>
        <ul className={styles.facts}>
          {story.facts.slice(0, 3).map((fact) => (
            <li className={styles.fact} key={fact} dir="auto">
              <span className={styles.factDot} aria-hidden="true" />
              {fact}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

export function SiteFooter({ tenant, m }: { tenant: Tenant; m: StorefrontMessages }) {
  return (
    <footer className={styles.footer}>
      <div className={styles.footerRow} dir="auto">
        {tenant.address}
      </div>
      <div className={styles.footerRow}>
        <span>{m.hours}</span>
        <span className={styles.ltr} dir="ltr">
          {tenant.hours.opens}–{tenant.hours.closes}
        </span>
      </div>
      <div className={styles.footerRow}>
        <span>{m.callRestaurant}</span>
        <span className={styles.ltr} dir="ltr">
          {tenant.phone}
        </span>
      </div>
      <p className={styles.footerCredit}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={styles.footerMark}
          src="/bizbot-symbol-256.png"
          alt=""
          width={16}
          height={16}
          loading="lazy"
          decoding="async"
        />
        {m.poweredBy} <span className={styles.footerBrand}>BIZBOT</span>
      </p>
    </footer>
  );
}

export function EmptyMenu({ tenant, m }: { tenant: Tenant; m: StorefrontMessages }) {
  return (
    <div className={styles.empty} role="status">
      <p className={styles.emptyTitle}>{m.emptyMenu}</p>
      <p className={styles.emptyBody} dir="auto">
        {fill(m.emptyMenuBody, { r: tenant.displayName })}
      </p>
    </div>
  );
}

export type { Locale };
