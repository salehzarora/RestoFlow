'use client';

/**
 * THE FUNCTIONAL WIDE CART ASIDE - 360px, container >= 900px, home and search.
 *
 * WHY THIS IS A SEPARATE FILE FROM CartParts.tsx, AGAIN. `CartParts.tsx` is
 * guarded as PRESENTATION ONLY - no state, no store, no handlers - and that
 * guard is still correct and still enforced. Phase D does not route around it:
 * the boundary is widened deliberately to name this file, exactly as
 * LiveCartDock.tsx already is, so the rule stays written down.
 *
 * HOW IT DIFFERS FROM THE CART PAGE, by design and not by omission:
 *   no back chevron        - it is a panel, not a route
 *   no thumbnails          - the page has 64px thumbs, the aside has none
 *   no kitchen note        - shown on the page only
 *   no Edit, no Remove     - removal is by decrementing to zero
 *   34px steppers          - the page's are 40px
 *   no cart notices        - they have no wide surface at all
 *   a 50px CTA, no total   - the page's 56px CTA carries the total
 *   no dashed total rule   - the page has one
 *
 * ONE DELIBERATE DEPARTURE FROM THE PROTOTYPE: the delivery-fee row.
 * The prototype's aside renders subtotal, tax and total only (:636) while its
 * tax is computed on `subtotal + fee` (:695). Once a zone has been chosen on
 * checkout - reachable at wide, because Back from checkout returns to the menu
 * with the aside visible - that panel reads 110 + 21.60 = 141.60, with ten
 * shekels invisible. A totals block that does not add up is a money defect, so
 * the fee row is rendered here on the same `feeApplies` rule every other
 * surface uses. Recorded in PHASE_D_DECISIONS.md.
 *
 * THE CHECKOUT CONTROL IS ONE ELEMENT FOR ITS WHOLE LIFE (E-stage repair of the
 * D1 keyboard regression). D1 rendered a `<button aria-disabled>` while the
 * quote was pending and swapped in a `<Link>` once it settled. The swap
 * destroyed the focused node, so a keyboard visitor who had reached the control
 * during the pending window was dropped to `<body>` the moment it became
 * usable. The control is now a single `<button>` - the element the prototype
 * uses (:636) - that stays inert while blocked and performs the same SOFT
 * navigation a Link click would once a matching total exists. Its identity
 * never changes, so focus survives settlement without anything having to
 * restore it, and nothing ever moves focus that the visitor did not move.
 */
import { useRouter } from 'next/navigation';
import type { CartSummary } from '@/cart/cartModel';
import { optionSummary } from '@/cart/cartModel';
import { fill, type StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { Quote } from '@/money/quote';
import type { ModifierSelections, ServiceState } from '@/source/types';
import { TenantText } from '../TenantText';
import styles from '../home/home.module.css';

export type CartUpdate = (
  lineId: string,
  draft: { qty: number; selections: ModifierSelections; note: string },
) => void;

function blockedReason(state: ServiceState, m: StorefrontMessages, opensAt: string): string | null {
  if (state === 'closed') return fill(m.orderingClosed, { t: opensAt });
  if (state === 'paused') return m.orderingPaused;
  return null;
}

export function LiveCartAside({
  summary,
  quote,
  pending,
  update,
  remove,
  m,
  state,
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
  opensAt: string;
  checkoutHref: string;
}) {
  const router = useRouter();
  const reason = blockedReason(state, m, opensAt);
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

                <div className={styles.totalRow}>
                  <span>{m.tax}</span>
                  <span className={styles.ltr} dir="ltr">
                    {formatMoney(quote.taxMinor)}
                  </span>
                </div>

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
