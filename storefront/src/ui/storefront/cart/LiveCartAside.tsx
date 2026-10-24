'use client';

/**
 * Shared live cart content: a persistent aside on Search at container >=900px,
 * and content inside Home's native cart dialog at every supported width.
 * Host CSS owns width and visibility; this component owns no cart persistence.
 *
 * Lines include published thumbnails (or initials), option summaries, quantity,
 * delegated Edit and explicit Remove. Decrementing below one also removes a
 * line. Edit keeps the existing product/line trigger and modifier validation.
 *
 * All amounts use the current shared quote, including any applicable fee.
 * No amounts appear before a quote exists, and missing/pending/blocked quotes
 * cannot progress. Checkout uses one persistent button and soft navigation so
 * quote settlement cannot replace the focused control.
 */
import { useRouter } from 'next/navigation';
import type { CartSummary } from '@/cart/cartModel';
import { optionSummary } from '@/cart/cartModel';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney, formatRateBp } from '@/money/format';
import type { Quote } from '@/money/quote';
import type { ModifierSelections, ServiceState } from '@/source/types';
import { TenantText } from '../TenantText';
import { productFrameClass, productImageClass } from '../contentPresentation';
import contentStyles from '../storefront.module.css';
import { orderingBlocker, orderingReason } from '../checkout/eligibility';
import styles from '../home/home.module.css';

export type CartUpdate = (
  lineId: string,
  draft: { qty: number; selections: ModifierSelections; note: string },
) => void;

