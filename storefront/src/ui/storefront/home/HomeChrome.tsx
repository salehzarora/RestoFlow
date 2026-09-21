'use client';

/**
 * The ONE interactive island on home.
 *
 * It owns the three things that genuinely need the client — the scroll-driven
 * compact header, the scroll-spy that keeps the category rails in sync, and
 * dismissing the announcement — and takes the hero, service strip and notice as
 * already-rendered server nodes so none of that markup is shipped as JavaScript.
 *
 * Dismissal lasts the TAB SESSION, per route slug, through the one allowlisted
 * UI-session helper (INTERACTIONS.md:41, COMPONENT_INVENTORY.md:9). The strip is
 * present in the static HTML for every visitor and is removed only after
 * hydration, in a LAYOUT effect, so the served bytes never differ and there is
 * no hydration mismatch.
 */
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import {
  isAnnouncementDismissed,
  markAnnouncementDismissed,
  markIntroSeen,
} from '@/session/uiSession';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { Category, Tenant } from '@/source/types';
import { ChevronIcon, CloseIcon, SearchIcon, SendIcon } from '../icons';
import { TenantText } from '../TenantText';
import styles from './home.module.css';

/** The design's threshold: the compact header appears past 200px of scroll. */
const COMPACT_AT = 200;
/** Scroll-spy offset, standalone (no status bar). */
const SPY_OFFSET = 116;
/** One arrow tap scrolls the rail by this much, in the reading direction. */
const ARROW_STEP = 180;

/**
 * Every programmatic scroll on this screen resolves its behaviour here.
 *
 * "Programmatic scrolling switches to `auto` under reduced motion"
 * (DESIGN_HANDOFF.md:78, INTERACTIONS.md:128, TOKENS.json motion.reducedMotion),
 * and the locked prototype does exactly this (Storefront.dc.html:704).
 *
 * Read at CALL time, never at module load: the setting can change while the
 * page is open, and a module-level constant would freeze the wrong answer for
 * the life of the document.
 *
 * `auto` and not `instant`: `instant` is a late re-addition to the
 * ScrollBehavior IDL enum, and an engine that predates it throws a TypeError on
 * the dictionary rather than ignoring the member. `auto` then defers to the
 * element's computed `scroll-behavior` - which is why the two rails drop their
 * own `scroll-behavior: smooth` under reduced motion in home.module.css.
 */
function scrollBehavior(): ScrollBehavior {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';
}

/** A 1px slack: fractional layout means an end is never reached exactly. */
const EDGE_EPS = 1;

/**
 * How far a rail sits from its inline START and END - direction-safe.
 *
 * No `direction` sniffing: every shipping engine follows the CSSOM-View
 * "negative" model, where scrollLeft is 0 at the inline start and runs to +max
 * (LTR) or -max (RTL), so the MAGNITUDE is the distance from the start in both.
 * A rail that cannot scroll at all reports itself at both ends, which disables
 * both arrows rather than offering an affordance that does nothing.
 */
function railEdges(rail: HTMLElement): { atStart: boolean; atEnd: boolean } {
  const max = rail.scrollWidth - rail.clientWidth;
  if (max <= EDGE_EPS) return { atStart: true, atEnd: true };
  const from = Math.abs(rail.scrollLeft);
  return { atStart: from <= EDGE_EPS, atEnd: from >= max - EDGE_EPS };
}

function CategoryIcon({ path }: { path: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d={path} />
    </svg>
  );
}

