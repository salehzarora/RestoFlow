/**
 * Intro / welcome — screen 1, approved handoff.
 * Canonical evidence: screenshots/intro__ar__dark__default__390x844.png
 *
 * A SERVER component with no client JavaScript of its own. The language control
 * is a <details> disclosure of real links, because each locale is a separate
 * static document and approved decision 2 requires the served bytes to already
 * carry the right `lang`/`dir`. PG-1 proved `history.replaceState` works, but
 * using it to change LANGUAGE would leave <html lang> disagreeing with the URL,
 * so it is reserved for same-locale URL updates.
 *
 * There is deliberately NO skip control and NO auto-advance: the CTA is the only
 * way forward.
 */
import Link from 'next/link';
import { dirOf, type Locale } from '@/i18n/locales';
import { fill, storefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import { storefrontPath } from '@/routes/routes';
import type { Tenant } from '@/source/types';
import { LanguageMenu } from './LanguageMenu';
import { ChevronIcon, DeliveryIcon, SearchIcon, StoreIcon } from './icons';
import styles from './Intro.module.css';

export function Intro({ tenant, locale }: { tenant: Tenant; locale: Locale }) {
  const m = storefrontMessages(locale);
  const dir = dirOf(locale);
  const { service, hours } = tenant;

  const stateLabel =
    service.state === 'open' ? m.openNow : service.state === 'closed' ? m.closed : m.paused;
  const stateTone =
    service.state === 'open'
      ? styles.toneOk
      : service.state === 'closed'
        ? styles.toneBad
        : styles.toneWarn;

  return (
    <div className={styles.screen}>
      <div className={styles.media}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={styles.mediaImg}
          src={tenant.heroImage}
          alt=""
          width={1600}
          height={1067}
          decoding="async"
          fetchPriority="high"
        />
      </div>
      <div className={styles.vignette} />

      <div className={styles.content}>
        <div className={styles.topRow}>
          <LanguageMenu
            locale={locale}
            hrefFor={(target) => storefrontPath(target, tenant.slug)}
          />
          <button className={styles.glassBtn} type="button" aria-label={m.search} disabled>
            <SearchIcon />
          </button>
        </div>

        <div className={styles.centre}>
          <div className={styles.logoRing}>
            {tenant.brand.logo === null ? (
              <span className={styles.logoFallback} aria-hidden="true">
                {tenant.displayName.slice(0, 1)}
              </span>
            ) : (
              /* eslint-disable-next-line @next/next/no-img-element */
              <img
                className={styles.logo}
                src={tenant.brand.logo}
                alt=""
                width={192}
                height={192}
                decoding="async"
              />
            )}
          </div>

          <p className={styles.kicker}>{m.welcome}</p>
          <h1 className={styles.name} dir="auto">
            {tenant.displayName}
          </h1>
          <p className={styles.tagline} dir="auto">
            {tenant.tagline}
          </p>

          <ul className={styles.pills}>
            {/* Service state. The dot pulses only while ordering is open. */}
            <li className={`${styles.pill} ${stateTone}`}>
              <span className={styles.dot} aria-hidden="true" />
              <span>{stateLabel}</span>
            </li>

            <li className={`${styles.pill} ${service.pickupEnabled ? '' : styles.pillOff}`}>
              <span className={styles.pillIcon} aria-hidden="true">
                <StoreIcon />
              </span>
              <span>{service.pickupEnabled ? m.pickup : m.pickupOff}</span>
            </li>

            <li className={`${styles.pill} ${service.deliveryEnabled ? '' : styles.pillOff}`}>
              <span className={styles.pillIcon} aria-hidden="true">
                <DeliveryIcon />
              </span>
              {service.deliveryEnabled ? (
                <>
                  <span>{m.delivery}</span>
                  <span className={styles.sep} aria-hidden="true" />
                  <span className={styles.ltr} dir="ltr">
                    {fill(m.fromFee, { f: formatMoney(service.deliveryFromMinor) })}
                  </span>
                </>
              ) : (
                <span>{m.deliveryOff}</span>
              )}
            </li>
          </ul>

          <Link
            className={styles.cta}
            href={`${storefrontPath(locale, tenant.slug)}/menu`}
            prefetch={false}
            dir={dir}
          >
            <span className={styles.ctaLabel}>{m.explore}</span>
            <span className={styles.ctaChevron} aria-hidden="true">
              <ChevronIcon />
            </span>
          </Link>
        </div>

        <p className={styles.credit}>
          {m.poweredBy} <span className={styles.creditName}>BIZBOT</span>
          <span className={styles.srOnly}>
            {' · '}
            {hours.opens}–{hours.closes}
          </span>
        </p>
      </div>
    </div>
  );
}
