/**
 * Cart dock (inert reference rendering) and the wide persistent aside (seam).
 *
 * PRESENTATION ONLY. No store, no persistence, no mutation, no navigation.
 *
 * `CartDock` renders a `CartView` and is the Phase B reference rendering of the
 * dock's anatomy. It is NOT what a visitor sees: the live dock a visitor gets
 * is cart/LiveCartDock.tsx, named by the boundary guard in sf-home.test.mjs.
 * Nothing in the shipped app renders this component, so no fixture cart can
 * reach a static document through it.
 *
 * `CartAside` takes NO cart at all. At container >= 900px it is the wide
 * Phase-D seam and must stay truthful while the cart screen does not exist, so
 * it deliberately has no lines, no count, no subtotal, no tax and no total, and
 * a checkout CTA that is disabled because its route is Phase D.
 */
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { CartView, ServiceState } from '@/source/types';
import { ChevronIcon } from '../icons';
import { TenantText } from '../TenantText';
import styles from './home.module.css';

function countLabel(cart: CartView, m: StorefrontMessages): string {
  return cart.itemCount === 1 ? m.item : fill(m.items, { n: String(cart.itemCount) });
}

/** The reason the cart is unavailable, or null when ordering is open. */
function blockedReason(state: ServiceState, m: StorefrontMessages, opensAt: string): string | null {
  if (state === 'closed') return fill(m.orderingClosed, { t: opensAt });
  if (state === 'paused') return m.orderingPaused;
  return null;
}

export function CartDock({
  cart,
  m,
  state,
  opensAt,
}: {
  cart: CartView;
  m: StorefrontMessages;
  state: ServiceState;
  opensAt: string;
}) {
  // Hidden while the cart is empty, exactly as the design specifies.
  if (cart.itemCount === 0) return null;
  const reason = blockedReason(state, m, opensAt);

  return (
    <div className={styles.dock}>
      <div className={`${styles.dockThumbs} ${styles.dockRelative}`}>
        {cart.lines.slice(0, 3).map((line) =>
          line.image === null ? null : (
            /* eslint-disable-next-line @next/next/no-img-element */
            <img
              className={styles.dockThumb}
              key={line.lineId}
              src={line.image}
              alt=""
              width={80}
              height={80}
              loading="lazy"
              decoding="async"
            />
          ),
        )}
        <span className={styles.dockCount} aria-hidden="true">
          {cart.itemCount}
        </span>
      </div>

      <span className={styles.dockText}>
        <span className={styles.dockItems}>{countLabel(cart, m)}</span>
        {/* The dock carries the running SUBTOTAL, not the total: the approved
            anatomy is "item count + running subtotal in accent"
            (DESIGN_HANDOFF.md:76, COMPONENT_INVENTORY.md:102). The full
            subtotal/fee/tax/total breakdown belongs to the cart aside. */}
        <span className={`${styles.dockTotal} ${styles.ltr}`} dir="ltr">
          {formatMoney(cart.subtotalMinor)}
        </span>
      </span>

      <button
        className={`${styles.dockCta} ${reason === null ? '' : styles.dockDisabled}`}
        type="button"
        disabled
        aria-disabled="true"
      >
        {reason === null ? m.viewCart : reason}
        {reason === null ? <ChevronIcon /> : null}
      </button>
    </div>
  );
}

export function CartAside({
  m,
  state,
  opensAt,
}: {
  m: StorefrontMessages;
  state: ServiceState;
  opensAt: string;
}) {
  const reason = blockedReason(state, m, opensAt);

  return (
    <aside className={styles.aside} aria-labelledby="sf-aside-title" data-sf-aside="seam">
      <div className={styles.asideHead}>
        <h2 className={styles.asideTitle} id="sf-aside-title">
          {m.cart}
        </h2>
        <span className={styles.asideCount}>{m.emptyCart}</span>
      </div>

      {/*
        NO lines, NO subtotal, NO tax, NO total. Rendering a totals block here
        would be business state, and this seam is deliberately not wired to the
        cart. It is the same bytes for every visitor and does not move when a
        real cart exists.
      */}

      <button
        className={`${styles.asideCta} ${reason === null ? '' : styles.asideCtaDisabled}`}
        type="button"
        disabled
        aria-disabled="true"
      >
        {reason === null ? m.checkout : reason}
      </button>
    </aside>
  );
}