export function LiveCartAside({
  summary,
  quote,
  pending,
  update,
  remove,
  m,
  state,
  orderingEnabled,
  opensAt,
  checkoutHref,
}: {
  /** Null until this visitor's own cart has been read. */
  summary: CartSummary | null;
  quote: Quote | null;
  /**
   * True while the quote for the CURRENT cart has not arrived. A stale total may
   * be SHOWN; nothing may progress against it.
   */
  pending: boolean;
  update: CartUpdate | null;
  remove: ((lineId: string) => void) | null;
  m: StorefrontMessages;
  state: ServiceState;
  /** False for a browse-only storefront: the CTA states the reason, never navigates. */
  orderingEnabled: boolean;
  opensAt: string;
  checkoutHref: string;
}) {
  const router = useRouter();
  // The ONE shared reason (eligibility.ts): browse-only first, then closed / paused.
  const reason = orderingReason(orderingBlocker(state, orderingEnabled), m, opensAt);
  const lines = summary?.lines ?? [];
  const count = summary?.itemCount ?? 0;

  /*
   * THREE STATES, NOT TWO.
   *
   * The head's count and the body's empty sentence must come from the SAME fact,
   * or the panel says "3 items" and "your cart is empty" in the same frame - which
   * it did, measurably, on every wide load. Both now derive from `lines`.
   *
   * A priced total is a separate question. Between the cart being read and its
   * first quote resolving there is a moment with real lines and no total: that
   * renders the lines and a totals frame with no amounts, rather than pretending
   * the cart is empty or showing a price that belongs to a different cart.
   */
  const hasLines = lines.length > 0;
  const priced = quote !== null;
  /* Nothing may progress against a missing or superseded total. */
  const blocked = reason !== null || !priced || pending;

  return (
    <aside className={styles.aside} aria-labelledby="sf-aside-title" data-sf-aside="live">
      <div className={styles.asideHead}>
        <h2 className={styles.asideTitle} id="sf-aside-title">
          {m.cart}
        </h2>
        {/*
          The UNIT count, and it renders at zero too - "0 items" is what the
          prototype puts here (:630 + :793) and it keeps the head a constant
          shape rather than swapping in a sentence.
        */}
        <span className={styles.asideCount} data-sf-aside-count="">
          {count === 1 ? m.item : fill(m.items, { n: String(count) })}
        </span>
      </div>

      {!hasLines ? (
        /* One centred line. The aside's empty state is not the page's. */
        <p className={styles.asideEmpty} data-sf-aside-empty="">
          {m.emptyCartBody}
        </p>
      ) : (
        <>
          <ul className={styles.asideLines}>
            {lines.map((line) => {
              const mods = optionSummary(line);
              const setQty = (next: number) => {
                if (next <= 0) {
                  remove?.(line.line.lineId);
                  return;
                }
                update?.(line.line.lineId, {
                  qty: next,
                  selections: line.line.selections,
                  note: line.line.note,
                });
              };
              return (
                <li
                  className={styles.asideLine}
                  key={line.line.lineId}
                  data-sf-aside-line={line.line.lineId}
                >
                  <span className={`${styles.asideThumb} ${productFrameClass(line.item, contentStyles.wholeFrame)}`}>
                    {line.item.image === null ? line.item.name.slice(0, 1) : (
                      /* eslint-disable-next-line @next/next/no-img-element */
                      <img className={`${styles.imageCover} ${productImageClass(line.item, contentStyles.wholeImage)}`} src={line.item.image} alt="" width={70} height={87} loading="lazy" decoding="async" />
                    )}
                  </span>
                  <div className={styles.asideLineMain}>
                    <span className={styles.asideLineName}>
                      <TenantText>{line.item.name}</TenantText>
                    </span>
                    {mods === '' ? null : (
                      <span className={styles.asideLineOpts}>
                        <TenantText>{mods}</TenantText>
                      </span>
                    )}
                    {/* 34px. Decrementing past one removes the line - the same
                        rule as the cart page, and no undo is designed. */}
                    <span className={styles.asideStepper} data-sf-stepper="aside">
                      <button
                        className={`${styles.stepBtn} ${styles.stepBtnStart}`}
                        type="button"
                        aria-label={m.decrease}
                        onClick={() => setQty(line.line.qty - 1)}
                        data-sf-aside-dec=""
                      >
                        {'−'}
                      </button>
                      <span className={`${styles.stepValue} ${styles.ltr}`} dir="ltr">
                        {line.line.qty}
                      </span>
                      <button
                        className={`${styles.stepBtn} ${styles.stepBtnEnd}`}
                        type="button"
                        aria-label={m.increase}
                        onClick={() => setQty(line.line.qty + 1)}
                        data-sf-aside-inc=""
                      >
                        {'+'}
                      </button>
                    </span>
                    <span className={styles.asideActions}>
                      <button type="button" data-sf-item={line.item.id} data-sf-line={line.line.lineId}>{m.edit}</button>
                      <button type="button" onClick={() => remove?.(line.line.lineId)}>{m.remove}</button>
                    </span>
                  </div>
                  <span className={`${styles.asideLinePrice} ${styles.ltr}`} dir="ltr">
                    {formatMoney(line.totalMinor)}
                  </span>
                </li>
              );
            })}
          </ul>

          <div className={styles.asideTotals} data-sf-aside-totals="">
            {/*
              No amounts until a quote for THIS cart exists. The frame stays so
              the column does not jump; the rows are the only thing that waits.
            */}
            {quote === null ? null : (
              <>
                <div className={styles.totalRow}>
                  <span>{m.subtotal}</span>
                  <span className={styles.ltr} dir="ltr">
                    {formatMoney(quote.subtotalMinor)}
                  </span>
                </div>

                {quote.feeApplies && quote.zone !== null ? (
                  <div className={styles.totalRow} data-sf-aside-fee="">
                    <span>
                      {m.deliveryFee} &middot; <TenantText>{quote.zone.name}</TenantText>
                    </span>
                    <span className={styles.ltr} dir="ltr">
                      {formatMoney(quote.feeMinor)}
                    </span>
                  </div>
                ) : null}

                {/* No tax row when the tenant charges none (rate 0): a zero line
                    would read as a tax that was waived, not one that does not exist. */}
                {quote.taxRateBp === 0 ? null : (
                  <div className={styles.totalRow}>
                    <span>{fill(m.tax, { p: formatRateBp(quote.taxRateBp) })}</span>
                    <span className={styles.ltr} dir="ltr">
                      {formatMoney(quote.taxMinor)}
                    </span>
                  </div>
                )}

                <div className={`${styles.totalRow} ${styles.totalRowFinal}`}>
                  <span>{m.total}</span>
                  <span className={`${styles.amount} ${styles.ltr}`} dir="ltr">
                    {formatMoney(quote.totalMinor)}
                  </span>
                </div>
              </>
            )}

            {/*
              At wide there is no dock and no cart route to visit: the cart is
              already on screen, so this goes STRAIGHT to checkout
              (DESIGN_HANDOFF.md:13).

              It refuses in two different ways, for two different reasons.

              Ordering CLOSED or PAUSED is a standing fact with its own copy, and
              the control states it as a `span`, so nothing focusable leads
              nowhere - the Phase C position, unchanged.

              A MISSING OR SUPERSEDED TOTAL is transient and the control will come
              back, so it is a real button: focusable, activatable by pointer
              and by keyboard, and inert while it refuses. That is the same
              aria-disabled-never-disabled rule the four flow CTAs use, and it is
              what stops an old amount authorising the next step.

              It is the SAME button before and after the total lands. Only its
              refusal changes - never its node - so focus that was on it while
              it refused is still on it when it works. A blocked activation does
              nothing at all: no navigation, no focus move, no announcement.
              The settled activation is a soft navigation through the router,
              exactly what a Link click performs, so the memory-only draft
              survives; there is no prefetch to 404 because there is no href.
            */}
            {reason !== null ? (
              <span
                className={`${styles.asideCta} ${styles.asideCtaDisabled}`}
                role="status"
                data-sf-aside-cta="blocked"
              >
                {reason}
              </span>
            ) : (
              <button
                className={`${styles.asideCta} ${blocked ? styles.asideCtaDisabled : ''}`}
                type="button"
                aria-disabled={blocked ? 'true' : undefined}
                onClick={() => {
                  if (!blocked) router.push(checkoutHref);
                }}
                data-sf-aside-cta={blocked ? 'pending' : 'checkout'}
              >
                {m.checkout}
              </button>
            )}
          </div>
        </>
      )}
    </aside>
  );
}
