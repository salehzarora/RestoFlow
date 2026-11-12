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
import { usePathname } from 'next/navigation';
import { cartNavigationHref } from '@/routes/cart-navigation';
import { useEffect, useRef, useState } from 'react';
import type { StorefrontMessages } from '@/i18n/storefront';
import { fill } from '@/i18n/fill';
import { formatMoney } from '@/money/format';
import type { CartSummary } from '@/cart/cartModel';
import type { MotionMode, ServiceState } from '@/source/types';
import { TrolleyIcon } from '../icons';
import { orderingBlocker, orderingReason } from '../checkout/eligibility';
import styles from '../home/home.module.css';

function countLabel(count: number, m: StorefrontMessages): string {
  return count === 1 ? m.item : fill(m.items, { n: String(count) });
}

export function LiveCartDock({
  summary,
  m,
  motion,
  state,
  orderingEnabled,
  opensAt,
  cartHref: canonicalCartHref,
}: {
  summary: CartSummary;
  m: StorefrontMessages;
  motion: MotionMode;
  state: ServiceState;
  /** False for a browse-only storefront: the CTA states the reason, never links. */
  orderingEnabled: boolean;
  opensAt: string;
  cartHref: string;
}) {
  const count = summary.itemCount;
  const cartHref = cartNavigationHref(canonicalCartHref, usePathname());
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
  // The ONE shared reason (eligibility.ts): browse-only first, then closed / paused.
  const reason = orderingReason(orderingBlocker(state, orderingEnabled), m, opensAt);

  const contents = <>
    <span className={styles.dockText}>
      <span className={`${styles.dockItems} ${bump && motion !== 'calm' ? styles.dockBump : ''}`}>{countLabel(count, m)}</span>
      <span className={`${styles.dockTotal} ${styles.ltr}`} dir="ltr">{formatMoney(summary.subtotalMinor)}</span>
    </span>
    <span className={`${styles.dockCta} ${reason ? styles.dockDisabled : ''}`} data-sf-dock-cta={reason ? 'blocked' : 'cart'}><TrolleyIcon />{reason ?? m.viewCart}</span>
  </>;
  // One native link owns the whole bar; no nested controls or new cart action.
  return reason === null ? <Link className={styles.dock} data-sf-dock="live" href={cartHref} prefetch={false}>{contents}</Link>
    : <div className={styles.dock} data-sf-dock="live" role="status">{contents}</div>;
}
