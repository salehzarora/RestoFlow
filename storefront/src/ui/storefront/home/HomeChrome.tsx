'use client';

/**
 * The ONE interactive island on home.
 *
 * It owns the three things that genuinely need the client — the scroll-driven
 * compact header, the scroll-spy that keeps the category rails in sync, and
 * dismissing the announcement — and takes the hero, service strip and notice as
 * already-rendered server nodes so none of that markup is shipped as JavaScript.
 *
 * Dismissal is IN-MEMORY for this view. The design calls for it to last the
 * session, which needs sessionStorage, and the Phase A source rule forbids the
 * app layer from touching browser storage. Relaxing that guard is a contract
 * change, so it is reported rather than taken unilaterally.
 */
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { Category, Tenant } from '@/source/types';
import { ChevronIcon, CloseIcon, SearchIcon, SendIcon } from '../icons';
import styles from './home.module.css';

/** The design's threshold: the compact header appears past 200px of scroll. */
const COMPACT_AT = 200;
/** Scroll-spy offset, standalone (no status bar). */
const SPY_OFFSET = 116;
/** One arrow tap scrolls the rail by this much, in the reading direction. */
const ARROW_STEP = 180;

function CategoryIcon({ path }: { path: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d={path} />
    </svg>
  );
}

export function HomeChrome({
  tenant,
  m,
  categories,
  announcement,
  hero,
  service,
  notice,
  searchLabel,
}: {
  tenant: Tenant;
  m: StorefrontMessages;
  categories: readonly Category[];
  announcement: string | null;
  hero: ReactNode;
  service: ReactNode;
  notice: ReactNode;
  searchLabel: string;
}) {
  const [dismissed, setDismissed] = useState(false);
  const [compact, setCompact] = useState(false);
  const [active, setActive] = useState(categories[0]?.id ?? '');
  const orbRail = useRef<HTMLDivElement>(null);
  const chipRail = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (categories.length === 0) return undefined;
    let frame = 0;
    const read = () => {
      frame = 0;
      setCompact(window.scrollY > COMPACT_AT);
      // The active category is the last section whose top has passed the offset.
      let current = categories[0].id;
      for (const category of categories) {
        const section = document.getElementById(`sf-cat-${category.id}`);
        if (section === null) continue;
        if (section.getBoundingClientRect().top - SPY_OFFSET <= 0) current = category.id;
      }
      setActive(current);
    };
    const onScroll = () => {
      if (frame === 0) frame = window.requestAnimationFrame(read);
    };
    read();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (frame !== 0) window.cancelAnimationFrame(frame);
    };
  }, [categories]);

  // Keep the active chip centred in both rails whenever it changes.
  useEffect(() => {
    for (const rail of [orbRail.current, chipRail.current]) {
      if (rail === null) continue;
      const chip = rail.querySelector(`[data-category="${active}"]`);
      if (chip === null) continue;
      const railBox = rail.getBoundingClientRect();
      const chipBox = chip.getBoundingClientRect();
      const delta = chipBox.left + chipBox.width / 2 - (railBox.left + railBox.width / 2);
      if (Math.abs(delta) > 4) rail.scrollBy({ left: delta, behavior: 'smooth' });
    }
  }, [active]);

  const goTo = useCallback((id: string) => {
    const section = document.getElementById(`sf-cat-${id}`);
    if (section === null) return;
    setActive(id);
    section.scrollIntoView({ block: 'start', behavior: 'smooth' });
  }, []);

  const nudge = useCallback((direction: 1 | -1) => {
    const rail = orbRail.current;
    if (rail === null) return;
    // In RTL the rail's scroll axis is inverted, so the reading direction is
    // what the arrow means, not the raw sign.
    const rtl = getComputedStyle(rail).direction === 'rtl';
    rail.scrollBy({ left: ARROW_STEP * direction * (rtl ? -1 : 1), behavior: 'smooth' });
  }, []);

  return (
    <>
      {announcement === null || dismissed ? null : (
        <div className={styles.announce} role="status">
          <span className={styles.announceGlyph} aria-hidden="true">
            <SendIcon />
          </span>
          <span className={styles.announceText} dir="auto">
            {announcement}
          </span>
          <button
            className={styles.announceClose}
            type="button"
            aria-label={m.close}
            onClick={() => setDismissed(true)}
          >
            <CloseIcon />
          </button>
        </div>
      )}

      <div className={styles.compactHost}>
        <div
          className={`${styles.compact} ${compact ? styles.compactOn : ''}`}
          data-sf-compact={compact ? 'on' : 'off'}
        >
        <div className={styles.compactRow}>
          {tenant.brand.logo === null ? null : (
            /* eslint-disable-next-line @next/next/no-img-element */
            <img
              className={styles.compactLogo}
              src={tenant.brand.logo}
              alt=""
              width={60}
              height={60}
              decoding="async"
            />
          )}
          {/* The run is isolated with dir="auto" on an INNER span so a Latin
              name reads correctly without flipping the block's own alignment
              away from the logo it belongs beside. */}
          <span className={styles.compactName}>
            <span dir="auto">{tenant.displayName}</span>
          </span>
          <button className={styles.compactBtn} type="button" aria-label={searchLabel} disabled>
            <SearchIcon />
          </button>
        </div>
        {categories.length === 0 ? null : (
          <div className={styles.chipRail} ref={chipRail}>
            {categories.map((category) => (
              <button
                className={`${styles.chip} ${category.id === active ? styles.chipActive : ''}`}
                key={category.id}
                type="button"
                data-category={category.id}
                aria-current={category.id === active ? 'true' : undefined}
                onClick={() => goTo(category.id)}
              >
                <CategoryIcon path={category.iconPath} />
                <span className={styles.chipLabel} dir="auto">
                  {category.name}
                </span>
              </button>
            ))}
            </div>
          )}
        </div>
      </div>

      {hero}
      {service}
      {notice}

      {categories.length === 0 ? null : (
        <nav className={styles.rail} aria-label={m.menuLabel}>
          <button
            className={`${styles.railArrow} ${styles.railArrowStart}`}
            type="button"
            aria-label={m.prevCategory}
            onClick={() => nudge(-1)}
          >
            <ChevronIcon />
          </button>
          <div className={styles.railTrack} ref={orbRail}>
            {categories.map((category) => (
              <button
                className={`${styles.orb} ${category.id === active ? styles.orbActive : ''}`}
                key={category.id}
                type="button"
                data-category={category.id}
                aria-current={category.id === active ? 'true' : undefined}
                onClick={() => goTo(category.id)}
              >
                <span className={styles.orbCircle}>
                  {category.image === null ? (
                    <span className={styles.orbIcon} aria-hidden="true">
                      <CategoryIcon path={category.iconPath} />
                    </span>
                  ) : (
                    /* eslint-disable-next-line @next/next/no-img-element */
                    <img
                      className={styles.orbImg}
                      src={category.image}
                      alt=""
                      width={128}
                      height={128}
                      loading="lazy"
                      decoding="async"
                    />
                  )}
                </span>
                <span className={styles.orbLabel} dir="auto">
                  {category.name}
                </span>
              </button>
            ))}
          </div>
          <button
            className={`${styles.railArrow} ${styles.railArrowEnd}`}
            type="button"
            aria-label={m.nextCategory}
            onClick={() => nudge(1)}
          >
            <ChevronIcon />
          </button>
        </nav>
      )}

    </>
  );
}

