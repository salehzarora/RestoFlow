'use client';

/**
 * THE CART RUNTIME: one cart, shared by two DOM positions.
 *
 * WHY A CONTEXT AND NOT ONE COMPONENT. The dock is `position: sticky` INSIDE
 * `<main>` so it pins to the scrolling column, while the scope has to wrap the
 * whole shell. Providing the cart once and consuming it in place keeps the dock
 * in its layout parent instead of moving it to where the state lives.
 *
 * BOTH SLOTS ARE LIVE FROM PHASE D. The dock is the phone affordance; the wide
 * aside at container >= 900px is the same cart in a 360px column. Phase C's
 * aside was a deliberately non-functional seam because the cart route did not
 * exist; it does now, so the seam has been replaced by LiveCartAside and the
 * guard that pinned the seam has moved with it rather than being deleted.
 *
 * NEITHER SLOT SHOWS A CART until this visitor's own cart has been read, so the
 * static document and the first client render are identical and neither
 * contains one. The dock renders nothing at all; the aside keeps its frame,
 * because 360px of layout appearing after hydration would reflow the page.
 */
import {
  createContext,
  useContext,
  useLayoutEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { CartApi } from '@/cart/useCart';
import { storefrontMessages } from '@/i18n/storefront';
import type { Locale } from '@/i18n/locales';
import type { MotionMode, ServiceState } from '@/source/types';
import { LiveCartDock } from './LiveCartDock';
import { LiveCartAside } from './LiveCartAside';
import { EMPTY_DRAFT, useCheckoutDraft } from '../checkout/CheckoutDraftProvider';
import { raceQuoteSource, useQuote } from '@/money/useQuote';
import { isQuoteRace, readFlowScenario } from '@/source/flow-scenarios';
import type { QuoteInput } from '@/money/quote';
import { MENU_ITEMS, TAX_RATE } from '@/source/menu-fixture';
import { findZone } from '@/source/zones';
import type { CartState } from '@/source/types';

/** A stable identity, so the quote key does not churn on every render. */
const EMPTY_CART: CartState = { schema: 1, slug: '', menuVersion: '', lines: [] };

const CartContext = createContext<CartApi | null>(null);

export function CartScope({ cart, children }: { cart: CartApi; children: ReactNode }) {
  return <CartContext.Provider value={cart}>{children}</CartContext.Provider>;
}

/** Null outside a CartScope, so a slot rendered by mistake shows the fallback. */
export function useCartApi(): CartApi | null {
  return useContext(CartContext);
}

export function DockSlot({
  locale,
  motion,
  state,
  opensAt,
  cartHref,
}: {
  /** The locale; the dictionary is resolved client-side (E-OPT-1). */
  locale: Locale;
  motion: MotionMode;
  state: ServiceState;
  opensAt: string;
  cartHref: string;
}) {
  const cart = useCartApi();
  const m = storefrontMessages(locale);
  // Nothing before the visitor's own cart has been read: an empty cart renders
  // no dock, and that is exactly what the static document must contain.
  if (cart === null || !cart.ready) return null;
  return (
    <LiveCartDock
      summary={cart.summary}
      m={m}
      motion={motion}
      state={state}
      opensAt={opensAt}
      cartHref={cartHref}
    />
  );
}

/**
 * The wide cart column.
 *
 * UNLIKE THE DOCK, THE FRAME ALWAYS RENDERS. The dock is an overlay, so
 * rendering nothing before the cart has been read costs no layout. The aside
 * is a 360px LAYOUT COLUMN: returning null until hydration would reflow the
 * whole page the moment the cart arrives. So the frame and the head are always
 * present and only the lines and the totals wait for `ready` - which keeps the
 * static document free of any cart while keeping the geometry stable.
 *
 * IT READS THE SAME QUOTE THE CART PAGE DOES. The checkout draft lives in the
 * `[slug]` layout, above the menu and search routes as well as the flow, so a
 * service and a zone chosen on checkout are visible here - which is precisely
 * the case where an aside that ignored the delivery fee would print a total
 * that does not add up.
 */
export function AsideSlot({
  locale,
  state,
  opensAt,
  checkoutHref,
}: {
  /** The locale; the dictionary is resolved client-side (E-OPT-1). */
  locale: Locale;
  state: ServiceState;
  opensAt: string;
  checkoutHref: string;
}) {
  const m = storefrontMessages(locale);
  const cart = useCartApi();
  const draftApi = useCheckoutDraft();
  const draft = draftApi?.draft ?? EMPTY_DRAFT;
  const ready = cart !== null && cart.ready;

  /*
   * The aside honours the SAME closed scenario allowlist the flow does, so the
   * one state that is otherwise unreachable here - a quote in flight - can be
   * reproduced and proven. With the immediate fixture source a pending frame
   * lasts one microtask, which is why the gap went unmeasured in D.
   *
   * Read after hydration, never during render: the first client render has to
   * match the static document byte for byte.
   */
  const [fx, setFx] = useState('');
  useLayoutEffect(() => {
    setFx(readFlowScenario(window.location.search));
    const onPop = () => setFx(readFlowScenario(window.location.search));
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  const input: QuoteInput = useMemo(
    () => ({
      cart: cart?.state ?? EMPTY_CART,
      items: MENU_ITEMS,
      service: draft.service,
      zone: findZone(draft.zoneId),
      taxRate: TAX_RATE,
    }),
    [cart?.state, draft.service, draft.zoneId],
  );
  const { quote, pending } = useQuote(input, isQuoteRace(fx) ? raceQuoteSource : undefined);

  return (
    <LiveCartAside
      summary={ready ? cart.summary : null}
      quote={quote}
      /*
       * BOTH halves of readiness reach the aside. Before, `pending` was
       * discarded here, so the one surface that could navigate to checkout was
       * the one surface with no gate on whether its total still belonged to the
       * cart on screen.
       */
      pending={pending}
      update={cart?.update ?? null}
      remove={cart?.remove ?? null}
      m={m}
      state={state}
      opensAt={opensAt}
      checkoutHref={checkoutHref}
    />
  );
}
