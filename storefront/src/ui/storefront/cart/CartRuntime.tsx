'use client';

/**
 * THE CART RUNTIME: one cart, shared by two DOM positions.
 *
 * WHY A CONTEXT AND NOT ONE COMPONENT. The two cart surfaces cannot be
 * siblings. The dock is `position: sticky` INSIDE `<main>` so it pins to the
 * scrolling column; the wide aside is a sibling OF `<main>` because
 * home.module.css lays `.shell` out as `main + .aside` at container >= 900px.
 * Rendering both from one component would move one of them out of its layout
 * parent and break the approved geometry, so the state is provided once and
 * consumed in place by two slots.
 *
 * WHY THE ASIDE MATTERS. At container >= 900px the dock is `display: none` and
 * the aside is the ONLY cart surface. Leaving it on the build-time fixture
 * would show every desktop visitor a cart they never created, and their real
 * additions would change nothing on screen.
 *
 * BOTH SLOTS RENDER THEIR PRERENDERED CHILD until the visitor's own cart has
 * been read, so the static document and the first client render are identical
 * and there is no hydration mismatch.
 */
import { createContext, useContext, type ReactNode } from 'react';
import { toCartView } from '@/cart/cartModel';
import type { CartApi } from '@/cart/useCart';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { MotionMode, ServiceState } from '@/source/types';
import { CartAside } from '../home/CartParts';
import { LiveCartDock } from './LiveCartDock';

const CartContext = createContext<CartApi | null>(null);

export function CartScope({ cart, children }: { cart: CartApi; children: ReactNode }) {
  return <CartContext.Provider value={cart}>{children}</CartContext.Provider>;
}

/** Null outside a CartScope, so a slot rendered by mistake shows the fallback. */
function useCartApi(): CartApi | null {
  return useContext(CartContext);
}

export function DockSlot({
  m,
  motion,
  state,
  opensAt,
  children,
}: {
  m: StorefrontMessages;
  motion: MotionMode;
  state: ServiceState;
  opensAt: string;
  children: ReactNode;
}) {
  const cart = useCartApi();
  if (cart === null || !cart.ready) return <>{children}</>;
  return (
    <LiveCartDock
      summary={cart.summary}
      m={m}
      motion={motion}
      state={state}
      opensAt={opensAt}
    />
  );
}

export function AsideSlot({
  m,
  state,
  opensAt,
  taxRate,
  children,
}: {
  m: StorefrontMessages;
  state: ServiceState;
  opensAt: string;
  taxRate: number;
  children: ReactNode;
}) {
  const cart = useCartApi();
  if (cart === null || !cart.ready) return <>{children}</>;
  // The SAME presentational component, handed the visitor's real numbers in the
  // CartView shape it already renders. Its steppers and checkout CTA stay
  // disabled: those are Phase D business controls, not Phase C.
  return (
    <CartAside cart={toCartView(cart.summary, taxRate)} m={m} state={state} opensAt={opensAt} />
  );
}