export function HomeChrome({
  tenant,
  slug,
  m,
  categories,
  announcement,
  hero,
  service,
  notice,
  searchLabel,
  searchHref,
}: {
  tenant: Tenant;
  /** The ROUTE slug, not tenant.slug: every demo scenario resolves to the same
      tenant, so tenant.slug would collapse several slugs onto one session key. */
  slug: string;
  m: StorefrontMessages;
  categories: readonly Category[];
  announcement: string | null;
  hero: ReactNode;
  service: ReactNode;
  notice: ReactNode;
  searchLabel: string;
  searchHref: string;
}) {
  const [dismissed, setDismissed] = useState(false);
  const [compact, setCompact] = useState(false);
  const [active, setActive] = useState(categories[0]?.id ?? '');
  const orbRail = useRef<HTMLDivElement>(null);
  const chipRail = useRef<HTMLElement>(null);
  // Both arrows start disabled. Pre-hydration they genuinely do nothing - they
  // are onClick-only - so rendering them enabled in the static HTML was a lie;
  // the measurement below corrects this within a frame of mount. Server and
  // client agree on this initial value, so there is no hydration mismatch.
  const [edges, setEdges] = useState({ atStart: true, atEnd: true });

  // Reaching home is what "the intro has been seen" means for this tab: the
  // intro CTA is the only way past it, and a deep link here is a visitor the
  // handoff also sends straight to home (DESIGN_HANDOFF.md:27).
  useEffect(() => {
    markIntroSeen(slug);
  }, [slug]);

  // Restore a dismissal made earlier in this tab. A LAYOUT effect, so the strip
  // is removed in the hydration commit rather than a painted frame later.
  useLayoutEffect(() => {
    if (isAnnouncementDismissed(slug)) setDismissed(true);
  }, [slug]);

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
      if (Math.abs(delta) > 4) rail.scrollBy({ left: delta, behavior: scrollBehavior() });
    }
  }, [active]);

  // Arrow availability is MEASURED, never assumed: a rail already at an end -
  // or too short to scroll at all - must not offer the affordance.
  useEffect(() => {
    const rail = orbRail.current;
    if (rail === null) return undefined;
    const measure = () =>
      setEdges((prev) => {
        const next = railEdges(rail);
        // Same object when nothing changed: a smooth scroll fires this every
        // frame and must not re-render the rail every frame.
        return prev.atStart === next.atStart && prev.atEnd === next.atEnd ? prev : next;
      });
    measure();
    rail.addEventListener('scroll', measure, { passive: true });
    // ResizeObserver, not window.resize: the wide layout is keyed to the
    // CONTAINER (@container storefront (min-width: 900px)), so the rail's
    // clientWidth can change when the aside appears without the window moving.
    const observer = new ResizeObserver(measure);
    observer.observe(rail);
    return () => {
      rail.removeEventListener('scroll', measure);
      observer.disconnect();
    };
  }, [categories]);

  const goTo = useCallback((id: string) => {
    const section = document.getElementById(`sf-cat-${id}`);
    if (section === null) return;
    setActive(id);
    section.scrollIntoView({ block: 'start', behavior: scrollBehavior() });
  }, []);

  const nudge = useCallback((direction: 1 | -1) => {
    const rail = orbRail.current;
    if (rail === null) return;
    // In RTL the rail's scroll axis is inverted, so the reading direction is
    // what the arrow means, not the raw sign.
    const rtl = getComputedStyle(rail).direction === 'rtl';
    rail.scrollBy({ left: ARROW_STEP * direction * (rtl ? -1 : 1), behavior: scrollBehavior() });
  }, []);

  return (
    <>
      {announcement === null || dismissed ? null : (
        <div className={styles.announce} role="status" data-sf-module="announce">
          <span className={styles.announceGlyph} aria-hidden="true">
            <SendIcon />
          </span>
          <span className={styles.announceText}>
            <TenantText>{announcement}</TenantText>
          </span>
          <button
            className={styles.announceClose}
            type="button"
            aria-label={m.close}
            onClick={() => {
              setDismissed(true);
              markAnnouncementDismissed(slug);
            }}
          >
            <CloseIcon />
          </button>
        </div>
      )}

      <div className={styles.compactHost} data-sf-module="compact">
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
          <a className={styles.compactBtn} href={searchHref} aria-label={searchLabel}>
            <SearchIcon />
          </a>
        </div>
        {categories.length === 0 ? null : (
          <nav className={styles.chipRail} ref={chipRail} aria-label={m.compactMenuLabel}>
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
            </nav>
          )}
        </div>
      </div>

      {hero}
      {service}
      {notice}

      {categories.length === 0 ? null : (
        <nav className={styles.rail} aria-label={m.menuLabel} data-sf-module="categories">
          <button
            className={`${styles.railArrow} ${styles.railArrowStart}`}
            type="button"
            aria-label={m.prevCategory}
            disabled={edges.atStart}
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
            disabled={edges.atEnd}
            onClick={() => nudge(1)}
          >
            <ChevronIcon />
          </button>
        </nav>
      )}

    </>
  );
}
