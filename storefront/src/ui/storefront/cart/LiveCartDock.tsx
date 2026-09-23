'use client';

/**
 * THE LIVE CART DOCK.
 *
 * WHY THIS IS A SEPARATE FILE FROM CartParts.tsx. `CartParts.tsx` is guarded by
 * tests/sf-source-rules.test.mjs as PRESENTATION ONLY - no state, no store, no
 * handlers - and that guard is still correct and still enforced. This build
 * does NOT route around it: the guard has been widened deliberately to name
 * this file as the one live dock, so the boundary is written down rather than
 * quietly abandoned. CartParts keeps rendering the prerendered dock; this
 * component replaces it once the visitor's own cart has been read.
 *
 * Anatomy is unchanged from the approved Phase B dock (DESIGN_HANDOFF.md:76),
 * so it reuses home.module.css rather than restating the measurements. What is
 * new is everything that needs a real cart: the halo, the count bump, the
 * no-image thumbnail fallback and a subtotal that moves.
 *
 * THE CTA IS LIVE FROM PHASE D. Its approved destination is the `cart` route
 * (INTERACTIONS.md:78), which now exists, so it is a real link. While ordering
 * is closed or paused it states the reason instead and does not navigate -
 * rendered as a `span` rather than a dead link, so nothing focusable leads
 * nowhere. The dock only exists below 900px anyway; at wide the aside replaces
 * it and goes straight to checkout.
 */
import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { CartSummary } from '@/cart/cartModel';
import type { MotionMode, ServiceState } from '@/source/types';
import { ChevronIcon } from '../icons';
import styles from '../home/home.module.css';

function countLabel(count: number, m: StorefrontMessages): string {
  return count === 1 ? m.item : fill(m.items, { n: String(count) });
}

function blockedReason(state: ServiceState, m: StorefrontMessages, opensAt: string): string | null {
  if (state === 'closed') return fill(m.orderingClosed, { t: opensAt });
  if (state === 'paused') return m.orderingPaused;
  return null;
}

export function LiveCartDock({
  summary,
  m,
  motion,
  state,
  opensAt,
  cartHref,
}: {
  summary: CartSummary;
  m: StorefrontMessages;
  motion: MotionMode;
  state: ServiceState;
  opensAt: string;
  cartHref: string;
}) {
  const count = summary.itemCount;
  const [bump, setBump] = useState(false);
  const previous = useRef(count);

  useEffect(() => {
    if (count > previous.current) {
      setBump(true);
      // 1 -> 1.25 -> 1 over 200ms, then the class comes off so the next add can
      // restart the animation rather than find it already applied.
      const timer = window.setTimeout(() => setBump(false), 220);
      previous.current = count;
      return () => window.clearTimeout(timer);
    }
    previous.current = count;
    return undefined;
  }, [count]);

  // Hidden while the cart is empty, exactly as the design specifies.
  if (count === 0) return null;
  const reason = blockedReason(state, m, opensAt);

  return (
    <div className={styles.dock} data-sf-dock="live">
      {motion === 'calm' ? null : <span className={styles.dockHalo} aria-hidden="true" />}

      <div className={`${styles.dockThumbs} ${styles.dockRelative}`}>
        {summary.lines.slice(0, 3).map((line) =>
          line.item.image === null ? (
            <span
              className={`${styles.dockThumb} ${styles.dockThumbNone}`}
              key={line.line.lineId}
              aria-hidden="true"
            >
              {line.item.name.trim().slice(0, 1)}
            </span>
          ) : (
            /* eslint-disable-next-line @next/next/no-img-element */
            <img
              className={styles.dockThumb}
              key={line.line.lineId}
              src={line.item.image}
              alt=""
              width={80}
              height={80}
              loading="lazy"
              decoding="async"
            />
          ),
        )}
        <span
          className={`${styles.dockCount} ${bump ? styles.dockBump : ''}`}
          aria-hidden="true"
        >
          {count}
        </span>
      </div>

      <span className={styles.dockText}>
        <span className={styles.dockItems}>{countLabel(count, m)}</span>
        {/* SUBTOTAL, not total - DESIGN_HANDOFF.md:76. */}
        <span className={`${styles.dockTotal} ${styles.ltr}`} dir="ltr">
          {formatMoney(summary.subtotalMinor)}
        </span>
      </span>

      {reason === null ? (
        <Link
          className={styles.dockCta}
          href={cartHref}
          /* A static export serves no per-segment RSC payload, so Next's
             viewport prefetch would 404 on every render of this dock. */
          prefetch={false}
          data-sf-dock-cta="cart"
        >
          {m.viewCart}
          <ChevronIcon />
        </Link>
      ) : (
        <span
          className={`${styles.dockCta} ${styles.dockDisabled}`}
          role="status"
          data-sf-dock-cta="blocked"
        >
          {reason}
        </span>
      )}
    </div>
  );
}
