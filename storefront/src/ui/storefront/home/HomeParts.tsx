/**
 * Home modules that render from data alone — no interactivity of their own.
 * All are SERVER components; only the chrome that needs scroll is a client one.
 */
import { type Locale } from '@/i18n/locales';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { PromoModule, ServiceState, StoryModule, Tenant } from '@/source/types';
import { ChevronIcon, ClockIcon, DeliveryIcon, MapMotif, StoreIcon } from '../icons';
import { TenantText } from '../TenantText';
import { closedNoticeBody, hoursLabel } from './hoursCopy';
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
  children,
}: {
  tenant: Tenant;
  m: StorefrontMessages;
  title: string;
  subline: string;
  children: React.ReactNode;
}) {
  return (
    <div className={styles.hero} data-sf-module="hero">
      <div className={styles.heroMedia}>
        {/* A tenant that published no hero keeps the brand-colour panel with no
            photo (owner decision D11): the media box stays, the img does not. */}
        {tenant.heroImage === null ? null : (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            className={styles.heroImg}
            src={tenant.heroImage}
            alt=""
            width={1600}
            height={1067}
            decoding="async"
            fetchPriority="high"
          />
        )}
      </div>
      <div className={styles.heroShade} />
      {/* The motif is unconditional: INTERACTIONS.md:124 and STATE_MATRIX.json:104
          say calm suppresses the motif DRAW, not the motif. There is no draw
          animation in this build, so calm needs no gate at all. */}
      <div className={styles.heroMotif}>
        <MapMotif />
      </div>
      {children}
      <div className={styles.heroCopy}>
        {/* dir="auto" isolates the RUN on an inner span, never the block: the
            block must keep the page direction so the title, the accent rule and
            the subline share one alignment edge even when tenant copy is in a
            different script than the interface (prototype Storefront.dc.html
            :140/:142; CONTENT_AND_LOCALIZATION.md:211, :223). */}
        <h1 className={styles.heroTitle}>
          <span dir="auto">{title}</span>
        </h1>
        {/* The rule and the subline exist only when there IS a second line:
            a live tenant's campaign is its tagline alone (D11). */}
        {subline === '' ? null : (
          <>
            <div className={styles.heroRule} />
            <p className={styles.heroSub}>
              <span dir="auto">{subline}</span>
            </p>
          </>
        )}
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
  const { service } = tenant;
  const hoursText = hoursLabel(tenant, m);
  const stateWord =
    service.state === 'open' ? m.openNow : service.state === 'closed' ? m.closed : m.paused;

  // Cell order is delivery -> pickup -> hours, which puts the hours cell at the
  // END of the strip: the left in RTL, exactly as the handoff specifies, and
  // the right in LTR. The strip mirrors with the reading direction like the
  // rest of the row content.
  return (
    <div className={styles.serviceWrap} data-sf-module="service">
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
            <span className={styles.serviceMeta}>
              <TenantText>{service.pickupEnabled ? tenant.city : m.unavailableNow}</TenantText>
            </span>
          </span>
        </div>

        {/* Icon first, like the delivery and pickup cells: the clock belongs on
            the START side (prototype Storefront.dc.html:156-157). Flex follows
            the writing direction, so this mirrors for RTL with no physical CSS. */}
        <div className={styles.serviceCell}>
          <span className={`${styles.serviceIcon} ${styles.serviceClock}`} aria-hidden="true">
            <ClockIcon />
          </span>
          <span className={styles.serviceText}>
            {/* Closed shows "opens {t}" per the approved strip view-model
                (Storefront.dc.html:798, CONTENT_AND_LOCALIZATION.md:44); open and
                paused keep the range. The range is a numeric LTR island, but the
                closed copy is localized PROSE and must follow the page direction -
                a time renders correctly inside RTL text on its own. Every branch
                (incl. closed with no window today) is a complete sentence:
                hoursCopy.ts owns the rule. */}
            {hoursText.numeric ? (
              <span className={`${styles.serviceLabel} ${styles.ltr}`} dir="ltr">
                {hoursText.text}
              </span>
            ) : (
              <span className={styles.serviceLabel}>{hoursText.text}</span>
            )}
            <span className={`${styles.serviceMeta} ${STATE_CLASS[service.state]}`}>
              <span className={styles.stateRow}>
                <span className={styles.stateDot} aria-hidden="true" />
                {stateWord}
              </span>
            </span>
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
      className={closed ? styles.notice : `${styles.notice} ${styles.noticePaused}`}
      data-sf-notice={state}
      data-sf-module="notice"
      role="status"
    >
      <span className={styles.noticeIcon} aria-hidden="true">
        <ClockIcon />
      </span>
      <span>
        <span className={styles.noticeTitle}>{closed ? m.closedTitle : m.pausedTitle}</span>
        <span className={styles.noticeBody}>
          <TenantText>
            {closed
              ? closedNoticeBody(tenant, m)
              : fill(m.pausedBody, { r: tenant.displayName })}
          </TenantText>
        </span>
      </span>
    </div>
  );
}

/**
 * The browse-only notice (STOREFRONT-READ-001, owner decision D5): the menu is
 * real, requests are not yet accepted here. Informational, no action. It is a
 * `notice` module like the closed / paused one and precedes it.
 */
export function OrderingOffNotice({ m }: { m: StorefrontMessages }) {
  return (
    <div
      className={`${styles.notice} ${styles.noticePaused}`}
      data-sf-notice="ordering-off"
      data-sf-module="notice"
      role="status"
    >
      <span className={styles.noticeIcon} aria-hidden="true">
        <ClockIcon />
      </span>
      <span>
        <span className={styles.noticeTitle}>{m.orderingOfflineTitle}</span>
        <span className={styles.noticeBody}>{m.orderingOfflineBody}</span>
      </span>
    </div>
  );
}

export function PromoBanner({ promo, m }: { promo: PromoModule; m: StorefrontMessages }) {
  return (
    <div className={styles.promo} data-sf-module="promo">
      {/* Source order follows the approved band: parchment copy first, 42%
          photo second (prototype Storefront.dc.html:189 then :195). The panes
          are also pinned to explicit grid columns, so the composition does not
          depend on this order. */}
      <div className={styles.promoBody}>
        <p className={styles.promoKicker}>{promo.kicker}</p>
        <p className={styles.promoTitle}>
          <span dir="auto">{promo.title}</span>
        </p>
        <p className={styles.promoText}>
          <span dir="auto">{promo.body}</span>
        </p>
        {/* The sheet this opens is a later phase; the affordance is present but
            inert rather than linking to a route that does not exist yet. */}
        <button className={styles.promoCta} type="button" disabled>
          {m.orderNow}
          <ChevronIcon />
        </button>
      </div>
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
    </div>
  );
}

export function StoryCard({ story }: { story: StoryModule }) {
  return (
    <section className={styles.story} aria-labelledby="sf-story-title" data-sf-module="story">
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
        <p className={styles.storyKicker}>
          <TenantText>{story.kicker}</TenantText>
        </p>
        <h2 className={styles.storyTitle} id="sf-story-title">
          <TenantText>{story.title}</TenantText>
        </h2>
        <p className={styles.storyText}>
          <TenantText>{story.body}</TenantText>
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
  const hoursText = hoursLabel(tenant, m);
  return (
    <footer className={styles.footer} data-sf-module="footer">
      <div className={styles.footerRow}>
        <TenantText>{tenant.address}</TenantText>
      </div>
      <div className={styles.footerRow}>
        <span>{m.hours}</span>
        {hoursText.numeric ? (
          <span className={styles.ltr} dir="ltr">
            {hoursText.text}
          </span>
        ) : (
          <span>{hoursText.text}</span>
        )}
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
