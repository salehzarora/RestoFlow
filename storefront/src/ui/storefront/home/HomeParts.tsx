/**
 * Home modules that render from data alone — no interactivity of their own.
 * All are SERVER components; only the chrome that needs scroll is a client one.
 */
import type { ReactNode } from 'react';
import { Fragment } from 'react';
import { type Locale } from '@/i18n/locales';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { CampaignModule, MenuItem, PromoModule, ServiceState, StoryModule, Tenant } from '@/source/types';
import { ChevronIcon, ClockIcon, DeliveryIcon, StoreIcon } from '../icons';
import { TenantText } from '../TenantText';
import { RestaurantContact } from '../RestaurantContact';
import { closedNoticeBody, hoursLabel } from './hoursCopy';
import { headlineParts, productFrameClass, productImageClass } from '../contentPresentation';
import contentStyles from '../content.module.css';
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

/** Editorial and canonical product media are explicit modes, never guessed. */
export function CampaignHero({ tenant, m, title, subline, eyebrow, ctaHref, ctaLabel, suggestion, content, item }: {
  tenant: Tenant; m: StorefrontMessages; title: string; subline: string;
  /** Intro is a derived composition; Home keeps its existing in-page action. */
  eyebrow?: string; ctaHref?: string; ctaLabel?: string; suggestion?: ReactNode;
  content?: CampaignModule['hero']; item?: MenuItem;
}) {
  const parts = headlineParts(title, content?.format);
  const eyebrowText = content?.eyebrow ?? eyebrow ?? tenant.city;
  const product = content?.mode === 'item' ? item : undefined;
  const photo = product === undefined ? tenant.heroImage : product.image;
  return <section className={`${styles.inner} ${styles.hero}`} data-sf-module="hero" aria-labelledby="sf-hero-title">
    <div className={styles.heroCopy}>
      {eyebrowText ? <p className={styles.eyebrow}><span className={styles.littlePin} aria-hidden="true">⌖</span><TenantText>{eyebrowText}</TenantText></p> : null}
      <h1 className={styles.heroTitle} id="sf-hero-title" aria-label={title}><span dir="auto">{parts.map((part, index) => <Fragment key={index}>{part.breakBefore ? <br aria-hidden="true" /> : null}<span className={part.highlight ? styles.heroWord : undefined}>{part.text}{part.highlight ? <svg viewBox="0 0 320 22" preserveAspectRatio="none" aria-hidden="true" focusable="false"><path d="M3 12C95-3 188 0 312 7M70 20c95-10 155-9 218-7" /></svg> : null}</span></Fragment>)}</span></h1>
      {subline === '' ? null : <p className={styles.heroSub}><span dir="auto">{subline}</span></p>}
      <div className={styles.heroActions}>{product === undefined ? <a className={styles.promoCta} href={ctaHref ?? '#sf-menu'}>{ctaLabel ?? m.discoverMenu}<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M19 12H5m6-6-6 6 6 6" /></svg></a> : <button className={styles.promoCta} type="button" data-sf-item={product.id} disabled={product.soldOut}>{product.soldOut ? m.soldOut : m.orderNow}<ChevronIcon /></button>}{suggestion}</div>
      {content?.footnote ? <p className={styles.heroSub}><TenantText>{content.footnote}</TenantText></p> : null}
    </div>
    <div className={styles.heroVisual}>
      <div className={styles.heroGhost} aria-hidden="true"><TenantText>{tenant.displayName}</TenantText></div>
      <svg className={styles.heroMotif} viewBox="0 0 560 460" fill="none" aria-hidden="true"><path d="M465 40c110 80 45 165-9 167S380 110 471 111c106 0 65 216-15 251S254 428 164 426" /><circle cx="466" cy="40" r="5"/><path d="m167 413-14 16 24 1"/></svg>
      <div className={`${styles.heroMedia} ${product === undefined ? '' : productFrameClass(product, contentStyles.wholeFrame)}`} data-sf-product={product?.id}>{photo === null ? null : (
        /* eslint-disable-next-line @next/next/no-img-element */
        <img className={`${styles.heroImg} ${product === undefined ? '' : productImageClass(product, contentStyles.wholeImage)}`} src={photo} alt="" width={720} height={960} decoding="async" fetchPriority="high" />
      )}{content?.stamp ? <span className={styles.badge}><TenantText>{content.stamp}</TenantText></span> : null}</div>
      {product === undefined ? null : <div className={`${styles.cardMain} ${contentStyles.heroProduct}`}><p className={styles.cardName}><TenantText>{product.name}</TenantText></p><Price minor={product.priceMinor} from={product.hasOptions ? m.from : undefined} /></div>}
    </div>
  </section>;
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
        <span className={styles.brandName}>
          <TenantText>{tenant.displayName}</TenantText>
        </span>
        <span className={styles.brandCity}>
          <TenantText>{tenant.city}</TenantText>
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
      <RestaurantContact publicPhone={tenant.phone} label={m.callRestaurant} className={styles.promoCta} />
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
  const isCategory = promo.kind === 'category';
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
        <button className={styles.promoCta} type="button" data-sf-category={isCategory ? promo.categoryId : undefined} data-sf-item={isCategory ? undefined : promo.itemId}>
          {isCategory ? m.browseMenu : m.orderNow}
          <ChevronIcon />
        </button>
      </div>
      <div className={`${styles.promoMediaWrap} ${isCategory ? '' : productFrameClass(promo, contentStyles.wholeFrame)}`}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={`${styles.promoImg} ${isCategory ? '' : productImageClass(promo, contentStyles.wholeImage)}`}
          src={promo.image}
          alt=""
          width={780}
          height={495}
          loading="lazy"
          decoding="async"
        />
        {isCategory ? null : <span className={`${styles.promoPrice} ${styles.ltr}`} dir="ltr"><Price minor={promo.priceMinor} from={promo.hasOptions ? m.from : undefined} /></span>}
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
            <li className={styles.fact} key={fact}>
              <span className={styles.factDot} aria-hidden="true" />
              <TenantText>{fact}</TenantText>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

export function SiteFooter({ tenant, m }: { tenant: Tenant; m: StorefrontMessages }) {
  const hoursText = hoursLabel(tenant, m);
  return <footer className={styles.footer} data-sf-module="footer">
    <section className={`${styles.inner} ${styles.findUs}`} id="sf-find" aria-label={m.callRestaurant}>
      <div className={styles.findCopy}><p className={styles.eyebrow}>{m.callRestaurant}</p><h2><TenantText>{tenant.displayName}</TenantText></h2><p><TenantText>{tenant.address}</TenantText></p>
        <RestaurantContact publicPhone={tenant.phone} label={m.callRestaurant} className={styles.phoneLink} />
        <p className={styles.footerRow}><span>{m.hours}</span><bdi dir={hoursText.numeric ? 'ltr' : 'auto'}>{hoursText.text}</bdi></p>
      </div>
      {/* Decorative illustration only: no geographic pin or navigation promise. */}
      <div className={styles.brandMap} aria-hidden="true"><svg viewBox="0 0 500 240" className={styles.mapLines}><path d="M-20 40h200l35 40h305M60-20v100l100 60v120M320-20v75l-70 75v150M-20 200l130-80 85 30 140-30 200 100M420-20l-50 110 70 80v100M-20 92l90 25 60-80"/><path className={styles.mapRoute} d="M65 187c52-125 144 61 219-65s144 44 106-83"/><circle cx="65" cy="187" r="7"/></svg><span className={styles.mapBrand}><TenantText>{tenant.displayName}</TenantText></span></div>
    </section>
    <div className={styles.footerBand}><div className={`${styles.inner} ${styles.footerInner}`}><BrandLockup tenant={tenant} small /><TenantText>{tenant.tagline}</TenantText><p className={styles.footerCredit}>{m.poweredBy} <span className={styles.footerBrand}>BIZBOT</span></p></div></div>
  </footer>;
}
export function EmptyMenu({ tenant, m }: { tenant: Tenant; m: StorefrontMessages }) {
  return (
    <div className={styles.empty} role="status">
      <p className={styles.emptyTitle}>{m.emptyMenu}</p>
      <p className={styles.emptyBody}>
        <TenantText>{fill(m.emptyMenuBody, { r: tenant.displayName })}</TenantText>
      </p>
    </div>
  );
}

export type { Locale };
