/**
 * Cart dock and the wide persistent aside.
 *
 * PRESENTATION ONLY. Both render a `CartView` that the fixture layer assembles;
 * there is no store, no persistence, no mutation and no navigation to a cart
 * route, because none of that belongs to Phase B. The steppers and CTAs are
 * rendered as disabled controls so the layout and contrast can be reviewed
 * without implying behaviour that does not exist yet.
 */
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { CartView, ServiceState } from '@/source/types';
import { ChevronIcon } from '../icons';
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
        <span className={`${styles.dockTotal} ${styles.ltr}`} dir="ltr">
          {formatMoney(cart.totalMinor)}
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
  const reason = blockedReason(state, m, opensAt);

  return (
    <aside className={styles.aside} aria-labelledby="sf-aside-title">
      <div className={styles.asideHead}>
        <h2 className={styles.asideTitle} id="sf-aside-title">
          {m.cart}
        </h2>
        <span className={styles.asideCount}>
          {cart.itemCount === 0 ? m.emptyCart : countLabel(cart, m)}
        </span>
      </div>

      <ul className={styles.asideLines}>
        {cart.lines.map((line) => (
          <li className={styles.asideLine} key={line.lineId}>
            <div className={styles.asideLineTop}>
              <span>
                <span className={styles.asideLineName} dir="auto">
                  {line.name}
                </span>
                <span className={styles.asideLineOpts} dir="auto">
                  {line.optionSummary}
                </span>
              </span>
              <span className={`${styles.price} ${styles.ltr}`} dir="ltr">
                {formatMoney(line.lineTotalMinor)}
              </span>
            </div>
            {/* Disabled: quantity is real cart behaviour, not Phase B. */}
            <span className={styles.asideStepper} aria-hidden="true">
              <span className={styles.stepBtn}>+</span>
              <span className={`${styles.stepValue} ${styles.ltr}`} dir="ltr">
                {line.quantity}
              </span>
              <span className={styles.stepBtn}>−</span>
            </span>
          </li>
        ))}
      </ul>

      <div className={styles.asideTotals}>
        <div className={styles.totalRow}>
          <span>{m.subtotal}</span>
          <span className={styles.ltr} dir="ltr">
            {formatMoney(cart.subtotalMinor)}
          </span>
        </div>
        <div className={styles.totalRow}>
          <span>{m.tax}</span>
          <span className={styles.ltr} dir="ltr">
            {formatMoney(cart.taxMinor)}
          </span>
        </div>
        <div className={`${styles.totalRow} ${styles.totalRowFinal}`}>
          <span>{m.total}</span>
          <span className={`${styles.amount} ${styles.ltr}`} dir="ltr">
            {formatMoney(cart.totalMinor)}
          </span>
        </div>
      </div>

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
