'use client';

/**
 * SCREEN 5 - THE CART.
 *
 * Header with the title and the UNIT count, an optional notice card, the line
 * cards, the totals block and a sticky footer CTA carrying the total. An empty
 * cart replaces the lines AND the totals AND the footer with one empty state
 * offering the menu (DESIGN_HANDOFF.md:110-116).
 *
 * WHAT THIS SCREEN DOES NOT DO:
 *   - It never computes money. Every figure comes from the Quote.
 *   - It never repairs the cart on the visitor's behalf. A notice TELLS; it
 *     does not remove a line, substitute a product or change a price
 *     (README.md:42-49 truth rules).
 *   - It never raises a notice itself. Which lines changed is a server answer
 *     that does not exist yet (OPEN_QUESTIONS.md:42-43, SNAP-001), so the
 *     notice is INJECTED and this screen only renders it.
 *
 * DECREMENTING BELOW ONE REMOVES THE LINE, with no undo, because no undo is
 * designed (INTERACTIONS.md:82). The removal is ANNOUNCED, which is the one
 * thing the prototype does not do and a keyboard visitor needs.
 */
import Link from 'next/link';
import { useCallback, useState } from 'react';
import type { CartApi } from '@/cart/useCart';
import { optionSummary, type ResolvedCartLine } from '@/cart/cartModel';
import type { StorefrontMessages } from '@/i18n/storefront';
import { formatMoney } from '@/money/format';
import type { Quote } from '@/money/quote';
import type { MotionMode, ServiceState } from '@/source/types';
import { AlertIcon, InfoIcon, MinusIcon, NoteIcon, PlusIcon, TrolleyIcon } from '../icons';
import { TenantText } from '../TenantText';
import { Announcer, Banner, Bidi, FooterCta, Interpolate, Money, Totals, CartHeader } from './flowParts';
import { orderingBlocker, orderingReason } from './eligibility';
import s from './flow.module.css';

/**
 * The three designed notices. The KIND is injected; the copy, tone and
 * geometry are locked. `soldOut` deliberately reuses `changedTitle` - there is
 * no sold-out-specific title in the approved pack (Storefront.dc.html:849).
 */
export type CartNoticeKind = 'changed' | 'price' | 'soldOut';

export interface CartNotice {
  readonly kind: CartNoticeKind;
  /** The real item name for `soldOut`. Never a placeholder. */
  readonly itemName?: string;
}

function CartLineCard({
  line,
  m,
  onQty,
  onRemove,
}: {
  line: ResolvedCartLine;
  m: StorefrontMessages;
  onQty: (next: number) => void;
  onRemove: () => void;
}) {
  const mods = optionSummary(line);
  const initial = line.item.name.trim().slice(0, 1);

  return (
    <li className={s.line} data-sf-cart-line={line.line.lineId}>
      <span className={s.lineMedia}>
        {line.item.image === null ? (
          <span className={s.lineNoImg} aria-hidden="true">
            {initial}
          </span>
        ) : (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            className={s.lineImg}
            src={line.item.image}
            alt=""
            width={128}
            height={128}
            loading="lazy"
            decoding="async"
          />
        )}
      </span>

      <div className={s.lineBody}>
        <div className={s.lineTop}>
          <span className={s.lineName}>
            <TenantText>{line.item.name}</TenantText>
          </span>
          <span className={`${s.linePrice} ${s.ltr}`} dir="ltr">
            {formatMoney(line.totalMinor)}
          </span>
        </div>

        {mods === '' ? null : (
          <div className={s.lineMods}>
            <TenantText>{mods}</TenantText>
          </div>
        )}

        {line.line.note === '' ? null : (
          <div className={s.lineNote}>
            <NoteIcon />
            <TenantText>{line.line.note}</TenantText>
          </div>
        )}

        <div className={s.lineFoot}>
          {/* DOM order is decrement, value, increment - so in RTL the "+" side
              paints on the left, exactly as the approved screenshot shows. */}
          <span className={s.stepper} data-sf-stepper="cart">
            <button
              className={s.stepBtn}
              type="button"
              aria-label={m.decrease}
              onClick={() => onQty(line.line.qty - 1)}
              data-sf-dec=""
            >
              <MinusIcon />
            </button>
            <span className={`${s.stepValue} ${s.ltr}`} dir="ltr">
              {line.line.qty}
            </span>
            <button
              className={`${s.stepBtn} ${s.stepPlus}`}
              type="button"
              aria-label={m.increase}
              onClick={() => onQty(line.line.qty + 1)}
              data-sf-inc=""
            >
              <PlusIcon />
            </button>
          </span>

          <span className={s.lineActions}>
            {/*
              Edit re-opens the SAME product sheet, pre-filled, and the sheet
              replaces this line instead of appending a second one. The two
              data attributes are what StorefrontRuntime's delegation reads;
              it also checks that the line really belongs to this item before
              letting the sheet rewrite it.
            */}
            <button
              className={s.lineAction}
              type="button"
              data-sf-item={line.item.id}
              data-sf-line={line.line.lineId}
            >
              {m.edit}
            </button>
            <button
              className={`${s.lineAction} ${s.lineRemove}`}
              type="button"
              onClick={onRemove}
              data-sf-remove=""
            >
              {m.remove}
            </button>
          </span>
        </div>
      </div>
    </li>
  );
}

