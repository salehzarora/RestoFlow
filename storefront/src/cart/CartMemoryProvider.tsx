'use client';

import { createContext, useContext, useMemo, useRef, type ReactNode } from 'react';
import type { CartState } from '@/source/types';

interface MemoryCart {
  get: (slug: string, menuVersion: string) => CartState | null;
  set: (cart: CartState) => void;
}
const CartMemory = createContext<MemoryCart | null>(null);

/** Live item details, modifier selections and notes live only in this layout. */
export function CartMemoryProvider({ slug, children }: { slug: string; children: ReactNode }) {
  const held = useRef<CartState | null>(null);
  if (held.current?.slug !== slug) held.current = null;
  const api = useMemo<MemoryCart>(() => ({
    get: (owner, version) => held.current?.slug === owner && held.current.menuVersion === version ? held.current : null,
    set: (cart) => { if (cart.slug === slug) held.current = cart; },
  }), [slug]);
  return <CartMemory.Provider value={api}>{children}</CartMemory.Provider>;
}

export function useMemoryCart() { return useContext(CartMemory); }
