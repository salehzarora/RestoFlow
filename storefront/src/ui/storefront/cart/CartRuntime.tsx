'use client';

/**
 * THE CART RUNTIME: one cart, shared by two DOM positions.
 *
 * WHY A CONTEXT AND NOT ONE COMPONENT. The dock is `position: sticky` INSIDE
 * `<main>` so it pins to the scrolling column, while the scope has to wrap the
 * whole shell. Providing the cart once and consuming it in place keeps the dock
 * in its layout parent instead of moving it to where the state lives.
 *
 * ONLY THE PHONE DOCK IS LIVE IN PHASE C. The wide aside at container >= 900px
 * is a NON-FUNCTIONAL Phase-D seam: it is a plain server component that never
 * reaches this context, so it cannot show lines, a count, a subtotal, tax or a
 * total, and cannot change when a real cart exists.
 *
 * THE SLOT RENDERS NOTHING until this visitor's own cart has been read, so the
 * static document and the first client render are identical - and neither
 * contains a cart.
 */
import { createContext, useContext, type ReactNode } from 'react';
import type { CartApi } from '@/cart/useCart';
import type { StorefrontMessages } from '@/i18n/storefront';
import type { MotionMode, ServiceState } from '@/source/types';
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
}: {
  m: StorefrontMessages;
  motion: MotionMode;
  state: ServiceState;
  opensAt: string;
}) {
  const cart = useCartApi();
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
    />
  );
}
