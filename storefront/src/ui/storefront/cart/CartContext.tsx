'use client';

import { createContext, useContext, type ReactNode } from 'react';
import type { CartApi } from '@/cart/useCart';
import type { BasisPoints, DeliveryZone, MenuItem, ModifierGroup } from '@/source/types';

/**
 * THE MENU THE SCOPE WAS RENDERED WITH (STOREFRONT-READ-001). Items, groups,
 * zones, the tax rate, the cart key and the browse-only flag come from the
 * route's source through StorefrontRuntime; the aside reads them here instead
 * of importing a fixture, so a live tenant's quote is priced on ITS menu.
 */
export interface MenuData {
  /**
   * Which source produced the menu. The `?fx=` demo scenario tokens are
   * honoured for `fixture` ONLY; a live tenant's cart ignores every URL token
   * (STOREFRONT-READ-001 review finding C5).
   */
  readonly source: 'fixture' | 'live';
  readonly items: readonly MenuItem[];
  readonly groups: readonly ModifierGroup[];
  readonly zones: readonly DeliveryZone[];
  readonly taxRateBp: BasisPoints;
  readonly menuVersion: string;
  readonly orderingEnabled: boolean;
}

const EMPTY_MENU: MenuData = { source: 'live', items: [], groups: [], zones: [], taxRateBp: 0, menuVersion: '', orderingEnabled: false };

const CartContext = createContext<CartApi | null>(null);
const MenuContext = createContext<MenuData>(EMPTY_MENU);

export function CartScope({ cart, menu, children }: { cart: CartApi; menu: MenuData; children: ReactNode }) {
  return (
    <MenuContext.Provider value={menu}>
      <CartContext.Provider value={cart}>{children}</CartContext.Provider>
    </MenuContext.Provider>
  );
}

/** Null outside a CartScope, so a slot rendered by mistake shows the fallback. */
export function useCartApi(): CartApi | null {
  return useContext(CartContext);
}

/** The menu of the enclosing scope; an empty, browse-only menu outside one. */
export function useMenuData(): MenuData {
  return useContext(MenuContext);
}