export function CartScreen({
  m,
  cart,
  quote,
  menuHref,
  state,
  opensAt,
  motion,
  notice,
  pending,
  onDismissNotice,
  onCheckout,
}: {
  m: StorefrontMessages;
  cart: CartApi;
  quote: Quote;
  menuHref: string;
  state: ServiceState;
  opensAt: string;
  motion: MotionMode;
  notice: CartNotice | null;
  /** True while the quote for the CURRENT cart has not arrived. */
  pending: boolean;
  onDismissNotice: () => void;
  onCheckout: () => void;
}) {
  const [announcement, setAnnouncement] = useState('');
  const lines = cart.summary.lines;
  // The one shared reason: exactly 'open' proceeds, anything else states why.
  const reason = orderingReason(orderingBlocker(state), m, opensAt);

  const setQty = useCallback(
    (line: ResolvedCartLine, next: number) => {
      if (next <= 0) {
        cart.remove(line.line.lineId);
        // AUTHORED COPY ONLY: the Remove label plus the item name. The pack has
        // no sentence for "X was removed", and inventing one here would be
        // inventing system copy.
        setAnnouncement(`${m.remove} · ${line.item.name}`);
        return;
      }
      cart.update(line.line.lineId, {
        qty: next,
        selections: line.line.selections,
        note: line.line.note,
      });
    },
    [cart, m.remove],
  );

  return (
    <div className={`${s.screen} ${motion === 'calm' ? '' : s.motionFull}`} data-sf-screen="cart">
      <CartHeader m={m} backHref={menuHref} count={cart.summary.itemCount} />

      <div className={s.body}>
        {notice === null ? null : (
          <Banner
            tone={notice.kind === 'price' ? 'info' : 'warn'}
            icon={notice.kind === 'price' ? <InfoIcon /> : <AlertIcon />}
            title={notice.kind === 'price' ? m.priceTitle : m.changedTitle}
            body={
              notice.kind === 'price' ? (
                <Interpolate
                  template={m.priceBody}
                  values={{ t: <Money minor={quote.totalMinor} /> }}
                />
              ) : notice.kind === 'soldOut' ? (
                <Interpolate
                  template={m.soldOutCart}
                  values={{ i: <Bidi>{notice.itemName ?? ''}</Bidi> }}
                />
              ) : (
                m.changedBody
              )
            }
            action={{ label: m.gotIt, onAction: onDismissNotice }}
            testId={`cart-${notice.kind}`}
          />
        )}

        {lines.length === 0 ? (
          <div className={s.empty} data-sf-empty="cart">
            <span className={s.emptyTile} aria-hidden="true">
              <TrolleyIcon />
            </span>
            <h2 className={s.emptyTitle}>{m.emptyCart}</h2>
            <p className={s.emptyBody}>{m.emptyCartBody}</p>
            {/* prefetch={false}: see BackLink - a static export serves no
                per-segment RSC payload, so a prefetch is a guaranteed 404. */}
            <Link className={s.emptyCta} href={menuHref} prefetch={false} data-sf-browse="">
              {m.browseMenu}
            </Link>
          </div>
        ) : (
          <>
            <ul className={s.lines}>
              {lines.map((line) => (
                <CartLineCard
                  key={line.line.lineId}
                  line={line}
                  m={m}
                  onQty={(next) => setQty(line, next)}
                  onRemove={() => setQty(line, 0)}
                />
              ))}
            </ul>

            <Totals quote={quote} m={m} />
          </>
        )}

        <Announcer text={announcement} />
      </div>

      {/* The totals block and the footer BOTH disappear with the last line
          (Storefront.dc.html:398, :407). */}
      {lines.length === 0 ? null : (
        <FooterCta
          label={reason ?? m.checkout}
          onActivate={reason === null && !pending ? onCheckout : () => undefined}
          totalMinor={quote.totalMinor}
          blocked={reason !== null || pending}
          dim={reason !== null}
          live={motion !== 'calm'}
          tall
          testId="cart-checkout"
        />
      )}
    </div>
  );
}
